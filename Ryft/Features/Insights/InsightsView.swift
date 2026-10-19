import SwiftUI

extension TrendMetric {
    var title: String { spec.title }
    var color: Color { spec.color }
    func format(_ v: Double) -> String { spec.text(v) }

    /// Metrics with a personal baseline get the 30-day range as a band.
    var showsPersonalRange: Bool { self == .hrv || self == .rhr }
}

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published var range: TrendRange = .month
    @Published private(set) var series: [TrendMetric: TrendSeries] = [:]
    /// 30-day series behind the personal-range bands (HRV, resting HR), whatever the range.
    @Published private(set) var monthly: [TrendMetric: TrendSeries] = [:]

    func load(state: AppState) async {
        // Instant paint from what's already loaded, then the platform's series.
        for m in TrendMetric.allCases where series[m]?.range != range.rawValue {
            series[m] = state.cachedTrend(m, range: range)
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
        for m in TrendMetric.allCases where m.showsPersonalRange {
            monthly[m] = range == .month ? series[m] : await state.trend(m, range: .month)
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
                // Guideline 1.4.1: observations, not diagnoses; see a doctor for concerns.
                Label("RYFT is a wellness tool, not a medical device. Talk to a doctor about health concerns.",
                      systemImage: "stethoscope")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    TrendCard(metric: metric, range: model.range, series: model.series[metric],
                              monthly: model.monthly[metric])
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
        }
    }
}

private struct TrendCard: View {
    let metric: TrendMetric
    let range: TrendRange
    let series: TrendSeries?
    let monthly: TrendSeries?

    /// The 30-day min–max until the API serves a σ (`docs/API_REQUESTS.md`).
    private var band: ClosedRange<Double>? {
        guard metric.showsPersonalRange, let lo = monthly?.min, let hi = monthly?.max, lo < hi else { return nil }
        return lo...hi
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                TrendChart(points: series?.points ?? [], spec: metric.spec, window: ChartWindow(range),
                           end: series?.to.flatMap(DayFormat.date(from:)),
                           baseline: metric.showsPersonalRange ? series?.baseline : nil,
                           band: band, height: 150)
                HStack(spacing: 16) {
                    summary("Avg", series?.avg)
                    summary("Min", series?.min)
                    summary("Max", series?.max)
                    Spacer()
                    if band != nil {
                        Text("Band: 30-day range")
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

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
