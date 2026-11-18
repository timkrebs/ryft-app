// Sleep → Week and Month in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-7.2, the drafts `draft-sleep-week-*`,
// `draft-sleep-month-top`): the average as the hero numeral, the bed-and-wake glow tile, Quality and Consistency, the stage card
// and the nights list. `SleepRangeBoard` decides every value and look; the views draw it.
import Charts
import SwiftUI

// MARK: - the board (pure)

/// Week or Month as values: the numeral, the caption and the "vs 7 d" line, the strip, the tiles, the stage chart and the
/// nights, formatted; the look for loading, no sleep and a failed load. Pure: tests build it without a view.
struct SleepRangeBoard: Equatable {
    enum Look: Equatable {
        /// Nights to show.
        case loaded
        /// Nothing cached and the load in flight: the unlit numeral, outlines, no spinner.
        case loading
        /// No sleep in the range (or nothing cached and no answer): "No sleep data for this range yet."
        case empty
        /// The load failed with nothing cached: the calm sentence, Details and Today's button (`SleepLoadFailure`).
        case failed
    }

    /// The bed-and-wake tile.
    struct Strip: Equatable {
        let bedtimes: [SleepBedtime]
        /// 14 with the dates (Week), 7 without (Month).
        let rowHeight: CGFloat
        let showsRowLabels: Bool
        /// "7 nights".
        let count: String
        /// The consistency sentence under the strip.
        let hint: String
        /// The tile as one VoiceOver value: "7 nights. Mean bedtime 22:48, mean wake time 06:41. Fairly regular. …"
        let spoken: String
    }

    /// One stage of one night in the chart, in hours, its upper end 1.5 pt short of the next stage (the gap).
    struct Segment: Equatable, Identifiable {
        let day: String
        let date: Date
        /// `nil`: a night without stages ("Asleep").
        let stage: SleepStageKind?
        let lower: Double
        let upper: Double
        var id: String { "\(day)-\(stage?.rawValue ?? "asleep")" }
    }

    /// The stage card.
    struct Stages: Equatable {
        /// Bottom to top per night: Deep, Light, REM (or Asleep alone).
        let segments: [Segment]
        /// "avg 7h 58m"; the dashed rule's height.
        let average: String
        let averageHours: Double?
        /// The hours axis: 0 … `top` in steps of 3 (at least 12).
        let top: Double
        let yTicks: [Double]
        /// The x domain (the window's first day … the day after the last) and its labels.
        let start: Date
        let end: Date
        let xTicks: [Date]
        let window: ChartWindow
        let barRatio: Double
        /// The legend, as the tints darken: Deep, REM, Light, then Asleep when a night has no stages.
        let legend: [SleepStageKind?]
        /// Per night, oldest first: "Wednesday 18: Deep 1 hour 35 minutes, REM 1 hour 45 minutes, Light 4 hours 28 minutes".
        let spokenNights: [String]
        /// The card's head as VoiceOver reads it: "7 hours 58 minutes average sleep".
        let spokenAverage: String
    }

    let kind: SleepRangeKind
    let look: Look
    /// "7:58"; `nil` draws the unlit "0:00".
    let clock: String?
    /// "7 hours 58 minutes average sleep", "Loading…"; `nil` hides the numeral from VoiceOver (the message says it).
    let numeralLabel: String?
    /// "Average · last 7 nights", "Average · 4 nights", "Loading…"; empty keeps the line.
    let caption: String
    /// The newest night against the seven before it (F6), in the sleep colour when it is better.
    let delta: MetricDelta?
    let strip: Strip?
    /// Quality and Consistency.
    let tiles: [SleepTile]
    let stages: Stages?
    /// Newest first.
    let nights: [SleepRangeSummary.NightRow]
    /// The failed load's sentence, symbol, Details and button.
    let failure: SleepLoadFailure?

    var isOutline: Bool { look != .loaded }

