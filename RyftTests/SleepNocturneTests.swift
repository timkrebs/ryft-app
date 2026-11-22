import Foundation
import SwiftUI
import Testing
@testable import Ryft

// Sleep → Day in Nocturne, the pure half (docs/work/2026-11-16-nocturne/design.md §P4-11 tests 1 (Sleep), 5, 6, 26–31):
// the measurements, the board's values and looks, the header, the night stepping, the ruler, the hypnogram tile and the
// four tiles. `SleepNocturneHostedTests` checks the same in a window.

private let enUS = Locale(identifier: "en_US")

private func date(_ day: String) -> Date { DayFormat.date(from: day) ?? .distantPast }

/// The board's night (`MockData`, T4.0): 7:48 asleep, 22:50 – 07:00, need 8:18, performance 94.
private var boardSleep: SleepDetail { MockData.todayDetail.sleep ?? SleepDetail() }
private var boardScore: DailyScore? { MockData.todayDetail.score }

// MARK: - 1. Layout

@MainActor
struct SleepLayoutTests {
    @Test func theBoardsMeasurements() {
        #expect(SleepLayout.headerHeight == 40 && SleepLayout.headerHeight == ScreenHeaderSpec.height)
        #expect(SleepLayout.pickerGap == 12 && SleepLayout.numeralGap == 22)
        #expect(SleepLayout.captionGap == 12 && SleepLayout.rulerGap == 14 && SleepLayout.hypnogramGap == 20)
        #expect(SleepLayout.hypnogramHeight == 168 && SleepLayout.hypnogramRadius == 28)
        #expect(SleepLayout.tilesGap == 12 && SleepLayout.tileGap == 12)
        #expect(SleepLayout.tileHeight == 88 && SleepLayout.tileRadius == 22)
        #expect(SleepLayout.tilePadding.top == 14 && SleepLayout.tilePadding.leading == 16)
        #expect(SleepLayout.tilePadding.trailing == 16 && SleepLayout.tilePadding.bottom == 12)
    }

    /// The hypnogram tile is the `.hypnogram` glow kind's own size and radius.
    @Test func theHypnogramTileIsTheGlowKinds() {
        let shape = GlowTileSpec.shape(for: .hypnogram, size: CGSize(width: 350, height: 168))
        #expect(shape.minHeight == SleepLayout.hypnogramHeight && shape.radius == SleepLayout.hypnogramRadius)
        #expect(GlowTileSpec.padding(for: .hypnogram) == SleepLayout.tilePadding)
    }
}

// MARK: - 5. The numeral

@MainActor
struct SleepNumeralTests {
    @Test func boardNightIs748AtTheDetailGap() {
        let board = SleepBoard(sleep: boardSleep, score: boardScore, locale: enUS)
        #expect(board.clock == "7:48")
        #expect(DotNumeral.size(of: board.clock, glyphGap: DotNumeral.glyphGapDetail) == CGSize(width: 125, height: 47))
    }

    /// Loading, no night: the unlit "0:00" takes the same box, so nothing under it moves.
    @Test func theUnlitNumeralHasTheSameSize() {
        for board in [SleepBoard(sleep: nil, score: nil, isLoading: true, locale: enUS),
                      SleepBoard(sleep: nil, score: nil, locale: enUS)] {
            #expect(board.clock == nil)
            #expect(DotNumeral.size(of: board.clock, placeholder: "0:00", glyphGap: DotNumeral.glyphGapDetail)
                    == CGSize(width: 125, height: 47))
        }
    }

    @Test func clockFormatting() {
        #expect(Fmt.clock(minutes: 468) == "7:48" && Fmt.clock(minutes: 0) == "0:00" && Fmt.clock(minutes: 61) == "1:01")
        #expect(Fmt.clock(minutes: nil) == "–")
    }

    @Test func theNumeralFollowsHeroNumbers() {
        #expect(HeroNumerals.dots.style == .dots && HeroNumerals.thin.style == .light)
    }
}

// MARK: - 6 and 29. The hypnogram

