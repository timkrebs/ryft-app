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
8. **PR 3: the UISmoke launch step gets 3 s, not 1.5 s.** XCUITest's first query after `launch()` takes about 1.15 s on an idle simulator, both with the entrance (9 runs, 1.13–1.19 s) and without it (8 runs, 1.15–1.28 s). So the brief's 1.5 s budget measures the harness and leaves 0.3 s of headroom; on the self-hosted runner (this Mac, often loaded) it would fail at random. The step keeps its purpose (the number is on screen right after launch, from frame 0) and attaches the timing. The "no slower than `main`" check is the profiler's comparison (`perf-baseline.md`, `perf-branch.md`).
9. **PR 4: what "ship with the band hidden" means.** Checked again on 2026-10-30 (plattform 7f0f8db): `API.md` and `SCORING.md`
   still have no per-day strain recommendation. PR 4 builds everything up to the data, and nothing invents the data:
   - **The drawing** (ui-designer, design.md §8): the band rail inside the outer orbit; past the band's upper end, the arc and
     dot shift toward `alert`. It is driven only by `OrbitGaugeValues.strainBand`. `nil` draws exactly today's gauge, and
     tests pin that.
   - **Previews and tests** use a synthetic band (8–13). Production passes `nil` on Today and in the widget. The snapshot
     shape stays the same, because a field that is always empty would only widen the widget's contract.
   - **VoiceOver:** once a band is present, the strain part says the range. That's one new string, en and de
     (localization-editor). It's unreachable until the field exists, and it is listed as such in the catalog comment.
   - **The request** (api-contract-keeper): `API_REQUESTS.md` → Charts and gauges #2 gets the brief's rationale and the
     readiness-band link. It is renamed "Readiness → recommended strain range per day", and its consumers are listed (this
     gauge, the Strain tab's `MetricGauge` target).
   - **When the platform ships it:** api-contract-keeper mirrors `strain_target_lo/hi` with a fixture test, and one line in
     `OrbitGaugeMode+Today` (plus the snapshot) passes it through. That follow-up isn't part of this PR.
10. **PR 4: the order of work.**
    1. The ui-designer (drawing, previews, design.md §11) and the api-contract-keeper (`API_REQUESTS.md`) work in parallel
       on separate files.
    2. Then the test-engineer writes geometry, colour and contrast, nil-parity and VoiceOver tests, while the
       localization-editor reviews the string.
    3. Reviews: code-reviewer and ui-validator. The performance-profiler is skipped: the band adds one stroke and touches
       neither launch nor lists.
