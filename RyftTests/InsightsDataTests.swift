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

    @Test("Spec 29: the value is the range's newest; the change is Today's: against the 6 days before it, not 7 or 8 back")
    func latestAndDelta() throws {
        // Oldest first: 99 nine days back, 10 eight back, 90 seven back, then six days of 70, the newest 82.
        let s = Self.series(.readiness, [99, 10, 90, 70, 70, 70, 70, 70, 70, 82])
        let card = Self.make(.readiness, series: s)
        #expect(card.latest == 82)
        #expect(card.delta == MetricDelta(current: 82, reference: 70), "the 90 seven days back and the 10 eight back are out")
        #expect(card.values.count == 30 && card.values.last == 82)
        // Six days back is in: 82 there moves the mean to 72.
        let six = Self.series(.readiness, [10, 90, 82, 70, 70, 70, 70, 70, 82])
        #expect(Self.make(.readiness, series: six).delta == MetricDelta(current: 82, reference: 72))
        // A gap is skipped, not a zero.
        let gap = Self.series(.readiness, [70, nil, 70, 70, nil, 70, 77])
        #expect(Self.make(.readiness, series: gap).delta == MetricDelta(current: 77, reference: 70))
    }

    @Test("Spec 29: one earlier day in the 6 is enough (Today's rule); none, no change")
    func deltaNeedsOne() {
        #expect(Self.make(.hrv, series: Self.series(.hrv, [nil, nil, nil, nil, nil, 50, 60])).delta
                == MetricDelta(current: 60, reference: 50))
        #expect(Self.make(.hrv, series: Self.series(.hrv, [60])).delta == nil)
        #expect(Self.make(.hrv, series: Self.series(.hrv, [50, nil, nil, nil, nil, nil, nil, 60])).delta == nil,
                "the only earlier value is 7 days back")
    }

    @Test("Spec 29: the band is mean ± 1 SD of the 30 days before the newest value; the newest reads within, above or below it",
          arguments: [(65.0, TrendLine.Ending.within), (70, .within), (75, .above), (55, .below)])
    func usualRange(_ newest: Double, _ ending: TrendLine.Ending) {
        // API-shaped: one point per day, oldest first; 60 and 70 in turn before the newest: mean 65, SD 5.
        let month = Self.series(.readiness, [60, 70, 60, 70, 60, 70, 60, 70, newest])
        let card = Self.make(.readiness, series: month, monthly: month)
        #expect(card.band == 60...70)
        #expect(TrendLine.ending(values: card.values, band: card.band) == ending)
        #expect(card.chartEnding == TrendLine.spoken(ending))
    }

    @Test("Spec 29: the four banded metrics only; 7 values before the newest make a band, 6 don't")
    func bands() {
        let month = Self.series(.hrv, [60, 70, 60, 70, 60, 70, 60, 70, 66])
        for metric in TrendMetric.allCases {
            let card = Self.make(metric, series: Self.series(metric, [55, 60]), monthly: month)
            #expect((card.band == 60...70) == [.readiness, .hrv, .sleepMin, .rhr].contains(metric), "\(metric)")
        }
        #expect(Set(TrendMetric.banded) == [.readiness, .hrv, .sleepMin, .rhr])
        let seven = Self.series(.hrv, [60, 70, 60, 70, 60, 70, 65, 66])
        #expect(Self.make(.hrv, series: seven, monthly: seven).band != nil)
        let six = Self.series(.hrv, [60, 70, 60, 70, 60, 70, 66])
        let short = Self.make(.hrv, series: six, monthly: six)
        #expect(short.band == nil)
        #expect(short.note == String(localized: "Usual range needs 7 days of data"))
    }

    @Test("Spec 29: \"Band needs…\" only with the 30-day series loaded; without it, the metric's own note")
    func noBandUntilLoaded() {
        let s = Self.series(.readiness, [70, 72, 74], avg: 72)
        let card = Self.make(.readiness, series: s, monthly: nil)
        #expect(card.band == nil)
        #expect(card.note == String(localized: "Avg \(MetricSpec.readiness.number(72))"))
        #expect(Self.make(.hrv, series: Self.series(.hrv, [60]), monthly: nil).note == String(localized: "SDNN"))
    }

    @Test("Spec 29: the notes: readiness names the band, HRV says SDNN, the others their average")
    func notes() {
        let month = Self.series(.hrv, [60, 70, 60, 70, 60, 70, 60, 70, 66])
        #expect(Self.make(.readiness, series: Self.series(.readiness, [70]), monthly: month).note
                == String(localized: "Shaded: your usual range"))
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
        #expect(hrv.deltaColor(up, spec: .hrv) == Theme.recovery)
        #expect(hrv.deltaColor(down, spec: .hrv) == Theme.alert)
        let readiness = TrendCardStyle(.readiness)
        #expect(readiness.line == Theme.textPrimary && readiness.bandOpacity == 0.06)
        #expect(readiness.deltaColor(up, spec: .readiness) == Theme.recovery)
        #expect(TrendCardStyle(.sleepMin).line == Theme.metricSleep)
        #expect(TrendCardStyle(.strain).line == Theme.metricStrain)
        // Resting HR: lower is better, the good change in ink, never red for good news.
        let rhr = TrendCardStyle(.rhr)
        #expect(rhr.deltaColor(MetricDelta(current: 48, reference: 52), spec: .rhr) == Theme.textPrimary)
        #expect(rhr.deltaColor(MetricDelta(current: 56, reference: 52), spec: .rhr) == Theme.alert)
        // Flat, and a metric with no good direction: secondary ink.
        #expect(hrv.deltaColor(MetricDelta(current: 60.5, reference: 60), spec: .hrv) == Theme.textSecondary)
        #expect(TrendCardStyle(.strain).deltaColor(up, spec: .strain) == Theme.textSecondary)
        // Where DeltaLabel and the card agree (flat, bad, no good direction), the card takes DeltaLabel's ink.
        let flat = MetricDelta(current: 60.5, reference: 60)
        for metric in TrendMetric.allCases {
            let style = TrendCardStyle(metric), spec = metric.spec
            #expect(style.deltaColor(flat, spec: spec) == DeltaLabel.color(flat, spec: spec), "\(metric)")
            let bad = spec.polarity == .lowerIsBetter ? up : down
            if spec.polarity != .neutral { #expect(style.deltaColor(bad, spec: spec) == Theme.alert, "\(metric)") }
        }
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

    @Test("A duration's change reads as on Sleep (\"▲ +17m · +4 %\"), not as a clock: one rule app-wide")
    func durationChanges() throws {
        let nbsp = DeltaLabel.noBreakSpace
        let asleep = Self.make(.sleepMin, series: Self.series(.sleepMin, [451, 451, 468]))
        let delta = try #require(asleep.delta)
        #expect(DeltaLabel.text(delta, spec: asleep.spec) == "▲\(nbsp)+17m · +4\(nbsp)%")
        #expect(asleep.spokenValue.contains(DeltaLabel.spoken(delta, spec: .sleepMin, reference: TrendCardContent.deltaReference)))
    }

    @Test("Spec 29: the 30-day series is fetched for the four banded metrics only, whatever the range")
    func monthlyFetchesFour() async {
        let api = MockPlatformAPI()
        let (state, _) = Self.makeState(api: api)
        let vm = InsightsViewModel(state: state)
        vm.range = .week
        await vm.load()
        #expect(api.count("trends") == TrendMetric.allCases.count + TrendMetric.banded.count)
        for metric in TrendMetric.allCases {
            #expect((state.cachedTrend(metric, range: .month) != nil) == metric.hasBand, "\(metric)")
            #expect((vm.card(metric).band != nil) == metric.hasBand, "\(metric)")
        }
    }

    // MARK: 30. trend states

    @Test("Spec 30: loading with nothing cached is pending: no value, no note, the flat line, read as loading")
    func loading() {
        let card = Self.make(.hrv, series: nil, loading: true)
        #expect(card.isPending && card.latest == nil && card.note == nil && card.delta == nil)
        #expect(card.spokenValue == String(localized: "Loading…"))
        // Nothing cached and nothing in flight (offline, a failed read): "Not loaded", not "No data".
        let none = Self.make(.readiness, series: nil, loading: false)
        #expect(!none.isPending && !none.isLoaded && none.note == String(localized: "Not loaded"))
        #expect(!none.spokenValue.contains(String(localized: "No data")))
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
        let card = Self.make(.readiness, series: Self.series(.readiness, [70]),
                             monthly: Self.series(.readiness, [60, 70, 60, 70, 60, 70, 60, 70, 70]), stale: true)
        let day = Self.today.formatted(.dateTime.month(.abbreviated).day())
        #expect(card.note == String(localized: "As of \(day)"))
    }

    @Test("Spec 30: VoiceOver reads the value, the change, the note and the chart's sentence, ending against the band")
    func spoken() {
        let s = Self.series(.readiness, [60, 70, 60, 70, 60, 70, 60, 70, 78])
        let card = Self.make(.readiness, series: s, monthly: s)
        #expect(card.chartLabel == String(localized: "\(String(localized: "Readiness")) over \(30) days"))
        #expect(card.chartEnding == TrendLine.spoken(.above))
        #expect(card.spokenValue.hasPrefix("78"))
        #expect(card.spokenValue.contains(String(localized: "versus 7 days")))
        #expect(card.spokenValue.contains(String(localized: "Shaded: your usual range")))
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

    // MARK: through the view model (`GET /v1/trends` scripted)

    @Test("S1: one data set gives the same change in 7 D, 30 D and 90 D, and the same as Today's caption", .timeLimit(.minutes(1)))
    func sameDeltaInEveryRange() async throws {
        // The newest 82; six days of 70 before it; 90 seven days back, 10 eight back, 60 before that.
        let readiness = [0: 82.0, 1: 70, 2: 70, 3: 70, 4: 70, 5: 70, 6: 70, 7: 90, 8: 10]
            .merging((9..<90).map { ($0, 60.0) }) { a, _ in a }
        let (vm, state, _) = Self.scripted([.readiness: readiness])
        var captions: [String] = []
        for range in [TrendRange.week, .month, .quarter] {
            vm.range = range
            await vm.load()
            let delta = try #require(vm.card(.readiness).delta, "\(range)")
            #expect(delta == MetricDelta(current: 82, reference: 70), "\(range)")
            captions.append(DeltaLabel.text(delta, spec: .readiness))
        }
        // Today: `TodayViewModel.readinessDelta`, the 7-day series' `vsSevenDayMean`.
        let today = try #require(MetricDelta.vsSevenDayMean(state.readinessWeek?.points ?? []))
        #expect(Set(captions) == [DeltaLabel.text(today, spec: .readiness)])
        #expect(captions.first == "▲\(DeltaLabel.noBreakSpace)+12")
    }

    @Test("S3 (T5.7): Strain and Insights' strain card give the same \"vs 7 d\" for the same day; 2 prior days are enough",
          .timeLimit(.minutes(1)), arguments: [
              // Two days before: both show a change (Strain once needed 3).
              ([0: 13.0, 1: 10, 2: 10], MetricDelta(current: 13, reference: 10)),
              // Days 1, 2 and 6 back count; 7 back (90) is outside the window, for both.
              ([0: 15.0, 1: 10, 2: 12, 6: 11, 7: 90], MetricDelta(current: 15, reference: 11)),
          ])
    func strainAgreesWithInsights(_ row: (strains: [Int: Double], expected: MetricDelta)) async throws {
        let (vm, state, _) = Self.scripted([.strain: row.strains])
        vm.range = .month
        await vm.load()
        let insights = try #require(vm.card(.strain).delta, "Insights' strain card")
        // Strain reads the same days from the cached scores.
        let today = Calendar.current.startOfDay(for: state.env.clock.now())
        state.history = row.strains.map { back, strain in
            DailyScore(day: DayFormat.string(from: DayFormat.shift(today, days: -back)), strain: strain)
        }
        let strain = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        #expect(insights == row.expected)
        #expect(strain.strainDelta == insights)
        #expect(strain.board.hero.delta == insights)
        #expect(DeltaLabel.text(insights, spec: .strain) == DeltaLabel.text(try #require(strain.board.hero.delta), spec: .strain))
    }

    @Test("S2, S4: in 7 D the band comes from the 30-day series (7 and 8 days back count), the change doesn't (they don't)", .timeLimit(.minutes(1)))
    func weekBandAndDelta() async {
        // The newest 56; six days of 50; 40 seven days back, 60 eight back: 8 values before the newest, mean 50, SD 5.
        let hrv = [0: 56.0, 1: 50, 2: 50, 3: 50, 4: 50, 5: 50, 6: 50, 7: 40, 8: 60]
        let (vm, _, _) = Self.scripted([.hrv: hrv])
        vm.range = .week
        await vm.load()
        let card = vm.card(.hrv)
        #expect(card.band == 45...55)
        #expect(card.delta == MetricDelta(current: 56, reference: 50))
        #expect(card.chartEnding == TrendLine.spoken(.above))
        #expect(card.note == String(localized: "SDNN"))
    }

    @Test("S3: a read that fails leaves no series: \"Not loaded\" once the load is over, pending before; no band note", .timeLimit(.minutes(1)))
    func failedRead() async throws {
        let hold = RequestHold()
        let (vm, _, source) = Self.scripted([.readiness: [0: 70, 1: 72]])
        source.holds[.month] = hold
        source.failing = [.readiness, .strain]
        // Before the first load, and while it runs: pending.
        #expect(vm.card(.strain).isPending)
        let load = Task { await vm.load() }
        while hold.waiting == 0 { await Task.yield() }
        #expect(vm.card(.strain).isPending && vm.card(.readiness).note == nil)
        hold.release()
        await load.value
        for metric in [TrendMetric.readiness, .strain] {
            let card = vm.card(metric)
            #expect(!card.isPending && !card.isLoaded && card.latest == nil, "\(metric)")
            #expect(card.note == String(localized: "Not loaded"), "\(metric)")
        }
        // A metric whose read answered with no values: "No data in this range".
        #expect(vm.card(.steps).note == String(localized: "No data in this range"))
    }

    @Test("S3: a range switch in flight: the older loads finishing don't mark the newest one's range", .timeLimit(.minutes(1)))
    func rangeSwitchInFlight() async throws {
        let monthHold = RequestHold(), weekHold = RequestHold()
        let (vm, _, source) = Self.scripted([.readiness: [0: 70, 1: 72]])
        source.holds = [.month: monthHold, .week: weekHold]
        source.failing = [.strain]
        // 30 D, then 7 D, then back to 30 D, each load starting before the one before it ends (`.task(id:)`).
        vm.range = .month
        let first = Task { await vm.load() }
        while monthHold.waiting == 0 { await Task.yield() }
        vm.range = .week
        let second = Task { await vm.load() }
        while weekHold.waiting == 0 { await Task.yield() }
        vm.range = .month
        let third = Task { await vm.load() }
        // The 30-day reads answer: the first and the third load end; the second still waits for its 7-day reads.
        monthHold.release()
        await first.value
        await third.value
        #expect(!vm.isLoadingTrends && vm.loadedRange == .month)
        // The 7-day reads still run (`AppState.isLoading`): a card with nothing cached stays pending, never "Not loaded" while a
        // read is out.
        #expect(vm.card(.strain).isPending)
        // The second, older load ends last: it marks no range, and the card reads "Not loaded".
        weekHold.release()
        await second.value
        #expect(!vm.isLoadingTrends && vm.loadedRange == .month)
        #expect(!vm.card(.strain).isPending && vm.card(.strain).note == String(localized: "Not loaded"))
        // Back on 7 D before its load runs: a card with nothing cached is pending again.
        vm.range = .week
        #expect(vm.card(.strain).isPending)
    }

    // MARK: helpers

    private static func makeState(api: MockPlatformAPI = MockPlatformAPI()) -> (AppState, TestClock) {
        let clock = TestClock()
        return (AppState(env: .test(api: api, clock: clock)), clock)
    }

    /// A view model over `ScriptedTrends`: `values` per metric, days back → value, ending on the test clock's day. Every read
    /// starts at once (the test budget's 3 in flight would queue a held range's reads behind another's).
    private static func scripted(_ values: [TrendMetric: [Int: Double]]) -> (InsightsViewModel, AppState, ScriptedTrends) {
        let clock = TestClock()
        let source = ScriptedTrends(today: clock.now(), values: values)
        let env = AppEnvironment.test(api: MockPlatformAPI(screens: source), clock: clock)
        env.reads.budget = RequestBudget(clock: clock, maxInFlight: 64, maxStarts: .max)
        let state = AppState(env: env)
        return (InsightsViewModel(state: state), state, source)
    }
}

/// `GET /v1/trends` as the platform answers it (one point per day with a value, oldest first, `to` = today), from scripted
/// values; a range's reads can be held, and a metric's can fail. The rest is `MockDataSource`.
private final class ScriptedTrends: RyftDataSource, @unchecked Sendable {
    private let today: Date
    private let values: [TrendMetric: [Int: Double]]
    var holds: [TrendRange: RequestHold] = [:]
    var failing: Set<TrendMetric> = []

    init(today: Date, values: [TrendMetric: [Int: Double]]) {
        self.today = today
        self.values = values
    }

    func trends(metric: TrendMetric, range: TrendRange) async throws -> TrendSeries {
        if let hold = holds[range] { await hold.wait() }
        // Not retried (a 5xx would wait out a backoff on the test clock).
        if failing.contains(metric) { throw APIError.http(404, "not found", requestID: "rid-trends") }
        let byBack = values[metric] ?? [:]
        let points = (0..<range.days).reversed().compactMap { back -> TrendPoint? in
            byBack[back].map { TrendPoint(day: DayFormat.string(from: DayFormat.shift(today, days: -back)), value: $0) }
        }
        let present = points.compactMap(\.value)
        var series = TrendSeries(metric: metric.rawValue, range: range.rawValue, points: points,
                                 avg: present.isEmpty ? nil : present.reduce(0, +) / Double(present.count),
                                 min: present.min(), max: present.max(), baseline: nil)
        series.from = DayFormat.string(from: DayFormat.shift(today, days: -(range.days - 1)))
        series.to = DayFormat.string(from: today)
        return series
    }

    func me() async throws -> User { try await MockDataSource.shared.me() }
    func patchMe(_ p: UserPatch) async throws -> User { try await MockDataSource.shared.patchMe(p) }
    func days(from: Date, to: Date) async throws -> [DailyScore] { try await MockDataSource.shared.days(from: from, to: to) }
    func day(_ date: Date) async throws -> DayDetail { try await MockDataSource.shared.day(date) }
    func sleep(range: SleepRangeKind) async throws -> SleepRange { try await MockDataSource.shared.sleep(range: range) }
    func workouts(from: Date, to: Date) async throws -> [Workout] {
        try await MockDataSource.shared.workouts(from: from, to: to)
    }
    func workout(id: UUID) async throws -> WorkoutDetail { try await MockDataSource.shared.workout(id: id) }
    func insights() async throws -> [Insight] { try await MockDataSource.shared.insights() }
    func recompute(from: Date, to: Date) async throws {}
    func deleteMe() async throws -> AccountDeleted { try await MockDataSource.shared.deleteMe() }
}
