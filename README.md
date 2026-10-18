# RYFT — iOS app

*Your whole health.* RYFT reads your Garmin watch's data out of Apple Health, syncs it
to your self-hosted RYFT platform (`../plattform`) and shows daily **Readiness, Sleep,
Recovery and Strain**.

| Today | Sleep | Strain | Insights | Profile |
|---|---|---|---|---|
| ![Today](docs/screenshots/today-dark.png) | ![Sleep](docs/screenshots/sleep-dark.png) | ![Strain](docs/screenshots/strain-dark.png) | ![Insights](docs/screenshots/insights-dark.png) | ![Profile](docs/screenshots/profile-dark.png) |
| ![Today light](docs/screenshots/today-light.png) | ![Sleep week](docs/screenshots/sleep-week-dark.png) | ![Workout](docs/screenshots/workout-dark.png) | ![Insights light](docs/screenshots/insights-light.png) | ![Setup](docs/screenshots/setup-dark.png) |

Screenshots come from the simulator with the built-in mock data (`scripts/screenshots.sh`).

## Requirements

- Xcode 16 or newer (built and tested with Xcode 27.1), iOS 17+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An iPhone for real data. HealthKit has no data in the simulator, which runs in demo mode.

## Setup

```bash
scripts/fetch-fonts.sh      # optional: Satoshi from Fontshare (see "Fonts")
xcodegen generate           # creates Ryft.xcodeproj from project.yml
open Ryft.xcodeproj
```

Or from the command line:

```bash
make build                  # xcodegen + xcodebuild for the simulator
make test                   # unit tests (Swift Testing) on an iPhone 17 Pro simulator
```

### Fonts

Headlines and UI use **Satoshi** (Fontshare, ITF Free Font License). The licence allows
embedding the font in apps but **not** redistributing it through a repository, so the
font files are git-ignored. `scripts/fetch-fonts.sh` downloads Regular/Medium/Bold into
`Ryft/Resources/Fonts/`; they're registered via `UIAppFonts` in `project.yml`. Without
them the app falls back to SF Pro Rounded automatically and still builds.

### Capabilities

`project.yml` already declares these. If you build the project by hand, add in
*Signing & Capabilities*:

- **HealthKit**, with **Background Delivery** checked
- **Background Modes**: **Background fetch** (and **Background processing**)
- BGTask identifier `dev.timkrebs.ryft.refresh` (Info.plist → `BGTaskSchedulerPermittedIdentifiers`)

Signing uses `DEVELOPMENT_TEAM` in `project.yml` (currently the personal team `M77SKHKG63`, automatic
signing). HealthKit apps must be signed, so change this to your own team ID if you fork the
project. Always build `Ryft.xcodeproj` (run `xcodegen generate` first); a plain folder window in
Xcode compiles files in isolation and reports bogus "Cannot find type … in scope" errors.

Garmin Connect must write to Apple Health: *Garmin Connect → More → Settings → Apple Health*.

## Running

### Simulator (demo mode)

Demo mode is on by default in the simulator. The app serves a deterministic 90-day
history (`Ryft/Preview/MockData.swift`) whose "today" matches the brand board. You
can toggle it in **Profile → Data → Demo data**, or with launch arguments:

| Argument | Effect |
|---|---|
| `-demoMode YES/NO` | Force demo data on or off |
| `-appearance dark/light/system` | Colour scheme (dark is the default) |
| `-RyftTab today/sleep/strain/insights/profile` | Initial tab |
| `-RyftSleepMode day/week/month` | Initial Sleep segment |
| `-RyftOpenWorkout YES` | Push the first workout on the Strain tab |

`scripts/screenshots.sh ["iPhone 17 Pro"]` builds the app, launches each tab in both
colour schemes and writes PNGs to `docs/screenshots/`.

### Device

1. Run on your iPhone and allow Health access when asked.
2. Open **Profile**, enter the server URL and API key, then tap **Save & test connection**.
   This switches demo mode off, runs the first sync (90-day backfill) and loads Today.
3. After that, sync runs on every foreground, through HealthKit background delivery
   (sleep, workouts, HRV) and through a `BGAppRefreshTask`.

### Pointing at a local platform

Run the platform on your Mac (see `../plattform/README.md`) and use your Mac's LAN IP
from the phone:

- **Server URL**: `http://<lan-ip>:8082` (the api service)
- **Ingest URL**: `http://<lan-ip>:8081`. With `docker compose` the ingest service runs
  on its own port. Leave this field empty only when ingest and api share one host
  behind the Kubernetes Ingress.
- **API key**: the `API_KEY` the platform was started with (compose default: `dev-api-key-change-me`)

Plain `http://` works for local addresses because `NSAllowsLocalNetworking` is set.
Find the IP with `ipconfig getifaddr en0`.

## Architecture

```
Ryft/
  App/         entry point, AppState (read-side store + disk cache), Settings (Keychain), formatting
  Design/      Theme, Typography, RyftMark and components (ScoreRing, MetricTile, Card,
               SegmentedPicker, StageBar, InsightCard, TrendChart, status views)
  Features/    Today, Sleep, Strain (+ WorkoutDetail), Insights, Profile
  Health/      HealthKitManager: anchored queries, background delivery (from the scaffold)
  Sync/        SyncService: page → upload → persist anchor (from the scaffold)
  Networking/  APIClient, v1 wire models, client-side fallbacks, response cache
  Preview/     MockData + MockDataSource, preview helpers
  Resources/   Fonts (fetched), string catalog
RyftTests/     Swift Testing unit tests + JSON fixtures for every API shape
scripts/       fetch-fonts.sh, render-icon.swift, screenshots.sh
```

- **Data flow.** `SyncService` drains HealthKit into `POST /v1/sync`. `AppState` reads the
  API through a `RyftDataSource` (`APIClient` live, `MockDataSource` in demo mode and previews).
- **Offline.** The last successful Today payload is written to `Caches/ryft-responses/`
  and shown immediately at launch, with an "Updated 5 min ago" line.
- **Graceful degradation.** Fields can be `null` while the platform calibrates, and every
  view shows "–". If the platform doesn't serve `/v1/trends`, `/v1/sleep`,
  `/v1/insights` or `/v1/workouts/{id}` yet, the app derives them from `/v1/days`
  (`Networking/Derived.swift`). Without `readiness`/`state` it uses recovery and the
  recovery bands. Without `DayDetail.sleep` it rebuilds the night from `score.details`.
- **App icon.** `make icon` compiles `scripts/render-icon.swift` together with
  `Ryft/Design/RyftMark.swift` and renders the light, dark and tinted 1024 px PNGs with
  `ImageRenderer`, so the icon and the in-app mark share one geometry.
