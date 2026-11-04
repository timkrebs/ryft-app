import Foundation

/// The Focused layout's page and warm-up groups (architecture.md §2 to §5, ADR 0013). A page change is no edit: it
/// never calls `sessionChanged`, so it reaches neither `updatedAt` nor the outbox, and the undo window keeps running.
extension SessionController {
    // MARK: the page

    /// The exercise on screen: the pager's and the strip's only source.
    var pageExerciseID: UUID? {
        SessionPage.resolve(stored: session.currentExerciseID, in: Self.states(of: exercises))
    }

    var pageExercise: LocalSessionExercise? {
        guard let id = pageExerciseID else { return nil }
        return exercises.first { $0.id == id }
    }

    /// The user moved: a swipe, a strip tap or adjust, the + tile. No jump for the next 3 s. An echo of the page that
    /// already shows returns here, so a programmatic move can't stamp the window.
    func jump(to id: UUID) {
        guard id != pageExerciseID, exercises.contains(where: { $0.id == id }) else { return }
        userScrolled()
        showPage(id)
    }

    /// The planner moved (`advance`): no stamp, or the next flip of a superset would stay. Only `to` counts, and a row
    /// that went since the decision is ignored.
    func follow(_ request: AdvanceRequest) {
        guard case let .advance(_, to) = request.step, exercises.contains(where: { $0.id == to.exerciseID }) else { return }
        showPage(to.exerciseID)
    }

    /// The screen appeared, or the resolved page changed: what `resolve` chose is stored, so a nil page can't move by
    /// itself as sets get checked. Not once the session has ended: the cover's last change arrives after Discard deleted
    /// the row, and after Finish it would move the stored page during the dismissal.
    func pinPage() {
        guard isUnderway else { return }
        showPage(pageExerciseID)
    }

    /// Every page change ends here. Invariant: an open keypad's set is on the current page. `commitBuffer` runs on
    /// every key, so closing the keypad has nothing to flush.
    func showPage(_ id: UUID?) {
        guard layout == .focused, id != session.currentExerciseID else { return }
        if let focused = focusedSet, focused.exercise.id != id { focus = nil }
        tappedSet = nil
        session.currentExerciseID = id
        store.save()
    }

    /// `ex` is about to go: its page moves first, while `focusedSet` still finds the row.
    func leavePage(of ex: LocalSessionExercise) {
        guard layout == .focused, ex.id == pageExerciseID else { return }
        showPage(SessionPage.neighbour(of: ex.id, in: exercises.map(\.id)))
    }

    // MARK: read-only rows

    /// Focused shows a stored time or distance and has no entry for it (L20), so the row has no reps field for the keypad.
    /// Always false in List.
    func isReadOnly(_ set: LocalSet) -> Bool {
        layout == .focused && SetStoredValue(reps: set.reps, durationSec: set.durationSec, distanceM: set.distanceM) != nil
    }

    // MARK: warm-up groups

    /// Focused hides this exercise's warm-ups: they leave the planner's input too (`plannerStates`). Always false in List.
    func isFolded(_ ex: LocalSessionExercise) -> Bool {
        layout == .focused && !expandedWarmups.contains(ex.id)
    }

    /// Folding changes no set and uploads nothing, but "Next:" can change. A tapped warm-up isn't active any more, and a
    /// keypad on a warm-up closes, or digits would go to a hidden row. Auto-fold comes through here too.
    func setWarmups(expanded: Bool, for ex: LocalSessionExercise) {
        if expanded {
            expandedWarmups.insert(ex.id)
        } else {
            expandedWarmups.remove(ex.id)
            if ex.sets.contains(where: { $0.id == tappedSet && $0.isWarmup }) { tappedSet = nil }
            if let focused = focusedSet, focused.exercise.id == ex.id, focused.set.isWarmup { focus = nil }
        }
        refreshActivity()
    }

    /// The group folds itself once its last warm-up is checked (L6). `expandedWarmups` is empty in List: nothing happens.
    func foldWarmupsIfDone(after set: LocalSet, in ex: LocalSessionExercise) {
        guard set.isWarmup, expandedWarmups.contains(ex.id),
              !ex.sets.contains(where: { $0.isWarmup && !$0.isCompleted }) else { return }
        setWarmups(expanded: false, for: ex)
    }

    /// The `…` menu and the open group: a new set at the end, as a warm-up, shown at once (`toggleWarmup`).
    func addWarmup(to ex: LocalSessionExercise) {
        toggleWarmup(addSet(to: ex))
    }

    // MARK: supersets

    /// The other exercises of `ex`'s superset, in order.
    func supersetPartners(of ex: LocalSessionExercise) -> [LocalSessionExercise] {
        guard let group = ex.supersetGroup else { return [] }
        return exercises.filter { $0.supersetGroup == group && $0.id != ex.id }
    }

    /// Consecutive exercises of one superset group together: the strip's bar, List's bracket.
    var exerciseGroups: [[LocalSessionExercise]] {
        var out: [[LocalSessionExercise]] = []
        for ex in exercises {
            if let g = ex.supersetGroup, let last = out.last?.last, last.supersetGroup == g {
                out[out.count - 1].append(ex)
            } else {
                out.append([ex])
            }
        }
        return out
    }
}
