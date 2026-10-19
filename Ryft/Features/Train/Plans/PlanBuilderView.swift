import SwiftUI

/// Create or edit a plan: name, goal, days per week, weeks or repeating,
/// progression; per day the exercises with sets, rep range, target, rest and
/// supersets. Validation (PlanValidation) runs live; Save sends the whole plan.
struct PlanBuilderView: View {
    @State var plan: Plan
    @EnvironmentObject private var library: TrainLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var addingTo: UUID?
    @State private var attempted = false
    @State private var saving = false
    @State private var confirmRemoveDay: PlanDay?
    @State private var confirmDiscard = false
    private let original: Plan

    init(plan: Plan) {
        _plan = State(initialValue: plan)
        original = plan
    }

    private var issues: [PlanIssue] { PlanValidation.issues(in: plan) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                    if attempted && !issues.isEmpty { issueList }
                    basics
                    ForEach($plan.days) { $day in dayEditor($day) }
                    Button {
                        let i = (plan.days.map(\.dayIndex).max() ?? -1) + 1
                        let letter = String(UnicodeScalar(UInt8(65 + min(i, 25))))
                        plan.days.append(PlanDay(dayIndex: i, name: String(localized: "Day \(letter)"), exercises: []))
                    } label: {
                        Label("Add day", systemImage: "plus")
                    }
                    .buttonStyle(TealButtonStyle(prominent: false))
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(original.name.isEmpty ? "New plan" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if plan == original { dismiss() } else { confirmDiscard = true } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save") { Task { await save() } } }
                }
            }
            .sheet(isPresented: Binding(get: { addingTo != nil }, set: { if !$0 { addingTo = nil } })) {
                AddExerciseSheet(title: "Add to day") { e in add(e) }
            }
            .confirmationDialog("Remove \(confirmRemoveDay?.name ?? "")?",
                                isPresented: Binding(get: { confirmRemoveDay != nil }, set: { if !$0 { confirmRemoveDay = nil } }),
                                titleVisibility: .visible) {
                Button("Remove day", role: .destructive) {
                    if let d = confirmRemoveDay { plan.days.removeAll { $0.id == d.id } }
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
        }
        .interactiveDismissDisabled(plan != original)
    }

    // MARK: sections

