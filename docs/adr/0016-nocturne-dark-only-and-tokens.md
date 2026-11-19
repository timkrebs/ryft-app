# 0016 — Nocturne: dark-only, one value per token, the wordmark icon

- Status: accepted (2026-11-16, Nocturne PR 1 `design: nocturne tokens, type and icon`; `docs/work/2026-11-16-nocturne/brief.md`
  §1, §2, §6, `plan.md` D1–D7, `design.md` §PR 1)
- Deciders: Tim Krebs (NOCTURNE_STYLE v0.2, approved 2026-11-16); ios-lead (D1–D7), on ui-designer's token table; recorded by
  ios-architect
- Applies to: every colour set in `Ryft/Assets.xcassets` and `RyftWidgets/Assets.xcassets`, `Ryft/Design/Theme.swift`,
  `Ryft/Design/Typography.swift`, `Ryft/Design/RyftHeader.swift` (`Wordmark`, `WordmarkLockup`), `Shared/OrbitGaugePalette.swift`,
  `RyftWidgets/RyftWidgets.swift` (`Brand`), `RyftWidgets/ReadinessWidget.swift`, `Ryft/Info.plist` (`UIUserInterfaceStyle`,
  `UIAppFonts`), `Ryft/App/RyftApp.swift`, `Ryft/App/Settings.swift`, `Ryft/Features/Profile/ProfileView.swift` (the appearance
  picker, the report form's prompt), `Ryft/Features/Strain/StrainComponents.swift` (the strain pill's placeholder),
  `Ryft/Features/Profile/LicensesView.swift`, `scripts/render-icon.swift`, `scripts/icon-spec.swift`, `scripts/mark-svg.swift`,
  `scripts/fetch-fonts.sh`, `Makefile`, `CLAUDE.md` (the preview rule), `RyftTests/NocturneTokenTests.swift`

## Context

- **The style is approved.** NOCTURNE_STYLE v0.2 (`brief.md`) decides in §1:
  - the app is dark-only;
  - the rings are the legend: one colour per metric, everywhere;
  - Volt is the signal and never text;
  - Satoshi Light for titles and numbers, sentence-case labels;
  - the app icon is M1, the wordmark.

  §2 gives the tokens. It says the metric colours are "today's ring colours, slightly desaturated", to be checked against the
  assets and changed only where contrast or consistency asks for it, with an ADR. This is that ADR.
- **Before PR 1**, every colour set had a light and a dark value.
  - Profile → Appearance offered Dark (the default), Light and System, and the `-appearance` launch argument set it.
  - The widget's `Brand` had a light branch.
  - Every preview came in pairs.
  - The icon was the orbit mark, rendered from `RyftMarkGeometry`, with SVG twins in `design/`.
- **PR 1 is tokens, type and icon only.** The components come in PR 2, the gauge in PR 3 and the screens in PRs 4 and 5
  (`brief.md` §7).
- **The widget shares colour sets by name.** `Shared/OrbitGaugePalette.swift` names `TextPrimary`, `Signal`, `Recovery`,
  `MetricSleep`, `MetricStrain` and `Alert`. `scripts/check-shared-types.py` fails unless each of them is in both catalogs
  with the same `Contents.json` (ADR 0010).

## Decision

### 1. Dark-only, for the app and the widget

- **It is enforced in three places:**
  - `Ryft/Info.plist` sets `UIUserInterfaceStyle` = `Dark`. That covers what SwiftUI does not draw: the launch screen, alerts and
    UIKit chrome.
  - The app root's `.preferredColorScheme(settings.appearance.colorScheme)` becomes `.preferredColorScheme(.dark)`.
  - The Readiness widget's content gets `.environment(\.colorScheme, .dark)`. `Brand` loses `ink(_:)` and `background(_:)` and
    keeps one `ink` and one `background`. The Live Activities and the control have no appearance branch.
- **A colour set has one value.** Every `Contents.json` has a single `universal` entry with no `appearances`, so a light trait
  resolves to the same colour (`NocturneTokenTests.noTokenDependsOnTheAppearance`). The plist makes the system's components dark.
  The single value keeps our own colours right if a light trait reaches a view anyway.
