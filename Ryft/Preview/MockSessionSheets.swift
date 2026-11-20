import Foundation

/// Preview states for the live workout's List layout and the sheets it opens (PR 6 B §4.7, §4.8), on top of `FocusedPreview`'s
/// sessions: synthetic values only (the plan's "Upper A", 80 × 5, 60 × 8). Each call builds its own store, so one preview's
/// checks can't reach another's.
@MainActor
enum SessionSheetsPreview {
    /// `b-02`: Bench press's set 1 at 80 × 5, set 2 the current set, a rest running with 1:54 left; last time 4 × 80 × 5 for
    /// Bench press and 4 × 60 × 8 for Barbell row, as the draft's cards say.
    static func listDraft() -> SessionController {
        let c = FocusedPreview.controller(.draftList)
        c.exercises.first?.lastTime = (0..<4).map { SessionSet(setIndex: $0, reps: 5, weightKg: 80) }
        if c.exercises.count > 1 {
            c.exercises[1].lastTime = (0..<4).map { SessionSet(setIndex: $0, reps: 8, weightKg: 60) }
        }
        return c
    }

    /// `listDraft` with Bench press done and folded into its row, and the rest just over: the collapsed row, "Rest over" and,
    /// further down, the superset's bracket.
    static func listFolded() -> SessionController {
        let c = listDraft()
        guard let bench = c.exercises.first else { return c }
        for set in bench.orderedSets where !set.isCompleted {
            let ghost = bench.ghost(forSetAt: set.setIndex)
            set.reps = set.reps ?? ghost.reps ?? 5
            set.weightKg = set.weightKg ?? ghost.kg
            set.completedAt = .now
        }
        c.collapsed.insert(bench.id)
        c.adjustRest(by: -RestTimer.maxRest)
        return c
    }

    /// Replace mode for Bench press: one set done, three to go, a plan day to change too (or not, offline).
    static func replaceContext(split: Bool = true, plan: Bool = true, offline: Bool = false) -> ReplaceContext {
        ReplaceContext(name: MockTrain.bench.name, exerciseID: MockTrain.bench.id,
                       kind: split ? .split(done: 1, remaining: 3) : .inPlace,
                       plan: plan ? PlanChangeOption(dayName: MockTrain.upperA.name, isAvailable: !offline) : nil,
                       offline: offline)
    }
}
