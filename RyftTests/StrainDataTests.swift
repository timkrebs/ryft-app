import Foundation
import SwiftUI
import Testing
@testable import Ryft

// Strain and the Workout detail in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-12 tests 15, 24–27): the pure
// decisions behind the board, its states, the activity rows and the workout's page.

private let gb = Locale(identifier: "en_GB")
/// `AppEnvironment.test()`'s clock: the day the view models see as today.
private let testNow = TestClock().now()

/// Today at `hour:minute` in the current calendar.
private func at(_ hour: Int, _ minute: Int, days: Int = 0) -> Date {
    let day = DayFormat.shift(Calendar.current.startOfDay(for: .now), days: days)
    return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
}

/// 7:10 today as the rows write it.
private var seven10: String { Fmt.time(at(7, 10), locale: gb) }

private func workout(_ activity: String = "running", start: Date = at(7, 10), minutes: Double = 42, avgHr: Double? = 148,
                     distance: Double? = 7_800, strain: Double? = 9.8, sessionId: UUID? = nil,
                     muscularLoad: Double? = nil) -> Workout {
    Workout(id: UUID(), activity: activity, start: start, end: start.addingTimeInterval(minutes * 60), avgHr: avgHr, maxHr: 176,
            energyKcal: 540, distanceM: distance, source: "Garmin Connect", strain: strain, muscularLoad: muscularLoad,
            sessionId: sessionId)
}

/// `SessionSummary` has no memberwise init: decoded from the wire shape, as the app gets it.
private func session(title: String = "Upper A", start: Date = at(17, 30), minutes: Int = 55, strain: Double? = 6.1,
                     load: Double? = 84.6) throws -> SessionSummary {
    let iso = ISO8601DateFormatter()
    var json: [String: Any] = [
        "id": UUID().uuidString, "title": title, "started_at": iso.string(from: start),
        "ended_at": iso.string(from: start.addingTimeInterval(Double(minutes) * 60)),
        "status": "completed", "duration_min": minutes, "exercise_count": 5, "set_count": 18, "pr_count": 0,
    ]
    if let strain { json["strain"] = strain }
    if let load { json["muscular_trimp"] = load }
    return try APIClient.jsonDecoder.decode(SessionSummary.self, from: JSONSerialization.data(withJSONObject: json))
}

private func detail(strain: Double?, zones: [Int] = [11, 24, 27, 14, 6], muscular: Int? = nil,
                    workouts: [Workout] = [], on date: Date = .now) -> DayDetail {
    DayDetail(score: DailyScore(day: DayFormat.string(from: date), strain: strain, steps: 9_412, activeKcal: 612), sleep: nil,
              strain: DayStrain(trimp: 112, hrMin: 600, zoneMin: zones, steps: 9_412, activeKcal: 612, muscularTrimp: muscular),
              workouts: workouts)
}

// MARK: - test 15: the zone ticks

@Suite("Strain: zone ticks (§P5-12 test 15)")
struct StrainZoneTickTests {
    @Test(arguments: [(11.0, 8), (24, 18), (27, 20), (14, 11), (6, 5), (40, 30), (90, 30)])
    func theBoardsZonesLight(minutes: Double, lit: Int) {
        #expect(TickRow.litCount(minutes: minutes, scaleMax: StrainZones.scaleMax) == lit)
    }

    @Test func theScaleIsFortyMinutes() {
        #expect(StrainZones.scaleMax == 40)
    }

