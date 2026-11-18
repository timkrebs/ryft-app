import SwiftUI

/// Insights in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-5; build plan F4, F5, F7): the title with the range control,
/// the attention cards (notices and warnings), the recovery tile with the first insight, the other insights, Behaviors, the
/// trend cards (the board's three, then "More trends") and the wellness note last. Layout only: everything shown comes from
/// `InsightsViewModel` through `InsightsPageContent`.
struct InsightsView: View {
    @Environment(AppState.self) private var state
    @Environment(ScreenModels.self) private var screens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: InsightsViewModel { screens.insights }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                InsightsPage(content: InsightsPageContent(model), range: Bindable(model).range, actions: actions)
                    // A deep link to a metric: open its card and scroll it into view.
                    .task(id: model.focusedMetric) {
                        guard let metric = model.openFocused() else { return }
                        withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)) {
                            proxy.scrollTo(metric, anchor: .top)
                        }
                    }
                    // The behavior-impact insight, or a link to /insights/behaviors.
                    .task(id: model.focusesBehaviors) {
                        guard model.focusesBehaviors else { return }
                        withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)) {
                            proxy.scrollTo(InsightsViewModel.behaviorsAnchor, anchor: .top)
                        }
                        model.focusesBehaviors = false
                    }
            }
        }
        .task(id: TaskKey(range: model.range, refreshed: state.lastUpdated)) { await model.load() }
    }

    private struct TaskKey: Equatable {
        let range: TrendRange
        let refreshed: Date?
    }

    private var actions: InsightsPageActions {
        InsightsPageActions(
            dismiss: { model.dismiss($0) },
            open: { insight in
                model.route(for: insight).map { route -> () -> Void in { Task { await screens.router.open(route) } } }
            },
            toggle: { model.toggle($0) },
            retry: { await screens.pullToRefresh() },
            signIn: { await model.signIn() })
    }
}

/// What the page shows, as values: previews and tests build every state from it.
struct InsightsPageContent {
    var hasDataSource = true
    var isDemo = false
    /// The shared offline / error card under the header; the cards below keep their cached data.
    var issue: RefreshIssue?
    var arrangement: InsightsArrangement
    /// "Nothing stands out today…" / "All caught up for today." when no insight is visible.
    var emptyMessage: String?
    var impacts: BehaviorImpacts?
    var boardCards: [TrendCardContent]
    var moreCards: [TrendCardContent]
    var expanded: Set<TrendMetric> = []

    init(hasDataSource: Bool = true, isDemo: Bool = false, issue: RefreshIssue? = nil, arrangement: InsightsArrangement,
         emptyMessage: String? = nil, impacts: BehaviorImpacts? = nil, boardCards: [TrendCardContent],
         moreCards: [TrendCardContent], expanded: Set<TrendMetric> = []) {
        self.hasDataSource = hasDataSource
        self.isDemo = isDemo
        self.issue = issue
        self.arrangement = arrangement
        self.emptyMessage = emptyMessage
        self.impacts = impacts
        self.boardCards = boardCards
        self.moreCards = moreCards
        self.expanded = expanded
    }

    @MainActor
    init(_ model: InsightsViewModel) {
        self.init(hasDataSource: model.hasDataSource, isDemo: model.isDemo, issue: model.refreshIssue,
                  arrangement: model.arrangement, emptyMessage: model.emptyMessage, impacts: model.impacts,
                  boardCards: model.boardCards, moreCards: model.moreCards, expanded: model.expanded)
    }

    /// The page's blocks under the header, in order (§P5-5.1 rows 2–7).
    var blocks: [InsightsLayout.Block] {
        guard hasDataSource else { return [] }
        var blocks: [InsightsLayout.Block] = []
        if issue != nil { blocks.append(.issue) }
        if !arrangement.attention.isEmpty { blocks.append(.attention) }
        if arrangement.tile != nil { blocks.append(.tile) }
        if arrangement.isEmpty, emptyMessage != nil { blocks.append(.empty) }
        if !arrangement.more.isEmpty { blocks.append(.more) }
        if impacts != nil { blocks.append(.behaviors) }
        blocks.append(.trends)
        if !moreCards.isEmpty { blocks.append(.moreTrends) }
        return blocks
    }

    /// The tile is the only insight block and Behaviors is not there: the board's 12 between the tile and the trend cards.
    var tileOnly: Bool {
        arrangement.tile != nil && arrangement.attention.isEmpty && arrangement.more.isEmpty && impacts == nil
    }
}

/// What the page's controls do.
struct InsightsPageActions {
    var dismiss: (Insight) -> Void = { _ in }
    /// The insight's link, or `nil` when it leads nowhere.
    var open: (Insight) -> (() -> Void)? = { _ in nil }
    var toggle: (TrendMetric) -> Void = { _ in }
    var retry: () async -> Void = {}
    var signIn: () async -> Void = {}
}

