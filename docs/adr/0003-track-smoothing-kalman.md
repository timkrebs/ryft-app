# 0003 — GPS tracks are smoothed by a constant-velocity Kalman filter, not a moving window

- Status: proposed (2026-10-22, My Day and activities, `docs/work/2026-10-22-my-day-activities/design.md` §3.3)
- Amended: 2026-10-23, amendment 1 (A3a): distance from the filter's speed; a still-phone guard; the re-init counts
  both gates
- Deciders: ios-lead, on ios-architect's proposal; sync-engineer implements (A3)
- Applies to: `Ryft/Activities/Recording/TrackPipeline.swift`, `KalmanTrack.swift`, `Geodesy.swift`,
  `Ryft/Activities/Sport.swift` (per-sport parameters)

## Context

RYFT records runs, rides and hikes with the phone's GPS. Distance, live pace, km splits and auto-pause all come from
the fixes.

**What the fixes are like:**
- **Rate and noise.** About 1 Hz, with a reported horizontal accuracy of 3–30 m. Accuracy is worse under tree
  canopy and between buildings.
- **Raw sums overestimate.** Summing the distances between raw fixes adds the noise as length: several percent at
  jogging speed, and tens of metres an hour for a phone lying still.
- **Outliers can look good.** Multipath in cities produces jumps of 50 m or more whose *reported* accuracy is good.
  A gate on accuracy alone doesn't catch them.
- **Tight turns.** Trails have switchbacks with radii of 10–20 m, so heavy smoothing cuts corners and *under*states
  the distance.

**What we need from the smoothing:**
- live values on the recording screen: it must be **causal**, with no look-ahead;
- velocity for auto-pause and pace;
- **±2 %** of ground truth on the brief's fixture tracks: a 5 km road run, a trail with switchbacks and bad fixes,
  and a stationary phone;
- cheap enough for the ≤ 8 %/h battery target;
- deterministic in unit tests.

## Decision

1. **Hard gates first:**
   - a fix is dropped when its accuracy is invalid or above 25 m, when it's stale (older than 10 s) or out of order;
   - it's dropped when its implied speed from the last *filtered* position (minus both accuracies) exceeds the sport's
     `maxSpeed`.
2. **A constant-velocity Kalman filter, two states per axis (position, velocity):**
   - **Frame.** East and north metres in a local tangent plane: WGS84 meridional and prime-vertical radii at the
     anchor latitude, re-anchored every 5 km. The anchor lives in memory only. It's never part of a checkpoint
     (ADR 0005), so a resume re-initialises the filter at its first fix.
   - **Measurement variance** is `max(horizontalAccuracy, 3 m)²`, so every fix is weighted by what Core Location
     says about it.
   - **Process noise** is white acceleration with σa per sport: 1.0 for walking and hiking, 1.5 for running, 3.0 for
     cycling, 5.0 for snow sports.
   - **Innovation gate** at 3.5σ. Three rejections in a row re-initialise the filter at the measurement (a real jump,
     a tunnel exit). Δt over 15 s resets the velocity variance.
3. **Distance and pace:**
   - **Distance** is the sum of geodesic steps between consecutive *filtered* positions, counted only while
     recording and while the filter's speed is ≥ 0.3 m/s. Gaps over 10 s are bridged by the straight line when the
     implied speed is plausible.
   - **Pace** is a rolling 30 s of moving time.
   - **Splits** interpolate the 1000 m crossing between filtered points.
   - **Auto-pause** uses the filter's speed with hysteresis.
4. **The pipeline is a pure value type** (`TrackPipeline.ingest(_:) -> [PipelineEvent]`), owned by the
   `ActivityRecorder` actor. Unit tests drive it with seeded synthetic fixture tracks of known length
   (`scripts/make-tracks.py`), without an actor or a clock.
5. **The distance shown live is the distance saved.** Nothing re-smooths after Finish.

## Consequences

