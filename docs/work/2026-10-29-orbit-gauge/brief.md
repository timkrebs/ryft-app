# RYFT iOS — `OrbitGauge`: the logo becomes the readiness gauge — brief for `ios-lead`

Run: `claude --agent ios-lead` → "Run `CLAUDE_FOLLOWUP_ORBIT_GAUGE.md`". Owner: **ui-designer** (the component, its
design note, every visual decision below that says "designer decides"). With: **ios-developer** (Today, widget, launch
wiring), **ios-architect** (where the gauge model lives so the app and the widget share it), **accessibility-reviewer**,
**test-engineer**, **localization-editor**; reviewers per fleet. Four PRs, in order, each shippable on its own.

Reference sketch: `docs/work/2026-10-29-orbit-gauge/states.svg` (three states, app colours). It's a sketch of the
mechanic, not the final drawing.

## The idea

The app icon is a centre ring, an inner orbit carrying two dots and an outer orbit carrying one, with the dots sitting
at the heads of broken arcs. That is four elements for four scores, and the mechanic is already in the mark:
**arc length = score, the dot = where you are today.**

| Element | Score | Why there |
| --- | --- | --- |
| Centre ring | **Readiness** (number inside) | The number at the top of Today; everything else feeds it. |
| Inner orbit, counter-clockwise from the top | **Recovery** (teal) | Readiness's inputs sit closest to the centre: Recovery 60 %… |
| Inner orbit, clockwise from the top | **Sleep** (violet) | …and sleep performance 40 %. Both at 100 % meet at the bottom: a whole inner ring is a whole night. |
| Outer orbit, clockwise from the top | **Strain** (blue, 0–21) | The day: what you spend after the night has given what it gives. |

A great day approaches the complete mark; a rough night leaves fragments. "Your whole health" becomes literal. The
rings are the glance; the number in the centre and the three tiles under the gauge stay the truth.

Read first: `Ryft/Design/MetricGauge.swift` (`MetricGauge`, `BaselineGauge`, `PendingGauge`, `GaugeNote`), `Features/Today/
TodayView.swift` (the `day.hero` switch: `.importing`, `.pending`, `.calibrating`, `.score`), `TodayViewModel.swift`
(`TodayPresentation`, paths S1/S2/N1/N2/L, `CalibrationProgress`, `fillingSignals`), `RyftWidgets/ReadinessWidget.swift`
and `ReadinessSnapshot.swift`, `Design/Theme.swift` (`Theme.Motion.respecting`), `docs/CHART_STYLE.md`, and
`../plattform/docs/API.md` → Days (`readiness`, `recovery`, `sleep_performance`, `strain`, `calibrating_reason`,
`baseline_*_days`) and → Scoring for the readiness bands and any strain recommendation.

---

## PR 1 · `design: OrbitGauge replaces MetricGauge on Today and in the widget`

**Component.** `OrbitGauge` in `Ryft/Design/`, pure SwiftUI, no UIKit, one `Shape` per arc so it animates with
`trim`. Model:

```swift
struct OrbitGaugeValues: Equatable {
    var readiness: Int?          // centre, 1–100
    var recovery: Double?        // inner, ccw, 0–1
    var sleep: Double?           // inner, cw, 0–1
    var strain: Double?          // outer, cw, 0–21 → 0–1
    var strainBand: ClosedRange<Double>?   // PR 4; nil until then
}
enum OrbitGaugeMode: Equatable { case scored(OrbitGaugeValues), calibrating(CalibrationProgress), assembling, pending(previous: Int?) }
```

Sizes `.small` (widget small / tiles), `.medium`, `.large` (Today), the same three as `MetricGauge` so nothing else
moves. Geometry at `.large`: outer radius ≈ 80 pt, inner ≈ 50 pt, centre ≈ 16 pt, strokes 6 / 6 / 5, dots 9 pt;
designer tunes so the drawing at `.small` is still the icon (that's the test: a 44 pt render should be recognisably the
app icon).

**Drawing rules.**
- Tracks in `Theme.surfaceRaised`; arcs in the metric colours from `Theme` (`metricRecovery`/teal, `metricSleep`,
  `metricStrain`); dots are the arc's colour, filled.
- A missing score → **hollow dot at the start position**, no arc. A Garmin user without HRV still gets a complete gauge
  (Recovery draws from what the platform scored).
- The centre ring is stroked in the readiness band colour when scored, `Theme.textPrimary` when there is no readiness,
  with the number inside as today (`showsMark`, band word and delta line under the gauge unchanged).
- Value changes animate the arc (`Theme.Motion.standard`, ≈600 ms ease-out, as `MetricGauge` does for strain); the dot
  rides the head. **Nothing rotates on its own in this mode.** A gauge that turns all day reads as "still loading".
- Light and dark, Dynamic Type up to accessibility sizes (the gauge keeps its size; the labels scale), Reduce Motion
  → arcs appear at their value with a cross-fade.

**Accessibility.** One element. Label "Overall readiness", value "71, High. Recovery 71, Sleep 88 percent, Strain 9.6
of 21." plus the existing `accessibilityNote`. The three scores are distinguishable by orbit and direction, not only
colour; confirm with the colour-blind simulator in the design note. Identifier stays `today.readinessGauge`.

**Where it goes.**
- Today `.score` → `OrbitGauge(mode: .scored(...))` in place of `readinessRing`. The values come from `TodayContent`
  (it already has recovery, sleep and strain for the tiles).
- Widget: `ReadinessWidget` draws the same gauge (small and medium) from `ReadinessSnapshot`; extend the snapshot with
  recovery, sleep and strain fractions. The gauge model therefore lives in a file both targets compile
  (ios-architect: a `Shared/` or the existing pattern for `ReadinessSnapshot`), with no app-only dependencies.
