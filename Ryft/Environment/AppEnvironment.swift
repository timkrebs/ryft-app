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
    /// Concrete so SwiftUI can observe it; services read it as `Connectivity`.
    let connectivityMonitor: ConnectivityMonitor

    var connectivity: Connectivity { connectivityMonitor }
    /// Fixed for previews (on) and tests (off); live follows the Demo data switch.
    private let demoOverride: Bool?

    /// Demo mode serves the realistic sample history instead of the account.
    var isDemo: Bool { demoOverride ?? settings.demoMode }
    var api: PlatformAPI { isDemo ? demoAPI : liveAPI }

    init(settings: Settings, health: HealthStore, liveAPI: PlatformAPI, demoAPI: PlatformAPI, auth: AuthService,
         persistence: Persistence, clock: AppClock, notifier: Notifier, flags: FeatureFlagProvider,
         connectivity: ConnectivityMonitor, demoOverride: Bool? = nil) {
        self.demoOverride = demoOverride
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
        flags: StaticFlags(), connectivity: .shared)

    /// Previews: signed in, mock data, nothing leaves the process.
    static func preview(online: Bool = true, flags: [FeatureFlag: Bool] = [:]) -> AppEnvironment {
        let api = MockPlatformAPI()
        return AppEnvironment(
            settings: .shared, health: MockHealthStore(), liveAPI: api, demoAPI: api, auth: .preview(),
            persistence: TrainStore(inMemory: true), clock: SystemClock(), notifier: MockNotifier(),
            flags: StaticFlags(flags), connectivity: .preview(online: online), demoOverride: true)
    }

    /// Unit tests: every dependency a mock the test can script and inspect.
    static func test(api: MockPlatformAPI = MockPlatformAPI(), health: MockHealthStore = MockHealthStore(),
                     clock: TestClock = TestClock(), notifier: MockNotifier? = nil,
                     auth: AuthService? = nil, flags: [FeatureFlag: Bool] = [:],
                     online: Bool = true) -> AppEnvironment {
        AppEnvironment(
            settings: .shared, health: health, liveAPI: api, demoAPI: api, auth: auth ?? .preview(),
            persistence: TrainStore(inMemory: true), clock: clock, notifier: notifier ?? MockNotifier(),
            flags: StaticFlags(flags), connectivity: .preview(online: online), demoOverride: false)
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