- **What users lose: the Appearance setting.**
  - `Settings.Appearance`, its Profile picker and the `-appearance` launch argument are removed (T1.2, `feat/nocturne-dark-only`).
  - A stored `appearance` value is not read and not migrated. It stays in `UserDefaults`, inert.
  - The default was already Dark, so only people who chose Light or System see a change. `CHANGELOG.md` → Unreleased says so.
- **Previews are dark-only.** The lead changes the `CLAUDE.md` rule ("dark and light") in this PR (D3). Light previews go file by
  file as PRs 1–5 touch each file, and PR 5 removes the rest. `DarkPreview` (`Preview/PreviewSupport.swift`) is the
  single-appearance wrapper. `SchemePair` stays until its last caller goes.

### 2. The tokens

| §2 token | Colour set (legacy alias) | Value | Against §2 |
|---|---|---|---|
| `background` | `Background` (`Graphite`) | `#0A0C0B` | as §2 |
| `surface` | `Surface` (`Slate`) | `#121514` | as §2 |
| `textPrimary` | `TextPrimary` (`Mist`) | `#F2F1EC` | as §2 |
| `textSecondary` | `TextSecondary` | `#F2F1EC` @ 62 % | as §2 |
| `textTertiary` | `TextTertiary` | `#F2F1EC` @ **48 %** | §2 says 45 % (2.4) |
| `separator` | `Separator` | `#F2F1EC` @ 8 % | the top of §2's 6–8 % |
| `track` | `SurfaceRaised` | **`#2F312F`, opaque** (= `#F2F1EC` @ 16 % over `background`) | one token, §2 gives 7–16 % (2.4, 2.5) |
| `recovery` | `Accent` (`Teal`), `Theme.recovery` | `#63D2B4` | as §2 |
| `sleep` | `MetricSleep` | `#9B8AF0` | as §2 |
| `strain` | `MetricStrain` | `#5E8BEA` | as §2 |
| `signal` | `Signal` (new) | `#D8FF4F` | as §2 |
| `onSignal` | `OnSignal` (new) | `#0A0C0B` | as §2 |

`design.md` §PR 1 → 2 has the old → new value of every set, including those outside §2.

#### 2.1 The metric colours follow the canvas, not today's assets

| Metric (set) | Before (light / dark) | Now | On `background`, before → now |
|---|---|---|---|
| recovery (`Accent`) | `#107561` / `#3FD1B4` | `#63D2B4` | 10.27 → 10.66 |
| sleep (`MetricSleep`) | `#5B4FC9` / `#8F87F1` | `#9B8AF0` | 6.45 → 6.81 |
| strain (`MetricStrain`) | `#2E5BBF` / `#5B8DEF` | `#5E8BEA` | 6.07 → 5.94 |

- **The reason is fidelity to the approved canvas.** The screens and the icon are reviewed against it.
- **Contrast did not force it.** Today's dark values are twice the 3:1 they need, and strain's new value is slightly lower than its
  old one. The light values go with the light appearance.
- **Reverting is cheap.** It means changing three sets: six `Contents.json`, because `Shared/` names all three and both catalogs
  carry them. Their pins in `NocturneTokenTests` change with them. Nothing else depends on the hexes.

#### 2.2 Signal is for marks, never text

- `Signal` `#D8FF4F` is used only for the five marks §1 names:
  - the ruler's needle;
  - the readiness marker in the inner ring;
  - the "today" dot in dot rows;
  - the active tab's dot;
  - the hint dot on Insights.
- It is never text. At 17.13:1 it would pass, but it is a signal, and a Volt word would compete with the legend.
- The rule is in `Theme.signal`'s doc comment. No contrast test can catch a breach, so it is a review check.
- `OnSignal` `#0A0C0B` (17.13:1) is for a glyph on a filled signal dot. Both sets are in the widget catalog too, for PR 3.

#### 2.3 Accent is recovery, and the asset names stay

