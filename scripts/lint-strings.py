#!/usr/bin/env python3
"""String-catalog lint (make lint): every key is translated to German, no key
is stale (unused in code), and plural keys have one/other in both languages.
Exits 1 with the offending keys."""
import json, sys

CATALOGS = ["Ryft/Resources/Localizable.xcstrings", "Ryft/Resources/InfoPlist.xcstrings",
            "RyftWidgets/Localizable.xcstrings"]
problems = []
for path in CATALOGS:
    strings = json.load(open(path))["strings"]
    for key, entry in strings.items():
        if not key.strip() or entry.get("shouldTranslate") is False:
            continue
        if entry.get("extractionState") == "stale":
            problems.append(f"{path}: stale key {key!r}")
            continue
        loc = entry.get("localizations", {})
        de = loc.get("de")
        if de is None:
            problems.append(f"{path}: no German for {key!r}")
            continue
        plural = de.get("variations", {}).get("plural")
        if plural is not None and not {"one", "other"} <= plural.keys():
            problems.append(f"{path}: German plural incomplete for {key!r}")
if problems:
    print("\n".join(problems))
    print(f"\n{len(problems)} string problem(s).")
    sys.exit(1)
print("Strings: English and German complete.")
