# Nocturne — plan

**Goal:** the premium look of `brief.md` (NOCTURNE_STYLE v0.2): the same OrbitGauge geometry, model and mapping,
rendered premium. The rings are the legend (recovery teal, sleep violet, strain blue everywhere), Volt `#D8FF4F` is
signal only, the app is dark-only, and the launch turns the rings into the orbit mark.
**Mockups:** https://claude.ai/artifact/1Gc5U9M2MyFgRKQHwHRtMi (Today, Sleep, Strain, Insights, Profile, Launch, Icon M1).
**Out of scope:** model, sync and API changes. A screen that lacks data gets a MockData placeholder and an
entry in `docs/API_REQUESTS.md`.

## Decisions taken by the lead (2026-11-16)

| # | Decision | Why |
|---|---|---|
| D1 | Previews and validation in **English only** (dark, AX3), not en/de as the session brief says. | `CLAUDE.md` and #105: RYFT is English only. |
| D2 | The ADR is **0016**. | 0015 was used on the closed Alpine PR #100. |
| D3 | PR 1 changes the `CLAUDE.md` preview rule to dark-only. Light previews go file by file as PRs 1–5 touch each file; PR 5 removes the rest. | Avoids a repo-wide preview sweep in a tokens PR. |
| D4 | Satoshi is already in `LicensesView` (ITF Free Font License). PR 1 only adds the Light weight to that entry, `fetch-fonts.sh`, `UIAppFonts` and the archive check. | Same family, same licence. |
| D5 | `main` shows a mixed look between PR 1 and PR 5: the new colours and type on the old layouts. Accepted. | The brief's order. The nightly has been red since 2026-11-05 (signing), so no build reaches testers before the user fixes it anyway. |
| D6 | The widget follows the app: same tokens, dark only. | §1 dark-only; `check-shared-types.py` keeps both catalogs aligned. |
| D7 | `textTertiary` at 45 % is about 4.1:1 on `background`, under 4.5:1 for 11–12 pt text. The designer verifies and raises it if needed. ADR 0016 records the number. | §2 allows deviations "wo Kontrast … es verlangt". |

## Tickets

### PR 1 — `design: nocturne tokens, type and icon` (branch `feat/nocturne-tokens`)

| Ticket | Owner | Files |
|---|---|---|
| T1.1 Tokens, type, wordmark, icon, fonts | ui-designer | `Design/`, both `Assets.xcassets`, `scripts/render-icon.swift`, `scripts/icon-spec.swift`, `scripts/mark-svg.swift`, `scripts/fetch-fonts.sh`, `Makefile`, `Ryft/Info.plist` (`UIAppFonts`), `LicensesView` entry, token tests, `design.md` §PR1 |
| T1.2 Dark-only wiring, caps outside Design | ios-developer (branch `feat/nocturne-dark-only`, merged into PR 1) | `App/Settings.swift`, `App/RyftApp.swift`, `Features/Profile/ProfileView.swift`, `DebugComponentCatalog.swift`, `Features/Train/Session/ExercisePage.swift`, `Ryft/Info.plist` (`UIUserInterfaceStyle`), string catalog (removed keys only) |
| T1.3 ADR 0016 | ios-architect | `docs/adr/0016-…` |

Acceptance criteria:
1. The colorsets in `Ryft/` and `RyftWidgets/` carry the §2 values with a single appearance. `Signal` `#D8FF4F` and
   `OnSignal` `#0A0C0B` exist. A unit test pins every §2 token; any deviation is the ADR's number.
2. Every text token reaches ≥ 4.5:1 on `background` and `surface`. Metric and signal colours reach ≥ 3:1 on both
   (unit test).
3. The app is dark in every context, whatever the system setting: the root, sheets, alerts and the launch screen.
   Profile has no appearance setting, and a stored `appearance` value is ignored.
4. Satoshi Light is registered and fetched, and the archive check covers it. Titles and numbers are Light, body
   Regular and buttons Medium, per the §2 scale with tabular digits. `ryftLabelStyle` is sentence case without
   tracking. No `.textCase(.uppercase)` is left on a label.
5. The wordmark is "RYFT" in Satoshi Light at 0.32 em tracking, beside the orbit mark, with a Preview.
6. `make icon` renders M1 into the asset catalog: `#0A0C0B` tile, "RYFT" Satoshi Light `#F2F1EC`, 0.02 em tracking,
   ≈ 280 px on 1024, no mark, light, dark and tinted alike. `make lint` is green.
