import SwiftUI
import Testing
@testable import Ryft

/// What Insights shows (docs/work/2026-11-16-nocturne/design.md §P5-12 tests 28–30; §P5-5.1–§P5-5.3): which insight is the tile, the
/// trend cards' data and colours, their states and their order. Pure where it can be; the view model on the test graph
/// (`MockPlatformAPI`, `TestClock`) for loading and focusing.
@MainActor
@Suite("T5.3: Insights data")
struct InsightsDataTests {
    private static let lastDay = "2026-11-18"
    private static var today: Date { DayFormat.date(from: lastDay) ?? .now }

    /// A series whose last day is `lastDay`, one point per value (oldest first); `nil` values are left out, as the platform does.
    private static func series(_ metric: TrendMetric, _ values: [Double?], range: TrendRange = .month,
                               avg: Double? = nil) -> TrendSeries {
        let days = DayFormat.days(endingAt: today, count: values.count)
        let points = zip(days, values).compactMap { day, v in v.map { TrendPoint(day: day, value: $0) } }
        let present = values.compactMap { $0 }
        var s = TrendSeries(metric: metric.rawValue, range: range.rawValue, points: points, avg: avg,
                            min: present.min(), max: present.max(), baseline: nil)
        s.to = lastDay
        return s
    }

    private static func insight(_ id: String, _ severity: InsightSeverity, metric: String = "hrv") -> Insight {
        Insight(id: id, severity: severity, title: id, body: "", metric: metric)
    }

    private static func make(_ metric: TrendMetric, _ range: TrendRange = .month, series: TrendSeries?,
                             monthly: TrendSeries? = nil, loading: Bool = false, stale: Bool = false) -> TrendCardContent {
        .make(metric, range: range, series: series, monthly: monthly, isLoading: loading, isStale: stale, today: today)
    }

    // MARK: 28. the tile rule

    @Test("Spec 28: the tile is the first visible info insight; notices and warnings above it, the other info insights below")
    func arrangement() {
        let warn = Self.insight("strain-no-recovery", .warn), notice = Self.insight("bedtime-irregular", .notice)
        let best = Self.insight("hrv-best-30d", .info), up = Self.insight("readiness-up", .info), pr = Self.insight("pr", .info)
        let a = InsightsArrangement([best, warn, up, notice, pr])
        #expect(a.tile == best)
        #expect(a.attention == [warn, notice])
        #expect(a.more == [up, pr])
        #expect(!a.isEmpty)
    }

    @Test("Spec 28: no tile with only notices and warnings; nothing at all is empty")
    func noTileWithoutInfo() {
        let only = InsightsArrangement([Self.insight("hrv-low-3d", .warn), Self.insight("sleep-debt", .notice)])
        #expect(only.tile == nil && only.more.isEmpty && only.attention.count == 2 && !only.isEmpty)
        #expect(InsightsArrangement([]).isEmpty && InsightsArrangement([]).tile == nil)
    }

    @Test("Spec 28: dismissing the tile promotes the next info insight")
    func dismissPromotes() {
        let (state, _) = Self.makeState()
        let vm = InsightsViewModel(state: state)
        let best = Self.insight("hrv-best-30d", .info), up = Self.insight("readiness-up", .info)
        state.insights = [Self.insight("rhr-elevated", .warn), best, up]
        #expect(vm.arrangement.tile == best)
        vm.dismiss(best)
        #expect(vm.arrangement.tile == up && vm.arrangement.more.isEmpty)
        vm.dismiss(up)
        #expect(vm.arrangement.tile == nil && vm.arrangement.attention.count == 1)
    }

    @Test("Spec 28: the link's words per kind", arguments: [
        ("behavior-impact", "See behaviors"), ("pr", "See the session"), ("hrv-best-30d", "Show the chart"),
        ("readiness-up", "Show the chart"), ("a-new-rule", "Show the chart"),
    ])
    func linkTitles(_ id: String, _ title: String) {
        #expect(Self.insight(id, .info).linkTitle == title)
    }

    @Test("Spec 28: the severity's word: Insight, Notice, Attention")
    func severityWords() {
        #expect(Self.insight("x", .info).severityWord == String(localized: "Insight"))
        #expect(Self.insight("x", .notice).severityWord == String(localized: "Notice"))
        #expect(Self.insight("x", .warn).severityWord == String(localized: "Attention"))
    }

    // MARK: 29. trend data

    @Test("Spec 29: the value is the range's newest, the change is against the mean of the 7 days before it")
    func latestAndDelta() throws {
        // 10 days: 99 and 60 more than 7 days back, then six days of 60, the day before the last missing, the last 70.
        let s = Self.series(.readiness, [99, 60, 60, 60, 60, 60, 60, 60, nil, 70])
        let card = Self.make(.readiness, series: s)
        #expect(card.latest == 70)
        let delta = try #require(card.delta)
        #expect(delta.value == 10, "the 7 days before: six 60s; the 99 nine days back is out")
        #expect(card.values.count == 30 && card.values.last == 70 && card.values[28] == nil)
    }

