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

        // Done = no open working set after this check, however the sets were ticked (a forgotten middle set too).
        // A superset collapses as one, once every member is done.
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

    /// Not a step towards finishing in order: a warm-up, or a working set checked while an earlier one is still open
    /// (set 4 with set 2 open). Checking the forgotten set 2 last is in order: it finishes the exercise.
    static func isOutOfOrder(_ setID: UUID, in ex: ExerciseState) -> Bool {
        let working = ex.sets.filter { !$0.isWarmup }
        guard let i = working.firstIndex(where: { $0.id == setID }) else { return true }
        return working[..<i].contains { !$0.isCompleted }
    }

    /// What comes next, the one definition behind the jump, the highlight, the rest bar's "Next:" and the lock
    /// screen: after `exerciseID` (the exercise just checked), a superset's partners first (A1 → B1 → A2), then the
    /// exercise itself, then the list below it, wrapping to the top. An exercise with no open working set offers
    /// nothing, not even an open warm-up; in one that is still open, its first open set (a warm-up if the user hasn't
    /// done those yet). Without a checked exercise: from the top.
    static func next(after exerciseID: UUID?, in exercises: [ExerciseState]) -> SetRef? {
        func open(_ ex: ExerciseState) -> SetRef? {
            guard !ex.isFinished, let set = ex.sets.first(where: { !$0.isCompleted }) else { return nil }
            return SetRef(exerciseID: ex.id, setID: set.id)
        }
        guard let exerciseID, let i = exercises.firstIndex(where: { $0.id == exerciseID }) else {
            return exercises.lazy.compactMap(open).first
        }
        let ex = exercises[i]
        var order: [ExerciseState] = []
        if let group = ex.supersetGroup {
            let partners = exercises.filter { $0.supersetGroup == group }
            if let j = partners.firstIndex(where: { $0.id == exerciseID }) {
                order += partners[(j + 1)...] + partners[..<j]
            }
        }
        order.append(ex)
        order += exercises[(i + 1)...] + exercises[..<i]
        return order.lazy.compactMap(open).first
    }

    /// Every working set is checked and at least one was (an empty session, or one with only open warm-ups left,
    /// isn't "all done" in the first case and is in the second).
    static func isAllDone(_ exercises: [ExerciseState]) -> Bool {
        exercises.allSatisfy(\.isFinished)
            && exercises.contains { ex in ex.sets.contains { !$0.isWarmup && $0.isCompleted } }
    }
}
