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
                            ZoneBar(minutes: zones)
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
                ChartHeader(spec: .heartRate, value: workout.avgHr, deltaReference: nil,
                            window: Fmt.duration(seconds: workout.duration),
                            valueOverride: workout.avgHr.map { String(localized: "avg \(Int($0.rounded())) bpm") })
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

/// Beats per minute over the workout: 1.5 pt linear line, no fill, the average
/// as a dashed reference, the peak marked, nice bpm bounds, clock-time ticks.
private struct HeartRateChart: View {
    let points: [HRPoint]
    let average: Double?

    @State private var selection: Date?

    private var selected: HRPoint? {
        guard let selection else { return nil }
        return points.min { abs($0.t.timeIntervalSince(selection)) < abs($1.t.timeIntervalSince(selection)) }
    }

    private var timeTicks: [Date] {
        guard let first = points.first?.t, let last = points.last?.t else { return [] }
        let minutes = last.timeIntervalSince(first) / 60
        // 10 / 15 / 30 / 60-minute steps, at most five ticks, on round clock times.
        let step = [10.0, 15, 30, 60, 120].first { minutes / $0 <= 4 } ?? 120
        let start = (first.timeIntervalSinceReferenceDate / (step * 60)).rounded(.up) * step * 60
        return stride(from: start, through: last.timeIntervalSinceReferenceDate, by: step * 60)
            .map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    var body: some View {
        let spec = MetricSpec.heartRate
        let scale = ChartStyle.scale(for: points.map(\.bpm) + [average].compactMap { $0 }, spec: spec)
        let peak = points.max { $0.bpm < $1.bpm }
        let selected = selected
        Chart {
            if let average {
                BaselineRule(value: average, label: String(localized: "avg \(Int(average.rounded())) bpm"))
            }
            ForEach(points, id: \.t) { p in
                LineMark(x: .value("Time", p.t), y: .value("BPM", p.bpm))
                    .interpolationMethod(.linear)
                    .foregroundStyle(spec.color)
                    .lineStyle(ChartStyle.line)
            }
            if let s = selected {
                RuleMark(x: .value("Time", s.t))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ScrubReadout(value: "\(Int(s.bpm)) bpm", date: Fmt.time(s.t),
                                     delta: average.map { avg in
                                         let d = Int((s.bpm - avg).rounded())
                                         return String(localized: "\(d >= 0 ? "+" : "−")\(abs(d)) vs average")
                                     })
                    }
                PointMark(x: .value("Time", s.t), y: .value("BPM", s.bpm))
                    .foregroundStyle(spec.color)
                    .symbolSize(ChartStyle.marker)
            } else if let peak {
                PointMark(x: .value("Time", peak.t), y: .value("BPM", peak.bpm))
                    .foregroundStyle(spec.color)
                    .symbolSize(ChartStyle.marker)
                    .annotation(position: .top, spacing: 3) {
                        Text("peak \(Int(peak.bpm))")
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textPrimary)
                    }
            }
        }
        .chartYScale(domain: scale.domain)
        .chartXScale(domain: (points.first?.t ?? .now)...(points.last?.t ?? .now))
        .chartXSelection(value: $selection)
        .chartXAxis { ChartStyle.xAxis(timeTicks, format: .dateTime.hour().minute()) }
        .chartYAxis { ChartStyle.yAxis(scale.ticks, unit: "bpm", label: spec.axis) }
        .frame(height: 180)
        .chartAppear()
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
