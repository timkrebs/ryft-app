---
name: review-checks-numeric-pipelines
description: RYFT review checks for pure numeric pipelines (GPS track/Kalman A3a) — fixture noise model vs design, generator determinism across Python, NaN-trapping redaction, wall-clock cost tests, init-error leaks; plus a fast swiftc probe harness
metadata:
  type: feedback
---

Found in the A3a track-pipeline review (2026-10-23); the suite (86 tests) was green:
- **Fixture noise model decides the acceptance criteria.** `make-tracks.py` used correlated Gauss–Markov error (τ up to
  300 s when still) instead of design §11.2's white σ = acc/2, and the 10-min "stationary" fixture only reached 5–12 m
  accuracy (spec 5–30). Re-run the claims under the design's literal model and a middle one (τ 30–60 s): a still phone
  then accrues 100s of metres with auto-pause off. Check which tests run with the profile's auto-pause *on* while the
  claim is about *off*.
- **Generator determinism across Python versions:** Python ≥ 3.12 `sum()` uses Neumaier summation, so an unrounded
  float in the output (`distance_m: path.length`) differs on 3.9/3.11 (macOS `/usr/bin/python3` is 3.9). Run
  `--check` with `/usr/bin/python3` and `/opt/homebrew/bin/python3.11`; check it's wired into `make lint`.
- **Redacted `description`s with `Int(double)`** trap on NaN/inf (exit 133) — the logging-safe path must not crash.
- **Wall-clock "cost is linear" ratio tests** in the Unit plan (parallel, random order): under bursty load 4/20 runs
  broke a 24x bound (idle 8.5x). Repo convention: timing tests live in `PerformanceTests` (Full plan only, docs/CI.md).
- **Position steps after a filter (re)init** count the init fix's error as distance (+20 m for a 20 m-off first fix);
  the first fix after a restore is the realistic trigger.
- **Pre-start state leaking into Start** (`stepFrom` kept across `start(at:)` while `resume` clears it) and
  "newest time seen" updated by *rejected* inputs (one future-dated invalid fix → everything stale).

Re-review of the fixes (b059151, 2026-10-23) — what the fixes themselves broke or missed:
- **Settle/hold windows with a cap** ("wait up to 30 s for 4 fixes") silently drop everything when the cap fires with
  too few samples: first fix + 35 s dropout lost 105 m that the gap rule would have bridged. Probe dropouts of
  cap-5 s and cap+5 s right after every (re)start path.
- **Counting more rejections toward a re-init** fixes sustained ghosts but costs ~18-27 m per 3-6 s ghost and drops a
  legit over-max segment the old aged-open gate used to bridge (2-min descent at 33 m/s: 7559 -> 3599 m). Always run
  old vs new on the same probes (keep the old harness dir) and report both directions.
- **"Standing start" tests that start before any fix** skip the real flow (filter warmed in pre-start): -7 m at
  3 m/s, -20 m at 9 m/s. Ask for a warm-up in the test.
- **Test teeth via tuning knobs:** re-run a new test's scenario with the knob that implements the fix turned off
  (settleWindow = 0, maxDeadBand = floor). A bound that still passes (4.1 m < 5 m) proves nothing.
- Mutating control calls that do work internally (`pause` settling a window) but return Void drop the events.

A3a.2 speed-gate guard review (4ef4c6e, 2026-10-26):
- **Seeded acceptance tests with 3-5 noise seeds pass by seed choice.** Rerun 20-30 seeds with the test's *own*
  helpers: copy `GuardTrack.swift` / `SyntheticTrack` / `SeededGenerator` into the scratch harness minus
  `@testable import Ryft`. `fastButOnFootIsNotTooFast` failed both bounds on seeds 9 and 28.
- **A per-step limit with no hysteresis** (refuse each step above `maxSpeed`, event only after 3 s) loses distance
  silently near the limit. Filter velocity noise is absolute (~0.5 m/s), so a relative margin fails slow sports
  (walk limit 6 m/s flaps at 90 %). What I measured as working: hold refusals until the state confirms, enter at
  max(5 %, 0.6 m/s) over the limit.
- **Probe drifting (sliding) multipath, not just hopping offsets:** gates accept a slide, so the filter's speed
  includes the ghost's motion, which gives false "too fast" for walkers. Core Location's Doppler `speed` is the
  independent check.
- **Windows without an anchor:** a rule that fills spans "from the last settled point" misses re-inits that start
  inside an unrelated open window (Start, velocity reset): -24...-42 m.
- Re-review (ee974c0): entry hysteresis on a limit moves the counted boundary (the train +8 m kinematically).
  "Hold steps above the limit, confirm above the entry speed" keeps the old boundary but needs an age cap on the held
  buffer. A sensor veto (Doppler) fails open when the sensor is missing: probe 30-70 % random availability and gaps
  of 5 fixes, not just 0 % and 100 %.
- c33883f (sticky Doppler, veto only on entry): check (a) that a disturbance starting *inside* an episode can't
  extend it (it did, up to 20 s for a walker), (b) holdover state across mode-change edges (a pause into a car: the
  held slow reading vetoed 3 s longer, +27 m), (c) gaps longer than the holdover (10-fix gaps fail open again). Build
  in my own `git worktree add --detach <scratch>/rv-…` (copy `Config/*.xcconfig`), never in the shared worktree.
- Synthesized Codable doesn't apply property defaults for missing keys (keyNotFound). Check "new fields decode with
  a default" claims.

Technique: copy the pure sources (`git archive <sha> | tar -x`) into *my own* scratch dir and compile with a
`main.swift` probe via `swiftc -O` (seconds, no simulator); `setvbuf(stdout, nil, _IONBF, 0)` so a trap doesn't eat
output. Never write into another agent's scratch dir (an implementer's `harness/` existed with the same name).

**Why:** none of these showed in the PR's own green run. **How to apply:** any PR with a numeric core + synthetic
fixtures (tracks, scores, HR). See [[review-checks-wire-drafts-and-flags]].
