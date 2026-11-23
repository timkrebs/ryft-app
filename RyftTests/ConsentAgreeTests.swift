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

    /// Profile over this graph, with the coordinator, as ScreenModels builds it.
    func profile() -> ProfileViewModel {
        let sync = sync()
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync, apiStatus: status), clock: clock)
        return ProfileViewModel(state: state, sync: sync, coordinator: coordinator, onboarding: onboarding, apiStatus: status)
    }

    /// Sync details for `sync`, with the coordinator or without one.
    func details(_ sync: SyncService, onboarding: OnboardingCoordinator?) -> SyncDetailsModel {
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync, apiStatus: status), clock: clock)
        return SyncDetailsModel(state: state, sync: sync, coordinator: coordinator, apiStatus: status, onboarding: onboarding)
    }

    /// ScreenModels over this graph, as the app builds it (its own onboarding, the import's coordinator and uploader).
    func screens() -> ScreenModels {
        let sync = SyncService.ungated(env: env)
        let store = TrainStore(inMemory: true)
        let outbox = TrainSyncService.preview(store: store)
        let library = TrainLibrary(store: store, remote: { [api] in api }, outbox: { outbox }, restore: false)
        let steps = LiveSyncSteps(state: state, sync: sync, apiStatus: status)
        return ScreenModels(state: state, sync: sync, coordinator: SyncCoordinator(steps: steps, clock: clock),
                            store: store, library: library, apiStatus: status)
    }

    /// Train's outbox for A, its gate the coordinator's, as ScreenModels wires it.
    func trainOutbox() -> TrainSyncService {
        let api = api, account = account
        let train = TrainSyncService(store: persistence, remote: { api }, owner: { account }, debounce: .seconds(3_600),
                                     monitorsNetwork: false, connectivity: connectivity, defaults: defaults)
        train.gate = { [onboarding] in onboarding.uploadGate(for: .train, write: $0) }
        return train
    }

    /// Agreed, and RYFT's word on it didn't come (its re-read offline): the agreement unsettled, `/v1/me` answering again.
    func agreedUnsettled() async throws {
        try await ready()
        api.faults["me"] = .init(.offline)
        try #require(await onboarding.agree())
        api.faults["me"] = nil
        try #require(consent.unsettledAgreement == Self.version)
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

    @Test("Round 6, 3: Agree's POST still reads a 502 or 504 as a plain failure: no re-read, the DELETE's gateway rule is its own",
          .timeLimit(.minutes(1)), arguments: [502, 504])
    func agreeTreatsABadGatewayAsAPlainFailure(_ status: Int) async throws {
        let h = H()
        try await h.ready()
        let reads = h.api.count("me")
        h.api.faults["consent"] = .init(.status(status, retryAfter: nil))

        #expect(await h.onboarding.agree() == false)
        #expect(h.api.count("consent") == 1)
        #expect(h.api.count("me") == reads, "no re-read: \(h.api.calls)")
        #expect(h.onboarding.errorMessage != nil && h.onboarding.errorMessage != OnboardingCoordinator.consentUnansweredMessage)
        #expect(h.onboarding.flowStep == .consent && h.consent.agreement == nil)
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
        // Its sentence belonged to the consent step: gone with it, not on About you (code review round 2, 2).
        #expect(await eventually(timeout: .seconds(5)) { h.onboarding.errorMessage == nil }, "\(h.onboarding.errorMessage ?? "-")")
        await post.open()
    }

    @Test("Code 2: RYFT shows the consent while the POST is out, and Agree ends without an answer: no sentence stays",
          .timeLimit(.minutes(1)))
    func aConsentHeardDuringTheFlightLeavesNoSentence() async throws {
        let h = H()
        try await h.ready()
        let post = Gate(), me = FirstCallsHold()
        let api = h.api
        api.beforeConsent = { await post.wait() }
        let sleeps = h.clock.pendingSleeps

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { h.onboarding.isWorking && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        // Given elsewhere meanwhile, and heard here: the consent step goes while the POST is out.
        api.accountConsent = Consent(policyVersion: H.version, grantedAt: .now)
        await h.onboarding.check(force: true)
        #expect(!h.onboarding.missing.contains(.consent), "\(h.onboarding.missing)")
        // No answer; asked again, /v1/me doesn't come in time either: Agree fails with its step already gone.
        api.beforeMe = { await me.wait() }
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await eventually { me.waiting == 1 }, "asked again")
        #expect(await eventually(timeout: .seconds(10)) {
            h.clock.advance(by: OnboardingCoordinator.checkTimeout)
            return !h.onboarding.isWorking
        }, "the wait ended, the read didn't")
        #expect(await agreeing.value == false)
        #expect(h.onboarding.errorMessage == nil, "\(h.onboarding.errorMessage ?? "-")")
        me.release()
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

    @Test("T9b: RYFT's word comes while a withdrawal is on its way: no first sync, and every data path waits",
          .timeLimit(.minutes(1)))
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
        // Settled, and still nothing goes while the DELETE is out (security review round 2, S-1); erasure does.
        for path in [UploadPath.healthKit, .activities, .train, .trainImport] {
            #expect(h.onboarding.uploadGate(for: path) != nil, "\(path) waits for the withdrawal")
        }
        #expect(h.onboarding.uploadGate(for: .activities, write: .erasure) == nil, "erasure goes")
        #expect(!h.onboarding.missing.contains(.consent), "the flow doesn't count it: \(h.onboarding.missing)")
        let end = h.clock.now()
        try #require(h.env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900), end: end)) != nil)
        await h.env.uploader.flush()
        #expect(h.api.count("putActivity") == 0, "nothing went: \(h.api.calls)")

        delete.release()
        #expect(await withdrawing.value)
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(h.starts.runs == 0)
        #expect(h.api.count("putActivity") == 0)
    }

    // MARK: Security review N-3: an agreement from after now is void

    @Test("N-3: an agreement from after now (the clock set back) is void: the stored user decides; it counts once passed",
          .timeLimit(.minutes(1)))
    func anAgreementFromAfterNowIsVoid() async throws {
        let h = H()
        // A consent cached from before and a kept refusal, as in S3: the agreement is what holds the gate.
        h.api.accountConsent = Consent(policyVersion: H.version, grantedAt: h.clock.now())
        await h.onboarding.check()
        h.consent.refused(.consentRequired, at: h.clock.now())
        h.api.faults["me"] = .init(.offline)
        #expect(await h.onboarding.agree())
        h.api.faults["me"] = nil
        let agreedAt = try #require(h.consent.agreement?.at)
        try #require(h.consent.unsettledAgreement == H.version)
        try #require(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired), "held for RYFT's word (S3)")

        // The clock was ahead when Agree was tapped: set back an hour.
        h.clock.set(agreedAt.addingTimeInterval(-3_600))
        #expect(h.consent.unsettledAgreement == nil && h.consent.agreement?.settled == false)
        #expect(h.consent.statusSpeaksForConsent(askedAt: h.clock.now()))
        // The stored user decides: its consent counts. The policy answer is from after now too, so it holds as unknown.
        #expect(!h.onboarding.missing.contains(.consent), "\(h.onboarding.missing)")
        #expect(h.onboarding.uploadGate(for: .healthKit) == .policyUnknown)

        // Once the clock passes it, it counts again, until RYFT's word asked after it.
        h.clock.set(agreedAt.addingTimeInterval(1))
        #expect(h.consent.unsettledAgreement == H.version)
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
        await h.onboarding.check()
        #expect(h.consent.agreement?.settled == true)
        #expect(h.onboarding.uploadGate(for: .healthKit) == nil)
    }

    // MARK: Code review S2: Privacy, Sync details and the import while the agreement is unsettled

    @Test("S2: Privacy while RYFT's word is out: given, not confirmed yet, neutral; Check with RYFT asks, Withdraw is there",
          .timeLimit(.minutes(1)))
    func privacyWhileUnsettled() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let profile = h.profile()
        #expect(profile.consentAwaitsConfirmation && !profile.consentNeedsAttention)
        // Given: RYFT recorded it at the 204; only this iPhone waits (security review round 2, N2).
        #expect(profile.consentText == String(localized: "Given"))
        #expect(profile.consentDetail
            == String(localized: "RYFT has recorded your consent. This iPhone starts syncing once it hears back."))
        #expect(ProfileRows.rows(.privacy, ProfileRowFacts(profile, journalLive: false, bedtimeEnabled: true))
            == [.consent, .checkConsent, .withdrawConsent])
        #expect(profile.canCheckConsent && profile.consentCheckMessage == nil)

        let reads = h.api.count("me")
        await profile.checkConsent()
        #expect(h.api.count("me") == reads + 1, "asked again: \(h.api.calls)")
        #expect(h.onboarding.sheetStep == nil, "nothing opened")
        #expect(!profile.consentAwaitsConfirmation && profile.consentIsCurrent)
        #expect(profile.consentText == String(localized: "Given"))
        #expect(ProfileRows.rows(.privacy, ProfileRowFacts(profile, journalLive: false, bedtimeEnabled: true))
            == [.consent, .withdrawConsent])
    }

    @Test("S2: Check with RYFT, and RYFT doesn't have it: Not given, and Review and agree", .timeLimit(.minutes(1)))
    func checkingFindsNoConsent() async throws {
        let h = H()
        try await h.agreedUnsettled()
        h.api.accountConsent = nil
        let profile = h.profile()
        await profile.checkConsent()
        #expect(!profile.consentAwaitsConfirmation && profile.consentNeedsAttention)
        #expect(profile.consentText == String(localized: "Not given"))
        #expect(ProfileRows.rows(.privacy, ProfileRowFacts(profile, journalLive: false, bedtimeEnabled: true))
            == [.consent, .reviewConsent])
    }

    @Test("S2: Withdraw from a consent not confirmed yet: held while on its way, then Not given", .timeLimit(.minutes(1)))
    func withdrawingAnUnconfirmedConsent() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let delete = FirstCallsHold()
        h.api.beforeRevokeConsent = { await delete.wait() }
        let profile = h.profile()

        let withdrawing = Task { await profile.withdrawConsent() }
        #expect(await eventually { delete.waiting == 1 })
        #expect(profile.withdrawingConsent, "Demo data and Log out are held")
        #expect(profile.consentDetail == String(localized: "Withdrawing your consent. Nothing syncs while it's on its way."))
        #expect(!profile.canCheckConsent, "no check while it's on its way")
        delete.release()
        await withdrawing.value
        #expect(h.consent.withdrawnAt != nil && h.consent.agreement == nil)
        #expect(!profile.withdrawingConsent && !profile.consentAwaitsConfirmation)
        #expect(profile.consentText == String(localized: "Not given"))
    }

    @Test("S4, S2: Sync details while RYFT's word is out: the sync and the workouts wait, Paused, not Action needed",
          .timeLimit(.minutes(1)))
    func syncDetailsWhileUnsettled() async throws {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [H.page()]])
        let h = H(health: health)
        try await h.agreedUnsettled()
        let sync = h.sync()
        _ = try await sync.upload()
        try #require(sync.pausedFor == .gate(.consentRequired))
        let train = h.trainOutbox()
        _ = await train.finish(SessionFactory.empty(in: h.persistence))
        try #require(train.pendingCount > 0 && train.heldAt == .gate(.consentRequired))

        let details = h.details(sync, onboarding: h.onboarding)
        details.trainOutbox = train
        #expect(details.idleState == .paused)
        #expect(details.workoutsHeldText == String(localized: "Waiting for RYFT to confirm your consent"))
        let without = h.details(sync, onboarding: nil)
        without.trainOutbox = train
        #expect(without.idleState == .actionNeeded(.consent), "no coordinator: the hold's own gate")
        #expect(without.workoutsHeldText == String(localized: "Action needed: agree to the privacy policy"))
    }

    @Test("S2: the import's gate pause is I8 only when onboarding asks for a step")
    func theImportsGatePause() {
        func flow(_ hold: UploadGate, _ pending: OnboardingCoordinator.Step??) -> ImportFlowModel {
            ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.status(.paused(.gated(hold)))),
                                pendingGate: pending)
        }
        #expect(!flow(.gate(.consentRequired), .some(nil)).gateAsksForStep, "agreed here, RYFT's word out")
        #expect(flow(.gate(.consentRequired), .some(.consent)).gateAsksForStep)
        #expect(flow(.gate(.consentRequired), nil).gateAsksForStep, "no coordinator: the hold's own gate")
        #expect(!flow(.policyUnknown, .some(.consent)).gateAsksForStep)
        #expect(!ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.status(.paused(.held))))
            .gateAsksForStep)
    }

    // MARK: Code review S4: T3d, and Paused

    @Test("T3d: a /v1/me asked before the tap and answered after it settles nothing and bounces nothing; the follow-up does",
          .timeLimit(.minutes(1)))
    func aReadFromBeforeTheTapSettlesNothing() async throws {
        let h = H()
        try await h.ready()
        let early = FirstCallsHold()
        h.api.beforeMe = { await early.wait() }
        // Asked before the tap (read when it arrives: no consent yet), and held on its way back.
        let refreshing = Task { try? await h.state.repository.refreshUser(force: true) }
        #expect(await eventually { early.waiting == 1 })
        h.clock.advance(by: .seconds(1))
        let follow = FirstCallsHold()
        h.api.beforeMe = { await follow.wait() }

        let agreeing = Task { await h.onboarding.agree() }
        #expect(await eventually { h.consent.unsettledAgreement == H.version })
        early.release()
        await refreshing.value
        #expect(await eventually { follow.waiting == 1 }, "the follow-up, asked after the 204: \(h.api.calls)")
        #expect(h.state.repository.user()?.consent == nil, "the early answer is stored")
        #expect(h.consent.unsettledAgreement == H.version, "and settles nothing")
        #expect(h.onboarding.flowStep == .aboutYou, "nothing bounces: \(h.onboarding.missing)")
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(h.starts.runs == 0)

        follow.release()
        #expect(await agreeing.value)
        #expect(h.consent.agreement?.settled == true)
        #expect(h.onboarding.uploadGate(for: .healthKit) == nil && h.starts.runs == 1)
    }

    @Test("S4: a gate's hold no step answers is Paused, not Action needed; without onboarding, the hold's own gate")
    func aHoldNoStepAnswersIsPaused() {
        func decide(_ hold: UploadGate, _ pending: OnboardingCoordinator.Step??) -> SyncIdleState {
            SyncIdleState.decide(pausedFor: hold, pendingGate: pending, offline: false, failed: false, backfillDone: true,
                                 backlog: false, uploaded: true)
        }
        let consent = UploadGate.gate(.consentRequired)
        #expect(decide(consent, .some(nil)) == .paused, "agreed here, RYFT's word out")
        #expect(decide(consent, .some(.consent)) == .actionNeeded(.consent))
        #expect(decide(consent, nil) == .actionNeeded(.consent), "no coordinator")
        #expect(decide(.gate(.inviteRequired), .some(.invite)) == .actionNeeded(.invite))
        #expect(decide(.gate(.inviteRequired), nil) == .actionNeeded(.invite))
        #expect(decide(.policyUnknown, .some(.consent)) == .paused)
        #expect(SyncIdleState.held(at: .demo, pendingGate: .some(.consent)) == nil)
    }

    // MARK: Code review N2: the scoring wait's gate

    @Test("N2: the scoring wait reads a status's gate by R2: consent_required at the 204 + 3 s is none, at + 11 s it's one",
          .timeLimit(.minutes(1)))
    func theScoringWaitReadsTheGateByR2() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        let steps = h.syncSteps()
        h.api.syncStatusOverride = h.cachedStatus(gate: .consentRequired)
        h.clock.advance(by: .seconds(3))
        let early = try await steps.syncStatus(userInitiated: true)
        #expect(early.gate == .consentRequired && steps.scoringGate(of: early) == nil)

        h.clock.advance(by: .seconds(8))
        let late = try await steps.syncStatus(userInitiated: true)
        #expect(steps.scoringGate(of: late) == .consentRequired)
        #expect(steps.scoringGate(of: h.cachedStatus(gate: .inviteRequired)) == .inviteRequired, "not consent's: as it is")
    }
    // MARK: Review round 2, security S-1: the withdrawal's hold

    @Test("S-1: a withdrawal's own re-read settles nothing: RYFT may record the DELETE after it", .timeLimit(.minutes(1)))
    func aWithdrawalsReReadSettlesNothing() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let delete = Gate()
        h.api.beforeRevokeConsent = { await delete.wait() }
        let sleeps = h.clock.pendingSleeps

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.onboarding.isWithdrawing && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        let reads = h.api.count("me")
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await withdrawing.value == false)
        #expect(h.api.count("me") == reads + 1, "asked again: \(h.api.calls)")
        #expect(h.state.repository.user()?.consent?.policyVersion == H.version, "RYFT still shows the consent")
        // Answered in time, with the consent, but the agreement is still unsettled and the gate is closed: not "syncing
        // continues" (round 6, 1b), the sentence for a withdrawal that may still have arrived.
        #expect(h.onboarding.errorMessage == OnboardingCoordinator.withdrawalUnansweredMessage)
        #expect(h.consent.unsettledAgreement == H.version, "the re-read settled nothing")
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(h.starts.runs == 0)
        await delete.open()
    }

    @Test("Round 6, 1a: a withdrawal without an answer, its re-read an older policy's consent: the gate is closed, so not \"didn't reach RYFT\"",
          .timeLimit(.minutes(1)))
    func aReReadWithAnOlderConsentIsNotAWithdrawalThatDidntReach() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        try #require(h.consent.unsettledAgreement == nil && h.consent.latestPolicyVersion == H.version, "settled, the latest policy")
        let delete = Gate()
        h.api.beforeRevokeConsent = { await delete.wait() }
        // RYFT, asked again, still shows a consent, to an older version than the latest one.
        h.api.accountConsent = Consent(policyVersion: "2026-01-01", grantedAt: h.clock.now())
        let sleeps = h.clock.pendingSleeps

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.onboarding.isWithdrawing && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await withdrawing.value == false)
        #expect(h.state.repository.user()?.consent?.policyVersion == "2026-01-01", "RYFT showed the older consent")
        #expect(h.consent.withdrawalUnresolvedSince == nil && h.consent.withdrawnAt != nil, "the answer recorded the withdrawal")
        #expect(h.onboarding.uploadGate(for: .healthKit) == .gate(.consentRequired), "the gate is closed")
        #expect(h.onboarding.errorMessage == OnboardingCoordinator.withdrawalUnansweredMessage)
        #expect(h.onboarding.errorMessage != OnboardingCoordinator.withdrawalNotReachedMessage)
        await delete.open()
    }

    // MARK: Review round 2, code 1 and 2: RYFT's late answer

    @Test("Code 1: a withdrawal that landed without an answer, its /v1/me late: the late answer opens no consent sheet",
          .timeLimit(.minutes(1)))
    func aLateWithdrawalAnswerOpensNoSheet() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        h.onboarding.reachedTabs()
        try #require(!h.onboarding.isFirstRun && h.onboarding.accountHint == nil)
        let delete = Gate(), me = FirstCallsHold()
        let api = h.api
        // RYFT records the withdrawal, and its answer never comes; asked again, its /v1/me is held past the deadline.
        api.beforeRevokeConsent = {
            api.accountConsent = nil
            await delete.wait()
        }
        api.beforeMe = { await me.wait() }
        let sleeps = h.clock.pendingSleeps

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.onboarding.isWithdrawing && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await eventually { me.waiting == 1 && h.clock.pendingSleeps > sleeps }, "asked again, its wait running")
        h.clock.advance(by: OnboardingCoordinator.checkTimeout)
        #expect(await eventually(timeout: .seconds(5)) { !h.onboarding.isWithdrawing }, "the wait ended, the read didn't")
        #expect(h.onboarding.errorMessage == OnboardingCoordinator.withdrawalUnansweredMessage)

        me.release()
        #expect(await withdrawing.value == false)
        #expect(await eventually { h.state.repository.user().map { $0.consent == nil } ?? false }, "the late answer landed")
        #expect(h.onboarding.missing.contains(.consent), "\(h.onboarding.missing)")
        #expect(h.onboarding.sheetStep == nil, "no consent sheet over Profile on its own")
        // Asked for, it shows (Privacy's Review and agree, Today's action).
        h.onboarding.show(.consent)
        #expect(h.onboarding.sheetStep == .consent)
        await delete.open()
    }

    // MARK: Review round 2, code 5: a read during the void

    @Test("Code 5: a /v1/me heard while the agreement is void settles it: nothing waits for it once the clock passes it",
          .timeLimit(.minutes(1)))
    func aReadDuringTheVoidSettlesIt() async throws {
        let h = H()
        // As in N-3: a consent cached from before and a kept refusal, so the agreement is what holds the gate.
        h.api.accountConsent = Consent(policyVersion: H.version, grantedAt: h.clock.now())
        await h.onboarding.check()
        h.consent.refused(.consentRequired, at: h.clock.now())
        h.api.faults["me"] = .init(.offline)
        #expect(await h.onboarding.agree())
        h.api.faults["me"] = nil
        let agreedAt = try #require(h.consent.agreement?.at)
        try #require(h.consent.unsettledAgreement == H.version)

        h.clock.set(agreedAt.addingTimeInterval(-3_600))
        try await h.state.repository.refreshUser(mode: .latest, userInitiated: true)
        #expect(h.consent.agreement?.settled == true, "the stored user decides from now on")

        h.clock.set(agreedAt.addingTimeInterval(1))
        #expect(h.consent.unsettledAgreement == nil)
        #expect(h.onboarding.uploadGate(for: .healthKit) == nil, "nothing waits for it again")
    }

    // MARK: Review round 2, code 9: onboarding's status and the scoring wait

    @Test("Code 9: onboarding's status reaches the scoring wait with when it was asked for, not when it arrived",
          .timeLimit(.minutes(1)))
    func onboardingsStatusCountsFromItsAsk() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        let sync = h.sync()
        // As ScreenModels wires it.
        h.onboarding.statusReceived = { sync.receive($0, requestedAt: $1) }
        let steps = LiveSyncSteps(state: h.state, sync: sync, apiStatus: h.status)
        let held = FirstCallsHold()
        h.api.syncStatusOverride = h.cachedStatus(gate: .consentRequired)
        h.api.beforeSyncStatus = { await held.wait() }

        // Asked at the 204 + 3 s, within the platform's cache time; it arrives at + 11 s.
        h.clock.advance(by: .seconds(3))
        let checking = Task { await h.onboarding.check(force: true) }
        #expect(await eventually { held.waiting == 1 })
        h.clock.advance(by: .seconds(8))
        held.release()
        await checking.value
        let status = try #require(h.state.syncStatus)
        #expect(status.gate == .consentRequired && sync.statusReadAt == h.clock.now(), "arrived at + 11 s")
        #expect(steps.scoringGate(of: status) == nil, "asked at + 3 s: it says nothing about consent")
    }

    // MARK: Review round 2, code 3 and 7: Check with RYFT

    @Test("Code 3: offline, Check with RYFT is dimmed and sends nothing; the footer says when RYFT is asked again",
          .timeLimit(.minutes(1)))
    func checkingOffline() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let profile = h.profile()
        h.connectivity.update(false)
        #expect(!profile.canCheckConsent)
        #expect(profile.consentDetail == String(
            localized: "RYFT has recorded your consent. This iPhone asks RYFT again once it's back online, then starts syncing."))
        let reads = h.api.count("me")
        await profile.checkConsent()
        #expect(h.api.count("me") == reads && profile.consentCheckMessage == nil, "nothing sent, nothing said")

        h.connectivity.update(true)
        #expect(profile.canCheckConsent)
        #expect(profile.consentDetail
            == String(localized: "RYFT has recorded your consent. This iPhone starts syncing once it hears back."))
    }

    @Test("Code 3: a check that brings no word says so in one line; one that does clears it", .timeLimit(.minutes(1)))
    func aCheckWithoutAnAnswerSaysSo() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let profile = h.profile()
        h.api.faults["me"] = .init(.offline)
        await profile.checkConsent()
        #expect(profile.consentAwaitsConfirmation)
        #expect(profile.consentCheckMessage == String(localized: "RYFT didn't answer. Try again in a moment."))

        h.api.faults["me"] = nil
        await profile.checkConsent()
        #expect(!profile.consentAwaitsConfirmation && profile.consentCheckMessage == nil)
    }

    @Test("Code 3: Check with RYFT is the person's own read: a Retry-After window holds a reconnect, not the check",
          .timeLimit(.minutes(1)))
    func theCheckIsThePersonsOwnRead() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let profile = h.profile()
        h.env.reads.seed([.me: ResourceState(retryNotBefore: h.clock.now().addingTimeInterval(300))])
        let reads = h.api.count("me")
        await h.onboarding.reconnected()
        #expect(h.api.count("me") == reads, "held back: \(h.api.calls)")
        await profile.checkConsent()
        #expect(h.api.count("me") == reads + 1, "asked: \(h.api.calls)")
        #expect(!profile.consentAwaitsConfirmation && profile.consentCheckMessage == nil)
    }

    @Test("Code 7: Withdraw waits while Check with RYFT asks: nothing is sent", .timeLimit(.minutes(1)))
    func withdrawIsHeldWhileChecking() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let profile = h.profile()
        let me = FirstCallsHold()
        h.api.beforeMe = { await me.wait() }

        let checking = Task { await profile.checkConsent() }
        #expect(await eventually { me.waiting == 1 && profile.checkingConsent })
        await profile.withdrawConsent()
        #expect(h.api.count("revokeConsent") == 0 && !h.onboarding.isWithdrawing, "\(h.api.calls)")

        me.release()
        await checking.value
        #expect(!profile.checkingConsent && !profile.consentAwaitsConfirmation)
    }

    // MARK: Review round 2, security N1, code 6: a pause names its cause

    @Test("N1: a pause names its cause: RYFT's confirmation only while the agreement is unsettled, the policy, else nothing")
    func aPauseNamesItsCause() {
        typealias Cause = SyncIdleState.PauseCause
        #expect(Cause.of(.gate(.consentRequired), agreementUnsettled: true) == .confirmation)
        #expect(Cause.of(.gate(.consentRequired), agreementUnsettled: false) == .other, "the account not known, a withdrawal")
        #expect(Cause.of(.gate(.inviteRequired), agreementUnsettled: true) == .other)
        #expect(Cause.of(.policyUnknown, agreementUnsettled: true) == .policy)

        func flow(_ hold: UploadGate, _ pending: OnboardingCoordinator.Step??, unsettled: Bool) -> ImportFlowModel {
            ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.status(.paused(.gated(hold)))),
                                pendingGate: pending, agreementUnsettled: unsettled)
        }
        #expect(flow(.gate(.consentRequired), .some(nil), unsettled: true).gatedPauseCause == .confirmation)
        #expect(flow(.gate(.consentRequired), .some(nil), unsettled: false).gatedPauseCause == .other)
        #expect(flow(.policyUnknown, .some(nil), unsettled: true).gatedPauseCause == .policy)
        #expect(flow(.gate(.consentRequired), .some(.consent), unsettled: false).gatedPauseCause == nil, "a step: I8")
        #expect(ImportResultText.gatedWaiting(.confirmation)
            == String(localized: "It continues by itself once RYFT confirms your consent. Nothing to do here."))
        #expect(ImportResultText.gatedWaiting(.policy)
            == String(localized: "It continues by itself once the privacy policy has loaded. Nothing to do here."))
        #expect(ImportResultText.gatedWaiting(.other) == nil)
    }

    @Test("N1, S-1: Sync details during a withdrawal: the workouts wait, Paused, nothing named", .timeLimit(.minutes(1)))
    func syncDetailsDuringAWithdrawal() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        try #require(h.consent.agreement?.settled == true)
        let delete = FirstCallsHold()
        h.api.beforeRevokeConsent = { await delete.wait() }

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { delete.waiting == 1 })
        let train = h.trainOutbox()
        _ = await train.finish(SessionFactory.empty(in: h.persistence))
        try #require(train.pendingCount > 0 && train.heldAt == .gate(.consentRequired), "held while the DELETE is out")
        let details = h.details(h.sync(), onboarding: h.onboarding)
        details.trainOutbox = train
        #expect(details.workoutsHeldText == SyncDetailsModel.workoutsPausedText, "not RYFT's confirmation: nothing waits for it")

        delete.release()
        #expect(await withdrawing.value)
    }

    // MARK: Review round 3, S-2: a withdrawal without an answer

    @Test("S-2: a withdrawal that landed without an answer, its /v1/me late: nothing goes until RYFT is heard from after it",
          .timeLimit(.minutes(1)))
    func anUnansweredWithdrawalKeepsTheHold() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        try #require(h.consent.agreement?.settled == true)
        let train = h.trainOutbox()
        let delete = Gate(), me = FirstCallsHold()
        let api = h.api
        // RYFT records the withdrawal, and its answer never comes; asked again, its /v1/me is held past the deadline.
        api.beforeRevokeConsent = {
            api.accountConsent = nil
            await delete.wait()
        }
        api.beforeMe = { await me.wait() }
        let sleeps = h.clock.pendingSleeps

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.onboarding.isWithdrawing && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        h.clock.advance(by: SettingsWrite.deadline)
        let cancelled = h.clock.now()
        #expect(await eventually { me.waiting == 1 && h.clock.pendingSleeps > sleeps }, "asked again, its wait running")
        h.clock.advance(by: OnboardingCoordinator.checkTimeout)
        #expect(await withdrawing.value == false)
        #expect(h.onboarding.errorMessage == OnboardingCoordinator.withdrawalUnansweredMessage)

        // The stored user still shows the consent, and nothing goes: RYFT may have recorded the DELETE.
        #expect(!h.onboarding.isWithdrawing && h.state.repository.user()?.consent != nil)
        #expect(h.consent.withdrawalUnresolvedSince == cancelled)
        #expect(h.onboarding.uploadGate(for: .train) != nil, "Train's outbox waits")
        for path in [UploadPath.healthKit, .activities, .trainImport] {
            #expect(h.onboarding.uploadGate(for: path) != nil, "\(path) waits")
        }
        #expect(h.onboarding.uploadGate(for: .activities, write: .erasure) == nil, "erasure goes")
        _ = await train.finish(SessionFactory.empty(in: h.persistence))
        await train.flush()
        #expect(train.pendingCount > 0 && h.api.count("putSession") == 0, "nothing went: \(h.api.calls)")
        // The next process on this iPhone (a relaunch, a background launch) holds too.
        let (next, _) = h.relaunched(online: true)
        #expect(next.uploadGate(for: .train) != nil, "after a relaunch")
        #expect(next.uploadGate(for: .healthKit) != nil, "after a relaunch")

        // RYFT's late answer, asked after the attempt ended, resolves it: no consent, and the stored user holds from now.
        me.release()
        #expect(await eventually { h.consent.withdrawalUnresolvedSince == nil }, "the late read resolved it")
        #expect(h.state.repository.user().map { $0.consent == nil } ?? false)
        #expect(h.onboarding.uploadGate(for: .train) == .gate(.consentRequired))
        await train.flush()
        #expect(h.api.count("putSession") == 0)
        await delete.open()
    }

    @Test("S-2: a withdrawal without an answer ends on a /v1/me asked after it, an answered one, a new Agree, another account",
          .timeLimit(.minutes(1)))
    func anUnresolvedWithdrawalsEnds() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        let user = try #require(h.state.repository.user())
        func unresolved() -> Date {
            let at = h.clock.now()
            h.consent.withdrawalUnresolved(since: at)
            h.clock.advance(by: .seconds(1))
            return at
        }

        // A /v1/me asked for before it says nothing about it; one asked at or after it does, whatever it shows.
        let at = unresolved()
        h.state.repository.store(fetchedUser: user, askedAt: at.addingTimeInterval(-1))
        #expect(h.consent.withdrawalUnresolvedSince == at && h.onboarding.uploadGate(for: .train) != nil)
        h.state.repository.store(fetchedUser: user, askedAt: at)
        #expect(h.consent.withdrawalUnresolvedSince == nil && h.onboarding.uploadGate(for: .train) == nil)

        // The next check asks, even within its recheck interval, for a /v1/me asked after it.
        _ = unresolved()
        let reads = h.api.count("me")
        await h.onboarding.check()
        #expect(h.api.count("me") == reads + 1 && h.consent.withdrawalUnresolvedSince == nil)

        // A withdrawal answered, and a new Agree.
        _ = unresolved()
        h.consent.withdrew(at: h.clock.now())
        #expect(h.consent.withdrawalUnresolvedSince == nil)
        _ = unresolved()
        h.consent.consented(to: H.version, at: h.clock.now())
        #expect(h.consent.withdrawalUnresolvedSince == nil)

        // Another account: A's ends with it, and B's uploads aren't held by it.
        _ = unresolved()
        let a = h.account
        await h.signIn(H.b)
        h.accountChanged(from: a)
        #expect(h.defaults.object(forKey: ConsentState.unresolvedWithdrawalKey(a)) == nil)
        #expect(h.consent.withdrawalUnresolvedSince == nil)
    }

    // MARK: Review round 3, code 3: the sheet stays deferred

    @Test("Code 3: a withdrawal without an answer whose re-read still shows the consent: the sheet stays deferred",
          .timeLimit(.minutes(1)))
    func anUnansweredWithdrawalKeepsTheSheetDeferred() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        h.onboarding.reachedTabs()
        try #require(!h.onboarding.isFirstRun && !h.onboarding.deferred.contains(.consent))
        let delete = Gate()
        // The DELETE's answer never comes, and RYFT hasn't recorded it yet: the re-read, in time, shows the consent.
        h.api.beforeRevokeConsent = { await delete.wait() }
        let sleeps = h.clock.pendingSleeps

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.onboarding.isWithdrawing && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await withdrawing.value == false)
        // RYFT answered in time, with the consent: the withdrawal didn't reach it, syncing continues, and it's said so
        // plainly (round 5, option B).
        #expect(h.onboarding.errorMessage == OnboardingCoordinator.withdrawalNotReachedMessage)
        #expect(h.state.repository.user()?.consent != nil, "RYFT showed the consent")
        #expect(h.consent.withdrawalUnresolvedSince == nil && h.onboarding.uploadGate(for: .train) == nil, "syncing continues")
        #expect(h.onboarding.deferred.contains(.consent), "still deferred")

        // RYFT records the DELETE after the re-read: the next check shows the step, and no sheet opens on its own.
        h.api.accountConsent = nil
        await h.onboarding.check(force: true)
        #expect(h.onboarding.missing.contains(.consent), "\(h.onboarding.missing)")
        #expect(h.onboarding.sheetStep == nil, "no consent sheet over Profile on its own")
        h.onboarding.show(.consent)
        #expect(h.onboarding.sheetStep == .consent, "asked for, it shows")
        await delete.open()
    }

    // MARK: Review round 3, N-a and N-b: a withdrawal of a consent not confirmed yet

    @Test("N-a: withdrawing a consent not confirmed yet, on its way or without an answer: a pause names no confirmation",
          .timeLimit(.minutes(1)))
    func aPauseDuringAWithdrawalNamesNoConfirmation() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let train = h.trainOutbox()
        _ = await train.finish(SessionFactory.empty(in: h.persistence))
        try #require(train.pendingCount > 0 && train.heldAt == .gate(.consentRequired))
        let details = h.details(h.sync(), onboarding: h.onboarding)
        details.trainOutbox = train
        #expect(details.workoutsHeldText == String(localized: "Waiting for RYFT to confirm your consent"), "before")
        let delete = Gate(), me = FirstCallsHold()
        let api = h.api
        api.beforeRevokeConsent = { await delete.wait() }
        let sleeps = h.clock.pendingSleeps

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.onboarding.isWithdrawing && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        #expect(!h.onboarding.awaitsConfirmation)
        #expect(details.workoutsHeldText == SyncDetailsModel.workoutsPausedText, "on its way")
        // No answer, and RYFT not heard from since: the agreement is still unsettled, and the pause still names nothing.
        api.beforeMe = { await me.wait() }
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await eventually { me.waiting == 1 && h.clock.pendingSleeps > sleeps }, "asked again, its wait running")
        h.clock.advance(by: OnboardingCoordinator.checkTimeout)
        #expect(await withdrawing.value == false)
        try #require(h.consent.unsettledAgreement != nil && h.consent.withdrawalUnresolvedSince != nil)
        #expect(!h.onboarding.awaitsConfirmation && !h.consent.awaitsConfirmation, "with or without a coordinator")
        #expect(details.workoutsHeldText == SyncDetailsModel.workoutsPausedText, "without an answer")
        me.release()
        await delete.open()
    }

    @Test("N-b: withdrawing a consent not confirmed yet, the late answer shows none: settled, and Privacy says Not given",
          .timeLimit(.minutes(1)))
    func aLateAnswerWithoutTheConsentSettles() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let profile = h.profile()
        #expect(profile.consentAwaitsConfirmation && profile.consentText == String(localized: "Given"))
        let delete = Gate(), me = FirstCallsHold()
        let api = h.api
        // RYFT records the withdrawal, and its answer never comes; asked again, its /v1/me is held past the deadline.
        api.beforeRevokeConsent = {
            api.accountConsent = nil
            await delete.wait()
        }
        api.beforeMe = { await me.wait() }
        let sleeps = h.clock.pendingSleeps

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.onboarding.isWithdrawing && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        h.clock.advance(by: SettingsWrite.deadline)
        #expect(await eventually { me.waiting == 1 && h.clock.pendingSleeps > sleeps }, "asked again, its wait running")
        h.clock.advance(by: OnboardingCoordinator.checkTimeout)
        #expect(await withdrawing.value == false)
        #expect(profile.consentAwaitsConfirmation, "RYFT's word isn't in yet")

        // The withdrawal's own re-read, late, shows no consent: closing is always safe, so it settles.
        me.release()
        #expect(await eventually { h.consent.agreement?.settled == true }, "settled by the answer without the consent")
        #expect(!profile.consentAwaitsConfirmation)
        #expect(profile.consentText == String(localized: "Not given"))
        #expect(h.onboarding.uploadGate(for: .train) == .gate(.consentRequired))
        await delete.open()
    }

    // MARK: Review round 3, code S and 4: Check with RYFT's failure

    @Test("Code S, 4: a failure RYFT sent back is said in its own words, with Details; offline, no line",
          .timeLimit(.minutes(1)))
    func aCheckFailureHasItsWordsAndDetails() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let profile = h.profile()
        let unanswered = String(localized: "RYFT didn't answer. Try again in a moment.")
        // A 429 over the read's cap: it fails at once, with RYFT's answer in hand.
        h.api.faults["me"] = .init(.status(429, retryAfter: 600))
        await profile.checkConsent()
        let busy = APIError.http(429, "", requestID: "fault-me", retryAfter: 600)
        #expect(profile.consentAwaitsConfirmation)
        #expect(profile.consentCheckMessage == OnboardingCoordinator.fallbackMessage(for: busy))
        #expect(profile.consentCheckMessage != unanswered, "RYFT did answer")
        #expect(profile.consentCheckDetails == busy.diagnosticDetails, "\(profile.consentCheckDetails ?? "-")")
        #expect(profile.consentCheckDetails?.contains("fault-me") == true, "the request ID")

        // Offline: no line; the footer says when RYFT is asked again.
        h.connectivity.update(false)
        #expect(profile.consentCheckMessage == nil && profile.consentCheckDetails == nil)
        h.connectivity.update(true)
        #expect(profile.consentCheckMessage != nil, "back online, still unanswered")
    }

    // MARK: Review round 3, code 6: ScreenModels' wiring of onboarding's status

    @Test("Code 6: ScreenModels hands onboarding's status to the sync with when it was asked for: the ledger counts from then")
    func screenModelsPassTheStatusAskedTime() throws {
        let h = H()
        let sync = SyncService.ungated(env: h.env)
        let store = TrainStore(inMemory: true)
        let outbox = TrainSyncService.preview(store: store)
        let library = TrainLibrary(store: store, remote: { [api = h.api] in api }, outbox: { outbox }, restore: false)
        let steps = LiveSyncSteps(state: h.state, sync: sync, apiStatus: h.status)
        let screens = ScreenModels(state: h.state, sync: sync, coordinator: SyncCoordinator(steps: steps, clock: h.clock),
                                   store: store, library: library, apiStatus: h.status)
        let day = DayFormat.string(from: h.clock.now())
        let written = h.clock.now()
        sync.awaiting([day])
        try #require(sync.scoringLedger[day]?.kind == .pending)
        h.clock.advance(by: .seconds(30))
        let status = h.cachedStatus(gate: nil)

        // Arrived 30 s after the write, but asked 5 s after it: maybe the platform's cache from before the write.
        screens.onboarding.statusReceived?(status, written.addingTimeInterval(5))
        #expect(sync.scoringLedger[day]?.kind == .pending, "asked within the cache time: no answer to the write")
        screens.onboarding.statusReceived?(status, written.addingTimeInterval(ScoringWord.statusCacheTime))
        #expect(sync.scoringLedger[day] == nil, "asked after it: the write is answered")
    }

    // MARK: Review round 4, fixed in round 5

    /// A signed-in A who agreed with RYFT's word out and whose Check with RYFT failed with a `429`; `profile` shows the line.
    private func aFailedCheck(_ h: H) async throws -> ProfileViewModel {
        try await h.agreedUnsettled()
        let profile = h.profile()
        h.api.faults["me"] = .init(.status(429, retryAfter: 600))
        await profile.checkConsent()
        try #require(profile.consentCheckMessage != nil && profile.consentCheckDetails != nil, "A's line and its Details")
        return profile
    }

    @Test("Round 5, 1: Profile's account change forgets the failed Check with RYFT, its Details too", .timeLimit(.minutes(1)))
    func aCheckFailureDoesntOutliveTheAccount() async throws {
        let h = H()
        let profile = try await aFailedCheck(h)
        // RyftApp's handler, which also runs after a sign-out or another account. Called alone (the state's own reset would
        // run the forgetters, which clear the line too), with the agreement still waiting: only this handler clears it.
        profile.accountChanged(from: h.account)
        #expect(profile.consentAwaitsConfirmation, "an unsettled agreement is what shows the line")
        #expect(profile.consentCheckMessage == nil && profile.consentCheckDetails == nil)
    }

    @Test("Round 5, 1: the Demo data switch forgets the failed Check with RYFT too", .timeLimit(.minutes(1)))
    func aCheckFailureDoesntOutliveTheDemoSwitch() async throws {
        let h = H()
        let profile = try await aFailedCheck(h)
        // `setDemoMode` and `endDemo` both reset the state, which runs the account-state forgetters.
        h.state.reset()
        #expect(profile.consentAwaitsConfirmation)
        #expect(profile.consentCheckMessage == nil && profile.consentCheckDetails == nil)
    }

    @Test("Round 5, 2: a late answer without the consent records the withdrawal before the hold goes; a relaunch holds",
          .timeLimit(.minutes(1)))
    func aLateAnswerWithoutTheConsentRecordsTheWithdrawal() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        let consenting = try #require(h.state.repository.user())
        try #require(consenting.consent != nil)
        var none = consenting
        none.consent = nil

        // One that shows the consent to the policy in force records nothing: it only ends the hold.
        h.consent.withdrawalUnresolved(since: h.clock.now())
        h.clock.advance(by: .seconds(1))
        h.consent.heard(consenting, askedAt: h.clock.now())
        #expect(h.consent.withdrawalUnresolvedSince == nil && h.consent.withdrawnAt == nil)

        // One without it: the withdrawal is recorded, then the hold goes. The stored user still shows the consent (this
        // phone's save of the answer was refused), as it does after a relaunch.
        h.consent.withdrawalUnresolved(since: h.clock.now())
        h.clock.advance(by: .seconds(5))
        let asked = h.clock.now()
        h.consent.heard(none, askedAt: asked)
        #expect(h.consent.withdrawalUnresolvedSince == nil, "the hold ended")
        #expect(h.consent.withdrawnAt == asked, "and the withdrawal is recorded, as an answered one is")
        #expect(h.state.repository.user()?.consent != nil)
        #expect(h.onboarding.uploadGate(for: .train) == .gate(.consentRequired))
        let (next, _) = h.relaunched(online: true)
        #expect(next.uploadGate(for: .train) != nil, "after a relaunch")
        #expect(next.uploadGate(for: .healthKit) != nil, "after a relaunch")
    }

    @Test("Round 5, 3: a withdrawal hold from after now (the clock set back) is void: any stored /v1/me ends it",
          .timeLimit(.minutes(1)))
    func aWithdrawalHoldFromAfterNowIsVoid() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        let user = try #require(h.state.repository.user())
        let since = h.clock.now()
        h.consent.withdrawalUnresolved(since: since)
        try #require(h.onboarding.uploadGate(for: .train) != nil)

        // The clock was ahead when the attempt ended: set back an hour. A /v1/me asked now is "before" the hold.
        h.clock.set(since.addingTimeInterval(-3_600))
        h.state.repository.store(fetchedUser: user, askedAt: h.clock.now())
        #expect(h.consent.withdrawalUnresolvedSince == nil, "any stored answer ends it")
        // What holds it now is the stale status asked before the consent (a kept `consent_required`, no longer silenced by the
        // void agreement) and the policy answer from after now (N-3): not the withdrawal.
        #expect(!h.onboarding.facts.withdrawing, "\(h.onboarding.facts)")
        #expect(h.consent.withdrawnAt == nil, "the answer showed the consent: nothing recorded")

        // Not when it isn't void: one asked before a hold dated at or before now ends nothing (S-2).
        h.clock.set(since.addingTimeInterval(10))
        h.consent.withdrawalUnresolved(since: h.clock.now())
        h.state.repository.store(fetchedUser: user, askedAt: h.clock.now().addingTimeInterval(-1))
        #expect(h.consent.withdrawalUnresolvedSince != nil)
    }

    @Test("Round 5, 4: the hold is written before the DELETE leaves: a relaunch meanwhile holds; a 204 records, a refusal clears",
          .timeLimit(.minutes(1)))
    func theHoldIsWrittenBeforeTheDeleteLeaves() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        let delete = Gate()
        let api = h.api
        api.beforeRevokeConsent = { await delete.wait() }
        let sleeps = h.clock.pendingSleeps
        let began = h.clock.now()

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.onboarding.isWithdrawing && h.clock.pendingSleeps > sleeps }, "out, its deadline running")
        // The app is killed here: the next process, and a background launch that never checks, hold every upload.
        #expect(h.consent.withdrawalUnresolvedSince == began, "since the attempt's start")
        let (next, _) = h.relaunched(online: true)
        for path in [UploadPath.train, .healthKit, .activities, .trainImport] {
            #expect(next.uploadGate(for: path) != nil, "\(path) waits after a relaunch")
        }
        #expect(next.uploadGate(for: .activities, write: .erasure) == nil, "erasure goes")

        // The 204: recorded as a withdrawal, and the hold is gone.
        await delete.open()
        #expect(await withdrawing.value)
        #expect(h.consent.withdrawalUnresolvedSince == nil)
        #expect(h.consent.withdrawnAt != nil)
        #expect(h.onboarding.uploadGate(for: .train) == .gate(.consentRequired))
    }

    @Test("Round 5, 4: a refusal that left the consent as it was clears the hold, and an earlier one stays",
          .timeLimit(.minutes(1)))
    func aRefusalClearsTheHoldItWrote() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        // 500 and 503 are answers that leave the consent as it was; offline sends nothing.
        for fault in [FaultInjection.Fault.status(500, retryAfter: nil), .status(503, retryAfter: nil), .status(403, retryAfter: nil)] {
            h.api.faults["revokeConsent"] = .init(fault)
            #expect(await h.onboarding.withdrawConsent() == false)
            #expect(h.consent.withdrawalUnresolvedSince == nil, "\(fault): the consent is as it was")
            #expect(h.consent.withdrawnAt == nil && h.onboarding.uploadGate(for: .train) == nil, "\(fault)")
        }
        h.api.faults["revokeConsent"] = nil
        h.connectivity.update(false)
        #expect(await h.onboarding.withdrawConsent() == false)
        #expect(h.consent.withdrawalUnresolvedSince == nil && h.api.count("revokeConsent") == 3, "offline sent nothing")
        h.connectivity.update(true)

        // An earlier withdrawal without an answer isn't this attempt's to clear.
        let earlier = h.clock.now()
        h.consent.withdrawalUnresolved(since: earlier)
        h.clock.advance(by: .seconds(1))
        h.api.faults["revokeConsent"] = .init(.status(500, retryAfter: nil))
        #expect(await h.onboarding.withdrawConsent() == false)
        #expect(h.consent.withdrawalUnresolvedSince == earlier)
    }

    @Test("Round 5, 5: a 502 or 504 on the DELETE is no answer: the hold stays, asked again, the sentence says it may have arrived",
          .timeLimit(.minutes(1)), arguments: [502, 504, 500])
    func aGatewayFailureIsNoAnswer(_ status: Int) async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        let me = FirstCallsHold()
        h.api.faults["revokeConsent"] = .init(.status(status, retryAfter: nil))
        h.api.beforeMe = { await me.wait() }
        let sleeps = h.clock.pendingSleeps

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        let gateway = status != 500
        if gateway {
            // Asked again, and its answer is late: the hold stays from when the attempt ended.
            #expect(await eventually { me.waiting == 1 && h.clock.pendingSleeps > sleeps }, "asked again, its wait running")
            h.clock.advance(by: OnboardingCoordinator.checkTimeout)
        }
        #expect(await withdrawing.value == false)
        if gateway {
            #expect(h.consent.withdrawalUnresolvedSince != nil, "RYFT may have recorded it")
            #expect(h.onboarding.errorMessage == OnboardingCoordinator.withdrawalUnansweredMessage)
            #expect(h.onboarding.uploadGate(for: .train) != nil)
        } else {
            #expect(h.consent.withdrawalUnresolvedSince == nil, "back as it was")
            #expect(me.waiting == 0, "nothing asked again")
            #expect(h.onboarding.errorMessage != OnboardingCoordinator.withdrawalUnansweredMessage)
        }
        me.release()
    }

    @Test("Round 5, 6: the account wipe removes that account's withdrawal hold, nobody else's", .timeLimit(.minutes(1)))
    func theWipeRemovesTheWithdrawalHold() async throws {
        let h = H()
        try await h.ready()
        let a = h.account
        let b = H.b.uuidString.lowercased()
        h.consent.withdrawalUnresolved(since: h.clock.now())
        h.defaults.set(h.clock.now(), forKey: ConsentState.unresolvedWithdrawalKey(b))
        try #require(h.defaults.object(forKey: ConsentState.unresolvedWithdrawalKey(a)) != nil)

        // Nothing tells the coordinator (a wipe a launch resumed runs before it does): the wipe itself removes it.
        await h.auth.signOut()
        #expect(h.defaults.object(forKey: ConsentState.unresolvedWithdrawalKey(a)) == nil)
        #expect(h.defaults.object(forKey: ConsentState.unresolvedWithdrawalKey(b)) != nil, "another account's stays")
    }

    @Test("Round 5, 8: N-a through ScreenModels' importer: while the DELETE is held the import's pause names no confirmation",
          .timeLimit(.minutes(1)))
    func theImportsPauseDuringAWithdrawal() async throws {
        let h = H()
        try await h.agreedUnsettled()
        (h.env.flags as? StaticFlags)?.overrides[.trainImport] = true
        let screens = h.screens()
        // Its check can't hear RYFT (a /v1/me would settle the agreement and the job would go).
        h.api.faults["me"] = .init(.offline)
        await screens.onboarding.check()
        // A job held at the gate while RYFT's word on the agreement is out.
        let plan = ImportUploadPlan(exercises: [ImportUploadHarness.custom(1)], sessions: ImportUploadHarness.sessions(3))
        #expect(await screens.trainImport.start(plan, account: h.account, source: .alphaProgression,
                                                zone: ImportBuildFixture.berlin, duplicatesChecked: true))
        await screens.trainImport.resume()
        try #require(screens.trainImport.status?.phase == .paused(.gated(.gate(.consentRequired))))
        screens.importer.start()
        let flow = try #require(screens.importer.flow)
        #expect(flow.gatedPauseCause == .confirmation, "before: the pause waits for RYFT's confirmation")

        // The window before its marker: another step's request holds the turn (an invite), the withdrawal waits behind it,
        // and nothing is written yet (`withdrawalUnresolvedSince` is set once its turn comes). `awaitsConfirmation:` is
        // the only thing that tells the import so (round 6, 2).
        let invite = Gate(), delete = Gate()
        h.api.beforeInvite = { await invite.wait() }
        h.api.beforeRevokeConsent = { await delete.wait() }
        screens.onboarding.inviteCode = "ABCD-EFGH"
        let redeeming = Task { await screens.onboarding.redeemInvite() }
        #expect(await eventually { h.api.count("redeemInvite") == 1 }, "the invite is out: \(h.api.calls)")
        let withdrawing = Task { await screens.onboarding.withdrawConsent() }
        #expect(await eventually { screens.onboarding.isWithdrawing }, "the withdrawal waits its turn")
        try #require(screens.onboarding.isWithdrawing && h.consent.withdrawalUnresolvedSince == nil)
        #expect(flow.gatedPauseCause == .other, "waiting its turn, the withdrawal is the last word: no confirmation is waited for")

        // Its turn: the DELETE is out, the marker written.
        await invite.open()
        _ = await redeeming.value
        // The mock holds the DELETE before it takes the call, so the marker is what shows the withdrawal's turn came.
        #expect(await eventually { h.consent.withdrawalUnresolvedSince != nil }, "its turn: the marker is written before the DELETE leaves")
        #expect(flow.gatedPauseCause == .other, "the withdrawal is the last word: no confirmation is waited for")
        h.api.faults["me"] = nil
        await delete.open()
        _ = await withdrawing.value
    }

    @Test("Round 6, 2: a withdrawal waiting for another step's turn already holds every data upload, with no marker written yet",
          .timeLimit(.minutes(1)))
    func aWithdrawalWaitingItsTurnHoldsTheUploads() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        try #require(h.consent.unsettledAgreement == nil && h.consent.withdrawnAt == nil, "RYFT's word on the consent is in")
        try #require(h.onboarding.uploadGate(for: .train) == nil, "open before")
        // About you's PATCH is out and holds the turn.
        let patch = Gate()
        h.api.beforePatchMe = { await patch.wait() }
        let saving = Task { await h.onboarding.saveAboutYou(birthYear: 1990) }
        #expect(await eventually { h.api.count("patchMe") == 1 }, "the PATCH is out: \(h.api.calls)")

        let withdrawing = Task { await h.onboarding.withdrawConsent() }
        #expect(await eventually { h.onboarding.isWithdrawing }, "the withdrawal waits its turn")
        try #require(h.onboarding.isWithdrawing && h.consent.withdrawalUnresolvedSince == nil)
        #expect(h.api.count("revokeConsent") == 0, "nothing sent yet")
        #expect(h.onboarding.uploadGate(for: .train) != nil, "held by the withdrawal on its way")

        await patch.open()
        _ = await saving.value
        _ = await withdrawing.value
    }

    @Test("Round 5, 8: a relaunch's first check with /v1/me failing keeps the withdrawal hold (never from no account)",
          .timeLimit(.minutes(1)))
    func theFirstCheckAfterARelaunchKeepsTheHold() async throws {
        let h = H()
        try await h.ready()
        #expect(await h.onboarding.agree())
        h.consent.withdrawalUnresolved(since: h.clock.now())
        h.clock.advance(by: .seconds(1))
        let (next, _) = h.relaunched(online: true)
        try #require(next.uploadGate(for: .train) != nil)

        h.api.faults["me"] = .init(.offline)
        await next.check()
        #expect(next.uploadGate(for: .train) != nil, "RYFT wasn't heard from: the hold stays")
        #expect(h.defaults.object(forKey: ConsentState.unresolvedWithdrawalKey(h.account)) != nil)
    }

    // MARK: UI validation round 3

    @Test("UI: offline, Check with RYFT's VoiceOver hint says why it's dimmed; online, none", .timeLimit(.minutes(1)))
    func theCheckSaysWhyItsDimmed() async throws {
        let h = H()
        try await h.agreedUnsettled()
        let profile = h.profile()
        #expect(profile.canCheckConsent && profile.checkConsentHint == nil)
        h.connectivity.update(false)
        #expect(!profile.canCheckConsent)
        #expect(profile.checkConsentHint == String(localized: "Available when this iPhone is online."))
    }

    @Test("UI: Sync details' preview of workouts waiting for RYFT's confirmation names it", .timeLimit(.minutes(1)))
    func theWorkoutsPreviewNamesTheConfirmation() async {
        let g = MockDevicesStates.graph(demo: false, workoutsAwaitConfirmation: true, clock: TestClock())
        _ = await g.train.finish(SessionFactory.empty(in: g.store))
        #expect(g.train.pendingCount > 0 && g.train.heldAt == .gate(.consentRequired))
        #expect(g.details.workoutsHeldText == String(localized: "Waiting for RYFT to confirm your consent"))
    }
}
