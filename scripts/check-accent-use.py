#!/usr/bin/env python3
"""Colour hygiene for the Nocturne redesign (make lint; docs/work/2026-11-16-nocturne/design-pr6-b-train.md, "colour hygiene").

Teal is recovery's colour and nothing else (L27); Volt is "now" and nothing else. Two rules:

1. In `Features/Train/**` (except `Import/**`, area C's), `Features/MyDay/**`, `Features/Activities/**` and
   `Features/Journal/JournalViews.swift`, none of `Theme.accent`, `Theme.teal` (and the `Accent` and `Teal` assets),
   SwiftUI's `.teal` and `.accentColor`, `TealButtonStyle`, `PrimaryButton`, `Theme.accentSecondary`, `Theme.warning`,
   `Theme.sage`, `Theme.stageLight`, `Theme.zones` or `Theme.band` appears, and `Theme.alert` appears only inside a
   destructive control: a call with `.destructive` as an argument (`Button(role: .destructive) { ... }`,
   `PillButton(..., style: .destructive)`; its trailing closures and modifiers count as inside, up to a `;`), or in the
   true branch of `kind == .destructive ? Theme.alert : ...`. The ternary is a destructive-or-not control choosing coral
   exactly when it is destructive, which is the rule; a comparison elsewhere in a call's arguments does not make the call
   destructive, and neither does the false branch (`kind != .destructive ? Theme.alert : ...`).
2. `Theme.signal` (and `Brand.signal`, the `Signal` asset, and its aliases `FocusedRowInk.mark`, `RulerScale.needleColor`,
   `RestBar.ringInk`) appears in `Ryft/`, `Shared/` and `RyftWidgets/` only in the marks `ALLOW` lists, each with its reason.

Assets are matched as `Color("X")`, `Color("X", bundle: ...)`, `UIColor(named: "X")` and the generated `Color(.x)`.
Comments and string literals are not code and never count; the code inside a string's `\\( )` does.

An `ALLOW` entry is keyed by file and a pattern for the mark's own expression (`Circle().fill(Theme.signal)`), not by line
number, so edits don't move it, and not by the function or call around it: a label or a line beside the mark is still
checked. It allows its tokens only inside what the pattern matches, and only `uses` times in the file (a second copy of
the mark needs its own entry). An entry that matches nothing, or a different number of times, fails too, so a deleted or
renamed mark takes its entry with it.

What the lint cannot close: it reads names, not types or values. A colour reached through indirection is invisible:
`MetricSpec.*.color`, `Theme.color(for:)`, a `let tint = ...` assigned elsewhere, a colour passed in as a parameter, a
type alias for `Theme`, a new alias constant for Volt (name it in SIGNAL when you add it). Review those by eye.

    python3 scripts/check-accent-use.py              # the repository; prints file:line: token: reason, exit 1 on any
    python3 scripts/check-accent-use.py --self-test  # snippets that must pass or fail
"""
import os
import re
import sys
from collections import Counter
from dataclasses import dataclass

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# MARK: where each rule applies

HYGIENE_DIRS = ("Ryft/Features/Train/", "Ryft/Features/MyDay/", "Ryft/Features/Activities/")
HYGIENE_FILES = ("Ryft/Features/Journal/JournalViews.swift",)
HYGIENE_EXCLUDED = ("Ryft/Features/Train/Import/",)  # area C's
SIGNAL_DIRS = ("Ryft/", "Shared/", "RyftWidgets/")


def in_hygiene_scope(path):
    return (path.startswith(HYGIENE_DIRS) or path in HYGIENE_FILES) and not path.startswith(HYGIENE_EXCLUDED)


def in_signal_scope(path):
    return path.startswith(SIGNAL_DIRS)


# MARK: the tokens

RETIRED = "retired by the Nocturne accent map (docs/work/2026-11-16-nocturne/accent-map.md)"


@dataclass(frozen=True)
class Token:
    """One colour the lint watches. `code` are patterns on code with strings blanked (names, expressions); `assets` are
    asset names, matched as `Color("X")`, `Color("X", bundle:)`, `UIColor(named: "X")` on code with strings kept, and as
    the generated symbol (`Color(.x)`, `ColorResource.x`) on code. `no_symbol` are asset names whose symbol another
    token already catches (`.teal`), so one use is one finding."""
    name: str
    code: tuple
    assets: tuple
    reason: str
    no_symbol: tuple = ()

    def patterns(self):
        """(patterns on code with strings blanked, patterns on code with strings kept)."""
        blanked, kept = list(self.code), []
        if self.assets:
            names = "|".join(self.assets)
            kept.append(rf'\b(?:UIColor|Color)\(\s*(?:named:\s*)?"(?:{names})"\s*[,)]')
            syms = "|".join(a[0].lower() + a[1:] for a in self.assets if a not in self.no_symbol)
            if syms:
                blanked.append(rf"\b(?:UIColor|Color)\(\s*(?:resource:\s*)?\.(?:{syms})\s*\)")
                blanked.append(rf"\bColorResource\.(?:{syms})\b")
        return blanked, kept