7. ADR 0016 covers dark-only, the tokens with every deviation from §2 or from today's assets (with numbers), the
   signal rules, the widget and the icon.
8. Zero warnings in our code, all tests green, a CHANGELOG line under Unreleased, and a line in STATUS.md.

Verify: code-reviewer and ui-validator (dark, en, AX3, icon at 60 and 40 px), in parallel.
No security-privacy-reviewer: the only Info.plist changes are a font entry and the interface style, with no
auth, data or network.

### PR 2 — `design: dot numeral, ruler, glow tile` (branch `feat/nocturne-components`)
`DotNumeral` (5×7, dots 5 pt, gap 2 pt; falls back to Light digits from AX1), `RulerScale` (band zone, Volt
needle), `GlowTile` (§2 gradient, flat `surface` + 2-pt metric border under Reduce Transparency), `DotRow`,
`TickRow` (zones), pill and circle buttons. Catalog entries and tests: the digit matrix, luminance under text in
the glow core (§6).

| Ticket | Owner | Files |
|---|---|---|
| T2.1 Component spec: API, geometry, states, accessibility, glyph table | ui-designer | `design.md` §PR 2 |
| T2.2 Components, previews, catalog entries | ios-developer | new files in `Ryft/Design/`, `DebugComponentCatalog.swift` |
| T2.3 Tests from the criteria below | test-engineer | new files in `RyftTests/` |

T2.2 and T2.3 run one after the other in the same worktree, because both need builds. No screen uses the components
before PRs 4 and 5.

**Measurements from the canvas boards** (390 pt wide; CSS px = pt):

| Component | Values |
|---|---|
| DotNumeral | Glyphs are 5 × 7 dots; `:` and `.` are 1 × 7 (`:` lights rows 3 and 5, `.` lights row 7). Dots are 5 pt with a 2 pt gap, so a digit is 33 × 47 pt. Glyph gap is 8 pt (Today) or 7 pt (Sleep, Strain). On `textPrimary`, off `textPrimary` at 10 %. Matrices in the boards: `1` 00100 01100 00100 00100 00100 00100 01110 · `2` 01110 10001 00001 00010 00100 01000 11111 · `4` 00010 00110 01010 10010 11111 00010 00010 · `7` 11111 00001 00010 00100 01000 01000 01000 · `8` 01110 10001 10001 01110 10001 10001 01110. One accessibility element: "Readiness 84 of 100", "7 hours 48 minutes asleep", "Strain 12.4 of 21". |
| RulerScale | 36 pt high. A tick row of 22 pt under 8 pt of top padding, ticks spread edge to edge: Today 61 (0–100), Sleep 61 (0–10 h), Strain 64 (0–21). Outside the zone: 1 × 8 pt, `textPrimary` at 22 %. Inside: 1.5 × 14 pt in `textPrimary` at 55 % (Today "high" ≥ 67), sleep at 85 % (need 7.5–8.3 h) or strain at 95 % (target 10–14). Needle: a Volt triangle 12 wide × 8 high pointing down at the top, then a 1.5 × 20 pt line, at the value. Labels below in 11 pt `textTertiary`: "0 · low · moderate · high · 100", "0 h · need 8:18 · 10 h", "0 · target 10–14 · 21". Compact variant inside the strain glow tile on Today: 43 ticks; zone ticks 1.5 × 12 at 60 %, others 1 × 7 at 26 %, needle line 16 pt. |
| GlowTile | Fill = the metric colour, under a radial overlay of `background`: 97 % at the centre, 92 % at 34 %, 55 % at 68 %, 10 % at the edge. Ellipse 85–90 % wide × 80–110 % high, centred at 50 % / 50–55 %. Radius 24 (Today 2-up tiles, 124 high) or 28 (Sleep and Strain hero tiles, 168–176 high); padding 14 top, 16 sides; no shadow, no border. Labels in it are 13 pt at 78 %. |
| DotRow | Dots are 6 pt with a 4 pt gap. Full = `textPrimary`, missed = 1 pt outline at 50 %, today = signal. |
| TickRow | Heart-rate zones: 5 rows, 9 pt apart. Each row: label 12 pt at 62 % (74 pt wide), 30 ticks of 3 × 12 pt with radius 1.5 and a 3 pt gap (lit `textPrimary`, unlit 12 %), value 12 pt with tabular digits (40 pt wide, trailing). Lit ticks = round(minutes / scale max × 30). |
| CircleButton | 40 pt circle with a 1 pt border in `textPrimary` at 16 %, no fill; icon 14 pt, stroke 1.3, `textPrimary` (disabled 35 %). Hit target 44. |
| PillButton | 52 pt high, radius 26. **Primary:** `textPrimary` fill, 15 pt Medium text in `background`, with a 40 pt `background` circle on the trailing side holding a `textPrimary` icon (padding 20 leading, 6 trailing). **Secondary:** outline 1 pt at 20 %, 15 pt `textPrimary`, padding 22. |

