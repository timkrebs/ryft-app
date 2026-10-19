import SwiftUI

extension TrendMetric {
    var title: String { spec.title }
    var color: Color { spec.color }
    func format(_ v: Double) -> String { spec.text(v) }

    /// Metrics with a personal baseline get the 30-day range as a band.
    var showsPersonalRange: Bool { self == .hrv || self == .rhr }
}

/// Insight cards (dismissible for the day) and trend charts for every metric.
struct InsightsView: View {
    @Environment(AppState.self) private var state
    @Environment(ScreenModels.self) private var screens

    private var model: InsightsViewModel { screens.insights }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                        SegmentedPicker(selection: Bindable(model).range, options: TrendRange.allCases,
                                        title: InsightsViewModel.rangeTitle)
                    }
                    ForEach(TrendMetric.allCases) { metric in
                        TrendCard(metric: metric, range: model.range, series: model.series[metric],
                                  band: model.band(for: metric))
                            .id(metric)
                    }
                }
                // A deep link to a metric: scroll its trend into view.
                .task(id: model.focusedMetric) {
                    guard let metric = model.focusedMetric else { return }
                    withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)) {
                        proxy.scrollTo(metric, anchor: .top)
                    }
                    model.focusedMetric = nil
                }
            }
        }
        .task(id: TaskKey(range: model.range, refreshed: state.lastUpdated)) { await model.load() }
    }

    private struct TaskKey: Equatable {
        let range: TrendRange
        let refreshed: Date?
    }

    @ViewBuilder
    private var insights: some View {
        VStack(spacing: 12) {
            if let empty = model.emptyMessage {
                InlineMessage(message: empty, systemImage: "checkmark.circle")
            } else {
                ForEach(model.visibleInsights) { insight in
                    InsightCard(insight: insight) {
                        withAnimation(.easeOut(duration: 0.25)) { model.dismiss(insight) }
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
    let band: ClosedRange<Double>?

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
