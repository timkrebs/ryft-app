#!/usr/bin/env python3
"""An independent implementation of the training import's `SourceExerciseKey.fold` (ADR 0007, Amendment 1), checked
against `RyftTests/Fixtures/Import/source-keys.golden.json`. The app's Swift code and the golden file must agree with
this script: the key derives every imported custom exercise's id and every remembered match, so any difference is a
breaking id change.

Standard library only. Character properties that the rule names are explicit tables here, not Python's own notions
(`str.isspace()` would call U+001C–U+001F whitespace, and `str.lower()` applies Final_Sigma):
- White_Space: Unicode PropList.txt;
- Default_Ignorable_Code_Point: Unicode DerivedCoreProperties.txt;
- the apostrophe set: the ADR's list;
- lowercase: each scalar on its own (full mapping, no context, no locale).
General categories (Cc, Cf, L*, M*, N*) and NFKC come from `unicodedata`.

    python3 scripts/import-fold-check.py            # make lint
"""
import json
import os
import sys
import unicodedata

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GOLDEN = os.path.join(ROOT, "RyftTests", "Fixtures", "Import", "source-keys.golden.json")

# PropList.txt, White_Space.
WHITE_SPACE = [(0x0009, 0x000D), (0x0020, 0x0020), (0x0085, 0x0085), (0x00A0, 0x00A0), (0x1680, 0x1680),
               (0x2000, 0x200A), (0x2028, 0x2029), (0x202F, 0x202F), (0x205F, 0x205F), (0x3000, 0x3000)]

# DerivedCoreProperties.txt, Default_Ignorable_Code_Point.
DEFAULT_IGNORABLE = [(0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160), (0x17B4, 0x17B5),
                     (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x206F), (0x3164, 0x3164),
                     (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF), (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3),
                     (0x1D173, 0x1D17A), (0xE0000, 0xE0FFF)]

# ADR 0007, Amendment 1, step 1.
APOSTROPHES = {0x0027, 0x0060, 0x00B4, 0x02B9, 0x02BB, 0x02BC, 0x02BD, 0x2018, 0x2019, 0x201B, 0x2032, 0xFF07}


def in_ranges(code, ranges):
    return any(low <= code <= high for low, high in ranges)


def dropped(ch):
    code = ord(ch)
    return code in APOSTROPHES or unicodedata.category(ch) in ("Cc", "Cf") or in_ranges(code, DEFAULT_IGNORABLE)


def fold(text):
    # 1. White_Space → U+0020; Cc, Cf, Default_Ignorable_Code_Point and apostrophes dropped.
    step1 = "".join(" " if in_ranges(ord(ch), WHITE_SPACE) else ("" if dropped(ch) else ch) for ch in text)
    # 2. NFKC.
    step2 = unicodedata.normalize("NFKC", step1)
    # 3. Each scalar's own full lowercase mapping (a one-scalar string: no Final_Sigma context).
    step3 = "".join(ch.lower() for ch in step2)
    # 4. The drop set again, then runs of anything but L*, M*, N* become one space, none at the ends.
    out, pending = [], False
    for ch in step3:
        if dropped(ch):
            continue
        if unicodedata.category(ch)[0] in "LMN":
            if pending and out:
                out.append(" ")
            pending = False
            out.append(ch)
        else:
            pending = True
    return "".join(out)


# The rule's own clauses, so a table error fails here even before the golden file is read.
SELF_TEST = [
    ("Bench\u001fPress", "benchpress"), ("Bench\u001cPress", "benchpress"), ("Bench\u0085Press", "bench press"),
    ("Bench Press", "bench press"), ("Curl ❤️", "curl"), ("Bank͏drücken", "bankdrücken"),
    ("CurlㅤPress", "curlpress"), ("Farmer’s Walk", "farmers walk"), ("Farmer″s Walk", "farmers walk"),
    ("Farmer´s Walk", "farmers walk"), ("RockŉRoll", "rocknroll"), ("ΟΔΟΣ", "οδοσ"),
    ("İncline", "i̇ncline"), ("FUẞ", "fuß"), ("Curl ²", "curl 2"), ("Ｂench", "bench"),
    ("  Lat-Pulldown (Machine) ", "lat pulldown machine"), ("", ""),
]


def main():
    problems = [f"self-test: {text!r} → {fold(text)!r}, expected {want!r}" for text, want in SELF_TEST if fold(text) != want]
    with open(GOLDEN, encoding="utf-8") as f:
        golden = json.load(f)
    for entry in golden:
        name, equipment = entry["name"], entry["equipment"] or ""
        if fold(name) != entry["key"]:
            problems.append(f"name {name!r}: golden {entry['key']!r}, fold {fold(name)!r}")
        if fold(equipment) != entry["keyEquipment"]:
            problems.append(f"equipment {equipment!r}: golden {entry['keyEquipment']!r}, fold {fold(equipment)!r}")
        if fold(entry["key"]) != entry["key"]:
            problems.append(f"not idempotent: {entry['key']!r}")
    if problems:
        print("\n".join(problems[:40]))
        print(f"Import fold: {len(problems)} problems (Unicode {unicodedata.unidata_version}).")
        return 1
    print(f"Import fold: {len(golden)} golden keys agree (Unicode {unicodedata.unidata_version}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
