import Auth
import Foundation
import Observation
import SwiftData
import Testing
import UIKit
@testable import Ryft

// P2 (ADR 0008, docs/work/2026-10-26-consent-gates/design.md §9): one rule for every upload, per path and kind of
// write, decided from the persisted consent record. T1–T8 of the design; each test names the decision it pins.

// MARK: - helpers

/// `Persistence` over an in-memory `TrainStore` that counts document reads.
@MainActor
private final class CountingPersistence: Persistence {
    let base = TrainStore(inMemory: true)
    private(set) var documentReads = 0

    var container: ModelContainer { base.container }
    var context: ModelContext { base.context }
    var isDurable: Bool { base.isDurable }
    func save() { base.save() }
    func wipe() { base.wipe() }
    func document<T: Decodable>(_ type: T.Type, key: String) -> T? {
        documentReads += 1
        return base.document(type, key: key)
    }
    func saveDocument<T: Encodable>(_ value: T, key: String, at date: Date) { base.saveDocument(value, key: key, at: date) }
    func saveDocumentData(_ data: Data, key: String, at date: Date) { base.saveDocumentData(data, key: key, at: date) }
    func removeDocument(key: String) { base.removeDocument(key: key) }
}

/// A real `AuthService` whose wipe works on the test store, an environment around it, and the coordinator whose
/// gates ScreenModels wires.
@MainActor
private final class ConsentHarness {
    nonisolated static let a = UUID(uuidString: "0000000A-0000-4000-8000-0000000000C1") ?? UUID()
    nonisolated static let b = UUID(uuidString: "0000000B-0000-4000-8000-0000000000C2") ?? UUID()

    let clock = TestClock()
    let api: MockPlatformAPI
    let persistence: TrainStore
    let defaults: UserDefaults
    let settings: Settings
    let client: MockAuthClient
    let auth: AuthService
    let health: MockHealthStore
    let env: AppEnvironment
    let state: AppState
    let status = APIStatus()
    let onboarding: OnboardingCoordinator

    init(api: MockPlatformAPI = MockPlatformAPI(), health: MockHealthStore = MockHealthStore(),
         persistence: TrainStore? = nil, defaults: UserDefaults? = nil,
         online: Bool = true, demo: Bool = false, signedInAs account: UUID? = ConsentHarness.a) {
        self.api = api
        let persistence = persistence ?? TrainStore(inMemory: true)
        self.persistence = persistence
        self.health = health
        let defaults = defaults ?? UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        self.defaults = defaults
        settings = Settings(defaults: defaults)
        settings.demoMode = demo
        client = MockAuthClient(session: account.map { .preview(id: $0) })
        let clock = clock
        auth = AuthService(client: client, settings: settings, defaults: defaults,
                           wipeLocalData: { wipe in persistence.wipe(parkingActivitiesOf: wipe.parking, at: clock.now()) },
                           deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                           postAppleAuthorization: { _ in })
        api.now = { clock.now() }
        env = AppEnvironment(settings: settings, health: health, liveAPI: api, demoAPI: api, auth: auth,
                             persistence: persistence, clock: clock, notifier: MockNotifier(), flags: StaticFlags([:]),
                             connectivity: .preview(online: online), defaults: defaults, demoOverride: demo ? nil : false)
        env.reads.random = { $0.lowerBound }
        env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
        env.uploader.random = { $0.lowerBound }
        env.consent.isProtectedDataAvailable = { true }
        state = AppState(env: env)
        onboarding = OnboardingCoordinator(state: state, apiStatus: status) {}
        onboarding.reachedTabs()
        env.uploader.gate = { [onboarding] in onboarding.uploadGate(for: .activities, write: $0) }
        api.reportsGates = status
    }

    var consent: ConsentState { env.consent }
    var account: String { auth.accountID ?? "-" }

    func config(_ version: String = MockData.policyVersion, ttl: Int = 21_600) -> RemoteConfig {
        RemoteConfig(flags: [:], evaluatedAt: clock.now(), ttlSec: ttl, privacyPolicyVersion: version,
                     privacyPolicyUrl: "https://ryftapp.de/privacy/\(version)")
    }

    /// A policy answer recorded now.
    func answer(_ version: String = MockData.policyVersion, ttl: Int = 21_600) {
        consent.received(config(version, ttl: ttl), at: clock.now(), binding: AccountBinding(env))
    }

    /// The account as a cached user (consent to `version`), as a background launch finds it.
    func cachedUser(consent version: String? = MockData.policyVersion) async throws {
        api.accountConsent = version.map { Consent(policyVersion: $0, grantedAt: clock.now()) }
        state.user = try await api.me()
    }

    func signIn(_ id: UUID) async {
        client.signInSession = .preview(id: id)
        _ = await auth.logIn(email: "tim@example.com", password: "0123456789")
    }

    /// A SyncService with the coordinator's gate, as ScreenModels wires it.
    func sync() -> SyncService {
        let sync = SyncService(env: env)
        sync.gate = { [onboarding] in onboarding.uploadGate(for: .healthKit) }
        return sync
    }

    /// An activity of 15 minutes that ended an hour ago, saved on this phone.
    func saveActivity() -> UUID? {
        let end = clock.now().addingTimeInterval(-3_600)
        return env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900), end: end))?.id
    }

    /// A HealthKit page of one heart-rate sample.
    static func page(_ value: Double = 60) -> HealthDelta {
        HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: value, unit: "bpm", source: "W")])
    }
}

/// Counts the coordinator's uploads (T7: "a sync runs again").
@MainActor
private final class CountingSteps: SyncSteps {
    private(set) var uploads = 0
    func upload() async throws -> [String] {
        uploads += 1
        return []
    }
    var hasBacklog: Bool { false }
    var isWaitingForUnlock: Bool { false }
    var isUploading: Bool { false }
    func stopAfterCurrentPage() async {}
    var expectedScoringSeconds: Int? { nil }
    func syncStatus() async throws -> SyncStatus { throw ReadScheduler.NotSent() }
    func refreshDays(_ days: [String]) async throws {}
    func refreshTrends() async throws {}
    func refreshInsights() async throws {}
    func refreshStale() async {}
    func report(_ phase: SyncPhase) {}
}

/// A count a `@Sendable` completion can bump.
private final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}

/// A switch a test flips while closures read it.
@MainActor
private final class Switch {
    var on: Bool
    init(_ on: Bool) { self.on = on }
}

// MARK: - T1: the rule

@Suite("Consent gates: the rule (T1)")
struct ConsentGateRuleTests {
    typealias Facts = OnboardingCoordinator.Facts

    struct Row: CustomTestStringConvertible, Sendable {
        let facts: Facts
        let path: UploadPath
        let write: UploadWrite
        let gate: UploadGate?
        let testDescription: String
    }