    @Test func rowsRunZ5ToZ1WithTheirMinutesAndSpokenRanges() throws {
        let zones = StrainZones(minutes: [11, 24, 27, 14, 6], trimp: 112)
        #expect(zones.rows.map(\.zone) == [5, 4, 3, 2, 1])
        #expect(zones.rows.map(\.value) == ["6", "14", "27", "24", "11"])
        #expect(zones.rows.map(\.label) == ["Z5 · Max", "Z4 · Threshold", "Z3 · Tempo", "Z2 · Aerobic", "Z1 · Easy"])
        let z3 = try #require(zones.rows.first { $0.zone == 3 })
        #expect(z3.spoken == "Zone 3, tempo, 70 to 80\u{00A0}percent of heart-rate reserve, 27 minutes")
        let z5 = try #require(zones.rows.first { $0.zone == 5 })
        #expect(z5.spoken.contains("90\u{00A0}percent or more"))
        #expect(zones.head.replacingOccurrences(of: "\u{00A0}", with: " ") == "82 min · TRIMP 112")
        #expect(zones.spokenValue(missing: "x").hasSuffix("TRIMP 112. Zones are in % of heart-rate reserve."))
    }

    @Test func withoutFiveValuesThereAreNoZones() {
        #expect(StrainZones(minutes: nil).minutes == nil)
        #expect(StrainZones(minutes: [1, 2, 3]).minutes == nil)
        #expect(StrainZones(minutes: nil).head == Fmt.placeholder)
        #expect(StrainZones(minutes: nil).rows.allSatisfy { $0.value == Fmt.placeholder && $0.minutes == nil })
        #expect(StrainZones(minutes: nil).spokenValue(missing: "None") == "None")
    }
}

// MARK: - test 24: the screen's decisions

@Suite("Strain: week, band, ruler, delta, split (§P5-12 test 24)")
@MainActor
struct StrainScreenDecisionTests {
    private func model(_ seed: DayDetail? = nil, history: [DailyScore] = [],
                       flags: [FeatureFlag: Bool] = [:]) -> (StrainViewModel, AppState) {
        let state = AppState(env: .test(flags: flags))
        if let seed { state.repository.seed(.detail(seed)) }
        state.history = history
        return (StrainViewModel(state: state, store: TrainStore(inMemory: true)), state)
    }

    @Test func theWeekIsSevenDaysEndingToday() throws {
        let (vm, state) = model()
        let today = Calendar.current.startOfDay(for: state.env.clock.now())
        #expect(vm.week.count == 7)
        let last = try #require(vm.week.last)
        #expect(Calendar.current.isDate(last.date, inSameDayAs: today) && last.isToday && last.isSelected)
        let first = try #require(vm.week.first)
        #expect(Calendar.current.isDate(first.date, inSameDayAs: DayFormat.shift(today, days: -6)))
    }

    /// The strip's taps stay in its week; a deep link's day only stops at today (review, deviation 3).
    @Test func theStripClampsToTheWeekADeepLinkOnlyToToday() {
        let (vm, state) = model()
        let today = Calendar.current.startOfDay(for: state.env.clock.now())
        vm.step(to: DayFormat.shift(today, days: 3))
        #expect(Calendar.current.isDate(vm.date, inSameDayAs: today), "no future day")
        vm.step(to: DayFormat.shift(today, days: -10))
        #expect(Calendar.current.isDate(vm.date, inSameDayAs: DayFormat.shift(today, days: -6)), "the strip's first day")

        vm.select(DayFormat.shift(today, days: 3))
        #expect(Calendar.current.isDate(vm.date, inSameDayAs: today), "no future day")
        vm.select(DayFormat.shift(today, days: -10))
        #expect(vm.date == DayFormat.shift(today, days: -10), "older than the strip: that day")
        #expect(!vm.week.contains { $0.isSelected }, "no strip cell selected")
        vm.select(DayFormat.shift(today, days: -2).addingTimeInterval(3_600 * 15))
        #expect(Calendar.current.isDate(vm.date, inSameDayAs: DayFormat.shift(today, days: -2)))
        #expect(vm.date == Calendar.current.startOfDay(for: vm.date), "the start of the day")
    }

