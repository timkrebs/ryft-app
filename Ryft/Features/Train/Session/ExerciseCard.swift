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
    /// How far the row is swiped open (0 or less); "Delete" shows in the space it leaves.
    @State private var swipe: CGFloat = 0
    @State private var swipeAxis: Axis?
    @State private var swipeStart: CGFloat = 0
    /// When a sideways drag last ended: the tap a button sees at its end isn't one.
    @State private var swipeEndedAt: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let revealWidth: CGFloat = 88

    private var ghost: (reps: Int?, kg: Double?) { controller.ghost(for: set, in: exercise) }
    private var usesWeight: Bool { exercise.loadType == .weight || exercise.loadType == .bodyweight }

    var body: some View {
        row
            .offset(x: swipe)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if swipe < 0 { deleteButton.frame(width: -swipe) }
            }
            .clipped()
            // Unchecked rows only; a vertical drag stays the list's scroll.
            .simultaneousGesture(swipeGesture, including: set.isCompleted ? .subviews : .all)
            .onChange(of: set.isCompleted) { _, done in if done { swipe = 0 } }
            .contextMenu {
                Button(set.isWarmup ? "Mark as working set" : "Mark as warm-up", systemImage: "flame") {
                    controller.toggleWarmup(set)
                }
                Button("Delete set", systemImage: "trash", role: .destructive) { requestDelete() }
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
            .accessibilityAction(named: Text("Delete set")) { requestDelete() }
            .accessibilityIdentifier("set.\(exercise.position).\(number)")
    }

    private var row: some View {
        HStack(spacing: 6) {
            Button {
                tap { controller.toggleWarmup(set) }
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
                tap { controller.toggleCheck(set, in: exercise) }
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
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            requestDelete()
        } label: {
            Label("Delete", systemImage: "trash")
                .labelStyle(.iconOnly)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.alert, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.leading, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("set.delete")
    }

    /// Starts only once the drag is clearly sideways (1.5 : 1), so the list's vertical scroll wins otherwise.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let dx = value.translation.width, dy = value.translation.height
                if swipeAxis == nil {
                    swipeAxis = abs(dx) > abs(dy) * 1.5 ? .horizontal : .vertical
                    swipeStart = swipe
                }
                guard swipeAxis == .horizontal else { return }
                swipe = min(0, max(-Self.revealWidth * 1.3, swipeStart + dx))
            }
            .onEnded { _ in
                defer { swipeAxis = nil }
                if swipeAxis == .horizontal { swipeEndedAt = .now }
                guard swipeAxis == .horizontal else { return }
                withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                    swipe = swipe < -Self.revealWidth / 2 ? -Self.revealWidth : 0
                }
            }
    }

    /// A row button's action, unless the touch was a swipe; on an open row a tap only closes it.
    private func tap(_ action: () -> Void) {
        guard swipeAxis != .horizontal, Date.now.timeIntervalSince(swipeEndedAt) > 0.35 else { return }
        if swipe < 0 {
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) { swipe = 0 }
            return
        }
        action()
    }

    /// A set with values (or checked) asks first; an empty one goes at once.
    private func requestDelete() {
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) { swipe = 0 }
        if set.hasValues || set.isCompleted {
            confirmDelete = true
        } else {
            controller.delete(set, from: exercise)
        }
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
            tap { controller.edit(set, f) }
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
    @State private var showsReplace = false
    @State private var showsTargets = false
    @State private var showsNotes = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

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
        .sheet(isPresented: $showsReplace) {
            AddExerciseSheet(replacing: replaceContext) { picked, alsoChangePlan in
                let ex = exercise, window = voiceOver ? SessionController.undoWindowVoiceOver : SessionController.undoWindow
                Task { await controller.replace(ex, with: picked, alsoChangePlan: alsoChangePlan, window: window) }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showsTargets) {
            EditTargetsSheet(controller: controller, exercise: exercise)
        }
        .sheet(isPresented: $showsNotes) {
            ExerciseNotesSheet(controller: controller, exercise: exercise)
        }
    }

    private var replaceContext: ReplaceContext {
        ReplaceContext(name: exercise.name, exerciseID: exercise.exerciseId, kind: controller.replaceKind(for: exercise),
                       plan: controller.planChangeOption(for: exercise), offline: !controller.sync.isOnline)
    }

    /// The `…` menu and the header's context menu, in one order (ui.md §1): Replace · Edit targets · Notes ·
    /// Plate calculator (barbell) · History · Rest ▸ · Superset ─ Remove.
    @ViewBuilder
    private var menuItems: some View {
        Section {
            Button {
                controller.beginReplace()
                showsReplace = true
            } label: {
                Label(String(localized: "Replace exercise…", comment: "Exercise menu in a workout: pick another exercise for this one."),
                      systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!controller.canReplace(exercise))
            .accessibilityIdentifier("session.replace")
            Button {
                controller.focus = nil
                showsTargets = true
            } label: {
                Label(String(localized: "Edit targets…", comment: "Exercise menu in a workout: sets, reps, weight and rest for this workout."),
                      systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("session.editTargets")
            Button {
                controller.focus = nil
                showsNotes = true
            } label: {
                Label(String(localized: "Notes", comment: "Exercise menu in a workout: this exercise's notes."),
                      systemImage: "note.text")
            }
            if exercise.kind == .barbell {
                Button("Plate calculator", systemImage: "circle.grid.cross") { onPlates() }
            }
            Button("History", systemImage: "chart.xyaxis.line") { onHistory() }
            Menu {
                ForEach([60, 90, 120, 150, 180, 240, 300], id: \.self) { sec in
                    Button(Fmt.clock(TimeInterval(sec))) { controller.setRest(sec, for: exercise) }
                }
            } label: {
                Label("Rest \(Fmt.clock(TimeInterval(exercise.restSec)))", systemImage: "timer")
            }
            if exercise.supersetGroup != nil {
                Button("Remove from superset", systemImage: "link.badge.plus") { controller.toggleSuperset(exercise) }
            } else if controller.canLinkBelow(exercise) {
                Button("Superset with next", systemImage: "link") { controller.toggleSuperset(exercise) }
            }
        }
        Section {
            Button("Remove exercise", systemImage: "trash", role: .destructive) { confirmRemove = true }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    // The toast's Undo, reachable from the card too while it lasts (ui.md §4).
                    .accessibilityActions {
                        if let undo = controller.undo, undo.touches(exercise.id) {
                            Button(String(localized: "Undo", comment: "Toast button that takes back the last change, e.g. a replaced exercise.")) {
                                SessionToastOverlay.undo(undo, in: controller)
                            }
                        }
                    }
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
                if !exercise.notes.isEmpty {
                    Button {
                        controller.focus = nil
                        showsNotes = true
                    } label: {
                        Label(exercise.notes, systemImage: "note.text")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 28, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Notes: \(exercise.notes)", comment: "VoiceOver: an exercise's notes in a workout. 1: the notes."))
                    .accessibilityHint(Text("Edits the notes", comment: "VoiceOver hint on an exercise's notes in a workout."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu { menuItems }
            Spacer(minLength: 4)
            Menu {
                menuItems
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

    /// "97.5 × 5, 97.5 × 4".
    private var lastTimeText: String? {
        let sets = exercise.lastTime.filter { !$0.isWarmup }
        guard !sets.isEmpty else { return nil }
        return sets.prefix(5).map { s in
            switch (s.weightKg, s.reps) {
            case let (kg?, r?): return "\(Fmt.kgNumber(kg)) × \(r)"
            case let (nil, r?): return "\(r)"
            default: return Fmt.placeholder
            }
        }.joined(separator: ", ")
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
