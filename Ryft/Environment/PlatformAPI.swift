import Foundation

/// The whole platform surface (`../plattform/docs/API.md`): what screens read
/// (`RyftDataSource`), Train (`TrainDataSource`), activities (`ActivitiesAPI`, a draft
/// until the contract is published), and the calls services make.
/// `APIClient` is the live implementation, `MockPlatformAPI` the in-memory one.
protocol PlatformAPI: RyftDataSource, TrainDataSource, ActivitiesAPI {
    /// `POST /v1/sync`; the body is a `SyncRequest`, encoded by `SyncEngine` off the main actor,
    /// gzipped when `contentEncoding` is `"gzip"`.
    func sync(encoded body: Data, contentEncoding: String?) async throws -> SyncResponse
    /// `POST /v1/me/apple-authorization`, once after Sign in with Apple.
    func postAppleAuthorization(code: String) async throws
    /// `GET /v1/config`: feature flags evaluated for the caller.
    func config() async throws -> RemoteConfig
    /// `POST /v1/devices/{id}/push`.
    func registerPush(deviceID: UUID, _ registration: PushRegistration) async throws
    /// `DELETE /v1/devices/{id}/push`.
    func deletePush(deviceID: UUID) async throws
    /// `PATCH /v1/me/notifications`.
    func patchNotifications(_ patch: NotificationPatch) async throws -> NotificationPrefs

    // Beta gates and sync state.
    /// `GET /v1/me/sync`: the gate, the newest record per kind, today's scoring state.
    func syncStatus() async throws -> SyncStatus
    /// `POST /v1/me/consent`: `204`; `422` when `policyVersion` isn't the one in force.
    func consent(policyVersion: String, appVersion: String?) async throws
    /// `DELETE /v1/me/consent`: `204`; sync answers `403 consent_required` from then on.
    func revokeConsent() async throws
    /// `POST /v1/me/invite`: `204`; `422` for every bad code, `429` after 5 tries an hour.
    func redeemInvite(code: String) async throws
    /// `POST /v1/feedback`: `204`; `429` after 10 a day; `422` outside the limits. Open behind the invite gate.
    func postFeedback(_ post: FeedbackPost) async throws

    /// `GET /v1/sleep/plan?wake=HH:MM` (local wake time).
    func sleepPlan(wake: String) async throws -> SleepPlan

    // Journal (M5). `404` until the platform deploys it: callers hide the feature.
    /// `GET /v1/behaviors`.
    func behaviors() async throws -> [Behavior]
    /// `PATCH /v1/behaviors`: the whole list back.
    func patchBehaviors(_ patch: BehaviorsPatch) async throws -> [Behavior]
    /// `POST /v1/behaviors`: `201` new, `200` repeated; `409` id taken.
    func createBehavior(_ input: BehaviorInput) async throws -> Behavior
    /// `DELETE /v1/behaviors/{id}`: `204`; `403` for a built-in.
    func deleteBehavior(id: UUID) async throws
    /// `GET /v1/journal/{day}`.
    func journal(day: String) async throws -> JournalDay
    /// `PUT /v1/journal/{day}`: replaces the day.
    func putJournal(day: String, _ body: JournalPut) async throws -> JournalDay
    /// `GET /v1/behaviors/impact`.
    func behaviorImpact() async throws -> BehaviorImpacts
}

extension APIClient: PlatformAPI {
    func config() async throws -> RemoteConfig {
        try await send("GET", path: "/v1/config", body: Optional<Int>.none)
    }

    /// `204`.
    func registerPush(deviceID: UUID, _ registration: PushRegistration) async throws {
        _ = try await data("POST", path: "/v1/devices/\(deviceID.uuidString.lowercased())/push", body: registration)
    }

    /// `204`, also when there is none.
    func deletePush(deviceID: UUID) async throws {
        _ = try await data("DELETE", path: "/v1/devices/\(deviceID.uuidString.lowercased())/push",
                           body: Optional<Int>.none)
    }

    func patchNotifications(_ patch: NotificationPatch) async throws -> NotificationPrefs {
        try await send("PATCH", path: "/v1/me/notifications", body: patch)
    }

    func syncStatus() async throws -> SyncStatus {
        try await send("GET", path: "/v1/me/sync", body: Optional<Int>.none)
    }

