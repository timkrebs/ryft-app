---
name: project-gate-g3-ax-and-keyboard
description: Nocturne gate G3 (2026-11-21) — Report a problem's Done in the pinned bar, ruler labels from AX1, About you's menu row, the journal chip cap; hosted keyboard and pixel probes
metadata:
  type: project
---

G3 of the Nocturne gate (T5.9), branch `feat/nocturne-gate-g3` off `feat/nocturne-gate` f51a7fa:
- D5 `ReportProblemView`: no `.keyboard` toolbar; while `editing` the pinned bar is [Done · Send] (12 apart,
  `ReportProblemLayout.barButtonGap`), from AX1 stacked Send above Done (8). Bar Done is `report.done`, the same id as the
  sent/queued outcome's Done (never on screen together; the note chose it). `startsEditing` param for previews.
- Row 4 `RulerLabels`: from AX1 `RulerScale.accessibilityLabelSets` = [all, ends, first], then an empty fallback; the
  interior labels are all-or-nothing (in-order or middle-first priority would give "0 moderate 100" at AX3, contradicting
  the note's "0 … 100"). Below AX1 the old joined-lines fallback stays. `RulerLabelLinesTests` had to change (its "all, in
  order" fails at AX by design).
- Row 5 `AboutYouView`: from AX1 `GroupedRow.menu("Birth year", value: year or "Choose", identifier: "aboutYou.year")`
  in a titleless `GroupedCard`; wheel below AX1. Device geometry (402 × 874, top 62, bottom 34): at AX3 the row starts
  at 629 under a bar at 662 (needs a short scroll to be whole); at AX5 it starts at 795, below the bar at 637. The draft
  had no safe areas, so "above the bar without scrolling" is a spec gap reported to the lead; tests assert "starts above
  at AX3, above the bar after a scroll at AX3/AX5", and the UI test uses `app.reveal(row)`.
- Row 6 `JournalDateStrip`: chip is a nested `Chip` view so its `@ScaledMetric` reads the capped size
  (`.dynamicTypeSize(...JournalLayout.chipMaxTypeSize)` on the strip); `JournalLayout.chipInsets(for:)` pure rule.

**How to apply (probes):**
- `@ScaledMetric` on a view reads that view's environment: a `.dynamicTypeSize` cap applied inside its own body doesn't
  reach it. Put the metric in a child view below the cap.
- Hosted keyboard: `w.window.makeKey()` then `UITextView.becomeFirstResponder()`; observe
  `keyboardWillChangeFrameNotification` in a `@MainActor` class (no deinit touching the token; `stop()`).
- Text inside a combined a11y element: ink box with `WindowPixels.box(in: chip.frame) { lum > 0.45 }` on an unselected
  (surface) chip; the ground in the rounded corners is dark too, so only words count.
- UI test content size: `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXL` (AX3).
- Hosted probes need `w.host.additionalSafeAreaInsets.top = 62` to see device geometry; a draft render without it
  hides "under the bar" problems.
- Mutants (all caught): ruler AX path off, About you wheel at AX, journal cap/insets off, the keyboard toolbar back
  (hosted + UI); Done above Send at AX, cap only, ends-before-all, value text; strip without scrollTo, 8 gap. Zero
  vertical chip inset is caught only by the pure `chipInsets` test (44 pt min height hides it from the ink probe).
- `xcodebuild -test-iterations 1` is refused (rc 64, "more than 1 iteration"): leave the flag out.
- A cold-keyboard hosted test takes ~30 s and holds `HostedWindow.busy`; with parallel clones a neighbour
  (SignedOutOnboardingTests.welcomeWaysIn) hit its 60 s allowance once; alone it passes.
- FormField's focus bar draws a white bar at the field's leading edge while focused: not a stray caret.
- Row 4 also broke `NocturneComponentRenderTests` (two AX3 Today-ruler tests expected the joined, wrapping line): updated
  to "ends alone, one line, nothing in the middle third". Grep RyftTests for a component's old fallback before calling
  a ruler/label rule done. Commits 546e0b5..2e6d4c3 on `feat/nocturne-gate-g3`; base f51a7fa already fails G1's sweep
  (GaugeNote `Theme.accent`, G2-deleted files on the skip list).
