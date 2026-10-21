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

    var connectivity: Connectivity { connectivityMonitor }
    /// Fixed for previews (on) and tests (off); live follows the Demo data switch.
    private let demoOverride: Bool?

    /// Demo mode serves the realistic sample history instead of the account.
    var isDemo: Bool { demoOverride ?? settings.demoMode }
    /// The live graph (previews and tests pin demo mode): only it writes what the widget reads.
    var sharesWithWidget: Bool { demoOverride == nil }
    var api: PlatformAPI { isDemo ? demoAPI : liveAPI }

    init(settings: Settings, health: HealthStore, liveAPI: PlatformAPI, demoAPI: PlatformAPI, auth: AuthService,
         persistence: Persistence, clock: AppClock, notifier: Notifier, flags: FeatureFlagProvider,
         connectivity: ConnectivityMonitor, defaults: UserDefaults = .standard, demoOverride: Bool? = nil) {
        self.demoOverride = demoOverride
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
        settings: .shared, health: HealthKitManager.shared, liveAPI: APIClient.shared, demoAPI: MockPlatformAPI(),
        auth: .shared, persistence: TrainStore.shared, clock: SystemClock(), notifier: SystemNotifier(),
        flags: FlagStore.shared, connectivity: .shared)

    /// Previews: signed in, mock data, nothing leaves the process.
    static func preview(online: Bool = true, auth: AuthService? = nil,
                        flags: [FeatureFlag: Bool] = [:], coachMarks: Bool = false) -> AppEnvironment {
        let api = MockPlatformAPI()
        let defaults = UserDefaults(suiteName: "ryft.preview") ?? .standard
        // Coach marks only in the preview that asks for them.
        defaults.set(!coachMarks, forKey: CoachMarks.doneKey)
        return AppEnvironment(
            settings: .shared, health: MockHealthStore(), liveAPI: api, demoAPI: api, auth: auth ?? .preview(),
            persistence: TrainStore(inMemory: true), clock: SystemClock(), notifier: MockNotifier(),
            flags: StaticFlags(flags), connectivity: .preview(online: online),
            defaults: defaults, demoOverride: true)
    }

    /// Unit tests: every dependency a mock the test can script and inspect.
    static func test(api: MockPlatformAPI = MockPlatformAPI(), health: MockHealthStore = MockHealthStore(),
                     clock: TestClock = TestClock(), notifier: MockNotifier? = nil,
                     auth: AuthService? = nil, flags: [FeatureFlag: Bool] = [:],
                     online: Bool = true) -> AppEnvironment {
        api.now = { clock.now() }
        return AppEnvironment(
            settings: .shared, health: health, liveAPI: api, demoAPI: api, auth: auth ?? .preview(),
            persistence: TrainStore(inMemory: true), clock: clock, notifier: notifier ?? MockNotifier(),
            flags: StaticFlags(flags), connectivity: .preview(online: online),
            defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard, demoOverride: false)
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
