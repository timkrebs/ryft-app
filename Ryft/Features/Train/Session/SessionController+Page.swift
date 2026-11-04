import Foundation

/// A warm-up group folded itself (L6): the view moves VoiceOver off the row that went. A fold from the pill isn't one, the
/// pill stays. A new `id` per fold.
struct AutoFold: Equatable {
    let id = UUID()
    let exerciseID: UUID
}

/// The Focused layout's page and warm-up groups (architecture.md §2 to §5, ADR 0013). A page change is no edit: it
/// never calls `sessionChanged`, so it reaches neither `updatedAt` nor the outbox, and the undo window keeps running.
extension SessionController {
    // MARK: the page

    /// The exercise on screen: the pager's and the strip's only source. Read on every update, so a stored page that still
    /// exists, the usual case, builds no planner states.
    var pageExerciseID: UUID? {
        if let stored = session.currentExerciseID, exercises.contains(where: { $0.id == stored }) { return stored }
        return SessionPage.resolve(stored: nil, in: Self.states(of: exercises))
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

    // MARK: the active set

    /// `ex`'s active row: one per page, derived, so a page beside the current one renders right during a swipe, and a
    /// deleted set or one a server copy completed leaves it on its own (architecture.md §3).
    func activeSet(in ex: LocalSessionExercise) -> LocalSet? {
        guard let state = Self.states(of: [ex]).first,
              let id = SessionPage.activeSet(in: state, tapped: tappedSet, warmupsExpanded: !isFolded(ex)) else { return nil }
        return ex.sets.first { $0.id == id }
    }

    /// A tap on an upcoming row: it becomes the active one. No set changes and nothing is saved.
    func activate(_ set: LocalSet) {
        guard layout == .focused, !set.isCompleted else { return }
        tappedSet = set.id
    }

    /// ✓ on the active row (L17). A set that would log neither reps nor load opens the keypad on the first missing field
    /// instead; the rest is `toggleCheck`. VoiceOver's check on that row comes here too (L23).
    func checkActive(_ set: LocalSet, in ex: LocalSessionExercise) {
        if let field = missingField(of: set, in: ex) {
            edit(set, field)
        } else {
            toggleCheck(set, in: ex)
        }
    }

    /// Read against what `toggleCheck` fills. Reps for bodyweight: its added load is optional. Time and distance have no
    /// field to open (L20), and a stored value is a logged one.
    private func missingField(of set: LocalSet, in ex: LocalSessionExercise) -> SetFocus.Field? {
        guard layout == .focused, !set.isCompleted, !isReadOnly(set) else { return nil }
        let g = ghost(for: set, in: ex)
        guard set.reps == nil, g.reps == nil, set.weightKg == nil else { return nil }
        switch ex.loadType {
        case .weight: return g.kg == nil ? .kg : nil
        case .bodyweight: return .reps
        case .time, .distance: return nil
        }
    }

    // MARK: the table

    /// Focused's rows top to bottom: an open group's warm-ups, then the working sets. Not `setIndex` order: `addWarmup` gives
    /// a warm-up the highest index and the group sits above the table.
    func tableRows(of ex: LocalSessionExercise) -> [LocalSet] {
        let sets = ex.orderedSets
        let working = sets.filter { !$0.isWarmup }
        return isFolded(ex) ? working : sets.filter(\.isWarmup) + working
    }

    /// Where the keypad's Next goes. In Focused: down the table, past what it can't edit (a read-only row has no reps to go
    /// to). A folded warm-up isn't in the table, so it can't get the keypad.
    func nextRow(after set: LocalSet, in ex: LocalSessionExercise) -> LocalSet? {
        guard layout == .focused else { return ex.orderedSets.first { $0.setIndex > set.setIndex } }
        let rows = tableRows(of: ex)
        guard let i = rows.firstIndex(where: { $0.id == set.id }) else { return nil }
        return rows[(i + 1)...].first { !isReadOnly($0) }
    }

    /// A set's number as the user reads it: Focused numbers warm-ups and working sets apart, as its table does. List
    /// counts every set.
    func position(of set: LocalSet, in ex: LocalSessionExercise) -> (number: Int, count: Int, isWarmup: Bool) {
        let sets = ex.orderedSets
        let peers = layout == .focused ? sets.filter { $0.isWarmup == set.isWarmup } : sets
        return ((peers.firstIndex { $0.id == set.id } ?? 0) + 1, peers.count, layout == .focused && set.isWarmup)
    }

    /// What VoiceOver hears when the page moves on its own: "Bench press, set 1 of 4". `nil` with no open row.
    func pageAnnouncement(of ex: LocalSessionExercise) -> String? {
        guard let set = activeSet(in: ex) else { return nil }
        let at = position(of: set, in: ex)
        return at.isWarmup
            ? String(localized: "\(ex.name), warm-up \(at.number) of \(at.count)",
                     comment: "VoiceOver: the page moved to the next exercise, on a warm-up, e.g. Bench press, warm-up 1 of 2.")
            : String(localized: "\(ex.name), set \(at.number) of \(at.count)",
                     comment: "VoiceOver: the page moved to the next exercise, e.g. Bench press, set 1 of 4.")
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
        autoFold = AutoFold(exerciseID: ex.id)
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
