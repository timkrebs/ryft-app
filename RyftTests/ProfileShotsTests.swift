import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes Profile's main list (design.md §P5-6) as 3x PNGs, whole pages (`PagedWindowShot`), at the default size and at
/// AX3 when `PROFILE_SHOTS_DIR` is set; otherwise does nothing. Run it with `TEST_RUNNER_PROFILE_SHOTS_DIR=<dir> xcodebuild …
/// -only-testing:RyftTests/ProfileShotsTests test-without-building` and compare the set with the board's measurements. Drawn
/// from a real window (`drawHierarchy`); for comparing, not a golden-file test. Synthetic data only (Alex Doe).
@MainActor
@Suite("T5.4: Profile, shots", .serialized)
struct ProfileShotsTests {
    /// One state per test case (both sizes).
    @Test(arguments: Self.names)
    func writeScreen(_ name: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["PROFILE_SHOTS_DIR"] else { return }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            // A graph per size: the demo-exit refusal and the failed sync are each one step on fresh models.
            let graph = try await ProfileShotGraph.make(name)
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                       graph.view) { w in
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/profile-\(name)-\(size).png"))
            }
            await graph.releaseWithdrawal()
            graph.tearDown()
        }
    }

    nonisolated static let names = ["signed-in", "demo", "signed-out", "sync-issue", "demo-exit-error", "withdrawing"]
}

/// Thrown by a Train store that can't be read: the demo exit's refusal (review R12).
private struct UnreadableStore: Error {}

/// Profile on a graph of its own: the Demo data switch and the session as the state needs, the app's screen models.
@MainActor
struct ProfileShotGraph {
    /// Each graph's own defaults: suites run side by side never share a store.
    let suite: String
    let state: AppState
    let settings: Settings
    let sync: SyncService
    let screens: ScreenModels
    /// Kept alive for the demo-exit state: its coordinator is the one Profile asks.
    let rig: DemoTrainRig?
    /// The session's client: a test signs another account in through it.
    let client: MockAuthClient
    /// The "withdrawing" state's `DELETE /v1/me/consent`, held open until `releaseWithdrawal()`.
    var withdrawal: Gate?

    var view: AnyView {
        AnyView(ProfileView()
            .environment(\.appEnvironment, state.env)
            .environment(screens)
            .environment(settings)
            .environment(state.env.auth)
            .environment(sync)
            .environment(state)
            .environment(TrainPreview.library)
            .environment(TrainPreview.sync)
            .environment(TrainPreview.coordinator)
            .environment(state.env.connectivityMonitor)
            .environment(\.locale, Locale(identifier: "en_US"))
            .toggleStyle(.ryft)
            .tint(Theme.textPrimary))
    }

    func tearDown() {
        state.env.defaults.removePersistentDomain(forName: suite)
    }

    /// Lets the held withdrawal answer and waits until Profile says so (nothing to do for the other states).
    func releaseWithdrawal() async {
        guard let withdrawal else { return }
        await withdrawal.open()
        _ = await eventually { !screens.profile.withdrawingConsent }
    }

    static func make(_ name: String) async throws -> ProfileShotGraph {
        switch name {
        case "signed-in": return graph(demo: false, signedIn: true, lastSync: .now)
        // Demo data on over a signed-in Apple account: the account's rows are the session's, never the demo's person.
        case "demo": return graph(demo: true, signedIn: true, provider: "apple")
        case "signed-out": return graph(demo: true, signedIn: false)
        case "sync-issue":
            // A signed-in account whose last upload failed (500): Profile's notice under the sync rows.
            let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [heartRate(3)]])
            let api = MockPlatformAPI(activities: .demoSource())
            api.failNext = APIError.http(500, "")
            let g = graph(demo: false, signedIn: true, lastSync: .now.addingTimeInterval(-5 * 3_600), health: health, api: api)
            await g.sync.syncNow()
            return g
        case "demo-exit-error":
            // Demo data on with a workout the store can't read: turning it off is refused, and says so (review R12).
            let rig = DemoTrainRig()
            let g = graph(demo: true, signedIn: false, rig: rig)
            rig.startWorkout("Live")
            rig.sync.fetchSessions = { _, _ in throw UnreadableStore() }
            _ = g.screens.profile.switchingDemoOff()
            return g
        case "withdrawing":
            // D6: the confirmation's Withdraw consent tapped, the request on its way: Demo data and Log out held.
            var g = graph(demo: false, signedIn: true, lastSync: .now)
            let gate = Gate()
            g.withdrawal = gate
            let api = try #require(g.state.env.api as? MockPlatformAPI)
            api.beforeRevokeConsent = { await gate.wait() }
            let profile = g.screens.profile
            Task { await profile.withdrawConsent() }
            let held = await eventually { profile.withdrawingConsent }
            try #require(held, "the withdrawal is on its way")
            return g
        default:
            throw UnreadableStore()
        }
    }

    private static func graph(demo: Bool, signedIn: Bool, provider: String = "email", lastSync: Date? = nil,
                              health: MockHealthStore = MockHealthStore(),
                              api: MockPlatformAPI = MockPlatformAPI(activities: .demoSource()),
                              rig: DemoTrainRig? = nil) -> ProfileShotGraph {
        let suite = "ryft.test.profile-shots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let settings = Settings(defaults: defaults)
        settings.demoMode = demo
        // Apple Health's last good upload: "up to date" needs one.
        settings.lastSync = lastSync
        // `AuthService.preview`'s session in the graph's own defaults: a sign-out here leaves nothing for other suites.
        let client = MockAuthClient(session: signedIn ? .preview(provider: provider) : nil)
        let auth = AuthService(client: client, defaults: defaults,
                               wipeLocalData: { _ in true },
                               deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
        let env = AppEnvironment(settings: settings, health: health, liveAPI: api, demoAPI: api,
                                 auth: auth, persistence: TrainStore(inMemory: true),
                                 clock: SystemClock(), notifier: MockNotifier(),
                                 flags: StaticFlags([.devicesSetup: true, .trainImport: true]),
                                 connectivity: .preview(online: true), defaults: defaults, demoOverride: demo)
        env.uploader.gate = { _ in nil }
        let state = AppState(env: env)
        state.repository.widgetFile = nil
        state.history = MockData.history
        state.user = MockData.user
        state.insights = MockData.insights
        state.today = MockData.todayDetail
        let sync = SyncService.ungated(env: env)
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock)
        let screens = ScreenModels(state: state, sync: sync, coordinator: coordinator, store: TrainPreview.store,
                                   library: TrainPreview.library, apiStatus: APIStatus(), train: rig?.coordinator)
        // The policy in force is the demo account's: its consent is current.
        sync.gate = { nil }
        return ProfileShotGraph(suite: suite, state: state, settings: settings, sync: sync, screens: screens, rig: rig,
                                client: client)
    }

    private static func heartRate(_ n: Int) -> HealthDelta {
        let t = Date(timeIntervalSince1970: 1_792_300_000)
        return HealthDelta(samples: (0..<n).map {
            Sample(type: .heartRate, start: t.addingTimeInterval(Double($0) * 60), end: t.addingTimeInterval(Double($0) * 60),
                   value: 60, unit: "bpm", source: "Alex's Apple Watch")
        })
    }
}