    init(range: SleepRange?, kind: SleepRangeKind, isLoading: Bool = false, failure: SleepLoadFailure? = nil,
         locale: Locale = .autoupdatingCurrent, calendar: Calendar = .current) {
        self.kind = kind
        guard let range, range.nights > 0, !range.days.isEmpty else {
            let look: Look = isLoading ? .loading : failure != nil ? .failed : .empty
            self.look = look
            clock = nil
            let loading = String(localized: "Loading…")
            numeralLabel = look == .loading ? loading : nil
            caption = look == .loading ? loading : ""
            delta = nil
            strip = nil
            tiles = [Self.quality(nil, locale: locale), Self.consistency(nil, week: [], locale: locale)]
            stages = nil
            nights = []
            self.failure = look == .failed ? failure : nil
            return
        }
        let summary = SleepRangeSummary(range: range, locale: locale)
        look = .loaded
        self.failure = nil
        clock = range.avgTotalMin.map { Fmt.clock(minutes: $0) }
        caption = Self.caption(nights: range.nights, kind: kind)
        numeralLabel = range.avgTotalMin.map {
            String(localized: "\(Fmt.spokenDuration(minutes: $0, locale: locale)) average sleep",
                   comment: "VoiceOver on Sleep → Week or Month's numeral: the range's average time asleep (\"7 hours 58 minutes average sleep\").")
        } ?? caption
        delta = .vsSevenDayMean(summary.totals)
        strip = Self.strip(summary, kind: kind)
        let week = Self.lastNights(range, end: summary.end, calendar: calendar)
        tiles = [Self.quality(range.avgQuality, locale: locale), Self.consistency(range.avgConsistency, week: week, locale: locale)]
        stages = Self.stages(range, summary: summary, kind: kind, locale: locale, calendar: calendar)
        nights = summary.nightRows
    }

    /// "Average · last 7 nights" with the whole range, "Average · 4 nights" with fewer.
    static func caption(nights: Int, kind: SleepRangeKind) -> String {
        if nights >= kind.days {
            return String(localized: "Average · last \(kind.days) nights",
                          comment: "Sleep → Week or Month, under the numeral: the time asleep is the average of the whole range (\"Average · last 7 nights\").")
        }
        return String(localized: "Average · \(nights) nights",
                      comment: "Sleep → Week or Month, under the numeral, when the range has fewer nights than its days (\"Average · 4 nights\").")
    }

    private static func strip(_ summary: SleepRangeSummary, kind: SleepRangeKind) -> Strip? {
        guard !summary.bedtimes.isEmpty else { return nil }
        let count = String(localized: "\(summary.bedtimes.count) nights")
        let means = BedtimeLayout(summary.bedtimes).spoken
        return Strip(bedtimes: summary.bedtimes,
                     rowHeight: kind == .week ? SleepModesLayout.weekRowHeight : SleepModesLayout.monthRowHeight,
                     showsRowLabels: kind == .week, count: count, hint: summary.consistencyHint,
                     spoken: "\(count). \(means). \(summary.consistencyHint)")
    }

    /// `sleepConsistency` of the seven nights ending at `end`, oldest first; a night that isn't in the range is `nil`.
    static func lastNights(_ range: SleepRange, end: Date, calendar: Calendar = .current) -> [Int?] {
        let last = calendar.startOfDay(for: end)
        return (0..<SleepBoard.weekNights).reversed().map { back in
            let day = DayFormat.string(from: calendar.date(byAdding: .day, value: -back, to: last) ?? last)
            return range.days.first { $0.day == day }?.consistency
        }
    }

    // MARK: tiles

    /// "91" + "%" (the range's mean quality); "–" without one.
    static func quality(_ value: Int?, locale: Locale = .autoupdatingCurrent) -> SleepTile {
        SleepTile(kind: .quality, value: value.map(String.init) ?? Fmt.placeholder, unit: value.map { _ in "%" }, notes: [],
                  marks: [], spokenValue: value.map { String(localized: "\($0) percent") } ?? String(localized: "No data"))
    }