    /// The shown day is named: the header's spoken value always, the date line under it on another day (review S4).
    @Test func theShownDayIsNamed() {
        let (vm, state) = model()
        let today = Calendar.current.startOfDay(for: state.env.clock.now())
        #expect(vm.title == String(localized: "Today"))
        #expect(vm.dateLine == nil, "today: no line, as in the draft")
        vm.step(to: DayFormat.shift(today, days: -1))
        #expect(vm.title == String(localized: "Yesterday"))
        let yesterday = DayFormat.shift(today, days: -1)
        #expect(vm.dateLine == yesterday.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        #expect(StrainPageContent.dateLine(today, today: today) == nil)
    }

    @Test(arguments: [(9.9, "light"), (10, "moderate"), (13.9, "moderate"), (14, "high"), (17.9, "high"), (18, "all out")])
    func theBandWord(strain: Double, word: String) {
        #expect(StrainHero(strain: strain).caption == "of 21 · \(word)")
        #expect(StrainHero(strain: strain, namesStrain: true).caption == "Strain · of 21 · \(word)")
    }

    @Test func theRulersZoneIsTicks30To42() {
        let ticks = RulerScale.zoneTickIndices(count: RulerScale.Ticks.strain, range: StrainHero.scale, zone: StrainHero.zone)
        #expect(ticks == Array(30...42))
        #expect(StrainHero.rulerLabels == ["0", "moderate 10–14", "21"])
        #expect(StrainHero(strain: 12.4).rulerValue
                == "\(Fmt.strain(12.4)), Moderate strain, on a scale from 0 to 21. The moderate range is 10 to 14.")
        #expect(StrainHero(strain: nil).rulerValue == String(localized: "No data"))
    }

    @Test func theDeltaNeedsThreePriorDays() {
        #expect(StrainHero.delta(12, prior: [10, 11]) == nil)
        #expect(StrainHero.delta(12, prior: [10, 11, 12]) == MetricDelta(current: 12, reference: 11))
        #expect(StrainHero.delta(nil, prior: [10, 11, 12]) == nil)

        let day = { (offset: Int) in DayFormat.string(from: DayFormat.shift(testNow, days: offset)) }
        let two = model(history: [DailyScore(day: day(-1), strain: 10), DailyScore(day: day(-2), strain: 10),
                                  DailyScore(day: day(0), strain: 13)]).0
        #expect(two.strainDelta == nil)
        #expect(two.board.hero.delta == nil)
        let three = model(history: (1...3).map { DailyScore(day: day(-$0), strain: 10) } + [DailyScore(day: day(0), strain: 13)]).0
        #expect(three.strainDelta == MetricDelta(current: 13, reference: 10))
        #expect(three.board.hero.delta == three.strainDelta)
        #expect(three.board.hero.numeralValue.contains("versus 7 days"))
    }

    @Test func theSplitOnlyWithAStrengthSession() {
        let cardio = model(detail(strain: 12.4, on: testNow)).0
        #expect(cardio.board.hero.split == nil)
        let both = model(detail(strain: 13.3, muscular: 44, on: testNow)).0
        let split = both.strainSplitText
        #expect(split != nil)
        #expect(both.board.hero.split == split)
        #expect(both.board.hero.numeralValue.hasSuffix(split ?? "–"))
    }

    @Test func theNumeral() {
        let hero = StrainHero(strain: 12.4)
        #expect(hero.numeral == Fmt.strain(12.4))
        #expect(hero.numeralLabel == "Strain \(Fmt.strain(12.4)) of 21")
        #expect(hero.numeralValue == "Moderate strain")
        #expect(StrainHero(strain: nil).numeral == nil)
        #expect(StrainHero.placeholder == "00.0")
    }
}

// MARK: - test 25: activity rows

