# Status — 2026-10-21

## Sync engine: order, first score first, pipelined (sync brief §2, first part)

- **`SyncEngine`** (actor) reads, maps, encodes and uploads; `SyncService` stays the
  observable face. Streams go night-first (sleep, HRV, resting HR, breathing rate, SpO₂,
  workouts, then heart rate, steps, energy, VO₂ max).
- **First score first:** an account's first sync sends the last 3 days of every stream
  and stops; the coordinator scores and refreshes Today, then continues with the anchored
  90-day backfill (`.backlog` run).
- **Pipelined, pages by bytes:** the next page is read while the current one uploads
  (one ahead, never more); pages hold what fits 2 MB at the measured bytes per record;
  `413` still halves.
- **State per account** (`SyncEngineState`): phase, stream, per-stream counts, bytes and
  date range, last error with request ID. The import card and Sync details build on it.

**Finding #11 of the brief (sync work on the main thread) did not hold.** The brief says
the target builds with `SWIFT_APPROACHABLE_CONCURRENCY = YES`; only the widget and UI-test
targets do. In the app target a nonisolated `async` function runs on the global executor,
so `HealthKitManager`'s mapping and `APIClient`'s encoding already ran off the main
thread. A probe against `main` (a `HealthStore` recording `Thread.isMainThread` in
`nextPage`, driven by the `@MainActor` `SyncService`) confirmed it: off the main thread.
The engine keeps it that way whatever the build setting becomes, and
`readingMappingEncodingAndUploadingStayOffTheMainThread` guards it. Instruments numbers on
your iPhone are still open (perf section, later).

Verified: 453 unit tests (+ order, nothing on the main thread, the two-phase backfill,
one page ahead and never more, page sizes from measured bytes, persisted state and
errors, a full re-sync, the backlog run and that a cancelled run doesn't continue).

## Account gates and honest errors (sync brief §1, `CLAUDE_FOLLOWUP_SYNC_403.md` §1–§3)

**Root cause of "RYFT didn't accept your sign-in · HTTP 403"** (from the platform's
`docs/STATUS.md`, incident 2026-10-20, so the `kubectl` steps of the 403 brief weren't
needed): every `POST /v1/sync` of the one account (Apple and email reach the API as the
same user) answered `403 consent_required`. Consent is enforced on sync, nobody had a
consent yet, and the app showed every `401` **and** `403` as a sign-in failure. The
invite gate was off; there was no second account. The platform has since put both
gates in `warn` until this app's screens are on TestFlight.

What changed:
- **Errors say what is wrong.** `APIError.http` carries the body's `code`. `401` →
  "Your session has ended" (only after the refresh failed); `403 invite_required` /
  `consent_required` → a gate, reported to `APIStatus`, never shown as a failure; a
  code-less `403` → "This is built into RYFT and can't be changed". Details show
  status, code and the request ID exactly as received.
- **Gates.** `X-RYFT-Gate` on a served request (warn mode) is reported like a refusal.
  After a hard `403 invite_required`, only onboarding's routes go out. A sync refused at
  a gate pauses (`SyncService.pausedFor`), keeps the page's anchor and doesn't count as a
  failure.
- **`OnboardingCoordinator`** decides from `GET /v1/me`, `GET /v1/config` and
  `GET /v1/me/sync` on every launch and sign-in: invite (only when the platform says its
  gate applies), consent (policy in force), about you (birth year → the platform's max-HR
  estimate). Full screen on an account's first run (per account), a sheet over the tabs
  afterwards; Today shows "Action needed" while one is put off. Nothing syncs before
  consent or while the account is unknown, the gate is re-checked before every page, and
  after agreeing the first sync starts at once. Train keeps writes refused at a gate.
- **`account_hint`** → "This is a new RYFT account" once per account, with "Use the other
  account" (signs out).
- **Profile:** Sign-in methods (identities, "Add Sign in with Apple" through Supabase
  identity linking), Privacy (consent date and version, withdraw), birth year and the
  max-HR source with "Use the estimate".
- **Every request** sends `X-RYFT-Device-ID`; every sync `app_version`, `os_version` and
  `source_bundle_id`. Mirror: the Beta and "Accounts and sync state" shapes, contract
  check extended to `SyncStatus` and `ModelInfo`.

Verified: 441 unit tests (56 new: the status matrix, the onboarding decision table, the
flow, no sync before consent or an unknown account, a gate between pages, account switch,
invite link, the review's edge cases), the contract check (24
examples), strict build, `make lint`, `make style`. Screens captured in the simulator
(dark/light, en/de): `docs/screenshots/onboarding-*.png`.

**Not verified on a device**, please run on your iPhone (Debug build, production):
1. Launch: the consent sheet appears over Today (your account has no consent). Agree →
   the sync runs; Profile → Privacy shows today's date and policy `2026-10-20`.
2. Log out → Continue with Apple → straight to Today (same account), no "log in again".
3. Profile → Sign-in methods lists both methods.
4. Profile → Privacy → Withdraw → Today says "Action needed"; Review → agree again.

**Your steps:**
- Supabase → Authentication → Settings → **Manual Linking** on, for "Add Sign in with
  Apple" (without it the app says linking isn't switched on yet).
- Once this is on TestFlight: both gates `on` on the platform (its `STATUS.md` →
  Accounts and sync, step 6).
- `ryftapp.de/support` is named in the account-hint sheet; it has to exist.
- **`Ryft/` and `RyftTests/` are classic groups, not synchronized folders** (only
  `RyftWidgets/` and `RyftUITests/` are). New files there need the project file, which
  sessions don't edit, so this work went into existing files. In Xcode: select the
  `Ryft` group → right-click → **Convert to Folder**, the same for `RyftTests`, commit
  the project. Later work can then split files.
- `Package.resolved` on `main` doesn't match the package requirements (dependabot's
  swift-crypto 5.0.1; the resolver picks 4.5.2 and adds swift-issue-reporting). CI
  resolves on its own; open the project in Xcode once and commit what it writes.

