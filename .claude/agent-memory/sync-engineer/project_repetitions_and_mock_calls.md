---
name: project-repetitions-and-mock-calls
description: -test-iterations runs Swift Testing repetitions in parallel and still prints "passed" with issues; MockPlatformAPI.calls is read without its lock and races
metadata:
  type: project
---

Found 2026-10-31 (PR #88 round 3, a flake in `aRelaunchWithTodayStillPendingPollsUntilItLands`):

- **`MockPlatformAPI.calls` is read without the mock's lock.** `enter` appends under the lock from whatever thread a
  call runs on (the stale refresh's `day`/`days`/`me` reads arrive off the main actor). A test reading `api.calls`
  at that moment saw no "syncStatus" (about 4 in 60 repetitions) while `api.count("syncStatus")` said 1.
  **How to apply:** count calls with `api.count(_:)` (locked), never `api.calls.filter`. About 46 test lines still
  use `.calls`; a locked getter in the mock would fix them all (not done: outside that PR's scope).
- **Repetitions.** `xcodebuild … -test-iterations N -parallel-testing-enabled NO` starts all N Swift Testing
  repetitions at once in one process (good flake pressure), and the console ended "✔ Test run … passed" even though a
  repetition had recorded an issue. **How to apply:** judge by `grep -c 'recorded an issue'`, not the summary line.
- **Seeing a joined read.** `ReadScheduler.joiners(for:)` (internal) says a caller joined a flight in progress; wait
  on it (with the clock's next sleeper) before landing the flight. Waiting on `pendingSleeps` alone raced the join.

Related: [[feedback-test-waits-on-actors]], [[project-simulator-and-tools]].
