import Foundation
import SwiftUI
import Testing
@testable import Ryft

// Sleep → Week, Month and Bedtime in Nocturne, the pure half (docs/work/2026-11-16-nocturne/design.md §P5-12 tests 4, 34–37):
// the measurements, the boards' values and looks, `Fmt.clockParts`, the strip's rows, and the grep for the stage tokens.
// `SleepModesHostedTests` checks the screens in a window.

private let enUS = Locale(identifier: "en_US")
private let enGB = Locale(identifier: "en_GB")

/// `Fmt.time` puts U+202F before "AM": compared as a plain space.
private func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }

/// Wednesday 18 November 2026.
private let wednesday = DayFormat.date(from: "2026-11-18") ?? .now

/// Seven nights ending at the week's last day with this consistency each, oldest first.
private func week(consistency: [Int?]) -> SleepRange {
    var range = MockData.sleepRange(.week)
    let end = range.to.flatMap(DayFormat.date(from:)) ?? .now
    range.days = DayFormat.days(endingAt: end, count: consistency.count).enumerated().map { index, day in
        var n = night(day, deep: 90, light: 270, rem: 100)
        n.consistency = consistency[index]
        return n
    }
    range.nights = range.days.count
    range.avgConsistency = 72
    return range
}

/// A night with these stage minutes (Deep, Light, REM), or only a total.
private func night(_ day: String, deep: Int = 0, light: Int = 0, rem: Int = 0, total: Int? = nil) -> SleepNight {
    let stages = [StageShare(stage: .deep, min: deep, pct: nil), StageShare(stage: .light, min: light, pct: nil),
                  StageShare(stage: .rem, min: rem, pct: nil)].filter { $0.min > 0 }
    return SleepNight(day: day, totalMin: total ?? deep + light + rem, stages: stages, quality: 90, start: nil, end: nil,
                      inBedMin: nil, efficiency: nil, qualityLabel: nil, hasStages: !stages.isEmpty, restorative: nil,
                      consistency: 80, napMin: nil)
}

// MARK: - 4. Layout

@MainActor
struct SleepModesLayoutTests {
    @Test("The picker is SegmentedPicker's ink fill: 40 high, padding 3, gap 4, segments 34 with radius 17, control radius 20")
    func thePicker() {
        #expect(SleepModesLayout.pickerHeight == 40 && SleepModesLayout.pickerHeight == SegmentedPickerSpec.controlHeight)
        #expect(SleepModesLayout.pickerPadding == 3 && SleepModesLayout.pickerPadding == SegmentedPickerSpec.padding)
        #expect(SleepModesLayout.pickerGap == 4 && SleepModesLayout.pickerGap == SegmentedPickerSpec.gap)
        #expect(SleepModesLayout.segmentHeight == 34 && SleepModesLayout.segmentHeight == SegmentedPickerSpec.segmentHeight)
        #expect(SleepModesLayout.segmentRadius == 17 && SleepModesLayout.segmentRadius == SegmentedPickerSpec.segmentRadius)
        #expect(SleepModesLayout.controlRadius == 20 && SleepModesLayout.controlRadius == SegmentedPickerSpec.controlRadius)
        // 3 + 34 + 3.
        #expect(SleepModesLayout.pickerPadding * 2 + SleepModesLayout.segmentHeight == SleepModesLayout.pickerHeight)
    }

    @Test("Day's picker is 40 (PR 4's was 52), so its numeral sits 12 higher: +52 against the board")
    func daysPicker() {
        #expect(SleepLayout.pickerHeight == SleepModesLayout.pickerHeight)
        // The board has no picker: the numeral is 12 + the picker under where the board puts it.
        #expect(SleepLayout.pickerGap + SleepLayout.pickerHeight == 52)
        #expect(SleepModesLayout.numeralGap == SleepLayout.numeralGap)
    }

    @Test("The modes' gaps and sizes")
    func theGaps() {
        #expect(SleepModesLayout.numeralGap == 22 && SleepModesLayout.captionGap == 12 && SleepModesLayout.deltaGap == 4)
        #expect(SleepModesLayout.tileGap == 20 && SleepModesLayout.tilesGap == 12 && SleepModesLayout.cardGap == 12)
        #expect(SleepModesLayout.bedWakeMinHeight == SleepLayout.hypnogramHeight)
        #expect(SleepModesLayout.weekRowHeight == 14 && SleepModesLayout.monthRowHeight == 7)
        #expect(SleepModesLayout.stageChartHeight == 150 && SleepModesLayout.stagePlotHeight == 128)
        #expect(SleepModesLayout.stageCardRadius == 22 && SleepModesLayout.stageCardPadding == (top: 14, sides: 16, bottom: 14))
        #expect(SleepModesLayout.stageSegmentGap == 1.5 && SleepModesLayout.stageCornerRadius == 1.5)
        #expect(SleepModesLayout.weekBarRatio == 0.55 && SleepModesLayout.monthBarRatio == 0.7)
        #expect(SleepModesLayout.nightRowHeight == GroupedListSpec.rowMinHeight && SleepModesLayout.nightConsistencyWidth == 44)
        #expect(SleepModesLayout.goToBedMinHeight == 176 && SleepModesLayout.markerSize == 6 && SleepModesLayout.optionTimeSize == 24)
    }

    @Test("The stage tints: Deep 100 %, REM 80 %, Light and Asleep 62 %, Awake not violet")
    func theTints() {
        #expect(SleepStageTint.deep == 1.0 && SleepStageTint.rem == 0.80 && SleepStageTint.light == 0.62)
        #expect(SleepStageTint.asleep == 0.62)
        #expect(SleepStageTint.opacity(.deep) == 1.0 && SleepStageTint.opacity(.rem) == 0.80)
        #expect(SleepStageTint.opacity(.light) == 0.62 && SleepStageTint.opacity(.awake) == nil)
    }
}

