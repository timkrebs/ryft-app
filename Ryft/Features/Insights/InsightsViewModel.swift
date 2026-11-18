import Foundation
import Observation

/// Where the visible insights go on the page (docs/work/2026-11-16-nocturne/design.md §P5-5.1, D5-6): notices and warnings
/// as neutral cards above, the first `info` insight in the recovery tile, the other `info` insights as cards under it. Each
/// keeps the platform's order.
struct InsightsArrangement: Equatable {
    let attention: [Insight]
    let tile: Insight?
    let more: [Insight]

    init(_ visible: [Insight]) {
        attention = visible.filter { $0.severity != .info }
        let info = visible.filter { $0.severity == .info }
        tile = info.first
        more = Array(info.dropFirst())
    }

    var isEmpty: Bool { attention.isEmpty && tile == nil }
}

/// Insight cards (dismissible for the day) and a trend card per metric for the selected range, with the 30-day series
/// behind the usual ranges of readiness, HRV, time asleep and resting HR.
@MainActor
@Observable
final class InsightsViewModel {
    private let state: AppState

    var range: TrendRange = .month
    /// A deep link's metric; the view opens its card, scrolls to it and clears it (`openFocused()`).
    var focusedMetric: TrendMetric?
    /// The cards open in place (§P5-5.2, D5-8). Kept here, so a rebuilt tab keeps them.
    private(set) var expanded: Set<TrendMetric> = []

    /// Bumped by each `load()`. `.task(id:)` starts the new range's load before the old one unwinds, so only the newest
    /// load sets `isLoadingTrends` and `loadedRange`.
    @ObservationIgnored private var loadGeneration = 0
    /// The newest load is running.
    private(set) var isLoadingTrends = false
    /// The range whose newest load finished; until then a card with nothing cached is pending, not "Not loaded".
    private(set) var loadedRange: TrendRange?
    /// A card with nothing cached waits for this page's read of the selected range.
    var trendsPending: Bool { isLoadingTrends || loadedRange != range }

    /// Behaviors section (M5); nil in tests that don't need it.
    let journal: JournalStore?

    init(state: AppState, journal: JournalStore? = nil) {
        self.state = state
        self.journal = journal
    }

    /// The range for VoiceOver and the menu: "7 days".
    static func rangeTitle(_ r: TrendRange) -> String {
        switch r {
        case .week: return String(localized: "7 days")
        case .month: return String(localized: "30 days")
        case .quarter: return String(localized: "90 days")
        }
    }

    /// The range on its segment: "7 D".
    static func rangeShortTitle(_ r: TrendRange) -> String {
        switch r {
        case .week: return String(localized: "7 D", comment: "Insights' range control: 7 days.")
        case .month: return String(localized: "30 D", comment: "Insights' range control: 30 days.")
        case .quarter: return String(localized: "90 D", comment: "Insights' range control: 90 days.")
        }
    }

    // MARK: the page's state

    var hasDataSource: Bool { state.hasDataSource }
    var isDemo: Bool { state.isDemo }
    /// The shared offline / error card (Today's), 12 under the header; the cards keep their cached data.
    var refreshIssue: RefreshIssue? { state.refreshIssue }

    func signIn() async { await state.signInAgain() }

    // MARK: insights

    var visibleInsights: [Insight] { state.visibleInsights }

    var arrangement: InsightsArrangement { InsightsArrangement(visibleInsights) }

    /// Shown instead of cards: nothing came, or everything was dismissed today.
    var emptyMessage: String? {
        guard visibleInsights.isEmpty else { return nil }
        return state.insights.isEmpty
            ? String(localized: "Nothing stands out today. Insights appear when your data shifts.")
            : String(localized: "All caught up for today.")
    }

    func dismiss(_ insight: Insight) { state.dismiss(insight) }

    /// Where a card leads (`AppRoute.forInsight`); Behaviors only once the journal is live.
    func route(for insight: Insight) -> AppRoute? {
        let route = AppRoute.forInsight(insight)
        return route == .insightsBehaviors && !showsBehaviors ? nil : route
    }

    func canOpen(_ insight: Insight) -> Bool { route(for: insight) != nil }

    /// The journal is live and the impacts have answered.
    var showsBehaviors: Bool { journal?.isLive == true && journal?.impacts != nil }
    var impacts: BehaviorImpacts? { showsBehaviors ? journal?.impacts : nil }
    /// Scroll to the Behaviors section (an insight or a deep link).
    var focusesBehaviors = false
    static let behaviorsAnchor = "insights.behaviors"

    // MARK: trends

    /// One metric's card for the selected range: two cached reads at most (the range's series, and the 30-day one behind a
    /// usual range). Nothing cached is pending while this page's read of the range, or any other read (`AppState.isLoading`),
    /// runs; "Not loaded" after.
    /// `isStale`: the page's refresh issue, read once for all cards.
    func card(_ metric: TrendMetric, isStale: Bool? = nil) -> TrendCardContent {
        let own = state.cachedTrend(metric, range: range)
        let month = metric.hasBand ? (range == .month ? own : state.cachedTrend(metric, range: .month)) : nil
        return TrendCardContent.make(metric, range: range, series: own, monthly: month,
                                     isLoading: trendsPending || state.isLoading,
                                     isStale: isStale ?? (refreshIssue != nil), today: state.env.clock.now())
    }

    /// Readiness, HRV and time asleep (the board's), then the other eleven under "More trends": every metric, so every deep
    /// link lands on a card.
    var boardCards: [TrendCardContent] { cards(TrendMetric.boardOrder) }
    var moreCards: [TrendCardContent] { cards(TrendMetric.moreOrder) }

    private func cards(_ metrics: [TrendMetric]) -> [TrendCardContent] {
        let stale = refreshIssue != nil
        return metrics.map { card($0, isStale: stale) }
    }

    func isExpanded(_ metric: TrendMetric) -> Bool { expanded.contains(metric) }

    /// A tap on a card opens or closes it.
    func toggle(_ metric: TrendMetric) {
        if expanded.contains(metric) { expanded.remove(metric) } else { expanded.insert(metric) }
    }

    /// A deep link's metric: its card opens, and the view scrolls to it. Clears `focusedMetric`.
    func openFocused() -> TrendMetric? {
        guard let metric = focusedMetric else { return nil }
        expanded.insert(metric)
        focusedMetric = nil
        return metric
    }

    /// Revalidates every series (each skipped while fresh, 1 h) and the 30-day series behind the usual ranges, alongside
    /// the journal's reads. Only the newest load marks the range loaded.
    func load() async {
        guard state.hasDataSource else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoadingTrends = true
        async let journalLoaded: Void = loadJournal()
        let state = state
        let r = range
        await withTaskGroup(of: Void.self) { group in
            for m in TrendMetric.allCases {
                group.addTask { _ = await state.trend(m, range: r) }
            }
            if r != .month {
                for m in TrendMetric.banded {
                    group.addTask { _ = await state.trend(m, range: .month) }
                }
            }
        }
        if generation == loadGeneration {
            isLoadingTrends = false
            // A cancelled load (the page went away) leaves the range unanswered: pending again on return.
            if !Task.isCancelled { loadedRange = r }
        }
        await journalLoaded
    }

    private func loadJournal() async {
        guard let journal else { return }
        if journal.availability == .unknown { await journal.load() }
        await journal.loadImpacts()
    }
}
