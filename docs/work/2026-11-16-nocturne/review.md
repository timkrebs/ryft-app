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

**performance-profiler (84bccc8, Release, iPhone 17 Pro simulator, 60 Hz, demo mode; A = skip, B = play, C = reduced; n = 12
each, medians).** Criterion 5: the sequence adds nothing to the critical path. App.init → `first-screen` 442.4 ms (A) vs
447.6 ms (B), bootstrap CI of the difference [−7.7, +14.0] ms; Today's first reads and stores start at the same time
underneath; the only new work before the first frame is §9.1's list, 3.3 ms; `.active` → first frame 6.1 ms; first frame →
hand-off 5214 ms; nothing ticks after done. The overlay costs 0.06 ms per frame to build and draw (`LaunchFrame` 0.009 ms,
`drawMark` 0.045 ms p50).

| # | Finding | Decision | Owner |
|---|---|---|---|
| 22 | "No dropped frames" fails: about 14 frames per run, 10 of them in the first 0.3 s (longest gap 123 ms), 3 in the draw-in, 1–2 at the hand-off. The same main-thread stalls happen **without** the sequence (A: 11 dropped in the first 312 ms): the demo refresh encodes JSON and writes SwiftData on the main actor right after `.active` (`Repository.store(scores:/detail:/user:/trend:/activities:)`, `publishWidget`, `TrainStore.save`), then Today re-renders. The sequence makes the existing stall visible as a jumpy fade-in. | Not a PR 3 defect; PR 3 merges. Follow-up PR "persistence writes off the main actor" (ios-architect note first, then sync-engineer): encode and upsert on a `@ModelActor`. It also helps every launch without the sequence. The interim mitigation E1 (start the clock after 4 steady frames: 10 → 2 drops in the fade-in, +245 ms to the hand-off) is not taken: it only moves the start, and with real data the stores land mid-animation anyway. | follow-up |
| 23 | The hand-off stall (40–50 ms): the uncovered gauge is built a second time (ADR 0017's accepted cost). | Follow-up with the persistence work: build the entrance gauge armed under the cover, flip it at the hand-off. | follow-up |
| 24 | Nit: the hand-off event fires 14 ms late (p90 23) and the reduced variant stays 1.262 s (spec ≤ 1.25), from `Task.sleep`'s default tolerance; the fade itself is on time (timeline dates). | Follow-up: a tolerance parameter on `AppClock.sleep`. | follow-up |

Device-only: absolute numbers, 120 Hz (stall frame counts double, per-frame cost holds), signed-in launches with real data
(stores land mid-animation), Animation Hitches (not supported on the simulator; main-thread vsync and `TimelineView` tick
gaps used instead).

## PR 4 — today and sleep in nocturne

**Code review (code-reviewer, eb8a803).** No blockers. Checked fine: the view models against the spec and API.md (first
name and greeting, the 7-entry weeks ending on the tiles' day with gaps as nil, strain bands 10/14/18, L24's integer
"enough" rule, Sleep's oldest night, stepping and clamping, the consistency week and the debt delta), day keys in the
device's time zone, no invented numbers, no new Repository, Persistence or Sync API, the pure launch-move state machine
(decided once at the hand-off, no retain cycle, nothing after done), deterministic `LaunchMoveTests`, body cost, one
accessibility element per tile and hypnogram, and the catalog diff (62 added, 10 removed, 1 changed; plurals right).

| # | Finding | Decision | Owner |
|---|---|---|---|
| 1 | Should fix: Sleep → Day said "No sleep recorded for this night." on a night still being scored (`sleep: null` from the API); every pending test passed a non-nil `sleep`. | §P4-5's pending row: Apple Health's raw night (numeral, ruler, outline hypnogram, "–" tiles), caption "From Apple Health · not scored yet" (deviation from "Asleep": raw totals are unscored); "Your night is being scored." without a raw night. Tests decode the API placeholder. | ios-developer |
| 2 | Should fix: `GlowTileKindTests.boardTiles` warned (Swift 6 error). | `nonisolated private static let`. | test-engineer |
| 3 | Nit: hand-off targets reported on every scroll for the life of the process. | Collected only while the launch is on screen; test. | ios-developer |
| 4 | Nit: the 2-up height was fixed at 98 by `idealHeight`; a long caption could clip. | No `idealHeight`; the pair grows to the taller tile (with ui-validator row 13). | ios-developer |
| 5 | Nit: "Display" had no catalog comment; a few `"\(a), \(b)"` joins. | Comment added (localization-editor); the joins stay (English only). | localization-editor |
| 6 | Nit: the mark also flew on an interruption. | Only the natural end or a tap move it; test. | ios-developer |
| 7 | Nit: `MiniHypnogram`, the old `Hypnogram` and `StageBar` were catalog-only. | Deleted; `StageRow` stays (Sleep's stage card), in `Design/StageRow.swift`. | ios-developer |
| 8 | Nit: "Asleep" under an unlit 0:00 after a failed load. | Empty caption that keeps its line. | ios-developer |
| 9 | Pre-existing: two quick night steps run two loads and two announcements. | Follow-up. | — |

**ui-validator (eb8a803, iPhone 17 Pro and 16e, iOS 27.2).** Not mergeable because of row 10; everything else within
tolerance. Measured: tiles 169 × 124 / 175 × 124, strain 350 × 96 / 362 × 96, gap 12, gauge top 144 below the header top,
Volt `#D8FF4F`, ink `#F2F1EC`, the glow's brightest pixels 59–60 % metric colour (the board's 72 % is the unrounded
corner), text 4.73–6.3:1 in the cores, Reduce Transparency flat with the metric border, VoiceOver order as the tables.

| # | Finding | Decision | Owner |
|---|---|---|---|
| 10 | Blocker: the matched move landed about 62 pt low, held, then jumped: a named coordinate space isn't resolved across the `TabView`'s hosting, so the header reported window coordinates and the top inset was added twice. The tests pinned the same premise. | Target and stage both in `.global`; `overlayRect(fromWindow:stageOrigin:)`; a real-window test of the landing ink boxes (±0.5 pt) at 390 and 402. | ios-developer |
| 11 | Should fix: the block under a ruler sat 14 pt low. The lead measured the board: the 36 pt box is 8 + a 22 pt tick row, the labels start at +32 and overflow it, and the next block is measured from the box. | `RulerScale(followingGap:)`: tiles at ruler top + 58, Sleep's hypnogram at + 56; at AX sizes the labels still push it down. | ios-developer |
| 12 | Should fix: Sleep's picker costs +64, not the recorded +48. | Design text corrected; the picker is restyled in PR 5. | lead |
| 13 | Should fix: calibrating and pending 2-up tiles lifted the value 22 pt. | `TodayTwoUpValueRow`: the caption beside the value, scaled to 0.8, or above it; the value line never moves. | ios-developer |
| 14 | Nit: Sleep's failed load showed `localizedDescription` ("NSURLErrorDomain -1009"). | The app's calm sentences (`SleepLoadFailure`), Details with the request ID. | ios-developer |
| 15 | Nit: Today's fault sub-line said "Your scores appear after the first synced night." | The date alone; the status row and the card say why. | ios-developer |
| 16 | Nit: Thin numerals make Sleep's numeral block 17 pt taller than Dots. | Accepted. | — |
| 17 | Nit: the AX3 strain caption wrapped ragged. | `TodayStrainValueRow`: beside the value, or under it from the leading edge. | ios-developer |
| 18 | Nit: the sync status row's target was 43 pt. | ≥ 44 pt, measured from the label. | ios-developer |
| 19 | Nit: the header mark's ink box is 24.7 pt against 26. | Accepted: 26 is the SVG box with the stroke inset. | — |
| 20 | Nit: the last dot of a week row is always Volt. | Per spec. | — |
| 21 | At 390 × 844 the strain tile's ruler sits about 16 pt under the floating tab bar at the scroll top. | PR 5 (the board's dot tab bar). | PR 5 |

**test-engineer (T4.5).** §P4-11 is mapped to tests row by row; new: the VoiceOver order, traits, labels and hints on
Today and Sleep (25 tests), the strings contract, the models PR 4 leaves alone, and five UI smoke tests (in `UISmoke`).
Every new assertion was mutation-checked. Design text drift it found (strain and Sleep ruler VoiceOver keys, the sleep
tile's "; 1 night has no data") is corrected in `design.md`.

**Re-review round 2 (code-reviewer on a13b5c0; ui-validator on a13b5c0, iPhone 17 Pro and 16e).** Row 10 is fixed on
real pixels: the mark lands on the header mark at 402 (21.0, 70.0 – 45.0, 94.3) and at 390, at the natural end and on a
tap, with no hold or jump; Reduce Motion cross-fades. Rows 11 (+58 / +56), 13 (tiles 124 in every state, one value
line), 14, 15, 17 and 18 pass. The validator called it mergeable; both reviews found should-fix items, fixed in
`392cd11..567de10`:

| # | Finding | Decision | Owner |
|---|---|---|---|
| R2-F1 | Should fix (regression from row 1): Sleep said "Your night is being scored." on `waiting_for_sleep`, because the day marker folds it into pending. | Sleep reads the day's scoring state: `waiting_for_sleep`, and `stale` today without a night, say "Last night hasn't reached RYFT yet." as Today does; `stale` with a night keeps its score. Tests decode the API JSON for each state. | ios-developer |
| R2-F2 | Catalog key "in bed %@ to %@" orphaned. | Removed. | localization-editor |
| R2-a | Sleep's failed load offered "Try again" when signed out. | Today's action: "Sign in", none for an outdated app, "Try again" otherwise. | ios-developer |
| R2-N2–N4 | Doc order in `RulerScale.swift`; `StageRow`'s preview; the 2-up value placed by height, not baseline. | Fixed; the value sits by its baseline, the 0.8 boundary has 1 pt slack, captions tested by frame width. | ios-developer |
| A | Should fix: the landing render test failed once under parallel load. | The renderer had returned an empty image (every pixel off, the corner transparent): the test draws again, up to three times, when the background is missing; a different drawing still fails. 25 of 25 parallel iterations pass. | ios-developer |
| B | Should fix: "Recov…" at xxxLarge. | The sparkline moves under the label in both tiles before a title is cut; hosted test at 375, 390, 402 from large to xxxLarge. | ios-developer |
| C | Nit: "calibrating" beside the value in one tile, above it in the other. | Each tile measures the other's words; if one goes above, both do. | ios-developer |
| D | Nit: the AX3 ruler labels wrapped with a line starting "·". | `RulerLabels`: whole labels per line, never a separator at a line's edge (AX3 and AX5 tested). | ios-developer |
| E | Nit: the status row's target was 43.67 pt in the fault state. | The outset makes it one device pixel over 44, on the pixel grid; a pure test at 1x, 2x, 3x. | ios-developer |
| — | Accepted: Light numerals at AX3; the lock-up passes over the ruler in flight. | — | — |

**Re-review round 3 (code-reviewer on 567de10).** No blocker. Checked fine: the scoring mapping (`stale` with a night
keeps its score, as the backend's `todayState` orders it), VoiceOver following the caption, the failure buttons, the
2-up layouts (one decision for both tiles, no layout loop, the partner's words hidden from drawing, hit testing and
VoiceOver), `RulerLabels`' line breaking, the status row's pixel-grid outset, the landing test's redraw (a wrong drawing
still fails), parallel safety of the hosted tests, strings and previews.

| # | Finding | Decision | Owner |
|---|---|---|---|
| R3-S1 | Should fix: right after the night uploads, Today says "being scored" (the phone's ledger) while Sleep, reading only the cached row, says the night hasn't arrived. | Sleep takes today's state from `ScoringWord.state` (ledger, then `/v1/me/sync`, then the row), as Today and the widget do. | ios-developer |
| R3-N1 | An unknown `scoring_state` read as scored. | Mirrors Today: unscored → waiting for the night. | ios-developer |
| R3-N2 | Two string comments still said Sleep shows "Try again" when signed out or outdated. | Corrected in code and catalog. | ios-developer |
| R3-N3 | The failure button's wiring is written twice. | One shared helper. | ios-developer |
| R3-N4 | `RulerLabels` tries 2^(n−1) arrangements. | Documented, asserted ≤ 6 labels; RTL not supported (English only). | ios-developer |
| R3-N5 | Two tests prove less than their names. | Pinned per case, or renamed. | ios-developer |
| R3-N6 | No preview of the xxxLarge arrangement. | Added. | ios-developer |
| R3-N7 | A nil-width sizing edge. | Unreachable from `TodayTiles`; left. | — |

**ui-validator round 3 (567de10, iPhone 16e and 17 Pro, iOS 27.2).** Mergeable. On real pixels:
- **B:** the full "Recovery" and "Sleep" in all 24 size × state × width cases; the series goes under the label in both tiles from xxLarge at 390.
- **C:** captions sit alike in both tiles.
- **D:** no line starts or ends with "·" at AX3 or AX5.
- **E:** the status row's target is 44.33 pt in the up-to-date, fault and signed-out states, at 390 and 402.
- **Sleep's failure:** "Sign in" for a 401, "Try again" for a 503.
- **Unchanged:** the launch still lands on the header mark at 390 and 402, and the gaps are still +58 and +56.

Sleep's waiting state, the outdated-app state and an earlier day aren't reachable in demo; they were verified hosted.

| # | Finding | Decision | Owner |
|---|---|---|---|
| R3-V1 | Should fix: at 390 the pair grows from 124 to 146.67 pt at xxLarge (149.33 at xxxLarge) when the captions go above. | Accepted: both tiles grow together and the value stays on its line from the bottom; 124 holds at every default size. Recorded in D4-16. | — |
| R3-V2 | Nit: for a 401 in demo, Sleep offers "Sign in" while Today's card has no button. | One rule for both screens, through the shared helper (R3-N3). | ios-developer |
| R3-V3 | Nit: three Sleep states have no on-screen path in demo. | Follow-up: a `-RyftScenario` hook for Sleep, then UI smoke tests. | — |
| R3-V4 | Nit: "100" alone on the second line at AX3. | Accepted (fewest lines, earlier lines fuller). | — |

**Round 4 (e0d5e7e).** Fixed: R3-S1, R3-N1–N6 and R3-V2.
- **R3-S1:** for today, Sleep takes `ScoringWord.state` (the phone's ledger word, then `/v1/me/sync`, then the row) and redraws when the word lands. `todayAgrees` runs 13 cases on the same facts.
- **R3-V2:** demo data offers no "Sign in" on either screen, because it would sign out a real session behind the demo. Details stays. A UI smoke test covers a 401 in demo.
- **Mutation checks:** every fix has one that fails without it, except the `RulerLabels` assert, which Swift Testing can't test on iOS.
- **Strict CI build:** no warnings.
- **Tests:** Unit 3232 of 3232 passed; UISmoke 48 run, 0 failures, 1 skipped by design.

Known differences between Today and Sleep, accepted:
- `stale` today without a night: Today says "No readiness yet today…" and Sleep says "Last night hasn't reached RYFT yet."
- A scored row with no readiness and no sleep: Today says "No readiness yet today…" and Sleep says "No sleep recorded for this night."

## PR 5 — strain, insights, profile and the tab bar in nocturne

Tickets: T5.0-A/B (controls, structures), T5.1 (tab bar), T6.0 (PR 6's shared parts, landed here), T5.2 Strain, T5.3
Insights, T5.4 Profile, T5.5 Sleep's modes, T5.6 strings and copy, T5.7 the whole-PR fix round. Main merged in at
29d3c53 (#107, #109, #123, #124) and 9fc09c5 (#126).

**Per-ticket code reviews (code-reviewer).** No blocker in T5.2, T5.3 or T5.4; one in T5.5. Decisions:

| # | Finding | Decision |
|---|---|---|
| T5.2-S1 | A cancelled day load cleared the next load's spinner; a late error landed on the other day. | Generation counter; test A → B → A. |
| T5.2-S2/S3 | "No strain" and "didn't record zones" read as final on a day still being scored, and on a failed workout detail. | The day's scoring state; a couldn't-load state with Try again. |
| T5.2-S4 | The day shown was never named. | The header names it when it isn't today, and VoiceOver hears it on a deep link. |
| T5.3-S1, T5.5-S1 | "vs 7 d" differed per range and from Today. | One rule everywhere: `MetricDelta.vsSevenDayMean` (T5.7 brought Strain onto it too). |
| T5.3-S2 | The band (min–max incl. the latest value) always filled the box. | Mean ± 1 SD of the prior 30 days, from 7 values; copy "Shaded: your usual range". |
| T5.3-S3 | A never-loaded series read "No data". | "Not loaded", read with a generation token. |
| T5.5-B1 | Sleep → Bedtime's numeral followed the picker's last wake, not the schedule's next wake like Today, the reminder and the widget. | Seeded from the schedule; test against `BedtimePlanner.bedtime`. |
| T5.5-S2–S6 | An older night called "Last night"; a mode-switch race; 24 h times in English US; silent stale ranges; `localizedDescription` on failure. | Named night, generation token, `Fmt.time` with en_US/en_GB tests, "As of <day>", `SleepLoadFailure`. |
| T5.4-B | Profile said "updated now" after a failed upload. | Freshness from the last successful sync. |
| T5.4-S | Duplicate accessibility identifiers through `GroupedRow`. | Additive `identifier:`. |

**T5.4 security review.** No blockers. Demo data while signed in showed the demo identity and offered "Change password"
to an Apple account: identity and account rows now come from the session when signed in (the demo identity only when
signed out). Consent rows in Demo hide Withdraw and Review (they would hit the demo API) and say why.

**Strings (T5.6) and copy round.** +97 / −27 keys with plurals for nights, days, beats and minutes; then a copy round:
no-break spaces before units and %, "usual range" instead of "band" (another wearable's word), link hints by address
("Opens in the browser" / "Opens outside the app" / "Opens the page in RYFT"), one no-strain wording, "Sleep need",
"Opens sign in". `scripts/sync-strings.py` now writes a `defaultValue`'s English as the `en` value (a key with only `{}`
compiled to the dotted key).

**Whole-PR review (code-reviewer, 4512338),** including T5.0-A/B, T5.1 and T6.0, which had no review of their own: no
blockers, five should-fix, all fixed in T5.7 (6d4ef39…a815d1b):

| # | Finding | Decision |
|---|---|---|
| S1 | On iOS 27.2 the window root's `.toggleStyle(.ryft)` doesn't reach sheet or cover content (the root's `.tint` does): stock switches in Report a problem, the import cover and others. Previews and hosted tests set the style themselves, so none showed it. | `presentedRoot()` (`Design/PresentedRoot.swift`) at all 59 presenters; `PresentedRootTests` probes the behaviour, checks real presenters for no `UISwitch` and ink tints, and a source lint fails any presentation without it. |
| S2 | The main merge lost #109's ingest URL field (label and placeholder). | Restored; `TabBarUITests` finds it by identifier. |
| S3 | Strain's "vs 7 d" used the 7 days before with at least 3; the others the 7-day window ending on the day with at least 1. | Strain on `MetricDelta.vsSevenDayMean`; duplicate delta helpers folded; test that Strain and Insights agree. |
| S4 | Insights said nothing offline (the refresh issue is nil offline). | Strain's offline line and "As of" on the cards; Demo counts as online. |
| S5 | Bedtime showed "Planning…" for ever in Demo offline. | Fixed in PR 6 C (Demo counts as online). |
| N | Dead API, stale comments, three keys without a no-break space, two comments for one key, `SegmentedMenu` without a name for VoiceOver, unbounded test waits. | Fixed; the menu reads "Range, Week". |

**Integration runs** (`strict build-for-testing` + warning grep, Unit plan, `make lint`, `make style`,
`sync-strings --check`, and a Release build, which PR CI doesn't do): 29d3c53 failed two `NocturneStringsTests` (the
PR 4 contract pinned "Display", which T5.4 drops: moved to removed); from 9f94e6c on all green. Last run at a815d1b:
0 warnings, 3,892 of 3,895 passed (2 skipped, 1 expected failure), lint, style, strings check and Release 0.

**ui-validator (a815d1b, iPhone 17 Pro, iOS 27.2, Demo data, default and AX3; states the demo can't reach rendered
from the previews' builders).** No blockers. Verified: the tab bar (74 × 44 items, "Tab n of 5", the Selected trait,
labels capped at xxLarge, reselect pops and scrolls to the top, the keyboard covers the bar), Strain's states (failed,
pending, no zones, ten days ago, offline day), Insights' ranges and offline cards, Profile with Nocturne switches only
(`presentedRoot()` reaches Details → Report a problem), Sleep's modes and the AX menu ("Range, Week"), Reduce Motion
through `Theme.Motion.respecting`, synthetic data only.

| # | Finding | Decision |
|---|---|---|
| S1 | Sleep Week and Month at AX3: the delta row widened the column to 394 pt (4 pt margins). | T5.8: the row wraps at AX sizes; hosted test of the 20 pt margins. |
| S2 | Details sheet: "Send to RYFT" a teal capsule, "Copy details" the old button. | T5.8: `PillButton` primary and secondary. |
| S3 | Bedtime's wake chip is the system compact picker, 87 × 36. | Accepted, as D6C-17 (Apple's control; the row is 44). |
| S4 | A breaking space before % in Insights' "Avg 68 %" and Bedtime's "Time in bed". | T5.8: no-break spaces. |
| S5 | Insights → Behaviors breaks words at AX3. | PR 6 (§P5-5.1 row 5 leaves Behaviors to PR 6; both merge on one day). |
| N | AX3 caption gap on Strain, dangling "·" in activity rows, glyph-row text x in Profile, an em dash in "moderate 10–14". | T5.8. |
| N | Teal on PR 6's screens reached from PR 5 (Add activity, the planner, Journal, Notifications); the Insight glow tile teal for any info insight (spec F4, a known exception to L27); a −2 % sleep drop in alert red; AX3 ruler labels; the switch's nested accessibility element. | PR 6, and the gate PR's design check. |
| N | Demo data disagrees across screens (sleep consistency 54 / 72 / 86; identical zones on other days; "Demo data · up to date" beside "Last sync Never"). | One mock-data pass before the beta screenshots. |

**T5.8 (dc27a2f…707e418).** The validator's "AX3" shots were taken at AX5 (its "vs 7 d" measures 103 × 47.7, AX5's
size; AX3 gives 79 × 36.3), so the fixes start at AX1 and are tested at AX3 and AX5. S1's cause was the night list (a
night with a nap needs 330 pt at AX5), not only the delta: the nap moves under the total, and the head stacks into three
centred lines (`DeltaLabel(stacked:)`); the picker is back at x 20, width 362. S2: both Details buttons are
`PillButton`s, and the sync line's actions and the request ID's "Copied" are ink; a pixel test finds no teal in the
sheet. S4: `TrendCardContent.valueText` joins every unit with a no-break space; Bedtime's tile and the wind-down reminder
too. DeltaLabel's gap scales with the text (4 pt default, 9.7 at AX3). Activity rows put the meta one part per line from
AX1. Profile's import rows share one glyph column. "moderate 10–14" was already an en dash (U+2013; Satoshi draws it
0.93 em wide), now pinned by a test, and stays. Every new test failed against its mutant. Whole Unit plan 3,903 passed.
Left for the PR 6 strings pass: a plain space before % in the planner (`SleepPlannerView` :102, :121), Sleep Day's
quality line, Behaviors' "90 % interval" and "% 1RM" in Train; Today's `SetupCard` teal goes to the gate PR.

**Left for later:** the shared-component retirements and token clean-up (card radius 22 vs `Theme.Metrics.cardRadius`
18, `MetricTile`, `AppState.workoutDetail`) go to the gate PR (T5.9) with an ink `AccentColor` asset as a safety net;
the leftover `.tint(Theme.accent)` roots in Activities go with PR 6 B; three "band" words outside PR 5 (coach marks,
"watch, band or ring") to the PR 6 strings pass.

## PR 6 — onboarding, Train and settings in nocturne

One PR from three branches: A (onboarding and sign-in, T6A.*), B (Train, My Day, Activities, the journal card,
T6B.0–T6B.8) and C (settings, Profile subpages, Journal settings, Bedtime & wake, the import, widgets, C1–C5 and three
fix rounds). Each branch took in PR 5's final state (M1, M2), then they were combined (M3) with the follow-ups the
combine left (M3b), the colour lint (M4, T6B.11) and one strings pass (M5). Main merged in at b9cc307 (#128 App Attest)
and 20c70e7 (#127, PR 5 squashed; its tree equals the PR 5 branch this one already had, so that merge changes nothing).

**Before the combine.** A: code and security review, re-reviews, all fixed. B: one code review per ticket, each with
its fix round. C: per-ticket reviews, a whole-PR code and security review, three fix rounds (the Demo/account split of
the journal, Bedtime & wake and Notifications), and a ui-validator pass fixed in 6c9.

**The combine (M1–M3b).**
- PR 5 into A: only `StatusViews.swift` conflicted; A's Details sheet already did T5.8's changes.
- PR 5 into B: 12 files, resolved by behaviour; #126's outbox at B's call sites; `presentedRoot()` at B's presenters.
- A, B and C: About you takes A's rows and C's editor values, with C's missed-save notice under the card; the journal
  takes B's card and sheet with C's Demo/account split; one `expectNocturneFrame`. `SettingRow`/`SettingRowLabel` go.
- Decisions: the busy rule (a spinner, the title stays, VoiceOver "In progress") beats C §2.6's gerunds, on about ten
  buttons and rows; `InlineMessage`'s text retry "Trying again…" stays as designed. "Habits" everywhere (F1). Train
  history's numbers take the locale they're given (the tests failed on a simulator with a German region).

**Colour lint (M4).** `scripts/check-accent-use.py` in `make lint`: no teal (`Theme.accent`, `Theme.teal`, `.teal`,
the assets), retired colours or zone palette in Train, My Day, Activities and the journal card; coral only in
destructive controls; Volt only in its marks, with an allowlist keyed on each mark's expression and use counts, and
Volt aliases (`FocusedRowInk.mark`, `RulerScale.needleColor`, `RestBar.ringInk`) counted as tokens. Self-test with 191
checks; each rule shown to fail on a planted violation.

**Strings (M5, M5b).** App catalog +150 / −47, widget +9 / −4, plurals for sessions, days a week, beats, sets; no-break
spaces before units and %; "usual range" and "level" for band, "tracker" for band, the habit limit reworded. A
sequential `%#@sets@ of %@` crashed every plan exercise's VoiceOver line (caught by the suites); it takes its arguments
by position. M5b synced the fix rounds' keys (+4 / −4) and gave both pending-strain lines one verb ("arrives").

**Whole-B review (code-reviewer, bd795ed): 1 B, 3 S, 9 N.**

| # | Finding | Decision |
|---|---|---|
| B1 | History, an exercise's page, a session and a plan read the platform directly: offline they showed outlines, no "Offline · as of", for up to 300 s, and didn't reload on reconnect. | Through `ReadScheduler`: offline answers at once with the cached copy or a failed state; reload on reconnect; tests with a suspending remote. |
| S1 | Those pages and My Day's uncached day failed without Details or a request ID. | `TrainRead` carries the failure; My Day reads its diagnostic. |
| S2 | "Logged session" on a workout did nothing from Today's stack. | `WorkoutDetailView` pushes the session by item (R2); UI test restored. |
| S3 | A read cancelled by a push was stored as offline or failed. | No write when cancelled. |
| N | Dead `LoadChip`; two writers of the session list (30 vs 90 days); histories kept after a finish; History's window on the wall clock; the exercise page's first load said "No data"; a detail model rebuilt per render. | Fixed. |
| N | Three hand-drawn circle menus; sheets built two ways; the live workout's offline line twice. | T5.9. |

**Combine seams review (code-reviewer, bd795ed): 0 B, 2 S, 7 N.**

| # | Finding | Decision |
|---|---|---|
| S1 | The journal sheet guarded its side only in Save: after an account session ended in Demo it read the new side, and Save closed with nothing saved. | `JournalSheetModel.isCurrent` guards every entry and the rebuild after each await; the sheet closes when it flips; test with a held read. |
| S2 / N1 | The accent lint missed `Theme.teal`, `Color("Teal")`, the zones, `.teal`, `.accentColor`, `UIColor(named:)`; its allowlist was too wide. | Fixed with self-test cases; the allowlist keys on each mark's expression. |
| N | `JournalStore.time` duplicated `Fmt.time` (wrong on a DST day); the locale missed three views; the late-save branch untested; stale `FormClosing` comments; two online sources in one sheet; a launch test that passed without its tap. | Fixed. |

**Security review (security-privacy-reviewer, bd795ed): 0 B, 1 S, 5 N.**

| # | Finding | Decision |
|---|---|---|
| S-1 | Train's reads had no binding check after their await and bypassed `ReadScheduler`: after a sign-out, an account switch or the Demo switch, A's workouts and e1RMs could land in B's caches. | Treated as a blocker. Each read takes its client (source, outbox, binding) before the await and drops a late answer; through `ReadScheduler`, so `reset()` cancels them; tests across a wipe and the Demo switch. |
| N-1 | Train's cache is shared by Demo and the account (ADR 0019). | `TrainLibrary.demoModeChanged()` clears the lists, histories, catalog and today; a demo Train store is a follow-up (`APP_STORE.md` Demo line marked open). |
| N-2 | The journal sheet could show the other side's rows. | = seams S1. |
| N-3 | Invite and consent sent once only because of the view. | `guard !isWorking` in `OnboardingCoordinator.perform`. |
| N-4 | Copy request ID used `UIPasteboard.general`. | `LocalPasteboard` (local only, 10-minute expiry); a source scan finds no other use. |
| N-5 | Demo's summary sets the account's Apple Health choice. | Accepted (the write is refused in Demo). |

Closures from earlier PRs (Journal S-1, Bedtime S-2, Notifications S1) hold. No Info.plist, privacy manifest, pbxproj
or xcconfig change; the only entitlement change is #128's App Attest environment.

**ui-validator (ecca568, iPhone 17 Pro, iOS 27.2, Demo data, default, AX3 and AX5): 0 B, 8 S.**

| # | Finding | Decision |
|---|---|---|
| S1 | `PushedHeader` had no layout for AX sizes (design §2.9). | The title stacks under Back from AX1 (V1). |
| S2 | Start workout and the plate calculator offered `.medium` at AX3. | `.sheetDetents()` / `SheetFrameSpec.detents` (V1). |
| S3–S5 | The Sport picker's header under the grabber; the plan name truncated; Check sync rows flush at AX3. | Fixed (V1). |
| S6 | Summaries left a dangling "·" at AX sizes. | `PartsLine`: one part per line from AX1, VoiceOver unchanged (V1, then R3 at the remaining sites). |
| S7 | Reduce Motion ignored in the live workout, rest timer, Start workout and the habits section. | `Theme.Motion.respecting` everywhere, with a source scan (V2; widened in R4). |
| S8 | The list workout's rest bar took ~42 % of the AX3 screen. | Ring, time and Skip at AX sizes (~415 → ~80 pt); ±15 s in the rest timer it opens; VoiceOver keeps the adjust actions (V2). |
| N | Banner glyph column and text links; the invite field's autofocus at AX sizes; a My Day number without its word. | Fixed (V2). |
| N | Report a problem's floating keyboard Done covers Send; one sheet-header convention; HR ruler labels at AX3; About you's wheel below the fold at AX sizes. | T5.9. |

**Fix rounds.** R1: F-Train (9 commits, 29 mutants), F-Journal (8 commits, 18 mutants), F-Lint. R2: S2 Logged session,
V1 layout at AX sizes, V2 motion and the rest bar. R3: `PartsLine` at the exercise page, My Day's header, an
activity's page, About you's and the body settings' source lines, Sleep need and Bedtime & wake rows, Start workout's
options; the session's loading outline under Back (11 mutants). R4 (after the re-verification below): R4T, Train's
sides and the read scheduler's reasons (8 commits, 39 mutants); R4O, onboarding and the motion scan (5 commits, 21
mutants). Every new test was run against its mutant.

**Re-verification (a0bd5c2).** Code: every earlier "fix" finding fixed. Security: S-1, N-2, N-3, N-4 closed. New:

| # | Finding | Decision |
|---|---|---|
| Code S1 | A Demo read could join an account read still in flight (`ReadScheduler` joins by key; the late `refresh()` kept going after its binding ended): the account's plans would show as Demo data. | Blocker. `fetch` sends nothing and `refresh()` writes nothing once their binding ends; Train's read keys carry the owner; `isLoading` counts refreshes. Tested through the real scheduler (account read held, reset, Demo refresh). |
| Sec S-A | Start workout kept the previous account's plan and last workout (`TrainTodayViewModel` lives for the process; on main too, wider since R1). | Blocker. `TrainTodayViewModel.forget()` on every account or side change; the options drop answers after the binding changed; a plan's days show only for the enrolment in use. The sweep did the same for Strain's, Sleep's and My Day's failures and Details. |
| Code S2 | Onboarding's own-words list lost #128's App Attest sentence (merge collision). | Kept: the invite and consent steps show #128's sentence, Details the request ID. |
| Sec N-A, code N2 | Train's action error and paused plan outlived the account; two actions wrote after an await unguarded. | Actions take their client first and write only for it; `deletePlan` goes through the same path (now with Details); the wipe and the Demo switch clear the message. |
| Sec N-B, code N6 | A consent withdrawal during another onboarding request was dropped; onboarding's busy state carried to the next account. | The withdrawal waits for the step in flight, then sends; on an account change it ends unsent. It doesn't skip the guard: an Agree answered after a concurrent withdrawal would reopen the gate. Profile shows a failed withdrawal with Details. Each step's request is bound to its account and turn; a switch clears busy. |
| Code N1, N4, N5 | The plan page fell back to outlines after a failed load; a held-back read said "Offline" online; My Day's Details from another day. | The plan page keeps its own failure. `ReadScheduler` tells offline from held back: held back online shows the cached copy as "Showing data from …", or "RYFT is busy" with the hold's Details, and Try again goes through. One hold for all Train pages stays (the platform's limits are per user and service). Each failed My Day day keeps its own Details. |
| Code N3 | The Reduce Motion scan covered three folders and three patterns. | All of `Ryft/` (362 files), six more forms, a stricter "respecting" check, and an allowlist with counts and reasons (12 guarded calls; no real hit). |

**R4 re-checks (145c91a).** Code: 0 B, 0 S, every R4 item fixed, three nits (below, T5.9). Security: S-A, N-A, N-B,
N-C and code S1 closed. New:

| # | Finding | Decision |
|---|---|---|
| Sec N-1 | The invite field kept A's code after a switch, so B could redeem a code A never sent (R4O made a late answer skip the clear). | R5: `switchAccount` clears it when leaving a known account; a link that arrives signed out still fills the next account's field, and a launch link stays for the launch account. |
| Sec nit | An onboarding failure and its request ID survived the Demo switch (Profile shows it under Privacy). | R5: cleared with the other account-state forgetters. |
| Sec N-2 | A withdrawal waiting for a step ends without a word on a sign-out or the Demo switch (seconds-long window). | T5.9: a design call (hold the Demo switch and Sign out while a withdrawal is on its way). |

**Integration runs.** At 145c91a (R4 merged): strict build-for-testing with 0 warnings in our code, the whole Unit
plan (4,669 tests, 7,170 runs with parameters: 0 failed, 4 skipped, 1 expected failure), `make lint`, `make style`,
`sync-strings --check` and the Release build. R5 on top, with CI's signing flags: strict build 0 warnings, Unit plan
4,673 passed (0 failed, 4 skipped, 1 expected failure), SignedOut and ProfileSubpages UI tests, Release, lint and
style. The PR head's code is R5's tree. `AppAttestRequiredTests/fiveConcurrentRefusalsWaitForOneRenewal` (#128) failed
once under load and passed on the rerun: it checks the server's held count before the renewal's challenge arrives
(follow-up `test:` PR).

**Left for later.** T5.9: one `CircleMenu`, one sheet assembly and header convention, the live workout's offline line,
Report a problem's keyboard Done, HR ruler labels at AX3, the remaining ~30 plain-space unit keys, the joined lines
R3 left (sentence keys), Train's online failure with nothing cached still saying "try again when you're online" (new
strings), Insights' loaded range surviving a switch (outlines missing until the next load), and the R4 re-check's three
nits: a plan page's failure also written to the library's shared message (it shows on Plans), My Day's forget without
a generation (a failed day's Details can flash one frame on the next account's Today), and a failed re-read after
pause or delete keeping the old list without a word. Security N-2 (above). ADR 0019: a demo Train store (exercise library, plans' details, the paused plan, workouts
logged with the account). Offline-first: Plans, a plan and a session say nothing offline yet; the journal's answers
wait for O6. CI: a Release build in PR checks, and the UI smoke near its 25-minute cap.
