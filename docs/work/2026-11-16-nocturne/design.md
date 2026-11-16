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
| D-f | §2 "numbers Light" | `ryftNumber(size:)` without a weight: Light from 20 pt, Regular below (`RyftFonts.lightFloor`) | Light strokes under 20 pt on `#0A0C0B` are about one device pixel: the 9–19 pt scale labels and set inputs stay Regular. Callers that pass a weight keep it. |
| D-g | §2 "Label 13 (`textSecondary`)" and "keine Versal-Labels" | `.label` is 13 Regular, sentence case, no tracking; `ryftLabelStyle` loses `.textCase(.uppercase)` and `.tracking(2)`; MetricGauge's centre title (was 9 pt uppercase tracked) is 11 pt sentence case | 9 pt is under the scale's 11. The BrandLockup tagline lost its `.tracking(4)`. |
| D-h | §1 Wordmark "Laufweite 0.32 em" | 0.32 em, and the trailing tracking is pulled back with a negative trailing padding | CSS letter-spacing adds space after the last letter; without the pull-back a centred wordmark sits 0.32 em left of centre. The icon uses the same rule (ink centred). |
| D-i | Icon "Dark/Tinted identical" | Three PNGs, byte-identical | The appiconset keeps its three slots so Xcode needs no change. |

Not deviations, recorded so ADR 0016 has them: `Theme.Metrics` radii and padding are untouched (PR 2). The
two `.textCase(.uppercase)` in `Features/Train/Session/ExercisePage.swift` (lines ~436, 504) are in a file owned by T1.2.

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
left 209.0 / right 209.0 / top 412.9 / bottom 412.9 px; the renderer fails if either pair differs by more than 1 px. The word is
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
composite the track over a ground:

| Test | Change | Reason |
|---|---|---|
| `OrbitGaugeContrastTests`, `OrbitGaugeBandTests` | Dark only; the light-only expectation (Sleep/Strain at 0.6 under 3:1) is removed | There is no light scheme. Thresholds unchanged (3:1, 4.5:1). The 16 % track pixel is `#2F312F`: recovery, sleep, strain 7.12, 4.55, 3.97 on it. |
| `OrbitGaugeRenderTests`, `OrbitGaugeBandRenderTests`, `OrbitGaugeShotsTests`, `OrbitGaugeEntranceTests`, `OrbitEntranceTimelineTests` | Scheme loops dark only | There is no second appearance; the "light" shots were the same colours. Pixel expectations unchanged. |

`NocturneTokenTests` pins `surfaceRaised` as `over(rgba(ink, 0.16), rgba(0x0A0C0B))` and has a contract row: `textPrimary` and
`textSecondary` ≥ 4.5:1 on it (and `textTertiary` under 4.5 and over 3, the reason for the rule).

Not changed: the `Light:` tests in `FocusedPolishTests`, and the screenshot tests that render a light variant (`FocusedSessionShotsTests`,
`HostedAccessibility`, `ImportScreenshotTests`, `FocusedPolishHostedTests`). They pass (light now resolves to the same dark tokens);
removing the light branches is T1.2's and PR 5's.

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

The widget on a device in system-light mode (forced `.dark` in code, not seen). Satoshi Light on screen needs the font files:
previews and tests fall back to SF Pro Rounded Light when they are absent (CI). The App Store's icon mask and the tinted icon on the
Home Screen were not seen.
