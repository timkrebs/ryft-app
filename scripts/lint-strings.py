#!/usr/bin/env python3
"""Check the App, Info.plist and widget string catalogs (make lint).

English is the source language and German translations are required for translatable keys.
Manual keys need their English text and plurals in both languages need one and other.
"""
import json
import sys


def string_units(node):
    for key, value in node.items():
        if key == "stringUnit":
            yield value
        elif isinstance(value, dict):
            yield from string_units(value)


def plurals(localization):
    """Find both a primary plural and any plurals attached to substituted arguments."""
    nodes = {"": localization, **localization.get("substitutions", {})}
    return {name: node["variations"]["plural"] for name, node in nodes.items()
            if "plural" in node.get("variations", {})}

CATALOGS = ["Ryft/Resources/Localizable.xcstrings", "Ryft/Resources/InfoPlist.xcstrings",
            "RyftWidgets/Localizable.xcstrings"]
problems = []
for path in CATALOGS:
    catalog = json.load(open(path, encoding="utf-8"))
    if catalog.get("sourceLanguage") != "en":
        problems.append(f"{path}: sourceLanguage is not en")
    for key, entry in catalog["strings"].items():
        loc = entry.get("localizations", {})
        for lang in sorted(set(loc) - {"en", "de"}):
            problems.append(f"{path}: unsupported {lang} localization for {key!r}")
        if not key.strip() or entry.get("shouldTranslate") is False:
            continue
        if entry.get("extractionState") == "stale":
            problems.append(f"{path}: stale key {key!r}")
            continue
        if entry.get("extractionState") == "manual" and "en" not in loc:
            problems.append(f"{path}: no English for manual key {key!r} (its key is not the English text)")
        de = loc.get("de", {})
        german_units = list(string_units(de))
        if not german_units or any(unit.get("state") != "translated" or not unit.get("value", "").strip()
                                   for unit in german_units):
            problems.append(f"{path}: incomplete German translation for {key!r}")
        english_plurals = plurals(loc.get("en", {}))
        german_plurals = plurals(de)
        for label, entries in (("English", english_plurals), ("German", german_plurals)):
            expected = set(entries) if label == "English" else set(entries) | set(english_plurals)
            for name in sorted(expected):
                if not {"one", "other"} <= entries.get(name, {}).keys():
                    argument = f" ({name})" if name else ""
                    problems.append(f"{path}: {label} plural incomplete for {key!r}{argument}")
if problems:
    print("\n".join(problems))
    print(f"\n{len(problems)} string problem(s).")
    sys.exit(1)
print("Strings: English and German complete.")
