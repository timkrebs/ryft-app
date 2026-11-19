import Charts
import SwiftUI

/// The exercise page's numbers (PR 6 B §7.3, `b-15`), bottom of one element to the top of the next.
enum ExerciseDetailLayout {
    /// The header → the numeral; the numeral → "Estimated 1RM · kg"; that → the 90-day change.
    nonisolated static let heroGap: CGFloat = 22, captionGap: CGFloat = 12, changeGap: CGFloat = 4
    /// The hero → the chart card.
    nonisolated static let chartGap: CGFloat = 22
    /// The chart card: radius 24, 16 inside; its head → the value line 6, the value line → the chart 8, plus what the PR's
    /// label (the axis style, 13 high at the default size) grows by with Dynamic Type: it hangs above the plot.
    nonisolated static let chartRadius = Theme.Metrics.glowTileRadius, chartPadding: CGFloat = 16
    nonisolated static let chartHeadGap: CGFloat = 6, chartTopGap: CGFloat = 8, prLabelHeight: CGFloat = 13
    /// The chart: 150 high (200 from AX1, so its large labels keep apart); the sentence without a trend in 120.
    nonisolated static let chartHeight: CGFloat = 150, chartHeightLargeText: CGFloat = 200, emptyChartHeight: CGFloat = 120
    /// The value line's number: 26 Light at the default size, growing with Dynamic Type like `.title`.
    nonisolated static let valueSize: CGFloat = 26
    /// The line 1.4 pt with round joins; the PR's dashed rule (the charts' 1 pt baseline) at ink 30 %; the newest point a
    /// 3 pt (radius) Volt dot.
    nonisolated static let line: CGFloat = 1.4, prRuleOpacity = 0.30, lastDotRadius: CGFloat = 3
    /// The chart card → "Personal records", and between the groups.
    nonisolated static let sectionGap = GroupedListSpec.groupSpacing
    /// A record's row: 56 high at least.
    nonisolated static let recordRowHeight: CGFloat = 56
    /// A recent session's row: the date in a 58 pt column, 12 above and below.
    nonisolated static let recentDateWidth: CGFloat = 58, recentRowPadding: CGFloat = 12
    /// While the history loads the first time: the chart card's and the sets' outlines.
    nonisolated static let placeholderChartHeight: CGFloat = 230, placeholderSetsHeight: CGFloat = 138
    /// Under the last group.
    nonisolated static let bottomPadding: CGFloat = 32
}

/// An estimated 1RM's change in kg (PR 6 B §7.3): "▲ 11.6 kg" in strain blue when it rose (a training metric, D6B-14),
/// "▼ 1.5 kg" or "Steady" in `textSecondary` otherwise: a drop is never red. The arrow carries the direction, so the colour is
/// never the only cue. Pure.
enum E1RMChange {
    enum Direction: Equatable { case up, down, steady }

    /// To the tenth of a kilogram, as the chart's points are.
    static func rounded(_ kg: Double) -> Double { (kg * 10).rounded() / 10 }

    static func direction(_ kg: Double) -> Direction {
        let r = rounded(kg)
        return r > 0 ? .up : (r < 0 ? .down : .steady)
    }

    /// "▲ 11.6 kg", "▼ 1.5 kg", "Steady".
    static func text(_ kg: Double) -> String {
        let size = Fmt.kg(abs(rounded(kg))).replacingOccurrences(of: " ", with: DeltaLabel.noBreakSpace)
        switch direction(kg) {
        case .up: return "▲" + DeltaLabel.noBreakSpace + size
        case .down: return "▼" + DeltaLabel.noBreakSpace + size
        case .steady: return String(localized: "Steady")
        }
    }

    /// "Up 11.6 kg", "Down 1.5 kg", "No change".
    static func spoken(_ kg: Double) -> String {
        let size = Fmt.kg(abs(rounded(kg)))
        switch direction(kg) {
        case .up: return String(localized: "Up \(size)")
        case .down: return String(localized: "Down \(size)")
        case .steady: return String(localized: "No change")
        }
    }