Tooling for sessions without Xcode: `make strings` (`scripts/sync-strings.py`) syncs the
string catalog from the last build, as Xcode does on build; `scripts/screenshots.sh`
also takes the Debug screens (`-RyftScreen consent`, …).

## Platform wiring — every API.md endpoint has a caller

The follow-up brief `CLAUDE_FOLLOWUP_PLATFORM_WIRING.md` was written against an older
snapshot. Its §0 (the `SyncCoordinator` step) had already landed as `8fc32bd`, and remote
config and push already existed in a first form. Each section below adjusts the existing
code and ends in its own commit:

| § | Commit | What changed |
| --- | --- | --- |
| 0 | `122c66a` | Associated Domains kept empty (your change) and `CLAUDE.md` committed; background identifiers and modes checked against the code |
| 1 | `d343762` | Mirror: the M4 sleep fields, `SleepPlan`, five trend metrics, open `InsightKind`, the journal types, eight `PlatformAPI` methods, fixtures from API.md, `MirrorDecodingTests` |
| 2 | `2bb6922` | Flags: TTL counts from `evaluated_at`, a cache per account, a flip waits for the next screen appearance; `physiology.card` / `coach.enabled` reserved (TODO). The physiology card from the previous pass was removed, as the brief asks. |
| 3 | `988270d` | Push: the capability (`aps-environment`); the environment read from the signed profile; the one-sentence pre-prompt that returns once after 14 days; the registration record in SwiftData; DELETE before sign-out and account deletion; a 25 s silent-push budget; categories without actions; the Notifications screen explains the rollout when the flag is off |
| 4 | `92108ad` | Sleep: need bar, quality / restorative / consistency tiles, nap chip, bedtime strip, Planner (`sleep.planner`), baseline source in Profile, insight kinds |
| 5 | `61f891b` | Journal: Today card and sheet, Profile → Journal, Insights → Behaviors; hidden while `/v1/behaviors` answers `404` |
| 6 | `f2fe438` | One `AppRoute` parser for links, pushes and insights; the AASA request |
| 7 | `318d769` | Strain: cardio / strength split, workout → session link, record wording from `PR_BODY_*` |
| 8 | `111063f` | Status: `422` inline, `409` id taken, `404` not live, `204` no plan |

**Tests:** 385, all green. They ran in Xcode through its test runner, which works from
this session; only command-line `xcodebuild test` doesn't. **Build:** zero warnings in
our targets. **Strings:** English and German complete (`make lint`).

### Endpoint → screen coverage (API.md → Screens → endpoints)

| Screen | Endpoint | Where in the app |
| --- | --- | --- |
| Today | `GET /v1/days/{today}` | `TodayView` / `TodayViewModel` (ring, tiles, HRV, RHR, need and debt) ✓ |
| Today — Trends | `GET /v1/trends?metric=readiness&range=7d` | Today trends card ✓ |
| Sleep — Day | `GET /v1/days/{day}` → `sleep` | `SleepDaySection`: total, stages, hypnogram, need bar, tiles, nap ✓ |
| Sleep — Week / Month | `GET /v1/sleep?range=` | `SleepRangeSection`: bars, averages, consistency, bedtime strip, nights ✓ |
| Sleep — Planner | `GET /v1/sleep/plan?wake=` | `SleepPlannerSection` (`sleep.planner`) ✓ |
| Strain | `GET /v1/days/{day}` → `score.strain`, `strain`, `workouts` | `StrainView`: gauge, cardio / strength split, zones, activities ✓ |
| Strain — workout | `GET /v1/workouts/{id}` | `WorkoutDetailView`, with the link to its session ✓ |
| Insights | `GET /v1/insights`, `GET /v1/trends` | `InsightsView`: kind icons, card → chart, all 14 metrics ✓ |
| Profile | `GET` / `PATCH /v1/me`, `POST /v1/recompute` | `ProfileView`: max HR, baseline source, Use the learned value, Apply & recompute ✓ |
| Profile — Delete account | `DELETE /v1/me` | `AuthService.deleteAccount` (push deleted first) ✓ |
| Profile — Notifications | `User.notifications`, `PATCH /v1/me/notifications` | `NotificationSettingsView` ✓ |
| (launch, every 6 h) | `GET /v1/config` | `FlagStore` + `FeatureFlags` ✓ |
| (after first sync, token change, sign-out) | `POST` / `DELETE /v1/devices/{id}/push` | `PushRegistrar` ✓ |
| Notifications | push payloads | `AppDelegate`, `PushCategories`, 17 loc-keys in en and de ✓ (API.md lists 17, the brief said 18) |
| (after Sign in with Apple) | `POST /v1/me/apple-authorization` | `AuthService` ✓ |
| Strain — Train | `GET /v1/plans/today`, `PUT /v1/sessions/{id}`, `…/complete` | `TrainSection`, `SessionController` ✓ |
| Strain — Train: plans | `/v1/plans…` | `PlansView`, `PlanDetailView`, `PlanBuilderView` ✓ |
| Journal | `GET` / `PUT /v1/journal/{day}` | `JournalCard`, `JournalSheet` ✓ (hidden until M5) |
| Insights — Behaviors | `GET /v1/behaviors/impact` | `BehaviorsSection` ✓ (hidden until M5) |
| Profile — Journal | `GET` / `PATCH` / `POST /v1/behaviors`, `DELETE /v1/behaviors/{id}` | `JournalSettingsView` ✓ (hidden until M5) |
| Strain — Train: library, history | `/v1/exercises…`, `GET /v1/sessions` | `ExerciseDetailView`, `TrainHistoryView` ✓ |
| (background) | `POST /v1/sync` | `SyncService` through `SyncCoordinator` ✓ |

