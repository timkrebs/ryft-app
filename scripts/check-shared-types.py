#!/usr/bin/env python3
"""The app and the widget extension can't share a source file (`Ryft/` is a classic group), so a
few types exist twice and must stay identical: what one target encodes, the other decodes.

- `RestTimerAttributes`: the whole struct (ActivityKit matches it by name and Codable shape).
- `OpenWorkoutIntent`: its `static let` declarations (the system performs the app's copy).
- `WakeAlarmMetadata`: the declaration (AlarmKit's attributes carry it).
- `ReadinessSnapshot`: its stored properties and `Kind` cases (the JSON the widget reads).
"""
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


def snapshot_shape(text):
    body = block(text, "struct ReadinessSnapshot")
    if body is None:
        return None
    kind = block(body, "enum Kind")
    stored = [l for l in code(body.replace(kind or "", "")) if re.match(r"^(var|let) \w+: [^{=]+$", l)]
    return code(kind or "") + stored


same("ReadinessSnapshot", "Ryft/Persistence/Repository.swift", "RyftWidgets/ReadinessSnapshot.swift", snapshot_shape)

for p in problems:
    print(p)
if problems:
    print(f"\n{len(problems)} shared type(s) out of step.")
    sys.exit(1)
print("Shared types: app and widget copies match.")
