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

### Re-verification of the fix round (6a90e5f, 60ca4e0, 2b0d27e)

code-reviewer:
- All three findings are fixed.
- The fill doesn't replay on a foreground return, a tab switch or an unrelated re-render.
- `neverBreaksAWord` was tested in isolation: German shrinks onto one line, English isn't shrunk at standard width, and empty titles are safe.

Two nits, handled by the lead:
1. **`stepFill` re-implemented `nextShown`'s guard**, so the test didn't prove the Reduce Motion sync. `stepFill` now takes every decision from `nextShown`.
2. **No German AX3 proof in the shots.** Added the designer's renders as `shots/pr2-fix-caption-de-ax3-{baselines,readiness}.png`.

The ui-validator's blocking finding (German AX3 caption) is closed by these renders.

## PR 3 · `today: the gauge assembles on launch`

Branch `feat/orbit-assemble`, from `main` c8dcf2a. Plan decisions 5–8.

### security-privacy-reviewer (c8dcf2a..f53107f): no blocking findings

- **The new debug log** carries the scene phase only (public, debug level).
- **The locked widget** is unchanged.
- **`OrbitGaugeMode`** isn't `Codable`, so removing `.assembling` can't break an old snapshot.
- **The flag** lives in memory only.
- **Nit:** `perf-baseline.md` committed the scratchpad path, which contains the local username. Scrubbed to `$SCRATCH` (4a08d4b).

### code-reviewer (c8dcf2a..f53107f)

Blocking:
1. **Reduce Motion on at launch and later off freezes the gauge mid-entrance.** The fade ends with `elapsed` at 0.25; `reduced` is recomputed per render, so the stage then draws the choreography frozen at t = 0.25: no arcs, no number, and the dots over the greeting. → designer: end both paths on `OrbitEntranceFrame.end` (or draw `settled` once `entranceDone`), plus a test with `orbitForcesReducedMotion`.

Should-fix:
2. **The once-per-process decisions are untested.** They live in the private `GaugeEntranceConsumer`: appear in `.active`, `.background` played-unseen, the rebuild, inactive → active. → developer: a pure decision function plus a table test.

Nits:
3. **Inactive → background without ever being active** plays the entrance unseen and loses it. → developer, in the same function: mark it played-unseen when the scene goes to the background while the flag is set. Something covering Today at launch (import cover, gate sheet, alert) also plays it unseen: accepted, and architecture §4 now says so.
4. **The UISmoke step checks the accessibility value,** which is final from frame 0. It's a smoke check, not proof that the number is drawn. Accepted, noted.
5. **The log line repeats on each appearance while the flag is set.** Fine at debug level.

Verified sound:
- no replay on a foreground return, tab switch, pull-to-refresh or sign-out/in;
- the latch survives the re-render after the flag is consumed;
- the PR 2 fill and breathing start at the entrance's end;
- one `withAnimation` clock, with nothing outliving 850 ms;
- the static path is byte-identical;
- iPhone only, so there's no multi-scene case.

The fix round is held until the performance-profiler finishes measuring f53107f, so builds don't skew its numbers.

### code-reviewer, re-verification (23f6a83..6bc2849)

Findings 1–3 are fixed:
- `done` draws `settled` on both paths;
- `TodayGaugeEntrance.decide` is table-tested;
- the background marks the entrance played-unseen.

The PR 2 fill and breathing still start at the entrance's end. The no-consume rebuild row is correct, because the rebuilt instance must latch `.assemble` before the flag is consumed.

New nits, sent with round 2:
- **`.appeared` outside the background clears `playedUnseen`** (an unlikely ordering) → developer.
- **The completion rebuilds `settled` once, invisibly,** and a 171-character line → designer.

### ui-validator (6bc2849: cold-launch recordings, en/de, dark/light, standard/AX3, Reduce Motion)