`GET /v1/days?from&to` feeds the 90-day history. `GET /v1/workouts?from&to` is used by
the data export.

### Push setup

- **Capability:** Push Notifications (`aps-environment` `development`; the export
  re-signs it as production). `PushRegistration.env` comes from the embedded profile's
  `aps-environment`.
- **Before a push can arrive, someone has to act on the platform side:** turn
  `push.enabled` on and allow-list the account (`../plattform` `OPERATIONS.md` → Feature
  flags). Until then the pre-prompt stays hidden, and Notifications explains the rollout.
- **Later:** the Notification Service Extension, which adds the ring image
  (`RyftNotificationService/` sources and the tested `NotificationRing`). Add it as a
  target in Xcode when wanted.

### Waiting for M5 deployment

The journal endpoints are committed on the platform but not deployed. Production answers
`404`, so the Today card, Profile → Journal and Insights → Behaviors stay hidden with no
error. Against compose (or in demo mode) all three show up.

### Universal links

No `associated-domains` entitlement until `ryftapp.de` hosts an AASA with the app's paths (an empty array blocked launching; `make check-entitlements` now guards it). The
request is in `docs/API_REQUESTS.md`, with app ID `M77SKHKG63.dev.timkrebs.ryft` and the
paths. `ryft://` links and notification taps work now.

### Device verification (brief §9) — not done here; needs your iPhone

I have no device. Everything above is verified in unit tests and Xcode previews only. To
verify on a Debug build:

1. Sign in, sync, see the pre-prompt, Allow. Profile → Developer shows `POST 204`.
2. With `push.enabled` on for the account, the next `MORNING_SCORE` arrives in German.
   The silent refresh updates Today first, and a tap opens that day.
3. Planner with three bedtimes, and the need bar on a real night.
4. Journal saved for yesterday and read back. Create and delete one custom behavior.
   This needs M5 deployed, or compose.
5. Notification toggles round-trip. Sign-out deletes the token (`204`).

Screenshots go here once taken. `make check-swift` in `../plattform` (it decodes this
mirror against a running stack) is for you to run, since the platform repo is read-only
for me.

**Preview captures, compared with the board (dark and light):**
- Sleep Day with the need bar
- Week with the bedtime strip
- Planner
- Journal sheet
- Behaviors section
- Notifications settings


## Platform parity (WHOOP's iOS stack) — §1–§9 written; device and CI checks open

### Done-when checklist (brief §10)

| Criterion | State |
| --- | --- |
| Every view model and state machine tested | ✅ 318 unit tests, all green in Xcode |
| Offline history works | ✅ in tests (`RepositoryOfflineTests`, SwiftData read models); ⏳ device check: airplane mode, relaunch, scroll 90 days |
| Sandbox push arrives | ⏳ capability and registration done; device check open (Platform wiring → Device verification) |
| A universal link opens the right screen | ✅ router tested for every path; `ryft://` works now; ⛔ `https://` needs `applinks:ryftapp.de` and the platform's AASA paths |
| Flags toggle without a rebuild | ✅ observation test; ⏳ device check: flip a flag on the platform, return to the app |
| CI green, one nightly TestFlight build | ⏳ workflows written, not yet run: no GitHub remote push from here, and the ASC secrets and paid team are missing (`docs/CI.md`) |
| Docs: ARCHITECTURE.md, CI.md, STATUS.md | ✅ |

### §9 — CI/CD

- `.xcode-version` (27.1) and four workflows in `.github/workflows/`:
  - `ios.yml`: PRs and main
  - `nightly.yml`: Internal group
  - `weekly.yml`: External group, Mondays 07:00 Berlin
  - `release.yml`: manual, raises `VERSION`

  They share `_testflight.yml` and `.github/actions/setup`.
- Signing: `-allowProvisioningUpdates` with the ASC API key (not fastlane match). The
  secrets are `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8`.
- `scripts/testflight.py` handles What to Test, groups and beta review over the App
  Store Connect API, with the standard library only.
- `VERSION` is the marketing version. It's passed to xcodebuild, so the pbxproj isn't
  edited. The build number is the UTC build time, `yyyyMMdd.HHmmss`, from
  `scripts/build-number.sh`, which CI and `make archive` share.
