# RYFT iOS architecture

How the app is put together, following the technologies WHOOP's iOS team describes
(engineering.prod.whoop.com/ios-technologies), minus BLE and GPS. Each section names the
code that implements it.

## 1. Seams: every external dependency behind a protocol

Nothing reaches HealthKit, the network, Supabase, the store, the clock, notifications,
flags or the network path directly. Each sits behind a protocol with a live and a mock
implementation:

| Seam | Protocol | Live | Mock |
| --- | --- | --- | --- |
| HealthKit | `HealthStore` | `HealthKitManager` | `MockHealthStore` (scripted pages per stream) |
| Platform API | `PlatformAPI` (= `RyftDataSource` + `TrainDataSource` + sync, Apple code, config, push, notification prefs) | `APIClient` | `MockPlatformAPI` (mock data, records calls, scripted failures) |
| Supabase Auth | `AuthClientProtocol` (Supabase's own type is `AuthClient`) | `SupabaseAuthClient` | `MockAuthClient` |
| SwiftData | `Persistence` | `TrainStore` (on disk) | `TrainStore(inMemory: true)` |
| Time | `AppClock` (`now()`, `sleep(for:)`); not `Clock`, which would shadow Swift's | `SystemClock` | `TestClock` (moves only on `advance(by:)`) |
| Notifications | `Notifier` (local + APNs registration) | `SystemNotifier` | `MockNotifier` |
| Feature flags | `FeatureFlagProvider` | remote flags (§8) | `StaticFlags` |
| Network path | `Connectivity` | `ConnectivityMonitor` | `ConnectivityMonitor.preview(online:)` |

`HealthStore` hides HealthKit's types:
- A sync drains `HealthStream`s (each quantity type, sleep, workouts) page by page.
- A `HealthPage` carries an opaque anchor that is only `commit`ted after the upload was
  accepted.
- The mock behaves like HealthKit: an uncommitted page comes back again, which is what
  the 413 retry relies on.

### One environment, three graphs

`AppEnvironment` (`Ryft/Environment/AppEnvironment.swift`) holds every dependency and is
built once:

- `AppEnvironment.live` is created at launch by `RyftApp`. It is passed into services
  (`SyncService(env:)`, `AppState(env:)`) and into views via `@Environment(\.appEnvironment)`.
- `.preview(online:flags:)`: signed in with a fake session, mock data, an in-memory store,
  nothing leaves the process. `previewEnvironment()` injects it.
- `.test(api:health:clock:notifier:auth:flags:online:)`: the same mocks with a `TestClock`.
  Tests keep handles to script and inspect them (`EnvironmentTests`).

Demo mode is the same seam at runtime:
- `env.api` returns `demoAPI` (a `MockPlatformAPI`) when Demo data is on, `liveAPI`
  otherwise.
- Previews force it on and tests force it off (`demoOverride`), independent of the
  simulator's default.

### Migrating without a big bang

WHOOP's pattern is to run the old and the new implementation side by side, select one
with a flag, and remove the old one once the new one has proven itself. RYFT applies it
twice:

1. **Singletons → environment.** The old `.shared` singletons still exist, but they are
   *the members of `AppEnvironment.live`*. `SyncService.shared` is `SyncService(env: .live)`,
   and `TrainSource.current` is `AppEnvironment.live.api`.
   - Old call sites and migrated ones see the same instances.
   - A call site moves by taking `env` (or the protocol) instead of `.shared`.
   - When the last caller of a `.shared` is gone, the static goes too.
2. **Behaviour behind a flag.** A new implementation of a seam (or a redesigned screen)
   ships next to the old one, and a `FeatureFlag` picks between them per user:
   - for example `today.redesign`;
   - flags come from `GET /v1/config` with compiled defaults, plus local overrides in
     Debug (§8);
   - rolled out by percentage on the platform;
   - the old path is deleted after the flag has been at 100 % for a release.

Rules for new code:
- Take dependencies in the initializer (protocols, or `AppEnvironment`), never `.shared`.
- No `Date()` / `.now` in logic that tests need to control: use `env.clock.now()`.
- No `Task.sleep` for timing a feature: use `env.clock.sleep(for:)`.
- Tests wait with the bounded `eventually { … }` helper, never with an unbounded loop. A
  broken expectation must fail, not hang the run.

## 2. MVVM: one `@Observable` view model per screen

Views contain layout only. What a screen shows comes from its view model:
- values already formatted ("7h 48m", "▲ +6", "Yesterday");
- which message wins (retrying › error › sync paused);
- what an action does (refresh, recompute, export, enrol).

There is no networking, date maths or formatting logic in views. Colours stay in the
view because they are design, picked from `Theme` by a state the view model exposes
(e.g. `Theme.band(forScore: model.recovery)`).

| Screen | View model | Lives in |
| --- | --- | --- |
| Today | `TodayViewModel` | `ScreenModels` (built once at launch) |
| Sleep | `SleepViewModel` (+ `SleepNightSummary`, `SleepRangeSummary` for its sections) | `ScreenModels` |
| Strain | `StrainViewModel` | `ScreenModels` |
| Insights | `InsightsViewModel` | `ScreenModels` |
| Profile | `ProfileViewModel` | `ScreenModels` |
| Train card, start sheet, Train links | `TrainTodayViewModel` | `ScreenModels` |
| Workout | `WorkoutDetailViewModel` | per workout |
| Train history | `TrainHistoryViewModel` | per screen |
| Exercise | `ExerciseDetailViewModel` | per exercise |
| Plans / plan / builder | `PlansViewModel`, `PlanDetailViewModel`, `PlanBuilderViewModel` | per screen |
| Live session | `SessionController` | per session (`TrainCoordinator`) |
| Custom exercise | `CustomExerciseDraft` (value type) | the form |

- **Tab screens.** Their view models are in `ScreenModels`, which `RyftApp` builds with the
  shared `AppState`, so a tab keeps its selection and data when you switch away.
  `previewEnvironment()` builds one from the preview state.
- **Detail screens.** A thin view (`ExerciseDetailView`) builds its view model from the
  environment and hands it to a private `…Screen` view, which keeps the first instance in
  `@State` for its lifetime.
- **Dependencies.** View models take `AppState` (whose `env` is the §1 environment) or a
  service (`TrainLibrary`) plus `env.clock`. "Today" is always `clock.now()`, so past-day
  and time-of-day states are testable.
- **Observation.** Every former `ObservableObject` is `@Observable` (iOS 17 Observation):
  `AppState`, `Settings`, `AuthService`, `SyncService`, `ConnectivityMonitor`, `APIStatus`,
  `TrainLibrary`, `TrainSyncService`, `TrainCoordinator`, `SessionController`.
  - Views read them with `@Environment(Type.self)`.
  - Bindings into them use `Bindable(object).property`.

**Today's in-between states** (sync brief §4). `TodayViewModel.facts` gathers what they're
decided from into one value (`TodaySyncFacts`: the engine state, the sync's phase and
activity, `GET /v1/me/sync`, the cached scores, last night and the newest record per
source from HealthKit); `TodayStates` decides from it alone, so tests build facts directly:
- **hero** (the gauge's place): the first import's card until a day is scored › a night
  not scored yet (`today.state` `pending` / `waiting_for_sleep` and no readiness) › the
  baseline gauge while `calibrating` › the score. A landed score is never pending again,
  whatever an older `GET /v1/me/sync` said.
- **import row**: the backfill still going after the first score.
- **status line** (`SyncLine`): a gate › offline › locked › reading / uploading › scoring ›
  updating › paused › "Up to date · 2 min ago".
- **watch hint**: the freshest heart-rate (else sleep) source quiet for over 6 h in the
  morning or 12 h in the day, named as HealthKit names it.
`TodayScenario` (`-RyftScenario import|pending|calibrating|watch` in Debug demo mode, and
previews) applies one state on mock data for screenshots and the UI tests.

**The readiness widget** reads what Today shows from `readiness.json` in the App Group
container (`group.dev.timkrebs.ryft`). `Repository.publishWidget()` writes it after every
days write and when `AppState.syncStatus` changes today's state (`ReadinessSnapshot.make`
mirrors the hero's priority), and reloads the widget only when what it shows changed.
`ReadinessSnapshot` exists in both targets (the folders can't share a file); its JSON
shape is the contract. Only the live graph writes (`AppEnvironment.sharesWithWidget`).

**Tests** (`ViewModelTests`). Each view model runs against `AppEnvironment.test` with a
`MockPlatformAPI`, `MockHealthStore`, a `TestClock` and its own defaults suite and response
cache, so nothing leaks between parallel suites. Covered states:
- loaded
- error without data / error with data on screen
- offline (no request)
- calibrating
- past day
- sync paused
- recompute waiting for scoring on the clock
- validation on Save

## 3. Offline-first persistence (SwiftData)

**One container.** Train already had a SwiftData container (`TrainStore`); it now also
holds every platform read model (`Ryft/Persistence/ReadModels.swift`):

| Model | What it holds |
| --- | --- |
| `CachedDay` | a day's `DailyScore` and, once opened, its `DayDetail` |
| `CachedTrend` | one row per metric × range |
| `CachedInsight` | one row per card, in the platform's order |
| `CachedUser` | the signed-in user |
| `CachedSleepRange` | week / month |
| `CachedWorkout` | the HR curve and zones |
| `CachedDocument` | Train's plans overview, today's prescription, exercise histories, sessions list |

- Rows keep the wire JSON (the API's own coder) and their fetch time.
- `RepositoryStorageTests` round-trips every cached type against its `API.md` fixture.

**The rule.** Views read only from SwiftData.
- `Repository` (`Ryft/Persistence/Repository.swift`) is the only writer: it fetches from the
  `PlatformAPI` and writes the store.
- `AppState` exposes the cached values (`today`, `history`, `user`, `insights`,
  `readinessWeek`, `cachedDayDetail(for:)`, …) as reads of the Repository.
- View models compute what they show from those reads; `load()` only *revalidates*.
- The Repository bumps an observable `revision` on every write. Reads touch it, so SwiftUI
  re-renders when the store changes. Decoded values are memoized per revision.

**Freshness** (`Repository.Policy`): cache-first, stale-while-revalidate.

| Data | Fresh for |
| --- | --- |
| Today | 5 min |
| A past day | 24 h, counted from a fetch after the day ended |
| Trends | 1 h |
| Insights | 5 min |
| User | 1 h |
| Sleep ranges | 1 h |
| Workout details | 24 h |

- Browsing history never requests a day that is cached and fresh.
- Pull to refresh forces everything. A sync forces the days it touched (`days_touched`).
- App active and reconnect refresh only what's stale.

**Offline and failures.**
- Offline, nothing is requested and the cache is served.
- A failure keeps the cached copy; only without one does a screen show an error.
- A response that arrives after the account changed is dropped.

**Accounts and demo.**
- Sign-out wipes the whole store (`Persistence.wipe`), and `AppState.reset()` invalidates
  the Repository's memo.
- Demo data goes to a separate in-memory store, so it never mixes with an account's.

**Migration.** `LegacyCacheMigration` imports the old `ResponseCache` JSON files
(Caches/ryft-responses) once on first launch, then deletes them. `ResponseCache` is gone.

**Invalidation per kind.** A write invalidates only its kind (days, trends, insights,
user, sleep ranges, workouts): that kind's decoded values are dropped and its own
observed revision bumps. A trends write neither re-decodes a `DayDetail` nor re-renders a
view that only reads days. `Repository.decodes` counts the JSON decodes behind the memo
(`RepositoryInvalidationTests`).

**Memory.** Every fetch has a descriptor with a predicate and `fetchLimit`: 1 for lookups,
`Repository.maxHistoryRows` (400) for history, 50 insights. There are no full-table loads.

## 4. Structured concurrency: one `SyncCoordinator`

Every sync goes through `SyncCoordinator` (`Ryft/Sync/SyncCoordinator.swift`), an `actor`.
That covers pull to refresh, app active, back online, HealthKit delivery, `BGAppRefreshTask`
and the silent push. Ad-hoc tasks and `onDaysTouched` are gone. The pipeline is a dependency
graph of `await`s and a `TaskGroup`:

    upload ──▶ awaitScoring(days_touched) ──▶ refreshDays ──┬─▶ refreshTrends
                                                             └─▶ refreshInsights

- **Stages.** They are a `SyncSteps` protocol.
  - `LiveSyncSteps`: `SyncService.upload()` runs the `SyncEngine` (below); `syncStatus()`
    asks `GET /v1/me/sync` and keeps the answer in `AppState.syncStatus`; refreshes go
    through the Repository.
  - The tests use fakes on the `TestClock`.
- **The upload: `SyncEngine`** (an actor, `Sync/SyncService.swift`; `SyncService` is its
  `@MainActor` observable face):
  - **Order:** the night and the overnight vitals first (sleep, HRV, resting HR, breathing
    rate, SpO₂), then workouts, then heart rate, steps, active energy, VO₂ max.
  - **First score first:** an account's first sync (no anchors) sends the last 3 days of
    every stream (date-bounded, anchors never committed) and stops with a backlog; the
    coordinator scores and refreshes, then a `.backlog` run does the anchored 90-day
    backfill. The platform counts the overlap as `ignored.duplicate`.
  - **Pipelined:** the next page is read (and mapped) while the current one uploads,
    never more than one ahead; a page's anchor is committed only after its own upload.
  - **Pages by bytes:** as many records as fit 2 MB of JSON at the bytes per record the
    stream's last page measured; a `413` halves pages for the rest of the run.
  - **Off the main actor:** reads run in the engine or its read-ahead task, JSON encoding
    in a `@concurrent` function, the upload from the engine (`MainThread.assertOff` in
    Debug, and `SyncEngineTests` check it with the mocks).
  - **State per account** (`SyncEngineState`, UserDefaults like the anchors): phase,
    current stream, per-stream records, bytes and date range, the last error with its
    request ID. Wiped on sign-out with the anchors.
  - The gate (`SyncService.gate`) is asked before every page.
  - **gzip** (`sync.gzip`, off until the platform takes it): the encoded page is gzipped
    off the main actor; a `400` / `415` sends it plain and keeps the run plain.
- **Signposts** (`Signposts.sync`, `Signposts.launch`): intervals for read, map, encode,
  gzip, upload, score-wait and refresh, and the launch from `App.init` to the first
  display refresh after Today's first frame was committed (with or without cached data).
  The same signal for any screen but the splash is the launch barrier optional startup
  work (flags, push, Train, the gate re-check) waits behind. Instruments shows them under Points of Interest;
  `log show --signpost --predicate 'subsystem == "dev.timkrebs.ryft"'` lists them too.
- **Scoring, by the platform's word** (no clock comparison): after an upload the
  pipeline waits `SyncResponse.scoring.expected_within_sec`, then asks `GET /v1/me/sync`
  (while the next wait runs) until `pending_days` no longer holds the touched days,
  doubling the wait up to a minute, five minutes on the clock in all. An answer that
  says "scored", or the silent push for a scored day, ends the wait at once
  (`ScoringSignal`, which also keeps a word that arrives between waits); the push then
  joins the run, so the day isn't refreshed twice. A `gate` in the answer ends the wait
  and goes to onboarding. Every answer (the launch check's too) goes to
  `SyncService.receive`: a `resync_requested_at` this account hasn't handled (compared
  as the server sent it) makes the next upload a full re-sync.
- **Nothing touched.** A sync that uploaded nothing only refreshes what's stale.
- **Silent push.** It skips the upload and refreshes the pushed day.
- **One in flight.** A trigger while a sync runs queues one rerun; later triggers join it.
- **Priorities.** User-initiated, app active and reconnect run at `.userInitiated`;
  background, HealthKit and push at `.utility`.
- **Cancellation.** `cancel()` runs on sign-out (account change) and when a background
  task's time runs out. Waits are `clock.sleep`, so they throw `CancellationError` promptly.
- **Leaving the app** doesn't cancel: `BackgroundWork.finishInBackground` holds a
  `beginBackgroundTask` while `windDown()` lets the page in flight finish (anchor
  committed) and stops the upload there; a scoring wait is abandoned. What's left goes to
  the `BGProcessingTask` "backfill" (network required, power above an estimated 10 MB),
  which runs until the backlog is gone; at expiry it cancels at once, reschedules and
  completes (the page in flight goes again: uploads are idempotent).
- **In the background** (the app's lifecycle, not the trigger: launched into the
  background, or after `windDown` until the scene is active again; a BG task always) a
  run uploads and skips the scoring wait (the platform's silent push refreshes), its
  requests use `APIClient`'s background session (no waiting for a network, 20 s / 25 s),
  and a backlog it leaves goes to the backfill task. A HealthKit delivery while the user
  looks at Today is a foreground run and refreshes Today.
- **HealthKit delivery.** The observers (sleep, workouts, HRV; `.immediate`) are
  registered in `RyftApp.init` when the account has seen the Health explanation, so a
  background launch for a delivery finds them; bootstrap covers the first time (once).
  `run(.healthKit, afterUpload:)` calls the delivery's completion right after the upload
  step, also when it failed, was cancelled or joined another run.
- **Locked phone.** HealthKit's `errorDatabaseInaccessible` is a wait, not a failure
  (`SyncService.waitingForUnlock`); `protectedDataDidBecomeAvailable` and the next app
  start run it again.
- **Deletions.** The anchored reads' `deletedObjects` are kept per account and stream
  (`PendingDeletions`, 2 000 per stream) until the platform can take them.
- **Backoff.** Transport errors and 5xx (after `APIClient`'s own 503/429 handling) retry
  the upload at 2 s, then 4 s; 4xx don't.
- **Time-scheduled work** (`Sync/ScheduledWork.swift`):
  - `BGAppRefreshTask` runs a `.background` sync about every 2 h.
  - `BGProcessingTask` "backfill" (`dev.timkrebs.ryft.backfill`): the rest of an import.
  - `BGProcessingTask` runs nightly from 03:00 on power and compacts the cache:
    - days older than a year
    - workout details and exercise histories not fetched for 30 days
    - series older than a week
  - `ReminderScheduler` puts user-facing timers on a repeating `UNCalendarNotificationTrigger`
    (bedtime, §7).
- **Tests** (`SyncCoordinatorTests`, `ScheduledWorkTests`):
  - stage order
  - nothing uploaded
  - the scoring wait: the platform's estimate, doubling to a minute, five minutes, the
    push ending it, a gate ending it
  - coalescing (four triggers → two uploads)
  - cancellation mid-wait
  - exponential backoff, and no retry on 4xx
  - silent push
  - priorities
  - the 03:00 schedule
  - the calendar trigger
  - compaction

## 5. State machines (GameplayKit)

Flows with many states and guards are explicit machines, not boolean combinations
(`Ryft/StateMachines/`).

- **The protocol.** `StateMachine` is the protocol. A `TransitionTable` lists the allowed
  edges, plus entry and exit side effects.
- **Two engines.**
  - `GKTableMachine` runs on GameplayKit's `GKStateMachine`, with one `GKState` subclass
    per case, because GameplayKit identifies states by class.
  - `TableMachine` is the plain-Swift equivalent behind the same protocol, so the engine
    can be swapped.
  - A refused transition does nothing and returns `false`.

| Machine | States | Owner | Replaces |
| --- | --- | --- | --- |
| `SyncMachine` | idle → reading ⇄ uploading → awaitingScores → refreshing → done; failed, offline; idle again on cancel | `SyncService.phase` (upload), `SyncCoordinator` via `SyncSteps.report` (the rest) | `isSyncing` (now derived) |
| `AuthMachine` | restoring → signedOut ⇄ signingIn → signedIn ⇄ refreshing; expired | `AuthService.phase` | `isRestoring`, `signingOut`, sign-in `isWorking`; `state` for RootView is derived |
| `LiveSessionMachine` | idle → active ⇄ resting; paused (app backgrounded); finishing → completed; discarded | `SessionController.phase` (the rest timer drives active ⇄ resting) | `SessionView`'s `finishing`; a second Finish is refused |
| `HealthOnboardingMachine` | explain → requesting → granted → firstSync; denied | `HealthOnboardingViewModel` | `asking`; the intro is marked done on `denied` / `firstSync` |

**Tests.**
- `StateMachineTests` walks every (from, to) pair for each machine on *both* engines.
  It reaches `from` by its shortest path, checks that `to` is accepted exactly when the
  table has the edge, and that a refusal leaves the state unchanged. It also checks:
  - reachability
  - terminal states
  - exit-then-enter effects
- `StateMachineIntegrationTests` drives the owners:
  - sign in / out / expiry / refresh
  - upload phases, offline, failure
  - rest timer ⇄ resting, pause, a single finish
  - onboarding connect / not now

## 6. Component catalog and motion

**Catalog.** `DebugComponentCatalog` (Debug builds only, Profile → Developer) shows
every `Design/` component with mock data. Each one can be switched between dark and
light and between the XS, L and AX3 text sizes, so you can check them without opening
Xcode Previews.

**Motion.** Every animation goes through `Theme.Motion`. Each one is easeOut, and
nothing springs.

| Token | Duration | Used for |
| --- | --- | --- |
| `quick` | 0.25 s | selection, toggles, the segmented picker |
| `standard` | 0.4 s | value changes (`numericText`), cards appearing |
| `slow` | 0.6 s | the gauge and strain-target arcs filling from zero |

- `Theme.Motion.respecting(reduceMotion, _)` returns `nil` when Reduce Motion is on.
  The value then changes without the animation.
- Coach marks (`Design/CoachMarks.swift`) highlight three things on the first visit to
  Today: the gauges, then the physiology card, then the trends. They scroll each one into
  view, and their done flag is `coachMarks.today.done`. UI tests pass
  `-coachMarks.today.done YES`, and `.preview(coachMarks: true)` shows them.
- `HealthIllustration` is a 2 s loop on the Health permission screen. With Reduce
  Motion on it is a still image.

## 7. Push notifications and routes

**Routes.** `AppRoute(url:)` is the one parser for `.onOpenURL`, notification taps
(`ryft.url`) and insight cards (`AppRoute.forInsight`). It accepts
`https://ryftapp.de/<path>` (and `www.`) and `ryft://<path>`:
- `/day/YYYY-MM-DD`
- `/sleep/YYYY-MM-DD`, `/sleep/plan`
- `/insights/<metric>`, `/insights/behaviors`
- `/train/session(s)/<id>`, `/train/exercises/<id>`, `/train/plan/<id>`, `/train/history`
- `/auth/*`, which goes to Supabase

Unknown paths on our host open Today; foreign URLs return `nil`. `DeepLinkRouter` (in
`ScreenModels`) selects the tab and sets the target view model:
`strain.select` / `requestedRoute`, `sleep.show(night:)` / `showPlanner()`,
`insights.focusedMetric` / `focusesBehaviors`. A link that arrives signed out waits for
the next sign-in. `ryft://train/session` (the Live Activity) stays with
`TrainCoordinator`. There is no `associated-domains` entitlement until an AASA is hosted.

**Push.** `PushRegistrar` (behind `push.enabled`):
- **Asking:** after this account's first successful sync, Today asks in one sentence.
  "Not now" is remembered per user and asked once more after 14 days.
- **Registering:** `POST /v1/devices/{id}/push` with `{token, env, locale}`.
  - `env` comes from the signed profile's `aps-environment`.
  - It is sent again only when the account, token, environment or language changed
    from the record kept in SwiftData.
- **Removing:** `DELETE` runs before sign-out and before account deletion, through
  `AuthService.beforeSignOut`. A failure is logged and ignored.

`AppDelegate`:
- **Silent push:** refreshes the pushed day and Today through
  `SyncCoordinator.run(.silentPush)`, cancelled after 25 s. The completion handler is
  always called.
- **Taps:** follow `ryft.url`. `SYNC_STALE` has no URL; it opens Today and syncs.
- **Categories:** `MORNING_SCORE`, `SESSION_SCORED`, `PR`, `SYNC_STALE` and the local
  `BEDTIME`, without actions.
- **Text:** loc-keys from API.md (17, en and de, `extractionState: manual`).

The Notification Service Extension (ring image) is a later item: its sources are in
`RyftNotificationService/`.

**Profile → Notifications** (`NotificationSettingsViewModel`):
- a toggle per category, with its "when" line
- quiet hours (equal times = off, start after end = across midnight)
- every change is a `PATCH /v1/me/notifications`, shown at once and reverted on `422`
- with `push.enabled` off, the screen explains the rollout and the toggles are disabled

**Tests:** `PushAndDeepLinkTests`.

## 8. Feature flags (`GET /v1/config`)

- **`FlagStore`** (`Environment/FeatureFlags.swift`, `@MainActor @Observable`) is the
  live `FeatureFlagProvider` (the brief calls it `RemoteFlags`). A flag resolves in
  this order:
  1. a Debug override (UserDefaults; Release ignores overrides)
  2. the platform's value (`RemoteConfig.flags`, evaluated per user)
  3. `FeatureFlag.compiledDefault`

  Unknown keys are kept in `remote` and never read. `source(of:)` reports which of
  the three applied.
- **Per user.** The answer is cached as the `CachedDocument` `config.<account>` (through
  `Repository`'s store):
  - an offline cold start uses that account's flags
  - `switchAccount(_:)` (RyftApp, whenever `accountID` changes) loads another account's
    cache, or the compiled defaults
  - sign-out wipes the caches with the other read models
- **TTL:** due once `evaluated_at + ttl_sec` (6 h) has passed.
- **Never mid-interaction.** A new answer is cached at once, but the screens switch to
  it in `applyPending()`, which runs on a tab change and when the app becomes active.
  Only the first answer for an account, when nothing remote is showing yet, applies
  directly. A running Train session isn't gated by `train.enabled`; its full-screen
  cover lives on RootView.
- **`FeatureFlags`** (an actor in `ScreenModels`) does the fetching:
  - `run()` fetches at launch, then sleeps the TTL on the environment's clock
  - `refresh()` on foreground asks only when the config is due; `refresh(force:)` after
    sign-in and from Debug
  - one request at a time; overlapping callers share it
  - a failure keeps the cache
  - nothing is asked before sign-in
- **Gates:**

  | Flag | Gates |
  | --- | --- |
  | `train.enabled` | Today's Train card, Strain's Train section |
  | `sleep.planner` | Sleep → Planner |
  | `today.redesign` | Today's variant (last night's hypnogram); ships dark |
  | `push.enabled` | the pre-prompt, push registration, Profile → Notifications (explains the rollout when off) |
  | `coach.enabled`, `physiology.card` | reserved: read, no feature (`TODO(<flag>)` in code) |

- **Debug:** Profile → Developer → Feature flags shows each flag's value and source,
  with an override and a forced reload.
- **Tests:** `FeatureFlagsTests` covers:
  - precedence, unknown keys, TTL from `evaluated_at`
  - deferred flips, per-user caches and an offline cold start
  - fetch scheduling and failure, and every gate

## 9. CI/CD

The workflows, signing, secrets, versions and TestFlight distribution are documented in
`docs/CI.md`. Two architectural points:
- `MARKETING_VERSION` comes from the committed `VERSION` file on the xcodebuild command
  line, so the pbxproj is never edited.
- The build number is the CI run's ID.

## 10. Gates and onboarding (`invite_required`, `consent_required`)

A gate is not an error. The platform refuses with `403` and a `code`, or (in `warn`
mode) serves the request and names the gate in `X-RYFT-Gate`:

- **`APIClient`** puts the code into `APIError.http(…, code:)` (`error.gate`) and reports
  every gate it sees to **`APIStatus`** (`gates`, and `inviteBlocked` after a hard
  `403 invite_required`, which keeps every call but onboarding's from going out).
- **`OnboardingCoordinator`** (`Features/Onboarding/HealthPermissionView.swift`, in
  `ScreenModels`) decides what's missing with one pure function, `missing(_:)`, over the
  facts from `GET /v1/me`, `GET /v1/config` and `GET /v1/me/sync` plus the reported
  gates. It checks on every launch and sign-in (`bootstrap`), when `APIStatus.gates`
  changes, after each step, and on app active (at most every 60 s).
  - First run of an account on this phone (it hasn't reached the tabs yet; tracked per
    account, not by the device's Health permission): the steps full screen in RootView
    (invite → consent → about you → Health), a splash while the first check runs (at
    most 10 s).
  - Afterwards: a gate as a sheet over the tabs; "Not now" is remembered for the
    session and Today shows "Action needed".
- **`SyncService.gate`** asks the coordinator before every page: nothing syncs before
  consent, before the account is known, or behind an enforced invite gate (`pausedFor`). A sync the platform refuses at
  a gate pauses the same way and keeps the anchor of the page it couldn't send.
- `account_hint` (the platform's guess that this is the same person signed in another
  way) shows once per account; Profile → Sign-in methods links Apple to an email account
  (Supabase identity linking).

Tests: `OnboardingDecisionTests` (the decision table), `OnboardingCoordinatorTests` (the
flow, mid-session sheets, invite codes, account switch, the hint, Today's action),
`APIClientStatusTests` (the status matrix and the headers).