// MARK: - 34. Week and Month

@MainActor
struct SleepRangeBoardTests {
    @Test("Week: the numeral is avgTotalMin as a clock, the caption the whole range, the strip 14 pt rows with dates")
    func theWeek() throws {
        let range = MockData.sleepRange(.week)
        let board = SleepRangeBoard(range: range, kind: .week, locale: enUS)
        let average = try #require(range.avgTotalMin)
        #expect(board.look == .loaded)
        #expect(board.clock == Fmt.clock(minutes: average))
        #expect(board.numeralLabel == "Average sleep, \(Fmt.spokenDuration(minutes: average, locale: enUS))")
        #expect(board.caption == (range.nights >= 7 ? "Average · last 7 nights" : "Average · \(range.nights) nights"))
        let strip = try #require(board.strip)
        #expect(strip.rowHeight == 14 && strip.showsRowLabels && strip.bedtimes == range.bedtimes)
        #expect(strip.count == "\(range.bedtimes.count) nights")
        #expect(board.tiles.map(\.kind) == [.quality, .consistency])
        #expect(board.nights.map(\.day) == range.days.reversed().map(\.day), "newest first")
    }

    @Test("Month: 7 pt rows without row labels, bars at 0.7 of a day")
    func theMonth() throws {
        let board = SleepRangeBoard(range: MockData.sleepRange(.month), kind: .month, locale: enUS)
        let strip = try #require(board.strip)
        #expect(strip.rowHeight == 7 && !strip.showsRowLabels)
        #expect(board.stages?.barRatio == 0.7 && board.stages?.window == .month)
        let week = try #require(SleepRangeBoard(range: MockData.sleepRange(.week), kind: .week).stages)
        #expect(week.barRatio == 0.55 && week.window == .week)
    }

    @Test("Fewer nights than the range: \"Average · 4 nights\"")
    func fewerNights() {
        #expect(SleepRangeBoard.caption(nights: 4, kind: .week) == "Average · 4 nights")
        #expect(SleepRangeBoard.caption(nights: 7, kind: .week) == "Average · last 7 nights")
        #expect(SleepRangeBoard.caption(nights: 21, kind: .month) == "Average · 21 nights")
        #expect(SleepRangeBoard.caption(nights: 30, kind: .month) == "Average · last 30 nights")
        var range = MockData.sleepRange(.week)
        range.days = Array(range.days.suffix(4))
        range.nights = 4
        #expect(SleepRangeBoard(range: range, kind: .week).caption == "Average · 4 nights")
    }

    @Test("Consistency: the mean without a unit and the last 7 nights as dots (≥ 60 full, < 60 missed, none no data, the last today)")
    func theConsistencyDots() throws {
        let range = week(consistency: [80, 50, nil, 60, 59, 90, 70])
        let board = SleepRangeBoard(range: range, kind: .week, locale: enUS)
        let tile = try #require(board.tiles.first { $0.kind == .consistency })
        #expect(tile.marks == [.full, .missed, .noData, .full, .missed, .full, .today])
        #expect(tile.value == "72" && tile.unit == nil)
        #expect(tile.spokenValue.hasPrefix("72 out of 100. "), "the scale is said: \(tile.spokenValue)")
        #expect(tile.spokenValue.contains("4 of the last 7 nights were regular"), "\(tile.spokenValue)")
        #expect(tile.spokenValue.contains("the last is the newest night"))
        // Nights the range doesn't have are no data.
        #expect(SleepRangeBoard.consistency(nil, week: [nil, 70]).marks.prefix(6).allSatisfy { $0 == .noData })
        let quality = try #require(board.tiles.first { $0.kind == .quality })
        #expect(quality.value == range.avgQuality.map(String.init) && quality.unit == "%")
    }