@Suite("Strain: activity rows (§P5-12 test 25)")
struct StrainRowTests {
    @Test func aRunSaysStartDurationDistance() {
        let run = workout()
        let row = StrainRows.workout(run, session: nil, locale: gb)
        #expect(row.meta == MyDayText.join([seven10, "42 min", Fmt.distance(meters: 7_800)]))
        #expect(row.title == "Run")
        #expect(row.value == Fmt.strain(9.8))
        #expect(row.systemImage == ActivityStyle.icon(for: "running"))
        #expect(row.spoken.hasPrefix("Run, \(seven10), 42 minutes, \(StrainFormat.spokenDistance(7_800, locale: gb)), "))
        #expect(row.spoken.hasSuffix("Strain \(Fmt.strain(9.8))"))
    }

    @Test func withoutADistanceTheAverageHeartRate() {
        let row = StrainRows.workout(workout("hiit", distance: nil), session: nil, locale: gb)
        #expect(row.meta == MyDayText.join([seven10, "42 min", "148 bpm"]))
        #expect(row.spoken.contains("average heart rate 148\u{00A0}bpm"))
    }

    @Test func aLoggedSessionAddsItsLoad() throws {
        let s = try session()
        let merged = StrainRows.workout(workout("strength", distance: nil), session: s, locale: gb)
        #expect(merged.meta == MyDayText.join([seven10, "42 min", "148 bpm", "Load \(Fmt.load(84.6))"]))
        #expect(merged.title == "Upper A")
        #expect(merged.systemImage == "dumbbell")
        #expect(merged.spoken.hasSuffix("Muscular load \(Fmt.load(84.6))"))

        let alone = StrainRows.session(s, locale: gb)
        #expect(alone.meta == MyDayText.join([Fmt.time(at(17, 30), locale: gb), "55 min", "Load \(Fmt.load(84.6))"]))
        #expect(alone.value == Fmt.strain(6.1))
    }

    @Test func noStrainIsADash() {
        let row = StrainRows.workout(workout(strain: nil), session: nil, locale: gb)
        #expect(row.value == nil, "the row draws Fmt.placeholder in textSecondary")
        #expect(row.spoken.hasSuffix("No strain"))
    }

    @Test func anHourOrMoreIsAClock() {
        #expect(StrainFormat.durationText(minutes: 42) == "42 min")
        #expect(StrainFormat.durationText(minutes: 65) == "1:05 h")
        let long = StrainRows.workout(workout(minutes: 65), session: nil, locale: gb)
        #expect(long.meta?.hasPrefix(MyDayText.join([seven10, "1:05 h"])) == true)
    }

    /// One row for the three kinds: a workout, a logged session and a My Day item, the same `ActivityListRow.Content`.
    @Test func oneViewForTheThreeKinds() throws {
        let w = workout()
        let s = try session()
        let fromWorkout = StrainRow(.workout(w, nil), locale: gb)
        let fromSession = StrainRow(.session(s), locale: gb)
        let item = MyDayItem(id: "activity.\(UUID().uuidString)", kind: .activity(UUID()), symbol: "figure.run", title: "Run",
                             start: at(7, 10), end: at(7, 52), duration: 42 * 60, distanceM: 7_800, strain: .scored(10.6),
                             sources: [], upload: nil, editable: true)
        let fromMyDay = try #require(StrainRow(item, day: .now, workout: { _ in nil }, locale: gb))
        #expect(fromWorkout.identifier == "strain.row.workout.\(w.id.uuidString)")
        #expect(fromSession.identifier == "strain.row.session.\(s.id.uuidString)")
        #expect(fromMyDay.identifier == "strain.row.\(item.id)")
        #expect(fromMyDay.content.value == Fmt.strain(10.6))
        #expect(fromMyDay.content.meta == MyDayText.join([seven10, "42 min", Fmt.distance(meters: 7_800)]))
        #expect(fromWorkout.hint == String(localized: "Opens the workout"))
        #expect(fromSession.hint == String(localized: "Opens the session"))
    }