    /// The account known, consented to V, nothing refused, V fresh, the record readable: open. Each row changes one
    /// thing.
    private static func base() -> Facts {
        Facts(userKnown: true, consentVersion: "V", policyVersion: "V", policyFresh: true)
    }

    private static func row(_ name: String, _ gate: UploadGate?, path: UploadPath = .healthKit, write: UploadWrite = .data,
                            _ change: (inout Facts) -> Void) -> Row {
        var f = base()
        change(&f)
        return Row(facts: f, path: path, write: write, gate: gate, testDescription: name)
    }

    /// Every closed fact at once, for demo's rows.
    private static func everythingClosed(_ f: inout Facts) {
        f.demo = true
        f.recordReadable = false
        f.inviteBlocked = true
        f.userKnown = false
        f.consentVersion = nil
        f.policyFresh = false
    }

    static let dataRows: [Row] = [
        // 1. Demo: HealthKit's client is the platform's, so it holds; the others go to the mock, bound to demo.
        row("1 demo, HealthKit", .demo, path: .healthKit, everythingClosed),
        row("1 demo, activities", nil, path: .activities, everythingClosed),
        row("1 demo, Train", nil, path: .train, everythingClosed),
        row("1 demo, the import", nil, path: .trainImport, everythingClosed),
        // 2. The record can't be read (before the first unlock): unknown, before the invite and the account.
        row("2 record unreadable", .policyUnknown) { $0.recordReadable = false },
        row("2 record unreadable, invite blocked too", .policyUnknown) {
            $0.recordReadable = false
            $0.inviteBlocked = true
        },
        // 3. An enforced invite gate, even with everything else fine.
        row("3 invite blocked", .gate(.inviteRequired)) { $0.inviteBlocked = true },
        row("3 invite blocked, the account not known", .gate(.inviteRequired)) {
            $0.inviteBlocked = true
            $0.userKnown = false
        },
        // 4. The account not known: a consent can't be assumed.
        row("4 account not known", .gate(.consentRequired)) {
            $0.userKnown = false
            $0.consentVersion = nil
        },
        // 5. Refused: stored or reported, or the server's gate.
        row("5 refused (stored or reported)", .gate(.consentRequired)) { $0.reported = [.consentRequired] },
        row("5 refused (the server's gate)", .gate(.consentRequired)) { $0.serverGate = .consentRequired },
        // 6. No consent: the user's action, whatever the policy's state.
        row("6 no consent, fresh policy", .gate(.consentRequired)) { $0.consentVersion = nil },
        row("6 no consent, policy unknown", .gate(.consentRequired)) {
            $0.consentVersion = nil
            $0.policyVersion = nil
            $0.policyFresh = false
        },
        // 7. Fresh and matching: open, on every path.
        row("7 fresh and matching, HealthKit", nil) { _ in },
        row("7 fresh and matching, activities", nil, path: .activities) { _ in },
        row("7 fresh and matching, Train", nil, path: .train) { _ in },
        // 8. A different version, any age: consent.
        row("8 different and fresh", .gate(.consentRequired)) { $0.policyVersion = "W" },
        row("8 different and stale", .gate(.consentRequired)) {
            $0.policyVersion = "W"
            $0.policyFresh = false
        },
        // 9. Matching but stale, or no version: unknown (revalidate online, else hold).
        row("9 matching but stale", .policyUnknown) { $0.policyFresh = false },
        row("9 no version heard of", .policyUnknown) {
            $0.policyVersion = nil
            $0.policyFresh = false
        },
        // A warn-mode invite never holds (a product nudge, not a legal basis).
        row("warn-mode invite only", nil) {
            $0.reported = [.inviteRequired]
            $0.betaAccess = false
        },
    ]

    static let erasureRows: [Row] = [
        row("1 demo, HealthKit", .demo, path: .healthKit, write: .erasure, everythingClosed),
        row("1 demo, activities", nil, path: .activities, write: .erasure, everythingClosed),
        row("1 demo, Train", nil, path: .train, write: .erasure, everythingClosed),
        row("2 record unreadable", .policyUnknown, path: .activities, write: .erasure) { $0.recordReadable = false },
        row("3 invite blocked", .gate(.inviteRequired), path: .activities, write: .erasure) { $0.inviteBlocked = true },
        row("3 invite blocked, Train", .gate(.inviteRequired), path: .train, write: .erasure) { $0.inviteBlocked = true },
        // Open in every other case (Art. 17).
        row("account not known", nil, path: .activities, write: .erasure) {
            $0.userKnown = false
            $0.consentVersion = nil
        },
        row("no consent", nil, path: .train, write: .erasure) { $0.consentVersion = nil },
        row("refused", nil, path: .activities, write: .erasure) {
            $0.reported = [.consentRequired]
            $0.serverGate = .consentRequired
        },
        row("a different policy", nil, path: .activities, write: .erasure) { $0.policyVersion = "W" },
        row("policy stale", nil, path: .train, write: .erasure) { $0.policyFresh = false },
        row("no policy heard of", nil, path: .activities, write: .erasure) {
            $0.policyVersion = nil
            $0.policyFresh = false
        },
    ]

    @Test(arguments: dataRows)
    func data(_ row: Row) {
        #expect(OnboardingCoordinator.gate(row.facts, path: row.path, write: row.write) == row.gate)
    }

    @Test(arguments: erasureRows)
    func erasure(_ row: Row) {
        #expect(OnboardingCoordinator.gate(row.facts, path: row.path, write: row.write) == row.gate)
    }

    @Test func missingIsUnchangedByAnUnknownPolicy() {
        var f = Self.base()
        f.policyVersion = nil
        f.policyFresh = false
        #expect(!OnboardingCoordinator.missing(f).contains(.consent)) // never asked just because it's unknown
    }

    @MainActor
    @Test func inDemoOnlyHealthKitHolds() {
        let onboarding = OnboardingCoordinator(state: AppState.preview(), apiStatus: APIStatus()) {}
        #expect(onboarding.uploadGate(for: .healthKit) == .demo)
        #expect(onboarding.uploadGate(for: .activities) == nil && onboarding.uploadGate(for: .train) == nil)
        #expect(onboarding.uploadGate(for: .train, write: .erasure) == nil)
    }
}

// MARK: - T2: the record

@Suite("Consent gates: the record (T2)")
@MainActor
struct ConsentRecordTests {
    @Test func freshUntilTheTTLOnThisPhonesClock() {
        let h = ConsentHarness()
        let start = h.clock.now()
        h.answer(ttl: 3_600)
        h.clock.set(start.addingTimeInterval(3_599))
        #expect(h.consent.isPolicyFresh(at: h.clock.now()))
        h.clock.set(start.addingTimeInterval(3_600))
        #expect(!h.consent.isPolicyFresh(at: h.clock.now()))
        // A clock set back is stale too.
        h.clock.set(start.addingTimeInterval(-1))
        #expect(!h.consent.isPolicyFresh(at: h.clock.now()))
    }

