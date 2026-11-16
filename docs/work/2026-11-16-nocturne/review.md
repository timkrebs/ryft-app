# Nocturne — review log

## PR 1 — `design: nocturne tokens, type and icon`

Reviewed at d1010b0 by code-reviewer (read-only, diff) and ui-validator (simulator, demo mode, system set to light,
default and AX3, English, real-pixel contrast). Neither found a blocker.

| # | Source | Finding | Decision | Owner |
|---|---|---|---|---|
| 1 | CR | ADR 0016 still described the branch before d77809f: the open item, tests that composite the track, "CI has no Satoshi", "half a pixel". | Fix in PR 1. | ios-architect |
| 2 | CR, UV | `WelcomeView` call-site `.tracking(3)` shows now that `ryftLabelStyle` has no tracking. | Fix in PR 1. | ui-designer |
| 3 | CR | `ExerciseCard` kg/reps inputs turned Light (`numeral` ≥ 20 pt), next to Regular RPE; `design.md` D-f says inputs stay Regular. | Inputs stay Regular (`weight: .regular`), matching D-f. | ui-designer |
| 4 | CR | `OrbitGaugeContrastTests` lost its "below 3:1" assertion with the light scheme, though dark has the same case (2.34–2.81). | Re-add it in dark. | ui-designer |
| 5 | CR | "CI has no Satoshi" is wrong: the test and TestFlight jobs run `make fonts`; only Lint has none. | Fix the docs. The real gap is local runs without fonts, where the existing fallback ignores role sizes: follow-up. | ui-designer, ios-architect |
| 6 | CR | Stale docs: README fonts and icon lines, two light hero screenshots, the PR template's dark/light table, CHART_STYLE's preview rule. | Fix in PR 1. The 74 committed `-light` screenshots stay until PR 5 re-shoots every screen. | lead |
| 7 | CR | `render-icon` horizontal centring guard can't fail (`x` from `ink.midX`); the docs say 0.5 px, the code 1 px. | Measure the rendered bitmap, 1 px everywhere. | ui-designer |
| 8 | CR | Dead `.light` branches: `FocusedRowInk` (comment says 4.40:1, now 3.94), `ExerciseCard.raisedFill`, `SourceBadge`, `FocusedPolishTests` Light cases. | Remove in PR 1. | ui-designer |
| 9–11, 14 | CR | `Theme.swift:29` comment ahead of PR 3; a second background literal in the token test; `Wordmark.size` literal vs the unused role; the `Makefile` comment. | Fix in PR 1. | ui-designer |
| 12 | CR, UV | Widget and Live Activity caps: "REST"/"WORKOUT", "SNOOZING", tracked. | Sentence case, no tracking, keys renamed in the widget catalog. | ui-designer |
| 13 | CR | The widget's `Brand` hexes aren't checked against the catalog. | PR 3 (the widget gauge). | — |
| 15 | UV | The Sleep segment control truncates one more character at AX3 ("M…"; main already had "Mo…"). | PR 4 (Sleep screen). | — |
| 16 | UV | The icon at 40 px: strokes about 0.9 px, a little grey, still legible. | Accepted: it is the approved M1 look. | — |
| 17 | UV | "TRIMP 112" in capitals. | Acronym, stays. | — |

Not checked: the widget on a light Home Screen (`simctl` can't add widgets), the Live Activities rendered, the
`StrainPill` empty state (demo mode doesn't reach it), and anything on a device.
