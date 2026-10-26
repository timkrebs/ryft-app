import Foundation
import Testing
@testable import Ryft

/// Profile → Log out → "Send first" (design.md §8.4, privacy review): it logs out only the account that tapped it,
/// and isn't offered when nothing can be sent.
@MainActor
private struct SendFirstGraph {
    static let a = UUID(uuidString: "0000000A-0000-4000-8000-0000000000F1") ?? UUID()
    static let b = UUID(uuidString: "0000000B-0000-4000-8000-0000000000F2") ?? UUID()

    let clock = TestClock()
    let api = MockPlatformAPI()
    let client = MockAuthClient(session: .preview(id: SendFirstGraph.a))
    let auth: AuthService
    let env: AppEnvironment
    let state: AppState
    let profile: ProfileViewModel

    init(online: Bool = true) {
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        auth = AuthService(client: client, settings: Settings(defaults: defaults), defaults: defaults,
                           wipeLocalData: { _ in }, deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                           postAppleAuthorization: { _ in })
        env = .test(api: api, clock: clock, auth: auth, flags: [.activitiesManual: true], online: online)
        env.uploader.random = { $0.lowerBound }
        env.uploader.gate = { nil } // consent given: what goes up, goes up
        state = AppState(env: env)
        state.bindAccountHooks(auth)
        let sync = SyncService(env: env)
        profile = ProfileViewModel(state: state, sync: sync,
                                   coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: clock),
                                   apiStatus: APIStatus())
    }

    /// A run that ended an hour ago, saved for the signed-in account.
    @discardableResult
    func saveRun() -> UUID? {
        let end = clock.now().addingTimeInterval(-3_600)
        return env.activities.save(manual: ActivityDraft(sport: .running, start: end.addingTimeInterval(-1_800), end: end))?.id
    }
}

@Suite("Profile: Send first before logging out")
@MainActor
struct SendFirstTests {
    @Test func whenEverythingWentUpTheAccountIsLoggedOut() async throws {
        let g = SendFirstGraph()
        try #require(g.saveRun() != nil)
        #expect(g.profile.unconfirmedActivities == 1 && g.profile.sendFirst == .available)

        #expect(await g.profile.sendFirstThenLogOut() == .loggedOut)

        #expect(!g.auth.isSignedIn)
    }

    @Test func anotherAccountSignedInMeanwhileStaysSignedIn() async throws {
        let g = SendFirstGraph()
        try #require(g.saveRun() != nil)
        let hold = RequestHold()
        g.api.activitySource.beforeWrite = { await hold.wait() }
        let sending = Task { await g.profile.sendFirstThenLogOut() }
        #expect(await eventually { hold.waiting == 1 })
        // A's session ends while the PUT is out, and B signs in.
        await g.auth.rejectedAfterRefresh()
        g.client.signInSession = .preview(id: SendFirstGraph.b)
        _ = await g.auth.logIn(email: "b@example.com", password: "0123456789")
        hold.release()

        #expect(await sending.value == .accountChanged)

        #expect(g.auth.accountID == SendFirstGraph.b.uuidString, "B isn't logged out by A's Send first")
    }

    @Test func offlineItIsNotOfferedAndLogsNobodyOut() async throws {
        let g = SendFirstGraph(online: false)
        try #require(g.saveRun() != nil)
        #expect(g.profile.sendFirst == .offline)

        #expect(await g.profile.sendFirstThenLogOut() == .unsent(1))

        #expect(g.auth.isSignedIn && g.api.calls.isEmpty)
    }

    @Test func withDemoDataOnItIsNotOffered() throws {
        // Demo data's client is in use: the account's rows can't go up.
        let env = AppEnvironment.preview(flags: [.activitiesManual: true])
        let state = AppState(env: env)
        let sync = SyncService(env: env)
        let profile = ProfileViewModel(state: state, sync: sync,
                                       coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                                       apiStatus: APIStatus())
        #expect(env.isDemo)
        #expect(profile.sendFirst == .unavailable)
    }

    @Test func behindTheConsentGateItIsNotOffered() throws {
        let g = SendFirstGraph()
        g.env.uploader.gate = { .gate(.consentRequired) }
        #expect(g.profile.sendFirst == .unavailable)
        g.env.uploader.gate = { .policyUnknown }
        #expect(g.profile.sendFirst == .unavailable)
    }

    @Test func offlineWithThePolicyUnknownItSaysOffline() throws {
        let g = SendFirstGraph(online: false)
        g.env.uploader.gate = { .policyUnknown }
        #expect(g.profile.sendFirst == .offline)
    }
}
