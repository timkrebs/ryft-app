import SwiftUI

/// One set: number (tap: warm-up), kg, reps, RPE, check. 56 pt tall, large
/// monospaced numbers; empty fields show last time / the target ghosted.
struct SetRow: View {
    var controller: SessionController
    let set: LocalSet
    let exercise: LocalSessionExercise
    let number: Int
    let count: Int

    @State private var confirmDelete = false

    private var ghost: (reps: Int?, kg: Double?) { controller.ghost(for: set, in: exercise) }
    private var usesWeight: Bool { exercise.loadType == .weight || exercise.loadType == .bodyweight }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                controller.toggleWarmup(set)
            } label: {
                Text(set.isWarmup ? "W" : "\(number)")
                    .font(.ryftNumber(size: 17))
                    .foregroundStyle(set.isWarmup ? Theme.warning : Theme.textSecondary)
                    .frame(width: 40, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            if usesWeight {
                field(.kg, value: set.weightKg.map(Fmt.kgNumber), ghost: ghost.kg.map(Fmt.kgNumber))
            }
            field(.reps, value: set.reps.map(String.init), ghost: ghost.reps.map(String.init))
            field(.rpe, value: set.rpe.map(Fmt.kgNumber), ghost: nil)
                .frame(maxWidth: 64)

            Button {
                controller.toggleCheck(set, in: exercise)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(set.isCompleted ? Theme.onAccent : Theme.textTertiary)
                    .frame(width: 56, height: 56)
                    .background(set.isCompleted ? Theme.accent : Theme.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
        .background(set.isCompleted ? Theme.accent.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button(set.isWarmup ? "Mark as working set" : "Mark as warm-up", systemImage: "flame") {
                controller.toggleWarmup(set)
            }
            Button("Delete set", systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("Delete set \(number)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete set", role: .destructive) { controller.delete(set, from: exercise) }
        }
        // VoiceOver: one element per set with actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(set.isCompleted ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { controller.toggleCheck(set, in: exercise) }
        .accessibilityAction(named: Text(set.isCompleted ? "Mark not done" : "Check off")) {
            controller.toggleCheck(set, in: exercise)
        }
        .accessibilityAction(named: Text("Edit weight")) { controller.edit(set, .kg) }
        .accessibilityAction(named: Text("Edit reps")) { controller.edit(set, .reps) }
        .accessibilityAction(named: Text("Edit RPE")) { controller.edit(set, .rpe) }
        .accessibilityAction(named: Text(set.isWarmup ? "Mark as working set" : "Mark as warm-up")) {
            controller.toggleWarmup(set)
        }
        .accessibilityAction(named: Text("Delete set")) { confirmDelete = true }
        .accessibilityIdentifier("set.\(exercise.position).\(number)")
    }

    /// "Set 2 of 5, 8 reps at 80 kilograms, completed".
    private var accessibilityText: String {
        var parts = [String(localized: "Set \(number) of \(count)")]
        if set.isWarmup { parts.append(String(localized: "warm-up")) }
        let reps = set.reps ?? ghost.reps, kg = set.weightKg ?? ghost.kg
        switch (reps, kg) {
        case let (r?, k?): parts.append(String(localized: "\(r) reps at \(Fmt.kgNumber(k)) kilograms"))
        case let (r?, nil): parts.append(String(localized: "\(r) reps"))
        case let (nil, k?): parts.append(String(localized: "\(Fmt.kgNumber(k)) kilograms"))
        default: break
        }
        if let rpe = set.rpe { parts.append(String(localized: "RPE \(Fmt.kgNumber(rpe))")) }
        parts.append(set.isCompleted ? String(localized: "completed") : String(localized: "not done"))
        return parts.joined(separator: ", ")
    }

    private func field(_ f: SetFocus.Field, value: String?, ghost: String?) -> some View {
        let focused = controller.focus == SetFocus(setID: set.id, field: f)
        let shown = focused ? (controller.buffer.isEmpty ? nil : controller.displayBuffer) : value
        return Button {
            controller.edit(set, f)
        } label: {
            Text(shown ?? ghost ?? Fmt.placeholder)
                .font(.ryftNumber(size: 22))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(shown == nil ? Theme.textTertiary.opacity(0.7) : Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.surfaceRaised.opacity(focused ? 1 : 0.55),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// An exercise in the live session: name, target, last time, set rows, add set.
struct ExerciseCard: View {
    var controller: SessionController
    let exercise: LocalSessionExercise
    var onPlates: () -> Void
    var onHistory: () -> Void

    @State private var confirmRemove = false

    private var usesWeight: Bool { exercise.loadType == .weight || exercise.loadType == .bodyweight }

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                header
                columnTitles
                let sets = exercise.orderedSets
                ForEach(Array(sets.enumerated()), id: \.element.id) { i, set in
                    SetRow(controller: controller, set: set, exercise: exercise, number: i + 1, count: sets.count)
                        .id(set.id) // scroll anchor for the keypad
                }
                Button {
                    controller.addSet(to: exercise)
                } label: {
                    Label("Add set", systemImage: "plus")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog("Remove \(exercise.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove exercise", role: .destructive) { controller.remove(exercise) }
        } message: {
            Text("Its sets in this workout are deleted.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let target = exercise.targetText {
                    Text(target)
                        .font(.ryft(.callout))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel(Text("Target \(target)"))
                }
                if let last = lastTimeText {
                    Text("Last time: \(last)")
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 4)
            Menu {
                if usesWeight {
                    Button("Plate calculator", systemImage: "circle.grid.cross") { onPlates() }
                }
                Button("History", systemImage: "chart.xyaxis.line") { onHistory() }
                Menu("Rest \(Fmt.clock(TimeInterval(exercise.restSec)))") {
                    ForEach([60, 90, 120, 150, 180, 240, 300], id: \.self) { sec in
                        Button(Fmt.clock(TimeInterval(sec))) {
                            exercise.restSec = sec
                            controller.sync.sessionChanged(controller.session)
                        }
                    }
                }
                if exercise.supersetGroup != nil {
                    Button("Remove from superset", systemImage: "link.badge.plus") { controller.toggleSuperset(exercise) }
                } else if controller.canLinkBelow(exercise) {
                    Button("Superset with next", systemImage: "link") { controller.toggleSuperset(exercise) }
                }
                Button("Remove exercise", systemImage: "trash", role: .destructive) { confirmRemove = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Options for \(exercise.name)"))
        }
    }

    private var columnTitles: some View {
        HStack(spacing: 6) {
            Text("Set").frame(width: 40)
            if usesWeight { Text("kg").frame(maxWidth: .infinity) }
            Text("Reps").frame(maxWidth: .infinity)
            Text("RPE").frame(maxWidth: 64)
            Text("").frame(width: 56)
        }
        .ryftLabelStyle(Theme.textTertiary)
        .accessibilityHidden(true)
    }

    /// "97.5 × 5, 97.5 × 4"; past five sets "…, 80 × 5, +2 more", never a silent cut.
    private var lastTimeText: String? {
        let sets = exercise.lastTime.filter { !$0.isWarmup }
        guard !sets.isEmpty else { return nil }
        let shown = 5
        let list = sets.prefix(shown).map { s in
            switch (s.weightKg, s.reps) {
            // No-break spaces keep a set ("80 × 5") on one line when the list wraps.
            case let (kg?, r?): return "\(Fmt.kgNumber(kg))\u{00A0}×\u{00A0}\(r)"
            case let (nil, r?): return "\(r)"
            default: return Fmt.placeholder
            }
        }.joined(separator: ", ")
        let more = sets.count - shown
        guard more > 0 else { return list }
        return list + ", " + String(localized: "+\(more) more",
                                   comment: "Train session, an exercise's Last time line: sets not listed after the first five.")
    }
}

/// Exercises sharing a superset group, held together by a teal bracket.
struct SupersetBracket<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Superset", systemImage: "link")
                .ryftLabelStyle(Theme.accent)
                .padding(.leading, 18)
            HStack(spacing: 8) {
                BracketShape()
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 10)
                    .padding(.vertical, 18)
                    .accessibilityHidden(true)
                VStack(spacing: 10, content: content)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Superset"))
    }
}

/// `[` with rounded ends.
private struct BracketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

#Preview("Exercise card", traits: .sizeThatFitsLayout) {
    let c = TrainPreview.liveController()
    return SchemePair {
        VStack(spacing: 12) {
            ExerciseCard(controller: c, exercise: c.exercises[0], onPlates: {}, onHistory: {})
            SupersetBracket {
                ForEach(c.exercises.filter { $0.supersetGroup == 1 }) {
                    ExerciseCard(controller: c, exercise: $0, onPlates: {}, onHistory: {})
                }
            }
        }
    }
}
