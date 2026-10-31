#!/usr/bin/env python3
"""The tracker catalog's bundled copy (ADR 0002, design.md §2.4).

Content/trackers.json is canonical. `Ryft/` was a classic Xcode group when this was written, so instead of a JSON
resource the app compiles the file as a string literal: the region between the GENERATED markers at the end of
Ryft/Health/HealthKitManager+Status.swift. Since #39 `Ryft/` is a synchronized folder; ADR 0002's follow-up can make it
a resource.

  python3 scripts/trackers.py --write   # (make trackers) rewrite the region from the JSON
  python3 scripts/trackers.py --check   # (make lint) fail when the region is stale or the content breaks a rule

--check covers what CI can see without the app: valid JSON, schema_version 1, unique ids, complete en/de
pairs, the denylisted brand (the pattern of .claude/hooks/pre-edit-guard.sh, which must equal the app's
runtime validator's), and each tracker's `checked` date (a warning at 90 days, a failure at 180). The full
rule set lives once, in Swift (`TrackerCatalog.decode`); DecodingTests proves the bundled literal passes it.
Stdlib only.
"""
import argparse
import datetime
import json
import os
import re
import sys
import tempfile
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENT = os.path.join(ROOT, "Content", "trackers.json")
SWIFT = os.path.join(ROOT, "Ryft", "Health", "HealthKitManager+Status.swift")
HOOK = os.path.join(ROOT, ".claude", "hooks", "pre-edit-guard.sh")

BEGIN = "// BEGIN GENERATED trackers.json"
END = "// END GENERATED trackers.json"
WARN_DAYS, FAIL_DAYS = 90, 180
LINE_LENGTH = 160  # .swiftlint.yml line_length warning
PAIRS = ("setup_steps", "habits", "limits")
# `sync`: one sentence per language ({"en": "...", "de": "..."}), the habits' cap; the app's validator has every text rule.
SENTENCES = ("sync",)
SENTENCE_MAX = 240
# Keys that would let content choose what the app opens. The app's schemes are compiled (ADR 0012) and its decoder
# ignores these, so a file carrying one only looks as if it worked.
REFUSED_KEYS = ("url_scheme", "open_url")
MARKUP = re.compile(r"<|>|\]\(|://|www\.|@|mailto:|tel:", re.IGNORECASE)


def canonical(data):
    # Two-space indents, key order as in the file, UTF-8 as is, and every `#` as the JSON escape
    # #: in the Swift raw literal a closing quote run followed by `#` would end the string, and a
    # backslash followed by `#(` would interpolate code. Without any `#` neither can appear; the app's
    # JSON parse turns the escape back.
    return json.dumps(data, ensure_ascii=False, indent=2).replace("#", "\\u0023")


def folded(s):
    """As the app folds before its brand check: compatibility forms, case and diacritics away."""
    decomposed = unicodedata.normalize("NFKD", unicodedata.normalize("NFKC", s))
    return "".join(c for c in decomposed if not unicodedata.combining(c)).casefold()


def region(data):
    lines = [("    " + line) if line else "" for line in canonical(data).split("\n")]
    # Guide text runs long; SwiftLint's line length is off only when a line needs it (an unneeded
    # disable is a warning of its own).
    long = any(len(line) > LINE_LENGTH for line in lines)
    return "\n".join([
        BEGIN + " (scripts/trackers.py --write from Content/trackers.json; do not edit)",
        *(["// swiftlint:disable line_length"] if long else []),
        "extension TrackerCatalog {",
        "    /// Content/trackers.json at build time: the copy that always works (offline, first launch, demo).",
        '    static let bundledJSON = #"""',
        *lines,
        '    """#',
        "}",
        *(["// swiftlint:enable line_length"] if long else []),
        END,
    ]) + "\n"


def split_swift(text):
    """(before, region or None): the region is the file's tail from the BEGIN marker."""
    start = text.find(BEGIN)
    if start < 0:
        return text, None
    end = text.find(END, start)
    if end < 0:
        sys.exit(f"{SWIFT}: {BEGIN} without {END}")
    tail = text[end + len(END):]
    if tail.strip():
        sys.exit(f"{SWIFT}: the generated region must be the end of the file")
    return text[:start], text[start:end + len(END)] + "\n"


