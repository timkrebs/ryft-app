import SwiftUI
import Charts

/// One workout: HR over time from `/v1/workouts/{id}`, zones, TRIMP, calories, distance.
struct WorkoutDetailView: View {
    let workout: Workout

    @EnvironmentObject private var state: AppState
    @State private var detail: WorkoutDetail?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Metrics.sectionSpacing) {
                header
                stats
                heartRate
                if let zones = detail?.zoneMin, zones.count == 5 {
                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            CardHeader(title: "Heart-rate zones")
                            ZoneMinutesView(minutes: zones)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(ActivityStyle.name(for: workout.activity))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { detail = await state.workoutDetail(workout) }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: ActivityStyle.icon(for: workout.activity))
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Theme.accent.opacity(0.12), in: Circle())
            Text(ActivityStyle.name(for: workout.activity))
                .font(.ryft(.title))
                .foregroundStyle(Theme.textPrimary)
            Text("\(workout.start.formatted(.dateTime.weekday(.wide).day().month())) · \(Fmt.time(workout.start))–\(Fmt.time(workout.end))")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            Text(workout.source)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var stats: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 10) {
            stat("Strain", Fmt.strain(workout.strain))
            stat("Duration", Fmt.duration(seconds: workout.duration))
            stat("TRIMP", Fmt.integer(detail?.trimp))
            stat("Avg HR", Fmt.integer(workout.avgHr))
            stat("Max HR", Fmt.integer(workout.maxHr))
            stat("Calories", Fmt.integer(workout.energyKcal))
            if workout.distanceM != nil {
                stat("Distance", Fmt.distance(meters: workout.distanceM))
            }
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(title).ryftLabelStyle().lineLimit(1).minimumScaleFactor(0.8)
            Text(value)
                .font(.ryft(.headline))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var heartRate: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Heart rate", trailing: workout.avgHr.map { LocalizedStringKey("avg \(Int($0.rounded())) bpm") })
                if let hr = detail?.hr, hr.count > 1 {
                    HeartRateChart(points: hr, average: workout.avgHr)
                } else if detail == nil {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    Text("No heart-rate series available for this workout.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
    }
}

private struct HeartRateChart: View {
    let points: [HRPoint]
    let average: Double?

    @State private var selection: Date?

    private var domain: ClosedRange<Double> {
        let values = points.map(\.bpm)
        return ((values.min() ?? 60) - 10)...((values.max() ?? 180) + 10)
    }

    private var selected: HRPoint? {
        guard let selection else { return nil }
        return points.min { abs($0.t.timeIntervalSince(selection)) < abs($1.t.timeIntervalSince(selection)) }
    }

    var body: some View {
        let domain = domain
        Chart {
            ForEach(points, id: \.t) { p in
                AreaMark(x: .value("Time", p.t), yStart: .value("Floor", domain.lowerBound), yEnd: .value("BPM", p.bpm))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.alert.opacity(0.1))
                LineMark(x: .value("Time", p.t), y: .value("BPM", p.bpm))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.alert)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if let s = selected {
                RuleMark(x: .value("Time", s.t))
                    .foregroundStyle(Theme.textTertiary)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(Int(s.bpm)) bpm · \(Fmt.time(s.t))")
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.surfaceRaised, in: Capsule())
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.separator)
                AxisValueLabel().font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart rate over time"))
        .accessibilityValue(Text("Peak \(Int(points.map(\.bpm).max() ?? 0)) bpm"))
        .accessibilityChartDescriptor(SeriesChartDescriptor(title: String(localized: "Heart rate"), valueName: "bpm",
                                                            points: points.map { ($0.t, $0.bpm) },
                                                            valueText: { "\(Int($0)) bpm" }))
    }
}

#Preview("Workout · dark") {
    NavigationStack {
        WorkoutDetailView(workout: MockData.todayDetail.workouts[0])
    }
    .previewEnvironment()
}

#Preview("Workout · light") {
    NavigationStack {
        WorkoutDetailView(workout: MockData.todayDetail.workouts[0])
    }
    .previewEnvironment(scheme: .light)
}