**Good:**
- **Causal and accuracy-weighted.** A 30 m fix moves the estimate a little; a 4 m fix moves it a lot.
- **Outliers.** The innovation gate rejects multipath jumps that the accuracy gate lets through.
- **One estimate for everything.** The filter's velocity serves auto-pause, stationary detection and pace, so
  there's no second speed estimate.
- **Cheap.** A few dozen floating-point operations per fix; no allocation per fix.
- **Testable.** Pure, deterministic, and every parameter sits in the sport catalogue.

**Costs:**
- **Tuning.** σa per sport needs device validation (D1). Too low cuts switchback corners; too high passes jitter.
- **Corner lag.** A constant-velocity model lags for one or two fixes on a hairpin when the fixes are poor.
- **Horizontal only.** Distance ignores slope, as GPS watches do. Steep trails read a little shorter than their
  slope length.

**Follow-ups:**
- Tune σa and the gates with D1's real run.
- Add one real track from a public course as a regression fixture.
- Revisit Core Location's own `speed` as a filter input if D1 shows lag.

**Rejected alternatives:**
- **A moving average or a centred window.**
  - It lags (a centred one needs look-ahead), so live values trail.
  - It cuts corners in proportion to the window.
  - It weights a 30 m fix like a 4 m one, and an outlier pulls the mean.
- **A moving median.** Better with outliers, but it still lags, quantises the path into steps and ignores accuracy.
- **Raw fixes behind an accuracy gate only.** It overestimates by several percent at jogging speed, and a stationary
  phone drifts.
- **A Rauch–Tung–Striebel smoother at Finish.** It's more accurate after the fact, but it changes the number the user
  watched, and the splits with it. It may come later as a separately labelled corrected distance.
- **Map matching.** No offline map data, trails are often unmapped, and MapKit offers no matching API.

## Amendment 1 (2026-10-23, A3a): distance from the filter's speed; a still-phone guard; the re-init counts both gates

- Status: proposed by ios-architect after A3a (`activities: track pipeline`); the lead confirms.
- Replaces the first bullet of decision 3. Decision 2's re-init rule stands as written and is spelled out below.
- Numbers marked *[fix commit]* come from the implementer's fix commit on A3a; fill them in when it lands.

### What A3a measured

- **The evidence uses drifting noise, not white noise.** `make-tracks.py` draws each fix's error as Gauss–Markov
  processes that wander (design §11.2): τ up to 600 s, and about 300 s for a phone lying still.
  - **Why drifting.** Receivers smooth their output (Doppler-aided, over about 30 s), so consecutive fixes share most
    of their error. White noise of σ = accuracy / 2 at 1 Hz would make every 1 s step mostly noise, which no phone
    reports. It would test the filter against a receiver that doesn't exist.
  - **What white noise does.** It makes position steps read +17 to +125 % long and the velocity +2 to +12 % (A3a
    review).
  - **What drifting noise hides.** A slow drift looks like slow motion. That's the hard case for walking speeds and
    for a still phone, so D1 measures both on a device.
- **Position steps read long under canopy.** On `trail-switchbacks` over 20 seeds, summing the steps between filtered
  positions read +2.7 % on average, outside ±2 % on 15 of the 20. Two causes:
  - measurement jitter reaches the position through the filter's position gain;
  - a lagging estimate overshoots a hairpin and comes back, and a position sum counts both ways.
- **The filter's speed doesn't.** Integrating its ground speed: trail −0.33 % (committed seed; sweep −0.91…+2.10 %),
  road +0.31 %.
- **A second probe** (ios-architect): 100 more tracks from `make-tracks.py`'s noise model, 20 seeds per row, run
  through A3a's code in a scratch harness that isn't committed.

