# fix/pr6-follow-ups: review log

## Code review (b6e416e..3e44a02), 2026-11-21
No blockers. All four items confirmed, as are the binding checks and the contract (API.md and the platform's train.go).

| # | Sev | Finding | Decision |
|---|---|---|---|
| 1 | S | `train.pausedPlanID` in `UserDefaults.standard` is shared by suites running in parallel, so tests can race | Fix: inject a `UserDefaults` into `TrainLibrary`; each rig gets its own suite |
| 2 | N | A refresh in flight can undo an action's patch | Fix: a catalog write counter; the refresh skips its writes if the counter moved |
| 3 | N | `aPlanThatCannotLoadSaysSo` is weaker | Fix: assert the message |
| 4 | N | Start workout's failed plan read shows nowhere | Left: needs strings; logged |
| 5 | N | After a switch whose plans re-read fails, today's plan day isn't fetched | Fix: `loadToday` runs whatever the plans read returned |
| + | — | The midnight flake in `ActivitiesNocturneRuleTests/saveStaysOffUntilTheFormIsValid` | Fix in the test (`test:` commit) |

## Round 2 (a53a9ea)
- **S1:** `TrainLibrary` takes an injected `UserDefaults`. Every test rig gets a suite of its own
  (`UserDefaults.isolated()`), and the save/restore code is gone. Two isolation tests cover it.
- **N2:** a `catalogWrites` counter. A refresh skips its overview and plan-day writes if an action or a re-read wrote in
  between. Four cases, plus a save during a refresh.
- **N3:** the test asserts the message and the Details again.
- **N5:** `reloadCatalog` reads today's plan day even when the plans read fails (bound to its side).
- **Midnight flake:** `saveStaysOffUntilTheFormIsValid` runs on a `TestClock` at 10:00.
- **Left:** Start workout's failed plan read shows nowhere (needs strings). `reloadCatalog`'s own read against a later
  action is the same class of race, rare, and fixed by the next refresh.

## Runs
- **Round 1 (3e44a02):** 16/16 mutants killed; UISmoke 53 passed, 0 failed, 1 skipped; the Release build passed.
- **Round 2 (a53a9ea):**
  - strict build with ios.yml's flags, 0 warnings;
  - Unit plan twice, at parallel width 4 in random order: 4,789 passed, 0 failed, 4 skipped, 1 expected failure, each time;
  - UISmoke 53 passed, 0 failed, 1 skipped;
  - 10/10 mutants killed;
  - `make lint` and `make style` green.
