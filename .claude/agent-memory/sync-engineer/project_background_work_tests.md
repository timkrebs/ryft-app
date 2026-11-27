---
name: project-background-work-tests
description: BackgroundWork/BGTask completion tests - FakeSteps waits for scoring unless touched = []; give the Repository its own TestClock; settle closures must honour cancellation
metadata:
  type: project
---

Testing a BGTask's or background time's completion (`BackgroundWork.runRefresh`, `runBackfill`, `finishInBackground`)
against a held read-model write (2026-11-17, P1 fix round):

- `FakeSteps`' run waits for scoring on its clock (`pendingSleeps == 1` "waiting for scoring") unless
  `steps.touched = []`. With a TestClock nobody advances, the work never ends and the completion never starts its wait.
- Give the coordinator one TestClock and the Repository another (`repositoryWithAHeldWrite(clock:)`), then poll
  `clock.pendingSleeps == 1` on the Repository's to know the completion is inside `settledBeforeCompletion()`.
- An expiry can only stop a wait that honours cancellation: pass `settledBeforeCompletion()` (cancellable), not
  `settled()`, or the expiry test hangs until WriterHold's 10 s cap and "passes" late.
- Assert promptness with `eventually(timeout: .seconds(2)) { task.completed != nil }` before `await completion.value`:
  awaiting the value alone lets a mutant that waits for the hold pass after 10 s.

**Why:** the first version of these tests hung (60 s time limit, xctest restart) and the expiry ones failed for the
wrong reason. **How to apply:** any new test of a system completion; see [[feedback-test-waits-on-actors]] and
[[feedback-tests-pin-decisions]].