- **`Accent` carries the recovery teal**, and `Theme.recovery` is an alias, `Color("Accent")`.
  - There is no `MetricRecovery` set, because a second set for the same colour could drift.
  - Renaming `Accent` would touch both catalogs, `Shared/` and the checker, with nothing visible to show for it.
  - "One accent per screen" and "recovery" are the same teal, so callers of `accent` keep working. PRs 2–5 write the legend as
    `recovery`, `metricSleep`, `metricStrain`.
- **Legacy names are remapped, not removed.**
  - `Graphite`, `Mist`, `Slate` and `Teal` carry the Nocturne values of `background`, `textPrimary`, `surface` and `accent`.
  - `Sage` keeps its value, and `AccentSecondary` keeps its dark one.
  - `Warning`, `Alert`, `StageAwake` and `StageREM` take their dark values.
  - `StageLight` and `StageDeep` keep the one value they already had in both appearances.

#### 2.4 Deviations, with their numbers

- **`textTertiary` is 48 %, not §2's 45 %** (plan D7).
  - 45 % is 4.12:1 on `background` and 4.13:1 on `surface`. That is under 4.5:1 for the 11–12 pt scales and meta it is for.
  - 46 % gives 4.26, 47 % gives 4.40 and **48 % gives 4.54 on both grounds**, so 48 % is the lowest whole percent that passes.
  - Rounding the composite by 1/255 moves the ratio by about 0.04, so the margin is small. Do not go below 48 %.
  - The step from secondary (62 %) to tertiary is still deliberate, but smaller than the canvas's.
- **`separator` is 8 %.** §2 gives 6–8 %; the canvas uses 8 %.
- **The track is one token at 16 %.** §2 gives 7–16 %, and the canvas uses 16 % outer, 7 % middle and 13 % inner.
  - Until PR 3 the gauge draws one track. 16 % over `background` is 1.49:1, about the weight of the old opaque `#263137` (1.45:1 on the old `#0B0F0E`).
  - PR 3 draws all three strengths from `textPrimary.opacity(…)` where the gauge draws them.
- **Changes to sets outside §2:**
  - `OnAccent` becomes `#0A0C0B` (10.66:1 on the teal).
  - The widget's `WidgetBackground` becomes `#0A0C0B`.
  - The widget's `AccentColor` stays empty, because giving it the teal makes Xcode warn that its `accent` symbol collides with the
    `Accent` set.

#### 2.5 `SurfaceRaised` is an opaque fill, `#2F312F`

- **It has two jobs.** It has 34 references besides its definition and doc comments (33 in `Ryft/`, one in `Shared/`):
  - 7 are tracks or outlines;
  - 27 are fills behind content: chips, capsules, the selected segment, keypad and secondary buttons, fields, the undo toast, the
    scrub readout.
- **It is the 16 % track, flattened over the screen.** `#F2F1EC` @ 16 % over `#0A0C0B` is `#2F312F`.
  - A track drawn on the screen gets the same pixel as §2's track, so the gauge does not change.
  - A fill gets the same pixel on every ground.
- **Contrast on it, whatever is underneath:**

  | On `#2F312F` | Ratio | Needs |
  |---|---|---|
  | `textPrimary` | 11.60 | 4.5 |
  | `textSecondary` | 5.50 | 4.5 |
  | `textTertiary` | 3.94 | 4.5, so it fails |
  | recovery, sleep, strain arcs | 7.12, 4.55, 3.97 | 3 |
  | alert, warning arcs | 4.07, 7.58 | 3 |

  It is 1.40:1 on `surface`, still a visible step.
