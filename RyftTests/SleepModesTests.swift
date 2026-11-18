import Foundation
import SwiftUI
import Testing
@testable import Ryft

// Sleep → Week, Month and Bedtime in Nocturne, the pure half (docs/work/2026-11-16-nocturne/design.md §P5-12 tests 4, 34–37):
// the measurements, the boards' values and looks, `Fmt.clockParts`, the strip's rows, and the grep for the stage tokens.
// `SleepModesHostedTests` checks the screens in a window.

private let enUS = Locale(identifier: "en_US")
private let enGB = Locale(identifier: "en_GB")

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
        #expect(board.numeralLabel == "\(Fmt.spokenDuration(minutes: average, locale: enUS)) average sleep")
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

    @Test("The \"vs 7 d\" line: the newest night against the seven before it (F6)")
    func theDelta() {
        let range = MockData.sleepRange(.week)
        let board = SleepRangeBoard(range: range, kind: .week)
        #expect(board.delta == .vsSevenDayMean(SleepRangeSummary(range: range).totals))
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
        #expect(board.caption == "In bed by · 100 % of your need")
        let perform = SleepBedtimeBoard(plan: plan, wake: wake, goal: .perform, locale: enUS)
        #expect(perform.digits == Fmt.clockParts(plan.bedtime85, locale: enUS).digits)
        #expect(perform.caption == "In bed by · 85 % of your need")
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
        #expect(board.rows.map(\.share) == ["100 % of your need", "85 % of your need", "70 % of your need"])
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
        #expect(board.tiles[1].notes == [SleepTile.Note(text: "\(plan.efficiency) %", ink: .tertiary)])
        let getBy = SleepBedtimeBoard(plan: plan, wake: wake, goal: .getBy, locale: enUS)
        #expect(getBy.tiles[1].value == Fmt.clock(minutes: Int((Double(plan.inBedMin) * 0.7).rounded())))
    }

    @Test("No schedule: the invitation, no ruler, no tile, no rows")
    func noSchedule() {
        let board = SleepBedtimeBoard(plan: plan, wake: wake, goal: nil)
        #expect(board.look == .noSchedule && board.digits == nil && board.numeralLabel == nil)
        #expect(board.ruler == nil && board.rows.isEmpty && board.tiles.isEmpty && board.plan == nil)
    }

    @Test("Planning: the unlit numeral, the ruler without a needle, three unlit rows, outlines")
    func planning() throws {
        let board = SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, isLoading: true)
        #expect(board.look == .planning && board.digits == nil && board.numeralLabel == "Loading…")
        let ruler = try #require(board.ruler)
        #expect(ruler.value == nil && ruler.zone == nil)
        #expect(board.rows.count == 3 && board.rows.allSatisfy { $0.time == Fmt.placeholder })
        #expect(board.isOutline && board.tiles.map(\.value) == [Fmt.placeholder, Fmt.placeholder])
    }

    @Test("Failed and offline: the message in the tile's place")
    func failedAndOffline() {
        let failed = SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, error: "RYFT is busy.")
        #expect(failed.look == .failed && failed.message == "RYFT is busy.")
        let offline = SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, isOnline: false)
        #expect(offline.look == .offline)
        #expect(offline.message == "Tonight's bedtime needs a connection. It appears once you're online.")
        // A cached plan offline still shows, with its time.
        let cached = SleepBedtimeBoard(plan: plan, wake: wake, goal: .peak, isOnline: false, asOf: wake, locale: enUS)
        #expect(cached.look == .planned && cached.asOf == "As of \(Fmt.time(wake, locale: enUS))")
    }

    @Test("The alarm problem and the schedule's summary pass through; the settings card's need is the plan's")
    func theSettings() {
        let board = SleepBedtimeBoard(plan: plan, wake: wake, goal: .peak, alarmProblem: "The wake-up alarm is off.",
                                      summary: "06:30 · weekend 08:00")
        #expect(board.alarmProblem == "The wake-up alarm is off." && board.summary == "06:30 · weekend 08:00")
        #expect(board.plan == plan && board.asOf == nil)
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