    @Test("Stages: Deep at the bottom, then Light, REM on top, 1.5 pt of the card between them; Asleep alone without stages")
    func theStageOrder() throws {
        var range = MockData.sleepRange(.week)
        let days = range.days.map(\.day)
        range.days = [night(days[days.count - 2], deep: 90, light: 270, rem: 100),
                      night(days[days.count - 1], total: 420)]
        range.bedtimes = []
        let stages = try #require(SleepRangeBoard(range: range, kind: .week, locale: enUS).stages)
        let first = stages.segments.filter { $0.day == days[days.count - 2] }
        #expect(first.map(\.stage) == [.deep, .light, .rem])
        let gap = 1.5 * stages.top / 128
        #expect(abs(first[0].lower) < 1e-9 && abs(first[0].upper - (1.5 - gap)) < 1e-9)
        #expect(abs(first[1].lower - 1.5) < 1e-9 && abs(first[1].upper - (6 - gap)) < 1e-9)
        // The top segment ends at the night's total: no gap above it.
        #expect(abs(first[2].lower - 6) < 1e-9 && abs(first[2].upper - (460.0 / 60)) < 1e-9)
        let second = stages.segments.filter { $0.day == days[days.count - 1] }
        #expect(second.map(\.stage) == [nil] && abs(second[0].upper - 7) < 1e-9)
        // The legend in the tints' order, Asleep last when a night has no stages.
        #expect(stages.legend == [.deep, .rem, .light, nil])
        #expect(stages.top == 12 && stages.yTicks == [0, 3, 6, 9, 12])
        #expect(stages.spokenNights.count == 2)
        #expect(stages.spokenNights[0].hasSuffix("Deep 1 hour 30 minutes, REM 1 hour 40 minutes, Light 4 hours 30 minutes"),
                "\(stages.spokenNights[0])")
    }

    @Test("A night over 12 h lifts the axis to the next 3 h")
    func aLongNight() throws {
        var range = MockData.sleepRange(.week)
        range.days = [night(range.days[range.days.count - 1].day, deep: 120, light: 500, rem: 140)]
        let stages = try #require(SleepRangeBoard(range: range, kind: .week).stages)
        #expect(stages.top == 15 && stages.yTicks.last == 15)
    }

    @Test("The stage tints are the sleep violet at 100 / 80 / 62 %, Asleep at 62 %")
    func theStageColours() {
        #expect(SleepStageTint.color(.deep) == Theme.metricSleep.opacity(1.0))
        #expect(SleepStageTint.color(.rem) == Theme.metricSleep.opacity(0.80))
        #expect(SleepStageTint.color(.light) == Theme.metricSleep.opacity(0.62))
        #expect(SleepStageTint.color(nil) == Theme.metricSleep.opacity(0.62))
        #expect(SleepStageTint.color(.awake) == Theme.textTertiary)
    }

    @Test("The \"vs 7 d\" line: the newest night against the six before it in its seven, the same in Week and Month (F6)")
    func theDelta() throws {
        // Oldest first: 300 eight nights back, 600 seven back, six nights of 420, then the newest, 480.
        let totals = [300, 600] + Array(repeating: 420, count: 6) + [480]
        let days = DayFormat.days(endingAt: wednesday, count: totals.count)
        let nights = zip(days, totals).map { night($0, total: $1) }
        let month = SleepRange(range: "month", from: days.first, to: days.last, days: nights, avgTotalMin: 433, avgQuality: 90)
        let week = SleepRange(range: "week", from: days[2], to: days.last, days: Array(nights.suffix(7)), avgTotalMin: 429,
                              avgQuality: 90)
        // 480 against 420: neither the night seven back (600) nor eight back (300) counts.
        let expected = MetricDelta(current: 480, reference: 420)
        let monthBoard = SleepRangeBoard(range: month, kind: .month, today: wednesday)
        let weekBoard = SleepRangeBoard(range: week, kind: .week, today: wednesday)
        #expect(monthBoard.delta == expected && weekBoard.delta == expected)
        #expect(abs((monthBoard.delta?.percent ?? 0) - 100.0 / 7) < 1e-9)
        // A missing newest value: the newest night with one is compared, with the six before it.
        var gap = nights
        gap[gap.count - 1].totalMin = nil
        let older = SleepRange(range: "month", from: days.first, to: days.last, days: gap, avgTotalMin: 433, avgQuality: 90)
        #expect(SleepRangeBoard(range: older, kind: .month, today: wednesday).delta
                == MetricDelta(current: 420, reference: (600.0 + 5 * 420) / 6))
    }

    @Test("The delta names its night: \"Last night\" when it ended this morning, else its weekday")
    func theDeltasNight() throws {
        let monday = try #require(DayFormat.date(from: "2026-11-16"))
        let mondayBefore = try #require(DayFormat.date(from: "2026-11-09"))
        #expect(SleepRangeBoard.lead(night: wednesday, today: wednesday, locale: enUS) == ("Last night", "Last night"))
        #expect(SleepRangeBoard.lead(night: monday, today: wednesday, locale: enUS) == ("Mon", "Monday"))
        let far = SleepRangeBoard.lead(night: mondayBefore, today: wednesday, locale: enUS)
        #expect(far.shown.hasPrefix("Mon") && far.shown.contains("Nov") && far.shown.contains("9"), "\(far.shown)")
        #expect(far.spoken.hasPrefix("Monday") && far.spoken.contains("November"), "\(far.spoken)")
        // The board: a week whose newest night is Monday's, read on Wednesday.
        let days = DayFormat.days(endingAt: monday, count: 3)
        let range = SleepRange(range: "week", from: days.first, to: "2026-11-18", days: days.map { night($0, total: 420) },
                               avgTotalMin: 420, avgQuality: 90)
        let board = SleepRangeBoard(range: range, kind: .week, today: wednesday, locale: enUS)
        #expect(board.deltaLead == "Mon" && board.spokenDeltaLead == "Monday")
        let today = SleepRangeBoard(range: range, kind: .week, today: monday, locale: enUS)
        #expect(today.deltaLead == "Last night")
    }

    @Test("\"As of\" its last day: offline or after a failed read, or when the range doesn't end today")
    func theAsOfNote() {
        let days = DayFormat.days(endingAt: wednesday, count: 3)
        let range = SleepRange(range: "week", from: days.first, to: days.last, days: days.map { night($0, total: 420) },
                               avgTotalMin: 420, avgQuality: 90)
        #expect(SleepRangeBoard(range: range, kind: .week, today: wednesday, locale: enUS).asOf == nil)
        #expect(SleepRangeBoard(range: range, kind: .week, isStale: true, today: wednesday, locale: enUS).asOf == "As of Nov 18")
        let thursday = DayFormat.shift(wednesday, days: 1)
        #expect(SleepRangeBoard(range: range, kind: .week, today: thursday, locale: enUS).asOf == "As of Nov 18")
        // Nothing to date without a range.
        #expect(SleepRangeBoard(range: nil, kind: .week, isStale: true, today: wednesday).asOf == nil)
    }

    @Test("Without an average the numeral is silent: the caption says it once")
    func noAverage() {
        var range = MockData.sleepRange(.week)
        range.avgTotalMin = nil
        let board = SleepRangeBoard(range: range, kind: .week)
        #expect(board.clock == nil && board.numeralLabel == nil && !board.caption.isEmpty)
    }

    @Test("The 4-night preview's averages are its 4 nights'")
    func theFewNightsPreview() throws {
        let nights = Array(MockData.sleepRange(.week).days.suffix(4))
        let totals = nights.compactMap(\.totalMin)
        let mean = Int((Double(totals.reduce(0, +)) / Double(totals.count)).rounded())
        let board = SleepRangePreviewPage(.fewNights).board
        #expect(board.clock == Fmt.clock(minutes: mean) && board.caption == "Average · 4 nights")
        #expect(board.strip?.bedtimes.map(\.day).allSatisfy { day in nights.contains { $0.day == day } } == true)
    }

    @Test("Loading, no sleep and a failed load")
    func theLooks() {
        let loading = SleepRangeBoard(range: nil, kind: .week, isLoading: true)
        #expect(loading.look == .loading && loading.clock == nil && loading.numeralLabel == "Loading…")
        #expect(loading.isOutline && loading.tiles.map(\.value) == [Fmt.placeholder, Fmt.placeholder])
        let empty = SleepRangeBoard(range: nil, kind: .month)
        #expect(empty.look == .empty && empty.numeralLabel == nil && empty.caption.isEmpty && empty.strip == nil)
        var none = MockData.sleepRange(.week)
        none.days = []
        none.nights = 0
        #expect(SleepRangeBoard(range: none, kind: .week).look == .empty)
        let failure = SleepLoadFailure(reason: .busy, details: "HTTP 503")
        let failed = SleepRangeBoard(range: nil, kind: .week, failure: failure)
        #expect(failed.look == .failed && failed.failure == failure)
        // A cached range wins over a failure: the values stay.
        #expect(SleepRangeBoard(range: MockData.sleepRange(.week), kind: .week, failure: failure).look == .loaded)
    }
}