    private var issueList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Set(issues.map(\.message))).sorted(), id: \.self) { message in
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.alert)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.alert.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var basics: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Plan name", text: $plan.name)
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel(Text("Plan name"))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal").ryftLabelStyle()
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(PlanGoal.allCases) { g in
                                FilterChip(title: g.title, selected: plan.goal == g) { plan.goal = g }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                ValueStepper(title: "Days per week", value: "\(plan.daysPerWeek)",
                             minus: { plan.daysPerWeek = max(1, plan.daysPerWeek - 1) },
                             plus: { plan.daysPerWeek = min(7, plan.daysPerWeek + 1) })
                Toggle(isOn: Binding(get: { plan.weeks == nil }, set: { plan.weeks = $0 ? nil : 8 })) {
                    Text("Repeats every week").font(.ryft(.body))
                }
                .tint(Theme.accent)
                if let weeks = plan.weeks {
                    ValueStepper(title: "Weeks", value: "\(weeks)",
                                 minus: { plan.weeks = max(1, weeks - 1) },
                                 plus: { plan.weeks = min(52, weeks + 1) })
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Progression").ryftLabelStyle()
                    SegmentedPicker(selection: Binding(get: { plan.progression.type },
                                                       set: { plan.progression = .of($0) }),
                                    options: ProgressionType.allCases) { type in
                        switch type {
                        case .linear: return String(localized: "Linear")
                        case .percent: return String(localized: "Percent")
                        case .none: return String(localized: "None")
                        }
                    }
                    Text(progressionHelp)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextField("Description (optional)", text: $plan.description, axis: .vertical)
                    .font(.ryft(.callout))
                    .lineLimit(1...4)
            }
        }
    }

    private var progressionHelp: String {
        switch plan.progression.type {
        case .linear: return String(localized: "+2.5 kg after every set is done; the same weight after a miss; 10 % lighter after three misses.")
        case .percent: return String(localized: "Weights follow % of your estimated 1RM, rounded to 2.5 kg.")
        case .none: return String(localized: "Targets stay as you set them.")
        }
    }

    private func dayEditor(_ day: Binding<PlanDay>) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("Day name", text: day.name)
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    if let w = day.wrappedValue.week {
                        Text("Week \(w)").font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
                    }
                    Button(role: .destructive) {
                        confirmRemoveDay = day.wrappedValue
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityLabel(Text("Remove \(day.wrappedValue.name)"))
                }
                if attempted, issues.contains(.emptyDay(dayID: day.wrappedValue.id)) {
                    Text(PlanIssue.emptyDay(dayID: day.wrappedValue.id).message)
                        .font(.ryft(.caption)).foregroundStyle(Theme.alert)
                }
                let count = day.wrappedValue.exercises.count
                ForEach(Array(day.exercises.enumerated()), id: \.element.id) { i, $ex in
                    PlanExerciseEditor(exercise: $ex, isLast: i == count - 1,
                                       issues: attempted ? issues : [],
                                       linkedWithNext: linked(day.wrappedValue, i),
                                       onLink: { link(day, i, $0) },
                                       onRemove: { remove(day, i) },
                                       onMove: { move(day, i, by: $0) })
                    if i < count - 1 { Divider().overlay(Theme.separator) }
                }
                Button {
                    addingTo = day.wrappedValue.id
                } label: {
                    Label("Add exercise", systemImage: "plus")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    // MARK: editing

    private func add(_ e: Exercise) {
        guard let id = addingTo, let d = plan.days.firstIndex(where: { $0.id == id }) else { return }
        let weighted = e.loadType == .weight
        plan.days[d].exercises.append(PlanExercise(
            exercise: e, position: plan.days[d].exercises.count, sets: 3,
            repsMin: weighted ? 8 : 10, repsMax: weighted ? 10 : 12,
            targetKind: weighted ? .rpe : .bodyweight, targetValue: weighted ? 8 : nil,
            restSec: SessionFactory.defaultRest(for: e)))
    }

    private func linked(_ day: PlanDay, _ i: Int) -> Bool {
        guard i + 1 < day.exercises.count, let g = day.exercises[i].supersetGroup else { return false }
        return day.exercises[i + 1].supersetGroup == g
    }

    /// Superset with the next exercise (or split it off).
    private func link(_ day: Binding<PlanDay>, _ i: Int, _ on: Bool) {
        guard i + 1 < day.wrappedValue.exercises.count else { return }
        if on {
            let group = day.wrappedValue.exercises[i].supersetGroup
                ?? day.wrappedValue.exercises[i + 1].supersetGroup
                ?? ((day.wrappedValue.exercises.compactMap(\.supersetGroup).max() ?? 0) + 1)
            day.wrappedValue.exercises[i].supersetGroup = group
            day.wrappedValue.exercises[i + 1].supersetGroup = group
        } else {
            day.wrappedValue.exercises[i + 1].supersetGroup = nil
            if i == 0 || !linked(day.wrappedValue, i - 1) { day.wrappedValue.exercises[i].supersetGroup = nil }
        }
    }

    private func remove(_ day: Binding<PlanDay>, _ i: Int) {
        day.wrappedValue.exercises.remove(at: i)
        renumber(day)
    }

    private func move(_ day: Binding<PlanDay>, _ i: Int, by delta: Int) {
        let j = i + delta
        guard day.wrappedValue.exercises.indices.contains(j) else { return }
        day.wrappedValue.exercises.swapAt(i, j)
        renumber(day)
    }

    private func renumber(_ day: Binding<PlanDay>) {
        for i in day.wrappedValue.exercises.indices { day.wrappedValue.exercises[i].position = i }
        // A superset left with one member isn't one.
        let counts = Dictionary(grouping: day.wrappedValue.exercises.compactMap(\.supersetGroup), by: { $0 }).mapValues(\.count)
        for i in day.wrappedValue.exercises.indices {
            if let g = day.wrappedValue.exercises[i].supersetGroup, counts[g, default: 0] < 2 {
                day.wrappedValue.exercises[i].supersetGroup = nil
            }
        }
    }

    private func save() async {
        attempted = true
        plan.name = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard issues.isEmpty else { return }
        saving = true
        let ok = await library.savePlan(plan)
        saving = false
        if ok { dismiss() }
    }
}

