import Foundation
import Testing
@testable import Ryft

// Agree and continue moves on at the consent's `204`; uploads wait for RYFT's own word on it (ADR 0025,
// docs/work/2026-11-22-consent-agree-lag/design.md §7, T1–T11). Synthetic data only.

/// Holds the first `count` calls it's asked to until `release()`; later ones go through at once. `waiting` says how many
/// are held: tests poll it (never a fixed sleep) before they act on a request in flight.
final class FirstCallsHold: @unchecked Sendable {
    private let lock = NSLock()
    private let hold = RequestHold()
    private var left: Int

    init(_ count: Int = 1) { left = count }

    var waiting: Int { hold.waiting }

    func wait() async {
        let held = lock.withLock { () -> Bool in
            guard left > 0 else { return false }
            left -= 1
            return true
        }
        if held { await hold.wait() }
    }

    func release() { hold.release() }
}

/// What a closure saw, for a test to read afterwards.
private final class Seen<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?
    var value: Value? { lock.withLock { stored } }
    func record(_ value: Value) { lock.withLock { stored = value } }
}

/// How often the coordinator's `startSync` ran.
@MainActor
private final class AgreeStarts {
    var runs = 0
}

/// What an environment is built over: the same again for the next process on this iPhone.
@MainActor
private struct AgreeGround {
    let api: MockPlatformAPI
    let health: MockHealthStore
    let auth: AuthService
    let settings: Settings
    let persistence: TrainStore
    let clock: TestClock
    let defaults: UserDefaults
    /// Demo data can be switched on (`settings.demoMode`); otherwise the graph is pinned to the account.
    let demoSwitch: Bool

    func environment(_ connectivity: ConnectivityMonitor) -> AppEnvironment {
        let env = AppEnvironment(settings: settings, health: health, liveAPI: api, demoAPI: api, auth: auth,
                                 persistence: persistence, clock: clock, notifier: MockNotifier(),
                                 flags: StaticFlags([:]), connectivity: connectivity, defaults: defaults,
                                 demoOverride: demoSwitch ? nil : false)
        env.reads.random = { $0.lowerBound }
        env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
        env.uploader.random = { $0.lowerBound }
        env.consent.isProtectedDataAvailable = { true }
        return env
    }
}

/// A real `AuthService` whose wipe works on the test store, an environment around it on the test clock, the fake
/// platform (`MockPlatformAPI`, its own Train source), and a first-run coordinator whose gates ScreenModels wires.
@MainActor
private final class AgreeHarness {
    nonisolated static let a = UUID(uuidString: "0000000A-0000-4000-8000-0000000000A9") ?? UUID()
    nonisolated static let b = UUID(uuidString: "0000000B-0000-4000-8000-0000000000B9") ?? UUID()
    nonisolated static let version = MockData.policyVersion

    let clock = TestClock()
    let api = MockPlatformAPI(train: MockTrainSource())
    let persistence = TrainStore(inMemory: true)
    let defaults: UserDefaults
    let settings: Settings
    let client: MockAuthClient
    let auth: AuthService
    let health: MockHealthStore
    private let ground: AgreeGround
    /// The network path, as tests switch it (`update`).
    let connectivity = ConnectivityMonitor.preview(online: true)
    let env: AppEnvironment
    let state: AppState
    let status = APIStatus()
    let onboarding: OnboardingCoordinator
    let starts = AgreeStarts()

    init(health: MockHealthStore = MockHealthStore(), demoSwitch: Bool = false) {
        self.health = health
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        self.defaults = defaults
        settings = Settings(defaults: defaults)
        // On by default in the simulator: off, the account's side.
        settings.demoMode = false
        client = MockAuthClient(session: .preview(id: Self.a))
        let clock = clock, persistence = persistence
        auth = AuthService(client: client, settings: settings, defaults: defaults,
                           wipeLocalData: { wipe in persistence.wipe(parkingActivitiesOf: wipe.parking, at: clock.now()) },
                           deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                           postAppleAuthorization: { _ in })
        api.now = { clock.now() }
        let ground = AgreeGround(api: api, health: health, auth: auth, settings: settings, persistence: persistence,
                                 clock: clock, defaults: defaults, demoSwitch: demoSwitch)
        self.ground = ground
        env = ground.environment(connectivity)
        state = AppState(env: env)
        let starts = starts
        onboarding = OnboardingCoordinator(state: state, apiStatus: status) { starts.runs += 1 }
        env.uploader.gate = { [onboarding] in onboarding.uploadGate(for: .activities, write: $0) }
        api.reportsGates = status
    }