// MARK: - 35. Fmt.clockParts

struct ClockPartsTests {
    @Test("Splits the digits from the meridiem on any whitespace", arguments: ["10:06\u{202F}PM", "10:06\u{00A0}PM", "10:06 PM"])
    func splits(_ text: String) {
        let parts = Fmt.clockParts(text)
        #expect(parts.digits == "10:06" && parts.meridiem == "PM")
    }

    @Test("A 24-hour time has no meridiem; an empty string none either; a meridiem before the digits is found")
    func edges() {
        #expect(Fmt.clockParts("22:06") == ("22:06", nil))
        #expect(Fmt.clockParts("") == ("", nil))
        #expect(Fmt.clockParts("PM 10:06") == ("10:06", "PM"))
    }

    @Test("From a date: en_US has a meridiem, en_GB none")
    func fromADate() throws {
        let date = try #require(Calendar.current.date(bySettingHour: 22, minute: 6, second: 0, of: .now))
        let us = Fmt.clockParts(date, locale: enUS)
        #expect(us.digits == "10:06" && us.meridiem == "PM")
        let gb = Fmt.clockParts(date, locale: enGB)
        #expect(gb.digits == "22:06" && gb.meridiem == nil)
    }

    @Test("The digits are dot glyphs, not the Light fallback")
    func theDigitsAreDots() {
        #expect(DotNumeral.cells("10:06", placeholder: "00:00", glyphGap: DotNumeral.glyphGapDetail) != nil)
        #expect(DotNumeral.cells("10:06\u{202F}PM", placeholder: "00:00", glyphGap: DotNumeral.glyphGapDetail) == nil,
                "the whole time would fall back to Light")
    }
}

// MARK: - 36. Bedtime

@MainActor
struct SleepBedtimeBoardTests {
    private let plan = MockJournal.sleepPlan(wake: "07:00")
    private var wake: Date { plan.wake }

    @Test("The numeral is the goal's bedtime, digits and meridiem apart; the caption its share")
    func theNumeral() {
        let board = SleepBedtimeBoard(plan: plan, wake: wake, goal: .peak, locale: enUS)
        let parts = Fmt.clockParts(plan.bedtime100, locale: enUS)
        #expect(board.look == .planned && board.digits == parts.digits && board.meridiem == parts.meridiem)
        #expect(board.numeralLabel == "Go to bed at \(Fmt.time(plan.bedtime100, locale: enUS))")
        #expect(board.caption == "In bed by · 100\u{00A0}% of your need")
        let perform = SleepBedtimeBoard(plan: plan, wake: wake, goal: .perform, locale: enUS)
        #expect(perform.digits == Fmt.clockParts(plan.bedtime85, locale: enUS).digits)
        #expect(perform.caption == "In bed by · 85\u{00A0}% of your need")
        // 24-hour: no meridiem.
        #expect(SleepBedtimeBoard(plan: plan, wake: wake, goal: .peak, locale: enGB).meridiem == nil)
    }

    @Test("The ruler: the needle at the goal's sleep, the zone 90–100 % of the need, \"need 8:01\" in the middle")
    func theRuler() throws {
        let board = SleepBedtimeBoard(plan: plan, wake: wake, goal: .perform, locale: enUS)
        let ruler = try #require(board.ruler)
        let need = Double(plan.needMin) / 60
        #expect(ruler.value == Double(SleepBedtimeBoard.sleepMin(plan, goal: .perform)) / 60)
        let zone = try #require(ruler.zone)
        #expect(abs(zone.lowerBound - 0.9 * need) < 1e-9 && abs(zone.upperBound - need) < 1e-9)
        #expect(ruler.labels == ["0 h", "need \(Fmt.clock(minutes: plan.needMin))", "10 h"])
    }

    @Test("Three rows, earliest first, the goal's marker on one")
    func theRows() {
        let board = SleepBedtimeBoard(plan: plan, wake: wake, goal: .perform, locale: enUS)
        #expect(board.rows.map(\.goal) == [.peak, .perform, .getBy])
        #expect(board.rows.map(\.isGoal) == [false, true, false])
        #expect(board.rows.map(\.time) == [plan.bedtime100, plan.bedtime85, plan.bedtime70].map { Fmt.time($0, locale: enUS) })
        #expect(board.rows.map(\.share) == ["100\u{00A0}% of your need", "85\u{00A0}% of your need", "70\u{00A0}% of your need"])
        #expect(board.rows[0].asleep == "\(Fmt.duration(minutes: plan.needMin)) asleep")
        #expect(board.rows[1].spoken.hasSuffix("your goal") && !board.rows[0].spoken.contains("your goal"))
        #expect(board.wake == "wake \(Fmt.time(plan.wake, locale: enUS))")
        #expect(board.spokenTile.hasPrefix(board.wake))
    }

