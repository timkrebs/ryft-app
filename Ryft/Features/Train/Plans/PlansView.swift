import SwiftUI

extension PlanExercise {
    /// "4 × 5 @ 80 kg", "3 × 10–12 @ RPE 8", "6 × 2 @ 75 % 1RM".
    var targetText: String {
        let base = Fmt.prescription(sets: sets, repsMin: repsMin, repsMax: repsMax)
        guard let v = targetValue else { return targetKind == .bodyweight ? "\(base) · \(TargetKind.bodyweight.title)" : base }
        switch targetKind {
        case .kg: return "\(base) @ \(Fmt.kg(v))"
        case .rpe: return "\(base) @ RPE \(Fmt.kgNumber(v))"
        case .pct1rm: return "\(base) @ \(Fmt.kgNumber(v)) % 1RM"
        case .bodyweight: return "\(base) · BW + \(Fmt.kg(v))"
        }
    }
}

/// "Hypertrophy · 4 days/week · repeating".
private func planSummaryText(goal: PlanGoal, daysPerWeek: Int, weeks: Int?) -> String {
    let length = weeks.map { String(localized: "\($0) weeks") } ?? String(localized: "repeating")
    return [goal.title, String(localized: "\(daysPerWeek) days/week"), length].joined(separator: " · ")
}

extension PlanSummary {
    var summaryText: String { planSummaryText(goal: goal, daysPerWeek: daysPerWeek, weeks: weeks) }
}

extension Plan {
    var summaryText: String { planSummaryText(goal: goal, daysPerWeek: daysPerWeek, weeks: weeks) }

    static func blank() -> Plan {
        Plan(name: "", goal: .general, weeks: nil, daysPerWeek: 3, description: "", progression: .linear,
             isBuiltin: false, days: [PlanDay(dayIndex: 0, name: String(localized: "Day A"), exercises: [])])
    }

    /// An editable copy with fresh ids (for "Copy and edit" on a built-in).
    func copy() -> Plan {
        Plan(name: String(localized: "\(name) (copy)"), goal: goal, weeks: weeks, daysPerWeek: daysPerWeek,
             description: description, progression: progression, isBuiltin: false,
             days: days.map { d in
                 PlanDay(week: d.week, dayIndex: d.dayIndex, name: d.name, exercises: d.exercises.map { e in
                     PlanExercise(exercise: e.exercise, position: e.position, sets: e.sets, repsMin: e.repsMin,
                                  repsMax: e.repsMax, targetKind: e.targetKind, targetValue: e.targetValue,
                                  restSec: e.restSec, supersetGroup: e.supersetGroup, notes: e.notes)
                 })
             })
    }
}

/// Built-in templates, the user's plans and the active (or paused) enrolment.
struct PlansView: View {
    @Environment(TrainLibrary.self) private var library

    var body: some View {
        PlansScreen(model: PlansViewModel(library: library))
    }
}

