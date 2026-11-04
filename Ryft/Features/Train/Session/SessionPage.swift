import Foundation

/// Which exercise the Focused layout shows (architecture.md §1, ADR 0014). Pure, like `SessionAdvance`, whose states it
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
}