    @Test("Need and Time in bed: the clock and \"h\", the efficiency as the note; the goal's share of the time in bed")
    func theTiles() {
        let board = SleepBedtimeBoard(plan: plan, wake: wake, goal: .peak, locale: enUS)
        #expect(board.tiles.map(\.kind) == [.need, .timeInBed])
        #expect(board.tiles[0].value == Fmt.clock(minutes: plan.needMin) && board.tiles[0].unit == "h")
        #expect(board.tiles[1].value == Fmt.clock(minutes: plan.inBedMin))
        #expect(board.tiles[1].notes == [SleepTile.Note(text: "\(plan.efficiency)\u{00A0}%", ink: .tertiary)])
        let getBy = SleepBedtimeBoard(plan: plan, wake: wake, goal: .getBy, locale: enUS)
        #expect(getBy.tiles[1].value == Fmt.clock(minutes: Int((Double(plan.inBedMin) * 0.7).rounded())))
    }

    @Test("No schedule: the three bedtimes for the wake time asked, without a goal; no ruler, no tiles; the need's terms")
    func noSchedule() {
        let board = SleepBedtimeBoard(plan: plan, wake: wake, goal: nil, summary: BedtimePlanner.summary(nil), locale: enUS)
        #expect(!board.hasSchedule && board.look == .planned && board.digits == nil && board.numeralLabel == nil)
        #expect(board.caption.isEmpty && board.ruler == nil && board.tiles.isEmpty)
        #expect(board.rows.map(\.time) == [plan.bedtime100, plan.bedtime85, plan.bedtime70].map { Fmt.time($0, locale: enUS) })
        #expect(board.rows.allSatisfy { !$0.isGoal && !$0.spoken.contains("your goal") })
        #expect(board.plan == plan && board.summary == "Off", "Why this need, and Bedtime & wake says Off")
        // While it plans: unlit rows, no "Loading…" numeral (there is no goal to load).
        let planning = SleepBedtimeBoard(plan: nil, wake: wake, goal: nil, isLoading: true)
        #expect(planning.look == .planning && planning.numeralLabel == nil && planning.rows.count == 3 && planning.tiles.isEmpty)
    }

    @Test("Planning: the unlit numeral, the ruler without a needle, three unlit rows, outlines")
    func planning() throws {
        let board = SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, isLoading: true)
        #expect(board.look == .planning && board.digits == nil && board.numeralLabel == "Loading…")
        let ruler = try #require(board.ruler)
        #expect(ruler.value == nil && ruler.zone == nil)
        // Its own sentence, not Day's "No time asleep yet".
        #expect(ruler.spokenValue == SleepBedtimeBoard.rulerPlaceholder)
        #expect(ruler.spokenValue != SleepRuler(totalMin: nil, needMin: nil).spokenValue)
        #expect(board.rows.count == 3 && board.rows.allSatisfy { $0.time == Fmt.placeholder })
        #expect(board.isOutline && board.tiles.map(\.value) == [Fmt.placeholder, Fmt.placeholder])
    }

    @Test("Failed and offline: the calm sentence with Details in the tile's place; offline is said first")
    func failedAndOffline() {
        let failure = SleepLoadFailure(reason: .busy, details: "HTTP 503 · Request ID r-plan")
        let failed = SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, failure: failure)
        #expect(failed.look == .failed && failed.message == RefreshIssue.Reason.busy.message)
        #expect(failed.failure?.details == "HTTP 503 · Request ID r-plan" && failed.failure?.action == .retry)
        let offline = SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, isOnline: false)
        #expect(offline.look == .offline && offline.failure == nil)
        #expect(offline.message == "Tonight's bedtime needs a connection. It appears once you're online.")
        // A failure from before the connection went: offline.
        #expect(SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, failure: failure, isOnline: false).look == .offline)
        // A cached plan offline still shows, with its time.
        let cached = SleepBedtimeBoard(plan: plan, wake: wake, goal: .peak, isOnline: false, asOf: wake, locale: enUS)
        #expect(cached.look == .planned && cached.asOf == "As of \(Fmt.time(wake, locale: enUS))")
    }

    @Test("The alarm problem and the schedule's summary pass through; the settings card's need is the plan's")
    func theSettings() {
        let summary = BedtimePlanner.summary(.default, locale: enUS)
        let board = SleepBedtimeBoard(plan: plan, wake: wake, goal: .peak, alarmProblem: "The wake-up alarm is off.",
                                      summary: summary)
        #expect(board.alarmProblem == "The wake-up alarm is off." && board.summary == summary)
        #expect(board.plan == plan && board.asOf == nil)
    }

    @Test("Bedtime & wake's summary in the locale's clock: 12-hour in en_US, 24-hour in en_GB (Profile's row too)")
    func theSummary() {
        // en_GB's short time is 24-hour; whether it has a leading zero is the system's (iOS 27: "6:30").
        #expect(plain(BedtimePlanner.summary(.default, locale: enUS)) == "6:30 AM · weekend 8:00 AM")
        let gb = BedtimePlanner.summary(.default, locale: enGB)
        #expect(["6:30 · weekend 8:00", "06:30 · weekend 08:00"].contains(gb), "\(gb)")
        let everyDay = SleepSchedule(wake: Array(repeating: "06:30", count: 7))
        #expect(plain(BedtimePlanner.summary(everyDay, locale: enUS)) == "6:30 AM")
        #expect(["6:30", "06:30"].contains(BedtimePlanner.summary(everyDay, locale: enGB)))
        #expect(BedtimePlanner.summary(nil, locale: enUS) == "Off")
    }

    @Test("The strip's means in the locale's clock")
    func theStripsMeans() throws {
        let cal = Calendar.current
        let wake = try #require(cal.date(bySettingHour: 6, minute: 41, second: 0, of: wednesday))
        let bed = wake.addingTimeInterval(-(7 * 60 + 53) * 60)   // 22:48 the evening before
        let layout = BedtimeLayout([SleepBedtime(day: "2026-11-18", bed: bed, wake: wake)])
        #expect(plain(layout.spoken(locale: enUS)) == "Mean bedtime 10:48 PM, mean wake time 6:41 AM")
        let gb = layout.spoken(locale: enGB)
        #expect(["Mean bedtime 22:48, mean wake time 6:41", "Mean bedtime 22:48, mean wake time 06:41"].contains(gb), "\(gb)")
    }
}

