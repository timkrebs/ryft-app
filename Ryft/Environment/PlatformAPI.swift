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

    // MARK: screens

    func me() async throws -> User { try enter("me"); return try await screens.me() }
    func patchMe(_ p: UserPatch) async throws -> User { try enter("patchMe"); return try await screens.patchMe(p) }
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
