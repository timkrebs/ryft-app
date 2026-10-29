import Foundation

/// A jump the view performs once: scroll to `step`'s target (or the finish prompt). A new `id` per decision, so
/// the same target twice still scrolls.
struct AdvanceRequest: Identifiable, Equatable {
    let id: UUID
    let step: SessionAdvance.Step
}

/// Jump to the next exercise (design.md §7): collapsed cards, the 0.6 s delay on the injected clock, manual scrolls.
extension SessionController {
    /// A finished card is shown collapsed. Derived, so a card that has an open working set again (an uncheck, a new
    /// set, an undo, a server copy) is never shown collapsed.
    func isCollapsed(_ ex: LocalSessionExercise) -> Bool {
        collapsed.contains(ex.id) && !ex.sets.contains { !$0.isWarmup && !$0.isCompleted }
    }

    /// The user dragged the list: no jump for the next 3 s.
    func userScrolled() {
        lastManualScroll = clock.now()
    }

    /// Tap on a collapsed row: open, and it stays open.
    func expand(_ ex: LocalSessionExercise) {
        collapsed.remove(ex.id)
        userExpanded.insert(ex.id)
    }

    /// The set row the user does next: an open set the keypad is on, else the next set after the last check.
    /// `nil` when nothing is open.
    var currentSetID: UUID? {
        if let focused = focusedSet, !focused.set.isCompleted { return focused.set.id }
        let after = lastCheckedExercise.flatMap { id in exercises.first { $0.id == id } }
        return nextUp(after: after)?.set.id
    }

    /// Every set is checked off: the list ends in "All sets done" with Finish.
    var isAllDone: Bool { !exercises.isEmpty && nextUp == nil }

    /// After a check: decide in 0.6 s, from the state then.
    func scheduleAdvance(after set: LocalSet, in ex: LocalSessionExercise) {
        advanceTask?.cancel()
        lastCheckedExercise = ex.id
        let checked = SessionAdvance.SetRef(exerciseID: ex.id, setID: set.id)
        advanceTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: SessionAdvance.delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.fireAdvance(checked)
        }
    }

    /// After an uncheck: no pending jump, and a collapsed card opens again.
    func checkUndone(in ex: LocalSessionExercise) {
        advanceTask?.cancel()
        advanceTask = nil
        collapsed.remove(ex.id)
    }

    /// The planner's input from the live state.
    func advanceInput(checked: SessionAdvance.SetRef) -> SessionAdvance.Input {
        let states = exercises.map { ex in
            SessionAdvance.ExerciseState(id: ex.id, supersetGroup: ex.supersetGroup, sets: ex.orderedSets.map {
                SessionAdvance.SetState(id: $0.id, isWarmup: $0.isWarmup, isCompleted: $0.isCompleted)
            })
        }
        let next = nextUp(after: exercises.first { $0.id == checked.exerciseID })
        return SessionAdvance.Input(
            exercises: states, checked: checked,
            next: next.map { SessionAdvance.SetRef(exerciseID: $0.exercise.id, setID: $0.set.id) },
            keypadOpen: focus != nil, lastManualScroll: lastManualScroll, userExpanded: userExpanded,
            enabled: jumpToNext(), now: clock.now())
    }

    private func fireAdvance(_ checked: SessionAdvance.SetRef) {
        advanceTask = nil
        // The set may have been unchecked or deleted meanwhile.
        guard exercises.contains(where: { ex in ex.sets.contains { $0.id == checked.setID && $0.isCompleted } })
        else { return }
        let step = SessionAdvance.step(advanceInput(checked: checked))
        switch step {
        case .stay:
            return
        case let .advance(collapse, _), let .allDone(collapse):
            collapsed.formUnion(collapse)
        }
        advance = AdvanceRequest(id: UUID(), step: step)
    }
}