    var consent: ConsentState { env.consent }
    var account: String { auth.accountID ?? "-" }

    /// Signed in as A, without consent, the first run's check done: the consent step on screen.
    func ready() async throws {
        api.accountConsent = nil
        await onboarding.check()
        try #require(onboarding.flowStep == .consent, "the consent step: \(onboarding.missing)")
        try #require(consent.isPolicyFresh(at: clock.now()), "the policy is fresh: Agree reads nothing first")
    }

    func signIn(_ id: UUID) async {
        client.signInSession = .preview(id: id)
        _ = await auth.logIn(email: "alex@example.com", password: "0123456789")
    }

    /// The app's account-change handler (RyftApp), after `auth.accountID` changed from `old`.
    func accountChanged(from old: String?) {
        state.accountChanged(from: old)
        onboarding.switchAccount(auth.accountID)
    }

    /// A SyncService with the coordinator's gate, as ScreenModels wires it.
    func sync() -> SyncService {
        let sync = SyncService.ungated(env: env)
        sync.gate = { [onboarding] in onboarding.uploadGate(for: .healthKit) }
        return sync
    }

    /// The sync's status door (`SyncCoordinator`'s poll and pull), as the app builds it.
    func syncSteps() -> LiveSyncSteps { LiveSyncSteps(state: state, sync: sync(), apiStatus: status) }

    /// What the platform's 10 s status cache holds: `gate` as it was when it was cached.
    func cachedStatus(gate: APIErrorCode?) -> SyncStatus {
        SyncStatus(gate: gate, lastSyncAt: nil, lastSyncDevice: nil, latest: [:],
                   today: TodayState(day: DayFormat.string(from: clock.now()), state: .scored, scoredAt: nil,
                                     modelVersion: "2026.10.1"),
                   pendingDays: [], expectedWithinSec: 20, resyncRequestedAt: nil)
    }

    /// The next process on this iPhone: a new environment over the same store, defaults and session, and a new
    /// coordinator with a fresh `APIStatus`.
    func relaunched(online: Bool) -> (OnboardingCoordinator, AgreeStarts) {
        let next = ground.environment(.preview(online: online))
        let starts = AgreeStarts()
        let coordinator = OnboardingCoordinator(state: AppState(env: next), apiStatus: APIStatus()) { starts.runs += 1 }
        return (coordinator, starts)
    }

    /// A HealthKit page of one heart-rate sample.
    static func page(_ value: Double = 60) -> HealthDelta {
        HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: value, unit: "bpm", source: "W")])
    }
}

@MainActor
@Suite("Consent: Agree moves on at the 204, uploads wait for RYFT's word (ADR 0025)", .serialized)
struct ConsentAgreeTests {
    fileprivate typealias H = AgreeHarness

    // MARK: T1, T2: the step at the 204, the gate at RYFT's word

    @Test("T1: the next step shows at the 204, with /v1/me, the config and the status still out; only /v1/me is asked",
          .timeLimit(.minutes(1)))
    func theNextStepShowsAtThe204() async throws {
        let h = H()
        try await h.ready()
        let me = FirstCallsHold(), config = FirstCallsHold(), status = FirstCallsHold()
        h.api.beforeMe = { await me.wait() }
        h.api.beforeConfig = { await config.wait() }
        h.api.beforeSyncStatus = { await status.wait() }
        let configs = h.api.count("config"), statuses = h.api.count("syncStatus")

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { me.waiting == 1 }, "RYFT asked again: \(h.api.calls)")
        #expect(h.onboarding.flowStep == .aboutYou, "the next step: \(h.onboarding.missing)")
        #expect(!h.onboarding.isWorking)
        #expect(h.api.count("consent") == 1)
        #expect(h.api.count("config") == configs && h.api.count("syncStatus") == statuses, "only /v1/me: \(h.api.calls)")