    @Test func noTTLMeansSixHoursAndNoneLastsLongerThanADay() {
        let h = ConsentHarness()
        let start = h.clock.now()
        h.answer(ttl: 0)
        #expect(h.consent.isPolicyFresh(at: start.addingTimeInterval(6 * 3_600 - 1)))
        #expect(!h.consent.isPolicyFresh(at: start.addingTimeInterval(6 * 3_600)))
        h.clock.advance(by: .seconds(60))
        h.answer(ttl: 7 * 86_400) // a misconfigured server (privacy review N3)
        let later = h.clock.now()
        #expect(h.consent.isPolicyFresh(at: later.addingTimeInterval(86_400 - 1)))
        #expect(!h.consent.isPolicyFresh(at: later.addingTimeInterval(86_400)))
    }

    @Test func theNextProcessSeesTheAnswerAndBothRefusals() {
        let h = ConsentHarness()
        h.answer()
        h.consent.refused(.consentRequired, at: h.clock.now())
        h.consent.refused(.inviteRequired, at: h.clock.now())
        let next = ConsentState(env: h.env) // what a background launch builds
        next.isProtectedDataAvailable = { true }
        #expect(next.latestPolicyVersion == MockData.policyVersion && next.isPolicyFresh(at: h.clock.now()))
        #expect(next.refusals == [.consentRequired, .inviteRequired])
    }

    @Test func aUserSignOutEmptiesTheRecord() async {
        let h = ConsentHarness()
        h.answer()
        h.consent.refused(.consentRequired, at: h.clock.now())
        await h.auth.signOut()
        await h.signIn(ConsentHarness.a)
        #expect(h.consent.latestPolicyVersion == nil && h.consent.refusals.isEmpty)
        #expect(ConsentState(env: h.env).latestPolicyVersion == nil)
    }

    @Test func anExpiryWithParkingEmptiesItAndTheSameAccountReadsNoOldMemo() async {
        let h = ConsentHarness()
        h.answer()
        h.consent.refused(.consentRequired, at: h.clock.now())
        #expect(h.consent.refusals == [.consentRequired]) // memoised for A
        await h.auth.rejectedAfterRefresh() // parks activity rows only
        await h.signIn(ConsentHarness.a)
        #expect(h.consent.refusals.isEmpty && h.consent.latestPolicyVersion == nil)
        #expect(ConsentState(env: h.env).refusals.isEmpty)
    }

    @Test func anAccountDeletionEmptiesIt() async {
        let h = ConsentHarness()
        h.answer()
        #expect(await h.auth.deleteAccount())
        await h.signIn(ConsentHarness.a)
        #expect(h.consent.latestPolicyVersion == nil)
    }

    @Test func anotherAccountSeesNothingOfTheFirst() async {
        let h = ConsentHarness()
        h.answer()
        h.consent.refused(.consentRequired, at: h.clock.now())
        await h.auth.signOut()
        await h.signIn(ConsentHarness.b)
        #expect(h.consent.latestPolicyVersion == nil && h.consent.refusals.isEmpty)
    }

    @Test func demoDataWritesNothingAndTheAccountsRecordComesBack() {
        let h = ConsentHarness(demo: true)
        h.answer("D")
        h.consent.refused(.consentRequired, at: h.clock.now())
        #expect(h.consent.latestPolicyVersion == nil && h.consent.refusals.isEmpty)
        #expect(h.persistence.document(ConsentState.Record.self, key: ConsentState.key(h.account)) == nil)
        h.settings.demoMode = false
        h.answer("A")
        h.settings.demoMode = true
        #expect(h.consent.latestPolicyVersion == nil) // nothing in demo
        h.settings.demoMode = false
        #expect(h.consent.latestPolicyVersion == "A") // the account's record, read again
    }

    @Test func anAnswerForAnotherBindingIsDroppedAndAnOlderOneNeverWins() async {
        let h = ConsentHarness()
        let startedUnderA = AccountBinding(h.env)
        await h.auth.signOut()
        await h.signIn(ConsentHarness.b)
        h.consent.received(h.config("A's"), at: h.clock.now(), binding: startedUnderA)
        #expect(h.consent.latestPolicyVersion == nil)
        // Under B: a newer answer, then one that arrived out of order.
        let earlier = h.clock.now()
        h.clock.advance(by: .seconds(10))
        h.consent.received(h.config("new"), at: h.clock.now(), binding: AccountBinding(h.env))
        h.consent.received(h.config("old"), at: earlier, binding: AccountBinding(h.env))
        #expect(h.consent.latestPolicyVersion == "new")
    }

    private func countingEnvironment(_ persistence: CountingPersistence, clock: TestClock,
                                     api: MockPlatformAPI = MockPlatformAPI()) -> AppEnvironment {
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let env = AppEnvironment(settings: Settings(defaults: defaults), health: MockHealthStore(), liveAPI: api,
                                 demoAPI: api, auth: .preview(), persistence: persistence, clock: clock,
                                 notifier: MockNotifier(), flags: StaticFlags([:]), connectivity: .preview(online: true),
                                 defaults: defaults, demoOverride: false)
        env.reads.random = { $0.lowerBound }
        env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
        return env
    }

    @Test func aHundredReadsAreOneStoreRead() {
        let clock = TestClock()
        let persistence = CountingPersistence()
        let env = countingEnvironment(persistence, clock: clock)
        env.consent.isProtectedDataAvailable = { true }
        let before = persistence.documentReads
        for _ in 0..<100 { _ = env.consent.isPolicyFresh(at: clock.now()) }
        #expect(persistence.documentReads - before == 1)
    }

    @Test func aReadWhileTheStoreIsLockedIsntKeptAndTheUnlockReadsAgain() async {
        let clock = TestClock()
        let persistence = CountingPersistence()
        let api = MockPlatformAPI()
        let env = countingEnvironment(persistence, clock: clock, api: api)
        let unlocked = Switch(false)
        env.consent.isProtectedDataAvailable = { unlocked.on }
        let before = persistence.documentReads
        let readable = env.consent.isRecordReadable
        let refusals = env.consent.refusals
        #expect(!readable && refusals.isEmpty)
        #expect(persistence.documentReads - before == 2) // empty and locked: asked again each time (N2)
        // Nothing could be stored meanwhile: no config request.
        try? await env.consent.revalidate()
        #expect(api.count("config") == 0)
        // The store is readable now and holds the account's record; the unlock reads it again.
        let account = env.auth.accountID ?? "-"
        let record = ConsentState.Record(policyVersion: "V", answeredAt: clock.now(), refusals: [.consentRequired: clock.now()])
        persistence.base.saveDocument(record, key: ConsentState.key(account), at: clock.now())
        unlocked.on = true
        NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        #expect(env.consent.isRecordReadable && env.consent.refusals == [.consentRequired])
        let afterUnlock = persistence.documentReads
        _ = env.consent.refusals
        #expect(persistence.documentReads == afterUnlock) // kept from here on
    }