    @Test("Spec 29: no change under 3 values in the 7 days before", arguments: [(2, false), (3, true)])
    func deltaNeedsThree(_ prior: Int, _ shows: Bool) {
        let s = Self.series(.hrv, [Double?](repeating: nil, count: 7 - prior) + [Double?](repeating: 50, count: prior) + [60])
        #expect((Self.make(.hrv, series: s).delta != nil) == shows)
    }

    @Test("Spec 29: the band is the 30-day series' range for readiness, HRV, time asleep and resting HR only")
    func bands() {
        let month = Self.series(.hrv, [50, 70, 60])
        for metric in TrendMetric.allCases {
            let card = Self.make(metric, series: Self.series(metric, [55, 60]), monthly: month)
            #expect((card.band == 50...70) == [.readiness, .hrv, .sleepMin, .rhr].contains(metric), "\(metric)")
        }
        #expect(Set(TrendMetric.banded) == [.readiness, .hrv, .sleepMin, .rhr])
    }

    @Test("Spec 29: no band without a 30-day series (or with a flat one): the note asks for 30 days")
    func noBand() {
        let s = Self.series(.readiness, [70, 72, 74])
        let card = Self.make(.readiness, series: s, monthly: nil)
        #expect(card.band == nil)
        #expect(card.note == String(localized: "Band needs 30 days of data"))
        #expect(Self.make(.readiness, series: s, monthly: Self.series(.readiness, [70, 70])).band == nil)
    }

