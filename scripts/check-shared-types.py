#!/usr/bin/env python3
"""What the app and the widget extension share, kept in step (make lint).

`Shared/` is compiled by both targets (ADR 0010). Its rules:
- Swift only, importing Foundation, CoreGraphics and SwiftUI only.
- No user-facing strings: each target's catalog owns its copy, the wrappers add text and accessibility.
- No fonts: the app has Satoshi, the widget the system's face; each wrapper sets its own.
- Colours by asset name: every colorset `Shared/` names is in both asset catalogs, with the same Contents.json.

Types that predate `Shared/` still exist twice and must stay identical (each moves into `Shared/` when next touched):
- `RestTimerAttributes`: the whole struct (ActivityKit matches it by name and Codable shape).
- `OpenWorkoutIntent`: its `static let` declarations (the system performs the app's copy).
- `WakeAlarmMetadata`: the declaration (AlarmKit's attributes carry it).
"""
import json
import os
import re
import sys

os.chdir(os.path.join(os.path.dirname(__file__), ".."))
problems = []


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def block(text, start):
    """From `start` to its closing brace, by counting braces."""
    i = text.find(start)
    if i < 0:
        return None
    depth = 0
    for j in range(text.index("{", i), len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
    return None


def code(lines):
    """Without comments and blank lines, trimmed."""
    out = []
    for line in lines.splitlines():
        line = line.split("//")[0].strip()
        if line:
            out.append(line)
    return out


def same(name, a_path, b_path, pick):
    if not (os.path.exists(a_path) and os.path.exists(b_path)):
        return
    a, b = pick(read(a_path)), pick(read(b_path))
    if a is None or b is None:
        problems.append(f"{name}: not found in {a_path if a is None else b_path}")
    elif a != b:
        problems.append(f"{name}: {a_path} and {b_path} differ")


same("RestTimerAttributes", "Ryft/Train/RestActivity.swift", "RyftWidgets/RestTimerAttributes.swift",
     lambda t: code(block(t, "struct RestTimerAttributes") or ""))
same("OpenWorkoutIntent", "Ryft/Features/Train/TrainCoordinator.swift", "RyftWidgets/OpenWorkoutIntent.swift",
     lambda t: [l for l in code(block(t, "struct OpenWorkoutIntent") or "") if l.startswith("static let")])
same("WakeAlarmMetadata", "Ryft/Features/Sleep/SleepPlannerViewModel.swift", "RyftWidgets/WakeAlarmMetadata.swift",
     lambda t: [l for l in code(t) if l.startswith("struct WakeAlarmMetadata")])


# MARK: Shared/

SHARED = "Shared"
ALLOWED_IMPORTS = {"Foundation", "CoreGraphics", "SwiftUI"}
# A user-facing string or an accessibility text: the wrappers' job, with their own catalogs.
USER_FACING = re.compile(r'String\(localized|NSLocalizedString|LocalizedStringKey|LocalizedStringResource|\bText\(|\bLabel\('
                         r'|\.accessibility(Label|Value|Hint)\(|\.navigationTitle\(|\.help\(')
APP_CATALOG, WIDGET_CATALOG = "Ryft/Assets.xcassets", "RyftWidgets/Assets.xcassets"


def without_comments(text):
    """Swift without `//` and `/* */` comments; string literals kept (good enough for these rules)."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(line.split("//")[0] for line in text.splitlines())


def check_shared():
    if not os.path.isdir(SHARED):
        return
    colours = set()
    for root, _, files in os.walk(SHARED):
        for name in sorted(files):
            path = os.path.join(root, name)
            if name == ".DS_Store":
                continue
            if not name.endswith(".swift"):
                problems.append(f"{path}: Shared/ holds Swift only (both targets would bundle it)")
                continue
            src = without_comments(read(path))
            for module in re.findall(r"^[ \t]*(?:@\w+[ \t]+)*import[ \t]+(?:(?:struct|class|enum|protocol|func|var|let|typealias)[ \t]+)?(\w+)",
                                 src, flags=re.M):
                if module not in ALLOWED_IMPORTS:
                    problems.append(f"{path}: imports {module}; Shared/ allows {', '.join(sorted(ALLOWED_IMPORTS))}")
            for n, line in enumerate(src.splitlines(), 1):
                if USER_FACING.search(line):
                    problems.append(f"{path}:{n}: a user-facing string in Shared/ (ADR 0010): {line.strip()}")
                if re.search(r"\bTheme\.", line):
                    problems.append(f"{path}:{n}: Theme in Shared/; name colours by asset (OrbitGaugePalette)")
                if re.search(r"\bFont\b|\.font\(|\.ryft(Number)?\(", line):
                    problems.append(f"{path}:{n}: a font in Shared/ (ADR 0010); the wrappers set fonts: {line.strip()}")
            colours.update(re.findall(r'\bColor\("(\w+)"\)', src))
    for name in sorted(colours):
        a = os.path.join(APP_CATALOG, f"{name}.colorset", "Contents.json")
        b = os.path.join(WIDGET_CATALOG, f"{name}.colorset", "Contents.json")
        missing = [p for p in (a, b) if not os.path.exists(p)]
        if missing:
            problems.append(f"colorset {name} (named in Shared/): missing {', '.join(missing)}")
        elif json.loads(read(a)) != json.loads(read(b)):
            problems.append(f"colorset {name}: {a} and {b} differ")


check_shared()

for p in problems:
    print(p)
if problems:
    print(f"\n{len(problems)} problem(s) with what the app and the widget share.")
    sys.exit(1)
print("Shared: Shared/ follows ADR 0010, colorsets and the remaining copies match.")