// MARK: - the strip's rows

struct BedtimeStripRowTests {
    @Test("Row centres: the newest night at the bottom, half a row up; a y finds its row")
    func rows() {
        #expect(BedtimeLayout.rowCentre(0, count: 7) == 6.5)
        #expect(BedtimeLayout.rowCentre(6, count: 7) == 0.5)
        #expect(BedtimeLayout.row(at: 6.9, count: 7) == 0)
        #expect(BedtimeLayout.row(at: 0.1, count: 7) == 6)
        #expect(BedtimeLayout.row(at: 7.5, count: 7) == nil && BedtimeLayout.row(at: -0.5, count: 7) == nil)
    }

    @Test("At accessibility sizes the clock and the hours label every other tick")
    func everyOtherTick() {
        #expect(SleepModesLayout.everyOther([0, 120, 240, 360, 480, 600, 720, 840]) == [0, 240, 480, 720])
        #expect(SleepModesLayout.everyOther([0, 3, 6, 9, 12]) == [0, 6, 12])
    }
}

// MARK: - 37. Day's lower cards: no stage blue

struct SleepStageTokenTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Ryft")

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("SleepNeedBar, StageRow, the strip and the modes use no stage token, no metricStrain and no accent",
          arguments: ["Design/SleepNeedBar.swift", "Design/StageRow.swift", "Design/BedtimeStrip.swift",
                      "Features/Sleep/SleepRangeSection.swift", "Features/Sleep/SleepBedtimeSection.swift",
                      "Features/Sleep/SleepView.swift"])
    func noStageBlue(_ path: String) throws {
        let text = try Self.source(path)
        for token in ["Theme.stage", "Theme.color(for:", "metricStrain", "accentSecondary", "Theme.accent"] {
            #expect(!text.contains(token), "\(path) uses \(token)")
        }
    }

    /// The stage tokens' callers outside `Theme.swift`: none in Sleep. RestTimerView (Train, PR 6 B) is the last; drop it from
    /// the list when its rest ring moves to the Nocturne tokens.
    @Test("The stage tokens have no caller in Sleep, Today or the design system")
    func theStageTokensCallers() throws {
        let known: Set<String> = ["Features/Train/Session/RestTimerView.swift"]
        let pattern = try Regex(#"Theme\.(stageDeep|stageLight|stageREM|stageAwake)\b|Theme\.color\(for: *\.(deep|light|rem|awake)\b"#)
        // /tmp is a link to /private/tmp: both sides resolved, so the relative paths line up.
        let root = Self.root.resolvingSymlinksInPath().path
        let files = try #require(FileManager.default.enumerator(at: Self.root, includingPropertiesForKeys: nil))
        var callers: Set<String> = []
        for case let url as URL in files where url.pathExtension == "swift" && url.lastPathComponent != "Theme.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains(pattern) {
                callers.insert(String(url.resolvingSymlinksInPath().path.dropFirst(root.count + 1)))
            }
        }
        #expect(callers.isSubset(of: known), "\(callers.subtracting(known).sorted())")
        #expect(!callers.contains { $0.hasPrefix("Features/Sleep/") || $0.hasPrefix("Features/Today/") || $0.hasPrefix("Design/") })
    }
}

/// The stage chart's date row (§P5-7.3): labels centred under their bars, inside the plot, colliding ones left out.
struct SleepStageAxisRowTests {
    @Test func labelsAreCentredOnTheirBars() {
        let positions = SleepStageAxisRow.positions(centres: [22, 66, 110], widths: [8, 10, 12], width: 132)
        #expect(positions == [18, 61, 104])
    }

    @Test func edgeLabelsStayInsideThePlot() {
        let positions = SleepStageAxisRow.positions(centres: [5, 300], widths: [34, 34], width: 305)
        #expect(positions == [0, 271])
    }

    @Test func aCollidingLabelIsLeftOutAndTheNewestKept() {
        // 66 wide on a 70 pitch: each label would come within 6 of the next, so every other one shows, newest first.
        let positions = SleepStageAxisRow.positions(centres: [35, 105, 175, 245, 315], widths: [66, 66, 66, 66, 66], width: 350)
        #expect(positions == [2, nil, 142, nil, 282])
    }
}

// MARK: - the view model: loads, the planner's wake, failures

/// `MockDataSource` with the night's detail and each sleep range held until a test lets it go, then answering with a scripted
/// range (else the mock's) or failing.
final class HeldSleepReads: RyftDataSource, @unchecked Sendable {
    enum Route: Hashable { case day, week, month }

    let dayHold = RequestHold(), weekHold = RequestHold(), monthHold = RequestHold()
    private let lock = NSLock()
    private var ranges: [SleepRangeKind: SleepRange] = [:]
    private var errors: [Route: Error] = [:]

    init(held: Bool = true) {
        if !held {
            dayHold.release()
            weekHold.release()
            monthHold.release()
        }
    }

    func answer(_ kind: SleepRangeKind, with range: SleepRange) { lock.withLock { ranges[kind] = range } }
    func fail(_ route: Route, with error: Error?) { lock.withLock { errors[route] = error } }
    private func error(_ route: Route) -> Error? { lock.withLock { errors[route] } }

