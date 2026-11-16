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
}

struct DotNumeral: View {
    enum Style { case dots, light }
    static let dot: CGFloat = 5, dotGap: CGFloat = 2, height: CGFloat = 47      // 7·5 + 6·2
    static let glyphGapToday: CGFloat = 8, glyphGapDetail: CGFloat = 7          // Today / Sleep, Strain
    static let offOpacity = 0.10, lightSize: CGFloat = 52
    static func size(of text: String?, placeholderGlyphs: Int = 2, glyphGap: CGFloat) -> CGSize?   // nil = not in the table
    static func rendersDots(_ text: String?, style: Style, typeSize: DynamicTypeSize) -> Bool
    init(_ text: String?, style: Style = .dots, glyphGap: CGFloat = DotNumeral.glyphGapToday,
         placeholderGlyphs: Int = 2, accessibilityLabel: Text)
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
| Pending | `text == nil` | `placeholderGlyphs` blank cells, every dot at 10 %, same size as digits; in the Light fallback `–` repeated `placeholderGlyphs` times at `textTertiary`. The caller's label says "no value yet" |

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
         zoneTint: Color = Theme.textPrimary, zoneOpacity: Double? = nil, tickCount: Int,
         labels: [String] = [], size: Size = .regular,
         accessibilityLabel: Text, accessibilityValue: Text, reduceMotion: Bool? = nil)

    static func tickCentres(count: Int, width: CGFloat) -> [CGFloat]
    static func zoneTickIndices(count: Int, range: ClosedRange<Double>, zone: ClosedRange<Double>?) -> [Int]
    static func needleX(value: Double?, range: ClosedRange<Double>, width: CGFloat) -> CGFloat?
}
```

`zoneOpacity: nil` means 0.55 regular, 0.60 compact; callers pass 0.85 (Sleep, `metricSleep`) and 0.95 (Strain, `metricStrain`).
Width is whatever is proposed (the ruler fills it); height is fixed per size.

**Geometry** (y from the top of the ruler; ticks and needle are fixed-size graphics, never scaled):

| | Regular | Compact (strain tile) |
|---|---|---|
| Ruler height | 36 = 8 top + 22 tick row + 6 bottom | 32 = 8 + 18 + 6 (**derived**, not measured) |
| Tick row | y 8…30, ticks centred vertically | y 8…26 |
| Outside the zone | 1 × 8, `textPrimary` 22 % (compact: 1 × 7, 26 %) | |
| Inside the zone | 1.5 × 14, `zoneTint` at `zoneOpacity` (compact: 1.5 × 12, 60 %) | |
| Needle | triangle 12 × 8 pointing down, apex y 8; line 1.5 × 20, y 8…28; `Theme.signal` | line 16 (y 8…24); triangle as regular (**derived**) |
| Labels | under the ruler, `Font.ryft(.axis)` (11), `textTertiary` | same |

- **Ticks.** `n = max(tickCount, 2)`. Tick `i` is centred at `x_i = i / (n − 1) × width`; its rect is `x_i − w/2`. The outer ticks
  overhang by ≤ 0.75 pt, so the view must not clip. Drawing snaps the rect's x to the device pixel; `tickCentres` returns the unsnapped values.
- **Value of tick `i`:** `lo + Double(i) · (hi − lo) / Double(n − 1)` (multiply first: 30·21/63 = 10 exactly). Tick counts are chosen so zone
  edges land on ticks.
- **Zone ticks:** `v_i` in `zone` ± 1e-9. Today (0…100, 67…100) → indices 41…60 (20 ticks). Sleep (0…10, 7.5…8.3) → 45…49 (5). Strain
  (0…21, 10…14) → 30…42 (13). Compact strain (43 ticks) → 20…28 (9). `zone == nil` → none.
- **Needle x:** `clamp((value − lo) / (hi − lo), 0, 1) · width`; `nil` for `value == nil`, NaN or `hi ≤ lo`. The needle's centre is clamped, its
  triangle may overhang 6 pt (padding of the parent contains it).
- **Labels:** `[String]` in one line, distributed edge to edge (first leading, last trailing, the rest evenly spaced), the board's
  "0 · low · moderate · high · 100". Placement under the zones is **not measured**; space-between is assumed. If they do not fit on one
  line (AX), `ViewThatFits` falls back to the strings joined by " · ", wrapping, leading-aligned.

**States.** Value (needle + zone); **no value** (`value == nil`): ticks, zone and labels stay, no needle, the caller's value text says "no value yet";
**no zone**: all ticks outside; **clamped**: a value outside the range sits on the end, and the caller's value text keeps the real number.
State is never colour alone: the needle's position, the zone's longer and thicker ticks, the band word in `labels` and the sentence.

**Motion.** Only the needle moves: `.animation(Theme.Motion.respecting(reduceMotion ?? system, .quick), value: value)` on its x (250 ms
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
extension View { func ryftGlowLabelStyle() -> some View }       // Font.ryft(.label), textPrimary at 78 %
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
| **TickRow** | One zone row: `label` (74 wide, leading, `Font.ryft(.caption)`, `textSecondary` = 62 %) · 30 ticks of 3 × 12, radius 1.5, gap 3 (177 wide) · `value` (40 wide, trailing, `.caption`, `textPrimary`); columns `Theme.Metrics.itemSpacing` (12) apart, so 315 pt; value pushed to the trailing edge. Row height 12 (ticks); text may overhang. Five rows are the caller's `VStack(spacing: TickRow.rowSpacing)` (9) | Lit = first `litCount` ticks in `textPrimary`, rest 12 %. `litCount = clamp(Int((minutes·30 / scaleMax).rounded()), 0…30)`; `nil`, negative, NaN or `scaleMax ≤ 0` → 0 (the caller's `value` says "–" or "no data"). All five rows share one `scaleMax` | Label/value widths and row height are `@ScaledMetric(relativeTo: .caption)`. If the row no longer fits, `ViewThatFits` stacks: label · spacer · value above, ticks (177 fixed) below (always at AX1+) | one element per row, `.ignore`, the caller's label ("Zone 3, 24 minutes"). The caller groups the five with `.contain` |
| **CircleButton** | 40 circle, no fill, `strokeBorder` 1 pt `textPrimary` 16 %; `Image(systemName:)` 14 pt, `.regular` (≈ 1.3 pt stroke), `textPrimary`. **Layout box 44 × 44** (the circle centred, 2 pt transparent each side, `contentShape(Rectangle())`) | normal; pressed: circle filled `textPrimary` 8 %, no scale, no animation; disabled (`isEnabled` false): icon `textPrimary` 35 %, border unchanged | fixed (icon-only) | `Button` trait, the caller's label (required: there is no text); disabled is exposed by SwiftUI as not enabled |
| **PillButton** | `Capsule`, height ≥ 52 (`minHeight`), full proposed width. **Primary:** fill `textPrimary`; leading 20, trailing 6; title `Font.ryft(.button)` in `Theme.background`, leading-aligned; trailing 40 pt `Theme.background` circle with the icon (14 pt, `textPrimary`). **Secondary:** fill none, `strokeBorder` 1 pt `textPrimary` 20 %; padding 22 horizontal; title `Font.ryft(.button)`, `textPrimary`, centred; no icon | normal; pressed: primary fill at 85 %, secondary filled `textPrimary` 8 %, no animation; disabled: whole pill at 35 % opacity. No busy state: the caller disables and changes the title | title scales (`.button` is relative to `.body`), no line limit, vertical padding 12 so it grows past 52 and wraps at AX3 without clipping; the 40 circle stays 40 and is vertically centred | the title is the label, the icon `accessibilityHidden`, `Button` trait; the whole pill is the target (≥ 52 high) |

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
   `"0"` 33×47; `":"` 5×47; `nil` with 2 placeholders 74×47; a string outside the table → `nil`.
5. **AX1 fallback:** `rendersDots("84", .dots, .xxxLarge)` true; `.accessibility1`, `.accessibility3` false; `.light` false at `.large`;
   `"7h"` false at `.large`; `nil` + `.dots` + `.large` true.
6. `tickCentres(count: 61, width: 300)` = `i·5`, first 0, last 300; `count: 64, width: 630` = `i·10`; `count: 2` = `[0, w]`; `count: 1` and `0` behave as 2.
7. **Needle x** (range 0…100, width 300): 84 → 252; 0 → 0; 100 → 300; 150 → 300 (clamped); −10 → 0; `nil` → `nil`; NaN → `nil`.
   Range 0…21: 10.5 → 150; range 0…10: 7.5 → 225; `5...5` (hi ≤ lo) → `nil`.
8. **Zone ticks:** Today `zoneTickIndices(61, 0...100, 67...100)` = 41…60 (count 20; index 40 is out); Sleep `(61, 0...10, 7.5...8.3)` = 45…49 (5);
   Strain `(64, 0...21, 10...14)` = 30…42 (13); compact `(43, 0...21, 10...14)` = 20…28 (9); `zone: nil` → `[]`.
9. Ruler size: `.regular` renders 36 high, `.compact` 32; needle colour is `Theme.signal`; the default `zoneOpacity` is 0.55 regular, 0.60 compact.
10. **TickRow `litCount`:** (0, 60) 0; (1, 60) 1 (0.5 rounds up); (7, 60) 4 (3.5); (24, 60) 12; (60, 60) 30; (90, 60) 30; (−5, 60) 0; (10, 0) 0; (nil, 60) 0.
11. `DotRow.size`: 7 → 66×6, 1 → 6×6, 0 → `.zero`.
12. **Form tokens:** `Theme.Metrics` has `neutralTileRadius` 22, `glowTileRadius` 24, `heroTileRadius` 28, `circleButton` 40, `minHitTarget` 44, `pillHeight` 52,
    `itemSpacing` 12; the old `cardRadius` 18, `tileRadius` 16, `screenPadding` 20 are unchanged; `GlowTileSpec.Radius.tile.points` 24, `.hero` 28.
13. **Gradient pinned:** `GlowTileSpec.stops` are `Theme.background` at alpha 0.97/0.92/0.55/0.10 and locations 0/0.34/0.68/1; `overlayOpacity`: 0 → 0.97,
    0.34 → 0.92, 0.5 → 0.7459 (±0.001), 0.68 → 0.55, 1 → 0.10, 2 → 0.10; `ellipse` = (0.90, 1.10, 0.55); padding 14/16/14/16.
14. Button constants: `CircleButton.diameter` 40, `hitSize` 44, `borderOpacity` 0.16; `PillButton.minHeight` 52, `iconCircle` 40; `TickRow` ticks 3×12, gap 3, 30 ticks,
    `rowSpacing` 9, widths 74/40; `DotRow` 6/4.
15. `ryftGlowLabelStyle` uses `GlowTileSpec.labelOpacity` 0.78 (the constant is 0.78).
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

`screenPadding` 20 already exists. The pill radius is `Capsule()` (26 at 52 pt). Per-component measurements (dot 5, gap 2, tick 3 × 12, …) stay
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
| P2-D5 | `textTertiary` 45 % on the boards | 48 % (PR 1's token) | Already D-a; the ruler labels use it. |

None of these contradicts the brief. Derived, not measured (the boards give no number; ios-developer must not tune them without asking): compact ruler height
32 and row 18; compact needle triangle = regular; glow-tile bottom padding 14; ticks vertically centred in their row; ruler labels space-between; TickRow column gap 12;
primary pill text leading-aligned and secondary centred; pill icon 14 pt (the circle's); `today` as a filled dot; the `,` glyph; the plain `0`.