- Strain tab keeps `MetricGauge(spec: .strain)` for now; the component catalog shows both. **Don't delete
  `MetricGauge`** in this PR.

**Design note** `docs/work/2026-10-29-orbit-gauge/design.md`: geometry, the mapping table, colour and hollow-dot rules,
screenshots light/dark at all three sizes, the icon-at-44-pt check, the VoiceOver sentence, and what was tried and
rejected (e.g. three concentric rings: not the logo).

---

## PR 2 · `today: calibrating draws the orbit filling night by night`

Replaces `BaselineGauge`. The outer orbit is **7 segments** (the existing count) with thin gaps; `nights` of them in
teal, the rest track colour. Inner orbit and centre are tracks, the three dots hollow at their start positions (the dots
make it unmistakably "the same gauge, not finished yet"). "3 / 7" under the gauge where the readiness number would be;
the existing `GaugeNote`/`CalibrationProgress` copy under it unchanged.

- `countsHeartRateNights` / `fillingSignals` keep their meaning: the segments count whichever signal is filling (this
  is what `CLAUDE_FOLLOWUP_BETA_FEEDBACK_2.md` §3 fixes; land that first or in the same branch, and don't show a
  counter that can't move).
- Path S2 (a readiness already computed while the baseline still learns): the scored gauge, with the outer orbit's
  segments drawn *under* the strain arc faintly, so the learning state is visible without a second gauge. Designer
  decides whether that is legible at `.large`; if not, S2 keeps the note only.
- `.pending` (scoring last night): the scored gauge from the previous day in `PendingGauge`'s breathing style, dots
  dimmed, until the new scores arrive. Replaces `PendingGauge`.
- Widget: the same calibrating and pending drawings from the snapshot.
- Remove `BaselineGauge` and `PendingGauge` once nothing references them; catalog updated.

---

## PR 3 · `today: the gauge assembles on launch`

**Not a splash screen.** The launch storyboard stays static (Apple requires it), and no screen is held back. Today
appears immediately; the animation is the gauge arriving.

Sequence (`.assembling`, cold start only, ≤ 900 ms on a warm cache):
1. 0–250 ms: tracks draw themselves (trim 0 → 1), the centre ring last.
2. 150–600 ms: the three dots fly in from outside the gauge's bounds to their orbits and make part of one slow turn
   (≈ 40° in 350 ms, ease-out). Spring-free; `Theme.Motion` curves.
3. When the scores are available: dots glide to their value positions while the arcs fill behind them (the PR 1
   value animation). If the scores arrive before step 2 ends, step 3 starts at its end, never earlier.
4. If the scores are **not** available yet, the dots keep orbiting slowly (one turn ≈ 6 s) — this *is* the loading
   indicator, so Today needs no spinner for the gauge. Hand-off to `.pending`, `.calibrating` or `.scored` is one
   continuous animation; never a swap.

Rules: once per process launch (store a flag in the view model, not UserDefaults); not on tab switches, not on
foreground returns, not after a pull-to-refresh. Reduce Motion: tracks and arcs fade in at their values, no flight, no
rotation; the loading state is a gentle opacity breathe. Low Power Mode: the same as Reduce Motion. Keep the main
thread free: no work in the animation beyond the view; measure with Instruments that first-frame-to-content doesn't
regress against `main` (note the numbers in the PR).

Widget: no assembling animation (widgets can't), the static drawing.

---

## PR 4 · `today: the strain orbit shows today's band`

A complete outer ring is 21: all-out, not "good". So the outer track shows **today's recommended strain band** faintly
(track colour lightened in the strain hue, `butt` caps), and "whole" means *you spent what you had*. Past the band's
upper end, the arc and dot shift toward `Theme.alert` (designer decides the mix; the number stays blue in the tile).

Source of the band: check `../plattform/docs/API.md` and `SCORING.md` for a per-day strain recommendation tied to the
readiness band. If the platform gives one, use it. If it doesn't, **don't invent weights in the app**: file
"Readiness → recommended strain range per day" in `docs/API_REQUESTS.md` with the rationale (the readiness bands' copy
already says "a good day for high strain / keep it moderate / take it easy"), and ship PR 4 with the band hidden until
the field exists. The Strain tab's `MetricGauge` target uses the same value once it exists.

---

## Tests (test-engineer)

- Snapshot tests for `OrbitGauge` at three sizes × light/dark × modes: scored (71/71/88 %/9.6), all missing (three
  hollow dots), one missing (no HRV, Recovery present), calibrating 0/3/7, pending, assembling frame at t=0 and t=end,
  band present / exceeded.
- Geometry unit tests: fraction → angle per orbit (Recovery ccw, Sleep cw, both at 1.0 meet at 180°; Strain 21 → 360°),
  the dot sits at the arc's head, hollow when nil.
- Snapshot ↔ widget: the same `OrbitGaugeValues` renders identically in the app and the extension (one test in each
  target).
- Launch: a view-model test that `.assembling` runs once per launch and never on foreground return; a UISmoke step
  that Today's readiness number is on screen within 1.5 s of launch in demo mode.
- Accessibility: the VoiceOver value string per mode; contrast of each arc on both tracks in light and dark (≥ 3:1 for
  graphics).

## Ship

Strings en + de (only the VoiceOver sentences and "3 / 7" change). `docs/CHART_STYLE.md` gains the orbit gauge; the
component catalog shows every mode. TestFlight note: "Today's readiness is now the RYFT orbit: Recovery and Sleep on
the inner ring, Strain on the outer, and the gauge assembles when you open the app."

Done when Today and the widget draw the same orbit from the same values, every calibration and pending state has a
drawing, cold start shows content as fast as before, and a 44 pt render still reads as the app icon.

> Copy note: example scores replaced with synthetic ones (public repo).
