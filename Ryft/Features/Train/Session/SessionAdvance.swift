import Foundation

/// "Jump to next exercise" (design.md §7): what happens 0.6 s after a set is checked. Pure: the controller builds
/// the input from the live state when the delay has run out, so a scroll, an uncheck or an open keypad inside the
/// delay still counts.
enum SessionAdvance {
    struct SetState: Equatable {
        let id: UUID
        let isWarmup: Bool
        let isCompleted: Bool
    }

    /// Sets in `setIndex` order.
    struct ExerciseState: Equatable {
        let id: UUID
        let supersetGroup: Int?
        let sets: [SetState]

        /// No open working set left (an open warm-up doesn't keep an exercise open).
        var isFinished: Bool { !sets.contains { !$0.isWarmup && !$0.isCompleted } }
    }

    struct SetRef: Equatable {
        let exerciseID: UUID
        let setID: UUID
    }

    struct Input {
        var exercises: [ExerciseState]
        /// The set whose check started the delay.
        var checked: SetRef
        /// `SessionController.nextUp(after:)` for the checked exercise: the one owner of the order.
        var next: SetRef?
        var keypadOpen: Bool
        var lastManualScroll: Date?
        /// Cards the user opened again: never collapsed on their own.
        var userExpanded: Set<UUID>
        /// Profile → Training → Jump to next exercise.
        var enabled: Bool
        var now: Date
    }

    enum Step: Equatable {
        /// Nothing moves.
        case stay
        /// Collapse these cards, scroll `to` under the rest bar and highlight it.
        case advance(collapse: [UUID], to: SetRef)
        /// No open set left: collapse these and scroll to the finish prompt.
        case allDone(collapse: [UUID])
    }

    /// Lets the check animation and haptic land first.
    static let delay: Duration = .milliseconds(600)
    /// A drag this recent wins over the jump.
    static let manualScrollWindow: TimeInterval = 3

    static func step(_ input: Input) -> Step {
        guard input.enabled, !input.keypadOpen else { return .stay }
        if let scrolled = input.lastManualScroll, input.now.timeIntervalSince(scrolled) < manualScrollWindow {
            return .stay
        }
        guard let ex = input.exercises.first(where: { $0.id == input.checked.exerciseID }),
              !isOutOfOrder(input.checked.setID, in: ex) else { return .stay }

        // A superset collapses as one, once every member is finished.
        let members = ex.supersetGroup.map { group in input.exercises.filter { $0.supersetGroup == group } } ?? [ex]
        let finished = members.allSatisfy(\.isFinished)
        let collapse = finished
            ? members.map(\.id).filter { !input.userExpanded.contains($0) && $0 != input.next?.exerciseID }
            : []

        guard let next = input.next else { return finished ? .allDone(collapse: collapse) : .stay }
        // A1 → B1 → A2: the partner's next set, whether or not this one is finished.
        let toPartner = ex.supersetGroup != nil && next.exerciseID != ex.id
            && members.contains { $0.id == next.exerciseID }
        guard toPartner || finished else { return .stay }
        return .advance(collapse: collapse, to: next)
    }

    /// Checking set 4 while set 2 is open, or set 1 after set 3 is done, isn't finishing in order (working sets only).
    static func isOutOfOrder(_ setID: UUID, in ex: ExerciseState) -> Bool {
        let working = ex.sets.filter { !$0.isWarmup }
        guard let i = working.firstIndex(where: { $0.id == setID }) else {
            // A warm-up: out of order once a working set is done.
            return working.contains(where: \.isCompleted)
        }
        let openBefore = working[..<i].contains { !$0.isCompleted }
        let doneAfter = working[(i + 1)...].contains(where: \.isCompleted)
        return openBefore || doneAfter
    }
}
