---
name: review-checks-today-state
description: Recurring things to check early when reviewing RYFT Today/widget state changes (day labels, per-accessor recomputation, widget day rollover, facts-builder cost, hidden-note UI tests, de previews)
metadata:
  type: feedback
---

When reviewing Today hero/tiles/widget changes, check these first (found in T2 "one consistent Today" review, 2026-10-21):
- Hard-coded day words ("Yesterday's readiness…") next to values from the *latest scored day*, which can be older (a night without the watch). Gauge/tiles show the real date; copy must too.
- Every `TodayViewModel` accessor rebuilds `facts` (incl. a SwiftData fetch via `lastUpdated`) and re-runs the decision; count calls per body when accessors are added.
- Widget snapshot fields that only matter after midnight (`previousReadiness` feeds `asOf`); a branch that drops them shows "–" the next morning.
- Debugger-authored tests that the implementer edits: compare against design.md (authoritative) and against the debugger's other tests (they can contradict each other).

Found in T4 "honest calibration" (2026-10-23), nothing blocking but easy to miss:
- New inputs added to `TodayViewModel.facts` (flag, tracker selection) run on *every* `facts` call (~4 per body plus
  `TimelineView` ticks) and on the first frame. Reading `env.trackerCatalog` there forces the lazy
  `TrackerCatalog.bundled` decode on main before `RyftApp` decodes it off-main after the first frame. Ask to gate the
  read on the row that needs it (e.g. `today.waitingEndsCalibration == false`).
- A note shown with `.accessibilityHidden(readWithGauge)` (spoken via the gauge's value) can't be found by its
  identifier in XCUITest; design UI-test plans that say "shows `today.gaugeNote`" must assert the gauge's value.
- `.environment(\.locale, de)` previews don't localize strings built by `String(localized:)` in models or by
  `ListFormatStyle`; only `SHOT_LANG=de` screenshots prove German copy.

**Why:** these were the non-obvious defects in a review where the decision table itself was correct.
**How to apply:** scan for them before deep-reading the table logic. See [[ryft-review-workflow]].

Per-body reads (My Day A1 part 2, 2026-10-23): grep new view models for `env.reads.revision` / `reads.states`. The
ReadScheduler doc says only Sync details observes `revision`; a Today card reading it re-renders on every landed read
(journal, config, Train…). Then count SwiftData fetches in the computed content: Repository reads are memoised,
`ActivityStore` / `TrainStore` fetches are not ("runs per render on memoised reads" was half true).
