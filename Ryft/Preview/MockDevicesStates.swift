// Devices & sync, the tracker detail and picker, Check sync and Sync details on graphs of their own (Nocturne PR 6 C2):
// previews, hosted tests and the comparison shots. Synthetic data only (Alex Doe). Each graph has its own defaults suite,
// so an engine state, a selection or a check seeded here never reaches another preview or suite.
#if DEBUG
import Foundation

@MainActor
enum MockDevicesStates {
    /// How the account's `GET /v1/me` (the "Seen in Apple Health" list) last went.
    enum SourcesLoad {
        /// Loaded this long ago, and the last refresh worked.
        case loaded(ago: TimeInterval)
        /// Loaded this long ago; the refreshes since have failed (`consecutiveFailures`).
        case failing(ago: TimeInterval)
        /// Nothing loaded for this account yet: no `User`.
        case never
        /// The last load was refused at the consent gate (never counted as a failure); `cached`: a list from before, of
        /// unknown age (the cache's time isn't the read record's).
        case refused(cached: Bool)
    }

    /// One page's world: the app state, the sync, and the three models these pages read.
    @MainActor
    struct Graph {
        let suite: String
        let state: AppState
        let sync: SyncService
        /// The in-memory store behind the environment (activities) and Train's outbox.
        let store: TrainStore
        /// Train's outbox, connected to Sync details' "Waiting to send" (`ProfileViewModel` does it in the app).
        let train: TrainSyncService
        let devices: DevicesViewModel
        let details: SyncDetailsModel
        let apiStatus: APIStatus

        var env: AppEnvironment { state.env }

        /// Check sync for the graph's trackers on `scenario`'s store, as Devices & sync makes it (`TrackerCheckModel.make`).
        func check(_ scenario: SyncCheckScenario, trackers: [String]? = nil) -> TrackerCheckModel {
            TrackerCheckModel(env: env, health: scenario.store(now: env.clock.now()), trackers: trackers ?? scenario.trackers)
        }

        func tearDown() {
            env.defaults.removePersistentDomain(forName: suite)
            TrackerCheckRecord.demo = nil
        }
    }

    /// What Apple Health has seen as of a load at `now`: Alex's Apple Watch and iPhone, and an app RYFT doesn't know.
    static func sources(now: Date) -> [UserSource] {
        [
            UserSource(name: "Alex's Apple Watch", bundleId: "com.apple.health.81E2",
                       kinds: [.energy, .hr, .hrv, .resp, .sleep, .workout], lastSeen: now.addingTimeInterval(-1_800)),
            UserSource(name: "Alex's iPhone", bundleId: "com.apple.health.3F0A", kinds: [.steps],
                       lastSeen: now.addingTimeInterval(-600)),
            UserSource(name: "Sleep Cycle", bundleId: "com.lexwarelabs.goodmorning", kinds: [.sleep],
                       lastSeen: now.addingTimeInterval(-47_000)),
        ]
    }