HYGIENE_TOKENS = [
    # Theme.teal and the Teal asset are Theme.accent's colour (Theme.swift: "the same colour as `accent`").
    Token("Theme.accent", (r"\bTheme\s*\.\s*(?:accent|teal)\b",), ("Accent", "Teal"),
          "teal is recovery's colour only (L27); controls and icons are Theme.textPrimary, the primary button is PillButton",
          no_symbol=("Teal",)),
    Token("Color.teal", (r"(?<!Theme)\.(?:teal|systemTeal)\b",), (),
          "SwiftUI's teal is still teal: recovery's colour only (L27)"),
    Token("Color.accentColor", (r"\.accentColor\b(?!\s*\()",), (),
          "the app's accent is teal (it goes neutral only in PR 5): controls and icons are Theme.textPrimary"),
    Token("TealButtonStyle", (r"\bTealButtonStyle\b",), (), "the teal button is gone (T5.9); use PillButton"),
    Token("PrimaryButton", (r"\bPrimaryButton\b",), (), "the teal primary button is gone; use PillButton"),
    Token("Theme.accentSecondary", (r"\bTheme\s*\.\s*accentSecondary\b",), ("AccentSecondary",), RETIRED),
    Token("Theme.warning", (r"\bTheme\s*\.\s*warning\b",), ("Warning",), RETIRED),
    Token("Theme.sage", (r"\bTheme\s*\.\s*sage\b",), ("Sage",), RETIRED),
    Token("Theme.stageLight", (r"\bTheme\s*\.\s*stageLight\b",), ("StageLight",), RETIRED),
    # The palettes that hold the retired colours (Theme.swift: zones = stageAwake, accentSecondary, accent, warning, alert;
    # band = accent, warning, alert).
    Token("Theme.zones", (r"\bTheme\s*\.\s*zones\b",), (),
          "the zone palette holds accent, warning, alert and accentSecondary: pick the zone's ink from the metric, not the palette"),
    Token("Theme.band", (r"\bTheme\s*\.\s*band\b",), (),
          "the band colour is accent, warning or alert by score: pick the ink from the metric"),
]
ALERT = Token("Theme.alert", (r"\bTheme\s*\.\s*alert\b",), ("Alert",),
              "coral only inside a destructive control (Button(role: .destructive) or a .destructive pill); elsewhere it is "
              "metricStrain, the metric's colour or ink")
# The named constants that are Theme.signal under another name: their uses are marks too, each needs its own ALLOW entry
# (`Self.` is how their own types read them).
SIGNAL = Token("Theme.signal",
               (r"\b(?:Theme|Brand)\s*\.\s*signal\b",
                r"\b(?:FocusedRowInk\.mark|RulerScale\.needleColor|RestBar\.ringInk|Self\.(?:needleColor|ringInk))\b"),
               ("Signal",),
               "Volt is 'now' only: the active row, the rest ring, a today dot, the ruler needle, a series' last point; "
               "a new mark needs design sign-off and an ALLOW entry in scripts/check-accent-use.py")
TOKENS = [*HYGIENE_TOKENS, ALERT, SIGNAL]


@dataclass(frozen=True)
class Allow:
    """`tokens` may appear in `path` only inside what `inside` matches (a regex on code with comments blanked and strings
    kept). Write `inside` as the mark's own expression (`Circle()\\s*\\.fill\\(Theme\\.signal\\)`), never the function or
    call around it: whatever else that holds (a label, a line beside it) is still checked. `construct` is for a whole
    deleted-soon definition: the match then runs on to the end of its statement (braces, parentheses, modifier chain).
    `uses` is how many places in the file the entry covers; a different count fails, so a second copy of the mark does not
    ride on the first one's entry."""
    path: str
    tokens: tuple
    inside: str
    reason: str
    uses: int = 1
    construct: bool = False


# Up to two levels of nested parentheses inside a call's arguments.
ARGS = r"(?:[^()]|\((?:[^()]|\([^()]*\))*\))*"