**Acceptance criteria**
1. `DotNumeral`:
   - Draws `0`–`9`, `:`, `.` and `,` (region decimal separators) from a pinned glyph table, with the sizes above. It is drawn as shapes, not a font.
   - One accessibility element, with a label the caller provides.
   - At AX1 and above, and with `style: .light`, it renders Light digits (52 pt at the default size). Any character outside the table falls back the same way.
2. `RulerScale`:
   - Takes the range, value, zone, zone tint, tick count and labels. The value is clamped and the needle is Volt.
   - Has a regular and a compact size.
   - Is one accessibility element whose sentence carries the value, the band word and the range (§6: never colour alone).
3. `GlowTile`:
   - Takes the metric colour, draws the §2 gradient, and comes in radius 24 or 28.
   - Its content sits in the dark core. A test proves `textPrimary`, and 13 pt labels at 78 %, reach ≥ 4.5:1 over the core for all three metric colours.
   - Under Reduce Transparency it draws flat `surface` with a 2 pt border in the metric colour.
4. `DotRow` and `TickRow` render as measured above and expose a summary accessibility label from the caller.
5. Buttons:
   - `CircleButton` has a hit target of at least 44 pt.
   - `PillButton` primary and secondary have disabled states and grow with Dynamic Type without clipping at AX3.
6. Every component has a dark `#Preview` at default size and AX3, and an entry in `DebugComponentCatalog`.
7. Zero warnings, Unit plan and `make lint` green. No user-facing strings inside the components beyond what callers pass in.

Verify: ui-validator (the catalog and previews against the measurements, AX3, Reduce Transparency) and code-reviewer.

### PR 3 — `design: orbit gauge v3 and launch` (branch `feat/nocturne-gauge`)
§3 rendering without model changes. ios-architect design note first, because the launch sequence is a state
machine plus timing at cold start. §5 launch from `RyftMarkGeometry`, played once per cold start, with a static
mark and cross-fade under Reduce Motion. The gauge and mark tests are re-pinned. performance-profiler checks
launch, because the sequence is on the cold start path.

| Ticket | Owner | Output |
|---|---|---|
| T3.0 Launch design note: where the sequence lives, its states, what skips it, the hand-off, seams for tests, the cold-start budget | ios-architect | `launch-design.md` (+ ADR 0017 if it decides something lasting) |
| T3.1 Visual spec: gauge v3 geometry and states; the launch timeline mapped to SwiftUI; Reduce Motion; accessibility | ui-designer | `design.md` "PR 3" |
| T3.2 Gauge v3 rendering, previews, catalog; re-pinned gauge tests | ios-developer | `OrbitGauge.swift` and its tests |
| T3.3 Launch sequence per T3.0 and T3.1 | ios-developer | new `Design/` or `App/` files, `RyftApp.swift` wiring |
| T3.4 Tests from the criteria | test-engineer | `RyftTests/`, `RyftUITests/` if needed |

T3.0 and T3.1 run in parallel (docs only, separate files); T3.2 → T3.3 → T3.4 in one worktree. Carried over: the
widget's `Brand` hexes are checked against the asset catalog (PR 1 review row 13).