    @Test func theUnlockReloadsAReadKeptEarlier() {
        let clock = TestClock()
        let persistence = CountingPersistence()
        let env = countingEnvironment(persistence, clock: clock)
        env.consent.isProtectedDataAvailable = { true }
        _ = env.consent.refusals
        let before = persistence.documentReads
        NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        _ = env.consent.refusals
        #expect(persistence.documentReads - before == 1)
    }

    @Test func aLockedStoreHoldsEveryWriteOfTheAccount() async throws {
        let h = ConsentHarness()
        try await h.cachedUser()
        h.answer()
        #expect(h.onboarding.uploadGate(for: .healthKit) == nil)
        // What the next process finds before the first unlock: the store reads empty.
        h.persistence.removeDocument(key: ConsentState.key(h.account))
        h.consent.isProtectedDataAvailable = { false }
        h.consent.reload()
        #expect(h.onboarding.uploadGate(for: .healthKit) == .policyUnknown)
        #expect(h.onboarding.uploadGate(for: .activities, write: .erasure) == .policyUnknown)
    }

    @Test func aNewAnswerAndTheRefusalsEndReleaseTheGateForObservers() async throws {
        let h = ConsentHarness()
        try await h.cachedUser()
        let fired = Tally()
        withObservationTracking { _ = h.onboarding.uploadGate(for: .healthKit) } onChange: { fired.add() }
        h.answer()
        #expect(fired.value == 1)
        h.consent.refused(.consentRequired, at: h.clock.now())
        withObservationTracking { _ = h.onboarding.uploadGate(for: .healthKit) } onChange: { fired.add() }
        h.consent.cleared(.consentRequired)
        #expect(fired.value == 2)
    }

    @Test func revalidateAsksOnceAMinuteWhileTheConfigFails() async {
        let h = ConsentHarness()
        h.api.faults["config"] = .init(.status(404, retryAfter: nil))
        await #expect(throws: APIError.self) { try await h.consent.revalidate() }
        await #expect(throws: APIError.self) { try await h.consent.revalidate() }
        h.clock.advance(by: .seconds(59))
        await #expect(throws: APIError.self) { try await h.consent.revalidate() }
        #expect(h.api.count("config") == 1)
        h.clock.advance(by: .seconds(2))
        await #expect(throws: APIError.self) { try await h.consent.revalidate() }
        #expect(h.api.count("config") == 2)
        // Answered: fresh, nothing more to ask.
        h.api.faults["config"] = nil
        h.clock.advance(by: .seconds(61))
        try? await h.consent.revalidate()
        try? await h.consent.revalidate()
        #expect(h.api.count("config") == 3 && h.consent.isPolicyFresh(at: h.clock.now()))
    }

    @Test func revalidateJoinsTheChecksConfigRead() async {
        let h = ConsentHarness()
        let hold = RequestHold()
        h.api.beforeConfig = { await hold.wait() }
        let check = Task { await h.onboarding.check(force: true) }
        #expect(await eventually { hold.waiting == 1 })
        let revalidate = Task { try await h.consent.revalidate() }
        try? await Task.sleep(for: .milliseconds(30)) // a negative check: no second request may start
        #expect(h.api.count("config") == 1)
        hold.release()
        await check.value
        _ = try? await revalidate.value
        #expect(h.api.count("config") == 1 && h.consent.isPolicyFresh(at: h.clock.now()))
    }
}

// MARK: - T3: the writers

@Suite("Consent gates: the writers (T3)")
@MainActor
struct ConsentWriterTests {
    @Test func theConsentGateIsKeptEnforcedOrWarnedAndEndsWhenResolved() {
        let h = ConsentHarness()
        h.status.observe([.consentRequired], enforced: true)
        #expect(h.consent.refusals == [.consentRequired])
        h.status.resolved(.consentRequired)
        #expect(h.consent.refusals.isEmpty)
        // Warn mode (`X-RYFT-Gate`, `GET /v1/me/sync`): kept too, on purpose (N4).
        h.status.observe([.consentRequired], enforced: false)
        #expect(h.consent.refusals == [.consentRequired])
    }

    @Test func onlyAnEnforcedInviteGateIsKept() {
        let h = ConsentHarness()
        h.status.observe([.inviteRequired], enforced: false) // a warning: a product nudge
        #expect(h.consent.refusals.isEmpty)
        h.status.observe([.inviteRequired], enforced: true)
        #expect(h.consent.refusals == [.inviteRequired])
        // The next process, with a fresh APIStatus, still holds at the invite gate (privacy review N1).
        let next = OnboardingCoordinator(state: h.state, apiStatus: APIStatus()) {}
        #expect(next.uploadGate(for: .healthKit) == .gate(.inviteRequired))
        h.status.resolved(.inviteRequired)
        #expect(h.consent.refusals.isEmpty)
    }

    @Test func aRedeemedCodeEndsTheKeptInviteGate() async {
        let h = ConsentHarness()
        h.api.betaAccess = false
        h.api.inviteGateOn = true
        h.status.observe([.inviteRequired], enforced: true)
        h.onboarding.inviteCode = "RYFT7K3MQX9P"
        #expect(await h.onboarding.redeemInvite())
        #expect(!h.consent.refusals.contains(.inviteRequired))
    }

    @Test func checkKeepsTheServersConsentGateAndEndsTheInvites() async {
        let h = ConsentHarness()
        h.consent.refused(.inviteRequired, at: h.clock.now())
        h.api.betaAccess = false // the invite ended by the status alone, not by beta access
        h.api.accountConsent = Consent(policyVersion: "2026-01-01", grantedAt: h.clock.now()) // the mock's gate
        await h.onboarding.check(force: true)
        #expect(h.consent.refusals == [.consentRequired])
        // Agreed elsewhere: the next check finds no gate.
        h.api.accountConsent = Consent(policyVersion: MockData.policyVersion, grantedAt: h.clock.now())
        await h.onboarding.check(force: true)
        #expect(h.consent.refusals.isEmpty)
    }

    @Test func checkWithNoGateEndsBoth() async {
        let h = ConsentHarness()
        h.consent.refused(.consentRequired, at: h.clock.now())
        h.consent.refused(.inviteRequired, at: h.clock.now())
        h.api.betaAccess = false // the invite ended by the status alone, not by beta access
        await h.onboarding.check(force: true)
        #expect(h.consent.refusals.isEmpty)
    }

