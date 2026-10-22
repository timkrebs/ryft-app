---
name: review-checks-today-state
description: Recurring things to check early when reviewing RYFT Today/widget state changes (day labels, per-accessor recomputation, widget day rollover)
metadata:
  type: feedback
---

When reviewing Today hero/tiles/widget changes, check these first (found in T2 "one consistent Today" review, 2026-10-21):
- Hard-coded day words ("Yesterday's readiness…") next to values from the *latest scored day*, which can be older (a night without the watch). Gauge/tiles show the real date; copy must too.
- Every `TodayViewModel` accessor rebuilds `facts` (incl. a SwiftData fetch via `lastUpdated`) and re-runs the decision; count calls per body when accessors are added.
- Widget snapshot fields that only matter after midnight (`previousReadiness` feeds `asOf`); a branch that drops them shows "–" the next morning.
- Debugger-authored tests that the implementer edits: compare against design.md (authoritative) and against the debugger's other tests (they can contradict each other).

**Why:** these were the non-obvious defects in a review where the decision table itself was correct.
**How to apply:** scan for them before deep-reading the table logic. See [[ryft-review-workflow]].