- `.swiftformat` and `.swiftlint.yml`, plus `make style` and `make format`.
- **`.gitignore` no longer ignores `*.xcodeproj/`.** Until now the project wasn't in
  git, so a fresh clone (or CI) had nothing to build. It's committed with this section;
  `xcuserdata` stays ignored.
- **Not verified here:** SwiftFormat and SwiftLint weren't run locally (the agent's
  shell was unavailable at the time). Run `make style` once; if it reports anything,
  `make format` and commit. The workflows haven't run yet: the first PR is the test.
  The macOS runner image needs Xcode 27.1; otherwise change `runs-on` or
  `.xcode-version`.

### §1–§8

Design notes are in `docs/ARCHITECTURE.md` (one section per brief section). Each
section is its own commit, and every commit has green tests and zero warnings in our
code.

| § | What | Tests |
| --- | --- | --- |
| 1 | Protocol seams, `AppEnvironment` live / preview / test | `EnvironmentTests` |
| 2 | `@Observable` view model per screen | `ViewModelTests` |
| 3 | SwiftData read models behind `Repository`, TTLs, migration, wipe on sign-out | `RepositoryTests` |
| 4 | `SyncCoordinator` actor, `BGProcessingTask` compaction, calendar reminders | `SyncCoordinatorTests` |
| 5 | GameplayKit state machines: sync, auth, live session, Health onboarding | `StateMachine*Tests` |
| 6 | Component catalog (Debug), `Theme.Motion`, coach marks, Health illustration | previews |
| 7 | Push registration, silent refresh, categories, loc-keys, deep links, Profile → Notifications | `PushAndDeepLinkTests` (36) |
| 8 | `FlagStore` + `FeatureFlags` actor: `GET /v1/config` at launch and every 6 h, SwiftData cache, Debug overrides, gates | `FeatureFlagsTests` (15) |

- **Tests:** 318 pass, run in Xcode. `RepositoryOfflineTests` used the real time and failed after 23:00 (the advanced hour crossed midnight); it now uses a fixed morning time.
- **§5 flake fixed:** `LocalSessionExercise.sets` is an unordered SwiftData relationship, so
  the rest-timer test now picks two distinct sets.
- **In-memory stores:** each `TrainStore(inMemory:)` now gets its own name, so parallel
  tests no longer share one.

### §7 and §8 — open items

Superseded by **Platform wiring** above: push setup, the AASA, the Notification
Service Extension, and the flags that are only reserved.

## Chart language and instrument components — done

The brief's sections 1–2 are done; its Today layout section never arrived.

- **Chart language.** `ChartStyle` + `MetricSpec`, documented in `docs/CHART_STYLE.md`.
  - Applied to the trend charts (Today, Insights), sleep per night, both hypnograms,
    workout heart rate and e1RM.
  - catmullRom, area fills, gradients, the ring glow and count-ups are removed.
- **New components** (`Design/`), each with dark and light previews:
  - `MetricGauge`: now on Today (readiness) and Strain (day strain), replacing the 220 /
    200 pt rings.
  - `RangeBar`, `DeltaLabel`.
  - `ZoneBar`: replaces `ZoneMinutesView`.
  - `MiniHypnogram`.
- **Colours.** `MetricStrain` (blue) and `MetricSleep` (indigo) were added, ≥ 4.5:1 in
  both appearances.
- **Not placed yet**: `RangeBar` and `MiniHypnogram` wait for the Today layout.
- **API requests**: strain band, strain target, baseline σ, resp / SpO₂ trends (see
  `docs/API_REQUESTS.md`). Until then the gauge's target arc stays empty and the bands use
  the 30-day min / max.
- **Tests**: 10 new chart tests (scales, ticks, deltas, range stats).
  - A parameterized SleepMath test used dictionaries as arguments, so its case names
    changed per process and Xcode waited for results that never came. It now uses arrays.
  - Verified in Xcode: 174 passed, before that fix.
  - Command-line `xcodebuild test` can't run from the agent's environment: the simulator
    launch fails with "Pseudo Terminal Setup Error" (EPERM), and xcodebuild then doesn't
    exit. Please run the tests once in Xcode.
- **Strings**: German complete, stale keys removed (`make lint` passes).

## App Store readiness — done

Audited on **2026-10-19** with **Xcode 27.1 (27A9275), iOS 27.1 SDK**. The audit used
Apple's current documentation, not memory. The checklist is `docs/APP_STORE.md`, and it has
no open *fix* rows.

- **Privacy** (`7cd708e`):
  - `PrivacyInfo.xcprivacy`: no tracking, 7 linked data types, UserDefaults `CA92.1`.
  - Health purpose string in en and de; the unused write string is removed.
  - A "Connect Apple Health" explanation comes before the permission prompt.
  - "No Health data yet" hint when access is denied.
  - Privacy Policy and Terms in in-app Safari (Welcome, Create account, About).
  - Export my data (JSON via the share sheet).
  - Wellness disclaimer in About and on Insights.
- **Release hygiene** (`9213d79`):
  - `ITSAppUsesNonExemptEncryption = NO`; background modes `fetch` only.
  - Graphite launch screen; no Mac or Vision Pro.
  - Associated Domains `applinks:ryftapp.de`, with the universal-link auth callback.
  - Version 1.0.0 with a timestamp build number.
  - `make archive` with `scripts/ExportOptions.plist`, and a Licences screen.