    @Test func aPendingMyDayItemSaysSoInItsMeta() throws {
        let item = MyDayItem(id: "activity.x", kind: .activity(UUID()), symbol: "figure.walk", title: "Walk",
                             start: at(12, 5), end: at(12, 29), duration: 24 * 60, distanceM: nil, strain: .pending,
                             sources: [], upload: nil, editable: false)
        let row = StrainRows.myDay(item, locale: gb)
        #expect(row.value == nil)
        #expect(row.meta?.hasSuffix(String(localized: "Strain pending").replacingOccurrences(of: " ", with: "\u{00A0}")) == true)
    }

    @Test func aWorkoutTheDayNoLongerHoldsHasNoRow() {
        let item = MyDayItem(id: "workout.x", kind: .workout(UUID()), symbol: "figure.run", title: "Run", start: at(7, 10),
                             end: at(7, 52), duration: 42 * 60, distanceM: nil, strain: .scored(9), sources: [], upload: nil,
                             editable: false)
        #expect(StrainRow(item, day: .now, workout: { _ in nil }, locale: gb) == nil)
    }
}

// MARK: - test 26: states

@Suite("Strain: states (§P5-12 test 26)")
@MainActor
struct StrainStateTests {
    @Test func loadingIsOutlinesAndNoSpinner() {
        let board = StrainBoard(detail: nil, score: nil, prior: [], split: nil, isLoading: true, failure: nil)
        #expect(board.look == .loading)
        #expect(board.isOutline)
        #expect(board.hero.numeral == nil)
        #expect(board.hero.caption.isEmpty, "no sentence while it loads")
        #expect(StrainBoard.loadingLabel == "Loading this day")
    }

    @Test func aCachedScoreShowsBeforeTheDetail() {
        let score = DailyScore(day: DayFormat.string(from: .now), strain: 12.4)
        let board = StrainBoard(detail: nil, score: score, prior: [], split: nil, isLoading: true, failure: nil)
        #expect(board.look == .loading, "the zones and tiles still load")
        #expect(board.hero.numeral == Fmt.strain(12.4))
        #expect(!board.lacksZones, "no \"no zones\" before the day is there")
    }

    @Test func noStrainSaysSo() {
        let board = StrainBoard(detail: detail(strain: nil), score: nil, prior: [], split: nil, isLoading: false, failure: nil)
        #expect(board.look == .loaded)
        #expect(board.hero.numeral == nil)
        #expect(board.hero.caption == "No strain recorded for this day.")
        #expect(board.stepsText == Fmt.integer(9_412))
    }

    @Test func noZonesIsTheShortTile() {
        let board = StrainBoard(detail: detail(strain: 9, zones: []), score: nil, prior: [], split: nil, isLoading: false,
                                failure: nil)
        #expect(board.lacksZones)
        #expect(board.zonesMissing == .sentence(StrainBoard.noZonesSentence))
        #expect(StrainBoard.noZonesSentence == "Your watch didn't record heart-rate zones for this day.")
        let full = StrainBoard(detail: detail(strain: 9), score: nil, prior: [], split: nil, isLoading: false, failure: nil)
        #expect(!full.lacksZones)
    }

    /// Review S2: today the absence isn't final; while the platform scores, nothing is said to be missing.
    @Test func theAbsenceCopyFollowsTheDaysScoring() {
        func board(_ scoring: StrainBoard.DayScoring) -> StrainBoard {
            StrainBoard(detail: detail(strain: nil, zones: []), score: nil, prior: [], split: nil, isLoading: false,
                        failure: nil, scoring: scoring)
        }
        let final = board(.final)
        #expect(final.hero.caption == StrainBoard.noStrainSentence)
        #expect(final.zonesMissing == .sentence(StrainBoard.noZonesSentence) && final.lacksZones)

        let today = board(.today)
        #expect(today.hero.caption == "No strain yet today.")
        #expect(today.zonesMissing == .sentence("No heart-rate zones yet today.") && today.lacksZones)

        let pending = board(.pending)
        #expect(pending.hero.caption == String(localized: "Scoring your latest data"))
        #expect(pending.hero.caption != StrainBoard.noStrainSentence)
        #expect(!pending.lacksZones, "the rows with \"–\", not the short tile")
        #expect(pending.zonesMissing == .pending(String(localized: "Scoring your latest data")))
        #expect(pending.zones.rows.allSatisfy { $0.value == Fmt.placeholder })
    }

