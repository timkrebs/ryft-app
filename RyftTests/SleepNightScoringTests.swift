import Foundation
import Testing
@testable import Ryft

// R2-F1: Sleep → Day tells the platform's three words about a night without sleep apart, as Today does. `DayMarker` maps
// `pending` and `waiting_for_sleep` to one dot, and Sleep said "Your night is being scored." for both. A watch charging
// overnight: the platform scores today and answers `scoring_state: "waiting_for_sleep"` with `sleep: null` all day; Today
// says "Last night hasn't reached RYFT yet." and hides Apple Health's raw night. So does Sleep now. The days are decoded
// from `GET /v1/days/{day}` JSON, as the client gets them.
//
// S1 (round 4): today's state is Today's (`ScoringWord.state`): this phone's word since its last write, then
// `GET /v1/me/sync`'s, then the row. Right after the night uploads the row still says `waiting_for_sleep` while the
// ledger says `pending`: Today shows the night being scored, and Sleep must too. N1: a `scoring_state` this app doesn't
// know decodes to nil, which is not "scored" on its own.

private let enUS = Locale(identifier: "en_US")
private let waiting = "Last night hasn't reached RYFT yet."

@MainActor
struct SleepNightScoringTests {
    private let now = Date(timeIntervalSince1970: 1_794_906_000) // 2026-11-17, morning in Berlin
    private var today: Date { Calendar.current.startOfDay(for: now) }