    /// "72" (the platform's mean consistency, 0–100, without a unit as drawn) and the last seven nights as Day's dots: full
    /// from 60, missed below, a small dot without a value, the newest night last in Volt; VoiceOver says which is which.
    static func consistency(_ value: Int?, week: [Int?], locale: Locale = .autoupdatingCurrent) -> SleepTile {
        let day = SleepTile.consistency(value, week: week, locale: locale)
        var spoken = value.map(String.init) ?? String(localized: "No data")
        if !week.isEmpty {
            let regular = week.filter { $0.map { $0 >= SleepTile.regularThreshold } ?? false }.count
            let irregular = week.filter { $0.map { $0 < SleepTile.regularThreshold } ?? false }.count
            let unknown = week.filter { $0 == nil }.count
            var parts = [String(localized: "\(regular) of the last 7 nights were regular",
                                comment: "VoiceOver, Sleep's Consistency tile: nights of the seven that were regular (60+). Plural: one \"was regular\".")]
            if irregular > 0 {
                parts.append(String(localized: "\(irregular) were not",
                                    comment: "VoiceOver, Sleep's Consistency tile, after the regular nights: those that were not. Plural: one \"was not\"."))
            }
            if unknown > 0 {
                parts.append(String(localized: "\(unknown) have no data",
                                    comment: "VoiceOver on Sleep's Consistency tile: nights without a consistency value. Needs a plural: one \"has no data\"."))
            }
            let last = String(localized: "the last is the newest night",
                              comment: "VoiceOver on Sleep → Week or Month's Consistency tile, after the counts: the last dot (Volt) is the newest night.")
            spoken = "\(spoken). \(parts.joined(separator: ", ")); \(last)"
        }
        return SleepTile(kind: .consistency, value: value.map(String.init) ?? Fmt.placeholder, unit: nil, notes: [],
                         marks: day.marks, spokenValue: spoken)
    }

    // MARK: the stage chart

    private static func stages(_ range: SleepRange, summary: SleepRangeSummary, kind: SleepRangeKind, locale: Locale,
                               calendar: Calendar) -> Stages {
        let top = max(SleepModesLayout.minimumHours,
                      (summary.tallestNight / SleepModesLayout.hourStep).rounded(.up) * SleepModesLayout.hourStep)
        // 1.5 pt of the card between two stages, in hours at the plot's height.
        let gap = Double(SleepModesLayout.stageSegmentGap) * top / Double(SleepModesLayout.stagePlotHeight)
        var segments: [Segment] = []
        var spokenNights: [String] = []
        for night in range.days {
            let parts = Self.segments(night)
            var lower = 0.0
            for (index, part) in parts.enumerated() {
                let upper = lower + part.hours
                let isTop = index == parts.count - 1
                segments.append(Segment(day: night.day, date: night.date, stage: part.stage, lower: lower,
                                        upper: isTop ? upper : max(lower, upper - gap)))
                lower = upper
            }
            if !parts.isEmpty { spokenNights.append(Self.spoken(night, parts: parts, locale: locale)) }
        }
        let window = summary.window
        let start = window.start(endingAt: summary.end)
        let end = DayFormat.shift(calendar.startOfDay(for: summary.end), days: 1)
        let present = Set(segments.map(\.stage))
        let legend: [SleepStageKind?] = ([.deep, .rem, .light] as [SleepStageKind?]).filter(present.contains)
            + (present.contains(nil) ? [nil] : [])
        let average = String(localized: "avg \(summary.averageSleep)")
        let spokenAverage = range.avgTotalMin.map {
            String(localized: "\(Fmt.spokenDuration(minutes: $0, locale: locale)) average sleep")
        } ?? average
        return Stages(segments: segments, average: average, averageHours: summary.averageHours, top: top,
                      yTicks: Array(stride(from: 0, through: top, by: SleepModesLayout.hourStep)), start: start, end: end,
                      xTicks: window.ticks(endingAt: summary.end), window: window,
                      barRatio: kind == .week ? SleepModesLayout.weekBarRatio : SleepModesLayout.monthBarRatio,
                      legend: legend, spokenNights: spokenNights, spokenAverage: spokenAverage)
    }

    /// A night's stages bottom to top (`SleepRangeSummary.stageOrder`: Deep, Light, REM), or its total as "Asleep".
    static func segments(_ night: SleepNight) -> [(stage: SleepStageKind?, hours: Double)] {
        let staged: [(stage: SleepStageKind?, hours: Double)] = SleepRangeSummary.stageOrder.compactMap { stage in
            let minutes = night.minutes(for: stage)
            return minutes > 0 ? (stage, Double(minutes) / 60) : nil
        }
        if !staged.isEmpty { return staged }
        guard let total = night.totalMin, total > 0 else { return [] }
        return [(nil, Double(total) / 60)]
    }