@MainActor
struct SleepHypnogramTests {
    private let start = Date(timeIntervalSince1970: 1_794_869_400)
    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }
    private func seg(_ stage: SleepIntervalStage, _ from: Double, _ to: Double) -> SleepInterval {
        SleepInterval(stage: stage, start: at(from), end: at(to))
    }

    private func night(segments: [SleepInterval], stages: [StageShare]? = nil, hasStages: Bool = true) -> SleepDetail {
        SleepDetail(start: at(0), end: at(490), totalMin: 468, stages: stages ?? [
            StageShare(stage: .deep, min: 95), StageShare(stage: .rem, min: 105),
            StageShare(stage: .light, min: 268), StageShare(stage: .awake, min: 22),
        ], hasStages: hasStages, segments: segments)
    }

    /// The plot's geometry in Sleep's tile: the grid lines, the deep bars, the line, the stage column.
    @Test func plotGeometry() {
        let ys = HypnogramPlot.Level.allCases.map { HypnogramPlot.gridY($0, height: HypnogramPlot.plotHeight) }
        #expect(zip(ys, [4, 31.33, 58.67, 86]).allSatisfy { abs($0 - $1) < 0.01 })
        #expect(HypnogramPlot.deepBarHeight == 8 && HypnogramPlot.deepBarRadius == 4 && HypnogramPlot.lineWidth == 1.4)
        #expect(HypnogramPlot.columnWidth == 38)
        let model = HypnogramPlot.model(segments: [seg(.light, 0, 100), seg(.deep, 100, 160), seg(.light, 160, 490)],
                                        start: at(0), end: at(490))
        let bar = HypnogramPlot.deepBarRects(model, size: CGSize(width: 300, height: 90))
        #expect(bar.count == 1 && bar[0].midY == 86 && bar[0].height == 8)
    }

    /// The stage names top to bottom, the plot's levels; `asleep` plots on Light.
    @Test func levelsPerStage() {
        #expect(SleepHypnogramContent.plotOrder == [.awake, .rem, .light, .deep])
        #expect(HypnogramPlot.Level.allCases.map(\.rawValue) == [0, 1, 2, 3])
        let model = HypnogramPlot.model(segments: [seg(.asleep, 0, 245), seg(.awake, 245, 490)], start: at(0), end: at(490))
        #expect(model.runs.joined().map(\.level) == [.light, .awake])
    }

    /// The night's start is x 0 and its end x 1; segments outside it are clamped; a gap breaks the path.
    @Test func clampsToTheNightAndBreaksAtGaps() {
        let model = HypnogramPlot.model(segments: [seg(.light, -30, 200), seg(.rem, 260, 520)], start: at(0), end: at(490))
        #expect(model.runs.count == 2)
        #expect(model.runs.first?.first?.from == 0 && model.runs.last?.last?.to == 1)
    }

    @Test func variants() {
        let plotted = SleepHypnogramContent(sleep: night(segments: [seg(.light, 0, 490)]), locale: enUS)
        #expect(plotted.hasPlot)
        let noTimeline = SleepHypnogramContent(sleep: night(segments: []), locale: enUS)
        #expect(noTimeline.body == .timelineMissing && noTimeline.totals.count == 4)
        #expect(noTimeline.accessibilityValue.hasSuffix(SleepHypnogramContent.noTimeline))
        let noStages = SleepHypnogramContent(sleep: night(segments: [], stages: [], hasStages: false), locale: enUS)
        #expect(noStages.body == .stagesMissing && noStages.totals.isEmpty)
        #expect(noStages.accessibilityValue == SleepHypnogramContent.noStages)
        // Stages flagged but all zero: the same as none.
        let zero = SleepHypnogramContent(sleep: night(segments: [], stages: [StageShare(stage: .deep, min: 0)]), locale: enUS)
        #expect(zero.body == .stagesMissing)
    }

    @Test func boardNightHasAPlotAndItsTimes() throws {
        let content = try #require(SleepBoard(sleep: boardSleep, score: boardScore, locale: enUS).hypnogram)
        #expect(content.hasPlot)
        #expect(content.timeRange.contains(" – "))
        #expect(content.accessibilityLabel.hasPrefix("Hypnogram, "))
    }

    // MARK: 30. Totals

    @Test func totalsFromTheStages() {
        let content = SleepHypnogramContent(sleep: night(segments: []), locale: enUS)
        #expect(content.totals.map(\.text) == ["Deep 1:35", "REM 1:45", "Light 4:28", "Awake 0:22"])
        let missing = SleepHypnogramContent(sleep: night(segments: [], stages: [
            StageShare(stage: .rem, min: 105), StageShare(stage: .light, min: 268),
        ]), locale: enUS)
        #expect(missing.totals.map(\.text) == ["Deep –", "REM 1:45", "Light 4:28", "Awake –"])
    }

    @Test func boardTotals() throws {
        let content = try #require(SleepBoard(sleep: boardSleep, score: boardScore, locale: enUS).hypnogram)
        #expect(content.totals.map(\.text) == ["Deep 1:35", "REM 1:45", "Light 4:28", "Awake 0:22"])
    }
}