- **Accessibility** (`89e3d9a`):
  - Audio Graph descriptors on the trend, e1RM and heart-rate charts.
  - A recovery band word on Today.
  - Light-mode contrast ≥ 4.5:1, with `OnAccent` for labels on teal.
  - 44 pt targets.
  - Today tiles stack at AX sizes.
  - German complete; `make lint` → 0 problems.
- **Smoke UI test**: `RyftUITests/StoreSmokeUITests.swift`.
  - The demo walkthrough passes.
  - The reviewer walkthrough (log in → tabs → Delete account → Cancel) skips without
    credentials.
  - The Train UI test still passes.
- **Tests**: 164 unit tests and 2 UI tests passing, 1 skipped (iPhone 18 Pro simulator).
  Zero warnings.

## App Store readiness — open / user only

Only the account holder can do these; the full list is in `docs/APP_STORE.md` §6.

- **Uploadable ipa: not produced.** `make archive` builds and verifies an unsigned Release
  archive. The export needs the paid Developer Program team (Personal Team can't sign
  HealthKit background delivery, Sign in with Apple or Associated Domains for distribution).
- **Privacy report**: Organizer → Generate Privacy Report on the signed archive. Compare it
  with §1.
- **Reviewer demo account** (30 days of synthetic data). Then run
  `testReviewerWalkthroughCancelsDeletion` with `TEST_RUNNER_RYFT_DEMO_EMAIL` /
  `TEST_RUNNER_RYFT_DEMO_PASSWORD`.
- **Simulator only so far**: HealthKit permission flow, Instruments memory peak on the first
  90-day sync, Network Link Conditioner, one iPad run (compatibility mode).
- **Website**: `/privacy`, `/terms` and `/support` on ryftapp.de, and the AASA file for
  `/auth/*`.
- **App Store Connect**: age rating, App Privacy, Accessibility Nutrition Labels, DSA trader
  status, review notes.

## Go-live pass (accounts, live host) — done

This pass checked `CLAUDE_FOLLOWUP_APP_GOLIVE.md` against what an earlier session had built.
It added the missing pieces and brought the models in line with the current `API.md`,
which now includes Train.

- **Config.** The real Supabase URL and publishable key are in
  `Config/Production.xcconfig`.
  - `PlatformConfig` validates all three values. Placeholders and unexpanded values count as
    missing, and Release also requires HTTPS.
  - A missing value stops Debug at launch; Release shows only a "misconfigured build" screen.
    There is no fallback host.
  - ATS is HTTPS-only in Release. `Info.plist` is preprocessed, and only `Debug.xcconfig`
    turns `NSAllowsLocalNetworking` on. Verified in the built Debug and Release plists.
  - The Info.plist strings are now manual catalog entries, with German for the Health prompt.
- **Auth gate.** `AuthService.state` is `.restoring` / `.signedOut` / `.signedIn`.
  - `.restoring` shows a splash with the mark, and is skipped when a session is stored.
  - The cause of the earlier flaky `authFailureOnTokenSignsOut` is fixed: a late
    `.initialSession` re-applied the stored session after a sign-out.
- **Sign-out reasons.** A second `401`, a revoked refresh token or a token failure show "You
  were signed out" on Welcome.
  - After a deletion Welcome says what was erased, and that the sign-in removal "will finish
    in the background" when `auth_user_deleted` is false.
  - A `503` on delete says nothing was deleted.
- **Apple.** After Sign in with Apple the app sends `POST /v1/me/apple-authorization`, once,
  with the authorization code.
  - `422` and `501` are ignored; a `503` is retried once. The code is never logged.
  - Also mirrored: `AccountDeleted.apple_token_revoked` and `AppleAuthorization`.
- **Check your inbox** gained "Use another email".
- **Requests** send `Accept-Language`, so exercise names follow the phone's language.
- **ConnectivityMonitor**:
  - Offline, nothing is requested and Today shows an "Offline" pill.
  - Reconnecting syncs, refreshes and replays Train's queue.
- **Sync**:
  - HealthKit anchors are keyed by the signed-in user id; old anchors migrate once.
  - After `days_touched`, the app waits ~3 s and reloads Today.
  - "Updated hh:mm" comes from `computed_at`.
- **Contract (`API.md` Swift mirror)**:
  - `DailyScore.strength_min` / `volume_kg`, `DayStrain.muscular_trimp` / `sessions`,
    `Trend.from` / `to`.
  - All of Train: `Muscle` enum, `name_en` / `name_de`, `ExerciseInput`, `SessionSet`,
    `SessionSummary`, `PlanSummary`, `PlansOverview`, `PlanTarget` fields, `PR.set_id` /
    `session_id`, `ExerciseHistorySession`, `E1RMPoint`, `SessionComplete { ended_at }`.
  - Naming difference: `Session` is `TrainSession`, because Supabase's `Session` is taken.
  - Fixtures were rebuilt from the API.md examples.
- **Bugs fixed by the contract.** A finished session was PUT as `completed`, which the
  platform refuses.
  - It is now PUT as `in_progress` until `…/complete` succeeds, and complete sends
    `ended_at`.
  - Pause is `DELETE /v1/plans/enrollment` and resume enrols again. The paused plan is
    remembered locally: see `docs/API_REQUESTS.md`.
  - The Today card's "load" is the session's `strain`.