Blocking:
1. **German AX3: the assembling gauge is about 80 pt lower than the settled one, overlapping its caption, then everything jumps up** (`pr3-validate/m11.png`). Standard size is clean. → designer: the stage and `settled` share one frame and anchor; the flying dots must not take part in layout.
2. **First launch after install (and demo mode): the entrance plays on the empty no-data gauge.** The scores arrive about 0.5 s later and the arcs just fade in (`pr3-validate/m2.png`). Architecture §4's "first frame is decided" holds with stored data only. Lead decision: **the entrance plays on the first gauge that has something to show** (scores, calibrating, or pending with a previous day). The placeholder is static and never consumes the flag; the gauge becomes a new instance when content first becomes showable. Still once per process. → developer: the predicate in the pure layer, table-tested.

Nits:
3. **The band word appears with the tracks, before the score** → designer: fade it in with the glide.
4. **Light mode's first frame is dark grey:** the launch screen background is dark-first. Pre-existing; follow-up.
5. **The Reduce Motion fade** shows a placeholder for about 100 ms before the values (the same race as 2).

Verified:
- the motion reads calm, on brand and as the mark assembling;
- no flash of the final state; the tiles appear at once;
- calibrating and pending launches are correct;
- a foreground return doesn't replay;
- Reduce Motion fades only, and turning it off then returning shows the complete gauge.

Not verified: the tab-switch replay (no tap driver; covered by the table), Low Power Mode, and the real device.

### Round 2, developer (866cd23)

- **Predicate:** `TodayGaugeEntrance.hasSomethingToShow`:
  - scores: at least one value;
  - calibrating: always;
  - pending: a non-empty previous day.
  - The no-data gauge is `.scored(.empty)`, so it is not showable.
- **`decide`** takes `showable`; a non-showable gauge is never consumed, marked or rebuilt.
- **Identity:** the gauge's `.id` includes `showable`, so the first showable content is a new instance that latches `.assemble`.
- **The nit is fixed:** an appearance keeps `playedUnseen`, and an active appearance after an unseen play rebuilds.
- **Tests:** 20 `TodayGaugeEntranceTests`. Unit: 2129 passed. UISmoke: 35 passed.
- **First-launch frames** (`pr3-validate/fix-firstlaunch-*.png`): the static placeholder, then the entrance on the data.

**Accepted, follow-up:** on a first launch in demo mode, the app's main thread stalls for about 400 ms after the demo data is seeded. The whole screen freezes, the status line included. It can land on the entrance, leaving the gauge blank for about 0.4 s or skipping the glide. It is pre-existing and app-wide (also in the validator's earlier recording), not caused by the gauge. Real first launches show the import card. → follow-up for the performance-profiler: the first-launch demo seeding stall.

### Round 2 (6af8d48, designer): the clock moved to a `TimelineView`

