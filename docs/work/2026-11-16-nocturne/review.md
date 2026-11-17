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

**Fix round (884a9a8…6949eaf):** rows 1, 3–5 and 7–10 are fixed as decided; row 2 is done in `design.md` (P2-D6 to P2-D14).
The compact edge labels went from 3.68–3.90:1 to 6.99–7.65:1 in the strain tile, and from 3.13–3.44 to 5.52–6.32 in a
recovery tile (worst case), at L; ≥ 7.65 at AX3. The Unit plan stays at 2806 green.

**Re-review of the fix round (code-reviewer, 95d7260..fe1be90):**

| # | Finding | Decision |
|---|---|---|
| 17 | Blocking: row 6 isn't met. A mid-length `TickRow` label (about 75–120 pt) stays on one line and is drawn over the ticks, because the value column takes the space first. | `layoutPriority(1)` on the label column: the label widens its own column instead of overlapping, and the row stacks only when it no longer fits. A block that must keep one tick column decides stacking for all rows (PR 5). Render test with a ~100 pt label in a 361 pt row. |
| 18 | `design.md` gave `[31]` for `(61, 0...100, 50.5...51)`; the code gives `[30]`. | Doc fixed (`[30]`; `50.9...51.1` → `[31]`). |
| 19 | A floating-point tie (25.499999999999996) rounds down, against the documented "tie goes up". | Round `position + 1e-9`. |
| 20 | `ZoneStyle`'s implicit init lets callers write literals again; `.standard.opacity` reads nil next to `opacity(for:)`. | A private init; the stored value is renamed `fixedOpacity`. |
| 21 | Doc drift: the DotGlyphs API block, tests 4/9/15, the Large Content Viewer, the contrast figures, plan carry-overs. | Fixed in the docs. |
Accepted as is: in the Light fallback (AX1+) the pending "–:––" is wider than "7:48" (231 vs 174 pt at AX3), because an
en dash is wider than a digit; only the dot grid keeps the width. A figure dash (U+2012) would fix it if Satoshi has
the glyph: follow-up, not PR 2.

## PR 3 — gauge v3 and launch

**Code review of gauge v3 (code-reviewer, 9953a8e..79bcfd8).** No blockers. Checked fine: geometry (code angle = board
+ 90°, ±6° / 160°, lit-tick rounding over 0–100, tiers, omitted ticks at the board values), the cut scoping per ring,
every contrast number recomputed, `Shared/` compiling for the widget, the API additive, the widget `Brand` hexes against
the app catalog (PR 1 row 13: no drift; `check-shared-types.py` now checks them in `make lint`).