    /// Strain blue for a rise, `textSecondary` for a drop or none.
    static func color(_ kg: Double) -> Color {
        direction(kg) == .up ? Theme.metricStrain : Theme.textSecondary
    }

    /// "▲ 11.6 kg in 90 days" under the numeral.
    static func overWindow(_ change: String) -> String {
        String(localized: "\(change) in 90 days",
               comment: "The exercise page, under its estimated 1RM: the change over the chart's 90 days (\"▲ 11.6 kg\", \"Steady\").")
    }

    /// "93.3", "100": the hero's and the chart card's number, without its unit.
    static func number(_ kg: Double, locale: Locale = .autoupdatingCurrent) -> String {
        kg.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }
}

/// One exercise over time (PR 6 B §7.3, `b-15`): its estimated 1RM as the hero numeral with the 90-day change, the chart, the
/// records and the recent sets. Pushed from the session detail and Strain; in a sheet from the live workout (`onClose`: a
/// close circle instead of Back).
struct ExerciseDetailView: View {
    let exerciseID: UUID
    var name: String?
    /// In a sheet: the sheet header's close circle runs this. Nil: a pushed page with Back.
    var onClose: (() -> Void)?

    @Environment(TrainLibrary.self) private var library
    @Environment(\.appEnvironment) private var env

    var body: some View {
        ExerciseDetailScreen(model: ExerciseDetailViewModel(exerciseID: exerciseID, name: name, library: library, clock: env.clock),
                             onClose: onClose)
    }
}

/// Wiring; the first model handed in is kept for the screen's lifetime.
private struct ExerciseDetailScreen: View {
    @State var model: ExerciseDetailViewModel
    let onClose: (() -> Void)?
    @Environment(\.appEnvironment) private var env

    var body: some View {
        ExerciseDetailPage(model: model, numeralStyle: env.settings.heroNumerals.style, onClose: onClose)
            .task { await model.load() }
    }
}