**Cause of the German AX3 drift** (the designer's inference, confirmed live by the ui-validator): the old clock was a `withAnimation(.linear(0.85))` transaction, which also animated an unrelated hero layout change. At AX3 the status line changes from 3 lines to 1 in the same update, so the ring slid slowly. The `TimelineView` clock animates nothing else. The caption, with its band and delta, now fades in with the glide, and `settled` keeps one identity.

**code-reviewer: nothing blocking.**
- The timeline pauses at done.
- The start is captured once.
- A tab switch or the background mid-entrance continues or settles, and never restarts.
- `entranceDone` is set from `onChange`, so there's no update loop.
- The PR 2 interplay is correct.
- The identity scheme is correct.
- A refresh never empties the hero.

Nits:
1. **The frozen AX3 test can't show a transaction drift.** Closed by the live recheck below instead.
2. **The whole caption fades, title included, not only the band.** Kept, since "OVERALL READINESS" arriving with the score reads well; the comment and design.md are corrected (lead).
3. **The arcs pop in on a showable flip after the flag is consumed.** → developer, round 3.

**ui-validator re-check:**
- **German and English AX3: fixed.** No overlap and no drift; the hero moves at once when the status line changes height (pre-existing).
- **Fresh install: mostly fixed.** The placeholder is static and no longer consumes the flag, and the data instance assembles.
- **Band with the score: fixed.**
- **Regressions pass:** second launch, calibrating, pending, foreground return, Reduce Motion.

New nit, which I treat as visible polish (demo mode is what App Review and TestFlight see):
- When the data instance replaces the placeholder, frame 0 is empty, so the rings blink out and redraw (about 0.2 s; the whole stall on a fresh install).
- → developer, round 3: replacing a placeholder starts over drawn tracks.

### Round 3 (296fdcc, developer)

The entrance now assembles over the placeholder's tracks (`.assembleOverTracks`), and after the flag is consumed the identity stays fixed, so data that comes or goes animates.

Live frames (`pr3-validate/r3-*`): the rings and caption title stay through the hand-off, a fresh install's stall freezes on full tracks, and content from frame 0 gets the full entrance. Unit: 2136 passed. UISmoke: 35 passed.

**code-reviewer: OK.**
- `placeholderSeen` is set only for a placeholder seen outside the background.
- A background-only placeholder gets the full entrance.
- The over-tracks Reduce Motion path can't get stuck.
- The identity is stable when the flag is consumed, and PR 2 state is kept.

Accepted nit: when the data arrives in a different hero row than the placeholder (calibrating or pending), the rows' 250 ms crossfade dips the kept tracks to about 75 %. A same-row hand-off swaps without a dip.

## PR 4: the strain band (#81)

The band is drawn and hidden: production passes no band (plan decision 9).

### Round 1 (f0ba40b)

**code-reviewer:** the nil path adds no views, IDs or animations. Two blocking, three should-fix, one nit.
- **Blocking:**
  1. **The entrance turned the whole arc alert.** The past wedge got `to < from` while the arc grew, and `addArc` wrapped the long way round. The arc was all alert from 600 to 780 ms, then snapped. → designer.
  2. **Lint:** a double blank line in `OrbitGauge.swift`, and `optional_data_string_conversion` in a test. → designer and test-engineer.
- **Should fix:**
  1. **Crossing the band's end swapped two arc views,** a crossfade with no trim. The wedge's `to` didn't animate, so a decreasing arc cut its tail at once. → designer: one `Animatable` strain-arc structure whenever a band exists.
  2. **The rail's cut-out jumped to the destination** ahead of the dot. → designer.
  3. **The nil-parity test only proved the `clampedBand` guard.** → test-engineer: renamed to what it proves. Nil against `main` stays the designer's one-off 84-render hash check, a manual step.
- **Nit:** a leftover `print`.

**ui-validator** (shots and code; no simulator run): nothing blocking.
- **Should fix:** the preview's "no band" column reused the banded view (duplicate `ForEach` ids). → designer.
- **Nits:**
  - The modes shot didn't match the preview. → re-shot from the committed previews.
  - The rail is faint in dark mode. Kept at 0.5: 0.6 gives 2.85:1 and starts competing with the arc (design.md §11).
  - **VoiceOver gave no verdict past the band, so colour was the only carrier.** → designer: "above today's recommended range". This is one new key (en/de).
- **Accepted:** the rail runs about 7 pt beside the arc for about 80°. It reads like a double line near the dot, but is tolerable.

**localization-editor:**
- "today's range" became "today's recommended range" ("heutiger empfohlener Bereich"), because it could be heard as the day's observed lowest and highest strain.
- "target" / "Ziel" isn't used, because it is the user's own goals in the app and another wearable's term.

### Round 2 (6daa51a designer, 5d7fb1d test-engineer)

The designer's fixes:
- an empty wedge when `to <= from`, and the past layer skipped while `sweep <= split`;
- `OrbitStrainArc` and `OrbitStrainDot` are `Animatable` in the sweep, and the dot flips colour exactly at the split;
- the rail cut is `start: 0` with the sweep, as the tracks do;
- the preview ids fixed and the shots re-shot from the previews;
- the "above" key.

The nil renders are still byte-identical to `main` c0927f1 (84 renders).

New tests:
- the "above" sentence in en and de;
- `strainSplitDegrees`;
- wedge emptiness;
- mid-glide frames with a band (0.65 / 0.72 / 0.8, light and dark);
- the end frame equal to the static render;
- the `Animatable` sweep and the dot flip.

Unit: 2170 passed, 0 warnings. `make lint` passes; swiftlint and swiftformat aren't installed locally, so CI's Lint job is the real check.
