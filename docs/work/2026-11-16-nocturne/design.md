# Nocturne — design

Source of truth for the style: `brief.md` (NOCTURNE_STYLE v0.2). Plan and decisions D1–D7: `plan.md`. This file grows one
section per PR; ADR 0016 is written from §PR 1.

## PR 1 — tokens, type, icon

Scope: the colour sets of both asset catalogs, `Theme.swift`, `Typography.swift`, the wordmark, the fonts, the app
icon M1. No screen is restyled (PRs 4–5), no component is added (PR 2), the gauge is not redrawn (PR 3).
Mixed look on `main` until PR 5 is accepted (D5).

### 1. Decisions

| # | Decision | Why |
|---|---|---|
| T1 | **One value per colour set, no appearances.** Every `Contents.json` has a single `universal` entry. | Dark-only (§1, D6). A light/dark split would be dead data, and `check-shared-types.py` compares whole files, so one shape keeps the two catalogs trivially equal. |
| T2 | **Asset names stay.** `Accent` becomes the recovery teal. `Theme.recovery` is added as an alias of `Color("Accent")`; no `MetricRecovery` set. | No renames in PR 1. A second set for the same colour could drift. The alias lets PRs 2–5 write `recovery`, `metricSleep`, `metricStrain` as the legend. Callers of `accent` keep working: "one accent per screen" and "recovery" are the same teal. |
| T3 | **Legacy tokens are remapped, not removed.** Graphite, Mist, Slate and Teal take the Nocturne values of `background`, `textPrimary`, `surface`, `accent`. Sage and AccentSecondary keep their dark value. Nothing is deleted. | `Theme.graphite` (PlatformConfig, RestTimerView), `Theme.mist`/`sage` (RestTimerView) and `Color("…")` names in `Shared/` are still used. Remapping removes the old cooler greys without touching call sites. |
| T4 | **The track is one opaque token: `SurfaceRaised` = `#2F312F`, the 16 % track (`#F2F1EC`) composited over `background`.** | §2 gives 7–16 %; the mock-up uses 16 % outer, 7 % middle, 13 % inner. Until PR 3 the gauge has one track. `SurfaceRaised` has two jobs, track and fill behind content (27 of its 34 references are fills); opaque, it is the same pixel on every ground, so a fill's text contrast belongs to the token. 1.50:1 on `background` (1.49 for the exact 16 % composite before 8-bit rounding), the old opaque `#263137` was 1.45:1, so today's gauge keeps its weight. A translucent value (my first one) made every fill depend on what is underneath (ADR 0016 §2.5). PR 3 draws the 7 % and 13 % rings from `textPrimary.opacity(…)`. **Rule: a raised fill carries `textPrimary` or `textSecondary`, never `textTertiary`.** The catalog stores a literal; `NocturneTokenTests` pins it as `over(rgba(ink, 0.16), rgba(0x0A0C0B))`, so a change to `background` fails the test. |
| T5 | **Signal is for marks, never text** (§1). It has a doc comment saying so on `Theme.signal`. `OnSignal` exists for a filled signal dot with a glyph. | Rule from §1. |
| T6 | **The widget follows.** The widget catalog carries the same values (identical `Contents.json` where `Shared/` names a set), `Signal`/`OnSignal` are added to it for PR 3, and `Brand` in `RyftWidgets.swift` takes the Nocturne hexes and loses its light branch; the Readiness widget forces `.dark`. | D6. Without it a system-light widget would draw the now single-valued dark arcs on a Mist background. |
| T7 | **Titles and numbers Light, text Regular, buttons and row titles Medium; tabular digits on every style.** | §2. |
| T8 | **`ryftNumber` without a weight is Light from 20 pt and Regular below.** | Deviation, see §4. |

### 2. Colour sets, old → new

Old values are `any / dark` (light appearance first); the old files carried two values for all but the unchanged ones.
New values are the single appearance. `Ryft/` = app catalog, `RyftWidgets/` = widget catalog (`Shared/OrbitGaugePalette.swift`
names the sets marked ◆ in both).

| Colour set | Old (light / dark) | New | Notes |
|---|---|---|---|
| `Background` | `#E8E7E3` / `#0B0F0E` | `#0A0C0B` | §2 `background`. |
| `Surface` | `#F5F4F1` / `#1A2226` | `#121514` | §2 `surface`. |
| `TextPrimary` | `#0B0F0E` / `#E8E7E3` | `#F2F1EC` | |
| `TextSecondary` | `#0B0F0E`@60 % / `#E8E7E3`@60 % | `#F2F1EC`@62 % | |
| `TextTertiary` ◆ | `#0B0F0E`@60 % / `#E8E7E3`@55 % | `#F2F1EC`@**48 %** | Deviation D7, §4. Widget catalog too. |
| `Separator` | `#0B0F0E`@8 % / `#E8E7E3`@8 % | `#F2F1EC`@8 % | §2 gives 6–8 %; the upper end, the mock-up's. |
| `SurfaceRaised` (track, raised fill) ◆ | `#DAD9D4` / `#263137` | `#2F312F`, opaque | T4: the 16 % track flattened over `background`. 1.40:1 on `surface`. Widget catalog too. |
| `Accent` ◆ (recovery) | `#107561` / `#3FD1B4` | `#63D2B4` | §2 `recovery`. `Theme.recovery` aliases it. Widget catalog too. |
| `MetricSleep` ◆ | `#5B4FC9` / `#8F87F1` | `#9B8AF0` | §2 `sleep`. Widget catalog too. |
| `MetricStrain` ◆ | `#2E5BBF` / `#5B8DEF` | `#5E8BEA` | §2 `strain`. Widget catalog too. |
| `Signal` (new) | — | `#D8FF4F` | §2 `signal`. App and widget catalogs. |
| `OnSignal` (new) | — | `#0A0C0B` | §2 `onSignal`. App and widget catalogs. |
| `OnAccent` | `#FFFFFF` / `#0B0F0E` | `#0A0C0B` | Text on a teal fill: 10.7:1. |
| `Graphite` | `#0B0F0E` / `#0B0F0E` | `#0A0C0B` | = `Background`. T3. |
| `Mist` | `#E8E7E3` / `#E8E7E3` | `#F2F1EC` | = `TextPrimary`. T3. |
| `Slate` | `#1A2226` / `#1A2226` | `#121514` | = `Surface`. T3. Unused in the app today. |
| `Teal` | `#3FD1B4` / `#3FD1B4` | `#63D2B4` | = `Accent`. T3. Unused in the app today. |
| `Sage` | `#6EA89A` / `#6EA89A` | `#6EA89A` | Unchanged; used by the rest timer's zones. |
| `AccentSecondary` | `#3E6F65` / `#6EA89A` | `#6EA89A` | Its dark value. Info insights and HRR zone 2. The only hue off the legend; PR 5 reworks the zones. |
| `Warning` ◆ | `#7E6316` / `#E3C25B` | `#E3C25B` | Dark value. Band "moderate". Widget catalog too. |
| `Alert` ◆ | `#B04436` / `#E36B5B` | `#E36B5B` | Dark value. Band "low". Widget catalog too. |
| `StageAwake` | `#A3AFC2` / `#B8C4D6` | `#B8C4D6` | Dark value. Hypnogram is PR 4. |
| `StageLight` | `#4F7BE8` / `#4F7BE8` | `#4F7BE8` | Unchanged. |
| `StageDeep` | `#2F55D4` / `#2F55D4` | `#2F55D4` | Unchanged. 2.95:1 on `surface`: see §3. |
| `StageREM` | `#7FA3F2` / `#8FB3FF` | `#8FB3FF` | Dark value. |
| `AccentColor` (widget) | empty | empty | Kept empty. Giving it the teal makes Xcode warn that its symbol `accent` collides with the `Accent` set (a new warning in the widget target). The widget's accent is drawn from `Accent` in code. |
| `WidgetBackground` (widget) | empty | `#0A0C0B` | The widget's default background (`ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME`). |

`Theme.swift` additions: `signal`, `onSignal`, `recovery`. Doc comments say what each is for and drop "adapts to light/dark".

### 3. Contrast (WCAG 2.x; text and graphics composited in sRGB over the ground)

Grounds: `background` `#0A0C0B`, `surface` `#121514` (1.07:1 above the screen: a step, not a second background).

| Token | On `background` | On `surface` | Needs |
|---|---|---|---|
| `textPrimary` `#F2F1EC` | 17.35 | 16.24 | 4.5 |
| `textSecondary` @62 % | 6.95 | 6.78 | 4.5 |
| `textTertiary` @48 % | 4.54 | 4.54 | 4.5 |
| `textTertiary` @45 % (the style) | 4.12 | 4.13 | fails |
| `recovery` `#63D2B4` | 10.66 | 9.98 | 3 |
| `sleep` `#9B8AF0` | 6.81 | 6.38 | 3 |
| `strain` `#5E8BEA` | 5.94 | 5.56 | 3 |
| `signal` `#D8FF4F` | 17.13 | 16.04 | 3 |
| `warning` `#E3C25B` | 11.34 | 10.62 | 3 |
| `alert` `#E36B5B` | 6.09 | 5.70 | 3 |
| `accentSecondary` `#6EA89A` | 7.22 | 6.76 | 3 |
| `onAccent` on `accent` | 10.66 | | 4.5 |
| `onSignal` on `signal` | 17.13 | | 4.5 |

Today's dark values pass too (`#3FD1B4` 10.27, `#8F87F1` 6.45, `#5B8DEF` 6.07 on `background`), so the metric colours were
not changed for contrast; see D-b.

Outside the contract, known: `StageDeep` `#2F55D4` is 3.15:1 on `background` and **2.95:1 on `surface`** (under 3).
It was this value in both appearances before. The hypnogram is redrawn in PR 4 in the sleep colour; that PR fixes or drops it.