/// Layout only; the first model handed in is kept for the screen's lifetime.
private struct PlansScreen: View {
    @State var model: PlansViewModel
    @State private var editing: Plan?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                if let id = model.currentPlanID {
                    currentCard(planID: id)
                }
                if let error = model.error {
                    InlineMessage(message: error, details: model.errorDetails, retry: { await model.refresh() })
                }
                section("Built-in", plans: model.builtin)
                section("My plans", plans: model.mine)
                Button {
                    editing = .blank()
                } label: {
                    Label("New plan", systemImage: "plus")
                }
                .buttonStyle(TealButtonStyle(prominent: false))
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await model.refresh() }
        .task { await model.loadIfNeeded() }
        .sheet(item: $editing) { PlanBuilderView(plan: $0) }
    }

    private func currentCard(planID: UUID) -> some View {
        let paused = model.isPaused
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(paused ? "Paused" : "Active").ryftLabelStyle(paused ? Theme.warning : Theme.accent)
                    Spacer()
                    if let week = model.currentWeekText {
                        Text(week)
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                NavigationLink(value: TrainRoute.plan(planID)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.currentName)
                                .font(.ryft(.headline))
                                .foregroundStyle(Theme.textPrimary)
                            if let detail = model.currentDetail {
                                Text(detail)
                                    .font(.ryft(.callout))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(paused ? "Resume" : "Pause") {
                    Task { await model.togglePause() }
                }
                .buttonStyle(TealButtonStyle(prominent: paused))
                .disabled(model.working)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, plans: [PlanSummary]) -> some View {
        if !plans.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                TrainSectionTitle(title: title)
                ForEach(plans) { p in
                    NavigationLink(value: TrainRoute.plan(p.id)) {
                        TrainLinkRow(title: p.name, detail: p.summaryText,
                                     systemImage: model.currentPlanID == p.id ? "checkmark.circle.fill" : "list.bullet.rectangle")
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
    }
}

/// A plan's weeks → days → exercises, and enrol / switch / pause.
struct PlanDetailView: View {
    let planID: UUID
    @Environment(TrainLibrary.self) private var library

    var body: some View {
        PlanDetailScreen(model: PlanDetailViewModel(planID: planID, library: library))
    }
}

/// Layout only; the first model handed in is kept for the screen's lifetime.
private struct PlanDetailScreen: View {
    @State var model: PlanDetailViewModel
    @Environment(TrainCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Plan?
    @State private var confirmSwitch = false
    @State private var confirmDelete = false

    private var plan: Plan? { model.plan }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                if let plan {
                    header(plan)
                    actions(plan)
                    if model.weeks.count > 1 {
                        SegmentedPicker(selection: Bindable(model).week, options: model.weeks) {
                            String(localized: "Week \($0)")
                        }
                    }
                    ForEach(model.shownDays) { dayCard($0) }
                } else {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(plan?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: model.planID) { await model.load() }
        .sheet(item: $editing, onDismiss: { Task { await model.load() } }) {
            PlanBuilderView(plan: $0)
        }
        .confirmationDialog("Switch to \(plan?.name ?? "")?", isPresented: $confirmSwitch, titleVisibility: .visible) {
            Button("Switch plan") { Task { await model.enroll() } }
        } message: {
            Text("\(model.currentPlanName) is paused; this one starts at week 1. Logged workouts stay.")
        }
        .confirmationDialog("Delete \(plan?.name ?? "")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete plan", role: .destructive) {
                Task {
                    if await model.delete() { dismiss() }
                }
            }
        } message: {
            Text("Logged workouts stay.")
        }
    }

    private func header(_ p: Plan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(p.summaryText)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.accent)
            Text(p.progressionType.title)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
            if !p.description.isEmpty {
                Text(p.description)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func actions(_ p: Plan) -> some View {
        VStack(spacing: 10) {
            if model.isCurrent {
                Button(model.isPaused ? "Resume plan" : "Pause plan") {
                    Task { await model.togglePause() }
                }
                .buttonStyle(TealButtonStyle(prominent: model.isPaused))
            } else {
                Button(model.hasEnrollment ? "Switch to this plan" : "Start this plan") {
                    if model.hasEnrollment { confirmSwitch = true } else { Task { await model.enroll() } }
                }
                .buttonStyle(TealButtonStyle())
            }
            HStack(spacing: 18) {
                if p.isBuiltin {
                    Button("Copy and edit") { editing = p.copy() }
                } else {
                    Button("Edit") { editing = p }
                    Button("Delete", role: .destructive) { confirmDelete = true }
                        .foregroundStyle(Theme.alert)
                }
            }
            .font(.ryft(.callout))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
            if let error = model.error {
                InlineMessage(message: error, details: model.errorDetails)
            }
        }
        .disabled(model.working)
    }

    private func dayCard(_ day: PlanDay) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(day.name)
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("~\(SessionEstimate.minutes(for: day.exercises)) min")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(day.exercises.sorted { $0.position < $1.position }) { e in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: e.supersetGroup == nil ? "circle.fill" : "link")
                            .font(.system(size: e.supersetGroup == nil ? 5 : 11, weight: .bold))
                            .foregroundStyle(e.supersetGroup == nil ? Theme.textTertiary : Theme.accent)
                            .frame(width: 14, height: 18)
                            .accessibilityLabel(Text(e.supersetGroup == nil ? "" : String(localized: "Superset")))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.exercise.name)
                                .font(.ryft(.body))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(e.targetText) · rest \(Fmt.clock(TimeInterval(e.restSec)))")
                                .font(.ryft(.caption))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                            if !e.notes.isEmpty {
                                Text(e.notes).font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    coordinator.start(day: day)
                } label: {
                    Label("Start \(day.name)", systemImage: "play.fill")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(coordinator.active != nil)
            }
        }
    }
}

#Preview("Plans · dark") {
    NavigationStack { PlansView().trainDestinations() }
        .previewEnvironment()
}

#Preview("Plans · light") {
    NavigationStack { PlansView().trainDestinations() }
        .previewEnvironment(scheme: .light)
}

#Preview("Plan detail · dark") {
    NavigationStack { PlanDetailView(planID: MockTrain.upperLower.id) }
        .previewEnvironment()
}

#Preview("Plan detail · weeks, light") {
    NavigationStack { PlanDetailView(planID: MockTrain.weightlifting.id) }
        .previewEnvironment(scheme: .light)
}
