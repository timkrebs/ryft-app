import Foundation
import Observation

/// Insight cards (dismissible for the day) and a trend series per metric for the
/// selected range, plus the 30-day series behind the personal-range bands.
@MainActor
@Observable
final class InsightsViewModel {
    private let state: AppState

    var range: TrendRange = .month
    private(set) var series: [TrendMetric: TrendSeries] = [:]
    /// 30-day series behind the personal-range bands (HRV, resting HR), whatever the range.
    private(set) var monthly: [TrendMetric: TrendSeries] = [:]

    init(state: AppState) {
        self.state = state
    }

    static func rangeTitle(_ r: TrendRange) -> String {
        switch r {
        case .week: return String(localized: "7 days")
        case .month: return String(localized: "30 days")
        case .quarter: return String(localized: "90 days")
        }
    }

    var visibleInsights: [Insight] { state.visibleInsights }

    /// Shown instead of cards: nothing came, or everything was dismissed today.
    var emptyMessage: String? {
        guard visibleInsights.isEmpty else { return nil }
        return state.insights.isEmpty
            ? String(localized: "Nothing stands out today. Insights appear when your data shifts.")
            : String(localized: "All caught up for today.")
    }

    func dismiss(_ insight: Insight) { state.dismiss(insight) }

    /// The 30-day min–max until the API serves a σ (`docs/API_REQUESTS.md`).
    func band(for metric: TrendMetric) -> ClosedRange<Double>? {
        guard metric.showsPersonalRange, let lo = monthly[metric]?.min, let hi = monthly[metric]?.max, lo < hi else {
            return nil
        }
        return lo...hi
    }

    func load() async {
        // Instant paint from what's already loaded, then the platform's series.
        for m in TrendMetric.allCases where series[m]?.range != range.rawValue {
            series[m] = state.cachedTrend(m, range: range)
        }
        guard state.hasDataSource else { return }
        let state = state
        let r = range
        await withTaskGroup(of: (TrendMetric, TrendSeries).self) { group in
            for m in TrendMetric.allCases {
                group.addTask { await (m, state.trend(m, range: r)) }
            }
            for await (m, s) in group where s.range == r.rawValue || s.range.isEmpty {
                series[m] = s
            }
        }
        for m in TrendMetric.allCases where m.showsPersonalRange {
            monthly[m] = r == .month ? series[m] : await state.trend(m, range: .month)
        }
    }
}
