---
name: review-checks-large-text
description: RYFT review checks for Dynamic Type / AX3-AX5 layout fixes (AX3 Welcome + live workout, 2026-11-17) - probed ViewThatFits lifetimes, test bounds measured at the uncapped size, guard-vs-repro tests, main-vs-fix test recipe, pixel-diff recipe
metadata:
  type: feedback
---

Found in the AX3 Welcome/live-workout fix review (90d9a3d, 2026-11-17). The code was sound; the gaps were in the tests:
- **ViewThatFits facts (probed with macOS swiftc + NSHostingView, no need to re-probe):** `.onAppear`/`.task` run only in the
  displayed child, and run again on every flip. The hidden plain child keeps its `@State` while hidden. The hidden child's
  representables are created for measuring but are not in the window. So a screen-level `onAppear` that changes the
  content's height must sit outside the ViewThatFits (inside it, it would oscillate). Sheets and `openURL` routing belong
  outside it too, because a flip removes the child that presented them. Dialogs inside `content` still close on a flip
  (an edge case). `content` is built once per child, so any fetch in it runs twice per body.
- **A bound measured at the uncapped size can't see a capped view.** The column titles are capped with
  `.dynamicTypeSize(...xxxLarge)`, but the bound was `1.5 x line(AX3)` = 59.5 pt, and two capped lines are only 47 pt.
  Measure the bound at the cap instead. Measured `.ryft(.label)` line heights: L 15.7, xxxL 23, AX3 39.7, AX5 52.7.
- **Check "fails on main" per test, not per suite:** the no-overlap test passed on main, because the elements were off
  screen, not overlapping. Recipe: `git archive HEAD | tar -x -C <scratch>`, then `git show origin/main:<file>` for the
  view files, then copy the xcconfigs. Build with the allowed DerivedData, then read the "Failure Message" nodes with
  `xcresulttool get test-results tests --compact` (on the bundle under DerivedData/Logs/Test).
- **"Pixel-identical at default":** diff the before/after PNGs with swiftc + ImageIO, skipping y < 140 px (the status bar).
  For sheets, compare only the sheet: its glass edges differ by 1-2 levels when the background behind it differs.
- A fresh-DerivedData build plus one suite took about 3 min even at load 200+. A review worktree lacks
  `Config/Debug.xcconfig`: copy the examples, then remove them afterwards.
- STATUS.md "Follow-ups" often lists the very bug that a fix closes. Check that the fix updates it.

Custom `Layout`s for large text (PR 4 fix round, 2026-11-17): check `sizeThatFits` and `placeSubviews` use the same width
and the same arrangement function; a baseline row that pins one child to `maxY` but reserves `max(descents)` agrees only
while that child's descent is the larger. A hosted a11y test can't prove "not truncated": a cut Text's label is still the
full string; compare the frame width with the ideal width (works for unscaled text only: a `minimumScaleFactor` Text cut at its floor still fills the offered width, so `width >= ideal x 0.8` passes either way), or read pixels.

**Why:** the suite was green and the screenshots were right. Only these checks showed that the tests prove less than
their names claim. **How to apply:** use them on any Dynamic Type / AX layout fix that comes with hosted tests. See
[[review-checks-design-components]], [[review-checks-session-ui]], [[review-checks-launch-overlays]].
