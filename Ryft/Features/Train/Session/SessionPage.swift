import Foundation

/// Which exercise the Focused layout shows (architecture.md §1, ADR 0013). Pure, like `SessionAdvance`, whose states it
/// reads: no SwiftData and no clock.
enum SessionPage {
    /// The stored page while its row exists; else the first exercise with an open working set, else the last one.
    /// `nil` only with no exercises.
    static func resolve(stored: UUID?, in exercises: [SessionAdvance.ExerciseState]) -> UUID? {
        if let stored, exercises.contains(where: { $0.id == stored }) { return stored }
        return SessionAdvance.next(after: nil, in: exercises)?.exerciseID ?? exercises.last?.id
    }

    /// Where the page goes when `id` is removed: the next exercise, else the previous one, else nowhere.
    static func neighbour(of id: UUID, in order: [UUID]) -> UUID? {
        guard let i = order.firstIndex(of: id) else { return nil }
        if i + 1 < order.count { return order[i + 1] }
        return i > 0 ? order[i - 1] : nil
    }

    /// The row to do on an exercise's page (L6): the set the user tapped if it is open and shown, else the first open
    /// warm-up while the group is expanded, else the first open working set. `nil`: no open row.
    static func activeSet(in ex: SessionAdvance.ExerciseState, tapped: UUID?, warmupsExpanded: Bool) -> UUID? {
        let shown = ex.sets.filter { !$0.isWarmup || warmupsExpanded }
        if let tapped, shown.contains(where: { $0.id == tapped && !$0.isCompleted }) { return tapped }
        if warmupsExpanded, let warmup = ex.sets.first(where: { $0.isWarmup && !$0.isCompleted }) { return warmup.id }
        return ex.sets.first { !$0.isWarmup && !$0.isCompleted }?.id
    }
}
