import SwiftUI

/// The builder's numbers (PR 6 B §6.3, `b-12`).
enum PlanBuilderLayout {
    /// The sheet header → the name.
    nonisolated static let headerGap: CGFloat = 16
    /// Between the blocks (the name, Plan, the description, each day, Add day): the grouped list's 18.
    nonisolated static let sectionSpacing = GroupedListSpec.groupSpacing
    /// A day: its name row → its first exercise, and the exercise cards apart.
    nonisolated static let dayTitleGap: CGFloat = 8, exerciseSpacing: CGFloat = 12
    /// A validation line under its row: the row's 16 at the sides, 10 under it.
    nonisolated static let issueBottom: CGFloat = 10
    /// The target's value field, wide enough for "102.5".
    nonisolated static let targetFieldWidth: CGFloat = 72
    nonisolated static let bottomPadding: CGFloat = 32
}

/// What the builder decides without a view (PR 6 B §6.3): which issues show, when Save is on, the rest choices.
enum PlanBuilderRules {
    /// Nothing is wrong on a fresh form; from the first change (or a Save) each issue shows under its field, so the disabled
    /// Save is explained.
    static func shownIssues(_ issues: [PlanIssue], attempted: Bool, hasChanges: Bool) -> [PlanIssue] {
        attempted || hasChanges ? issues : []
    }

    /// Save is on once the plan is valid (a name, an exercise on every day). While it saves it is busy, not off.
    static func canSave(issues: [PlanIssue]) -> Bool {
        issues.isEmpty
    }

    /// The issues no field carries (no day at all, a superset of one, sets or rest out of range from an older plan): each
    /// a line above Add day, so a Save that is off always says why. One line per sentence.
    static func formIssues(_ shown: [PlanIssue]) -> [PlanIssue] {
        var seen = Set<String>()
        return shown.filter { issue in
            switch issue {
            case .noDays, .lonelySuperset, .sets, .rest: return seen.insert(issue.message).inserted
            default: return false
            }
        }
    }

    /// The rests the old stepper reached that the session's presets leave out: none, 30 s, 45 s, and 6 to 15 minutes.
    static let extraRests = [0, 30, 45, 360, 480, 600, 900]

    /// The Rest menu's choices: the session's presets, `extraRests`, and the exercise's own, in order.
    @MainActor
    static func restChoices(current: Int) -> [Int] {
        Array(Set(RestChoices.presets + extraRests + [current])).sorted()
    }
}

/// Create or edit a plan: name, goal, days per week, weeks or repeating,
/// progression; per day the exercises with sets, rep range, target, rest and
/// supersets. Validation (PlanValidation) runs live; Save sends the whole plan.
struct PlanBuilderView: View {
    let plan: Plan
    @Environment(TrainLibrary.self) private var library

    var body: some View {
        PlanBuilderScreen(model: PlanBuilderViewModel(plan: plan, library: library))
    }
}