ALLOW = [
    # Teal: one definition left, deleted with Theme.accent in the gate PR.
    Allow("Ryft/Features/Train/TrainComponents.swift", ("Theme.accent", "TealButtonStyle"), r"\bstruct TealButtonStyle\b",
          "its definition only: still used outside the linted folders (CoachMarks, PushPrePromptCard); T5.9 deletes the "
          "struct, Theme.accent and this entry together", construct=True),
    # Volt: the brief's five marks (brief.md §1, Theme.signal's doc), L27's two for Train, L17's series end. Each entry is
    # the mark's own expression; a label or a line beside it is not covered.
    # The active row's dot and bar: the constant and its three uses.
    Allow("Ryft/Features/Train/Session/FocusedRowInk.swift", ("Theme.signal",), r"\bstatic let mark\s*=\s*Theme\.signal\b",
          "the active row's dot and leading bar (L27, D6B-1): the constant's definition"),
    Allow("Ryft/Features/Train/Session/CollapsedExerciseRow.swift", ("Theme.signal",), r"\bCapsule\(\)\s*\.fill\(FocusedRowInk\.mark\)",
          "the active row's leading bar (L27, D6B-1)"),
    Allow("Ryft/Features/Train/Session/SetRow.swift", ("Theme.signal",), r"\bCircle\(\)\s*\.fill\(FocusedRowInk\.mark\)",
          "the active row's dot on its number (L27, D6B-1)"),
    Allow("Ryft/Features/Train/Session/SetRow.swift", ("Theme.signal",), r"\bCapsule\(\)\s*\.fill\(FocusedRowInk\.mark\)",
          "the active row's leading bar (L27, D6B-1)"),
    # The rest ring: the pill's and the List layout's.
    Allow("Ryft/Features/Train/Session/RestPill.swift", ("Theme.signal",), r"\.stroke\(Theme\.signal,\s*style:",
          "the running rest's progress ring, the stroke only, not its track (L27, D6B-10)"),
    Allow("Ryft/Features/Train/Session/RestBar.swift", ("Theme.signal",), r"\bstatic let ringInk\s*=\s*Theme\.signal\b",
          "the List layout's rest ring (L27, D6B-1): the constant's definition"),
    Allow("Ryft/Features/Train/Session/RestBar.swift", ("Theme.signal",), r"\.stroke\(Self\.ringInk,\s*style:",
          "the List layout's rest ring, the stroke only, not its track (L27, D6B-1)"),
    Allow("Ryft/Features/Train/History/ExerciseDetailView.swift", ("Theme.signal",),
          rf"\bPointMark\({ARGS}\)\s*\.foregroundStyle\(Theme\.signal\)",
          "the e1RM series' last point, the 'today' mark of a series (L17, D6B-14); the line is `spec.color`"),
    Allow("Ryft/Design/DateStrip.swift", ("Theme.signal",), r"\bif isToday\s*\{\s*Circle\(\)\s*\.fill\(Theme\.signal\)",
          "the 4 pt dot under today (S11, D6B-15)"),
    Allow("Ryft/Design/RulerScale.swift", ("Theme.signal",), r"\bstatic let needleColor\s*=\s*Theme\.signal\b",
          "the ruler's needle (brief §1): the constant's definition"),
    Allow("Ryft/Design/RulerScale.swift", ("Theme.signal",), rf"\bRulerNeedle\({ARGS}\)\s*\.fill\(Self\.needleColor\)",
          "the ruler's needle (brief §1): its fill, not the ticks"),
    Allow("Ryft/Design/Sparkline.swift", ("Theme.signal",),
          r"\.fill\(Self\.circle\(end,\s*Self\.endDotRadius\),\s*with:\s*\.color\(Theme\.signal\)\)",
          "the sparkline's end dot, the 'today' mark of a series (L17); the line and the lone dots are ink"),
    Allow("Ryft/Design/DotRow.swift", ("Theme.signal",), r"\bcase \.today:\s*Circle\(\)\s*\.fill\(Theme\.signal\)",
          "the 'today' dot in dot rows (brief §1)"),
    Allow("Ryft/Design/RyftTabBar.swift", ("Theme.signal",), r"\bCircle\(\)\s*\.fill\(isSelected\s*\?\s*Theme\.signal\s*:",
          "the active tab's dot, not its label (brief §1)"),
    Allow("Ryft/Design/GlowTile.swift", ("Theme.signal",), r"\bCircle\(\)\s*\.fill\(Theme\.signal\)",
          "the Insights hint dot, drawn in the tile's preview, not the preview's texts (brief §1)"),
    Allow("Ryft/Features/Insights/InsightTile.swift", ("Theme.signal",), r"\bCircle\(\)\s*\.fill\(Theme\.signal\)",
          "the Insights hint dot before the idea, not `wordColor` or `bodyColor` (brief §1)"),
    Allow("Ryft/Features/Profile/NocturneStructuresCatalog.swift", ("Theme.signal",), r"\bCircle\(\)\s*\.fill\(Theme\.signal\)",
          "the debug catalog's copy of that hint dot (area C's file)"),
    Allow("Ryft/Design/Theme.swift", ("Theme.signal",), r'\bstatic let signal\s*=\s*Color\("Signal"\)',
          "the colour's definition"),
    Allow("Shared/OrbitGaugePalette.swift", ("Theme.signal",), r'\bsignal:\s*Color\("Signal"\)',
          "the readiness marker in the orbit's inner ring, by asset name because Shared/ has no Theme (brief §1)"),
    Allow("RyftWidgets/RyftWidgets.swift", ("Theme.signal",), r"\bCircle\(\)\s*\.fill\(Brand\.signal\)",
          "the Live Activity's dot while resting (D6B-11)"),
    Allow("RyftWidgets/RyftWidgets.swift", ("Theme.signal",), r"\.progressViewStyle\(\.linear\)\s*\.tint\(Brand\.signal\)",
          "the Live Activity's rest bar while resting (D6B-11)"),
]


# MARK: reading Swift

STRING_START = re.compile(r'#*"')


