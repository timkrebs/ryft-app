# Nocturne gate (T5.9), the design note (G0, ui-designer, 2026-11-20)

Base: `main` at b6e416e, branch `feat/nocturne-gate` at a514b02. Inputs: `plan.md` (this folder), `../2026-11-16-nocturne/`
(`design.md` §P5-13, `accent-map.md`, `design-pr6-a/b/c`, `review.md` PR 5 and PR 6 "Left for later"), `../2026-11-20-analytics/`
(`ui.md`, `design.md`, `review.md`), `design/brand-board.png`. The inventory is a grep over `Ryft/`, `RyftWidgets/` and `Shared/`
at b6e416e; tests are listed apart (§1.8) because the compiler finds them too.

## 0. At a glance

**What this note finds that the plan did not know**
- Five of the components T5.9 was to delete have no caller in the app. `MetricTile`, `MetricGauge`, `ZoneBar` and `ScoreRing`
  are reached only from `DebugComponentCatalog` (`DateStrip` draws its own ring; Strain's tiles are `NeutralTile`s). `AppState.workoutDetail(_:)`
  and `cachedWorkoutDetail(_:)` have no caller at all (the 8 grep hits are `MockData.workoutDetail`, the analytics screen name and
  an enum case). The Stage colours (`Theme.stageDeep/Light/REM/Awake`, `Theme.color(for: SleepStageKind)`) are unused since
  PR 5 (`SleepStageTint` draws the stages in the sleep violet). So most of D7 is deletion, not a design.
- `ImportPrimaryButton` is already a `PillButton` under an old name (14 sites): a rename, not a restyle.
- The app's catalog has **no** `AccentColor` asset (the build setting names one; the widget has an empty one). The plan's "the
  `AccentColor` asset becomes ink" means adding it (G4).
- The only places that draw 18-pt cards (`Theme.Metrics.cardRadius`) are `CoachMarks` and Today's `WatchSyncHintCard`.
- The accent lint can widen to all of `Ryft/` only for its retired-token rule: its "no `warning`, `alert`, `accentSecondary`,
  `band`" rule would flag 50 legitimate uses in 29 files outside its four folders (G4, §5.4).
- At AX3 the analytics prompt's pinned bar (two pills) takes 28 % of the screen, so the buttons go inline from AX1 (D2).
- Add activity has no pinned Send (its Save is in the header), so D5 is only Report a problem.

**Decisions** (details in §2)

| # | Decision | On screen |
|---|---|---|
| D1 | The Insight glow tile takes its metric's colour (recovery teal, sleep violet, strain blue); an insight with no metric colour gets a flat neutral tile. No exception to L27 any more | Only a non-recovery insight changes: the demo's HRV insight stays teal |
| D2 | The analytics prompt is an `OnboardingScreen` sheet with four `OnboardingPoint`s, two equal outline pills, **no teal and no symbol** | The 30-pt teal symbol goes; the page looks like the Consent step |
| D3 | One `CircleMenu` (a `Menu` that is a `CircleButton`): live workout More, My Day Add, activity detail More | Nothing at rest; a disabled menu now dims, as the button does |
| D4 | One sheet header: close circle **leading**, title **centred** (`callout`), the trailing slot holds the commit pill or one circle button; pinned. C's sheet roots move to it | C's ten sheets lose the 26-pt Light leading title and the trailing close |
| D5 | Report a problem: no keyboard toolbar; Done joins Send in the pinned bar while the field has focus | The floating Done no longer covers Send |
| D6 | While a consent withdrawal runs, Profile dims the Demo data switch and Log out and says why (one sentence, in both places) | Seconds-long state, built in the follow-ups PR (F2) |
| D7 | Delete the Stage colours, `Theme.zones` and `SchemePair`; stages stay `SleepStageTint` | None |
| D8 | The card radius is 22 (`Theme.Metrics.neutralTileRadius`); the 18/16/18 tokens go | `WatchSyncHintCard` and the coach-mark card: +4 pt radius, 16 pt padding |
| D9 | `ValueChipRow` gets a `role` (field caption or row title); `PillButton` dim kept; "Last time" at its fade kept; rulers keep their end labels at AX; About you's wheel is a menu row from AX1; the journal strip keeps scrolling, padded and capped | See §2.9 |

**Ticket sizes** (files, sites; a site is one grep hit or one edit named in §1)

| Ticket | Files | Sites | Of which deleted / new |
|---|---|---|---|
| G1 sweep | 16 | 59 | none |
| G2 components | 25 | 34 (+3 in tests) | 4 files deleted, 2 new |
| G3 AX and keyboard | 4 | 4 | none |
| G4 deletion | 7 app files, 12 asset changes, 1 script, 14 test files | 27 + 12 + 1 + 37 | 11 colorsets deleted, 1 added |

**Needs the user** (a visible change he should see first): D4 (C sheets lose their big title), D1 (a sleep or strain insight is
no longer teal), D2 (the prompt loses its symbol). The renders are in §3.

## 1. The replacement table

Each file belongs to **one** ticket. G1 sweep, G2 components, G3 AX, G4 deletion. The Nocturne replacement is a token or
component that exists unless the row says "new".

### 1.1 `PrimaryButton(` (23 uses, 9 files) and `ImportPrimaryButton(`

| File:line | Use | Replacement | Ticket |
|---|---|---|---|
| `Features/Profile/ProfileComponents.swift:35` | the `struct PrimaryButton` (its body uses `Theme.onAccent` :86 and `Theme.accent` :94) | Delete the struct (the file keeps `RescoreStatus`) | G4 |
| `Features/Profile/DebugComponentCatalog.swift:212–215` | four `PrimaryButton(title:)` rows (primary, secondary, destructive, busy) | Delete the rows: "Nocturne · buttons" already shows every `PillButton` style and state | G2 |
| `Features/Profile/FeatureFlagsDebugView.swift:29` | `PrimaryButton(title: "Clear all overrides", style: .secondary)` | `PillButton(Text("Clear all overrides"), style: .secondary) { … }` (same catalog key) | G1 |
| `…/FeatureFlagsDebugView.swift:49` | `PrimaryButton(title: "Reload from the platform", style: .secondary, busy: reloading)` | `PillButton(Text(…), style: .secondary, busy: reloading) { async }` | G1 |
| `…/FeatureFlagsDebugView.swift:78` | `PrimaryButton(title: "Reload tracker catalog", style: .secondary, busy: reloadingCatalog)` | same; keeps `dev.reloadCatalog` | G1 |
| `Features/Profile/AnalyticsOptInSheet.swift:32, :34` | the prompt's two `PrimaryButton(…, style: .secondary)` | `PillButton(Text(…), style: .secondary)` ×2, see D2 | G1 |
| `Features/Train/Import/ImportFlowView.swift:195` | `struct ImportPrimaryButton` (a `PillButton` with `isEnabled`, an identifier and `busy`) | Rename to `ImportStepButton` (it is "a step's primary action"); body unchanged | G1 |
| `…/ImportPreviewView.swift:300, :309, :319` | `ImportPrimaryButton(` ×3 | `ImportStepButton(` | G1 |
| `…/ImportChooseView.swift:17` | ×1 | `ImportStepButton(` | G1 |
| `…/ImportPickView.swift:28` | ×1 | `ImportStepButton(` | G1 |
| `…/ImportDetectedView.swift:34, :39` | ×2 | `ImportStepButton(` | G1 |
| `…/ImportResultView.swift:353, :359, :370, :374, :383, :386` | ×6 | `ImportStepButton(` | G1 |
| `…/ImportMapView.swift:37` | ×1 | `ImportStepButton(` | G1 |

`ImportNocturneTests:72–73` bans `\bPrimaryButton\b` and passes today because `ImportPrimaryButton` is one word; after the
rename it keeps passing.

### 1.2 `TealButtonStyle` (8 uses, 5 files)

| File:line | Use | Replacement | Ticket |
|---|---|---|---|
| `Features/Train/TrainComponents.swift:124` | `struct TealButtonStyle` (:131 `Theme.onAccent` / `Theme.accent`, :133 `Theme.accent`; the doc at :122 says it "stays for the callers outside Area B") | Delete the struct | G4 |
| `Design/CoachMarks.swift:147` | "Next" / "Done" `.buttonStyle(TealButtonStyle()).frame(maxWidth: 140)` | `PillButton(Text(marks.isLast ? "Done" : "Next"), size: .compact) { advance() }` (the compact primary, no icon), id `coach.next` kept | G1 |
| `Push/PushPrePromptCard.swift:20` | "Allow" `TealButtonStyle(prominent: true)` | `PillButton(Text("Allow")) { enable() }` (regular primary, forward arrow) | G1 |
| `Push/PushPrePromptCard.swift:24` | "Not now" `TealButtonStyle(prominent: false)` | `LaterButton(title: "Not now") { dismiss() }` under the pill (the onboarding steps' quiet action; "Not now" is a deferral, not a refusal) | G1 |
| `Features/Today/TodayView.swift:703, :705` | the same pair in `ImportCard` ("Tell me when my first scores are ready") | the same pair: `PillButton(Text("Allow"))`, `LaterButton(title: "Not now")` | G1 |
| `Features/Profile/DebugComponentCatalog.swift:216, :217` | `Button("Start")`, `Button("New plan")` with the style | Delete the rows | G2 |

### 1.3 `Theme.accent` (21 uses, 11 files) and `Theme.onAccent` (4 uses, 4 files)

| File:line | Use | Replacement | Ticket |
|---|---|---|---|
| `Design/Theme.swift:42` (and :70 in `band(forScore:)`, :104 in `zones`) | the token; `band` returns `accent` for 67+ | Delete `accent`; `band` returns `recovery` (the same `#63D2B4`) | G4 |
| `Design/Theme.swift:47` | `onAccent` | Delete | G4 |
| `Design/RangeBar.swift:35` | "good side of the range" colour | `Theme.recovery` (accent map D: a personal range of a recovery metric) | G1 |
| `Design/ScoreRing.swift:11` | default ring colour | file deleted (unused) | G2 |
| `Design/MetricGauge.swift:241, :256` | doc comment; the link's `foregroundStyle` | file deleted (unused) | G2 |
| `Design/MetricTile.swift:8` | default tint | file deleted (unused) | G2 |
| `Design/MetricSpec.swift:90` | `readiness.color` | `Theme.recovery` (the legend) | G1 |
| `Design/MetricSpec.swift:93` | `recovery.color` | `Theme.recovery` | G1 |
| `Design/MetricSpec.swift:107` | `hrv.color` | `Theme.recovery` (HRV belongs to recovery, D5-9) | G1 |
| `Design/StatusViews.swift:952` | `SetupCard`'s `RyftMark` | `Theme.textPrimary` | G1 |
| `Design/StatusViews.swift:972, :975` | `SetupCard`'s "Open Profile": `onAccent` ink on an `accent` capsule | `PillButton(Text("Open Profile")) { action() }` (primary, forward arrow); delete the hand-built capsule | G1 |
| `Features/Today/TodayView.swift:669` | `ImportCard`'s `RyftMark` | `Theme.textPrimary` | G1 |
| `Features/Today/TodayView.swift:683` | the import's `ProgressView(value:).tint(Theme.accent)` | `.tint(Theme.textPrimary)` (accent map class G: progress is ink) | G1 |
| `Features/Today/TodayView.swift:726, :730` | the current step: `onAccent` ink on an `accent` capsule | the inverse chip: `Theme.background` ink on a `Theme.textPrimary` capsule (accent map class F); the step still reads "Step n of 3" for VoiceOver | G1 |
| `Features/Today/TodayView.swift:769` | `ImportRow`'s `ProgressView(value:).tint(Theme.accent)` | `.tint(Theme.textPrimary)` | G1 |
| `Features/Train/TrainComponents.swift:131, :133` | inside `TealButtonStyle` | deleted with it | G4 |
| `Features/Profile/ProfileComponents.swift:86, :94` | inside `PrimaryButton` | deleted with it | G4 |
| `Features/Profile/FeatureFlagsDebugView.swift:101` | a `Toggle`'s `.tint(Theme.accent)` | delete the line (the root's `.toggleStyle(.ryft)` applies; accent map class T) | G1 |
| `Features/Profile/FeatureFlagsDebugView.swift:106` | "Use the platform's value" `foregroundStyle(Theme.accent)` | `.ryftLink()` (accent map class X: a text control on its own line) | G1 |
| `Features/Profile/AnalyticsOptInSheet.swift:54, :84` | the symbol's teal; `ConsentPoint.symbolColor` default | both go with the frame and `ConsentPoint`, see D2 | G1 |

### 1.4 `Theme.zones` (2 uses), the Stage colours (4), `Color("Accent")`, `Color("Teal")`

| File:line | Use | Replacement | Ticket |
|---|---|---|---|
| `Design/ZoneBar.swift:42, :57` | `Theme.zones[i]` | file deleted (unused; `ZoneBlock` is Strain's zones) | G2 |
| `Design/Theme.swift:104` | `static let zones` | Delete | G4 |
| `Design/Theme.swift:69–72` | `stageDeep/Light/REM/Awake = Color("Stage…")` | Delete (D7) | G4 |
| `Design/Theme.swift:74–80` | `color(for stage: SleepStageKind)`, no caller | Delete (`SleepStageTint` is the stage palette) | G4 |
| `Design/Theme.swift:19` | `teal = Color("Teal")` | Delete | G4 |
| `Design/Theme.swift:42` | `accent = Color("Accent")` | Delete | G4 |
| `Ryft/Assets.xcassets` | `Accent`, `Teal`, `OnAccent`, `StageDeep`, `StageLight`, `StageREM`, `StageAwake` colour sets | Delete | G4 |

No other `Color("Accent")`, `Color("Teal")` or `Color("Stage…")` exists in `Ryft/`, `RyftWidgets/` or `Shared/`.

### 1.5 `SchemePair` (16 uses, 6 files)

| File:line | Use | Replacement | Ticket |
|---|---|---|---|
| `Preview/PreviewSupport.swift:4` (def), :22 (comment) | `struct SchemePair` | Delete; `DarkPreview` stays. Also drop the `scheme:` parameter of `previewEnvironment` (:46) | G4 |
| `Design/ZoneBar.swift:85` | 1 | file deleted | G2 |
| `Design/MetricTile.swift:84, :95, :130` | 3 | file deleted | G2 |
| `Design/ScoreRing.swift:52` | 1 | file deleted | G2 |
| `Design/RangeBar.swift:131` | 1 | `DarkPreview { … }`, keep the AX3 preview if there is one | G1 |
| `Design/StatusViews.swift:1491, :1535, :1546, :1559, :1570, :1613, :1648, :1660` | 8 | `DarkPreview { … }`; the three `· de` previews (:1534 "Sync status line · de", :1569 "… taking longer · de · AX3", :1659 "Error card · de · AX3") become their English AX3 previews | G1 |

### 1.6 `MetricTile`, `MetricGauge`, `AppState.workoutDetail`

| File:line | Use | Replacement | Ticket |
|---|---|---|---|
| `Design/MetricTile.swift` (140 lines) | the type and 6 previews (3 `SchemePair`, 1 `de`) | Delete the file | G2 |
| `Features/Profile/DebugComponentCatalog.swift:36, :160–163` | `section("MetricTile") { tiles }` and its 3 tiles | Delete the section | G2 |
| `Design/NeutralTile.swift:4` | a comment saying Train still uses `MetricTile` (not true) | Reword: "replaces `MetricTile`" gone | G2 |
| `Design/MetricGauge.swift` (378 lines) | the type and 8 previews (incl. 3 `de`) | Delete the file | G2 |
| `Features/Profile/DebugComponentCatalog.swift:30, :91–101` | `section("MetricGauge") { gauges }` and 6 gauges | Delete the section | G2 |
| `Design/OrbitGauge.swift:19`, `Shared/OrbitGaugeDrawing.swift:20, :37` | comments naming `MetricGauge`'s dials | Reword to "the dial sizes" (so the grep is empty); `check-shared-types.py` compares the Shared copy | G2 |
| `Design/ScoreRing.swift:5` | a comment naming `MetricGauge` | file deleted | G2 |
| `App/AppState.swift:523` | `func workoutDetail(_ w: Workout) async -> WorkoutDetail`: **no caller** | Delete it and `cachedWorkoutDetail` (:520), also unused; then check whether `repository.workout(_:)` / the refresh it called still has a caller (the compiler won't say) | G2 |
| `Features/Strain/WorkoutDetailView.swift:12`, `Analytics/AnalyticsEvent.swift:88`, `Preview/MockData.swift:63–67, :531` | `.workoutDetail` the analytics screen, `MockData.workoutDetail` | not the symbol: keep | — |

### 1.7 Light previews and the previews in German

Every `.preferredColorScheme(.light)`, `scheme: .light`, `ColorScheme.light`, `userInterfaceStyle = .light` and "· light"
preview in `Ryft/`, `RyftWidgets/` and `Shared/` (the 54 / 38 of the plan counted `SchemePair` blocks and `de` previews with them;
this grep is exact):

| File:line | Use | Replacement | Ticket |
|---|---|---|---|
| `Features/Profile/FeatureFlagsDebugView.swift:126–129` | `#Preview("Feature flags · light")` | delete the preview | G1 |
| `Push/PushPrePromptCard.swift:39–45` | `#Preview("Push pre-prompt · light")` | delete; add the AX3 dark preview | G1 |
| `Features/Train/Session/SetColumnPreview.swift:18, :26, :34, :42` | four "Column · … light" previews | delete | G4 |
| `Features/Train/Session/SessionPager.swift:59–60` | "Pager · light" | delete | G4 |
| `Preview/PreviewSupport.swift:9` (the pair), :46 (`scheme:`) | the pair's loop; the parameter | see §1.5 | G4 |
| `SchemePair` sites | §1.5 | | G1 / G2 |
| `· de` previews | `StatusViews` ×3 (§1.5); `MetricGauge` ×3 and `MetricTile` ×1 (deleted files) | | G1 / G2 |

No light variant exists in `RyftWidgets/` or `Shared/`. `docs/screenshots` (74 `-light`, 67 `-de`) is G6's.

### 1.8 Tests that name a retired symbol (G4 with the test-engineer; the compiler finds them)

`Theme.accent` → `Theme.recovery` is a pure rename (`NocturneTokenTests:117` pins that they resolve to the same pixel today).

| File:line | Use | Edit |
|---|---|---|
| `OrbitGaugeShotsTests:53`, `:140` | `Theme.accent`; `Theme.graphite` / `Theme.mist` | `recovery`; `background` / `textPrimary` |
| `OrbitGaugeRenderTests:88, :207` | `Theme.accent` ×2 | `recovery` |
| `OrbitGaugeContrastTests:113–140` | the doc and a table row | `recovery` |
| `NocturneTokenTests:72, :77, :79–83, :87–90, :117, :137` | token rows (`accent`, `onAccent`, `graphite`, `slate`, `mist`, `teal`, `sage`, the four stages) and two relations | delete the rows and the two relations; keep `recovery` ≥ 4.5 on `background` |
| `NocturneFoundationTests:134` | `Tokens.resolve(Theme.accent)` | `Theme.recovery` |
| `DevicesSyncNocturneTests:44` | `$0.color == Theme.accent …` | `Theme.recovery` only |
| `ChartStyleTests:52` | `DeltaLabel.color(d, spec: .hrv) == Theme.accent` | `Theme.recovery` |
| `NocturneControlsTests:392` | "the same as Accent" | delete the line |
| `ProfileSubpagesTests:50–51, :434, :439` | `Theme.accent` | `Theme.recovery` |
| `ActivitiesNocturneTests:24` | `!= Theme.accent` | `!= Theme.recovery` |
| `NocturneComponentTests:494–495` | pins `cardRadius == 18`, `tileRadius == 16`, `cardPadding == 18` | delete (D8) |
| `HostedAccessibility:83, :98`, `Import/ImportScreenshotTests:122, :187`, `FocusedSessionShotsTests:189` | render a light variant | drop the variant and the `dark:` parameter |
| `ReduceMotionScanTests:44, :56` | two `Guarded(file:)` entries for `MetricGauge.swift` and `ScoreRing.swift` | delete the entries (**G2**: it deletes the files) |
| `OrbitGaugeGeometryTests:72` | a test named `sizesKeepMetricGaugeFrames` | rename (**G2**) |

The string-literal bans (`SignedOutOnboardingTests:540`, `ProfileSubpagesTests:76`, `ImportNocturneTests:52`, `BedtimeNocturneTests:753`,
`WidgetNocturneTests:502`, `SleepNeedEditorsTests:943`, `SleepModesTests:481/491`) keep guarding and need no edit.

### 1.9 Unused symbols (G4 deletes; the compiler proves it)

`Theme.stageDeep/Light/REM/Awake` and `Theme.color(for: SleepStageKind)` (no caller since PR 5); `Theme.zones` (after `ZoneBar`);
`Theme.graphite`, `slate`, `sage`, `mist` (only a widget doc comment, `OrbitGaugeShotsTests:140` and `NocturneTokenTests` name them; the
`Graphite`, `Slate`, `Sage`, `Mist` colour sets go with them); `Theme.Metrics.cardRadius`, `tileRadius`, `cardPadding` (D8);
`SchemePair` and `previewEnvironment(scheme:)`. G2 deletes the unused `ZoneBar`, `ScoreRing`, `MetricGauge`, `MetricTile`,
`AppState.workoutDetail` and `cachedWorkoutDetail`. Kept on purpose: `Theme.accentSecondary` (sage; `MetricSpec.respRate`/`steps`,
`color(for: InsightSeverity)`), `Theme.band(forScore:)`, `RangeBar` (unplaced since PR 2 "waits for the Today layout"; one
colour fix, G1), `DarkPreview`.

### 1.10 The `AccentColor` asset (G4)

`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor` is set in both app configurations, but `Ryft/Assets.xcassets` has no
`AccentColor.colorset`, so a control that nobody tints falls back to system blue (`PresentedRoot.swift:13` says so). G4 adds
`AccentColor.colorset` with one universal value, `#F2F1EC` (the `TextPrimary` value): the safety net the PR 5 review asked for. The
widget's empty `AccentColor` stays: its one `Link` is tinted `Brand.signal` in code and nothing else there is a control.

## 2. Decisions D1 to D9

The rule behind every one is L27 (`plan.md` of the Nocturne folder: teal is recovery only; links, toggles, checks and icon tints are
`textPrimary`; Volt is the one marked thing) and the accent map's classes (T tints, M medallions, F solid fills, G bars and rules,
S selection, X text and glyphs, D data). Colours come from the legend: `recovery`, `metricSleep`, `metricStrain`.

### 2.1 D1: the Insight glow tile's teal

**Options.**
- A. Keep the recovery glow for every `info` insight (spec F4, "a known exception to L27").
- B. A neutral tile for every insight (flat `surface`, a ring in ink at 16 %).
- C. The glow takes the colour of the insight's metric, as the trend cards do; an insight whose metric has no legend colour
  gets B's flat neutral tile.

**Decision: C.**
- The mapping is `TrendCardStyle`'s (`TrendCardContent.swift`, "the rings are the legend"): `readiness`, `recovery`, `hrv` →
  `Theme.recovery`; `sleep`, `sleepMin`, `sleepQuality`, `sleepConsistency`, `napMin` → `Theme.metricSleep`; `strain`,
  `strengthMin`, `volumeKg` → `Theme.metricStrain`; `rhr`, `steps`, `activeKcal` and an insight with no known `trendMetric` →
  neutral. One function, `InsightTile.tint(for: Insight) -> Color?` (nil = neutral).
- The neutral tile is the tile's own flat look (`surface`, 120 pt, radius 28) with a 1.5 pt ring in `textPrimary` at 16 % (the
  `controlOutline` weight, the `IconDisc` ring colour) instead of the tint's 2 pt border; the Volt hint dot, "Insight" label,
  title, body and link stay as they are.

**Why.**
- L27 says teal means recovery. A "Naps are paying off" or "New personal record" tile in teal tells the reader it is about
  recovery, and the legend is the one thing the brand board teaches (teal ring, violet and blue beside it).
- F4 approved the *name* "Insight" and the glow tile; it did not need teal. Keeping the glow keeps the board's look.
- Contrast is no obstacle: teal (`#63D2B4`) is the lightest of the three tints, so `textPrimary` on a violet or blue glow is
  better than the pinned recovery figures (350 × 120: ≥ 6.2:1, 420 high: ≥ 4.8:1); the flat neutral tile is 16:1 (D5-20).
- The accent map has no row for this tile (it was built from `Theme.accent`; the tile uses `Theme.recovery`), so nothing in
  T5.9 forces a change; this is a design call, and C removes the one standing exception to L27 instead of writing it into the lint.

**On screen.** The demo's insight ("Best HRV in 30 days", `hrv`) stays teal, so nothing changes by default. A sleep insight now
glows violet, a strain or training one blue, a resting-heart-rate, steps or energy one is a flat neutral tile. Reduce
Transparency and the flat-above-420 pt rule draw the 2 pt border in the tint, or in ink at 16 % for the neutral tile.
Owner: G1 (`InsightTile.swift`, one file). Renders: none needed (the glow in violet and blue is `GlowTile(metricSleep/metricStrain,
kind: .hypnogram/.zones)`, already approved; the flat look is Reduce Transparency's).

### 2.2 D2: the analytics prompt in Nocturne

The prompt is shown to nobody in phase 1 (no-op sink everywhere), so this is the redraw that ships dark and is right the day phase
2 turns it on. Today it is a private `AnalyticsPromptFrame` that copies PR 6 A's *old* `OnboardingScreen` (a 30-pt teal symbol, the
title, the text, 20 pt apart), four `ConsentPoint`s with `textSecondary` symbols, and two `PrimaryButton(.secondary)`.

**The conflict.** `ui.md` says "`OnboardingScreen(symbol: "chart.bar", …)`, accent only on the symbol". Both halves are out of date:
`OnboardingScreen` has no symbol parameter any more (PR 6 A A-7 replaced the symbol with the title, lead and, in the first run, the
lock-up), and the accent map's rule (class X, "an icon tint is `textPrimary`") plus L27 leave no teal for a symbol that isn't the
recovery metric.

**Decision.**
- **Frame:** `OnboardingScreen(title:lead:showsLockup: false)` (a sheet: the grabber shows, the title starts 36 below the sheet's
  edge, 26 Light, header trait; the lead in 16 `textSecondary`). No symbol, no teal, no Volt. The page is the Consent step's sibling.
- **Points:** one `GroupedCard` of four `OnboardingPoint`s (17 pt `textPrimary` glyph in a 28 pt column, a 16 Medium title, the text
  in 15 `textSecondary`). `OnboardingPoint` needs a title, so each point gets one (new strings, §4): "What is counted", "What is
  not", "Your ID", "Where it goes". `ConsentPoint` and `AnalyticsPromptFrame` are deleted (the file keeps `AnalyticsOptInSheet` and the
  modifier).