    /// - Parameters:
    ///   - demo: Demo data on (its own selection and check, nothing uploads), or a signed-in account.
    ///   - trackers: what the user wears; `later` of them put off.
    ///   - checkedAgo: the last Check sync, on the Garmin-like store; nil: never checked.
    ///   - lastSync: Apple Health's last good upload (`Settings.lastSync`), this long ago; nil: never.
    ///   - reportsWaiting: problem reports kept for later (Sync details' "Waiting to send").
    ///   - workoutsAwaitConfirmation: agreed on this iPhone, RYFT's word on it still out: Train's outbox waits at the
    ///     consent gate, and Sync details (with onboarding) names RYFT's confirmation. Queue a workout to show it
    ///     (`Graph.train`).
    ///   - clock: tests pass a `TestClock`; every time here is relative to its now.
    static func graph(demo: Bool = true, online: Bool = true, trackers: [String] = ["apple_watch", "oura"],
                      later: [String] = [], checkedAgo: TimeInterval? = 14 * 60, sources: SourcesLoad = .loaded(ago: 300),
                      lastSync: TimeInterval? = 300, seedsEngine: Bool = true, reportsWaiting: Int = 0,
                      workoutsAwaitConfirmation: Bool = false, clock: AppClock = SystemClock()) -> Graph {
        let now = clock.now()
        let suite = "ryft.preview.devices.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let settings = Settings(defaults: defaults)
        settings.demoMode = demo
        settings.lastSync = lastSync.map { now.addingTimeInterval(-$0) }
        let api = MockPlatformAPI(activities: .demoSource())
        let health = MockHealthStore(streams: [.quantity(.heartRate), .sleep, .quantity(.steps)])
        let store = TrainStore(inMemory: true)
        let env = AppEnvironment(settings: settings, health: health, liveAPI: api, demoAPI: api, auth: .preview(),
                                 persistence: store, clock: clock, notifier: MockNotifier(),
                                 flags: StaticFlags([.devicesSetup: true]), connectivity: .preview(online: online),
                                 defaults: defaults, demoOverride: demo)
        env.uploader.gate = { _ in nil }
        // The 204 on this iPhone, RYFT's own word on it still out.
        if workoutsAwaitConfirmation { env.consent.consented(to: MockData.policyVersion, at: now) }
        if seedsEngine, let account = env.auth.accountID {
            engine(now: now).save(account: account, defaults: defaults)
        }
        let state = AppState(env: env)
        state.repository.widgetFile = nil
        state.history = MockData.history
        state.today = MockData.todayDetail
        // The list as of its load: no source's "Last data" is newer than the load that brought it.
        switch sources {
        case .loaded(let ago):
            state.user = user(now: now.addingTimeInterval(-ago))
            env.reads.seed(reads(now: now, me: ResourceState(fetchedAt: now.addingTimeInterval(-ago))))
        case .failing(let ago):
            state.user = user(now: now.addingTimeInterval(-ago))
            let error = ResourceError(kind: .transient, status: nil, code: nil, requestID: nil, transport: "timedOut",
                                      attempts: 3, at: now.addingTimeInterval(-120))
            env.reads.seed(reads(now: now, me: ResourceState(fetchedAt: now.addingTimeInterval(-ago), lastError: error,
                                                             consecutiveFailures: 3)))
        case .never:
            state.user = nil
            env.reads.seed([:])
        case .refused(let cached):
            state.user = cached ? user(now: now.addingTimeInterval(-86_400)) : nil
            let error = ResourceError(kind: .gate, status: 403, code: "consent_required",
                                      requestID: "01a14ffb-0c2d-7e11-a1d4-5b2e09c4f3a8", transport: nil, attempts: 1,
                                      at: now.addingTimeInterval(-60))
            env.reads.seed(reads(now: now, me: ResourceState(lastError: error)))
        }

        let selection = TrackerSelectionStore(env: env, launch: nil)
        if demo {
            selection.stage(trackers)
        } else {
            selection.set(trackers)
        }
        later.forEach(selection.markLater)
        if let checkedAgo {
            record(env: env, trackers: trackers, at: now.addingTimeInterval(-checkedAgo), now: now)
        } else if demo {
            TrackerCheckRecord.demo = nil
        }

        let sync = SyncService(env: env)
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock)
        let apiStatus = APIStatus()
        for request in Self.requests(now: now) { apiStatus.served(request) }
        let devices = DevicesViewModel(state: state, selection: selection)
        devices.reloadCheck()
        // Asked about a gate's hold first, as the app's Sync details is.
        let onboarding = workoutsAwaitConfirmation
            ? OnboardingCoordinator(state: state, apiStatus: apiStatus, startSync: {}) : nil
        let details = SyncDetailsModel(state: state, sync: sync, coordinator: coordinator, apiStatus: apiStatus,
                                       onboarding: onboarding)
        // Train's outbox for the account (or demo data), held at no gate unless a test closes it.
        let owner = demo ? TrainSyncService.demoOwner : env.auth.accountID
        let train = TrainSyncService(store: store, remote: { api }, owner: { owner }, debounce: .seconds(3_600),
                                     monitorsNetwork: false, connectivity: .preview(online: online), defaults: defaults)
        train.gate = { (_: UploadWrite) -> UploadGate? in workoutsAwaitConfirmation ? .gate(.consentRequired) : nil }
        details.trainOutbox = train
        details.reportsWaiting = { reportsWaiting }
        return Graph(suite: suite, state: state, sync: sync, store: store, train: train, devices: devices, details: details,
                     apiStatus: apiStatus)
    }

    /// The demo's person with the sources above.
    private static func user(now: Date) -> User {
        var user = MockData.user
        user.sources = sources(now: now)
        return user
    }

    /// The last check, on the Garmin-like store with sleep off (a fix to show), as Check sync would have saved it.
    private static func record(env: AppEnvironment, trackers: [String], at: Date, now: Date) {
        let store = MockHealthStore.garminLike(now: now, sleepOff: true)
        let catalog = env.trackerCatalog
        let chosen = trackers.compactMap(catalog.tracker)
        let checks = chosen.map {
            TrackerCheckRules.classify($0, samples: store.samples, visible: store.visible, now: now, catalog: catalog,
                                       alongside: chosen)
        }
        if env.isDemo {
            TrackerCheckRecord.demo = TrackerCheckRecord(account: "demo", at: at, checks: checks)
        } else if let account = env.auth.accountID {
            env.persistence.saveDocument(TrackerCheckRecord(account: account, at: at, checks: checks),
                                         key: TrackerCheckRecord.documentKey, at: at)
        }
    }

    /// Check sync in one state without reading: `.done` with the results the scenario's store gives, or any other phase.
    static func staged(_ model: TrackerCheckModel, _ phase: TrackerCheckModel.Phase, scenario: SyncCheckScenario) {
        guard phase == .done else {
            model.stage(phase)
            return
        }
        let now = model.now
        let store = scenario.store(now: now)
        let results = model.trackers.map {
            TrackerCheckRules.classify($0, samples: store.samples, visible: store.visible, now: now, catalog: model.catalog,
                                       alongside: model.trackers)
        }
        model.stage(.done, checks: results, visible: store.visible)
    }

    /// An engine that finished its import and sends only what's new: three streams with their last pages.
    static func engine(now: Date) -> SyncEngineState {
        var engine = SyncEngineState()
        engine.phase = .idle
        engine.recentDone = true
        engine.backfillDone = true
        engine.bytesUploaded = 1_284_000
        engine.updatedAt = now.addingTimeInterval(-300)
        func stream(_ records: Int, newest: TimeInterval, page: Int) -> SyncEngineState.StreamProgress {
            var progress = SyncEngineState.StreamProgress()
            progress.records = records
            progress.bytes = records * 120
            progress.newest = now.addingTimeInterval(-newest)
            progress.backfilled = true
            progress.lastAccepted = page
            progress.lastUploadAt = now.addingTimeInterval(-newest + 60)
            return progress
        }
        engine.streams = [
            HealthStream.quantity(.heartRate).anchorID: stream(18_402, newest: 1_200, page: 500),
            HealthStream.sleep.anchorID: stream(412, newest: 14_400, page: 38),
            HealthStream.quantity(.steps).anchorID: stream(9_115, newest: 900, page: 120),
        ]
        return engine
    }

    /// Loaded data: Today and History fine, Profile (`me`) as asked, Trends failed once, Insights fine.
    private static func reads(now: Date, me: ResourceState) -> [ReadResource: ResourceState] {
        func error(_ status: Int?, ago: TimeInterval) -> ResourceError {
            ResourceError(kind: .transient, status: status, code: nil, requestID: "01a14ff2-7be0-7c11-a1d4-5b2e09c4f3a8",
                          transport: status == nil ? "timedOut" : nil, attempts: 3, at: now.addingTimeInterval(-ago))
        }
        return [
            .history: ResourceState(fetchedAt: now.addingTimeInterval(-1_740)),
            .me: me,
            .syncStatus: ResourceState(fetchedAt: now.addingTimeInterval(-60)),
            .trends: ResourceState(fetchedAt: now.addingTimeInterval(-900), lastError: error(503, ago: 2_580), consecutiveFailures: 1),
            .insights: ResourceState(fetchedAt: now.addingTimeInterval(-900)),
            .config: ResourceState(fetchedAt: now.addingTimeInterval(-3_600)),
        ]
    }

    /// The last requests, oldest first: two served, one 503. The upload is `POST /v1/sync` (on the ingest host).
    private static func requests(now: Date) -> [APIStatus.RequestFailure] {
        [
            .init(date: now.addingTimeInterval(-2_580), method: "GET", path: "/v1/sleep/plan", status: 503,
                  requestID: "01a14f12-7be0-7c11-a1d4-5b2e09c4f3a8"),
            .init(date: now.addingTimeInterval(-65), method: "GET", path: "/v1/days/today", status: 200,
                  requestID: "01a14ff0-91d2-7c11-a1d4-5b2e09c4f3a8"),
            .init(date: now.addingTimeInterval(-60), method: "POST", path: "/v1/sync", status: 200,
                  requestID: "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c"),
        ]
    }
}
#endif