def mask(text, strings):
    """`text` with `//` and (nested) `/* */` comments blanked, and with `strings` also string literals blanked (the
    code inside `\\( )` stays). Same length, line breaks kept, so offsets and line numbers carry over."""
    out, n = [], len(text)

    def blank(s):
        return re.sub(r"[^\n]", " ", s)

    def literal(s):
        return blank(s) if strings else s

    def string(i):
        pounds = STRING_START.match(text, i).end() - i - 1
        quote = '"""' if text.startswith('"""', i + pounds) else '"'
        close, escape = quote + "#" * pounds, "\\" + "#" * pounds
        j = i + pounds + len(quote)
        out.append(literal(text[i:j]))
        while j < n and not text.startswith(close, j):
            if text.startswith(escape + "(", j):
                k = j + len(escape) + 1
                out.append(literal(text[j:k]))
                j = code(k, nested=True)
                if j < n:
                    out.append(literal(")"))
                    j += 1
            elif text.startswith(escape, j):
                out.append(literal(text[j:j + len(escape) + 1]))
                j += len(escape) + 1
            else:
                out.append(literal(text[j]))
                j += 1
        out.append(literal(text[j:j + len(close)]))
        return min(j + len(close), n)

    def code(i, nested):
        depth = 0
        while i < n:
            if text.startswith("//", i):
                end = text.find("\n", i)
                end = n if end < 0 else end
                out.append(blank(text[i:end]))
                i = end
            elif text.startswith("/*", i):
                start, i, level = i, i + 2, 1
                while i < n and level:
                    if text.startswith("/*", i) or text.startswith("*/", i):
                        level += 1 if text[i + 1] == "*" and text[i] == "/" else -1
                        i += 2
                    else:
                        i += 1
                out.append(blank(text[start:i]))
            elif STRING_START.match(text, i):
                i = string(i)
            else:
                c = text[i]
                if nested:
                    if c == "(":
                        depth += 1
                    elif c == ")":
                        if depth == 0:
                            return i
                        depth -= 1
                out.append(c)
                i += 1
        return i

    code(0, nested=False)
    return "".join(out)


OPEN, CLOSE = "([{", ")]}"
CONTINUES = re.compile(r"\s*(?:\.[A-Za-z_]|\{|\?|:|&&|\|\||else\b)")


def extent(src, start):
    """The end of the statement or declaration that begins at `start`: balanced brackets, then on past a line break only
    while the next line continues it (`.modifier(...)`, a trailing `{`, `else`, `? :`, `&&`, `||`). A `;` ends it."""
    depth, i, n = 0, start, len(src)
    while i < n:
        c = src[i]
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
            if depth < 0:
                return i
        elif c == ";" and depth == 0:
            return i
        elif c == "\n" and depth == 0 and not CONTINUES.match(src, i):
            return i
        i += 1
    return n


COMPARED = re.compile(r"(?:==|!=|~=|\bcase)\s*$")
TERNARY = re.compile(r"==\s*\.destructive\s*\?\s*")


def branch_end(src, start):
    """The end of a ternary's true branch that begins at `start`: its `:` (or the bracket that closes it)."""
    depth, i, n = 0, start, len(src)
    while i < n:
        c = src[i]
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
            if depth < 0:
                return i
        elif c == ":" and depth == 0:
            return i
        i += 1
    return n


def destructive_ranges(src):
    """Offset ranges inside which coral is a destructive control's: the calls that have `.destructive` among their
    arguments (not compared with it), from the callee's name to the end of its trailing closures and modifiers, and the true
    branches of `x == .destructive ? ... : ...`."""
    ranges = [(m.end(), branch_end(src, m.end())) for m in TERNARY.finditer(src)]
    for m in re.finditer(r"\.destructive\b", src):
        if COMPARED.search(src, 0, m.start()):
            continue  # `kind == .destructive`, `case .destructive`: asks, does not declare
        depth, i = 0, m.start() - 1
        while i >= 0:
            c = src[i]
            if c in CLOSE:
                depth += 1
            elif c in OPEN:
                if depth == 0:
                    break
                depth -= 1
            i -= 1
        if i < 0 or src[i] != "(":
            continue  # `case .destructive:` or a bare argument: not a control
        head = i
        while head > 0 and re.match(r"[\w.]", src[head - 1]):
            head -= 1
        ranges.append((head, extent(src, head)))
    return ranges


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


# MARK: the check

@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    token: str
    reason: str

    def __str__(self):
        return f"{self.path}:{self.line}: {self.token}: {self.reason}"


def check_source(path, text, allow, used=None):
    """The findings in one Swift file; `used` (a Counter) collects, per ALLOW entry, the places it covered a token."""
    hygiene, signal = in_hygiene_scope(path), in_signal_scope(path)
    if not (hygiene or signal):
        return []
    code = mask(text, strings=True)
    named = mask(text, strings=False)
    assert len(code) == len(text) == len(named)
    tokens = ([*HYGIENE_TOKENS, ALERT] if hygiene else []) + ([SIGNAL] if signal else [])
    destructive = destructive_ranges(code)
    allowed = []  # (token name, start, end, entry)
    for entry in allow:
        if entry.path != path:
            continue
        for m in re.finditer(entry.inside, named):
            end = extent(code, m.start()) if entry.construct else m.end()
            for token in entry.tokens:
                allowed.append((token, m.start(), end, entry))
    findings, covered = [], set()
    for token in tokens:
        in_code, as_asset = token.patterns()
        hits = [m.start() for pattern in in_code for m in re.finditer(pattern, code)]
        hits += [m.start() for pattern in as_asset for m in re.finditer(pattern, named)]
        for offset in sorted(set(hits)):
            covering = {(entry, start) for name, start, end, entry in allowed if name == token.name and start <= offset < end}
            if covering:
                covered |= covering
                continue
            if token.name == ALERT.name and any(start <= offset < end for start, end in destructive):
                continue
            findings.append(Finding(path, line_of(text, offset), token.name, token.reason))
    if used is not None:
        for entry, _ in covered:
            used[entry] += 1
    return findings


