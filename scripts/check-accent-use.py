#!/usr/bin/env python3
"""Colour hygiene for the Nocturne redesign (make lint; docs/work/2026-11-16-nocturne/design-pr6-b-train.md, "colour hygiene").

Teal is recovery's colour and nothing else (L27); Volt is "now" and nothing else. Two rules:

1. In `Features/Train/**` (except `Import/**`, area C's), `Features/MyDay/**`, `Features/Activities/**` and
   `Features/Journal/JournalViews.swift`, none of `Theme.accent`, `TealButtonStyle`, `PrimaryButton`,
   `Theme.accentSecondary`, `Theme.warning`, `Theme.sage`, `Theme.stageLight` appears, and `Theme.alert` appears only
   inside a destructive control (a call with `.destructive` among its arguments: `Button(role: .destructive) { ... }`,
   `PillButton(..., kind: .destructive)`; its trailing closures and modifiers count as inside).
2. `Theme.signal` (and `Brand.signal`, `Color("Signal")`) appears in `Ryft/`, `Shared/` and `RyftWidgets/` only in the
   marks `ALLOW` lists, each with its reason.

Comments and string literals are not code and never count; the code inside a string's `\\( )` does.

An `ALLOW` entry is keyed by file and a pattern that opens the construct it covers (a declaration, a call), not by line
number, so edits don't move it; the token is allowed only inside that construct. An entry that matches nothing fails too,
so a deleted or renamed mark takes its entry with it.

    python3 scripts/check-accent-use.py              # the repository; prints file:line: token: reason, exit 1 on any
    python3 scripts/check-accent-use.py --self-test  # snippets that must pass or fail
"""
import os
import re
import sys
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
# name, pattern on code with strings blanked, pattern on code with strings kept (asset names), reason
HYGIENE_TOKENS = [
    ("Theme.accent", r"\bTheme\.accent\b", r'\bColor\("Accent"\)',
     "teal is recovery's colour only (L27); controls and icons are Theme.textPrimary, the primary button is PillButton"),
    ("TealButtonStyle", r"\bTealButtonStyle\b", None, "the teal button is gone (T5.9); use PillButton"),
    ("PrimaryButton", r"\bPrimaryButton\b", None, "the teal primary button is gone; use PillButton"),
    ("Theme.accentSecondary", r"\bTheme\.accentSecondary\b", r'\bColor\("AccentSecondary"\)', RETIRED),
    ("Theme.warning", r"\bTheme\.warning\b", r'\bColor\("Warning"\)', RETIRED),
    ("Theme.sage", r"\bTheme\.sage\b", r'\bColor\("Sage"\)', RETIRED),
    ("Theme.stageLight", r"\bTheme\.stageLight\b", r'\bColor\("StageLight"\)', RETIRED),
]
ALERT = ("Theme.alert", r"\bTheme\.alert\b", r'\bColor\("Alert"\)',
         "coral only inside a destructive control (Button(role: .destructive) or a .destructive pill); elsewhere it is "
         "metricStrain, the metric's colour or ink")
SIGNAL = ("Theme.signal", r"\b(?:Theme|Brand)\.signal\b", r'\bColor\("Signal"\)',
          "Volt is 'now' only: the active row, the rest ring, a today dot, the ruler needle, a series' last point; "
          "a new mark needs design sign-off and an ALLOW entry in scripts/check-accent-use.py")


@dataclass(frozen=True)
class Allow:
    """`tokens` may appear in `path` inside the construct that `inside` opens (matched on code, comments and strings
    blanked; the construct runs from the match to the end of its statement: braces, parentheses, the modifier chain)."""
    path: str
    tokens: tuple
    inside: str
    reason: str


