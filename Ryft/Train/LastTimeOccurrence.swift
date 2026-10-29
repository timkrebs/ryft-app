import Foundation

/// "Last time" for one plan row when a day holds the same exercise more than once (beta feedback 2, §4).
///
/// The platform's `last_time` for a plan target is the completed working sets of that `exercise_id` in the newest
/// completed session, ordered by the session exercise's position, then `set_index`, and concatenated: two rows of one
/// exercise both got the joint list, and their ghosts with it. Each session exercise numbers its sets from 0, so a new
/// occurrence usually starts where `set_index` stops increasing. The list is split only when that gives exactly as many
/// runs as the day has rows of the exercise; then the k-th row (by position) gets the k-th run. Otherwise every row
/// keeps the joint list, as before: a wrong split is worse than none. Known limits, all falling back to the joint list:
/// - Warm-ups and unfinished sets are left out, so `set_index` has gaps; an occurrence that starts above where the
///   previous one ended merges with it (fewer runs than rows).
/// - An occurrence with no completed working sets isn't in the list at all (fewer runs than rows).
/// - Two sets with one `set_index` (a 409 merge keeps both, `SessionMerge.mergeSets` sorts the tie) split a run (more
///   runs than rows).
/// Pure; a stand-in until the platform returns `last_time` per occurrence (`docs/API_REQUESTS.md`).
enum LastTimeOccurrence {
    /// `sets` split where `set_index` doesn't increase.
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

    /// The sets for occurrence `index` (0-based) of `count` rows of one exercise: its run when the runs and rows
    /// match one to one, else the whole list.
    static func sets(_ sets: [SessionSet], occurrence index: Int, of count: Int) -> [SessionSet] {
        guard count > 1 else { return sets }
        let runs = runs(sets)
        guard runs.count == count, runs.indices.contains(index) else { return sets }
        return runs[index]
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