        me.release()
        config.release()
        status.release()
        #expect(await agreeing.value)
        #expect(h.onboarding.flowStep == .aboutYou)
    }

    @Test("T2: every data path waits for RYFT's word, erasure doesn't; the first sync starts once /v1/me shows the consent",
          .timeLimit(.minutes(1)))
    func uploadsWaitForRyftsWord() async throws {
        let h = H()
        try await h.ready()
        let me = FirstCallsHold()
        h.api.beforeMe = { await me.wait() }

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { me.waiting == 1 })
        try #require(h.onboarding.flowStep == .aboutYou)
        for path in [UploadPath.healthKit, .activities, .train, .trainImport] {
            #expect(h.onboarding.uploadGate(for: path) == .gate(.consentRequired), "\(path) waits")
        }
        #expect(h.onboarding.uploadGate(for: .activities, write: .erasure) == nil, "erasure goes")
        #expect(h.onboarding.uploadGate(for: .train, write: .erasure) == nil, "erasure goes")
        #expect(h.starts.runs == 0)
        #expect(h.consent.unsettledAgreement == H.version)

        me.release()
        #expect(await agreeing.value)
        #expect(h.consent.agreement?.settled == true && h.consent.unsettledAgreement == nil)
        for path in [UploadPath.healthKit, .activities, .train, .trainImport] {
            #expect(h.onboarding.uploadGate(for: path) == nil, "\(path) open")
        }
        #expect(h.starts.runs == 1, "the first sync, once")
    }

    // MARK: T3: the status cache (R2) and real refusals (R4)

    @Test("T3a: the sign-in's status, asked before the 204 and answered after it, bounces nothing", .timeLimit(.minutes(1)))
    func aStatusFromBeforeThe204BouncesNothing() async throws {
        let h = H()
        try await h.ready()
        let status = FirstCallsHold()
        h.api.beforeSyncStatus = { await status.wait() }
        // A check asked before the tap: its status says consent_required (read when it arrives), and is held.
        let checking = Task { await h.onboarding.check(force: true) }
        #expect(await eventually { status.waiting == 1 })
        h.clock.advance(by: .seconds(1))

        #expect(await h.onboarding.agree())
        #expect(h.onboarding.uploadGate(for: .healthKit) == nil, "open after /v1/me")
        status.release()
        await checking.value
        #expect(h.onboarding.flowStep == .aboutYou, "nothing bounces: \(h.onboarding.missing)")
        #expect(h.onboarding.uploadGate(for: .healthKit) == nil)
        #expect(h.consent.refusals.isEmpty && h.status.gates.isEmpty)
    }

    @Test("T3b: at the 204 + 3 s, a cached consent_required says nothing, in either status door", .timeLimit(.minutes(1)))
    func aCachedStatusSaysNothingInEitherDoor() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        try #require(h.onboarding.uploadGate(for: .healthKit) == nil)
        h.api.syncStatusOverride = h.cachedStatus(gate: .consentRequired)
        h.clock.advance(by: .seconds(3))
        let statuses = h.api.count("syncStatus")

        await h.onboarding.check(force: true)
        #expect(h.api.count("syncStatus") == statuses + 1, "\(h.api.calls)")
        #expect(h.onboarding.flowStep == .aboutYou && h.onboarding.uploadGate(for: .healthKit) == nil, "onboarding's check")
        #expect(h.consent.refusals.isEmpty && h.status.gates.isEmpty, "onboarding's check")

        _ = try await h.syncSteps().syncStatus(userInitiated: true)
        #expect(h.api.count("syncStatus") == statuses + 2, "\(h.api.calls)")
        #expect(h.onboarding.flowStep == .aboutYou && h.onboarding.uploadGate(for: .healthKit) == nil, "the sync's door")
        #expect(h.consent.refusals.isEmpty && h.status.gates.isEmpty, "the sync's door")
    }

    @Test("T3c: at the 204 + 11 s the status speaks again: the consent step shows and the refusal is kept",
          .timeLimit(.minutes(1)), arguments: [true, false])
    func aStatusAfterTheCacheTimeSpeaks(onboardingsCheck: Bool) async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        h.api.syncStatusOverride = h.cachedStatus(gate: .consentRequired)
        h.clock.advance(by: .seconds(11))

        if onboardingsCheck {
            await h.onboarding.check(force: true)
        } else {
            _ = try await h.syncSteps().syncStatus(userInitiated: true)
        }
        #expect(h.onboarding.flowStep == .consent, "\(h.onboarding.missing)")
        #expect(h.consent.refusals == [.consentRequired])
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
    }

    @Test("T3c: an upload's 403 consent_required at the 204 + 2 s wins at once", .timeLimit(.minutes(1)))
    func anUploadsRefusalWinsAtOnce() async throws {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [H.page()]])
        let h = H(health: health)
        try await h.ready()
        #expect(await h.onboarding.agree())
        try #require(h.onboarding.uploadGate(for: .healthKit) == nil)
        h.clock.advance(by: .seconds(2))
        // RYFT doesn't hold it after all (withdrawn elsewhere): the upload hears so, fresh from the user's row.
        h.api.enforcesConsent = true
        h.api.accountConsent = nil

        let sync = h.sync()
        _ = try await sync.upload()
        #expect(sync.pausedFor == .gate(.consentRequired))
        #expect(h.consent.refusals == [.consentRequired])
        #expect(h.onboarding.flowStep == .consent, "\(h.onboarding.missing)")
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
    }

    // MARK: T4, T5: RYFT's word fails, or says no

    @Test("T4: RYFT's word doesn't come: the next step stays, without a word, the gate closed; a check within 60 s asks",
          .timeLimit(.minutes(1)), arguments: [FaultInjection.Fault.offline, .unavailable, .timeout])
    func aFailedReReadLeavesTheStepAndTheGateClosed(_ fault: FaultInjection.Fault) async throws {
        let h = H()
        try await h.ready()
        h.api.faults["me"] = .init(fault)
        let reads = h.api.count("me")

        #expect(await h.onboarding.agree())
        #expect(h.api.count("me") > reads, "asked: \(h.api.calls)")
        #expect(h.onboarding.flowStep == .aboutYou)
        #expect(h.onboarding.errorMessage == nil, "no word: \(h.onboarding.errorMessage ?? "nil")")
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(h.starts.runs == 0)
        #expect(h.consent.unsettledAgreement == H.version)
        #expect(AgreeTiming.load(h.env)?.confirmed?.hasPrefix("failed") == true, "\(AgreeTiming.load(h.env)?.line ?? "-")")

        // Within the 60 s a check is answered from the last one: not while RYFT's word is out.
        h.api.faults["me"] = nil
        let before = h.api.count("me")
        await h.onboarding.check()
        #expect(h.api.count("me") == before + 1, "\(h.api.calls)")
        #expect(h.consent.agreement?.settled == true)
        #expect(h.onboarding.uploadGate(for: .healthKit) == nil)
        #expect(h.onboarding.flowStep == .aboutYou)
    }

    @Test("T4: back online, an agreement RYFT hasn't confirmed is asked about again; once settled, nothing more",
          .timeLimit(.minutes(1)))
    func backOnlineAsksAgain() async throws {
        let h = H()
        try await h.ready()
        h.api.faults["me"] = .init(.offline)
        #expect(await h.onboarding.agree())
        h.api.faults["me"] = nil
        h.connectivity.update(false)
        let before = h.api.count("me")

        await h.onboarding.check()
        #expect(h.api.count("me") == before, "offline: nothing is sent")
        #expect(h.onboarding.flowStep == .aboutYou && h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))

        h.connectivity.update(true)
        await h.onboarding.reconnected()
        #expect(h.api.count("me") == before + 1, "\(h.api.calls)")
        #expect(h.onboarding.uploadGate(for: .healthKit) == nil)
        await h.onboarding.reconnected()
        #expect(h.api.count("me") == before + 1, "settled: coming back online asks nothing of its own")
    }

    @Test("T5: RYFT's word, asked after the 204, has no consent: the consent step shows again, and nothing uploads",
          .timeLimit(.minutes(1)))
    func anAnswerWithoutTheConsentShowsTheStepAgain() async throws {
        let h = H()
        try await h.ready()
        let api = h.api
        api.beforeMeRead = { api.accountConsent = nil }

        #expect(await h.onboarding.agree())
        #expect(h.onboarding.flowStep == .consent, "\(h.onboarding.missing)")
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(h.starts.runs == 0)
        #expect(h.consent.agreement?.settled == true, "RYFT's word was heard, and it decides")
        #expect(AgreeTiming.load(h.env)?.confirmed == "no_consent")
    }

    // MARK: T6, T7: another side, a second tap

    enum Leaving: String, CaseIterable, Sendable {
        case signOut, anotherAccount, demoData
    }

    @Test("T6: signed out, another account or Demo data while RYFT's word is out: nothing of A's goes on",
          .timeLimit(.minutes(1)), arguments: Leaving.allCases)
    func leavingDuringTheReReadEndsIt(_ leaving: Leaving) async throws {
        let h = H(demoSwitch: leaving == .demoData)
        h.state.bindAccountHooks(h.auth, apiStatus: h.status)
        try await h.ready()
        let me = FirstCallsHold()
        h.api.beforeMe = { await me.wait() }
        let a = h.account

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { me.waiting == 1 })
        switch leaving {
        case .signOut:
            await h.auth.signOut()
            h.accountChanged(from: a)
        case .anotherAccount:
            await h.signIn(H.b)
            h.accountChanged(from: a)
        case .demoData:
            // As Profile's switch does it.
            h.settings.demoMode = true
            h.state.reset()
        }
        me.release()

        #expect(await agreeing.value == false)
        #expect(h.starts.runs == 0, "no sync for A")
        #expect(!h.onboarding.isWorking)
        #expect(h.persistence.document(AgreeTiming.self, key: AgreeTiming.documentKey) == nil, "no line for A")
        switch leaving {
        case .signOut, .anotherAccount:
            #expect(h.state.repository.user() == nil, "A's answer isn't stored")
            #expect(h.persistence.document(ConsentState.Record.self, key: ConsentState.key(a)) == nil,
                    "A's record isn't written after the wipe")
        case .demoData:
            #expect(h.env.isDemo)
        }
        guard leaving == .anotherAccount else { return }
        // B's steps are free: B's own Agree sends, and B's agreement is B's.
        #expect(h.consent.agreement == nil)
        try await h.ready()
        #expect(await h.onboarding.agree())
        #expect(h.api.count("consent") == 2 && h.onboarding.flowStep == .aboutYou)
        #expect(h.starts.runs == 1)
    }

    @Test("T7: a second Agree while RYFT's word is out sends nothing, and the line counts it", .timeLimit(.minutes(1)))
    func aSecondAgreeDuringTheReReadSendsNothing() async throws {
        let h = H()
        try await h.ready()
        let me = FirstCallsHold()
        h.api.beforeMe = { await me.wait() }

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { me.waiting == 1 })
        #expect(await h.onboarding.agree() == false)
        #expect(h.api.count("consent") == 1)

        me.release()
        #expect(await agreeing.value)
        #expect(h.api.count("consent") == 1 && h.starts.runs == 1)
        #expect(AgreeTiming.load(h.env)?.busyTaps == 1)
    }

    // MARK: T8: the POST, fail-fast

    @Test("T8: the POST is one attempt on the fail-fast session", .timeLimit(.minutes(1)))
    func thePostIsOneAttempt() async throws {
        let h = H()
        try await h.ready()
        let single = Seen<Bool>()
        h.api.beforeConsent = { single.record(APIClient.singleAttempt) }

        #expect(await h.onboarding.agree())
        #expect(single.value == true)
        #expect(AgreeTiming.load(h.env)?.session == .failFast)
    }

    @Test("T8: no answer in time, and RYFT has the consent: asked again once, it moves on, settled", .timeLimit(.minutes(1)))
    func noAnswerButRyftHasIt() async throws {
        let h = H()
        try await h.ready()
        let post = Gate()
        let api = h.api
        // RYFT records the consent, and its answer never comes.
        api.beforeConsent = {
            api.accountConsent = Consent(policyVersion: H.version, grantedAt: .now)
            await post.wait()
        }
        let sleeps = h.clock.pendingSleeps, reads = h.api.count("me")

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { h.onboarding.isWorking && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await agreeing.value)
        #expect(h.api.count("me") == reads + 1, "asked again once: \(h.api.calls)")
        #expect(h.onboarding.errorMessage == nil, "\(h.onboarding.errorMessage ?? "nil")")
        #expect(h.onboarding.flowStep == .aboutYou)
        #expect(h.consent.agreement?.settled == true)
        #expect(h.onboarding.uploadGate(for: .healthKit) == nil && h.starts.runs == 1)
        #expect(AgreeTiming.load(h.env)?.confirmed == "ok")
        await post.open()
    }

    @Test("T8: no answer in time, and RYFT doesn't show the consent: it may still have arrived, try again",
          .timeLimit(.minutes(1)))
    func noAnswerAndRyftDoesntShowIt() async throws {
        let h = H()
        try await h.ready()
        let post = Gate()
        h.api.beforeConsent = { await post.wait() }
        let sleeps = h.clock.pendingSleeps, reads = h.api.count("me")

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { h.onboarding.isWorking && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await agreeing.value == false)
        #expect(h.api.count("me") == reads + 1, "asked again once: \(h.api.calls)")
        #expect(h.onboarding.errorMessage == OnboardingCoordinator.consentUnansweredMessage)
        #expect(h.onboarding.flowStep == .consent && !h.onboarding.isWorking)
        #expect(h.consent.agreement == nil)
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired) && h.starts.runs == 0)
        await post.open()
    }

    @Test("T8: offline, nothing is sent and it says so at once", .timeLimit(.minutes(1)))
    func offlineSendsNothing() async throws {
        let h = H()
        try await h.ready()
        h.connectivity.update(false)

        #expect(await h.onboarding.agree() == false)
        #expect(h.api.count("consent") == 0)
        #expect(h.onboarding.errorMessage == String(localized: "No connection. Check your internet and try again."))
        #expect(h.onboarding.flowStep == .consent && h.consent.agreement == nil)
    }

    @Test("T8: a 503 is said at once in RYFT's words, after one attempt; trying again agrees", .timeLimit(.minutes(1)))
    func aBusyPlatformSaysSoAtOnce() async throws {
        let h = H()
        try await h.ready()
        h.api.faults["consent"] = .init(.unavailable)

        #expect(await h.onboarding.agree() == false)
        #expect(h.api.count("consent") == 1)
        #expect(h.onboarding.errorMessage == "RYFT is catching up. Try again in a moment.")
        #expect(h.onboarding.flowStep == .consent && h.consent.agreement == nil)

        h.api.faults["consent"] = nil
        #expect(await h.onboarding.agree())
        #expect(h.api.count("consent") == 2 && h.onboarding.flowStep == .aboutYou)
    }

    // MARK: T9, T10: the withdrawal, the next process

    @Test("T9: a withdrawal while RYFT's word is out goes at once; the late answer is dropped, the gate stays closed",
          .timeLimit(.minutes(1)))
    func aWithdrawalDuringTheReReadWins() async throws {
        let h = H()
        try await h.ready()
        let me = FirstCallsHold()
        h.api.beforeMe = { await me.wait() }

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { me.waiting == 1 })
        // Later than the re-read was asked: the Repository takes no /v1/me asked before this phone's change of the user.
        h.clock.advance(by: .seconds(1))
        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.api.count("revokeConsent") == 1 }, "goes without waiting: \(h.api.calls)")
        #expect(await eventually { h.consent.withdrawnAt != nil })
        #expect(h.consent.agreement == nil, "the agreement goes with it")
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(me.waiting == 1, "the re-read is still out")

        me.release()
        #expect(await agreeing.value)
        #expect(await withdrawing.value)
        #expect(h.state.repository.user()?.consent == nil, "the late answer, with the consent, was dropped")
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(h.starts.runs == 0)
        #expect(AgreeTiming.load(h.env)?.confirmed == "dropped")
    }

    @Test("T10: the next process, offline, with RYFT's word still out: no consent step, the gate closed",
          .timeLimit(.minutes(1)))
    func theNextProcessKeepsTheAgreement() async throws {
        let h = H()
        try await h.ready()
        h.api.faults["me"] = .init(.offline)
        #expect(await h.onboarding.agree())
        try #require(h.consent.unsettledAgreement == H.version)

        let (next, starts) = h.relaunched(online: false)
        await next.check()
        #expect(!next.missing.contains(.consent), "\(next.missing)")
        #expect(next.flowStep == .aboutYou)
        #expect(next.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(starts.runs == 0)
    }

    // MARK: T11: the agree line

    @Test("T11: the agree line under the test clock: the marks of §6.2, and no date, time, account, device or request ID",
          .timeLimit(.minutes(1)))
    func theAgreeLine() async throws {
        let h = H()
        try await h.ready()
        let clock = h.clock, status = h.status
        let requestID = "req-7f3a9c2e-1b4d-4e8f-9a6b-0c2d4e6f8a1b"
        // The POST takes 3 s; APIClient records its one attempt (2 980 ms on the wire, with its request ID).
        h.api.beforeConsent = {
            clock.advance(by: .milliseconds(3_000))
            await MainActor.run {
                status.served(.init(date: .now, method: "POST", path: "/v1/me/consent", status: 204,
                                    requestID: requestID, durationMs: 2_980))
            }
        }
        // RYFT's word takes 500 ms more.
        h.api.beforeMe = { clock.advance(by: .milliseconds(500)) }

        #expect(await h.onboarding.agree())
        h.onboarding.stepShown(h.onboarding.flowStep)
        let line = try #require(AgreeTiming.load(h.env)?.line)
        #expect(line == "agree: sent +0 · answered +3000 (204; attempts 204/2980) · step +3000 · shown +3500 · "
            + "confirmed +3500 ok · committed +3500 · session fail_fast · policy_read no · busy_taps 0")

        let forbidden: [(String, String)] = [
            ("a date", #"\d{4}-\d{2}-\d{2}"#),
            ("a time of day", #"\b\d{1,2}:\d{2}\b"#),
            ("a UUID", #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"#),
            ("a request ID", #"req-"#),
            ("a device", #"(?i)iphone|ipad|watch"#),
        ]
        for (what, pattern) in forbidden {
            #expect(line.range(of: pattern, options: .regularExpression) == nil, "\(what) in \(line)")
        }
        #expect(!line.contains(h.account) && !line.contains(H.a.uuidString), "the account in \(line)")
        #expect(!line.contains(H.version), "the policy version in \(line)")
        #expect(!line.contains(requestID))
    }

    // MARK: Review round 1, code review S1: asking again has a deadline

    @Test("S1: no answer, and RYFT's /v1/me doesn't come either: within 10 s it says so, and the late answer still lands",
          .timeLimit(.minutes(1)))
    func askingAgainAfterNoAnswerHasADeadline() async throws {
        let h = H()
        try await h.ready()
        let post = Gate(), me = FirstCallsHold()
        let api = h.api
        // RYFT records the consent, and its answer never comes; asked again, its /v1/me is held too.
        api.beforeConsent = {
            api.accountConsent = Consent(policyVersion: H.version, grantedAt: .now)
            await post.wait()
        }
        api.beforeMe = { await me.wait() }
        let sleeps = h.clock.pendingSleeps

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { h.onboarding.isWorking && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await eventually { me.waiting == 1 && h.clock.pendingSleeps > sleeps }, "asked again, its wait running")
        h.clock.advance(by: OnboardingCoordinator.checkTimeout)
        #expect(await eventually(timeout: .seconds(5)) { !h.onboarding.isWorking }, "the wait ended, the read didn't")
        #expect(h.onboarding.errorMessage == OnboardingCoordinator.consentUnansweredMessage)
        #expect(h.onboarding.flowStep == .consent && h.consent.agreement == nil)

        me.release()
        #expect(await agreeing.value == false)
        // The read went on in the pipeline: its answer, with the consent, is stored. The next check sees it (the sign-in's
        // status refusal, kept, goes with RYFT's newer word), and the flow moves on.
        #expect(await eventually { h.state.repository.user()?.consent?.policyVersion == H.version })
        await h.onboarding.check(force: true)
        #expect(h.onboarding.flowStep == .aboutYou, "\(h.onboarding.missing)")
        await post.open()
    }

    @Test("S1: a withdrawal with no answer, and RYFT's /v1/me doesn't come either: within 10 s it says so",
          .timeLimit(.minutes(1)))
    func askingAgainAfterAnUnansweredWithdrawalHasADeadline() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        let delete = Gate(), me = FirstCallsHold()
        h.api.beforeRevokeConsent = { await delete.wait() }
        h.api.beforeMe = { await me.wait() }
        let sleeps = h.clock.pendingSleeps

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.onboarding.isWithdrawing && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await eventually { me.waiting == 1 && h.clock.pendingSleeps > sleeps }, "asked again, its wait running")
        h.clock.advance(by: OnboardingCoordinator.checkTimeout)
        #expect(await eventually(timeout: .seconds(5)) { !h.onboarding.isWithdrawing }, "the wait ended, the read didn't")
        #expect(h.onboarding.errorMessage == OnboardingCoordinator.withdrawalUnansweredMessage)
        #expect(h.consent.withdrawnAt == nil)

        me.release()
        #expect(await withdrawing.value == false)
        await delete.open()
    }

    // MARK: Code review S3: the gate holds while the agreement is unsettled

    @Test("S3: a consent cached from before and a refusal the 204 clears: nothing goes until RYFT's word asked after the 204",
          .timeLimit(.minutes(1)))
    func aCachedConsentWaitsForRyftsWordToo() async throws {
        let h = H()
        h.api.accountConsent = Consent(policyVersion: H.version, grantedAt: h.clock.now())
        await h.onboarding.check()
        try #require(h.state.repository.user()?.consent?.policyVersion == H.version)
        // An upload's 403 consent_required, kept: the consent step, over the consent cached from before.
        h.consent.refused(.consentRequired, at: h.clock.now())
        try #require(h.onboarding.flowStep == .consent, "\(h.onboarding.missing)")
        let end = h.clock.now()
        try #require(h.env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900), end: end)) != nil)
        let me = FirstCallsHold()
        h.api.beforeMe = { await me.wait() }

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { me.waiting == 1 })
        #expect(h.onboarding.flowStep == .aboutYou)
        for path in [UploadPath.healthKit, .activities, .train, .trainImport] {
            #expect(h.onboarding.uploadGate(for: path) == .gate(.consentRequired), "\(path) waits")
        }
        await h.env.uploader.flush()
        #expect(h.api.count("putActivity") == 0, "nothing went: \(h.api.calls)")

        me.release()
        #expect(await agreeing.value)
        #expect(h.consent.agreement?.settled == true)
        #expect(h.onboarding.uploadGate(for: .activities) == nil)
        await h.env.uploader.flush()
        #expect(h.api.count("putActivity") == 1, "\(h.api.calls)")
    }

    // MARK: Security review N-1: no first sync while a withdrawal is on its way

    @Test("T9b: RYFT's word comes while a withdrawal is on its way: no first sync", .timeLimit(.minutes(1)))
    func noFirstSyncDuringAWithdrawal() async throws {
        let h = H()
        try await h.ready()
        let me = FirstCallsHold(), delete = FirstCallsHold()
        h.api.beforeMe = { await me.wait() }
        h.api.beforeRevokeConsent = { await delete.wait() }

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { me.waiting == 1 })
        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { delete.waiting == 1 })
        me.release()
        #expect(await agreeing.value)
        #expect(h.consent.agreement?.settled == true, "RYFT's word came first")
        #expect(h.starts.runs == 0, "no sync while the withdrawal is on its way")

        delete.release()
        #expect(await withdrawing.value)
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(h.starts.runs == 0)
    }
}
