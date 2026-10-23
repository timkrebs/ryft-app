# 0003 — GPS tracks are smoothed by a constant-velocity Kalman filter, not a moving window

- Status: proposed (2026-10-22, My Day and activities, `docs/work/2026-10-22-my-day-activities/design.md` §3.3)
- Amended: 2026-10-23, amendment 1 (A3a): distance from the filter's speed; a still-phone guard; a settle window;
  the re-init counts both gates
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

## Amendment 1 (2026-10-23, A3a): distance from the filter's speed; a still-phone guard; a settle window; the re-init counts both gates

- Status: proposed by ios-architect after A3a (`activities: track pipeline`), reconciled with what A3a built
  (`b059151`); the lead confirms.
- Replaces the first bullet of decision 3. Decision 2's re-init rule stands as written and is spelled out below.
- Numbers are A3a's own unless marked "probe" (ios-architect's scratch harness over `make-tracks.py`'s noise model, not
  committed).

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
- **The filter's speed doesn't.** As built, on the committed seeds:
  - road +0.31 % (20 seeds −0.10…+0.45 %);
  - trail −0.34 % (20 seeds −0.95…+2.04 %);
  - stationary 0.0 m.
- **The probe agrees on other tracks.** 20 seeds per row, run through A3a's first code (before the guards below):

| Track | Position steps | Ground speed |
| --- | --- | --- |
| Hike under canopy, 1.2 m/s, a 5-min stop, auto-pause off | +2.84 % (17 of 20 outside ±2 %) | +0.73 % (1 of 20) |
| Urban walk, 1.4 m/s, three 60 s stops, auto-pause off | +2.15 % (12 of 20) | +0.75 % (0 of 20) |
| Jog under canopy, 2.2 m/s | +1.58 % (5 of 20) | +0.83 % (1 of 20) |
| Open road, 3 m/s, one stop | +0.35 % | +0.20 % |

- **A still phone without Core Location's flag drifts into distance.** Under drifting noise at ±6–25 m, a still phone
  with auto-pause off accrued 15–228 m in 10 min (A3a review), and more with shorter correlation times. The 0.3 m/s
  floor alone wasn't a guard. The fixtures never set `isStationary`, which is the guard on a real phone.
- **A coarse first fix inflated the restart.** Before the settle window below:
  - a still phone whose first fix was 20 / 40 m off read +20.5 / +42.0 m;
  - at 3 m/s it read +16.9 / +34.6 m;
  - a restore whose first fix was 30 m off read +30.7 m.

  The filter's walk back from a bad first fix isn't distance.

### Decision

- **Distance** is the trapezoid of the filter's ground speed between consecutive accepted fixes, counted while
  recording.
- **A still phone adds nothing, in two layers** (also with auto-pause off, the walking and hiking default):
  1. **`CLLocationUpdate.isStationary` first.** A fix Core Location flags adds no distance. This is the guard on a
     real phone. The still fixture now flags its fixes after 15 s, as `liveUpdates` does.
  2. **A dead-band as the backstop**, for a phone the flag misses. A step counts only when the mean of the two speeds
     is at least half the sport's auto-pause threshold, clamped to 0.3–0.5 m/s:
     - run, bike and ski: 0.5 m/s;
     - trail: 0.4 m/s;
     - walk and hike: 0.3 m/s.
     - **Without the flag** (run profile, 5 seeds, worst / mean), the dead-band cut the still phone's distance:

       | Error correlation τ | Before | With the dead-band |
       | --- | --- | --- |
       | 300 s | 19.2 / 9.8 m | 4.7 / 0.9 m |
       | 120 s | 38 m | 10.4 m |
       | 60 s | 61 m | 18.1 m |
       | 30 s | 132 m | 70 m |

     - **Walk and hike keep the 0.3 m/s floor and rely on the flag.** Without it, their worst case is 10.3 m (τ 300 s)
       to 116 m (τ 30 s).
     - **Slow movers:** walk at 1.4 m/s +1.1 %, hike at 0.6 m/s +2.0 %, hike at 0.4 m/s −4.8 % (the floor bites).
     - **Why not one global value:** 0.4 m/s would cost the 0.4 m/s hike −34 %.