| Track | Position steps | Ground speed |
| --- | --- | --- |
| Hike under canopy, 1.2 m/s, a 5-min stop, auto-pause off | +2.84 % (17 of 20 outside ±2 %) | +0.73 % (1 of 20) |
| Urban walk, 1.4 m/s, three 60 s stops, auto-pause off | +2.15 % (12 of 20) | +0.75 % (0 of 20) |
| Jog under canopy, 2.2 m/s | +1.58 % (5 of 20) | +0.83 % (1 of 20) |
| Open road, 3 m/s, one stop | +0.35 % | +0.20 % |
| Phone still for 10 min, canopy-level accuracy, never flagged stationary, auto-pause off; σa 1.0 / 1.5 | 7.8 / 18.6 m | 4.7 / 9.3 m (max 10.3 / 22.9) |
| Committed `stationary`, auto-pause off, σa 1.5 | 16.8 m | 2.6 m |

- **A still phone without Core Location's flag drifts into distance.**
  - **In the review:** under drifting noise at ±6–25 m, a still phone with auto-pause off accrued 15–228 m in
    10 min, and more with shorter correlation times.
  - **In the probe:** the slower drift (τ 300 s) gave 4.7–9.3 m on average.
  - Either way the 0.3 m/s floor alone isn't a guard. The fixtures never set `isStationary`, which is the guard on a
    real phone.
- **A coarse first fix inflates the restart window.** Position steps right after a (re)start added up to +42 m in the
  review when the first fixes were coarse.

### Decision

- **Distance** is the trapezoid of the filter's ground speed between consecutive accepted fixes, counted while
  recording.
- **A still phone adds nothing, in two layers** (also with auto-pause off, the walking and hiking default):
  1. **`CLLocationUpdate.isStationary` first.** A fix Core Location flags adds no distance. This is the guard on a
     real phone, and the fixtures now model it.
  2. **A dead-band as the backstop**, for a phone the flag misses: no distance while the filtered ground speed is
     below *[fix commit: threshold and form]*. Today's 0.3 m/s floor on the mean of two speeds is its first form.
     Measured on the widened still fixture without the flag: *[fix commit]* m in 10 min.
- **Position steps for 10 s** replace the speed:
  - after the filter initialises or re-initialises;
  - after a velocity reset (Δt > 15 s);
  - after an auto-resume.

  They recover the lag of a converging velocity, which integrating the velocity would lose: a standing or flying
  start, a tunnel exit.
  - **Only once the position is good.** Within the window a step uses positions only after `positionSigma` is about
    8 m or less (*[fix commit: the exact value, and what the steps before it use]*). A coarse first fix added up to
    +42 m in the review.
- **Gaps** over 10 s are bridged by the straight line, as before.
- **`Tuning.distanceFromVelocity = false`** keeps the old sum for D1 only. After D1 the losing branch and the flag are
  deleted.
- **Re-init (decision 2, spelled out).** Three rejections in a row **by the speed gate or the innovation gate**
  re-initialise the filter at the third fix. Accuracy, stale and out-of-order rejections neither count nor break the
  run. A3a counted innovation rejections only, which costs distance on sustained multipath (risk 5), so A3a changes
  back before it merges.
- **Unchanged:** live = saved, splits on the recorded distance, the filter, the other gates, σa per sport.

### Why it works

- **Less noise.** The velocity state takes far less of the measurement noise than the position (its gain is smaller),
  and a speed never doubles back at a hairpin.
- **Lag cancels over a stop.** A linear filter's velocity lags at an acceleration and gives the lag back at the next
  deceleration, so over a go–stop cycle the integral loses nothing. It loses distance only where the integral is cut:
  at a (re)start, which the position steps cover, and below the 0.3 m/s floor.

### Risks

1. **Low-speed bias.** The length of a noisy velocity is biased upward: at rest its mean is about 1.25 σv, and a
   drifting error adds a real-looking speed on top.
   - The guards above handle it: the flag on a real phone, the dead-band where the flag fails.
   - What's left with the dead-band is *[fix commit]*. It matters for walking and hiking, whose auto-pause is off by
     default.
   - The dead-band's cost is real slow motion below it, such as a slow scramble, a queue or a crowded start. D1's
     walk measures it.