/// The page: the header, the numeral 22 under it with its caption and change, the chart card 22 under that, then "Personal
/// records" and "Recent sets", 18 apart. Pushed, no navigation bar: Back is the header's, the edge swipe still pops.
struct ExerciseDetailPage: View {
    let model: ExerciseDetailViewModel
    var numeralStyle: DotNumeral.Style = .dots
    var onClose: (() -> Void)?

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .caption2) private var prLabelHeight = ExerciseDetailLayout.prLabelHeight

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                hero
                    .padding(.top, ExerciseDetailLayout.heroGap)
                chartCard
                    .padding(.top, ExerciseDetailLayout.chartGap)
                VStack(alignment: .leading, spacing: ExerciseDetailLayout.sectionGap) {
                    if !model.records.isEmpty { records }
                    recentSets
                }
                .padding(.top, ExerciseDetailLayout.sectionGap)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.top, onClose == nil ? 0 : SheetHeaderSpec.topInset)
            .padding(.bottom, ExerciseDetailLayout.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepsBackSwipe()
        .modifier(ExerciseSheetPresentation(isSheet: onClose != nil))
    }

    @ViewBuilder private var header: some View {
        if let onClose {
            SheetHeader(Text(verbatim: model.title), onClose: onClose)
        } else {
            PushedHeader(Text(verbatim: model.title), subtitle: model.subtitle.map { Text(verbatim: $0) },
                         identifierPrefix: "exerciseDetail")
        }
    }

    // MARK: hero

    /// "93.3" in dots, "Estimated 1RM · kg", "▲ 11.6 kg in 90 days". One element: "Estimated 1RM", "93.3 kilograms, Up 11.6 kg
    /// in 90 days".
    private var hero: some View {
        let latest = model.latest
        return VStack(spacing: 0) {
            DotNumeral(latest.map { E1RMChange.number($0, locale: locale) }, style: numeralStyle,
                       glyphGap: DotNumeral.glyphGapDetail, placeholder: "00.0",
                       accessibilityLabel: Text("Estimated 1RM"))
            Text("Estimated 1RM · kg", comment: "The exercise page, under its estimated one-rep max numeral.")
                .font(.ryft(.label))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ExerciseDetailLayout.captionGap)
            if let change = model.change {
                Text(verbatim: E1RMChange.overWindow(E1RMChange.text(change)))
                    .font(.ryft(.label))
                    .monospacedDigit()
                    .foregroundStyle(E1RMChange.color(change))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ExerciseDetailLayout.changeGap)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Estimated 1RM"))
        .accessibilityValue(Text(verbatim: heroSpoken(latest)))
        .accessibilityIdentifier("exerciseDetail.numeral")
    }

    private func heroSpoken(_ latest: Double?) -> String {
        guard let latest else { return String(localized: "No data") }
        var parts = [HistorySpeech.kilograms(latest, locale: locale)]
        if let change = model.change { parts.append(E1RMChange.overWindow(E1RMChange.spoken(change))) }
        return parts.joined(separator: ", ")
    }

    // MARK: chart

    private var chartShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ExerciseDetailLayout.chartRadius, style: .continuous)
    }

    @ViewBuilder private var chartCard: some View {
        if model.isLoading {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: ExerciseDetailLayout.placeholderChartHeight)
                .background { PlaceholderOutline(chartShape) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Loading the exercise's history",
                                         comment: "VoiceOver: the exercise page's outlines while its history loads the first time."))
                .accessibilityIdentifier("exerciseDetail.loading")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                chartHead
                if model.hasTrend {
                    E1RMChart(points: model.points, best: model.bestE1RM, now: model.now)
                        .padding(.top, ExerciseDetailLayout.chartTopGap + max(0, prLabelHeight - ExerciseDetailLayout.prLabelHeight))
                } else {
                    Text(verbatim: model.emptyChartText)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: ExerciseDetailLayout.emptyChartHeight, alignment: .leading)
                        .accessibilityIdentifier("exerciseDetail.noTrend")
                }
            }
            .padding(ExerciseDetailLayout.chartPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: chartShape)
            .accessibilityElement(children: .contain)
        }
    }

    /// "Estimated 1RM" · "90 d", then "93.3 kg ▲ 2.9 kg vs last": one element.
    private var chartHead: some View {
        VStack(alignment: .leading, spacing: ExerciseDetailLayout.chartHeadGap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Estimated 1RM")
                    .font(.ryft(.label))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(verbatim: ChartWindow.quarter.title)
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            ChartValueLine(latest: model.latest, lastChange: model.lastChange)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Estimated 1RM"))
        .accessibilityValue(Text(verbatim: chartHeadSpoken))
        .accessibilityIdentifier("exerciseDetail.chartHead")
    }

    private var chartHeadSpoken: String {
        guard let latest = model.latest else { return String(localized: "No data") }
        var parts = [HistorySpeech.kilograms(latest, locale: locale)]
        if let change = model.lastChange { parts.append("\(E1RMChange.spoken(change)) \(String(localized: "vs last"))") }
        return parts.joined(separator: ", ")
    }

    // MARK: records and sets

    /// "Personal records": the trophy, the kind over its date, the value at the right; the sentence is VoiceOver's.
    private var records: some View {
        GroupedCard(Text("Personal records")) {
            ForEach(PRKind.allCases, id: \.self) { kind in
                if let pr = model.records.first(where: { $0.kind == kind }) {
                    RecordRow(record: pr)
                }
            }
        }
        .accessibilityIdentifier("exerciseDetail.records")
    }

    @ViewBuilder private var recentSets: some View {
        let rows = model.recentRows
        if model.isLoading {
            PlaceholderRow(height: ExerciseDetailLayout.placeholderSetsHeight)
                .accessibilityHidden(true)
        } else if rows.isEmpty {
            VStack(alignment: .leading, spacing: GroupedListSpec.titleGap) {
                GroupTitle(Text("Recent sets"))
                Text(verbatim: model.emptySetsText)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("exerciseDetail.noSets")
        } else {
            GroupedCard(Text("Recent sets")) {
                ForEach(rows) { RecentSetsRow(row: $0) }
            }
            .accessibilityIdentifier("exerciseDetail.sets")
        }
    }
}

/// The sheet's background and grabber, when the page is a sheet's.
private struct ExerciseSheetPresentation: ViewModifier {
    let isSheet: Bool

    func body(content: Content) -> some View {
        if isSheet {
            content
                .presentationBackground(Theme.background)
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

/// "93.3 kg ▲ 2.9 kg vs last": the newest estimate in 26 Light, "kg", and the change since the session before in strain blue
/// (a drop or none in `textSecondary`). The change goes under the number from AX1.
private struct ChartValueLine: View {
    let latest: Double?
    let lastChange: Double?

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = ExerciseDetailLayout.valueSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: NeutralTile.unitGap) {
                Text(verbatim: latest.map { E1RMChange.number($0, locale: locale) } ?? Fmt.placeholder)
                    .font(.ryftNumber(size: valueSize, weight: .light))
                    .foregroundStyle(latest == nil ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                Text("kg")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
            if let lastChange {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: E1RMChange.text(lastChange))
                        .fixedSize()
                    Text("vs last")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(E1RMChange.color(lastChange))
            }
        }
    }
}

/// A record in the grouped card: `PRBadge` (trophy disc, kind over its date, value) in a 56 pt row.
private struct RecordRow: View {
    let record: PersonalRecord
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        PRBadge(record: record, showsDate: true)
            .padding(.horizontal, GroupedListSpec.rowInset)
            // 52 + 2 + 2 at the default size; grown rows keep the list's 10 above and below their text.
            .padding(.vertical, typeSize.isAccessibilitySize ? GroupedListSpec.textPadding : (ExerciseDetailLayout.recordRowHeight - PRBadgeSpec.minHeight) / 2)
            .frame(maxWidth: .infinity, minHeight: ExerciseDetailLayout.recordRowHeight, alignment: .leading)
            .groupedRowHairline()
    }
}

/// A recent session: the date (`callout`, `textSecondary`, 58 wide), its working sets (they wrap) and their best estimate at
/// the right. From AX1 the three lines stack. One element: "Nov 13, 80 kg × 5 · 80 kg × 5, e1RM 93.5 kg".
private struct RecentSetsRow: View {
    let row: ExerciseDetailViewModel.RecentRow
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                    date
                    sets
                    best
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: GroupedListSpec.rowSpacing) {
                    date.frame(width: ExerciseDetailLayout.recentDateWidth, alignment: .leading)
                    sets.frame(maxWidth: .infinity, alignment: .leading)
                    best
                }
            }
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, ExerciseDetailLayout.recentRowPadding)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        .groupedRowHairline()
        .accessibilityElement(children: .combine)
    }

    private var date: some View {
        Text(verbatim: row.date)
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
    }

    private var sets: some View {
        Text(verbatim: row.sets)
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var best: some View {
        if let best = row.bestText {
            Text(verbatim: best)
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel(Text(verbatim: row.bestSpoken ?? best))
        }
    }
}

