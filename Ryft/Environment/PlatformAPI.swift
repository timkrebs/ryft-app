import Foundation

/// The whole platform surface (`../plattform/docs/API.md`): what screens read
/// (`RyftDataSource`), Train (`TrainDataSource`), and the calls services make.
/// `APIClient` is the live implementation, `MockPlatformAPI` the in-memory one.
protocol PlatformAPI: RyftDataSource, TrainDataSource {
    func sync(_ req: SyncRequest) async throws -> SyncResponse
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
}

/// The platform in memory: screens read `MockDataSource`, Train runs on
/// `MockTrainSource`, and every service call is recorded. Tests script failures
/// with `failure` (thrown by every call until cleared) or `failNext`.
final class MockPlatformAPI: PlatformAPI, @unchecked Sendable {
    private let lock = NSLock()
    private let screens: RyftDataSource
    private let train: TrainDataSource

    var failure: Error?
    /// Thrown once by the next call.
    var failNext: Error?
    var syncResponse = SyncResponse(samples: 0, sleep: 0, workouts: 0, daysTouched: [])
    var remoteConfig = RemoteConfig(flags: [:], evaluatedAt: .now, ttlSec: 21_600)
    var prefs = NotificationPrefs.allOn
    /// `false`: the journal endpoints answer `404`, as before M5 is deployed.
    var journalLive = true
    private var behaviorList = MockJournal.behaviors
    private var journals: [String: JournalDay] = [:]
    private(set) var journalPuts: [String: JournalPut] = [:]
    private(set) var planWakes: [String] = []
    private(set) var mePatches: [UserPatch] = []

    private(set) var calls: [String] = []
    private(set) var syncRequests: [SyncRequest] = []
    private(set) var pushRegistrations: [PushRegistration] = []
    private(set) var appleCodes: [String] = []

    init(screens: RyftDataSource = MockDataSource.shared, train: TrainDataSource = MockTrainSource.shared) {
        self.screens = screens
        self.train = train
    }

    /// Records the call, then throws a scripted failure if there is one.
    private func enter(_ name: String) throws {
        let error: Error? = lock.withLock {
            calls.append(name)
            if let e = failNext { failNext = nil; return e }
            return failure
        }
        if let error { throw error }
    }

    func count(_ name: String) -> Int { lock.withLock { calls.filter { $0 == name }.count } }

    // MARK: services

    func sync(_ req: SyncRequest) async throws -> SyncResponse {
        try enter("sync")
        lock.withLock { syncRequests.append(req) }
        return syncResponse
    }

    func postAppleAuthorization(code: String) async throws {
        try enter("appleAuthorization")
        lock.withLock { appleCodes.append(code) }
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

    // MARK: sleep planner, journal

    func sleepPlan(wake: String) async throws -> SleepPlan {
        try enter("sleepPlan")
        lock.withLock { planWakes.append(wake) }
        return MockJournal.sleepPlan(wake: wake)
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

    func me() async throws -> User { try enter("me"); return try await screens.me() }
    func patchMe(_ p: UserPatch) async throws -> User {
        try enter("patchMe")
        lock.withLock { mePatches.append(p) }
        return try await screens.patchMe(p)
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
}