| # | Finding | Decision | Owner |
|---|---|---|---|
| 1 | Should fix: the halo-not-clipped test samples at 212.6°, inside the frame square, so a `.clipped()` would pass. | Render strain 10.5 or 21, sample 2 pt outside the frame on the axis, rect guard. | test-engineer |
| 2 | Should fix: "entrance last frame = static" renders at `end`, which takes the settled branch; the choreography is never drawn. | Render at `end − 1e-4`, plus a pure scene test at `end` and at 0.4 s (no Volt yet, halo = flight). | test-engineer |
| 3 | Should fix: `design.md` lags the code (centre weight, the "–" placeholder, layer order, caption, entrance Volt fade, `<=`, removals). | P3-10 rows 20–29 and the P3-1 text. | lead |
| 4 | Nit: pending strain contrast is pinned over the 7 % ring, a pairing never drawn. | Pin 2.34 over the 16 % ticks. | test-engineer |
| 5 | Nit: by centre distance a whole tick reaches 0.59 pt into a dot's cleared ring (strain 20.3). | Omit by rect distance; sweep test (P3-8 case 7). | ios-developer |
| 6 | Nit: dead code (`Tracks`/`Marks` inits, palette band colours, `stroke(of:)`'s argument). | Delete. | ios-developer |
| 7 | Nit: the Light numeral rolls on `quick` while the arcs move on `slow`. | Scope `quick` to the dots. | ios-developer |
| 8 | Nit: `colorset_rgba` misreads integer components; `without_comments` cuts `"ryft://…"`. | Handle both; re-prove with planted drift. | ios-developer |
| 9 | Heads-up: dots by size alone would draw "100" over the inner ticks. | Size gate AND width check (row 20). | ios-developer |
| 10 | Heads-up: the widget track override must not go through `ink`, which the lit ticks use. | A separate optional track colour. | ios-developer |

For PR 4: `GlowTile` clips its content, so a gauge inside one needs ≥ 3 pt inset for the halo.

**Code review of the launch and the gauge fixes (code-reviewer, 79bcfd8..9f8d8b6).** No blockers. Checked fine: nothing
new gates startup (two `UserDefaults` reads, a pure decision and a background fill before the first frame; bootstrap,
`afterFirstFrame`, sync and auth run unchanged beneath); no ticking after done; signposts balanced on every path but
row 15; no double play (process-scoped model); the string catalog diff is two targeted keys; `RyftMark` unchanged
(`mark-svg --check` passes); the gauge fixes (rows 5–10) as decided. Every stated deviation is accepted except the
strain head (row 14).

| # | Finding | Decision | Owner |
|---|---|---|---|
| 11 | Should fix: `InviteCodeView` focuses its field on appear, so under a playing launch the keyboard slides over the arcs and keystrokes go into a hidden field (invite-gated first run, cold reopen > 10 min). | Focus only when not covered; focus on `launchCoversRoot` → false. The only root auto-focus in the app. | ios-developer |
| 12 | Should fix: no `CHANGELOG.md` line. | Two lines under Changed (gauge, launch). | lead |
| 13 | Should fix: `design.md` and `launch-design.md` lag the accepted deviations (reduced timing, Low Power Mode, identifier and traits, catalog Play, the frame API, L9's row, `lateActivation` focus, the `.launch` offset). | P3-5/6/7/9, P3-10 rows 30–34; an "as built" list in `launch-design.md`; ADR 0017 §5 on `play` vs L9. | lead |
| 14 | Nit: the launch re-derives the strain head (`360 × fraction`) beside the gauge's mapping. | Use `OrbitGaugeGeometry`'s `headDegrees(for:)` (122.565°, 0.006° off). | ios-developer |
| 15 | Nit: if the natural-end deadline runs ≥ 0.4 s late, `playing → done` skips the `launch-handoff` signpost (M2's end). | Emit it on `playing → done` too, except when backgrounded. | ios-developer |
| 16 | Nit: XCUITest traps: the overlay is a Button; tap-to-gone measured 1.56 s (idle wait); hidden children are still listed. | Passed to test-engineer for T3.4. | test-engineer |
| 17 | Nit: the tick-sweep oracle uses the code's own formula (independently verified correct). | Optional: corners of the transformed tick path. | test-engineer |

Not verifiable by reading: whether `.accessibilityHidden` on the covered root reaches the UIKit-hosted tabs (Accessibility
Inspector or VoiceOver on a device), taps on the tab bar while covered, hitches (performance-profiler), device-only
launch paths (SpringBoard, HealthKit/BG, real purpose launches).

**ui-validator (9f8d8b6, iPhone 17 Pro simulator, dark, English).** No blocker, no should-fix. The gauge at 260 measures
118.0 / 88.0 / 58.0, ticks 1.20 × 6.0 and 1.30 × 7.0, dots within 0.1° of the spec, the "84" grid 74.0 × 47.0 centred, the
tracks' colours exact; Today's `.large` gauge is v3 with a Light centre and its entrance after the hand-off. The launch
fits the sample table at RMS 0.84°, layout within 0.7 pt, reduced 1.25 s, a tap ends it 0.252 s later (log), the AX3
tagline scales on one line. Contrast from pixels equals P3-3.

| # | Finding | Decision | Owner |
|---|---|---|---|
| 18 | Nit: the sequence clock starts at `.active`, about 0.15 s before the first `TimelineView` draw, so in Debug the first frame is t ≈ 0.03 at 77 % group opacity: a pop instead of a fade (P3-10 row 5). | Anchor the start to the first drawn frame. | ios-developer |
| 19 | Nit: Release simulator, a ~3-frame freeze at the start (group opacity 0.2 → 0.85), plus 1–2 frame repeats in the draw-in. | performance-profiler measures hitches on a quiet machine (M4); fix if it is ours. | performance-profiler |
| 20 | Nit: pending dims the marks to 0.6 over full-strength 16 % ticks, so the ticks show through the strain arc as a ladder; Today shows pending every morning. | Cut the outer ticks under the strain arc while pending (as scored hides them). | ios-developer |
| 21 | Nit: the overlay is a Button "Loading RYFT" (`launch.sequence`). | Accepted (P3-10 row 32). | — |

The system launch screen reads `#090C0B` in screenshots against the overlay's `#0A0C0B`: one level of red, no visible
flash. Not checked: VoiceOver itself, frame pacing on a device, Low Power Mode, the widget on the Lock Screen.

**Fix round (d92ebe7…84bccc8).** Rows 11, 14, 15, 18 and 20 are fixed as decided, plus the tagline inset (the stage read
the safe area inside `.ignoresSafeArea()`, so a > 40 pt inset was ignored; test-engineer pinned it as a known issue,
now a plain pass) and L13 (one tagline: `BrandLockup` says "Engineered for peak.", the two old keys left the catalog by
targeted edits). Row 18's evidence: the first drawn frame is t = 0 with group opacity 0 in 5 of 5 Debug launches (was
t ≈ 0.03 at 77 %); Debug stalls of 60–280 ms in the first 0.3 s can still swallow part of the 0.25 s fade, which is
performance-profiler's (row 19). Row 20: the scored shots are byte-identical; only pending shots change. Unit 3010
passed + 2 skipped, UISmoke 41 + 1 skipped, zero warnings, `make lint` and `make style` green.
