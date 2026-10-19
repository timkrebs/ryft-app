import SwiftUI

@MainActor
final class StrainViewModel: ObservableObject {
    @Published var date = Calendar.current.startOfDay(for: .now)
    @Published private(set) var detail: DayDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    func load(state: AppState) async {
        error = nil
        detail = state.cachedDayDetail(for: date)
        guard state.hasDataSource else { return }
        isLoading = detail == nil
        defer { isLoading = false }
        do {
            detail = try await state.dayDetail(for: date)
        } catch {
            if detail == nil { self.error = error.localizedDescription }
        }
    }
}

/// Strain ring for the selected day, week strip, zone minutes and activities.
struct StrainView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var coordinator: TrainCoordinator
    @EnvironmentObject private var trainSync: TrainSyncService
    @StateObject private var model = StrainViewModel()
    @State private var path = NavigationPath()
    /// `-RyftOpenWorkout YES` pushes the first workout once (screenshots).
    @State private var autoOpen = UserDefaults.standard.bool(forKey: "RyftOpenWorkout")

    static let maxStrain = 21.0

    private var score: DailyScore? { model.detail?.score ?? state.score(for: model.date) }

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScaffold {
                VStack(spacing: 2) {
                    Text("Strain")
                        .font(.ryft(.title))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(Fmt.dayTitle(model.date))
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
                weekStrip
                ring
                movement
                zones
                if Calendar.current.isDateInToday(model.date) { TrainSection() }
                activities
            }
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
            .trainDestinations()
        }
        .sheet(isPresented: $coordinator.showsStart) { StartWorkoutSheet() }
        .task(id: TaskKey(date: model.date, refreshed: state.lastUpdated)) {
            await model.load(state: state)
            if autoOpen, let first = model.detail?.workouts.first {
                autoOpen = false
                path.append(first)
            }
        }
    }

    /// The day's workouts, each merged with its logged session (`session_id`),
    /// then sessions without a workout yet (e.g. still syncing).
    private var activityItems: [ActivityItem] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: model.date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let local = trainSync.store.completedSessions(from: start, to: end).map(\.summary)
        let sessions = TrainLibrary.merged(local: local, remote: model.detail?.strain?.sessions ?? [])
        let workouts = model.detail?.workouts ?? []
        var linked = Set<UUID>()
        var items: [ActivityItem] = workouts.map { w in
            let s = sessions.first { $0.id == w.sessionId || $0.workoutId == w.id }
            if let s { linked.insert(s.id) }
            return .workout(w, s)
        }
        items += sessions.filter { !linked.contains($0.id) }.map(ActivityItem.session)
        return items.sorted { $0.start < $1.start }
    }

    private struct TaskKey: Equatable {
        let date: Date
        let refreshed: Date?
    }

    // MARK: sections

    private var weekStrip: some View {
        let days = (0..<7).reversed().map { DayFormat.shift(Calendar.current.startOfDay(for: .now), days: -$0) }
        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let strain = state.score(for: day)?.strain
                let selected = Calendar.current.isDate(day, inSameDayAs: model.date)
                Button {
                    model.date = day
                } label: {
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.ryft(.caption))
                            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                        ScoreRing(progress: strain.map { $0 / Self.maxStrain }, size: 36, lineWidth: 3, color: Theme.metricStrain,
                                  accessibilityLabel: Text(day.formatted(.dateTime.weekday(.wide))),
                                  accessibilityValue: Text("Strain \(Fmt.strain(strain))")) {
                            Text(strain.map { String(Int($0.rounded())) } ?? Fmt.placeholder)
                                .font(.ryftNumber(size: 11))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(selected ? Theme.surface : .clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// Day strain on the 0–21 scale, ticks at 10 / 14 / 18, against the 7 days before.
    private var ring: some View {
        let prior = (1...7).compactMap { state.score(for: DayFormat.shift(model.date, days: -$0))?.strain }
        return MetricGauge(spec: .strain, value: score?.strain, size: .large,
                           delta: .against(score?.strain, prior: prior),
                           title: String(localized: "Day strain"))
            .id(model.date) // settle the arc again per day
    }

    /// Steps and active energy for the day (`DayDetail.strain`, else the score).
    private var movement: some View {
        let dayStrain = model.detail?.strain
        let steps = dayStrain?.steps ?? score?.steps
        let kcal = dayStrain?.activeKcal ?? score?.activeKcal
        return HStack(spacing: 10) {
            MetricTile(title: "Steps", value: Fmt.integer(steps.map(Double.init)), systemImage: "figure.walk",
                       tint: MetricSpec.steps.color)
            MetricTile(title: "Active kcal", value: Fmt.integer(kcal.map(Double.init)), systemImage: "flame",
                       tint: MetricSpec.activeKcal.color)
        }
    }

    private var zones: some View {
        let dayStrain = model.detail?.strain
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(title: "Heart-rate zones", trailing: dayStrain.map { "TRIMP \($0.trimp)" }.map { LocalizedStringKey($0) })
                ZoneBar(minutes: dayStrain?.zoneMin.map(Double.init))
            }
        }
    }

    @ViewBuilder
    private var activities: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activities").ryftLabelStyle()
            let items = activityItems
            if items.isEmpty {
                if let error = model.error {
                    InlineMessage(message: error, retry: { await model.load(state: state) })
                } else if model.isLoading {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                } else {
                    InlineMessage(message: String(localized: "No workouts recorded on this day."),
                                  systemImage: "figure.walk")
                    if state.hasNoHealthData { HealthAccessHint() }
                }
            } else {
                ForEach(items) { item in
                    switch item {
                    case .workout(let w, let session):
                        NavigationLink(value: w) { ActivityRow(workout: w, session: session) }
                            .buttonStyle(PressableButtonStyle())
                    case .session(let s):
                        NavigationLink(value: TrainRoute.session(s.id)) { SessionActivityRow(session: s) }
                            .buttonStyle(PressableButtonStyle())
                    }
                }
            }
        }
    }
}

#Preview("Strain · dark") {
    StrainView().previewEnvironment()
}

#Preview("Strain · light") {
    StrainView().previewEnvironment(scheme: .light)
}
