import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Today in Nocturne (docs/work/2026-11-16-nocturne/design.md §P4-11, tests 1–4, 17–25 and Today's half of 36): the
/// layout's numbers, the data each row shows (greeting, sub-line, label row, ruler, the tiles' week, the strain band, the
/// captions), the look per state, and the identifiers the UI tests rely on. Pure first, through `TodayViewModel` on a
/// test clock; the frames and identifiers hosted in a real window (`HostedWindow`).
@MainActor
@Suite("Today in Nocturne: layout, data and states", .serialized)
struct TodayNocturneTests {
    /// Sunday, Nov 15, 7:30: the board's day.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 7, minute: 30))!
    private var key: String { DayFormat.string(from: now) }
    private func dayKey(_ offset: Int) -> String { DayFormat.string(from: DayFormat.shift(now, days: offset)) }
    private let english = Locale(identifier: "en_US")

    /// `n` scored days before today, oldest first: HRV 50 + offset (so the week has a range), 7:00 asleep of an 8:00 need
    /// (short, 87.5 %), yesterday 76 · 75 % · 7:10 · 0.9.
    private func history(_ n: Int = 30, vitals: Bool = true) -> [DailyScore] {
        (1...n).reversed().map { offset in
            DailyScore(day: dayKey(-offset), readiness: offset == 1 ? 76 : 70, recovery: offset == 1 ? 75 : 60,
                       strain: offset == 1 ? 0.9 : 8, sleepNeedMin: 480, sleepActualMin: offset == 1 ? 430 : 420,
                       hrvMs: vitals ? Double(50 + offset) : nil, rhr: vitals ? 50 : nil, baselineDays: 30,
                       computedAt: DayFormat.shift(now, days: -offset))
        }
    }

    private func scored(_ readiness: Int?, recovery: Int = 82, strain: Double = 12.4, hrv: Double? = 66,
                        asleep: Int? = 468, need: Int? = 498) -> DailyScore {
        DailyScore(day: key, readiness: readiness, state: .balanced, recovery: recovery, strain: strain, sleepNeedMin: need,
                   sleepActualMin: asleep, hrvMs: hrv, rhr: 48, baselineDays: 30, computedAt: now, scoringState: .scored)
    }

    /// The platform's calibrating row: readiness 80, `calibrating: true`, `baseline_days: 0` (the reported screenshot).
    private var calibratingRow: DailyScore {
        DailyScore(day: key, readiness: 80, state: .balanced, recovery: 75, strain: 0.9, sleepActualMin: 437,
                   baselineDays: 0, calibrating: true, computedAt: now, scoringState: .scored)
    }

    /// API.md → `GET /v1/days/{day}`: a day not scored yet, exactly as the platform sends it.
    private func placeholder() throws -> DailyScore {
        let json = #"{"day":"\#(key)","state":"calibrating","baseline_days":0,"calibrating":false,"#
            + #""computed_at":"0001-01-01T00:00:00Z","scoring_state":"pending"}"#
        return try APIClient.jsonDecoder.decode(DailyScore.self, from: Data(json.utf8))
    }

    private func model(today: DailyScore?, history: [DailyScore], status: ScoringState?, name: String? = "Alex Doe")
        -> TodayViewModel {
        let env = AppEnvironment.test(clock: TestClock(now: now))
        let state = AppState(env: env)
        state.history = history
        if let today { state.today = DayDetail(score: today, sleep: nil, workouts: []) }
        state.readinessWeek = TrendSeries(metric: "readiness", range: "7d",
                                          points: (0..<7).map { TrendPoint(day: dayKey(-6 + $0), value: Double(70 + $0)) },
                                          avg: 73, min: 70, max: 76, baseline: nil)
        if let name {
            let user = MockData.user
            state.user = User(id: user.id, name: name, tz: user.tz, maxHr: user.maxHr, sleepBaseMin: user.sleepBaseMin)
        }
        if let status {
            state.syncStatus = SyncStatus(gate: nil, lastSyncAt: now, lastSyncDevice: nil, latest: [:],
                                          today: TodayState(day: key, state: status, scoredAt: nil, modelVersion: "x"),
                                          pendingDays: [], expectedWithinSec: 20, resyncRequestedAt: nil)
        }
        let sync = SyncService.ungated(env: env)
        return TodayViewModel(state: state, sync: sync,
                              coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                              apiStatus: APIStatus())
    }

    private func scenario(_ scenario: TodayScenario, flags: [FeatureFlag: Bool] = [:]) -> TodayViewModel {
        let state = AppState.preview(flags: flags, scenario: scenario)
        let sync = SyncService.ungated(env: state.env)
        return TodayViewModel(state: state, sync: sync,
                              coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock),
                              apiStatus: APIStatus())
    }

    /// The demo's days with a readiness under a calibration note (S2 learning, N1 blocked): the band word goes.
    private func notedScores() -> [TodayViewModel] {
        [TodayScenario.learningHRV, .learningRestingHRScored, .blockedHRV, .blockedNoNight, .blockedOura, .blockedEarly]
            .map { scenario($0) }
            .filter { $0.content.hero == .score && $0.content.readiness != nil && !$0.content.showsReadinessBand }
    }

    // MARK: 1. the layout's numbers

    @Test func theLayoutIsTheBoards() {
        typealias L = TodayLayout
        #expect(L.header == 40 && ScreenHeaderSpec.height == 40)
        #expect(L.headerToGreeting == 18 && L.greetingToSubLine == 4 && L.subLineToStatus == 4)
        #expect(L.statusToGauge == 14 && L.gaugeToLabel == 8 && L.labelGap == 10 && L.labelToRuler == 12)
        #expect(L.rulerToTiles == 22 && L.tileGap == 12 && L.tilesToStrain == 12)
        #expect(L.twoUpHeight == 124 && L.strainHeight == 96 && L.strainRowInset == 16)
        #expect(L.heroDial == 248 && L.heroFrame == 260)
        // The content heights are the tiles' less the glow tile's padding (14 top, 12 bottom).
        #expect(L.twoUpContentHeight == L.twoUpHeight - 26 && L.strainContentHeight == L.strainHeight - 26)
        #expect(L.greetingTracking == -0.26, "−0.01 em at 26 pt")
    }

    // MARK: 2. the pair

    @Test func thePairsWidthFollowsTheColumn() {
        #expect(TodayLayout.twoUpWidth(contentWidth: 350) == 169)
        #expect(TodayLayout.twoUpWidth(contentWidth: 335) == 161.5)
        #expect(TodayLayout.twoUpWidth(contentWidth: 400) == 194)
    }

    private func tiles(_ content: TodayTilesContent) -> some View {
        TodayTiles(content: content) { _ in }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    @Test func thePairIs169By124AndTheStrainTile350By96() async throws {
        let vm = model(today: scored(84), history: history(), status: .scored)
        try await HostedWindow.run(width: 390, height: 600, tiles(TodayTilesContent(vm.content))) { w in
            try await w.settle()
            let nodes = w.nodes()
            let recovery = try #require(nodes.first { $0.identifier == "today.tile.recovery" })
            let sleep = try #require(nodes.first { $0.identifier == "today.tile.sleep" })
            let strain = try #require(nodes.first { $0.identifier == "today.tile.strain" })
            #expect(recovery.frame.size == CGSize(width: 169, height: 124), "recovery \(recovery.frame)")
            #expect(sleep.frame.size == CGSize(width: 169, height: 124), "sleep \(sleep.frame)")
            #expect(recovery.frame.minX == 20 && sleep.frame.minX == 20 + 169 + 12 && recovery.frame.minY == sleep.frame.minY)
            #expect(strain.frame.size == CGSize(width: 350, height: 96), "strain \(strain.frame)")
            #expect(strain.frame.minY == recovery.frame.maxY + 12)
        }
    }

    @Test func atAX1ThePairStacksTo350() async throws {
        let vm = model(today: scored(84), history: history(), status: .scored)
        try await HostedWindow.run(width: 390, height: 1600, typeSize: .accessibility1, category: .accessibilityMedium,
                                   tiles(TodayTilesContent(vm.content))) { w in
            try await w.settle()
            let nodes = w.nodes()
            let recovery = try #require(nodes.first { $0.identifier == "today.tile.recovery" })
            let sleep = try #require(nodes.first { $0.identifier == "today.tile.sleep" })
            #expect(recovery.frame.width == 350 && sleep.frame.width == 350)
            #expect(sleep.frame.minY >= recovery.frame.maxY + 12 - 0.01, "stacked: \(recovery.frame) \(sleep.frame)")
            for node in nodes { #expect(node.frame.maxX <= 390, "'\(node.label)' inside the width: \(node.frame)") }
        }
    }

    /// A long caption beside a clock value ("calibrating" by "7:11 h") keeps its one word and the unit: it shrinks beside
    /// the value or goes above it (VF3), never "calibratin / g", never the unit pushed out; the pair keeps 124. The tile is
    /// one VoiceOver element, so the parts are read on its content (`TwoUpHost`, `TodayTwoUpTileTests`).
    @Test func aLongCaptionKeepsItsWordsAndTheUnit() async throws {
        let content = TodayTilesContent(recovery: nil, recoveryCaption: "calibrating", hrvWeek: [], sleepMinutes: 431,
                                        caption: "calibrating", sleepWeek: TodaySleepWeek(nights: []), strain: nil,
                                        isEarlierDay: false)
        try await HostedWindow.run(width: 390, height: 600, tiles(content)) { w in
            try await w.settle()
            let sleep = try #require(w.nodes().first { $0.identifier == "today.tile.sleep" })
            #expect(sleep.frame.height == 124, "the pair keeps the board's height: \(sleep.frame)")
        }
        let frames = TwoUpFrames()
        let tile = TwoUpCase(name: "calibrating", title: "Sleep", value: "7:11", unit: "h", caption: "calibrating")
        try await HostedWindow.run(width: 390, height: 600, TwoUpHost.pair(tile, tile, frames: frames)) { w in
            try await w.wait("the tile") { frames.byName["a"] != nil }
            try await w.settle()
            let box = try #require(frames.byName["a"])
            let inside = w.nodes().filter { box.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            // One element with the whole word: not broken over lines, nor cut ("calibrat…").
            let caption = try #require(inside.first { $0.label == "calibrating" }, "\(inside.map(\.label))")
            #expect(caption.frame.height < 20, "one line: \(caption.frame)")
            let value = try #require(inside.first { $0.label == "7:11" })
            let unit = try #require(inside.first { $0.label == "h" }, "the unit stays")
            #expect(unit.frame.minX > value.frame.maxX && unit.frame.maxX <= box.maxX - 16 + 0.5, "the unit in the tile: \(unit.frame)")
            // Beside the value, after the unit; or above it: never over either.
            #expect(caption.frame.minX >= unit.frame.maxX + TodayLayout.tileRowGap - 0.5 || caption.frame.maxY <= value.frame.minY + 0.5,
                    "the caption \(caption.frame) clear of the value \(value.frame) and unit \(unit.frame)")
            #expect(caption.frame.maxX <= box.maxX - 16 + 0.5, "inside the tile: \(caption.frame)")
        }
    }

    // MARK: 3. the header

    private func header(myDay: Bool) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                TodayHeader()
                Text(verbatim: "below").frame(height: 20)
                Spacer()
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .previewEnvironment(.preview(flags: [.todayMyDay: myDay]))
        }
    }

    @Test func theHeaderIs40HighWithTheCalendarOnTheInset() async throws {
        try await HostedWindow.run(width: 390, height: 300, header(myDay: true)) { w in
            try await w.settle()
            let nodes = w.nodes()
            let calendar = try #require(nodes.first { $0.identifier == "today.header.calendar" })
            #expect(calendar.label == "Calendar")
            #expect(calendar.frame.size == CGSize(width: 44, height: 44), "the 44 pt box: \(calendar.frame)")
            // The 40 pt circle's edge on the 20 pt inset: its box reaches 2 pt past it.
            #expect(calendar.frame.maxX == 390 - 20 + ScreenHeaderSpec.buttonOverhang)
            let below = try #require(w.node("below", exactly: true))
            // To one device pixel (1/3 pt): the row's edge is rounded to the screen's grid.
            #expect(abs(below.frame.minY - calendar.frame.midY - 20) < 0.34, "the row is 40, the button centred in it")
        }
    }

    @Test func withoutMyDayTheCalendarIsAbsentAndTheRowKeepsItsHeight() async throws {
        var withButton: CGFloat = 0
        try await HostedWindow.run(width: 390, height: 300, header(myDay: true)) { w in
            try await w.settle()
            withButton = try #require(w.node("below", exactly: true)).frame.minY
        }
        try await HostedWindow.run(width: 390, height: 300, header(myDay: false)) { w in
            try await w.settle()
            #expect(!w.nodes().contains { $0.identifier == "today.header.calendar" }, "absent, not disabled")
            let below = try #require(w.node("below", exactly: true))
            #expect(below.frame.minY == withButton, "the row stays 40 high")
        }
    }

    // MARK: 4. the hero gauge

    @Test func theHeroGaugeIs260WithA248Dial() {
        #expect(OrbitGaugeSize.hero.frame == 260 && OrbitGaugeSize.hero.dial == 248)
        #expect(OrbitGaugeSize.hero.frame == TodayLayout.heroFrame && OrbitGaugeSize.hero.dial == TodayLayout.heroDial)
        #expect(TodayLayout.heroHaloRadius > TodayLayout.heroFrame / 2, "the halo (133) reaches past the frame's 130")
    }

    // MARK: 17. greeting

    @Test func theGreetingFollowsTheHourAndTheFirstName() {
        func at(_ hour: Int) -> Date { Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now)! }
        #expect(ReadinessCopy.greeting(at: at(4), name: "Alex") == String(localized: "Good evening, \("Alex")"))
        #expect(ReadinessCopy.greeting(at: at(5), name: "Alex") == String(localized: "Good morning, \("Alex")"))
        #expect(ReadinessCopy.greeting(at: at(11), name: "Alex") == String(localized: "Good morning, \("Alex")"))
        #expect(ReadinessCopy.greeting(at: at(12), name: "Alex") == String(localized: "Good afternoon, \("Alex")"))
        #expect(ReadinessCopy.greeting(at: at(17), name: "Alex") == String(localized: "Good afternoon, \("Alex")"))
        #expect(ReadinessCopy.greeting(at: at(18), name: "Alex") == String(localized: "Good evening, \("Alex")"))
        #expect(ReadinessCopy.greeting(at: at(7), name: "Alex") == "Good morning, Alex")
        for hour in [4, 5, 12, 18] {
            #expect(!ReadinessCopy.greeting(at: at(hour), name: nil).contains(","), "no comma without a name at \(hour)")
        }
        #expect(ReadinessCopy.firstName("Alex Doe") == "Alex")
        #expect(ReadinessCopy.firstName("Anna-Lena  von Berg") == "Anna-Lena")
        #expect(ReadinessCopy.firstName("") == nil && ReadinessCopy.firstName("  ") == nil && ReadinessCopy.firstName(nil) == nil)
        // Through the view model: the account's name, or none.
        #expect(model(today: scored(84), history: history(), status: .scored).greeting == "Good morning, Alex")
        let nameless = model(today: scored(84), history: history(), status: .scored, name: "")
        #expect(nameless.firstName == nil && nameless.greeting == "Good morning")
    }

    // MARK: 18. sub-line

    @Test func theSubLineIsTheDateThenTheSentence() throws {
        let cases = [model(today: scored(84), history: history(), status: .scored),
                     model(today: try placeholder(), history: history(), status: .pending),
                     model(today: nil, history: [], status: nil),
                     model(today: calibratingRow, history: history(4), status: .scored)]
        for vm in cases {
            let content = vm.content
            #expect(content.subLine(locale: english) == "Sunday, Nov 15 · " + content.sentence)
        }
        #expect(TodayContent.subLineDate(now, locale: english) == "Sunday, Nov 15")
        #expect(TodayContent.spokenDate(now, locale: english) == "Sunday, November 15")
    }

    // MARK: 19. label row

    @Test func theLabelRowNamesTheBand() {
        #expect(model(today: scored(84), history: history(), status: .scored).content.readinessLabel == "Readiness · High")
        #expect(model(today: scored(50), history: history(), status: .scored).content.readinessLabel == "Readiness · Moderate")
        #expect(model(today: scored(20), history: history(), status: .scored).content.readinessLabel == "Readiness · Low")
        // A calibration note owns the line (S2, N1: learning, blocked): "Readiness" alone, and no delta.
        let noted = notedScores()
        #expect(!noted.isEmpty, "a scenario with a readiness under a calibration note")
        for vm in noted {
            #expect(vm.content.readinessLabel == "Readiness" && vm.readinessDelta == nil)
        }
        // "Needs vitals" is not a calibration note: the band stays.
        let vitals = model(today: calibratingRow, history: history(30, vitals: false), status: .scored)
        #expect(vitals.content.showsReadinessBand && vitals.content.readinessLabel == "Readiness · High")
        #expect(vitals.readinessDelta == nil)
        // Beside the baselines counter.
        let counter = model(today: calibratingRow, history: history(4), status: .scored)
        #expect(counter.content.readinessLabel == "Baselines" && counter.readinessDelta == nil)
        // Row A has its delta.
        #expect(model(today: scored(84), history: history(), status: .scored).readinessDelta != nil)
    }

    // MARK: 20. ruler

    @Test func theRulerPerState() throws {
        let a = model(today: scored(84), history: history(), status: .scored).content
        #expect(a.rulerZone == 67...100 && a.rulerValue == 84)
        #expect(RulerScale.zoneTickIndices(count: RulerScale.Ticks.today, range: 0...100, zone: a.rulerZone) == Array(41...60))
        #expect(RulerScale.needleX(value: a.rulerValue, range: 0...100, width: 300) == 252)
        #expect(a.rulerLabels == ["0", "low", "moderate", "high", "100"])
        #expect(a.rulerSpoken == "84, high, on a scale from 0 to 100")
        // Calibrating: no band, so no zone; "0 · 100".
        let counter = model(today: calibratingRow, history: history(4), status: .scored).content
        #expect(counter.rulerZone == nil && counter.rulerLabels == ["0", "100"] && counter.rulerValue == nil)
        // Under a calibration note: the needle, no zone.
        for vm in notedScores() {
            let c = vm.content
            let value = try #require(c.rulerValue)
            #expect(c.rulerZone == nil && c.rulerLabels == ["0", "100"])
            #expect(c.rulerSpoken == "\(Int(value.rounded())), on a scale from 0 to 100")
        }
        // Pending and empty: no needle.
        let pending = model(today: try placeholder(), history: history(), status: .pending).content
        #expect(pending.rulerValue == nil && pending.rulerSpoken == "No readiness yet, on a scale from 0 to 100")
        let empty = model(today: nil, history: [], status: nil).content
        #expect(empty.rulerValue == nil)
        #expect(RulerScale.needleX(value: nil, range: 0...100, width: 300) == nil)
        // The bands as the ruler names them.
        #expect(TodayContent.band(67) == .high && TodayContent.band(66) == .moderate)
        #expect(TodayContent.band(34) == .moderate && TodayContent.band(33) == .low)
    }

    // MARK: 21. hrvWeek

    @Test func theHRVWeekEndsOnTheShownDay() throws {
        let vm = model(today: scored(84, hrv: 66), history: history(), status: .scored)
        #expect(vm.hrvWeek.count == 7)
        #expect(vm.hrvWeek == [56, 55, 54, 53, 52, 51, 66], "oldest first, the shown day last")
        #expect(!Sparkline.isPending(vm.hrvWeek))
        // A gap day is nil, never interpolated.
        var gap = history()
        gap.removeAll { $0.day == dayKey(-3) }
        let withGap = model(today: scored(84), history: gap, status: .scored).hrvWeek
        #expect(withGap.count == 7 && withGap[3] == nil && withGap[2] == 54)
        // Without today's HRV the last is nil (no Volt dot); fewer than two values draw the pending line.
        let noToday = model(today: scored(84, hrv: nil), history: history(), status: .scored).hrvWeek
        #expect(noToday.last == .some(nil) && noToday.count == 7)
        let one = model(today: scored(84, hrv: 60), history: history(30, vitals: false), status: .scored).hrvWeek
        #expect(Sparkline.isPending(one) && one.last == 60)
        // While the night is pending, the week ends on the tiles' day: yesterday.
        let pending = model(today: try placeholder(), history: history(), status: .pending)
        #expect(pending.hrvWeek == [57, 56, 55, 54, 53, 52, 51])
        // The VoiceOver sentence: the shown day's value and the week's range.
        let tile = TodayTilesContent(vm.content)
        #expect(tile.hrvSentence == "HRV 66 milliseconds, lowest 51 and highest 66 over the last 7 days")
        #expect(TodayTilesContent(model(today: scored(84, hrv: nil), history: history(), status: .scored).content)
            .hrvSentence == nil)
    }

    // MARK: 22. sleepNights (L24: asleep ≥ 90 % of the need)

    @Test func aNightIsEnoughAt90PercentOfItsNeed() {
        func night(_ actual: Int?, _ need: Int?) -> TodaySleepWeek.Night {
            TodaySleepWeek.night(DailyScore(day: key, sleepNeedMin: need, sleepActualMin: actual))
        }
        #expect(night(449, 498) == .enough, "90.2 %")
        #expect(night(448, 498) == .short, "89.96 %")
        #expect(night(432, 480) == .enough, "exactly 90 %")
        #expect(night(431, 480) == .short)
        #expect(night(520, 498) == .enough)
        #expect(night(nil, 498) == .unknown && night(468, nil) == .unknown && night(468, 0) == .unknown)
        #expect(TodaySleepWeek.night(nil) == .unknown)
    }

    @Test func theSleepWeekHasSevenMarksTheLastToday() {
        // History: 7:00 of 8:00 (87.5 %, short) each night; today 7:48 of 8:18 (94 %, enough).
        let vm = model(today: scored(84), history: history(), status: .scored)
        #expect(vm.sleepNights == [.missed, .missed, .missed, .missed, .missed, .missed, .today])
        let week = vm.content.sleepWeek
        #expect(week.nights.count == 7 && week.enoughCount == 1 && week.unknownCount == 0)
        #expect(week.summary == "Slept enough on 1 of the last 7 nights; the last is the night shown")
        // Enough, unknown and a gap.
        let mixed = TodaySleepWeek(nights: [.enough, .unknown, .short, .enough, .unknown, .enough, .short])
        #expect(mixed.marks == [.full, .noData, .missed, .full, .noData, .full, .today])
        #expect(mixed.enoughCount == 3 && mixed.unknownCount == 2)
        #expect(mixed.summary == String(localized: "Slept enough on \(3) of the last 7 nights; the last is the night shown; \(2) nights have no data"))
        var gap = history()
        gap.removeAll { $0.day == dayKey(-2) }
        let withGap = model(today: scored(84), history: gap, status: .scored).sleepNights
        #expect(withGap.count == 7 && withGap[4] == .noData)
    }

    // MARK: 23. strain tile

    @Test func theStrainBandAndItsZone() {
        let cases: [(Double, TodayStrainBand)] = [(0, .light), (9.9, .light), (10, .moderate), (13.9, .moderate), (14, .high),
                                                  (17.9, .high), (18, .allOut), (21, .allOut)]
        for (value, band) in cases { #expect(TodayStrainBand(value) == band, "\(value)") }
        #expect(TodayStrainBand.zone == 10...14)
        #expect(TodayStrainBand.moderate.caption == "of 21 · moderate" && TodayStrainBand.allOut.caption == "of 21 · all out")
        #expect(TodayStrainBand.moderate.spoken == MetricSpec.strainBand(12).label)
        let vm = model(today: scored(84, strain: 12.4), history: history(), status: .scored)
        let tile = TodayTilesContent(vm.content)
        #expect(vm.strainBand == .moderate && tile.strainText == Fmt.strain(12.4) && tile.strainCaption == "of 21 · moderate")
        #expect(tile.strainSpoken == "\(Fmt.strain(12.4)), \(MetricSpec.strainBand(12.4).label), on a scale from 0 to 21. The moderate range is 10 to 14.")
        // No value: "–", the scale alone, no needle, no band.
        let none = TodayTilesContent(recovery: nil, recoveryCaption: nil, hrvWeek: [], sleepMinutes: nil, caption: nil,
                                     sleepWeek: TodaySleepWeek(nights: []), strain: nil, isEarlierDay: false)
        #expect(none.strainText == Fmt.placeholder && none.strainCaption == "of 21" && none.strainBand == nil)
        #expect(RulerScale.needleX(value: none.strain, range: 0...21, width: 318) == nil)
        #expect(none.strainSpoken == "No data")
    }

    // MARK: 24. captions: one day for the three tiles

    @Test func theCaptionsSayTheDayForAllThreeTiles() throws {
        // Row A: the band word under Recovery, nothing under the others.
        let a = TodayTilesContent(model(today: scored(84), history: history(), status: .scored).content)
        #expect(a.recoveryCaption == MetricSpec.scoreBand(82).label && a.caption == nil && !a.isEarlierDay)
        #expect(a.strainLabel == "Strain")
        #expect(a.recoverySpoken.hasPrefix("82 percent, High"))
        #expect(a.sleepText == "7:48" && a.sleepSpoken.hasPrefix(Fmt.spokenDuration(minutes: 468) + ". Slept enough on"))
        // Pending with a previous day: yesterday's tiles, the same caption on all three, said not dimmed.
        let c = TodayTilesContent(model(today: try placeholder(), history: history(), status: .pending).content)
        let yesterday = String(localized: "Yesterday")
        #expect(c.isEarlierDay && c.recoveryCaption == yesterday && c.caption == yesterday)
        #expect(c.strainLabel == "Strain · \(yesterday)" && c.sleepText == "7:10" && c.recoveryText == "75")
        #expect(c.recoverySpoken.hasPrefix("75 percent, \(yesterday), not today's score"))
        #expect(c.strainSpoken == "\(Fmt.strain(0.9)), \(yesterday), not today's score")
        // Calibrating (a short history): "calibrating" on all three; Recovery's "–" beside the baselines counter.
        let calibrating = String(localized: "today.tile.calibrating", defaultValue: "calibrating")
        let b = TodayTilesContent(model(today: calibratingRow, history: history(4), status: .scored).content)
        #expect(b.recoveryCaption == calibrating && b.caption == calibrating && !b.isEarlierDay)
        #expect(b.recovery == nil && b.recoveryText == Fmt.placeholder && b.recoverySpoken == "No data, \(calibrating)")
        #expect(b.strainLabel == "Strain · \(calibrating)")
    }

    // MARK: 25. state → look

    private struct Look: Equatable, CustomStringConvertible {
        var hero: String
        var tiles: Bool
        var zone: Bool
        var needle: Bool

        var description: String { "\(hero) tiles \(tiles) zone \(zone) needle \(needle)" }
    }

    private func look(_ vm: TodayViewModel) -> Look {
        let c = vm.content
        let hero: String
        switch c.hero {
        case .importing: hero = "importing"
        case .pending: hero = "pending"
        case .calibrating: hero = "calibrating"
        case .score: hero = "score"
        }
        return Look(hero: hero, tiles: c.showsTiles, zone: c.rulerZone != nil, needle: c.rulerValue != nil)
    }

    @Test func everyStateHasItsLook() {
        let expected: [(TodayScenario?, Look)] = [
            (nil, Look(hero: "score", tiles: true, zone: true, needle: true)),
            (.pending, Look(hero: "pending", tiles: true, zone: true, needle: false)),
            (.scoringSlow, Look(hero: "pending", tiles: true, zone: true, needle: false)),
            (.pendingNoPrevious, Look(hero: "pending", tiles: false, zone: true, needle: false)),
            (.waitingForSleep, Look(hero: "pending", tiles: true, zone: true, needle: false)),
            (.calibrating, Look(hero: "calibrating", tiles: true, zone: false, needle: false)),
            (.needsVitals, Look(hero: "score", tiles: true, zone: true, needle: true)),
            (.recalculating, Look(hero: "score", tiles: true, zone: true, needle: true)),
            (.recalculatingYesterday, Look(hero: "score", tiles: true, zone: true, needle: true)),
            (.importing, Look(hero: "importing", tiles: false, zone: true, needle: false)),
        ]
        for (scenario, want) in expected {
            let vm = scenario.map { self.scenario($0) } ?? self.scenario(.watch)
            #expect(look(vm) == want, "\(scenario.map { "\($0)" } ?? "scored"): \(look(vm))")
        }
        // No scores yet (row E after the import): the empty gauge, no tiles.
        let none = model(today: nil, history: [], status: nil)
        #expect(!none.content.showsTiles && none.content.rulerValue == nil && none.presentation.row == .firstImport)
    }

    /// Offline, stale and demo are the status row's (the gauge and tiles stay as they are): the line says it.
    @Test func offlineAndDemoAreTheStatusRows() {
        let offline = AppState.preview(online: false)
        let sync = SyncService.ungated(env: offline.env)
        let vm = TodayViewModel(state: offline, sync: sync,
                                coordinator: SyncCoordinator(steps: LiveSyncSteps(state: offline, sync: sync),
                                                             clock: offline.env.clock),
                                apiStatus: APIStatus())
        #expect(vm.isOffline && vm.content.hero == .score && vm.content.showsTiles)
        let demo = scenario(.watch)
        #expect(!demo.isOffline && demo.content.showsTiles)
    }

    // MARK: 33. placeholders: a missing value is a pending look, never a number

    @Test func aDayOfNullsShowsNoNumberAnywhere() throws {
        let nulls = DailyScore(day: key, readiness: nil, recovery: nil, strain: nil, sleepNeedMin: nil, sleepActualMin: nil,
                               hrvMs: nil, baselineDays: 30, computedAt: now, scoringState: .scored)
        let vm = model(today: nulls, history: history(vitals: false), status: .scored, name: nil)
        let c = vm.content
        #expect(c.readiness == nil && c.rulerValue == nil && c.readinessDelta == nil)
        #expect(c.rulerSpoken == "No readiness yet, on a scale from 0 to 100")
        #expect(c.readinessLabel == "Readiness", "no band word without a readiness")
        let tiles = TodayTilesContent(c)
        #expect(tiles.recoveryText == Fmt.placeholder && tiles.sleepText == Fmt.placeholder && tiles.strainText == Fmt.placeholder)
        #expect(tiles.strainBand == nil && tiles.strainCaption == "of 21")
        // The sparkline has nothing to draw (no hrv_ms in the history either) and says nothing about it.
        #expect(tiles.hrvWeek.allSatisfy { $0 == nil } && Sparkline.isPending(tiles.hrvWeek) && tiles.hrvSentence == nil)
        #expect(tiles.sleepWeek.marks.last == .noData || tiles.sleepWeek.marks.last == .today,
                "the shown night has no numbers to compare: \(tiles.sleepWeek.marks)")
        // Nothing the tiles say aloud is a number for the shown day.
        #expect(!tiles.recoverySpoken.contains { $0.isNumber }, "\(tiles.recoverySpoken)")
        #expect(!tiles.strainSpoken.contains { $0.isNumber }, "\(tiles.strainSpoken)")
        #expect(!tiles.sleepSpoken.hasPrefix("0"), "\(tiles.sleepSpoken)")
        // No name: the greeting is the word alone.
        #expect(vm.greeting == ReadinessCopy.greeting(at: now, name: nil) && !vm.greeting.contains(","))
    }

    // MARK: 36. identifiers (Today's half), hosted

    private func identifiers(_ state: AppState) async throws -> Set<String> {
        var found: Set<String> = []
        try await HostedWindow.run(width: 390, height: 2600,
                                   TodayView().previewEnvironment(state).environment(\.locale, english)) { w in
            try await w.settle()
            found = Set(w.nodes().compactMap(\.identifier))
        }
        return found
    }

    @Test func theScoredDayKeepsItsIdentifiersAndAddsTheNewOnes() async throws {
        let ids = try await identifiers(.preview(flags: [.todayMyDay: true], scenario: .watch))
        for id in ["today.readinessGauge", "today.syncLine.line", "today.header.calendar", "today.ruler", "today.tile.recovery",
                   "today.tile.sleep", "today.tile.strain"] {
            #expect(ids.contains(id), "\(id) in \(ids.sorted())")
        }
        #expect(!ids.contains("today.pendingGauge") && !ids.contains("today.baselineGauge"))
    }

    @Test func thePendingNightKeepsItsIdentifiers() async throws {
        let ids = try await identifiers(.preview(scenario: .pending))
        for id in ["today.pendingGauge", "today.rawNight", "today.ruler", "today.tile.sleep"] {
            #expect(ids.contains(id), "\(id) in \(ids.sorted())")
        }
        #expect(!ids.contains("today.header.calendar"), "My Day is off by default")
    }

    @Test func theBaselinesAndTheImportKeepTheirIdentifiers() async throws {
        let calibrating = try await identifiers(.preview(scenario: .calibrating))
        #expect(calibrating.contains("today.baselineGauge") && calibrating.contains("today.ruler"), "\(calibrating.sorted())")
        let importing = try await identifiers(.preview(scenario: .importing))
        #expect(importing.contains("today.importCard"), "\(importing.sorted())")
        #expect(!importing.contains("today.tile.recovery"), "no tiles during the first import")
        let gap = try await identifiers(.preview(scenario: .nightGap))
        // The card is a container (no label of its own, so not a node here); its action carries the card's identifier.
        #expect(gap.contains { $0.hasPrefix("today.nightHint") }, "\(gap.sorted())")
    }
}
