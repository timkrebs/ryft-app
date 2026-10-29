import Foundation

/// "Last time" for one plan row when a day holds the same exercise more than once (beta feedback 2, §4).
///
/// The platform's `last_time` for a plan target is every working set of that `exercise_id` in the newest completed
/// session, ordered by the session exercise's position, then `set_index`, and concatenated: two rows of one exercise
/// both got the joint list, and their ghosts with it. Each session exercise numbers its sets from 0 (the app renumbers
/// them on delete), so a new occurrence starts where `set_index` stops increasing. The k-th row of the exercise (by
/// position) gets the k-th run; rows past the last run get the last run; a day with the exercise once keeps the list
/// as it came. Pure; a stand-in until the platform returns `last_time` per occurrence.
enum LastTimeOccurrence {
    /// `sets` split where `set_index` doesn't increase. Warm-ups stay in their run.
    static func runs(_ sets: [SessionSet]) -> [[SessionSet]] {
        var out: [[SessionSet]] = []
        for set in sets {
            if let previous = out.last?.last, set.setIndex > previous.setIndex {
                out[out.count - 1].append(set)
            } else {
                out.append([set])
            }
        }
        return out
    }

    /// The run for occurrence `index` (0-based) of `count` rows of one exercise.
    static func sets(_ sets: [SessionSet], occurrence index: Int, of count: Int) -> [SessionSet] {
        guard count > 1 else { return sets }
        let runs = runs(sets)
        guard let last = runs.last else { return [] }
        return runs.indices.contains(index) ? runs[index] : last
    }

    /// The last time for `row`, given its target's `lastTime` and every row of its day.
    static func sets(_ sets: [SessionSet], for row: PlanExercise, in day: [PlanExercise]) -> [SessionSet] {
        let same = day.enumerated()
            .filter { $0.element.exerciseId == row.exerciseId }
            .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
            .map(\.element.id)
        guard let index = same.firstIndex(of: row.id) else { return sets }
        return Self.sets(sets, occurrence: index, of: same.count)
    }
}