    @Test(arguments: [(ScoringState?.none, true, StrainBoard.DayScoring.today), (.scored, true, .today),
                      (.waitingForSleep, true, .today), (.pending, true, .pending), (.pending, false, .pending),
                      (.scored, false, .final), (.stale, false, .final), (nil, false, .final)])
    func theDaysScoring(state: ScoringState?, isToday: Bool, expected: StrainBoard.DayScoring) {
        #expect(StrainBoard.DayScoring(state, isToday: isToday) == expected)
    }

    @Test func noWorkoutsIsAnEmptyList() {
        let state = AppState(env: .test())
        state.repository.seed(.detail(detail(strain: 4, on: testNow)))
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        #expect(vm.detail != nil, "the day is there")
        #expect(vm.rows().isEmpty)
    }

    @Test func theRowsKeepTheirIdentifiers() {
        let state = AppState(env: .test())
        let run = workout(start: Calendar.current.date(bySettingHour: 7, minute: 10, second: 0, of: testNow) ?? testNow)
        state.repository.seed(.detail(detail(strain: 9.8, workouts: [run], on: testNow)))
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        #expect(vm.rows().map(\.identifier) == ["strain.row.workout.\(run.id.uuidString)"])
        #expect(vm.rows().first?.destination == .workout(run))
    }

    /// The calm sentence, never the system's error text (R3-N3).
    @Test func anErrorIsTheCalmSentence() async throws {
        let api = MockPlatformAPI()
        let failure = APIError.transport(URLError(.notConnectedToInternet))
        api.failure = failure
        let state = AppState(env: .test(api: api))
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))

        await vm.load()

        let shown = try #require(vm.board.failure)
        #expect(shown.message == String(localized: "No connection. Check your internet and try again."))
        #expect(shown.message != failure.localizedDescription)
        #expect(vm.error == shown.message)
        #expect(vm.board.isOutline)
        #expect(vm.board.hero.caption.isEmpty)
    }

    @Test func offlineAndStale() {
        let error = ResourceError(URLError(.timedOut), kind: .transient, attempts: 3, at: .now)
        let issue = RefreshIssue(reason: .unreachable, resource: .today, dataFrom: nil, failures: 3, error: error)
        #expect(StrainStatus.decide(issue: issue, isOnline: true, isDemo: false, hasDataSource: true, hasCachedDay: true,
                                    staleSince: nil) == .issue(issue))
        #expect(StrainStatus.decide(issue: nil, isOnline: false, isDemo: false, hasDataSource: true, hasCachedDay: true,
                                    staleSince: nil) == .line(.offline))
        #expect(StrainStatus.decide(issue: nil, isOnline: false, isDemo: false, hasDataSource: true, hasCachedDay: false,
                                    staleSince: nil) == nil, "nothing cached: the board's own sentence")
        let since = Date(timeIntervalSince1970: 1_792_000_000)
        #expect(StrainStatus.decide(issue: nil, isOnline: true, isDemo: false, hasDataSource: true, hasCachedDay: true,
                                    staleSince: since) == .line(.stale(since: since)))
        #expect(StrainStatus.decide(issue: nil, isOnline: false, isDemo: true, hasDataSource: true, hasCachedDay: true,
                                    staleSince: nil) == nil, "demo data is never offline")
        #expect(StrainStatus.decide(issue: nil, isOnline: true, isDemo: false, hasDataSource: true, hasCachedDay: true,
                                    staleSince: nil) == nil)
    }

    @Test func anotherDayHidesTrain() {
        let state = AppState(env: .test(flags: [.trainEnabled: true]))
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        #expect(vm.showsTrainSection)
        vm.step(to: DayFormat.shift(state.env.clock.now(), days: -1))
        #expect(!vm.showsTrainSection)
        #expect(vm.takeStepAnnouncement()?.hasPrefix(String(localized: "Yesterday")) == true)
        #expect(vm.takeStepAnnouncement() == nil, "once")
    }
}