**Measurements from the Today board** (gauge 260 × 260, centre 130; angles 0° = 3 o'clock, clockwise):

| Ring | Radius | Track | Arc |
|---|---|---|---|
| Outer, strain | 118 | tick ring: ticks 1.2 wide, 6 long, pitch 5.8 (1.2 + 4.6), `textPrimary` 16 % | 3.5 round, `metricStrain`, from −90° clockwise; 12.4 of 21 = 59 % ends at 122.6° |
| Middle, recovery and sleep | 88 | full ring 3.5 wide, `textPrimary` 7 % | 3.5 round. Split at the vertical as today: recovery from −96° counter-clockwise, sleep from −84° clockwise, each over at most 160° (14° short of the bottom). Recovery 82 % ends at −227° (133°); sleep 94 % ends at 66° |
| Inner, readiness | 58 | 60 ticks, 1.3 wide, 7 long, `textPrimary` 13 % | ticks up to the value in `textPrimary` (84 → 50 ticks, ending at −147.6°); a Volt dot r 5 with a 2.5 `background` ring at the value |

Arc end dots: r 7 in the metric colour with a 3 pt `background` ring, and a halo r 15 in the metric colour at 16 %.
Centre: `DotNumeral` (glyph gap 8) or Light digits at 52 pt. The "Readiness · High" line and the ruler under the gauge
are Today's layout (PR 4), not part of the gauge.

**Measurements from the Launch board** (5.2 s; the mark is 184 pt in the 100 box of `RyftMarkGeometry`, centred and
40 pt above the middle):
- Tracks: r 44 / 25.6 / 7.6, stroke 3.16, `textPrimary` 10 %. Dots: r 6. Easing `cubic-bezier(.45, 0, .15, 1)`.
- Timeline: brief §5. The colours are the metric colours until 76 %, then `textPrimary` by 86 %. The tracks are in from 6 %
  and gone at 74 %.
- Wordmark: "RYFT" 22 pt Light, 28 pt under the mark; tracking 0.9 em → 0.32 em from 74 % to 86 %, easing
  `cubic-bezier(.2, 0, 0, 1)`.
- Tagline: "Engineered for peak." 13 pt at 55 %, 64 pt above the bottom, fades in from 80 % to 88 %.
- VoiceOver: a status "Loading RYFT". The board's fade-out at 94–100 % belongs to its loop only.

**Lead decisions**
- **L1:** The launch never blocks the app. Startup work (auth restore, sync, Today's data) runs while it plays. A tap
  anywhere skips to the hand-off.
- **L2:** It plays only on a cold start into the foreground. It does not play on a background launch (HealthKit
  delivery, BG task), a return from the background, UI tests, screenshot runs, or `-RyftScreen` launch arguments.
  Demo mode plays it, so the user can see it.
- **L3 (designer Q1):** `OrbitGaugeSize` stays as it is in PR 3 (`.large` = 172). Previews and the catalog show 260 through
  `.custom`. The hero size comes with Today's layout in PR 4, because PR 3 changes rendering, not layout.
- **L4 (Q2):** The widget draws v3 through `Shared/`. Its catalog gets a `TextPrimary` colorset (D6: same tokens), and
  `check-shared-types.py` covers it. This also closes PR 1 review row 13 (the widget `Brand` hexes).
- **L5 (Q3):** The dots ride the arc end plus the mark's clear air (14.02° outer, 24.22° middle), as on the board, so
  the hold frame matches the board and the dots land in the mark's gaps.
- **L6 (Q4):** PR 3 hands off with a cross-fade; the logo's flight into the header comes with PR 4's header.
- **L7 (Q5):** The gauge gets an additive `numeral: .dots | .light` parameter (default `.dots`) in PR 3. PR 4 wires
  Today's switch to it.
- **L8 (Q7–Q9):** `Wordmark` gets an additive `tracking` parameter. `RyftMarkShape`'s arc and dot path builders become
  shared statics on `RyftMarkGeometry`, so the launch uses the same geometry. The wordmark is 28 pt below the 184 pt box.
- **L9 (architect O1):** The launch also skips when the app went to the background less than 10 minutes ago
  (`launch.lastBackgroundAt`). iOS often evicts a suspended app, and a reopen that feels like a return must not
  play 5.2 s; this is §5's intent.
- **L10 (O2):** Confirmed: launches with a purpose (URL, user activity, shortcut, notification), an open workout, root
  presentations, system UI and late activation skip or hand off at once; VoiceOver users get the reduced variant.
- **L11:** The reduced (Reduce Motion / VoiceOver) frame is the t = 1 frame: mark, wordmark and tagline.
- **L12:** Plain Xcode runs play the sequence (a tap skips); the shared scheme stays unchanged.
- To PR 4: the splash as the launch's last frame; whether only the mark or the whole lock-up moves into the header; and
  whether the gauge entrance starts with the move or after it lands (`launch-design.md` §14, questions 5–7).
- **L13 (user, 2026-11-16):** RYFT has one tagline, "Engineered for peak.". `BrandLockup` (Welcome, About) says it
  instead of "Your whole health.", which leaves the catalog and the README.

**Acceptance criteria**
1. **Gauge v3 renders the table above** for any `OrbitGauge` input, with the model unchanged. The tick rings scale with the
   side (`RyftMarkGeometry`-style metrics), and the tests that pin the gauge are re-pinned with the new numbers:
   - arc end angles for the board's values;
   - tick counts;
   - colours, with Volt only on the readiness dot;
   - contrast: arcs and dots ≥ 3:1 on `background`.
2. **The gauge keeps its VoiceOver sentence and its entrance** (`OrbitGaugeEntrance`), which now starts at the
   launch hand-off. Reduce Motion behaves as today.
3. **The launch follows §5's timeline within one frame of the keyframes**, from `RyftMarkGeometry` with no second
   geometry, and ends on the exact static mark.
   - A test samples the timeline at 0, 26, 50, 76, 86 and 100 % (angles, lengths, colours).
   - Under Reduce Motion it shows the static mark and wordmark, then cross-fades.
4. **It plays once per cold start and never in the cases in L2**, and a tap skips it. A unit test covers the state
   machine; a UI test proves that UI tests skip it.
5. **Cold start:** performance-profiler measures time to the first frame and to an interactive Today, with and
   without the sequence. The sequence adds no main-thread work before the first frame, and no dropped frames on
   an iPhone 17 Pro simulator.
6. **Hygiene:** dark `#Preview`s and catalog entries for gauge v3 and the launch at a scrubbed time. Zero warnings;
   Unit plan, `make lint` and `make style` green. New strings ("Engineered for peak.", "Loading RYFT") go
   into the catalog.

Verify: code-reviewer; ui-validator (the gauge against the board; the launch filmed or sampled frame by frame;
AX3; Reduce Motion); performance-profiler (criterion 5). The widget `Brand` check is part of code-review.

### PR 4 — `today and sleep in nocturne`; PR 5 — `strain, insights, profile in nocturne`
The §4 screens; the new tab bar is in PR 5. Missing data (the Insights hint, among others) comes from MockData
placeholders plus `docs/API_REQUESTS.md`. localization-editor for the new copy. ui-validator against each board.
Carried over from the PR 2 review (`review.md` rows 4, 9–13 and 17):
- `DotRow`: `today` is the trailing mark, and the caller's summary names it (position is the non-colour cue).
- Glow tiles wider than 350 pt or taller than 176 pt in recovery (Insights "An idea") set labels in full `textPrimary`;
  `paddedRectContrast` is extended to each concrete tile.
- Build zones from server data with `RulerScale.zone(lo:hi:)`, never `lo...hi`.
- Sleep's pending numeral passes `placeholder: "0:00"`, so the row keeps its width.
- The heart-rate zone block (five `TickRow`s) keeps one tick column: measure the longest label and stack all rows
  together if it is wider than 74 pt. `TickRow` has no hook for that yet: PR 5 adds one (e.g. `stacked: Bool` or an
  environment value), because each row's own `ViewThatFits` picks one line whenever that row fits. At AX3 the stacked ticks stay 177 pt wide, left-aligned: decide whether they span the width.
- **The glow edge is as bright as the board (user, 2026-11-16).** PR 4 switches `GlowTileSpec` to the board's ellipse
  (about 70 % metric colour in the 2-up corners) and sets labels in recovery glow tiles in full `textPrimary` instead of
  78 %, so §6's 4.5:1 still holds; the contrast tests are re-pinned. P2-D1 is superseded.

## Risks
- **The string catalog.** A local Xcode build re-serialised it in the user's checkout (8.7k lines, uncommitted on
  `chore/domain-ryftlab`). Every brief requires `make strings` or targeted edits, and a `--stat` check.
- **The icon render needs Satoshi Light locally.** The fonts are git-ignored; `make fonts` fetches them from
  Fontshare. The PNGs are committed, so CI does not render.
- **Pinned tests.** The gauge contrast, shots and mark tests pin today's colours; PR 1 and PR 3 re-pin them
  deliberately and say so in the PR.