// MARK: - 26. Summary, caption and subtitle

@MainActor
struct SleepSummaryCopyTests {
    private let today = date("2026-11-15")

    private func subtitle(_ mode: SleepMode, _ night: String) -> String {
        SleepHeaderContent.subtitle(mode: mode, night: date(night), today: today, locale: enUS)
    }

    @Test func captions() {
        #expect(SleepBoard(sleep: boardSleep, score: boardScore, locale: enUS).caption == "Asleep · 94\u{00A0}% of your need")
        var noNeed = boardScore
        noNeed?.sleepPerformance = nil
        noNeed?.sleepNeedMin = nil
        #expect(SleepBoard(sleep: boardSleep, score: noNeed, locale: enUS).caption == "Asleep")
        // Pending: the raw night, no performance.
        #expect(SleepBoard(sleep: boardSleep, score: boardScore, scoring: .scoring, locale: enUS).caption == "Asleep")
    }

    @Test func subtitles() {
        #expect(subtitle(.day, "2026-11-15") == "Last night · Sun, Nov 15")
        #expect(subtitle(.day, "2026-11-14") == "Yesterday · Sat, Nov 14")
        #expect(subtitle(.day, "2026-11-11") == "Wed, Nov 11")
        #expect(subtitle(.week, "2026-11-11") == "Last 7\u{00A0}nights")
        #expect(subtitle(.month, "2026-11-11") == "Last 30\u{00A0}nights")
        #expect(subtitle(.plan, "2026-11-11") == "Tonight")
    }

    @Test func spokenSubtitlesHaveTheDateInFull() {
        let header = SleepHeaderContent(mode: .day, night: date("2026-11-15"), today: today, marker: .pending,
                                        canStepBack: true, canStepForward: false, locale: enUS)
        #expect(header.spokenSubtitle == "Last night, Sunday, November 15")
        #expect(header.spokenValue.hasPrefix("Last night, Sunday, November 15, "))
        #expect(SleepHeaderContent.spokenSubtitle(mode: .day, night: date("2026-11-14"), today: today, locale: enUS)
                == "Yesterday, Saturday, November 14")
    }

    /// Week, Month and Bedtime keep the buttons' places, hidden.
    @Test func nightButtonsOnlyInDayMode() {
        for mode in SleepMode.allCases {
            let header = SleepHeaderContent(mode: mode, night: today, today: today, marker: nil, canStepBack: true,
                                            canStepForward: false, locale: enUS)
            #expect(header.showsNightButtons == (mode == .day))
        }
    }

    @Test func looksPerState() {
        #expect(SleepBoard(sleep: boardSleep, score: boardScore, locale: enUS).look == .night)
        let loading = SleepBoard(sleep: nil, score: nil, isLoading: true, locale: enUS)
        #expect(loading.look == .loading && loading.isOutline && loading.numeralLabel == "Loading this night")
        let failed = SleepBoard(sleep: nil, score: nil, error: "Offline", locale: enUS)
        #expect(failed.look == .failed("Offline") && failed.isOutline && failed.numeralLabel == nil)
        let none = SleepBoard(sleep: nil, score: nil, locale: enUS)
        #expect(none.look == .noSleep && !none.isOutline && none.caption == "No sleep recorded for this night.")
        for board in [loading, failed, none] {
            #expect(board.ruler.value == nil && board.hypnogram == nil)
            #expect(board.tiles.map(\.value) == ["–", "–", "–", "–"])
        }
    }
}

// MARK: - 27. Night stepping

@MainActor
struct SleepSteppingTests {
    private let today = date("2026-11-15")

