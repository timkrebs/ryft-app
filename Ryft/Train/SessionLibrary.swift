import Foundation

/// What a live session reads from (and writes to) the exercise and plan library while it runs: an exercise's
/// "Last time" for a replacement, and the user's own plan for "Also change the plan". A seam, so tests decide what
/// is cached and whether a plan save succeeds (`SessionController`, design.md §1, §5).
@MainActor
protocol SessionLibrary: AnyObject {
    /// The working sets of the newest finished session with this exercise, from the cache only (no request).
    /// Empty when nothing is cached.
    func cachedLastTime(for exerciseID: UUID) -> [SessionSet]
    /// The same, asked for again (`GET /v1/exercises/{id}/history`); the cached copy when the request fails,
    /// empty when there is none.
    func lastTime(for exerciseID: UUID) async -> [SessionSet]
    /// A cached plan the user may change (not built-in) that holds this plan exercise; nil otherwise.
    func editablePlan(containing planExerciseID: UUID) -> Plan?
    /// `PUT /v1/plans/{id}` (online only). `false` when it failed.
    func savePlan(_ plan: Plan) async -> Bool
}

extension TrainLibrary: SessionLibrary {
    func cachedLastTime(for exerciseID: UUID) -> [SessionSet] {
        Self.lastWorkingSets(in: cachedHistory(for: exerciseID))
    }

    func lastTime(for exerciseID: UUID) async -> [SessionSet] {
        Self.lastWorkingSets(in: await history(for: exerciseID))
    }

    func editablePlan(containing planExerciseID: UUID) -> Plan? {
        store.plans().first { plan in
            !plan.isBuiltin && plan.days.contains { day in day.exercises.contains { $0.id == planExerciseID } }
        }
    }

    /// History is newest first: the first session's sets, warm-ups left out.
    nonisolated static func lastWorkingSets(in history: ExerciseHistory?) -> [SessionSet] {
        guard let sets = history?.sessions.first?.sets else { return [] }
        return sets.filter { !$0.isWarmup }.sorted { $0.setIndex < $1.setIndex }
    }
}
