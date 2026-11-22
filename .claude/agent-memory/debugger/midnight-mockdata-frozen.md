---
name: midnight-mockdata-frozen
description: "Index out of range" in hosted tests at 00:00 = MockData built once per process; tests that cross midnight
metadata:
  type: project
---

CI run 45079786939 (2026-11-23 00:00:15) trapped in `MockData.todayDetail.workouts[0]` (via `WorkoutPreview.workout`,
StrainHostedTests): MockData's nights were a `static let` built at first read, `todayDetail` reads at `.now`.
Fixed on branch `fix/midnight-index-crash` (nights keyed per day, `asOf:` seam).

**Why:** the whole hosted run is one process, so a run that spans 00:00 crashes whichever test reads next; no crash report
because the host dies inside the simulator. The 23:55 MyDayFailureTests failures in the same run were `TestClock(now: .now)` + 600 s.

**How to apply:** for a date-dependent crash or failure at 00:00 or 23:5x, look for process-lifetime `static let`s built
from `.now` (MockTrain.history is still one) and for `TestClock(now: .now)` advanced by minutes. Not a user crash: only
previews and tests index `workouts[0]`.