- **Footnote:** "Change this any time in Profile → Privacy." in `caption` `textTertiary`, 12 under the card.
- **Buttons:** two `PillButton(style: .secondary)`, "Share usage analytics" and "Don't share", **the same size and style**, 10 apart (the
  `PinnedBarSpec.spacing`). Equal weight is the point (a consent is not a funnel): there is no primary and no icon circle, and
  neither is in the accent. Order as `ui.md`: Share, then Don't share. A swipe down is still "Don't share".
- **Placement:** pinned (`.pinnedBar`) up to the largest standard size, so both answers are always on screen; from AX1 they are
  inline at the end of the page, as `ui.md` wants at AX5 and as the onboarding steps do (a pinned bar of two wrapped pills would take
  a third of the screen at AX3; the draft shows it).
- **Title:** keep the shipped "Share usage analytics?" (`ui.md` says "Share anonymous usage analytics?"; the privacy review
  removed "anonymous": a random ID plus the IP is pseudonymous).
- **Decision B of #130** (the prompt as an onboarding step, so the funnel events can fire) is the user's call; the frame is the
  same either way (`showsLockup: true`, `dismissible: false`).

**Why.** The brand board's calm comes from one idea per screen and thin rules; the Consent step is the app's other
data-permission page, and a user who has just read it should recognise this one as the same kind of question. Teal here would
claim the recovery colour for a privacy choice (accent map class X).

