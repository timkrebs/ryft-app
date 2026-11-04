import SwiftUI

/// Strain tab → Train: Start workout (or resume), today's plan, plans, history.
struct TrainSection: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(TrainCoordinator.self) private var coordinator

    private var model: TrainTodayViewModel { screens.trainToday }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrainSectionTitle(title: "Train")
            if let active = coordinator.active {
                WorkoutInProgressBanner(session: active) { coordinator.resume() }
            } else {
                Button {
                    coordinator.showsStart = true
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                }
                .buttonStyle(TealButtonStyle())
                .accessibilityIdentifier("train.start")
            }
            if let today = model.today, let title = model.todayLinkTitle {
                NavigationLink(value: TrainRoute.plan(today.enrollment.planId)) {
                    TrainLinkRow(title: title, detail: model.todayLinkDetail, systemImage: "calendar")
                }
                .buttonStyle(PressableButtonStyle())
            }
            NavigationLink(value: TrainRoute.plans) {
                TrainLinkRow(title: String(localized: "My plans"), detail: model.plansDetail,
                             systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("train.plans")
            NavigationLink(value: TrainRoute.history) {
                TrainLinkRow(title: String(localized: "History"), detail: model.historyDetail,
                             systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(PressableButtonStyle())
        }
    }
}

enum TodayPlanText {
    /// "5 exercises · ~55 min".
    static func detail(_ today: PlanToday) -> String {
        let exercises = String(localized: "\(today.day.exercises.count) exercises")
        return "\(exercises) · ~\(SessionEstimate.minutes(for: today.day.exercises)) min"
    }
}

/// From today's plan, repeat the last session, a plan day, or empty.
struct StartWorkoutSheet: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(TrainCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var showsDays = false

    private var model: TrainTodayViewModel { screens.trainToday }
    private var last: TrainSession? { model.lastSession }
    private var plan: Plan? { model.activePlan }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let todayText = model.todayText {
                        option(title: String(localized: "From today's plan"),
                               detail: todayText,
                               systemImage: "calendar", prominent: true) {
                            coordinator.startFromToday()
                        }
                        .accessibilityIdentifier("train.start.today")
                    }
                    if let last {
                        option(title: String(localized: "Repeat last session"),
                               detail: "\(last.title) · \(Fmt.dayTitle(last.startedAt))",
                               systemImage: "arrow.clockwise") {
                            coordinator.repeatSession(last)
                        }
                    }
                    if let plan, !plan.days.isEmpty {
                        option(title: String(localized: "A day from \(plan.name)"),
                               detail: plan.days.map(\.name).joined(separator: " · "),
                               systemImage: "list.bullet", chevron: showsDays ? "chevron.up" : "chevron.down") {
                            withAnimation(Theme.Motion.quick) { showsDays.toggle() }
                        }
                        if showsDays {
                            ForEach(model.planDays) { day in
                                Button {
                                    coordinator.start(day: day)
                                } label: {
                                    HStack {
                                        Text(day.week.map { String(localized: "Week \($0) · \(day.name)") } ?? day.name)
                                            .font(.ryft(.body))
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Text("\(day.exercises.count) · ~\(SessionEstimate.minutes(for: day.exercises)) min")
                                            .font(.ryft(.caption))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 56)
                                    .background(Theme.surface.opacity(0.6),
                                                in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
                                }
                                .buttonStyle(PressableButtonStyle())
                                .padding(.leading, 24)
                            }
                        }
                    }
                    option(title: String(localized: "Empty session"),
                           detail: String(localized: "Add exercises as you go"), systemImage: "plus") {
                        coordinator.startEmpty()
                    }
                    .accessibilityIdentifier("train.start.empty")
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Start workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            // The last session to repeat, and the active plan's days for "A day from …".
            .task { await model.loadStartOptions() }
        }
        .presentationDetents([.medium, .large])
    }

    private func option(title: String, detail: String, systemImage: String, prominent: Bool = false,
                        chevron: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(prominent ? Theme.onAccent : Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(prominent ? Theme.onAccent.opacity(0.12) : Theme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.ryft(.headline))
                    Text(detail).font(.ryft(.caption)).lineLimit(2)
                        .opacity(0.8)
                }
                .foregroundStyle(prominent ? Theme.onAccent : Theme.textPrimary)
                Spacer()
                if let chevron {
                    Image(systemName: chevron).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(14)
            .frame(minHeight: 64)
            .background(prominent ? Theme.accent : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Today: "Today: Upper A · 5 exercises · ~55 min" → Start; in progress → Resume;
/// after a session "Done · load 84.6 · 2 PRs".
struct TrainTodayCard: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(TrainCoordinator.self) private var coordinator

    private var model: TrainTodayViewModel { screens.trainToday }

    var body: some View {
        if let active = coordinator.active {
            WorkoutInProgressBanner(session: active) { coordinator.resume() }
        } else if let done = model.doneToday {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(done.title).ryftLabelStyle()
                        Text(TrainTodayViewModel.doneText(done))
                            .font(.ryft(.body))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        if done.pendingCompletion { WillSyncNote() }
                    }
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
        } else if let todayText = model.todayText {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Text("Today: \(todayText)")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        Task { await coordinator.quickStart(.auto) }
                    } label: {
                        Label("Start strength workout", systemImage: "play.fill")
                    }
                    .buttonStyle(TealButtonStyle())
                    .accessibilityIdentifier("today.train.start")
                }
            }
        } else {
            // No plan: start one anyway, empty or as last time.
            let last = model.historyDetail
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Text("Quick start")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 10) {
                        Button {
                            Task { await coordinator.quickStart(.empty) }
                        } label: {
                            Label("Empty workout", systemImage: "plus")
                        }
                        .buttonStyle(TealButtonStyle())
                        .accessibilityIdentifier("today.train.empty")
                        if last != nil {
                            Button {
                                Task { await coordinator.quickStart(.repeatLast) }
                            } label: {
                                Label("Repeat last", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(TealButtonStyle(prominent: false))
                            .accessibilityIdentifier("today.train.repeat")
                        }
                    }
                    if let last {
                        Text(last)
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Train").ryftLabelStyle()
            Spacer()
            Image(systemName: "dumbbell.fill").foregroundStyle(Theme.accent).accessibilityHidden(true)
        }
    }
}

#Preview("Train section · dark") {
    NavigationStack {
        ScrollView { TrainSection().padding(20) }
            .background(Theme.background)
            .trainDestinations()
    }
    .previewEnvironment()
}

#Preview("Train section · light") {
    NavigationStack {
        ScrollView { TrainSection().padding(20) }
            .background(Theme.background)
    }
    .previewEnvironment(scheme: .light)
}

#Preview("Start workout") {
    Text("").sheet(isPresented: .constant(true)) { StartWorkoutSheet().previewEnvironment() }
        .previewEnvironment()
}

#Preview("Today card", traits: .sizeThatFitsLayout) {
    SchemePair { TrainTodayCard() }
        .previewEnvironment()
}