/// The page: the header, the blocks with their gaps, the footer.
struct InsightsPage: View {
    let content: InsightsPageContent
    @Binding var range: TrendRange
    var actions = InsightsPageActions()
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScreenScaffold(showsHeader: false) {
            VStack(spacing: 0) {
                header
                if content.hasDataSource {
                    let blocks = content.blocks
                    ForEach(Array(blocks.enumerated()), id: \.element) { index, block in
                        self.block(block)
                            .padding(.top, InsightsLayout.gap(above: block, below: index == 0 ? .header : blocks[index - 1],
                                                              tileOnly: content.tileOnly))
                    }
                } else {
                    Card {
                        Text("Connect a data source to see trends.", comment: "Insights without a signed-in account or a server.")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("insights.notSetUp")
                    .padding(.top, InsightsLayout.headerToFirstBlock)
                }
                footer
                    .padding(.top, InsightsLayout.sectionGap)
            }
        }
    }

    // MARK: row 1

    private var header: some View {
        ScreenHeader(title: Text("Insights"), trailingLayout: .wide) {
            if content.hasDataSource {
                SegmentedPicker(selection: $range, options: TrendRange.allCases, look: .inkFill, width: .content,
                                spokenTitle: InsightsViewModel.rangeTitle, title: InsightsViewModel.rangeShortTitle)
                    .accessibilityIdentifier("insights.range")
            }
        }
    }

    // MARK: rows 2–6

    @ViewBuilder
    private func block(_ block: InsightsLayout.Block) -> some View {
        switch block {
        case .issue:
            if let issue = content.issue {
                RefreshIssueCard(issue: issue, isDemo: content.isDemo, retry: actions.retry, signIn: actions.signIn)
            }
        case .attention:
            insightCards(content.arrangement.attention)
        case .tile:
            if let insight = content.arrangement.tile {
                InsightTile(insight: insight, onDismiss: { dismiss(insight) }, onOpen: actions.open(insight),
                            reduceTransparency: reduceTransparency)
                    .id(insight.id)
                    .transition(.opacity)
            }
        case .empty:
            if let message = content.emptyMessage {
                Card {
                    Text(message)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("insights.empty")
            }
        case .more:
            insightCards(content.arrangement.more)
        case .behaviors:
            if let impacts = content.impacts {
                BehaviorsSection(impacts: impacts)
                    .id(InsightsViewModel.behaviorsAnchor)
            }
        case .trends:
            trendCards(content.boardCards)
        case .moreTrends:
            VStack(alignment: .leading, spacing: InsightsLayout.labelToCards) {
                Text("More trends", comment: "Insights: the label above the other trend cards.")
                    .ryftLabelStyle()
                    .accessibilityAddTraits(.isHeader)
                trendCards(content.moreCards)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .header, .footer:
            EmptyView()
        }
    }

    private func insightCards(_ insights: [Insight]) -> some View {
        VStack(spacing: InsightsLayout.cardGap) {
            ForEach(insights) { insight in
                InsightCard(insight: insight, onDismiss: { dismiss(insight) }, onOpen: actions.open(insight))
                    .transition(.opacity)
            }
        }
    }

    private func trendCards(_ cards: [TrendCardContent]) -> some View {
        VStack(spacing: InsightsLayout.trendCardGap) {
            ForEach(cards) { card in
                TrendCard(content: card, isExpanded: content.expanded.contains(card.metric)) {
                    withAnimation(Theme.Motion.respecting(reduceMotion)) { actions.toggle(card.metric) }
                }
                .id(card.metric)
            }
        }
    }

    private func dismiss(_ insight: Insight) {
        withAnimation(Theme.Motion.respecting(reduceMotion)) { actions.dismiss(insight) }
    }

    // MARK: row 7

    /// Guideline 1.4.1: observations, not diagnoses; see a doctor for concerns. The page's last line (D5-5, F7).
    private var footer: some View {
        Label("RYFT is a wellness tool, not a medical device. Talk to a doctor about health concerns.", systemImage: "stethoscope")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("insights.disclaimer")
    }
}

// MARK: previews (dark only)

/// The page's states on the demo data, without the network.
enum InsightsPreview {
    /// Every insight's link shows, as on the screen (where each leads to its chart, Behaviors or the session); taps do nothing.
    static let actions = InsightsPageActions(open: { _ in {} })

    /// - Parameters:
    ///   - loading: nothing cached, this page's read in flight (pending cards).
    ///   - notLoaded: nothing cached, and the read answered with nothing (offline, or it failed): "Not loaded".
    ///   - bands: `false` gives the banded cards 6 days of history: "Band needs 7 days of data".
    static func content(range: TrendRange = .month, insights: [Insight] = MockData.insights, dismissedAll: Bool = false,
                        loading: Bool = false, notLoaded: Bool = false, hrvSeries: TrendSeries?? = nil, bands: Bool = true,
                        issue: RefreshIssue? = nil, hasDataSource: Bool = true,
                        expanded: Set<TrendMetric> = []) -> InsightsPageContent {
        let today = Date.now
        func card(_ metric: TrendMetric) -> TrendCardContent {
            let series: TrendSeries? = loading || notLoaded ? nil
                : metric == .hrv ? (hrvSeries ?? MockData.trend(metric, range: range)) : MockData.trend(metric, range: range)
            var monthly = series == nil ? nil : MockData.trend(metric, range: .month)
            if !bands { monthly?.points = Array(MockData.trend(metric, range: .month).points.suffix(7)) }
            return .make(metric, range: range, series: series, monthly: metric.hasBand ? monthly : nil, isLoading: loading,
                         isStale: issue != nil, today: today)
        }
        let visible = dismissedAll ? [] : insights
        let empty = visible.isEmpty
            ? (insights.isEmpty ? String(localized: "Nothing stands out today. Insights appear when your data shifts.")
                                : String(localized: "All caught up for today."))
            : nil
        return InsightsPageContent(hasDataSource: hasDataSource, issue: issue, arrangement: InsightsArrangement(visible),
                                   emptyMessage: empty, boardCards: TrendMetric.boardOrder.map(card),
                                   moreCards: TrendMetric.moreOrder.map(card), expanded: expanded)
    }

    static let onlyTile = MockData.insights.filter { $0.severity == .info }

    /// The trends could not be read for a while: no response since 14:05.
    static var offline: RefreshIssue {
        let at = Calendar.current.date(bySettingHour: 14, minute: 7, second: 0, of: .now) ?? .now
        let error = ResourceError(kind: .transient, status: nil, code: nil, requestID: nil, transport: "timedOut", attempts: 3,
                                  at: at)
        return RefreshIssue(reason: .unreachable, resource: .trends, dataFrom: at.addingTimeInterval(-120), failures: 3,
                            error: error)
    }
}

private struct InsightsPagePreview: View {
    let content: InsightsPageContent
    var reduceTransparency: Bool?
    @State private var range = TrendRange.month

    var body: some View {
        InsightsPage(content: content, range: $range, actions: InsightsPreview.actions, reduceTransparency: reduceTransparency)
            .previewEnvironment()
    }
}

#Preview("Insights") {
    InsightsView().previewEnvironment()
}

#Preview("Insights · scored") {
    InsightsPagePreview(content: InsightsPreview.content())
}

