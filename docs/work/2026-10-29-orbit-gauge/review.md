# OrbitGauge: review log

PR 1 (#76) was reviewed in the session log and in the PR body. This file starts with PR 2.

## PR 2 · `today: calibrating draws the orbit filling night by night`

Branch `feat/orbit-calibrating`, from `main` 7643988.

### Lead decisions on the designer's open questions (d053628)

1. **Pending arcs below 3:1, accepted.** At 0.6 the dimmed arcs measure 2.2–4.2; at the trough of the breath (0.45), 1.9–2.9. They mean "yesterday, not today" and must not read as today's score. The number stays at 4.7 (light) and 5.3 (dark), and VoiceOver speaks the previous day's values, so nothing depends on the arcs alone. The contrast test pins `pendingOpacity` instead of asserting 3:1.
2. **Today owns the pending title and date line.** `OrbitGauge.Caption` gets no detail line.
3. **"Last scored: %@" / "Zuletzt bewertet: %@" is kept.** The previous scored day isn't always yesterday, so the line names the day.

### security-privacy-reviewer: no blocking findings

The locked widget stays constant in every new state. `WidgetOrbitGauge` passes `mode: nil` when the widget is redacted, so no marks are drawn and the outer orbit is a plain ring rather than the segments (which would reveal "calibrating"). The centre shows "00". The structure is `drawsOrbit || locked` in every family. The snapshot shape and file protection are unchanged, and nothing is logged.

Nits:
- **Stale comments** in `Shared/OrbitGaugeDrawing.swift` and `RyftWidgets/WidgetOrbitGauge.swift`, plus `PendingGauge` / `BaselineGauge` mentions in `OrbitGauge.swift`. Fixed by the lead in 0f9e645.
- **The unlocked widget's VoiceOver while pending** says only "Last readiness X." although the arcs show the previous recovery, sleep and strain. Kept short on purpose; the comment now says so.

### test-engineer: tests (690f077)

43 tests in 5 suites pass with `RYFT_STRICT_WARNINGS=YES`. The new files are `OrbitGaugeCalibratingTests`, which covers geometry, the count, the mode helpers and VoiceOver, and `OrbitGaugeRenderTests`, which reads pixels from an `ImageRenderer` at points the geometry gives. `OrbitGaugeContrastTests` was extended. There are no golden snapshots, because no snapshot library is allowed; the render tests check pixels at known points instead.

Findings:
- **The pending sentence has no final period.** This is intended and matches the scored sentence.
- **The stale comment in `OrbitGaugeDrawing.swift`** was already fixed in 0f9e645.
- **`segments(required:)` overlaps from about 30 segments** (the 0.5° sweep floor). This is harmless at 7, and a test documents it. No change.
- **Not testable in unit tests:** Reduce Motion (the environment value is read-only) and the stepped fill on a device. They are covered by `animatesFill: false` and the ui-validator.

### ui-validator (d62559a, iOS 27.1, en/de × dark/light × standard/AX3 × Reduce Motion)

Blocking:
1. **German AX3, calibrating: the caption breaks mid-word** ("AUSGANGSWERT" / "E"). The caption is now a `Text` under the gauge (`OrbitGauge.captionLines`), uppercase with tracking 2. Inside `BaselineGauge` it didn't scale, so this is new in PR 2. The fix must keep the scored caption ("Overall readiness" / German) right too: a word must never break, whether the caption shrinks or wraps.

Nits, judged:
2. **"Scoring your night" appears twice in pending** (the status pill and the title under the gauge). Pre-existing; not in this PR. Follow-up.
3. **The Strain tile shows "0.9" with "calibrating"** in the learningRestingHR scenario. Pre-existing tile logic. Follow-up if wanted.

Verified:
- Pending reads as "not today" in every variant; "Last scored" / "Zuletzt bewertet" wraps at AX3.
- "3 / 7" is never clipped.
- Breathing animates and stops under Reduce Motion (byte-identical frames).
- VoiceOver is one element per gauge, and the visible lines are hidden so nothing is read twice.

Not verified: the widget previews (they need Xcode), the 60 ms step on video, the 44 pt icon likeness (PR 1's `icon-44-*` shots still apply; `.small` is unchanged apart from the modes), and live VoiceOver speech.

### code-reviewer (7643988..690f077): no blocking findings

Should-fix:
1. **The fill goes empty after Reduce Motion is turned off.** The `.task(id:)` holds only the count, so `shownNights` stays nil, and on return to the app the gauge shows "3 / 7" over empty segments. → designer: put the step flag in the task id, and sync `shownNights` when not stepping.
2. **The widget loses the previous readiness when the snapshot has no orbit** (rows A / N2, and a calibrating file turning over at midnight): small and circular show a dash although `previousReadiness` is known. → developer: `WidgetOrbitGauge(previousReadiness:)` as the fallback for the centre number. Lead decision: hollow dots beside a known number are fine. The locked path is unchanged.
3. **`pendingScoredDay` / `pendingSpokenNote` are untested.** → developer: tests for yesterday, a gap day and no previous day.

Nits:
- The pure `stepFill` decision for a unit test → designer, if it's cheap.
- A `calibratingValue` vs `calibration` doc cross-reference → designer.
- A 202-character test line → developer.
- The `TodayHero.calibrating(nights:)` payload is read only by tests. Left as is.

Verified sound: the fill's grow, shrink, resume and cancel behaviour; `phaseAnimator` with a single phase doesn't churn; the Today mapping against the architecture §3 table; the catalog dict compare; the UI test identifiers kept; iOS 17 APIs.

Fix round sent to the designer (OrbitGauge.swift, Shared) and the developer (RyftWidgets, ViewModelTests), on separate files.
