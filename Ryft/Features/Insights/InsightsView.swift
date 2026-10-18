import SwiftUI

extension TrendMetric {
    var title: String {
        switch self {
        case .readiness: return String(localized: "Readiness")
        case .recovery: return String(localized: "Recovery")
        case .strain: return String(localized: "Strain")
        case .sleep: return String(localized: "Sleep")
        case .hrv: return String(localized: "HRV")
        case .rhr: return String(localized: "Resting HR")
        }
    }

    var color: Color {
        switch self {
        case .readiness, .strain, .hrv: return Theme.accent
        case .recovery: return Theme.accentSecondary
        case .sleep: return Theme.stageLight
        case .rhr: return Theme.alert
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .readiness: return Fmt.integer(v)
        case .recovery: return Fmt.percent(v)
        case .strain: return Fmt.strain(v)
        case .sleep: return Fmt.duration(minutes: Int(v.rounded()))
        case .hrv: return "\(Fmt.integer(v)) ms"
        case .rhr: return "\(Fmt.integer(v)) bpm"
        }
    }
}

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published var range: TrendRange = .month
    @Published private(set) var series: [TrendMetric: TrendSeries] = [:]

    func load(state: AppState) async {
        // Instant paint from the loaded history, then the platform's series.
        for m in TrendMetric.allCases where series[m]?.range != range.rawValue {
            series[m] = state.derivedTrend(m, range: range)
        }
        guard state.hasDataSource else { return }
        await withTaskGroup(of: (TrendMetric, TrendSeries).self) { group in
            for m in TrendMetric.allCases {
                let r = range
                group.addTask { await (m, state.trend(m, range: r)) }
            }
            for await (m, s) in group where s.range == range.rawValue || s.range.isEmpty {
                series[m] = s
            }
        }
    }
}

/// Insight cards (dismissible for the day) and trend charts for every metric.
struct InsightsView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var model = InsightsViewModel()

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                Text("Insights")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                insights
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trends").ryftLabelStyle()
                    SegmentedPicker(selection: $model.range, options: TrendRange.allCases) { r in
                        switch r {
                        case .week: return String(localized: "7 days")
                        case .month: return String(localized: "30 days")
                        case .quarter: return String(localized: "90 days")
                        }
                    }
                }
                ForEach(TrendMetric.allCases) { metric in
                    TrendCard(metric: metric, series: model.series[metric])
                }
            }
        }
        .task(id: TaskKey(range: model.range, refreshed: state.lastUpdated)) { await model.load(state: state) }
    }

    private struct TaskKey: Equatable {
        let range: TrendRange
        let refreshed: Date?
    }

    @ViewBuilder
    private var insights: some View {
        let visible = state.visibleInsights
        VStack(spacing: 12) {
            if visible.isEmpty {
                InlineMessage(message: state.insights.isEmpty
                              ? String(localized: "Nothing stands out today. Insights appear when your data shifts.")
                              : String(localized: "All caught up for today."),
                              systemImage: "checkmark.circle")
            } else {
                ForEach(visible) { insight in
                    InsightCard(insight: insight) {
                        withAnimation(.easeOut(duration: 0.25)) { state.dismiss(insight) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            if !state.insightsFromPlatform && !state.insights.isEmpty {
                Text("Computed on your phone from your daily scores.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct TrendCard: View {
    let metric: TrendMetric
    let series: TrendSeries?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title)
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(latest.map(metric.format) ?? Fmt.placeholder)
                        .font(.ryft(.headline))
                        .monospacedDigit()
                        .foregroundStyle(metric.color)
                }
                TrendChart(points: series?.points ?? [], title: metric.title, color: metric.color,
                           baseline: metric == .hrv ? series?.baseline : nil,
                           showsAxes: true, interactive: true, height: 150, valueText: metric.format)
                HStack(spacing: 16) {
                    summary("Avg", series?.avg)
                    summary("Min", series?.min)
                    summary("Max", series?.max)
                    Spacer()
                }
            }
        }
    }

    private var latest: Double? { series?.points.last { $0.value != nil }?.value }

    private func summary(_ title: LocalizedStringKey, _ value: Double?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
            Text(value.map(metric.format) ?? Fmt.placeholder)
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Insights · dark") {
    InsightsView().previewEnvironment()
}

#Preview("Insights · light") {
    InsightsView().previewEnvironment(scheme: .light)
}
