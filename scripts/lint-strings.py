#!/usr/bin/env python3
"""String-catalog lint (make lint). RYFT is English only.

Over Localizable, InfoPlist and the widget catalogs: no localization other than `en` (a key without
an `en` block is its own English text), no stale key (unused in code), plural
variations complete in English (one and other), and every manual key (push loc-keys and Info.plist
texts, whose key is not the English text) has its `en`. Exits 1 with the offending keys."""
import json, sys

CATALOGS = ["Ryft/Resources/Localizable.xcstrings", "Ryft/Resources/InfoPlist.xcstrings",
            "RyftWidgets/Localizable.xcstrings"]
problems = []
for path in CATALOGS:
    catalog = json.load(open(path, encoding="utf-8"))
    if catalog.get("sourceLanguage") != "en":
        problems.append(f"{path}: sourceLanguage is not en")
    for key, entry in catalog["strings"].items():
        loc = entry.get("localizations", {})
        for lang in loc:
            if lang != "en":
                problems.append(f"{path}: {lang} localization for {key!r} (the app is English only)")
        if not key.strip() or entry.get("shouldTranslate") is False:
            continue
        if entry.get("extractionState") == "stale":
            problems.append(f"{path}: stale key {key!r}")
            continue
        if entry.get("extractionState") == "manual" and "en" not in loc:
            problems.append(f"{path}: no English for manual key {key!r} (its key is not the English text)")
        en = loc.get("en")
        if en is None:
            continue
        plural = en.get("variations", {}).get("plural")
        if plural is not None and not {"one", "other"} <= plural.keys():
            problems.append(f"{path}: English plural incomplete for {key!r}")
        # A plural on one argument of several (Xcode's substitutions), e.g. "n of 7 nights".
        for name, sub in en.get("substitutions", {}).items():
            sub_plural = sub.get("variations", {}).get("plural")
            if sub_plural is not None and not {"one", "other"} <= sub_plural.keys():
                problems.append(f"{path}: English plural incomplete for {key!r} ({name})")
if problems:
    print("\n".join(problems))
    print(f"\n{len(problems)} string problem(s).")
    sys.exit(1)
print("Strings: English complete, no other language.")
