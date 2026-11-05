import Foundation

/// The Focused table's fourth column (design.md §7). Like a page change, this is no edit: it never calls `sessionChanged`,
/// so it reaches neither `updatedAt` nor the outbox.
extension SessionController {
    /// What `ex`'s fourth column shows. Always RPE in List. An RPE on the keypad shows its field, whatever was chosen:
    /// the context menu and VoiceOver reach RPE from any column, and the digits need somewhere to go.
    func column(for ex: LocalSessionExercise) -> SetColumn {
        guard layout == .focused else { return .rpe }
        if isEditingRPE(of: ex) { return .rpe }
        let sessionHasRPE = session.exercises.contains { $0.sets.contains { $0.rpe != nil } }
        return SetColumn.shown(chosen: settings.setColumn, loadType: ex.loadType, targetKind: ex.targetKind,
                               sessionHasRPE: sessionHasRPE)
    }

    /// Whether `ex`'s header is a button: time and distance have nothing to cycle through.
    func cyclesColumn(of ex: LocalSessionExercise) -> Bool {
        layout == .focused && SetColumn.offersEstimates(for: ex.loadType)
    }

    /// The header's tap: on from what shows, for every exercise and the sessions after this one. An RPE on the keypad
    /// closes: its field is what the column is leaving, and `commitBuffer` has stored every key.
    func cycleColumn(of ex: LocalSessionExercise) {
        guard cyclesColumn(of: ex) else { return }
        let next = column(for: ex).next
        if isEditingRPE(of: ex) { focus = nil }
        settings.setColumn = next
    }

    /// The cell for `set`.
    func columnText(of set: LocalSet, in ex: LocalSessionExercise) -> String {
        let values = estimatedValues(of: set, in: ex)
        return column(for: ex).text(weightKg: values.kg, reps: values.reps, rpe: set.rpe)
    }

    /// Whether `set`'s row has an RPE line, at the sizes without a fourth column (design.md §5.1): when it holds an RPE or the
    /// keypad is on it, and on the active row of an exercise whose column would be RPE, as the way in. The other rows stay
    /// one line: a table of empty lines would push the sets apart at the sizes with the least room.
    func showsRPELine(of set: LocalSet, in ex: LocalSessionExercise, columns: SetTableColumns) -> Bool {
        guard !columns.hasFourth else { return false }
        if set.rpe != nil || focus == SetFocus(setID: set.id, field: .rpe) { return true }
        return !set.isCompleted && activeSet(in: ex)?.id == set.id && column(for: ex) == .rpe
    }

    /// What VoiceOver adds for an estimate. The row says its RPE in any column, so nothing here for that one.
    func columnSpoken(of set: LocalSet, in ex: LocalSessionExercise) -> String? {
        let shown = column(for: ex)
        guard shown != .rpe else { return nil }
        let values = estimatedValues(of: set, in: ex)
        return shown.spoken(weightKg: values.kg, reps: values.reps, rpe: set.rpe)
    }

    /// The numbers an estimate reads, the ones the row shows: what a done set logged, and for an open set what is typed,
    /// else the ghost. A stored time or distance stands in the reps slot, so that row has no reps to read.
    private func estimatedValues(of set: LocalSet, in ex: LocalSessionExercise) -> (reps: Int?, kg: Double?) {
        guard !set.isCompleted else { return (set.reps, set.weightKg) }
        let g = ghost(for: set, in: ex)
        let stored = SetStoredValue(reps: set.reps, durationSec: set.durationSec, distanceM: set.distanceM)
        return (SetRow.spokenReps(set.reps, ghost: g.reps, stored: stored), set.weightKg ?? g.kg)
    }

    private func isEditingRPE(of ex: LocalSessionExercise) -> Bool {
        guard let focus, focus.field == .rpe else { return false }
        return ex.sets.contains { $0.id == focus.setID }
    }
}