**On screen.** The symbol and the teal go; the points get headings and sit in a card; the buttons are outline pills in a pinned bar.
Identifiers stay (`analytics.share`, `analytics.decline`). Owner: G1 (`AnalyticsOptInSheet.swift`).

### 2.3 D3: one circle menu

**The three hand-drawn ones** (a `Menu` whose label re-draws `CircleButton`'s numbers because a `CircleButton` is a `Button`):
1. `Features/Train/Session/SessionView.swift:274–290`, the live workout's **More** (`ellipsis`; Reorder exercises, Discard workout).
2. `Features/Activities/ActivityDetailView.swift:112–132`, the activity detail's **More** (`ellipsis`; Edit, Delete).
3. `Features/MyDay/MyDayCard.swift:426–460` (`MyDayAddMenu`), My Day's **Add** (`plus`; Add activity, Start strength workout, Add sleep).

Three more menus use a bare, ring-less `ellipsis` inside a row (`PlanBuilderView.swift:375`, `ExercisePage.swift:181`,
`ExerciseCard.swift:127`). They are not circle buttons and stay (a ring on every exercise card would add three rings to a
card that has its own edge); they are not in G2.

**Component.** `Design/CircleMenu.swift`:

```swift
struct CircleMenu<Items: View>: View {
    init(systemImage: String, iconSize: CGFloat = CircleButton.iconSize, accessibilityLabel: Text,
         @ViewBuilder items: () -> Items)
}
```

- **Look: the `CircleButton`'s, from one source.** Extract the circle's numbers into `CircleButtonLook` (a `ViewModifier` in
  `CircleButton.swift`: the 40 pt circle, the 1 pt `textPrimary` ring at 16 %, the 44 pt box, icon `textPrimary`, 35 % when
  disabled); `CircleButtonStyle` and `CircleMenu` both apply it. A `Menu` shows the system's highlight when pressed instead of the
  8 % fill; the draft shows idle and disabled next to a `CircleButton`.
- **Accessibility:** the label is the caller's; `accessibilityShowsLargeContentViewer` as `CircleButton`'s; the identifier is the
  caller's (`activityDetail.menu`, `myday.add`; the live workout's gets `session.more`).