    func day(_ date: Date) async throws -> DayDetail {
        await dayHold.wait()
        if let error = error(.day) { throw error }
        return try await MockDataSource.shared.day(date)
    }

    func sleep(range: SleepRangeKind) async throws -> SleepRange {
        await (range == .week ? weekHold : monthHold).wait()
        if let error = error(range == .week ? .week : .month) { throw error }
        if let scripted = lock.withLock({ ranges[range] }) { return scripted }
        return try await MockDataSource.shared.sleep(range: range)
    }

    func me() async throws -> User { try await MockDataSource.shared.me() }
    func patchMe(_ p: UserPatch) async throws -> User { try await MockDataSource.shared.patchMe(p) }
    func days(from: Date, to: Date) async throws -> [DailyScore] { try await MockDataSource.shared.days(from: from, to: to) }
    func workouts(from: Date, to: Date) async throws -> [Workout] {
        try await MockDataSource.shared.workouts(from: from, to: to)
    }
    func workout(id: UUID) async throws -> WorkoutDetail { try await MockDataSource.shared.workout(id: id) }
    func trends(metric: TrendMetric, range: TrendRange) async throws -> TrendSeries {
        try await MockDataSource.shared.trends(metric: metric, range: range)
    }
    func insights() async throws -> [Insight] { try await MockDataSource.shared.insights() }
    func recompute(from: Date, to: Date) async throws {}
    func deleteMe() async throws -> AccountDeleted { try await MockDataSource.shared.deleteMe() }
}

