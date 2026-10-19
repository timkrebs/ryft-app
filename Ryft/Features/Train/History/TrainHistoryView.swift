import SwiftUI

/// Finished sessions by week, with each week's volume and muscular load.
struct TrainHistoryView: View {
    @Environment(TrainLibrary.self) private var library

    var body: some View {
        TrainHistoryScreen(model: TrainHistoryViewModel(library: library))
    }
}

/// Layout only; the first model handed in is kept for the screen's lifetime.
private struct TrainHistoryScreen: View {
    @State var model: TrainHistoryViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if model.isEmpty {
                    if model.loaded {
                        InlineMessage(message: String(localized: "No workouts logged yet. Finished sessions appear here."),
                                      systemImage: "dumbbell")
                    } else {
                        ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                    }
                }
                ForEach(model.weeks) { week in
                    VStack(alignment: .leading, spacing: 10) {
                        weekHeader(week)
                        ForEach(week.sessions) { s in
                            NavigationLink(value: TrainRoute.session(s.id)) { SessionRow(session: s) }
                                .buttonStyle(PressableButtonStyle())
                        }
                    }
                }
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await model.load() }
        .refreshable { await model.refresh() }
    }

    private func weekHeader(_ week: TrainHistoryViewModel.Week) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(week.title)
                .ryftLabelStyle()
            Spacer()
            Text(week.summary)
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// History row: dumbbell, title, day · duration · volume, load chip.
struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title.isEmpty ? String(localized: "Workout") : session.title)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 6)
            LoadChip(load: session.muscularTrimp)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))]
        if let min = session.durationMin { parts.append(Fmt.duration(minutes: min)) }
        if let v = session.volumeKg { parts.append(Fmt.volume(v)) }
        return parts.joined(separator: " · ")
    }
}

/// A finished session: totals, then each exercise with its sets.
struct SessionDetailView: View {
    let sessionID: UUID
    @Environment(TrainLibrary.self) private var library
    @State private var session: TrainSession?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let s = session {
                    HStack(spacing: 10) {
                        MetricTile(title: "Volume", value: Fmt.volume(s.volumeKg), systemImage: "scalemass")
                        MetricTile(title: "Load", value: Fmt.load(s.muscularTrimp), systemImage: "dumbbell.fill",
                                   tint: Theme.accentSecondary)
                        MetricTile(title: "Strain", value: Fmt.strain(s.strain), systemImage: "bolt.fill")
                    }
                    if !s.notes.isEmpty {
                        Card { Text(s.notes).font(.ryft(.body)).foregroundStyle(Theme.textPrimary) }
                    }
                    ForEach(s.exercises.sorted { $0.position < $1.position }) { e in
                        exerciseCard(e)
                    }
                } else if loaded {
                    InlineMessage(message: String(localized: "This workout couldn't be loaded. Try again when you're online."))
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(session?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            session = await library.session(id: sessionID)
            loaded = true
        }
    }

    private func exerciseCard(_ e: SessionExercise) -> some View {
        let name = library.exercise(id: e.exerciseId)?.name ?? String(localized: "Exercise")
        return NavigationLink(value: TrainRoute.exercise(e.exerciseId)) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    CardHeader(title: LocalizedStringKey(name), showsChevron: false)
                    ForEach(Array(e.sets.sorted { $0.setIndex < $1.setIndex }.enumerated()), id: \.element.id) { i, set in
                        HStack {
                            Text(set.isWarmup ? "W" : "\(i + 1)")
                                .font(.ryftNumber(size: 14))
                                .foregroundStyle(set.isWarmup ? Theme.warning : Theme.textTertiary)
                                .frame(width: 24, alignment: .leading)
                            Text(SetText.short(set))
                                .font(.ryft(.body))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if let rpe = set.rpe {
                                Text("RPE \(Fmt.kgNumber(rpe))")
                                    .font(.ryft(.caption))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text("Opens the exercise's history"))
    }
}

enum SetText {
    /// "100 kg × 5", "× 8", "45 s".
    static func short(_ s: SessionSet) -> String {
        if let d = s.durationSec, s.reps == nil { return String(localized: "\(d) s") }
        switch (s.weightKg, s.reps) {
        case let (kg?, r?): return "\(Fmt.kg(kg)) × \(r)"
        case let (nil, r?): return "× \(r)"
        case let (kg?, nil): return Fmt.kg(kg)
        default: return Fmt.placeholder
        }
    }
}

/// Where Train screens navigate inside a tab's NavigationStack.
enum TrainRoute: Hashable {
    case plans
    case plan(UUID)
    case history
    case session(UUID)
    case exercise(UUID)
}

extension View {
    /// Registers every Train destination on the enclosing NavigationStack.
    func trainDestinations() -> some View {
        navigationDestination(for: TrainRoute.self) { route in
            switch route {
            case .plans: PlansView()
            case .plan(let id): PlanDetailView(planID: id)
            case .history: TrainHistoryView()
            case .session(let id): SessionDetailView(sessionID: id)
            case .exercise(let id): ExerciseDetailView(exerciseID: id)
            }
        }
    }
}

#Preview("History · dark") {
    NavigationStack { TrainHistoryView().trainDestinations() }
        .previewEnvironment()
}

#Preview("History · light") {
    NavigationStack { TrainHistoryView().trainDestinations() }
        .previewEnvironment(scheme: .light)
}

#Preview("Session detail") {
    NavigationStack { SessionDetailView(sessionID: MockTrain.history[MockTrain.history.count - 1].id).trainDestinations() }
        .previewEnvironment()
}
