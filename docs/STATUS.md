# Status — 2026-10-18

## Done

- **Brand**: `Theme` palette as asset-catalog colour sets with light variants; `Font.ryft`
  (Satoshi with SF Pro Rounded fallback, Dynamic Type); vector `RyftMark`; wordmark header.
- **App icon**: light, dark and tinted 1024 px PNGs rendered from `RyftMark` by
  `scripts/render-icon.swift` (`make icon`), with no alpha channel.
- **Components**: RyftMark, RyftHeader, ScoreRing (glow, 0.8 s animate-in, count-up,
  Reduce Motion aware), MetricTile, Card, SegmentedPicker, StageBar, InsightCard,
  TrendChart (scrubbing, baseline), InlineMessage, UpdatedLabel, SetupCard. Each has a
  `#Preview` that renders dark and light side by side.
- **Screens**:
  - Today: greeting, state sentence, readiness ring, tiles that navigate, 7-day trend, setup state.
  - Sleep: Day view with stages, quality and details, plus a ‹ › night picker. Week/Month
    views with stacked bars, averages and bedtime consistency.
  - Strain: week strip, strain ring, HR zones, activities, and `WorkoutDetailView` with an HR chart.
  - Insights: dismissible-for-the-day cards, plus 7/30/90-day charts for all six metrics
    (HRV with a 30-day baseline).
  - Profile: account and connection test, body settings and recompute, Health and sync
    controls, full re-sync with confirmation, demo toggle, appearance, about.
  - Every screen has the RYFT header and pull-to-refresh (sync + reload), plus previews in dark and light.
- **Data**: v1 wire models with null-tolerant, lenient decoding. New endpoints. A
  `RyftDataSource` abstraction. Client-side fallbacks for endpoints and fields the
  platform doesn't serve yet. Today snapshot cached on disk.
- **Sync**: the scaffold's HealthKit and sync design is unchanged. The only addition is a
  read-only `HealthKitManager+Status` helper for the Profile screen.
- **Tests**: 35 Swift Testing tests (4 suites). They cover day formatting, decoding of
  every API shape from fixtures (including the current pre-v1 backend payload),
  state → sentence, and stage percentage maths.
- **Build**: `xcodegen generate && xcodebuild … build` succeeds with zero warnings in app code.

## Open

- **Not yet verified on a device against a running platform.** The flow "HealthKit
  prompt → first sync → Today shows real numbers" is wired but was only exercised in the
  simulator with mock data. HealthKit doesn't work there.
- `../plattform/docs/API.md` didn't exist when this was built. The models follow the
  contract in the prompt. The running backend currently serves only `/v1/me`,
  `/v1/days`, `/v1/days/{day}`, `/v1/workouts` and `/v1/recompute`, without
  `readiness`/`state` or `DayDetail.sleep`, so the app uses the fallbacks. Check the
  field formats once the platform implements them:
  - `efficiency` and `pct` are accepted as 0–1 or 0–100.
  - `SleepNight.stages` is accepted as a list or a map.
  - `SleepNight.start` is optional, but bedtime consistency needs it.
- German localisation. Strings go through `String(localized:)` and `LocalizedStringKey`,
  and `Localizable.xcstrings` exists but has no translations yet. The calibrating
  sentence uses a simple singular/plural branch and should become a plural variation.
- Insight dismissal is stored per device (UserDefaults), not synced to the platform.

## Known issues

- Satoshi isn't committed because of its licence (see README). Fresh clones render in SF
  Pro Rounded until `scripts/fetch-fonts.sh` runs.
- Xcode previews couldn't be rendered from the folder workspace used during development.
  Screens were checked in the simulator instead. Open `Ryft.xcodeproj` to use the canvas.
- The ring and strain numbers inside rings use fixed sizes so they fit the ring geometry.
  They don't grow with the largest Dynamic Type sizes; the surrounding text does.
- On iOS 26+ the tab bar uses the system Liquid Glass style. The opaque Graphite bar
  from the board is applied on iOS 17–18 only.
- "Open Health permissions" opens the Health app. iOS offers no deep link to the per-app
  read permissions screen.
- The "Recovery" tile on Today opens Insights (where the recovery trend lives), because
  Recovery has no tab of its own.