- **The rule: a raised fill carries `textPrimary` or `textSecondary` text, never `textTertiary`.**
  - No colour fixes this. For 48 % to reach 4.5:1, the fill would have to be under 5 % ink, which is 1.02:1 on `surface` and no
    longer raised.
  - Before PR 1 the pair was 4.40:1, already short.
  - PR 1 applies it at the two places that broke it. The strain pill's placeholder when there is no strain
    (`StrainComponents.swift`) and the report form's prompt "What happened? What did you expect?" (`ProfileView.swift`) are
    now `textSecondary`, 5.50:1.
  - `NocturneTokenTests.raisedFillsCarryPrimaryAndSecondaryText` pins it: `surfaceRaised` is opaque, `textPrimary` and
    `textSecondary` reach 4.5:1 on it, and `textTertiary` stays under 4.5:1 there but reaches 3:1, so it may still be a glyph.
  - Four places put a `textTertiary` glyph on a raised fill. Graphics need 3:1, and these get 3.94:
    - `SourceBadge` (decorative, beside the name);
    - `MyDayRow` (missing sleep);
    - `ExerciseCard.checkFill` (the List layout's unchecked set);
    - Profile's disabled circle button (exempt).
  - The List layout's empty set field (`textTertiary` at 70 % on the fill at 55 %) is faint on purpose and predates Nocturne.
- **The value is derived but stored as a literal**, because an asset catalog cannot compute. The pin keeps it derived:
  `NocturneTokenTests` pins it as `over(rgba(ink, 0.16), rgba(0x0A0C0B))`, so a change to `background` that leaves `SurfaceRaised`
  alone fails.
- **Once PR 3 draws the orbit's tracks from `textPrimary.opacity(…)`, `SurfaceRaised` is a fill.** Until their own PRs, it also stays
  the track of `ScoreRing`, `MetricGauge` and the bars (`RangeBar`, `ZoneBar`, `StageBar`).
- **What PR 1 ships:**
  - Both `SurfaceRaised.colorset/Contents.json` files (app and widget, identical) carry `0x2F 0x31 0x2F` at alpha `1.000`.
  - The token pin is the composite, and `Theme.surfaceRaised`'s doc comment says opaque.
  - No test composites the track or a fill over a ground. The gauge tests and `FocusedPolishTests` read `surfaceRaised` as it
    resolves, which is right only because the token is opaque.
  - The one guard is the alpha check in `raisedFillsCarryPrimaryAndSecondaryText`. If the set turns translucent again, that check
    fails; the other ratios would otherwise go wrong silently.

### 3. Typography

- **Satoshi Light is added in four places:**
  - `scripts/fetch-fonts.sh`;
  - `UIAppFonts` (`Satoshi-Light.otf`, PostScript name `Satoshi-Light`);
  - the archive check in the `Makefile`;
  - `LicensesView`'s Satoshi entry, which now names the four weights.

  It is the same family under the same licence as the existing entry, the ITF Free Font License (Indian Type Foundry, via
  Fontshare). There is no new licence entry and no new dependency. The files stay git-ignored.
- **CI has the fonts.** `.github/actions/setup/action.yml` runs `make fonts` for the test, CodeQL and TestFlight jobs. Only the
  Lint job has none, and lint does not need them.
- **The gap is a local or agent run without `make fonts`.** It falls back to SF Pro Rounded, and that fallback takes the system
  text style's size, not the role's (the `.system(textStyle, …)` branch of `Font.ryft` in `Typography.swift`). `metric`, for
  example, is drawn at 22 pt instead of 26. That is a follow-up, not part of this PR.
- **Weights and digits.** Titles and numbers are Light, text is Regular, and buttons and row titles are Medium. Every `Font.ryft`
  and `Font.ryftNumber` is `.monospacedDigit()`.
- **The scale moves each role only to the nearest end of its §2 range:**

  | Role | Before | Now |
  |---|---|---|
  | `callout` | 14 | 15 |
  | `metric` | 22 | 26 |
  | `numberLarge` | 40 | 34 |
  | `display` (§3's Light digits) | 56 | 52 |
  | `headline` | 18 | 17 |
  | `axis` | 10 | 11 |
  | `label` | 11 | 13 |
  | `wordmark` | 17 | 15 |

  `title` (26), `body` (16) and `caption` (12) were already in range. §2 gives the wordmark no size; 15 pt is its size in the
  lock-up (the wordmark bullet below, `design.md` §PR 1 → 6). The new roles `button` (16 Medium) and `tab` (11 Regular) have
  no callers until PRs 2 and 5.
- **One deviation: `ryftNumber(size:)` without a weight is Light from 20 pt and Regular below** (`RyftFonts.lightFloor`). A Light
  stroke under 20 pt is about one device pixel on `#0A0C0B`. Callers that pass a weight keep it.
  - The exception is `ExerciseCard`'s set inputs: the kg and reps fields and their read-only values. They pass `weight: .regular`,
    so they stay Regular at 20 pt and above too (`design.md` D-f).
- **Labels are sentence case.**
  - `ryftLabelStyle` loses `.textCase(.uppercase)` and `.tracking(2)`. `label` is 13 pt Regular in `textSecondary`.
  - MetricGauge's centre title goes from 9 pt uppercase and tracked to 11 pt sentence case.
  - The BrandLockup tagline loses its tracking.
  - The two `.textCase(.uppercase)` in `ExercisePage.swift` go with T1.2.
- **The wordmark** is "RYFT" in Satoshi Light, tracked 0.32 em, 15 pt by default.
  - The tracking after the last letter is pulled back, so a centred word really is centred.
  - `WordmarkLockup` (mark 26 pt, 10 pt gap) is one VoiceOver element, "RYFT", with the header trait.
  - Like the mark, it has a fixed size: it is a brand mark, not text.

### 4. The app icon is M1, the wordmark

- **What it shows:**
  - "RYFT" in Satoshi Light, `#F2F1EC` on `#0A0C0B` (17.35:1), tracked 0.02 em;
  - 279.3 px on the 1024 tile (the canvas's 60/220), ink centred;
  - no mark.

  Light, Dark and Tinted are byte-identical. The appiconset keeps its three slots, so Xcode needs no change.
- **How it is drawn.** `make icon` renders it with CoreText from `Ryft/Resources/Fonts/Satoshi-Light.otf` (git-ignored,
  `make fonts`).
  - It reads both colours from the asset catalog (`Background`, `TextPrimary`), so the icon cannot drift from the tokens.
  - It never falls back to another face. It exits 1 on any of these:
    - a missing or wrong font;
    - a word under 4.5:1;
    - an alpha channel;
    - ink off centre. The ink box is measured on the rendered bitmap, on all four sides, and the left and right (or top and
      bottom) margins may differ by at most 1 px.
  - It also writes 180, 120, 60 and 40 px versions into `build/icon-preview/` for review.
- **The PNGs are committed.** No CI job runs `make icon`.
- **`design/ryft-app-icon-{light,dark}.svg` are deleted and no longer generated.**
  - They have no consumer. A grep over `app/` and `plattform/` finds only docs, history and a comment in `scripts/mark-svg.swift`.
  - Generating them from the wordmark would need either glyph outlines from the git-ignored font in `make lint`, whose CI job has no
    fonts, or a committed outline that could drift from the PNGs.
- **`design/ryft-mark.svg` stays.** The mark is still the logo, in the header lock-up and the launch (§5).
  - It is still generated from `RyftMarkGeometry` and checked by `make lint` (`check-mark-svg`).
  - `mark-svg.swift` no longer includes `icon-spec.swift`.
  - The old comparison variants (`--ring-span`, `--dots`, `--mono`, `--suffix`) are gone.

## Consequences

**Good:**
- **One value per colour.** Nothing resolves by trait, every token is one pinned number, and `check-shared-types.py` compares
  single-entry files.
- **The legend is one colour per metric in both targets.** `recovery` gives PRs 2–5 the legend's names without a rename.
- **The icon follows the tokens by construction.**
- **A raised fill's contrast belongs to the token**, not to where it is drawn. Tests of raised sites need no ground.

**Costs:**
- **Light and System appearance are gone.**
- **`main` shows a mixed look from PR 1 to PR 5**: the new colours and type on the old layouts (D5). This is accepted. It is the
  brief's order, and the nightly has been red since 2026-11-05 (signing), so no tester build carries it until that is fixed.
- **The gauge tests are re-pinned to dark-only.**
  - `OrbitGaugeContrastTests`, `OrbitGaugeBandTests`, `OrbitGaugeRenderTests`, `OrbitGaugeBandRenderTests`, `OrbitGaugeShotsTests`,
    `OrbitGaugeEntranceTests` and `OrbitEntranceTimelineTests` loop over dark only.
  - They read the track as it resolves. Nothing composites it, because the token is opaque (2.5).
  - The light-only expectation is removed (Sleep and Strain pending at 0.6 under 3:1), because the case no longer exists.
  - The thresholds are unchanged (3:1, 4.5:1).
  - `FocusedPolishTests.theActiveField` reads the field as it resolves, as on `main`.
- **PR 1 removes the dead light branches.**
  - These are the light conditions in `FocusedRowInk`, `ExerciseCard.raisedFill` and `SourceBadge`, and the light cases in
    `FocusedPolishTests`.
  - Two screenshot suites still write a light variant, `FocusedSessionShotsTests` and `ImportScreenshotTests`. It shows the same
    dark tokens, and a later PR drops it (PR 5 at the latest, D3).
- **Text gets larger.** `callout` grows 1 pt at 236 uses and `label` goes from 11 to 13 pt, so more text wraps at accessibility
  sizes. The AX3 previews and tests were run.
- **On `surface`, the raised fill is a little quieter.** It is 1.40:1 instead of the translucent value's 1.56:1, so chips inside a card
  stand out a little less. Selected states there also carry their ink or an accent border.

**What could go wrong:**
- **`StageDeep` `#2F55D4` is 2.95:1 on `surface`** (3.15:1 on `background`), under 3:1. It had this value in both appearances
  before. This is a known issue, left for PR 4, which redraws the hypnogram in the sleep colour and fixes or drops it.
- **The 48 % margin is 0.04.** Any change to `background`, `surface` or the ink must re-run `NocturneTokenTests`. Do not lower
  `textTertiary`.
- **Light below 20 pt.** A caller that passes `.light` under `lightFloor` gets it anyway. Review check.
- **Signal as text.** No contrast test fails on it (17:1). Review check: no `Theme.signal` as a text foreground.
- **A run without the fonts looks different.** A local or agent run without `make fonts` draws SF Pro Rounded at the system text
  styles' sizes, not the roles' (3, the follow-up). `make archive` refuses to run without all four weights, and `make icon` without
  Light.
- **Not seen yet** (`design.md` §PR 1 → 11): the widget on a device in system-light mode (forced in code), the tinted icon on the Home
  Screen, and the App Store's icon mask.
- **An appearance option later** would split every set again and double every pin. If it comes back, it gets its own ADR rather
  than a revert of this one.

**Rejected alternatives:**
- **A light appearance next to the dark one.** §1 says dark-only, and the canvas has no light screens, so a light set would be
  unreviewed. It would double every set, pin and preview.
- **Today's metric colours.** They pass, but the screens and the icon are measured against the canvas. Reverting stays cheap (2.1).
- **`textTertiary` at 45 %, limited to large text.** Its uses are 11–12 pt scales and meta, which is not large text.
- **`SurfaceRaised` translucent at 16 %** (the designer's first value, `design.md` T4). It needs no change now, but a fill's contrast
  then depends on its ground:
  - on `surface`, `textSecondary` drops to 5.11, `textTertiary` to 3.72, and strain on a track inside a card to 3.57;
  - `.opacity(0.6)` and nested fills stack;
  - every test of a raised site has to know what is under it.

  It fixes nothing the opaque value leaves open.
- **A separate `Track` set next to an opaque `SurfaceRaised`.** It means:
  - a new set in both catalogs, which the checker pairs once `Shared/` names it;
  - a new token;
  - seven call sites re-pointed and `OrbitGaugePalette` changed.

  All that is for a 16 % value that PR 3 then draws as one of three strengths from `textPrimary.opacity(…)`, which would leave two
  mechanisms for one concept.
- **Renaming `Accent` to `Recovery`.** Nothing visible changes, and it touches both catalogs, `Shared/` and the checker.
- **Generating the icon SVGs from the wordmark.** See 4.
