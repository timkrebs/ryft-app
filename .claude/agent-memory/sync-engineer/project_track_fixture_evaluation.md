---
name: project-track-fixture-evaluation
description: How to evaluate GPS track-pipeline changes honestly - a SwiftPM harness that runs the real track tests on macOS in seconds, multi-seed runs, and why one seeded probe or fixture misleads
metadata:
  type: project
---

The recording pipeline (`Ryft/Activities/Recording/*.swift`) imports only Foundation, so
`swiftc -O -swift-version 5 Ryft/Activities/Recording/*.swift harness/main.swift` builds a macOS harness that replays
the `RyftTests/Fixtures/Tracks` JSON in milliseconds. For seed sweeps, copy `scripts/make-tracks.py` to scratch, make
the `random.Random(<seed>)` values variables, and generate 20 seeds.

**The real tests on macOS (A3a.2, 2026-10-24).** A scratch SwiftPM package runs the Swift Testing track suites
unchanged: target `Ryft` = symlinks to `Recording/*.swift` plus a `TrackProfile` shim (Sport.swift needs the wire
`Sport`); test target `RyftTests` = symlinks to the `Activities/*Tests.swift`, `TrackFixture.swift`, helpers, plus a
`TrackProfileFixture` shim with the catalogue's values and a `Fixture` shim on `Bundle.module`
(`resources: [.process("Fixtures")]`, not `.copy`), `swiftLanguageModes: [.v5]`. `swift test` takes ~25 s with the
build, ~2 s for 100 tests: iterate there, then confirm with xcodebuild. For mutants copy the sources (not symlinks)
so a running xcodebuild never sees a mutant; ~30 s per mutant.

Findings from A3a (2026-10-23):
- One seed hid systematic errors: summing filtered positions read +0.77 % on the committed trail but +2.7 % mean
  over 20 seeds. The reason was cancellation between noise-added length and long gap bridges. Velocity integration,
  with position steps for 10 s after a restart, reads +0.5 % mean.
- Split crossing ±2 s and per-sample pace ±3 % are limited by physics: open-sky along-track error of about 3 m is
  ±1 s at 3 m/s. No method or seed choice fixes that, so test exact semantics on noiseless tracks and use
  physics-derived bounds on fixtures.
- The pass/fail of canopy accuracy depends on the fixture's error correlation time (20 s: +3.2 % error-only floor;
  30 s: +1.7 %). Report such sensitivities instead of tuning the fixture until it passes.

Findings from A3a.2 (2026-10-24):
- The architect's acceptance bounds came from one probe seed. Under the design's own noise helper (σ = accuracy / 2)
  "descent above the limit ±1 %" read −1.21 … +1.09 % over 20 seeds at 5 m (each second a too-fast boundary moves is
  limit × 1 s), and "train ≤ 120 m vs truth" read up to +129 m because the run's own noise was in it. Measure noisy
  rows against the same seed without the fault, and give boundary-timing rows a physics bound; report both.
- A rule that passes every acceptance scenario can still break an old test the probe never ran (association broke
  `aCoarseFirstFixAddsNothing`; a run at exactly `maxSpeed` rang over the limit). Run the whole suite on the probe's
  variant before trusting its table.

**Why:** the acceptance numbers sit inside the uncertainty of the noise model; a single seed can pass for the wrong
reason.

**How to apply:** any change to TrackPipeline, KalmanTrack or make-tracks.py (A3b, D1 tuning of σa or the gates):
rerun the 20-seed sweep with both `Tuning.distanceFromVelocity` values before trusting the committed-fixture tests.
Related: [[project-dev-machine-disk]], [[feedback-tests-pin-decisions]].