/// e1RM over the last 90 days (PR 6 B §7.3, D6B-14): a 1.4 pt strain-blue line with round joins, the PR a dashed 1 pt rule at
/// ink 30 % labelled "PR 93.5 kg", the newest point a Volt dot (the series' "now", L17). Trailing y labels, monthly x labels, no
/// fill. One VoiceOver element with the series as its audio graph.
struct E1RMChart: View {
    let points: [E1RMPoint]
    var best: Double?
    var now: Date = .now

    @Environment(\.dynamicTypeSize) private var typeSize

    private var values: [Double] { points.map(\.value) }

    private var dot: CGSize {
        CGSize(width: ExerciseDetailLayout.lastDotRadius * 2, height: ExerciseDetailLayout.lastDotRadius * 2)
    }

    var body: some View {
        let spec = MetricSpec.e1rm
        let window = ChartWindow.quarter
        let scale = ChartStyle.scale(for: values + [best].compactMap { $0 }, spec: spec)
        Chart {
            if let best {
                RuleMark(y: .value("e1RM", best))
                    .foregroundStyle(Theme.textPrimary.opacity(ExerciseDetailLayout.prRuleOpacity))
                    .lineStyle(ChartStyle.baseline)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("PR \(Fmt.kg(best))")
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
            }
            ForEach(points) { p in
                LineMark(x: .value("Day", p.date), y: .value("e1RM", p.value))
                    .interpolationMethod(.linear)
                    .foregroundStyle(spec.color)
                    .lineStyle(StrokeStyle(lineWidth: ExerciseDetailLayout.line, lineCap: .round, lineJoin: .round))
            }
            if let last = points.last {
                PointMark(x: .value("Day", last.date), y: .value("e1RM", last.value))
                    .foregroundStyle(Theme.signal)
                    .symbolSize(dot)
            }
        }
        .chartXScale(domain: window.domain(endingAt: now))
        .chartYScale(domain: scale.domain)
        .chartXAxis { ChartStyle.xAxis(window.ticks(endingAt: now), format: window.format) }
        .chartYAxis { ChartStyle.yAxis(scale.ticks, label: spec.axis) }
        .frame(height: typeSize.isAccessibilitySize ? ExerciseDetailLayout.chartHeightLargeText : ExerciseDetailLayout.chartHeight)
        .chartAppear()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Estimated one-rep max, last 90 days"))
        .accessibilityValue(Text(summary))
        .accessibilityChartDescriptor(SeriesChartDescriptor(title: String(localized: "Estimated 1RM"), valueName: "kg",
                                                            points: points.map { ($0.date, $0.value) },
                                                            valueText: { Fmt.kg($0) }))
        .accessibilityIdentifier("exerciseDetail.chart")
    }