- **Tests**: 163 Swift Testing tests plus the UI test, all passing on the iPhone 18 Pro
  simulator.
  - New: platform config, the auth state machine and notices, the Apple code, plain-text
    `429`, the `409` session body, `Accept-Language`, a single `503` retry, anchors per user.
  - Fixtures for every new shape.
- **German** for the new strings.
- **Preview captures** in `docs/screenshots/`: Welcome (dark, light, signed-out notice),
  Create account, Log in, Today (dark, light, offline), Profile, all in both schemes.
- **Build**: zero warnings.

## Go-live pass — open / blocked

- **§6 device run: not done.** It needs a real iPhone with the Release config. Every device
  build still fails at signing: `DEVELOPMENT_TEAM` is a free Personal Team, which can't
  provision Sign in with Apple. Not run yet:
  - fresh install → create account → confirm → HealthKit → first sync
  - relaunch
  - log out / Apple sign-in
  - airplane mode
  - delete account
  - recording the request IDs of the first `/v1/sync` and `/v1/days/{today}`
- **`make check-swift` in `../plattform`**: please run it against the new models. It compiles
  the Swift mirror and decodes a live stack.
- **Release configuration → `Config/Production.xcconfig`** must be set in Xcode (Project →
  Info → Configurations). Until then Release uses the git-ignored `Config/Release.xcconfig`,
  which includes Production, so a fresh clone needs `make config`.
- **Supabase project**: please confirm `ryft://auth/callback` is in Authentication → URL
  Configuration → Redirect URLs.

## M3b Train — done

Built against the M3b shapes and the platform's Train brief
(`plattform/CLAUDE_FOLLOWUP_TRAIN.md`), because `API.md` has no Train section yet. Open
contract points are in `docs/API_REQUESTS.md`.

- **Wire models** in `Networking/Models.swift`: Exercise, Plan / PlanDay / PlanExercise,
  Progression, Enrollment, PlanCatalog, PlanToday / PlanTarget, TrainSession / exercises /
  TrainSet, PersonalRecord, CompletedSession (Session + `prs`), ExerciseHistory.
  - Workout gains `session_id` and `muscular_load`; DayStrain gains `sessions`.
  - Unknown enum values fall back to a neutral case.
- **Endpoints** (`APIClient+Train.swift`):
  - exercises (+ custom, history)
  - plans (list, detail, PUT, DELETE, enrol, leave, pause)
  - `plans/today` (`204` → nil)
  - sessions (list, GET, PUT with `409` → `.conflict`, complete, DELETE)
  - `APIClient.exchange(accepting:)` returns accepted statuses with their body.
- **Local-first store** (SwiftData, `Train/Model/`):
  - `LocalSession`, `LocalSessionExercise`, `LocalSet`, `CachedExercise`, `CachedPlan`, plus
    a persisted outbox (`PendingTrainOp`).
  - Wiped on log out and account switch.
- **TrainSyncService**:
  - 2 s debounced whole-document PUT; one queued PUT per session.
  - Ordered replay on reconnect (`NWPathMonitor`, app active).
  - `409` → merge by set id (later `updated_at` wins, the local set on a tie; locally deleted
    sets stay deleted) → PUT again, at most 3 rounds.
  - Finish → PUT + complete. Offline it marks `pendingCompletion` and the UI says "will sync".
  - 4xx ops are set aside; 401/408/429/5xx and transport errors keep the queue.
- **TrainLibrary**: exercises, plans, enrolment, today's plan and recent sessions, cached for
  offline browsing and refreshed on app active.
- **Screens** (`Features/Train/`), each with dark and light `#Preview`s:
  - Strain → Train section: Start workout / resume, Today's plan, My plans, History.
  - Start sheet: today's plan, repeat last, a plan day, empty.
  - **Live session**:
    - elapsed time and the rest timer: auto-start after a check, per-exercise rest, ±15 s,
      skip; inside a superset the rest comes after the round
    - targets ("4 × 5 @ 80 kg") and ghosted last-time values
    - 56 pt set rows (kg / reps / RPE / warm-up / check) and the custom keypad (±2.5 kg,
      ±1 rep, Next, locale decimal separator)
    - plate calculator (20 kg bar, 2.5–25 kg plates)
    - add exercise (search, muscle/kind filters, custom form), reorder, superset bracket
    - summary (duration, volume, muscular load, strain, PRs with a small celebration,
      notes); discard only after confirmation
    - haptics on set check and rest end; the screen stays awake
    - VoiceOver: "Set 2 of 5, 8 reps at 80 kilograms, completed", with actions
  - **Rest timer Live Activity**: `RyftWidgetsExtension`, lock screen + Dynamic Island,
    countdown, next set, Done → `ryft://train/session`. Local only:
    `NSSupportsLiveActivities`, no push.
  - **Plans**: list (built-in, mine, active) with pause / resume / leave. Detail by week →
    day → exercises with Start. **Builder**: goal, days/week, weeks or repeating,
    progression (linear / percent / none), per-day exercises (sets, rep range, % 1RM / RPE /
    kg / bodyweight target, rest, superset), live validation. Enrol / switch with
    confirmation.
  - **History** by week (volume, load), session detail. **Exercise detail**: 90-day e1RM
    chart, PR badges, recent sets.
  - **Today card**: "Today: Upper A · 5 exercises · ~55 min" → Start; in progress → Resume;
    afterwards "Done · load 85.0 · 2 PRs".
  - **Strain activities**: sessions with a dumbbell and load chip; a Garmin workout whose
    `session_id` matches is merged into one row.