    func consent(policyVersion: String, appVersion: String?) async throws {
        _ = try await data("POST", path: "/v1/me/consent",
                           body: ConsentPost(policyVersion: policyVersion, appVersion: appVersion))
    }

    func revokeConsent() async throws {
        _ = try await data("DELETE", path: "/v1/me/consent", body: Optional<Int>.none)
    }

    func redeemInvite(code: String) async throws {
        _ = try await data("POST", path: "/v1/me/invite", body: InvitePost(code: code))
    }

    func sleepPlan(wake: String) async throws -> SleepPlan {
        try await send("GET", path: "/v1/sleep/plan?wake=\(wake)", body: Optional<Int>.none)
    }

    func behaviors() async throws -> [Behavior] {
        try await send("GET", path: "/v1/behaviors", body: Optional<Int>.none)
    }

    func patchBehaviors(_ patch: BehaviorsPatch) async throws -> [Behavior] {
        try await send("PATCH", path: "/v1/behaviors", body: patch)
    }

    func createBehavior(_ input: BehaviorInput) async throws -> Behavior {
        try await send("POST", path: "/v1/behaviors", body: input)
    }

    func deleteBehavior(id: UUID) async throws {
        _ = try await data("DELETE", path: "/v1/behaviors/\(id.uuidString.lowercased())", body: Optional<Int>.none)
    }

    func journal(day: String) async throws -> JournalDay {
        try await send("GET", path: "/v1/journal/\(day)", body: Optional<Int>.none)
    }

    func putJournal(day: String, _ body: JournalPut) async throws -> JournalDay {
        try await send("PUT", path: "/v1/journal/\(day)", body: body)
    }

    func behaviorImpact() async throws -> BehaviorImpacts {
        try await send("GET", path: "/v1/behaviors/impact", body: Optional<Int>.none)
    }

    /// `204`. One attempt (`singleAttempt`): the report queue retries, a retry after the platform stored
    /// the report would file it twice, and a `429` (10 a day) answers at once instead of waiting out
    /// `Retry-After`.
    func postFeedback(_ post: FeedbackPost) async throws {
        _ = try await APIClient.$singleAttempt.withValue(true) {
            try await exchange("POST", path: "/v1/feedback", body: post, unavailableRetries: 0)
        }
    }
}

/// The platform in memory: screens read `MockDataSource`, Train runs on
/// `MockTrainSource`, activities on `activitySource`, and every service call is
/// recorded. Tests script failures with `failure` (thrown by every call until
/// cleared) or `failNext`.
final class MockPlatformAPI: PlatformAPI, @unchecked Sendable {
    private let lock = NSLock()
    private let screens: RyftDataSource
    private let train: TrainDataSource

    var failure: Error?
    /// Thrown once by the next call.
    var failNext: Error?
    var syncResponse = SyncResponse(samples: 0, sleep: 0, workouts: 0, daysTouched: [])
    /// Demo data shows the features that ship dark for accounts: the tracker setup (`devices.setup`), My Day and
    /// activities.
    var remoteConfig = RemoteConfig(flags: MockPlatformAPI.demoFlags, evaluatedAt: .now, ttlSec: 21_600,
                                    privacyPolicyVersion: MockData.policyVersion,
                                    privacyPolicyUrl: "https://ryftapp.de/privacy")
    static let demoFlags: [String: Bool] = {
        var on: [FeatureFlag] = [.devicesSetup, .todayMyDay, .activitiesManual]
        #if DEBUG
        // Never in a Release demo before the release PR that adds the location background mode and turns
        // recording on (design.md §8.5, §10 → Flags): App Review can open demo data.
        on += [.activitiesRecording, .activityLiveHR]
        #endif
        return Dictionary(uniqueKeysWithValues: on.map { ($0.rawValue, true) })
    }()
    var prefs = NotificationPrefs.allOn

