import SwiftUI
import Charts

/// One workout (Nocturne, design.md §P5-4; drafts `draft-workout-top`, `-bottom`): the header with Back, the strain numeral
/// and ruler, the heart-rate zones, the stat tiles, the logged session, the heart-rate curve and its source.
struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(AppState.self) private var state

    var body: some View {
        WorkoutDetailScreen(model: WorkoutDetailViewModel(workout: workout, state: state))
            .analyticsScreen(.workoutDetail)
    }
}

/// Wiring; the first model handed in is kept for the screen's lifetime.
private struct WorkoutDetailScreen: View {
    @State var model: WorkoutDetailViewModel

    var body: some View {
        WorkoutDetailPage(board: model.board, numeralStyle: model.numeralStyle, isOffline: model.isOffline,
                          retry: { await model.load() }, signIn: { await model.signIn() }, sessionRPE: model.sessionRPE)
            .task { await model.load() }
    }
}

/// The page: header 40, the numeral 22 under it, caption and ruler as Strain's, the zones tile at the ruler's top + 56 (its
/// footnote 8 under it), the stat tiles 12 under that, the session row and the chart card 12 apart, the source 14 under the
/// card. No navigation bar: Back is the header's, the edge swipe still pops.
struct WorkoutDetailPage: View {
    let board: WorkoutBoard
    var numeralStyle: DotNumeral.Style = .dots
    var isOffline = false
    /// The failure's Try again: the detail's load.
    var retry: () async -> Void = {}
    var signIn: () async -> Void = {}
    /// Previews and tests; nil follows the system.
    var reduceTransparency: Bool?
    var sessionRPE: SessionRPEModel?

    @Environment(\.locale) private var locale
    /// The logged session, pushed by item (`navigationDestination(item:)` below).
    @State private var shownSession: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                if isOffline {
                    SyncStatusLineView(line: .offline, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, StrainLayout.statusGap)
                }
                if let sessionRPE, sessionRPE.showsPrompt {
                    SessionRPERow(model: sessionRPE, promptsForLoad: true)
                        .padding(.top, StrainLayout.tilesGap)
                }
                StrainHeroView(hero: board.hero, key: board.workout.id.uuidString, numeralStyle: numeralStyle,
                               pendingLabel: StrainRows.spokenStrain(nil), identifierPrefix: "workout")
                    .padding(.top, StrainLayout.numeralGap)
                zones
                WorkoutStatTiles(stats: board.stats)
                    .padding(.top, StrainLayout.tilesGap)
                if let row = board.sessionRow, let id = board.workout.sessionId {
                    // By item, not a value link: from My Day's full screen this page is two view pushes deep on Today's
                    // stack, where SwiftUI ignores a value link (review S2). The row still reads as a button.
                    Button { shownSession = id } label: { ActivityListRow(content: row, accessory: .chevron) }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityHint(Text("Opens the session", comment: "VoiceOver: a My Day row opens the Train session."))
                        .accessibilityIdentifier("workout.session")
                        .padding(.top, StrainLayout.tilesGap)
                }
                if let sessionRPE, sessionRPE.isVisible, !sessionRPE.showsPrompt {
                    SessionRPERow(model: sessionRPE)
                        .padding(.top, StrainLayout.tilesGap)
                }
                WorkoutHeartRateCard(board: board)
                    .padding(.top, StrainLayout.tilesGap)
                Text(verbatim: board.sourceText)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, StrainLayout.sourceGap)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, StrainLayout.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepsBackSwipe()
        .navigationDestination(item: $shownSession) { SessionDetailView(sessionID: $0) }
    }

    /// The zones tile, its outline while the detail loads, or the failure's sentence in its place (as Strain's, §P5-3.7).
    @ViewBuilder private var zones: some View {
        if let failure = board.failure {
            InlineMessage(message: failure.message, systemImage: failure.systemImage, retryTitle: failure.action.title,
                          details: failure.details, retry: failure.action.button(retry: retry, signIn: signIn),
                          identifier: "workout.failure")
        } else {
            StrainZonesTile(zones: board.zones, missing: .sentence(WorkoutBoard.noZonesSentence), isOutline: board.isOutline,
                            reduceTransparency: reduceTransparency, identifierPrefix: "workout")
        }
    }

    /// Back · the sport over its day and time · an empty 40 pt slot (§P5-4 row 1): the pushed pages' one header (DG-6).
    private var header: some View {
        PushedHeader(Text(verbatim: board.title), subtitle: Text(verbatim: board.when(locale: locale)),
                     spokenSubtitle: Text(verbatim: board.spokenWhen(locale: locale)), identifierPrefix: "workout")
    }
}

