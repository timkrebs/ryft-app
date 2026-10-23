# My Day and activities: review log

Lead: ios-lead. Reviews are read-only; their findings go back to the owner.

## A3a `activities: track pipeline` (2026-10-23)

**Commits:**

| Commit | What |
| --- | --- |
| f729e4f | The pure pipeline: Kalman, geodesy, splits, auto-pause, elevation, codec, seeded fixtures |
| 24c26cf, a2007ad | ADR 0003 Amendment 1, design §3.3/§3.4/§3.9/§11 amended, R20 |
| b059151 | Review fixes (code review + architect) |
| f07b6f4 | Re-review fixes |

**Gates:** strict build clean; Unit 960/960; `make lint`, including `make-tracks.py --check` on Python 3.9–3.15.

**Final fixtures:**

| Fixture | Distance | Other |
| --- | --- | --- |
| road-5k | +0.31 % | splits km 1–4 −1.96 … −2.81 s |
| trail-switchbacks | −0.34 % (raw fixes +10.5 %) | baro ascent 400.5 m (truth 399.9) |
| still phone | 0.0 m | auto-pause on and off |

Over 20 seeds: road −0.10 … +0.45 %, trail −0.95 … +2.09 %, worst split ≤ 4.37 s.

### code-reviewer (f729e4f), then the architect

| # | Finding | Result |
| --- | --- | --- |
| 1 | The start or restart fix counted as distance: +20/+42 m for a still phone | Settle window (Theil–Sen line vs filtered track): 0.0 m |
| 2 | Still phone with auto-pause off, under drifting noise: 15–228 m in 10 min; the fixture never tested it | `isStationary` modelled; a per-sport dead-band backstop; the noise model accepted in §11.2 |
| 3 | Redaction trapped on NaN or ∞ accuracy | "?" rendering, tested |
| 4 | A stopwatch linearity test, flaky under load | A structural retained-sample test |
| 5–14 | `stepFrom` across Start; Python-version-dependent `--check`; staleness after an invalid fix; late fixes after Resume; splits in backdated pauses; ascent 0 vs nil; ∞ average speed; dead code; warm-up diagnostics; `dump` leaking the anchor latitude | All fixed, with tests |
| A (architect) | Sustained multipath "aged open" the speed gate: +79–92 m per episode | The re-init counts both gates: −18 m |
| B (architect) | The auto-pause moving clock jumped back ≥ 10 s | The clock holds while a pause is pending; the displayed time never decreases |
| C (architect) | Route points emitted while paused | Emitted only while recording |
| D (architect) | 558 KB of unused GPX files in the test bundle | Generated on demand |

### code-reviewer re-verification (b059151)

All of the above were confirmed fixed with a standalone harness. New findings:

| # | Finding | Result |
| --- | --- | --- |
| N1 | A settle window closed by its cap with fewer than 3 fixes dropped up to −134 m | Falls back to the gap rule: 0.0 m |
| N3 | Standing start after a warm filter lost 7–20 m | The window always opens at Start: −0.1 … −2.8 m |
| N6 | `pause(at:)` discarded the window's events | Returns them |
| N7 | The dead-band test had no teeth | It fails with the dead-band at the floor |
| N2 | Counting speed-gate rejections costs short 3–6-fix ghosts −18…−27 m. A stretch above `maxSpeed + 2σ` (cycling > 33 m/s) records 0 m silently | **Deferred to A3a.2** (plan): architect first, with a shadow restore, a bridge, and a `.tooFast` event |
| N4, N5 | A U-turn inside the window loses up to ~18 m; +2.6 m per traffic-light stop | Accepted trade-offs |

**Privacy:** the pipeline logs nothing, `Checkpoint` has no coordinate, and every location type redacts in `description` and `dump`.
The security-privacy sign-off for trimming and sealing comes with A3b, where they're built.

**Contracts for A3b:**
- forward the events of `ingest`, `advance(to:)`, `pause(at:)` and `finish(at:)`;
- store splits from `checkpoint`;
- feed the first pedometer sample after `resume(at:)`, and add `rebasePedometer(_:)` for the restore path;
- route chunks only from `.route`, which is emitted only while recording;
- GPS-only elevation on a still phone: about 17 m of false ascent in 10 min. Gate it on `isStationary` (A3b, D1).
- **Merge with A1:** delete `Ryft/Activities/Recording/TrackProfile+Pending.swift`, since A1's `Sport.swift` declares `TrackProfile`. Then point the test fixtures at `Sport.*.trackProfile`.