ALLOW = [
    # Teal: one definition left, deleted with Theme.accent in the gate PR.
    Allow("Ryft/Features/Train/TrainComponents.swift", ("Theme.accent", "TealButtonStyle"), r"\bstruct TealButtonStyle\b",
          "its definition only: still used outside the linted folders (CoachMarks, PushPrePromptCard); T5.9 deletes the "
          "struct, Theme.accent and this entry together"),
    # Volt: the brief's five marks (brief.md §1, Theme.signal's doc), L27's two for Train, L17's series end.
    Allow("Ryft/Features/Train/Session/FocusedRowInk.swift", ("Theme.signal",), r"\bstatic let mark\b",
          "the active row's dot and leading bar (L27, D6B-1)"),
    Allow("Ryft/Features/Train/Session/RestPill.swift", ("Theme.signal",), r"\bfunc ring\(",
          "the running rest's progress ring (L27, D6B-10)"),
    Allow("Ryft/Features/Train/Session/RestBar.swift", ("Theme.signal",), r"\bstatic let ringInk\b",
          "the List layout's rest ring (L27, D6B-1)"),
    Allow("Ryft/Features/Train/History/ExerciseDetailView.swift", ("Theme.signal",), r"\bPointMark\(",
          "the e1RM series' last point, the 'today' mark of a series (L17, D6B-14)"),
    Allow("Ryft/Design/DateStrip.swift", ("Theme.signal",), r"\bstruct DateStripDot\b",
          "the 4 pt dot under today (S11, D6B-15)"),
    Allow("Ryft/Design/RulerScale.swift", ("Theme.signal",), r"\bstatic let needleColor\b",
          "the ruler's needle (brief §1)"),
    Allow("Ryft/Design/Sparkline.swift", ("Theme.signal",), r"\bfunc draw\(",
          "the sparkline's end dot, the 'today' mark of a series (L17)"),
    Allow("Ryft/Design/DotRow.swift", ("Theme.signal",), r"\bfunc dot\(",
          "the 'today' dot in dot rows (brief §1)"),
    Allow("Ryft/Design/RyftTabBar.swift", ("Theme.signal",), r"\bfunc tabButton\(",
          "the active tab's dot (brief §1)"),
    Allow("Ryft/Design/GlowTile.swift", ("Theme.signal",), r"\bstruct GlowPreviewIdea\b",
          "the Insights hint dot, drawn in the tile's preview (brief §1)"),
    Allow("Ryft/Features/Insights/InsightTile.swift", ("Theme.signal",), r"\bInsightRows\(",
          "the Insights hint dot before the idea (brief §1)"),
    Allow("Ryft/Features/Profile/NocturneStructuresCatalog.swift", ("Theme.signal",), r"\bvar idea\b",
          "the debug catalog's copy of that hint dot (area C's file; rename the pattern if `idea` moves)"),
    Allow("Ryft/Design/Theme.swift", ("Theme.signal",), r"\bstatic let signal\b",
          "the colour's definition"),
    Allow("Shared/OrbitGaugePalette.swift", ("Theme.signal",), r"\bsignal: Color\(",
          "the readiness marker in the orbit's inner ring, by asset name because Shared/ has no Theme (brief §1)"),
    Allow("RyftWidgets/RyftWidgets.swift", ("Theme.signal",), r"\bstruct RestTimerDot\b",
          "the Live Activity's dot while resting (D6B-11)"),
    Allow("RyftWidgets/RyftWidgets.swift", ("Theme.signal",), r"\bstruct RestTimerBar\b",
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
    while the next line continues it (`.modifier(...)`, a trailing `{`, `else`, `? :`, `&&`, `||`)."""
    depth, i, n = 0, start, len(src)
    while i < n:
        c = src[i]
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
            if depth < 0:
                return i
        elif c == "\n" and depth == 0 and not CONTINUES.match(src, i):
            return i
        i += 1
    return n


def destructive_ranges(src):
    """Offset ranges of the calls that have `.destructive` among their arguments, from the callee's name to the end of
    its trailing closures and modifiers."""
    ranges = []
    for m in re.finditer(r"\.destructive\b", src):
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
    """The findings in one Swift file; `used` collects the ALLOW entries that matched something."""
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
        for m in re.finditer(entry.inside, code):
            for token in entry.tokens:
                allowed.append((token, m.start(), extent(code, m.start()), entry))
    findings = []
    for name, in_code, as_asset, reason in tokens:
        hits = [m.start() for m in re.finditer(in_code, code)]
        if as_asset:
            hits += [m.start() for m in re.finditer(as_asset, named)]
        for offset in sorted(set(hits)):
            covering = [entry for token, start, end, entry in allowed if token == name and start <= offset < end]
            if covering:
                if used is not None:
                    used.update(covering)
                continue
            if name == ALERT[0] and any(start <= offset < end for start, end in destructive):
                continue
            findings.append(Finding(path, line_of(text, offset), name, reason))
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
    findings, used = [], set()
    for path in swift_files(base):
        with open(os.path.join(base, path), encoding="utf-8") as f:
            findings += check_source(path, f.read(), allow, used)
    for entry in allow:
        if entry not in used:
            findings.append(Finding(entry.path, 1, "unused ALLOW entry",
                                    f"`{entry.inside}` matches no use of {', '.join(entry.tokens)} any more; delete the entry "
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
    # Volt only in the allowed marks.
    ("signal in a Design file fails", DESIGN, "let c = Theme.signal", ["Theme.signal"]),
    ("signal in a Train view fails", TRAIN, "Circle().fill(Theme.signal)", ["Theme.signal"]),
    ("signal in the widget fails", "RyftWidgets/X.swift", "Circle().fill(Brand.signal)", ["Theme.signal"]),
    ("signal by asset name fails", "Shared/X.swift", 'let c = Color("Signal")', ["Theme.signal"]),
    ("signal in a comment", DESIGN, "/// Volt, `Theme.signal`, is the needle.\nlet x = 1", []),
    ("signal in a test is not linted", "RyftTests/X.swift", "let c = Theme.signal", []),
]

# ALLOW entries for the self-test only
TEST_ALLOW = [
    Allow(DESIGN, ("Theme.signal",), r"\bstatic let needle\b", "test"),
    Allow(DESIGN, ("Theme.signal",), r"\bPointMark\(", "test"),
    Allow(TRAIN, ("Theme.accent",), r"\bstruct Old\b", "test"),
]
ALLOW_CASES = [
    ("allowed declaration", DESIGN, "enum E {\n    static let needle = Theme.signal\n}", []),
    ("the same token on the next declaration", DESIGN, "enum E {\n    static let needle = Theme.signal\n    static let other = Theme.signal\n}",
     ["Theme.signal"]),
    ("allowed call with its modifier chain", DESIGN, "PointMark(x: a, y: b)\n    .foregroundStyle(Theme.signal)\n    .symbolSize(4)\nlet z = 1", []),
    ("the call's neighbour after a blank statement", DESIGN, "PointMark(x: a, y: b)\n    .symbolSize(4)\nCircle().fill(Theme.signal)", ["Theme.signal"]),
    ("allowed in a struct body only", TRAIN, "struct Old: ButtonStyle {\n    var c = Theme.accent\n}\nlet d = Theme.accent", ["Theme.accent"]),
    ("an entry allows its tokens only", TRAIN, "struct Old {\n    var c = Theme.warning\n}", ["Theme.warning"]),
    ("an entry is for its file only", MYDAY, "struct Old {\n    var c = Theme.accent\n}", ["Theme.accent"]),
    ("a moved line still passes (keyed by pattern)", DESIGN, "\n\n\n\nenum E {\n    // new comment\n    static let needle = Theme.signal\n}", []),
]


def self_test():
    failures = 0

    def expect(name, got, want):
        nonlocal failures
        if got != want:
            failures += 1
            print(f"FAIL {name}: got {got}, want {want}")

    for name, path, snippet, want in CASES:
        expect(name, [f.token for f in check_source(path, snippet, [])], want)
    for name, path, snippet, want in ALLOW_CASES:
        expect(name, [f.token for f in check_source(path, snippet, TEST_ALLOW)], want)
    lines = check_source(MYDAY, "let a = 1\n\nlet b = Theme.sage // x\n", [])
    expect("reports the line", [f.line for f in lines], [3])
    expect("prints file:line: token: reason", str(lines[0]).startswith(f"{MYDAY}:3: Theme.sage: "), True)
    # An ALLOW entry that matches nothing is reported; one that matches is not.
    used = set()
    check_source(DESIGN, "enum E { static let needle = Theme.signal }", TEST_ALLOW, used)
    expect("a matching entry is used", {e.inside for e in used}, {TEST_ALLOW[0].inside})
    # The real allowlist is well formed.
    for entry in ALLOW:
        expect(f"{entry.path}: has a reason", bool(entry.reason.strip()), True)
        expect(f"{entry.path}: compiles", bool(re.compile(entry.inside)), True)
        expect(f"{entry.path}: tokens are known", all(t in {k[0] for k in [*HYGIENE_TOKENS, ALERT, SIGNAL]} for t in entry.tokens), True)
    total = len(CASES) + len(ALLOW_CASES) + 5
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
