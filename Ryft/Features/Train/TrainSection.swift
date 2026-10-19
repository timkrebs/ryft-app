import SwiftUI

/// Strain tab → Train: Start workout (or resume), today's plan, plans, history.
struct TrainSection: View {
    @EnvironmentObject private var library: TrainLibrary
    @EnvironmentObject private var coordinator: TrainCoordinator

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
            if let today = library.today {
                NavigationLink(value: TrainRoute.plan(today.enrollment.planId)) {
                    TrainLinkRow(title: String(localized: "Today's plan: \(today.day.name)"),
                                 detail: TodayPlanText.detail(today), systemImage: "calendar")
                }
                .buttonStyle(PressableButtonStyle())
            }
            NavigationLink(value: TrainRoute.plans) {
                TrainLinkRow(title: String(localized: "My plans"), detail: plansDetail, systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(PressableButtonStyle())
            NavigationLink(value: TrainRoute.history) {
                TrainLinkRow(title: String(localized: "History"), detail: historyDetail,
                             systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private var plansDetail: String? {
        if let e = library.activeEnrollment, e.status == .active {
            return String(localized: "\(library.activePlanName ?? "") · week \(e.currentWeek)")
        }
        if let paused = library.pausedPlanID {
            let name = library.catalog?.summary(id: paused)?.name ?? library.plan(id: paused)?.name ?? ""
            return String(localized: "\(name) · paused")
        }
        return String(localized: "Pick a plan or build your own")
    }

    private var historyDetail: String? {
        guard let last = library.cachedSessions().first else { return nil }
        return String(localized: "Last: \(last.title) · \(Fmt.dayTitle(last.startedAt))")
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
    @EnvironmentObject private var library: TrainLibrary
    @EnvironmentObject private var coordinator: TrainCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var last: TrainSession?
    @State private var plan: Plan?
    @State private var showsDays = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let today = library.today {
                        option(title: String(localized: "From today's plan"),
                               detail: "\(today.day.name) · \(TodayPlanText.detail(today))",
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
                            withAnimation(.snappy) { showsDays.toggle() }
                        }
                        if showsDays {
                            ForEach(plan.days.sorted { ($0.week ?? 0, $0.dayIndex) < ($1.week ?? 0, $1.dayIndex) }) { day in
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
            .task {
                last = await library.lastSession()
                // The active plan's days, for "A day from …".
                if let id = library.activeEnrollment?.planId { plan = await library.loadPlan(id: id) }
            }
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
    @EnvironmentObject private var library: TrainLibrary
    @EnvironmentObject private var coordinator: TrainCoordinator
    @EnvironmentObject private var sync: TrainSyncService

    private var doneToday: LocalSession? {
        sync.store.completedSessions(from: Calendar.current.startOfDay(for: .now)).first
    }

    var body: some View {
        if let active = coordinator.active {
            WorkoutInProgressBanner(session: active) { coordinator.resume() }
        } else if let done = doneToday {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(done.title).ryftLabelStyle()
                        Text(doneText(done))
                            .font(.ryft(.body))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        if done.pendingCompletion { WillSyncNote() }
                    }
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
        } else if let today = library.today {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Train").ryftLabelStyle()
                        Spacer()
                        Image(systemName: "dumbbell.fill").foregroundStyle(Theme.accent).accessibilityHidden(true)
                    }
                    Text("Today: \(today.day.name) · \(TodayPlanText.detail(today))")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        coordinator.startFromToday()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(TealButtonStyle())
                    .accessibilityIdentifier("today.train.start")
                }
            }
        }
    }

    /// "Done · load 11.2 · 2 PRs": the session's `strain`, the muscular load on the strain scale.
    private func doneText(_ s: LocalSession) -> String {
        var parts = [String(localized: "Done")]
        if let load = s.strain { parts.append(String(localized: "load \(Fmt.load(load))")) }
        let prs = s.prs.count
        if prs > 0 { parts.append(String(localized: "\(prs) PRs")) }
        return parts.joined(separator: " · ")
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