/// One exercise in a plan day.
private struct PlanExerciseEditor: View {
    @Binding var exercise: PlanExercise
    let isLast: Bool
    let issues: [PlanIssue]
    let linkedWithNext: Bool
    let onLink: (Bool) -> Void
    let onRemove: () -> Void
    let onMove: (Int) -> Void

    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(exercise.exercise.name)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Menu {
                    Button("Move up", systemImage: "arrow.up") { onMove(-1) }.disabled(exercise.position == 0)
                    Button("Move down", systemImage: "arrow.down") { onMove(1) }.disabled(isLast)
                    Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityLabel(Text("Options for \(exercise.exercise.name)"))
            }
            ValueStepper(title: "Sets", value: "\(exercise.sets)",
                         minus: { exercise.sets = max(1, exercise.sets - 1) },
                         plus: { exercise.sets = min(PlanValidation.maxSets, exercise.sets + 1) })
            ValueStepper(title: "Reps from", value: "\(exercise.repsMin)",
                         minus: { exercise.repsMin = max(1, exercise.repsMin - 1) },
                         plus: {
                             exercise.repsMin += 1
                             exercise.repsMax = max(exercise.repsMax, exercise.repsMin)
                         })
            ValueStepper(title: "Reps to", value: "\(exercise.repsMax)",
                         minus: {
                             exercise.repsMax = max(1, exercise.repsMax - 1)
                             exercise.repsMin = min(exercise.repsMin, exercise.repsMax)
                         },
                         plus: { exercise.repsMax = min(PlanValidation.maxReps, exercise.repsMax + 1) })
            if has(.reps(exerciseID: exercise.id)) { issue(.reps(exerciseID: exercise.id)) }
            VStack(alignment: .leading, spacing: 8) {
                Text("Target").ryftLabelStyle()
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(TargetKind.allCases) { k in
                            FilterChip(title: k.title, selected: exercise.targetKind == k) {
                                exercise.targetKind = k
                                exercise.targetValue = Self.defaultValue(for: k)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                HStack {
                    Text(valueLabel).font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    TextField(exercise.targetKind == .bodyweight ? "0" : "–", value: $exercise.targetValue,
                              format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.ryft(.metric))
                        .monospacedDigit()
                        .frame(width: 110)
                        .accessibilityLabel(Text(valueLabel))
                }
                if has(.target(exerciseID: exercise.id)) { issue(.target(exerciseID: exercise.id)) }
            }
            ValueStepper(title: "Rest", value: Fmt.clock(TimeInterval(exercise.restSec)),
                         minus: { exercise.restSec = max(0, exercise.restSec - 15) },
                         plus: { exercise.restSec = min(PlanValidation.maxRestSec, exercise.restSec + 15) })
            if !isLast {
                Toggle(isOn: Binding(get: { linkedWithNext }, set: onLink)) {
                    Label("Superset with next", systemImage: "link").font(.ryft(.callout))
                }
                .tint(Theme.accent)
            }
        }
        .confirmationDialog("Remove \(exercise.exercise.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: onRemove)
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

    private func has(_ issue: PlanIssue) -> Bool { issues.contains(issue) }

    private func issue(_ issue: PlanIssue) -> some View {
        Text(issue.message).font(.ryft(.caption)).foregroundStyle(Theme.alert)
    }
}

/// "Sets   − 3 +" with 44 pt buttons.
struct ValueStepper: View {
    let title: LocalizedStringKey
    let value: String
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
            Spacer()
            stepButton("minus", action: minus)
            Text(value)
                .font(.ryft(.metric))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 56)
            stepButton("plus", action: plus)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: plus()
            case .decrement: minus()
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

#Preview("Plan builder · dark") {
    PlanBuilderView(plan: MockTrain.upperLower.copy())
        .previewEnvironment()
}

#Preview("Plan builder · light") {
    PlanBuilderView(plan: MockTrain.homeDumbbells)
        .previewEnvironment(scheme: .light)
}

#Preview("Plan builder · new") {
    PlanBuilderView(plan: .blank())
        .previewEnvironment()
}
