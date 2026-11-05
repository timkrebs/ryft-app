# The focused session screen: UI test plan

The brief asks for "the UI test plan" to be updated. The repo keeps no plan document, only `TestPlans/*.xctestplan`, so it's here.

## Where the tests run

| Plan | Runs | Holds |
| --- | --- | --- |
| `UISmoke` | every PR and `main` | the four tests below, and `JumpToNextUITests` |
| `Full` | nightly, manual | every test of `FocusedSessionUITests`, and `JumpToNextUITests` |

## Why not the whole class

CI's UI smoke step has 15 minutes and took 483 s on `main` on 2026-11-05. `FocusedSessionUITests` takes about 630 s alone, so the step would run out. These four take about 165 s together. Each carries one thing, listed below; none of them carries the whole screen.

| Test | Carries |
| --- | --- |
| `testAWholeSessionWithOnlyCheckTapsEndsOnFinish` | Upper A from start to Finish with only ✓ taps and the pill, and the strip's tiles |
| `testTheRestPillRunsSkipsAndStartsARest` | the pill's three states and its sheet |
| `testWithTheFlagOffTheSessionIsTheList` | flag off is List, with its rest bar and no pill, strip or column button |
| `testTheColumnHeaderCyclesAndTheRowsFollow` | the header button, the rows and the last-time card following it |

`JumpToNextUITests` stays in `UISmoke`: it is the only end-to-end test of List's jump, and with the flag off List is what every user runs. The flag-off test above covers List's rest bar.

## Run it locally

Use your own simulator and derived data:

```sh
xcodebuild test -scheme Ryft -testPlan UISmoke -destination "id=<udid>" -derivedDataPath <dd> \
  -parallel-testing-enabled NO -collect-test-diagnostics never
```

`make focused-shots` writes the renders for the design note.

## A UI run after Unit on one simulator

`HostedWindow` leaves the automation setting on. T4's review note asked it to restore the earlier value, but that value reads false on a fresh simulator, so restoring is the same as switching it off.

| `HostedWindow` after its last window | Unit | erase, full Unit, then UI tests |
| --- | --- | --- |
| Switches it off (`main`) | serial | AX failure in 1 of 1 |
| Restores the earlier value | serial | AX failure in 2 of 4 |
| Leaves it on | serial | no AX failure in 6 of 6: 3 runs of one test, 3 of all of `UISmoke` |

Each row is read back from the commands that ran: every Unit run here was serial (`-parallel-testing-enabled NO`). The first `UISmoke` run in the last row stopped at my 580 s limit, after a failure of my own assertion, with no AX failure up to there. `kAXErrorAPIDisabled` itself comes from T4 and isn't counted here. The error reproduced here was "Timed out waiting for AX loaded notification", taken to be the same class.

The failure comes and goes and these counts are few, so the cure is inferred from them, not shown. If it comes back, shut down, erase and boot the simulator.

This probably does nothing on CI. `TestPlans/Unit` runs in parallel there, so the hosted tests run in simulator clones, and the setting likely never reaches the simulator `UISmoke` uses. That is reasoning from the plan, not a measurement. It helps a local serial run followed by a UI run on one simulator.

## What each level reaches

- `testTheOptionsMenuKeepsTheDesignsOrder` chooses Plate calculator, in `Full` only. The title opening history and the menu listing plates are in `FocusedPolishHostedTests`, in `Unit`.

## What no test covers

- Tile selection during the run: nothing taps a tile mid-session and checks a set on the page it opened.
- Superset with next, from the `…` menu.
- The offline banner in the app. Renders and previews only.
- VoiceOver through a set row. The hand list is `voiceover-checklist.md`.

Device and iOS 17 runs are conditions for the flag (L15).