    /// "Wednesday 18: Deep 1 hour 35 minutes, REM 1 hour 45 minutes, Light 4 hours 28 minutes", in the legend's order.
    private static func spoken(_ night: SleepNight, parts: [(stage: SleepStageKind?, hours: Double)], locale: Locale) -> String {
        let order: [SleepStageKind?] = [.deep, .rem, .light, nil]
        let said = order.compactMap { stage -> String? in
            guard let part = parts.first(where: { $0.stage == stage }) else { return nil }
            let name = stage?.title ?? SleepRangeSummary.asleep
            return "\(name) \(Fmt.spokenDuration(minutes: Int((part.hours * 60).rounded()), locale: locale))"
        }
        let date = night.date.formatted(Date.FormatStyle(locale: locale).weekday(.wide).day())
        return "\(date): \(said.joined(separator: ", "))"
    }
}

// MARK: - the section

/// Week or Month under the header and the picker (§P5-7.2): the notice, the numeral 22 under the picker, its caption and the
/// "vs 7 d" line, the bed-and-wake tile 20 under them, the two tiles, the stage card, the nights.
struct SleepRangeSection: View {
    let board: SleepRangeBoard
    var numeralStyle: DotNumeral.Style = .dots
    /// "No Health data yet" under an empty range, when nothing came from Apple Health at all.
    var showsHealthHint = false
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?
    var notice = SleepModeNotice(issue: nil)
    /// A failed load's Try again and Sign in.
    var retry: (() async -> Void)?
    var signIn: (() async -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            notice
            SleepRangeHead(board: board, numeralStyle: numeralStyle)
            switch board.look {
            case .loaded:
                loaded
            case .loading:
                SleepModeOutline(title: Text("Bed and wake times"), minHeight: SleepModesLayout.bedWakeMinHeight,
                                 radius: SleepLayout.hypnogramRadius)
                    .padding(.top, SleepModesLayout.tileGap)
                SleepTileGrid(tiles: board.tiles, isOutline: true)
                    .padding(.top, SleepModesLayout.tilesGap)
                SleepModeOutline(title: Text("Time asleep per night"), minHeight: SleepStageCard.outlineHeight,
                                 radius: SleepModesLayout.stageCardRadius)
                    .padding(.top, SleepModesLayout.cardGap)
            case .empty:
                InlineMessage(message: String(localized: "No sleep data for this range yet."), systemImage: "moon.zzz",
                              identifier: "sleep.range.empty")
                    .padding(.top, SleepModesLayout.tileGap)
                if showsHealthHint {
                    HealthAccessHint()
                        .padding(.top, SleepModesLayout.cardGap)
                }
            case .failed:
                let failure = board.failure
                let action = failure?.action ?? .retry
                InlineMessage(message: failure?.message ?? "", systemImage: failure?.systemImage ?? "wifi.exclamationmark",
                              retryTitle: action.title, details: failure?.details,
                              retry: action.button(retry: retry, signIn: signIn), identifier: "sleep.range.failure")
                    .padding(.top, SleepModesLayout.tileGap)
            }
        }
    }

    @ViewBuilder private var loaded: some View {
        if let strip = board.strip {
            SleepBedWakeTile(strip: strip, reduceTransparency: reduceTransparency)
                .padding(.top, SleepModesLayout.tileGap)
        }
        SleepTileGrid(tiles: board.tiles)
            .padding(.top, board.strip == nil ? SleepModesLayout.tileGap : SleepModesLayout.tilesGap)
        if let stages = board.stages, !stages.segments.isEmpty {
            SleepStageCard(stages: stages)
                .padding(.top, SleepModesLayout.cardGap)
        }
        if !board.nights.isEmpty {
            GroupedCard {
                ForEach(board.nights) { SleepNightListRow(row: $0) }
            }
            .padding(.top, SleepModesLayout.cardGap)
        }
    }
}