def swift_files(base):
    for top in ("Ryft", "Shared", "RyftWidgets"):
        for root, dirs, files in os.walk(os.path.join(base, top)):
            dirs.sort()
            for name in sorted(files):
                if name.endswith(".swift"):
                    yield os.path.relpath(os.path.join(root, name), base)


def check_repository(base=ROOT, allow=None):
    allow = ALLOW if allow is None else allow
    findings, used = [], Counter()
    for path in swift_files(base):
        with open(os.path.join(base, path), encoding="utf-8") as f:
            findings += check_source(path, f.read(), allow, used)
    return findings + check_repository_entries(allow, used)


def check_repository_entries(allow, used):
    """The ALLOW entries that matched nothing, or a different number of places than they say."""
    findings = []
    for entry in allow:
        if used[entry] == 0:
            findings.append(Finding(entry.path, 1, "unused ALLOW entry",
                                    f"`{entry.inside}` matches no use of {', '.join(entry.tokens)} any more; delete the entry "
                                    f"({entry.reason})"))
        elif used[entry] != entry.uses:
            findings.append(Finding(entry.path, 1, "ALLOW entry covers the wrong number of places",
                                    f"`{entry.inside}` covers {used[entry]} use(s) of {', '.join(entry.tokens)}, the entry "
                                    f"says {entry.uses}; a new copy of the mark needs its own entry and design sign-off "
                                    f"({entry.reason})"))
    return findings


# MARK: self-test

TRAIN, MYDAY, ACTIVITIES = "Ryft/Features/Train/Session/X.swift", "Ryft/Features/MyDay/X.swift", "Ryft/Features/Activities/X.swift"
JOURNAL, DESIGN = "Ryft/Features/Journal/JournalViews.swift", "Ryft/Design/X.swift"

