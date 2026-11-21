import SwiftUI

/// Edit targets (ui.md §3; PR 6 B §4.8): this workout's sets, rep range, target weight and rest for one exercise. Session only;
/// Done writes once, the close circle ("Cancel") or a drag down discards. Sets go from the end, and only empty, unchecked ones.
///
/// Nocturne: `SheetHeader("Edit targets")` with a compact "Done", then one grouped card titled with the exercise: a
/// `RyftStepperRow` each for Sets, Reps from, Reps to, the target weight (with "Clear target weight" under it while there is
/// one) and Rest, and the footer that says the changes stay in this workout. From XL it opens at full height (§12).
struct EditTargetsSheet: View {
    var controller: SessionController
    let exercise: LocalSessionExercise

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var targets: SessionTargets

    /// More rows than this aren't a workout any more.
    static let maxSets = 20

    init(controller: SessionController, exercise: LocalSessionExercise) {
        self.controller = controller
        self.exercise = exercise
        _targets = State(initialValue: controller.targets(of: exercise))
    }

    private var minSets: Int { controller.minSets(for: exercise) }
    private var showsWeight: Bool { exercise.loadType == .weight || exercise.loadType == .bodyweight }

    var body: some View {
        SheetFrame(Text("Edit targets", comment: "Title of the sheet that edits one exercise's targets in a workout."),
                          closeLabel: Text("Cancel")) {
            PillButton(Text("Done"), size: .compact) {
                if targets != controller.targets(of: exercise) { controller.setTargets(targets, for: exercise) }
                dismiss()
            }
            .accessibilityIdentifier("editTargets.done")
        } content: {
            GroupedCard(Text(verbatim: exercise.name),
                        footer: Text("Changes apply to this workout only. To change your plan, use Replace exercise or the plan editor.",
                                     comment: "Footer of the Edit targets sheet in a workout.")) {
                setsRow
                repsRows
                if showsWeight { weightRows }
                restRow
            }
        }
        .presentationDetents(SheetFrameSpec.detents(for: typeSize))
    }

    // MARK: rows

    private var setsRow: some View {
        let value = RyftStepperValue(text: "\(targets.sets)", canDecrement: targets.sets > minSets,
                                     canIncrement: targets.sets < Self.maxSets) { targets.sets += $0 }
        return RyftStepperRow(Text("Sets", comment: "Edit targets: number of sets."), detail: setsNote.map { Text(verbatim: $0) },
                              value: value)
            // The row reads its title and value; at the floor the reason is said with it ("2, minimum. 2 sets are done and
            // stay."), as `TargetStepper` did: `RyftStepperRow` doesn't read its detail line.
            .accessibilityValue(Text(verbatim: Self.spokenValue(value, floorNote: setsNote)))
    }

    /// The stepper's VoiceOver value, with the reason at the floor when there is one.
    static func spokenValue(_ value: RyftStepperValue, floorNote: String?) -> String {
        guard !value.canDecrement, let floorNote else { return value.accessibilityValue }
        return String(localized: "\(value.text), minimum. \(floorNote)",
                      comment: "VoiceOver value of a stepper at its lowest. 1: value, 2: why it can't go lower.")
    }

    /// Why "−" stops: done sets (always said), or a set with values (said at the floor).
    private var setsNote: String? {
        switch controller.setsFloor(for: exercise) {
        case .done(1):
            return String(localized: "1 set is done and stays.", comment: "Edit targets, under the sets stepper.")
        case .done(let n):
            return String(localized: "\(n)\u{00A0}sets are done and stay.",
                          comment: "Edit targets, under the sets stepper. 1: number of done sets.")
        case .values where targets.sets <= minSets:
            return String(localized: "Sets with values can't be removed here. Delete them in the list.",
                          comment: "Edit targets: the sets stepper can't go lower because a set has values.")
        default:
            return nil
        }
    }

    @ViewBuilder private var repsRows: some View {
        RyftStepperRow(Text("Reps from", comment: "Edit targets: the lower end of the rep range."),
                       value: RyftStepperValue(text: targets.repsMin.map(String.init) ?? Fmt.placeholder,
                                               canDecrement: (targets.repsMin ?? 2) > SessionTargets.reps.lowerBound,
                                               canIncrement: (targets.repsMin ?? 0) < SessionTargets.reps.upperBound) {
                           targets.stepRepsMin($0)
                       })
        RyftStepperRow(Text("Reps to", comment: "Edit targets: the upper end of the rep range."),
                       value: RyftStepperValue(text: targets.repsMax.map(String.init) ?? Fmt.placeholder,
                                               canDecrement: (targets.repsMax ?? 2) > SessionTargets.reps.lowerBound,
                                               canIncrement: (targets.repsMax ?? 0) < SessionTargets.reps.upperBound) {
                           targets.stepRepsMax($0)
                       })
    }

    /// The weight moves 2.5 kg a step; from nothing it starts at the suggestion (last time, or the plan's target).
    @ViewBuilder private var weightRows: some View {
        RyftStepperRow(exercise.loadType == .bodyweight
                           ? Text("Added weight (kg)", comment: "Edit targets: extra load on a bodyweight exercise.")
                           : Text("Target weight (kg)", comment: "Edit targets: the weight to lift."),
                       value: RyftStepperValue(text: targets.kg.map(Fmt.kgNumber) ?? Fmt.placeholder,
                                               canDecrement: (targets.kg ?? 1) > SessionTargets.kgRange.lowerBound,
                                               canIncrement: (targets.kg ?? 0) < SessionTargets.kgRange.upperBound) {
                           targets.stepKg(Double($0), from: controller.suggestedKg(for: exercise))
                       })
        if targets.kg != nil {
            // `RyftStepperRow` has no trailing slot for "Clear": it is the next row, a quiet action.
            GroupedRow.action(Text("Clear target weight", comment: "VoiceOver: removes the target weight."),
                              systemImage: "xmark.circle") {
                targets.kg = nil
            }
            .accessibilityIdentifier("editTargets.clearWeight")
        }
    }

    private var restRow: some View {
        RyftStepperRow(Text("Rest", comment: "Edit targets: rest between sets."),
                       value: RyftStepperValue(text: Fmt.clock(TimeInterval(targets.restSec)),
                                               spoken: RestSpeech.duration(targets.restSec),
                                               canDecrement: targets.restSec > SessionTargets.rest.lowerBound,
                                               canIncrement: targets.restSec < SessionTargets.rest.upperBound) {
                           targets.stepRest($0)
                       })
    }
}

// MARK: - previews (dark only)

/// Bench press of the List draft: one set done, so the sets stepper says why it stops at 1… and a target weight to clear.
#Preview("Edit targets") {
    let c = SessionSheetsPreview.listDraft()
    return Color.clear
        .sheet(isPresented: .constant(true)) { EditTargetsSheet(controller: c, exercise: c.exercises[0]).presentedRoot() }
        .previewEnvironment()
}

#Preview("Edit targets · AX3") {
    let c = SessionSheetsPreview.listDraft()
    return EditTargetsSheet(controller: c, exercise: c.exercises[0])
        .previewEnvironment()
        .dynamicTypeSize(.accessibility3)
}