/// The numeral 22 under the picker, centred; its caption 12 under it; the newest night's "vs 7 d" 4 under that (F6).
struct SleepRangeHead: View {
    let board: SleepRangeBoard
    var numeralStyle: DotNumeral.Style = .dots

    var body: some View {
        VStack(spacing: 0) {
            DotNumeral(board.clock, style: numeralStyle, glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00",
                       accessibilityLabel: Text(board.numeralLabel ?? ""))
                .accessibilityHidden(board.numeralLabel == nil)
                .accessibilityIdentifier("sleep.range.numeral")
                .frame(maxWidth: .infinity)
                .padding(.top, SleepModesLayout.numeralGap)
            // An empty caption keeps its line, so nothing below moves.
            Text(verbatim: board.caption.isEmpty ? " " : board.caption)
                .font(.ryft(.label))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                // The numeral already says "Loading…".
                .accessibilityHidden(board.caption.isEmpty || board.look == .loading)
                .padding(.top, SleepModesLayout.captionGap)
            if let delta = board.delta {
                SleepRangeDelta(delta: delta)
                    .padding(.top, SleepModesLayout.deltaGap)
            }
        }
    }
}

/// "Last night ▲ +17m · +4 % vs 7 d": the newest night against the seven before it, the change in the sleep colour when it is
/// longer and `alert` when shorter (`DeltaLabel`, the arrow and the sign carry the direction). One VoiceOver element.
struct SleepRangeDelta: View {
    let delta: MetricDelta

    var body: some View {
        // One line, or "Last night" over the change when the line doesn't fit (large text).
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                lead
                change
            }
            VStack(spacing: 2) {
                lead
                change
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sleep.range.delta")
    }

    private var lead: some View {
        Text("Last night")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
    }

    private var change: some View {
        DeltaLabel(spec: .sleepMin, delta: delta, reference: String(localized: "vs 7 d"))
    }
}

/// The bed-and-wake glow tile (§P5-7.2 row 2): "Bed and wake times" and "7 nights", the strip 8 under them, the consistency
/// sentence 8 under the strip. It grows with its rows (Week about 228, Month about 300). One VoiceOver element.
struct SleepBedWakeTile: View {
    let strip: SleepRangeBoard.Strip
    var reduceTransparency: Bool?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GlowTile(Theme.metricSleep, kind: .hypnogram, minHeight: SleepModesLayout.bedWakeMinHeight,
                 reduceTransparency: reduceTransparency) {
            VStack(alignment: .leading, spacing: 0) {
                head
                BedtimeStrip(bedtimes: strip.bedtimes, rowHeight: strip.rowHeight, showsRowLabels: strip.showsRowLabels)
                    .padding(.top, SleepModesLayout.stripGap)
                Text(strip.hint)
                    .ryftGlowLabelStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SleepModesLayout.hintGap)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bed and wake times"))
        .accessibilityValue(Text(strip.spoken))
        .accessibilityIdentifier("sleep.range.bedtimes")
    }

    @ViewBuilder private var head: some View {
        let title = Text("Bed and wake times", comment: "Sleep → Week or Month: the glow tile with each night's bed and wake time.")
            .ryftGlowLabelStyle()
        let count = Text(strip.count).ryftGlowLabelStyle(.caption)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                title
                count
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title
                Spacer(minLength: 0)
                count.lineLimit(1)
            }
        }
    }
}

/// The stage card (§P5-7.2 row 4): "Time asleep per night" and the average; a bar per night, Deep at the bottom, then Light,
/// REM on top, 1.5 pt of the card between them, the average a dashed rule; the legend 10 under the chart.
struct SleepStageCard: View {
    let stages: SleepRangeBoard.Stages