/// The sheet (`b-12`): the header (the Cancel circle, the title, a compact Save), the name, the plan's settings, the
/// description, each day with its exercises, and Add day. The first model handed in is kept for the sheet's lifetime.
private struct PlanBuilderScreen: View {
    @State var model: PlanBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var addingTo: UUID?
    @State private var confirmRemoveDay: PlanDay?
    @State private var confirmDiscard = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, description }

    private var plan: Plan {
        get { model.plan }
        nonmutating set { model.plan = newValue }
    }

    private var shownIssues: [PlanIssue] {
        PlanBuilderRules.shownIssues(model.issues, attempted: model.attempted, hasChanges: model.hasChanges)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: PlanBuilderLayout.sectionSpacing) {
                    name
                    basics
                    descriptionField
                    ForEach(Bindable(model).plan.days) { $day in dayEditor($day) }
                    formIssueLines
                    PillButton(Text("Add day"), style: .secondary) { model.addDay() }
                        .accessibilityIdentifier("planBuilder.addDay")
                }
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.top, PlanBuilderLayout.headerGap)
                .padding(.bottom, PlanBuilderLayout.bottomPadding)
                // While Save is busy, nothing else changes the plan it is sending.
                .disabled(model.saving)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: Binding(get: { addingTo != nil }, set: { if !$0 { addingTo = nil } })) {
            AddExerciseSheet(title: "Add to day") { e in add(e) }.presentedRoot()
        }
        .confirmationDialog("Remove \(confirmRemoveDay?.name ?? "")?",
                            isPresented: Binding(get: { confirmRemoveDay != nil }, set: { if !$0 { confirmRemoveDay = nil } }),
                            titleVisibility: .visible) {
            Button("Remove day", role: .destructive) {
                if let d = confirmRemoveDay { model.removeDay(d.id) }
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
        }
        .interactiveDismissDisabled(model.hasChanges || model.saving)
    }

    // MARK: sections

    /// Cancel (it asks first when something changed) · "Edit plan" / "New plan" · Save, off until the plan is valid, its hint
    /// what is missing.
    private var header: some View {
        SheetHeader(model.isNew ? Text("New plan") : Text("Edit plan"), closeLabel: Text("Cancel"), onClose: {
            // Off while a save is in flight (`closeDisabled` below); the guard keeps a tap already under way harmless.
            guard !model.saving else { return }
            if model.hasChanges { confirmDiscard = true } else { dismiss() }
        }) {
            // Busy while saving (it ignores taps itself); off only while the plan isn't valid.
            PillButton(Text("Save"), size: .compact, busy: model.saving) {
                Task { if await model.save() { dismiss() } }
            }
            .disabled(!PlanBuilderRules.canSave(issues: model.issues))
            .accessibilityHint(Text(verbatim: model.issues.first?.message ?? ""))
            .accessibilityIdentifier("planBuilder.save")
            // A compact pill keeps its one line (`SheetHeader`).
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        // Cancel is dimmed and does nothing while the plan saves.
        .closeDisabled(model.saving)
        .padding(.horizontal, SheetHeaderSpec.sidePadding)
        .padding(.top, SheetHeaderSpec.topInset)
    }

    /// "Name" over the plan's name in 22 Light; "Give the plan a name." under it once something changed.
    private var name: some View {
        GroupedCard {
            FormField(Text("Name"), isFocused: focus == .name, valueSize: .large) {
                TextField(text: Bindable(model).plan.name, prompt: Text("Plan name").fieldPrompt()) { Text("Name") }
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .name)
            }
            issueLines([.missingName])
        }
    }

    /// Goal, days per week, repeats every week (or the weeks), progression; the progression's sentence under the card.
    private var basics: some View {
        GroupedCard(Text("Plan"), footer: Text(verbatim: progressionHelp)) {
            GroupedRow.menu(Text("Goal"), value: Text(verbatim: plan.goal.title)) {
                Picker(selection: Bindable(model).plan.goal) {
                    ForEach(PlanGoal.allCases) { Text(verbatim: $0.title).tag($0) }
                } label: {
                    Text("Goal")
                }
            }
            RyftStepperRow(Text("Days per week"), value: Bindable(model).plan.daysPerWeek, in: 1...7)
            GroupedRow.toggle(Text("Repeats every week"),
                              isOn: Binding(get: { plan.weeks == nil }, set: { plan.weeks = $0 ? nil : 8 }))
            if plan.weeks != nil {
                RyftStepperRow(Text("Weeks"), value: Binding(get: { plan.weeks ?? 8 }, set: { plan.weeks = $0 }), in: 1...52)
            }
            GroupedRow.menu(Text("Progression"), value: Text(verbatim: progressionName(plan.progressionType))) {
                Picker(selection: Binding(get: { plan.progressionType }, set: { plan.progression = .of($0) })) {
                    ForEach(ProgressionType.allCases) { Text(verbatim: progressionName($0)).tag($0) }
                } label: {
                    Text("Progression")
                }
            }
            issueLines([.daysPerWeek, .weeks])
        }
    }

    private var descriptionField: some View {
        GroupedCard {
            FormField(Text("Description"), isFocused: focus == .description) {
                TextField(text: Bindable(model).plan.description, prompt: Text("Optional").fieldPrompt(), axis: .vertical) {
                    Text("Description")
                }
                .lineLimit(1...4)
                .focused($focus, equals: .description)
            }
        }
    }

    private func progressionName(_ type: ProgressionType) -> String {
        switch type {
        case .linear: return String(localized: "Linear")
        case .percent: return String(localized: "Percent")
        case .none: return String(localized: "None")
        }
    }

    private var progressionHelp: String {
        switch plan.progressionType {
        case .linear: return String(localized: "+2.5 kg after every set is done; the same weight after a miss; 10\u{00A0}% lighter after three misses.")
        case .percent: return String(localized: "Weights follow % of your estimated 1RM, rounded to 2.5 kg.")
        case .none: return String(localized: "Targets stay as you set them.")
        }
    }

    /// The day's name (`headline`) with the trash circle; a card per exercise; Add exercise.
    private func dayEditor(_ day: Binding<PlanDay>) -> some View {
        let dayID = day.wrappedValue.id
        let count = day.wrappedValue.exercises.count
        return VStack(alignment: .leading, spacing: PlanBuilderLayout.exerciseSpacing) {
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                HStack(spacing: GroupedListSpec.rowSpacing) {
                    TextField(text: day.name, prompt: Text("Day name").fieldPrompt()) { Text("Day name") }
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.textPrimary)
                    if let w = day.wrappedValue.week {
                        Text("Week \(w)")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    CircleButton(systemImage: "trash", accessibilityLabel: Text("Remove \(day.wrappedValue.name)")) {
                        // A day with exercises asks first; an empty one goes.
                        if day.wrappedValue.exercises.isEmpty {
                            model.removeDay(dayID)
                        } else {
                            confirmRemoveDay = day.wrappedValue
                        }
                    }
                }
                if shownIssues.contains(.emptyDay(dayID: dayID)) {
                    issueText(.emptyDay(dayID: dayID))
                }
            }
            .padding(.bottom, PlanBuilderLayout.dayTitleGap - PlanBuilderLayout.exerciseSpacing)
            ForEach(Array(day.exercises.enumerated()), id: \.element.id) { i, ex in
                PlanExerciseEditor(exercise: ex, isFirst: i == 0, isLast: i == count - 1,
                                   issues: shownIssues,
                                   linkedWithNext: model.isLinked(dayID: dayID, i),
                                   onLink: { model.link(dayID: dayID, i, $0) },
                                   onRemove: { model.remove(dayID: dayID, i) },
                                   onMove: { model.move(dayID: dayID, i, by: $0) })
            }
            GroupedCard {
                GroupedRow.action(Text("Add exercise"), systemImage: "plus") { addingTo = dayID }
                    .accessibilityIdentifier("planBuilder.addExercise")
            }
        }
    }

    /// The shown issues no field carries, above Add day.
    @ViewBuilder
    private var formIssueLines: some View {
        let issues = PlanBuilderRules.formIssues(shownIssues)
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                ForEach(issues) { issueText($0) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("planBuilder.issues")
        }
    }

    /// The shown issues among `issues`, each a line under its card's rows.
    private func issueLines(_ issues: [PlanIssue]) -> some View {
        ForEach(issues.filter(shownIssues.contains), id: \.self) { issue in
            issueText(issue)
                .padding(.horizontal, GroupedListSpec.rowInset)
                .padding(.bottom, PlanBuilderLayout.issueBottom)
        }
    }

    // MARK: editing

    private func add(_ e: Exercise) {
        guard let id = addingTo else { return }
        model.add(e, toDay: id)
    }
}

