#!/usr/bin/env python3
"""What the app and the widget extension share, kept in step (make lint).

`Shared/` is compiled by both targets (ADR 0010). Its rules:
- Swift only, importing Foundation, CoreGraphics and SwiftUI only.
- No user-facing strings: each target's catalog owns its copy, the wrappers add text and accessibility.
- No fonts: the app has Satoshi, the widget the system's face; each wrapper sets its own.
- Colours by asset name: every colorset `Shared/` names is in both asset catalogs, with the same Contents.json.

The widget's colours stay the app's:
- Every colorset in both catalogs has the same Contents.json, whether or not `Shared/` names it.
- `WidgetBackground` is the app's `Background`.
- Each hex literal in the widget's `enum Brand` (`RyftWidgets/RyftWidgets.swift`) is the app colorset of its name
  (`graphite` is `Graphite.colorset`); a `Brand` colour without one fails.

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


STRING_START = re.compile(r'#*"')


def string_end(text, i):
    """Just past the Swift string literal at `i`: `"…"`, `\"\"\"…\"\"\"` or raw (`#"…"#`), interpolations included (they may
    hold strings of their own)."""
    pounds = STRING_START.match(text, i).end() - i - 1
    quote = '"""' if text.startswith('"""', i + pounds) else '"'
    close, escape = quote + "#" * pounds, "\\" + "#" * pounds
    j = i + pounds + len(quote)
    while j < len(text) and not text.startswith(close, j):
        if text.startswith(escape + "(", j):
            j, depth = j + len(escape) + 1, 1
            while j < len(text) and depth:
                if STRING_START.match(text, j):
                    j = string_end(text, j)
                    continue
                depth += {"(": 1, ")": -1}.get(text[j], 0)
                j += 1
        elif text.startswith(escape, j):
            j += len(escape) + 1
        else:
            j += 1
    return min(j + len(close), len(text))


def without_comments(text):
    """Swift without `//` and (nested) `/* */` comments, line breaks kept; string literals kept whole, so a `//` inside
    one ("ryft://today") is not a comment."""
    out, i = [], 0
    while i < len(text):
        if text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
        elif text.startswith("/*", i):
            i, depth = i + 2, 1
            while i < len(text) and depth:
                if text.startswith("/*", i) or text.startswith("*/", i):
                    depth += 1 if text[i] == "/" else -1
                    i += 2
                else:
                    out.append("\n" if text[i] == "\n" else "")
                    i += 1
        elif STRING_START.match(text, i):
            end = string_end(text, i)
            out.append(text[i:end])
            i = end
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def code(lines):
    """Without comments and blank lines, trimmed."""
    out = []
    for line in without_comments(lines).splitlines():
        line = line.strip()
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


# MARK: the widget's colours

WIDGET_BRAND = "RyftWidgets/RyftWidgets.swift"


def colorset_rgba(path):
    """(r, g, b, a) in 0...255 of a colorset's universal sRGB colour, None when it is not one."""
    for entry in json.loads(read(path)).get("colors", []):
        if entry.get("appearances"):
            continue
        colour = entry.get("color", {})
        if colour.get("color-space") not in ("srgb", None):
            return None
        c = colour.get("components", {})

        def channel(v):
            # Xcode writes a component three ways: "0xF2" (hex), "0.949" (0...1) or "242" (8-bit, no point).
            v = str(v).strip()
            if v.lower().startswith("0x"):
                return int(v, 16)
            if re.fullmatch(r"\d+", v):
                return int(v)
            return round(float(v) * 255)
        try:
            return tuple(channel(c[k]) for k in ("red", "green", "blue")) + (round(float(c.get("alpha", 1)) * 255),)
        except (KeyError, ValueError):
            return None
    return None


def check_widget_colours():
    if not (os.path.isdir(APP_CATALOG) and os.path.isdir(WIDGET_CATALOG)):
        return
    sets = lambda d: {n[:-len(".colorset")] for n in os.listdir(d) if n.endswith(".colorset")}
    for name in sorted(sets(APP_CATALOG) & sets(WIDGET_CATALOG)):
        a = os.path.join(APP_CATALOG, f"{name}.colorset", "Contents.json")
        b = os.path.join(WIDGET_CATALOG, f"{name}.colorset", "Contents.json")
        if json.loads(read(a)) != json.loads(read(b)):
            problems.append(f"colorset {name}: {a} and {b} differ")
    background = os.path.join(APP_CATALOG, "Background.colorset", "Contents.json")
    widget_background = os.path.join(WIDGET_CATALOG, "WidgetBackground.colorset", "Contents.json")
    if os.path.exists(background) and os.path.exists(widget_background) \
            and colorset_rgba(background) != colorset_rgba(widget_background):
        problems.append(f"{widget_background}: not the app's Background ({background})")
    if not os.path.exists(WIDGET_BRAND):
        return
    brand = block(without_comments(read(WIDGET_BRAND)), "enum Brand")
    if brand is None:
        problems.append(f"{WIDGET_BRAND}: enum Brand not found")
        return
    hexes = re.compile(r"static\s+let\s+(\w+)\s*=\s*Color\(\s*red:\s*0x([0-9A-Fa-f]{2})\s*/\s*255\s*,"
                       r"\s*green:\s*0x([0-9A-Fa-f]{2})\s*/\s*255\s*,\s*blue:\s*0x([0-9A-Fa-f]{2})\s*/\s*255\s*\)")
    found = 0
    for name, r, g, b in hexes.findall(brand):
        found += 1
        asset = name[:1].upper() + name[1:]
        path = os.path.join(APP_CATALOG, f"{asset}.colorset", "Contents.json")
        if not os.path.exists(path):
            problems.append(f"{WIDGET_BRAND}: Brand.{name} has no app colorset {asset} to match")
            continue
        app = colorset_rgba(path)
        widget = (int(r, 16), int(g, 16), int(b, 16), 255)
        if app != widget:
            problems.append(f"{WIDGET_BRAND}: Brand.{name} is #{r}{g}{b}, the app's {asset} is "
                            + (f"#{app[0]:02X}{app[1]:02X}{app[2]:02X}" if app else "not an sRGB colour"))
    # Any other colour literal in Brand escapes the check: name it after an app colorset in the form above.
    if len(re.findall(r"Color\(", brand)) != found:
        problems.append(f"{WIDGET_BRAND}: a Brand colour not written as Color(red: 0xRR / 255, green: ..., blue: ...)")


check_widget_colours()

# A colorset `Shared/` names is compared by both checks: say it once.
problems = list(dict.fromkeys(problems))
for p in problems:
    print(p)
if problems:
    print(f"\n{len(problems)} problem(s) with what the app and the widget share.")
    sys.exit(1)
print("Shared: Shared/ follows ADR 0010, colorsets and the remaining copies match.")