    // The account behind the Beta gates; `me()` reports it, the gates follow it.
    var betaAccess = true
    var accountConsent: Consent? = Consent(policyVersion: MockData.policyVersion, grantedAt: MockData.consentedAt)
    var accountHint: AccountHint?
    /// `GET /v1/me/sync` → `gate`: the invite gate when it's on (or warns) and there's no access.
    var inviteGateOn = false
    /// Valid codes for `POST /v1/me/invite`, compared like the platform (case, spaces and dashes ignored).
    var inviteCodes: Set<String> = ["RYFT7K3MQX9P"]
    var scoringToday = TodayState(day: DayFormat.string(from: .now), state: .scored, scoredAt: .now,
                                  modelVersion: "2026.10.1")
    var pendingDays: [String] = []
    /// `GET /v1/me/sync` → `resync_requested_at` (the operator's request).
    var resyncRequestedAt: Date?
    private(set) var consentPosts: [String] = []
    private(set) var inviteAttempts: [String] = []
    /// `false`: the journal endpoints answer `404`, as before M5 is deployed.
    var journalLive = true
    private var behaviorList = MockJournal.behaviors
    private var journals: [String: JournalDay] = [:]
    private(set) var journalPuts: [String: JournalPut] = [:]
    private(set) var planWakes: [String] = []
    /// Scripts `GET /v1/sleep/plan` (tests); the mock plan otherwise.
    var planFor: (@Sendable (String) -> SleepPlan)?
    /// The mock plan's "now": `wake` resolves to its next occurrence after it, as on the server. The activities
    /// follow it too.
    var now: @Sendable () -> Date = { .now } {
        didSet { activitySource.now = now }
    }
    /// Activities and manual sleep (`ActivitiesAPI`): empty and scored at once by default (tests); the demo
    /// graphs pass `MockActivitiesSource.demoSource()`.
    let activitySource: MockActivitiesSource
    private(set) var mePatches: [UserPatch] = []

    private(set) var calls: [String] = []
    private(set) var syncRequests: [SyncRequest] = []
    private(set) var pushRegistrations: [PushRegistration] = []
    private(set) var appleCodes: [String] = []

    init(screens: RyftDataSource = MockDataSource.shared, train: TrainDataSource = MockTrainSource.shared,
         activities: MockActivitiesSource = MockActivitiesSource()) {
        self.screens = screens
        self.train = train
        activitySource = activities
        #if DEBUG
        faults = FaultInjection.parse(UserDefaults.standard.string(forKey: "RyftFault"))
        #endif
    }

    #if DEBUG
    /// Fault injection (DEBUG only, compiled out of Release): `-RyftFault "/v1/me=429:2x1,/v1/days=timeout"` in
    /// demo mode (or a test setting `faults`) makes the named routes fail the way one attempt of the live
    /// client fails (scheduled reads make single attempts; `ReadScheduler` retries above this). Keyed by the
    /// call name `enter` records; a rule with `remaining` fails that many calls, then lets them through.
    var faults: [String: FaultInjection.Rule] = [:]
    #endif

    /// Records the call, then throws a scripted failure if there is one.
    private func enter(_ name: String) throws {
        let error: Error? = lock.withLock {
            calls.append(name)
            if let e = failNext { failNext = nil; return e }
            #if DEBUG
            if let rule = faults[name] {
                switch rule.remaining {
                case nil:
                    return rule.fault.error(route: name)
                case let n? where n > 0:
                    faults[name]?.remaining = n - 1
                    return rule.fault.error(route: name)
                default:
                    faults[name] = nil
                }
            }
            #endif
            return failure
        }
        if let error { throw error }
    }

    func count(_ name: String) -> Int { lock.withLock { calls.filter { $0 == name }.count } }

    // MARK: services

    /// Runs before each sync answers (tests hold an upload open with it).
    var beforeSync: (@Sendable () async -> Void)?

    func sync(encoded body: Data, contentEncoding: String?) async throws -> SyncResponse {
        let onMain = MainThread.isCurrent
        try enter("sync")
        await beforeSync?()
        lock.withLock { syncEncodings.append(contentEncoding) }
        if contentEncoding == "gzip", refusesGzip { throw APIError.http(415, "unsupported content encoding") }
        if enforcesConsent, gate == .consentRequired {
            throw APIError.http(403, "consent required", code: .consentRequired)
        }
        let json = contentEncoding == "gzip" ? try Gzip.decompress(body) : body
        let req = try APIClient.jsonDecoder.decode(SyncRequest.self, from: json)
        lock.withLock {
            syncRequests.append(req)
            syncBodySizes.append(body.count)
            if onMain { syncsOnMainThread += 1 }
        }
        afterSync?()
        return syncResponse
    }