- **A settle window after the filter (re)starts.** After the filter initialises or re-initialises, or resets its
  velocity (Δt > 15 s), nothing accrues for 10 s (up to 30 s with fewer than 4 fixes). Then the window counts the
  shorter of two lengths:
  - **a Theil–Sen line through its raw fixes:** the median of the pairwise velocities, so one bad fix tilts nothing,
    and a flying start keeps its speed;
  - **the filtered track's length.**

  They fail in opposite directions: a coarse first fix lengthens the track as the filter walks back, and an
  acceleration (a standing start) lengthens the line. Measured: every coarse case above → 0.0 m.
  - **The cost:** the first 10 s of distance appears at the window's end, all at once.
  - **Why not a `positionSigma` gate** (this amendment's first draft: steps only once σ ≲ 8 m): under canopy the
    steady-state σ is 10–12 m, so it would never open.
- **Position steps for 10 s only after an auto-resume.** The filter is settled then. The steps recover its velocity's
  lag behind the acceleration, which integrating the velocity would lose.
- **Gaps** over 10 s are bridged by the straight line, as before.
- **`Tuning.distanceFromVelocity = false`** keeps the old sum for D1 only. After D1 the losing branch and the flag are
  deleted.
- **Re-init (decision 2, spelled out).** Three rejections in a row, **by the speed gate or the innovation gate**,
  re-initialise the filter at the third fix (and a settle window follows). Accuracy, stale and out-of-order rejections
  neither count nor break the run. Measured on a 60 m, 15 s multipath offset: +75.4 m with only innovation rejections
  counting, −18.0 m with both.
  - **Side effect:** a movement steadily faster than the sport's `maxSpeed` re-initialises every third fix and
    records 0 m (a "run" at 16 m/s: a car, a train, the wrong sport). That's intended for implausible speeds. *Lead:
    adjust this sentence if the code review finds a legitimate profile that can exceed its `maxSpeed`.*
- **Unchanged:** live = saved, splits on the recorded distance, the filter, the other gates, σa per sport.

### Why it works

- **Less noise.** The velocity state takes far less of the measurement noise than the position (its gain is smaller),
  and a speed never doubles back at a hairpin.
- **Lag cancels over a stop.** A linear filter's velocity lags at an acceleration and gives the lag back at the next
  deceleration, so over a go–stop cycle the integral loses nothing. It loses distance only where the integral is cut:
  at a (re)start, which the settle window covers, and below the dead-band.

### Risks

1. **Low-speed bias.** The length of a noisy velocity is biased upward: at rest its mean is about 1.25 σv, and a
   drifting error adds a real-looking speed on top.
   - The flag and the dead-band handle it (numbers above).
   - The dead-band's cost is real slow motion below it: a hike at 0.4 m/s reads −4.8 % at the 0.3 m/s floor. A slow
     scramble, a queue or a crowded start lose a little. D1's walk measures it.
2. **Stops.** The decaying velocity keeps adding until it falls under the dead-band. The probe measured about 4–5 m
   per 60 s stop at 1.4 m/s, where position steps added 2–3 m. Totals stay better.
3. **Auto-resume may count the lag twice.**
   - Why: the deceleration tail is counted during the 10 s auto-pause confirmation, and the position steps after the
     auto-resume recover the start lag again.
   - Without those position steps (probe): the urban walk with auto-pause on reads +0.54 % instead of +1.08 %, and the
     road +0.15 % instead of +0.21 %.
   - But then a noiseless instant start reads 3–4 m short per stop.

   So it's about ±3 m per auto-pause either way. D1 decides.
4. **Hairpins.** The speed lags the turn and reads slightly short (trail −0.34 %).
5. **Sustained multipath on rides stays open.**
   - **The mechanism.** The speed gate ages open as Δt grows; counting its rejections toward the re-init fixed runs
     (above).
   - **Rides.** With σa 3.0 the innovation gate opens after two rejections, so an offset of 10 s or more read about
     +70 m per episode under either rule (probe).
   - A3b adds a sustained-multipath ride fixture and settles the rule before D1.
6. **Correlated error.** To any filter, a wandering GPS error looks like motion. The fixtures model it (Gauss–Markov,
   30–600 s), but only D1 shows real receivers.
7. **Core Location's own speed** (`fix.speed`, usually Doppler-derived) isn't used. If D1 shows it beats the filter's
   speed, the follow-up feeds it into the filter as a velocity measurement. That needs `speedAccuracy` and `course`
   in `LocationFix`, a frozen type, so it goes through the lead. It never becomes a second distance.
8. **The settle window shows distance late.** For the first 10 s after Start, a resume after a kill or a tunnel exit,
   the distance stands still, then catches up at once. Splits crossed in the window are interpolated over it.

### What D1 compares

- **Shadow totals, with no coordinate on disk.** A3b adds them to Debug and TestFlight builds: running sums over the
  same fixes and gates, kept as numbers in `PipelineDiagnostics` and Copy diagnostics. They're deleted with the losing
  methods after D1.
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

- **Tests** (design §11.1):
  - still phone with auto-pause off, with and without the flag;
  - the dead-band per sport;
  - a coarse first fix, still and at 3 m/s, and after a restore;
  - a sustained offset on a run;
  - `flyingStartLosesNothing`.
- **The fixture noise model** is drifting Gauss–Markov noise (design §11.2), not white noise.
- **Unchanged:** the ±2 % fixture bounds and every other rule of this ADR.