    @Test func oldestNightIsTheFirstWithSleep() {
        let history = [DailyScore(day: "2026-09-01"), DailyScore(day: "2026-09-02", sleepActualMin: 410),
                       DailyScore(day: "2026-09-03", sleepActualMin: 430)]
        #expect(SleepNights.oldest(in: history, today: today, reach: AppState.historyDays) == date("2026-09-02"))
        #expect(SleepNights.oldest(in: [DailyScore(day: "2026-09-01")], today: today, reach: 90)
                == DayFormat.shift(today, days: -89))
        #expect(SleepNights.oldest(in: [], today: today, reach: 90) == DayFormat.shift(today, days: -89))
    }

    @Test func clampsToTheNightsThereAre() {
        let oldest = date("2026-09-02")
        #expect(SleepNights.clamp(date("2026-11-20"), oldest: oldest, today: today) == today)
        #expect(SleepNights.clamp(date("2026-08-01"), oldest: oldest, today: today) == oldest)
        #expect(SleepNights.clamp(date("2026-10-01"), oldest: oldest, today: today) == date("2026-10-01"))
    }

    @Test func theModelStopsAtBothEnds() async {
        let clock = TestClock()
        let state = AppState(env: .test(clock: clock))
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        let today = Calendar.current.startOfDay(for: clock.now())
        #expect(!vm.canStepForward && vm.header.canStepForward == false)

        vm.show(night: DayFormat.shift(today, days: 3))
        #expect(vm.date == today)

        vm.show(night: DayFormat.shift(today, days: -400))
        #expect(vm.date == vm.oldestNight)
        #expect(!vm.canStepBack && vm.canStepForward)
        await vm.step(by: -1)
        #expect(vm.date == vm.oldestNight)

        await vm.step(by: 1)
        #expect(vm.date == DayFormat.shift(vm.oldestNight, days: 1) || vm.oldestNight == today)
        vm.mode = .week
        #expect(!vm.canStepBack && !vm.canStepForward && !vm.header.showsNightButtons)
    }

    @Test func aStepAnnouncesTheNight() {
        let state = AppState(env: .test())
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        #expect(vm.stepAnnouncement.hasPrefix(vm.header.spokenSubtitle + ". "))
    }
}

// MARK: - 28. The ruler

@MainActor
struct SleepRulerTests {
    @Test func needZoneIsTheLastTenPercent() throws {
        let ruler = SleepRuler(totalMin: 468, needMin: 498, locale: enUS)
        let zone = try #require(ruler.zone)
        #expect(abs(zone.lowerBound - 7.47) < 0.001 && abs(zone.upperBound - 8.3) < 0.001)
        #expect(RulerScale.zoneTickIndices(count: RulerScale.Ticks.sleep, range: SleepRuler.range, zone: zone) == [45, 46, 47, 48, 49])
        #expect(ruler.value == 7.8)
        #expect(ruler.labels == ["0\u{00A0}h", "need 8:18", "10\u{00A0}h"])
        #expect(ruler.spokenValue.contains("on a scale from 0 to 10\u{00A0}hours") && ruler.spokenValue.contains("Your need is"))
    }

    @Test func withoutANeedNoZoneNoMiddleLabel() {
        for need in [nil, 0] as [Int?] {
            let ruler = SleepRuler(totalMin: 468, needMin: need, locale: enUS)
            #expect(ruler.zone == nil && ruler.labels == ["0\u{00A0}h", "10\u{00A0}h"])
            #expect(!ruler.spokenValue.contains("Your need"))
        }
    }

    @Test func noNightNoNeedle() {
        let ruler = SleepRuler(totalMin: nil, needMin: 498, locale: enUS)
        #expect(ruler.value == nil && ruler.zone != nil)
        #expect(ruler.spokenValue.hasPrefix("No time asleep yet"))
    }

    @Test func theNeedleClampsAtTenHours() {
        let ruler = SleepRuler(totalMin: 12 * 60, needMin: 498, locale: enUS)
        #expect(RulerScale.needleFraction(value: ruler.value, range: SleepRuler.range) == 1)
    }

    /// Pending: the raw night's need (the breakdown's total) still draws the zone.
    @Test func pendingUsesTheRawNightsNeed() {
        let board = SleepBoard(sleep: boardSleep, score: boardScore, scoring: .scoring, locale: enUS)
        #expect(board.ruler.value == 7.8)
        #expect((board.ruler.zone != nil) == (boardSleep.need != nil))
    }
}

// MARK: - 31. Tiles