/// A validation line: `caption` in `textPrimary` (no alert red, L27), `PlanValidation`'s sentence.
private func issueText(_ issue: PlanIssue) -> some View {
    Text(verbatim: issue.message)
        .font(.ryft(.caption))
        .foregroundStyle(Theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
}

/// One exercise of a plan day, a grouped card: its name with the `…` menu (move, superset, remove), Sets, Reps from, Reps to,
/// the target (a value and its kind) and the rest.
private struct PlanExerciseEditor: View {
    @Binding var exercise: PlanExercise
    let isFirst: Bool
    let isLast: Bool
    let issues: [PlanIssue]
    let linkedWithNext: Bool
    let onLink: (Bool) -> Void
    let onRemove: () -> Void
    let onMove: (Int) -> Void

    @State private var confirmRemove = false

    var body: some View {
        GroupedCard {
            GroupedRow.custom(Text(verbatim: exercise.exercise.name),
                              detail: linkedWithNext ? Text("Superset with next") : nil) { options }
            RyftStepperRow(Text("Sets"), quiet: true, value: $exercise.sets, in: 1...PlanValidation.maxSets)
            RyftStepperRow(Text("Reps from"), quiet: true, value: repsFrom)
            RyftStepperRow(Text("Reps to"), quiet: true, value: repsTo)
            issueLine(.reps(exerciseID: exercise.id))
            GroupedRow.custom(Text("Target")) { target }
            issueLine(.target(exerciseID: exercise.id))
            GroupedRow.menu(Text("Rest"), value: Text(verbatim: Fmt.clock(TimeInterval(exercise.restSec)))) {
                Picker(selection: $exercise.restSec) {
                    ForEach(PlanBuilderRules.restChoices(current: exercise.restSec), id: \.self) {
                        Text(verbatim: Fmt.clock(TimeInterval($0))).tag($0)
                    }
                } label: {
                    Text("Rest")
                }
            }
        }
        .confirmationDialog("Remove \(exercise.exercise.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    /// `…`: Move up, Move down, Superset with next (checked while on), Remove.
    private var options: some View {
        Menu {
            Button("Move up", systemImage: "arrow.up") { onMove(-1) }.disabled(isFirst)
            Button("Move down", systemImage: "arrow.down") { onMove(1) }.disabled(isLast)
            if !isLast {
                Toggle(isOn: Binding(get: { linkedWithNext }, set: onLink)) {
                    Label("Superset with next", systemImage: "link")
                }
            }
            Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: GroupedListSpec.glyphSize, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: CircleButton.hitSize, height: CircleButton.hitSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Options for \(exercise.exercise.name)"))
    }

    /// Reps from: one up raises "to" with it.
    private var repsFrom: RyftStepperValue {
        RyftStepperValue(text: "\(exercise.repsMin)", canDecrement: exercise.repsMin > 1,
                         canIncrement: exercise.repsMin < PlanValidation.maxReps) { direction in
            exercise.repsMin = RyftStepperSpec.stepped(exercise.repsMin, direction: direction, step: 1,
                                                       in: 1...PlanValidation.maxReps)
            exercise.repsMax = max(exercise.repsMax, exercise.repsMin)
        }
    }

    /// Reps to: one down lowers "from" with it.
    private var repsTo: RyftStepperValue {
        RyftStepperValue(text: "\(exercise.repsMax)", canDecrement: exercise.repsMax > 1,
                         canIncrement: exercise.repsMax < PlanValidation.maxReps) { direction in
            exercise.repsMax = RyftStepperSpec.stepped(exercise.repsMax, direction: direction, step: 1,
                                                       in: 1...PlanValidation.maxReps)
            exercise.repsMin = min(exercise.repsMin, exercise.repsMax)
        }
    }

    /// "80" in a field, then its kind as a menu chip ("kg", "RPE", "% 1RM", "Bodyweight"): "80 kg" on one line.
    private var target: some View {
        HStack(spacing: ValueChipSpec.spacing) {
            TextField(value: $exercise.targetValue, format: .number.precision(.fractionLength(0...1)),
                      prompt: Text(exercise.targetKind == .bodyweight ? "0" : "–").fieldPrompt()) {
                Text(valueLabel)
            }
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.textPrimary)
            .frame(width: PlanBuilderLayout.targetFieldWidth)
            .accessibilityLabel(Text(valueLabel))
            Menu {
                Picker(selection: Binding(get: { exercise.targetKind }, set: { k in
                    exercise.targetKind = k
                    exercise.targetValue = Self.defaultValue(for: k)
                })) {
                    ForEach(TargetKind.allCases) { Text(verbatim: $0.title).tag($0) }
                } label: {
                    Text("Target")
                }
            } label: {
                ValueChip(Text(verbatim: exercise.targetKind.title))
            }
            .accessibilityLabel(Text("Target"))
            .accessibilityValue(Text(verbatim: exercise.targetKind.title))
        }
    }

    private var valueLabel: LocalizedStringKey {
        switch exercise.targetKind {
        case .pct1rm: return "% of 1RM"
        case .rpe: return "RPE"
        case .kg: return "Weight (kg)"
        case .bodyweight: return "Added load (kg)"
        }
    }

    private static func defaultValue(for kind: TargetKind) -> Double? {
        switch kind {
        case .pct1rm: return 75
        case .rpe: return 8
        case .kg: return 20
        case .bodyweight: return nil
        }
    }

    @ViewBuilder
    private func issueLine(_ issue: PlanIssue) -> some View {
        if issues.contains(issue) {
            issueText(issue)
                .padding(.horizontal, GroupedListSpec.rowInset)
                .padding(.bottom, PlanBuilderLayout.issueBottom)
        }
    }
}

// MARK: - previews (dark only)

#Preview("Plan builder · copy") {
    PlanBuilderView(plan: MockTrain.upperLower.copy())
        .toggleStyle(.ryft)
        .previewEnvironment()
}

#Preview("Plan builder · new") {
    PlanBuilderView(plan: .blank())
        .toggleStyle(.ryft)
        .previewEnvironment()
}

#Preview("Plan builder · mine, AX3") {
    PlanBuilderView(plan: MockTrain.homeDumbbells)
        .toggleStyle(.ryft)
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}