    @Test func checkRecordsNothingForTheInviteGate() async {
        let h = ConsentHarness()
        h.consent.refused(.consentRequired, at: h.clock.now())
        // An older consent, so only the status could end the refusal; the mock names the invite gate first.
        h.api.accountConsent = Consent(policyVersion: "2026-01-01", grantedAt: h.clock.now())
        h.api.inviteGateOn = true
        h.api.betaAccess = false
        await h.onboarding.check(force: true)
        #expect(h.consent.refusals == [.consentRequired]) // neither ended nor an invite refusal kept
    }

    @Test func betaAccessEndsAKeptInviteGateWhenTheStatusDoesntNameIt() async {
        let h = ConsentHarness()
        h.consent.refused(.inviteRequired, at: h.clock.now())
        h.api.faults["syncStatus"] = .init(.status(404, retryAfter: nil))
        h.api.betaAccess = false
        await h.onboarding.check(force: true)
        #expect(h.consent.refusals == [.inviteRequired])
        h.api.betaAccess = true
        await h.onboarding.check(force: true)
        #expect(h.consent.refusals.isEmpty)
    }

    @Test func checkEndsTheConsentRefusalWhenItsOwnAnswersAgreeEvenWithoutTheStatus() async {
        let h = ConsentHarness()
        h.consent.refused(.consentRequired, at: h.clock.now())
        h.api.faults["syncStatus"] = .init(.status(404, retryAfter: nil))
        await h.onboarding.check(force: true)
        #expect(h.consent.refusals.isEmpty)
        // Answers that don't agree leave it.
        h.consent.refused(.consentRequired, at: h.clock.now())
        h.api.accountConsent = Consent(policyVersion: "2026-01-01", grantedAt: h.clock.now())
        await h.onboarding.check(force: true)
        #expect(h.consent.refusals == [.consentRequired])
    }

    @Test func agreeingEndsTheRefusalAndCountsAsAnAnswer() async {
        let h = ConsentHarness()
        h.api.accountConsent = nil
        await h.onboarding.check(force: true)
        #expect(h.consent.refusals == [.consentRequired])
        // Three hours later the check's answer is still fresh: agreeing uses it.
        let agreedAt = h.clock.now().addingTimeInterval(3 * 3_600)
        h.clock.set(agreedAt)
        let before = h.api.calls.count
        h.api.faults["config"] = .init(.status(404, retryAfter: nil)) // only the 204 can make it fresh now
        #expect(await h.onboarding.agree())
        #expect(h.api.calls.dropFirst(before).first == "consent") // no config read first
        #expect(h.consent.refusals.isEmpty)
        // Fresh for six hours from the 204, not from the check's read three hours earlier.
        #expect(h.consent.isPolicyFresh(at: agreedAt.addingTimeInterval(6 * 3_600 - 1)))
        #expect(!h.consent.isPolicyFresh(at: agreedAt.addingTimeInterval(6 * 3_600)))
    }

    @Test(arguments: [APIErrorCode.consentRequired, .inviteRequired])
    func aKeptRefusalAtAnOfflineLaunchAsksForItsStep(_ code: APIErrorCode) async throws {
        let h = ConsentHarness(online: false)
        try await h.cachedUser()
        if code == .inviteRequired { h.state.user?.betaAccess = false }
        let record = ConsentState.Record(refusals: [code: h.clock.now()])
        h.persistence.saveDocument(record, key: ConsentState.key(h.account), at: h.clock.now())
        h.consent.reload()
        let launch = OnboardingCoordinator(state: h.state, apiStatus: APIStatus()) {}
        launch.reachedTabs()
        await launch.check() // offline: nothing asked
        let step: OnboardingCoordinator.Step = code == .consentRequired ? .consent : .invite
        #expect(launch.pendingGate == step)
        let sync = SyncService(env: h.env)
        let today = TodayViewModel(state: h.state, sync: sync,
                                   coordinator: SyncCoordinator(steps: LiveSyncSteps(state: h.state, sync: sync),
                                                                clock: h.clock),
                                   onboarding: launch, apiStatus: APIStatus())
        guard case .actionNeeded(let shown, _, _)? = today.status else {
            Issue.record("expected an action, got \(String(describing: today.status))")
            return
        }
        #expect(shown == step)
    }
}

// MARK: - T4: HealthKit sync