- **Demo mode**: `MockTrainSource` plays the platform:
  - 28 exercises, the 4 built-in templates from the brief plus 1 custom plan, an active
    Upper/Lower enrolment
  - 90 days of progressive history linked to MockData's strength workouts
  - completion returns a demo load (calibrated to ≈ 85 / strain ≈ 11) and PRs
- **Tests**: 137 Swift Testing tests in 14 suites (44 new) plus 1 UI test. All of them pass on
  the iPhone 18 Pro simulator (iOS 27).
  - fixtures for every new shape
  - e1RM display maths (Epley, capped at 12 reps, as the platform scores)
  - plate calculator
  - rest-timer state machine
  - plan-builder validation
  - offline queue replay order, debounce, 409 merge and re-PUT, and refused ops, against a
    stub `URLProtocol`
  - UI test (`RyftUITests` scheme): start → log 2 sets → kill → resume → finish
- **German** for all Train screens (269 strings, plural variants) and the widget's own
  catalog.
- **Preview captures** in `docs/screenshots/train-*.png`: live session (dark, light, keypad),
  plan builder (dark, light), exercise detail (dark, light), summary, Strain section, Live
  Activity (lock screen, Dynamic Island). Compared with the brand board: Graphite / Slate
  surfaces, Teal accents, Satoshi, tracked labels. Fixed during review:
  - the keypad covered the focused set
  - summary icons animated off-centre
  - the demo load was too high
- **Build**: zero warnings in app, widget and test code (simulator, Debug).

## M3b Train — open

- **Done in the go-live pass:** the app mirrors `API.md` → Train, and the fixtures are
  rebuilt. Two points are still open in `docs/API_REQUESTS.md`:
  - deleting a set mid-session
  - a paused enrolment in `GET /v1/plans`
- **Device test, not done.** Blocked by the signing issue below.
  - One real session in airplane mode; reconnect; verify it lands in `/v1/sessions` and the
    day's strain rises.
  - Live Activity on the lock screen and in the Dynamic Island, and its Done deep link. The
    simulator doesn't run Live Activities from previews.
  - Haptics.
  - Everything Train was verified with unit tests, previews and the UI test in the
    simulator's demo mode only.
- **`RestTimerAttributes` is declared twice** (app and extension, identical). Prefer one file
  with membership in both targets (Xcode File inspector).
