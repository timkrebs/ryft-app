---
name: project-validator-ax-size-and-column-width
description: Check which content size a validator's "AX3" shot really is before fixing; what widens a scrolling column at AX5; hosted-test pitfalls from T5.8
metadata:
  type: project
---

T5.8 (2026-11-20): the validator's "AX3" sim shots (uiv-5 `x-*`) were AX5 (accessibility-extra-extra-extra-large).
Proof: its tree's "vs 7 d" (Satoshi caption, 12 pt) is 103 x 48; hosted, the same text is 79 x 36 at AX3
(`.accessibility3` + `.accessibilityExtraLarge`) and 103 x 48 at AX5. At true AX3 Sleep Week/Month had no overflow.

**Why:** the fix and the test must target the size where the bug shows, or the test passes under its mutant.

**How to apply:**
- Before fixing an "AX3" layout finding, match one text frame from the validator's tree against a hosted measurement
  at AX3/AX4/AX5 (a scratch `ZZDiag` test that `Issue.record`s frames; delete it after). Caption line heights:
  AX1 25, AX2 30, AX3 36.3, AX4 41.3, AX5 47.7. `@ScaledMetric(relativeTo: .caption)` 4 pt is 9.67 at AX3.
- A scrolling column (VStack in ScreenScaffold) takes the width of its widest child that can't shrink: one fixed-size
  row anywhere widens every sibling (picker, tiles) and shifts them off the 20 pt margin. Find it by hosting each piece
  alone in a 350-wide column and listing nodes wider than 350 (it was the night list: "7h 48m" + nap + consistency,
  not the delta the validator named). Test: every node's minX >= 20 and width <= screen - 40, at AX3 and AX5.
- A `ViewThatFits` whose last child is still too wide lays it out wider than offered; make the fallback one that always
  fits (text that wraps), or stack deterministically from AX1.
- Hosted sheets can be drawn scaled (~0.96 on 27.2): divide window-frame sizes by
  `sheet.convert(sheet.bounds, to: window).width / sheet.bounds.width` before comparing with a spec height.
- A nested `func` inside `HostedWindow.run { w in ... }` is not main-actor: calling `w.nodes()` in it fails to compile;
  inline the loop instead.
- zsh does not word-split `$G` (`G="git -C path"`): use a shell function `g() { git -C path "$@"; }`.
- Shared pixel reader for hosted tests: `RyftTests/WindowPixels.swift` (`at`, `count(in:where:)`, `box(in:where:)`).
- Mutation runs in T5.8 caught two weak tests: a "stays inside the width" check passes when text squeezes and wraps
  beside its neighbour (assert the stacked label is no wider than its widest line, measured as a separate Text); and
  once the real widener (night rows) was fixed, the head's old layout fit too, so the margins test no longer guarded
  it: a pixel test of the delta's ink bands (three lines, each centred) did. One element with `children: .combine`
  hides its parts from `w.nodes()`; read bands with `WindowPixels.box(in:where:)` row by row.
- Move a shared test helper into the first commit that uses it (cherry-pick onto a reset branch, `git checkout <tip>
  -- file`, amend), then compare `HEAD^{tree}` with the old tip.