@Suite("Consent gates: HealthKit sync (T4)")
@MainActor
struct ConsentSyncTests {
    @Test func staleAndOfflineReadsAndSendsNothing() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [ConsentHarness.page()]])
        let h = ConsentHarness(health: health, online: false)
        try await h.cachedUser()
        let sync = h.sync()
        #expect(try await sync.upload() == [])
        #expect(health.pageReads == 0 && health.recentReads == 0 && health.committed.isEmpty)
        #expect(h.api.count("sync") == 0 && h.api.count("config") == 0)
    }

    @Test func staleAndOnlineAsksTheConfigFirstThenSends() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [ConsentHarness.page()]])
        let h = ConsentHarness(health: health)
        try await h.cachedUser()
        let sync = h.sync()
        _ = try await sync.upload()
        let calls = h.api.calls.filter { $0 == "config" || $0 == "sync" }
        #expect(calls.first == "config" && h.api.count("config") == 1 && h.api.count("sync") >= 1)
        #expect(sync.pausedFor == nil)
    }

    @Test func aFailingConfigIsTheRunsErrorAndNothingIsRead() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [ConsentHarness.page()]])
        let h = ConsentHarness(health: health)
        try await h.cachedUser()
        h.api.faults["config"] = .init(.status(404, retryAfter: nil))
        let sync = h.sync()
        await #expect(throws: APIError.self) { try await sync.upload() }
        #expect(sync.phase == .failed && sync.lastErrorDetails?.contains("fault-config") == true)
        #expect(health.pageReads == 0 && health.recentReads == 0 && h.api.count("sync") == 0)
    }

    @Test func aLockedRecordHoldsWithoutAskingTheConfig() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [ConsentHarness.page()]])
        let h = ConsentHarness(health: health)
        try await h.cachedUser()
        h.consent.isProtectedDataAvailable = { false }
        let sync = h.sync()
        #expect(try await sync.upload() == [])
        #expect(sync.pausedFor == .policyUnknown && h.api.count("config") == 0 && health.pageReads == 0)
    }

    @Test func aKeptRefusalHoldsEveryLaterProcess() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [ConsentHarness.page()]])
        let first = ConsentHarness(health: health)
        try await first.cachedUser()
        first.answer()
        first.consent.refused(.consentRequired, at: first.clock.now())
        // Two more "processes" on the same stores: a new environment, consent record, coordinator and sync each.
        for _ in 0..<2 {
            let next = ConsentHarness(api: first.api, health: health, persistence: first.persistence,
                                      defaults: first.defaults)
            try await next.cachedUser()
            let sync = next.sync()
            #expect(try await sync.upload() == [])
            #expect(sync.pausedFor == .gate(.consentRequired))
        }
        #expect(first.api.count("sync") == 0 && health.committed.isEmpty)
    }

    @Test func aRefusalOnPageTwoKeepsItsAnchorAndIsKept() async throws {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [
            ConsentHarness.page(60), ConsentHarness.page(61),
        ]])
        let h = ConsentHarness(health: health)
        try await h.cachedUser()
        h.answer()
        let api = h.api
        api.enforcesConsent = true
        // Withdrawn on another device after page 1: this phone hears of it only from the 403.
        api.afterSync = { api.accountConsent = nil }
        let sync = h.sync()
        _ = try await sync.upload()
        #expect(api.count("sync") == 2 && health.committed.count == 1) // page 2's anchor stays
        #expect(sync.pausedFor == .gate(.consentRequired) && sync.lastError == nil)
        #expect(h.consent.refusals == [.consentRequired]) // the platform's word, kept for the next process
    }

    @Test func aLocalHoldMidRunRecordsNoRefusal() async throws {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [
            ConsentHarness.page(60), ConsentHarness.page(61),
        ]])
        let h = ConsentHarness(health: health)
        let api = h.api
        let sync = SyncService(env: h.env)
        sync.gate = { api.count("sync") >= 1 ? .gate(.consentRequired) : nil } // closes after page 1, locally
        _ = try await sync.upload()
        #expect(api.count("sync") == 1 && health.committed.count == 1)
        #expect(sync.pausedFor == .gate(.consentRequired))
        #expect(h.consent.refusals.isEmpty)
    }

    @Test(arguments: [UploadGate.gate(.consentRequired), .gate(.inviteRequired), .policyUnknown, .demo])
    func aHeldHealthKitDeliveryCompletesExactlyOnce(_ hold: UploadGate) async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [ConsentHarness.page()]])
        let h = ConsentHarness(health: health)
        h.consent.isProtectedDataAvailable = { false } // unknown stays unknown: nothing could be stored
        let sync = SyncService(env: h.env)
        sync.gate = { hold }
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: h.state, sync: sync), clock: h.clock)
        let completions = Tally()
        _ = await coordinator.run(.healthKit, afterUpload: { completions.add() })
        #expect(completions.value == 1)
        #expect(h.api.count("sync") == 0 && health.committed.isEmpty && sync.pausedFor == hold)
    }

    @Test func demoDataSendsNothingAndLeavesTheAccountsSyncAsItWas() async {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [ConsentHarness.page()]])
        let h = ConsentHarness(health: health, demo: true)
        let before = SyncEngineState.load(account: h.auth.accountID, defaults: h.defaults)
        let sync = SyncService(env: h.env) // no gate wired: the run itself refuses demo data (privacy review S1)
        await sync.fullResync()
        await sync.syncNow()
        sync.resendRecent()
        #expect(h.api.count("sync") == 0 && health.pageReads == 0 && health.recentReads == 0)
        #expect(health.resets == 0 && health.committed.isEmpty)
        #expect(SyncEngineState.load(account: h.auth.accountID, defaults: h.defaults) == before)
    }

    @Test func aWarnModeInviteGateDoesntHoldTheSyncAndAnEnforcedOneIsKept() async throws {
        let health = MockHealthStore(pages: [.quantity(.heartRate): [ConsentHarness.page()]])
        let h = ConsentHarness(health: health)
        try await h.cachedUser()
        h.answer()
        h.status.observe([.inviteRequired], enforced: false)
        let sync = h.sync()
        _ = try await sync.upload()
        #expect(h.api.count("sync") == 1 && sync.pausedFor == nil)
        // Enforced: held, and the next process holds too.
        h.status.observe([.inviteRequired], enforced: true)
        let next = ConsentHarness(api: h.api, health: health, persistence: h.persistence, defaults: h.defaults)
        try await next.cachedUser()
        let held = next.sync()
        _ = try await held.upload()
        #expect(h.api.count("sync") == 1 && held.pausedFor == .gate(.inviteRequired))
    }
}

// MARK: - T5–T6: activity uploads and reconnects

@Suite("Consent gates: activity uploads and reconnects (T5, T6)")
@MainActor
struct ConsentUploadTests {
    @Test func pendingAsksTheGateOncePerRowForItsKind() throws {
        let h = UploadHarness(online: false) // offline: the branch that tells "offline" from "gated" reads it too
        var asked: [UploadWrite] = []
        h.uploader.gate = {
            asked.append($0)
            return .policyUnknown
        }
        let rows = try (0..<3).map { _ in try #require(h.save()) }
        asked = []
        let states = rows.map { h.uploader.state(of: $0) }
        #expect(asked == [.data, .data, .data])
        #expect(states.allSatisfy { $0 == .pending(.offline) })
    }

    @Test func theReplayAsksThePolicyOnceThenSends() async throws {
        let h = ConsentHarness()
        try await h.cachedUser()
        let id = try #require(h.saveActivity())
        await h.env.uploader.flush()
        #expect(h.api.count("config") == 1 && h.env.uploader.state(of: id) == .confirmed)
        _ = try #require(h.saveActivity())
        await h.env.uploader.flush()
        #expect(h.api.count("config") == 1) // fresh now
    }

    @Test func aHeldPutKeepsTheLaterOnesBehindIt() async throws {
        let h = UploadHarness()
        // Written straight into the store, so no save starts a replay of its own.
        func insert(minutesAgo: Double) -> UUID {
            let end = h.clock.now().addingTimeInterval(-minutesAgo * 60)
            let row = LocalActivity(account: h.account ?? "-", sport: .cycling, origin: .manual,
                                    start: end.addingTimeInterval(-1_800), end: end, movingSec: 1_800, localRevision: 1,
                                    createdAt: end)
            h.env.persistence.context.insert(row)
            h.env.persistence.save()
            return row.id
        }
        let first = insert(minutesAgo: 120)
        let second = insert(minutesAgo: 60)
        // The data gate holds for the replay's start and the first row, then opens (consent arrives mid-pass).
        var dataAnswers: [UploadGate?] = [.gate(.consentRequired), .gate(.consentRequired)]
        h.uploader.gate = { write in
            guard write == .data else { return nil }
            return dataAnswers.isEmpty ? nil : dataAnswers.removeFirst()
        }
        await h.uploader.flush()
        #expect(h.puts() == 0) // the second row never overtakes the first
        await h.uploader.flush()
        #expect(h.platform.puts.map(\.id) == [first, second])
    }

    @Test func withoutConsentADeleteGoesAndAnEditDoesnt() async throws {
        let h = ConsentHarness()
        try await h.cachedUser()
        h.answer()
        let uploaded = try #require(h.saveActivity())
        await h.env.uploader.flush()
        #expect(h.env.uploader.state(of: uploaded) == .confirmed)
        // Consent withdrawn in this app; then a new activity, and the uploaded one deleted.
        h.state.user?.consent = nil
        let added = try #require(h.saveActivity())
        h.env.uploader.deleted(uploaded)
        await h.env.uploader.flush()
        #expect(h.api.count("deleteActivity") == 1 && h.env.activities.snapshot(id: uploaded) == nil)
        #expect(h.api.count("putActivity") == 1 && h.env.uploader.state(of: added) == .pending(.gated))
    }

    @Test func aDeleteRefusedForConsentStaysQueuedAndGoesOnTheNextTrigger() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        await h.uploader.flush()
        h.api.failNext = APIError.http(403, "consent required", code: .consentRequired)
        h.uploader.deleted(id)
        await h.uploader.flush()
        #expect(h.deletes() == 1 && h.store.snapshot(id: id)?.isTombstone == true)
        #expect(h.uploader.state(of: id) == .pending(.gated))
        await h.uploader.appBecameActive()
        #expect(h.deletes() == 2 && h.store.snapshot(id: id) == nil)
    }