@MainActor
@Suite(.serialized) struct SleepModesModelTests {
    /// 19 October 2026 (the test clock's day), 08:00 and 21:00.
    nonisolated private static let day = Date(timeIntervalSince1970: 1_792_400_000)
    nonisolated private static let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
    nonisolated private static let evening = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: day) ?? day

    private func model(_ source: HeldSleepReads, at now: Date = morning) throws -> (SleepViewModel, AppState, TestClock,
                                                                                     MockPlatformAPI) {
        let clock = TestClock(now: now)
        let api = MockPlatformAPI(screens: source)
        let state = AppState(env: .test(api: api, clock: clock))
        try #require(state.hasDataSource, "the test environment is signed in and configured")
        return (SleepViewModel(state: state), state, clock, api)
    }

    /// Three nights ending on `end`, each woken at `wake` (hour, minute), as `GET /v1/sleep` sends them.
    private func range(_ kind: SleepRangeKind, endingOn end: Date, wake: (Int, Int) = (6, 52)) -> SleepRange {
        let days = DayFormat.days(endingAt: end, count: 3)
        let bedtimes = days.compactMap { day -> SleepBedtime? in
            guard let date = DayFormat.date(from: day),
                  let woke = Calendar.current.date(bySettingHour: wake.0, minute: wake.1, second: 0, of: date) else { return nil }
            return SleepBedtime(day: day, bed: woke.addingTimeInterval(-8 * 3_600), wake: woke)
        }
        return SleepRange(range: kind.rawValue, from: days.first, to: days.last,
                          days: days.map { night($0, deep: 90, light: 270, rem: 100) }, avgTotalMin: 460, avgQuality: 90,
                          bedtimes: bedtimes)
    }

    // MARK: S3

    @Test("Day → Week → Month in flight: the late errors of Day and Week land nowhere, and Month shows loading until it answers")
    func aReplacedLoadWritesNothing() async throws {
        let source = HeldSleepReads()
        source.fail(.day, with: APIError.http(404, "not found", requestID: "r-day"))
        source.fail(.week, with: APIError.http(404, "not found", requestID: "r-week"))
        source.answer(.month, with: range(.month, endingOn: Self.morning))
        let (vm, _, _, _) = try model(source)
        vm.mode = .day
        let day = Task { await vm.load() }
        #expect(await eventually { source.dayHold.waiting == 1 })
        vm.mode = .week
        let week = Task { await vm.load() }
        #expect(await eventually { source.weekHold.waiting == 1 })
        vm.mode = .month
        let month = Task { await vm.load() }
        #expect(await eventually { source.monthHold.waiting == 1 })
        #expect(vm.isLoading && vm.rangeBoard.look == .loading)

        source.dayHold.release()
        await day.value
        #expect(vm.failure == nil && vm.isLoading && vm.rangeBoard.look == .loading, "Day's error isn't Month's")
        source.weekHold.release()
        await week.value
        #expect(vm.failure == nil && vm.isLoading && vm.rangeBoard.look == .loading, "nor Week's, and no empty state")
        source.monthHold.release()
        await month.value
        #expect(!vm.isLoading && vm.failure == nil && vm.rangeBoard.look == .loaded)
    }

    @Test("Week → Day with Week in flight: Week's late error doesn't land on Day")
    func aRangesErrorStaysOffDay() async throws {
        let source = HeldSleepReads()
        source.fail(.week, with: APIError.http(404, "not found", requestID: "r-week"))
        let (vm, _, _, _) = try model(source)
        vm.mode = .week
        let week = Task { await vm.load() }
        #expect(await eventually { source.weekHold.waiting == 1 })
        vm.mode = .day
        let day = Task { await vm.load() }
        #expect(await eventually { source.dayHold.waiting == 1 })
        source.weekHold.release()
        await week.value
        #expect(vm.failure == nil && vm.isLoading, "Day is still loading")
        source.dayHold.release()
        await day.value
        #expect(vm.failure == nil && !vm.isLoading)
    }

    // MARK: S5, S8: Week and Month failing

    @Test("Week and Month failing: nothing cached says why with Details; a cached copy stays \"As of\" its day until a read succeeds")
    func failingRanges() async throws {
        let source = HeldSleepReads(held: false)
        source.answer(.week, with: range(.week, endingOn: Self.morning))
        let (vm, _, clock, _) = try model(source)
        vm.mode = .week
        await vm.load()
        #expect(vm.rangeBoard(locale: enUS).look == .loaded && vm.rangeBoard(locale: enUS).asOf == nil)

        // An hour later the week is read again, and fails: the copy stays, dated.
        clock.advance(by: .seconds(2 * 3_600))
        source.fail(.week, with: APIError.http(404, "not found", requestID: "r-week"))
        await vm.load()
        #expect(vm.failure == nil && vm.staleRanges == [.week])
        #expect(vm.rangeBoard(locale: enUS).look == .loaded && vm.rangeBoard(locale: enUS).asOf == "As of Oct 19")

        // Month has nothing cached: the calm sentence and the request ID, not the system's text.
        source.fail(.month, with: APIError.http(404, "not found", requestID: "r-month"))
        vm.mode = .month
        await vm.load()
        let failed = vm.rangeBoard(locale: enUS)
        #expect(failed.look == .failed && failed.failure?.details == "HTTP 404 · Request ID r-month")
        #expect(failed.failure?.message.contains("not found") == false)

        // Week again, answering: no note.
        source.fail(.week, with: nil)
        vm.mode = .week
        clock.advance(by: .seconds(2 * 3_600))
        await vm.load()
        #expect(vm.staleRanges.isEmpty && vm.rangeBoard(locale: enUS).asOf == nil)
    }

    // MARK: B1

    @Test("Bedtime follows Bedtime & wake: schedule 06:30 over a cached wake of 06:52 says \"wake 6:30 AM\" and Tonight's bedtime")
    func bedtimeFollowsTheSchedule() async throws {
        let source = HeldSleepReads(held: false)
        source.answer(.week, with: range(.week, endingOn: Self.evening, wake: (6, 52)))
        let (_, state, clock, api) = try model(source, at: Self.evening)
        try await state.repository.refreshSleepRange(.week)
        let vm = SleepViewModel(state: state)
        #expect(vm.planner.wakeText == "06:52", "the last wake slept, before Bedtime is entered")

        let bedtime = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await bedtime.update(SleepSchedule(wake: Array(repeating: "06:30", count: 7)))
        let tonight = try #require(bedtime.bedtime)
        vm.mode = .plan
        await vm.load(bedtime: bedtime)
        var board = vm.bedtimeBoard(bedtime, locale: enUS)
        #expect(plain(board.wake) == "wake 6:30 AM")
        #expect(board.digits == Fmt.clockParts(tonight, locale: enUS).digits && board.meridiem == "PM",
                "Today's Tonight card's bedtime")
        #expect(api.planWakes.allSatisfy { $0 == "06:30" })

        // The picker moves: the board shows the picker's plan, also after a refresh.
        let picked = try #require(Calendar.current.date(bySettingHour: 7, minute: 15, second: 0, of: vm.planner.wake))
        vm.planner.setWake(picked)
        #expect(await eventually { clock.pendingSleeps >= 1 })
        clock.advance(by: SleepPlannerViewModel.debounce)
        await vm.planner.settle()
        await vm.load(bedtime: bedtime)
        board = vm.bedtimeBoard(bedtime, locale: enUS)
        #expect(plain(board.wake) == "wake 7:15 AM" && vm.planner.wakeText == "07:15")

        // A new schedule is followed again.
        await bedtime.update(SleepSchedule(wake: Array(repeating: "07:00", count: 7)))
        await vm.load(bedtime: bedtime)
        board = vm.bedtimeBoard(bedtime, locale: enUS)
        let seven = try #require(bedtime.bedtime)
        #expect(plain(board.wake) == "wake 7:00 AM" && board.digits == Fmt.clockParts(seven, locale: enUS).digits)

        // Leaving Bedtime and coming back after the picker moved: the schedule's again.
        vm.planner.setWake(picked)
        vm.mode = .week
        await vm.load(bedtime: bedtime)
        vm.mode = .plan
        await vm.load(bedtime: bedtime)
        #expect(plain(vm.bedtimeBoard(bedtime, locale: enUS).wake) == "wake 7:00 AM")
    }

    @Test("Without a schedule the planner keeps the last wake slept, and its three bedtimes")
    func noScheduleKeepsThePlanner() async throws {
        let source = HeldSleepReads(held: false)
        source.answer(.week, with: range(.week, endingOn: Self.evening, wake: (6, 52)))
        let (_, state, _, api) = try model(source, at: Self.evening)
        try await state.repository.refreshSleepRange(.week)
        let vm = SleepViewModel(state: state)
        let bedtime = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        vm.mode = .plan
        await vm.load(bedtime: bedtime)
        let board = vm.bedtimeBoard(bedtime, locale: enUS)
        #expect(!board.hasSchedule && board.rows.count == 3 && board.look == .planned)
        #expect(api.planWakes == ["06:52"] && board.summary == "Off")
    }

    // MARK: S6

    @Test("A failed plan says why in the app's words, with the request ID behind Details")
    func aFailedPlan() async throws {
        let api = MockPlatformAPI()
        let clock = TestClock(now: Self.evening)
        let state = AppState(env: .test(api: api, clock: clock))
        let error = APIError.http(503, "upstream unavailable", requestID: "r-plan")
        api.failure = error
        let planner = SleepPlannerViewModel(state: state)
        await planner.load()
        let failure = try #require(planner.failure)
        #expect(failure.details == "HTTP 503 · Request ID r-plan")
        #expect(failure.message != error.localizedDescription && !failure.message.contains("upstream"))
        #expect(failure == SleepLoadFailure(error, isOnline: true, at: clock.now()))
        let board = SleepBedtimeBoard(plan: planner.plan, wake: planner.wake, goal: .peak, failure: planner.failure)
        #expect(board.look == .failed && board.message == failure.message && board.failure == failure)
    }
}
