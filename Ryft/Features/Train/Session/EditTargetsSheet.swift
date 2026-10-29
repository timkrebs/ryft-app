import SwiftUI

/// Edit targets (ui.md §3): this workout's sets, rep range, target weight and rest for one exercise. Session only;
/// Done writes once, Cancel (or a drag down) discards. Sets go from the end, and only empty, unchecked ones.
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(exercise.name)
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    setsSection
                    repsSection
                    if showsWeight { weightSection }
                    restSection
                    Text("Changes apply to this workout only. To change your plan, use Replace exercise or the plan editor.",
                         comment: "Footer of the Edit targets sheet in a workout.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("Edit targets", comment: "Title of the sheet that edits one exercise's targets in a workout."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if targets != controller.targets(of: exercise) { controller.setTargets(targets, for: exercise) }
                        dismiss()
                    }
                    .accessibilityIdentifier("editTargets.done")
                }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }

    // MARK: sections

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TargetStepper(label: Text("Sets", comment: "Edit targets: number of sets."),
                          value: "\(targets.sets)",
                          canDecrement: targets.sets > minSets, canIncrement: targets.sets < Self.maxSets,
                          floorNote: setsNote) { targets.sets += $0 }
            if let setsNote {
                Text(setsNote)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Why "−" stops: done sets (always said), or a set with values (said at the floor).
    private var setsNote: String? {
        switch controller.setsFloor(for: exercise) {
        case .done(1):
            return String(localized: "1 set is done and stays.", comment: "Edit targets, under the sets stepper.")
        case .done(let n):
            return String(localized: "\(n) sets are done and stay.",
                          comment: "Edit targets, under the sets stepper. 1: number of done sets.")
        case .values where targets.sets <= minSets:
            return String(localized: "Sets with values can't be removed here. Delete them in the list.",
                          comment: "Edit targets: the sets stepper can't go lower because a set has values.")
        default:
            return nil
        }
    }

    private var repsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TargetStepper(label: Text("Reps from", comment: "Edit targets: the lower end of the rep range."),
                          value: targets.repsMin.map(String.init) ?? Fmt.placeholder,
                          canDecrement: (targets.repsMin ?? 2) > SessionTargets.reps.lowerBound,
                          canIncrement: (targets.repsMin ?? 0) < SessionTargets.reps.upperBound) {
                targets.stepRepsMin($0)
            }
            TargetStepper(label: Text("Reps to", comment: "Edit targets: the upper end of the rep range."),
                          value: targets.repsMax.map(String.init) ?? Fmt.placeholder,
                          canDecrement: (targets.repsMax ?? 2) > SessionTargets.reps.lowerBound,
                          canIncrement: (targets.repsMax ?? 0) < SessionTargets.reps.upperBound) {
                targets.stepRepsMax($0)
            }
        }
    }

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TargetStepper(label: exercise.loadType == .bodyweight
                              ? Text("Added weight (kg)", comment: "Edit targets: extra load on a bodyweight exercise.")
                              : Text("Target weight (kg)", comment: "Edit targets: the weight to lift."),
                          value: targets.kg.map(Fmt.kgNumber) ?? Fmt.placeholder,
                          canDecrement: (targets.kg ?? 1) > SessionTargets.kgRange.lowerBound,
                          canIncrement: (targets.kg ?? 0) < SessionTargets.kgRange.upperBound,
                          step: SessionTargets.kgStep) {
                targets.stepKg(Double($0), from: controller.suggestedKg(for: exercise))
            }
            if targets.kg != nil {
                Button {
                    targets.kg = nil
                } label: {
                    Text("Clear", comment: "Edit targets: remove the target weight.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear target weight", comment: "VoiceOver: removes the target weight."))
            }
        }
    }

    private var restSection: some View {
        TargetStepper(label: Text("Rest", comment: "Edit targets: rest between sets."),
                      value: Fmt.clock(TimeInterval(targets.restSec)),
                      canDecrement: targets.restSec > SessionTargets.rest.lowerBound,
                      canIncrement: targets.restSec < SessionTargets.rest.upperBound,
                      step: Double(SessionTargets.restStep)) {
            targets.stepRest($0)
        }
    }
}

/// Label, then "−" value "+" as 56 pt keys. VoiceOver: one adjustable element (swipe up or down).
private struct TargetStepper: View {
    let label: Text
    let value: String
    let canDecrement: Bool
    let canIncrement: Bool
    /// Shown on the keys when it isn't 1 ("−2.5").
    var step: Double = 1
    /// Read after the value at the floor ("2, minimum. 2 sets are done and stay.").
    var floorNote: String?
    let onStep: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            label
                .ryftLabelStyle()
            HStack(spacing: 12) {
                key(-1, enabled: canDecrement)
                Text(value)
                    .font(.ryftNumber(size: 34))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                key(1, enabled: canIncrement)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where canIncrement: onStep(1)
            case .decrement where canDecrement: onStep(-1)
            default: break
            }
        }
    }

    private var accessibilityValue: String {
        guard !canDecrement, let floorNote else { return value }
        return String(localized: "\(value), minimum. \(floorNote)",
                      comment: "VoiceOver value of a stepper at its lowest. 1: value, 2: why it can't go lower.")
    }

    private func key(_ direction: Int, enabled: Bool) -> some View {
        Button {
            onStep(direction)
        } label: {
            Group {
                if step == 1 {
                    Image(systemName: direction < 0 ? "minus" : "plus")
                        .font(.system(size: 20, weight: .semibold))
                } else {
                    Text(verbatim: (direction < 0 ? "\u{2212}" : "+") + Fmt.kgNumber(step))
                        .font(.ryftNumber(size: 17))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(enabled ? Theme.accent : Theme.textTertiary)
            .frame(width: 56, height: 56)
            .background(Theme.accent.opacity(enabled ? 0.14 : 0.05),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
    }
}

#Preview("Edit targets · dark") {
    let c = TrainPreview.liveController()
    return Color.clear
        .sheet(isPresented: .constant(true)) { EditTargetsSheet(controller: c, exercise: c.exercises[0]) }
        .preferredColorScheme(.dark)
}

#Preview("Edit targets · light") {
    let c = TrainPreview.liveController()
    return Color.clear
        .sheet(isPresented: .constant(true)) { EditTargetsSheet(controller: c, exercise: c.exercises[0]) }
        .preferredColorScheme(.light)
}

#Preview("Edit targets · AX3") {
    let c = TrainPreview.liveController()
    return EditTargetsSheet(controller: c, exercise: c.exercises[0])
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}
