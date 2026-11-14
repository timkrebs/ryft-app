---
name: feedback-test-waits-on-actors
description: RyftTests must poll actor state (not sleep a fixed real time) before asserting a task reached an actor; wait for TestClock.pendingSleeps before advance(by:); the parallel Unit plan breaks fixed sleeps
metadata:
  type: feedback
---

In RyftTests, never wait for a spawned task to reach an actor (e.g. `RequestBudget.acquire`) with a fixed
real `Task.sleep(for: .milliseconds(20))`. Poll the actor's observable state (`await budget.waiting == n`)
with a deadline instead. Negative checks ("still 3 admitted after 30 ms") may keep a short sleep.

**Why:** on 2026-10-22 two `RequestBudgetTests` passed alone but failed in the full Unit plan on iPhone 18 Pro
(parallel clones): the waiter hadn't reached the actor yet, so the queue order came out wrong. Tasks that stay
on the main actor (ReadScheduler.run callers in `@MainActor` tests) are FIFO and were safe with a sleep.

**How to apply:** any new test of an actor-based limiter, queue or coordinator; time-based behaviour goes on
`TestClock` ([[project-dev-machine-disk]] for running the plan).

**TestClock sleeps are relative (2026-10-26, A2 uploader).** `TestClock.sleep(for:)` computes its deadline when the
sleeper registers. A retry timer spawned in an unstructured `Task` may register *after* the test's `advance(by:)`, so
its deadline lands a whole step late and the retry never fires (failed ~2 of 3 runs, passed once with prints added).
Before advancing to fire a timer, `#expect(await eventually { clock.pendingSleeps == 1 })`; in app code, timers sleep
until an absolute due date (`due.timeIntervalSince(clock.now())`), so a late start fires at once instead of late.

**Proving ✗ on main (2026-10-31, D3b).** The Unit plan has a 1-minute execution allowance per test: a new test whose
`eventually` chain times out (30 s each) on the unchanged code gets killed, and the clone restarts. Killed tests
appear only in xcodebuild's failure list, not as "Test case … failed" lines; read per-test issues from the result
bundle (`xcresulttool get test-results tests`). Expect a ✗ run to take minutes; run just the new suite.

**Main-actor joiners and absent asks (2026-10-31, T2 round 1).** To make a main-actor `Task { … }` reach a
`ReadScheduler` flight before `advance(by:)`, `await Task { @MainActor in }.value` (enqueued after it, so it runs
after) and prove the join afterwards (`api.count("syncStatus") == 1`), never `eventually { inFlight.contains }`
(already true from the first flight). A test of "no ask before X" must wait briefly for the ask
(`!(await eventually(timeout: .milliseconds(200)) { reads > n })`): the coordinator cancels a poll task that hasn't run
yet when the next poll starts, so an early ask can vanish and a mutant survives. A killed run (1-minute allowance)
also stops later tests in the same clone: a suite count lower than expected means tests never ran, not that they passed.
Widget snapshot files aren't byte-stable: compare the decoded `kind`, not `Data`.