#Preview("Insights · AX3") {
    InsightsPagePreview(content: InsightsPreview.content())
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Insights · only the tile") {
    InsightsPagePreview(content: InsightsPreview.content(insights: InsightsPreview.onlyTile))
}

#Preview("Insights · no insights") {
    InsightsPagePreview(content: InsightsPreview.content(insights: []))
}

#Preview("Insights · loading") {
    InsightsPagePreview(content: InsightsPreview.content(loading: true))
}

#Preview("Insights · no data for HRV") {
    InsightsPagePreview(content: InsightsPreview.content(
        hrvSeries: .some(TrendSeries(metric: "hrv", range: "30d", points: [], avg: nil, min: nil, max: nil, baseline: nil))))
}

#Preview("Insights · calibrating band") {
    InsightsPagePreview(content: InsightsPreview.content(bands: false))
}

#Preview("Insights · offline") {
    InsightsPagePreview(content: InsightsPreview.content(issue: InsightsPreview.offline))
}

#Preview("Insights · offline, not loaded") {
    InsightsPagePreview(content: InsightsPreview.content(notLoaded: true, issue: InsightsPreview.offline))
}

#Preview("Insights · expanded card") {
    InsightsPagePreview(content: InsightsPreview.content(insights: [], expanded: [.readiness]))
}

#Preview("Insights · 7 D") {
    InsightsPagePreview(content: InsightsPreview.content(range: .week))
}

#Preview("Insights · 90 D") {
    InsightsPagePreview(content: InsightsPreview.content(range: .quarter))
}

#Preview("Insights · not set up") {
    InsightsPagePreview(content: InsightsPreview.content(hasDataSource: false))
}

#Preview("Insights · Reduce Transparency") {
    InsightsPagePreview(content: InsightsPreview.content(insights: InsightsPreview.onlyTile), reduceTransparency: true)
}
