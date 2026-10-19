// Train endpoints (exercises, plans, sessions). Paths follow the platform's M3b
// brief until `API.md` carries them; see `docs/API_REQUESTS.md` for the open
// points (pausing an enrolment, deleting a set mid-session).
import Foundation

/// Result of `PUT /v1/sessions/{id}`.
enum SessionPutResult: Equatable {
    case saved(TrainSession)
    /// `409`: the server holds a newer set; the body is its copy.
    case conflict(TrainSession)
}

protocol TrainDataSource {
    func exercises() async throws -> [Exercise]
    func createExercise(_ e: Exercise) async throws -> Exercise
    func exerciseHistory(id: UUID) async throws -> ExerciseHistory

    func plans() async throws -> PlanCatalog
    func plan(id: UUID) async throws -> Plan
    func savePlan(_ p: Plan) async throws -> Plan
    func deletePlan(id: UUID) async throws
    func enroll(planID: UUID) async throws -> Enrollment
    func setEnrollment(paused: Bool) async throws -> Enrollment
    func leaveEnrollment() async throws
    /// `nil` when nothing is planned today (`204`).
    func planToday() async throws -> PlanToday?

    func sessions(from: Date, to: Date) async throws -> [TrainSession]
    func session(id: UUID) async throws -> TrainSession
    func putSession(_ s: TrainSession) async throws -> SessionPutResult
    func completeSession(id: UUID, bodyweightKg: Double?) async throws -> CompletedSession
    func deleteSession(id: UUID) async throws
}

enum TrainSource {
    /// The platform, or the in-memory mock in demo mode.
    static var current: TrainDataSource {
        Settings.shared.demoMode ? MockTrainSource.shared as TrainDataSource : APIClient.shared
    }
}

extension APIClient: TrainDataSource {
    private static func idPath(_ id: UUID) -> String { id.uuidString.lowercased() }

    func exercises() async throws -> [Exercise] {
        try await send("GET", path: "/v1/exercises", body: Optional<Int>.none)
    }

    func createExercise(_ e: Exercise) async throws -> Exercise {
        try await send("POST", path: "/v1/exercises", body: e)
    }

    func exerciseHistory(id: UUID) async throws -> ExerciseHistory {
        try await send("GET", path: "/v1/exercises/\(Self.idPath(id))/history?limit=50", body: Optional<Int>.none)
    }

    func plans() async throws -> PlanCatalog {
        try await send("GET", path: "/v1/plans", body: Optional<Int>.none)
    }

    func plan(id: UUID) async throws -> Plan {
        try await send("GET", path: "/v1/plans/\(Self.idPath(id))", body: Optional<Int>.none)
    }

    func savePlan(_ p: Plan) async throws -> Plan {
        try await send("PUT", path: "/v1/plans/\(Self.idPath(p.id))", body: p)
    }

    func deletePlan(id: UUID) async throws {
        _ = try await data("DELETE", path: "/v1/plans/\(Self.idPath(id))", body: Optional<Int>.none)
    }

    func enroll(planID: UUID) async throws -> Enrollment {
        try await send("POST", path: "/v1/plans/\(Self.idPath(planID))/enroll", body: Optional<Int>.none)
    }

    /// Requested in `docs/API_REQUESTS.md` (the brief has no pause endpoint).
    func setEnrollment(paused: Bool) async throws -> Enrollment {
        struct Patch: Encodable { let status: EnrollmentStatus }
        return try await send("PATCH", path: "/v1/plans/enrollment", body: Patch(status: paused ? .paused : .active))
    }

    func leaveEnrollment() async throws {
        _ = try await data("DELETE", path: "/v1/plans/enrollment", body: Optional<Int>.none)
    }

    func planToday() async throws -> PlanToday? {
        let r = try await exchange("GET", path: "/v1/plans/today", body: Optional<Int>.none)
        guard r.status != 204, !r.data.isEmpty else { return nil }
        return try Self.jsonDecoder.decode(PlanToday.self, from: r.data)
    }

    func sessions(from: Date, to: Date) async throws -> [TrainSession] {
        try await send("GET", path: "/v1/sessions?from=\(Self.dayString(from))&to=\(Self.dayString(to))",
                       body: Optional<Int>.none)
    }

    func session(id: UUID) async throws -> TrainSession {
        try await send("GET", path: "/v1/sessions/\(Self.idPath(id))", body: Optional<Int>.none)
    }

    func putSession(_ s: TrainSession) async throws -> SessionPutResult {
        let r = try await exchange("PUT", path: "/v1/sessions/\(Self.idPath(s.id))", body: s, accepting: [409])
        let copy = try Self.jsonDecoder.decode(TrainSession.self, from: r.data)
        return r.status == 409 ? .conflict(copy) : .saved(copy)
    }

    func completeSession(id: UUID, bodyweightKg: Double?) async throws -> CompletedSession {
        try await send("POST", path: "/v1/sessions/\(Self.idPath(id))/complete",
                       body: SessionCompleteRequest(bodyweightKg: bodyweightKg))
    }

    func deleteSession(id: UUID) async throws {
        _ = try await data("DELETE", path: "/v1/sessions/\(Self.idPath(id))", body: Optional<Int>.none)
    }
}