/// The stat tiles in two columns, 12 apart (an odd last one alone, left); one column from AX1. Each pair matches the taller.
private struct WorkoutStatTiles: View {
    let stats: [WorkoutStat]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: StrainLayout.tileSpacing) {
            if typeSize.isAccessibilitySize {
                ForEach(stats) { tile($0) }
            } else {
                ForEach(Array(stride(from: 0, to: stats.count, by: StrainLayout.statColumns)), id: \.self) { i in
                    HStack(spacing: StrainLayout.tileSpacing) {
                        tile(stats[i])
                        if i + 1 < stats.count {
                            tile(stats[i + 1])
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tile(_ stat: WorkoutStat) -> some View {
        NeutralTile(Text(verbatim: stat.label), value: Text(verbatim: stat.value), unit: stat.unit.map { Text(verbatim: $0) },
                    accessibilityValue: stat.spoken.map { Text(verbatim: $0) })
            .accessibilityIdentifier("workout.stat.\(stat.id)")
    }
}

/// "Heart rate" and "avg 148 bpm" over the curve; an outline while the detail loads or after it failed; the sentence when
/// the detail has no series.
private struct WorkoutHeartRateCard: View {
    let board: WorkoutBoard

    @Environment(\.dynamicTypeSize) private var typeSize

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StrainLayout.chartRadius, style: .continuous)
    }

    var body: some View {
        // The curve's scales are worked out once per body.
        let plot = board.plot
        VStack(alignment: .leading, spacing: StrainLayout.chartHeadGap) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                    Spacer(minLength: 0)
                    average(plot)
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    average(plot)
                }
            }
            if let plot {
                WorkoutHeartRateChart(plot: plot)
            } else if board.lacksSeries {
                Text("No heart-rate series available for this workout.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                Color.clear.frame(height: typeSize.isAccessibilitySize ? StrainLayout.chartHeightLargeText : StrainLayout.chartHeight)
            }
        }
        .padding(.vertical, StrainLayout.chartPadding)
        .padding(.horizontal, StrainLayout.chartSidePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if board.isOutline {
                PlaceholderOutline(shape)
            } else {
                shape.fill(Theme.surface)
            }
        }
    }

    private var title: some View {
        Text("Heart rate")
            .font(.ryft(.label))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// "avg 148 bpm"; from AX1 with the peak after it ("avg 148 bpm · peak 159"), which the chart then doesn't draw.
    private func headText(_ plot: HeartRatePlot?) -> String? {
        guard typeSize.isAccessibilitySize, let peak = plot?.peakText else { return board.averageText }
        return MyDayText.join([board.averageText, peak].compactMap { $0 })
    }

    @ViewBuilder private func average(_ plot: HeartRatePlot?) -> some View {
        if let text = headText(plot) {
            Text(verbatim: text)
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                // In the chart's value.
                .accessibilityHidden(plot != nil)
        }
    }
}

/// Beats per minute over the workout (§P5-4 row 6): the line in `textPrimary` 1.4 pt with round joins, the average a dashed
/// 1 pt `textTertiary` rule, the peak a 3 pt dot with "peak 159", three trailing ticks with gridlines at ink 8 %, clock ticks
/// from the start. Scrubbing shows the reading at a time; VoiceOver has the descriptor.
private struct WorkoutHeartRateChart: View {
    let plot: HeartRatePlot

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: Date?

    /// From AX1: a taller chart, every other clock tick, and the peak's text in the card's head instead of over its dot.
    private var largeText: Bool { typeSize.isAccessibilitySize }

    private var selected: HRPoint? {
        guard let selection else { return nil }
        return plot.points.min { abs($0.t.timeIntervalSince(selection)) < abs($1.t.timeIntervalSince(selection)) }
    }

    private var dot: CGSize { CGSize(width: StrainLayout.chartPeakDot * 2, height: StrainLayout.chartPeakDot * 2) }

    var body: some View {
        let selected = selected
        let peak = plot.peak
        Chart {
            if let average = plot.average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: StrainLayout.chartAverageLine, dash: [3, 3]))
            }
            ForEach(plot.points, id: \.t) { p in
                LineMark(x: .value("Time", p.t), y: .value("BPM", p.bpm))
                    .interpolationMethod(.linear)
                    .foregroundStyle(Theme.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: StrainLayout.chartLine, lineCap: .round, lineJoin: .round))
            }
            if let s = selected {
                RuleMark(x: .value("Time", s.t))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ScrubReadout(value: "\(Int(s.bpm)) bpm", date: Fmt.time(s.t),
                                     delta: plot.average.map { avg in
                                         let d = Int((s.bpm - avg).rounded())
                                         return String(localized: "\(d >= 0 ? "+" : "−")\(abs(d)) vs average")
                                     })
                    }
                PointMark(x: .value("Time", s.t), y: .value("BPM", s.bpm))
                    .foregroundStyle(Theme.textPrimary)
                    .symbolSize(dot)
            } else {
                PointMark(x: .value("Time", peak.t), y: .value("BPM", peak.bpm))
                    .foregroundStyle(Theme.textPrimary)
                    .symbolSize(dot)
                    .annotation(position: .top, spacing: 3) {
                        if !largeText {
                            Text(verbatim: plot.peakText)
                                .font(ChartStyle.axisFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
            }
        }
        .chartYScale(domain: plot.domain)
        .chartXScale(domain: (plot.points.first?.t ?? .now)...(plot.points.last?.t ?? .now))
        .chartXSelection(value: $selection)
        .chartXAxis { ChartStyle.xAxis(largeText ? plot.largeTextXTicks : plot.xTicks, format: .dateTime.hour().minute()) }
        .chartYAxis {
            AxisMarks(position: .trailing, values: plot.yTicks) { value in
                AxisGridLine(stroke: ChartStyle.grid)
                    .foregroundStyle(Theme.textPrimary.opacity(StrainLayout.chartGridOpacity))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(verbatim: String(Int(v.rounded())))
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .frame(height: largeText ? StrainLayout.chartHeightLargeText : StrainLayout.chartHeight)
        .chartAppear()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart rate over time"))
        .accessibilityValue(Text(verbatim: plot.spokenValue))
        .accessibilityChartDescriptor(SeriesChartDescriptor(title: String(localized: "Heart rate"), valueName: "bpm",
                                                            points: plot.points.map { ($0.t, $0.bpm) },
                                                            valueText: { "\(Int($0)) bpm" }))
        .accessibilityIdentifier("workout.chart")
    }
}

// MARK: - previews (dark only)

/// The demo's first workout today, its detail, and the states without one.
enum WorkoutPreview {
    static var workout: Workout { MockData.todayDetail.workouts[0] }

    static func board(loading: Bool = false, failure: SleepLoadFailure? = nil, series: Bool = true, zones: Bool = true,
                      session: Bool = false) -> WorkoutBoard {
        var w = workout
        if session {
            w.sessionId = UUID(uuidString: "00000000-0000-4000-8000-00000000b001")
            w.muscularLoad = 84.6
        }
        var detail: WorkoutDetail? = loading || failure != nil ? nil : MockData.workoutDetail(w)
        if !series { detail?.hr = [] }
        if !zones { detail?.zoneMin = [] }
        return WorkoutBoard(workout: w, detail: detail, isLoading: loading, failure: failure)
    }
}

#Preview("Workout") {
    NavigationStack {
        WorkoutDetailView(workout: WorkoutPreview.workout)
    }
    .previewEnvironment()
}

#Preview("Workout · logged session") {
    NavigationStack { WorkoutDetailPage(board: WorkoutPreview.board(session: true)) }
        .previewEnvironment()
}

#Preview("Workout · loading") {
    NavigationStack { WorkoutDetailPage(board: WorkoutPreview.board(loading: true)) }
        .previewEnvironment()
}

#Preview("Workout · failed") {
    NavigationStack {
        WorkoutDetailPage(board: WorkoutPreview.board(failure: SleepLoadFailure(reason: .busy, details: "HTTP 503")))
    }
    .previewEnvironment()
}

#Preview("Workout · no series, no zones, offline") {
    NavigationStack { WorkoutDetailPage(board: WorkoutPreview.board(series: false, zones: false), isOffline: true) }
        .previewEnvironment()
}

#Preview("Workout · AX3") {
    NavigationStack { WorkoutDetailPage(board: WorkoutPreview.board(session: true)) }
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}