    /// The loading outline's height: about the card's.
    static let outlineHeight: CGFloat = 230

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let padding = SleepModesLayout.stageCardPadding
        VStack(alignment: .leading, spacing: 0) {
            head
            SleepStageChart(stages: stages)
                .padding(.top, SleepModesLayout.stageChartGap)
            SleepStageLegend(stages: stages.legend)
                .padding(.top, SleepModesLayout.legendGap)
        }
        .padding(EdgeInsets(top: padding.top, leading: padding.sides, bottom: padding.bottom, trailing: padding.sides))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface,
                    in: RoundedRectangle(cornerRadius: SleepModesLayout.stageCardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var head: some View {
        let title = Text("Time asleep per night", comment: "Sleep → Week or Month: the card with each night's stages as a bar.")
            .ryftLabelStyle()
        let average = Text(stages.average)
            .font(.ryft(.caption))
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    average
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                    Spacer(minLength: 0)
                    average.lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time asleep per night"))
        .accessibilityValue(Text(stages.spokenAverage))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("sleep.range.stages")
    }
}

/// The nightly stage bars: the hours axis at the trailing edge (0 / 3 / 6 / 9 / 12, gridlines ink 8 %), the days under the
/// plot (weekday initials, or weekly dates), the average dashed in `textTertiary`. VoiceOver reads one sentence per night.
struct SleepStageChart: View {
    let stages: SleepRangeBoard.Stages

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The date row under the plot: 150 − 128 at the default size, growing with the axis text.
    @ScaledMetric(relativeTo: .caption2) private var axisRowHeight: CGFloat =
        SleepModesLayout.stageChartHeight - SleepModesLayout.stagePlotHeight

    /// The middle of a day, where its bar is centred.
    private static func middle(of day: Date) -> Date {
        Date(timeIntervalSince1970: (day.timeIntervalSince1970 + DayFormat.shift(day, days: 1).timeIntervalSince1970) / 2)
    }

    var body: some View {
        Chart {
            ForEach(stages.segments) { segment in
                BarMark(x: .value("Night", segment.date, unit: .day), yStart: .value("From", segment.lower),
                        yEnd: .value("To", segment.upper), width: .ratio(stages.barRatio))
                    .foregroundStyle(SleepStageTint.color(segment.stage))
                    .cornerRadius(SleepModesLayout.stageCornerRadius)
            }
            if let average = stages.averageHours {
                RuleMark(y: .value("Time asleep", average))
                    .lineStyle(ChartStyle.baseline)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartXScale(domain: stages.start...stages.end)
        .chartYScale(domain: 0...stages.top)
        .chartXAxis {
            // Reserves the date row; the overlay draws the labels (Charts puts a date's label beside its tick, and a
            // centred one needs a next tick, which the last day doesn't have).
            AxisMarks(values: stages.xTicks) { _ in
                AxisValueLabel(format: stages.window.format)
                    .font(ChartStyle.axisFont)
                    .foregroundStyle(.clear)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame {
                    let plot = geo[frame]
                    SleepStageAxisRow(centres: stages.xTicks.map { proxy.position(forX: Self.middle(of: $0)) ?? 0 }) {
                        ForEach(stages.xTicks, id: \.self) { day in
                            // No room (`.zero`) hides a label that would collide: the frame is flexible, the text clipped.
                            Text(day, format: stages.window.format)
                                .font(ChartStyle.axisFont)
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .clipped()
                        }
                    }
                    .frame(width: plot.width, height: max(geo.size.height - plot.maxY, 0))
                    .offset(x: plot.minX, y: plot.maxY)
                }
            }
            .allowsHitTesting(false)
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: stages.yTicks) { _ in
                AxisGridLine(stroke: ChartStyle.grid)
                    .foregroundStyle(Theme.textPrimary.opacity(SleepModesLayout.gridOpacity))
            }
            // Every hour tick; at accessibility sizes every other one (0, 6, 12), so the labels fit the 128 pt plot.
            AxisMarks(position: .trailing,
                      values: typeSize.isAccessibilitySize ? SleepModesLayout.everyOther(stages.yTicks) : stages.yTicks) { value in
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(hours.formatted(.number.precision(.fractionLength(0))))
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartPlotStyle { plot in plot.frame(height: SleepModesLayout.stagePlotHeight) }
        .frame(height: SleepModesLayout.stagePlotHeight + axisRowHeight)
        .chartAppear()
        .accessibilityRepresentation {
            VStack(alignment: .leading) {
                ForEach(Array(stages.spokenNights.enumerated()), id: \.offset) { _, night in
                    Text(verbatim: night)
                }
            }
        }
    }
}

/// The stage chart's date row: each label centred on its day's bar (`centres`, from the plot's leading edge), kept inside
/// the plot and vertically centred in the row; a label that would come within `gap` of the next one's is left out (the
/// newest is always shown), as Charts' own labels do at large sizes.
struct SleepStageAxisRow: Layout {
    let centres: [CGFloat]
    nonisolated static let gap: CGFloat = 6

    /// Each label's leading x (from 0), or `nil` when it is left out: from the newest back, centred on its bar, clamped to
    /// `0…width`, shown when it ends `gap` before the label after it.
    nonisolated static func positions(centres: [CGFloat], widths: [CGFloat], width: CGFloat) -> [CGFloat?] {
        var positions = [CGFloat?](repeating: nil, count: min(centres.count, widths.count))
        var limit = width + gap
        for index in positions.indices.reversed() {
            let x = min(max(centres[index] - widths[index] / 2, 0), width - widths[index])
            if x + widths[index] + gap <= limit {
                positions[index] = x
                limit = x
            }
        }
        return positions
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let positions = Self.positions(centres: centres, widths: sizes.map(\.width), width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            if index < positions.count, let x = positions[index] {
                subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.midY - size.height / 2), proposal: ProposedViewSize(size))
            } else {
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.midY), proposal: .zero)
            }
        }
    }
}

