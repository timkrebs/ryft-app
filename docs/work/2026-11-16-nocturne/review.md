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

## PR 2 — `design: dot numeral, ruler, glow tile`

code-reviewer reviewed 5e8d0d4 (read-only, diff). ui-validator rendered the catalog in demo mode on iOS 27.2 at L
and AX3, and with system Reduce Transparency, and measured real pixels at 3x. Neither found a blocker. Every
measured value matches the plan's table.

| # | Source | Finding | Decision | Owner |
|---|---|---|---|---|
| 1 | CR | Ruler labels are always `textTertiary` (48 %). In the compact ruler inside Today's strain glow tile, the edge labels "0" and "21" reach 3.72:1 (350 × 124) and 3.92:1 (169 × 124), under the 4.5:1 that §6 requires. | Fix in PR 2: the compact size sets its labels with the glow label opacity (78 %, full `textPrimary` from AX1). A contrast test covers the edge labels. | ios-developer, test-engineer |
| 2 | CR | `design.md` still describes the spec before the accepted deviations: `Capsule`, `.quick`, labels always 78 %, test 15. | Add the deviations to §P2-10 and fix the text. | lead |
| 3 | CR | The zone opacities for Sleep (0.85) and Strain (0.95) exist only as literals in previews. | Named presets on `RulerScale`, so PRs 4–5 don't repeat literals. | ios-developer |
| 4 | CR | `ClosedRange` traps when server data gives lo > hi (strain target, `API_REQUESTS.md` #2). | A failable `zone(lo:hi:)` helper: nil unless both are finite and lo ≤ hi. | ios-developer |
| 5 | CR | A zone narrower than the tick pitch draws no zone tick, while VoiceOver says "in target". | Mark the tick nearest the zone's midpoint when no tick falls inside. | ios-developer |
| 6 | CR | A `TickRow` label longer than 74 pt truncates instead of stacking, because `ViewThatFits` measures the fixed column. | Let the label's ideal width decide, so a long label stacks. | ios-developer |
| 7 | CR | The pending Sleep numeral is 74 pt wide; "7:48" is 125 pt, so the row jumps when data arrives. | A placeholder template string (e.g. `"0:00"`) drawn unlit, instead of a digit count. | ios-developer |
| 8 | CR | `CircleButton`'s icon doesn't scale, and it has no Large Content Viewer. | Add `accessibilityShowsLargeContentViewer` with the icon and the caller's label. | ios-developer |
| 9 | UV | `DotRow`: "today" differs from "full" only by hue (Volt vs `textPrimary`, same size and shape). | Accepted, with position as the non-colour cue: §6 itself names position ("Nadelposition") as one. `today` is always the trailing mark, and the caller's summary names it. The `DotRow` doc comment says so, and the PR 4 caller must follow it. No shape change: §1 and the board define it as the Volt dot. | ios-developer (doc comment) |
| 10 | UV | The zone label isn't under its zone (Sleep "need 8:18" at 50 %, zone at 78 %). At AX3 the label gaps shrink until the row reads as one run. | The position is faithful to the board, which also spreads labels edge to edge; the VoiceOver sentence carries the need. Raise the labels' minimum gap to 16 pt, so AX3 falls back to the joined " · " line sooner. | ios-developer |
| 11 | UV | The recovery hero tile at 362 × 172 reaches 4.53 for the 78 % label: just over the limit. | PRs 4–5: glow tiles wider than 350 pt in recovery (Insights "An idea") set labels in full `textPrimary`. Added to the plan. | — |
| 12 | UV | The glow is dim at the edges: 15–31 % metric colour at the mid-edges, 38–44 % at the corners. | Keep P2-D1: §6 contrast wins over the board's brighter edge (about 70 % at the board's 2-up corners). The PR offers the user the alternative: the board's ellipse with full `textPrimary` labels in recovery tiles. That is a one-line change in `GlowTileSpec`. | user |
| 13 | UV | At AX3 the stacked `TickRow` ticks stay 177 pt wide, left-aligned. | As specified. PR 5 decides for the Strain screen. | — |
| 14 | UV | The secondary pill outline (20 %) and the circle button border (16 %) are under 3:1 for non-text boundaries. | Accepted: §2 sets these values, and the label or icon identifies each control. | — |
| 15 | UV | The dash in "target 10–14" looks long in Satoshi. | Font glyph; accepted. | — |
| 16 | UV | `design.md` still says `Capsule`. | Same as 2. | lead |

Not checked: AX1 itself (the catalog offers XS, L and AX3; AX3 shows the fallback), Reduce Motion with a moving
needle, pressed states, VoiceOver focus order, wide devices (440 pt), anything on a device.