- **Sites:** each caller keeps its `.headerEdgeButton()` where it had one (the live workout's), and the menu order
  (`.menuOrder(.fixed)`) stays where the exercise page sets it (not a circle menu).
- **Disabled:** dims like the button. The hand-drawn menus never dimmed; none is disabled today, so nothing changes on screen.

Owner: G2 (`CircleMenu.swift`, `CircleButton.swift`, `SessionView.swift`, `ActivityDetailView.swift`, `MyDayCard.swift`).

### 2.4 D4: one sheet header convention

**Today.** B's sheets (`SheetHeader`/`SheetFrame`: Start workout, Add activity, Add sleep, Plan, Reorder, Rest, Notes, Add exercise,
Edit targets, Exercise history, Journal, Plate calculator) draw the close circle **leading**, the title **centred** in `callout`, and a
trailing commit pill or one circle, pinned above the scroll. C's sheet roots (`SubpageScaffold(isSheet: true, navigation: .close())`:
Details, Add a habit, Sleep need, What do you wear?, the body-setting editors, Check sync, Devices & sync, Sync details, Tracker
detail when presented as sheets, the import's session detail, change password) draw the title **leading** in 26 Light and the close
circle **trailing**, scrolling with the page.

**Options.**
- A. B's convention everywhere (close leading, title centred, commit trailing, pinned).
- B. C's everywhere (title leading, close trailing). The commit has nowhere to go but a pinned bar, which rides the keyboard (D5's
  problem) and leaves a form with no keyboard-proof Save.
- C. Keep both and write the rule down. The review asked for one.

**Decision: A.**
1. **The close circle is leading.** A `CircleButton("xmark")` labelled "Close", or "Cancel" when closing discards what was typed
   (as today), or "Done" for a sheet that has nothing to discard and calls it so (Details). Always the sheet's dismissal; the caller's
   `onClose` asks first when work would be lost.
2. **The title is centred**, `callout` `textPrimary`, header trait, between slots of equal width (`SheetHeaderLayout`); below AX1
   under the row, centred, when it would be narrower than 120 pt (a wide pill at XXXL). **From AX1 the header stacks as
   `PushedHeader` does** (one header everywhere, part 2): the close circle and the trailing slot on the first 40 pt row; 12 below
   them the title from the leading inset, across the width, wrapping, never squeezed between the circles; VoiceOver in the order
   drawn (Close, the trailing slot, the title). Below AX1 VoiceOver reads the title first.
3. **The trailing slot is empty, one `CircleButton` or `CircleMenu`, or the commit**: a compact primary `PillButton`
   ("Save", "Add", "Done"). Never a second dismissal.
4. **Where the commit lives.** A sheet whose job is a short form with a keyboard puts its commit in the header (Add activity,
   Add sleep, plans, notes, targets). A sheet that is a page (Details' Send, Check sync, the tracker picker, an editor with a long
   footnote) keeps its single pinned primary (`PinnedActionBar`) and has an empty trailing slot. One primary per sheet, in one place.
5. **The header is pinned**, not scroll content: the close circle stays reachable. This is the only behavioural change for C's pages.
   While content has scrolled under it, the page stops 12 below the header at a 1 pt `separator` rule, the pinned bar's edge
   turned over (part 2, `.underPinnedHeader()`); at rest nothing shows.
6. **A page pushed inside a sheet** is a page: Back leading, its own title (`SubpageHeader`/`PushedHeader`), no close; a swipe down
   still dismisses the sheet. The one exception is the training import, a flow whose steps 2–5 need Back *and* a close that asks
   first: Back leading, the close circle trailing (`SubpageNavigation.backAndClose`, as built). Its root (step 1) has the sheet
   header.
7. **Not sheets with this header:** the onboarding steps and gate sheets (a page with the grabber, no dismissal button: they are
   flows), system sheets (share, Safari, file picker).

**Implementation (G2), in one place.** `SubpageScaffold` with `isSheet: true` and `navigation: .close(…)` draws `SheetHeader`
(pinned above its scroll view) instead of `SubpageHeader`, so the ~12 call sites don't change; `.backAndClose` and `.back` keep
`SubpageHeader`. `SubpageNavigation.close`'s doc says so. The trailing slot of the scaffold (`trailing:`) is what `SheetHeader`'s
trailing is. `SheetFrame` is unchanged.

**Superseded in part by the user's call (DG-6, `plan.md`, 2026-11-21): one header everywhere.** Pushed pages
(`.back`) draw `PushedHeader`'s row (Back leading, title centred). `.backAndClose` draws Back, the centred title, then
the caller's circles and Close trailing. `SubpageHeader` is deleted.

**Why.** HIG for iOS 26–27 sheets puts the dismissal leading and the confirmation trailing; B's header already does and is
keyboard-proof. "Numbers first" says the page's own first line should be its numeral, not a 26-pt title competing with it (Sleep
need opens on an 8:18 numeral; the draft shows both). C's 26-pt title is the *page* look (Back, big title); a sheet root is not a
page.

**On screen.** C's ten or so sheets: the large leading title becomes a small centred one, the close circle moves from the right to the
left, and the header stays put while the content scrolls (the header is 40 pt under the 26-pt inset instead of 40 + 22 of
scrolling title). B's sheets don't change. **This is the visible change to show the user first** (draft D4).

Owner: G2 (`SubpageScaffold.swift`; `SheetHeader.swift` doc).