# (name, path, snippet, tokens expected in order; empty = passes)
CASES = [
    ("accent in My Day fails", MYDAY, "Text(x).foregroundStyle(Theme.accent)", ["Theme.accent"]),
    ("accent in Activities fails", ACTIVITIES, "let c = Theme.accent", ["Theme.accent"]),
    ("accent in Train fails", TRAIN, "let c = Theme.accent", ["Theme.accent"]),
    ("accent in the Journal card fails", JOURNAL, "let c = Theme.accent", ["Theme.accent"]),
    ("accent in Train/Import is area C's", "Ryft/Features/Train/Import/X.swift", "let c = Theme.accent", []),
    ("accent in the other Journal files is not linted", "Ryft/Features/Journal/BehaviorsSection.swift", "let c = Theme.accent", []),
    ("accent in Design is not linted", DESIGN, "let c = Theme.accent", []),
    ("TealButtonStyle fails", TRAIN, ".buttonStyle(TealButtonStyle(prominent: true))", ["TealButtonStyle"]),
    ("PrimaryButton fails", MYDAY, 'PrimaryButton("Save") {}', ["PrimaryButton"]),
    ("ImportPrimaryButton is a different type", MYDAY, 'ImportPrimaryButton(title: "x")', []),
    ("accentSecondary fails", ACTIVITIES, "let c = Theme.accentSecondary", ["Theme.accentSecondary"]),
    ("warning fails", MYDAY, "let c = Theme.warning", ["Theme.warning"]),
    ("sage fails", MYDAY, "let c = Theme.sage", ["Theme.sage"]),
    ("stageLight fails", TRAIN, "let c = Theme.stageLight", ["Theme.stageLight"]),
    ("onAccent is not the accent", TRAIN, "let c = Theme.onAccent", []),
    ("the accent asset by name fails", MYDAY, 'let c = Color("Accent")', ["Theme.accent"]),
    # Teal under its other names (Theme.swift: teal is accent's colour).
    ("Theme.teal fails", TRAIN, "Circle().fill(Theme.teal)", ["Theme.accent"]),
    ("the Teal asset fails", TRAIN, 'Circle().fill(Color("Teal"))', ["Theme.accent"]),
    ("the accent asset with a bundle fails", TRAIN, 'Circle().fill(Color("Accent", bundle: .main))', ["Theme.accent"]),
    ("the accent asset by UIColor(named:) fails", TRAIN, 'let c = Color(uiColor: UIColor(named: "Accent")!)', ["Theme.accent"]),
    ("the retired assets by UIColor(named:) fail", MYDAY, 'let a = UIColor(named: "Warning")\nlet b = Color("Sage", bundle: nil)',
     ["Theme.warning", "Theme.sage"]),
    ("the generated colour symbol fails", TRAIN, "Circle().fill(Color(.accent))", ["Theme.accent"]),
    ("another asset name is not the accent", TRAIN, 'let c = Color("AccentLike")', []),
    ("SwiftUI's Color.teal fails", TRAIN, "Circle().fill(Color.teal)", ["Color.teal"]),
    ("a bare .teal fails", TRAIN, "Circle().fill(.teal)", ["Color.teal"]),
    ("systemTeal fails", TRAIN, "let c = Color(uiColor: .systemTeal)", ["Color.teal"]),
    ("Theme.teal is one finding, not two", TRAIN, "let c = Theme.teal", ["Theme.accent"]),
    ("a tealish name is not teal", TRAIN, "let c = tealish\nlet d = x.tealCount", []),
    ("Color.accentColor fails", TRAIN, "Text(x).foregroundStyle(Color.accentColor)", ["Color.accentColor"]),
    ("a bare .accentColor fails", TRAIN, "Text(x).foregroundStyle(.accentColor)", ["Color.accentColor"]),
    ("the accentColor modifier is not the value", TRAIN, "Text(x).accentColor(Theme.textPrimary)", []),
    # The palettes that hold the retired colours.
    ("a spaced Theme .accent fails", TRAIN, "let c = Theme .accent", ["Theme.accent"]),
    ("Theme.zones fails", TRAIN, "Circle().fill(Theme.zones[2])", ["Theme.zones"]),
    ("Theme.band fails", MYDAY, "let c = Theme.band(forScore: 70)", ["Theme.band"]),
    ("several in order, with their lines", MYDAY, "let a = Theme.warning\n\nlet b = Theme.sage", ["Theme.warning", "Theme.sage"]),
    # Comments and strings are not code.
    ("line comment", MYDAY, "// Theme.accent was here\nlet x = 1", []),
    ("doc comment", MYDAY, "/// Not `Theme.accent`, `TealButtonStyle`.\nlet x = 1", []),
    ("block comment", MYDAY, "/* Theme.warning */ let x = 1", []),
    ("nested block comment", MYDAY, "/* a /* Theme.warning */ Theme.sage */ let x = 1", []),
    ("string literal", MYDAY, 'let s = "Theme.accent"', []),
    ("multi-line string literal", MYDAY, 'let s = """\nTheme.accent\n"""', []),
    ("raw string literal", MYDAY, 'let s = #"Theme.accent \\(Theme.warning)"#', []),
    ("a // inside a string is not a comment", MYDAY, 'let s = "ryft://today"; let c = Theme.accent', ["Theme.accent"]),
    ("code inside an interpolation counts", MYDAY, 'let s = "x \\(Theme.accent)"', ["Theme.accent"]),
    ("a string inside an interpolation", MYDAY, 'let s = "\\(f("Theme.accent"))"', []),
    ("code after a comment on the line before", MYDAY, "// Theme.accent\nlet c = Theme.sage", ["Theme.sage"]),
    # Coral only in destructive controls.
    ("alert in a destructive Button passes", TRAIN,
     'Button(role: .destructive) {\n    go()\n} label: {\n    Label("Delete", systemImage: "trash")\n'
     "        .background(Theme.alert, in: Capsule())\n}\n.buttonStyle(.plain)", []),
    ("alert in a destructive pill passes", MYDAY, 'PillButton("Delete", kind: .destructive) { go() }.tint(Theme.alert)', []),
    ("alert in a plain Text fails", MYDAY, 'Text("x").foregroundStyle(Theme.alert)', ["Theme.alert"]),
    ("alert in a plain Button fails", TRAIN, "Button {\n    go()\n} label: {\n    Text(x).foregroundStyle(Theme.alert)\n}", ["Theme.alert"]),
    ("alert after a destructive Button fails", TRAIN,
     'Button(role: .destructive) { go() } label: { Text("x") }\nText("y").foregroundStyle(Theme.alert)', ["Theme.alert"]),
    ("alert under `case .destructive:` fails", MYDAY, "switch kind {\ncase .destructive: return Theme.alert\ndefault: return x\n}", ["Theme.alert"]),
    ("alert outside the linted folders", DESIGN, "let c = Theme.alert", []),
    ("alert by asset name outside a destructive control fails", MYDAY, 'Text(x).foregroundStyle(Color("Alert"))', ["Theme.alert"]),
    # Where a destructive control ends: at its `;`, not at the end of the line.
    ("alert after a destructive pill on the same line fails", MYDAY,
     'VStack { PillButton(Text("x"), style: .destructive) {}; Text(y).foregroundStyle(Theme.alert) }', ["Theme.alert"]),
    ("alert after a destructive pill and a semicolon fails", MYDAY,
     'PillButton(Text("x"), style: .destructive) { go() }; Text(y).foregroundStyle(Theme.alert)', ["Theme.alert"]),
    ("alert in the destructive pill before the semicolon passes", MYDAY,
     'PillButton(Text("x"), style: .destructive) { go() }.tint(Theme.alert); let z = 1', []),
    # A comparison with .destructive: the true branch is the destructive control's, nothing else is.
    ("alert in the true branch of == .destructive passes", MYDAY,
     "Text(x).foregroundStyle(kind == .destructive ? Theme.alert : Theme.textPrimary)", []),
    ("alert in the false branch of == .destructive fails", MYDAY,
     "Text(x).foregroundStyle(kind == .destructive ? Theme.textPrimary : Theme.alert)", ["Theme.alert"]),
    ("alert in the true branch of != .destructive fails", MYDAY,
     "Text(x).foregroundStyle(kind != .destructive ? Theme.alert : Theme.textPrimary)", ["Theme.alert"]),
    ("a call that only compares with .destructive is not a destructive control", MYDAY,
     "Row(title: t, active: kind == .destructive, valueColor: Theme.alert)", ["Theme.alert"]),
    ("the true branch ends at its colon", MYDAY,
     "Text(x).foregroundStyle(kind == .destructive ? Theme.textPrimary : Theme.alert)\nText(y).foregroundStyle(Theme.alert)",
     ["Theme.alert", "Theme.alert"]),
    ("a call that has .destructive as an argument is a destructive control", MYDAY,
     "Row(title: t, role: .destructive, valueColor: Theme.alert)", []),
    # Volt only in the allowed marks.
    ("signal in a Design file fails", DESIGN, "let c = Theme.signal", ["Theme.signal"]),
    ("signal in a Train view fails", TRAIN, "Circle().fill(Theme.signal)", ["Theme.signal"]),
    ("signal in the widget fails", "RyftWidgets/X.swift", "Circle().fill(Brand.signal)", ["Theme.signal"]),
    ("signal by asset name fails", "Shared/X.swift", 'let c = Color("Signal")', ["Theme.signal"]),
    ("signal by asset name with a bundle fails", "Shared/X.swift", 'let c = Color("Signal", bundle: nil)', ["Theme.signal"]),
    ("signal by UIColor(named:) fails", DESIGN, 'let c = UIColor(named: "Signal")', ["Theme.signal"]),
    ("onSignal is not the signal", DESIGN, "let c = Theme.onSignal", []),
    # The named constants that are Volt under another name.
    ("FocusedRowInk.mark in a Text fails", TRAIN, "Text(x).foregroundStyle(FocusedRowInk.mark)", ["Theme.signal"]),
    ("RulerScale.needleColor in a Text fails", TRAIN, "Text(x).foregroundStyle(RulerScale.needleColor)", ["Theme.signal"]),
    ("RestBar.ringInk in a Text fails", TRAIN, "Text(x).foregroundStyle(RestBar.ringInk)", ["Theme.signal"]),
    ("Self.needleColor and Self.ringInk fail", DESIGN, "a.fill(Self.needleColor)\nb.stroke(Self.ringInk)", ["Theme.signal", "Theme.signal"]),
    ("signal in a comment", DESIGN, "/// Volt, `Theme.signal`, is the needle.\nlet x = 1", []),
    ("signal in a test is not linted", "RyftTests/X.swift", "let c = Theme.signal", []),
]