    @Test func anEnforcedInviteGateHoldsDeletesToo() async throws {
        let h = ConsentHarness()
        try await h.cachedUser()
        h.answer()
        let id = try #require(h.saveActivity())
        await h.env.uploader.flush()
        h.status.observe([.inviteRequired], enforced: true)
        h.env.uploader.deleted(id)
        await h.env.uploader.flush()
        #expect(h.api.count("deleteActivity") == 0 && h.env.activities.snapshot(id: id)?.isTombstone == true)
    }

    @Test func aWarnModeInviteGateDoesntHoldUploads() async throws {
        let h = ConsentHarness()
        try await h.cachedUser()
        h.answer()
        h.status.observe([.inviteRequired], enforced: false)
        let id = try #require(h.saveActivity())
        await h.env.uploader.flush()
        #expect(h.env.uploader.state(of: id) == .confirmed)
    }

    @Test func fiveReconnectsInAMinuteWithTheConfigFailingAskItOnce() async throws {
        let h = ConsentHarness(online: false)
        try await h.cachedUser()
        let me = h.api.count("me")
        h.api.faults["config"] = .init(.status(404, retryAfter: nil))
        _ = try #require(h.saveActivity())
        let sync = h.sync()
        for _ in 0..<5 {
            h.env.connectivityMonitor.update(false)
            h.env.connectivityMonitor.update(true) // the uploader's own reconnect
            _ = try? await sync.upload() // and the sync's `.reconnect` run
            h.clock.advance(by: .seconds(5))
        }
        #expect(await eventually { h.env.uploader.inFlight == nil })
        #expect(h.api.count("config") == 1 && h.api.count("me") == me) // no forced check
    }
}

// MARK: - T7: the release edge

@Suite("Consent gates: the release edge (T7)")
@MainActor
struct ConsentReleaseTests {
    private func screens(_ h: ConsentHarness, steps: CountingSteps, trainSync: TrainSyncService? = nil)
        -> (ScreenModels, SyncService) {
        let sync = SyncService(env: h.env)
        let store = TrainStore(inMemory: true)
        let library = TrainLibrary(store: store, remote: { [api = h.api] in api }, restore: false)
        let screens = ScreenModels(state: h.state, sync: sync, coordinator: SyncCoordinator(steps: steps, clock: h.clock),
                                   store: store, library: library, apiStatus: h.status, trainSync: trainSync)
        return (screens, sync)
    }

    @Test func activitiesFlushWhenTheirGateOpens() async throws {
        let h = ConsentHarness()
        try await h.cachedUser()
        h.answer()
        let steps = CountingSteps()
        let (screens, _) = screens(h, steps: steps)
        h.env.uploader.gate = { _ in .gate(.consentRequired) } // held until the release below
        let id = try #require(h.saveActivity())
        screens.gateChanged(.activities, to: .policyUnknown) // not a release
        try? await Task.sleep(for: .milliseconds(30)) // a negative check: nothing may start
        #expect(h.api.count("putActivity") == 0)
        h.env.uploader.gate = { _ in nil }
        screens.gateChanged(.activities, to: nil)
        #expect(await eventually { h.env.uploader.state(of: id) == .confirmed })
        #expect(steps.uploads == 0) // no sync run for it
    }

    @Test func aSyncRunsAgainOnlyIfItsLastRunWasHeld() async throws {
        let h = ConsentHarness()
        try await h.cachedUser()
        h.answer()
        let steps = CountingSteps()
        let (screens, sync) = screens(h, steps: steps)
        screens.gateChanged(.healthKit, to: nil) // not held: no extra HealthKit pass
        try? await Task.sleep(for: .milliseconds(30)) // a negative check: no run may start
        #expect(steps.uploads == 0)
        var hold: UploadGate? = .gate(.consentRequired)
        sync.gate = { hold }
        _ = try await sync.upload()
        #expect(sync.pausedFor == .gate(.consentRequired))
        hold = nil
        screens.gateChanged(.healthKit, to: .policyUnknown) // not a release
        try? await Task.sleep(for: .milliseconds(30)) // a negative check: no run may start
        #expect(steps.uploads == 0)
        screens.gateChanged(.healthKit, to: nil)
        #expect(await eventually { steps.uploads == 1 })
    }

    @Test func trainsOutboxFlushesWhenItsGateOpens() async throws {
        let h = ConsentHarness()
        try await h.cachedUser()
        h.answer()
        let store = TrainStore(inMemory: true)
        let trainSync = TrainSyncService(store: store, remote: { [api = h.api] in api }, owner: { "A" },
                                         debounce: .seconds(3_600), monitorsNetwork: false)
        let (screens, _) = screens(h, steps: CountingSteps(), trainSync: trainSync) // wires its gate
        h.consent.refused(.consentRequired, at: h.clock.now())
        trainSync.sessionChanged(SessionFactory.empty(in: store))
        await trainSync.flush()
        #expect(h.api.count("putSession") == 0 && trainSync.pendingCount == 1)
        h.consent.cleared(.consentRequired)
        screens.gateChanged(.train, to: nil)
        #expect(await eventually { h.api.count("putSession") == 1 })
    }
}

// MARK: - T8: Train's outbox

@Suite("Consent gates: Train's outbox (T8)")
@MainActor
struct ConsentTrainTests {
    private func outbox(_ api: MockPlatformAPI) -> (TrainSyncService, TrainStore) {
        let store = TrainStore(inMemory: true)
        let sync = TrainSyncService(store: store, remote: { api }, owner: { "A" }, debounce: .seconds(3_600),
                                    monitorsNetwork: false)
        return (sync, store)
    }

