# 0003 — GPS tracks are smoothed by a constant-velocity Kalman filter, not a moving window

- Status: proposed (2026-10-22, My Day and activities, `docs/work/2026-10-22-my-day-activities/design.md` §3.3)
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
