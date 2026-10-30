# OrbitGauge: plan

Brief: `brief.md`, a redacted copy of `CLAUDE_FOLLOWUP_ORBIT_GAUGE.md`. Sketch: `states.svg`. Lead: ios-lead. Started
2026-10-29 from `origin/main` aadd751, in parallel with beta feedback round 2.

**Copy rule (public repo).** The brief's example scores (74 / 74 / 86 % / 11.4) match the user's real F3 screenshot.
Committed copies, tests, previews and PR bodies use 71 / 71 / 88 % / 9.6.

## Tickets

| PR | Ticket | Owner | Branch · PR title | Depends on |
| --- | --- | --- | --- | --- |
| 1a | `OrbitGauge` component, model, previews, `design.md` | ui-designer | `design/orbit-gauge` | — |
| 1b | Shared model location, snapshot extension, one presentation → mode mapping, the assembling flag (`architecture.md`) | ios-architect | (doc) | — |
| 1c | Today `.score` and the widget draw the gauge; snapshot extended | ios-developer | `design/orbit-gauge` · `design: OrbitGauge replaces MetricGauge on Today and in the widget` | 1a, 1b, **T3 merged** (`fix/today-baseline-counter`) |
| 2 | Calibrating (7 segments, the counted signal from T3) and pending drawings; `BaselineGauge` / `PendingGauge` removed | ios-developer + ui-designer | `today: calibrating draws the orbit filling night by night` | PR 1 merged |
| 3 | Assembling on cold start, once per launch; Instruments numbers vs `main` | ios-developer + performance-profiler | `today: the gauge assembles on launch` | PR 2 merged |
| 4 | The strain band. The platform has no per-day strain recommendation (API.md / SCORING.md, checked 2026-10-29), so file "Readiness → recommended strain range per day" in `API_REQUESTS.md` and ship with the band hidden | api-contract-keeper, ui-designer | `today: the strain orbit shows today's band` | PR 3 merged |

Tests: test-engineer per PR (snapshot, geometry, widget parity, launch-once, VoiceOver strings, contrast).
Reviewers: code-reviewer always; ui-validator (it covers accessibility, because the fleet has no
accessibility-reviewer); performance-profiler for PR 3.

## Lead decisions

1. **The component starts now, the wiring waits.** The component and its design start on a branch of their own; Today
   and the widget are wired only after T3 merges. T3 changes `TodayView`, `BaselineGauge`, `Repository` and
   `ScreenModels`. PR 1 never stacks on T3's branch: it waits for T3 to land on `main`, then merges `main` in
   (see the memory note `stacked-branch-after-squash`).
2. **PR 4 ships with the band hidden.** The strain band has no platform source, so PR 4 ships without it, as the brief
   says. The app never invents a band.
3. **PR 2: S2 keeps the note only.** S2 is a readiness that is already scored while the baseline still learns. The brief leaves it to the designer whether S2's learning segments can be read under the strain arc. design.md §8 expects 0.35 opacity on the arc's own radius to be too faint at `.large` and unreadable at `.small`. So S2 draws the plain scored gauge with the existing `GaugeNote`, and `.scored(_, learning:)` stays unused by the drawing. One gauge, no second meaning to decode.
4. **PR 2: the order of work.** The ui-designer draws first (`Shared/OrbitGaugeDrawing.swift`, previews, design.md). Then two people work in parallel on separate files: the ios-developer wires Today and the widget, removes `BaselineGauge` / `PendingGauge` and adds the VoiceOver sentences; the test-engineer writes new test files. The branch is `feat/orbit-calibrating` from `main` 7643988.
5. **PR 3: no endless orbit (brief step 4).** I confirm architecture §4. Today's first frame already has a decided `TodayContent`, read synchronously from SwiftData. First run shows the import card, and pending breathes and can last for hours. So no state ever waits on the gauge with nothing to show. The entrance always ends in the real mode (scored, calibrating or pending) within 900 ms, and a gauge that orbits forever would mean loading while nothing is loading.
6. **PR 3: `.assembling` leaves `OrbitGaugeMode`.** The entrance becomes a parameter of the app's wrapper: `OrbitGauge(…, entrance: .assemble | .none)`. The widget never assembles, because widgets can't animate. The flag is `TodayViewModel.assemblesGauge`, once per process (architecture §4). Low Power Mode is treated like Reduce Motion.
7. **PR 3: the order of work.**
   1. The ui-designer builds the entrance and removes `.assembling`; that touches `Shared/` and the files that switch over the mode.
   2. The ios-developer adds the flag, the Today wiring and the UISmoke "number within 1.5 s" step, while the test-engineer writes tests in parallel.
   3. The performance-profiler measures `main`'s first-frame-to-content baseline now, and the branch once it's built.
