# OrbitGauge PR 3: launch cost on `feat/orbit-assemble` (phase 2) against `main`

**Simulator only** (iPhone 17 Pro, iOS 27.0, Release app, demo mode, Debug XCUI runner), same harness and
method as `perf-baseline.md`. Branch head `f53107f`, baseline `main` @ `c8dcf2a`. Harness: `$SCRATCH/perf/`
(`run.sh <worktree> <dd> <label> 15`, unchanged from the baseline run).

## Verdict: no regression
Threshold: a regression is main-thread busy time in the 2 s after `main()` more than 15 % above the baseline
median (854 ms, i.e. > 982 ms) in the median, or any new frame from the entrance above 10 ms in total on the main
thread, or a growth of a baseline top frame beyond its baseline range. None applies.

## Table (n = 15 XCUI, n = 12 launch metric, n = 6 profiler per side)
| Measure | `main` median (range) | branch median (range) |
|---|---|---|
| Main-thread busy, 2 s after `main()` (ms) | 854 (830 to 1033) | **842 (810 to 961)** |
| Busy before the thread settles (ms) | 707 (636 to 867) | 668 (612 to 783) |
| Settle point after `main()` (ms) | 800 (700 to 900) | 750 (700 to 900) |
| `swift_conformsToProtocolMaybeInstantiateSuperclasses`, leaf (ms) | 327 (284 to 431) | 299 (275 to 373) |
| `ViewGraphRootValueUpdater.render`, inclusive (ms) | 311 (293 to 375) | 323 (301 to 365) |
| `AG::Graph::UpdateStack::update`, inclusive (ms) | 353 (333 to 440) | 363 (350 to 409) |
| Main-thread time in frames named `Orbit*` (ms) | 1 to 2 | 1 to 3 |
| XCUI `launch()` returns (ms) | 4568 (p90 5298) | 4103 (p90 4208) |
| XCUI gauge exists (ms) | 5725 (p90 6582) | 5259 (p90 5367) |
| XCUI readiness number readable (ms) | 5766 (p90 6697) | 5298 (p90 5404) |
| `ApplicationFirstFramePresentationResponsive` (s) | 3.453 (p90 3.565) | 3.215 (p90 3.645) |

The XCUI intervals did **not** grow by the animation length; the branch reads lower, but the Mac was quieter
(baseline sd about 400 ms, branch sd about 80 ms), so read them as "no change", not as a speed-up.
The gauge-to-number gap is still about 40 ms.

## The entrance on the main thread
- New frames from the entrance (`OrbitEntranceStage.body`, `.choreography`, `OrbitGaugeGeometry.Orbit.fraction`,
  `OrbitGaugeMarks.body`): 1 to 3 ms in total over the 2 s window, in every run; no `TimelineView`,
  `KeyframeAnimator` or Shape-path frame is in the top lists. The baseline has 1 to 2 ms in `OrbitGauge.body`.
- The entrance plays at about +0.4 s to +1.3 s after `main()`, right after the first render. The 100 ms buckets in
  that range sit at 5 to 18 ms busy (baseline in the same range: 6 to 21 ms), i.e. at most about 1 to 2 ms per
  frame at 60 fps. The entrance is view state plus the SwiftUI render, and costs nothing measurable on the main
  thread. (Profiler resolution is 1 ms; per-frame cost cannot be isolated more finely, and the simulator has no
  hitch instrument.)
- Dropped frames and hitches were **not measured**: `Animation Hitches` does not run on the simulator. If a hitch
  statement is wanted for the PR, an on-device trace of one cold launch is needed.

## Reduce Motion
Not measured. Setting `ReduceMotionEnabled` through `simctl spawn defaults write` did not take effect (it reads back
0), so the 4 profiler runs I took (busy 971 to 998 ms in three, 836 ms in one, under a load average of about 90)
are not Reduce Motion data. The cross-fade branch needs the setting turned on in the Simulator's
Settings > Accessibility > Motion, or a device.

## Noise
- Load average at the start: 13.6 (baseline: 160 to 190); about 90 during the Reduce Motion attempt. No CI job was in progress.
- Two read-only reviewers were running. Time Profiler adds overhead and shifts pre-`main` (about 1.6 s here too).
- With n = 6 per side the profiler medians differ by under 2 %, well inside the range; the branch's lower numbers
  are noise.