    @Test func withoutConsentPutsAndCompletionsWaitInOrderAndGoWhenItArrives() async {
        let api = MockPlatformAPI()
        let (sync, store) = outbox(api)
        let consent = Switch(false)
        sync.gate = { write in consent.on || write == .erasure ? nil : .gate(.consentRequired) }
        await sync.finish(SessionFactory.empty(in: store)) // a put and a complete
        #expect(api.count("putSession") == 0 && api.count("completeSession") == 0)
        #expect(sync.pendingCount == 2 && sync.heldAt == .gate(.consentRequired))
        consent.on = true
        await sync.flush()
        #expect(api.calls.filter { $0.hasSuffix("Session") } == ["putSession", "completeSession"])
        #expect(sync.pendingCount == 0 && sync.heldAt == nil)
    }

    @Test func aDeleteGoesWithoutConsentAndTakesItsSessionsHeldOpsWithIt() async {
        let api = MockPlatformAPI()
        let (sync, store) = outbox(api)
        sync.gate = { $0 == .erasure ? nil : .gate(.consentRequired) }
        let other = SessionFactory.empty(in: store)
        sync.sessionChanged(other) // another session's put, held, ahead of the delete
        let gone = SessionFactory.empty(in: store)
        gone.uploaded = true
        sync.sessionChanged(gone) // its own put, held
        sync.discard(gone)
        await sync.flush()
        #expect(api.count("deleteSession") == 1 && api.count("putSession") == 0)
        #expect(store.pendingOps().map(\.sessionId) == [other.id]) // the other session's put waits
    }

    @Test func aHeldPutKeepsTheLaterOnesBehindIt() async {
        let api = MockPlatformAPI()
        let (sync, store) = outbox(api)
        // Held at the replay's start and for the first op, then open (consent arrives mid-pass).
        var dataAnswers: [UploadGate?] = [.gate(.consentRequired), .gate(.consentRequired)]
        sync.gate = { write in
            guard write == .data else { return nil }
            return dataAnswers.isEmpty ? nil : dataAnswers.removeFirst()
        }
        let first = SessionFactory.empty(in: store), second = SessionFactory.empty(in: store)
        sync.sessionChanged(first)
        sync.sessionChanged(second)
        await sync.flush()
        #expect(api.count("putSession") == 0) // the second op never overtakes the first
        #expect(store.pendingOps().map(\.sessionId) == [first.id, second.id])
    }

    @Test func aWithdrawalMidQueueHoldsTheNextOp() async {
        let api = MockPlatformAPI()
        let (sync, store) = outbox(api)
        sync.gate = { _ in api.count("putSession") >= 1 ? .gate(.consentRequired) : nil }
        sync.sessionChanged(SessionFactory.empty(in: store))
        sync.sessionChanged(SessionFactory.empty(in: store))
        await sync.flush()
        #expect(api.count("putSession") == 1 && sync.pendingCount == 1) // the second stays queued, never dropped
    }

    @Test func anUnknownPolicyIsAskedForOnceBeforeHolding() async {
        let api = MockPlatformAPI()
        let (sync, store) = outbox(api)
        var asked = 0
        sync.gate = { _ in .policyUnknown }
        sync.revalidatePolicy = { asked += 1 }
        sync.sessionChanged(SessionFactory.empty(in: store))
        sync.sessionChanged(SessionFactory.empty(in: store))
        await sync.flush()
        #expect(asked == 1 && api.count("putSession") == 0 && sync.heldAt == .policyUnknown)
    }

    @Test func closedUntilTheAppConnectsIt() async {
        let api = MockPlatformAPI()
        let (sync, store) = outbox(api)
        let uploaded = SessionFactory.empty(in: store)
        uploaded.uploaded = true
        sync.sessionChanged(SessionFactory.empty(in: store))
        sync.discard(uploaded)
        await sync.flush()
        #expect(api.calls.isEmpty && sync.pendingCount == 2)
    }

    @Test func readsDontAskTheGate() async {
        let api = MockPlatformAPI()
        let (sync, store) = outbox(api)
        sync.gate = { _ in .gate(.consentRequired) }
        let library = TrainLibrary(store: store, remote: { api }, restore: false)
        _ = await library.sessions()
        #expect(api.count("sessions") == 1)
    }

    // MARK: binding

    /// The live app's pairing: the client and the owner both follow the Demo data switch.
    private func boundOutbox(demo: Switch, live: MockPlatformAPI, mock: MockPlatformAPI) -> (TrainSyncService, TrainStore) {
        let store = TrainStore(inMemory: true)
        let sync = TrainSyncService(store: store, remote: { demo.on ? mock : live },
                                    owner: { demo.on ? TrainSyncService.demoOwner : "A" },
                                    debounce: .seconds(3_600), monitorsNetwork: false)
        sync.gate = { _ in nil }
        return (sync, store)
    }

    @Test func aDemoOpNeverGoesLive() async {
        let demo = Switch(true), live = MockPlatformAPI(), mock = MockPlatformAPI()
        let (sync, store) = boundOutbox(demo: demo, live: live, mock: mock)
        sync.sessionChanged(SessionFactory.empty(in: store))
        demo.on = false
        await sync.flush()
        #expect(live.calls.isEmpty && mock.calls.isEmpty && sync.pendingCount == 1)
        demo.on = true
        await sync.flush()
        #expect(mock.count("putSession") == 1 && live.calls.isEmpty && sync.pendingCount == 0)
    }

    @Test func anAccountOpNeverGoesToTheMock() async {
        let demo = Switch(false), live = MockPlatformAPI(), mock = MockPlatformAPI()
        let (sync, store) = boundOutbox(demo: demo, live: live, mock: mock)
        sync.sessionChanged(SessionFactory.empty(in: store))
        demo.on = true
        await sync.flush()
        #expect(mock.calls.isEmpty && live.calls.isEmpty && sync.pendingCount == 1)
        demo.on = false
        await sync.flush()
        #expect(live.count("putSession") == 1 && mock.calls.isEmpty)
    }

    @Test func anOpFromBeforeBindingIsTheAccountsAndWaitsWhileDemoIsOn() async {
        let demo = Switch(true), live = MockPlatformAPI(), mock = MockPlatformAPI()
        let (sync, store) = boundOutbox(demo: demo, live: live, mock: mock)
        let s = SessionFactory.empty(in: store)
        store.enqueue(.put, sessionID: s.id) // no owner: queued by an earlier build
        await sync.flush()
        #expect(mock.calls.isEmpty && live.calls.isEmpty)
        demo.on = false
        await sync.flush()
        #expect(live.count("putSession") == 1 && mock.calls.isEmpty)
    }

    @Test func eachOpRecordsItsOwner() {
        let demo = Switch(true), live = MockPlatformAPI(), mock = MockPlatformAPI()
        let (sync, store) = boundOutbox(demo: demo, live: live, mock: mock)
        sync.sessionChanged(SessionFactory.empty(in: store))
        demo.on = false
        sync.sessionChanged(SessionFactory.empty(in: store))
        #expect(store.pendingOps().map(\.account) == [TrainSyncService.demoOwner, "A"])
    }
}
