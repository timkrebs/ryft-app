#!/usr/bin/env python3
"""Brings Localizable.xcstrings in line with the code, as Xcode does on build.

Xcode syncs a string catalog when it builds; `xcodebuild` from the command line
(VS Code sessions, CI) doesn't. This reads the `.stringsdata` files the last build
wrote into DerivedData (one per source file, every `String(localized:)`, `Text("…")`
and `LocalizedStringKey`), then:

- adds keys the code uses that the catalog lacks (English is the key itself), and
- removes keys no source uses any more, unless marked `extractionState: manual`
  (Info.plist and push loc-keys are).

Then `make lint` lists what still needs German. Usage (after a build into the same
DerivedData, as `make build` does):

    python3 scripts/sync-strings.py [--derived-data build/DerivedData]
        [--configuration Debug] [--platform iphonesimulator] [--check]

Only that configuration and platform are read, so an older Release or device build in
the same DerivedData can't stand in for the current one. `--check` changes nothing and
exits 1 if the catalog is out of date.
"""
import argparse
import glob
import json
import os
import sys

TARGETS = {
    "Ryft": "Ryft/Resources/Localizable.xcstrings",
    "RyftWidgetsExtension": "RyftWidgets/Localizable.xcstrings",
}


def skipped_lines(source: str) -> set[int]:
    """Lines whose strings the catalog leaves out, as Xcode's sync does: inside
    `#if DEBUG` (up to its `#else` / `#endif`), Debug-only UI; and `#Preview` lines,
    where every string in a preview's body is reported."""
    lines: set[int] = set()
    stack: list[bool] = []  # per open #if: is this branch Debug-only?
    try:
        with open(source) as f:
            text = f.read().splitlines()
    except OSError:
        return lines
    for number, line in enumerate(text, start=1):
        t = line.strip()
        if t.startswith("#if"):
            stack.append(t == "#if DEBUG")
        elif t.startswith("#else") or t.startswith("#elseif"):
            if stack:
                stack[-1] = False
        elif t.startswith("#endif"):
            if stack:
                stack.pop()
        elif any(stack) or t.startswith("#Preview"):
            lines.add(number)
    return lines


def extracted_keys(derived: str, configuration: str, platform: str, target: str) -> set[str]:
    objects = os.path.join(derived, "Build/Intermediates.noindex/Ryft.build",
                           f"{configuration}-{platform}", f"{target}.build/Objects-normal")
    archs = sorted(d for d in glob.glob(os.path.join(objects, "*")) if glob.glob(os.path.join(d, "*.stringsdata")))
    if not archs:
        sys.exit(f"No .stringsdata for {target} in {objects}: build first (make build).")
    # Every architecture of one build extracts the same keys; take the first.
    keys: set[str] = set()
    for path in glob.glob(os.path.join(archs[0], "*.stringsdata")):
        with open(path) as f:
            data = json.load(f)
        skipped = skipped_lines(data.get("source", ""))
        for entry in data.get("tables", {}).get("Localizable", []):
            if entry.get("location", {}).get("startingLine") not in skipped:
                keys.add(entry["key"])
    return keys


def merged(strings: dict, added: list[str], removed: set[str]) -> dict:
    """Existing keys keep their place; a new key goes before the first one that sorts
    after it, case-insensitively (close to Xcode's order, which it restores on its
    next sync), so the diff shows only what changed."""
    out: dict = {}
    pending = sorted(added, key=str.lower)
    for key, value in strings.items():
        while pending and pending[0].lower() < key.lower():
            out[pending.pop(0)] = {}
        if key not in removed:
            out[key] = value
    for key in pending:
        out[key] = {}
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--derived-data", default="build/DerivedData")
    parser.add_argument("--configuration", default="Debug")
    parser.add_argument("--platform", default="iphonesimulator")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = False
    for target, path in TARGETS.items():
        keys = extracted_keys(args.derived_data, args.configuration, args.platform, target)
        with open(path) as f:
            catalog = json.load(f)
        strings = catalog["strings"]
        added = sorted(k for k in keys if k not in strings)
        removed = sorted(k for k, v in strings.items()
                         if k not in keys and v.get("extractionState") != "manual")
        for k in added:
            print(f"{path}: + {k!r}")
        for k in removed:
            print(f"{path}: - {k!r}")
        if added or removed:
            stale = True
            if not args.check:
                catalog["strings"] = merged(strings, added, set(removed))
                with open(path, "w") as f:
                    json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", " : "))
                    f.write("\n")
    if args.check and stale:
        print("\nThe catalog is out of date: run python3 scripts/sync-strings.py after a build.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