    @Test("Spec 29: the notes: readiness names the band, HRV says SDNN, the others their average")
    func notes() {
        let month = Self.series(.hrv, [50, 70])
        #expect(Self.make(.readiness, series: Self.series(.readiness, [70]), monthly: month).note
                == String(localized: "Band: 30-day range"))
        #expect(Self.make(.hrv, series: Self.series(.hrv, [60]), monthly: month).note == String(localized: "SDNN"))
        let sleep = Self.make(.sleepMin, series: Self.series(.sleepMin, [468], avg: 451), monthly: month)
        #expect(sleep.note == String(localized: "Avg \("7:31 h")"))
        #expect(Self.make(.steps, series: Self.series(.steps, [9_412], avg: 8_000)).note
                == String(localized: "Avg \(MetricSpec.steps.number(8_000))"))
        #expect(Self.make(.steps, series: Self.series(.steps, [9_412])).note == nil, "no average, no note")
    }

    @Test("Spec 29: HRV's line, band and good change are recovery; readiness is an ink line with a recovery change")
    func colours() {
        let up = MetricDelta(current: 66, reference: 60), down = MetricDelta(current: 54, reference: 60)
        let hrv = TrendCardStyle(.hrv)
        #expect(hrv.line == Theme.recovery && hrv.bandOpacity == 0.12)
        #expect(hrv.deltaColor(up, polarity: .higherIsBetter) == Theme.recovery)
        #expect(hrv.deltaColor(down, polarity: .higherIsBetter) == Theme.alert)
        let readiness = TrendCardStyle(.readiness)
        #expect(readiness.line == Theme.textPrimary && readiness.bandOpacity == 0.06)
        #expect(readiness.deltaColor(up, polarity: .higherIsBetter) == Theme.recovery)
        #expect(TrendCardStyle(.sleepMin).line == Theme.metricSleep)
        #expect(TrendCardStyle(.strain).line == Theme.metricStrain)
        // Resting HR: lower is better, the good change in ink, never red for good news.
        let rhr = TrendCardStyle(.rhr)
        #expect(rhr.deltaColor(MetricDelta(current: 48, reference: 52), polarity: .lowerIsBetter) == Theme.textPrimary)
        #expect(rhr.deltaColor(MetricDelta(current: 56, reference: 52), polarity: .lowerIsBetter) == Theme.alert)
        // Flat, and a metric with no good direction: secondary ink.
        #expect(hrv.deltaColor(MetricDelta(current: 60.5, reference: 60), polarity: .higherIsBetter) == Theme.textSecondary)
        #expect(TrendCardStyle(.strain).deltaColor(up, polarity: .neutral) == Theme.textSecondary)
        // Nothing in a warning hue, and teal only for recovery's metrics.
        for metric in TrendMetric.allCases {
            let style = TrendCardStyle(metric)
            #expect(![Theme.warning, Theme.alert, Theme.accentSecondary].contains(style.line), "\(metric)")
            #expect((style.line == Theme.recovery) == [.hrv, .recovery].contains(metric), "\(metric)")
        }
    }

    @Test("Spec 29: the value's parts: a clock for durations, the unit after the number")
    func valueParts() {
        #expect(TrendCardContent.valueParts(.sleepMin, 468) == ("7:48", "h"))
        #expect(TrendCardContent.valueParts(.hrv, 66) == ("66", "ms"))
        #expect(TrendCardContent.valueParts(.readiness, 78) == ("78", nil))
        #expect(TrendCardContent.valueParts(.recovery, 82) == ("82", "%"))
    }

    @Test("AX3: the change wraps only after its \"·\", never between a number and its unit")
    func changeKeepsUnits() {
        let nbsp = "\u{00A0}"
        #expect(TrendCardContent.keepingUnitsTogether("▲ +7 ms · +12 %") == "▲\(nbsp)+7\(nbsp)ms · +12\(nbsp)%")
        #expect(TrendCardContent.keepingUnitsTogether("vs 7 d") == "vs\(nbsp)7\(nbsp)d")
        #expect(TrendCardContent.keepingUnitsTogether("Steady") == "Steady")
    }

    @Test("Spec 29: the 30-day series is fetched for the four banded metrics only, whatever the range")
    func monthlyFetchesFour() async {
        let api = MockPlatformAPI()
        let (state, _) = Self.makeState(api: api)
        let vm = InsightsViewModel(state: state)
        vm.range = .week
        await vm.load()
        #expect(Set(vm.monthly.keys) == Set(TrendMetric.banded))
        #expect(api.count("trends") == TrendMetric.allCases.count + TrendMetric.banded.count)
        #expect(state.cachedTrend(.strain, range: .month) == nil)
        for metric in TrendMetric.banded { #expect(vm.band(for: metric) != nil, "\(metric)") }
        #expect(vm.band(for: .strain) == nil)
    }

    // MARK: 30. trend states

    @Test("Spec 30: loading with nothing cached is pending: no value, no note, the flat line, read as loading")
    func loading() {
        let card = Self.make(.hrv, series: nil, loading: true)
        #expect(card.isPending && card.latest == nil && card.note == nil && card.delta == nil)
        #expect(card.spokenValue == String(localized: "Loading…"))
        // Not loading and nothing cached: no data, not pending.
        let none = Self.make(.hrv, series: nil, loading: false)
        #expect(!none.isPending && none.note == String(localized: "No data in this range"))
    }

    @Test("Spec 30: no data in the range: no value, the note says so, every day empty")
    func noData() {
        let card = Self.make(.hrv, series: Self.series(.hrv, [nil, nil, nil]))
        #expect(card.latest == nil && card.delta == nil && !card.isPending)
        #expect(card.note == String(localized: "No data in this range"))
        #expect(card.values.allSatisfy { $0 == nil })
    }

    @Test("Spec 30: offline, the note gives the data's last day")
    func stale() {
        let card = Self.make(.readiness, series: Self.series(.readiness, [70]), monthly: Self.series(.readiness, [60, 75]),
                             stale: true)
        let day = Self.today.formatted(.dateTime.month(.abbreviated).day())
        #expect(card.note == String(localized: "As of \(day)"))
    }

    @Test("Spec 30: VoiceOver reads the value, the change, the note and the chart's sentence, ending against the band")
    func spoken() {
        let s = Self.series(.readiness, [60, 60, 60, 60, 60, 60, 60, 78])
        let card = Self.make(.readiness, series: s, monthly: Self.series(.readiness, [55, 70]))
        #expect(card.chartLabel == String(localized: "\(String(localized: "Readiness")) over \(30) days"))
        #expect(card.chartEnding == TrendLine.spoken(.above))
        #expect(card.spokenValue.hasPrefix("78"))
        #expect(card.spokenValue.contains(String(localized: "Band: 30-day range")))
        #expect(card.spokenValue.hasSuffix(TrendLine.spoken(.above)))
        // Without a band, the sentence ends at the value.
        let strain = Self.make(.strain, series: Self.series(.strain, [9, 12.4]))
        #expect(strain.chartEnding == String(localized: "ending at \(MetricSpec.strain.text(12.4))"))
    }

    @Test("Spec 30: a deep link's metric opens its card once; a tap toggles a card")
    func focusOpensCard() {
        let (state, _) = Self.makeState()
        let vm = InsightsViewModel(state: state)
        #expect(vm.openFocused() == nil)
        vm.focusedMetric = .hrv
        #expect(vm.openFocused() == .hrv)
        #expect(vm.isExpanded(.hrv) && vm.focusedMetric == nil)
        #expect(vm.openFocused() == nil)
        vm.toggle(.hrv)
        #expect(!vm.isExpanded(.hrv))
        vm.toggle(.strain)
        #expect(vm.isExpanded(.strain) && vm.expanded == [.strain])
    }

    @Test("Spec 30: the order: readiness, HRV, time asleep, then the other eleven; 14 cards, none lost")
    func order() {
        let (state, _) = Self.makeState()
        let vm = InsightsViewModel(state: state)
        #expect(vm.boardCards.map(\.metric) == [.readiness, .hrv, .sleepMin])
        let all = vm.boardCards.map(\.metric) + vm.moreCards.map(\.metric)
        #expect(all.count == 14 && Set(all) == Set(TrendMetric.allCases))
        #expect(vm.moreCards.map(\.metric) == TrendMetric.allCases.filter { ![.readiness, .hrv, .sleepMin].contains($0) })
    }

    // MARK: helpers

    private static func makeState(api: MockPlatformAPI = MockPlatformAPI()) -> (AppState, TestClock) {
        let clock = TestClock()
        return (AppState(env: .test(api: api, clock: clock)), clock)
    }
}
