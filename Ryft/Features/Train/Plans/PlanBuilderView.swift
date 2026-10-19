import SwiftUI

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

/// The form; the first model handed in is kept for the sheet's lifetime.
private struct PlanBuilderScreen: View {
    @State var model: PlanBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var addingTo: UUID?
    @State private var confirmRemoveDay: PlanDay?
    @State private var confirmDiscard = false

    private var plan: Plan {
        get { model.plan }
        nonmutating set { model.plan = newValue }
    }
    private var issues: [PlanIssue] { model.issues }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                    if !model.shownIssues.isEmpty { issueList }
                    basics
                    ForEach(Bindable(model).plan.days) { $day in dayEditor($day) }
                    Button {
                        model.addDay()
                    } label: {
                        Label("Add day", systemImage: "plus")
                    }
                    .buttonStyle(TealButtonStyle(prominent: false))
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(model.isNew ? "New plan" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if model.hasChanges { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { if await model.save() { dismiss() } } }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { addingTo != nil }, set: { if !$0 { addingTo = nil } })) {
                AddExerciseSheet(title: "Add to day") { e in add(e) }
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
        }
        .interactiveDismissDisabled(model.hasChanges)
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
                TextField("Plan name", text: Bindable(model).plan.name)
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
                    SegmentedPicker(selection: Binding(get: { plan.progressionType },
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
                TextField("Description (optional)", text: Bindable(model).plan.description, axis: .vertical)
                    .font(.ryft(.callout))
                    .lineLimit(1...4)
            }
        }
    }

    private var progressionHelp: String {
        switch plan.progressionType {
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
                if model.shownIssues.contains(.emptyDay(dayID: day.wrappedValue.id)) {
                    Text(PlanIssue.emptyDay(dayID: day.wrappedValue.id).message)
                        .font(.ryft(.caption)).foregroundStyle(Theme.alert)
                }
                let count = day.wrappedValue.exercises.count
                ForEach(Array(day.exercises.enumerated()), id: \.element.id) { i, ex in
                    let dayID = day.wrappedValue.id
                    PlanExerciseEditor(exercise: ex, isLast: i == count - 1,
                                       issues: model.shownIssues,
                                       linkedWithNext: model.isLinked(dayID: dayID, i),
                                       onLink: { model.link(dayID: dayID, i, $0) },
                                       onRemove: { model.remove(dayID: dayID, i) },
                                       onMove: { model.move(dayID: dayID, i, by: $0) })
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
        guard let id = addingTo else { return }
        model.add(e, toDay: id)
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