@MainActor
struct SleepTileTests {
    @Test func consistencyDots() {
        let tile = SleepTile.consistency(86, week: [78, 64, nil, 52, 71, 80, 86], locale: enUS)
        #expect(tile.value == "86" && tile.unit == "%")
        #expect(tile.marks == [.full, .full, .noData, .missed, .full, .full, .today])
        // 78, 64, 71, 80 and the night shown (86) are regular, 52 isn't, one has no value.
        #expect(tile.spokenValue.hasPrefix("86\u{00A0}percent. 5 of the last 7\u{00A0}nights were regular"))
        #expect(tile.spokenValue.hasSuffix("the last is the night shown"))
        // The threshold is inclusive; a short week is padded with no-data nights at the start.
        #expect(SleepTile.consistency(60, week: [59, 60], locale: enUS).marks
                == [.noData, .noData, .noData, .noData, .noData, .missed, .today])
        #expect(SleepTile.consistency(nil, week: [], locale: enUS).marks.isEmpty)
        #expect(SleepTile.consistency(nil, week: [], locale: enUS).value == "–")
    }

    @Test func debt() {
        let down = SleepTile.debt(30, before: 72, locale: enUS)
        #expect(down.value == "0:30" && down.unit == "h")
        #expect(down.notes == [SleepTile.Note(text: "▼ 0:42", ink: .sleep)])
        #expect(down.spokenValue.hasPrefix("30 minutes, down ") && down.spokenValue.hasSuffix(" from the night before"))
        let up = SleepTile.debt(50, before: 30, locale: enUS)
        #expect(up.notes.map(\.text) == ["▲ 0:20", "high"])
        #expect(up.notes.map(\.ink) == [.secondary, .warning])
        #expect(SleepTile.debt(30, before: nil, locale: enUS).notes.isEmpty)
        #expect(SleepTile.debt(nil, before: 30, locale: enUS).value == "–")
        let none = SleepTile.debt(0, before: 20, locale: enUS)
        #expect(none.value == "None" && none.unit == nil)
        #expect(SleepTile.debt(45, before: nil, locale: enUS).notes.isEmpty, "45 is not above 45")
        #expect(SleepTile.debt(46, before: nil, locale: enUS).notes.map(\.ink) == [.warning])
    }

    @Test func efficiency() {
        #expect(SleepTile.efficiency(95, locale: enUS).value == "95")
        #expect(SleepTile.efficiency(94.6, locale: enUS).value == "95")
        #expect(SleepTile.efficiency(nil, locale: enUS).value == "–")
    }

    @Test func restorativeIsDeepPlusREM() {
        var sleep = SleepDetail(stages: [StageShare(stage: .deep, min: 95), StageShare(stage: .rem, min: 105),
                                         StageShare(stage: .light, min: 268)], restorative: 100)
        let tile = SleepTile.restorative(sleep, locale: enUS)
        #expect(tile.value == "3:20" && tile.unit == "h" && tile.notes.map(\.text) == ["Deep + REM"])
        #expect(tile.spokenValue.hasSuffix("100\u{00A0}percent of the target"))
        sleep.hasStages = false
        #expect(SleepTile.restorative(sleep, locale: enUS).value == "–")
    }

    /// The board night's four tiles, in order, with the identifiers the UI tests use.
    @Test func boardTiles() {
        let week = [78, 64, nil, 52, 71, 80, 86] as [Int?]
        let board = SleepBoard(sleep: boardSleep, score: boardScore, previousDebt: 72, weekConsistency: week, locale: enUS)
        #expect(board.tiles.map(\.kind) == [.consistency, .debt, .efficiency, .restorative])
        #expect(board.tiles.map(\.kind.identifier)
                == ["sleep.tile.consistency", "sleep.tile.debt", "sleep.tile.efficiency", "sleep.tile.restorative"])
        #expect(board.tiles.map(\.value) == ["86", "0:30", "95", "3:20"])
        #expect(board.tiles[1].notes.map(\.text) == ["▼ 0:42"])
    }

    /// Pending: the tiles that need a score show "–"; the raw night's stay.
    @Test func pendingTiles() {
        let board = SleepBoard(sleep: boardSleep, score: boardScore, previousDebt: 72,
                               weekConsistency: [78, 64, nil, 52, 71, 80, 86], scoring: .scoring, locale: enUS)
        #expect(board.tiles.map(\.value) == ["–", "–", "95", "3:20"])
        #expect(board.tiles[0].marks.last == .today && board.tiles[1].notes.isEmpty)
    }
}
