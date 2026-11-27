import Foundation

extension APIClient {
    static func isRecoveryRoute(_ path: String) -> Bool {
        path.hasPrefix("/v1/recovery/") || (path.hasPrefix("/v1/workouts/") && path.hasSuffix("/rpe"))
    }

    func recoveryStatus() async throws -> RecoveryStatus {
        try await send("GET", path: "/v1/recovery/status", body: Optional<Int>.none)
    }

    func recoveryCheckin(date: String) async throws -> RecoveryCheckin {
        try await send("GET", path: "/v1/recovery/checkins/\(date)", body: Optional<Int>.none)
    }

    func recoveryCheckins(from: String, to: String) async throws -> [RecoveryCheckin] {
        try await send("GET", path: "/v1/recovery/checkins?from=\(from)&to=\(to)", body: Optional<Int>.none)
    }

    func putRecoveryCheckin(date: String, _ body: RecoveryCheckinPut) async throws -> RecoveryCheckin {
        try await send("PUT", path: "/v1/recovery/checkins/\(date)", body: body)
    }

    func deleteRecoveryCheckin(date: String) async throws {
        _ = try await data("DELETE", path: "/v1/recovery/checkins/\(date)", body: Optional<Int>.none)
    }

    func putWorkoutRPE(id: UUID, _ body: WorkoutRPEPut) async throws -> Workout {
        try await send("PUT", path: "/v1/workouts/\(id.uuidString.lowercased())/rpe", body: body)
    }

    func deleteWorkoutRPE(id: UUID) async throws {
        _ = try await data("DELETE", path: "/v1/workouts/\(id.uuidString.lowercased())/rpe", body: Optional<Int>.none)
    }
}
