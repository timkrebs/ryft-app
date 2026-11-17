import Foundation
import Testing
@testable import Ryft

// R2-F1: Sleep → Day tells the platform's three words about a night without sleep apart, as Today does. `DayMarker` maps
// `pending` and `waiting_for_sleep` to one dot, and Sleep said "Your night is being scored." for both. A watch charging
// overnight: the platform scores today and answers `scoring_state: "waiting_for_sleep"` with `sleep: null` all day; Today
// says "Last night hasn't reached RYFT yet." and hides Apple Health's raw night. So does Sleep now. The days are decoded
// from `GET /v1/days/{day}` JSON, as the client gets them.

private let enUS = Locale(identifier: "en_US")
private let waiting = "Last night hasn't reached RYFT yet."

@MainActor
struct SleepNightScoringTests {
    private let now = Date(timeIntervalSince1970: 1_794_906_000) // 2026-11-17, morning in Berlin
    private var today: Date { Calendar.current.startOfDay(for: now) }

    /// `GET /v1/days/{day}` for today with `sleep: null`: the day scored without a night (`waiting_for_sleep`, `stale`:
    /// recovery and strain from the day so far, no sleep values), or the placeholder while the night is scored (`pending`).
    private func day(_ state: String, on date: Date? = nil) throws -> DayDetail {
        let key = DayFormat.string(from: date ?? today)
        let score = state == "pending"
            ? #"{"day":"\#(key)","state":"calibrating","baseline_days":0,"calibrating":false,"#
            + #""computed_at":"0001-01-01T00:00:00Z","scoring_state":"pending","coverage":null}"#
            : #"{"day":"\#(key)","readiness":null,"state":"calibrating","recovery":62,"strain":4.1,"#
            + #""sleep_need_min":492,"sleep_debt_min":35,"baseline_days":30,"calibrating":false,"#
            + #""computed_at":"2026-11-17T09:02:11.5Z","scoring_state":"\#(state)","coverage":null}"#
        let json = #"{"score":"# + score + #","sleep":null,"strain":null,"workouts":[]}"#
        return try APIClient.jsonDecoder.decode(DayDetail.self, from: Data(json.utf8))
    }

    /// Apple Health's night, woken at 06:52 this morning: 7:17 asleep.
    private var rawNight: RawNight {
        let wake = today.addingTimeInterval(6 * 3_600 + 52 * 60)
        return RawNight(asleepMin: 437, bedtime: wake.addingTimeInterval(-8 * 3_600 + 25 * 60), wake: wake, source: "Connect")
    }

    private func model(_ detail: DayDetail) -> SleepViewModel {
        let state = AppState(env: .test(clock: TestClock(now: now)))
        state.today = detail
        state.lastNight = rawNight
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        return vm
    }

    // MARK: the mapping

    @Test func theThreeWordsAboutANight() {
        #expect(SleepBoard.NightScoring(.pending, isToday: true, hasNight: false) == .scoring)
        #expect(SleepBoard.NightScoring(.waitingForSleep, isToday: true, hasNight: false) == .awaitingNight)
        #expect(SleepBoard.NightScoring(.stale, isToday: true, hasNight: false) == .awaitingNight)
        #expect(SleepBoard.NightScoring(.stale, isToday: true, hasNight: true) == .scored, "with a night the score stands")
        #expect(SleepBoard.NightScoring(.stale, isToday: false, hasNight: false) == .scored, "stale is about today only")
        #expect(SleepBoard.NightScoring(.scored, isToday: true, hasNight: false) == .scored)
        #expect(SleepBoard.NightScoring(nil, isToday: true, hasNight: false) == .scored)
    }

    // MARK: from the API's JSON, through the model

    @Test func pendingShowsApplesNightUnscored() throws {
        let vm = model(try day("pending"))
        #expect(vm.nightScoring == .scoring)
        let board = vm.board
        #expect(board.look == .pending && board.clock == "7:17")
        #expect(board.caption == String(localized: "From Apple Health · not scored yet"))
        #expect(vm.stepAnnouncement.hasSuffix(". \(board.numeralLabel ?? "")"), "\(vm.stepAnnouncement)")
    }

    @Test(arguments: ["waiting_for_sleep", "stale"])
    func noNightYetSaysWhatTodaySaysAndHidesTheRawNight(_ state: String) throws {
        let vm = model(try day(state))
        #expect(vm.nightScoring == .awaitingNight, "\(state)")
        let board = vm.board
        #expect(board.look == .awaitingNight && board.isOutline, "\(state): \(board.look)")
        #expect(board.caption == waiting && board.spokenCaption == waiting, "\(state): \(board.caption)")
        #expect(board.clock == nil && board.numeralLabel == nil && board.ruler.value == nil, "no raw night: \(state)")
        #expect(board.ruler.zone == nil, "no need from a day without its night")
        #expect(!board.caption.contains("being scored") && !board.caption.contains("No sleep"))
        #expect(vm.stepAnnouncement.hasSuffix(". \(waiting)"), "the announcement follows: \(vm.stepAnnouncement)")
    }

    @Test func aScoredDayWithoutANightSaysNoSleep() throws {
        let vm = model(try day("scored"))
        #expect(vm.nightScoring == .scored)
        #expect(vm.board.look == .noSleep && vm.board.caption == String(localized: "No sleep recorded for this night."))
        #expect(vm.board.clock == nil, "Apple Health's night isn't shown on a scored day")
    }

    /// Today says the same for the same day: the sentence while the platform waits, and no raw night.
    @Test func todayAgrees() throws {
        let detail = try day("waiting_for_sleep")
        var f = TodaySyncFacts(now: now)
        f.today = detail.score
        f.lastNight = rawNight
        f.engine.backfillDone = true
        let p = TodayPresentation.decide(f.scores)
        let content = TodayContent(facts: f, presentation: p, hero: TodayStates.hero(f, presentation: p), hasDataSource: true,
                                   readinessWeek: [], detailSleepMin: nil)
        #expect(content.sentence == waiting && content.presentation.rawNight == nil, "\(content.sentence)")
    }
}
