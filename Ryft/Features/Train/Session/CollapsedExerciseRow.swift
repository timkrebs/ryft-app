import SwiftUI

/// A finished exercise, folded after its last set (ui.md §5): "✓ Incline bench press · 4 sets · best 80 × 6".
/// A tap opens the card again, and it stays open.
struct CollapsedExerciseRow: View {
    let exercise: LocalSessionExercise
    var onExpand: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let summary = Self.summary(for: exercise)
        Button(action: onExpand) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        name
                        detail(summary.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    name.lineLimit(2)
                    Spacer(minLength: 8)
                    detail(summary.text).fixedSize()
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary.spoken))
        .accessibilityHint(Text("Expands the sets", comment: "VoiceOver hint on a collapsed exercise in a workout."))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("collapsed.\(exercise.position)")
    }

    private var name: some View {
        Text(exercise.name)
            .font(.ryft(.headline))
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
    }

    /// What the row shows and what VoiceOver says.
    struct Summary: Equatable {
        let text: String
        let spoken: String
    }

    /// "4 sets · best 80 × 6". Best = the heaviest checked working set, ties by reps; bodyweight: the most reps;
    /// time and distance: the longest. No values: "4 sets".
    static func summary(for ex: LocalSessionExercise) -> Summary {
        let working = ex.orderedSets.filter { !$0.isWarmup }
        let done = working.filter(\.isCompleted)
        let count = done.isEmpty ? working.count : done.count
        let best = Self.best(of: done, loadType: ex.loadType)
        guard let best else {
            return Summary(text: String(localized: "\(count) sets"),
                           spoken: String(localized: "\(ex.name), completed. \(count) sets.",
                                          comment: "VoiceOver: a collapsed exercise without values, e.g. Plank, completed. 3 sets."))
        }
        return Summary(
            text: String(localized: "\(count) sets · best \(best.text)",
                         comment: "A collapsed exercise in a workout: sets done and the best set, e.g. 4 sets · best 80 × 6."),
            spoken: String(localized: "\(ex.name), completed. \(count) sets, best \(best.spoken).",
                           comment: "VoiceOver: a collapsed exercise, e.g. Bench press, completed. 4 sets, best 6 reps at 80 kilograms."))
    }

    private static func best(of sets: [LocalSet], loadType: LoadType) -> (text: String, spoken: String)? {
        if let top = sets.filter({ ($0.weightKg ?? 0) > 0 })
            .max(by: { ($0.weightKg ?? 0, $0.reps ?? 0) < ($1.weightKg ?? 0, $1.reps ?? 0) }),
            let kg = top.weightKg, loadType == .weight || loadType == .bodyweight {
            guard let reps = top.reps else { return (Fmt.kg(kg), String(localized: "\(Fmt.kgNumber(kg)) kilograms")) }
            return ("\(Fmt.kgNumber(kg)) × \(reps)", String(localized: "\(reps) reps at \(Fmt.kgNumber(kg)) kilograms"))
        }
        switch loadType {
        case .time:
            guard let sec = sets.compactMap(\.durationSec).max() else { break }
            let text = Fmt.duration(seconds: TimeInterval(sec))
            return (text, text)
        case .distance:
            guard let m = sets.compactMap(\.distanceM).max() else { break }
            let text = Fmt.distance(meters: m)
            return (text, text)
        case .weight, .bodyweight:
            break
        }
        guard let reps = sets.compactMap(\.reps).max() else { return nil }
        let text = String(localized: "\(reps) reps")
        return (text, text)
    }
}

/// The set the user does next (ui.md §5): a stronger tint than a checked row and a 2 pt accent bar on the leading
/// edge, so it isn't colour alone. No keypad, no focus change. VoiceOver hears "Next set." as the row's value.
/// One view structure whether current or not, so the row (and its accessibility element) keeps its identity as
/// the highlight moves.
struct CurrentSetHighlight: ViewModifier {
    let isCurrent: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.accent.opacity(isCurrent ? 0.10 : 0))
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 2)
                    .padding(.vertical, 10)
                    .offset(x: -7) // in the card's padding, beside the set number
                    .opacity(isCurrent ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .accessibilityValue(isCurrent
                ? Text("Next set.", comment: "VoiceOver: said with the set row the user does next in a workout.")
                : Text(verbatim: ""))
    }
}

extension View {
    func currentSetHighlight(_ isCurrent: Bool) -> some View {
        modifier(CurrentSetHighlight(isCurrent: isCurrent))
    }
}

// MARK: - previews

/// The mock session has two of four bench sets checked: the collapsed row summarises those, and the card shows
/// set 3 as the current set.
#Preview("Collapsed row · highlighted set", traits: .sizeThatFitsLayout) {
    let c = TrainPreview.liveController()
    return SchemePair {
        VStack(spacing: 12) {
            CollapsedExerciseRow(exercise: c.exercises[0], onExpand: {})
            ExerciseCard(controller: c, exercise: c.exercises[0], onPlates: {}, onHistory: {})
        }
    }
}

#Preview("Collapsed row · AX3", traits: .sizeThatFitsLayout) {
    let c = TrainPreview.liveController()
    return SchemePair {
        CollapsedExerciseRow(exercise: c.exercises[0], onExpand: {})
    }
    .dynamicTypeSize(.accessibility3)
}
