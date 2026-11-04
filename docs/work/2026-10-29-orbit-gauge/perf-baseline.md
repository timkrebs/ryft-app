# OrbitGauge PR 3: launch baseline on `main` (phase 1)

All numbers are from the **iOS Simulator**, not a device. Use them only to compare `main` with the PR branch,
measured the same way on the same Mac. They say nothing about absolute launch time on an iPhone.

## Setup
- Commit: `main` @ `c8dcf2a` (detached worktree), flag state as shipped, no overrides.
- Host: MacBook, Apple M4 Pro (12 cores), 48 GB, macOS 27.2, Xcode 27.1 (27A9275).
- Simulator: fresh "iPhone 17 Pro" on iOS 27.0 (24A434), created for the run and deleted afterwards.
- App configuration: **Release** (`-configuration Release`), installed on the simulator. Demo mode works in Release
  (`-demoMode YES`), so no server and no HealthKit.
- The XCUI runner is a **Debug** build. It runs out of process and only drives the app by bundle id. Reason: the
  unit-test target does not compile in Release (it uses `#if DEBUG` seams), so `build-for-testing` cannot be Release
  for the whole scheme. The xctestrun was patched to install the Release `Ryft.app`.
- Launch arguments: `-demoMode YES -RyftTab today -appearance dark -coachMarks.today.done YES -AppleLanguages (en) -AppleLocale en_US`.
  Default scenario (scored Today), so the readiness number is on screen.
- CI: `gh run list --status in_progress` was empty during the measured runs (an earlier run of the `main` push, #78,
  was in progress while I was building).

## Method
Harness (outside the worktrees): `scratchpad/perf/` (see "Rerun on the branch").
1. **XCUI cold launches** (`LaunchPerfUITests.testColdLaunchToGauge`): 1 warm-up (discarded) + 15 measured, each
   `launch()` of a freshly terminated app. Wall clock from just before `app.launch()` to
   - `launchReturn`: `launch()` returning (XCUI waits for the app to be idle),
   - `gauge`: `today.readinessGauge` exists,
   - `value`: the gauge's accessibility value contains a digit (the readiness number is readable).
2. **`XCTApplicationLaunchMetric`** (`testApplicationLaunchMetric`, 12 iterations):
   `ApplicationFirstFramePresentationResponsive`, Apple's process-launch to first-frame metric.
3. **Time Profiler** (`xctrace record --template 'Time Profiler' --launch`, 6 s, 6 cold launches), main thread
   only, window = 2 s from the first sample inside `main [Ryft]`; `analyze_tp.py` prints the busy time, top leaf
   and inclusive frames and the busy ms per 100 ms bucket.

## Numbers (simulator, Release, `main`)

### Wall clock from `app.launch()` (n = 15, ms)
| Interval | median | p90 | min | max | sd |
|---|---|---|---|---|---|
| `launch()` returns | 4568 | 5298 | 4181 | 5809 | 398 |
| gauge exists | 5725 | 6582 | 5337 | 7174 | 453 |
| readiness number readable | 5766 | 6697 | 5389 | 7323 | 478 |

The gauge-to-number gap is ~40 ms at the median. These intervals include XCUI's own overhead (launch through
`testmanagerd`, waiting for idle, an accessibility snapshot per poll, ~1 s between `launch()` and the first
successful query). They are good for a before/after, not as an absolute.

### `ApplicationFirstFramePresentationResponsive` (n = 12, s)
median 3.453, p90 3.565, min 3.238, max 3.615 (relative sd 3.4 %).

### Main thread, Time Profiler (n = 6)
Main-thread busy time in the 2 s after `main()`: 861, 830, 844, 873, 847, 1033 ms, **median 854 ms**.
- Busy in the first ~0.7-0.9 s after `main()` (about 90 to 100 % of every 100 ms bucket), then the thread
  settles: ~10 ms per 100 ms. Settle point: 800, 700, 700, 800, 800, 900 ms after `main()`.
  Cause: the first SwiftUI render of Today. Later blips of 50 to 70 ms in a bucket at ~1.5 to 1.7 s are the first
  data refresh.
- Top frames in that window (typical run):
  - `swift_conformsToProtocolMaybeInstantiateSuperclasses` (libswiftCore): 284 to 431 ms leaf. First-use protocol
    conformance lookup during SwiftUI view-graph updates. It is the single biggest item, and a one-time cost per process.
  - Inclusive: `App.main` > `UIApplicationMain` > `CA::Transaction::commit` > `ViewGraphRootValueUpdater.render`
    (≈ 310 ms) > `AG::Graph::UpdateStack::update` (≈ 330 ms).
  - Small leaves (< 20 ms each): `__open`, `objc_msgSend`, `memmove`, malloc.
- Pre-`main()` (dyld in the simulator, first sample to `main`): ~1.6 s in five runs, 3.1 s in one. This is
  simulator dyld under the profiler. It is not representative of a device and not touched by the PR.
- **Hitches: not available.** `Animation Hitches` fails on the simulator ("Hitches is not supported on this
  platform"), and the `App Launch` template recorded no life-cycle intervals. The hitch count needs a device trace.
  Phase 2 should ask the user for one on-device 'Animation Hitches' trace of a cold launch if the entrance is to be
  signed off on hitches.

## What to compare in phase 2
- Same three XCUI intervals and the launch metric: expect `launch()` returning and `gauge` to move **later** by up
  to the animation length, because XCUI waits for animations to idle. That reading is an artefact of the harness.
  The real question is the Time Profiler: main-thread busy in the 2 s after `main()` (baseline median 854 ms,
  range 830 to 1033) and whether `swift_conformsToProtocolMaybeInstantiateSuperclasses` or `render` grows.
  `value` minus `gauge` stays ~40 ms if the number is readable while the gauge assembles.
- A change smaller than the noise (~±10 % on the XCUI intervals, sd about 400 ms) is not a regression.

## Noise
- Simulator on a shared Mac: system daemons (PerfPowerServices, spotlight, ANECompilerService at ~100 % CPU each) and a
  load average of 160 to 190 (mostly thread count) during the runs. Outliers: runs 10 and 11 of 15 (+1 to +1.5 s).
- The self-hosted runner is this Mac; no job was running during the measurement.
- Time Profiler sampling at 1 ms adds overhead and shifts pre-`main` considerably; compare Time Profiler runs only with each other.
- XCUI `launch()` waits for idle, so it measures "launch until the UI is quiet", not first frame.
- The first launch after install (warm-up) was ~1 s slower and is excluded.

## Rerun on the branch (unchanged harness)
```sh
P=$SCRATCH
$P/perf/run.sh <branch-worktree> $P/dd-perf-branch branch 15     # creates + deletes its own simulator
```
`run.sh` copies `perf/LaunchPerfUITests.swift` into `<worktree>/RyftUITests/` only while building, then removes it
(the `RyftUITests` folder is synchronized, so no project edit). For this baseline the steps were, by hand:
`xcodebuild build -scheme Ryft -configuration Release`, `xcodebuild build-for-testing -scheme Ryft -configuration Debug`,
xctestrun patched to the Release app, `TEST_RUNNER_PERF_N=15 xcodebuild test-without-building -xctestrun … -only-testing:RyftUITests/LaunchPerfUITests`,
then `perf/profile.sh <udid> base 6`. Raw logs and traces: `scratchpad/perf/run1.log`, `base-*.trace`, `base-*.txt`.