    /// `GET /v1/days/{day}` for today with `sleep: null`: the day scored without a night (`waiting_for_sleep`, `stale`:
    /// recovery and strain from the day so far, no sleep values), or the placeholder while the night is scored (`pending`,
    /// or `placeholder` with another word).
    private func day(_ state: String, on date: Date? = nil, placeholder: Bool = false) throws -> DayDetail {
        let key = DayFormat.string(from: date ?? today)
        let score = state == "pending" || placeholder
            ? #"{"day":"\#(key)","state":"calibrating","baseline_days":0,"calibrating":false,"#
            + #""computed_at":"0001-01-01T00:00:00Z","scoring_state":"\#(state)","coverage":null}"#
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

    private func appState(_ detail: DayDetail, word: ScoringWord.Kind? = nil, status: SyncStatus? = nil) -> AppState {
        let state = AppState(env: .test(clock: TestClock(now: now)))
        state.today = detail
        state.lastNight = rawNight
        let key = DayFormat.string(from: today)
        if let word { state.repository.scoringLedger = { [key: ScoringWord(kind: word, at: self.now)] } }
        state.syncStatus = status
        return state
    }

    private func model(_ state: AppState) -> SleepViewModel {
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        return vm
    }

    private func model(_ detail: DayDetail, word: ScoringWord.Kind? = nil, status: SyncStatus? = nil) -> SleepViewModel {
        model(appState(detail, word: word, status: status))
    }

    /// `GET /v1/me/sync` as API.md shows it, its `today` about `day` in `state`.
    private func status(_ state: String, day: Date? = nil) throws -> SyncStatus {
        let key = DayFormat.string(from: day ?? today)
        let json = #"{ "gate": null, "last_sync_at": "2026-11-17T06:58:12Z", "last_sync_device": "iPhone","#
            + #" "latest": { "hr": "2026-11-17T06:55:00Z", "sleep": "2026-11-17T06:41:00Z" },"#
            + #" "today": { "day": "\#(key)", "state": "\#(state)", "scored_at": null, "model_version": "2026.10.1" },"#
            + #" "pending_days": ["\#(key)"], "expected_within_sec": 20, "resync_requested_at": null }"#
        return try APIClient.jsonDecoder.decode(SyncStatus.self, from: Data(json.utf8))
    }

    // MARK: the mapping

    @Test func theThreeWordsAboutANight() {
        typealias N = SleepBoard.NightScoring
        #expect(N(.pending, isToday: true, hasNight: false, dayIsScored: false) == .scoring)
        #expect(N(.waitingForSleep, isToday: true, hasNight: false, dayIsScored: true) == .awaitingNight)
        #expect(N(.stale, isToday: true, hasNight: false, dayIsScored: true) == .awaitingNight)
        #expect(N(.stale, isToday: true, hasNight: true, dayIsScored: true) == .scored, "with a night the score stands")
        #expect(N(.stale, isToday: false, hasNight: false, dayIsScored: true) == .scored, "stale is about today only")
        #expect(N(.scored, isToday: true, hasNight: false, dayIsScored: true) == .scored)
        // A push's (or the status's) scored before today's row: being scored, as on Today.
        #expect(N(.scored, isToday: true, hasNight: false, dayIsScored: false) == .scoring)
        #expect(N(.scored, isToday: true, hasNight: false, dayIsScored: nil) == .scoring)
        #expect(N(.scored, isToday: false, hasNight: false, dayIsScored: false) == .scored)
        // N1 (re-pinned, was `.scored`): no word is not "scored" on its own. Today's unscored day waits for its night.
        #expect(N(nil, isToday: true, hasNight: false, dayIsScored: false) == .awaitingNight)
        #expect(N(nil, isToday: true, hasNight: false, dayIsScored: nil) == .awaitingNight)
        #expect(N(nil, isToday: true, hasNight: false, dayIsScored: true) == .scored)
        #expect(N(nil, isToday: false, hasNight: false, dayIsScored: false) == .scoring, "a past day: scored or pending")
        #expect(N(nil, isToday: false, hasNight: false, dayIsScored: true) == .scored)
        #expect(N(nil, isToday: false, hasNight: false, dayIsScored: nil) == .scored, "a past day without a row: no night")
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

    // MARK: S1: the same facts as Today

    /// The row still waits for sleep, but the night uploaded: the ledger's `pending` wins, as on Today.
    @Test func aPendingWordOverAWaitingRowIsBeingScored() throws {
        let vm = model(try day("waiting_for_sleep"), word: .pending)
        #expect(vm.scoringState == .pending && vm.nightScoring == .scoring)
        #expect(vm.board.look == .pending && vm.board.clock == "7:17", "Apple Health's night: \(vm.board.look)")
        #expect(vm.board.caption == String(localized: "From Apple Health · not scored yet"))
    }

    /// The same from `GET /v1/me/sync`: its `today` says pending; one about another day doesn't count.
    @Test func aPendingStatusOverAWaitingRowIsBeingScored() throws {
        let vm = model(try day("waiting_for_sleep"), status: try status("pending"))
        #expect(vm.scoringState == .pending && vm.nightScoring == .scoring)
        #expect(vm.board.look == .pending && vm.board.clock == "7:17")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let other = model(try day("waiting_for_sleep"), status: try status("pending", day: yesterday))
        #expect(other.nightScoring == .awaitingNight, "a status about yesterday says nothing about today")
    }

    /// Another day's state is its row's: the ledger and the status are about today.
    @Test func anotherDayIsItsRow() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let vm = model(try day("scored", on: yesterday), word: .pending, status: try status("pending"))
        vm.show(night: yesterday)
        #expect(!vm.isToday && vm.scoringState == .scored)
    }

    /// The board redraws when the word lands (the ledger and the status are observed).
    @Test func theBoardRedrawsWhenTheWordLands() throws {
        let state = appState(try day("waiting_for_sleep"))
        let vm = model(state)
        let sync = SyncService.ungated(env: state.env)
        state.repository.scoringLedger = { [weak sync] in sync?.scoringLedger ?? [:] }
        #expect(vm.nightScoring == .awaitingNight)
        let word = Redrawn()
        withObservationTracking { _ = vm.board } onChange: { word.set() }
        sync.awaiting([DayFormat.string(from: today)])
        #expect(word.value && vm.board.look == .pending, "the ledger's word redraws the board")
        let otherState = appState(try day("waiting_for_sleep"))
        let other = model(otherState)
        let status = Redrawn()
        withObservationTracking { _ = other.board } onChange: { status.set() }
        otherState.syncStatus = try self.status("pending")
        #expect(status.value && other.board.look == .pending, "the status redraws the board")
    }

    /// Today says the same for the same facts, this phone's word and the status included: the night is being scored on
    /// both or neither, with Apple Health's night on both or neither; where Today's gauge waits for the night, Sleep
    /// does, and without an earlier scored day in the same sentence (with one, Today's is about the dimmed readiness).
    /// Today's `stale` day without a night has the empty gauge, "It appears once last night has synced.": Sleep's
    /// "Last night hasn't reached RYFT yet." (R2-F1).
    @Test(arguments: [
        AgreeCase("waiting_for_sleep"), AgreeCase("waiting_for_sleep", prior: true), AgreeCase("stale"),
        AgreeCase("pending"), AgreeCase("pending", prior: true), AgreeCase("scored"),
        // S1: the row still waits, the word or the status doesn't.
        AgreeCase("waiting_for_sleep", word: .pending), AgreeCase("waiting_for_sleep", word: .pending, prior: true),
        AgreeCase("waiting_for_sleep", status: "pending"), AgreeCase("stale", word: .pending),
        AgreeCase("pending", word: .scored, prior: true), AgreeCase("waiting_for_sleep", word: .scored),
        // N1: a word this app doesn't know, on today's placeholder: waiting on both.
        AgreeCase("recomputing", placeholder: true, prior: true),
    ])
    func todayAgrees(_ c: AgreeCase) throws {
        let detail = try day(c.state, placeholder: c.placeholder)
        var f = TodaySyncFacts(now: now)
        f.today = detail.score
        f.lastNight = rawNight
        f.engine.backfillDone = true
        if c.prior {
            let yesterday = DayFormat.string(from: Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today)
            f.prior = [DailyScore(day: yesterday, readiness: 70, computedAt: now.addingTimeInterval(-86_400),
                                  scoringState: .scored)]
        }
        f.scoringWord = c.word.map { ScoringWord(kind: $0, at: now) }
        f.status = try c.status.map { try status($0) }
        let p = TodayPresentation.decide(f.scores)
        let content = TodayContent(facts: f, presentation: p, hero: TodayStates.hero(f, presentation: p), hasDataSource: true,
                                   readinessWeek: [], detailSleepMin: nil)
        var todayScores = false, todayWaits = false
        if case .pending(let night) = p.gauge { (todayScores, todayWaits) = (!night.waitingForSleep, night.waitingForSleep) }

        let vm = model(detail, word: c.word, status: try c.status.map { try status($0) })
        let said = "\(c): Sleep \(vm.nightScoring); Today \(p.gauge), \(content.sentence)"
        #expect((vm.nightScoring == .scoring) == todayScores, "being scored on both or neither: \(said)")
        #expect((vm.board.clock != nil) == (p.rawNight != nil), "Apple Health's night on both or neither: \(said)")
        if todayWaits { #expect(vm.nightScoring == .awaitingNight, "\(said)") }
        if todayWaits, !c.prior {
            #expect(content.sentence == waiting && vm.board.caption == waiting, "\(said)")
        }
        #expect(vm.nightScoring == c.expected, "\(said)")
    }

    struct AgreeCase: Sendable, CustomStringConvertible {
        let state: String
        let word: ScoringWord.Kind?
        let status: String?
        let placeholder: Bool
        /// A scored yesterday with a readiness, so Today dims it while it waits.
        let prior: Bool
        /// What Sleep says: waiting with the row's or no word, being scored with the platform's `pending` or this
        /// phone's word, scored for a scored day.
        var expected: SleepBoard.NightScoring {
            if state == "scored" { return .scored }
            if word == .pending || status == "pending" || state == "pending" { return .scoring }
            if word == .scored { return state == "waiting_for_sleep" ? .awaitingNight : .scoring }
            return .awaitingNight
        }
        init(_ state: String, word: ScoringWord.Kind? = nil, status: String? = nil, placeholder: Bool = false,
             prior: Bool = false) {
            self.state = state
            self.word = word
            self.status = status
            self.placeholder = placeholder
            self.prior = prior
        }
        var description: String {
            "\(state)\(word.map { ", word \($0)" } ?? "")\(status.map { ", status \($0)" } ?? "")\(prior ? ", after a scored day" : "")"
        }
    }
}

/// Set from `onChange`, which may run on any thread.
private final class Redrawn: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    var value: Bool { lock.withLock { on } }
    func set() { lock.withLock { on = true } }
}
