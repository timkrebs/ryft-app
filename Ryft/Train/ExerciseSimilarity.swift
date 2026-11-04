import Foundation

/// "Similar" in the replace sheet: exercises that could take another's place, from the cached library, on device.
/// The API has no movement pattern (requested in `docs/API_REQUESTS.md`), so this ranks by muscle and equipment
/// and never claims the movement is the same (ui.md §2).
enum ExerciseSimilarity {
    /// At most this many rows.
    static let limit = 6
    /// After the old exercise's own kind: barbell, dumbbell, machine, cable, then the rest.
    static let kindOrder: [ExerciseKind] = [.barbell, .dumbbell, .machine, .cable, .kettlebell, .bodyweight, .cardio]

    /// Candidates share the first primary muscle and the load type (so the kg column and ghosts keep working), and
    /// are neither the exercise itself nor archived. Order: the same kind first, then `kindOrder`, more shared
    /// muscles, the same one-side-at-a-time, built-in before custom, then by name.
    static func rank(for old: Exercise, in library: [Exercise]) -> [Exercise] {
        guard let muscle = old.primaryMuscles.first else { return [] }
        let muscles = Set(old.primaryMuscles + old.secondaryMuscles)
        let candidates = library.filter {
            $0.id != old.id && !$0.archived && $0.loadType == old.loadType && $0.primaryMuscles.first == muscle
        }
        func kindRank(_ e: Exercise) -> Int {
            e.kind == old.kind ? -1 : (kindOrder.firstIndex(of: e.kind) ?? kindOrder.count)
        }
        func overlap(_ e: Exercise) -> Int { muscles.intersection(e.primaryMuscles + e.secondaryMuscles).count }
        let sorted = candidates.sorted { a, b in
            if kindRank(a) != kindRank(b) { return kindRank(a) < kindRank(b) }
            if overlap(a) != overlap(b) { return overlap(a) > overlap(b) }
            let sideA = a.isUnilateral == old.isUnilateral, sideB = b.isUnilateral == old.isUnilateral
            if sideA != sideB { return sideA }
            if a.isCustom != b.isCustom { return !a.isCustom }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return Array(sorted.prefix(limit))
    }
}