// MARK: - test 27: the workout

@Suite("Workout detail (§P5-12 test 27)")
struct WorkoutBoardTests {
    private func detail(_ w: Workout, hr: [HRPoint]? = nil, zones: [Double] = [4, 24, 20, 0, 0]) -> WorkoutDetail {
        let points = hr ?? (0...52).map { HRPoint(t: w.start.addingTimeInterval(Double($0) * 60), bpm: 104 + Double($0 % 12) * 5) }
        return WorkoutDetail(workout: w, hr: points, zoneMin: zones, trimp: 114)
    }

    @Test func theNumeralAndRulerAreTheWorkouts() {
        let w = workout(strain: 10.6)
        let board = WorkoutBoard(workout: w, detail: nil, isLoading: true)
        #expect(board.hero.numeral == Fmt.strain(10.6))
        #expect(board.hero.caption == "Strain · of 21 · moderate")
        #expect(board.hero.rulerValue.hasPrefix("\(Fmt.strain(10.6)), Moderate strain"))
        #expect(WorkoutBoard(workout: workout(strain: nil), detail: nil, isLoading: false).hero.caption == "Strain · of 21")
    }

    @Test func theZonesAreOnTheFortyMinuteScale() {
        let w = workout()
        let board = WorkoutBoard(workout: w, detail: detail(w), isLoading: false)
        #expect(board.zones.minutes == [4, 24, 20, 0, 0])
        #expect(board.zones.head.replacingOccurrences(of: "\u{00A0}", with: " ") == "48 min", "no TRIMP: it is a tile")
        #expect(StrainZones.scaleMax == 40)
        #expect(board.zones.rows.map { TickRow.litCount(minutes: $0.minutes, scaleMax: StrainZones.scaleMax) } == [0, 0, 15, 18, 3])
    }

