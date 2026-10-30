import Foundation

/// A jump the view performs once: scroll to `step`'s target (or the finish prompt). A new `id` per decision, so
/// the same target twice still scrolls.
struct AdvanceRequest: Identifiable, Equatable {
    let id: UUID
    let step: SessionAdvance.Step
}

/// Jump to the next exercise (design.md §7, lead decisions D-a to D-d): what's next, collapsed cards, the 0.6 s
/// delay on the injected clock, manual scrolls.
extension SessionController {
    // MARK: what's next (one definition)

    /// The planner's view of the list: exercises in order, sets in `setIndex` order.
    var advanceStates: [SessionAdvance.ExerciseState] { Self.states(of: exercises) }

    static func states(of exercises: [LocalSessionExercise]) -> [SessionAdvance.ExerciseState] {
        exercises.map { ex in
            SessionAdvance.ExerciseState(id: ex.id, supersetGroup: ex.supersetGroup, sets: ex.orderedSets.map {
                SessionAdvance.SetState(id: $0.id, isWarmup: $0.isWarmup, isCompleted: $0.isCompleted)
            })
        }
    }

    /// `SessionAdvance.next` mapped back to the models: behind `nextUp`, the highlight and the rest bar's "Next:".
    func nextOpenSet(after exerciseID: UUID?) -> (exercise: LocalSessionExercise, set: LocalSet)? {
        let list = exercises
        guard let ref = SessionAdvance.next(after: exerciseID, in: Self.states(of: list)),
              let ex = list.first(where: { $0.id == ref.exerciseID }),
              let set = ex.sets.first(where: { $0.id == ref.setID }) else { return nil }
        return (ex, set)
    }

    /// The set row the user does next: an open set the keypad is on, else `nextUp`. `nil` when nothing is open.
    var currentSetID: UUID? {
        if let focused = focusedSet, !focused.set.isCompleted { return focused.set.id }
        return nextUp?.set.id
    }

    /// No open working set and at least one checked (D-b): the list ends in "All sets done" with Finish. Passive, so
    /// it shows with the setting off too (D-d).
    var isAllDone: Bool { SessionAdvance.isAllDone(advanceStates) }

    // MARK: collapsed cards

    /// A finished card is shown collapsed. Derived, so a card that has an open working set again (an uncheck, a new
    /// set, an undo, a server copy) is never shown collapsed.
    func isCollapsed(_ ex: LocalSessionExercise) -> Bool {
        collapsed.contains(ex.id) && !Self.hasOpenWorkingSet(ex)
    }

    static func hasOpenWorkingSet(_ ex: LocalSessionExercise) -> Bool {
        ex.sets.contains { !$0.isWarmup && !$0.isCompleted }
    }

    /// After any edit: a card with an open working set again (a new set, an undo, new targets) leaves `collapsed` and
    /// the carried collapse for good, so finishing it later collapses it only with a jump, never at the tap.
    func pruneCollapsed() {
        let open = Set(exercises.filter(Self.hasOpenWorkingSet).map(\.id))
        guard !open.isEmpty else { return }
        if !collapsed.isDisjoint(with: open) { collapsed.subtract(open) }
        if carriedCollapse.contains(where: open.contains) { carriedCollapse.removeAll(where: open.contains) }
    }

    /// Tap on a collapsed row: open, and it stays open.
    func expand(_ ex: LocalSessionExercise) {
        collapsed.remove(ex.id)
        userExpanded.insert(ex.id)
    }

    // MARK: the delay

    /// The user dragged the list: no jump for the next 3 s.
    func userScrolled() {
        lastManualScroll = clock.now()
    }

    /// After a check: decide 0.6 s after the latest check, from the state then. Earlier checks inside the delay stay
    /// pending, so their collapse isn't lost.
    func scheduleAdvance(after set: LocalSet, in ex: LocalSessionExercise) {
        lastCheckedExercise = ex.id
        pendingChecks.removeAll { $0.exerciseID == ex.id }
        pendingChecks.append(SessionAdvance.SetRef(exerciseID: ex.id, setID: set.id))
        advanceTask?.cancel()
        advanceTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: SessionAdvance.delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.fireAdvance()
        }
    }

    /// After an uncheck: this exercise's pending work goes (others' stays), and a collapsed card opens again.
    func checkUndone(in ex: LocalSessionExercise) {
        collapsed.remove(ex.id)
        carriedCollapse.removeAll { $0 == ex.id }
        pendingChecks.removeAll { $0.exerciseID == ex.id }
        if pendingChecks.isEmpty {
            advanceTask?.cancel()
            advanceTask = nil
        }
    }

    /// The session stops (finish, discard, another session): nothing is published after it.
    func cancelAdvance() {
        advanceTask?.cancel()
        advanceTask = nil
        pendingChecks = []
        carriedCollapse = []
    }

    /// The planner's input from the live state.
    func advanceInput(checked: SessionAdvance.SetRef) -> SessionAdvance.Input {
        let states = advanceStates
        return SessionAdvance.Input(
            exercises: states, checked: checked, next: SessionAdvance.next(after: checked.exerciseID, in: states),
            keypadOpen: focus != nil, lastManualScroll: lastManualScroll, userExpanded: userExpanded,
            enabled: jumpToNext(), now: clock.now())
    }

    /// Every pending check collapses what it finished; the latest one decides where the list goes. When the latest
    /// stays, nothing collapses yet: a collapse without a scroll would move rows under the thumb, so it is carried to
    /// the next jump.
    private func fireAdvance() {
        advanceTask = nil
        let checks = pendingChecks
        pendingChecks = []
        var collapse = carriedCollapse
        var latest: SessionAdvance.Step = .stay
        for ref in checks {
            // The set may have been unchecked or deleted meanwhile.
            guard exercises.contains(where: { ex in ex.sets.contains { $0.id == ref.setID && $0.isCompleted } })
            else { continue }
            let step = SessionAdvance.step(advanceInput(checked: ref))
            if case let .advance(c, _) = step { collapse += c }
            if case let .allDone(c) = step { collapse += c }
            latest = step
        }
        // Only cards finished now: one carried from earlier may have an open set again.
        let finished = Set(exercises.filter { !Self.hasOpenWorkingSet($0) }.map(\.id))
        var seen = Set<UUID>()
        collapse = collapse.filter { finished.contains($0) && seen.insert($0).inserted }
        if latest == .stay {
            carriedCollapse = collapse
            return
        }
        carriedCollapse = []
        collapsed.formUnion(collapse)
        switch latest {
        case .stay:
            return
        case let .advance(_, to):
            advance = AdvanceRequest(id: UUID(), step: .advance(collapse: collapse, to: to))
        case .allDone:
            advance = AdvanceRequest(id: UUID(), step: .allDone(collapse: collapse))
        }
    }
}
