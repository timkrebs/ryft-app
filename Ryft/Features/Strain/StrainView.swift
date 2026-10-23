import SwiftUI

/// Strain ring for the selected day, week strip, zone minutes and activities.
struct StrainView: View {
    @Environment(AppState.self) private var state
    @Environment(ScreenModels.self) private var screens
    @Environment(TrainCoordinator.self) private var coordinator
    @State private var path = NavigationPath()
    /// `-RyftOpenWorkout YES` pushes the first workout once (screenshots).
    @State private var autoOpen = UserDefaults.standard.bool(forKey: "RyftOpenWorkout")

    private var model: StrainViewModel { screens.strain }

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScaffold {
                VStack(spacing: 2) {
                    Text("Strain")
                        .font(.ryft(.title))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(model.title)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
                weekStrip
                ring
                movement
                zones
                if model.isToday && model.showsTrain { TrainSection() }
                activities
            }
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
            .trainDestinations()
        }
        .sheet(isPresented: Bindable(coordinator).showsStart) { StartWorkoutSheet() }
        .task(id: TaskKey(date: model.date, refreshed: state.lastUpdated)) {
            await model.load()
            if autoOpen, let first = model.detail?.workouts.first {
                autoOpen = false
                path.append(first)
            }
        }
        // A deep link to a session or plan: on top of a fresh stack.
        .task(id: model.requestedRoute) {
            guard let route = model.requestedRoute else { return }
            path = NavigationPath()
            path.append(route)
            model.requestedRoute = nil
        }
    }

    private struct TaskKey: Equatable {
        let date: Date
        let refreshed: Date?
    }

    // MARK: sections

    private var weekStrip: some View {
        DateStrip(days: model.week) { model.select($0) }
    }

    /// Day strain on the 0–21 scale, ticks at 10 / 14 / 18, against the 7 days before.
    private var ring: some View {
        VStack(spacing: 8) {
            MetricGauge(spec: .strain, value: model.strain, size: .large, delta: model.strainDelta,
                        title: String(localized: "Day strain"))
                .id(model.date) // settle the arc again per day
            if let split = model.strainSplitText {
                Text(split)
                    .font(.ryft(.callout).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHint(Text("Split by heart-rate and strength load"))
            }
        }
    }

    /// Steps and active energy for the day (`DayDetail.strain`, else the score).
    private var movement: some View {
        HStack(spacing: 10) {
            MetricTile(title: "Steps", value: model.stepsText, systemImage: "figure.walk", tint: MetricSpec.steps.color)
            MetricTile(title: "Active kcal", value: model.activeKcalText, systemImage: "flame",
                       tint: MetricSpec.activeKcal.color)
        }
    }

    private var zones: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(title: "Heart-rate zones", trailing: model.trimpText.map { LocalizedStringKey($0) })
                ZoneBar(minutes: model.zoneMinutes)
            }
        }
    }

    @ViewBuilder
    private var activities: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activities").ryftLabelStyle()
            if model.showsMyDayList {
                myDayList
            } else {
                workoutList
            }
        }
    }

    /// The list without `today.my_day`: workouts merged with their logged sessions (`model.activities`).
    @ViewBuilder
    private var workoutList: some View {
        let items = model.activities
        if items.isEmpty {
            if let error = model.error {
                InlineMessage(message: error, retry: { await model.load() })
            } else if model.isLoading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
            } else {
                InlineMessage(message: String(localized: "No workouts recorded on this day."),
                              systemImage: "figure.walk")
                if model.hasNoHealthData { HealthAccessHint() }
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

    /// `today.my_day`: My Day's rows without the night (ADR 0006), RYFT's activities among them. A merged activity
    /// opens its tracker's workout; other activities open nothing until A2's detail exists.
    @ViewBuilder
    private var myDayList: some View {
        let items = model.dayItems
        if items.isEmpty {
            if let error = model.error {
                InlineMessage(message: error, retry: { await model.load() })
            } else if model.isLoading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
            } else {
                InlineMessage(message: String(localized: "No workouts recorded on this day."),
                              systemImage: "figure.walk")
                if model.hasNoHealthData { HealthAccessHint() }
            }
        } else {
            ForEach(items) { item in
                switch item.kind {
                case .workout(let id):
                    if let w = model.workout(id) {
                        NavigationLink(value: w) { row(item) }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityHint(Text("Opens the workout", comment: "VoiceOver hint: the row opens the workout's detail."))
                            .accessibilityIdentifier("strain.row.\(item.id)")
                    }
                case .session(let id):
                    NavigationLink(value: TrainRoute.session(id)) { row(item) }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityHint(Text("Opens the session", comment: "VoiceOver: a My Day row opens the Train session."))
                        .accessibilityIdentifier("strain.row.\(item.id)")
                case .activity:
                    if let id = item.mergedWorkout, let w = model.workout(id) {
                        NavigationLink(value: w) { row(item) }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityHint(Text("Opens the workout", comment: "VoiceOver hint: the row opens the workout's detail."))
                            .accessibilityIdentifier("strain.row.\(item.id)")
                    } else {
                        MyDayRow(item: item, style: .tile, showsLoad: true)
                            .accessibilityIdentifier("strain.row.\(item.id)")
                    }
                case .sleep, .missingSleep:
                    MyDayRow(item: item, style: .tile, showsLoad: true)
                        .accessibilityIdentifier("strain.row.\(item.id)")
                }
            }
        }
    }

    private func row(_ item: MyDayItem) -> some View {
        MyDayRow(item: item, style: .tile, showsChevron: true, showsLoad: true)
    }
}

#Preview("Strain · dark") {
    StrainView().previewEnvironment()
}

#Preview("Strain · light") {
    StrainView().previewEnvironment(scheme: .light)
}

#Preview("Strain · My Day list (today.my_day)") {
    StrainView().previewEnvironment(.preview(flags: [.todayMyDay: true]))
}

#Preview("Strain · My Day list (today.my_day) · light") {
    StrainView().previewEnvironment(.preview(flags: [.todayMyDay: true]), scheme: .light)
}