2. **Stops.** The decaying velocity keeps adding until it falls under the floor: about 4–5 m per 60 s stop at
   1.4 m/s, where position steps added 2–3 m. Totals stay better.
3. **Auto-resume may count the lag twice.**
   - Why: the deceleration tail is counted during the 10 s auto-pause confirmation, and the position steps after the
     auto-resume recover the start lag again.
   - Without those position steps: the urban walk with auto-pause on reads +0.54 % instead of +1.08 %, and the road
     +0.15 % instead of +0.21 %.
   - But then a noiseless instant start reads 3–4 m short per stop.

   So it's about ±3 m per auto-pause either way. D1 decides.
4. **Hairpins.** The speed lags the turn and reads slightly short (trail −0.33 %).
5. **Sustained multipath**, with either distance method: it comes from the gates.
   - **The mechanism.** With only innovation rejections counting, the speed gate ages open as Δt grows. On a run, a
     60 m offset with a falsely good 10 m accuracy that lasts 10 s or more is accepted after about 10 rejections, as
     a bridged gap. Its large innovation kicks the velocity.
   - **Measured:** +79 to +92 m per episode (+94 m with position steps).
   - **Counting both gates:** −18 m (the three rejected seconds at each edge), and no fixture changes.
   - **Rides stay open.** With σa 3.0 the innovation gate opens after two rejections, so an offset of 10 s or more
     reads about +70 m per episode under either rule. A3b adds a sustained-multipath ride fixture and settles the
     rule before D1.
6. **Correlated error.** To any filter, a wandering GPS error looks like motion. The fixtures model it
   (Gauss–Markov, 30–600 s), but only D1 shows real receivers.
7. **Core Location's own speed** (`fix.speed`, usually Doppler-derived) isn't used. If D1 shows it beats the filter's
   speed, the follow-up feeds it into the filter as a velocity measurement. That needs `speedAccuracy` and `course`
   in `LocationFix`, a frozen type, so it goes through the lead. It never becomes a second distance.

### What D1 compares

- **Shadow totals, with no coordinate on disk.** In Debug and TestFlight builds the pipeline keeps three more running
  sums over the same fixes and gates. They're numbers in `PipelineDiagnostics` and Copy diagnostics, and they're
  deleted with the losing methods after D1:
  - (a) is the shipped total (ground speed);
  - (b) filtered-position steps, the old method;
  - (c) the trapezoid of Core Location's `speed` where it's ≥ 0;
  - (d) ground speed without the position steps after an auto-resume.
- **Five runs, each against a reference** (a measured course, such as lane 1 of a 400 m track or a certified 5 km, and
  the tracker's distance):
  1. An open road, 5 km, with at least 10 stops and auto-pause on: totals (a)–(d), and split times against the
     tracker.
  2. A forest trail with switchbacks: totals.
  3. **Slow speed.** A walk at about 1.4 m/s over a measured 2 km, with three 2-minute stops at marked points,
     auto-pause off: the total, and the distance added during each stop.
  4. The phone on a bench for 10 min, then in a pocket while standing for 10 min, auto-pause off: the distance
     (target < 20 m each), how many fixes Core Location flagged `isStationary`, and what the dead-band caught.
  5. A city ride: totals, re-initialisations, and fixes flagged `isStationary` while the filter said moving.
- **The rule.** Keep (a), unless one other total is closer to the reference by more than 0.5 % on at least four of the
  five runs.

### Consequences

- **New tests** (design §11.1):
  - the stationary fixture with auto-pause off, with and without the flag;
  - a coarse first fix doesn't inflate the restart window;
  - a sustained offset on a run.

  `flyingStartLosesNothing` stays.
- **The fixture noise model** is drifting Gauss–Markov noise (design §11.2), not white noise.
- **Unchanged:** the ±2 % fixture bounds and every other rule of this ADR.
