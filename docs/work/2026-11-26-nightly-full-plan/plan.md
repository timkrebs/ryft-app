# Nightly "Full test plan" times out (2026-11-26)

## Goal
The scheduled `ios.yml` run (FULL=true) gets through every test within its budget again, and stays meaningful.

## Measured (from CI logs, not locally)
| Night | Full step | Unit half | UI half |
|---|---|---|---|
| 11-04 (last green) | 14 min | 2,181 Swift Testing tests in 34 s | 48 tests, ~12.5 min |
| 11-17 | 28 min, red | 3,012 in 248 s | `LaunchSequenceUITests.testATapSkipsIt` red |
| 11-20 | 34 min, red (tests) | | |
| 11-21 → 11-26 | 45:12, timeout | 4,794 in 849 s (11-22); 5,093 in 1,073 s (11-25) | ~25 min reached P…, killed |

- Performance tests: 40 s.
- The unit half finishes ~4,200 tests in the first 3.5 minutes, then ~900 at about one per second for 14 minutes.
  Those are the hosted SwiftUI suites queued on the main actor (`TodayTwoUpTileTests`, `SleepModesHostedTests`, the
  Nocturne hosted/AX suites, `RyftTabBar`, `RulerLabelLinesTests`, …). The PR `Unit` step, with parallel clones, takes the same ~19 minutes.
- The UI half: 23 suites and 103 tests, serial on one simulator. `FocusedSessionUITests` takes ~11 min (23 tests),
  `AddActivityUITests` 2:50, `LaunchSequenceUITests` 2:36 and `ImportUITests` 2:06. The estimated total is ~34 min.
- Retries: none. `Full` has no `maximumTestRepetitions`; "Iteration 1 of 3" is `UISmoke` on PRs.

## Decision
Split Full into two steps with their own budgets, unit+performance 30 and UI 45. The UI step also runs after a red unit half.
The job gets 90 minutes on schedule/dispatch and keeps 75 for PRs and main (the sum of the steps plus ~8 minutes of setup).
- Parallel UI clones were not chosen. It's the same loaded Mac, and timing-based UI tests get worse; it needs its own proof runs.
- Parallel unit clones would not help either: the PR `Unit` step already uses them and takes as long.
- Dropping UI tests from the nightly was not chosen: it is the only place the non-smoke UI tests run.

## Found on the way (not fixed here)
1. `LaunchSequenceUITests.testATapSkipsIt` has failed in every nightly since #114 (11-17). From 11-22 on it fails the same way
   each time: `pairs: []`, so in 9 launches with `-RyftLaunchSequence play` no check ever saw `launch.sequence`.
   - "Wait for idle" ends 2 s after launch. A playing 5.2 s timeline would keep the app busy longer, so the full
     sequence likely never plays on this runner.
   - Two leads: `.skipped(.lateActivation)` (first `.active` more than 5 s after init) or `.play(.reduced)` (Low Power Mode,
     Reduce Motion or VoiceOver).
   - Not proven: a local run needs an idle Mac, and `pmset` was refused.
   - Owner: debugger.
2. The unit suite grew from 34 s to 18 minutes in three weeks, the same in PRs. Making the hosted tests stop queueing on the
   main actor would save ~15 minutes on every PR and every night. Owners: test-engineer + performance-profiler.
