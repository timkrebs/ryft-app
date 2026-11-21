import Foundation
import Testing
@testable import Ryft

/// The app's models over an account beside a switchable Demo data (`settings.demoMode`), each side with its own platform.
@MainActor
struct OnboardingDemoSideGraph {
    let state: AppState
    let live: MockPlatformAPI
    let demo: MockPlatformAPI
    let screens: ScreenModels

    init() {
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let settings = Settings(defaults: defaults)
        // In the simulator a fresh install starts in demo data: this graph starts on the account.
        settings.demoMode = false
        let live = MockPlatformAPI()
        let demo = MockPlatformAPI()
        let auth = AuthService(client: MockAuthClient(session: .preview()), settings: settings, defaults: defaults,
                               wipeLocalData: { _ in true },
                               deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
        let env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: live, demoAPI: demo, auth: auth,
                                 persistence: TrainStore(inMemory: true), clock: SystemClock(), notifier: MockNotifier(),
                                 flags: StaticFlags(), connectivity: .preview(online: true), defaults: defaults,
                                 demoOverride: nil)
        // The switch's refresh: no jitter, no budget to wait for.
        env.reads.random = { $0.lowerBound }
        env.reads.budget = RequestBudget(clock: env.clock, maxStarts: .max)
        let state = AppState(env: env)
        state.repository.widgetFile = nil
        let sync = SyncService(env: env)
        screens = ScreenModels(state: state, sync: sync,
                               coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                               store: TrainPreview.store, library: TrainPreview.library, apiStatus: APIStatus())
        self.state = state
        self.live = live
        self.demo = demo
    }
}

/// PR 6 security close-out: an onboarding failure, its sentence and request ID, is the side's. Profile → Privacy shows it
/// (`consentError`, `consentErrorDetails`), so the Demo data switch takes it, both ways, through the account-state
/// forgetters `ScreenModels` connects (Profile's switch runs them with `AppState.reset()`). Synthetic data only.
@MainActor
@Suite("Onboarding's failure goes with the Demo data switch", .serialized)
struct OnboardingDemoSideTests {
    @Test("The account's failed withdrawal isn't in Demo data's Profile, and Demo data's isn't in the account's",
          .timeLimit(.minutes(1)))
    func aFailureGoesWithTheSwitch() async {
        let g = OnboardingDemoSideGraph()
        let profile = g.screens.profile
        g.live.faults["revokeConsent"] = .init(.status(500, retryAfter: nil))
        await profile.withdrawConsent()
        #expect(g.live.count("revokeConsent") == 1)
        #expect(profile.consentError != nil)
        #expect(profile.consentErrorDetails?.contains("Request ID fault-revokeConsent") == true, "\(profile.consentErrorDetails ?? "nil")")

        await profile.setDemoMode(true)
        #expect(g.state.env.isDemo)
        #expect(g.screens.onboarding.errorMessage == nil && g.screens.onboarding.errorDetails == nil,
                "the account's failure and request ID stay out of Demo data")
        #expect(profile.consentError == nil && profile.consentErrorDetails == nil)

        g.demo.faults["revokeConsent"] = .init(.status(500, retryAfter: nil))
        await profile.withdrawConsent()
        #expect(g.demo.count("revokeConsent") == 1 && g.live.count("revokeConsent") == 1)
        #expect(profile.consentErrorDetails != nil)

        await profile.setDemoMode(false)
        #expect(!g.state.env.isDemo)
        #expect(g.screens.onboarding.errorMessage == nil && g.screens.onboarding.errorDetails == nil,
                "and Demo data's stays out of the account's")
        #expect(profile.consentError == nil && profile.consentErrorDetails == nil)
        withExtendedLifetime(g.screens) {}
    }
}