/// The legend: a 10 pt square in each tint and the stage's name (`.caption`, `textSecondary`), in a row or, when the row
/// doesn't fit, a column. Hidden from VoiceOver: each night's sentence names its stages.
struct SleepStageLegend: View {
    let stages: [SleepStageKind?]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { items }
            VStack(alignment: .leading, spacing: 6) { items }
        }
        .accessibilityHidden(true)
    }

    private var items: some View {
        ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: SleepModesLayout.legendSwatchRadius, style: .continuous)
                    .fill(SleepStageTint.color(stage))
                    .frame(width: SleepModesLayout.legendSwatch, height: SleepModesLayout.legendSwatch)
                Text(stage?.title ?? SleepRangeSummary.asleep)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize()
            }
        }
    }
}

/// A night in the list (§P5-7.2 row 5): the date, a nap, the total and the consistency at the end; 46 high. From AX1 the total
/// goes under the date. One VoiceOver element with the night in words.
struct SleepNightListRow: View {
    let row: SleepRangeSummary.NightRow

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        total
                        nap
                        Spacer(minLength: 0)
                        consistency
                    }
                }
                .padding(.vertical, GroupedListSpec.textPadding)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    title
                    Spacer(minLength: 8)
                    nap
                    total
                    consistency
                }
            }
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .frame(maxWidth: .infinity, minHeight: SleepModesLayout.nightRowHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.spokenTitle.isEmpty ? row.title : row.spokenTitle))
        .accessibilityValue(Text(row.spokenValue))
        .accessibilityIdentifier("sleep.night.\(row.day)")
        .groupedRowHairline()
    }

    private var title: some View {
        Text(row.title)
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var nap: some View {
        if let nap = row.nap {
            Label(nap, systemImage: "powersleep")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var total: some View {
        Text(row.total)
            .font(.ryft(.callout).monospacedDigit())
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    private var consistency: some View {
        Text(row.consistency ?? Fmt.placeholder)
            .font(.ryft(.caption).monospacedDigit())
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
            .frame(minWidth: SleepModesLayout.nightConsistencyWidth, alignment: .trailing)
    }
}

// MARK: - shared by the modes

/// Today's calm card under the picker while reads fail or the data is old (Week, Month, Bedtime; §P5-7 "Offline / stale");
/// nothing otherwise. The values under it stay in full ink.
struct SleepModeNotice: View {
    let issue: RefreshIssue?
    var isDemo = false
    var retry: () async -> Void = {}
    var signIn: () async -> Void = {}

    var body: some View {
        if let issue {
            RefreshIssueCard(issue: issue, isDemo: isDemo, retry: retry, signIn: signIn)
                .padding(.top, SleepModesLayout.noticeGap)
        }
    }
}

/// A tile or a card while its data loads: the placeholder outline with its title in `textTertiary` (as Day's hypnogram slot).
struct SleepModeOutline: View {
    let title: Text
    let minHeight: CGFloat
    let radius: CGFloat

    var body: some View {
        title
            .ryftLabelStyle(Theme.textTertiary)
            .padding(GlowTileSpec.padding(for: .hypnogram))
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background { PlaceholderOutline(RoundedRectangle(cornerRadius: radius, style: .continuous)) }
            .accessibilityHidden(true)
    }
}

// MARK: - previews

/// Sleep → Week or Month for a state, as `SleepView` lays it out (previews and the hosted tests).
struct SleepRangePreviewPage: View {
    enum Scene: String, CaseIterable {
        case week, month, fewNights, loading, empty, failed, offline
    }

    let scene: Scene

    init(_ scene: Scene) {
        self.scene = scene
    }

    private var kind: SleepRangeKind { scene == .month ? .month : .week }

    var board: SleepRangeBoard {
        switch scene {
        case .week, .month, .offline: return SleepRangeBoard(range: MockData.sleepRange(kind), kind: kind)
        case .fewNights:
            var range = MockData.sleepRange(.week)
            range.days = Array(range.days.suffix(4))
            range.nights = range.days.count
            range.bedtimes = Array(range.bedtimes.suffix(4))
            return SleepRangeBoard(range: range, kind: .week)
        case .loading: return SleepRangeBoard(range: nil, kind: .week, isLoading: true)
        case .empty: return SleepRangeBoard(range: nil, kind: .week)
        case .failed:
            return SleepRangeBoard(range: nil, kind: .week,
                                   failure: SleepLoadFailure(APIError.http(503, "", requestID: "01JD8K2V9Q7M3X"),
                                                             isOnline: true, at: .now))
        }
    }

    /// Reads failing for a while, the cache two hours old (Today's card).
    static var offlineIssue: RefreshIssue {
        let at = Date.now
        let error = ResourceError(kind: .transient, status: nil, code: nil, requestID: nil, transport: "timedOut", attempts: 3,
                                  at: at)
        return RefreshIssue(reason: .unreachable, resource: .today, dataFrom: at.addingTimeInterval(-7_200), failures: 3,
                            error: error)
    }

    var body: some View {
        let mode: SleepMode = scene == .month ? .month : .week
        let header = SleepHeaderContent(mode: mode, night: .now, today: .now, marker: nil, canStepBack: false,
                                        canStepForward: false)
        NavigationStack {
            SleepPage(header: header, mode: .constant(mode), modes: SleepMode.allCases, step: { _ in }) {
                SleepRangeSection(board: board, showsHealthHint: scene == .empty,
                                  notice: SleepModeNotice(issue: scene == .offline ? Self.offlineIssue : nil),
                                  retry: scene == .failed ? {} : nil, signIn: scene == .failed ? {} : nil)
            }
        }
    }
}

#Preview("Sleep · Week") { SleepRangePreviewPage(.week).previewEnvironment() }
#Preview("Sleep · Week · AX3") {
    SleepRangePreviewPage(.week).previewEnvironment().environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Sleep · Month") { SleepRangePreviewPage(.month).previewEnvironment() }
#Preview("Sleep · Month · AX3") {
    SleepRangePreviewPage(.month).previewEnvironment().environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Sleep · Week, 4 nights") { SleepRangePreviewPage(.fewNights).previewEnvironment() }
#Preview("Sleep · Week, loading") { SleepRangePreviewPage(.loading).previewEnvironment() }
#Preview("Sleep · Week, loading · AX3") {
    SleepRangePreviewPage(.loading).previewEnvironment().environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Sleep · Week, no sleep") { SleepRangePreviewPage(.empty).previewEnvironment() }
#Preview("Sleep · Week, no sleep · AX3") {
    SleepRangePreviewPage(.empty).previewEnvironment().environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Sleep · Week, load error") { SleepRangePreviewPage(.failed).previewEnvironment() }
#Preview("Sleep · Week, offline") { SleepRangePreviewPage(.offline).previewEnvironment() }