# ALLOW entries for the self-test only
TEST_ALLOW = [
    Allow(DESIGN, ("Theme.signal",), r"\bstatic let needle\b\s*=\s*Theme\.signal", "test"),
    Allow(DESIGN, ("Theme.signal",), r"\bPointMark\(\)\s*\.foregroundStyle\(Theme\.signal\)", "test"),
    Allow(DESIGN, ("Theme.signal",), r"\bCircle\(\)\s*\.fill\(Theme\.signal\)", "test"),
    Allow(TRAIN, ("Theme.accent",), r"\bstruct Old\b", "test", construct=True),
]
ALLOW_CASES = [
    ("allowed declaration", DESIGN, "enum E {\n    static let needle = Theme.signal\n}", []),
    ("the same token on the next declaration", DESIGN, "enum E {\n    static let needle = Theme.signal\n    static let other = Theme.signal\n}",
     ["Theme.signal"]),
    ("allowed call with its modifier chain", DESIGN, "PointMark()\n    .foregroundStyle(Theme.signal)\n    .symbolSize(4)\nlet z = 1", []),
    ("the call's neighbour is not covered", DESIGN, "PointMark()\n    .foregroundStyle(Theme.signal)\nText(x).foregroundStyle(Theme.signal)",
     ["Theme.signal"]),
    ("the call's other modifiers are not covered", DESIGN, "PointMark()\n    .foregroundStyle(Theme.textPrimary)\n    .background(Theme.signal)",
     ["Theme.signal"]),
    ("a mark's label is not covered", DESIGN, "HStack {\n    Circle().fill(Theme.signal)\n    Text(x).foregroundStyle(Theme.signal)\n}",
     ["Theme.signal"]),
    ("a construct entry covers the whole struct only", TRAIN, "struct Old: ButtonStyle {\n    var c = Theme.accent\n}\nlet d = Theme.accent", ["Theme.accent"]),
    ("an entry allows its tokens only", TRAIN, "struct Old {\n    var c = Theme.warning\n}", ["Theme.warning"]),
    ("an entry is for its file only", MYDAY, "struct Old {\n    var c = Theme.accent\n}", ["Theme.accent"]),
    ("a moved line still passes (keyed by pattern)", DESIGN, "\n\n\n\nenum E {\n    // new comment\n    static let needle = Theme.signal\n}", []),
]

