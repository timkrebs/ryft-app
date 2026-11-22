---
name: project-gate-g2-circle-menu-and-deletions
description: Nocturne gate G2 (2026-11-21) — CircleMenu/CircleButtonLook, SessionOfflineLine, card radius token, ValueChipRole; what the design note missed in the deletions; Menu pixel and a11y-frame pitfalls
metadata:
  type: project
---

G2 of the Nocturne gate (T5.9), branch `feat/nocturne-gate-g2` off `feat/nocturne-gate`:
- `Design/CircleMenu.swift` (a `Menu` drawn with `CircleButtonLook`, the `ViewModifier` in `CircleButton.swift` that
  `CircleButtonStyle` uses too); callers set the identifier (`session.more`, `activityDetail.menu`, `myday.add`).
- `Features/Train/Session/SessionOfflineLine.swift` (`session.offlineLine`), used by List and Focused.
- `ValueChipRole` (`.field` default textSecondary, `.row` textPrimary) on `ValueChipRow(_:role:chips:)`.
- Tests: `RyftTests/NocturneGateComponentsTests.swift` (source scans + hosted suite).

**Design-note gaps found (report them, don't trust "unused" claims blindly):**
- `MetricGauge.swift` also held `GaugeNote` and `GaugeNoteLink`, live on Today; moved to `Design/GaugeNote.swift`
  unchanged (GaugeNoteLink still uses `Theme.accent`: needs a replacement before G4 deletes the token).
- `AppState.cachedWorkoutDetail` has a caller (`WorkoutDetailViewModel.detail`); only `workoutDetail(_:)` was dead.
- Grep a file's every top-level declaration (`git show HEAD:file | grep -E "^(struct|enum|extension)"`) before deleting it.

**Pitfalls:**
- A `Menu` label and a `Button` label with the same modifiers can rasterise the centred glyph one pixel apart on 27.2
  (ellipsis at 15.33 vs 15.67 pt): compare rings pixel for pixel, glyphs by box (±⅓ pt) and brightest ink.
- `.accessibilityElement(children: .combine)` after a `.frame(maxWidth:minHeight:)` gives the element the union of its
  children's frames (the text, 15 high), not the 28 pt row: assert layout minimums as constants, not via the a11y frame.
- `ReduceMotionScanTests.noBareAnimation` has a floor on calls seen (was 110; 109 after the deletions → 105).
- `SessionView`'s List reads `@Environment(TrainSyncService.self)`, Focused reads `controller.sync`: a hosted List test
  must add `.environment(c.sync)` (inner beats `previewEnvironment`'s `TrainPreview.sync`).
- `FocusedPreview.controller(.draftList, connectivity: ConnectivityMonitor.preview(online: false))` = List offline;
  `monitor.update(true)` flips it live.
- Gate/build/test/mutate scripts: scratchpad `g2/` (gate.sh, build.sh, test.sh, mut/mutate.py with groups A/B).
- An env var for a hosted test under `xcodebuild test-without-building` needs the `TEST_RUNNER_` prefix
  (`TEST_RUNNER_G2_DIR=…`); a bare `G2_DIR=…` never reaches the runner and the guarded test silently writes nothing.
- A mutant that restores a deleted file must read it from the base commit, not `HEAD`, once the deletion is committed.
- Splitting one file's hunks across commits without `git add -p`: `git diff file > p`, cut the hunks into two patches,
  `git apply --cached` each before its commit.