### 2.5 D5: the keyboard's floating Done over a pinned Send

**Scope.** The iOS 27 `.keyboard` toolbar floats a glass "Done" above the keyboard; a bottom `safeAreaInset` bar rides on top of the
keyboard, so the two overlap. Only **Report a problem** has both (`ReportProblemView.swift:65–69` and the `sendBar` at :132). **Add
activity** has the keyboard Done too (`AddActivitySheet.swift:71–76`) but its Save is in the header and nothing is pinned above the keyboard:
keep, because the floating Done lands on scrolling form content. No other file uses `placement: .keyboard`.

**Options.** (a) Done in the page header (it scrolls away with a long message); (b) hide the pinned bar while editing (Send is two
taps away, and the bar jumps with the keyboard); (c) no Done (a multi-line field has no visible way out; Switch Control has none);
(d) Done joins Send in the bar while the field has focus.

**Decision: (d).**
- Delete the `.keyboard` toolbar from Report a problem.
- While the message field has focus (`editing`), `sendBar`'s row is **[Done · Send]**: `PillButton(Text("Done"), style: .secondary)`
  leading and the primary Send trailing, 12 apart, equal width; otherwise Send alone, full width, as today. The row changes with
  `Theme.Motion.quick` (none under Reduce Motion). Done sets `editing = false`; Send already does, then sends.
- From AX1 the two pills stack, **Send above Done** (primary first, as in every stacked bar), 8 apart (`PinnedBarSpec.spacing`).
- The caption and footnote keep their places (in the bar below AX1, at the page's end from AX1).
- Identifiers: `report.send` (kept), `report.done` (new). Done is not disabled while sending (`editing` is false by then).

**Why.** The primary action stays one tap away while the keyboard is up (the common case: type, Send), and the way out is a visible,
44-pt-plus control in the one place the thumb already is. It is the same pinned bar the page has, not a new surface.

**On screen.** With the keyboard up, the bar shows Done and Send side by side instead of a lone Send covered by a glass capsule. Draft
`d5-report-bar`. Owner: G3 (`ReportProblemView.swift`).

### 2.6 D6: Profile while a consent withdrawal is on its way (built in the follow-ups PR, F2)

**Why a hold.** `OnboardingCoordinator.withdrawConsent()` waits for a step's request in flight, sends `DELETE /v1/me/consent`, and
**ends unsent** on a sign-out or an account switch (so A's withdrawal never goes out with B's session). The Demo data switch changes
what `AppEnvironment.api` talks to, and Log out ends the session: either, tapped in those seconds, drops the user's withdrawal
without a word (security review N-2). The window is seconds long; nothing else in Profile can end it (Delete account removes the
account and with it the consent, so it stays enabled).

**Held while `model.withdrawingConsent`:** the **Demo data** switch and **Log out**. Everything else works (Export reads, Change
password is a sheet over the same session).

**States.**

| State | Trigger | Withdraw consent row | Demo data row | Log out | Privacy footer |
|---|---|---|---|---|---|
| Idle | consent given | "Withdraw consent" in `alert`, no spinner | switch live, detail "Show a realistic sample history instead of your server." | secondary pill, live | "Agreed on 20 Oct 2026 · policy 2026-10-20" |
| **Withdrawing** | the confirmation's "Withdraw consent" tapped, until the platform answers (a step's request included) | the busy rule: spinner trailing, **title stays**, taps ignored | **switch dimmed (35 %), untappable; detail becomes the reason** | **pill dimmed (35 %), untappable**; the reason one line under the buttons row | "Withdrawing your consent. Syncing stops once RYFT confirms." |
| Withdrawn | the answer arrived | gone; "Review and agree" in its place | live again | live again | the consent value reads "Not given"; VoiceOver is told |
| Failed | the answer is an error or no connection | "Withdraw consent" again; the failure under Privacy with Details (exists) | live again | live again | the failure's `InlineMessage` |
| Ended unsent | an account change ended it | row gone (another account) | live | live | none |
| Demo data on | `isDemo` | no Withdraw row (exists) | n/a | live | the existing "Demo data is on…" |

**The reason is one sentence, shown where the held control is:** "Waiting for your consent withdrawal to finish." (new string).
- *Demo data:* replaces the row's detail line while held; the detail is part of the toggle's label, so VoiceOver reads "Demo data,
  Waiting for your consent withdrawal to finish. Dimmed, switch button, off".
- *Log out:* `caption` `textSecondary` under the buttons row (8 below it); the pill carries it as its accessibility hint and the
  caption is hidden from VoiceOver, so it is read once ("Log out, dimmed, button. Waiting for your consent withdrawal to finish.").
- *Withdraw consent* (busy): "Withdraw consent, In progress" (the busy rule, as every busy pill and row).
- *Done:* post `AccessibilityNotification.Announcement("Consent withdrawn. Syncing has stopped.")` (new string); a failure announces
  itself through its `InlineMessage`.

**Motion.** The dim fades with `Theme.Motion.quick` (none under Reduce Motion). A withdrawal that answers in under a second shows a
short dim; that is honest and cheaper than a delay timer nobody can test.

**Copy direction.** Say what is happening and when it ends; never "please wait" or an apology; the same sentence in both places
so a user who sees one learns the other. **Alternatives rejected:** disabling without a reason (a dimmed control with no
explanation), a blocking spinner over the page (blocks Export and reading, and withdrawal is not a modal act), and a dialog on
the tap ("Withdrawal in progress"): a tap on a dimmed control should do nothing.

**On screen.** A few seconds after the confirmation. Draft `d6-profile-held` (default and AX3); `d6-profile-idle` for comparison.
Owner: F2 (`ProfileView.swift`, `ProfileViewModel.swift`), not the gate. The gate's files don't touch them.

### 2.7 D7: `SchemePair` and the Stage colours

**Options.** Keep the dark values as tokens, or use the existing palette.

**Decision: the existing palette; delete both.**
- `SchemePair` renders a component twice, dark above light; the app is dark only (ADR 0016) and PR 5/6 already moved every other
  preview to `DarkPreview`. After G1 and G2 it has no caller. Delete it and `previewEnvironment`'s `scheme:` parameter (G4).
- The Stage colours (`StageDeep #2F55D4`, `StageLight #4F7BE8`, `StageREM #8FB3FF`, `StageAwake #B8C4D6`) are a blue family the board
  doesn't have for sleep; PR 5 replaced them with `SleepStageTint` (the sleep violet at 100 / 80 / 62 %, Awake `textTertiary`:
  design.md §P5-7.2) and nothing calls `Theme.color(for: SleepStageKind)` any more. `SleepModesTests:481/491` already pins that no
  sleep view names them. Keeping them as tokens would keep a second sleep palette alive for no caller, and `Theme.zones` (which
  starts with `stageAwake`) goes with `ZoneBar`.

**On screen.** Nothing. Owner: G4 (tokens, `PreviewSupport.swift`), G2 (`ZoneBar`).

### 2.8 D8: the card radius

**Facts.** `Theme.Metrics.cardRadius` is 18 and `cardPadding` 18; `neutralTileRadius` is 22. Everything that is a card already reads
22: `Card` and `CardSpec` (22 / 16), `GroupedCard`, `NeutralTile`, `PlaceholderRow`, `IconDisc`'s panel, the toast, the stage card,
Strain's chart card, Profile's and the journal's local `cardRadius = 22`. The 18 survives in exactly two views:
`CoachMarks.swift:153` (radius; padding is a literal 18) and Today's `WatchSyncHintCard` (`TodayView.swift:904–907`).

**Options.** 22 everywhere, or move the token to 22 and keep two names.

**Decision: 22, one token, `Theme.Metrics.neutralTileRadius`** (keep the name: 14 files read it; a rename is churn for no reader).
- G1 moves the two odd views (they are in G1's files): the coach-mark card becomes a `Card` (radius `CardSpec.radius` 22, padding
  `CardSpec.padding` 16); `WatchSyncHintCard` reads `CardSpec.radius` and `CardSpec.padding`.
- G2 points the four local duplicates at the token: `ProfileLayout.cardRadius` (:22), `JournalSettingsLayout.cardRadius` (:10),
  `StrainLayout.chartRadius` (:71), `SleepModesLayout.stageCardRadius` (:33) become `= Theme.Metrics.neutralTileRadius`.
- G4 deletes `Theme.Metrics.cardRadius`, `tileRadius` (16, only `MetricTile`) and `cardPadding`, and their pins
  (`NocturneComponentTests:494–495`).