    /// The encoded size of every sync body, in order.
    private(set) var syncBodySizes: [Int] = []
    /// Every sync's `Content-Encoding`, in order (`nil`: plain JSON).
    private(set) var syncEncodings: [String?] = []
    /// A platform that doesn't take gzip yet: `415`.
    var refusesGzip = false
    /// Syncs called from the main thread (uploads belong off it).
    private(set) var syncsOnMainThread = 0

    /// `CONSENT_ENFORCE=on`: sync without consent to the current policy answers `403`.
    var enforcesConsent = false
    /// Runs after each accepted sync (tests change the world between pages with it).
    var afterSync: (@Sendable () -> Void)?
    /// After a withdrawal every call fails (the re-check gets no answer).
    var failAfterRevoke = false

    func postAppleAuthorization(code: String) async throws {
        try enter("appleAuthorization")
        lock.withLock { appleCodes.append(code) }
    }

    /// Reports `POST /v1/feedback` took, oldest first (`failure`/`failNext` script offline and `5xx`).
    private(set) var feedbackPosts: [FeedbackPost] = []
    /// The platform's cap per user and day: the next report past it answers `429`.
    var feedbackDailyLimit = 10
    private var feedbackDays: [String] = []

    /// Runs before each report is taken (tests hold one open with it).
    var beforeFeedback: (@Sendable (FeedbackPost) async -> Void)?

    func postFeedback(_ post: FeedbackPost) async throws {
        try enter("feedback")
        await beforeFeedback?(post)
        let today = DayFormat.string(from: now())
        try lock.withLock {
            guard feedbackDays.filter({ $0 == today }).count < feedbackDailyLimit else {
                throw APIError.http(429, "at most 10 reports a day", requestID: "mock-feedback-429")
            }
            feedbackDays.append(today)
            feedbackPosts.append(post)
        }
    }

    func config() async throws -> RemoteConfig { try enter("config"); return remoteConfig }

    func registerPush(deviceID: UUID, _ registration: PushRegistration) async throws {
        try enter("registerPush")
        lock.withLock { pushRegistrations.append(registration) }
    }

    func deletePush(deviceID: UUID) async throws { try enter("deletePush") }

    func patchNotifications(_ patch: NotificationPatch) async throws -> NotificationPrefs {
        try enter("patchNotifications")
        var categories = prefs.categories
        for (k, v) in patch.categories ?? [:] { categories[k] = v }
        let quiet = patch.quietHours.map { $0 } ?? prefs.quietHours
        prefs = NotificationPrefs(categories: categories, quietHours: quiet)
        return prefs
    }

    // MARK: Beta gates

    /// The gate `GET /v1/me/sync` reports: invite first, then consent.
    var gate: APIErrorCode? {
        lock.withLock {
            if inviteGateOn, !betaAccess { return .inviteRequired }
            if accountConsent?.policyVersion != remoteConfig.privacyPolicyVersion { return .consentRequired }
            return nil
        }
    }

    func syncStatus() async throws -> SyncStatus {
        try enter("syncStatus")
        let gate = gate
        return lock.withLock {
            SyncStatus(gate: gate, lastSyncAt: syncRequests.isEmpty ? nil : .now, lastSyncDevice: "iPhone",
                       latest: [:], today: scoringToday, pendingDays: pendingDays, expectedWithinSec: 20,
                       resyncRequestedAt: resyncRequestedAt)
        }
    }

    func consent(policyVersion: String, appVersion: String?) async throws {
        try enter("consent")
        try lock.withLock {
            guard policyVersion == remoteConfig.privacyPolicyVersion else { throw APIError.http(422, "outdated policy") }
            consentPosts.append(policyVersion)
            if accountConsent?.policyVersion != policyVersion {
                accountConsent = Consent(policyVersion: policyVersion, grantedAt: .now)
            }
        }
    }

    func revokeConsent() async throws {
        try enter("revokeConsent")
        lock.withLock {
            accountConsent = nil
            if failAfterRevoke { failure = APIError.transport(URLError(.timedOut)) }
        }
    }

