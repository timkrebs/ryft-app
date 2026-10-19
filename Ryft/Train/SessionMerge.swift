import Foundation

/// Resolves a `409` on `PUT /v1/sessions/{id}`: the server's copy has a newer
/// set (another device, or an earlier upload this phone no longer has).
enum SessionMerge {
    /// Exercises and sets are merged by id. A set in both keeps the later
    /// `updated_at` (the local one on a tie); one on either side is kept unless
    /// it was deleted locally. Session fields stay local (this phone is the one
    /// logging), except the scores only the server computes.
    static func merge(local: TrainSession, server: TrainSession, deletedSetIDs: Set<UUID> = []) -> TrainSession {
        var out = local
        out.muscularTrimp = local.muscularTrimp ?? server.muscularTrimp
        out.strain = local.strain ?? server.strain
        out.volumeKg = local.volumeKg ?? server.volumeKg
        out.workoutId = local.workoutId ?? server.workoutId

        let serverExercises = Dictionary(server.exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var exercises: [TrainSessionExercise] = local.exercises.map { mine in
            guard let theirs = serverExercises[mine.id] else { return mine }
            var merged = mine
            merged.sets = mergeSets(mine.sets, theirs.sets, deleted: deletedSetIDs)
            return merged
        }
        let localIDs = Set(local.exercises.map(\.id))
        for theirs in server.exercises where !localIDs.contains(theirs.id) {
            var e = theirs
            e.sets = theirs.sets.filter { !deletedSetIDs.contains($0.id) }
            exercises.append(e)
        }
        out.exercises = exercises.sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) }
        return out
    }

    static func mergeSets(_ mine: [TrainSet], _ theirs: [TrainSet], deleted: Set<UUID>) -> [TrainSet] {
        var byID: [UUID: TrainSet] = [:]
        for s in theirs where !deleted.contains(s.id) { byID[s.id] = s }
        for s in mine {
            if let other = byID[s.id], other.updatedAt > s.updatedAt { continue }
            byID[s.id] = s
        }
        return byID.values.sorted { ($0.setIndex, $0.updatedAt) < ($1.setIndex, $1.updatedAt) }
    }
}
