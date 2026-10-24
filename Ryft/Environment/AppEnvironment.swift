import SwiftUI

/// Every external dependency, in one place, injected into services and view
/// models instead of reached through singletons. Three graphs:
///
/// - `.live`: HealthKit, the platform over HTTPS, Supabase, the on-disk store, the
///   system clock and notification centre.
/// - `.preview`: mock data, a fake signed-in session, an in-memory store. No network.
/// - `.test(…)`: the same mocks, with a `TestClock` and handles to script them.
///
/// Migration (`docs/ARCHITECTURE.md`): the old `.shared` singletons still exist,
/// but they are the members of `.live`, so old and new code see the same instances
/// while call sites move over.
@MainActor
final class AppEnvironment {
    let settings: Settings
    let health: HealthStore
    /// The platform, and the in-memory one served in demo mode. `api` picks per call.
    let liveAPI: PlatformAPI
    let demoAPI: PlatformAPI
    let auth: AuthService
    let persistence: Persistence
    let clock: AppClock
    let notifier: Notifier
    let flags: FeatureFlagProvider
    /// Small per-install preferences (dismissed insights, UI state). Tests get their own suite.
    let defaults: UserDefaults
    /// Concrete so SwiftUI can observe it; services read it as `Connectivity`.
    let connectivityMonitor: ConnectivityMonitor
    /// ryftapp.de's static files (the tracker catalog): no auth, outside the read pipeline (ADR 0002).
    /// Only the live graph reaches the web; every other graph answers like a phone without a connection.
    let content: ContentSource
    /// Small files of the content above (the catalog's crash marker); a fresh directory for each test graph.
    let contentDirectory: URL

    var connectivity: Connectivity { connectivityMonitor }
    /// The read pipeline (ADR 0001): every scheduled read of the platform shares its coalescing,
    /// retries, budget and per-resource record, whoever asks (Repository, journal, flags, Train,
    /// onboarding).
    lazy var reads = ReadScheduler(env: self)
    /// The tracker catalog: bundled, or the newest valid copy from ryftapp.de (`trackerCatalog`).
    lazy var catalogStore = TrackerCatalogStore(env: self)
    /// Activities and manual sleep on this iPhone until the platform confirms them, scoped to the account
    /// (`persistence`'s store; demo data's own in memory).
    lazy var activities = ActivityStore(env: self)
    /// Fixed for previews (on) and tests (off); live follows the Demo data switch.
    private let demoOverride: Bool?

    /// Demo mode serves the realistic sample history instead of the account.
    var isDemo: Bool { demoOverride ?? settings.demoMode }
    /// The live graph (previews and tests pin demo mode): only it writes what the widget reads.
    var sharesWithWidget: Bool { demoOverride == nil }
    var api: PlatformAPI { isDemo ? demoAPI : liveAPI }

    init(settings: Settings, health: HealthStore, liveAPI: PlatformAPI, demoAPI: PlatformAPI, auth: AuthService,
         persistence: Persistence, clock: AppClock, notifier: Notifier, flags: FeatureFlagProvider,
         connectivity: ConnectivityMonitor, defaults: UserDefaults = .standard, demoOverride: Bool? = nil,
         content: ContentSource = MockContentSource(), contentDirectory: URL? = nil) {
        self.demoOverride = demoOverride
        self.content = content
        self.contentDirectory = contentDirectory ?? Self.temporaryContentDirectory()
        self.defaults = defaults
        self.settings = settings
        self.health = health
        self.liveAPI = liveAPI
        self.demoAPI = demoAPI
        self.auth = auth
        self.persistence = persistence
        self.clock = clock
        self.notifier = notifier
        self.flags = flags
        self.connectivityMonitor = connectivity
    }

    /// The app's graph, built once at launch.
    static let live = AppEnvironment(
        settings: .shared, health: HealthKitManager.shared, liveAPI: APIClient.shared,
        demoAPI: MockPlatformAPI(activities: .demoSource()),
        auth: .shared, persistence: TrainStore.shared, clock: SystemClock(), notifier: SystemNotifier(),
        flags: FlagStore.shared, connectivity: .shared, content: WebContentSource(),
        contentDirectory: URL.applicationSupportDirectory.appendingPathComponent("Content", isDirectory: true))

    /// Previews and tests: a directory of their own that nothing else reads.
    private static func temporaryContentDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ryft-content-\(UUID().uuidString)", isDirectory: true)
    }

    /// Previews: signed in, mock data, nothing leaves the process.
    static func preview(online: Bool = true, auth: AuthService? = nil,
                        flags: [FeatureFlag: Bool] = [:], coachMarks: Bool = false,
                        notifier: MockNotifier? = nil) -> AppEnvironment {
        let api = MockPlatformAPI(activities: .demoSource())
        let defaults = UserDefaults(suiteName: "ryft.preview") ?? .standard
        // Coach marks only in the preview that asks for them.
        defaults.set(!coachMarks, forKey: CoachMarks.doneKey)
        return AppEnvironment(
            settings: .shared, health: MockHealthStore(), liveAPI: api, demoAPI: api, auth: auth ?? .preview(),
            persistence: TrainStore(inMemory: true), clock: SystemClock(), notifier: notifier ?? MockNotifier(),
            flags: StaticFlags(flags), connectivity: .preview(online: online),
            defaults: defaults, demoOverride: true)
    }

    /// Unit tests: every dependency a mock the test can script and inspect.
    static func test(api: MockPlatformAPI = MockPlatformAPI(), health: MockHealthStore = MockHealthStore(),
                     clock: TestClock = TestClock(), notifier: MockNotifier? = nil,
                     auth: AuthService? = nil, flags: [FeatureFlag: Bool] = [:],
                     online: Bool = true, content: MockContentSource = MockContentSource()) -> AppEnvironment {
        api.now = { clock.now() }
        // Settings of its own: `Settings.shared` is process-wide, and parallel suites (every sync,
        // every sign-out) write `lastSync` and `healthIntroDone` there.
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let env = AppEnvironment(
            settings: Settings(defaults: defaults), health: health, liveAPI: api, demoAPI: api, auth: auth ?? .preview(),
            persistence: TrainStore(inMemory: true), clock: clock, notifier: notifier ?? MockNotifier(),
            flags: StaticFlags(flags), connectivity: .preview(online: online),
            defaults: defaults, demoOverride: false,
            content: content)
        // Time moves only when a test advances it: retries wait no jitter, and the starts-per-second
        // window doesn't hold back reads issued at one instant. Suites about retry timing and the
        // budget set their own (`reads.random`, `reads.budget`).
        env.reads.random = { $0.lowerBound }
        env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
        return env
    }
}

private struct AppEnvironmentKey: EnvironmentKey {
    // Previews and tests set their own; the live graph is the fallback.
    static var defaultValue: AppEnvironment { MainActor.assumeIsolated { .live } }
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