**Why.** Brief §2 "Form": neutral tiles and lists are 22; the 18/16 were pre-Nocturne and the `Card` TODO (`Card.swift:7`, "T6.0, lead:
set cardRadius to 22") says so. Two surfaces on Today with different corners next to each other is the visible defect.

**On screen.** `WatchSyncHintCard` (Today's "your tracker is quiet" card) and the coach-mark card: +4 pt corner radius, 16 instead
of 18 pt inside. The TODO comment in `Card.swift` goes.

### 2.9 D9: the nits

| # | Item | Decision | Owner |
|---|---|---|---|
| 1 | `ValueChipRow`'s label ink | **Spec: the label's ink follows its neighbours, as a parameter.** `ValueChipRow(_ label:, role: .field / .row)`, default `.field`: `callout` `textSecondary`, a field caption like `FormField`'s (Add activity, Add sleep and the journal's Time sit between `FormField`s; the draft `d4-sheet-b-add-activity-ax3` shows Start, End, Duration and Distance all as captions, and making only Start and End `textPrimary` would split one card in two inks). `.row`: `callout` `textPrimary`, a row title like a `GroupedRow`'s, for the two uses that sit beside `GroupedRow` titles: Notifications (From, Until) and Bedtime & wake (Weekdays, Weekend). On `surface`: 6.5:1 and 16.2:1. | G2 (`FormField.swift`, `NotificationSettingsView.swift`, `SleepPlannerView.swift`) |
| 2 | `PillButton`'s dimmed state | **Keep, because** the disabled pill is the whole pill at 35 % (`PillButton.disabledOpacity`), the same factor as a disabled `CircleButton`'s icon (`CircleButton.disabledIconOpacity`) and `DotNumeral`'s pending look; disabled controls are exempt from the contrast rule, and the primary dims to `#5B5C5A` on `#0A0C0B` (2.9:1), still a visible button. What a dim may not do is say nothing: **a dimmed primary names its reason** in the caption above it (`ImportBarCaption`, `PinnedActionBar(caption:)`), or in its VoiceOver hint (Add activity's Save hints the first issue). Not a pill edit; D6's held Log out follows it. | — |
| 3 | The "Last time" card at its fade | **Keep, because** the fade is the page's soft top edge (`FocusedSessionView.topFade` 16 pt, `keypadFade` 18 pt, `background` → clear): anything that scrolls under it fades by design, and the card sits at the page's end, so it is under the fade only while scrolling past it. Its rows are 17 Light `textSecondary` (6.5:1 on `surface`), the whole card is the button, and the table is clear of the fade once the page rests. The ui-validator's integrated run at AX3 checks the first row stays readable with the keypad up. | — |
| 4 | Ruler labels at AX3 | **Spec** (draft `d9-rulers-ax3`). The two rulers with three labels (Sleep "0 h · need 8:18 · 10 h", Strain "0 · moderate 10–14 · 21") fit and read well at AX3; the one with five (Today's readiness "0 · low · moderate · high · 100") falls into `RulerLabels`' fallback: a left-aligned run "0 • low • moderate • high" with "100" alone on the next line, detached from the ticks. New rule for `RulerLabels` from AX1 (replacing design.md D4-18's "fewest lines of whole labels joined by ·"): labels are placed by priority, **the two end labels first**, each under its end tick (first leading, last trailing); the interior labels follow only while every label keeps a gap of at least `labelMinGap` (16 pt) to its neighbours on **one** line; a label that doesn't fit is dropped, never joined with "·" and never left-aligned. At AX3 Today's ruler therefore reads "0 … 100". Nothing is lost: the band word is in the numeral's caption ("High") and in the ruler's VoiceOver value ("84, high, on a scale from 0 to 100"; the ruler is one element and ignores its labels). `RulerScale.zone` and `needle` don't change. | G3 (`RulerScale.swift`) |
| 5 | About you's wheel below the fold at AX sizes | **Spec** (draft `d9-about-you-before-ax3`, `-after-ax3`). At AX3 the lead takes 11 lines and the 176-pt wheel starts under the pinned Continue/Skip bar: only the wheel's first line shows, and a wheel does not scale with Dynamic Type anyway. From AX1 the wheel becomes a **menu row**: `GroupedRow.menu(Text("Birth year"), value: Text(year.map(String.init) ?? "Choose")) { Picker … }` in the same `GroupedCard`, items newest first with "Choose your birth year" as the first (nil) item; the row is 56 or more high, scales, and sits above the bar. Below AX1 the wheel stays (it is the better control at the default size). `aboutYou.year` is the row's identifier at AX sizes. The bar is unchanged (Continue is dimmed until a year is chosen, and the row says "Choose"). | G3 (`OnboardingSteps.swift`) |
| 6 | The journal chips at AX5 | **Spec** (draft `d9-journal-strip-ax5`). **Keep the horizontal strip** (14 days is the natural scroll; the selected day starts in view and yesterday plus three more show at AX5), but at AX5 the weekday and number fill their chip edge to edge (the 6 pt inset leaves "Mon" touching its border). From AX1: the chip inset grows to 10 pt, and the strip caps its type at `.accessibility3` (`.dynamicTypeSize(...DynamicTypeSize.accessibility3)`) with `accessibilityShowsLargeContentViewer` per chip, as the header pills cap theirs; each chip keeps its 44-pt minimum and its full VoiceOver date ("Monday, November 16"). A menu row would lose "yesterday is one tap away". | G3 (`JournalViews.swift`) |

Draft observation for row 2: a disabled *secondary* pill at 35 % nearly loses its 20 % outline (see `d6-profile-held`: "Log out" is a faint label, not a visible button). That is why the rule is that a dimmed control is never left to speak for itself: D6's reason line sits beside it.

## 3. Drafts

In `/private/tmp/claude-501/-Users-tim-krebs-Development-Projects-ryft-app/6c6f1e78-44f0-4400-b13c-ddf23bb79e65/scratchpad/gate-drafts/`
(not committed; 402 × 874 pt at 3×, iPhone 17 Pro, iOS 27.2, dark, synthetic data). Built from the real components in a hosted
window with real sheets, by a scratch test (`RyftTests/ZZGateDrafts.swift`, not committed); only `CircleMenu` (and the
"after" sleep-need page) are drawn in the scratch file. At AX3 the type is `.accessibility3`.

| File | Shows | Against the brand board |
|---|---|---|
| `d2-prompt-before.png`, `-ax3` | today's prompt: a 30-pt teal symbol, `ConsentPoint`s, two `surfaceRaised` pills | The board's one teal is the recovery ring; here teal sits on a chart glyph. Chrome is heavy (filled grey pills) |
| `d2-prompt-after.png` | D2: title, lead, one card of four `OnboardingPoint`s, two equal outline pills pinned | Thin rules, ink only, the Consent step's rhythm; the two outlines read as equals (no primary) |
| `d2-prompt-after-ax3.png` | the same at AX3, pinned | **Shows why the bar is inline from AX1**: the bar takes 28 % of the screen and hides all but one point |
| `d3-circle-menu.png`, `-ax3` | the activity detail header with `CircleMenu` | The board's 1-pt circle with a glyph, identical to `CircleButton` |
| `d3-circle-menu-lineup.png`, `-ax3` | the three headers (live workout, My Day, activity detail) with one component, and idle / disabled `CircleMenu` beside idle / disabled `CircleButton` | One circle across the app; the disabled pair match |
| `d4-sheet-b-add-activity.png`, `-ax3` | B's sheet (the real `AddActivitySheet`): close leading, centred title, Save pill trailing | The convention D4 keeps |
| `d4-sheet-c-sleep-need-before.png`, `-ax3` | C's sheet today: 26-pt Light title leading, close trailing, header scrolls | |
| `d4-sheet-c-sleep-need-after.png`, `-ax3` | D4: the same page under the sheet header; the 8:18 numeral is the first thing the eye reads (in the "after" the numeral is drawn as the Light-digit fallback, not the dots: a draft shortcut) | Numbers first: the numeral is no longer under a competing 26-pt title |
| `d6-profile-idle.png`, `d6-profile-held.png`, `d6-profile-held-ax3.png` | D6 on a slice of Profile (Devices and sync, Privacy, the buttons row): Demo data's switch dimmed with the reason as its detail, Withdraw consent busy, the footer, Log out dimmed with the reason under it. (The draft keeps the buttons in a row at AX3; the real page stacks them from AX1.) | Calm: no banner, no spinner over the page; one sentence |
| `d5-report-bar.png`, `-ax3` | D5: Done · Send in the pinned bar with a stand-in keyboard; stacked at AX3 | Pills as the board's: one filled, one outline |
| `d9-rulers.png`, `d9-rulers-ax3.png` | the three rulers; the five-label one breaks at AX3 | Evidence for D9 row 4 |
| `d9-about-you-before-ax3.png`, `-after-ax3.png` | the wheel under the pinned bar; the menu row above it | Evidence for row 5 |
| `d9-journal-strip.png`, `-ax5.png` | the journal's day strip | Evidence for row 6 |

What the comparison showed that changed the spec: the prompt's pinned bar at AX3 (inline from AX1); the dimmed secondary pill that
nearly disappears (D9 row 2, D6's reason line); `ValueChipRow` in Add activity at AX3, where Start and End match the field captions
around them (D9 row 1 became a role, not a global change); the About you wheel hidden under its own bar (row 5).

## 4. Strings the tickets will need (for the localization-editor, G5)

English only. New keys, each with the comment the catalog needs. Everything else the gate touches reuses an existing key:
`Allow`, `Not now`, `Open Profile`, `Done`, `Next`, `Choose`, `Birth year`, `Choose your birth year`, `Share usage analytics?`,
`Share usage analytics`, `Don't share`, `More`, `Add`, `Close`, `Cancel`, `Withdraw consent`, `Log out`, `Demo data`.

| Key | Used by | Comment for the catalog |
|---|---|---|
| `What is counted` | G1, the analytics prompt's first `OnboardingPoint` | Analytics prompt (shown once after onboarding). Heading of the first point; the text under it lists the screens, features, onboarding steps and errors that are counted. |
| `What is not` | G1, the second point | Analytics prompt. Heading of the second point: what is never collected (health data, scores, names, free text). |
| `Your ID` | G1, the third point | Analytics prompt. Heading of the third point: a random ID for this install, never the account or email. |
| `Where it goes` | G1, the fourth point | Analytics prompt. Heading of the fourth point: not used for tracking or ads; processed in the EU. |
| `Waiting for your consent withdrawal to finish.` | F2 (Profile): the Demo data row's detail line while held, the line under Log out, and Log out's VoiceOver hint | Profile while a consent withdrawal is being sent (a few seconds). Why the Demo data switch and Log out are dimmed: either would end the withdrawal before it reached RYFT. |
| `Withdrawing your consent. Syncing stops once RYFT confirms.` | F2: the Privacy group's footer while the request is in flight | Profile → Privacy footer while the withdrawal request is on its way. |
| `Consent withdrawn. Syncing has stopped.` | F2: a VoiceOver announcement, not drawn | VoiceOver announcement when the consent withdrawal was confirmed; Profile's consent row changes at the same time. |

No new string for D2's title, lead, footnote or buttons, for D3, D4, D5, D8 or the About you menu row (it reuses `Birth year`,
`Choose` and `Choose your birth year`). The journal strip needs none.

**Keys that become unused** (G5's `sync-strings --check` removes them; the gate deletes their only callers): the strings of
`MetricGauge.swift` (e.g. "Overall readiness" and its notes), `MetricTile.swift`'s previews (verbatim, so none), `ZoneBar`'s
`Heart-rate zones` label if `ZoneBlock` doesn't share it (check before removing), `ScoreRing`'s previews. `ConsentPoint`'s four texts
stay: `OnboardingPoint` takes the same keys.

**Comments to add while G5 is there** (the plan's list): the ~30 plain-space unit keys and the joined lines R3 left are G5's own
scope; nothing in this note adds to them.

## 5. Test hooks

Unit and hosted tests use `Tokens.resolve(Theme.recovery)` (the teal) and `WindowPixels` (`RyftTests/WindowPixels.swift`) for the
pixel checks; the existing `ProfileSubpagesTests:432–454` ("Report a problem draws no teal") and `JournalNocturneTests:580–595`
are the pattern. Every new test fails against a planted mutant first (the repository's rule).

### 5.1 G1 sweep

- **Source scan** (`NocturneGateTests.noRetiredTokensRemain`): over `Ryft/`, `RyftWidgets/`, `Shared/`, no match of
  `PrimaryButton\(` (the word, not `ImportStepButton`), `TealButtonStyle`, `Theme\.(accent|onAccent|teal|zones)\b`,
  `Theme\.stage`, `SchemePair`, `scheme: \.light`, `preferredColorScheme\(\.light\)`, `· light`, `· de"`. Before G4 it excludes
  `Theme.swift`, `ProfileComponents.swift`, `TrainComponents.swift`, `PreviewSupport.swift` (the definitions); after G4 it excludes nothing.
- **No teal, hosted, default and AX3** (count `recovery` pixels near 24 in the card's frame = 0): Today's `SetupCard`
  (`.preview(empty: true)`), Today's `ImportCard` (`.preview(scenario: .importing)`) with its push ask, `PushPrePromptCard`, the
  coach-mark card, the analytics prompt (the whole sheet), the import's six steps (the existing `ImportNocturneTests` pixel test stays).
  The inverse chip: the current import step's pixel at the capsule's centre is `textPrimary`, its ink `background`.
- **Buttons are pills:** `PushPrePromptCard`'s "Allow" and `SetupCard`'s "Open Profile" are ≥ 52 high, full width in their container (or
  half in a row), the fill `textPrimary`; identifiers `push.allow`, `push.notNow`, `today.setup.openProfile` (new), `coach.next` (kept).
- **The prompt:** (1) both buttons have the same frame size and an outline (the pixel at each button's centre is the background);
  (2) `analytics.share` and `analytics.decline` stay; (3) VoiceOver order: title (header trait), lead, the four points (one element each,
  the glyph hidden), footnote, Share, Don't share; (4) from AX1 the buttons are in the scroll content, below the footnote, and the page
  scrolls to them (hosted AX3: `analytics.share` is reachable by scrolling, no pinned bar: no element with the bar's frame); below AX1
  they are pinned and both inside the window; (5) a swipe is still "Don't share" (`AnalyticsPromptTests`, kept).
- **The Insight tile (D1):** `InsightTile.tint(for:)` table test over every `TrendMetric` and `nil`; hosted: an `hrv` insight has
  `recovery` pixels in the tile, a `sleep_min` one has `metricSleep` pixels and **no** `recovery` pixels, a `steps` one has neither
  (flat). Contrast: `GlowTileKindTests` gets `.idea` cases for `metricSleep` and `metricStrain` (350 × 120 … 420 ≥ 4.5).
- **MetricSpec:** `readiness.color == recovery.color == hrv.color == Theme.recovery`; `ChartStyleTests:52` follows.
- **Card radius:** `WatchSyncHintCard`'s and the coach-mark card's shape radius == `CardSpec.radius` == 22 (hosted, pixel at the corner).
- **Import rename:** the existing UI tests find `import.continue`, `import.done`, `import.chooseAnother`, `import.retryRejected`,
  `import.openHistory`; none changes.

### 5.2 G2 components

- **One circle menu:** a source scan finds no `Menu` whose label draws `CircleButton.diameter` outside `CircleMenu.swift`
  (`Circle().strokeBorder(…CircleButton.borderOpacity…)` appears in `CircleButton.swift` only, besides the two graphics that
  are not buttons: `CheckInboxView`, `HealthIllustration`). Hosted: the three menus' hit frame is 44 × 44 and the ring crop equals a
  `CircleButton`'s (pixels); disabled dims the glyph to 35 %; labels "More", "More", "Add"; each has its identifier
  (`session.more`, `activityDetail.menu`, `myday.add`). UI test (exists for `myday.add`): the menu opens with its three items.
- **One sheet header:** hosted over each sheet root type (a `SheetFrame` sheet, a `SubpageScaffold(isSheet:)` sheet, Add
  activity, Details): the close circle's `minX` < the title's `minX` < the trailing slot's `minX`; the title's centre within 1 pt
  of the header's centre when the slots differ; the header does not scroll (its frame is the same at scroll offset 0 and 200);
  `sheet.close` exists exactly once; at AX3 the title sits under the circles' row, centred. Source scan: `SubpageHeader(` is not
  built with `.close` anywhere but inside `SubpageScaffold` (it maps `.close` to `SheetHeader`); `placement: .keyboard` appears only
  in `AddActivitySheet.swift` and, after G3, nowhere else; no `ToolbarItem(placement: .cancellationAction | .confirmationAction |
  .topBarLeading | .topBarTrailing)` in `Ryft/` (none exists today).
- **Offline line once:** the sentence's source literal appears once in `Ryft/`; hosted, the list layout and the focused layout each
  expose one element with identifier `session.offlineLine` when offline and none when online.
- **Card radius token:** `CardSpec.radius == GroupedListSpec.cardRadius == ProfileLayout.cardRadius == JournalSettingsLayout.cardRadius ==
  StrainLayout.chartRadius == SleepLayout.stageCardRadius == Theme.Metrics.neutralTileRadius == 22`.
- **Deletions:** the compiler for the symbols; a scan that `MetricGauge`, `MetricTile`, `ZoneBar`, `ScoreRing` and
  `workoutDetail(_:` as an `AppState` method are gone, and that `ReduceMotionScanTests`' allowlist has no entry for a missing file.
- **ValueChipRow:** `role: .field` (default) resolves to `textSecondary`, `.row` to `textPrimary` (the `Tokens` ratio on `surface` ≥ 16); Notifications and Bedtime & wake pass `.row`, the other five callers the default (source scan); the existing AX1 stacking tests stay.

### 5.3 G3 AX and keyboard

- **Report a problem (D5), UI test:** focus the message → `report.send` and `report.done` are both `isHittable`; the keyboard has no
  accessory "Done" (`app.toolbars.buttons["Done"]` count 0); `report.done` dismisses the keyboard and Send alone returns; Send with
  text sends. Hosted AX3: Send above Done, both ≥ 44 pt and inside the window with the keypad frame subtracted.
- **Add activity:** UI test: with the keyboard up, `addActivity.save` is hittable (nothing pinned covers it).
- **Rulers (§2.9 row 4):** hosted at AX3 and AX5 for the three rulers: no two label frames intersect or sit closer than 16 pt, each stays inside the ruler's width, the first label's `minX` is the ruler's and the last's `maxX` is the ruler's; Today's five-label ruler shows only its two ends at AX3; Sleep's and Strain's show all three at AX3; no label contains " · ". Default size unchanged (the existing tests).
- **About you (row 5):** hosted AX3 and AX5: no `UIPickerView` in the hierarchy, `aboutYou.year` is a hittable button above the
  pinned bar (`maxY < bar.minY`) without scrolling the page; at the default size the wheel remains.
- **Journal strip (row 6):** hosted AX5: every chip ≥ 44 pt in both directions, the label inside the chip with ≥ 8 pt to each edge (the chip's frame less the text's), the selected chip in view at appear; the VoiceOver label is the full date.

### 5.4 G4 deletion and the lint

- **Build with the symbols gone.** `make lint`: `scripts/check-accent-use.py` **widens only its retired-token rule** (rule 1a:
  `Theme.accent`, `Theme.teal`, the `Accent` and `Teal` assets, `.teal`, `.accentColor`, `TealButtonStyle`, `PrimaryButton`,
  `Theme.zones`, `Theme.stage*`) to all of `Ryft/`, `RyftWidgets/` and `Shared/` (`SIGNAL_DIRS`). Its rule 1b (`Theme.warning`,
  `accentSecondary`, `sage`, `band`; `alert` only in a destructive control) **stays in its four folders**: outside them there are
  22 `Theme.warning`, 19 `Theme.alert`, 2 `accentSecondary` and 7 `Theme.band` uses in 29 files, all legitimate (amber notices,
  coral losses). Self-test: a planted `Theme.accent` in `Features/Profile/` and in `Design/`, a planted `PrimaryButton(` in `Push/` and a
  planted `Color("Teal")` in `RyftWidgets/` fail; the same snippets in a comment or a string pass; a planted `Theme.warning` in
  `Features/Profile/` **passes** (documents the narrower rule). Each rule shown to fail on its plant.
- **Tests that named the symbols** (§1.8) compile and pass unchanged in meaning.
- **`AccentColor`:** a unit test resolves `Color("AccentColor")` to `#F2F1EC`; `PresentedRootTests`' comment changes.
- **Light previews:** the source scan of §5.1 covers them.

## 6. The tickets, by file (one owner per file)

**G1 sweep: 16 files, 59 sites.** Order inside the branch: the import rename first (mechanical), then the rest in any order.
`Features/Profile/FeatureFlagsDebugView.swift` (6), `Features/Profile/AnalyticsOptInSheet.swift` (5 and the redraw, D2),
`Push/PushPrePromptCard.swift` (3), `Features/Today/TodayView.swift` (10), `Design/StatusViews.swift` (11), `Design/CoachMarks.swift` (3),
`Design/RangeBar.swift` (2), `Design/MetricSpec.swift` (3), `Features/Insights/InsightTile.swift` (1, D1), and the import:
`Features/Train/Import/ImportFlowView.swift` (the definition, 1), `ImportPreviewView` (3), `ImportChooseView` (1), `ImportPickView` (1),
`ImportDetectedView` (2), `ImportResultView` (6), `ImportMapView` (1). Dark previews and AX3 previews for each changed view.

**G2 components: 25 files (2 new, 4 deleted), 34 sites, plus 3 in tests.**
- New: `Design/CircleMenu.swift`, `Features/Train/Session/SessionOfflineLine.swift`.
- Circle menu (D3): `Design/CircleButton.swift` (extract `CircleButtonLook`), `Features/Train/Session/SessionView.swift` (`moreMenu`, and the
  offline line), `Features/Activities/ActivityDetailView.swift`, `Features/MyDay/MyDayCard.swift` (`MyDayAddMenu`).
- The offline line once: `Features/Train/Session/FocusedSessionView.swift` (`offlineBanner`, :141) and `SessionView.swift` (:316) both
  build `SessionOfflineLine`: `Label("Offline — every set is saved on this phone and syncs later.", systemImage: "wifi.slash")`,
  `caption` `textSecondary`, at least 28 high, wrapping; the caller gives the horizontal inset (Focused: `columns.padding`; List: none, it
  sits in the 16-pt list). The same key, so no string change; identifier `session.offlineLine`.
- Sheet header (D4): `Design/SubpageScaffold.swift` (the `isSheet` + `.close` path draws a pinned `SheetHeader`), `Design/SheetHeader.swift` (doc).
- Card radius (D8): `Features/Profile/ProfileLayout.swift`, `Features/Journal/JournalSettingsView.swift`, `Features/Strain/StrainLayout.swift`,
  `Features/Sleep/SleepModesLayout.swift`.
- `Design/FormField.swift` (`ValueChipRow(role:)`, D9 row 1), and its two `.row` callers `Features/Profile/NotificationSettingsView.swift` and `Features/Sleep/SleepPlannerView.swift`.
- Deleted: `Design/MetricGauge.swift`, `MetricTile.swift`, `ZoneBar.swift`, `ScoreRing.swift`; edited for them:
  `Features/Profile/DebugComponentCatalog.swift` (six blocks: the four `PrimaryButton` and two `TealButtonStyle` rows, and the
  `MetricTile`, `MetricGauge`, `ZoneBar`, `ScoreRing` sections), `App/AppState.swift` (`workoutDetail`, `cachedWorkoutDetail`), and three
  comments (`Design/NeutralTile.swift`, `Design/OrbitGauge.swift`, `Shared/OrbitGaugeDrawing.swift`; run `scripts/check-shared-types.py`).
- Tests: `ReduceMotionScanTests` (two entries), `OrbitGaugeGeometryTests` (a name), and the new tests of §5.2.

**G3 AX and keyboard: 4 files, 4 sites.** `Features/Profile/ReportProblemView.swift` (D5), `Design/RulerScale.swift` (D9 row 4),
`Features/Onboarding/OnboardingSteps.swift` (D9 row 5, `AboutYouView`), `Features/Journal/JournalViews.swift` (D9 row 6, `JournalDateStrip`).

**G4 deletion: 7 app files, 12 asset changes, 1 script, 14 test files; 27 + 12 + 1 + 37 sites.**
`Design/Theme.swift` (`teal`, `accent`, `onAccent`, `zones`, the four stages and `color(for stage:)`, `graphite`/`slate`/`sage`/`mist`,
`cardRadius`, `tileRadius`, `cardPadding`; `band` returns `recovery`), `Features/Profile/ProfileComponents.swift` (`PrimaryButton`),
`Features/Train/TrainComponents.swift` (`TealButtonStyle`), `Preview/PreviewSupport.swift` (`SchemePair`, `scheme:`),
`Features/Train/Session/SetColumnPreview.swift` (4 light previews), `Features/Train/Session/SessionPager.swift` (1), `Design/PresentedRoot.swift` (the
comment about `AccentColor`). Assets: delete `Accent`, `OnAccent`, `Teal`, `StageDeep`, `StageLight`, `StageREM`, `StageAwake`,
`Graphite`, `Slate`, `Sage`, `Mist` (11), add `AccentColor` (`#F2F1EC`). `scripts/check-accent-use.py` (§5.4). Tests: §1.8's 14 files.
G4 runs after G1 to G3 are merged into the branch: the compiler then lists what is left.

**Follow-ups PR, F2 (D6):** `Features/Profile/ProfileView.swift`, `ProfileViewModel.swift` and the three strings of §4. No gate file.

The files of G1 and G2 do not overlap: `DebugComponentCatalog.swift` is G2's alone (it shows both ticket's old components);
`TodayView.swift`, `StatusViews.swift`, `CoachMarks.swift` and `AnalyticsOptInSheet.swift` are G1's alone (the radius change in
the first three is G1's, the token deletion G4's).

## 7. Deviations and open questions

| # | Brief / plan | This note | Why |
|---|---|---|---|
| DG-1 | The plan counted 54 light previews in 38 files | 8 real light previews in 5 files, 16 `SchemePair` uses in 6 files, 3 `de` previews outside deleted files | The plan's grep counted `SchemePair` blocks and `de` previews with them |
| DG-2 | `ui.md` (analytics): accent on the symbol, `OnboardingScreen(symbol:)` | No symbol, no accent; title "Share usage analytics?" | §2.2 |
| DG-3 | The plan: "the `AccentColor` asset becomes ink" | the asset is *added* | the app's catalog has none |
| DG-4 | The plan: G1 sweeps `ScoreRing` | G2 deletes it | no caller |
| DG-5 | The plan: add a lint for all `Ryft/` | only the retired-token rule widens | §5.4 |
| DG-6 | B and C pushed pages | not decided here: B's pushed pages (`PushedHeader`) centre a small title, C's (`SubpageHeader`) lead with a 26-pt Light one | outside D4's scope; D4 only fixes sheets. The user may want one rule for pushed pages too |

**Questions for the lead / user.** (1) D4 changes ten sheets' headers: please look at `d4-sheet-c-sleep-need-before` and `-after`.
(2) D1 changes a non-recovery insight's hue: confirm that is wanted over keeping the tile teal. (3) DG-6: one header for pushed
pages too?