    private var summary: String {
        guard let first = values.first, let last = values.last else { return String(localized: "No data") }
        return String(localized: "From \(Fmt.kg(first)) to \(Fmt.kg(last)), best \(Fmt.kg(best ?? values.max() ?? last)).")
    }
}

// MARK: - previews (dark only)

@MainActor
enum ExerciseDetailPreview {
    /// The page as loaded with `history`, Bench press's by default.
    static func model(_ history: ExerciseHistory?, exercise: UUID = MockTrain.bench.id) -> ExerciseDetailViewModel {
        ExerciseDetailViewModel(exerciseID: exercise, history: history, library: TrainPreview.library, clock: SystemClock())
    }
}

#Preview("Exercise page") {
    NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id) }
        .previewEnvironment()
}

#Preview("Exercise page · first time") {
    NavigationStack { ExerciseDetailPage(model: ExerciseDetailPreview.model(MockTrain.firstTimeHistory(for: MockTrain.bench.id))) }
        .previewEnvironment()
}

#Preview("Exercise page · no records") {
    NavigationStack {
        ExerciseDetailPage(model: ExerciseDetailPreview.model(MockTrain.historyWithoutRecords(for: MockTrain.squat.id),
                                                              exercise: MockTrain.squat.id))
    }
    .previewEnvironment()
}

#Preview("Exercise page · loading") {
    NavigationStack {
        ExerciseDetailPage(model: ExerciseDetailViewModel(exerciseID: MockTrain.bench.id, library: TrainPreview.library,
                                                          clock: SystemClock()))
    }
    .previewEnvironment()
}

#Preview("Exercise page · sheet") {
    ExerciseDetailPage(model: ExerciseDetailPreview.model(MockTrain.exerciseHistory(for: MockTrain.bench.id,
                                                                                     sessions: MockTrain.history)),
                       onClose: {})
        .previewEnvironment()
}

#Preview("Exercise page · AX3") {
    NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id) }
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}
