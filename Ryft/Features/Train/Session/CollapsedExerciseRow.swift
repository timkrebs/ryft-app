import SwiftUI

/// A finished exercise, folded after its last set (ui.md §5; PR 6 B §4.7): "✓ Incline bench press · 4 sets · best 80 × 6".
/// A tap opens the card again, and it stays open. A `surface` row, radius 22 (the card's), with an outlined `checkmark.circle`
/// in grey: a done exercise is quiet, as a done set is, so no wall of filled checks builds up as the session goes on.
struct CollapsedExerciseRow: View {
    let exercise: LocalSessionExercise
    var onExpand: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The check: `checkmark.circle`, 20 pt, `textSecondary`.
    static let checkSymbol = "checkmark.circle", checkSize: CGFloat = 20
    static let checkInk = Theme.textSecondary
    /// The row's corners: the card's 22.
    static let radius = CardSpec.radius

    var body: some View {
        let summary = Self.summary(for: exercise)
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        Button(action: onExpand) {
            HStack(spacing: 10) {
                Image(systemName: Self.checkSymbol)
                    .font(.system(size: Self.checkSize, weight: .regular))
                    .foregroundStyle(Self.checkInk)
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
            .padding(ExerciseCard.padding)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Theme.surface, in: shape)
            .contentShape(shape)
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

/// The set the user does next in List (ui.md §5; PR 6 B §4.3, §4.7), drawn as Focused's active row (`FocusedRowHighlight`): ink
/// at 5 % under the row, radius 14, and a 2 pt Volt bar outside its leading edge, in the card's padding (10 pt from the row, 4 from
/// the card's edge), 8 shorter than the row at each end. The row's own dot and filled ✓ are `SetRow`'s. Not colour alone: the
/// tint, the bar, the raised fields and the filled ✓. No keypad, no focus change. VoiceOver hears "Next set." as the row's value;
/// the bar is hidden from it. One view structure whether current or not, so the row (and its accessibility element) keeps its
/// identity as the highlight moves. Inside the session the row can also take VoiceOver focus after a jump (`SessionVoiceOverFocus`).
struct CurrentSetHighlight: ViewModifier {
    let isCurrent: Bool
    let setID: UUID

    @Environment(\.sessionVoiceOverFocus) private var voiceOverFocus

    /// List's set row: 56 high at every size (its numerals are fixed), so the bar is 40.
    static let rowHeight: CGFloat = 56
    /// From the row's leading edge to the bar's: 10, as Focused's on its 16 pt page sides.
    static let barOutset = LiveSessionSpec.activeBarOutset(padding: LiveSessionSpec.sidePadding)

    func body(content: Content) -> some View {
        let highlighted = content
            .background {
                RoundedRectangle(cornerRadius: LiveSessionSpec.rowRadius, style: .continuous)
                    .fill(FocusedRowInk.activeRowFill(isCurrent))
            }
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(FocusedRowInk.mark)
                    .frame(width: LiveSessionSpec.activeBarWidth,
                           height: LiveSessionSpec.activeBarHeight(rowHeight: Self.rowHeight))
                    .offset(x: -Self.barOutset, y: LiveSessionSpec.activeBarInset)
                    .opacity(isCurrent ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .accessibilityValue(isCurrent
                ? Text("Next set.", comment: "VoiceOver: said with the set row the user does next in a workout.")
                : Text(verbatim: ""))
        // The environment is the same for every row of a screen, so this never switches a row's identity.
        if let voiceOverFocus {
            highlighted.accessibilityFocused(voiceOverFocus, equals: setID)
        } else {
            highlighted
        }
    }
}

/// The session screen's VoiceOver focus by set ID: after a jump, `SessionView` moves it to the target row.
private struct SessionVoiceOverFocusKey: EnvironmentKey {
    static let defaultValue: AccessibilityFocusState<UUID?>.Binding? = nil
}

extension EnvironmentValues {
    var sessionVoiceOverFocus: AccessibilityFocusState<UUID?>.Binding? {
        get { self[SessionVoiceOverFocusKey.self] }
        set { self[SessionVoiceOverFocusKey.self] = newValue }
    }
}

extension View {
    func currentSetHighlight(_ isCurrent: Bool, setID: UUID) -> some View {
        modifier(CurrentSetHighlight(isCurrent: isCurrent, setID: setID))
    }
}

// MARK: - previews (dark only)

/// The List draft with Bench press done: its folded row over Barbell row's card, whose set 1 is the current set.
#Preview("Collapsed row · highlighted set", traits: .sizeThatFitsLayout) {
    let c = SessionSheetsPreview.listFolded()
    return VStack(spacing: 14) {
        CollapsedExerciseRow(exercise: c.exercises[0], onExpand: {})
        ExerciseCard(controller: c, exercise: c.exercises[1], onPlates: {}, onHistory: {})
    }
    .padding(LiveSessionSpec.sidePadding)
    .frame(width: 390)
    .background(Theme.background)
    .previewEnvironment()
}

#Preview("Collapsed row · AX3", traits: .sizeThatFitsLayout) {
    let c = SessionSheetsPreview.listFolded()
    return CollapsedExerciseRow(exercise: c.exercises[0], onExpand: {})
        .padding(LiveSessionSpec.sidePadding)
        .frame(width: 390)
        .background(Theme.background)
        .previewEnvironment()
        .dynamicTypeSize(.accessibility3)
}
