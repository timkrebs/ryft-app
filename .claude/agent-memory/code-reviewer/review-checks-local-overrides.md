---
name: review-checks-local-overrides
description: RYFT review checks for phone-side words that override the platform's state (scoring ledger, "requested after" rules, joined flights, stale so-far accessors, persisted since-markers vs clock set back, failures kept across accounts), plus the probe/mutant recipe
metadata:
  type: feedback
---

From the T2 D3b review (PR #88, `ScoringWord` ledger, 2026-10-31). Each of these was confirmed with a probe test:
- **The answer window versus the poll delay.** The ledger ignores status reads made less than 10 s after a write (the
  platform's cache time). The scoring wait's first poll is `max(2 s, expected_within_sec)`, and the platform's
  `ExpectedScoreSec` is a p95 with a minimum of 1 s (`plattform/backend/internal/store/syncstate.go`). With a fast
  scorer the wait ends on an answer that doesn't count, and the word stays `pending` until a push. Pushes are limited
  to one per 5 minutes per account. Compare every "ignore answers younger than X" rule with the poll schedule that is
  supposed to answer it.
- **A local word that collapses a server enum.** A push turned into `.scored` replaced `waiting_for_sleep` on a day
  without a night. The hero went from "Waiting for last night's sleep" to the score hero with no number. Ask what each
  server state becomes when the local word wins.
- **Two copies of one fact** (SyncService and Repository, synchronised by hand). The demo toggle (`AppState.reset` →
  `repository.clear()`) clears only one copy, and `sync.accountChanged()` clears only the other. Today and the widget
  then disagree. List every place that clears each copy.
- **Tests that reimplement the production closure.** A test with its own hand-written `store:` closure passed even
  with LiveSyncSteps mutated from `asked` to `clock.now()`. All 18 new tests passed with that mutant. Look for a test
  that drives the real step.

Round 2 (2026-10-31), also confirmed with probes:
- **An age guard keyed on the caller's ask time instead of the flight's start.** The scoring wait's poll can join a
  `ReadScheduler` flight that started 2 s after the write. The cached answer ends the wait, the ledger keeps `pending`,
  and no more polls follow. The `asked − begun` guard can't catch this and is dead under the 10 s first poll (that
  mutant survives). Probe: `env.reads.run(ReadKey(.syncStatus)) { clock.sleep(15); return cached }` with
  `Harness(expected: 3)`.
- **A "so far" accessor that outlives its run** (`sync.lastDaysTouched`). It is read on cancel paths where this run
  never called `sync.upload()`: a cancel before attempt 1, or the demo short-circuit in `LiveSyncSteps.upload`. An
  earlier run's days become `pending` again. Ask whether every reader of `touchedSoFar` is paired with an upload call.

Probe recipe: `rsync -a --exclude .git` the worktree into the scratchpad, then add tests there. Swift Testing
`-only-testing` ids need `()` (`RyftTests/Suite/test()`); without them xcodebuild runs nothing and says SUCCEEDED. The
first simulator launch after a build often fails with "No such process". Rerun with `test-without-building`.
Use a fresh `simctl create` device with `-parallel-testing-enabled NO`; reused devices and clones hang. Serial xcodebuild
often fails to exit after the tests finish. Wait for `Test run with [1-9]`, then kill only your own xcodebuild. Never
`simctl shutdown all`: a CI device may be booted, and the classifier denies it. Run mutants in two batches
(about 1 minute to build and 1 minute to test each). Several mutants per batch work if they target different tests.

Consent agree lag round 4 (2026-11-23, read-only re-review):
- **Persisted "since" markers ended only by `askedAt >= since`** (`withdrawalUnresolvedSince`): a clock set back after
  writing one makes every later read "older", so the hold never ends and all uploads stay paused with nothing named.
  The agreement got a void rule for the same thing (round 1 N-3, round 2 #5); check every new wall-clock marker for
  its own void rule (`TestClock.set(_:)` is the user changing the date).
- **A failure kept in a long-lived view model with its request ID** (Profile's Check with RYFT): ScreenModels' rule
  says a step's failure and request ID are the side's and go with the account-state forgetters, and
  `ProfileViewModel.accountChanged(from:)` doesn't clear new ones. Grep each new `private var …Failure` against it.
- **Value-identical keyed strings** (`syncdetails.workouts.paused` = "Paused"): a call-site revert to the plain key is
  invisible to unit tests, and CI's `make lint` runs without a build, so nothing marks the key stale. Say so; don't
  ask for a test that can't exist.

**Why:** these are the defects that remained after the PR's own mutation check passed (9 of 9 mutants caught).
**How to apply:** use these checks with [[review-checks-derived-states]] and [[review_checks_today_state]] whenever
local state overrides `GET /v1/me/sync`.
