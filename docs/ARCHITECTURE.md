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
| Time | `AppClock` (`now()`, `sleep(for:)`, monotonic `uptime()`); not `Clock`, which would shadow Swift's | `SystemClock` | `TestClock` (moves only on `advance(by:)`) |
| App Attest (ADR 0023) | `AppAttestService` (DeviceCheck), `AppAttestKeyStore` (the key's ID, with its account); `AppAttestor` owns the token in memory | `DeviceAppAttestService`, `KeychainAppAttestKeys` (`AfterFirstUnlockThisDeviceOnly`) | `FakeAppAttestService`, `MemoryAppAttestKeys` (tests) |
| Notifications | `Notifier` (local + APNs registration) | `SystemNotifier` | `MockNotifier` |
| Feature flags | `FeatureFlagProvider` | remote flags (§8) | `StaticFlags` |
| Network path | `Connectivity` | `ConnectivityMonitor` | `ConnectivityMonitor.preview(online:)` |

`HealthStore` hides HealthKit's types:
- Every read type is declared once, in `HealthPermissionGroup` (`Ryft/Health/`, ADR 0027), and asked for by group:
  `requestAuthorization(_:)` and `accessStatus(_:)` take one. `core` is the ten types the sync uploads; `about` is the
  date of birth, of which only the year crosses the seam (`birthYear()`). Which groups an account asked for is
  `HealthPermissionLedger` (`health.asked.<account>`); the observers derive from it.
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
`ReadinessSnapshot` is one file both targets compile (`Shared/`, ADR 0010); its JSON shape
is the contract, and it only gains optional keys. It carries the orbit's scores, so the
widget draws Today's `OrbitGaugeMode` (`ReadinessSnapshot.gauge`). The file is written with
`completeUntilFirstUserAuthentication` protection and excluded from backups. On a locked
device the widget hides the values (the system's `.privacy` redaction): the orbit's tracks
only in every state, a constant number and line under the redaction (a redaction keeps its
text's width; `ReadinessSnapshot.numberSlot`/`lineSlot`/`bedtimeSlot`), no bedtime line, and
VoiceOver says "Readiness". Only the live graph writes
(`AppEnvironment.sharesWithWidget`).

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
  `readinessWeek`, `cachedDayDetail(for:)`, …) as reads of the Repository. Their setters
  are for previews and tests only (`seed`); Debug stops at one on the live graph.
- View models compute what they show from those reads; `load()` only *revalidates*.
- The Repository bumps an observable `revision` on every write. Reads touch it, so SwiftUI
  re-renders when the store changes. Decoded values are memoized per revision.

**Writes run off the main actor** (ADR 0018).
- A write is a `Sendable` value (`ReadModelWrite`), and `ReadModelWrites.apply` is the one
  implementation of each. Batch fetches only: one `#Predicate` per write, and deletes go
  through the context (never `delete(model:)`, which misses the batch's unsaved inserts).
- `Repository.store…` submits in the same main-actor step as the read pipeline's account
  check and returns a `WriteTicket`. `ReadModelDrain` applies the queue in submit order,
  one batch at a time, on the store's `ReadModelWriter` (a `@ModelActor`, private to the
  drain's file, so no main-actor code can make or await it). The drain does both on its own
  executor: on iOS 17.0 the thread that made a model actor ran its jobs, and iOS 18 is
  reported to do the same (unmeasured on 18.6); on iOS 27.2 the thread that awaits it. A
  batch never spans a store, an epoch or a seed, and it saves once.
  The drain runs at `.userInitiated` whoever submitted first: awaiting a ticket doesn't raise
  its priority.
- At the commit the Repository replaces its read context (one per store, never written),
  bumps each written kind's revision once, and publishes the widget. `committed()` resolves
  after that: a refresh's flight awaits it, so a refresh, and each sync stage, returns with
  its rows readable.
- `.user` is written through: `user()` returns it from the submit on, for reads of the store
  it went to, because the upload gate reads it back in that step (ADR 0008). It stays until
  `invalidate()`; a refused save of it goes again once. A `PATCH /v1/me` answer is stored
  `asOf` the `userChange()` taken before its request, and dropped after a sign-out, another
  account or the Demo data switch. The withdrawal is stored the same way
  (`storeConsentWithdrawn(asOf:)`: the cached user without the consent). Each stored change
  counts (`userChanges`): an answer whose request began before another change was stored
  is dropped, counts as no change of its own, and the user is asked again
  (`.changed(since:)`), because the platform may have read the user before that change,
  a withdrawn consent with it. A `GET /v1/me` asked for before this phone's last change is
  dropped too (`store(fetchedUser:askedAt:)`). Demo data on and off again while a `PATCH`
  is out passes (the same account and store): the cached user may then be up to its 1 h
  freshness behind the platform. The Notifications `PATCH` answers with the settings, not
  the user, so the user is asked again after it.
- The writer owns `CachedDay`, `CachedTrend`, `CachedInsight`, `CachedUser`,
  `CachedSleepRange`, `CachedWorkout` and the `activities.*` documents. Train's tables and
  every other document stay on the main context (`compact()` deletes Train's histories
  there). Only `ReadModelWrites` and `TrainStore.wipe` insert or delete writer-owned rows.
- `seed` writes at once on a context of its own, on main: previews, tests and the legacy
  import. Only while the queue is idle (`onMisuse` otherwise: Debug stops there, the unit
  tests' host fails the test that seeded, `Misuse.report`); the next write gets a new
  writer.
- `settled()` returns once every write submitted so far has committed. A `BGTask`'s
  completion, the end of the background time after leaving the app and a silent push's
  handler wait for it, 2 s at most and not once the system's time ran out
  (`settledBeforeCompletion()`): iOS may suspend the app there. If the wait ends that way
  in the background, the drain pauses (`ReadModelDrain.pause()`): no batch starts, the
  one in progress is awaited (a save takes milliseconds), so no save into the App Group's
  store is open at the suspension (0xdead10cc). What's queued is written when the app comes
  to the foreground (`resumeWrites()` at `.active`) or after `pauseAfterCompletion` (10 s,
  moved on by a later pause) of the app running. No pause in the foreground. The nightly
  compaction waits for its write the same way (2 s, not once cancelled), and its task's
  expiry stops it. A HealthKit delivery's `completion()` doesn't wait: it comes right
  after the upload.
- Debug asserts that each writer is made off main and that every job of it runs off main
  (`ReadModelOffMainTests` proves both through the real path, measured on 17.0 and 27.2; 18.6
  is the oldest-runtime gate); `OSSignposter` interval `write` on `reads` covers each batch.

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
- Sign-out wipes the whole store (`Persistence.wipe`), and the Repository's `invalidate()`
  forgets its memo, its read contexts and the user written through, and retires the
  wiped epoch's writer.
- The wipe's first step advances `StoreEpoch`. A write submitted before it is dropped
  unwritten; the writer saves inside the epoch's save gate, so a save in progress finishes
  first and the wipe then deletes it. Reading `current` takes a lock of its own and never
  waits for a save. The first write after a wipe gets a new writer, so no context keeps a
  deleted row (`ReadModelWipeRaceTests`). Queue, writers and read contexts are keyed by
  `StoreID`, which is never reused.
- **A wipe that doesn't finish is a debt** (ADR 0020, `docs/work/2026-11-05-wipe-recovery/design.md`):
  - The sign-out writes an entry to `WipeLedger` (a file in Application Support) before its first destructive step,
    and a wipe that returns false leaves it. `auth.lastUserID` (`AccountScope`) only says whose data the store holds,
    and follows the published session.
  - At the next launch `AuthService.init` resolves the entry before anything opens the store, and `TrainStore.shared`'s
    initializer replaces the store's files (`StoreReset`) before its first container exists, so no writer or read
    context can hold them. A session expiry's parked rows within 30 days keep the object wipe instead, after the first
    frame. The compaction retries too.
  - No session is published over an entry (`AuthService.clearTheWay`): another account's sign-in makes one attempt and
    is held if it fails, and Welcome says so. Once a pass was refused, nothing in that process ends the debt.
  - The wipe's own turn lets go of what holds Train rows (`TrainCoordinator.releaseRows`, `SessionController.release`):
    on iOS 18 and 26 reading a deleted row's relationship can be a fatal error. The demo's discard does the same, and
    both, and an account change, drop a workout still opening from the start sheet (`TrainCoordinator.open`).
- Demo data goes to a separate in-memory store, so it never mixes with an account's. The
  Demo data switch replaces it with an empty one at once (`Repository.reset()`); the old
  one's epoch moves on (`ReadModelDrain.retire(_:)`), so a batch already in its writer
  doesn't save, and its queued writes drop. There is no "clear" write: a store is wiped
  (`Persistence.wipe`) or replaced.
- Train's outbox (`PendingTrainOp`) is in the shared store, so each op records whose it is (the account, or demo):
  it goes only through that binding's client, and another binding's ops wait, uncounted (ADR 0008). A session's
  `DELETE` is bound to where its uploads went (`LocalSession.uploadedTo`); demo's ops go when demo data is switched off.
  - **A custom exercise is an op** (`exercise`, `POST /v1/exercises`), queued ahead of every other op, because a
    queued `PUT` sends the session as it is when it goes. No consent gate or undo window holds it, but it's bound to
    its account. A session's ops don't go while an exercise it uses is queued or refused, and a plan save waits for
    the exercises it names, at most 10 s (`TrainLibrary.savePlan`).
  - **A refusal is state, never a drop** ([ADR 0022](adr/0022-train-outbox-refusals.md)). A `400`, `409` after the
    merge rounds, `413`, `422`, any other `4xx` but the holds, a `404` on `complete`, or a body the app can't encode
    keeps the op and records an `UploadAttempt` (status, code, request ID, time) on the session, or on the op for an
    exercise. That session's ops wait until Retry or an edit; other sessions' go. Every `403`, a `404` on `PUT` or
    `POST`, `408`, `426`, `429` and `5xx` hold the queue (an exercise answered that way is passed over, so unrelated
    sessions still go); a `2xx` the app can't read was delivered. `UploadAttempt.isRefusal` is the one definition,
    the activities uploader's too, and `TrainSyncService.state(of:)` derives the session's `UploadState` from the rows
    each time it's asked. While a session's `PUT` is refused or queued, a completion's answer brings only what the
    platform owns (status, workout, PRs, scores, body weight), never the logged sets (`applyPlatformFields`).
  - **The exceptions:** a refused `DELETE` is dropped and logged (its session is gone here); a `complete` answered
    `409` means the platform discarded the session, so the op goes; a `complete` answered `404` before the session's
    `PUT` arrived queues that `PUT` ahead of it.
- **Ending the demo** (ADR 0019, `docs/work/2026-11-18-ios17-demo-exit/design.md`). Profile's switch is the only way out
  in production. Train has no demo store of its own, so the workouts started in the demo are named by a list:
  `TrainCoordinator.newSessionID()` adds a new session's id (`train.demoSessions` in defaults, ids only) when the
  binding is demo's, before the factory saves the row, and `TrainSyncService` owns it (an observable copy feeds
  Profile's VoiceOver hint). Turning the switch off with such a workout asks first (`ProfileViewModel.switchingDemoOff()`,
  computed from the list and the store, never stored); cancel changes nothing, and a store that can't be read shows an
  error under the switch instead of the dialog or the exit. `ProfileViewModel.endDemo()` then runs
  one main-actor step with no `await` up to the refresh:
  1. `TrainCoordinator.discardDemoWorkouts()`: the replay stops, the live workout closes (released, as by the wipe)
     and its Live Activity ends (checked against the list), every listed session goes with its ops and from Train's cached history list and
     exercise histories (sessions, records, chart points), and nothing is sent (not even a `DELETE`). The list keeps only ids a fresh context still finds; a store in memory in
     place of its file drops only what it deleted. If the store can't be read nothing changes, Demo data stays on and Profile says so.
     An account's workout is never on the list, even if it went on during the demo.
  2. The switch goes off, `reset()` drops what the demo showed (the demo's Train platform starts over too), with the
     demo's sync status and tonight's bedtime.
  3. The flags, the scoring words and the import's demo leftovers; then the widget is published from the account's
     store, and the refresh runs.

  At launch (`TrainCoordinator.demoAtLaunch`) the list is seeded once for workouts logged before it, and only with
  protected data (before the first unlock `auth.lastUserID` reads nil): with nobody signed in, every stored session
  (sign-out wipes Train), Demo data on or off; signed in, none. Then a launch with Demo data off and a non-empty list
  (the demo ended outside the switch, or the seed just listed a demo's leftovers) discards without asking. A listed
  session's ops are only ever bound to, and sent by, the demo. The iOS 17 reopen of the account's store
  that ADR 0019 also decided isn't built: the minimum becomes iOS 18.6.

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
    stream's last page measured; a `413` halves pages for the rest of the run. Workout pages
    stay within the platform's 5 000.
  - **Nothing the platform refuses** (`Sync/SyncScreen.swift`): ingest's `validate()` answers a
    whole page with `422` for one record, and an anchor can't move past a refused page. So a
    page goes up without the records it would refuse, compared as they go over the wire (whole
    seconds): a workout or sleep segment whose end isn't after its start, a sample ending before
    it starts or without a start, a workout without an id. A too-long `source_bundle_id`, `app_version`
    or `os_version` goes as nil instead. The anchor moves on, and the dropped records are counted per
    stream (`StreamProgress.invalid`, by the anchored reads only; "invalid N" in the diagnostics).
  - **Off the main actor:** reads run in the engine or its read-ahead task, JSON encoding
    in a `@concurrent` function, the upload from the engine (`MainThread.assertOff` in
    Debug, and `SyncEngineTests` check it with the mocks).
  - **State per account** (`SyncEngineState`, UserDefaults like the anchors): phase,
    current stream, per-stream records, bytes and date range, the last error with its
    request ID. Wiped on sign-out with the anchors.
  - The gate (`SyncService.gate`: `OnboardingCoordinator.uploadGate(for: .healthKit)`, §10) is asked before the
    first HealthKit read, after one `GET /v1/config` when the policy in force isn't known, and again before every
    page. A hold commits no anchor; in demo, `run()` refuses before anything else.
  - **gzip** (`sync.gzip`, off until the platform takes it): the encoded page is gzipped
    off the main actor; a `400` / `415` sends it plain and keeps the run plain.
- **Signposts** (`Signposts.sync`, `Signposts.launch`): intervals for read, map, screen, encode,
  gzip, upload, score-wait and refresh, and the launch from `App.init` to the first
  display refresh after Today's first frame was committed (with or without cached data).
  The same signal for any screen but the splash is the launch barrier optional startup
  work (flags, push, Train, the gate re-check) waits behind. Instruments shows them under Points of Interest;
  `log show --signpost --predicate 'subsystem == "dev.timkrebs.ryft"'` lists them too. The launch sequence (§6)
  adds `first-screen` (the barrier opening), `launch-decision` (`play-full`, `play-reduced`, `skip-<reason>`), the
  `launch-sequence` interval (first `.active` to the overlay's removal, ending with how it ended) and
  `launch-handoff` (the root becomes interactive).
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
  - `ReminderScheduler` (`Push/`, ADR 0024) drives every local reminder: bedtime's wind-down, the journal
    reminder and the "not syncing" fallback. Each kind is a pure plan (`ReminderPlans.swift`); a pass diffs the
    wishes against the ledger of what it put on iOS and adds or removes only the difference, as one-shot floating
    `UNCalendarNotificationTrigger`s. It reads iOS's pending set once per process and the authorization once and on
    every app active; a pass that changes nothing makes no system call. Triggers coalesce into one pass per 500 ms on
    the app's clock; a successful sync (`Settings.lastSync`) and bedtime's `offerBedtime` run one at once, and the BG
    refresh awaits one. Owner: the account binding, the store epoch and the scheduler's generation (bumped by every
    `forget()`, the wipe's and the Demo switch's turn), re-checked after every await; `notifications.owner` says whose
    requests iOS holds, and with no key yet each request's own `ryft.account` does (an earlier build's bedtime ones,
    without one, stay until the planner's first offer). Signed out it tears ours down and clears Notification Center;
    Demo data freezes them; locked, it takes nothing away for nobody. The journal reminder and the fallback ship dark
    behind `notifications.reminders` and pause while consent is withdrawn or refused; a gate not known yet keeps what's
    scheduled. The calendar follows the time zone. Every wipe removes every pending and delivered notification and
    unregisters APNs (`AuthService.notificationStep`); a session expiry keeps the account's journal setting. Signpost
    `reminders.pass` (`Signposts.sync`) with its adds and removes. Tests: `ReminderPlanTests`, `ReminderSchedulerTests`.
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

**Launch sequence** (ADR 0017; `docs/work/2026-11-16-nocturne/launch-design.md`). The 5.2 s brand moment on a cold
start: the rings draw the board's reading, the dots move into the orbit mark, "RYFT" and the tagline arrive. It is the
one exception to the 250 ms rule and never gates startup.
- **Where it lives.** `LaunchHost(model:) { RootView() }` is the `WindowGroup`'s view; `LaunchOverlay` sits in its
  overlay. `RootView` and every startup hook are built beneath it as without it. The model, `LaunchSequenceModel`, is
  `@State` on `RyftApp`, so it lives for the process and never plays twice. It wraps the pure `LaunchSequence`
  (phases `armed → playing → handingOff → done`, or `skipped`; all functions of a date) and refreshes on events and
  `AppClock` deadlines. The overlay draws `LaunchFrame(t:palette:side:)`, a pure function of t from
  `RyftMarkGeometry`, in a `TimelineView`; t = 1 is the static mark. Armed, it is only `Theme.background`, the launch
  screen's colour.
- **When it plays** (`LaunchPolicy.decide`, from the top): `-RyftLaunchSequence skip` → skip; a background launch →
  skip; any launch argument (every UI test, `scripts/screenshots.sh`, `-RyftScreen`) unless `-RyftLaunchSequence play`
  → skip; an open workout → skip; back within 10 minutes of the last `.background` (`launch.lastBackgroundAt`, L9)
  unless `play` → skip; Reduce Motion, Low Power Mode or VoiceOver → the reduced variant (the last frame for 1 s, then
  a 0.25 s cross-fade); otherwise the full sequence, demo mode included. After init, a link, notification, quick action
  or Handoff at connect (`QuickActionSceneDelegate` → `LaunchInterruptions`), a root sheet or cover
  (`RootView.presentsSomething`: a new root presentation joins that list), system UI (`.inactive`), the background and
  a first `.active` later than 5 s skip it or hand off at once. A tap, or VoiceOver's activate or "Skip", hands off.
- **The seam.** `launchCoversRoot` (environment) is true while armed or playing: anything that plays once when first
  seen treats it like the background. Today's gauge is built static under it and plays its entrance at the hand-off.
  PR 4's matched move into Today's header uses the `.launch` coordinate space, `LaunchStage(frame:markRect:)` and
  `LaunchSequence.handOff(at:)`.

## 7. Push notifications and routes

**Routes.** `AppRoute(url:)` is the one parser for `.onOpenURL`, notification taps
(`ryft.url`) and insight cards (`AppRoute.forInsight`). It accepts
`https://ryftlab.de/<path>` (and `www.`) and `ryft://<path>`:
- `/day/YYYY-MM-DD`
- `/sleep/YYYY-MM-DD`, `/sleep/plan`
- `/insights/<metric>`, `/insights/behaviors`
- `/journal/YYYY-MM-DD`: Today, with the journal sheet on that day (`DeepLinkRouter.requestedJournalDay`)
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
    from the record kept in SwiftData. An answer that arrives after the account changed (a sign-out, another sign-in)
    saves no record.
  - Behind the invite gate (`APIStatus.inviteBlocked`, or a standing `inviteRequired` refusal) the app doesn't
    register with APNs, because the platform refuses the `POST` and iOS may hand back an expired session's token
    (NT7). When the gate opens (`ScreenModels` watches `inviteBlocked`), `refresh()` runs at once.
  - A refused or failed `POST` with nothing accepted for the account unregisters from APNs again, unless the
    account changed meanwhile; the next launch or app active registers and sends again.
- **Removing:** `DELETE` runs before sign-out and before account deletion, through
  `AuthService.beforeSignOut`. A failure is logged and ignored.

`AppDelegate`:
- **Silent push:** refreshes the pushed day and Today through
  `SyncCoordinator.run(.silentPush)`, cancelled after 25 s. The completion handler is
  always called.
- **Foreground and taps:** one pure function, `PushPresentation` (design.md §7 of
  `docs/work/2026-11-22-notifications/`). Taps follow `ryft.url`; `SYNC_STALE` has no URL, it opens Today and syncs;
  `BEDTIME` opens Today. A local notification (any trigger but a push's) for another account than the signed-in one,
  or arriving while Demo data is shown (the wake notification excepted: it carries no data), isn't presented and
  opens Today only. This iPhone's `SYNC_STALE` isn't
  presented in the foreground: the open app syncs.
- **Categories:** `MORNING_SCORE`, `SESSION_SCORED`, `PR`, `SYNC_STALE`, `ACTIVITY_SCORED` (registered before the
  platform sends it) and the local `BEDTIME`, `JOURNAL_REMINDER` and `WAKE` (the wake notification below iOS 26),
  without actions. Each has a placeholder for
  hidden previews that says what kind it is and carries no value.
- **Local notifications** (`ReminderScheduler`, §4): bedtime, the journal reminder (`journal.<asked day>`, 3 mornings,
  `/journal/<day>`), the "not syncing" fallback (`sync.stale.1`/`.2`, 20 h and 72 h after the last sync, only where
  the server's `SYNC_STALE` can't reach this iPhone). Their `userInfo` has the server alerts' shape:
  `ryft: {category, day, url, account}`.
- **Text:** English only. Server alerts use API.md's loc-keys; local ones `String(localized:)` with symbolic keys
  (`JOURNAL_REMINDER_*`, `SYNC_STALE_LOCAL_*`, `HIDDEN_PREVIEW_*`).

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
- **"This day is being scored" has one owner** (ADR 0013): `SyncService.scoringLedger`, written only by
  `SyncCoordinator` steps (`awaiting` after accepted writes, `scored` on a push), answered by status reads requested at
  least the server's cache time after the write, read by Today and the widget through `ScoringWord.state`. New write
  paths reach it through the coordinator, never directly.
- **One rule for every upload** (ADR 0008): `OnboardingCoordinator.gate(_:path:write:)`, a pure function next to
  `missing(_:)`, asked through `uploadGate(for:write:)` by `SyncService` (`.healthKit`), `ActivityUploader`
  (`.activities`), `TrainSyncService` (`.train`) and, once built, the training import (`.trainImport`):
  - before a path's first read or request, and again before every page, item or op;
  - demo data holds HealthKit (its client is the platform's) and opens the others, whose requests are bound to demo;
  - data waits for the account, consent to the policy in force, and a **fresh** policy answer; an enforced invite
    gate and an unreadable record (before the first unlock) hold everything;
  - a `DELETE` goes without a current consent (erasure); a `consent_required` answer to it keeps it queued.
  A hold is never an error (`pausedFor`, `.pending(.gated)`, Train's pending count); no anchor or queued item is lost.
- **`ConsentState`** (`Environment/ConsentState.swift`, `env.consent`) is what this phone knows, per account, as one
  `CachedDocument`: the last `/v1/config` answer (or consent `204`) and when it arrived, and the platform's refusals.
  - Fresh while younger than `min(ttl_sec, 24 h)` on this phone's clock; a clock set back is stale.
  - `fetchConfig()` is the only way the app reads `/v1/config`; `revalidate()` asks once (joined with reads in
    flight, at most once a minute after a failure) before an upload holds for an unknown policy.
  - `APIStatus.onGate` keeps `consent_required` in any mode and `invite_required` only when enforced; a warn-mode
    invite never holds. `check()`, `agree()` and `redeemInvite()` end them.
  - Read once per `AccountBinding`; wiped with every account wipe; demo reads and writes nothing. In the live graph
    `TrainStore`'s in-memory fallback (a launch before the first unlock) never counts as readable: every write holds.
  - A withdrawal on this phone (`withdrew(at:)`) is recorded as the platform's `consent_required` refusal and kept
    beside the store, per account in `env.defaults` (`withdrawnAt`, a consent signal in `Facts.reported`): it holds
    every data gate when the store refuses the withdrawal's saves (any refused save; iOS 17 refused them all after demo
    data) and in a background launch that never runs `check()`. It ends when this phone agrees again (`consented`)
    or a `GET /v1/me` asked for after it shows consent to the policy in force (`heard`, from
    `Repository.store(fetchedUser:askedAt:)`). The withdrawal's re-check asks `/v1/me` and `/v1/me/sync` again rather
    than join reads begun before it.
  - The wipe forgets the leaving account's requests (`APIStatus.forgetRequests`) before the next session is
    published, so a late `403` of theirs is never kept as the next account's refusal.
- **The release edge:** RootView forwards each path's gate to `ScreenModels.gateChanged(_:to:)`; when it opens, the
  path's queue goes, and a sync whose last run was held (or whose policy read failed) runs again, unless one is already
  running or queued (`SyncCoordinator.runIfIdle`). In the background each run asks at its own start. Every gate is
  closed until the app connects it (`SyncService.gate` too).
- `account_hint` (the platform's guess that this is the same person signed in another
  way) shows once per account; Profile → Sign-in methods links Apple to an email account
  (Supabase identity linking).

Tests: `OnboardingDecisionTests` (the decision table), `OnboardingCoordinatorTests` (the
flow, mid-session sheets, invite codes, account switch, the hint, Today's action),
`APIClientStatusTests` (the status matrix and the headers), `ConsentGateTests` (the upload rule's tables, the record,
its writers, sync, activity and Train holds, the release edge).