    @Test func theTilesWithAndWithoutADistance() {
        let w = workout(minutes: 52)
        let board = WorkoutBoard(workout: w, detail: detail(w), isLoading: false)
        #expect(board.stats.map(\.id) == ["duration", "trimp", "averageHR", "maxHR", "energy", "distance"])
        #expect(board.stats.map(\.value).prefix(5) == ["52", "114", "148", "176", "540"])
        #expect(board.stats.map(\.unit).prefix(5) == ["min", nil, "bpm", "bpm", "kcal"])
        #expect(board.stats.map(\.label) == ["Duration", "TRIMP", "Average heart rate", "Max heart rate", "Energy", "Distance"])
        #expect(board.stats.first?.spoken == "52 minutes")

        let indoor = workout("strength", distance: nil)
        #expect(WorkoutBoard(workout: indoor, detail: nil, isLoading: true).stats.map(\.id)
                == ["duration", "trimp", "averageHR", "maxHR", "energy"])
        #expect(WorkoutBoard(workout: indoor, detail: nil, isLoading: true).stats[1].value == Fmt.placeholder)
    }

    @Test func theSessionRowOnlyWithASession() throws {
        #expect(WorkoutBoard(workout: workout(), detail: nil, isLoading: false).sessionRow == nil)
        let logged = workout("strength", sessionId: UUID(), muscularLoad: 84.6)
        let row = try #require(WorkoutBoard(workout: logged, detail: nil, isLoading: false).sessionRow)
        #expect(row.title == "Logged session")
        #expect(row.meta == "Load \(Fmt.load(84.6))")
        #expect(!row.showsValue)
    }

    @Test func theStates() {
        let w = workout()
        let loading = WorkoutBoard(workout: w, detail: nil, isLoading: true)
        #expect(loading.plot == nil && !loading.lacksZones, "outlines, not \"no zones\"")
        #expect(loading.isOutline && !loading.lacksSeries)
        let failed = WorkoutBoard(workout: w, detail: nil, isLoading: false, failure: SleepLoadFailure(reason: .busy))
        #expect(failed.isOutline, "couldn't load: outlines")
        #expect(!failed.lacksZones && !failed.lacksSeries, "never \"no zones\" or \"no series\" without a detail")
        let noSeries = WorkoutBoard(workout: w, detail: detail(w, hr: []), isLoading: false)
        #expect(noSeries.plot == nil && noSeries.lacksSeries && !noSeries.isOutline)
        let one = WorkoutBoard(workout: w, detail: detail(w, hr: [HRPoint(t: w.start, bpm: 120)]), isLoading: false)
        #expect(one.plot == nil, "a curve needs two points")
        let noZones = WorkoutBoard(workout: w, detail: detail(w, zones: []), isLoading: false)
        #expect(noZones.lacksZones)
        #expect(WorkoutBoard.noZonesSentence == "No heart-rate zones for this workout.")
        #expect(WorkoutBoard(workout: w, detail: detail(w), isLoading: false).plot != nil)
    }

    @Test func theHeaderAndSource() {
        let w = workout(start: at(6, 40), minutes: 52)
        let board = WorkoutBoard(workout: w, detail: nil, isLoading: false)
        #expect(board.title == "Run")
        let (from, to) = (Fmt.time(w.start, locale: gb), Fmt.time(w.end, locale: gb))
        #expect(board.when(locale: gb).hasSuffix(" · \(from)–\(to)"))
        #expect(board.spokenWhen(locale: gb).hasSuffix(", \(from) to \(to)"))
        #expect(board.sourceText == "Recorded by Garmin Connect")
        #expect(board.averageText == "avg 148 bpm")
    }

    /// The draft's curve, 104…159 bpm around an average of 148: ticks 120 / 150 / 180, the top tick inside the domain; 15-minute
    /// clock ticks from the start.
    @Test func theChartsScales() throws {
        let (domain, ticks) = HeartRatePlot.yScale(lo: 104, hi: 159)
        #expect(ticks == [120, 150, 180])
        #expect(domain.lowerBound < 104 && domain.upperBound > 180)

        let start = at(6, 40)
        let x = HeartRatePlot.xTicks(from: start, to: start.addingTimeInterval(52 * 60))
        #expect(x.map { Int($0.timeIntervalSince(start) / 60) } == [0, 15, 30, 45])
        // From AX1, every other one: 6:40 and 7:10.
        let fiftyTwo = try #require(HeartRatePlot(points: [HRPoint(t: start, bpm: 120), HRPoint(t: start.addingTimeInterval(52 * 60), bpm: 130)],
                                                  average: nil))
        #expect(fiftyTwo.largeTextXTicks.map { Int($0.timeIntervalSince(start) / 60) } == [0, 30])
        let long = HeartRatePlot.xTicks(from: start, to: start.addingTimeInterval(150 * 60))
        #expect(long.map { Int($0.timeIntervalSince(start) / 60) } == [0, 60, 120])

        let points = [HRPoint(t: start, bpm: 104), HRPoint(t: start.addingTimeInterval(600), bpm: 159),
                      HRPoint(t: start.addingTimeInterval(1_200), bpm: 140)]
        let plot = try #require(HeartRatePlot(points: points, average: 148))
        #expect(plot.peak.bpm == 159)
        #expect(plot.peakText == "peak 159")
        #expect(plot.spokenValue == "Average 148 beats per minute, peak 159")
        #expect(HeartRatePlot(points: points, average: nil)?.spokenValue == "Peak 159 bpm")
    }
}
