---
name: review-checks-screen-loads
description: RYFT review checks for screen view-model loads driven by .task(id:) (Nocturne T5.2 Strain/Workout, 2026-11-18) - probed restart order, defer-clobbered isLoading, day-keyed "loaded" markers, swallowed-error loaders, deep-link clamps
metadata:
  type: feedback
---

Found in the T5.2 review (Strain + Workout detail, 2026-11-18); the suite was green:
- **`.task(id:)` restart order (probed, macOS swiftc + NSHostingView, no need to re-probe):** SwiftUI starts the new
  task *before* the cancelled one unwinds. So a `defer { isLoading = false }` in the old load clears the new load's flag.
  Any "this day finished loading" marker (`loadedDay`) left from an earlier non-caching completion (a failure) then makes
  the board read "loaded, no data" while the reload runs. Fix that held in the probe: reset the marker at load start and
  guard post-await writes (incl. the defer) with a generation token. Probe recipe: a VM copy with a fake request that
  polls `Task.isCancelled`, keys A→B→A, sample the look at 50-600 ms.
- **Loaders that swallow errors** (`AppState.workoutDetail` returns `WorkoutDetail(workout:)` on failure, `loaded = true`)
  turn a 503/offline into "No heart-rate zones for this workout." Check every `try?` loader whose fallback feeds an
  absence sentence.
- **Clamping a selection to a strip** also clamps deep links (`DeepLinkRouter .day` → `strain.select`): an old
  notification lands on another day. Grep the router for every caller of a newly clamped setter.
- **A restyled shared strip without the date** (DateStrip shows weekday initials only): when a header subtitle is removed
  "because the strip shows the date", check the strip really does, for sight and VoiceOver.

**Why:** none was covered by the PR's tests; the first needed a probe to settle task ordering. **How to apply:** any
screen VM with `.task(id:)` loads, day selection or a "no X" state. See [[review-checks-derived-states]],
[[review-checks-multistep-flows]].

Recurred in T5.5 (Sleep modes, 2026-11-18): one VM's `isLoading`/`failure` shared by Day, Week and Month, with a range-load
`defer { isLoading = false }` and `if range == nil { failure = … }` read *after* the await (so with the mode by then current:
in Day `range` is nil, so Week's error lands on Day). Any `lastUpdated` bump restarts the task. Look for shared flags across modes.