def load_content():
    try:
        with open(CONTENT, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        sys.exit(f"{CONTENT}: not valid JSON ({e})")


def hook_pattern():
    try:
        with open(HOOK, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        sys.exit(f"{HOOK}: {e}")
    m = re.search(r"grep -Eiq '([^']+)'", text)
    if not m:
        sys.exit(f"{HOOK}: no brand pattern found (grep -Eiq '…')")
    return m.group(1)


def strings(value, path="$"):
    """Every string in the document, with its path."""
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, dict):
        for k, v in value.items():
            yield from strings(k, f"{path}.<key>")
            yield from strings(v, f"{path}.{k}")
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from strings(v, f"{path}[{i}]")


def check_pair(errors, pair, path, lists=True):
    if pair is None:
        return
    if not isinstance(pair, dict) or "en" not in pair or "de" not in pair:
        errors.append(f"{path}: needs both en and de")
        return
    en, de = pair["en"], pair["de"]
    if lists:
        if not isinstance(en, list) or not isinstance(de, list) or len(en) != len(de):
            errors.append(f"{path}: en and de need the same number of entries")
    elif not (isinstance(en, str) and en.strip() and isinstance(de, str) and de.strip()):
        errors.append(f"{path}: en and de both need text")


def check_sentence(errors, pair, path):
    """A plain sentence per language: both present, at most SENTENCE_MAX characters, no markup or links."""
    if pair is None:
        return
    before = len(errors)
    check_pair(errors, pair, path, lists=False)
    if len(errors) > before:
        return
    for language in ("en", "de"):
        text = pair[language]
        if len(text) > SENTENCE_MAX:
            errors.append(f"{path}.{language}: longer than {SENTENCE_MAX} characters")
        if MARKUP.search(text) or any(unicodedata.category(c) in ("Cc", "Cf") for c in text):
            errors.append(f"{path}.{language}: plain text only (no markup, links or control characters)")


def check(data, swift_text):
    errors, warnings = [], []
    if not isinstance(data, dict):
        return ["the document must be a JSON object"], warnings
    if data.get("schema_version") != 1 or isinstance(data.get("schema_version"), bool):
        errors.append(f"schema_version must be 1 (is {data.get('schema_version')!r})")
    if "#" in canonical(data):
        errors.append("the literal still contains #: it could end the Swift string or interpolate")

    pattern = hook_pattern()
    swift_pattern = re.search(r'static let brandPattern = #"(.+?)"#', swift_text)
    if not swift_pattern:
        errors.append(f"{SWIFT}: no CatalogValidator.brandPattern")
    elif swift_pattern.group(1) != pattern:
        errors.append(f"CatalogValidator.brandPattern differs from the hook's pattern ({pattern})")
    brand = re.compile(pattern, re.IGNORECASE)
    for path, s in strings(data):
        if brand.search(folded(s)):
            errors.append(f"{path}: contains the denylisted brand")
        if any(unicodedata.category(c) == "Co" for c in s):
            errors.append(f"{path}: contains a private-use character (U+F8FF draws Apple's logo)")

    check_pair(errors, (data.get("health_access") or {}).get("steps"), "health_access.steps")
    trackers = data.get("trackers")
    if not isinstance(trackers, list):
        return errors + ["trackers must be a list"], warnings
    today = datetime.date.today()
    seen = set()
    for i, t in enumerate(trackers):
        if not isinstance(t, dict):
            errors.append(f"trackers[{i}]: not an object")
            continue
        tid = t.get("id")
        if tid in seen:
            errors.append(f"trackers[{i}]: id {tid!r} appears twice")
        seen.add(tid)
        for key in PAIRS:
            check_pair(errors, t.get(key), f"{tid}.{key}")
        for key in SENTENCES:
            check_sentence(errors, t.get(key), f"{tid}.{key}")
        for key in REFUSED_KEYS:
            if key in t:
                errors.append(f"{tid}.{key}: not part of the schema; app schemes are compiled (ADR 0012, CatalogValidator.appSchemes)")
        for signal, note in (t.get("capability_notes") or {}).items():
            check_pair(errors, note, f"{tid}.capability_notes.{signal}", lists=False)
        try:
            age = (today - datetime.date.fromisoformat(t.get("checked", ""))).days
        except (TypeError, ValueError):
            errors.append(f"{tid}: checked must be YYYY-MM-DD")
            continue
        if age >= FAIL_DAYS:
            errors.append(f"{tid}: checked {t['checked']} is {age} days old (re-check the vendor's guide)")
        elif age >= WARN_DAYS:
            warnings.append(f"{tid}: checked {t['checked']} is {age} days old")
    for required in ("iphone", "other"):
        if required not in seen:
            errors.append(f"trackers: {required!r} is missing")
    return errors, warnings


def self_test():
    """The generator on scratch files: the region round-trips, `#` never reaches the literal, the
    line-length disable comes only with a long line, and a stale region fails --check."""
    data = {"schema_version": 1, "version": "2026-10-22.1", "trackers": [
        {"id": "iphone", "name": "Just my iPhone", "checked": datetime.date.today().isoformat()},
        {"id": "other", "name": "Other #1 \\#(evil) \"\"\"#", "checked": datetime.date.today().isoformat()}]}
    body = region(data)
    assert "#" not in body.split('#"""', 1)[1].rsplit('"""#', 1)[0], "a # reached the literal"
    literal = body.split('#"""\n', 1)[1].rsplit('\n    """#', 1)[0]
    assert json.loads("\n".join(line[4:] for line in literal.split("\n"))) == data, "the literal doesn't round-trip"
    assert "swiftlint:disable" not in body, "a disable without a long line"
    data["trackers"][1]["name"] = "x" * 200
    assert "// swiftlint:disable line_length" in region(data), "a long line without its disable"
    with tempfile.TemporaryDirectory() as tmp:
        swift = os.path.join(tmp, "Status.swift")
        with open(swift, "w", encoding="utf-8") as f:
            f.write("struct A {}\n")
        before, current = split_swift(open(swift, encoding="utf-8").read())
        assert current is None, "a region where none was written"
        with open(swift, "w", encoding="utf-8") as f:
            f.write(before.rstrip("\n") + "\n\n" + region(data))
        before, current = split_swift(open(swift, encoding="utf-8").read())
        assert current == region(data) and before == "struct A {}\n\n", "the rewrite moved something"
        data["version"] = "2026-10-22.2"
        assert current != region(data), "a stale region looks current"
    errors, _ = check({"schema_version": 1, "trackers": [{"id": "other", "name": "W\u0301h" + "oop", "checked": "2026-10-22"}]},
                      "static let brandPattern = #\"" + hook_pattern() + "\"#")
    assert any("denylisted brand" in e for e in errors), "the folded brand passed"
    errors, _ = check({"schema_version": 1, "trackers": [{"id": "other", "name": "Other \uf8ff", "checked": "2026-10-22"}]},
                      "static let brandPattern = #\"" + hook_pattern() + "\"#")
    assert any("private-use" in e for e in errors), "a private-use character passed"
    pattern = "static let brandPattern = #\"" + hook_pattern() + "\"#"
    for sync, expected in (({"en": "Open it."}, "needs both en and de"), ({"en": "Open it.", "de": " "}, "both need text"),
                           ({"en": ["Open it."], "de": ["Öffne sie."]}, "both need text"),
                           ({"en": "x" * 241, "de": "y"}, "longer than"), ({"en": "See www.example.com", "de": "y"}, "plain text"),
                           ({"en": "Two\nlines", "de": "y"}, "plain text")):
        errors, _ = check({"schema_version": 1, "trackers": [
            {"id": "other", "name": "Other", "checked": "2026-10-22", "sync": sync}]}, pattern)
        assert any(expected in e for e in errors), f"sync {sync!r} passed"
    errors, _ = check({"schema_version": 1, "trackers": [
        {"id": "other", "name": "Other", "checked": "2026-10-22", "sync": {"en": "Open it.", "de": "Öffne sie."}}]}, pattern)
    assert not any("sync" in e for e in errors), f"a valid sync was refused: {errors}"
    for key in REFUSED_KEYS:
        errors, _ = check({"schema_version": 1, "trackers": [
            {"id": "other", "name": "Other", "checked": "2026-10-22", key: "garminconnect"}]}, pattern)
        assert any(f"other.{key}" in e for e in errors), f"{key} passed"
    print("trackers.py self-test: ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="rewrite the generated region from the JSON")
    mode.add_argument("--check", action="store_true", help="fail when the region is stale or a rule is broken")
    mode.add_argument("--self-test", action="store_true", help="test this script on scratch copies (make lint)")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return

    data = load_content()
    with open(SWIFT, encoding="utf-8") as f:
        swift_text = f.read()
    errors, warnings = check(data, swift_text)
    for w in warnings:
        print(f"warning: trackers.json: {w}")
    if errors:
        for e in errors:
            print(f"error: trackers.json: {e}")
        sys.exit(1)

    before, current = split_swift(swift_text)
    wanted = region(data)
    if args.write:
        if current != wanted:
            with open(SWIFT, "w", encoding="utf-8") as f:
                f.write(before.rstrip("\n") + "\n\n" + wanted)
            print(f"wrote the trackers.json region of {os.path.relpath(SWIFT, ROOT)}")
        return
    if current != wanted:
        print(f"error: {os.path.relpath(SWIFT, ROOT)}: the trackers.json region is stale; run `make trackers`")
        sys.exit(1)
    print(f"trackers.json: {len(data['trackers'])} trackers, version {data.get('version')}, region up to date")


if __name__ == "__main__":
    main()