    func redeemInvite(code: String) async throws {
        try enter("redeemInvite")
        try lock.withLock {
            inviteAttempts.append(code)
            guard !betaAccess else { return }
            let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
            guard inviteCodes.contains(normalized) else { throw APIError.http(422, "invalid or used code") }
            betaAccess = true
        }
    }

    // MARK: sleep planner, journal

    func sleepPlan(wake: String) async throws -> SleepPlan {
        try enter("sleepPlan")
        lock.withLock { planWakes.append(wake) }
        if let plan = planFor?(wake) { return plan }
        return MockJournal.sleepPlan(wake: wake, now: now())
    }

    private func enterJournal(_ name: String) throws {
        try enter(name)
        if !journalLive { throw APIError.http(404, "not found") }
    }

    func behaviors() async throws -> [Behavior] {
        try enterJournal("behaviors")
        return lock.withLock { behaviorList }
    }

    func patchBehaviors(_ patch: BehaviorsPatch) async throws -> [Behavior] {
        try enterJournal("patchBehaviors")
        return try lock.withLock {
            for (id, on) in patch.enabled {
                guard let i = behaviorList.firstIndex(where: { $0.id.uuidString.lowercased() == id }) else {
                    throw APIError.http(422, "unknown behavior")
                }
                behaviorList[i].enabled = on
            }
            return behaviorList
        }
    }

    func createBehavior(_ input: BehaviorInput) async throws -> Behavior {
        try enterJournal("createBehavior")
        return try lock.withLock {
            if let existing = behaviorList.first(where: { $0.id == input.id }), !existing.isCustom {
                throw APIError.http(409, "id taken")
            }
            guard (1...60).contains(input.name.count) else { throw APIError.http(422, "name") }
            let b = Behavior(id: input.id, slug: input.name.lowercased().replacingOccurrences(of: " ", with: "-"),
                             name: input.name, nameEn: input.name, nameDe: input.nameDe ?? input.name,
                             category: input.category ?? .custom, kind: input.kind, defaultOn: true, enabled: true,
                             isCustom: true, sort: 0)
            behaviorList.removeAll { $0.id == input.id }
            behaviorList.append(b)
            return b
        }
    }

    func deleteBehavior(id: UUID) async throws {
        try enterJournal("deleteBehavior")
        try lock.withLock {
            if let b = behaviorList.first(where: { $0.id == id }), !b.isCustom { throw APIError.http(403, "built-in") }
            behaviorList.removeAll { $0.id == id }
        }
    }

    func journal(day: String) async throws -> JournalDay {
        try enterJournal("journal")
        return lock.withLock { journals[day] } ?? MockJournal.journal(day: day)
    }

    func putJournal(day: String, _ body: JournalPut) async throws -> JournalDay {
        try enterJournal("putJournal")
        guard MockJournal.isEditable(day) else { throw APIError.http(422, "not editable") }
        let saved = JournalDay(day: day, answered: true, answeredAt: .now, editable: true, entries: body.entries)
        lock.withLock {
            journals[day] = saved
            journalPuts[day] = body
        }
        return saved
    }

    func behaviorImpact() async throws -> BehaviorImpacts {
        try enterJournal("behaviorImpact")
        return MockJournal.impacts
    }

    // MARK: screens

    /// Runs before `me()` answers (tests hold an export's archive open with it).
    var beforeMe: (@Sendable () async -> Void)?

    func me() async throws -> User {
        try enter("me")
        await beforeMe?()
        if let patched = lock.withLock({ patchedUser }) { return withAccount(patched) }
        return withAccount(try await screens.me())
    }

    func patchMe(_ p: UserPatch) async throws -> User {
        try enter("patchMe")
        lock.withLock { mePatches.append(p) }
        await beforePatchMe?()
        // On top of the earlier patches, like the platform's stored user.
        let base = lock.withLock { patchedUser }
        let user: User
        if let mock = screens as? MockDataSource {
            user = try await mock.patchMe(p, on: base ?? MockData.user)
        } else {
            user = try await screens.patchMe(p)
        }
        lock.withLock { patchedUser = user }
        return withAccount(user)
    }

    /// The user after the patches so far (`nil`: none yet).
    private var patchedUser: User?