- **UI test target** has no *Target Application* (the tool couldn't set `TEST_TARGET_NAME`),
  so it launches the app by bundle ID. It runs on its own `RyftUITests` scheme, not in the
  `Ryft` scheme's test action.
- **Log out drops unsynced sessions** with the rest of the per-user data. A warning in the
  log-out confirmation when `TrainSyncService.pendingCount > 0` would help.
- German for Train is machine translated like the rest of `de`; it needs a native review.
  Exercise names come from the server's `name` (the platform has `name_de`).
- Intermediate Train commits reference each other (session ↔ history ↔ plans); only the last
  one builds on its own.
- ~~`AuthServiceTests/authFailureOnTokenSignsOut` flake~~: fixed in the go-live pass.

## Blocked on Apple configuration (Train)

- The widget extension needs an App ID (`dev.timkrebs.ryft.RyftWidgets`) under a **paid**
  team, like the app. Live Activities themselves need no capability.

## Done (before M3b)

- **Brand**: `Theme` palette as asset-catalog colour sets with light variants; `Font.ryft`
  (Satoshi with SF Pro Rounded fallback, Dynamic Type); vector `RyftMark`; wordmark header.
- **App icon**: light, dark and tinted 1024 px PNGs rendered from `RyftMark` (`make icon`).
- **Components**: RyftMark, RyftHeader, ScoreRing, MetricTile, Card, SegmentedPicker,
  StageBar, Hypnogram, InsightCard, TrendChart, InlineMessage (with request-ID Details),
  UpdatedLabel, SetupCard. Each has a `#Preview` in dark and light.
- **Screens**: Today, Sleep (Day with stage bar and hypnogram, Week/Month), Strain (ring,
  steps and active-kcal tiles, zones, activities, WorkoutDetail), Insights (cards, charts for
  all nine trend metrics), Profile, all with previews.
- **Accounts (Supabase Auth)**, in the WHOOP style:
  - **Welcome**: mark, wordmark, tagline, three value lines in the board's style,
    *Continue with Apple*, *Create account*, *Log in*.
  - **Create account**: name, email, password ≥ 10 with show/hide, consent line. Then
    *Check your inbox* (Open Mail, Resend) when the project requires confirmation.
  - **Log in**, **Forgot password**, **Set new password**. Errors are calm and never reveal
    whether an email has an account.
  - **Continue with Apple**: native `ASAuthorization` with a SHA-256 nonce. The name from
    the first authorisation is saved as `full_name` (via `update(user:)`, then a session
    refresh, because `signInWithIdToken` takes no metadata).
  - **Deep links**: `ryft://auth/callback` (PKCE). Reset links open *Set new password*.
  - **Session**: SDK-managed in the Keychain (readable after first unlock, so background
    sync works) and restored synchronously at launch.
  - **First sign-in**: `GET /v1/me`, then `PATCH /v1/me {"tz": …}`.
  - **Profile → Account**: name → email → "Apple ID", provider badge, Change password (email
    accounts), Log out, and Delete account (`DELETE /v1/me`, then log out). The
    confirmation names what is deleted.
  - **Log out and deletion** clear the session, `ResponseCache`, HealthKit anchors and
    per-user defaults. A different account on the phone also starts from scratch.
- **Configuration**: `Config/Production.xcconfig` (committed) carries `RYFT_API_URL`
  (`https://api.ryftapp.de`), `RYFT_SUPABASE_URL` and `RYFT_SUPABASE_PUBLISHABLE_KEY`,
  exposed via Info.plist. Per-user server fields are gone. A missing value shows an in-app
  message.
  - Debug-only **Profile → Developer**: API/ingest URL overrides, API key mode for
    `AUTH_MODE=apikey` compose, Show request IDs, Test connection.
- **Status handling** per `API.md`:
  - `401` → refresh once, retry once, then log out.
  - `503` → never log out; wait `Retry-After` with "RYFT is catching up, retrying in N s".
  - `429` → wait, retry once.
  - `413` → halve the HealthKit page size for the rest of the sync.
  - Request IDs are kept: inline *Details*, and the Developer log.
- **Contract cleanup**: models mirror `API.md`.
  - Typed fields: `baseline_days`, the baselines, `steps`/`active_kcal`, `DayStrain`,
    `SleepDetail.segments`, `SleepRange` with absent nights, `User.email`/`provider`,
    `APIErrorBody.request_id`, `AccountDeleted`.
  - Removed: `details`/`JSONValue`, the "endpoint missing" shims (`Derived.swift`) and the
    0–1 → % branch in `SleepMath` (the 1 % → 100 % bug).
  - Trends gain `sleep_min`, `steps` and `active_kcal`. `sleep` is now read as performance
    (%), as the API defines it.
  - `calibrating` copy covers both D4 cases: building the baseline ("N nights to go", a
    plural variation), and baseline complete with no readiness yet.
- **Tests**: 93 Swift Testing tests in 7 suites, all passing on the iPhone 18 Pro
  simulator (iOS 27.1). They cover:
  - fixtures regenerated from the `API.md` examples
  - nonce and hash
  - `AuthService` transitions with `MockAuthClient`: sign-up with and without a session,
    log in, wrong password, the reset flow, deep links, revoked session, account switch,
    deletion
  - `APIClient` 200/401/503/429/413 handling against a stub `URLProtocol`
  - sleep maths and copy
- **Build**: zero warnings in app and test code (simulator, Debug).
- **Localisation**: German (`de`) added to the project. Welcome/Auth, Today and Sleep
  strings are being translated in `Localizable.xcstrings`; the rest follows in M5.

## Blocked on Apple / Supabase configuration (can't be done from here)

- **Paid Apple Developer team.** `DEVELOPMENT_TEAM = M77SKHKG63` is a free Personal Team,
  and those can't provision Sign in with Apple. Every **device** build fails at signing
  until the project uses a paid team. Simulator builds and tests are unaffected. Then:
  - an App ID with Sign in with Apple and HealthKit
  - a Services ID, the Team ID, a Key ID and the `.p8` for Supabase's Apple provider
- **Supabase project settings.**
  - Add `ryft://auth/callback` to Authentication → URL Configuration → Redirect URLs.
  - Email provider on, minimum password length ≤ 10, Confirm email as wanted.
  - Apple provider with the bundle ID `dev.timkrebs.ryft`.
- **Release configuration → `Config/Production.xcconfig`.** Set it in Xcode (Project → Info
  → Configurations); per `CLAUDE.md` the project file isn't edited by hand. Until then,
  Release uses the git-ignored `Config/Release.xcconfig`, which includes it.
- **Legal pages.** The consent line links `https://ryftapp.de/terms` and
  `https://ryftapp.de/privacy`. Both must exist before release.

## Open

- **Not verified on a device.** None of the §5 run has been done:
  - fresh install → Welcome → create account → inbox → confirm → HealthKit prompt → first
    90-day sync → Today
  - log out, log in with Apple, delete account, confirm the `401` afterwards
  This is blocked by the signing issue above. Everything
  was verified with unit tests, previews and the simulator in demo mode only. No device
  screenshots yet.
- **`make check-swift` in `../plattform`** should be run against the new models. It
  compiles the API.md Swift mirror and decodes a live stack.
- **Apple token revocation on account deletion**: the app now sends the authorization code;
  revocation itself happens on the platform (`DELETE /v1/me`).
- **Package pin**: `swift-clocks` must stay at 1.1.0 (see README). `Ryft.xcodeproj` is
  git-ignored, so the pin and the project settings aren't versioned. Consider tracking the
  project now that it's the source of truth.
- German for the remaining screens (Strain, Insights, Profile) in M5.
- Insight dismissal is stored per device (UserDefaults), not synced to the platform.

## Known issues

- Satoshi isn't committed because of its licence (see README). Fresh clones render in SF
  Pro Rounded until `scripts/fetch-fonts.sh` runs.
- Welcome and the auth screens are always dark (Graphite, as on the board), also in light
  mode.
- The ring and strain numbers inside rings use fixed sizes so they fit the ring geometry.
- On iOS 26+ the tab bar uses the system Liquid Glass style; the opaque Graphite bar applies
  on iOS 17–18 only.
- "Open Health permissions" opens the Health app; iOS has no deep link to the per-app read
  permissions.
