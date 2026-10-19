import Foundation
import Observation

/// Insight cards (dismissible for the day) and a trend series per metric for the
/// selected range, plus the 30-day series behind the personal-range bands.
@MainActor
@Observable
final class InsightsViewModel {
    private let state: AppState

    var range: TrendRange = .month

    /// Each metric's series for the selected range, as cached (SwiftData).
    var series: [TrendMetric: TrendSeries] {
        Dictionary(uniqueKeysWithValues: TrendMetric.allCases.compactMap { m in
            state.cachedTrend(m, range: range).map { (m, $0) }
        })
    }

    /// 30-day series behind the personal-range bands (HRV, resting HR), whatever the range.
    var monthly: [TrendMetric: TrendSeries] {
        Dictionary(uniqueKeysWithValues: TrendMetric.allCases.filter(\.showsPersonalRange).compactMap { m in
            state.cachedTrend(m, range: .month).map { (m, $0) }
        })
    }

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

    /// Revalidates every series (each skipped while fresh, 1 h) and the 30-day bands.
    func load() async {
        guard state.hasDataSource else { return }
        let state = state
        let r = range
        await withTaskGroup(of: Void.self) { group in
            for m in TrendMetric.allCases {
                group.addTask { _ = await state.trend(m, range: r) }
            }
            if r != .month {
                for m in TrendMetric.allCases where m.showsPersonalRange {
                    group.addTask { _ = await state.trend(m, range: .month) }
                }
            }
        }
    }
}
