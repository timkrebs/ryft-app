// Sleep → Week and Month in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-7.2, the drafts `draft-sleep-week-*`,
// `draft-sleep-month-top`): the average as the hero numeral, the bed-and-wake glow tile, Quality and Consistency, the stage card
// and the nights list. `SleepRangeBoard` decides every value and look; the views draw it.
import Charts
import SwiftUI

// MARK: - the board (pure)

/// Week or Month as values: the numeral, the caption and the "vs 7 d" line, the strip, the tiles, the stage chart, the
/// nights and the "As of" note, formatted; the look for loading, no sleep and a failed load. Pure: tests build it without a
/// view.
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
        /// The tile as one VoiceOver value: "7 nights. Mean bedtime 10:48 PM, mean wake time 6:41 AM. Fairly regular. …"
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
        /// The card's head as VoiceOver reads it: "Average sleep, 7 hours 58 minutes".
        let spokenAverage: String
    }

    let kind: SleepRangeKind
    let look: Look
    /// "7:58"; `nil` draws the unlit "0:00".
    let clock: String?
    /// "Average sleep, 7 hours 58 minutes", "Loading…"; `nil` hides the numeral from VoiceOver (the message, or the caption
    /// without an average, says it).
    let numeralLabel: String?
    /// "Average · last 7 nights", "Average · 4 nights", "Loading…"; empty keeps the line.
    let caption: String
    /// The newest night against the mean of the others in the seven that end on it (F6, `MetricDelta.vsSevenDayMean`: Today's
    /// and Insights' rule, the same in Week and Month), in the sleep colour when it is longer.
    let delta: MetricDelta?
    /// Which night the delta is: "Last night" when it ended this morning, else its weekday ("Mon"; "Mon, Nov 9" beyond a
    /// week); and as VoiceOver says it ("Monday").
    let deltaLead: String
    let spokenDeltaLead: String
    let strip: Strip?
    /// Quality and Consistency.
    let tiles: [SleepTile]
    let stages: Stages?
    /// Newest first.
    let nights: [SleepRangeSummary.NightRow]
    /// The failed load's sentence, symbol, Details and button.
    let failure: SleepLoadFailure?
    /// "As of Nov 15" under the nights: the copy shown may be old (offline, the last read failed, or the range doesn't end
    /// today), as Bedtime's plan and Insights' cards say.
    let asOf: String?

    var isOutline: Bool { look != .loaded }

    /// - Parameters:
    ///   - isStale: offline, or the range's last read failed: the cached copy says "As of" its last day.
    ///   - today: the range is old when it doesn't end on this day.
    init(range: SleepRange?, kind: SleepRangeKind, isLoading: Bool = false, failure: SleepLoadFailure? = nil,
         isStale: Bool = false, today: Date = .now, locale: Locale = .autoupdatingCurrent, calendar: Calendar = .current) {
        self.kind = kind
        guard let range, range.nights > 0, !range.days.isEmpty else {
            let look: Look = isLoading ? .loading : failure != nil ? .failed : .empty
            self.look = look
            clock = nil
            let loading = String(localized: "Loading…")
            numeralLabel = look == .loading ? loading : nil
            caption = look == .loading ? loading : ""
            delta = nil
            deltaLead = ""
            spokenDeltaLead = ""
            asOf = nil
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
            String(localized: "Average sleep, \(Fmt.spokenDuration(minutes: $0, locale: locale))",
                   comment: "VoiceOver on Sleep → Week or Month's numeral: the range's average time asleep. %@: the duration, e.g. \"7 hours 58 minutes\".")
        }
        let newest = Self.newestNight(summary.totals)
        delta = .vsSevenDayMean(summary.totals)
        let lead = newest.map { Self.lead(night: $0.date, today: today, locale: locale, calendar: calendar) }
        deltaLead = lead?.shown ?? ""
        spokenDeltaLead = lead?.spoken ?? ""
        asOf = Self.asOf(range, isStale: isStale, today: today, end: summary.end, locale: locale, calendar: calendar)
        strip = Self.strip(summary, kind: kind, locale: locale)
        let week = Self.lastNights(range, end: summary.end, calendar: calendar)
        tiles = [Self.quality(range.avgQuality, locale: locale), Self.consistency(range.avgConsistency, week: week, locale: locale)]
        stages = Self.stages(range, summary: summary, kind: kind, locale: locale, calendar: calendar)
        nights = summary.nightRows
    }

    /// "Average · last 7 nights" with the whole range, "Average · 4 nights" with fewer.
    static func caption(nights: Int, kind: SleepRangeKind) -> String {
        if nights >= kind.days {
            return String(localized: "Average · last \(kind.days)\u{00A0}nights",
                          comment: "Sleep → Week or Month, under the numeral: the time asleep is the average of the whole range (\"Average · last 7 nights\").")
        }
        return String(localized: "Average · \(nights)\u{00A0}nights",
                      comment: "Sleep → Week/Month under the numeral: fewer nights than days (\"Average · 4 nights\"). Plural: \"Average · 1 night\".")
    }

    // MARK: the delta (F6)

    /// The newest night with a time asleep.
    private static func newestNight(_ totals: [TrendPoint]) -> TrendPoint? {
        totals.filter { $0.value != nil }.max { $0.day < $1.day }
    }

    /// "Last night" for the night that ended this morning, else its weekday ("Mon"), with its date beyond a week ("Mon, Nov
    /// 9"); VoiceOver hears the weekday in full.
    static func lead(night: Date, today: Date, locale: Locale = .autoupdatingCurrent,
                     calendar: Calendar = .current) -> (shown: String, spoken: String) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: night),
                                           to: calendar.startOfDay(for: today)).day ?? 0
        if days == 0 {
            let lastNight = String(localized: "Last night",
                                   comment: "Week/Month: the newest night before its change vs 7 d, when it ended this morning (else \"Mon\"). Also on Today.")
            return (lastNight, lastNight)
        }
        let style = Date.FormatStyle(locale: locale, calendar: calendar)
        if (1..<SleepBoard.weekNights).contains(days) {
            return (night.formatted(style.weekday(.abbreviated)), night.formatted(style.weekday(.wide)))
        }
        return (night.formatted(style.weekday(.abbreviated).month(.abbreviated).day()),
                night.formatted(style.weekday(.wide).month(.wide).day()))
    }

    /// "As of Nov 15" (the range's last day) offline, after a failed read, or when the range doesn't end today.
    private static func asOf(_ range: SleepRange, isStale: Bool, today: Date, end: Date, locale: Locale,
                             calendar: Calendar) -> String? {
        let endsToday = range.to.map { $0 == DayFormat.string(from: today) } ?? true
        guard isStale || !endsToday else { return nil }
        let day = end.formatted(Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day())
        // The key Bedtime's plan and Insights' cards use ("As of %@").
        return String(localized: "As of \(day)")
    }

    private static func strip(_ summary: SleepRangeSummary, kind: SleepRangeKind, locale: Locale) -> Strip? {
        guard !summary.bedtimes.isEmpty else { return nil }
        let count = String(localized: "\(summary.bedtimes.count)\u{00A0}nights")
        let means = BedtimeLayout(summary.bedtimes).spoken(locale: locale)
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
                  marks: [], spokenValue: value.map { String(localized: "\($0)\u{00A0}percent") } ?? String(localized: "No data"))
    }

    /// "72" (the platform's mean consistency, 0–100, without a unit as drawn) and the last seven nights as Day's dots: full
    /// from 60, missed below, a small dot without a value, the newest night last in Volt; VoiceOver says which is which.
    static func consistency(_ value: Int?, week: [Int?], locale: Locale = .autoupdatingCurrent) -> SleepTile {
        let day = SleepTile.consistency(value, week: week, locale: locale)
        var spoken = value.map {
            String(localized: "\($0) out of 100",
                   comment: "VoiceOver on Sleep → Week or Month's Consistency tile: the range's mean consistency on its 0–100 scale (\"72 out of 100\").")
        } ?? String(localized: "No data")
        if !week.isEmpty {
            let regular = week.filter { $0.map { $0 >= SleepTile.regularThreshold } ?? false }.count
            let irregular = week.filter { $0.map { $0 < SleepTile.regularThreshold } ?? false }.count
            let unknown = week.filter { $0 == nil }.count
            var parts = [String(localized: "\(regular) of the last 7\u{00A0}nights were regular",
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
        let byNight = Dictionary(grouping: summary.bars, by: \.day)
        for night in range.days {
            let parts = byNight[night.day] ?? []
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
            String(localized: "Average sleep, \(Fmt.spokenDuration(minutes: $0, locale: locale))",
                       comment: "VoiceOver on Sleep → Week or Month's stage card: the range's average time asleep. %@: the duration.")
        } ?? average
        return Stages(segments: segments, average: average, averageHours: summary.averageHours, top: top,
                      yTicks: Array(stride(from: 0, through: top, by: SleepModesLayout.hourStep)), start: start, end: end,
                      xTicks: window.ticks(endingAt: summary.end), window: window,
                      barRatio: kind == .week ? SleepModesLayout.weekBarRatio : SleepModesLayout.monthBarRatio,
                      legend: legend, spokenNights: spokenNights, spokenAverage: spokenAverage)
    }

    /// "Wednesday 18: Deep 1 hour 35 minutes, REM 1 hour 45 minutes, Light 4 hours 28 minutes", in the legend's order.
    private static func spoken(_ night: SleepNight, parts: [SleepRangeSummary.Bar], locale: Locale) -> String {
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
/// "vs 7 d" line, the bed-and-wake tile 20 under them, the two tiles, the stage card, the nights, and "As of" a copy that may
/// be old.
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
        if let asOf = board.asOf {
            SleepAsOfNote(text: asOf, identifier: "sleep.range.asOf")
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
                SleepRangeDelta(delta: delta, lead: board.deltaLead, spokenLead: board.spokenDeltaLead)
                    .padding(.top, SleepModesLayout.deltaGap)
            }
        }
    }
}

/// "Last night ▲ +17m · +4 % vs 7 d" ("Mon ▼ …" when the newest night is older): the newest night against the nights before
/// it in its seven, the change in the sleep colour when it is longer and `alert` when shorter (`DeltaLabel`, the arrow and
/// the sign carry the direction). One VoiceOver element.
struct SleepRangeDelta: View {
    let delta: MetricDelta
    /// The night: "Last night", "Mon"; and as VoiceOver says it ("Monday").
    var lead = ""
    var spokenLead = ""

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // From AX1 three lines: the night, the change, "vs 7 d". On one line the change and "vs 7 d" outgrow the
                // column at AX3, and a `ViewThatFits` whose last choice doesn't fit lays it out at its full width (T5.8 S1).
                VStack(spacing: 2) {
                    leadText
                    change(stacked: true)
                }
            } else {
                // One line, or the night over the change when the line doesn't fit (large text).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        leadText
                        change(stacked: false)
                    }
                    VStack(spacing: 2) {
                        leadText
                        change(stacked: false)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sleep.range.delta")
    }

    private var leadText: some View {
        Text(verbatim: lead)
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
            .accessibilityLabel(Text(verbatim: spokenLead.isEmpty ? lead : spokenLead))
    }

    private func change(stacked: Bool) -> some View {
        DeltaLabel(spec: .sleepMin, delta: delta, reference: String(localized: "vs 7\u{00A0}d"), stacked: stacked)
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
/// goes under the date, and the nap under the total when the three don't fit on a line (AX5: "7h 48m", "25m" and "86" are
/// 330 wide, more than a 402 pt screen's row has, and widened the whole column, T5.8 S1). One VoiceOver element with the night
/// in words.
struct SleepNightListRow: View {
    let row: SleepRangeSummary.NightRow

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    // The fallback (the nap on its own line) is at most the total and the consistency wide, which fits.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            total
                            nap
                            Spacer(minLength: 0)
                            consistency
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                total
                                Spacer(minLength: 0)
                                consistency
                            }
                            nap
                        }
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

/// "As of Nov 15" (Week, Month) or "As of 10:44 AM" (Bedtime) 12 under the last card: what's shown may be old.
struct SleepAsOfNote: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(verbatim: text)
            .font(.ryft(.caption))
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.top, SleepModesLayout.footerGap)
            .accessibilityIdentifier(identifier)
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
        case week, month, fewNights, older, loading, empty, failed, offline
    }

    let scene: Scene

    init(_ scene: Scene) {
        self.scene = scene
    }

    private var kind: SleepRangeKind { scene == .month ? .month : .week }

    var board: SleepRangeBoard {
        switch scene {
        case .week, .month: return SleepRangeBoard(range: MockData.sleepRange(kind), kind: kind)
        case .fewNights:
            let week = MockData.sleepRange(.week)
            return SleepRangeBoard(range: Self.nights(week, Array(week.days.suffix(4))), kind: .week)
        case .older:
            // Read two days ago: the newest night is named, the copy "As of" its day.
            let week = MockData.sleepRange(.week)
            var range = Self.nights(week, Array(week.days.dropLast(2)))
            range.to = range.days.last?.day
            return SleepRangeBoard(range: range, kind: .week)
        case .offline:
            // What the app shows offline: the cached week as it is, "As of" its day (no refresh card: reads aren't failing).
            return SleepRangeBoard(range: MockData.sleepRange(.week), kind: .week, isStale: true)
        case .loading: return SleepRangeBoard(range: nil, kind: .week, isLoading: true)
        case .empty: return SleepRangeBoard(range: nil, kind: .week)
        case .failed:
            return SleepRangeBoard(range: nil, kind: .week,
                                   failure: SleepLoadFailure(APIError.http(503, "", requestID: "01JD8K2V9Q7M3X"),
                                                             isOnline: true, at: .now))
        }
    }

    /// `range` with only `days`, its bedtimes and averages theirs, as the platform computes them (`MockData.sleepRange`).
    static func nights(_ range: SleepRange, _ days: [SleepNight]) -> SleepRange {
        func mean(_ xs: [Int]) -> Int? { xs.isEmpty ? nil : Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded()) }
        let kept = Set(days.map(\.day))
        return SleepRange(range: range.range, from: range.from, to: range.to, days: days,
                          avgTotalMin: mean(days.compactMap(\.totalMin)), avgQuality: mean(days.compactMap(\.quality)),
                          avgInBedMin: mean(days.compactMap(\.inBedMin)), avgEfficiency: mean(days.compactMap(\.efficiency)),
                          avgConsistency: mean(days.compactMap(\.consistency)),
                          bedtimes: range.bedtimes.filter { kept.contains($0.day) })
    }

    var body: some View {
        let mode: SleepMode = scene == .month ? .month : .week
        let header = SleepHeaderContent(mode: mode, night: .now, today: .now, marker: nil, canStepBack: false,
                                        canStepForward: false)
        NavigationStack {
            SleepPage(header: header, mode: .constant(mode), modes: SleepMode.allCases, step: { _ in }) {
                SleepRangeSection(board: board, showsHealthHint: scene == .empty,
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
#Preview("Sleep · Week, read two days ago") { SleepRangePreviewPage(.older).previewEnvironment() }
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