Track and raised fill, `SurfaceRaised` `#2F312F` (the gauge's own test prints the arc numbers): 1.50:1 on `background`, 1.40:1 on
`surface`. On it: `textPrimary` 11.60, `textSecondary` 5.50 (both ≥ 4.5), **`textTertiary` 3.94 (under 4.5)**; recovery, sleep, strain
arcs 7.12, 4.55, 3.97 and alert, warning 4.07, 7.58, all over 3:1. Hence the rule in T4: no `textTertiary` text on a raised fill.
Glyphs and outlines in `textTertiary` on it pass as graphics (3:1).

### 4. Deviations

| # | From | To | Number and reason |
|---|---|---|---|
| D-a | §2 `textTertiary` @45 % (plan D7) | **@48 %** | 45 % is 4.12:1 on `background` and 4.13:1 on `surface`: under 4.5 for 11–12 pt. The step ratio is 4.26 at 46 %, 4.40 at 47 %, **4.54 at 48 %** (both grounds), so 48 % is the lowest whole percent that passes on both. A ±1/255 rounding of the composite moves the ratio by about 0.04, so 48 % has a small margin; do not go below it. Today's catalog had 55 % dark, so the secondary-to-tertiary step is still deliberate but smaller than the mock-up's. |
| D-b | §2 "the three metric colours are today's ring colours, slightly desaturated; check against the assets and change only where contrast or consistency demands" | The mock-up's hexes `#63D2B4`, `#9B8AF0`, `#5E8BEA` (Δ to today's dark: teal +36 R, +1 G, 0 B; sleep +12 R, +3 G, −1 B; strain +3 R, −2 G, −5 B) | Not forced by contrast (today's pass 6+). Taken for consistency with the approved canvas, which is what the screens and the icon are measured against. If the lead wants today's values back, change the three `Contents.json` and the pins in `NocturneTokenTests`; nothing else depends on them. |
| D-c | §2 `track` @7–16 % | one opaque token, `#2F312F` (16 % over `background`) | T4. Opaque rather than alpha so fills behind text have one contrast on every ground; the pixel on the screen is the same as §2's 16 % track. 7 % and 13 % come in PR 3. |
| D-d | §2 `separator` @6–8 % | @8 % | The mock-up's. |
| D-e | §2 "Tile value 26–34", "Body 15–17", "Caption/scale 11–12": the sizes of the roles | `callout` 14 → 15, `metric` 22 → 26, `numberLarge` 40 → 34, `display` 56 → 52, `headline` 18 → 17, `axis` 10 → 11, `label` 11 → 13 | Each moved only as far as the nearest end of its §2 range. `callout` is used 236 times and grows 1 pt; the AX3 previews and tests were run. `display` 52 is §3's "Light digits 52 pt". |
| D-f | §2 "numbers Light" | `ryftNumber(size:)` without a weight: Light from 20 pt, Regular below (`RyftFonts.lightFloor`) | Light strokes under 20 pt on `#0A0C0B` are about one device pixel: the 9–19 pt scale labels stay Regular. Callers that pass a weight keep it: the kg and reps inputs and read-only values in `ExerciseCard` pass `.regular` at their 20–30 pt `numeral` sizes, so one set row does not mix Light kg/reps with Regular RPE. |
| D-g | §2 "Label 13 (`textSecondary`)" and "keine Versal-Labels" | `.label` is 13 Regular, sentence case, no tracking; `ryftLabelStyle` loses `.textCase(.uppercase)` and `.tracking(2)`; MetricGauge's centre title (was 9 pt uppercase tracked) is 11 pt sentence case | 9 pt is under the scale's 11. The BrandLockup tagline lost its `.tracking(4)`. |
| D-h | §1 Wordmark "Laufweite 0.32 em" | 0.32 em, and the trailing tracking is pulled back with a negative trailing padding | CSS letter-spacing adds space after the last letter; without the pull-back a centred wordmark sits 0.32 em left of centre. The icon uses the same rule (ink centred). |
| D-i | Icon "Dark/Tinted identical" | Three PNGs, byte-identical | The appiconset keeps its three slots so Xcode needs no change. |

Not deviations, recorded so ADR 0016 has them: `Theme.Metrics` radii and padding are untouched (PR 2). The
two `.textCase(.uppercase)` in `Features/Train/Session/ExercisePage.swift` were T1.2'"'"'s and are gone with its merge.

### 5. Type scale → roles (`Typography.swift`)

| §2 | Role (`RyftTextStyle`) | Size | Weight | Scales with |
|---|---|---|---|---|
| Hero digits (§3) | `.display` | 52 | Light | fixed (inside rings) |
| Tile value, large | `.numberLarge` | 34 | Light | fixed |
| Title 26 | `.title` | 26 | Light | `.title` |
| Tile value 26–34 | `.metric` | 26 | Light | `.title2` |
| (row title, emphasis) | `.headline` | 17 | Medium | `.headline` |
| Body 15–17 | `.body` | 16 | Regular | `.body` |
| Body, secondary | `.callout` | 15 | Regular | `.callout` |
| Button | `.button` (new) | 16 | Medium | `.body` |
| Label 13 | `.label`, `.ryftLabelStyle()` in `textSecondary` | 13 | Regular | `.footnote` |
| Caption 11–12 | `.caption` | 12 | Regular | `.caption` |
| Scale 11–12 | `.axis` (chart ticks) | 11 | Regular | `.caption2` |
| Tab 11 | `.tab` (new) | 11 | Regular | `.caption2` |
| Wordmark | `.wordmark` | 15 | Light | `.headline` |

Every `Font.ryft` and `Font.ryftNumber` is `.monospacedDigit()` (Satoshi ships `tnum` figures; the SF Pro Rounded fallback has them).
`RyftFonts.postScriptName` maps `.light`, `.thin`, `.ultraLight` to `Satoshi-Light`. `.button` and `.tab` have no callers yet:
`TealButtonStyle` and the tab bar adopt them in PRs 2 and 5. "Tile labels 13 at 78 %" and "subtitle 13 at 62 %" are colours at the call
site (`textPrimary.opacity(0.78)` / `textSecondary`), not roles.

Hand-over to PR 2 (from the mock-ups, not in code yet): inactive ticks `#F2F1EC` @22 %; scales `textTertiary`.

### 6. Wordmark

`Wordmark` (in `Design/RyftHeader.swift`, already the one place "RYFT" was drawn) is now Satoshi Light, 0.32 em, 15 pt by
default, with the trailing tracking pulled back (D-h). `WordmarkLockup` is new: orbit mark 26 pt, 10 pt gap, wordmark 15 pt,
all scaling with `markSize`. It is not on any screen yet (PR 4's header). `RyftHeader` and `BrandLockup` keep their layout and take
the new weight. Previews: "Header" and "Wordmark lock-up" (dark), "Wordmark lock-up · AX3".

VoiceOver: the lock-up is one element, label "RYFT", header trait. Dynamic Type: the wordmark is fixed-size like the mark (a brand
mark, not text); the lock-up does not grow at AX3.

### 7. Fonts

`scripts/fetch-fonts.sh` and the archive check in the Makefile now cover Light, Regular, Medium, Bold. `Info.plist` `UIAppFonts`
gains `Satoshi-Light.otf` (PostScript name `Satoshi-Light`, checked in the file's name table). `LicensesView`'s Satoshi entry names
the four weights. The files stay git-ignored.

### 8. App icon M1

The mock-up: 220 px tile, "RYFT" 60 px Light, letter-spacing 0.02 em, left padding 0.02 em. At 1024: 60/220 = 27.27 % → **279.3 px**
(§1 says ≈ 280). Tile `Background` `#0A0C0B`, word `TextPrimary` `#F2F1EC`, 17.35:1, both read from the catalog by
`scripts/icon-spec.swift`. Drawn with CoreText from `Ryft/Resources/Fonts/Satoshi-Light.otf`; a missing file or a font that is not
`Satoshi-Light` exits 1 (no fallback face).

Placement: the ink (the letters' outline) is centred horizontally, which is what the mock-up's equal left padding does for the
advance box; the cap height (198.3 px) is centred vertically (R, Y, F, T are flat: ink = cap height). Measured margins:
left 209 / right 209 / top 413 / bottom 413 px, read off the rendered bitmap (the ink is the pixels at least half way to the word colour); the renderer fails if either pair differs by more than 1 px. The glyph origin is rounded to whole pixels because a bitmap context snaps it. The word is
606 px wide, 59 % of the tile.

Light, Dark, Tinted: the same image (`cmp` equal). The tinted slot gets a near-black tile with a light word, which iOS
re-tints; no separate grayscale is needed.

`make icon` writes the three 1024 PNGs and, for review, 180/120/60/40 px versions into `build/icon-preview/`
(Core Graphics, high-quality interpolation; no `sips`). The old comparison variants (ring-span 0.915/0.963/0.80, `--dots`, `--mono`)
and `--ring-span`/`--suffix` are gone, with the mark's geometry no longer compiled into `render-icon`.

**`design/ryft-app-icon-{light,dark}.svg` are deleted and no longer generated.** No consumer: a grep over `app/` and
`plattform/` finds only the Makefile, `scripts/`, and history in `docs/STATUS.md` and the 2026-10-28 plan. Generating them from the
wordmark would need outlined glyph paths from the git-ignored font in `make lint` (`check-mark-svg` runs on CI without the font), or
a committed outline that can drift from the PNGs. `design/ryft-mark.svg` stays (the mark is still the logo), is still generated from
`RyftMarkGeometry` and checked by `make lint`; `mark-svg.swift` no longer includes `icon-spec.swift`.

### 9. Tests

New: `RyftTests/NocturneTokenTests.swift` (token values ±1/255 and alpha, appearance independence, the legend, text ≥ 4.5:1 and
metric/signal ≥ 3:1 on both grounds, the 45 → 48 % derivation, the type scale, `Satoshi-Light` in `UIAppFonts`).

Re-pinned (reasons are the appearance change only; no assertion is weakened otherwise). `SurfaceRaised` is opaque, so no test needs to
composite the track over a ground (the token is opaque, and the alpha check in `NocturneTokenTests` is what guards that):

| Test | Change | Reason |
|---|---|---|
| `OrbitGaugeContrastTests`, `OrbitGaugeBandTests` | Dark only; the light-only expectation (Sleep/Strain at 0.6 under 3:1) is replaced by its dark equivalent: Sleep and Strain at 0.6 over the track (2.58, 2.34) and Strain on the background (2.81) are under 3:1, Recovery is not | There is no light scheme, and the pending test keeps asserting what its name says. Thresholds unchanged (3:1, 4.5:1). The 16 % track pixel is `#2F312F`: recovery, sleep, strain 7.12, 4.55, 3.97 on it. |
| `OrbitGaugeRenderTests`, `OrbitGaugeBandRenderTests`, `OrbitGaugeShotsTests`, `OrbitGaugeEntranceTests`, `OrbitEntranceTimelineTests` | Scheme loops dark only | There is no second appearance; the "light" shots were the same colours. Pixel expectations unchanged. |

`NocturneTokenTests` pins `surfaceRaised` as `over(rgba(ink, 0.16), rgba(screen))`, where `screen` is the constant the `background` row uses, and has a contract row: `textPrimary` and
`textSecondary` ≥ 4.5:1 on it (and `textTertiary` under 4.5 and over 3, the reason for the rule).

Dead `.light` branches removed in PR 1 (the app is dark-only, so they could only mislead): `FocusedRowInk` (`estimate()`,
`upcomingOutline()` lose their scheme parameter), `ExerciseCard.raisedFill` (now `Theme.surfaceRaised`) and its `colorScheme`
environment, `SourceBadge`'s light outline. The "Light:" cases in `FocusedPolishTests` are gone; its dark cases stay, as dark-only
tests. The comment in `FocusedRowInk.value` now says 3.94:1 (it said 4.40:1).

Not changed: the screenshot tests that render a light variant (`FocusedSessionShotsTests`, `HostedAccessibility`,
`ImportScreenshotTests`, `FocusedPolishHostedTests`). They pass (light resolves to the same dark tokens); removing the light
variants is PR 5's.

`textTertiary` on a raised fill (the rule in T4), rechecked against `#2F312F`:
- **Text, changed to `textSecondary` (5.50:1; `textTertiary` was 3.94:1 there, 4.40:1 before PR 1):** the strain pill's empty
  placeholder (`StrainComponents.swift`, `StrainPill`) and the report form's prompt (`ProfileView.swift`, "What happened? …").
- **Glyphs and outlines, cleared as graphics at 3:1 (3.94:1):** the radio circle in `Card.swift`'s selectable row, `SourceBadge`'s
  glyph (decorative), `MyDayRow`'s missing-sleep icon (hidden from VoiceOver), `ExerciseCard`'s unchecked-set mark, `ProfileView`'s
  disabled stepper glyph (a disabled control is exempt anyway).
- Fields and other raised fills that carry `textPrimary` or `textSecondary` are above 4.5:1 by the contract row.

`RyftTests/NocturneShotsTests.swift` writes the board (swatches, type scale, wordmark lock-up at default size and AX3) into
`NOCTURNE_SHOTS_DIR` when `TEST_RUNNER_NOCTURNE_SHOTS_DIR` is set; otherwise it does nothing.

### 10. Previews

Dark only in the files PR 1 touches (D3): `MetricGauge`, `RyftHeader`, `LicensesView`, and the widget galleries. `DarkPreview`
(`Preview/PreviewSupport.swift`) is the new single-appearance wrapper; `SchemePair` stays for files not yet touched. Left for
later PRs: `RyftMark.swift`'s "Mark · light" preview (PR 3).

### 11. What PR 1 does not verify

The widget on a device in system-light mode (forced `.dark` in code, not seen). The App Store's icon mask and the tinted icon on the
Home Screen were not seen.

Fonts: the test and TestFlight jobs run `make fonts` (`.github/actions/setup/action.yml`), so CI has Satoshi; only the Lint job has no
fonts, and lint does not need them. The real gap is a local or agent run without the font files: `Font.ryft` then falls back to SF Pro
Rounded and its fallback branch (`Typography.swift`, the `.system(…)` returns) takes the role's weight but ignores the role's
size for the Dynamic-Type-relative styles, so a screenshot from such a run does not show the §2 sizes. **Follow-up, not PR 1.**

Not in PR 1: the widget `Brand` hexes are not checked against the catalog (PR 3); the Sleep segment control truncates at AX3 (PR 4).

## PR 2 — components

Scope: seven new files in `Ryft/Design/` (+ additive `Theme.Metrics` constants, §P2-8), previews, catalog sections, tests. No existing
component and no screen is modified (§P2-9). Measurements are `plan.md` §PR 2 (390 pt boards, CSS px = pt); the brief wins where they
disagree. Rules for every component:

- **No strings inside.** Callers pass text, labels, values and accessibility text. The only glyph literals are `–` (the numeral's
  placeholder) and SF Symbol names passed by callers.
- **Tokens only:** `Theme.*` colours and `Theme.Metrics`, `Font.ryft(_:)` roles; opacity steps are named constants in the component.
- **Pure layout first.** Every geometry rule is a non-isolated `static func` on a non-generic type, so tests assert numbers, not pixels.
  Generic types cannot hold static stored properties, hence `GlowTileSpec`.
- **Test/preview seams** (the repo cannot set `accessibilityReduceMotion` in an environment, see `OrbitGauge`):
  `reduceMotion: Bool? = nil` and `reduceTransparency: Bool? = nil` init parameters; `nil` follows the system.

| Component | File | Type |
|---|---|---|
| `DotNumeral` | `DotNumeral.swift` | `DotGlyph`, `DotGlyphs`, `DotNumeral` |
| `RulerScale` | `RulerScale.swift` | `RulerScale` |
| `GlowTile` | `GlowTile.swift` | `GlowTileSpec`, `GlowTile<Content>`, `View.ryftGlowLabelStyle()` |
| `DotRow` | `DotRow.swift` | `DotRow` |
| `TickRow` | `TickRow.swift` | `TickRow` |
| `CircleButton` | `CircleButton.swift` | `CircleButton` (+ private style) |
| `PillButton` | `PillButton.swift` | `PillButton` (+ private style) |

### P2-1. DotNumeral

```swift
struct DotGlyph: Equatable { let width: Int; let rows: [UInt8] }   // 7 rows, bit (width-1-c) = column c, MSB left

enum DotGlyphs {
    static let rowCount = 7
    static let table: [Character: DotGlyph]                          // the table in §P2-5
    static func glyphs(for text: String) -> [DotGlyph]?              // nil if any character is outside the table
    static let placeholder: DotGlyph                                 // one blank 5-wide cell
    static func pendingGlyphs(for template: String) -> [DotGlyph]    // the template's glyphs, all unlit; unknown characters dropped; empty → [placeholder]
}

struct DotNumeral: View {
    enum Style { case dots, light }
    static let dot: CGFloat = 5, dotGap: CGFloat = 2, height: CGFloat = 47      // 7·5 + 6·2
    static let glyphGapToday: CGFloat = 8, glyphGapDetail: CGFloat = 7          // Today / Sleep, Strain
    static let offOpacity = 0.10, lightSize: CGFloat = 52
    static func size(of text: String?, placeholder: String = "00", glyphGap: CGFloat) -> CGSize?   // nil = not in the table
    static func pendingText(for template: String) -> String                     // "0:00" → "–:––" (P2-D10)
    static func rendersDots(_ text: String?, style: Style, typeSize: DynamicTypeSize) -> Bool
    init(_ text: String?, style: Style = .dots, glyphGap: CGFloat = DotNumeral.glyphGapToday,
         placeholder: String = "00", accessibilityLabel: Text)
}
```

`text` is an already formatted numeral from the caller ("84", "7:48", "12.4", "12,4": the region's separator). `nil` is the pending state.

**Geometry.**

| Quantity | Rule |
|---|---|
| Glyph width | `w·5 + (w−1)·2`: 5 columns = 33 pt, 1 column = 5 pt. Height 47. |
| Glyph pitch | next glyph's left edge = this glyph's right edge + `glyphGap` (8 Today, 7 Sleep/Strain), for narrow glyphs too. |
| Total | `Σ glyph widths + (n−1)·glyphGap` × 47. `"84"` 74×47; `"7:48"` 128×47 (gap 8) / 125×47 (gap 7); `"12.4"` 128 / 125; `"0"` 33×47; `":"` 5×47. |
| Dot centre | `(x₀ + c·7 + 2.5, r·7 + 2.5)`, `x₀` = glyph's left edge, `c` = column, `r` = row from the top. Diameter 5. |
| Layers | Unlit cells in `textPrimary` at 10 % first, lit cells in `textPrimary` on top, as two `Shape`s (or one `Canvas`). Drawn, not a font. |
| Scaling | The grid is **fixed size** (a graphic, like `display`): never scales with Dynamic Type below AX1. |

**States.**

| State | Trigger | Rendering |
|---|---|---|
| Value | every character in the table, `style == .dots`, size below AX1 | the dot grid |
| Light | `style == .light`, **or** `typeSize.isAccessibilitySize` (AX1 and up), **or** any character outside the table (also a space, an empty string) | `Text(text)` in `Font.ryftNumber(size: s, weight: .light)`, `textPrimary`, `lineLimit(1)`, `minimumScaleFactor(0.5)`. `s` is `@ScaledMetric(relativeTo: .largeTitle) 52`: exactly 52 at the default size, larger from AX1 (about 1.5× at AX3) |
| Pending | `text == nil` | the `placeholder` template's glyphs (`DotGlyphs.pendingGlyphs(for:)`), every dot at 10 %, so pending is as wide as the loaded value (`"0:00"` = `"7:48"`); characters outside the table are dropped, an empty result draws one blank digit cell. In the Light fallback `pendingText(for:)` (digits → `–`, separators kept) at `textTertiary`. The caller's label says "no value yet" |

**Accessibility.** `accessibilityElement(children: .ignore)` + `accessibilityLabel(accessibilityLabel)`, in every state and in the fallback
("Readiness 84 of 100", "7 hours 48 minutes asleep", "Strain 12.4 of 21"). No traits, no value.
Contrast: lit dots `textPrimary` 17.4:1; the 10 % grid is decoration (1.24:1) and carries nothing.

### P2-2. RulerScale

```swift
struct RulerScale: View {
    enum Size { case regular, compact }
    enum Ticks { static let today = 61, sleep = 61, strain = 64, strainCompact = 43 }
    static let needleColor = Theme.signal
    init(range: ClosedRange<Double>, value: Double?, zone: ClosedRange<Double>? = nil,
         zoneStyle: ZoneStyle = .standard, tickCount: Int,
         labels: [String] = [], size: Size = .regular,
         accessibilityLabel: Text, accessibilityValue: Text, reduceMotion: Bool? = nil)

    static func tickCentres(count: Int, width: CGFloat) -> [CGFloat]
    static func zoneTickIndices(count: Int, range: ClosedRange<Double>, zone: ClosedRange<Double>?) -> [Int]
    static func zone(lo: Double?, hi: Double?) -> ClosedRange<Double>?   // nil unless both finite and lo ≤ hi: use for server data
    static func labelOpacity(size: Size, dynamicTypeSize: DynamicTypeSize) -> Double?   // nil = textTertiary
    static let labelMinGap: CGFloat = 16
    struct ZoneStyle { let tint: Color; let fixedOpacity: Double?   // private init; presets .standard, .sleep, .strain only
        func opacity(for size: Size) -> Double }
    static func needleX(value: Double?, range: ClosedRange<Double>, width: CGFloat) -> CGFloat?
}
```

`ZoneStyle.standard` is `textPrimary` at 0.55 regular, 0.60 compact; `.sleep` is `metricSleep` at 0.85, `.strain` `metricStrain` at 0.95 (P2-D11).
Width is whatever is proposed (the ruler fills it); height is fixed per size.

**Geometry** (y from the top of the ruler; ticks and needle are fixed-size graphics, never scaled):

| | Regular | Compact (strain tile) |
|---|---|---|
| Ruler height | 36 = 8 top + 22 tick row + 6 bottom | 32 = 8 + 18 + 6 (**derived**, not measured) |
| Tick row | y 8…30, ticks centred vertically | y 8…26 |
| Outside the zone | 1 × 8, `textPrimary` 22 % (compact: 1 × 7, 26 %) | |
| Inside the zone | 1.5 × 14, `zoneStyle.tint` at `zoneStyle.opacity(for:)` (compact: 1.5 × 12, 60 %) | |
| Needle | triangle 12 × 8 pointing down, apex y 8; line 1.5 × 20, y 8…28; `Theme.signal` | line 16 (y 8…24); triangle as regular (**derived**) |
| Labels | under the ruler, `Font.ryft(.axis)` (11), `textTertiary`, spread edge to edge, at least `labelMinGap` (16) apart, else one joined " · " line | `textPrimary` at `GlowTileSpec.labelOpacity(for:)`, because the compact ruler sits in a glow tile (P2-D12) |

- **Ticks.** `n = max(tickCount, 2)`. Tick `i` is centred at `x_i = i / (n − 1) × width`; its rect is `x_i − w/2`. The outer ticks
  overhang by ≤ 0.75 pt, so the view must not clip. Drawing snaps the rect's x to the device pixel; `tickCentres` returns the unsnapped values.
- **Value of tick `i`:** `lo + Double(i) · (hi − lo) / Double(n − 1)` (multiply first: 30·21/63 = 10 exactly). Tick counts are chosen so zone
  edges land on ticks.
- **Zone ticks:** `v_i` in `zone` ± 1e-9. Today (0…100, 67…100) → indices 41…60 (20 ticks). Sleep (0…10, 7.5…8.3) → 45…49 (5). Strain
  (0…21, 10…14) → 30…42 (13). Compact strain (43 ticks) → 20…28 (9). `zone == nil` → none. A zone that overlaps the range but contains
  no tick value marks the one tick nearest its midpoint (clamped into the range; a tie goes to the higher tick), so the zone never
  disappears while VoiceOver names it: `(61, 0...100, 50.5...51)` → `[30]` (midpoint 50.75, position 30.45), `50.9...51.1` → `[31]`.
  The position is rounded as `(position + 1e-9).rounded()`, so a floating-point tie such as 25.499999999999996 still goes up. A zone
  wholly outside the range marks none.
- **Needle x:** `clamp((value − lo) / (hi − lo), 0, 1) · width`; `nil` for `value == nil`, NaN or `hi ≤ lo`. The needle's centre is clamped, its
  triangle may overhang 6 pt (padding of the parent contains it).
- **Labels:** `[String]` in one line, distributed edge to edge (first leading, last trailing, the rest evenly spaced), the board's
  "0 · low · moderate · high · 100". Placement under the zones is **not measured**; space-between is assumed. If they do not fit on one
  line (AX), `ViewThatFits` falls back to the strings joined by " · ", wrapping, leading-aligned.

**States.** Value (needle + zone); **no value** (`value == nil`): ticks, zone and labels stay, no needle, the caller's value text says "no value yet";
**no zone**: all ticks outside; **clamped**: a value outside the range sits on the end, and the caller's value text keeps the real number.
State is never colour alone: the needle's position, the zone's longer and thicker ticks, the band word in `labels` and the sentence.

**Motion.** Only the needle moves: `.animation(Theme.Motion.respecting(reduceMotion ?? system, Theme.Motion.quick), value: value)` on its x (250 ms
ease-out); first appearance does not animate; Reduce Motion: it jumps.

**Accessibility.** One element (`children: .ignore`): label = the subject ("Readiness scale"), value = the caller's sentence, which
must carry value, band word and range ("84, high, on a scale from 0 to 100"). Labels and ticks are not separate elements.
Labels scale with Dynamic Type, the graphic does not.

### P2-3. GlowTile

```swift
enum GlowTileSpec {
    enum Radius { case tile, hero                                // 24 (Today 2-up) / 28 (Sleep, Strain hero)
        var points: CGFloat }                                    // Theme.Metrics.glowTileRadius / heroTileRadius
    static let stops: [Gradient.Stop]                            // background @ 0.97 / 0.92 / 0.55 / 0.10 at 0 / 0.34 / 0.68 / 1
    static let ellipse = (rx: 0.90, ry: 1.10, cy: 0.55)          // fractions of width, height, height
    static let padding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    static let twoUpMinHeight: CGFloat = 124, heroMinHeight: CGFloat = 172
    static let labelOpacity = 0.78, flatBorder: CGFloat = 2
    static func overlayOpacity(atRadiusFraction t: Double) -> Double   // piecewise linear through `stops`, 0.10 beyond 1
}

struct GlowTile<Content: View>: View {
    init(_ metric: Color, radius: GlowTileSpec.Radius = .tile, minHeight: CGFloat? = nil,
         reduceTransparency: Bool? = nil, @ViewBuilder content: () -> Content)
}
extension View { func ryftGlowLabelStyle() -> some View }       // Font.ryft(.label), textPrimary at GlowTileSpec.labelOpacity(for:): 78 %, 100 % from AX1
```

**Drawing, back to front.** `RoundedRectangle(cornerRadius: radius.points, style: .continuous)` filled with `metric`; the overlay;
content inside `padding`, `.topLeading`, default `foregroundStyle(Theme.textPrimary)`. No shadow, no border. Clipped to the same shape.

**The CSS ellipse.** `radial-gradient(ellipse 90% 110% at 50% 55%, …)` has radii `rx = 0.90·W`, `ry = 1.10·H` (of the box, not the
tile's diagonal), centre `(0.5·W, 0.55·H)`, `0 %` at the centre and `100 %` on the ellipse, the last colour beyond. In SwiftUI:

```swift
Canvas { ctx, size in
    ctx.translateBy(x: size.width * 0.5, y: size.height * 0.55)
    ctx.scaleBy(x: size.width * 0.90, y: size.height * 1.10)        // unit circle becomes the ellipse
    ctx.fill(Path(CGRect(x: -4, y: -4, width: 8, height: 8)),       // covers the tile in unit space
             with: .radialGradient(Gradient(stops: GlowTileSpec.stops), center: .zero, startRadius: 0, endRadius: 1))
}
```

The stops use `Theme.background.opacity(…)`. `EllipticalGradient` is not used: the Canvas form fixes the radii exactly. The ellipse is **not a
parameter**: it is the dark end of the measured ranges (85–90 % × 80–110 % at 50–55 %), see deviation P2-D1. The overlay opacity at `t`
(0 centre, 1 ellipse): `0.97, 0.92 (0.34), 0.746 (0.5), 0.55 (0.68), 0.10 (1)`.

**Contrast in the core** (WCAG; `textPrimary` and `textPrimary` at 78 % composited over the pixel; `background` over the metric colour):

| Region | Recovery | Sleep | Strain | Needs |
|---|---|---|---|---|
| Core, `t ≤ 0.60`: worst pixel, primary / label | 7.55 / 5.33 | 9.42 / 6.46 | 10.02 / 6.80 | 4.5 |
| Padded rect, worst corner, 169 × 124 (`t` 0.601) | 7.54 / 5.32 | 9.41 / 6.45 | 10.00 / 6.79 | 4.5 |
| Padded rect, 350 × 120 (0.640) | 6.67 / 4.79 | 8.56 / 5.95 | 9.17 / 6.30 | 4.5 |
| Padded rect, 350 × 168 (0.659) | 6.30 / 4.56 | 8.17 / 5.72 | 8.79 / 6.08 | 4.5 |
| Padded rect, 350 × 176 (0.662) | 6.25 / 4.53 | 8.13 / 5.69 | 8.75 / 6.05 | 4.5 |
| `t` where the 78 % label drops to 4.5 | 0.664 | 0.753 | 0.785 | |

Recovery is the limit. **Known limit:** a recovery tile wider than 350 pt or taller than 176 pt (390 × 176: 4.48; 350 × 260: 4.35) puts the
outer corner under 4.5:1 for a 78 % label there. A recovery tile that large (Insights "An idea", at AX3) sets such a label at
`textPrimary` (≥ 6.2) or keeps text off the corners; PR 4/5 checks it.

**Reduce Transparency** (`reduceTransparency ?? system`): no gradient, fill `Theme.surface`, `strokeBorder(metric, lineWidth: 2)` inside the shape,
same radius and padding. Contents: `textPrimary` 16.2:1, 78 % label 10.1:1 on `surface`.

**Dynamic Type.** The tile is content-sized with `minHeight` (never a fixed height): it grows at AX3, the gradient follows because it is
fractional. Radius and padding are fixed. **Accessibility:** `children: .contain`; the tile adds no element and no label, the colour is decoration.

### P2-4. DotRow, TickRow, CircleButton, PillButton

```swift
struct DotRow: View {
    enum Mark { case full, missed, today }
    static let dot: CGFloat = 6, gap: CGFloat = 4, outlineOpacity = 0.5
    static func size(count: Int) -> CGSize                       // (n·6 + (n−1)·4) × 6; 0 dots: .zero
    init(_ marks: [Mark], accessibilityLabel: Text)
}

struct TickRow: View {
    static let tickCount = 30, tick = CGSize(width: 3, height: 12), tickGap: CGFloat = 3, rowSpacing: CGFloat = 9
    static let labelWidth: CGFloat = 74, valueWidth: CGFloat = 40, unlitOpacity = 0.12
    static func litCount(minutes: Double?, scaleMax: Double) -> Int      // 0…30
    init(label: Text, minutes: Double?, scaleMax: Double, value: Text, accessibilityLabel: Text)
}

struct CircleButton: View {
    static let diameter: CGFloat = 40, hitSize: CGFloat = 44, iconSize: CGFloat = 14
    static let borderOpacity = 0.16, disabledIconOpacity = 0.35
    init(systemImage: String, accessibilityLabel: Text, action: @escaping () -> Void)
}

struct PillButton: View {
    enum Style { case primary, secondary }
    static let minHeight: CGFloat = 52, iconCircle: CGFloat = 40, outlineOpacity = 0.20, disabledOpacity = 0.35
    init(_ title: Text, style: Style = .primary, systemImage: String = "arrow.right", action: @escaping () -> Void)
}
```

| | Geometry | States | Dynamic Type | Accessibility |
|---|---|---|---|---|
| **DotRow** | `n` circles 6 pt, gap 4, left to right, one row; 7 dots = 66 × 6 | `full`: `textPrimary` fill. `missed`: 1 pt `strokeBorder` in `textPrimary` 50 %, no fill. `today`: `Theme.signal` fill. Empty array draws nothing | fixed (graphic) | one element, `children: .ignore`, the caller's summary ("Slept enough on 5 of the last 7 nights; tonight is marked"). `today` is a position marker (put it last); full/missed differ by shape, not colour. Volt vs `textPrimary` is the same luminance (17.1 / 17.4), so the summary names today |
| **TickRow** | One zone row: `label` (74 wide, or its one-line width if that is wider, never truncated or drawn over the ticks: the label column has `layoutPriority(1)`, so that row's ticks start further right; the row stacks only when the whole row no longer fits. A five-row block that must keep one tick column decides stacking for all rows, PR 5; leading, `Font.ryft(.caption)`, `textSecondary` = 62 %) · 30 ticks of 3 × 12, radius 1.5, gap 3 (177 wide) · `value` (40 wide, trailing, `.caption`, `textPrimary`); columns `Theme.Metrics.itemSpacing` (12) apart, so 315 pt; value pushed to the trailing edge. Row height 12 (ticks); text may overhang. Five rows are the caller's `VStack(spacing: TickRow.rowSpacing)` (9) | Lit = first `litCount` ticks in `textPrimary`, rest 12 %. `litCount = clamp(Int((minutes·30 / scaleMax).rounded()), 0…30)`; `nil`, negative, NaN or `scaleMax ≤ 0` → 0 (the caller's `value` says "–" or "no data"). All five rows share one `scaleMax` | Label/value widths and row height are `@ScaledMetric(relativeTo: .caption)`. If the row no longer fits, `ViewThatFits` stacks: label · spacer · value above, ticks (177 fixed) below (always at AX1+) | one element per row, `.ignore`, the caller's label ("Zone 3, 24 minutes"). The caller groups the five with `.contain` |
| **CircleButton** | 40 circle, no fill, `strokeBorder` 1 pt `textPrimary` 16 %; `Image(systemName:)` 14 pt, `.regular` (≈ 1.3 pt stroke), `textPrimary`. **Layout box 44 × 44** (the circle centred, 2 pt transparent each side, `contentShape(Rectangle())`) | normal; pressed: circle filled `textPrimary` 8 %, no scale, no animation; disabled (`isEnabled` false): icon `textPrimary` 35 %, border unchanged | fixed (icon-only) | `Button` trait, the caller's label (required: there is no text); disabled is exposed by SwiftUI as not enabled |
| **PillButton** | `RoundedRectangle(cornerRadius: 26, style: .circular)` (P2-D6), height ≥ 52 (`minHeight`), full proposed width. **Primary:** fill `textPrimary`; leading 20, trailing 6; title `Font.ryft(.button)` in `Theme.background`, leading-aligned; trailing 40 pt `Theme.background` circle with the icon (14 pt, `textPrimary`). **Secondary:** fill none, `strokeBorder` 1 pt `textPrimary` 20 %; padding 22 horizontal; title `Font.ryft(.button)`, `textPrimary`, centred; no icon | normal; pressed: primary fill at 85 %, secondary filled `textPrimary` 8 %, no animation; disabled: whole pill at 35 % opacity. No busy state: the caller disables and changes the title | title scales (`.button` is relative to `.body`), no line limit, vertical padding 12 so it grows past 52 and wraps at AX3 without clipping; the 40 circle stays 40 and is vertically centred | the title is the label, the icon `accessibilityHidden`, `Button` trait; the whole pill is the target (≥ 52 high) |

### P2-5. The glyph table

Rows top to bottom; `0b…` bit 4 is the left column (5-wide glyphs), `0b1` the one column of a narrow glyph. `1 2 4 7 8` are the
plan's matrices, unchanged. `0 3 5 6 9` follow their style (a one-dot corner cut, a 3-wide stem, the 1 with a flag and foot).
`0` is plain (no slash): rows 4–5 tell it from `8` and `6`. Lit dots per glyph: `0` 16, `1` 10, `2` 14, `3` 14, `4` 14, `5` 17, `6` 15,
`7` 11, `8` 17, `9` 15, `:` 2, `.` 1, `,` 2.

```swift
static let table: [Character: DotGlyph] = [
    "0": DotGlyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]),
    "1": DotGlyph(width: 5, rows: [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]),
    "2": DotGlyph(width: 5, rows: [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111]),
    "3": DotGlyph(width: 5, rows: [0b01110, 0b10001, 0b00001, 0b00110, 0b00001, 0b10001, 0b01110]),
    "4": DotGlyph(width: 5, rows: [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010]),
    "5": DotGlyph(width: 5, rows: [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110]),
    "6": DotGlyph(width: 5, rows: [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110]),
    "7": DotGlyph(width: 5, rows: [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000]),
    "8": DotGlyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110]),
    "9": DotGlyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100]),
    ":": DotGlyph(width: 1, rows: [0b0, 0b0, 0b1, 0b0, 0b1, 0b0, 0b0]),     // rows 3 and 5
    ".": DotGlyph(width: 1, rows: [0b0, 0b0, 0b0, 0b0, 0b0, 0b0, 0b1]),     // row 7
    ",": DotGlyph(width: 1, rows: [0b0, 0b0, 0b0, 0b0, 0b0, 0b1, 0b1]),     // rows 6 and 7: the full stop with a tail
]
```

### P2-6. Previews and catalog

Dark only (`DarkPreview`, D3). Each file carries its previews; names are `"<Type>"`, `"<Type> · AX3"` (`.environment(\.dynamicTypeSize, .accessibility3)`).

| File | Previews |
|---|---|
| `DotNumeral` | default (`84`, `7:48` gap 7, `12.4` gap 7, `12,4`, pending, `style: .light`), `0123456789:.,` strip, AX3 (falls back to Light) |
| `RulerScale` | default (Today, Sleep, Strain, compact on a `GlowTile`, no value, value out of range), AX3 |
| `GlowTile` | default (recovery 2-up pair, sleep hero, strain hero, each with a 13 pt label and a value), AX3, Reduce Transparency (`reduceTransparency: true`) |
| `DotRow` | default (7 full, mixed, all missed, today only), AX3 |
| `TickRow` | default (five zones, `scaleMax` 60), no data, AX3 (stacked) |
| `CircleButton`, `PillButton` | default (normal and disabled; primary and secondary), AX3 (the long title wraps) |

`DebugComponentCatalog` gets five sections after "Brand" (existing sections untouched), titled with the monospaced section header:
`Nocturne · numeral` (DotNumeral: both gaps, all glyphs, Light, pending), `Nocturne · ruler` (the four boards' rulers, no value, clamped),
`Nocturne · glow tile` (the three colours at both radii, one forced flat), `Nocturne · rows` (DotRow, five TickRows), `Nocturne · buttons`
(circle and pill, enabled and disabled). The catalog's XS/L/AX3 picker shows the AX1 fallback.

### P2-7. Tests

Swift Testing, `@MainActor`. Files: `RyftTests/NocturneComponentTests.swift` (pure, 1–15), `NocturneComponentRenderTests.swift`
(`ImageRenderer`, 16–22), `NocturneComponentAccessibilityTests.swift` (`HostedWindow`, 23–26). Pixel reads follow `OrbitGaugeRenderTests`.

1. **Glyph table pinned:** the 13 keys and, for each, `width` and all 7 `rows` equal §P2-5; every `rows.count == 7`; no row has a bit at or above `width`.
2. Lit-dot count per glyph equals the §P2-5 list (popcount of rows).
3. `DotGlyphs.glyphs(for: "7:48")` has 4 glyphs of widths 5, 1, 5, 5; `glyphs(for: "7h")` and `glyphs(for: "7 ")` are `nil`.
4. **Sizes:** `size(of: "84", glyphGap: 8)` = 74×47; `"7:48"` 128×47 (gap 8), 125×47 (gap 7); `"12.4"` 128 / 125; `"12,4"` same as `"12.4"`;
   `"0"` 33×47; `":"` 5×47; `nil` with the default `"00"` template 74×47 (`"0:00"` at gap 7 = 125×47, the size of `"7:48"`); a string outside the table → `nil`.
5. **AX1 fallback:** `rendersDots("84", .dots, .xxxLarge)` true; `.accessibility1`, `.accessibility3` false; `.light` false at `.large`;
   `"7h"` false at `.large`; `nil` + `.dots` + `.large` true.
6. `tickCentres(count: 61, width: 300)` = `i·5`, first 0, last 300; `count: 64, width: 630` = `i·10`; `count: 2` = `[0, w]`; `count: 1` and `0` behave as 2.
7. **Needle x** (range 0…100, width 300): 84 → 252; 0 → 0; 100 → 300; 150 → 300 (clamped); −10 → 0; `nil` → `nil`; NaN → `nil`.
   Range 0…21: 10.5 → 150; range 0…10: 7.5 → 225; `5...5` (hi ≤ lo) → `nil`.
8. **Zone ticks:** Today `zoneTickIndices(61, 0...100, 67...100)` = 41…60 (count 20; index 40 is out); Sleep `(61, 0...10, 7.5...8.3)` = 45…49 (5);
   Strain `(64, 0...21, 10...14)` = 30…42 (13); compact `(43, 0...21, 10...14)` = 20…28 (9); `zone: nil` → `[]`.
9. Ruler size: `.regular` renders 36 high, `.compact` 32; needle colour is `Theme.signal`; `ZoneStyle.standard.opacity(for:)` is 0.55 regular, 0.60 compact; `.sleep` 0.85, `.strain` 0.95.
10. **TickRow `litCount`:** (0, 60) 0; (1, 60) 1 (0.5 rounds up); (7, 60) 4 (3.5); (24, 60) 12; (60, 60) 30; (90, 60) 30; (−5, 60) 0; (10, 0) 0; (nil, 60) 0.
11. `DotRow.size`: 7 → 66×6, 1 → 6×6, 0 → `.zero`.
12. **Form tokens:** `Theme.Metrics` has `neutralTileRadius` 22, `glowTileRadius` 24, `heroTileRadius` 28, `circleButton` 40, `minHitTarget` 44, `pillHeight` 52,
    `itemSpacing` 12; the old `cardRadius` 18, `tileRadius` 16, `screenPadding` 20 are unchanged; `GlowTileSpec.Radius.tile.points` 24, `.hero` 28.
13. **Gradient pinned:** `GlowTileSpec.stops` are `Theme.background` at alpha 0.97/0.92/0.55/0.10 and locations 0/0.34/0.68/1; `overlayOpacity`: 0 → 0.97,
    0.34 → 0.92, 0.5 → 0.7459 (±0.001), 0.68 → 0.55, 1 → 0.10, 2 → 0.10; `ellipse` = (0.90, 1.10, 0.55); padding 14/16/14/16.
14. Button constants: `CircleButton.diameter` 40, `hitSize` 44, `borderOpacity` 0.16; `PillButton.minHeight` 52, `iconCircle` 40; `TickRow` ticks 3×12, gap 3, 30 ticks,
    `rowSpacing` 9, widths 74/40; `DotRow` 6/4.
15. `GlowTileSpec.labelOpacity(for:)` is 0.78 below AX1 and 1.0 from AX1 (`ryftGlowLabelStyle` and the compact ruler labels use it).
16. **GlowTile core contrast.** Render `GlowTile(color) { Color.clear }` at 169×124, scale 2, for `Theme.recovery`, `metricSleep`, `metricStrain`. Sample every 4th px.
    For pixels with `t ≤ 0.60` (`t` from the §P2-3 ellipse): contrast of `textPrimary` ≥ 7.0 and of `textPrimary` at 78 % ≥ 5.0.
    Skip the 2 pt next to the edge and the corners (anti-aliasing).
17. **Padded rect:** same render at 169×124, 350×120, 350×168, 350×176; over the rect inset 14/16/14/16, the worst pixel reaches 4.5:1 for `textPrimary`
    and for the 78 % label (the table's minimum is 4.53 at 350×176 recovery: assert ≥ 4.5, not the table).
18. **Gradient pixels:** centre pixel of a 169×124 recovery tile within ±2/255 of `background·0.97 + recovery·0.03`; the pixel 1 pt inside the left edge, at mid height,
    is lighter than the centre and darker than the pure metric colour; no pixel is brighter than the metric colour.
19. **Reduce Transparency** (`reduceTransparency: true`): centre and every sampled interior pixel equal `Theme.surface` (±1); pixels 1 pt inside the edge (mid-sides, away from corners) equal the
    metric colour (±2), pixels 3 pt inside equal `surface`; with `false` the 1-pt pixel is not `surface`. No shadow: pixels outside the shape are transparent.
20. **DotNumeral render:** `"8"` at gap 8, dots style: the pixel at each dot centre is `textPrimary` for lit cells of `8` and `textPrimary` at 10 % over `background` for unlit cells
    (±2); pixels between dots (the 2 pt gap centre) are `background`. At `.accessibility1` no dot centre matches (the Light text is drawn).
21. `"7:48"` at gap 7: the view's frame is 125×47, and the leftmost lit dot (the `7`'s top row) and the rightmost (the `8`'s column 4) touch its left and right edges (±0.5 pt).
22. **Ruler render:** at width 300, regular, Today: pixel at needle x, y 20 is `Theme.signal`; with `value: nil` it is not; a zone tick at index 50 is 14 pt tall, an outside tick (index 10) 8 pt;
    `reduceMotion: true` places the needle at its final x in the first frame after a value change.
23. **Accessibility labels** (`HostedWindow`): `DotNumeral`, `RulerScale`, `DotRow`, `TickRow` each expose exactly one element in their frame, with the caller's label (and
    the ruler's value text); none exposes its inner `Text`.
24. **Buttons:** `CircleButton` node frame ≥ 44×44 and has the button trait, label as passed; disabled → not enabled; `activate()` calls the action once, and zero times when disabled.
25. **PillButton:** frame height ≥ 52 in primary and secondary; button trait; label = the title; disabled → not enabled; at `.accessibility3` with a 40-character title the frame height
    grows beyond 52 and the label's frame is inside the pill's (no clipping).
26. `GlowTile` exposes no element of its own (`children: .contain`); `RulerScale`, `DotNumeral` at `.accessibility3` still expose one element.

### P2-8. Form tokens

Yes. Additive constants in `Theme.Metrics` (`Theme.swift`; the existing six keep their values, PRs 4–5 migrate their callers):

```swift
static let neutralTileRadius: CGFloat = 22   // neutral tiles, lists
static let glowTileRadius: CGFloat = 24      // Today 2-up glow tiles
static let heroTileRadius: CGFloat = 28      // Sleep, Strain hero tiles
static let circleButton: CGFloat = 40
static let minHitTarget: CGFloat = 44
static let pillHeight: CGFloat = 52
static let itemSpacing: CGFloat = 12         // §2 "Abstand 12"
```

`screenPadding` 20 already exists. The pill radius is 26 (`RoundedRectangle`, P2-D6), a capsule at 52 pt. Per-component measurements (dot 5, gap 2, tick 3 × 12, …) stay
`static let` on their component: they are not shared.

### P2-9. Overlaps with existing components

PR 2 touches none of them.

| Existing | New | After PRs 4–5 |
|---|---|---|
| `OrbitGauge` / `MetricGauge` centre numbers | `DotNumeral` | PR 3 puts it in the gauge centre. `MetricGauge` (only `StrainView`) goes with PR 5's Strain screen; PR 5 deletes it if the grep is empty |
| `RangeBar` (value in a 30-day range) | `RulerScale` | **Coexist.** Different job (personal range and status). No screen uses `RangeBar` today (catalog only) |
| `SleepNeedBar` | `RulerScale` (Sleep's 0–10 h need zone) | PR 4 decides; the need breakdown is a different view and may stay |
| `ZoneBar` (`StrainView`, `WorkoutDetailView`) | `TickRow` | `TickRow` replaces it in `StrainView` (PR 5); `WorkoutDetailView` keeps `ZoneBar`: **coexist** |
| `MetricTile`, `Card` | `GlowTile` | **Coexist.** `GlowTile` only for the section's one glow tile; neutral tiles stay `MetricTile`/`Card` (restyled to 22 pt in PRs 4–5) |
| `ScoreRing` (`DateStrip`) | none | untouched |
| `DateStrip`, Sleep's prev/next, Today's calendar button, Strain's plus | `CircleButton` | PR 4/5 replace the ad-hoc buttons |
| `PrimaryButton` (Profile, Auth) | `PillButton` | `PillButton` replaces `.primary`/`.secondary` in Profile (PR 5). `PrimaryButton` stays for Auth and for `.destructive` and `busy`, which `PillButton` lacks |
| `TealButtonStyle` (Train, Today, Coach marks), `PressableButtonStyle` | `PillButton` | **Coexist.** Train is not a Nocturne screen; Today's use moves in PR 4 if its design asks |
| `SegmentedPicker` | none | restyled in place by PR 5 |
| `MiniHypnogram`, `StageBar`, `Hypnogram` | none | PR 4 |

### P2-10. Deviations and derived values

| # | From | To | Number and reason |
|---|---|---|---|
| P2-D1 | Board ellipse 85–90 % × 80–110 % at 50 / 50–55 %, per tile | One fixed ellipse at the dark end: 90 % × 110 % at 50 % / 55 % | Brief §2/§6: text always in the dark core. The middle of the ranges (87.5 %, 95 %, 52.5 %) gives a recovery 78 % label 4.04 at 350 × 176 and 4.39 at 350 × 120, the low end 3.44. The dark end gives ≥ 4.53 on all four sizes. Inside the measured ranges, so no brief conflict. |
| P2-D2 | Pill text 15 pt Medium | `Font.ryft(.button)` = 16 pt Medium | There is no 15 Medium role; §2 allows body 15–17 and buttons Medium. |
| P2-D3 | Circle button 40 pt | 40 pt circle in a 44 pt layout box | Hit target ≥ 44 (§6, HIG). The two transparent points count in the caller's spacing. |
| P2-D4 | Ticks "edge to edge" (CSS space-between puts the edges at 0 and W) | centres at `i/(n−1)·W` (lead's rule); the outer ticks overhang ≤ 0.75 pt | Needle x and tick `i` then share one formula. |
| P2-D5 | `textTertiary` 45 % on the boards | 48 % (PR 1's token) | Already D-a; the regular ruler labels use it. |
| P2-D6 | Pill as `Capsule()` | `RoundedRectangle(cornerRadius: 26, style: .circular)` | At AX3 a three-line pill is 155 pt tall; a capsule's ends are then 77 pt round and the first and last letters fall off the fill. Identical at 52 pt. |
| P2-D7 | Glow labels always 78 % | 78 % below AX1, full `textPrimary` from AX1 (`GlowTileSpec.labelOpacity(for:)`) | Lead decision: tiles grow tall at accessibility sizes, and a 78 % label in an outer corner can fall under 4.5:1 (§P2-3 known limit). |
| P2-D8 | `.quick` | `Theme.Motion.quick` | `Animation` has no member `quick`; the spec's call did not compile. |
| P2-D9 | `nonisolated static func` reading `static let` | the constants they read are `nonisolated static let` | `View` conformance makes the types main-actor isolated; without it the helpers warned (6 warnings). |
| P2-D10 | `placeholderGlyphs: Int` | `placeholder: String` template, drawn unlit | Review row 7: the pending Sleep numeral was 74 pt wide against 125 for "7:48", so the row jumped. In the Light fallback the dashes are wider than digits; only the dot grid keeps the width. |
| P2-D11 | `zoneTint` + `zoneOpacity` | `zoneStyle: ZoneStyle` presets | Review row 3: PRs 4–5 must not repeat 0.85 / 0.95 as literals. |
| P2-D12 | Compact labels in `textTertiary` | `textPrimary` at the glow label opacity | Review row 1: the edge labels reached 3.68–3.90:1 in the strain tile (the board's place) and 3.13–3.44 in a recovery tile (worst case); now 6.99–7.65 and 5.52–6.32 at L, ≥ 7.65 at AX3. |
| P2-D13 | Ruler labels ≥ 8 pt apart | ≥ 16 pt | Review row 10: at AX3 the five Today labels read as one run. |
| P2-D14 | Icon-only circle button | adds `accessibilityShowsLargeContentViewer` (icon + the caller's label) | Review row 8: the icon stays 14 pt at AX3 (HIG: Large Content Viewer for controls that don't scale). |

None of these contradicts the brief. Derived, not measured (the boards give no number; ios-developer must not tune them without asking): compact ruler height
32 and row 18; compact needle triangle = regular; glow-tile bottom padding 14; ticks vertically centred in their row; ruler labels space-between; TickRow column gap 12;
primary pill text leading-aligned and secondary centred; pill icon 14 pt (the circle's); `today` as a filled dot; the `,` glyph; the plain `0`.

## PR 3 — gauge v3 and launch

Scope: the rendering of `OrbitGauge` (model, mapping, API, VoiceOver sentences and `OrbitGaugeEntrance` timings unchanged) and the visual
timeline of the launch (§5). Lifecycle (where the launch lives, when it plays, skip, hand-off) is `launch-design.md`, not here; open points
are in §P3-11. Measurements: `plan.md` §PR 3 (Today board 260 pt, Launch board 5.2 s). **Brief §5 wins** over the board; every board number
changed is in §P3-10.

Conventions. **S** is the gauge's side, `OrbitGaugeSize.frame` (dial + 12); **k = S / 260**. Code angles (`OrbitGaugeGeometry`) are degrees
clockwise from 12 o'clock; the boards, the brief and this spec's tables use 0° = 3 o'clock, clockwise: **board = code − 90**. Where a value is
pinned in code both are given. Colours: `ink` is `Theme.textPrimary`, `signal` is Volt; `ink 16 %` means `textPrimary` at 16 % alpha.

### P3-1. Gauge v3 geometry

The reference is the Today board at S = 260. Every length below is `fraction × S` with the floors in the second table, so one function
serves 56 to 260 pt. The model (`OrbitGaugeMode`, `OrbitGaugeValues`), `OrbitGauge`'s initialiser and `OrbitGaugeSize` keep their shape:
`.small` 84, `.medium` 124, `.large` 172 stay (the reference 260 is `.custom(dial: 248)`, see Q1).

| Ring | Radius at 260 | Fraction of S | Track | Arc / marks | Ticks |
|---|---|---|---|---|---|
| Outer, strain | 118 | 0.4538 | **tick ring**: 128 ticks, 1.2 × 6, centred on the radius, `ink 16 %` | 3.5 round, `metricStrain`, from the top clockwise, sweep = strain/21 × 360 (21 → 359.99) | none lit; the arc covers its track |
| Middle, recovery + sleep | 88 | 0.3385 | **full ring** 3.5 wide, `ink 7 %` | two 3.5 round arcs: recovery from −96° counter-clockwise, sleep from −84° clockwise, each over at most 160° | none |
| Inner, readiness | 58 | 0.2231 | **tick ring**: 60 ticks, 1.3 × 7, `ink 13 %` | the first `round(readiness/100 × 60)` ticks in `ink`; Volt dot r 5 with a 2.5 ring at the value | lit = `ink`, unlit = 13 % |
| Dots (orbits) | on the arc head | r 0.0269 | | r 7 in the metric colour, 3 ring, halo r 15 at 16 % | |
| Strain band rail (PR 4 feature, kept) | 109.5 | 0.4212 | | 3 wide, butt, `metricStrain` 50 %, from `bandRail(for:)` | |

| Quantity | At 260 | Fraction of S | Floor (pt) |
|---|---|---|---|
| Arc / ring width `arcW` | 3.5 | 0.01346 | 1.5 (`minStroke`) |
| Outer tick width × length | 1.2 × 6 | 0.00462 × 0.02308 | 0.75 × 3 |
| Inner tick width × length | 1.3 × 7 | 0.00500 × 0.02692 | 0.75 × 3 |
| Orbit dot radius | 7 | 0.02692 | 1.15 × `arcW` (the rule `metrics(forDial:)` has today) |
| Dot ring (the cut around a dot) | 3 | 0.01154 | 1.0 |
| Halo radius | 15 | 0.05769 | drawn from S ≥ 110 |
| Volt dot radius / ring | 5 / 2.5 | 0.01923 / 0.00962 | 2.0 / 1.0 |
| Hollow dot stroke | 1.5 | 0.00577 | 1.25 |
| Band rail width | 3 | 0.01154 | `minStroke` |

Extent at 260: outer ticks end at 121, the strain dot with its ring at 128, so the frame (half 130) holds everything except the halo
(133, 3 pt over at 16 %). **The gauge and its parents must not clip it** (`.clipped()` is forbidden there).

**Tick rings.**
- *Count.* `n = round(2πr / pitch)` with r 118 and pitch 5.8 (1.2 + 4.6) is 127.83, so **n = 128**: pitch 5.792, gap 4.592. 128 divides by 4, so a tick
  sits at 12, 3, 6 and 9 o'clock. Radius and pitch both scale with S, so n does not change with size; only the pitch in points does. Inner: 60
  ticks every 6°, pitch 6.07 at 260. Tick `i` is centred at `−90° + i × 360/n` (board), tick 0 at the top.
- *Tiers by S* (the tick width floor would otherwise make a dense ring a grey band):

| S | Outer | Inner | Where |
|---|---|---|---|
| ≥ 150 | 128 ticks | 60 ticks | Today `.large` 172, 260; widget home tile |
| 100 ..< 150 | 64 | 30 | `.medium` 124, widget dial 88–137 |
| < 100 | solid ring `arcW` wide, same tint | solid ring: unlit 13 %, lit part a solid `ink` arc | `.small` 84, lock-screen and rectangular widgets |

- *Lit ticks* (`n` = 60 or 30): `lit = clamp(round(readiness / 100 × n), 0...n)`, `Int((x).rounded())` (half up). 84 → 50 (of 60) or 25 (of 30); 0 → 0;
  100 → n; 1 → 1 (0.6 rounds up); 120 → n; −5 → 0. Ticks 0 ..< lit are `ink`.
- *Volt dot* at the value, not at a tick: board angle `−90 + clamp(readiness, 0...100)/100 × 360` (84 → **212.4° = −147.6°**; code 302.4°; 100 → back at the
  top). It rides the ring (r 58), r 5, 2.5 ring.
- *A tick is whole or absent.* A tick is omitted when its centre is closer than the cut radius (dot r + ring) to a dot of its own ring:
  angular distance `< 2·asin(cut / 2r)` — strain dot cut 10 at r 118 → 4.857°, Volt cut 7.5 at r 58 → 7.41°. No sliver is ever drawn. At 84 / 12.4 of 21
  the omitted ticks are outer 74…77 (four) and inner 50, 51; inner tick 49 (8.4° from the dot) stays lit. This is *drawing*; the logical lit count stays 50.

**Recovery / sleep split. "Wie heute" holds for the structure, not for the numbers.** Verified against `OrbitGaugeGeometry`:

| | Today (code) | v3 |
|---|---|---|
| Split | at the vertical; recovery counter-clockwise, sleep clockwise | same |
| Start | ±12.5° (`innerInset`) | **±6°** (board −96° / −84°) |
| Span at 100 % | `180 − 2 × 12.5` = 155° | **160°** (a constant; `180 − 2 × 6` would be 168) |
| Gap left at the bottom | 12.5° each side | **14°** each side; the two heads are 28° apart |
| 50 % | exactly 3 and 9 o'clock (±90 code) | ±86 code (board −176° / −4°) |
| Track | two arcs of the span | one full 7 % ring |

Mapping `angle(f) = ±6 + f × ±160` (code), `f` clamped to 0…1. Board angles: sleep head `−84 + 160 f`, recovery head `−96 − 160 f`. Strain head
`−90 + 360 f`. The board's numbers: strain 12.4/21 → **122.571°** (board 122.6), recovery 82 % → **−227.2°** (board −227), sleep 94 % → **66.4°** (board 66). The board
rounds to whole degrees; tests allow ±0.5° around the board values and ±0.01° around these. Start dots are 18.4 pt apart at 260 (≥ 2 × 7 + 4, so the PR 2 rule
"a dot's diameter and 4 pt of air" still holds); at 100 % the heads are 42.6 pt apart. Both hold at every S ≥ 56 (checked at 56: 3.96 ≥ 2 × 1.73).
Re-pinned in `OrbitGaugeGeometryTests`: `innerInset` 6, the span 160, `recoveryRuns…` expecting ±86 at 50 %.

**Arcs, dots, halo.**
- Arcs: `lineCap: .round`, width `arcW`, sweep 0 draws no arc (a score of 0 is a filled dot at its start; a missing score is a hollow dot, unchanged). The arc runs to the dot's centre.
- Dot: filled r 7, centred on the arc head. **Ring:** a 3 pt clear annulus (r 7…10) cut with `destinationOut` through everything below it in the marks layer (arc, halo, rail)
  and in the tracks layer (middle ring); it is *not* a painted `background` ring, so the gauge reads the same on `background`, `surface` and in the widget's
  tinted modes. On `background` it is pixel-identical to the board's 3 pt `background` ring.
- Halo: r 15, the metric colour at 16 %, behind the ring (so only r 10…15 shows). Strain past its band: arc, dot and halo in `alert`.
- Order, back to front. *Tracks layer* (one `compositingGroup`): outer ticks or ring, middle ring, inner unlit ticks or ring, ring cuts. *Marks layer* (one group, `pendingOpacity`
  applies to it): band rail, arcs, halos, ring cuts, lit inner ticks, dots, the Volt dot last. Dots are drawn after all cuts, so two close dots never cut each other.
  Ticks are never cut: a tick whose rect comes closer to a dot than its cleared ring is left out (§P3-10 row 23).

**Centre.** In a frame of `centreSlot = 0.86 × 2 × (0.2231 S − tickLength/2)` wide (93.7 pt at 260, 62 at 172, solid tier `arcW/2` instead of `tickLength/2`).
- Scored with a readiness: `DotNumeral(String(readiness), style: .dots, glyphGap: 8, accessibilityLabel:)` **only at S ≥ 205 and when it fits**:
  `DotNumeral.size(of:).width ≤ centreSlot`. The size gate decides the look per gauge, so a single digit at `.large` is Light like "84" (L, row 20).
  "84" is 74 × 47: dots at 260. "100" is 115 wide and never fits: Light. Below that, and at AX1 and up (the numeral's own
  fallback), and when a caller asks for thin digits: Light `Font.ryftNumber(size: 0.2 × S)` (ADR 0016's floor: Regular below 20 pt, row 21), `textPrimary`, tabular, `lineLimit(1)`,
  `minimumScaleFactor(0.5)` in the `centreSlot` frame (52 pt at 260). At AX3 `DotNumeral`'s fallback scales to about 78 pt; the slot's minimum scale keeps "100" inside.
- Calibrating: Light "3" with " / 7" at 55 % size in `textTertiary` (as today, count only below a 100 pt dial). Pending: the previous readiness as the numeral at 48 % opacity (= `textTertiary` on
  `background`) or `DotNumeral(nil)` — the unlit grid, "pending is an outline" — without one. Readiness missing in a scored mode: the same unlit grid.
  Below S 205, where the grid isn't used, both show a Light "–" in `textTertiary` (row 22).
- Shown from a 56 pt dial up (`minDialForNumber`, unchanged), as today.
- A numeral change cross-fades (`Theme.Motion.quick`, `.transition(.opacity)` on `.id(readiness)`) for the dots only; the Light numeral keeps `.numericText` and moves with the arcs (`slow`). Reduce Motion: no transition.
- Additive API for Today's thin-digit switch (§1 of the brief): `numeral: DotNumeral.Style = .dots` on the initialiser, default behaviour unchanged (Q5).

**Minimum size.** Supported down to **S = 56** (widget dial 44, the smallest user in the repo; `OrbitGaugeDrawing` is shared with the widget, so it gets v3 too, Q2).
Below S = 100 the tick rings become solid rings (table above); the halo goes below 110; the number below 68 (dial 56); the band rail below 102 (dial 90, unchanged).
The rings keep ≥ 6.4 pt between them at 56 (25.4 / 18.9 / 12.5), as the 44 pt gauge did today (21 / 14.9 / 8.8).
Nothing below 56 is supported, as `RyftMarkGeometry.innerRingMinSide` supports nothing below 18.

**Entrance (`OrbitGaugeEntrance`) on v3.** `OrbitEntranceFrame` timings are untouched (tracks 250 ms, flight 150–600 ms, glide 250 ms, total 850 ms; Reduce Motion and Low Power: 250 ms
cross-fade). What changes is what each stage draws:

| Stage | v3 |
|---|---|
| `trim(.strain)` | outer ticks appear clockwise from the top up to the fraction (an angular mask, not 128 animations) |
| `trim(.inner)` | the middle ring grows from the top in both directions, ±fraction × 180° |
| `trim(.centre)` | the unlit inner ticks appear clockwise the same way |
| flight | orbit dots fly in with their halos at 0 % growing to 16 % (halo opacity = flight); no Volt dot yet |
| glide | arcs fill, orbit dots reach their heads; the lit inner ticks fill behind the Volt dot, which fades in at the top at glide start and travels to the value; the numeral cross-fades in |

The last frame is the static drawing (existing test). The value animation after the entrance (`Theme.Motion.slow`, Reduce Motion `quick` cross-fade) now also moves the Volt dot
(`Animatable` angle); the lit count follows it by threshold.

### P3-2. Gauge v3 states

Every state the gauge has today is kept. Look at S ≥ 150; the solid tier (S < 100) only swaps ticks for rings.

| State | Trigger | v3 look | Spoken (unchanged) |
|---|---|---|---|
| Scored | `.scored(values)` | as §P3-1 | "71, High. Recovery 71 percent, …" |
| Partial: a score missing | `recovery`, `sleep` or `strain` nil | that orbit: track only and a **hollow dot** at its start (r 7 outline 1.5 in the metric colour, interior cleared, no halo); the others normal | "Sleep, not scored" |
| Partial: no readiness | `readiness` nil | inner ticks all unlit, no Volt dot (Volt marks a value), centre = unlit numeral grid | "Overall readiness, no data" |
| Zero | a score of 0 | no arc; a **filled** dot and halo at the start; readiness 0: no lit tick, the Volt dot at the top | "Recovery 0 percent" |
| Out of range | recovery/sleep < 0 or > 1; strain < 0 or > 21; readiness outside 0…100 | arcs and the Volt marker clamp (strain 25 = a whole turn, dot back at the top); the numeral shows the integer given, the platform's contract is 0–100 | as today |
| Strain band | `strainBand` usable | rail r 109.5 (inside the ticks), arc, dot and halo turn `alert` past the band's end (`OrbitStrainArc`, unchanged logic), rail cut around the dot | "…today's recommended range 8 to 13" |
| No data | `values.isEmpty` | tracks, three hollow dots, no Volt dot, empty grid | "No data" |
| Calibrating | `.calibrating` | outer orbit: **7 round segments** (seam clear 9°, gap 5°, `ink 16 %`), the counted ones in `calibration` (recovery teal), **no tick ring**; middle ring 7 %; inner ticks unlit; three hollow dots; centre "3 / 7"; fills 60 ms per night as today | "3 of 7 nights…" |
| Pending, with a previous day | `.pending(previous:)` | previous marks at `pendingOpacity` 0.6 breathing 1 ↔ 0.75 (1.4 s, off under Reduce Motion or `breathes: false`), lit ticks and Volt dot included; tracks full strength; number at 48 % | "Not scored yet. Last scored: …" |
| Pending, none | `previous` nil | tracks and three hollow dots, grid unlit | "Not scored yet" |
| Unknown (widget) | `mode == nil` | tracks only | — |

The band colour of the centre ring (high / moderate / low) is gone: lit ticks are `ink`, the band word is the caption under the gauge (PR 4's "Readiness · High") and the
spoken sentence, never colour alone. `OrbitGaugePalette.band(...)`, `high`, `moderate`, `low` become unused by the gauge (`strainPastBand` still uses `low`); the palette gains
`ink` and `signal` (Q2).

### P3-3. Contrast (WCAG 2.x, sRGB composites; graphics need 3:1)

Tracks over `background` `#0A0C0B`: `ink 7 %` `#1A1C1B`, `10 %` `#212322`, `13 %` `#282A28`, `16 %` `#2F312F` (= `SurfaceRaised`). All are decoration (1.15 to 1.50:1 on `background`).

| Graphic | On `background` | Over its track | Needs |
|---|---|---|---|
| Recovery arc / dot `#63D2B4` | 10.66 | 9.31 (7 % ring) | 3 |
| Sleep `#9B8AF0` | 6.81 | 5.94 (7 % ring) | 3 |
| Strain `#5E8BEA` | 5.94 | **3.97** (16 % ticks, the limit) | 3 |
| `alert` (strain past band) `#E36B5B` | 6.09 | 4.07 (16 %) | 3 |
| Volt dot `#D8FF4F` | 17.13 | 12.63 (over 13 % ticks) | 3 |
| Lit tick `ink` vs unlit tick (13 %) | 17.35 on `background` | **12.79** lit vs unlit | 3 |
| Dot over its own halo (16 % of the colour) | recovery 7.99, sleep 5.55, strain 4.95 | | 3 |
| Numeral dots `ink` | 17.35 | | 3 (graphic), 4.5 (Light fallback text) |

Volt versus a lit tick is 1.01:1 by colour, so the marker is told apart by shape and size (r 5 against a 1.3 pt tick), its cleared ring and its position, not by hue; the spoken sentence
carries the value. Pending: the 0.6 dimming stays "intentionally secondary" — Sleep 3.11 and Strain 2.80 on `background`, 2.98 and 2.71 over the 7 % ring, Recovery 4.38 / 4.16 (the PR 1 numbers were 2.58, 2.34
over a 16 % track): the test keeps asserting the three that are under 3, with these numbers. Halos and tracks carry nothing.

### P3-4. Launch visuals and timeline

**What the eye sees.** The three rings appear as an instrument, the arcs draw to a reading (the same reading the gauge shows, strain 12.4 of 21, recovery 82 %, sleep 94 %, readiness 84), the display holds
for 1.25 s, then the three dots travel to their places in the mark, the arcs reshape, the tracks fade, everything turns `ink` and "RYFT" and the tagline arrive. It is a brand moment, not data: the
reading is the board's demo, never the user's (no fetch, nothing sensitive on a locked phone).

`t = elapsed / 5.2 s`, clamped to 0…1. Segment easing as CSS applies it, per keyframe pair:
**E1** `cubic-bezier(.45, 0, .15, 1)` for geometry, group, tracks and colour; **E2** `cubic-bezier(.2, 0, 0, 1)` for the wordmark; **E3** CSS `ease`, `cubic-bezier(.25, .1, .25, 1)` for the tagline.
`progress(t, a, b) = clamp((t − a)/(b − a), 0, 1)`; a segment value is `from + (to − from) × E(progress)`. E1(0.5) = 0.7912, E2(0.5) = 0.8778, E3(0.5) = 0.8024 (±0.0005; solve x(τ) by bisection, 40 steps).
One frame at 60 fps is 1/312 = 0.0032 of t.

Angles: degrees, clockwise, 0° = 3 o'clock. An arc is `(start, end)` with `end > start`, drawn clockwise (the form `RyftMarkGeometry.arcs` returns); the recovery arc is therefore stored as
`(ccw head + 360, −96 + 360)`. `gO = 14.0203°` and `gM = 24.2172°` are `RyftMarkGeometry.halfGap` at 184 pt (outer, middle). **Rule: a dot is the arc's head plus the ring's clear air, in the direction of travel**
(`dot = head ± g`), which is what the board's numbers do and what the static mark has. Phase B follows the brief: the dots travel on their own.

| Element | Phase A, 0 → 0.26 (E1) draw-in | Hold 0.26 → 0.50 | Phase B, 0.50 → 0.76 (E1) | 0.76 → 0.86 | After |
|---|---|---|---|---|---|
| Strain arc start | −90 | −90 | −90 → **79.02** (+169.02) | | 79.02 |
| Strain arc end | −90 → **108.55** (value 122.571 − gO) | 108.55 | 108.55 → **410.98** (+302.43) | | 410.98 |
| Strain dot | −75.98 → **122.57** (= end + gO the whole way) | 122.57 | 122.57 → **425** (+302.43, clockwise; = 65 + 360) | | 425 |
| Sleep arc start | −84 | −84 | −84 → **−51.78** (+32.22) | | −51.78 |
| Sleep arc end | −84 → **42.18** (66.4 − gM) | 42.18 | 42.18 → **155.78** (+113.60) | | 155.78 |
| Sleep dot | −59.78 → **66.4** | 66.4 | 66.4 → **−76** (−142.4, counter-clockwise, through the arc) | | −76 |
| Recovery arc start (ccw head + 360) | 264 → **157.02** (−96 − 131.2 + gM, +360) | 157.02 | 157.02 → **204.22** (+47.20) | | 204.22 |
| Recovery arc end | 264 | 264 | 264 → **259.78** (−4.22) | | 259.78 |
| Recovery dot | −120.22 → **−227.2** | −227.2 | −227.2 → **180** (+407.2: a whole lap and 47.2° more, clockwise) | | 180 |
| Inner ring sweep from −90 | 0 → **302.4** (84 %) | 302.4 | 302.4 → **360** (closed) | | 360 |
| Arc / dot colour | metric (`#5E8BEA` strain, `#9B8AF0` sleep, `#63D2B4` recovery) | metric | metric | → `ink` over 0.76 → 0.86 (E1) | `ink` |
| Inner ring colour | `ink` throughout | | | | |
| Tracks (r 44 / 25.6 / 7.6, 3.16, `ink 10 %`) opacity | 0 → 1 over 0 → 0.06 (E1) | 1 | 1 until 0.52, then 1 → 0 over 0.52 → 0.74 (E1) | 0 | 0 |
| Group opacity | 0 → 1 over 0 → 0.04 (E1) | 1 | 1 | 1 | 1 |
| Wordmark opacity / tracking | 0 / 0.9 em | 0 / 0.9 | 0 / 0.9 until 0.74, then → 1 / 0.32 em over 0.74 → 0.86 (E2) | → 1 / 0.32 | 1 / 0.32 |
| Tagline opacity | 0 | 0 | 0 until 0.80, then → 1 over 0.80 → 0.88 (E3) | 1 at 0.88 | 1 |

In seconds: the draw-in takes 1.35 s, the hold 1.25 s (1.352 → 2.600), tracks in by 0.31 s, hold 1.35 → 2.60, tracks out 2.70 → 3.85, morph 2.60 → 3.95, colours 3.95 → 4.47,
wordmark 3.85 → 4.47, tagline 4.16 → 4.58, static until 5.20. The strain dot rides the strain arc's end all the way (constant 14.02°). The sleep dot leaves its arc at 0.50, travels back
across it and ends 24.22° behind the arc's new start, which is the mark's own clear air on the other side. The recovery dot makes one extra lap by the brief's design.

**The pure function.** Foundation and `RyftMarkGeometry` only (no SwiftUI), so a test needs no view:

```swift
struct LaunchFrame: Equatable {
    struct Arc: Equatable { var start: Double; var end: Double }       // degrees; drawn clockwise; empty when end - start < 0.05
    struct RGB: Equatable { var r, g, b: Double }                      // sRGB, 0...1, not premultiplied
    struct Palette { var strain, sleep, recovery, ink: RGB }           // resolved from the asset catalog by the view
    struct Orbit: Equatable { var arc: Arc; var dot: Double; var colour: RGB }
    static let duration = 5.2
    var t: Double
    var groupOpacity: Double              // 0...1
    var trackOpacity: Double              // 0...1, times 0.10 ink
    var strain, sleep, recovery: Orbit
    var innerSweep: Double                // degrees from -90; 360 = the closed ring
    var wordmarkOpacity: Double, wordmarkTracking: Double   // em
    var taglineOpacity: Double
    init(t: Double, palette: Palette, side: Double = 184)   // metrics = RyftMarkGeometry.metrics(forSide: side)
}
```

The values after phase B are **read from** `RyftMarkGeometry.arcs(of: outer / middle, metrics:)` and `.dots` (the strain dot as `dots[0] + 360`), the values at the end of phase A from the gauge mapping minus the halo gap,
the start values from the gauge starts plus the gap; there is no second set of numbers. Samples (`side` 184, `gO` 14.0203, `gM` 24.2172):

| t | Strain arc | Strain dot | Sleep arc | Sleep dot | Recovery arc | Recovery dot | Inner | Group / tracks | Wordmark (op / em) | Tagline | Colour mix |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | −90, −90 | −75.98 | −84, −84 | −59.78 | 264, 264 | −120.22 | 0 | 0 / 0 | 0 / 0.90 | 0 | 0 |
| 0.13 | −90, 67.10 | 81.12 | −84, 15.84 | 40.06 | 179.35, 264 | −204.87 | 239.27 | 1 / 1 | 0 / 0.90 | 0 | 0 |
| 0.26 | −90, 108.55 | 122.57 | −84, 42.18 | 66.40 | 157.02, 264 | −227.20 | 302.40 | 1 / 1 | 0 / 0.90 | 0 | 0 |
| 0.50 | −90, 108.55 | 122.57 | −84, 42.18 | 66.40 | 157.02, 264 | −227.20 | 302.40 | 1 / 1 | 0 / 0.90 | 0 | 0 |
| 0.63 | 43.74, 347.85 | 361.87 | −58.51, 132.07 | −46.27 | 194.36, 260.66 | 94.99 | 347.98 | 1 / 0.21 | 0 / 0.90 | 0 | 0 |
| 0.76 | 79.02, 410.98 | 425 | −51.78, 155.78 | −76 | 204.22, 259.78 | 180 | 360 | 1 / 0 | 0.41 / 0.66 | 0 | 0 |
| 0.86 | same | 425 | same | −76 | same | 180 | 360 | 1 / 0 | 1 / 0.32 | 0.96 | 1 |
| 1 | same | 425 | same | −76 | same | 180 | 360 | 1 / 0 | 1 / 0.32 | 1 | 1 |

(Groups at 0.13 and 0.63 are the E1 values: mid-segment progress 0.5 gives 0.7912 of the way: strain end −90 + 198.55 × 0.7912 = 67.10.) At 0.26 the board's own values are strain 108.61 / 122.6, sleep 41.78 / 66, recovery
−202.78 / −227: within 0.5° (§P3-10, row 1). The arc lengths at the hold are 55.15 %, 35.05 % and 29.72 % of the circle (board 55.17, 34.94, 29.66).

**t = 1 is the static mark, exactly.** `arcs(of: outer, metrics: metrics(forSide: 184))` is (79.0203, 410.9797), the middle ring (−51.7828, 155.7828) for sleep and (204.2172, 259.7827) for recovery, the dots
65 / −76 / 180, the inner ring present (`showsInnerRing` since 184 ≥ 22), stroke 3.16 and dot r 6 box units (5.81 and 11.04 pt at 184), all in `ink`. The view draws arcs and dots with `RyftMarkShape`'s own path builders
(extract them as static functions; this is not a second geometry), so the pixels match `RyftMark()` at 184 to within 2/255.

**Colour.** `mix = E1(progress(t, 0.76, 0.86))`; colour = `metric + (ink − metric) × mix`, **per component in gamma-encoded sRGB** (what CSS keyframes do, so the board's mid-frames match; linear light would
brighten the middle). At t = 0.81: strain `#D3DCEC` (211, 220, 236), sleep `#E0DCED` (224, 220, 237), recovery `#D4EBE0` (212, 235, 224; the green is 234.5). The dots mix with their arcs. Contrast never falls below the metric colour's (5.94 and up): the mix only gets lighter.

**Layout (the launch screen; portrait only).** `Theme.background` full-bleed, ignoring the safe areas; positions are from the full screen height H.

| Element | Size | Position |
|---|---|---|
| Mark | the 100 box is 184 × 184 pt; stroke 5.81, dot r 11.04, radii 80.96 / 47.10 / 13.98 | box centre at (W/2, H/2 − 40); the outer ring reaches 83.9 pt from it |
| Wordmark "RYFT" | 22 pt Satoshi Light (`Font.ryftNumber(size: 22, weight: .light)`), `ink`, tracking animated 0.9 → 0.32 em, trailing tracking pulled back so the ink stays centred (D-h) | line box top at the mark box's bottom + 28 = H/2 + 80, centred |
| Tagline "Engineered for peak." | `Font.ryft(.label)` (13 pt), `ink` at 55 % = 5.67:1 on `background`, centred, up to 2 lines | bottom edge at `max(64, safeAreaBottom + 24)` above the screen bottom (64 on every notched iPhone, 30 pt above the home indicator) |

390 × 844: mark centre y 382, wordmark top 502, tagline bottom 780. 375 × 667 (SE): 293.5 / 413.5 / 603; nothing collides at AX3. The wordmark's "28 pt below the mark" is read as below the 184 box,
not below the ring's edge (Q9). **Dynamic Type:** the mark and the wordmark are fixed size (brand marks, PR 1 §6); the tagline scales with `.footnote` up to AX3, wraps to two lines, never truncates. Dark only, so no light variant;
Reduce Transparency and Increase Contrast change nothing (no blur, tracks are decoration).

**Motion rule.** The 250 ms ceiling is for UI state changes; the 5.2 s sequence is the brief's brand moment and the only exception. It is cheap vector drawing (`TimelineView(.animation)` and a `Canvas`, or shapes driven by `LaunchFrame`),
nothing animates through SwiftUI's transaction system, so a layout change under it is never dragged along.

### P3-5. Reduce Motion

`accessibilityReduceMotion` (plus the `orbitForcesReducedMotion` preview seam the gauge already has). **No choreography:** the view shows `LaunchFrame(t: 1)` — the static mark in `ink`, "RYFT" at 0.32 em, the tagline — with
the same layout. **As built (launch-design §5.3, ADR 0017):** it is on screen from the first frame, holds **1.0 s**, then **cross-fades out into the app in 250 ms** (opacity only), 1.25 s in all; a tap skips as in the full
sequence. VoiceOver and **Low Power Mode** also get this variant (row 31); the gauge entrance that follows is reduced as before (plan decision 7).

### P3-6. Accessibility

- **Launch.** One element: `accessibilityElement(children: .ignore)`, label "Loading RYFT", identifier `launch.sequence`, trait `.isModal`, and a named "Skip" action (the existing string); with the tap gesture it reads as a button (row 32). Hidden: the mark, tracks, the
  wordmark (it would be read as "RYFT"), the tagline (marketing). The default action (double tap) skips too. Same element and label under Reduce Motion.
- **Gauge.** Unchanged: one element, label from the caption, value = the spoken sentence (`spokenValue`), the note after it. Ticks, halos, rings, the numeral and the Volt dot are all inside it and hidden. The state is never colour alone: arc length, dot
  position, the numeral and the sentence.
- **Flagged to the architect (not decided here):** VoiceOver focus after the hand-off (Today's first element? the header?), whether to post an announcement when the launch ends, and whether the 5.2 s is announced differently for VoiceOver users (Q6).

### P3-7. Previews and catalog

Dark only (`DarkPreview`, D3); names `"<Type>"` and `"<Type> · AX3"`; AX3 = `.environment(\.dynamicTypeSize, .accessibility3)`. The new previews replace the `SchemePair` ones in `OrbitGauge.swift` and `RyftMark.swift` (the "Mark · light" preview is deleted).

| File | Previews |
|---|---|
| `OrbitGauge` | **sizes** (260 = `.custom(dial: 248)`, `.large` 172, `.medium`, `.small`, `.custom(dial: 44)`); **board values** (strain 12.4, recovery 82 %, sleep 94 %, readiness 84, with the caption) at 260; **states** (missing a score, no readiness, zeros, 100 / 21, out of range, strain band with strain below / inside / past, no data); **calibrating** 0 / 3 / 7; **pending** with and without a previous day; **numeral** (dots at 260, Light at 172, "100" at 260); all of them again at AX3 (the gauge keeps its size, the numeral takes the Light fallback, captions scale) |
| `LaunchFrame` view | scrubbed frames **t = 0.26, 0.5, 0.76, 1** on the 390 × 844 layout, plus 0 and 0.13 and 0.86; the t = 1 frame at AX3; **Reduce Motion** (the static lockup, `forcesReducedMotion: true`) |
| `RyftMark` | "Mark" kept |

`DebugComponentCatalog`: `Nocturne · gauge` (the 260 board, `.large`, `.medium`, `.small`, every state; its XS / L / AX3 picker shows the numeral fallback) and `Nocturne · launch` (a `Slider` for t over the frame with buttons for 0, 0.26, 0.5, 0.76, 1, and a Reduce Motion toggle;
plus a Play button that runs the real sequence once; row 33).

### P3-8. Tests

Swift Testing, `@MainActor`; pure first. Names are suggestions. Files: `OrbitGaugeV3GeometryTests` (1–12, pure), `OrbitGaugeV3RenderTests` (13–17), `LaunchFrameTests` (18–30, pure, no UIKit), `LaunchRenderTests` (31–33).

**Gauge**
1. **Radii and widths at 260** (`S = 260`): 118 / 88 / 58 and fractions 0.4538 / 0.3385 / 0.2231 (±0.0001); `arcW` 3.5; outer tick 1.2 × 6, inner 1.3 × 7; dot 7, ring 3, halo 15; Volt 5 / 2.5; rail 109.5 × 3.
2. **Pitch:** outer count 128, `2π·118/128` = 5.792 (±0.005), gap 4.592; `round(2π·118/5.8)` = 128; inner 60, pitch 6.074.
3. **Tick counts by S:** 260, 172, 150 → (128, 60); 149.9, 124, 100 → (64, 30); 99.9, 84, 56 → (0, 0, solid). Floors: at 124 tick width ≥ 0.75, length ≥ 3; at 172 outer width 0.795.
4. **Arc end angles (board convention), ±0.01:** strain 12.4 → 122.571, 0 → −90, 21 → 269.99, 25 → 269.99; recovery 0.82 → −227.2, 0 → −96, 1 → −256, 0.5 → −176; sleep 0.94 → 66.4, 0 → −84, 1 → 76, 0.5 → −4. Each also within 0.5° of the board's 122.6, −227, 66.
5. **Split vs today:** `innerInset` 6, span 160; start dots (±6°) 18.4 pt apart at 260 and ≥ 2 × dot r at every S in 56…260; heads at 100 % 42.6 pt apart; code angles ±6 and ±166 at 100 %.
6. **Readiness:** 84 → lit 50 (60 ticks) / 25 (30), Volt at 212.4° board (−147.6°); 0 → 0 and the top; 100 → 60 and the top; 1 → 1; 120 → 60; −5 → 0; nil → 0 and no dot.
7. **Omitted ticks:** at 12.4 / 84: outer {74, 75, 76, 77}, inner {50, 51}; tick 49 stays; thresholds 4.857° and 7.41° (±0.01); no tick's rect reaches into a cleared ring,
   swept over strain 0…21 (0.1 steps) and readiness 0…100 at 260 and `.large`.
8. **Strain rail** present from S ≥ 102 with a usable band, absent below or without; `strainSplitDegrees` unchanged.
9. **Centre rule:** "84" dots at 260, Light at 172; "7" Light at 172 and dots at 260; "100" Light at 260; AX1 → Light; `numeral: .light` → Light; missing readiness →
   the unlit grid at 260, a Light "–" below 205.
10. **Sizes unchanged:** `.small` 84, `.medium` 124, `.large` 172 (`sizesKeepMetricGaugeFrames`), `minDialForNumber` 56.
11. **Calibrating segments:** 7, seam 9° and gap 5° visible, no tick ring; filled = `counted`.
12. **Palette:** `ink` and `signal` present; the arc colours resolve to `#63D2B4`, `#9B8AF0`, `#5E8BEA`, `alert` to `#E36B5B`; the entrance timings (`OrbitEntranceFrame`) are unchanged.
13. **Colours in pixels** (`ImageRenderer`, 260): arc heads and dots at the three metric colours, lit inner ticks `ink` (±2/255); **Volt appears only at the Volt dot**: the dot's centre is `signal`, and no pixel outside r 7.5 around it, anywhere in the gauge, is within 4/255 of `signal`; with readiness nil there is none.
14. **Ring and halo:** the annulus r 7…10 around each dot is `background` (±2) on `background` and transparent in a transparent render; r 10…15 is the metric colour at 16 % (±3); no halo below S = 110.
15. **Contrast** (replaces `OrbitGaugeContrastTests`' numbers): §P3-3 rows: metrics on `background` ≥ 3 and the printed values (10.66, 6.81, 5.94, 6.09, 17.13), over the 16 % track strain ≥ 3.97, over the 7 % ring ≥ 5.94 (sleep), lit vs unlit ≥ 12.79, Volt ≥ 3; pending at 0.6 keeps its three "under 3:1" assertions, with the new numbers: Strain on `background` 2.80, Strain over the 7 % ring 2.71, Sleep over the 7 % ring 2.98 (Sleep on `background` 3.11 and Recovery 4.38 / 4.16 stay over 3).
16. **States render:** every state of §P3-2 at 260, 172, 124, 84, 56 draws without crashing, with nonzero ink; pending dims marks (pixel ratio 0.6) and not the tracks; missing score = hollow dot (centre pixel is `background`).
17. **Entrance last frame = static render** at 260 and 172; Reduce Motion cross-fade 250 ms; spoken sentences equal the PR 2 strings for `.previewScored`.

**Launch**
18. **Constants:** `duration` 5.2; E1 / E2 / E3 control points; keyframe times 0.04, 0.06, 0.26, 0.5, 0.52, 0.74, 0.76, 0.80, 0.86, 0.88.
19. **Easing:** E1(0) = 0, E1(1) = 1, E1(0.5) = 0.7912, E2(0.5) = 0.8778, E3(0.5) = 0.8024 (±0.0005); each is non-decreasing on 0…1 (no overshoot).
20. **t = 0:** group 0, tracks 0, strain / sleep arc empty (start = end), recovery empty; dots −75.98, −59.78, −120.22; inner 0; wordmark 0 at 0.90 em; tagline 0; colours = metric.
21. **t = 0.26:** the table row (±0.01); and within 0.5° of the board: strain dot 122.6, sleep 66, recovery −227; arc lengths as fractions of 360° within 0.2 % of 55.17 / 34.94 / 29.66; inner 302.4; group 1, tracks 1; wordmark 0.
22. **t = 0.5** equals t = 0.26 in every geometry field (the hold); tracks 1 at 0.50, 0.52; 0.21 at 0.63; 0 at 0.74.
23. **t = 0.76:** geometry equals the final column exactly; colours still metric; tracks 0; wordmark opacity 0.41 and tracking 0.66 (±0.005); tagline 0.
24. **t = 0.86:** colours exactly `ink`; wordmark 1 at 0.32 em; tagline 0.96 (±0.005); t = 0.88 tagline 1.
25. **t = 1 equals the static mark:** each arc equals `RyftMarkGeometry.arcs(of:metrics:)` of `metrics(forSide: 184)` (strain (79.0203, 410.9797), sleep (−51.7828, 155.7828), recovery (204.2172, 259.7827)); dots 65 (425 − 360), −76, 180; `innerSweep` 360 with `showsInnerRing`; colours `ink`; wordmark and tagline 1; tracks 0; group 1.
26. **Rides the arc:** in phase A, `strainDot − strainArc.end` = 14.0203 and `sleepDot − sleepArc.end` = 24.2172 and `(recoveryArc.start − 360) − recoveryDot` = 24.2172 at every sampled t (±0.001); in phase B for the strain only.
27. **Direction and the lap:** phase B deltas: strain dot +302.43, sleep dot −142.40, recovery dot +407.20 (the lap); phase A: strain +198.55, sleep +126.18, recovery −107.
28. **Monotonic progress:** over t = 0…1 in steps of 1/312: group, `innerSweep`, wordmark opacity, tagline opacity and the colour mix never decrease; wordmark tracking never increases; the tracks rise to 1, stay, then fall (unimodal); within each phase every angle moves in the direction of §P3-4 and never reverses.
29. **Colour mix:** at 0.81 (mix 0.7912) strain (211, 220, 236), sleep (224, 220, 237), recovery (212, 235, 224) per 255 (±1); sRGB components, not linear.
30. **Clamping:** t < 0 equals t = 0, t > 1 equals t = 1; NaN equals 0.
31. **Pixels:** the t = 1 view at 184 pt equals `RyftMark()` in `ink` to within 2/255 per channel; t = 0.26 shows the three arcs and three dots in the metric colours at the points of row 21 (centre pixel of each dot is the colour).
32. **Layout:** on 390 × 844 the mark centre y 382, wordmark top 502, tagline bottom 780; on 375 × 667: 293.5, 413.5, 603; tagline bottom is 64 above the bottom when the home-indicator inset is 34; at AX3 the tagline stays inside the width and above the bottom.
33. **Reduce Motion:** the first frame is `LaunchFrame(t: 1)`'s look; fades are 250 ms, opacity only (no geometry changes between frames); the accessibility tree has one element, label "Loading RYFT", and no "RYFT" or tagline element.

### P3-9. Strings

Both go through `Ryft/Resources/Localizable.xcstrings`, English only (CLAUDE.md, D1). Keys are the English sentences, as in the rest of the catalog; targeted edits only (the file is dirty on `chore/domain-ryftlab`).

| Key | Comment | Used in |
|---|---|---|
| `Loading RYFT` | VoiceOver status while the launch animation plays. | the launch element's label |
| `Engineered for peak.` | The tagline under the wordmark on the launch screen. | tagline `Text` |

"RYFT" (the wordmark) stays `Text(verbatim:)` as in `Wordmark`. No other string is added: the gauge's sentences are unchanged, and the skip action reuses "Skip".

### P3-10. Deviations

| # | Board | Brief | Spec | Why |
|---|---|---|---|---|
| 1 | Hold angles 122.6 / 66 / −227, CSS lengths 55.17 / 34.94 / 29.66 %, arc ends 108.61 / 41.78 / −202.78 | §5 gives 122.6°, 66°, −227° | 122.571 / 66.4 / −227.2 from the gauge's own mapping (12.4/21, 94 %, 82 %); arcs 55.15 / 35.05 / 29.72 %; ends 108.55 / 42.18 / −202.98 | the board rounds to whole degrees; deriving from the fractions makes the hold frame the gauge's reading. Differences ≤ 0.4° |
| 2 | Dot angles at 0 %: −76, −59.78, −120.22 | "the dots ride the arc ends" | −75.98, −59.78, −120.22 = arc head ± the mark's clear air | the board's rule, not an override: head and dot are one clear air apart from t = 0 and at t = 1, so one rule runs the whole sequence. A dot exactly on the arc end would have to open the air during phase B (Q3) |
| 3 | Dots animate separately from arcs in 26 → 76 % | §5: strain dot +302°, sleep −142°, recovery +407° | as both | consistent; the dots do not follow the arcs in phase B (sleep, recovery), by design |
| 4 | Tracks in at 0 → 6 %, out at 52 → 74 % | "blenden ein" in 0–26 %, "aus" in 50–76 % | the board's | inside the brief's windows |
| 5 | Group opacity 0 → 1 by 4 % | not mentioned | kept | the first frame is empty, so it follows the empty launch screen without a pop |
| 6 | Inner ring colour not listed | readiness inside | `ink` throughout | the gauge's readiness is `ink` |
| 7 | Tagline "ease" | "blendet ein" | CSS `ease` = cubic-bezier(.25, .1, .25, 1) | |
| 8 | Wordmark "28 pt below the mark" | — | below the 184 box (line top at H/2 + 80) | the board is an HTML box; the ring edge is 8 pt inside the box |
| 9 | Loop fade at 94 → 100 % | "einmal" | not played; t = 1 is the static lockup | the hand-off is the architect's |
| 10 | — | "das Logo wandert in den Header" | cross-fade in PR 3 | `WordmarkLockup` is on no screen until PR 4 (Q4) |
| 11 | Today ring "like today", inner starts at the vertical | "getrennt an der Vertikalen wie heute" | ±6° start, 160° span (today ±12.5°, 155°) | the plan's table; the structure is today's |
| 12 | Outer tick pitch 5.8 | "Abstand ~4.6 pt" | 128 ticks, pitch 5.792 | the nearest whole count that tiles the circle |
| 13 | Dot "3 pt `background` ring" | same | a 3 pt cleared annulus (`destinationOut`) | identical on `background`; right on `surface` and in the widget's tinted modes |
| 14 | Halo r 15 at the outer ring reaches 133 > 130 | | kept, not clipped | 3 pt at 16 % |
| 15 | Centre `DotNumeral` | "DotNumeral oder Light 52" | dots only when the numeral fits (S ≥ 205, two digits); Light 0.2 × S otherwise, "100" always | the 5 pt grid does not scale: "100" is 115 pt, the free diameter 109 |
| 16 | Ring tint: readiness band colours (today) | lit ticks `ink` | no band colour in the gauge | §3; the band is in the caption and the sentence |
| 17 | Ticks at 1.2 wide down to any size | | tiers 128 / 64 / solid, floors 0.75 × 3 | a hairline tick ring turns grey below 150 pt |
| 18 | No readiness marker for a missing value | | none | Volt marks a value |
| 19 | Tracks as `SurfaceRaised` (PR 1 T4) | 7–16 % | `ink` at 7 / 13 / 16 % (16 % = the same pixel as `SurfaceRaised` on `background`) | T4 said PR 3 draws 7 and 13 % this way |

Recorded from the implementation (T3.2) and the code review, 2026-11-16:

| # | Spec said | Code does | Why |
|---|---|---|---|
| 20 | Dots whenever the numeral fits | dots only where a two-digit grid ("00", 74 pt) fits the slot, S ≥ 205.2, *and* the value fits | one look per gauge size: a single digit at `.large` fitted and drew dots next to a Light "84" (lead) |
| 21 | Light `weight: .light` | `ryftNumber(size:)` under ADR 0016's floor | Regular below 20 pt, so `.small` (16.8) and the 56–60 dials (13.6–14.4) draw Regular, as everywhere else |
| 22 | The unlit grid for pending or missing readiness | the grid at S ≥ 205; a Light "–" in `textTertiary` below | the grid isn't used below 205 (row 20) |
| 23 | Lit inner ticks before the halos and cuts; ticks omitted by centre distance | lit ticks after the cuts; a tick is omitted when its rect comes within a dot's cleared ring | ticks are never cut, only whole or absent; by centre distance a whole tick reached 0.59 pt into the strain dot's ring (strain 20.3) |
| 24 | Light numeral in the slot at `minimumScaleFactor(0.5)` | it also scales with Dynamic Type from `.largeTitle`, never below 0.2 × S; the calibrating count gets the same 0.5 minimum | "about 78 pt at AX3" (P3-1); "84" measures 78.7 × 51.3 at AX3 on 260, and "100" fits at AX5 |
| 25 | Caption at `.large` only | from a 160 dial up | so the 260 board shows it; Today (`.large`) is unchanged |
| 26 | Entrance unchanged | the Volt dot fades in over the first quarter of the glide; the halo follows the flight | the Volt dot is new in v3 and must not appear before its value |
| 27 | Band stroke < outer stroke | ≤ | both sit at the 1.5 pt floor up to S 111 |
| 28 | — | `OrbitGaugeBandRail` and `palette.track` removed; static gauge and entrance draw one `OrbitGaugeScene` | the entrance's last frame is the static render by construction |
| 29 | Tracks in `ink` in every rendering mode | the widget's non-full-colour modes keep white 25 % tracks | a 7 % ring vanishes on the Lock Screen (lead) |

Recorded from the launch implementation (T3.3) and its code review, 2026-11-16:

| # | Spec said | Code does | Why |
|---|---|---|---|
| 30 | Reduced: 250 ms fade-in, 1.0 s hold, 250 ms out (1.5 s) | on screen from the first frame, 1.0 s hold, 250 ms out (1.25 s) | the first frame continues the launch screen; launch-design §5.3 |
| 31 | Low Power Mode is not reduced | Low Power Mode → reduced | ADR 0017 and launch-design §6.2: no 5.2 s animation when the user asked the phone to save power |
| 32 | Identifier `launchSequence`, static text, unannounced skip | `launch.sequence`, `.isModal`, a named "Skip" action; exposed as a button | launch-design §8: VoiceOver users must be able to find the skip |
| 33 | Catalog: scrubber only, no auto-play | scrubber plus a Play button | launch-design §10 asks for a replay to judge the motion |
| 34 | Hold angles from the gauge's mapping | the launch's strain head uses `OrbitGaugeGeometry`'s own mapping (fix round), 122.565° | one formula for the gauge and the launch |

### P3-11. Open questions

Answered by the lead on 2026-11-16: Q1 → L3, Q2 → L4, Q3 → L5, Q4 → L6, Q5 → L7, Q7–Q9 → L8 (`plan.md`); Q6 → `launch-design.md`.

For the lead:
- **Q1.** Keep `OrbitGaugeSize` as is (`.large` = 172, v3 scaled) and reach the 260 board with `.custom(dial: 248)`, adding a `.hero` size in PR 4? The alternative (`.large` becomes 260 now) grows Today by 88 pt before PR 4 lays it out.
- **Q2.** The v3 drawing is in `Shared/` (`OrbitGaugeDrawing`, `OrbitGaugeGeometry`, `OrbitGaugePalette`), so the widget gets it. The palette needs `ink` and `signal`; the widget catalog has `Signal` but no `TextPrimary` (it uses `Brand.ink`). Add a `TextPrimary` colorset (and `check-shared-types.py`) or pass `ink` from `Brand`?
- **Q3.** Brief §5 "dots ride the arc ends": taken as head + the mark's clear air (the board's numbers). If you want the literal reading (a dot on the head), the air must open between 0.50 and 0.76 and the hold frame differs from the board by 14° / 24° of arc.
- **Q4.** The brief's "logo travels into the header" needs a header lock-up on screen: PR 4. PR 3 cross-fades. OK?
- **Q5.** Today's thin-digit switch (brief §1) needs a numeral style on the gauge: an additive `numeral:` parameter (default `.dots`), in PR 3 or with Today in PR 4?

For the architect (`launch-design.md`):
- **Q6.** Visual facts you need: the sequence ends on a static lockup at t = 1 (5.2 s); constant from t = 0.88. If the hand-off starts at 0.94 as the board's loop does, nothing in `LaunchFrame` changes. Reduce Motion proposal: 250 ms fade-in, 1.0 s hold, 250 ms cross-fade out; skip = freeze the current frame and cross-fade out in 250 ms. Yours to decide: the hold, the skip's hand-off, VoiceOver focus and an announcement afterwards, how VoiceOver users skip (the default action is there, unannounced), Low Power Mode, whether the gauge entrance starts when the fade starts or ends, and that the first frame (group opacity 0) continues the `UILaunchScreen`, whose `Graphite` is `#0A0C0B` since PR 1.

For the ios-developer:
- **Q7.** `Wordmark` needs a `tracking` parameter (default 0.32, additive) for the animated launch wordmark.
- **Q8.** `RyftMarkShape`'s arc and dot path builders become static functions the launch view shares.
- **Q9.** "28 pt below the mark" is read as below the box (Deviation 8); say if it is below the ring's edge (+8 pt).

## PR 4 — Today and Sleep

Scope: the layout, states, data, accessibility and strings of Today and Sleep in Nocturne; the glow tile's per-kind shape; the
launch's matched move; the thin-digit switch. Inputs: `plan.md` "PR 4 in detail" (board measurements, L14–L18, criteria 1–6) and
the PR 2 and PR 3 sections above. Nothing here changes the model, the sync or the API; data the screens need and the app lacks is
inventoried in §P4-4. Lifecycle of the launch is `launch-design.md`; §P4-7 gives the visuals and the seams it needs.

Conventions. Boards are 390 pt wide; content is **350 pt** (20 pt sides); CSS px = pt. "Ink" is `Theme.textPrimary`. The boards' ink alphas
map to tokens: **0.62 = `textSecondary`**, **0.55 and 0.45 = `textTertiary` (48 %, PR 1 D-a)**, 0.78 = a glow-tile label
(§P4-3). Gaps are from the bottom of the element above to the top of the next; a text line is its natural height (the Satoshi
line box), not a number from the board. Fixed heights (header 40, gauge 260, ruler 36, tiles 124 / 96 / 168 / 88) are exact. The board's 56 pt
top inset is its status-bar frame, not a layout number: content starts at the safe-area top (deviation D4-1). Layout constants are
`nonisolated static let`s on `TodayLayout` / `SleepLayout` (P2-D9) so tests assert numbers, not pixels.

### P4-1. Today

Top to bottom (`ScrollView`, content `VStack(spacing: 0)` with the gaps below; `ScreenScaffold(showsHeader: false)`, §P4-12):

| # | Element | Built from | Size and gap |
|---|---|---|---|
| 1 | **Header** | `ScreenHeader`: leading `WordmarkLockup(markSize: 26, handOff: true)` (mark 26, gap 10, "RYFT" 15 Light 0.32 em; stroke and dots by `RyftMarkGeometry.metrics(forSide: 26)`); trailing `CircleButton(systemImage: "calendar", iconSize: 16, label "Calendar")` opens My Day on today (`screens.myDay.select(today)`, push). Hidden, not disabled, when `screens.myDay.isEnabled` is false; the row keeps its height | 40 high; the circle's edge on the 20 pt inset (its 44 pt box overflows 2 pt, not clipped) |
| 2 | **Greeting** | `Text(model.greeting)` `.ryft(.title)` (26 Light), tracking −0.26 pt (−0.01 em), `textPrimary`, leading, header trait, `lineLimit(2)`. Time of day as today (05–12 morning, 12–18 afternoon, else evening). Name: first word of `User.name` (`full_name`), trimmed; none when empty ("Good evening", no comma) | 18 below the header |
| 3 | **Sub-line** | `Text(verbatim: "\(date) · \(day.sentence)")`, `.ryft(.label)` (13), `textSecondary`, leading, wraps. `date` = `EEEE, MMM d` from `env.clock`. The sentence is `TodayContent.sentence` as today | 4 below the greeting |
| 4 | **Status row** | `SyncStatusLineView`, leading-aligned (was centred), `.caption` 12, colours and states as today (`syncLine`); visual height is the text's, the tap target 44 (`contentShape(Rectangle().inset(by: -14))`), so it adds one line (≈ 16 pt) to the board (D4-2). It is where today's sync status text lives: "Updated 07:15", "Scoring your night", "Offline — will sync when back", "Showing data from 14:05 · Try again", "Action needed…", "Demo data · …" | 4 below the sub-line |
| 5 | **Import row** | `ImportRow` (slim, after the first score) when `day.importRow` | 12 below the status row; none otherwise |
| 6 | **Hero gauge** | `OrbitGauge(mode: day.orbit, size: .hero, caption: Caption(title: "Overall readiness", delta:, showsBand:), showsCaption: false, numeral: heroNumerals.style, accessibilityNote:, identifier:, entrance:)`. `OrbitGaugeSize.hero = .custom(dial: 248)`: frame 260 (L14). Centred; never clipped (the halo reaches 3 pt past the frame). Same size in every hero state so nothing jumps: scored, pending, calibrating, empty | 14 below row 4 (or 5). The caption is drawn by row 7, not the gauge; `caption` stays so the sentence still carries the band and the change |
| 7 | **Label row** | `HStack(spacing: 10)`, centred, 13 pt: `Text("Readiness · \(band)")` `textSecondary`; `DeltaLabel(spec: .readiness, delta: day.readinessDelta, reference: "vs 7 d", font: .ryft(.label), referenceColor: <delta colour>)` ("▲ +11 vs 7 d", teal up, `alert` down). No band while a calibration note owns the line (`showsReadinessBand` false): "Readiness" alone. At AX the two stack, centred. Hidden from VoiceOver (the gauge says it) | 8 below the gauge |
| 8 | **Gauge note** | `noteBlock(day.gaugeNote)` as today (`GaugeNote`, its link), centred | 8 below row 7; none without a note |
| 9 | **Ruler** | `RulerScale(range: 0...100, value: day.readiness, zone: RulerScale.zone(lo: 67, hi: 100), zoneStyle: .standard, tickCount: Ticks.today, labels: ["0", "low", "moderate", "high", "100"], size: .regular)`. Full 350 pt. The band is the high one (`MetricSpec.scoreBand`: ≥ 67), always marked, not "the current band". No zone and labels `["0", "100"]` while `showsReadinessBand` is false (a borrowed number is not placed in a band). No needle without a readiness | 12 below row 7 (or 8); 36 high plus the labels |
| 10 | **Attention cards** | `RawNightCard`, `WatchSyncHintCard` (pending night only), on `Card` (surface), full width | 12 below the ruler, 12 apart |
| 11 | **Two glow tiles** | `HStack(spacing: 12)`, 169 × 124 each, `GlowTile(…, kind: .twoUp)` (radius 24). **Recovery** (teal): row 1 "Recovery" leading, `Sparkline` trailing; row 2 (bottom-left, 16 / 12): "82" `.numberLarge` + "%" label; trailing caption (§ below). **Sleep** (violet): row 1 "Sleep" leading, `DotRow` of 7 nights trailing (66 × 6); row 2 "7:48" `.numberLarge` + "h". Each tile is one button (Recovery → Insights, Sleep → Sleep). The same day for both and for Strain (`tilesDimmed` day or "calibrating" shows as the caption, not as dimmed ink) | 22 below the ruler (12 below row 10 if present) |
| 12 | **Strain glow tile** | `GlowTile(Theme.metricStrain, kind: .strain)`, 350 × 96 (radius 24). Row: "Strain" label leading; "12.4" `ryftNumber(size: 30)` Light, pushed right; "of 21 · moderate" label (6 after the value). Below, 16 in from the sides and 12 above the bottom: compact `RulerScale(range: 0...21, value: strain, zone: RulerScale.zone(lo: 10, hi: 14), zoneStyle: .strain, tickCount: Ticks.strainCompact, labels: [], size: .compact)`. One button → Strain | 12 below row 11 |
| 13 | **Cards below** | In today's order, on `surface` cards, 12 apart: `HealthAccessHint`, `PushPrePromptCard`, **My Day**, `JournalCard`, `TonightCard`, `TrainTodayCard`, Trends (7-day readiness chart), then `status` (the error cards, last: it is the "Details" scroll target) | 24 below row 12 (`sectionSpacing`, derived) |

The recovery tile's trailing caption is `day.recoveryCaption` (band word "High", the day "Yesterday", or "calibrating"); the Sleep tile's
and the Strain tile's day / "calibrating" caption is `day.tileCaption` (Strain puts it in its label: "Strain · Yesterday"). All 13 pt, glow
label style. The 2-up tile's two rows are placed derived-not-measured as: row 1 baseline-aligned with the label, series right-aligned at the
16 pt inset (the board names the content, not the place). At AX1 and up the pair stacks (`VStack(spacing: 12)`), rows stack inside a tile
(label, series, value), tiles grow (minHeight 124 / 96 stay), the strain row stacks (label, value and "of 21 · …", ruler).

`Sparkline(values: [Double?], size 58 × 20)`: 7 points (the last 7 days' `DailyScore.hrvMs`, oldest first, the last is the tile's day), x at `i/6 × 58`,
y from the series' min to max inside a 2 pt inset (flat at mid height when min = max), straight segments, 1.3 pt `textPrimary` at 80 %, round caps and
joins; a missing day breaks the line (no interpolation), a lone point draws only its dot. The end dot is Volt r 3 with a 1.5 pt cleared ring (as the
gauge's dots), drawn only when the last point has a value (L17: it is the "today" mark of a series). Under two values: **pending look**, a flat
1 pt `textPrimary` 22 % line across, no dot. VoiceOver: hidden, the tile says it.

What Today has that the board does not, and where it goes (nothing is dropped except the first row, for the lead):

| Today now | In Nocturne |
|---|---|
| `MiniHypnogram` card behind `today.redesign` (default off) | **Proposed drop** (Q3): Sleep's tile and the Sleep tab show the night. The flag stays in `Seams`, unused |
| `ImportCard` (first import, replaces the gauge), `ImportRow`, `SetupCard`, `RawNightCard`, `WatchSyncHintCard`, `HealthAccessHint`, `PushPrePromptCard`, `RefreshIssueCard` / `InlineMessage` (`status`) | Kept, same rules, restyled by `Card` (22 pt, surface); positions in the table above |
| Sync status line, "Offline", "stale", "gated", "demo" | Row 4; the gate's `InlineMessage` stays last |
| Three `MetricTile`s with tint, icon, band caption, dimmed ink | Two glow tiles + the strain tile; icons gone (colour is the legend); dimming becomes the caption |
| Gauge caption ("Overall readiness", band, delta) | Row 7 (visible), the gauge's sentence (spoken) |
| Trends card, My Day, Journal, Tonight, Train card | Below the glow block (row 13) |
| Coach marks (`.gauges`, `.physiology`, `.trends`) | Targets move with the views: gauge + label + ruler, the tiles block, the Trends card |
| Pull to refresh, journal / calibration / sync-details sheets, `-RyftOpenMyDay` | Unchanged |
| Tab bar, `RyftHeader` on the other tabs | Unchanged until PR 5 |

### P4-2. Sleep

`ScreenScaffold(showsHeader: false)`. Day mode is the board; Week, Month and Bedtime keep their content. All sizes below are for Day mode.

| # | Element | Built from | Size and gap |
|---|---|---|---|
| 1 | **Header** | `ScreenHeader`: `CircleButton("chevron.left", "Previous night")` · centre: "Sleep" `.ryft(.callout)` (15), header trait, and 2 below, "Last night · Sun, Nov 15" `.caption` (12) `textTertiary` (+ `DayMarker`, as today) · `CircleButton("chevron.right", "Next night")`. Chevrons 14 pt. Week / Month: the buttons stay in the layout, hidden and disabled; the subtitle is "Last 7 nights" / "Last 30 nights"; Bedtime: "Tonight" | 40 high |
| 2 | **Mode picker** | `SegmentedPicker` Day · Week · Month · Bedtime, as today (restyled in PR 5) | 12 below the header, 36 high. **Shifts everything below by 48 pt** against the board (D4-3, Q1) |
| 3 | **Numeral** | `DotNumeral(clock(totalMin), glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00", accessibilityLabel: "7 hours 48 minutes asleep")`; `style` from the hero-numbers preference; 125 × 47; centred | 22 below row 2 (the board's: below the header) |
| 4 | **Caption** | `Text("Asleep · 94 % of your need")` 13 `textSecondary`, centred, wraps; "Asleep" alone without `sleepPerformance`; a nap chip (as today, `Label` on `surfaceRaised`) moves to the Details card | 12 below the numeral |
| 5 | **Ruler** | `RulerScale(range: 0...10, value: totalMin/60, zone: RulerScale.zone(lo: 0.9·need/60, hi: need/60), zoneStyle: .sleep, tickCount: Ticks.sleep, labels: ["0 h", "need 8:18", "10 h"], size: .regular)`; the zone is the last 10 % below the need (the board's 7.5–8.3 h for 8:18; D4-6); no zone or middle label without a need | 14 below the caption, 36 high plus labels |
| 6 | **Hypnogram tile** | `GlowTile(Theme.metricSleep, kind: .hypnogram)`, 350 × 168 (radius 28); §P4-2a | 20 below the ruler |
| 7 | **2 × 2 neutral tiles** | `LazyVGrid` of two flexible columns, gap 12; each 169 × 88, `surface`, radius 22 (`neutralTileRadius`), padding 14 / 16: label 13 `textSecondary`, value `.metric` (26 Light) + unit 12 `textTertiary`, bottom-left at 16 / 12. **Consistency** "86" + "%" and a 7-night `DotRow` bottom-right (full = that night's consistency ≥ 60, the platform's own threshold; `.noData` for a night without one; last = the night shown). **Sleep debt** "0:30" + "h", and "▼ 0:42" 12 pt in the sleep colour (debt against the night before; "None" with no unit at 0; ▲ in `textSecondary` when it grew; a high debt, > 45 min as today, adds "· high" in `warning`). **Efficiency** "95" + "%". **Restorative** "3:20" + "h", "Deep + REM" 12 `textTertiary` (deep + REM minutes from `stages`; the platform's `restorative` score is in the spoken value). Not buttons | 12 below the hypnogram tile |
| 8 | **Need card** | `Card { SleepNeedBar }` → `SleepNeedSheet`, as today (`sleep.need`) | 12 below the tiles |
| 9 | **Stages card** | `StageRow` ×4 (minutes and shares) on a `Card`; the proportional `StageBar` is dropped (Q3) | 12 below |
| 10 | **Details card** | Nap chip + "A nap lowers tonight's sleep need.", Quality ("91 · Good" with `ProgressBar`) and its "Quality is 60 % …" footnote, Bedtime, Wake time, planned vs actual, Time in bed, Sleep need (when no breakdown), Actual (+ "% of need"). The rows that repeat a tile (Efficiency, Sleep debt) go | 12 below |

States of the content below the header live in §P4-5. The nap chip stays out of the board's column so a night with a nap has the board's geometry.

**P4-2a. The hypnogram tile** (`HypnogramPlot`, a new `Design/` view; the Charts-based `Hypnogram` stays for the catalog):

| Part | Spec |
|---|---|
| Header row | "Hypnogram" 13, label style, leading; "22:50 – 07:00" 12, label style, trailing (`sleep.start` – `sleep.end` in the screen's locale; "–" ends without `end`) |
| Body | 10 below the header: a **38 pt column** of stage names top to bottom "Awake, REM, Light, Deep", `.axis` (11), label style, each centred on its grid line; then the plot |
| Plot | 90 high, the rest of the width. Four grid lines (ink 8 %, 1 pt) at y = 4, 31.33, 58.67, 86: Awake, REM, Light, Deep (`asleep` = unknown stage plots on Light). X = time linearly from `start` to `end`, no tick labels (the range is in the header) |
| Step line | One path per night: for each segment (oldest first, clamped to the night) a horizontal run at its level, a vertical join at each change; 1.4 pt, ink 85 %, round joins, no smoothing. A gap between segments breaks the path |
| Deep bars | For each Deep segment a bar on the Deep line: 8 high, radius 4, `metricSleep`, at least 3 pt wide |
| Totals | 8 below the plot, 12 pt, label style, four items spread edge to edge: "Deep 1:35", "REM 1:45", "Light 4:28", "Awake 0:22" (stage minutes from `stages`, `h:mm`). A stage with no minutes reads "–" |
| AX1+ | Column = the widest stage name (measured); plot height = max(90, 4 × the name's line height); totals wrap to a 2 × 2 grid; the header stacks |
| VoiceOver | One element, "Hypnogram, 10:50 PM to 7:00 AM", value "Deep 1 hour 35 minutes, REM 1 hour 45 minutes, light 4 hours 28 minutes, awake 22 minutes" |
| No segments, stages known | Tile with the header and the totals only (96 high) and "The timeline isn't available for this night." |
| No stages | Tile keeps the header and says "Your watch didn't record sleep stages for this night — only the total." (existing string); no plot, no totals |

### P4-3. The glow, per kind

The board's three ellipses differ, and the 2-up one is much brighter at the corners (about 72 % metric colour; the PR 2 spec took the dark end of every range, P2-D1, which the user superseded on 2026-11-16). `GlowTileSpec` changes from one ellipse to one per kind:

```swift
enum GlowTileSpec.Kind { case twoUp, strain, hypnogram, panel }
//            ellipse (rx, ry, cy)      stops (background opacity at t)               radius  minHeight
// twoUp      0.85, 0.80, 0.50          .97 @0, .92 @.30, .55 @.65, .10 @1            24      124
// strain     0.90, 1.10, 0.55          .97 @0, .92 @.32, .55 @.66, .10 @1            24       96
// hypnogram  0.90, 0.95, 0.55          .97 @0, .92 @.34, .55 @.68, .10 @1            28      168
// panel      0.90, 1.10, 0.55          .97 @0, .92 @.34, .55 @.68, .10 @1            28      172   (PR 2's single ellipse; Insights "An idea", PR 5)
static func shape(for kind: Kind, size: CGSize) -> Shape   // pure; twoUp falls back to panel's ellipse and stops when size.width > 200 or size.height > 160
GlowTile.init(_ metric: Color, kind: Kind, minHeight: CGFloat? = nil, reduceTransparency: Bool? = nil, content:)
// the PR 2 init(_:radius:) stays as a shim for the catalog: .tile → panel at 24, .hero → panel at 28
static func labelOpacity(metric: Color, typeSize: DynamicTypeSize) -> Double   // 1.0 for Theme.recovery at every size; 0.78 otherwise below AX1; 1.0 from AX1
```

`GlowTile` publishes the label opacity through a new environment value (`glowLabelOpacity`); `ryftGlowLabelStyle()` and the compact ruler's labels read it, so a view inside a recovery tile cannot forget. **Inside a glow tile there are only two inks: `textPrimary` (numerals, the primary text) and the label opacity (every other word, unit, caption, axis label and time); the board's 0.62 and 0.55 do not exist there** (they fail, below). Graphics: sparkline ink 80 %, step line ink 85 %, grid ink 8 % (decoration), `DotRow` and the ruler as built, Volt for the marks.
The twoUp fallback: a wide or tall 2-up (AX single column, 350 pt) would otherwise put the corners under 4.5:1 even in full ink (350 × 124 recovery: 4.41); it takes the PR 2 ellipse, which passes there (6.63).

**Contrast in the core.** WCAG 2.x, sRGB composite of `Theme.background` over the metric colour by `overlayOpacity(t)`, text composited over that pixel. "Text rect" is the padded rect the text sits in (16 sides, 14 top, 12 bottom: the value row is 12 up), worst pixel on a 40 × 40 grid (computed with a small script; test 10 reproduces it).

| Tile (default size) | Ellipse, worst `t` | `textPrimary` | Label as specified | Board's 0.78 / 0.62 / 0.55 | Needs |
|---|---|---|---|---|---|
| Recovery 2-up 169 × 124 | 85 × 80, 0.694 at (16, 112) | 5.07 | **100 % → 5.07** | 3.78 / 2.99 / 2.69 | 4.5 |
| Sleep 2-up 169 × 124 | same | 6.86 | **78 % → 4.92** | — / 3.75 / 3.30 | 4.5 |
| Strain 350 × 96 | 90 × 110, 0.624 at (16, 14) | 9.09 | **78 % → 6.25** | — / 4.60 / 3.97 | 4.5 |
| Hypnogram 350 × 168 | 90 × 95, 0.704 at (16, 14) | 7.21 | **78 % → 5.13** | — / 3.89 / 3.42 | 4.5 |

Other widths with the label rule: 2-up at 161 × 124 (SE) 5.14 recovery / 4.96 sleep, at 194 × 124 (Pro Max) 4.90 / 4.80, at 169 × 160 4.73 / 4.68; strain 335…400 wide 6.28…6.19; hypnogram 335…400 wide 5.15…5.07. The lowest alpha that reaches 4.5 in the same rect: recovery 2-up 91 %, sleep 2-up 73 %, strain 61 %, hypnogram 70 %. The board's 0.62 and 0.55 pass only in the strain tile (0.62 → 4.60, 0.10 of margin); everywhere else they fail, so the rule above replaces them (D4-4).
**AX3** (labels and numerals at 100 %, single column 350 wide, the panel ellipse for the 2-up): recovery 350 × 124…300: 6.63…5.89; sleep 8.51…7.74; strain 350 × 150…300: 8.52…7.93; hypnogram 350 × 260…420: 6.73…6.41. All ≥ 4.5.
Graphics (≥ 3:1, same rects): sparkline ink 80 % over the recovery top-right corner 4.06; Volt there 5.27 (sleep 7.06); `DotRow` missed outline (ink 50 %) in the sleep tile's top-right corner 3.09 (**margin 0.09**: nothing may lower `DotRow.outlineOpacity`); step line ink 85 % in the hypnogram plot 7.29; Deep bars `metricSleep` 4.09 on the Deep line (3.68 anywhere in the plot); the compact ruler's zone ticks (ink 60 %) 4.69, its Volt needle 9.79. Neutral tiles: `textSecondary` 6.78, `textTertiary` 4.54 on `surface`; the debt delta (`metricSleep`) 6.38.
**Reduce Transparency** (flat `surface`, 2 pt metric border): ink 16.24, label 78 % 10.13, `textSecondary` 6.78, sparkline 12.7, deep bars 6.38.

### P4-4. Data inventory (L18)

"Exists" means a view-model property or a cached API field today; every row below was checked against `Models.swift` and `API.md`. Nothing is invented on a device: a missing value is a pending look, never a number.

| # | Board element | Source today | Status | When it is absent (look) |
|---|---|---|---|---|
| T1 | Greeting word | `ReadinessCopy.greeting(at:)` | exists | — |
| T2 | First name | `AppState.user?.name` (`user_metadata.full_name`), first word; needs a new `TodayViewModel.firstName` | **partly**: empty for some Apple sign-ins | "Good evening" without name or comma. **R-N2** |
| T3 | Date in the sub-line | `env.clock.now()` | exists | — |
| T4 | Sentence, sync line | `TodayContent.sentence`, `syncLine` | exists | — |
| T5 | Gauge values, numeral | `day.orbit` | exists | PR 3's states |
| T6 | "Readiness · High" | `MetricSpec.scoreBand` | exists | band word dropped while `showsReadinessBand` is false |
| T7 | "▲ +11 vs 7 d" | `day.readinessDelta` (`GET /v1/trends` readiness 7d, `readinessWeek`) | exists | nothing renders (no "—") |
| T8 | Ruler: value, zone ≥ 67 | `day.readiness`, `scoreBand` thresholds | exists | no needle; no zone when the band is withheld |
| T9 | Recovery value, caption | `day.recovery`, `recoveryCaption` | exists | "–" and "calibrating" |
| T10 | HRV sparkline | `DailyScore.hrvMs` of the last 7 days, `AppState.history` (90 days cached); needs a new `TodayViewModel.hrvWeek: [Double?]` | exists in the cache | gaps break the line; under two values the flat pending line, no Volt dot |
| T11 | Sleep value | `day.sleepText` → `Fmt.clock(minutes:)` (new, "7:48") | exists | "–" |
| T12 | 7 nights of dots | `history[].sleepActualMin` against `sleepNeedMin`: full = slept at least the need; derived, no new score. New `TodayViewModel.sleepNights: [DotRow.Mark]` | exists, **rule is the app's** (Q5) | `.noData` mark for a night without both numbers |
| T13 | Strain value | `day.strainText` | exists | "–" |
| T14 | Strain word and zone 10–14 | `MetricSpec.strainBand` (thresholds 10 / 14 / 18) | **partly**: the moderate band, not a personal target | the zone is labelled by the band word, never "target". **R-N1** |
| T15 | Cards below | existing models | exists | — |
| S1 | Night title, date | `SleepViewModel.date`, `isToday`, `subtitle` | exists | — |
| S2 | Previous disabled at the oldest night | new `SleepViewModel.oldestNight` = first `history` day with `sleepActualMin`, else today − 89 | exists | chevron 35 %, "Previous night" dimmed |
| S3 | Duration | `sleep.totalMin` | exists | `DotNumeral(nil)`, unlit "0:00" |
| S4 | "94 % of your need" | `score.sleepPerformance` | exists | "Asleep" alone |
| S5 | Need, zone | `score.sleepNeedMin ?? sleep.need?.total`; zone = 90–100 % of it (display choice, Q6) | exists | no zone, no middle label |
| S6 | Hypnogram | `sleep.segments` (`GET /v1/days/{day}` only, so an uncached night loads on the step) | exists | §P4-2a states |
| S7 | Time range | `sleep.start`, `sleep.end` | exists | "–" |
| S8 | Phase totals | `sleep.stages[].min` | exists | "–" per stage |
| S9 | Consistency | `score.sleepConsistency` (needs 5 nights) | exists | "–" |
| S10 | Consistency dots | `history[].sleepConsistency` per night, full ≥ 60 (`sleep-consistency-low` fires below 60) | exists | `.noData` |
| S11 | Debt and its delta | `score.sleepDebtMin`; delta = debt minus the night before's (`AppState.score(for: date − 1)`) | exists (difference of two server values) | no delta without both |
| S12 | Efficiency | `sleep.efficiencyPercent` | exists | "–" |
| S13 | Restorative "3:20 h" | deep + REM from `sleep.stages` (the board's value is a duration, the API's `restorative` is a 0–100 score) | exists | "–"; the score is spoken |

**Missing, with placeholders and requests.** The placeholder is `MockData` (previews, demo) plus the pending look; the phone shows nothing for them on a real account until the platform answers.

| Id | Missing | Placeholder | One-line `API_REQUESTS.md` entry |
|---|---|---|---|
| R-N1 | A personal strain target (the board's "target 10–14", and `OrbitGaugeValues.strainBand`) | Today's zone is the fixed moderate band from `MetricSpec`; `MockData` has no target | `DailyScore.strain_target_min` / `strain_target_max` (number?, the day's recommended strain range, null before the baselines exist): Today's compact ruler and Strain's ruler zone, and the gauge's band rail, are the target, not the app's fixed band. |
| R-N2 | An editable display name | Greeting without a name; `MockData.user.name` for previews | `PATCH /v1/me` `name` (string, ≤ 40): Sign in with Apple may deliver no name, so Today's "Good evening, ‹first name›" falls back to nothing; Profile (PR 5) edits it. |
| R-N3 (optional) | A nightly "slept enough" fact for the 7-night dots | derived: `sleepActualMin ≥ sleepNeedMin` | `DailyScore.sleep_need_met` (bool?, `sleep_actual_min ≥ sleep_need_min`): only if the platform wants the rule on its side; Today's Sleep tile and Sleep's dots would read it instead of comparing two numbers. |

MockData must give the previews the board's night (T4.0): asleep 468, awake 22, deep 95, REM 105, light 268, latency 0 (22:50 – 07:00), efficiency 95, a nap credit of 40 so the need is 498 and the performance 94, debt 30 today and 72 the night before (the ▼ 0:42), consistency 86, plus a `hrv_ms` series and a mix of met / missed / no-data nights in the last seven. Readiness 84 with the week 72, 66, 75, 70, 79, 76 already gives "+11 vs 7 d".

### P4-5. States

Every state keeps its reason and its one action; none is a blank screen or a spinner. Pending is an outline: the unlit numeral grid, tracks, ticks without a needle, outline tiles.

**Today.** "Gauge" is PR 3's state; the other rows are the new layout's.

| State | Trigger | Look |
|---|---|---|
| Scored | `hero == .score`, row A | The table in §P4-1. |
| Pending night, with a previous day | `hero == .pending`, `previousReadiness != nil` | Gauge pending (dimmed, breathing); row 7 becomes the centred pending block: "Last scored: Yesterday" (caption, `textTertiary`), "Scoring your night…" (`.label`, `textPrimary`), the detail (`.caption`, `textSecondary`); the ruler has ticks, zone and labels but **no needle**; tiles show the latest scored day with the day as caption; `RawNightCard` under the ruler. Slow scoring: the gauge stops breathing, the title is "Still scoring your night" |
| Pending, nothing scored | `waitingForSleep`, no previous | Unlit grid; same block; tiles hidden (`showsTiles` false); `WatchSyncHintCard` if the night is late |
| Calibrating | `hero == .calibrating` | Gauge segments + "3 / 7"; row 7 is "Baselines" (no band, no delta); note and link in row 8; ruler without needle and zone, labels "0 · 100"; tiles after `showsTiles`, with "calibrating" captions and Recovery "–" where withheld |
| Calibrating, with a readiness | `.learning` note (S2), `.blocked` (N1) | Gauge scored; "Readiness" alone; the needle at the value, **no zone**; note in row 8 |
| Recalculating | row D, earlier day | Scored layout with the earlier day's values; the sub-line says the date; tile captions show the day; note "Recalculating your baselines" in row 8 |
| First import | `hero == .importing` | `ImportCard` replaces rows 6–9 and the tiles; header, greeting and status row stay |
| No scores yet | row E, `.firstImport` presentation | Empty gauge (hollow dots, unlit grid), "Readiness", ruler without needle, tiles hidden, sentence "Your scores appear after the first synced night." |
| Not set up | `!hasDataSource` | Header, greeting ("Let's get you set up."), `SetupCard`; no gauge |
| Offline | `!online` | Status row "Offline — will sync when back"; the last loaded values stay in full ink; no banner |
| Stale / error | `SyncLine.stale`, `RefreshIssueCard` | Status row "Showing data from 14:05 · Try again"; the card last, scrolled to by "Details" |
| Gated / invite | `.actionNeeded` | Status row is a button (icon + words, opens the step) and the `InlineMessage` last, as today |
| Demo | `isDemo` | "Demo data · Updated …" in the status row; the launch plays |
| Background refresh | `isRefreshing`, `.updating` | Status row "Updating…" with the pulse (off under Reduce Motion); values stay; a new score lands as the gauge's own animation |
| Thin digits | `heroNumerals == .thin` | Gauge `numeral: .light` (52 pt Light); nothing else changes |

**Sleep.**

| State | Trigger | Look |
|---|---|---|
| Scored night | `sleep` and `score` | The table in §P4-2 |
| Latest night | `isToday` | Subtitle "Last night · …"; Next disabled (35 %, label unchanged, hint "No newer night to show") |
| Oldest night | `date ≤ oldestNight` | Previous disabled the same way (hint "No older night to show") |
| An older night | stepped back | Subtitle "Sat, Nov 14" or "Yesterday · Sat, Nov 14"; the numeral cross-fades (250 ms; none under Reduce Motion) |
| Loading, nothing cached | `isLoading && sleep == nil` | Unlit "0:00", ruler ticks without a needle, hypnogram and four tiles as `surface` outlines (1 pt `separator`), values "–"; VoiceOver "Loading this night"; no spinner |
| Load error | `model.error` | As loading, plus the app's calm sentence (`SleepLoadFailure`, never `localizedDescription`) in the hypnogram tile's place, with Details (request ID) and Today's action: "Sign in" when signed out, none when the app is too old, "Try again" otherwise (review rows 14, R2) |
| No sleep recorded / missing night | a scored day without `sleep` | Unlit numeral, caption "No sleep recorded for this night.", ruler without needle, tiles "–", hypnogram slot an outline tile; `HealthAccessHint` if there is no Health data at all |
| Pending score | `scoring_state` `pending` (`sleep: null` from the API) | With Apple Health's raw night: numeral and ruler from it, caption "From Apple Health · not scored yet" (D4-15), outline hypnogram, tiles that need a score "–". Without one: "Your night is being scored." The marker dot is an outline, as today (review row 1) |
| Waiting for the night | `waiting_for_sleep`, or `stale` for today without a night | "Last night hasn't reached RYFT yet.", as Today says it; no raw night, outline hypnogram, tiles "–". `stale` with a night keeps its score (R2-F1) |
| Partial: no stages | `!hasStages` | Hypnogram tile with the explanatory line; Restorative "–"; Stages card hidden; the rest as scored |
| Partial: no timeline | `segments.isEmpty`, stages known | Tile with totals only |
| Partial: no need | `sleepNeedMin` nil | Ruler without zone or middle label; caption "Asleep"; Need card hidden |
| Week / Month / Bedtime | `mode` | Their content as today under the header and picker (restyled in place by PR 5); header buttons hidden |
| Demo | `isDemo` | The board's night (T4.0 fixtures) |

### P4-6. The thin-digit switch (L16)

**Recommendation: Profile → Settings, a "Hero numbers" row with two options, "Dots" (default) and "Thin".** The preference is set once; Today's board has no place for a control; a hidden gesture would not be found. Storage: `Settings.heroNumerals: HeroNumerals` (`enum: String { dots, thin }`), key **`ui.heroNumerals`** in `UserDefaults` (a device preference, kept on log-out, like `train.sessionLayout`); `HeroNumerals.style` maps to `DotNumeral.Style` (`.dots`, `.light`). Until PR 5 reworks Profile, the row sits in a new "Display" section above "About" with `SettingRow`'s look and a two-way `Picker` (menu) inside; footer "Large numbers on Today, Sleep and Strain." Effects: Today `OrbitGauge(numeral:)`; Sleep `DotNumeral(style:)`; Strain (PR 5) the same; the PR 3 rule still falls back to Light at AX1 and above and for characters the grid lacks, so "Dots" never produces unreadable text. A change applies at once (the screens read the observable `Settings`).
**Alternative:** a control on Today (a "Dots · Thin" toggle on a long press of the gauge, or a row at the end of the page). It is the brief's wording ("Today hat einen Schalter") but it adds an element to a measured screen or hides it; if the lead prefers it, the storage and effects stay as above and only the control moves.

### P4-7. The launch's matched move (L15)

What the eye sees: the mark and "RYFT" of the final launch frame (`ink`, mark 184 pt, wordmark 22 pt under it) lift off the background and travel, shrinking, into the header's lock-up (mark 26 pt, wordmark 15 pt to its right), while the background and the tagline fade and Today appears around them. It lands; then the gauge builds. Only when all of these hold (`launch-design.md` §7.5): `.full` variant, a `.mark` target registered by Today's header, and `progress(at: handOffStart) ≥ 0.86` (the mark has formed). Reduce Motion, VoiceOver, Low Power, an early skip, another root, a missing target: PR 3's cross-fade, unchanged. The header's lock-up is then visible at once.

| Quantity | Spec |
|---|---|
| Mark rect | from `LaunchStage.markRect(in:)` (390 × 844: 103, 290, 184 × 184) to the header mark, registered in the `.launch` space by `launchHandOffTarget(.mark)` (20, 7, 26 × 26: below the safe area) and converted to the overlay's space by adding the safe-area insets (as-built note: (20, 66) under a 59 pt inset). `LaunchFrame.rect(from:to:progress:) = ` the four components lerped; the centre moves on a straight line |
| Wordmark | ink-box centre and size lerped: from (W/2, box bottom + 28 + half the line) at 22 pt to (target mid-x, target mid-y) at 15 pt. Tracking is 0.32 em at both ends, so it follows the size and is **not** animated (the launch's 0.9 → 0.32 em is finished by 0.86); the trailing-tracking pull-back scales with the size |
| Easing | Mark: **E1** `cubic-bezier(.45, 0, .15, 1)` on `τ = clamp(elapsed / D)`; wordmark: E1 on `clamp((τ − 0.15) / 0.85)` (it starts 15 % later: without the delay the wordmark's top meets the mark's ring at τ ≈ 0.52, −5.4 pt of clearance; with it the clearance never falls under +7.3 pt) |
| Duration D | **0.50 s** at the natural end (was the 0.4 s fade); the quick hand-off after a tap at ≥ 86 % keeps 0.25 s. Background and tagline: `1 − easeOut(clamp(elapsed / 0.25))`, so Today is visible from 0.25 s while the lock-up still travels. This is a brand moment, the launch's exception to the 250 ms rule (P3-4 motion rule); Q7 |
| Mark stroke and dots | **Not interpolated.** The frame is `LaunchFrame(t: 1, palette:, side: current side)` each frame and `RyftMarkGeometry.metrics(forSide:)` gives the rest: stroke = max(3.16 % of the side, 1.25 pt), dot r = 6 % of the side × √k, so the gaps in the rings follow. Points: side 184 → stroke 5.81, dot 11.04, gaps 14.02° / 24.22°; 80 → 2.53, 4.80; 40 → 1.26, 2.40; 26 → 1.25, 1.92, gaps 17.92° / 31.05°. At the end it **is** `RyftMark()` at 26 pt (within 2/255), so the swap to the real header mark is invisible. The board's "stroke 5.2, dots 7.7 in the 100 box" are the 24 pt values (4.81 and 7.40 at 26 pt, 0.1 pt of difference; D4-7) |
| Landing | At `elapsed = D` the model is `done`: the overlay goes, the header lock-up (hidden at opacity 0 while the mark moved) is at 1; identical pixels. VoiceOver focus: the existing `ScreenChanged` at hand-off start lands on the lock-up (an opacity-0 view is still in the tree) |
| Gauge entrance | Starts when the lock-up has landed (L15). `launchCoversRoot` splits: `coversRoot` (taps, VoiceOver) ends at hand-off start as today; new `launchRevealsRoot` ends at `done` when the mark moves (else with `coversRoot`) and is what the gauge and its consumer read. During the move the gauge's slot is an empty 260 × 260 frame; at landing the consumer rebuilds, and the entrance plays (850 ms; the Reduce Motion path as before). The rest of Today is visible from the first frame of the hand-off |
| Reduce Motion | No move: PR 3's 250 ms cross-fade; the entrance's reduced path |

Needs from the lifecycle (to the lead, Q7): `Timing.full.handOff` 0.4 → 0.5 s when the mark moves; `LaunchSequenceModel.movesMark` decided at hand-off start; `targets: [LaunchHandOffRole: CGRect]` and `register(_:_:)` (§7.5); `launchRevealsRoot`; `LaunchStage` takes a wordmark placement beside `markRect`; `LaunchSequence.moveProgress(at:)` (linear time, then E1) beside `handOff(at:)`; `WordmarkLockup(handOff:)` applies `launchHandOffTarget(.mark / .wordmark)` and hides itself while `movesMark` and the phase is `handingOff`. Only Today's header sets `handOff: true`.

### P4-8. Accessibility

**Today, reading order** (top to bottom, one element each unless said):

| # | Element | Label / value / hint |
|---|---|---|
| 1 | Lock-up | "RYFT", header trait (`WordmarkLockup`) |
| 2 | Calendar | button "Calendar", hint "Opens My Day" |
| 3 | Greeting + sub-line (combined) | "Good evening, ‹first name›. Sunday, November 15. Your health is in balance." Header trait |
| 4 | Status row | the line's button(s) as today; a container |
| 5 | Gauge | label "Overall readiness", value = PR 3's sentence ("84, High, Up 11 vs 7 d. Recovery 82 percent, Sleep 94 percent, Strain 12.4 of 21"), then the note. The visible label row is hidden from VoiceOver |
| 6 | Ruler | label "Readiness scale", value "84, high, on a scale from 0 to 100"; calibrating: "84, on a scale from 0 to 100"; no value: "No readiness yet, on a scale from 0 to 100" |
| 7 | Attention cards | as today |
| 8 | Recovery tile | button; label "Recovery", value "82 percent, High. HRV 66 milliseconds, lowest 51 and highest 66 over the last 7 days"; dimmed day: "…, Yesterday, not today's score"; hint "Opens Insights". The sparkline is inside the element and hidden |
| 9 | Sleep tile | button; label "Sleep", value "7 hours 48 minutes. Slept enough on 4 of the last 7 nights; the last is the night shown"; hint "Opens Sleep" |
| 10 | Strain tile | button; label "Strain", value "12.4 of 21, moderate. The moderate range is 10 to 14"; hint "Opens Strain" |
| 11 | Cards below | in their order; My Day's title is a header + button as today |

Sleep: "Previous night" (button, dimmed and "No older night to show" at the end) · "Sleep" (header; value "Last night, Sunday, November 15", plus "not scored yet" from `DayMarker`) · "Next night" · the picker · the numeral ("7 hours 48 minutes asleep") · the caption ("94 percent of your need") · the ruler ("Sleep duration scale", "7 hours 48 minutes, on a scale from 0 to 10 hours. Your need is 8 hours 18 minutes") · the hypnogram (one element, §P4-2a) · Consistency, Sleep debt, Efficiency, Restorative (each one element: "Sleep debt, 30 minutes, down 42 minutes from the night before"; "Restorative, 3 hours 20 minutes of deep and REM sleep, 100 percent of the target"; "Consistency, 86 percent. 5 of the last 7 nights were regular, 1 was not, 1 has no data; the last is the night shown") · the cards. A step re-reads the new night: post `AccessibilityNotification.Announcement` with the subtitle and the duration after the load. Colour never carries state: Volt is a position (last mark), teal / `alert` arrows come with ▲ ▼ and the spoken "up / down".

**Dynamic Type (AX3 = `.accessibility3`).**

| Element | Behaviour |
|---|---|
| Header, gauge, ruler ticks, sparkline, `DotRow`, circle buttons | Fixed size (graphics); the gauge keeps 260; the header lock-up does not grow |
| `DotNumeral` (Sleep, Today's gauge) | From AX1 Light digits, 52 pt scaled by `.largeTitle` (about 78 pt at AX3); Sleep's row stays centred, `minimumScaleFactor(0.5)` |
| Greeting, sub-line, label row, ruler labels, tile labels, captions | Scale with their styles (`.title`, `.footnote`, `.caption2` …), wrap, never truncate; the label row stacks (band over delta); the ruler's labels join into one wrapping line |
| Today tiles | Stack at AX1+ (single column, 350 wide), rows stack inside (label, series, value), tiles grow, the panel ellipse takes over from 160 pt of height; tile numerals `.numberLarge` / 30 stay fixed |
| Strain tile | Label, value + "of 21 · …", then the ruler; grows |
| Sleep 2 × 2 | One column at AX1+; value `.metric` fixed; units and deltas wrap under the value |
| Hypnogram tile | §P4-2a "AX1+" |
| Sleep header, picker | Title and subtitle scale and wrap between the fixed buttons. The picker truncated its titles at AX3 (PR 1 §11 left it to PR 4): from AX1 it becomes a one-row `Menu` showing the current mode (44 pt high, "Day ▾"), and the four segments return below AX1; PR 5 restyles it |

**Reduce Motion:** no numeral cross-fade, no needle move (`RulerScale`), no sync-line pulse, no launch move (cross-fade), the gauge's own reduced paths. **Reduce Transparency:** `GlowTile` is flat `surface` with a 2 pt metric border (PR 2); inks as §P4-3; the matched move does not change. **Motion budget:** every UI animation is `Theme.Motion.quick` (250 ms); the matched move (0.5 s) is the launch's brand-moment exception.

### P4-9. Strings

English only, `Localizable.xcstrings`, targeted edits and a `--stat` check (plan risk). Keys are the English text. Bold = replaces an existing key, which is **removed** in the same edit.

| Key | Comment for translators / developers |
|---|---|
| `Good morning, %@` · `Good afternoon, %@` · `Good evening, %@` | Today's greeting with the user's first name. **Replace** `Good morning,` `Good afternoon,` `Good evening,` |
| `Good morning` · `Good afternoon` · `Good evening` | The same without a name (none known). |
| `Readiness · %@` | Under Today's gauge: "Readiness", then the band word (High, Moderate, Low). |
| `today.ruler.low` "low" · `…moderate` "moderate" · `…high` "high" | Scale words under Today's readiness ruler, lower case. |
| `Calendar` · `Opens My Day` | Today's header button; its VoiceOver hint. |
| `Readiness scale` · `%lld, %@, on a scale from 0 to 100` · `%lld, on a scale from 0 to 100` · `No readiness yet, on a scale from 0 to 100` | VoiceOver on the readiness ruler (with band, without, no value). |
| `of 21` · `of 21 · light` · `of 21 · moderate` · `of 21 · high` · `of 21 · all out` | After Today's strain value: the scale and the band. |
| `Strain · %@` | The strain tile's label while it shows another day or "calibrating". |
| `Strain scale` · `%1$@, %2$@, on a scale from 0 to 21. The moderate range is 10 to 14.` | VoiceOver on the strain ruler and its tile. |
| `HRV %lld milliseconds, lowest %lld and highest %lld over the last 7 days` | VoiceOver on the recovery tile's sparkline. |
| `Slept enough on %lld of the last 7 nights; the last is the night shown` · `…; %lld nights have no data` (plural: "1 night has no data") | VoiceOver on the sleep dots (Today, `DotRow` summary). |
| `Last night · %@` · `Yesterday · %@` | Sleep header subtitle; %@ is the date ("Sun, Nov 15"). **Replace** `Last night` as the subtitle (the key stays for the raw-night card). |
| `Asleep · %lld %% of your need` · `%lld percent of your need` | Caption under Sleep's numeral; its VoiceOver text. `Asleep` exists. |
| `Sleep duration scale` · `0 h` · `need %@` · `10 h` · `%@, on a scale from 0 to 10 hours. Your need is %@.` · `%@, on a scale from 0 to 10 hours.` · `No time asleep yet, on a scale from 0 to 10 hours.` (± `Your need is %@.`) | Sleep ruler: label, scale words, VoiceOver (with and without a need, no value). |
| `h` | Hours unit after a clock value ("7:48 h"). |
| `Deep + REM` | Restorative tile's note. **Replaces** `deep + REM`. |
| `No newer night to show` · `No older night to show` | Hints on the disabled night buttons. |
| `Loading this night` · `The timeline isn't available for this night.` | Sleep loading state (VoiceOver) and the hypnogram tile without a timeline. |
| `Hypnogram, %@ to %@` | VoiceOver label on the hypnogram tile (times). |
| `Consistency, %lld percent. …` · `Sleep debt, …` · `Restorative, …` | VoiceOver on the neutral tiles (sentences in §P4-8). |
| `Display` · `Hero numbers` · `Dots` · `Thin` · `Large numbers on Today, Sleep and Strain.` | Profile → Display (§P4-6). |

Also **remove** (no other caller after the change, verified by grep before the edit): `Total sleep`, `Performance` (the tile title), `asleep in bed`, `of your need` (the tile detail, lower case; the planner's `%lld % of your need` is another key), `last 7 nights`. `SleepScoreTile` is deleted with them. Kept: `Overall readiness` (spoken label), `Quality`, `Efficiency`, `Restorative`, `Consistency`, `Sleep debt`, `None`, `Previous night`, `Next night`, `vs 7 d`.

### P4-10. Previews and catalog

Dark only (D3), default size and AX3 for each (`"<View> · <state>"`, `"… · AX3"`); the old light and `de` previews of the two files go. `DebugComponentCatalog` gets `Nocturne · glow kinds` (four kinds, the fallback, Reduce Transparency), `Nocturne · sparkline`, `Nocturne · hypnogram` (full, no timeline, no stages), `Nocturne · header` (lock-up + calendar, three-slot) and the `DotRow` `.noData` mark; the screens' previews do the rest.

| Screen | Previews (each × default, AX3) |
|---|---|
| Today | scored · thin digits · pending with a previous day · pending slow · pending, nothing scored · calibrating · calibrating with a readiness (learning) · first import · no scores yet · not set up · offline · stale · action needed · refresh issue · demo · with attention cards (night hint) · with a name and without · Reduce Transparency · launch hand-off frames at τ 0, 0.25, 0.5, 0.79, 1 (the move, over the Today layout) |
| Sleep | scored · thin digits · latest night · oldest night · an older night · loading · load error · no sleep · pending score · no stages · no timeline · no need · with a nap · Reduce Transparency · Week · Month · Bedtime (kept) · Sleep need sheet (kept) |

### P4-11. Tests

Swift Testing, `@MainActor`; pure first. Files: `TodayLayoutTests`, `SleepLayoutTests`, `GlowTileKindTests` (+ the re-pinned `NocturneComponentTests` 12–19), `TodayDataTests`, `SleepDataTests`, `LaunchMoveTests`, `HeroNumeralsTests`, `NocturneTodaySleepA11yTests`; `RyftUITests` for 51.

**Layout constants**
1. `TodayLayout`: header 40, header→greeting 18, greeting→sub-line 4, sub-line→status 4, status→gauge 14, gauge→label 8, label gap 10, label→ruler 12, ruler→tiles 22, tile gap 12, tiles→strain 12, tile heights 124 / 96, strain row inset 16, hero dial 248 and frame 260. `SleepLayout`: header 40, picker gap 12, header(picker)→numeral 22, numeral→caption 12, caption→ruler 14, ruler→tile 20, tile height 168 radius 28, tile→grid 12, grid gap 12, neutral tile 88 radius 22, padding 14 / 16.
2. The 2-up pair is 169 × 124 at 350 wide, 161 at 335, 194 at 400; stacks at AX1 (`isAccessibilitySize`) to 350.
3. Header: the circle's edge on the 20 pt inset; the row is 40 and its buttons' boxes 44; Calendar is absent (row height unchanged) when My Day is off.
4. `OrbitGaugeSize.hero.frame` 260 and `dial` 248; the gauge is centred and unclipped (halo 133 > 130).
5. Sleep numeral `"7:48"` at gap 7 is 125 × 47; pending `"0:00"` the same; `Fmt.clock(minutes: 468)` "7:48", 0 → "0:00", 61 → "1:01", nil → "–".
6. Hypnogram plot: grid lines at y 4, 31.33, 58.67, 86 in 90; deep bar 8 high radius 4 centred on y 86; step line 1.4; column 38.

**Glow and contrast**
7. `GlowTileSpec.shape(for:size:)`: the four kinds' ellipse, stops, radius, minHeight as §P4-3; `twoUp` at 169 × 124 and 200 × 160 keeps its own, at 201 × 124 and 169 × 161 and 350 × 124 returns the `panel` ellipse and stops.
8. `overlayOpacity` per kind at 0, the second stop, the third, 1 equals the table; `twoUp` at t 0.858 (the corner) ≈ 0.283.
9. `labelOpacity(metric:typeSize:)`: recovery 1.0 at every size; sleep and strain 0.78 below AX1, 1.0 from AX1.
10. Contrast per concrete tile, rendered (`ImageRenderer`) or computed from `overlayOpacity`, worst pixel over each text rect at default size: recovery 2-up `textPrimary` ≥ 5.0 and label (100 %) ≥ 5.0; sleep 2-up ≥ 6.8 and label (78 %) ≥ 4.9; strain ≥ 9.0 and 6.2; hypnogram ≥ 7.2 and 5.1. Assert ≥ 4.5 in every case (the numbers are margins, not pins).
11. The same at 161 × 124, 194 × 124, 169 × 160 (2-up), 335 and 400 wide (strain, hypnogram): all ≥ 4.5.
12. AX3: recovery and sleep 2-up at 350 × 124 / 160 / 240 / 300 with the panel ellipse and full ink ≥ 4.5 (6.63…5.89, 8.51…7.74); strain 350 × 150…300 ≥ 7.9; hypnogram 350 × 260…420 ≥ 6.4.
13. The board's own values fail where stated: recovery 2-up label at 78 % is < 4.5 (3.78), sleep 2-up at 62 % < 4.5 (3.75), hypnogram at 55 % < 4.5 (3.42): the test documents why the rule exists.
14. Graphics ≥ 3: sparkline (ink 80 %) and Volt in the recovery top-right; `DotRow` missed outline (ink 50 %) in the sleep top-right ≥ 3.0; step line, deep bars over the plot, compact-ruler zone ticks in the strain tile.
15. Reduce Transparency: flat `surface`, 2 pt border; ink, 78 %, sparkline, bars ≥ 4.5 / 3 on it.
16. The PR 2 pins that the new shape supersedes are re-pinned (13, 16–19 of §P2-7: gradient stops per kind, padded rect numbers, `ellipse`); the `init(_:radius:)` shim still draws `panel`.

**Data and states**
17. Greeting: hours 4 → evening, 5 and 11 → morning, 12 and 17 → afternoon, 18 → evening; `firstName` of "‹first name› Surname" is the first word, of "" nil, of "  " nil; the string has no comma without a name.
18. Sub-line "Sunday, Nov 15 · " + each `sentence` row; wraps rather than truncates.
19. Label row: "Readiness · High" for 84, "Moderate" 50, "Low" 20; "Readiness" alone while `showsReadinessBand` is false; no delta when `readinessDelta` is nil.
20. Ruler inputs per state: scored 84 → zone 67…100, 41…60 ticks, needle 252 at 300 wide; calibrating (no band) → no zone; pending / calibrating / empty → no needle.
21. `hrvWeek`: seven entries, the last the shown day's; a gap day is nil; fewer than two values → pending look; the Volt dot only when the last value exists.
22. `sleepNights`: `sleepActualMin ≥ sleepNeedMin` full, below missed, either nil `.noData`; seven marks; the last is `.today`; the summary says "Slept enough on n of the last 7 nights" with the unknown count.
23. Strain tile: `Fmt.strain`, band word per 9.9 / 10 / 13.9 / 14 / 17.9 / 18 (light, moderate, moderate, high, high, all out); zone 10…14; value nil → "–", no needle.
24. Tile captions: dimmed day, "calibrating", band word; the recovery tile's "–" beside the baselines counter; the same day for all three tiles.
25. State → look for every row of the Today table (pending with and without previous, slow, calibrating S1 / S2 / N1, recalculating, first import, no scores yet, not set up, offline, stale, gated, demo), asserted on the pure decisions (`hero`, `presentation`, `syncLine`) and on the views' identifiers.
26. Sleep summary: caption "Asleep · 94 % of your need" and "Asleep"; subtitle "Last night · Sun, Nov 15", "Yesterday · Sat, Nov 14", "Wed, Nov 11"; "Last 7 nights" / "Last 30 nights" / "Tonight".
27. Night stepping: `canStepForward` false at today; `canStepBack` false at `oldestNight`; `oldestNight` = first history day with `sleepActualMin`, else today − 89; `show(night:)` and `step` clamp.
28. Sleep ruler: zone `RulerScale.zone(lo: 0.9 · need/60, hi: need/60)` for 498 → 7.47…8.3, ticks 45…49; need nil → no zone, labels `["0 h", "10 h"]`; needle at 7.8; clamped at 12 h.
29. Hypnogram plot model: levels per stage, `asleep` on Light, clamping to the night, a gap breaks the path, deep bars (≥ 3 pt), x of `start` = 0 and of `end` = 1; empty segments and no stages choose their tile variants.
30. Totals: "Deep 1:35 · REM 1:45 · Light 4:28 · Awake 0:22" from the stages; a missing stage "–".
31. Tiles: Consistency dots (≥ 60 full, < 60 missed, nil `.noData`, last `.today`); Sleep debt "0:30" and delta "▼ 0:42" (down), ▲ when up, none with either night missing, "None" at 0, "· high" above 45; Efficiency "95"; Restorative "3:20" from deep + REM and spoken score from `restorative`.
32. `DotRow.Mark.noData`: size unchanged, drawn as a 2 pt dot at 35 %, distinct from `.missed` by shape.
33. Placeholders: every missing value of §P4-4 renders its pending look and no number: nil `DailyScore` fields, no `segments`, no `hrv_ms`, no name (R-N1…3 rows do not appear in a real decode).
34. Fixture decode: `strain_target_*`, `name`, `sleep_need_met` are not decoded (nothing in `Models.swift` changes in this PR).
35. `MockData` board night: 468 / 22 / 95 / 105 / 268, 22:50 – 07:00, need 498, performance 94, efficiency 95, debt 30 (72 the night before), restorative 3:20, consistency 86; readiness delta +11.
36. Identifiers kept: `today.readinessGauge`, `today.pendingGauge`, `today.baselineGauge`, `today.importCard`, `today.rawNight`, `today.nightHint`, `today.watchHint`, `today.syncLine.line`, `sleep.need`, `sleep.plannedVsActual`; new: `today.header.calendar`, `today.ruler`, `today.tile.recovery` / `.sleep` / `.strain`, `sleep.header.previous` / `.next`, `sleep.numeral`, `sleep.ruler`, `sleep.hypnogram`, `sleep.tile.consistency` / `.debt` / `.efficiency` / `.restorative`.

**The matched move**
37. `LaunchFrame.rect(from:to:progress:)`: 0 → the start, 1 → the target, 0.5 → the midpoint; with E1: at τ 0.25 the side is 151.3, at 0.5 the origin (37.3, 112.8) and side 59.0 for 103, 290, 184 → 20, 66, 26 (u = 0.2068 / 0.7912).
38. The safe-area conversion: a header mark read as (20, 7, 26 × 26) in the `.launch` space becomes (20, 66, 26 × 26) in the overlay's for insets (0, 59, 0, 34); the test fixes the convention with a non-zero inset and with zero insets (identity).
39. `moveProgress(at:)`: linear to D, then E1; 0 before the hand-off, 1 after; D 0.5 s natural, 0.25 s after a tap.
40. Wordmark progress: E1 of `clamp((τ − 0.15)/0.85)`; at τ 0.15 it has not moved; both are 1 at τ = 1; the size is 22 at 0 and 15 at 1, the tracking 0.32 em throughout.
41. Clearance: for τ = 0, 0.02 … 1 the mark's outer ink (0.44 · side + dot radius from the centre) and the wordmark's ink rect (advance 0.62 em per letter plus 0.32 em tracking) are at least 4 pt apart.
42. Mark metrics along the move: `metrics(forSide:)` at 184 / 80 / 40 / 26 → stroke 5.81 / 2.53 / 1.26 / 1.25 pt, dot 11.04 / 4.80 / 2.40 / 1.92 pt, gaps 14.02 / 14.02 / 14.02 / 17.92° (outer); the frame at τ = 1 equals `LaunchFrame(t: 1, side: 26)` and renders as `RyftMark()` at 26 pt within 2/255.
43. Decision: moves only for `.full` ∧ progress ≥ 0.86 ∧ target registered ∧ `.mark`; not for reduced, a skip at 0.5, a missing target, another root (those cross-fade); `movesMark` is decided once.
44. Reveal: `launchRevealsRoot` false from hand-off start to `done` when the mark moves, equal to `coversRoot` otherwise; the gauge consumer rebuilds when it flips; the slot is 260 × 260 and empty before.
45. Overlay layers: background and tagline reach 0 at 0.25 s, the mark and wordmark stay at 1 until `done`; the header lock-up is at 0 only while `movesMark` and `.handingOff`.

**The switch and accessibility**
46. `Settings.heroNumerals` defaults `.dots`, persists under `ui.heroNumerals`, survives log-out, ignores an unknown stored value; `.thin` gives `.light` to the gauge and to Sleep's `DotNumeral`; AX1 renders Light for both settings.
47. Profile shows the row and changing it updates Today without a reload.
48. VoiceOver: the reading order of both tables above (element counts and labels, hosted), one element per gauge, ruler, tile, hypnogram; header traits on the greeting, "Sleep" and the lock-up; the buttons' labels; disabled night buttons are not enabled and carry their hints.
49. AX3: nothing clipped in the hosted views (frames inside the width), the pair stacked, the numeral Light, the label row stacked, hypnogram column and totals as specified.
50. Strings: the catalog has every key of §P4-9 with a comment and none of the removed ones; `make lint` strings green.
51. UI (`UISmoke`): Today shows the header, gauge, ruler and three tiles in demo; the Sleep tile opens Sleep; Previous night then Next night returns to the latest night and disables Next; Calendar opens My Day; the launch test still passes with the move (`-RyftLaunchSequence play`, the header lock-up exists at the end).

### P4-12. Files and the split

T4.2 (Today) and T4.3 (Sleep) can run in parallel worktrees **after a short T4.0** that makes every shared change, so that their file sets are disjoint. T4.4 (copy) follows both; T4.5 tests.

| Ticket | Files |
|---|---|
| **T4.0 shared** (one worktree, first) | `Design/GlowTile.swift` (`Kind`, `shape(for:size:)`, `labelOpacity(metric:)`, the environment value, the shim); `Design/RulerScale.swift` (compact labels read the environment value); `Design/DotRow.swift` (`.noData`); `Design/DeltaLabel.swift` (`referenceColor:`); `Design/CircleButton.swift` (`iconSize:`); `Design/StatusViews.swift` (`ScreenScaffold(showsHeader:)`, `SyncStatusLineView` leading alignment and 44 pt target); `Design/OrbitGauge.swift` (`showsCaption:`); new `Design/ScreenHeader.swift`, `Design/Sparkline.swift`, `Design/HypnogramPlot.swift`; `Design/RyftHeader.swift` (`WordmarkLockup(handOff:)`); `App/Formatting.swift` (`Fmt.clock(minutes:)`, a spoken duration); `App/Settings.swift` + `Features/Profile/ProfileView.swift` ("Display"); `Preview/MockData.swift` (the board night); `DebugComponentCatalog.swift` (§P4-10); `Design/Theme.swift`: none; tests 7–16, 32, 46–47 |
| **T4.2 Today** | `Features/Today/TodayView.swift`, `TodayViewModel.swift` (`firstName`, `hrvWeek`, `sleepNights`, strain word), `ReadinessCopy.swift`, new `TodayHeader.swift`, `TodayTiles.swift`, `OrbitGaugeSize+Hero.swift`; `App/LaunchHost.swift`, `LaunchSequence.swift`, `LaunchSequenceModel.swift`; `Design/LaunchStage.swift`, `LaunchFrame.swift` (the move); the gauge consumer; Today previews; tests 1–4, 17–25, 36–45 |
| **T4.3 Sleep** | `Features/Sleep/SleepView.swift` (header, day section, tiles, hypnogram tile), `SleepViewModel.swift` (`oldestNight`, summary additions, subtitle), new `SleepTiles.swift`, `SleepHypnogramTile.swift`; Sleep previews; tests 1, 5, 6, 26–31, 36 |
| **Shared, last** | `Resources/Localizable.xcstrings` (T4.4, localization-editor; targeted edits), `docs/API_REQUESTS.md` (T4.6: R-N1…R-N3), `CHANGELOG.md`, `docs/STATUS.md` |
| **Not touched** | `OrbitGauge` geometry, `RyftMark`, the Strain / Insights / Profile screens (the Profile row aside), the tab bar, the model, sync, API, `Models.swift` |

### P4-13. Deviations

| # | Board | Brief | Spec | Why |
|---|---|---|---|---|
| D4-1 | Content top at 56 | — | safe-area top | 56 is the board's status-bar frame; a device's safe area is 54–62 |
| D4-2 | No sync status | — | A status row (+≈ 20 pt) under the sub-line | Today's sync status text, tappable (Sync details, gates, Try again), must stay visible; Q2 |
| D4-3 | No mode picker on Sleep | — | Picker under the header, content below it +64 pt (measured; first written +48, review row 12) | Week, Month and Bedtime would otherwise be unreachable; Q1 |
| D4-4 | Glow-tile text at 0.62 / 0.55; labels 0.78 | §6 text ≥ 4.5 in the core | 100 % (recovery) or 78 % for every non-numeral text; recovery tile all full ink | The board's alphas fail 4.5:1 in all tiles but strain (numbers in §P4-3); user decision of 2026-11-16 for recovery |
| D4-5 | Meta text at 0.55 and 0.45 | `textTertiary` 45 % | `textTertiary` 48 % for both | PR 1 D-a; 0.55 maps to the dimmer token to keep the hierarchy (label 0.62 above meta) |
| D4-6 | Need zone 7.5–8.3 h | — | 90–100 % of the need | The board's example is one night; the rule is the display choice that reproduces it; Q6 |
| D4-7 | Header mark stroke 5.2, dots 7.7 (100 box) | — | 4.81 and 7.40 (`metrics(forSide: 26)`) | 5.2 / 7.7 are the 24 pt values; the difference is 0.1 pt |
| D4-8 | Calendar glyph 16 pt, 1.2 stroke | — | `CircleButton(iconSize: 16)`, the component's stroke (≈ 1.3) | One component, one stroke |
| D4-9 | Restorative "3:20 h" | — | deep + REM minutes from `stages` | A sum of server minutes, not a score; the 0–100 `restorative` is spoken |
| D4-10 | — | "Today hat einen Schalter" | The switch lives in Profile → Display | No place on the measured board; Q8 |
| D4-11 | — | "das Logo wandert in den Header" | 0.5 s move (brand exception to 250 ms), wordmark delayed 15 % | Clearance in flight; Q7 |
| D4-12 | 2-up ellipse 85 × 80 at any size | text in the core | `panel` ellipse when a 2-up is wider than 200 or taller than 160 | At 350 × 124 the board's ellipse gives 4.41:1 in full ink |
| D4-13 | Recovery tile in the recovery colour; no band tint | one colour per metric | The tile and the gauge are teal always (was the band colour) | The legend |
| D4-14 | Greeting with a name | — | Without a name when none is known | `full_name` can be empty (R-N2) |
| D4-15 | Sleep caption "Asleep" | — | "From Apple Health · not scored yet" on a pending night with a raw night | Raw totals are unscored; "Asleep" under them read as RYFT's number (review row 1) |
| D4-16 | 2-up captions under the label, value 22 pt lower when a caption is there | — | `TodayTwoUpValueRow`: the caption beside the value at 0.8 scale (1 pt slack) or above it; the value sits by its baseline and its line never moves; both tiles arrange alike (caption and sparkline), and the sparkline moves under the label before a title is cut. At default sizes the pair is 124 pt in every state; at 390 from xxLarge, with the captions above, it grows together (146.67, 149.33 at xxxLarge) | Calibrating and pending tiles lifted the value; "Recov…" at xxxLarge (review rows 13, B, C, R3-V1) |
| D4-17 | — | — | Today's fault sub-line is the date alone | The status row and the card already say why (review row 15) |
| D4-18 | Ruler labels on one line | — | `RulerLabels`: one line when they fit, else the fewest lines of whole labels joined by " · " | AX sizes wrapped at a separator (review row D) |
| D4-19 | The strain tile clear of the tab bar | — | At 390 × 844 the strain ruler sits about 16 pt under the floating tab bar at the scroll top | The board's dot tab bar is PR 5 (review row 21) |
| D4-20 | — | Q3: drop `StageBar`, `MiniHypnogram`, the old `Hypnogram` | Dropped; `StageRow` stays for Sleep's stage card (`Design/StageRow.swift`) | The stage card still lists the stages (review row 7) |

**The ruler's box (measured on the board, review row 11).** The next block is measured from the ruler's 36 pt box (8 + a 22 pt tick row); the labels start at +32 and overflow it. `RulerScale(followingGap:)` puts Today's tiles at ruler top + 58 and Sleep's hypnogram at + 56; at accessibility sizes the labels push the block down.

Derived, not measured (do not tune without asking): the series' and dots' place in the 2-up tiles; the unit and caption places; the strain row's spacing; the status row; section spacing 24 below the glow block; the hypnogram grid's y positions; the compact ruler without labels on Today; left-aligned greeting; ruler labels space-between; the Sleep ruler's middle label at the centre.

### Questions for the lead

1. **Sleep's modes (D4-3).** The board has no Week / Month / Bedtime. Recommended: the picker under the header, board content 48 pt lower (ui-validator offsets Day mode by 48). Alternative: Day is the board exactly and the three modes are rows ("Week", "Month", "Bedtime") at the end of Day, pushing their sections with a back button; more code, deep links (`show(night:)`, `showPlanner()`) change.
2. **Sync status row (D4-2).** Recommended: always shown, +≈ 20 pt. Alternative: shown only when it is not the plain "Updated 07:15", which moves to Sync details only; Today then matches the board in the happy state but loses a visible freshness date, against the honest-states rule.
3. **Drops.** `MiniHypnogram` on Today (flag `today.redesign`, default off), the proportional `StageBar` on Sleep, the Efficiency and Sleep debt rows in the Details card (they repeat tiles). Everything else is kept. OK to drop?
4. **Glow inks (D4-4).** I raise the board's 0.62 and 0.55 inside glow tiles to the label rule because they fail 4.5:1. Alternative: keep the strain tile's 0.62 (4.60, margin 0.10) for "of 21 · moderate" so that one colour matches the board.
5. **"Slept enough" (T12).** I compare `sleepActualMin` with `sleepNeedMin` (full at ≥ need). Alternative: R-N3, the platform's flag; or a threshold such as 90 % of the need (the board's 94 % night would then be full).
6. **Need zone (S5).** 90–100 % of the need. Alternative: ask the platform for a window.
7. **Launch lifecycle (§P4-7).** (a) the hand-off becomes 0.5 s when the mark moves (0.4 s today), the tap case stays 0.25 s; (b) the 250 ms rule has the launch as its exception, now also for this move; (c) `launchRevealsRoot` and an empty gauge slot during the move; (d) the splash is not made the last frame (L15). Please confirm (a)–(c).
8. **Thin-digit switch.** Profile → Display (recommended) or on Today.
9. **`DotRow.Mark.noData`** is an addition to a PR 2 component (T4.0), so a night without data is not drawn as a miss. OK?
10. **MockData** gets the board's night (T4.0), which changes today's mock values (performance 87 → 94, need 538 → 498, debt 137 → 30, consistency 81 → 86, stages), and with them existing tests that pin them.

## PR 5 — the accent change, tab bar, Strain, Insights, Profile, Sleep modes

Scope (plan.md "After the screen audit", L27–L30): **T5.0** the accent change (teal is recovery only; the light pill is the primary
button); the **dot tab bar**; **Strain** and the **Workout detail**; **Insights**; **Profile's main list**; **Sleep → Week, Month and
Bedtime** with the mode picker. Not here: Profile's subpages, Sleep's editors and sheets, Train, Auth, onboarding, My Day (PR 6; T5.0
only swaps their buttons and tints). No model, sync or API change: data the boards show and the app lacks is inventoried in §P5-9.
Inputs: `plan.md` L27–L30 and the PR 4 carry-overs, `review.md` (PR 4 row 21; PR 2 rows 9–13, 17), `audit.md`, the lead's board
measurements (`pr5-boards.md`, 2026-11-18), and the PR 1–4 sections above. Companion file: **`accent-map.md`** (every `Theme.accent`
use with its replacement, and the D3 preview list). Draft renders for the four screens without a board (L28) and the tab bar are in the
lead's scratchpad (`pr5-drafts/`, listed in §P5-13); they were built from the real components on the demo data.

Conventions are PR 4's (390 pt boards, **350 pt** content, 20 pt sides; "ink" is `textPrimary`; the boards' **0.62 is `textSecondary`,
0.55 and 0.45 are `textTertiary`** (48 %), **0.78 is a glow label**; gaps are bottom of one element to top of the next; fixed heights are
exact, a text line is its natural height). Layout constants are `nonisolated static let`s on `StrainLayout`, `InsightsLayout`,
`ProfileLayout`, `SleepModesLayout` (P2-D9). Contrast is WCAG 2.x on sRGB composites, the worst pixel over the padded text rect, as in
§P4-3; the numbers below come from a script (`make contrast` in the lead's scratchpad, which reproduces §P4-3's hypnogram row, 7.21 and
5.13, to the hundredth) and are reproduced by tests 6–12.

### P5-0. Decisions in one table

| # | Decision | Where |
|---|---|---|
| 1 | **`PrimaryButton` and `TealButtonStyle` are deleted, not kept for Auth.** `PillButton` gains `.destructive`, `busy`, an `async` action and an icon table, which were the only reasons P2-9 kept `PrimaryButton`. 58 call sites + 4 catalog entries and 32 + 14 (`ImportPrimaryButton`) move. | §P5-1.2 |
| 2 | **`Theme.accent`, `onAccent` and `teal` are deleted** after the sweep; the compiler finds every site. The legend is `recovery`, `metricSleep`, `metricStrain`. The app-wide `.tint` becomes `textPrimary`. | §P5-1.3, `accent-map.md` |
| 3 | Toggles: a new `RyftToggleStyle` (light track, dark knob). Links: `ryftLink()` (`textPrimary`, underlined). Icon tints: `IconDisc`. Selected states change shape, not hue. | §P5-1.4 |
| 4 | **The tab bar is a custom `RyftTabBar`** in the `TabView`'s bottom safe-area inset, the system bar hidden. The system bar cannot be flattened on iOS 26+ (tried on 27.2: the glass capsule stays, only the dot and colours change). | §P5-2 |
| 5 | The zone block is one `ZoneBlock` over five `TickRow`s that share one label column, or all stack. `TickRow` gets an `arrangement`. | §P5-3.4 |
| 6 | Strain keeps its week selection as a new `DayStrip` (44 pt under the header); the board has none. | §P5-3.1 |
| 7 | **The HRV card is teal (recovery), not the board's strain blue.** "The rings are the legend". | §P5-5.2 |
| 8 | Insights' glow tile shows the first visible **info** insight under its own severity word ("Insight"); notice and warn insights are neutral cards above it. The board's "An idea" promises advice the rules do not give. | §P5-5.1 |
| 9 | Profile: the app's real rows in seven grouped cards; the display name falls back to the email, initials to its first letter (R-N2 open). The status dot is neutral, not teal. | §P5-6 |
| 10 | Sleep Week, Month and Bedtime use Day's header, picker and components; stage tints are the sleep violet at 100 / 80 / 62 %, no blue. | §P5-7 |
| 11 | The Workout detail is the Strain screen for one workout (numeral, ruler, zone tile) with stat tiles and a neutral heart-rate chart; no red. | §P5-4 |
| 12 | The `SegmentedPicker` is restyled in place (board: surface, ink-filled selection, 34 pt segments); Sleep's AX menu keeps its behaviour. | §P5-7.1 |

### P5-1. T5.0 — the accent change

**1. What teal is.** `Theme.recovery` (`#63D2B4`, the asset `Accent`) is the colour of the recovery metric: the ring, the recovery
glow tile, the readiness delta, the HRV line, the readiness band. It is not the app's interactive colour. After T5.0 nothing that is
not a recovery value is teal. Volt stays the marked thing (§1 of the brief). Everything else that was teal is `textPrimary` (a
glyph, a link, a selected state, a control) or `textSecondary` (a spinner).

**2. Buttons.** `PillButton` (P2-4) becomes the one button. Additions, all additive:

```swift
enum PillButton.Style { case primary, secondary, destructive }
init(_ title: Text, style: Style = .primary, systemImage: String? = nil /* nil = the table below */, busy: Bool = false,
     action: @escaping () -> Void)
init(_ title: Text, style: Style = .primary, systemImage: String? = nil, busy: Bool = false,
     action: @escaping () async -> Void)                  // PrimaryButton's shape: the pill runs it in a Task
init(verbatim title: String, ...)                          // a title from outside (a tracker's app name), never parsed
static let destructiveOutlineOpacity = 0.70               // alert at 70 % over background: 3.47:1 (surface 3.37), the 3:1 for a boundary
```

| Style | Look | States |
|---|---|---|
| `.primary` | as P2-4: `textPrimary` fill, `.button` title in `background`, the 40 pt `background` icon circle, trailing | **busy:** the circle's glyph is replaced by a `ProgressView` (`textPrimary`, `.small`), the title stays, the pill is disabled for taps and keeps its width; VoiceOver value "In progress" |
| `.secondary` | as P2-4: 1 pt outline `textPrimary` 20 %, title centred in `textPrimary`, no icon | **busy:** the title is replaced by a `ProgressView` (`textPrimary`), the label stays "Sync now" for VoiceOver, value "In progress"; the width does not change |
| `.destructive` | outline 1 pt `alert` at 70 %, title in `alert` (6.09 on background, 5.70 on surface), no icon, centred | busy as secondary with an `alert` spinner. A destructive action that shares a row with a primary (Delete account) is never the primary |

Disabled is P2-4's: the whole pill at 35 %. `PillButton` stays 52 pt and grows with Dynamic Type; the 38 secondary and 4 destructive
sites are `PrimaryButton`'s 44 pt capsules today, so every button row grows by 8 pt (accepted: D5-1). Two pills side by side
("Allow access", "Open Health"; "Sync now", "Full re-sync") are both `.secondary` or `.destructive` (no icon, so 169 pt is enough);
from AX1 the pair stacks. A `.primary` is full width, or fills a row beside one outline pill (Profile's "Export data" and "Log out").

*Icon table* (the primary's circle glyph; the call site passes nothing unless it differs):

| Glyph | Titles |
|---|---|
| `arrow.right` (default) | Log in, Create account, Continue, Use the other account, Start workout's plan row |
| `checkmark` | Save password, Agree and continue, Review and agree, Done, Save |
| `arrow.up` | Send reset link, Send |
| `arrow.up.right` | Open Mail, Open Health, any link out |
| `arrow.down` | Export data |
| `play.fill` | Start workout |
| `arrow.clockwise` | Check again, Try again |

**Why `PrimaryButton` does not survive** (P2-9 said it stays for Auth, `.destructive`, `busy`): L27 moves Auth to the Nocturne buttons, and
the two features it kept are now in `PillButton`. Keeping it would leave a teal button in the app. It is deleted in the last ticket
(T5.9) when the grep is empty.

*`PrimaryButton`, 58 call sites (+ 4 in the catalog), by file*

| Replacement | Count | Sites |
|---|---|---|
| `PillButton(.primary)` | 15 | Auth: `SetNewPasswordView` Save password, `CheckInboxView` Open Mail, `LogInView` Log in, `CreateAccountView` Create account, `ForgotPasswordView` Send reset link, `AuthComponents` Use the other account; Onboarding (`HealthPermissionView`): Continue ×5 (700, 861, 872, 1053), Agree and continue (770), Done (1117); Profile: Review and agree (383), Send (2045) |
| `PillButton(.primary)` or `.secondary` | 1 | `ProfileView` Check again (1556): `.secondary` when `embedded`, else `.primary` |
| `PillButton(.secondary)` | 38 | `StatusViews` ×3 (Copy details, "… in the App Store", Add a tracker); `CheckInboxView` Resend; `WelcomeView` Create account; `MyDayCard`, `MyDayView` Add activity; `ProfileView` ×22 (Change password, Log out, Test connection, Rescore ×2, Allow access ×4, Open Health ×4, Open Health permissions, Sync now, Export my data, Sync last 3 days again, Copy diagnostics, "… in the App Store", Done, Choose); `AuthComponents` Continue with this one; `FeatureFlagsDebugView` ×3; `NotificationSettingsView` ×2; `AddActivitySheet`, `ActivityDetailView` ×2 (Log in Train, Edit); `HealthPermissionView` Use another account, Check sync; `SportPicker` Use Other. (Profile's main-list rows are action rows now, §P5-6; the others stay pills in their subpages until PR 6) |
| `PillButton(.destructive)` | 4 | `ProfileView`: Delete account (180), Withdraw consent (379), Full re-sync (480), Full resync (786) |
| `busy:` kept | 18 | the same sites; `PillButton(busy:)` |

*`TealButtonStyle`, 32 uses (13 default, 5 `prominent: true`, 2 `prominent: paused / model.isPaused`, 12 `prominent: false`), + 14 call sites of
`ImportPrimaryButton`*

| Replacement | Count | Sites |
|---|---|---|
| `PillButton(.primary)` | 20 | `TrainSection` ×3 (Start workout 21, 207, 226), `TodayView` Start (704, `Label` kept as the title with `play.fill`), `PlansView` ×2 (286; 171 and 281 when `paused`/`isPaused`: Resume plan), `RestTimerView` 180, `RestSheet` 133 and 146, `SessionView` 597 and 638, `AllSetsDoneCard` 28, `PushPrePromptCard` 20, `HealthPermissionView` 1308, `CoachMarks` 147, `ImportFlowView` 139 (`ImportPrimaryButton`, so its 14 call sites follow) and 242 |
| `PillButton(.secondary)` | 12 | `TodayView` 706, `PlansView` 112, 120, 171 / 281 when not `paused`, `PlanBuilderView` 41, `TrainSection` 234, `ImportResultView` 392, `AddExerciseSheet` 110, `SessionView` 327 and 641, `HealthPermissionView` 1377, `PushPrePromptCard` 24 |

`ImportPrimaryButton` keeps its identifier and its disabled caption wiring and wraps `PillButton`. The live workout's Finish (`SessionView`
289–297, `controller.finishIsFilled`) is a hand-built capsule, not `TealButtonStyle`: T5.0 swaps its token (filled: `textPrimary` fill,
`background` ink; outline: `textPrimary`), PR 6 restyles it with the AX layout of L30 intact (the AX3 tests of `SessionView` must stay green).

**3. Tokens.** `Theme.accent`/`recovery`: `recovery` stays (alias of the `Accent` asset); `accent`, `onAccent` (25 uses → `Theme.background`)
and `teal` are removed; `band(forScore:)` returns `recovery`; `color(for severity)` returns `textSecondary` / `warning` / `alert`;
`zones` is removed with `ZoneBar` (§P5-3). `Theme.accentSecondary` (sage `#6EA89A`), the one hue off the legend (PR 1 §2 "PR 5 reworks the
zones"): its zone use goes with `ZoneBar`, its info-insight use becomes `textSecondary`, `MetricSpec.steps` and `respRate` become
`textPrimary`; `LoadChip` (Train) still uses it, so **the token goes in PR 6**, when Train is restyled. `MetricSpec.activeKcal` (`warning`)
and `rhr` / `heartRate` (`alert`) become `textPrimary`: amber and red mean "attention" only. `StageDeep/Light/REM/Awake` (the blue stage
tokens) lose their last callers in §P5-7 (`StageRow`, Sleep range) and are deleted with them; `StageAwake`'s one remaining use, the zone
colours, goes with `zones`.

The sweep over the 229 `Theme.accent` uses is `accent-map.md`: 12 spinners, 38 tints, 23 medallions, 15 solid fills, 25 graphics, 16
selected states, 74 glyphs or link texts, 26 data or special cases, each with its replacement and its file and line.

**4. The new primitives** (all in `Design/`, token-only, dark previews at default size and AX3, catalog entries, no strings):

| Component | Spec |
|---|---|
| `RyftToggleStyle` (`.toggleStyle(.ryft)`) | A 51 × 31 pill. **On:** `textPrimary` track, a 25 pt `background` knob at the trailing end (17.35:1). **Off:** 1.5 pt `textTertiary` outline on the ground (4.54:1: a boundary needs 3:1; the filled-grey system off state would be 2.5:1), a 25 pt `textTertiary` knob at the leading end. Both knobs have an inset of 3. 250 ms knob slide, none under Reduce Motion. The row is the target (≥ 44 high); disabled 35 %. It stays a `Toggle`: `ToggleStyle` keeps the switch accessibility (label, value "on / off", `isToggle`), so no hand-made traits. |
| `ryftLink()` | `View` modifier for a text that is a control on its own line: `.callout`, `textPrimary`, underline in `textPrimary` at 50 % (the same ink as the body text would not be a cue by colour: 17.35 against `textSecondary` 6.95 is 2.5:1, so the underline is the cue, WCAG 1.4.1), `frame(minHeight: 44)`, `contentShape`. Inside running text a link is the same with the link on its own words. |
| `IconDisc(systemImage:size:)` | 36 pt disc (40 for a row's leading icon), no fill, a 1 pt ring `textPrimary` at 16 % (the circle button's), the glyph `textPrimary` at 16 pt `.light` (≈ 1.2 pt stroke, the board's). Not a button; hidden from VoiceOver unless the caller labels it. |
| Selection | A selectable row or chip: selected = `textPrimary` ring 1.5 pt (or an inverse fill: `textPrimary` with `background` ink for a chip) and a filled glyph (`checkmark.circle.fill`); unselected = the `separator` ring and `circle`. Hue never carries the state. `Card`'s selectable row, `EffortScale`, `BodyweightQuestion`, `ImportSessionRow` and `AddExerciseSheet`'s chips (the 16 **S** uses) follow it. |
| App tint | `RyftApp`: `.tint(Theme.textPrimary)`; `PreviewSupport` the same. Menus, date pickers and steppers inherit it. |

**5. Contrast of every new pairing** (WCAG 2.x, sRGB; text 4.5, boundaries and graphics 3)

| Pairing | Ratio | Needs |
|---|---|---|
| `background` on the primary fill `textPrimary` (title, icon circle glyph's ground) | 17.35 | 4.5 |
| Pressed primary (fill 85 %): `background` text | 12.52 | 4.5 |
| `textPrimary` title on `background` / `surface` (secondary) | 17.35 / 16.24 | 4.5 |
| Secondary outline `textPrimary` 20 % / circle border 16 % on `background` | 1.71 / 1.49 | accepted, PR 2 row 14: the title or glyph names the control |
| `alert` title on `background` / `surface` | 6.09 / 5.70 | 4.5 |
| Destructive outline `alert` 70 % on `background` / `surface` | 3.47 / 3.37 | 3 |
| `ryftLink` text on `surface` | 16.24 | 4.5 |
| Toggle on: knob `background` on the `textPrimary` track | 17.35 | 3 |
| Toggle off: `textTertiary` outline and knob on `surface` / `background` | 4.54 / 4.54 | 3 |
| Spinner `textSecondary` on `surface` | 6.78 | 3 |
| Selected chip: `background` on `textPrimary` | 17.35 | 4.5 |
| Disabled controls (35 %) | exempt | — |
| `textTertiary` on a raised fill (`#2F312F`) | 3.94 | the PR 1 rule stands: no `textTertiary` text on a raised fill |

**6. Where T5.0 lands before its screens.** It lands on every screen first, including those PR 6 restyles later: a Welcome with a light
"Log in" pill and an outline "Create account" pill, an onboarding with ink glyphs and pills, the Train screens with ink progress, rest
rings and check marks. These screens keep their layouts and their 44 pt rows; only the colours and the buttons change (and the 8 pt per
button row, D5-1). The AX3 layouts of Welcome and the live workout (L30, merged in #115) are the regression tests for it.

### P5-2. The dot tab bar

**Board** (`pr5-boards.md`): 76 high, pinned, `background`, a top hairline 1 pt ink 8 %; five items space-around, padding 14 top / 16 sides;
each a column: dot 6, gap 6, label 11 pt, min width 44. Unselected: dot ink 30 %, label ink 50 %. Selected: dot Volt, label full ink. 76 =
42 of content + the 34 pt home-indicator inset of an iPhone with one.

**Approach: a custom bar, not the system bar restyled.** Tried on iOS 27.2 with `UITabBarAppearance` (opaque background, template dot
images, Volt `tintColor`, 11 pt title attributes): the dot, the colours and the labels work, but the bar stays Liquid Glass: a
floating capsule with a selection pill, translucent over the content, 70 pt from the screen's sides. There is no supported way to
make it the board's flat, pinned, full-width bar. So `RyftTabBar` (`Design/RyftTabBar.swift`, written with this spec, see §P5-13) is
drawn in the `TabView`'s bottom safe-area inset and the system bar is hidden:

```swift
TabView(selection: Bindable(state).selectedTab) { … }            // five tabs as today, .tag(AppTab.x)
    .toolbar(.hidden, for: .tabBar)                              // iOS 16+: no system bar
    .safeAreaInset(edge: .bottom, spacing: 0) {
        RyftTabBar(items: AppTab.allCases.map { … identifier: "tab.\($0.rawValue)" },
                   selection: state.selectedTab.rawValue, select: { state.selectedTab = … }, reselect: { state.reselect($0) })
            .ignoresSafeArea(.keyboard, edges: .bottom)          // the keyboard covers it, as it covers the system bar
    }
```

What the system bar gave, and where each thing now lives:

| Behaviour | Now |
|---|---|
| Tab state kept (each tab's stack, scroll) | Unchanged: it is still a `TabView`, only its bar is hidden. A hosted test pins it (test 38) |
| Selection, `-RyftTab`, the launch arguments | `AppState.selectedTab` is the single source; `-RyftTab <name>` selects the first tab (`AppState.init`), unchanged. There is no state restoration to keep: the system bar did not persist the selection and neither does the app |
| Tapping the selected tab: scroll to top / pop to root | **Reimplemented.** `AppState.tabStackIDs: [AppTab: Int]`; `reselect(tab)` bumps it; each tab's `NavigationStack` carries `.id(state.tabStackIDs[tab])`, so a re-tap rebuilds the stack at its root and its scroll at the top. Models live in `ScreenModels`, not in the views, so nothing but view-local `@State` (a dialog flag, a path) is dropped, which is what a deliberate re-tap means. `StrainView`'s `path` is the only stack with a binding; the `.id` pops it too |
| VoiceOver "tab, 2 of 5", `app.tabBars` in UI tests | SwiftUI has no tab-bar trait (`isTabBar` does not exist), so: the bar is an accessibility container ("Tab bar", identifier `tab.bar`); each item is a button with the label "Sleep", the value "Tab 2 of 5", the `isSelected` trait on the current one, identifier `tab.sleep`. UI tests: `app.tabBars.buttons["Sleep"]` (11 sites in `MyDayUITests`, `DevicesUITests` ×2, `FocusedSessionUITests` ×3, `ImportUITests`, `NocturneTodaySleepUITests`, `RefreshResilienceUITests`, `StoreSmokeUITests` ×2 uses `.tabBars.firstMatch`) become `app.tab("Sleep")` (a helper in `RyftUITests/Support/UITestSupport.swift`: `app.buttons["tab.sleep"]`) and `app.otherElements["tab.bar"]` |
| Hides under the keyboard | `.ignoresSafeArea(.keyboard, edges: .bottom)` on the bar: the keyboard covers it. Profile's developer fields and the report form are the cases |
| Visible on pushed screens | Yes, as the system bar was (the bar is outside the stacks) |
| Over sheets and the live-workout cover | Under them, as before (sheets and `fullScreenCover` present above the root) |
| The launch overlay | Covers the root and the bar; the matched move's header target is measured in `.global` and does not depend on the inset |

**Component** (`RyftTabBar`, non-generic: a generic view cannot hold static stored properties; items are `String` ids):

| Quantity | Spec |
|---|---|
| Item | `VStack(spacing: 6)`: `Circle` 6 pt + the title in `.tab` (11 pt). Padding 14 top, **4** bottom (the board's 2: the item is then 44 high on a phone without a home indicator), `minHeight 44`, `minWidth 44`, the whole item is the tap target |
| Bar | items space-around inside 16 pt side padding, the hairline `Theme.separator` (8 %; the board's 8 %) on top, `background` extended under the home indicator (`ignoresSafeArea(.bottom)`). Height = 44 + the inset: **78** with an indicator (the board's 76 + 2, D5-3) |
| Selected | dot `Theme.signal`, label `textPrimary` in **Medium** (a second cue besides brightness and the dot: Volt is never alone), `isSelected` |
| Unselected | dot `textPrimary` 30 % (2.45:1: the dot is a mark, the label identifies the tab; the label is `textTertiary` 48 %, 4.54:1, the board's 50 % mapped to the token), label Regular |
| Press | the item at 60 % opacity, no scale |
| Motion | dot colour and label weight change in 250 ms (`Theme.Motion.quick`), none under Reduce Motion |
| Dynamic Type | labels scale with `.caption2` **up to `xxLarge`** (`dynamicTypeSize(...xxLarge)`), as the system bar does; at 390 an item is 71.6 wide, "Insights" is about 46 pt at 11 and 56 at `xxLarge`, so it never truncates. From `accessibility1` the Large Content Viewer shows the label (`accessibilityShowsLargeContentViewer`). The bar's height does not grow beyond `xxLarge`'s one line |
| Safe area | the bar is the bottom inset: every tab's content, pushed screens included, ends above it. `ScreenScaffold`'s own `padding(.bottom, 32)` stays as the air under the last card |
| VoiceOver order | content first, the bar last (the bar is in the inset, after the tab's content in the tree, as the system bar was); within it left to right |

**Today's strain tile (PR 4 review row 21 / D4-19).** With the bar in the inset the viewport ends at the bar's top, so nothing is under
it any more. At 402 × 874 (iPhone 17 Pro) the whole strain tile fits at the scroll top, 4 pt above the bar (`pr5-drafts/tab-bar-today.png`);
at the board's 390 × 844 the tile's lower edge is cut by the scroll viewport, its ruler 15 pt above the bar, and the rest scrolls in
(`tab-bar-today-390.png`). Both are the normal behaviour of a scroll view, not a bar over content. No change to Today's layout.

**Tests** (T5.1): `RyftTabBarTests` (pure: the constants 14 / 6 / 6 / 4 / 16 / 44, `contentHeight` 44, the unselected dot opacity 0.30,
the label cap `xxLarge`); a hosted test with a bottom inset of 34 (bar 78 high, items ≥ 44 × 44, the accessibility tree: container
"Tab bar", five buttons, the selected one `isSelected`, values "Tab 1 of 5" …, identifiers); a hosted test that a `TabView` with the bar
keeps its second tab's `@State` across selection changes; `reselect` bumps only that tab's id; UI: the five tabs open their screens
(`-RyftTab` for each), a re-tap on Strain with a pushed workout returns to Strain's root. The existing UI tests change only in how they
find the bar (the helper).

### P5-3. Strain

`ScreenScaffold(showsHeader: false)`, `NavigationStack` and every destination as today (`Workout`, `ActivityRoute`, `trainDestinations()`,
the start sheet, `-RyftOpenWorkout`, the deep link to a session or plan). The board is for the selected day; the screen is Today's by
default and any of the last seven days by `DayStrip`.

**P5-3.1 Layout** (all gaps bottom to top; `StrainLayout`):

| # | Element | Built from | Size and gap |
|---|---|---|---|
| 1 | **Header** | `ScreenHeader(title: "Strain", trailing:)` (new init: the lock-up style row with a title leading): "Strain" `.ryft(.title)` (26 Light, tracking −0.26), header trait; trailing `CircleButton("plus", "Add activity", iconSize: 14)` opens `AddActivitySheet` for the shown day. Hidden, row height kept, when `screens.myDay.isEnabled` is false (as Today's calendar) | 40 high |
| 2 | **Day strip** | `DayStrip` (new): the last seven days, ending today | 12 below, 44 high (**D5-2**: the board has none; today's week strip is the way to see an earlier day) |
| 3 | **Numeral** | `DotNumeral(Fmt.strain(v), style: heroNumerals.style, glyphGap: glyphGapDetail, placeholder: "00.0", label "Strain 12.4 of 21")`, 125 × 47, centred (Light from AX1) | 22 below the strip |
| 4 | **Caption** | "of 21 · moderate" `.label` (13) `textSecondary`, centred, wraps; the band word per `MetricSpec.strainBand` (light, moderate, high, all out; R-N1 not filed: never "in target") | 12 below |
| 5 | **Split** | `model.strainSplitText` "Cardio 9.2 · Strength 4.1", `.caption` (12) `textTertiary`, centred; only with a strength session; hint "Split by heart-rate and strength load" kept | 4 below the caption |
| 6 | **Ruler** | `RulerScale(range: 0...21, value: strain, zone: RulerScale.zone(lo: 10, hi: 14), zoneStyle: .strain, tickCount: Ticks.strain (64), labels: ["0", "moderate 10–14", "21"], size: .regular)`; no needle without a strain | 14 below (the previous row), 36 high |
| 7 | **Zones tile** | `GlowTile(Theme.metricStrain, kind: .zones)`, 350 × 176 min, radius 28, padding 14 / 16: §P5-3.4 | tile top at ruler top + **56** (`RulerScale(followingGap:)`, as Sleep's hypnogram, review row 11; the board's 20 below the ruler's labels) |
| 8 | **Steps, Active energy** | two neutral tiles, `HStack(spacing: 12)`, each 169 × 80, `surface`, radius 22, padding 14 / 16 / 12: label `.label` `textSecondary`, value `ryftNumber(size: 24)` Light bottom-left at 16 / 10 (+ "kcal" `.caption` `textTertiary`, 3 after); not buttons | 12 below the tile |
| 9 | **Train** | `TrainSection` (today only, `train.enabled`): §P5-3.5 | 24 below (`sectionSpacing`) |
| 10 | **Activities** | "Activities" `.label` `textSecondary`; 10 below, the rows (gap 8): §P5-3.6 | 24 below row 9 (18 below the tiles when there is no Train section: the board's) |
| 11 | **Footer cards** | `HealthAccessHint` and the error / offline card (§P5-3.7) | 12 below |

`DayStrip` (new, `Design/DayStrip.swift`; My Day keeps `DateStrip` until PR 6): seven cells, each 50 × 44, tap target the cell. A cell:
the weekday initial in `.axis` (11) `textTertiary` (`textSecondary` for today), the day number in `.label` (13) tabular below it, 2 apart.
The selected day's number sits in a 28 pt disc: `textPrimary` fill, `background` ink (the segmented control's selection, so one idea of
"selected"). A day with no score has its number in `textTertiary`. No future days. One element per cell: "Monday, November 16, strain 9.8",
"…, no data", the selected one `isSelected`; the strip is a container ("Days of this week"). Contrast: `textTertiary` on `background` 4.54.
Selecting a day cross-fades the numeral (250 ms; none under Reduce Motion) as Sleep's night step does, and posts an announcement.

**P5-3.2 What goes where** (audit rows 47–49; nothing is dropped)

| Today | In Nocturne |
|---|---|
| Title + date sub-line | Header title; the date is in the strip's selection (and "Yesterday" etc. in the announcement and VoiceOver); `model.title` stays as the header's spoken value |
| `DateStrip` rings | `DayStrip` (no ring; the day's strain is in the numeral when selected and in the cell's spoken label) |
| `MetricGauge` ring + delta vs the prior 7 days | The numeral and the ruler. **The delta `model.strainDelta` is not on the board**; it stays as the VoiceOver value and as a caption line "▲ +1.2 vs 7 d" (`DeltaLabel`, strain is neutral polarity so `textSecondary`) after the caption, same row, when there are 3 or more prior days (**D5-4**) |
| Split text | row 5 |
| Steps, Active kcal `MetricTile`s (teal icons) | row 8 (no icons: the colour is the legend); `MetricTile` is deleted (its only caller) |
| `ZoneBar` (five hues, HRR ranges, legend) | The zones tile; `ZoneBar`, `Theme.zones` and `MetricGauge` (only user: `StrainView`) are deleted. The HRR ranges ("50–60 %" …) move to each row's spoken label and a footnote line under the tile |
| "TRIMP 112" in the card header | The tile's head row: "82 min · TRIMP 112" |
| Train card (Start workout, plan, plans, history) | row 9 |
| Activities list (`ActivityRow`, `SessionActivityRow`; My Day list with `MyDayRow(.tile)` behind `today.my_day`) | row 10, one row component for all three |
| `InlineMessage` / `ProgressView` / `HealthAccessHint` | §P5-3.7 |

**P5-3.3 The zones tile and the glow.** `GlowTileSpec.Kind` gets **`.zones`** (strain, radius 28, min height 176, padding 14 / 16,
the ellipse of `.hypnogram`: 90 % × 95 % at 50 % / 55 %, stops 0.97 / 0.92 @ 34 % / 0.55 @ 68 % / 0.10, which is the board's). Text in it: `textPrimary`
(numerals, minutes) and the label rule (78 %); the board's 0.62 on the row labels is not used (it fails in the tile's corners).

| Tile (worst pixel, padded 14 / 16 / 14 / 16) | `textPrimary` | label 78 % | the board's 62 % | needs |
|---|---|---|---|---|
| Zones 350 × 176 | 7.77 | **5.46** | 4.09 | 4.5 |
| 335 × 176 / 362 × 176 / 400 × 176 | 7.80 / 7.74 / 7.67 | 5.48 / 5.44 / 5.40 | 4.11 / 4.08 / 4.05 | 4.5 |
| AX3, stacked rows: 350 × 240 / 300 / 420 | 7.42 / 7.23 / 7.02 | 5.25 / 5.13 / 5.01 | 3.96 / 3.88 / 3.80 | 4.5 (labels go to 100 % from AX1, `labelOpacity`) |
| Lit ticks (`textPrimary`) over the glow at the ticks' rect | 11.72 | | | 3 |

**P5-3.4 The zone block** (review rows 13 and 17, plan PR 5 hook). A new `Design/ZoneBlock.swift` holds five `TickRow`s and decides the
arrangement for all of them:

```swift
enum TickRowArrangement: Equatable { case automatic                       // today's: each row decides (ViewThatFits)
                                     case aligned(labelColumn: CGFloat)   // one line, the label column fixed to this width
                                     case stacked }                       // label + value above, ticks below (177 wide, leading)
extension EnvironmentValues { var tickRowArrangement: TickRowArrangement }   // default .automatic; TickRow reads it
struct ZoneBlock: View { init(zones: [ZoneBlock.Zone], scaleMax: Double = 40, accessibilityLabel: Text) }
```

`ZoneBlock` measures the five labels' ideal widths (a hidden `Text` with a `PreferenceKey`, at the current Dynamic Type), takes
`labelColumn = max(74 scaled, the widest label)`, and picks **aligned** if `labelColumn + 12 + 177 + 12 + valueColumn ≤ the available width`,
else **stacked for all five**. At 390 the widest label, "Z4 · Threshold", is 76 pt, so the row is 76 + 12 + 177 + 12 + 40 = **317 ≤ 318** (350 −
32): aligned, one tick column, with 1 pt to spare. At 375 (SE, 303 available) and from AX1 the block stacks. The ticks are 3 × 12 with
radius 1.5 and a 3 pt gap, 30 of them, lit = `round(min / 40 × 30)` clamped (a zone of 40 minutes or more lights all 30; its minutes are in
the value column), on `textPrimary`, unlit `textPrimary` 12 % (decoration). **AX3:** each row is label · value on one line, the ticks
below, **177 pt wide and leading-aligned** (they do not stretch: tick pitch and lit counts stay comparable with the default size,
PR 2 row 13's question answered). The tile grows (about 14 + 20 + 5 × 42 + 4 × 9 + 14 = 294); rows keep a 9 pt gap. The row's accessibility
label is the caller's: "Zone 3, tempo, 70 to 80 percent of heart-rate reserve, 20 minutes".

Zone names: "Z5 · Max", "Z4 · Threshold", "Z3 · Tempo", "Z2 · Aerobic", "Z1 · Easy" (top to bottom, as the board); generic training terms, not a
brand's. Footnote (not in the tile, 8 below it, `.axis` `textTertiary`): "Zones are in % of heart-rate reserve." (the old `ZoneBar` line).

**P5-3.5 The Train section** (today's, `train.enabled`; between the tiles and Activities, as before). It is not on the board, so it is
composed from the new parts:

| Part | Spec |
|---|---|
| Title | "Train" `.label` `textSecondary` (`TrainSectionTitle`, 13) |
| Start workout | `PillButton(Text("Start workout"), systemImage: "play.fill")`, `.primary`, full width, 52; or, with a session running, the in-progress card: `surface`, radius 22, a 6 pt `textPrimary` dot that pulses (the pulse is off under Reduce Motion; the dot is `textPrimary`, no longer teal), "Workout in progress · 23 min" 15 + "Upper body · 12 sets done" 12 `textTertiary`, trailing "Resume" chip (`textPrimary` fill, `background` ink, 40 high, padding 16: the inverse fill) |
| Plan, My plans, History | one grouped card `surface`, radius 22, rows 56 high (padding 0 16, gap 12): `IconDisc` 36 (calendar / list.bullet.rectangle / clock.arrow.circlepath), title 15, detail 12 `textTertiary`, chevron.right 12 at `textTertiary`; hairline `separator` between rows. Each row is a `NavigationLink(value:)` as today, identifiers `train.plans` etc. kept |

**P5-3.6 Activity rows** (`ActivityListRow`, one view for `ActivityItem.workout`, `.session`, and `MyDayItem` behind `today.my_day`; the
board): 60 high, radius 20, `surface`, padding 0 / 16, gap 12; leading `IconDisc` 36 (the sport glyph, 16 pt `.light`; the dumbbell for a
logged session); title `.callout` (15) `textPrimary`; 2 below, the meta `.caption` (12) `textTertiary`: "07:10 · 42 min · 7.8 km" (start · duration
· distance, else average heart rate "148 bpm"; a logged session "· Load 84.6" replaces the `LoadChip`); trailing the strain `ryftNumber(size: 20)` Light
`textPrimary` ("–" without one, `textSecondary`). The whole row is the link (`NavigationLink(value: Workout / TrainRoute.session / ActivityRoute)`);
no chevron (the board has none; hint "Opens the workout" carries it). A My Day item that does not open a detail is the same row without
a hint. `StrainPill`, `ActivityRow`'s chevron and `SessionActivityRow`'s teal disc are deleted. AX1+: the strain moves under the title
(row grows, `minHeight` 60), the title wraps.

**P5-3.7 States**

| State | Trigger | Look |
|---|---|---|
| Scored day | `strain != nil` | §P5-3.1 |
| Loading | `isLoading && detail == nil` | Unlit numeral (`placeholder`), ruler ticks without needle, the zones tile as a flat `surface` outline (1 pt `separator`, its five rows unlit with "–"), two tile outlines, two row outlines; VoiceOver "Loading this day"; **no spinner** (today's `ProgressView` is removed) |
| No strain / no data for the day | `strain == nil`, `detail` loaded | Numeral "–" unlit, caption "No strain recorded for this day.", ruler without needle, zones tile with "–", tiles "–" or the score's steps / energy, the activities empty state |
| No zone data | `zoneMinutes == nil` | The tile keeps its head ("Heart-rate zones", "–") and says "Your watch didn't record heart-rate zones for this day." in place of the rows (96 high) |
| No workouts | `items.isEmpty` | `InlineMessage` "No workouts recorded on this day." (figure.walk) + `HealthAccessHint` if there is no Health data at all; the Add activity button stays |
| Load error, nothing cached | `model.error` | As loading, plus the app's calm sentence (the shared `LoadFailure` helper of Sleep, R3-N3: never `localizedDescription`) in the zones tile's place, with Details and Today's action ("Sign in", none, "Try again") |
| Offline / stale / gated | `state.refreshIssue != nil` | The shared **`RefreshIssueCard`** (Today's, `Card` surface) 12 below the header row, with its Try again and Details; offline with cached values keeps them in full ink and shows only a one-line status ("Offline — will sync when back", the shared `SyncStatusLineView`, leading) under the strip, because the data is the day's cache |
| Another day | a strip cell other than today | The numeral cross-fades; the Train section is hidden (today only, as now); the caption is unchanged; Add activity opens for that day |
| Demo | `isDemo` | The board's day from `MockData` (§P5-9): 82 min in the zones, 9,412 steps, 612 kcal |
| Refreshing | `isRefreshing` | Pull-to-refresh as today; no inline indicator |

**P5-3.8 Accessibility.** Reading order: "Strain" (header; trailing "Add activity", hint "Opens the add-activity sheet") · the strip ·
numeral "Strain 12.4 of 21" · the caption (with the split, hidden: it is in the numeral's value) · ruler ("Strain scale", "12.4, moderate, on a scale from 0 to 21. The
moderate range is 10 to 14.") · the zones tile (one element: label "Heart-rate zones", value "82 minutes. Zone 5, max, 6 minutes; …; zone 1, easy, 11 minutes. TRIMP 112. Zones are in percent of heart-rate reserve.") · Steps ·
Active energy · Train (buttons) · "Activities" (header) · each row ("Run, 7:10 AM, 42 minutes, 7.8 kilometres, strain 9.8", hint "Opens the workout"). Volt is the needle's
position only. Dynamic Type: header, strip, numeral (Light from AX1), ruler as P4; tiles stack to one column (350) from AX1; rows stack as above; the zone block as §P5-3.4.
Reduce Motion: no needle move, no numeral cross-fade. Reduce Transparency: `GlowTile` flat `surface` + 2 pt `metricStrain` border (§P4-3).

### P5-4. Workout detail (Strain family; no board; draft renders `pr5-drafts/draft-workout-top.png`, `-bottom.png`)

The pushed screen (`WorkoutDetailView`, `-RyftOpenWorkout YES`). `ScreenScaffold`-style scroll, no navigation bar (`.toolbar(.hidden)`; the
back button is in the header, the swipe-back gesture stays: the pushed view keeps `navigationBarBackButtonHidden`).

| # | Element | Spec |
|---|---|---|
| 1 | **Header** (`ScreenHeader` three-slot) | `CircleButton("chevron.left", "Back")` · centre: the sport name `.callout` (15, header trait) and 2 below "Wed, Nov 18 · 6:40 AM–7:32 AM" `.caption` `textTertiary` · an empty trailing slot (a 40 pt spacer). 40 high |
| 2 | Numeral | `DotNumeral(Fmt.strain(workout.strain), glyphGap: glyphGapDetail)`, 22 below; caption "Strain · of 21 · moderate" 12 below; ruler 0–21, zone 10–14, 14 below: Strain's rows 3–6, for this workout |
| 3 | Zones tile | `GlowTile(metricStrain, kind: .zones)` with the `ZoneBlock`, its head "Heart-rate zones" and "48 min" (the workout's zone minutes), tile top at ruler top + 56. No zone data: the short tile with "No heart-rate zones for this workout." |
| 4 | Stat tiles | `LazyVGrid`, two columns, gap 12, 80 high, radius 22: Duration "52 min", TRIMP "114", Average heart rate "148 bpm", Max heart rate "176 bpm", Energy "540 kcal", Distance "5.2 mi" (only with a distance). Odd count: the last tile alone, left. Labels `.label` `textSecondary`, values 24 Light | 
| 5 | Logged session | Only with `sessionId`: a row as §P5-3.6 (dumbbell `IconDisc`, "Logged session", "Load 84.6", chevron), `NavigationLink(value: TrainRoute.session)`; 12 below the tiles |
| 6 | Heart-rate chart | `surface` card radius 22, padding 14 / 16 / 14: "Heart rate" `.label` `textSecondary` leading, "avg 148 bpm" `.caption` `textTertiary` trailing; 8 below, the chart 150 high: **the line in `textPrimary`, 1.4 pt, round joins (not `alert`: red means attention, and the heart rate is not a metric of the rings)**; the average a dashed rule 1 pt `textTertiary`; the peak a 3 pt `textPrimary` dot with "peak 159" `.axis` `textSecondary`; the y-axis on the trailing side (three ticks, `textTertiary`, gridlines `textPrimary` 8 %), x clock ticks every 15 min. Scrubbing and the Charts accessibility descriptor stay |
| 7 | Source | "Recorded by Garmin Connect" `.caption` `textTertiary`, leading, 14 below |

The ticks' footnote "Zones are in % of heart-rate reserve." sits 8 below the zones tile. States: loading (`isLoading`): the numeral from the
list's `workout.strain`, the zones tile and chart as outlines, no spinner; no heart-rate series: the chart card says "No heart-rate series
available for this workout." (existing string) at `textTertiary`; offline: cached detail shown, the shared status line under the header. Accessibility:
header ("Run", value "Wednesday, November 18, 6:40 AM to 7:32 AM"), numeral, ruler, zones tile, each stat tile one element, the session row, the chart (label
"Heart rate over time", value "Average 148 beats per minute, peak 159"). The zone tile and chart contrast as §P5-3.3; the chart line `textPrimary` 11.7 on `surface`
over its rules.

### P5-5. Insights

`ScreenScaffold(showsHeader: false)`, a `NavigationStack` as today, `focusedMetric` and `focusesBehaviors` scrolling kept.

**P5-5.1 Layout** (`InsightsLayout`)

| # | Element | Built from | Size and gap |
|---|---|---|---|
| 1 | **Header** | `ScreenHeader(title: "Insights", trailing:)` with the range control as the trailing view (not a circle button): the restyled `SegmentedPicker` (§P5-7.1) with the titles "7 D", "30 D", "90 D" (VoiceOver "7 days" …), about 168 × 40. From AX1 the control goes under the title, full width, 44 high | 40 high |
| 2 | **Attention cards** | the visible insights of severity `notice` and `warn`, each `InsightCardView` (§below) | 22 below the header, 12 apart; none if there are none |
| 3 | **Insight tile** | `GlowTile(Theme.recovery, kind: .idea)` for the first visible `info` insight: 120 high minimum, radius 28, padding 16 top / 18 sides. Row 1: a Volt dot 6 pt, 8, "Insight" `.label` (13, full `textPrimary`); trailing the dismiss "×" (44 pt target, 14 pt glyph, `textPrimary`). 10 below: `insight.title` `ryftNumber`-style 17 Light, line height 1.4, `textPrimary`. 8 below: `insight.body` `.label` (13) in full `textPrimary` (recovery tiles set labels at 100 %, §P4-3). Last: "Show the chart" / "See behaviors" / "See the session" as `ryftLink()` (44 high), only with a route | 22 below the header (12 below row 2 cards) |
| 4 | **More insights** | the remaining visible `info` insights as neutral cards (below) | 12 below, 12 apart |
| 5 | **Behaviors** | `BehaviorsSection` (journal live), restyled by T5.0's token swap; its layout is PR 6 | 24 below |
| 6 | **Trend cards** | the three board cards, then the rest, §P5-5.2 | 24 below (the board: 12 under the tile with no other sections; 12 when rows 2, 4 and 5 are empty) |
| 7 | **Footer** | the wellness disclaimer: "RYFT is a wellness tool, not a medical device. Talk to a doctor about health concerns." with the stethoscope glyph, `.caption` `textTertiary` | 24 below the last card (**D5-5**: it was under the title; it stays on the screen, last, because the board's header has no room for it) |

*Insight cards* (rows 2 and 4; the existing `InsightCard` restyled, no coloured stripe): `surface`, radius 24, padding 16 / 18; row 1: a 6 pt dot (`warning` for
notice, `alert` for warn, hollow `textTertiary` ring for info) + the severity word ("Notice", "Attention", "Insight") in `.label`, the colour only on the dot, the word in
`textSecondary`; the kind's glyph is dropped (it was the second hue); the dismiss ×; `title` `.headline` (17 Medium), `body` `.callout` (15) `textSecondary`, the link `ryftLink()`.
A severity is never colour alone: dot shape (filled / hollow), the word, VoiceOver "Attention: …".

**Why the tile is "Insight", not "An idea".** The board's Volt dot and "An idea" promise advice. The platform's insights are rule
observations (`hrv-low-3d`, `readiness-up`, `hrv-best-30d`, `baseline-learned`, `pr`, `behavior-impact`…) with a title and a body; calling one an
idea would be wrong for "HRV is above your range" and for a personal record. The glow tile is the recovery colour, so it carries
only `info` insights (good news and neutral facts); a `notice` or `warn` is never in the teal tile (D5-6). The Volt dot is the brief's
"hint dot on Insights", kept on the tile.

**Contrast, the insight tile** (recovery glow, padded rect 16 / 18, worst pixel): `textPrimary` and the 100 % label

| Tile | `textPrimary` | 78 % (not used in recovery) | the board's 62 % |
|---|---|---|---|
| 350 × 120 | **6.21** | 4.50 | 3.47 |
| 335 × 120 / 362 × 120 / 400 × 120 | 6.25 / 6.18 / 6.11 | 4.53 / 4.49 / 4.44 | |
| 350 × 150 / 200 / 260 | 5.85 / 5.43 / 5.15 | 4.28 / 4.01 / 3.83 | |
| 350 × 320 / 420 (AX3) | 4.98 / **4.81** | 3.72 / 3.61 | |
| Volt dot at its corner | 6.13 | | 3 |

So **all text in the tile is full `textPrimary`** (the label rule for recovery, §P4-3, makes this the default) and the board's 0.78 and 0.62 do not exist
in it (D5-7). 4.81:1 at 420 pt is the limit: **`GlowTileSpec` draws a `.idea` tile flat (`surface` + a 2 pt recovery border, the Reduce Transparency look) when
it is taller than 420 pt**, so a long body at AX3 never reaches the corners where the ratio would pass under 4.5 (`paddedRectContrast` is extended to this kind and
size, plan carry-over). `GlowTileSpec.Kind` gets **`.idea`**: the `.hypnogram` ellipse and stops, radius 28, min height 120, padding 16 / 18 / 16 / 18.

**P5-5.2 Trend cards.** Three first, in the board's order: **Readiness, HRV, Sleep per night** (`TrendMetric.readiness`, `.hrv`, `.sleepMin`); then
the other eleven (`recovery`, `strain`, `sleep`, `rhr`, `steps`, `active_kcal`, `strength_min`, `volume_kg`, `sleep_quality`, `sleep_consistency`, `nap_min`)
under a "More trends" label (`.label`, 24 above), as today's list, so every deep link still lands (`focusedMetric` scrolls to its card and opens it).

`TrendCard` (new layout, replaces `TrendCard`+`TrendChart` in the list): 350 wide, **132 high** minimum, radius 24, `surface`, padding 14 top / 16 sides / 14.

| Part | Spec |
|---|---|
| Head row (first baselines aligned) | the name `.label` (13) `textSecondary`; trailing a note `.caption` (12) `textTertiary`, then a 12 pt `chevron.down` (D5-8: the card opens in place) |
| Value row (2 below) | the latest value `.metric` (26 Light) `textPrimary` + the unit `.caption` `textTertiary` (3 after), 8, then the delta (`DeltaLabel`, 12): "▲ 11 vs 7 d" in the **metric colour** for the good direction, `alert` for the bad, `textSecondary` for flat or neutral |
| Chart (6 below) | `TrendLine`: 318 × 48 (the card's inner width), the series as a 1.4 pt line, round caps and joins, a missing day breaks the line, a lone point draws a 3 pt dot; the y scale spans the series and the band, with a 2 pt inset; the 30-day range as a rectangle behind it |
| Expanded | the card grows by the detailed chart (`TrendChart`: 150 high, axes, scrub, baseline, restyled to the tokens) and the Avg · Min · Max row; tap toggles; `focusedMetric` opens it |

| Metric | Line | Band (30-day range) | Delta colour | Note |
|---|---|---|---|---|
| Readiness | `textPrimary` | `textPrimary` 6 % | `recovery` ("▲ 11 vs 7 d") | "Band: 30-day range" |
| **HRV** | **`recovery`** | **`recovery` 12 %** | `recovery` ("▲ 6 ms") | **"SDNN"** |
| Sleep per night | `metricSleep` | `metricSleep` 12 % | `metricSleep` ("▲ 0:17") | "Avg 7:31 h" |
| Recovery | `recovery` | none | `recovery` | "Avg 78 %" |
| Strain, strength, volume | `metricStrain` | none | `textSecondary` (strain has no polarity) | "Avg …" |
| Sleep (performance), quality, consistency, naps | `metricSleep` | none | `metricSleep` | "Avg …" |
| Resting HR, steps, active energy | `textPrimary` | resting HR: `textPrimary` 6 % | `textPrimary` good / `alert` bad (resting HR lower is better) | "Avg …" |

**The HRV decision (D5-9).** The board draws the HRV card in strain blue. The brief's rule is "the rings are the legend": one colour per
metric, everywhere. HRV is a recovery input (Today's recovery tile carries its sparkline; `MetricSpec.hrv` is the recovery teal), and blue means strain: a blue HRV line
would read as a strain trend. So **HRV is `recovery` teal**: its line, its 12 % band and its delta. Readiness is the composite, so it keeps the board's ink line
with a teal delta; that makes HRV the one teal line on the screen, which is right. The card's note is "SDNN" rather than the board's "Morning, RMSSD": the platform and
Apple Health deliver SDNN (`API.md`: "HRV in ms (SDNN)"), and the note must say what the number is.

| Pairing on `surface` | Ratio | Needs |
|---|---|---|
| `recovery` / `metricSleep` / `metricStrain` line or delta text | 9.98 / 6.38 / 5.56 | 3 (line), 4.5 (the 12 pt delta) |
| Line over its own 12 % band: recovery / sleep / strain | 7.96 / 5.40 / 4.79 | 3 |
| Readiness: `textPrimary` line over the 6 % band | 14.15 | 3 |
| The band against `surface` (decoration; the note and the spoken label name it) | 1.25 / 1.18 / 1.16 | none |
| Note and unit `textTertiary` | 4.54 | 4.5 |

**Data.** Value = the latest non-nil point of the selected range; delta = `MetricDelta.against(latest, prior: the 7 days before)` (Strain's rule; no delta
under 3 priors); "Avg" from `series.avg`. The band needs the 30-day series: `InsightsViewModel.monthly` is extended from `showsPersonalRange` (HRV, resting HR) to
**readiness, HRV, sleep (min) and resting HR**, fetched with the range's series (the month's own series when the range is 30 D; one more cached request each otherwise,
`state.trend` skips a fresh one). No band without a 30-day series (note "Band needs 30 days of data"). No new endpoint.

**VoiceOver.** The chart: "Readiness over 30 days, ending above its usual range" (ending above / within / below the band; "…, ending at 78" without a band); the card is one
element: name, value, delta ("up 11 versus 7 days"), note, the chart's sentence; hint "Shows the detailed chart"; `isButton`; in the expanded card the detailed chart's descriptor
(`accessibilityChartDescriptor`) and Avg · Min · Max follow.

**P5-5.3 States**

| State | Trigger | Look |
|---|---|---|
| Scored | series present | as above |
| Loading, nothing cached | `series[metric] == nil && isLoading` | name, "–", a flat 1 pt `textPrimary` 22 % line across the chart box, the note empty; **no spinner**; VoiceOver "Loading" |
| No data for a metric | a series with no non-nil point | value "–", note "No data in this range", the flat line |
| Calibrating (band missing) | no 30-day series | the line without a band, note "Band needs 30 days of data" |
| No insights | `visibleInsights.isEmpty` | a neutral card, `textSecondary`: "Nothing stands out today. Insights appear when your data shifts." / "All caught up for today." (the existing strings), no tile |
| Offline / stale | `state.refreshIssue != nil` | the shared `RefreshIssueCard` 12 under the header; cached cards stay in full ink with the data's date in the card (the stale series' `to` day is spoken) |
| Not set up | `!state.hasDataSource` | the header and a neutral card "Connect a data source to see trends." (`SetupCard`'s sentence); no tile, no cards |
| Demo | `isDemo` | the board's cards from `MockData` (§P5-9) |

### P5-6. Profile — the main list

`ScreenScaffold(showsHeader: false)`; one `NavigationStack`; every sheet, dialog and subpage as today (the subpages are PR 6: they keep their code, with T5.0's
tokens and pills). **The app's real rows are the content; the board gives the look.**

**P5-6.1 Layout** (`ProfileLayout`)

| # | Element | Spec | Gap |
|---|---|---|---|
| 1 | Header | `ScreenHeader(title: "Profile")`, no trailing | 40 high |
| 2 | **Identity row** | `HStack(spacing: 16)`: the avatar (72 × 72) and a `VStack(alignment: .leading, spacing: 6)`: the name `ryftNumber(size: 20)` Light `textPrimary` (the title, 1 line, middle truncation; wraps at AX), and the status row: a 6 pt dot, 6, the line `.caption` (12) `textSecondary` | 18 below the header |
| 3 | Group title + card | the title `.label` (13) `textTertiary`; 8 below, the card: `surface`, radius 22, rows ≥ 46 high, padding 0 / 16, row title `.callout` (15), the value trailing `textTertiary` (the board's 0.55), a `separator` hairline between rows | 24 below the identity row, then groups **18** apart (the board) |
| 4 | **Buttons row** | `HStack(spacing: 12)`: `PillButton(Text("Export data"), systemImage: "arrow.down")` primary, fills; `PillButton(Text("Log out"), style: .secondary)` with `padding(.horizontal, 22)`-sized width (≈ 108). Each only when it applies (export: `canExport`; Log out: signed in) | 18 below the last group (before Developer) |

**The avatar:** a 72 pt frame; a **strain ring** of radius 34, stroke 1.6, round cap, `metricStrain`, from 12 o'clock clockwise by the share `strain / 21` of today's score (the board's
59 % reaches about 7:30), ending in a dot r 3.4 `metricStrain` with a 1.6 `background` ring (as the gauge's end dots); the track (derived, not measured) `textPrimary` 10 %; inside, at inset 8, a `surface`
disc with the initials `ryftNumber(size: 20)` Light `textPrimary`, tracking 0.04 em. No strain today: the track only, no arc and no dot. The avatar is `accessibilityHidden`; the identity row is one element.

**The display name (R-N2, no editable name yet).** `accountTitle` as today: the platform's `User.name` if not empty, else the account's email (`accountEmail`, middle truncation), else
`auth.identityDescription` (the account's provider description). Initials from the displayed title: for a name, the first letters of its first two words, upper case ("Alex Doe" → "AD"; one word → one letter);
for an email, the first letter of its local part; for neither (signed out, demo without a name) the `person` glyph at 20 pt Light. The name is read-only until R-N2: no edit affordance, nothing that says it
cannot be changed. When R-N2 lands the row becomes a button to a rename sheet. Today's greeting already falls back to nothing (D4-14).

**The status row.** Dot + `"{source} · {state}"`: the source is "Apple Health" (the sync's source); the state is the shared `SyncLine`'s word: "up to date" (a filled `textPrimary` dot), "updating…" (a hollow ring),
"offline" or "updated 5 h ago" (a `warning` dot), "action needed" (an `alert` dot). **The dot is not teal** (the board's recovery-teal dot is overruled by L27: teal is recovery only); the word carries the state, the dot's shape and the
amber / red are secondary cues. Demo: "Demo data · up to date". The row is tappable like Today's status row (Sync details, the gate's step, Try again), 44 pt target.

**P5-6.2 The groups and where every real row goes** (every row of today's `ProfileView` has a place; "→ sub" = a pushed subpage that PR 6 restyles)

| Group (title) | Rows (type) | From today's section |
|---|---|---|
| **About you** | Birth year (menu: value, a `Picker(.menu)` with the tint inherited; error `InlineMessage` under the card) · Maximum heart rate (value + source as the row's detail; opens the sheet, `editing = .maxHR`) · Baseline sleep need (value; sheet `.sleepBase`) · Rescore the last 90 days (an action row, `busy` shows a small spinner; `RescoreStatus` as the card's footer, the line "Changing a setting doesn't rescore past days on its own." under the card as footer text) | Body, Sleep |
| **Devices and sync** | Devices & sync (→ sub; value `devices.summary`; with `devices.setup`) · Apple Health (value `healthStatusText`; tapping asks (`canAskForHealth`) or opens Health ↗; the steps text as the footer) · Last sync (value) · Sync now (action row, busy) · Sync details (→ sub; "Full re-sync" is already in there) · Import training data and the file rows (`ImportProfileRows`, restyled rows) · Demo data (toggle, footer "Show a realistic sample history instead of your server.") | Data |
| **Training** (`showsTraining`) | Advance to the next exercise (toggle) · Session layout (menu row; `showsSessionLayout`) · Save strength workouts to Apple Health (toggle; the `HealthWriteAccessHint` under the card) | Training, Data |
| **Settings** | Notifications (→ sub; `showsNotifications`) · Journal (→ sub; `journal.isLive`; **the row's title is "Journal"**, the app's own feature, not the board's "Behaviors to track": the subpage's title is PR 6's, see question 3) · Hero numbers (menu row: Dots / Thin; PR 4 §P4-6, footer "Large numbers on Today, Sleep and Strain.") · Bedtime & wake (→ sub; value `bedtime.summary`; `bedtime.isEnabled`) | Notifications, Journal, Display, Sleep |
| **Privacy** | Health-data consent (value; the detail as the footer) · Review and agree (action row, when not current) or Withdraw consent (a destructive action row, `alert` ink, confirm dialog as today) | Privacy |
| **Account** (signed in) | Timezone (value, the phone's difference as the detail) · Sign-in methods (→ sub) · Change password (action row; `canChangePassword`) · Delete account (destructive action row, `alert` ink; the alert as today). Signed out: "Signed in: No" and "Turn off Demo data to log in or create an account." | Account |
| **About** | Version (value) · Report a problem (→ sub; the waiting count as its value) · Privacy Policy ↗ · Terms of Use ↗ · Licences (→ sub); the wellness-tool sentence as the footer; the brand lock-up above the group (as today) | About, Privacy (the duplicate link goes) |
| **Developer** (Debug builds) | the same rows, `ryftField` fields on `surface`, toggles `.ryft` | Developer |

Row types (`ProfileRow`): **value** (title, value trailing); **link** (title, value, `chevron.right` 12 pt `textTertiary` at the board's 0.35 look = `textTertiary` at 70 %); **link-out** (title, `arrow.up.right` 12 pt, opens the URL); **toggle**
(`.ryft`, the row is the target); **menu** (title, the current value and `chevron.up.chevron.down` as a `Menu`); **action** (title in `textPrimary`, trailing a spinner when busy; destructive: `alert`). Every row is ≥ 46 high and a full-width
target (≥ 44). Errors (`InlineMessage`) and footers sit under their card, 8 below. The Profile board's other rows ("Behaviors to track", the board's own wording) are not adopted.

**P5-6.3 States**

| State | Trigger | Look |
|---|---|---|
| Signed in, up to date | `isSignedIn`, sync fine | as above |
| Signed out / demo | `!isSignedIn` | the identity row shows `identityDescription` (or "Demo data"), the person glyph; the Account group is the two-row "Signed in: No" version; Log out and Export hidden |
| No strain today | `strain == nil` | the avatar ring is the track only |
| Syncing | `isSyncing` | the status line "updating…" (hollow dot); the Sync now row shows its spinner and `syncProgress` as its detail |
| Offline / stale / sync failed | `syncNotice`, `state.refreshIssue` | the status dot `warning` + "offline" or the age; the `InlineMessage` (retrying / failed with Details) under the Devices and sync card, as today |
| Health access needed | `healthNeedsAttention` | the Apple Health row's value in `warning` with the words ("Not requested") |
| Consent outdated | `!consentIsCurrent` | the consent value in `warning`; "Review and agree" as the first action row |
| Exporting | `model.exporting` | the Export pill `busy`; the share sheet as today; `exportError` under the buttons row |
| Logging out with unsent items | `sendsFirst` | the Log out pill `busy`; the dialog as today |

**P5-6.4 Accessibility.** Reading order: "Profile" (header) · the identity row ("Alex Doe. Apple Health, up to date. Strain today 12.4 of 21.", header trait on the name) · each group's title as a header, then its rows in order (one element each: "Birth year, 1990",
"Maximum heart rate, 190 beats per minute, from your age", "Notifications, button"; the toggles read "on / off" through `Toggle`) · the buttons ("Export data", "Log out"). Link-outs say "opens in the browser". Destructive rows say "Delete account, button" and keep their dialogs.
Dynamic Type: rows grow (≥ 46, wrapping titles, the value under the title from AX1), the identity row stacks the avatar over the name (avatar fixed 72), the buttons row stacks (Export over Log out). Contrast: initials 16.24 on `surface`; the strain ring 5.94 on `background`;
values `textTertiary` 4.54 on `surface`; the hairlines are decoration.

### P5-7. Sleep — Week, Month and Bedtime (no board; draft renders `pr5-drafts/draft-sleep-*.png`)

Day is the board and is not touched here except the colours listed in §P5-7.4. The three modes live under Day's header (`SleepHeader`, buttons hidden and disabled outside Day, subtitle "Last 7 nights" / "Last 30 nights" / "Tonight") and the picker.

**P5-7.1 The mode picker and `SegmentedPicker` (restyled in place)**

| Part | Spec |
|---|---|
| Control | `surface`, padding 3, segment gap 4, radius 20 (the board's Insights control), full width in Sleep (equal segments), content width in the Insights header; segments **34 high**, radius 17, `.label` (13); selected = `textPrimary` fill with `background` text (17.35:1), others transparent with `textTertiary` text (4.54 on `surface`); the control is 40 high. Selection slides (`matchedGeometryEffect`, 250 ms; none under Reduce Motion). Each segment is ≥ 44 wide and **the segment's tap box is 44 high** (the 3 pt padding is inside it) |
| Sleep | Day · Week · Month · Bedtime, 12 below the header. **40 high** (was 52 with its 44 pt segments): Day's content moves up 12 pt (`SleepLayout`'s numeral gap is measured from the picker, 22, so Day's board offset becomes +52 against the board, D5-10) |
| AX1+ | the one-row `Menu` of PR 4 (§P4-8) restyled: `surface`, radius 20, 44 high, "Week ▾" in `.label` `textPrimary`; its items as today with the checkmark on the current one |
| Other callers | Insights' range (3 segments), Profile's session layout (becomes a menu row, §P5-6.2) |
| VoiceOver | a container; each segment a button with `isSelected`; Insights' segments are labelled "7 days" … |

**P5-7.2 Week and Month** (`SleepRangeSection` restyled; the data and the view model's `SleepRangeSummary` are unchanged)

| # | Element | Spec |
|---|---|---|
| 1 | **Numeral** | `DotNumeral(Fmt.clock(avgTotalMin), glyphGap: glyphGapDetail, placeholder: "0:00", style: heroNumerals.style)`, 22 below the picker (`SleepLayout.numeralGap`), centred; caption 12 below: "Average · last 7 nights" / "Average · last 30 nights" `.label` `textSecondary` |
| 2 | **Bed and wake glow tile** | `GlowTile(metricSleep, kind: .hypnogram, min height 168)`; head row: "Bed and wake times" (glow label) leading, "7 nights" `.caption` trailing; 8 below, `BedtimeStrip` (the existing chart: a bar per night from bedtime to wake on a 20:00–10:00 axis, bars `metricSleep`, dashed mean rules): **Week** row 14 pt with the dates on the rows; **Month** row 7 pt, **no row labels** (30 labels collide, seen in the draft), the clock axis kept; 8 below the strip the consistency hint (`.caption`, the glow label colour: 78 %, wraps). The tile grows with the rows (Week about 228, Month about 300) | 20 below the caption (+56 from a ruler is not applicable: no ruler) |
| 3 | **Two neutral tiles** | `HStack(spacing: 12)`, 169 × 88, radius 22, as Day's tiles: **Quality** "91" + "%" (`averageQuality`) · **Consistency** "72" (`averageConsistency`) + a `DotRow` of the last 7 nights bottom-right (full ≥ 60, `.missed` below, `.noData` without; the last mark is `.today` = the newest night, the label says so, as Today's) | 12 below the tile |
| 4 | **Stage card** | `surface`, radius 22, padding 14 / 16 / 14: head "Time asleep per night" `.label` + "avg 7h 58m" `.caption` `textTertiary`; the chart 150 high (`Chart`, `BarMark` per stage per night: **Deep at the bottom, then Light, REM on top**, 1.5 pt `surface` gaps between the segments via a 1.5 pt `surface` stroke, `cornerRadius` 1.5; Week bars `ratio 0.55`, Month `0.7`; weekday initials (Week) or weekly dates (Month) `textTertiary`; the y axis trailing, 0 / 3 / 6 / 9 / 12 h, gridlines `textPrimary` 8 %; the average a dashed rule 1 pt `textTertiary`); the legend 10 below: three 10 pt squares + "Deep", "REM", "Light" `.caption` `textSecondary`. **Tints: Deep `metricSleep` 100 %, REM 80 %, Light 62 %; unstaged "Asleep" 62 %**. No blue anywhere (the stage tokens `StageDeep/Light/REM` are not used) | 12 below |
| 5 | **Nights list** | one grouped card, rows 46 high, padding 0 / 16: the night's title `.callout` `textPrimary` · a nap `Label` (`powersleep`, `.caption` `textSecondary`) · the total `.callout` tabular · the consistency `.caption` `textTertiary` (44 wide, trailing); `separator` hairlines. Month shows every night (30 rows), as today | 12 below |

Contrast: tints over `surface` 100 / 80 / 62 % = **6.38 / 4.50 / 3.19** (graphics need 3); neighbours are 1.42 / 1.41 apart, so stage identity is **never by tint alone**: the fixed
stack order, the legend and the chart's accessibility descriptor (per night: "Wednesday 18: deep 1:35, REM 1:45, light 4:28") carry it, and the 1.5 pt gaps separate the segments. The bars in the glow tile: `metricSleep` 100 % over the glow at its worst pixel in the plot = **3.68**
(Day's deep bars are the same colour in the same tile kind); the tile's text 7.21 / 5.13 at 350 × 168, 6.84 / 4.90 at 350 × 230, 6.62 / 4.77 at 350 × 300, 6.50 / 4.69 at 350 × 360 (needs 4.5). The old red delta text ("▼ −12m · −2 %") of the range header is gone: Week and Month show no delta (the header's value moved into
the numeral; the old header's "vs 7 d" delta is `DeltaLabel` with `metricSleep` for a good change if the lead wants it back: question 6).

**P5-7.3 Bedtime** (`SleepPlannerSection` + `TonightCard`; numbers from `GET /v1/sleep/plan` and `BedtimePlanner`; the editor `SleepScheduleView` is PR 6)

| # | Element | Spec |
|---|---|---|
| 1 | **Bedtime numeral** | `DotNumeral` of tonight's bedtime for the goal (`planner.options.first`), the digits only ("10:06"), + the meridiem ("PM") as `.label` `textSecondary` at the numeral's baseline, 8 after, centred as a pair; 22 below the picker. **`Fmt.clockParts(_ date:) -> (digits: String, meridiem: String?)`** splits on any whitespace, including U+202F: `Fmt.time` returns "10:06 PM" with a narrow no-break space, which sent the draft's first render to the Light fallback. 24-hour locales have no meridiem |
| 2 | Caption | "In bed by · 100 % of your need" `.label`, 12 below; no schedule: see states |
| 3 | **Planned-sleep ruler** | `RulerScale(range: 0...10, value: option.sleepMin / 60, zone: zone(lo: 0.9 × need, hi: need), zoneStyle: .sleep, labels: ["0 h", "need 8:01", "10 h"])`, 14 below: the same ruler as Day's, the needle at the sleep the shown bedtime gives |
| 4 | **Go-to-bed glow tile** | `GlowTile(metricSleep, kind: .hypnogram, min height 176)`, head: "Go to bed" (glow label) + "wake 7:00 AM" `.caption`; then three rows (12, 10, 10 apart): a 6 pt marker (filled `textPrimary` = your goal, hollow 1 pt ring = the other two: shape, not colour), the bedtime `ryftNumber(size: 24)` Light, and trailing "100 % of your need" (`.label`) over "8h 01m asleep" (`.caption`), both at the glow label colour. 20 below the ruler (+56 from the ruler's top, as Day) |
| 5 | **Two neutral tiles** | Need "8:01" + "h" · Time in bed "8:54" + "h" with "90 %" (efficiency) as the note; 12 below |
| 6 | **Settings card** | one grouped card, rows 46: "Wake up at" + the compact `DatePicker` (system chip, tint inherited) · "Why this need" (a disclosure row: expands `NeedBasisRows` inside the card) · "Bedtime & wake" (→ `SleepScheduleView`, the value = the schedule summary); 12 below. The footer "As of 10:44 AM" `.caption` `textTertiary`, 12 below |

Replaces today's `TonightCard` (Tonight, "In bed by 9:36 PM for 100 %", the goals, the disclosure, the teal "Bedtime & wake" link) and the "Try another wake time" card, "Go to bed", "Why this need" cards. The three goals (100 / 85 / 70 %) are the glow tile's rows.

States (Week, Month, Bedtime):

| State | Trigger | Look |
|---|---|---|
| Loaded | `range` / `plan` | as above |
| Loading, nothing cached | `isLoading && range == nil` | the numeral unlit ("0:00"), the tile and cards as `surface` outlines (1 pt `separator`), values "–"; VoiceOver "Loading"; no spinner (the draft's `ProgressView` goes) |
| No sleep in the range | `range` nil, not loading | `InlineMessage` "No sleep data for this range yet." + `HealthAccessHint` when there is no Health data; the numeral "–" |
| Fewer nights than the range | `nights < 7` / `< 30` | the numeral and tiles from what exists; the caption says "Average · 4 nights" |
| Load error | `model.error` | the calm sentence with Details and Today's action, as Day (`SleepLoadFailure`) |
| Bedtime: no schedule | `planner.schedule == nil` | the numeral unlit ("–:––"); "Tell RYFT when you want to wake up. It tells you when to go to bed, with what today's strain and your sleep debt add." `.callout` `textSecondary`; `PillButton(Text("Set up Bedtime & wake"), systemImage: "arrow.right")` → the editor; no ruler, no tile |
| Bedtime: planning | `plan == nil && isLoading` | unlit numeral, ruler ticks without needle, the tile an outline with three unlit rows |
| Bedtime: failed | `planner.error` | `InlineMessage` with retry in place of the tile |
| Bedtime: alarm problem | `planner.alarmProblem` | `InlineMessage` (alarm) under the settings card |
| Offline / stale | `state.refreshIssue` | the shared `RefreshIssueCard` under the picker; cached values in full ink |
| Demo | `isDemo` | `MockData`'s week, month and plan |

**P5-7.4 Day's lower cards (the leftovers of the blue)**: `SleepNeedBar` (strain top-up `metricStrain`, debt `warning`) becomes: baseline `metricSleep` 100 %, the strain top-up `metricSleep` 62 %, debt `textSecondary`, nap credit a 1 pt `textPrimary` outline segment (shape, not hue), the legend as text; `StageRow` (the stages card) draws its share bars in the 100 / 80 / 62 % tints and Awake `textTertiary`. `ProgressBar`'s default colour is `metricSleep`.
`SleepScheduleView`, the Need sheet and the baseline editor are PR 6.

**P5-7.5 Accessibility.** Header, picker (a container, `isSelected`), the numeral ("7 hours 58 minutes average sleep"), the tile (one element: "Bed and wake times, 7 nights. Average bedtime 10:48 PM, average wake 6:50 AM. Fairly regular."), each tile, the stage chart (descriptor per night), each night row ("Wednesday, November 18, 7 hours 48 minutes asleep, quality 91, consistency 86, nap 25 minutes"). Bedtime: the numeral ("Go to bed at 10:06 PM"), the ruler, the tile (one element, the three options with "your goal" on the first), the tiles, the rows. Dynamic Type: the picker becomes the menu from AX1; the 2-up tiles stack from AX1; the stage chart's legend wraps; the nights list rows stack the total under the title; the tile grows; labels in glow tiles go to 100 % from AX1 (`labelOpacity`). Reduce Motion: no needle move, no selection slide.

### P5-8. Motion and the cross-cutting accessibility rules

Every UI animation is `Theme.Motion.quick` (250 ms): the toggle knob, the segmented selection, the tab dot and weight, the day-strip selection and numeral cross-fade, the card
expansion (`standard` is not used), the needle (PR 2). **Reduce Motion** turns every one off (they jump); the Strain and Insights screens add no other motion. No launch-style exception is needed in PR 5.
**Reduce Transparency:** `GlowTile` is flat `surface` with a 2 pt metric border, as PR 2 and §P4-3 say; the `.zones` and `.idea` tiles follow. **Volt** appears only as the needle, the "today" dot in a `DotRow`, the active tab's dot and the Insights tile's hint dot, and each has a position or a word beside it.
**Header traits** on every screen's title; focus order is top to bottom, the tab bar last. A state is never colour alone: dot shape, the word, the glyph, the position. **Dark only**; every preview and render here is dark.

### P5-9. Data inventory and requests

"Exists" means a view-model property or cached API field today (checked against `Models.swift`, `API.md` and the view models). A missing value is a pending look, never a number.

| # | Board element | Source today | Status | When absent |
|---|---|---|---|---|
| ST1 | Strain value, band word | `DailyScore.strain`, `MetricSpec.strainBand` | exists | "–", unlit numeral, no needle |
| ST2 | Zone 10–14 and "in today's target" | the fixed moderate band | **partly** (R-N1 open) | labelled with the band word, never "target" |
| ST3 | Zone minutes Z1–Z5, total, TRIMP | `DayStrain.zoneMin`, `trimp` | exists | "–" per row; the sentence in §P5-3.7 |
| ST4 | Zone names and HRR ranges | hard-coded in the app (`ZoneBar.ranges`) | **partly** (R-N3, optional) | the app's names |
| ST5 | Steps, active energy | `DayStrain.steps/activeKcal`, the score | exists | "–" |
| ST6 | Activities: time, duration, distance, strain | `Workout`, `SessionSummary`, `MyDayItem` | exists | "–" |
| ST7 | 7-day strain delta | `StrainViewModel.strainDelta` | exists (not on the board) | no caption |
| WK1 | The workout: strain, duration, TRIMP, avg / max HR, energy, distance, HR series, zones, source, session | `Workout`, `WorkoutDetail` | exists | per §P5-4 |
| IN1 | 7 D / 30 D / 90 D | `TrendRange` | exists | — |
| IN2 | The insight tile and cards | `Insight` (`severity`, `title`, `body`, `metric`) | exists; **no advice type** (R-N4, optional) | §P5-5.3 |
| IN3 | Trend value, delta, average | `TrendSeries` (`points`, `avg`) | exists | "–" |
| IN4 | The 30-day band | `min`/`max` of the 30-day series; the σ request exists (Charts #3) | exists (derived, as today's HRV and RHR bands) | no band, note "Band needs 30 days of data" |
| IN5 | The HRV card's note | the platform's unit (SDNN) | exists | — |
| PR1 | Name | `User.name` | **partly** (R-N2 open) | email, then `identityDescription` |
| PR2 | Initials, strain share, status | derived from the title; today's `DailyScore.strain`; `SyncLine` | exists | person glyph; track only; the sync word |
| PR3 | Rows | `ProfileViewModel` and the editors | exists | per §P5-6.3 |
| SL1 | Week / Month: average, quality, consistency, bars, bedtimes, nights | `SleepRange`, `SleepRangeSummary` | exists | §P5-7.3 |
| SL2 | Bedtime: options, need, in bed, efficiency, wake | `SleepPlan`, `BedtimePlanner` | exists | §P5-7.3 |

**`MockData` placeholders** (T5.0 owns the file; previews and demo only; tests that pin today's values are re-pinned, each listed in the PR): the demo user is **"Alex Doe", `alex@example.com`**, and the source names "Alex's Apple Watch / iPhone" (today's mock carries the owner's real first name; the public repo should
not: a finding, see question 7); today's `DayStrain`: `zoneMin` Z1–Z5 = 11, 24, 27, 14, 6 (82 min), `steps` 9,412, `activeKcal` 612, TRIMP 112; the demo workouts keep their times (a 06:40 run of 52 min); trends: a readiness series ending above its 30-day range with a +11 delta,
an HRV series ending at 66 ms (+6), a sleep series averaging 7:31 with 7:48 last (+0:17), the other metrics as today; `MockData.insights` gets one `info`, one `notice` and one `warn` so the tile and both card kinds are previewable.

**Requests** (`docs/API_REQUESTS.md`, "Nocturne restyle" block; T5.7 files them; R-N1 and R-N2 are open from PR 4; R-N3 "slept enough" stays unfiled):

3. **R-N3 (optional): the heart-rate zone definitions.** The app hard-codes "Z1 Easy … Z5 Max" and the HRR ranges (50–60, 60–70, 70–80, 80–90, ≥ 90 %); `DayStrain.zone_min` carries five numbers and no meaning. *Proposal:* `DayStrain.zone_bounds_pct` (`[[50, 60], …]`, % of heart-rate reserve, the bounds the platform scored with) in `GET /v1/days/{day}` and `WorkoutDetail`. *Until then:* the app's constants, labelled "Zones are in % of heart-rate reserve."
4. **R-N4 (optional): advice versus observation.** Strain and Insights' tile is called "Insight" because every `Insight` is a rule's observation. *Proposal:* `Insight.type` (`observation` | `suggestion`); the app labels the tile "An idea" for a `suggestion` and "Insight" otherwise. *Until then:* the tile is "Insight".
5. **R-N5 (optional): the usual range for readiness and sleep.** Charts #3 asks for baseline ± σ for HRV and resting HR; Insights now draws a band on readiness and sleep too. *Proposal:* extend it: `baseline_lo` / `baseline_hi` (or σ) on the `/v1/trends` series for `readiness`, `sleep_min`. *Until then:* the 30-day min–max, labelled "Band: 30-day range".

### P5-10. Strings (English only; `Localizable.xcstrings`, targeted edits, a `--stat` check; localization-editor finalises)

| Key (English) | Where / comment |
|---|---|
| `Tab bar` · `Tab %lld of %lld` | VoiceOver: the bar's label, an item's position (the component's only strings) |
| `Opens the add-activity sheet` · `Days of this week` · `%1$@, strain %2$@` · `%@, no data` | Strain: header hint, the strip's container, a day cell |
| `moderate 10–14` · `Z5 · Max` · `Z4 · Threshold` · `Z3 · Tempo` · `Z2 · Aerobic` · `Z1 · Easy` · `%lld min` · `Zones are in % of heart-rate reserve.` | Strain's ruler label and zone block. **Replaces** `Zones in % of heart-rate reserve` |
| `Zone %1$lld, %2$@, %3$@ of heart-rate reserve, %4$lld minutes` | the zone row's spoken label |
| `Your watch didn't record heart-rate zones for this day.` · `No strain recorded for this day.` · `Loading this day` (exists) | Strain states |
| `Recorded by %@` · `Average heart rate` · `Max heart rate` · `Energy` · `No heart-rate zones for this workout.` | Workout detail. **Replaces** `Avg HR`, `Max HR`, `Calories` |
| `7 D` · `30 D` · `90 D` | Insights' segments (VoiceOver keeps `7 days` …) |
| `More trends` · `SDNN` · `Avg %@` · `Band needs 30 days of data` · `No data in this range` · `Shows the detailed chart` | Insights' cards. `Band: 30-day range` exists |
| `%1$@ over %2$lld days, ending above its usual range` · `…, ending within…` · `…, ending below…` · `%1$@ over %2$lld days, ending at %3$@` | a trend chart's spoken label |
| `Connect a data source to see trends.` | Insights, not set up |
| `About you` · `Devices and sync` · `Training` · `Settings` · `Privacy` · `Account` · `About` · `Export data` · `Journal` | Profile's group titles and rows. **Replaces** `Body`, `Sleep` (the group titles), `Export my data` |
| `%1$@ · %2$@` with `up to date` · `updating…` · `offline` · `updated %@` · `action needed` | Profile's status row (the source and the sync word) |
| `Alex Doe. %@, %@. Strain today %@ of 21.` (a template) | the identity row's spoken sentence |
| `Average · last %lld nights` · `Average · %lld nights` · `Bed and wake times` · `%lld nights` | Sleep Week and Month. **Replaces** `Avg sleep`, `Avg quality` |
| `In bed by · %lld %% of your need` · `wake %@` · `Need` · `Time in bed` · `Planned sleep` | Sleep Bedtime |

**Remove** (grep first): `Day strain`, `Active kcal`, `Try another wake time`, `Trends` (the label before the picker), `Show the chart` stays; the keys of the deleted views (`MetricGauge`, `ZoneBar`, `StrainPill`). The strings of `PrimaryButton` callers are unchanged.

### P5-11. Previews and catalog

Dark only (D3), default size and AX3 (`"<View> · <state>"`, `"… · AX3"`). `DebugComponentCatalog` gets, after "Nocturne · rows": `Nocturne · buttons` (primary, secondary, destructive, busy, disabled; icons), `Nocturne · toggle` (on, off, disabled, in a row), `Nocturne · icon disc and link`, `Nocturne · zone block` (aligned, stacked, no data), `Nocturne · day strip`, `Nocturne · trend line` (band above, within, below; broken; lone point; pending), `Nocturne · tab bar` (selected each; AX3), and the glow kinds section gets `.zones` and `.idea` (incl. the flat fallback at 420+).

| Screen | Previews (each × default, AX3) |
|---|---|
| Strain | scored · thin digits · strength split · another day · loading · no data · no zones · no workouts · error · offline with `RefreshIssueCard` · Train section (idle, in progress) · My Day list (`today.my_day`) · Reduce Transparency |
| Workout detail | run · strength (session linked) · no heart-rate series · no zones · loading |
| Insights | scored (all three card kinds) · only the tile · no insights · loading · no data for HRV · calibrating band · offline · expanded card · 7 D, 90 D · Reduce Transparency |
| Profile | signed in · no name (email) · no strain today · signed out / demo · syncing · offline · consent outdated · exporting · the Developer group (Debug) |
| Sleep modes | Week · Month · Bedtime · Bedtime no schedule · loading · no sleep · the picker (default, AX1 menu) · Day with the new picker |
| Tab bar | five selected states; AX3; keyboard up (hidden) |

### P5-12. Tests

Swift Testing, `@MainActor`; pure first. Files: `StrainLayoutTests`, `InsightsLayoutTests`, `ProfileLayoutTests`, `SleepModesLayoutTests`, `RyftTabBarTests`, `PillButtonNocturneTests`, `NocturneP5ComponentTests`, `GlowTileKindP5Tests`, `StrainDataTests`, `InsightsDataTests`, `ProfileDataTests`, `SleepModesDataTests`, `NocturneP5A11yTests`; `RyftUITests` for 52. Mutation-check each new assertion (PR 4's rule).

**Layout constants**
1. `StrainLayout`: header 40, strip gap 12 and height 44, strip→numeral 22, numeral→caption 12, caption→split 4, caption→ruler 14, ruler→tile (`followingGap`) 56, zones tile 176 min / radius 28, tile→tiles 12, tile height 80 / gap 12 / radius 22 / padding 14 / 16 / 12, tiles→Train 24, row 60 / radius 20 / gap 8 / padding 16 / `IconDisc` 36.
2. `InsightsLayout`: header 40, header→first block 22, tile min 120 / radius 28 / padding 16 / 18, tile→cards 12, trend card min 132 / radius 24 / gap 12, padding 14 / 16, head→value 2, value→chart 6, chart 318 × 48 (350 − 32), band opacities 0.06 / 0.12.
3. `ProfileLayout`: header 40, header→identity 18, avatar 72 / ring radius 34 / stroke 1.6 / dot 3.4 / ring 1.6 / inset 8, row gap 16, name→status 6, group title→card 8, identity→first group 24, groups 18, card radius 22, row min 46, buttons 18 below / 52 high / 12 gap.
4. `SleepModesLayout`: picker 40 (padding 3, gap 4, segment 34, radius 17, control radius 20), numeral gap 22, caption gap 12, tile gap 20, tiles gap 12, stage card height 150 (chart), tints 1.0 / 0.80 / 0.62, 1.5 pt segment gap; `SleepLayout.pickerHeight` 40 so Day is +52 against the board.
5. `RyftTabBar`: top 14, dot 6, gap 6, bottom 4, sides 16, item min 44 × 44, `contentHeight` 44, unselected dot 0.30, label cap `xxLarge`.

**Contrast** (computed from `GlowTileSpec.overlayOpacity`, rendered where it says)
6. `PillButton`: `background` on `textPrimary` ≥ 17; pressed 85 % ≥ 12; `alert` title on `background` ≥ 6.0 and on `surface` ≥ 5.6; destructive outline (`alert` 70 %) ≥ 3.3 on both.
7. Toggle: knob on track ≥ 17; off outline and knob (`textTertiary`) ≥ 4.5 on `surface` and `background`.
8. `.zones` (strain, padded 14 / 16): 350 × 176 `textPrimary` ≥ 7.7, 78 % label ≥ 5.4; 335 / 362 / 400 wide; AX3 350 × 240 / 300 / 420 ≥ 7.0 and ≥ 5.0; lit ticks ≥ 11.
9. `.idea` (recovery, padded 16 / 18): `textPrimary` at 350 × 120 ≥ 6.2, 150 ≥ 5.8, 260 ≥ 5.1, 420 ≥ 4.8; every size ≥ 4.5; above 420 the tile is flat (test the switch) and flat `surface` gives ≥ 16; the board's 78 % label **fails** at 350 × 200 (4.01) and the test documents why labels are full ink; the Volt dot ≥ 6.
10. Trend: line over band recovery ≥ 7.9, sleep ≥ 5.4, strain ≥ 4.7; readiness ink over its 6 % band ≥ 14; `textTertiary` note on `surface` ≥ 4.5.
11. Stage tints over `surface`: 100 % ≥ 6.3, 80 % ≥ 4.5, 62 % ≥ 3.1 (graphics need 3); the bars in the `.hypnogram` glow ≥ 3.6; text in a 350 × 230 / 300 / 360 sleep tile ≥ 6.5 / 6.6 / 6.5 and the label ≥ 4.6.
12. Tab bar: label `textTertiary` ≥ 4.5 on `background`; selected `textPrimary` ≥ 17; the unselected dot (0.30) is **documented as under 3** (2.45) and not asserted as a boundary.
13. `GlowTileSpec.shape(for: .zones / .idea)`: ellipse (0.90, 0.95, 0.55), stops, radius 28, min height 176 / 120, padding 14 / 16 and 16 / 18; `.idea` flat above 420; `overlayOpacity` per kind at the stops.

**Components**
14. `ZoneBlock`: five labels measured; at 318 available and the real label widths (76 pt for "Z4 · Threshold") → `.aligned(labelColumn: 76)`; at 303 → `.stacked`; from AX1 → `.stacked`; **all five rows' ticks start at the same x** (hosted, ±0.5 pt) when aligned; `TickRow` under `.stacked` keeps 177 pt ticks leading-aligned; `.automatic` is today's behaviour (the PR 2 tests unchanged).
15. `TickRow.litCount(minutes:scaleMax: 40)` for the board's zones: 11 → 8, 24 → 18, 27 → 20, 14 → 11, 6 → 5; 40 → 30; 90 → 30.
16. `RyftToggleStyle` (hosted): still a switch (label, value "on" / "off", `isToggle`), frame ≥ 51 × 31 and the row ≥ 44, `activate()` toggles, disabled does not.
17. `PillButton`: `.destructive`; `busy` disables the action, keeps the label, adds the value "In progress", width unchanged between busy and idle; the `async` init runs the action once; `systemImage: nil` takes the default; AX3 grows without clipping (PR 2 tests 25 extended).
18. `IconDisc`: 36 / 40, ring 16 %, no fill; hidden unless labelled. `ryftLink()`: 44 high, underline.
19. `DayStrip`: seven cells ending today, each 50 × 44, the selected cell's disc, no-data number `textTertiary`, spoken labels ("Monday, November 16, strain 9.8", "…, no data"), `isSelected`, the container label; selecting calls back with the day.
20. `TrendLine`: y domain = series ∪ band with a 2 pt inset, a `nil` breaks the path, a lone point draws a dot, a flat series is at mid height, the pending look is a flat 1 pt line; the spoken ending ("above / within / below").
21. `ScreenHeader(title:trailing:)`: 40 high, the title leading with the header trait, the trailing slot at the inset; the trailing `SegmentedPicker` at 390 and stacked at AX1.
22. A source scan (`scripts/check-accent.sh`, part of `make lint`): no `Theme.accent`, `Theme.onAccent`, `Theme.teal`, `PrimaryButton`, `TealButtonStyle`, `SchemePair` and no `.tint(Theme.` other than `textPrimary` / `textSecondary` in `Ryft/`; fails on a planted one.
23. `Theme.band(forScore:)` returns `recovery` ≥ 67; `DeltaLabel.color`: good = the spec colour, bad = `alert`, flat = `textSecondary`; `MetricSpec.hrv` is `recovery`, `rhr`, `heartRate`, `activeKcal`, `steps` are `textPrimary`; `Theme.color(for: .info)` is `textSecondary`.

**Data and states**
24. Strain: `week` has seven days ending today; `select` clamps to the week; the band word at 9.9 / 10 / 13.9 / 14 / 17.9 / 18; the zone ticks for 10–14 = 30…42; `strainDelta` shown only with ≥ 3 priors; the split text only with a strength session.
25. Activity row meta: "07:10 · 42 min · 7.8 km", the avg-HR variant, the session variant "· Load 84.6", "–" for no strain; one view for the three item kinds.
26. Strain states: loading, no strain, no zones, no workouts, error (the calm sentence, never `localizedDescription`), offline / stale (`RefreshIssueCard`), another day (Train hidden), each by the pure decision and the identifiers (`strain.numeral`, `strain.ruler`, `strain.zones`, `strain.tile.steps` / `.energy`, `strain.activities`, `strain.row.<id>`, `strain.header.add`, `strain.day.<yyyy-MM-dd>`).
27. Workout: the numeral and ruler from `workout.strain`; zones scale 40; the stat tile list with and without a distance; the session row only with `sessionId`; no-series, no-zones and loading variants.
28. Insights tile rule: the first visible `info` insight; none with only notice / warn; notice and warn above, other `info` below; dismissing the tile promotes the next; the route link text per kind ("Show the chart", "See behaviors", "See the session").
29. Trend data: latest value, delta vs the 7 before (none under 3), `avg`, the band from the 30-day series for readiness, HRV, sleep (min), resting HR; `monthly` fetches those four; no band without a series; the HRV line / band / delta are `recovery`; readiness line `textPrimary`; the note "SDNN".
30. Trend states: loading (flat line, "–"), no data, no band, expanded (`focusedMetric` opens its card), the order (Readiness, HRV, Sleep, then the rest, no card lost: 14 in all).
31. Profile identity: initials for "Alex Doe" → "AD", "alex" → "A", "Alex" → "A", "  " → glyph, "alex@example.com" → "A", nil → glyph, "Åsa Öhman" → "ÅÖ"; the title falls back name → email → `identityDescription`; the strain arc for 12.4 / 21 ends at 212.6° from 12 o'clock; no strain → no arc and no dot.
32. Profile status: the sync word and dot kind for up to date, updating, offline, stale, action needed, demo; never teal.
33. **Row inventory:** every identifier of today's Profile (`profile.signInMethods`, `.logOut`, `.logOut.sendFirst`, `.logOut.anyway`, `.bedtime`, `.devices`, `.saveWorkouts`, `.sleepBase`, `.syncDetails`, `.notifications`, `.journal`, `.reportProblem`, `.jumpToNext`, `.sessionLayout`, `dev.catalog`, `dev.flags`) is present or deliberately mapped; the groups' visibility follows `showsTraining`, `showsNotifications`, `journal.isLive`, `bedtime.isEnabled`, `devices.isEnabled`, `canExport`, `isSignedIn`; the Display → Hero numbers row exists (PR 4 §P4-6 tests 46–47 stay green).
34. Sleep modes: the picker constants; Day's numeral top is +52 against the board; Week / Month numeral from `avgTotalMin`; the consistency `DotRow` marks (≥ 60 full, < 60 missed, nil no data, last today); the stage order (Deep, Light, REM bottom to top) and tints; Month has no row labels; "Average · 4 nights" below the range.
35. `Fmt.clockParts`: "10:06 PM" (U+202F) → ("10:06", "PM"), the same with U+00A0 and a plain space, "22:06" → ("22:06", nil), "" → ("", nil); a 24-hour locale; the numeral renders dots (not the Light fallback) for the digits.
36. Bedtime: the numeral from the first option, the ruler zone 90–100 % of the need, the three rows with the goal's marker, the no-schedule / planning / failed / alarm states, the settings card rows.
37. Day's lower cards: `SleepNeedBar` and `StageRow` use no stage-blue and no `metricStrain`; the stage tokens have no callers (a grep test).

**Tab bar, accessibility, hosted**
38. The bar in a `TabView` with a 34 pt inset: 78 high; a tab's content ends at the bar's top (the last element's frame ≤ the bar's minY); the keyboard hides it; a tab keeps its `@State` across selection changes.
39. VoiceOver order and labels per §P5-3.8, §P5-5, §P5-6.4, §P5-7.5 (hosted): header traits, one element per tile, ruler, chart, row, the buttons labelled, the disabled ones hinted.
40. AX3 (hosted): nothing clipped (frames inside the width) on Strain, the Workout, Insights, Profile, Sleep Week / Month / Bedtime; the zone block stacked at 177 pt; the picker is the menu; the tab bar's labels capped.
41. Strings: the catalog has every key of §P5-10 with a comment and none of the removed ones; `make lint` strings green.
42. `reselect` bumps only that tab's stack id; re-tapping Strain with a pushed workout returns to the root (UI).
43. Reduce Motion: no needle move, no selection slide, no card-expansion animation; Reduce Transparency: the new glow kinds flat with a 2 pt border.
44. Regression: Welcome and the live workout at AX3 (L30) with the new pills; the launch test; the Today and Sleep PR 4 tests that pin `SegmentedPicker`'s height (52) are re-pinned to 40 and listed.
45. `Fixture decode`: nothing in `Models.swift` changes (R-N3 … R-N5 are not decoded).
46. Previews exist for every row of §P5-11 (a hosted smoke that instantiates them is optional).
47–51. **UI (`UISmoke`)**: each tab via `app.tab(...)`; Strain: pick the previous day, the numeral changes, the plus opens the sheet, a row opens the workout and back; Insights: 7 D, 90 D, the tile's dismiss, a card expands; Profile: the groups exist, Log out shows the dialog, the Hero numbers row; Sleep: Week, Month and Bedtime each show their numeral and the picker keeps the selection.
52. The five tabs open under `-RyftTab <name>` (the launch argument contract).

### P5-13. Files, the split into tickets, and the draft renders

**Order.** T5.0 (shared parts) first; T5.1 (tab bar) can run beside it; then T5.2–T5.5 and the three sweeps in parallel worktrees on disjoint file sets; strings, docs and tests after; the gate last.

| Ticket | Owner | Files (owned: no other ticket edits them) | Depends on | Parallel-safe with |
|---|---|---|---|---|
| **T5.0 Foundation** | ios-developer | New `Design/RyftToggleStyle.swift`, `IconDisc.swift`, `InlineLink.swift` (`ryftLink`), `ZoneBlock.swift`, `DayStrip.swift`, `TrendLine.swift`; changed `Design/PillButton.swift`, `SegmentedPicker.swift`, `ScreenHeader.swift` (`init(title:trailing:)`), `GlowTile.swift` (`.zones`, `.idea`, flat above 420, `paddedRectContrast`), `TickRow.swift` (`arrangement`), `DeltaLabel.swift`, `MetricSpec.swift`, `Theme.swift` (`band`, `color(for severity)`; `accent` stays until T5.9), the **Design sweep** of `accent-map.md` (`Card`, `EffortScale`, `ImportProgressBar`, `InsightCard` colours only, `RangeBar`, `ScoreRing`, `StepRule`, `UndoToast`, `StatusViews.swift` except `ScreenScaffold`, `CoachMarks`), `App/Formatting.swift` (`Fmt.clockParts`), `Preview/MockData.swift` (+ `MockActivities.swift`), `Preview/PreviewSupport.swift` (tint), `DebugComponentCatalog.swift` (§P5-11 entries; **the only ticket that edits it**), tests 6, 7, 13–21, 23, 35, `check-accent.sh` as a script (wired in T5.9) | — | T5.1; T5.5's reading of the spec |
| **T5.1 Tab bar** | ios-developer | `Design/RyftTabBar.swift` (exists; tests, finish), `App/RyftApp.swift` (`RootView.tabView`, the app `.tint`, `AppTab.title`), `App/AppState.swift` (`tabStackIDs`, `reselect`), `Design/StatusViews.swift` → **`ScreenScaffold` only** (a different hunk from T5.0's sweep; rebase), `RyftUITests/Support/UITestSupport.swift` and the nine UI-test files' tab lookups (§P5-2); tests 5, 12, 38, 42, 52 | — | T5.0, T5.2–T5.5, the sweeps |
| **T5.2 Strain + Workout** | ios-developer | `Features/Strain/*` (view, view model, components, `WorkoutDetailView`), new `StrainLayout.swift`, `ActivityListRow.swift`, `Features/Train/TrainSection.swift` (all of it); **deletes** `MetricGauge.swift`, `MetricTile.swift`, `ZoneBar.swift`, `StrainPill`; tests 1, 15, 24–27 | T5.0 | T5.3, T5.4, T5.5, T5.0b-*, T5.1 |
| **T5.3 Insights** | ios-developer | `Features/Insights/*`, `Design/InsightCard.swift` (layout), `Design/TrendChart.swift` (restyle, expanded use), new `InsightsLayout.swift`, `TrendCard.swift`, `InsightTile.swift`; tests 2, 28–30 | T5.0 | T5.2, T5.4, T5.5, T5.0b-*, T5.1 |
| **T5.4 Profile (main list)** | ios-developer | `Features/Profile/ProfileView.swift` (**the whole file, including the `PrimaryButton` swaps inside the subpages' code**), `ProfileViewModel.swift` (identity, status), new `ProfileLayout.swift`, `ProfileIdentity.swift`, `ProfileRows.swift`; tests 3, 31–33 | T5.0 | T5.2, T5.3, T5.5, T5.0b-*, T5.1 |
| **T5.5 Sleep modes** | ios-developer | `Features/Sleep/SleepView.swift`, `SleepPlannerView.swift` (the planner section and `TonightCard`; the editor's code is PR 6), `SleepViewModel.swift`, new `SleepRangeSection.swift`, `SleepBedtimeSection.swift`, `SleepModesLayout.swift`; `Design/SleepNeedBar.swift`, `StageRow.swift`, `BedtimeStrip.swift` (no row labels for 30 nights); tests 4, 34, 36, 37 | T5.0 (`SegmentedPicker`, `DayStrip` not needed) | T5.2, T5.3, T5.4, T5.0b-*, T5.1 |
| **T5.0b-1 Sweep A** | ios-developer | `Features/Auth/*`, `Features/Onboarding/*`, `Push/*`, `Features/Journal/*`, `Features/Activities/*`, `Features/MyDay/*`: the `accent-map.md` rows and the `PrimaryButton` sites of those files; their light previews | T5.0 | all but T5.0b-1 |
| **T5.0b-2 Sweep B** | ios-developer | `Features/Train/**` (incl. `Import/*`, `ImportPrimaryButton`, `TrainComponents.swift` with `TrainLinkRow` and `WorkoutInProgressBanner` as §P5-3.5), **not** `TrainSection.swift`; the AX3 tests of the live workout stay green | T5.0 | all but T5.0b-2 |
| **T5.0b-3 Sweep C** | ios-developer | `Features/Today/*` (the `TealButtonStyle` sites, `TodayView.swift`), `Features/Profile/NotificationSettingsView.swift`, `FeatureFlagsDebugView.swift`, `LicensesView.swift`, `DataExport.swift` | T5.0 | all but T5.0b-3 |
| **T5.6 Strings** | localization-editor | `Resources/Localizable.xcstrings` (targeted edits, `--stat`) | T5.2–T5.5 | T5.7 |
| **T5.7 Docs and requests** | api-contract-keeper | `docs/API_REQUESTS.md` (R-N3 … R-N5, §P5-9), `CHANGELOG.md`, `docs/STATUS.md` | — | everything |
| **T5.8 Tests** | test-engineer | the files and cases of §P5-12 not written by the owning ticket; the mutation checks; the UI tests 47–51 | each screen ticket | the next screen's |
| **T5.9 Gate** | ios-developer | Deletes `PrimaryButton`, `TealButtonStyle`, `Theme.accent`, `onAccent`, `teal`, `Theme.zones`, `StageDeep/Light/REM/Awake`, `SchemePair`; wires `check-accent.sh` into `make lint`; removes the leftover light previews (`accent-map.md`, D3) and the 74 `-light` screenshots; re-shoots `make screenshots`; zero warnings, Unit, UISmoke, `make lint`, `make style` green | all | — |

Shared files and their owners: **the catalog** (`Localizable.xcstrings`) T5.6; **`MockData`** T5.0; **`GlowTileSpec`** T5.0; **`Theme.swift`** T5.0 (additions and changes) then T5.9 (deletions); **the tab bar host** (`RyftApp.swift`, `AppState.swift`, `ScreenScaffold`) T5.1;
**`DebugComponentCatalog.swift`** T5.0; **`ProfileView.swift`** T5.4 alone; **`TrainSection.swift`** T5.2 alone; **`Train/**` otherwise** T5.0b-2. A sweep ticket that finds a line in a file it does not own sends it to the owner. Not touched in PR 5: `OrbitGauge`, `RyftMark`, `LaunchStage`, the model, sync, API, `Models.swift`.

**Draft renders** (L28; the lead shows them to the user before the screens are built). Dark, English, demo data, composed from the real components on the iPhone 16e simulator (390 × 844, iOS 27.2), no real data (the demo user was renamed to "Alex Doe" for the renders). They are scratch code
(a debug-only view file and launch arguments, **not committed**); the one committed piece is `Design/RyftTabBar.swift`, the real component. Where a draft stands in for a component that does not exist yet it says so: the zone rows in the Workout draft emulate the aligned label column of §P5-3.4; the Sleep draft's picker is the restyle of §P5-7.1.

| File (scratchpad `pr5-drafts/`) | Shows |
|---|---|
| `draft-workout-top.png`, `draft-workout-bottom.png` | Workout detail: header, numeral, ruler, zones tile, stat tiles; the session row, the heart-rate card (ink line), the source |
| `draft-sleep-week-top.png`, `-bottom.png` | Sleep → Week: numeral, bed-and-wake glow tile, Quality and Consistency tiles; stage card (100 / 80 / 62 % violet), the nights list |
| `draft-sleep-month-top.png`, `-bottom.png` | Sleep → Month: the same at 30 nights (no row labels, thinner bars) |
| `draft-sleep-bedtime.png` | Sleep → Bedtime (one screen): the bedtime numeral with its meridiem, planned-sleep ruler, the go-to-bed tile, Need and Time in bed, the settings card |
| `tab-bar-today.png` (402 × 874), `tab-bar-today-390.png` (390 × 844) | The dot tab bar on Today at the scroll top: the strain tile and its ruler clear of the bar |

Known in the drafts: `BedtimeStrip`'s row labels sit half a row off their bars and show one night too few labels for eight bars (the existing chart; T5.5 checks the data and the alignment before the labels are relied on). Not drawn (the board or an existing screen covers them): Strain, Insights, Profile (their boards), the Insights expanded card, the day strip, the Profile groups beyond the board's look. If the lead wants any of these drawn for approval, they are cheap to add.

### P5-14. Deviations

| # | Board / brief | Spec | Why |
|---|---|---|---|
| D5-1 | Pill buttons 52; the app's `PrimaryButton` 44 | Every button row is 52 pt (+8) | L27: one button, the board's size |
| D5-2 | Strain has no day selection | A 44 pt `DayStrip` under the header (+56 against the board) | Today's week strip is the only way to see an earlier day; Sleep has the same kind of step |
| D5-3 | Tab bar 76 | 78 on a phone with an indicator (content 44, not 42) | An item must be a 44 pt target on a phone without an indicator |
| D5-4 | No delta on Strain | "▲ +1.2 vs 7 d" after the caption with 3 or more prior days | `strainDelta` exists today; the numbers-first rule keeps the baseline |
| D5-5 | Insights header has no disclaimer | The wellness sentence is the page's last line | Guideline 1.4.1 content stays on the screen; the header has no room |
| D5-6 | Tile "An idea" | "Insight", only for `info` insights; notice and warn are neutral cards above | The rules produce observations; teal is not a warning's colour (R-N4) |
| D5-7 | Glow text at 0.78 / 0.62 / 0.55 | Full `textPrimary` and the label rule (78 %, 100 % in recovery) | 4.5:1 in the core: the board's 62 % is 4.09 (zones) and 3.47 (idea) |
| D5-8 | Trend card without a chevron | A chevron; the card opens in place to the detailed chart | The detailed chart and Avg · Min · Max exist today and must stay reachable (the "Show the chart" link) |
| D5-9 | HRV card in strain blue, "Morning, RMSSD" | `recovery` teal; note "SDNN" | The rings are the legend; the platform delivers SDNN |
| D5-10 | Sleep has no picker (PR 4, L20) | A 40 pt restyled picker; Day is +52 against the board | The picker is 12 pt shorter than PR 4's (+64) |
| D5-11 | Profile status dot in recovery teal | `textPrimary` filled dot (up to date), hollow, `warning`, `alert` | L27: teal is recovery only; the word carries the state |
| D5-12 | Three groups; "Behaviors to track" | Seven groups of the app's real rows; "Journal" | The board gives the look; no other brand's words |
| D5-13 | Zone labels in a 74 pt column | The column is the widest label (76 pt for "Z4 · Threshold"), else all rows stack | One tick column; 317 of 318 pt at 390 |
| D5-14 | Zone rows 0.62 labels | 78 % labels | D5-7 |
| D5-15 | Tab dot 30 %, label 50 % | The dot 30 % (decoration, 2.45), the label `textTertiary` 48 % (4.54) | PR 1 D-a |
| D5-16 | Selected label full ink | Also Medium | Volt and brightness are not the only cue |
| D5-17 | "82 min" in the zones tile head | "82 min · TRIMP 112" | TRIMP is on the screen today |
| D5-18 | "in today's target" | "of 21 · moderate" | R-N1 is unfiled: no target exists, so never "target" |
| D5-19 | Three trend cards | Fourteen: the board's three first, "More trends" after | Every metric and deep link exists today |
| D5-20 | Glow tile at any height | The `.idea` tile is flat `surface` + a 2 pt border above 420 pt | 4.81:1 at 420; the corners fail beyond |
| D5-21 | Ruler label "target 10–14" | "moderate 10–14" | R-N1 |
| D5-22 | Strain activity rows without a chevron | Same (board); the hint carries the link | — |
| D5-23 | Profile Privacy Policy twice | Once, in About | The duplicate is dropped |
| D5-24 | §P5-3.5: the Train links in one grouped card | Separate `ActivityListRow`s with a chevron, 12 apart (T5.2) | b-23 draws them so; one row look for the page's lists |
| D5-25 | F7: a `DayStrip`, ids `strain.day.*` | The shared `DateStrip` (My Day's), ids `datestrip.day.<yyyy-MM-dd>` (T5.2) | One strip in the app, the same 44 pt cells |
| D5-26 | The strip is the only way to another day; no date on the page | A tap stays in the strip's week; a deep link opens any past day (older than the strip: no cell selected). On another day than today a date line ("Mon 16 Nov", 13 Regular `textSecondary`) sits 2 under the header; today has none, as the draft. The header's title speaks the day ("Strain, Yesterday"), and a deep link's day is announced once it has loaded (T5.2 review) | Push and widget links name days older than a week; the shown day must be named |
| D5-27 | "52 min" | Under an hour "42 min"; from an hour "1:05 h" (T5.2) | The tile's value stays one short line |
| D5-28 | The chart's y ticks 120 / 150 / 180 | Three ticks a round step apart covering the curve: 120 / 150 / 180 for the draft's series, 120 / 140 / 160 for the demo's (T5.2) | The scale follows the data |
| D5-29 | Zones head and row meta at 0.55 | The glow-label ink (78 %) or `textTertiary` (T5.2) | No 0.55 token; 0.55 fails 4.5:1 in the glow tile (D5-7) |
| D5-30 | The heart-rate chart at one size | From AX1: 200 pt tall, every other clock tick, "peak 159" in the card's head instead of over its dot (T5.2) | At AX3 the clock labels collide and the peak note overlaps the head |
| D5-31 | The HRV note "Morning, RMSSD" | "SDNN" (T5.3) | The HRV RYFT reads from Apple Health is SDNN |
| D5-32 | A change on every trend card in the metric's colour | Grey for metrics with no good direction: naps, active energy, strain (T5.3) | Inventing a direction would turn less activity red |
| D5-33 | A 30-day min–max band | The usual range: mean ± 1 SD of the 30-day values before the newest, from 7 of them; below that "Band needs 7 days of data". The expanded chart draws it at TrendChart's 10 % (T5.3 review) | Min–max with the newest inside filled the chart box and could never read above or below |
| D5-34 | "vs 7 d" from each range's own series | Today's rule (`MetricDelta.vsSevenDayMean`) over the 7 days ending on the newest value, the same in every range; duration changes keep `DeltaLabel`'s "+17m" style, not the board's "0:17" (T5.3 review, lead) | Insights, Today and Sleep agree on one number and one format |
| D5-35 | Range control always shown; no stale note | "Not set up" hides the range control; a failed refresh shows "As of <MMM d>"; nothing loaded and nothing in flight shows "Not loaded" (T5.3) | Nothing to range over; never claim "no data" for a read that didn't happen |

### Questions for the lead

1. **Draft renders (L28).** Please show the user `pr5-drafts/draft-workout-*`, `draft-sleep-week-*`, `-month-*`, `draft-sleep-bedtime.png`: approve or what to change?
2. **Tab bar.** A custom flat bar (the board's) instead of the system bar, whose glass capsule cannot be flattened on iOS 26+ (tried on 27.2). Re-tap (scroll to top, pop to root) is reimplemented. OK?
3. **"Behaviors to track".** The app already has it as the Journal subpage's title; the Profile row says "Journal". Rename the subpage too (PR 6), or keep the app's own word?
4. **"An idea".** The Insights tile says "Insight" and only carries `info` insights (D5-6); R-N4 would let the platform mark real suggestions. OK, or file R-N4 as required?
5. **HRV colour.** Teal (recovery) against the board's blue (D5-9). Confirm.
6. **Sleep Week and Month** lose the old header's red delta ("▼ −12m · −2 %"). Keep a `metricSleep` "vs 7 d" delta in the caption instead?
7. **The demo user** in `MockData` is the owner's real first name ("Tim", `tim@example.com`, "Tim's Apple Watch") in a public repo. Change it to "Alex Doe" (T5.0)?
8. **Strain's day strip** (D5-2) and the Insights disclaimer at the bottom (D5-5): both OK against the board?
