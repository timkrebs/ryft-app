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
    @StateObject private var model = StrainViewModel()
    @State private var path: [Workout] = []
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
                activities
            }
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
        }
        .task(id: TaskKey(date: model.date, refreshed: state.lastUpdated)) {
            await model.load(state: state)
            if autoOpen, let first = model.detail?.workouts.first {
                autoOpen = false
                path = [first]
            }
        }
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
                        ScoreRing(progress: strain.map { $0 / Self.maxStrain }, size: 36, lineWidth: 3, glow: false,
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

    private var ring: some View {
        let strain = score?.strain
        return ScoreRing(progress: strain.map { $0 / Self.maxStrain }, size: 200, lineWidth: 10,
                         accessibilityLabel: Text("Strain"),
                         accessibilityValue: strain.map { Text("\(Fmt.strain($0)) of 21") } ?? Text("No data")) {
            VStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)
                CountingText(value: strain, format: Fmt.strain)
                    .font(.ryftNumber(size: 50))
                    .foregroundStyle(strain == nil ? Theme.textTertiary : Theme.textPrimary)
                Text("Day strain · of 21")
                    .font(.ryftNumber(size: 9, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .id(model.date) // re-run the ring animation per day
    }

    /// Steps and active energy for the day (`DayDetail.strain`, else the score).
    private var movement: some View {
        let dayStrain = model.detail?.strain
        let steps = dayStrain?.steps ?? score?.steps
        let kcal = dayStrain?.activeKcal ?? score?.activeKcal
        return HStack(spacing: 10) {
            MetricTile(title: "Steps", value: Fmt.integer(steps.map(Double.init)), systemImage: "figure.walk")
            MetricTile(title: "Active kcal", value: Fmt.integer(kcal.map(Double.init)), systemImage: "flame")
        }
    }

    private var zones: some View {
        let dayStrain = model.detail?.strain
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(title: "Heart-rate zones", trailing: dayStrain.map { "TRIMP \($0.trimp)" }.map { LocalizedStringKey($0) })
                ZoneMinutesView(minutes: dayStrain?.zoneMin.map(Double.init))
            }
        }
    }

    @ViewBuilder
    private var activities: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activities").ryftLabelStyle()
            let workouts = model.detail?.workouts ?? []
            if workouts.isEmpty {
                if let error = model.error {
                    InlineMessage(message: error, retry: { await model.load(state: state) })
                } else if model.isLoading {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                } else {
                    InlineMessage(message: String(localized: "No workouts recorded on this day."),
                                  systemImage: "figure.walk")
                }
            } else {
                ForEach(workouts) { w in
                    NavigationLink(value: w) { ActivityRow(workout: w) }
                        .buttonStyle(PressableButtonStyle())
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
