import SwiftUI

/// An exercise in the live session's List layout (PR 6 B §4.7, `b-02`): the name, the target in grey, last time, the notes, the
/// `…` menu, the column titles, the set rows in Focused's three looks (the controller's current set is the active one, marked by
/// `CurrentSetHighlight`), and "Add set" as a quiet link. `Card` at radius 22 with 14 inside.
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
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl

    private var usesWeight: Bool { exercise.loadType == .weight || exercise.loadType == .bodyweight }

    var body: some View {
        Card(padding: Self.padding) {
            VStack(alignment: .leading, spacing: 10) {
                header
                columnTitles
                let sets = exercise.orderedSets
                let current = controller.currentSetID
                ForEach(Array(sets.enumerated()), id: \.element.id) { i, set in
                    SetRow(controller: controller, set: set, exercise: exercise, number: i + 1, count: sets.count)
                        .id(set.id) // scroll anchor for the keypad
                        .currentSetHighlight(current == set.id, setID: set.id)
                }
                Button {
                    controller.addSet(to: exercise)
                } label: {
                    Label("Add set", systemImage: "plus")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary.opacity(ExercisePage.quietLink))
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
            AddExerciseSheet(replacing: controller.replaceContext(for: exercise)) { picked, alsoChangePlan in
                let ex = exercise, window = SessionController.undoWindow(voiceOver: voiceOver, switchControl: switchControl)
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

    /// Inside the card: 14 (the rows keep their 330 pt at 390; the active row's bar sits in this padding).
    static let padding: CGFloat = 14

    private var menuItems: some View {
        ExerciseMenuItems(controller: controller, exercise: exercise,
                          onReplace: { showsReplace = true }, onTargets: { showsTargets = true }, onNotes: { showsNotes = true },
                          onPlates: onPlates, onHistory: onHistory, onRemove: { confirmRemove = true })
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
                        .foregroundStyle(Theme.textSecondary)
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

    /// The column titles' widths: the list row's own (`SetRow` without Focused's `columns`), so each title sits over its
    /// column. kg and Reps share what's left. Named so a hosted test can hold each title against its column.
    enum TitleColumns {
        static let number: CGFloat = 40
        static let fourthMax: CGFloat = 64
        static let check: CGFloat = 56
        static let gap: CGFloat = 6
    }

    private var columnTitles: some View {
        HStack(spacing: TitleColumns.gap) {
            Text("Set").frame(width: TitleColumns.number)
            if usesWeight { Text("kg").frame(maxWidth: .infinity) }
            Text("Reps").frame(maxWidth: .infinity)
            Text("RPE").frame(maxWidth: TitleColumns.fourthMax)
            Text("").frame(width: TitleColumns.check)
        }
        .ryftLabelStyle(Theme.textTertiary)
        // As Focused's `SetTableHeader`: the titles share the rows' columns, whose numbers have a fixed size, so they stop
        // growing at XXXL and keep one line. At AX3 on a 402 pt iPhone "Set" broke inside the word ("Se/t"). VoiceOver
        // reads each row as one element with its values named, so the titles are hidden from it.
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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

/// Exercises sharing a superset group, held together by a bracket (PR 6 B §4.7): a 3 pt stroke of ink at 55 % (the strip's
/// superset bar), and "Superset" with `link` over it, 13 pt `textSecondary`. Grey, not a colour: the bracket and the word say it.
struct SupersetBracket<Content: View>: View {
    @ViewBuilder var content: () -> Content

    /// The bracket's stroke.
    static var lineWidth: CGFloat { 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Superset", systemImage: "link")
                .ryftLabelStyle(Theme.textSecondary)
                .padding(.leading, 18)
            HStack(spacing: 8) {
                BracketShape()
                    .stroke(ExerciseStrip.supersetInk,
                            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round))
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

// MARK: - previews (dark only)

/// `b-02`'s card: Bench press, set 1 done, set 2 the current set (the Volt bar and dot, the filled ✓), sets 3 and 4 upcoming.
#Preview("Exercise card", traits: .sizeThatFitsLayout) {
    let c = SessionSheetsPreview.listDraft()
    return ExerciseCard(controller: c, exercise: c.exercises[0], onPlates: {}, onHistory: {})
        .padding(LiveSessionSpec.sidePadding)
        .frame(width: 390)
        .background(Theme.background)
        .previewEnvironment()
}

/// The superset's two cards in their bracket.
#Preview("Exercise card · superset", traits: .sizeThatFitsLayout) {
    let c = TrainPreview.liveController()
    return SupersetBracket {
        ForEach(c.exercises.filter { $0.supersetGroup == 1 }) {
            ExerciseCard(controller: c, exercise: $0, onPlates: {}, onHistory: {})
        }
    }
    .padding(LiveSessionSpec.sidePadding)
    .frame(width: 390)
    .background(Theme.background)
    .previewEnvironment()
}

/// `b-03`: the column titles stay on one line, in the rows' columns.
#Preview("Exercise card · AX3", traits: .sizeThatFitsLayout) {
    let c = SessionSheetsPreview.listDraft()
    return ExerciseCard(controller: c, exercise: c.exercises[0], onPlates: {}, onHistory: {})
        .padding(LiveSessionSpec.sidePadding)
        .frame(width: 390)
        .background(Theme.background)
        .previewEnvironment()
        .dynamicTypeSize(.accessibility3)
}