    /// Runs before each `PATCH /v1/me` answers (tests hold one open with it).
    var beforePatchMe: (@Sendable () async -> Void)?

    /// The scripted access, consent and hint on top of the mock user.
    private func withAccount(_ user: User) -> User {
        var u = user
        lock.withLock {
            u.betaAccess = betaAccess
            u.consent = accountConsent
            u.accountHint = accountHint
        }
        return u
    }
    func days(from: Date, to: Date) async throws -> [DailyScore] {
        try enter("days"); return try await screens.days(from: from, to: to)
    }
    func day(_ date: Date) async throws -> DayDetail { try enter("day"); return try await screens.day(date) }
    func sleep(range: SleepRangeKind) async throws -> SleepRange {
        try enter("sleep"); return try await screens.sleep(range: range)
    }
    func workouts(from: Date, to: Date) async throws -> [Workout] {
        try enter("workouts"); return try await screens.workouts(from: from, to: to)
    }
    func workout(id: UUID) async throws -> WorkoutDetail { try enter("workout"); return try await screens.workout(id: id) }
    func trends(metric: TrendMetric, range: TrendRange) async throws -> TrendSeries {
        try enter("trends"); return try await screens.trends(metric: metric, range: range)
    }
    func insights() async throws -> [Insight] { try enter("insights"); return try await screens.insights() }
    func recompute(from: Date, to: Date) async throws { try enter("recompute") }
    func deleteMe() async throws -> AccountDeleted { try enter("deleteMe"); return try await screens.deleteMe() }

    // MARK: Train

    func exercises() async throws -> [Exercise] { try enter("exercises"); return try await train.exercises() }
    func createExercise(_ e: Exercise) async throws -> Exercise {
        try enter("createExercise"); return try await train.createExercise(e)
    }
    func exerciseHistory(id: UUID) async throws -> ExerciseHistory {
        try enter("exerciseHistory"); return try await train.exerciseHistory(id: id)
    }
    func plans() async throws -> PlansOverview { try enter("plans"); return try await train.plans() }
    func plan(id: UUID) async throws -> Plan { try enter("plan"); return try await train.plan(id: id) }
    func savePlan(_ p: Plan) async throws -> Plan { try enter("savePlan"); return try await train.savePlan(p) }
    func deletePlan(id: UUID) async throws { try enter("deletePlan"); try await train.deletePlan(id: id) }
    func enroll(planID: UUID) async throws -> Enrollment {
        try enter("enroll"); return try await train.enroll(planID: planID)
    }
    func pauseEnrollment() async throws { try enter("pauseEnrollment"); try await train.pauseEnrollment() }
    func planToday() async throws -> PlanToday? { try enter("planToday"); return try await train.planToday() }
    func sessions(from: Date, to: Date) async throws -> [SessionSummary] {
        try enter("sessions"); return try await train.sessions(from: from, to: to)
    }
    func session(id: UUID) async throws -> TrainSession { try enter("session"); return try await train.session(id: id) }
    func putSession(_ s: TrainSession) async throws -> SessionPutResult {
        try enter("putSession"); return try await train.putSession(s)
    }
    func completeSession(id: UUID, _ body: SessionComplete) async throws -> TrainSession {
        try enter("completeSession"); return try await train.completeSession(id: id, body)
    }
    func deleteSession(id: UUID) async throws { try enter("deleteSession"); try await train.deleteSession(id: id) }

    // MARK: activities (draft)

    var publishesActivities: Bool { activitySource.publishesActivities }

    func putActivity(_ a: SportActivity) async throws -> SportActivity {
        try enter("putActivity"); return try await activitySource.putActivity(a)
    }
    func activities(from: Date, to: Date) async throws -> [SportActivity] {
        try enter("activities"); return try await activitySource.activities(from: from, to: to)
    }
    func activity(id: UUID) async throws -> SportActivity {
        try enter("activity"); return try await activitySource.activity(id: id)
    }
    func deleteActivity(id: UUID) async throws {
        try enter("deleteActivity"); try await activitySource.deleteActivity(id: id)
    }
    func putManualSleep(day: String, _ body: ManualSleepPut) async throws {
        try enter("putManualSleep"); try await activitySource.putManualSleep(day: day, body)
    }
    func deleteManualSleep(day: String) async throws {
        try enter("deleteManualSleep"); try await activitySource.deleteManualSleep(day: day)
    }
}