# The real allowlist against the marks as they are drawn, and the lines beside them that must not ride on their entries.
REAL_CASES = [
    ("InsightTile: the dot passes", "Ryft/Features/Insights/InsightTile.swift",
     "InsightRows(insight: i, wordColor: Theme.textPrimary, bodyColor: Theme.textPrimary) {\n    Circle()\n        .fill(Theme.signal)\n}", []),
    ("InsightTile: wordColor Volt fails", "Ryft/Features/Insights/InsightTile.swift",
     "InsightRows(insight: i, wordColor: Theme.signal, bodyColor: Theme.textPrimary) {\n    Circle()\n        .fill(Theme.signal)\n}", ["Theme.signal"]),
    ("InsightTile: bodyColor Volt fails", "Ryft/Features/Insights/InsightTile.swift",
     "InsightRows(insight: i, wordColor: Theme.textPrimary, bodyColor: Theme.signal) {\n    Circle()\n        .fill(Theme.signal)\n}", ["Theme.signal"]),
    ("tab bar: the dot passes, the label fails", "Ryft/Design/RyftTabBar.swift",
     "Circle()\n    .fill(isSelected ? Theme.signal : Theme.textPrimary.opacity(0.3))\nTabItemLabel(title: t).foregroundStyle(Theme.signal)", ["Theme.signal"]),
    ("sparkline: the end dot passes, the line fails", "Ryft/Design/Sparkline.swift",
     "context.stroke(lines, with: .color(Theme.signal))\ncontext.fill(Self.circle(end, Self.endDotRadius), with: .color(Theme.signal))", ["Theme.signal"]),
    ("rest pill: the ring passes, its track fails", "Ryft/Features/Train/Session/RestPill.swift",
     "Circle().stroke(Theme.signal, lineWidth: 2)\nCircle().trim(from: 0, to: f(at: d)).stroke(Theme.signal, style: StrokeStyle(lineWidth: 4))", ["Theme.signal"]),
    ("glow preview: the dot passes, its text fails", "Ryft/Design/GlowTile.swift",
     "Circle().fill(Theme.signal).frame(width: 6, height: 6)\nText(verbatim: \"Insight\").foregroundStyle(Theme.signal)", ["Theme.signal"]),
    ("the active row's bar passes", "Ryft/Features/Train/Session/CollapsedExerciseRow.swift",
     "Capsule()\n    .fill(FocusedRowInk.mark)\n    .frame(width: 3)", []),
    ("the active row's mark in a Text fails", "Ryft/Features/Train/Session/CollapsedExerciseRow.swift",
     "Capsule().fill(FocusedRowInk.mark)\nText(x).foregroundStyle(FocusedRowInk.mark)", ["Theme.signal"]),
    ("the ruler's needle passes, its ticks fail", "Ryft/Design/RulerScale.swift",
     "RulerNeedle(fraction: f, head: 1)\n    .fill(Self.needleColor)\nRulerTicks(count: 3).fill(Self.needleColor)", ["Theme.signal"]),
    ("the rest bar's ring passes, its track fails", "Ryft/Features/Train/Session/RestBar.swift",
     "Circle().stroke(RestBar.ringInk, lineWidth: 4)\nCircle().trim(from: 0, to: f).stroke(Self.ringInk, style: StrokeStyle(lineWidth: 4))", ["Theme.signal"]),
]


def self_test():
    failures = total = 0

    def expect(name, got, want):
        nonlocal failures, total
        total += 1
        if got != want:
            failures += 1
            print(f"FAIL {name}: got {got}, want {want}")

    for name, path, snippet, want in CASES:
        expect(name, [f.token for f in check_source(path, snippet, [])], want)
    for name, path, snippet, want in ALLOW_CASES:
        expect(name, [f.token for f in check_source(path, snippet, TEST_ALLOW)], want)
    for name, path, snippet, want in REAL_CASES:
        expect(name, [f.token for f in check_source(path, snippet, ALLOW)], want)
    lines = check_source(MYDAY, "let a = 1\n\nlet b = Theme.sage // x\n", [])
    expect("reports the line", [f.line for f in lines], [3])
    expect("prints file:line: token: reason", str(lines[0]).startswith(f"{MYDAY}:3: Theme.sage: "), True)
    # An ALLOW entry that matches nothing is reported; one that matches is counted, once per place.
    used = Counter()
    check_source(DESIGN, "enum E { static let needle = Theme.signal }", TEST_ALLOW, used)
    expect("a matching entry is used once", dict(used), {TEST_ALLOW[0]: 1})
    used = Counter()
    check_source(DESIGN, "Circle().fill(Theme.signal)\nCircle().fill(Theme.signal)\n", TEST_ALLOW, used)
    expect("two copies of a mark are counted twice", used[TEST_ALLOW[2]], 2)
    unused = [f for f in check_repository_entries(TEST_ALLOW, Counter())]
    expect("an unused entry is reported", [f.token for f in unused], ["unused ALLOW entry"] * len(TEST_ALLOW))
    wrong = check_repository_entries(TEST_ALLOW, Counter({TEST_ALLOW[2]: 2}))
    expect("an entry with the wrong count is reported",
           [f.token for f in wrong if f.token != "unused ALLOW entry"], ["ALLOW entry covers the wrong number of places"])
    # The real allowlist is well formed.
    names = {t.name for t in TOKENS}
    for entry in ALLOW:
        expect(f"{entry.path}: has a reason", bool(entry.reason.strip()), True)
        expect(f"{entry.path}: compiles", bool(re.compile(entry.inside)), True)
        expect(f"{entry.path}: tokens are known", all(t in names for t in entry.tokens), True)
        expect(f"{entry.path}: {entry.inside} is a mark, not a function", re.match(r"\\bfunc |\\bstruct (?!TealButtonStyle)", entry.inside) is None, True)
    if failures:
        print(f"{failures} of {total} self-test checks failed.")
        sys.exit(1)
    print(f"check-accent-use self-test: {total} checks passed.")


def main():
    if "--self-test" in sys.argv[1:]:
        self_test()
        return
    findings = check_repository()
    for f in findings:
        print(f)
    if findings:
        print(f"\n{len(findings)} colour problem(s): teal is recovery's, Volt is 'now' "
              "(docs/work/2026-11-16-nocturne/design-pr6-b-train.md, colour hygiene).")
        sys.exit(1)
    print("Accent use: no retired or misplaced colour in Train, My Day, Activities or the Journal card; Volt only in its marks.")


if __name__ == "__main__":
    main()