#if DEBUG
/// `-RyftFault "<path>=<fault>[x<n>],…"` (DEBUG only; nothing of this exists in Release). Faults: `429`,
/// `429:7` (with `Retry-After: 7`), `503`, `500`, `404` (any status), `timeout`, `offline`, `cancel`;
/// `x<n>` fails the first n calls only: `-RyftFault "/v1/me=429:1x1,/v1/days=503:1x2"`. Paths are in
/// `routes`. Only the demo / mock API honours it, below the read pipeline, so the real retries run.
enum FaultInjection {
    enum Fault: Equatable, Sendable {
        /// `"429"`, `"429:7"`, `"503:2"`, `"500"`, `"404"`.
        case status(Int, retryAfter: Int?)
        /// `.transport(URLError(.timedOut))`.
        case timeout
        /// `.transport(URLError(.notConnectedToInternet))`.
        case offline
        /// `.transport(URLError(.cancelled))`: what a cancelled task's request throws.
        case cancel

        static let tooManyRequests = Fault.status(429, retryAfter: nil)
        static let unavailable = Fault.status(503, retryAfter: nil)
        static let notFound = Fault.status(404, retryAfter: nil)

        /// What one attempt throws: `.http(status, …, requestID: "fault-<route>", retryAfter:)` (a `429` with
        /// the edge's plain-text body) or `.transport(URLError)`.
        func error(route: String) -> Error {
            switch self {
            case .status(let status, let retryAfter):
                let message: String
                switch status {
                case 429: message = ""
                case 503: message = "request timed out"
                case 404: message = "not found"
                default: message = "injected fault"
                }
                return APIError.http(status, message, requestID: "fault-\(route)", retryAfter: retryAfter)
            case .timeout: return APIError.transport(URLError(.timedOut))
            case .offline: return APIError.transport(URLError(.notConnectedToInternet))
            case .cancel: return APIError.transport(URLError(.cancelled))
            }
        }

        init?(_ spec: String) {
            switch spec {
            case "timeout": self = .timeout
            case "offline": self = .offline
            case "cancel": self = .cancel
            default:
                let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
                guard let status = Int(parts[0]), (100...599).contains(status) else { return nil }
                let retryAfter = parts.count > 1 ? Int(parts[1]) : nil
                if parts.count > 1, retryAfter == nil { return nil }
                self = .status(status, retryAfter: retryAfter)
            }
        }
    }

    struct Rule: Equatable, Sendable {
        var fault: Fault
        /// Calls still to fail; nil: every call.
        var remaining: Int?

        init(_ fault: Fault, times remaining: Int? = nil) {
            self.fault = fault
            self.remaining = remaining
        }
    }

    /// Path → `MockPlatformAPI` call name.
    static let routes: [String: String] = [
        "/v1/me": "me", "/v1/me/sync": "syncStatus", "/v1/days": "days", "/v1/days/{day}": "day",
        "/v1/days/today": "day", "/v1/trends": "trends", "/v1/insights": "insights", "/v1/config": "config",
        "/v1/sync": "sync", "/v1/behaviors": "behaviors", "/v1/journal/{day}": "journal",
        "/v1/behaviors/impact": "behaviorImpact", "/v1/plans": "plans", "/v1/plans/today": "planToday",
        "/v1/exercises": "exercises", "/v1/sleep": "sleep",
        // Activities (draft): the list, an activity's PUT (the upload), a manual sleep's PUT.
        "/v1/activities": "activities", "/v1/activities/{id}": "putActivity", "/v1/sleep/manual/{day}": "putManualSleep",
    ]

    static func parse(_ spec: String?) -> [String: Rule] {
        var out: [String: Rule] = [:]
        for pair in (spec ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let route = routes[parts[0]] else { continue }
            var faultSpec = parts[1]
            var times: Int?
            if let x = faultSpec.lastIndex(of: "x"), let n = Int(faultSpec[faultSpec.index(after: x)...]), n > 0 {
                times = n
                faultSpec = String(faultSpec[..<x])
            }
            guard let fault = Fault(faultSpec) else { continue }
            out[route] = Rule(fault, times: times)
        }
        return out
    }
}
#endif
