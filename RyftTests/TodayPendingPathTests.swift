import Foundation
import Testing
@testable import Ryft

/// How an upload that outlived its account ended.
enum UploadEnding: String, CaseIterable, Sendable {
    case cancelled, failed, finished
}

/// The platform's day reads, scripted: the days the test put in, and today unscored until it puts today in.
private final class ScriptedDays: RyftDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String: DailyScore] = [:]
    private var unscored: ScoringState = .waitingForSleep
    private let base = MockDataSource.shared

    /// A scored (or calibrating) row, from now on.
    func put(_ row: DailyScore) { lock.withLock { rows[row.day] = row } }
    /// What an unscored day's `scoring_state` says.
    func unscoredState(_ state: ScoringState) { lock.withLock { unscored = state } }

    func days(from: Date, to: Date) async throws -> [DailyScore] {
        let lo = DayFormat.string(from: from), hi = DayFormat.string(from: to)
        return lock.withLock { rows.values.filter { $0.day >= lo && $0.day <= hi }.sorted { $0.day < $1.day } }
    }

    func day(_ date: Date) async throws -> DayDetail {
        let key = DayFormat.string(from: date)
        // API.md: a day not scored yet comes with `computed_at` 0001-01-01.
        let row = lock.withLock {
            rows[key] ?? DailyScore(day: key, computedAt: Date(timeIntervalSince1970: -62_135_596_800), scoringState: unscored)
        }
        return DayDetail(score: row, sleep: nil, workouts: [])
    }

    func me() async throws -> User { try await base.me() }
    func patchMe(_ p: UserPatch) async throws -> User { try await base.patchMe(p) }
    func sleep(range: SleepRangeKind) async throws -> SleepRange { try await base.sleep(range: range) }
    func workouts(from: Date, to: Date) async throws -> [Workout] { [] }
    func workout(id: UUID) async throws -> WorkoutDetail { try await base.workout(id: id) }
    func trends(metric: TrendMetric, range: TrendRange) async throws -> TrendSeries {
        try await base.trends(metric: metric, range: range)
    }
    func insights() async throws -> [Insight] { [] }
    func recompute(from: Date, to: Date) async throws {}
    func deleteMe() async throws -> AccountDeleted { try await base.deleteMe() }
}

/// Today's view model on the live pipeline (`LiveSyncSteps` over `SyncService`), `MockHealthStore`, the mock
/// platform and `TestClock`, at 07:30 with yesterday scored at 76.
@MainActor
private final class Harness {
    static let now = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0,
                                           of: Date(timeIntervalSince1970: 1_792_600_000))!
    let today = DayFormat.string(from: now)
    let yesterday = DayFormat.string(from: DayFormat.shift(now, days: -1))
    let days = ScriptedDays()
    let api: MockPlatformAPI
    let health: MockHealthStore
    let clock: TestClock
    let state: AppState
    let sync: SyncService
    let pipeline: SyncCoordinator
    let vm: TodayViewModel

    /// `firstSync`: no anchors yet (the first score's window goes first, the backfill after it) and nothing scored.
    /// `expected`: the upload's `expected_within_sec`.
    init(inBackground: Bool = false, firstSync: Bool = false, night: Bool = true, expected: Int = 20) {
        api = MockPlatformAPI(screens: days)
        let stream = HealthStream.quantity(.heartRate)
        health = MockHealthStore(streams: [stream])
        if firstSync {
            if night { health.recent = [stream: [Self.night()]] }
        } else {
            // A phone that synced before: the night is what's new.
            health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: stream)
            if night { health.pages = [stream: [Self.night()]] }
        }
        clock = TestClock(now: Self.now)
        let env = AppEnvironment.test(api: api, health: health, clock: clock)
        state = AppState(env: env)
        sync = SyncService.ungated(env: env)
        pipeline = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: clock, inBackground: inBackground)
        vm = TodayViewModel(state: state, sync: sync, coordinator: pipeline, apiStatus: APIStatus())
        api.syncResponse = SyncResponse(samples: 2, sleep: 0, workouts: 0, daysTouched: firstSync ? [yesterday, today] : [today],
                                        scoring: SyncScoring(queuedDays: [today], expectedWithinSec: expected))
        if !firstSync {
            let row = DailyScore(day: yesterday, readiness: 76, state: .balanced, recovery: 75, baselineDays: 30,
                                 calibrating: false, computedAt: Self.now.addingTimeInterval(-86_400), scoringState: .scored)
            days.put(row)
            state.history = [row]
        }
        waitsForSleep()
    }

    /// Last night's heart rate, as the watch wrote it.
    static func night() -> HealthDelta {
        let start = now.addingTimeInterval(-5 * 3_600)
        return HealthDelta(samples: (0..<2).map {
            Sample(type: .heartRate, start: start.addingTimeInterval(Double($0) * 60),
                   end: start.addingTimeInterval(Double($0) * 60), value: 52, unit: "bpm", source: "Watch")
        })
    }

    // MARK: the platform

    /// Before the night is uploaded.
    func waitsForSleep() {
        api.scoringToday = TodayState(day: today, state: .waitingForSleep, scoredAt: nil, modelVersion: "2026.10.1")
        api.pendingDays = []
        days.unscoredState(.waitingForSleep)
    }

    /// The upload was accepted: today is being scored.
    func lists(_ pending: [String]? = nil) {
        api.scoringToday = TodayState(day: today, state: .pending, scoredAt: nil, modelVersion: "2026.10.1")
        api.pendingDays = pending ?? [today]
        days.unscoredState(.pending)
    }

    /// Scoring finished: today's row with a readiness, or a calibrating one without (the first week).
    func scores(readiness: Int? = 74, calibrating: Bool = false) {
        days.put(DailyScore(day: today, readiness: readiness, state: readiness == nil ? nil : .balanced, recovery: 72,
                            baselineDays: calibrating ? 2 : 30, calibrating: calibrating, computedAt: clock.now(),
                            scoringState: .scored))
        api.scoringToday = TodayState(day: today, state: .scored, scoredAt: clock.now(), modelVersion: "2026.10.1")
        api.pendingDays = []
    }

    // MARK: waits

    /// Under the mock's lock: the stale refresh's reads append to its calls from other threads meanwhile (an unlocked
    /// `api.calls` read once saw none).
    var statusReads: Int { api.count("syncStatus") }

    /// The scoring wait sleeps on the clock (the only sleeper left). `phase`: the run uploaded first, so `SyncService`
    /// shows the wait (a `daysChanged` run starts from idle, which `SyncMachine` doesn't lead to `awaitingScores`).
    func waitsOnTheClock(phase: Bool = true) async -> Bool {
        await eventually { (!phase || sync.phase == .awaitingScores) && clock.pendingSleeps == 1 }
    }

    /// Advances to the wait's next ask and returns once its answer is stored.
    func nextPoll(after seconds: Int, phase: Bool = true) async {
        let asked = statusReads
        #expect(await waitsOnTheClock(phase: phase))
        clock.advance(by: .seconds(seconds))
        #expect(await eventually { statusReads == asked + 1 && sync.statusReadAt == clock.now() })
    }

    // MARK: what Today shows

    /// Row C's scoring variant: "Scoring your night…", not "Waiting for last night's sleep".
    var scoresTheNight: Bool {
        if case .pending(let night) = vm.hero { return !night.waitingForSleep }
        return false
    }

    func lands(readiness: Int = 74) async -> Bool {
        await eventually { vm.hero == .score && vm.readiness == Double(readiness) }
    }
}

/// D3b (`architecture.md` §D3b): after a write that touches today, every refresh path shows "Scoring your night…"
/// while the platform lists today, and lands the score once it's done, on Today and the widget alike.
@Suite("Today: pending on every refresh path")
@MainActor
struct TodayPendingPathTests {
    @Test func pullToRefreshShowsTheNightBeingScoredUntilItLands() async {
        let h = Harness()
        let pull = Task { await h.vm.refresh() }
        // The pull's own status read answered before the upload went up (its 10 s cache, or simply first).
        #expect(await eventually { h.api.count("sync") == 1 && h.sync.statusReadAt != nil })
        #expect(await h.waitsOnTheClock())
        h.lists()
        #expect(h.scoresTheNight, "right after the upload: \(h.vm.hero)")
        await h.nextPoll(after: 20)
        #expect(h.scoresTheNight, "the platform lists today: \(h.vm.hero)")
        h.scores()
        await h.nextPoll(after: 40)
        #expect(await h.lands())
        await pull.value
    }

    @Test func aDeliveryWhileTheUserLooksShowsTheNightBeingScored() async {
        let h = Harness()
        let run = Task { await h.pipeline.run(.healthKit) }
        #expect(await h.waitsOnTheClock())
        h.lists()
        #expect(h.scoresTheNight, "\(h.vm.hero)")
        #expect(h.state.repository.widgetFacts.scoringState == .pending)
        h.scores()
        await h.nextPoll(after: 20)
        #expect(await h.lands())
        _ = await run.value
    }

    @Test func aBackgroundDeliveryThenOpeningTheAppShowsTheNightBeingScoredAndItLands() async {
        let h = Harness(inBackground: true)
        let outcome = await h.pipeline.run(.healthKit)
        #expect(outcome.touched == [h.today] && h.statusReads == 0) // no status read in the background
        h.lists()
        #expect(h.scoresTheNight, "after the background upload: \(h.vm.hero)")
        #expect(h.state.repository.widgetFacts.scoringState == .pending) // the widget says the same
        await backgroundThenForeground(h)
    }

    @Test func aBackgroundRefreshTaskThenOpeningTheAppShowsTheNightBeingScoredAndItLands() async {
        let h = Harness(inBackground: true)
        let outcome = await h.pipeline.run(.background)
        #expect(outcome.touched == [h.today] && h.statusReads == 0)
        h.lists()
        #expect(h.scoresTheNight, "after BGAppRefresh: \(h.vm.hero)")
        await backgroundThenForeground(h)
    }

    /// An hour later the user opens the app; nothing new to upload. The platform still lists today.
    private func backgroundThenForeground(_ h: Harness) async {
        h.clock.advance(by: .seconds(3_600))
        await h.pipeline.enterForeground()
        let run = Task { await h.pipeline.run(.appActive) }
        #expect(await h.waitsOnTheClock())
        #expect(h.scoresTheNight, "after opening: \(h.vm.hero)")
        h.scores()
        await h.nextPoll(after: 20) // the estimate of the status this run just read
        #expect(await h.lands())
        _ = await run.value
    }

    @Test func theFirstMorningSaysScoringRightAfterTheUploadNotWaitingForSleep() async {
        let h = Harness()
        await h.pipeline.refreshStatus() // the launch check: no night on the platform yet
        #expect(h.state.syncStatus?.today.state == .waitingForSleep)
        let run = Task { await h.pipeline.run(.appActive) }
        #expect(await h.waitsOnTheClock())
        // Right after the upload the platform may still answer from its 10 s cache: no night there yet.
        await h.pipeline.refreshStatus()
        #expect(h.state.syncStatus?.today.state == .waitingForSleep)
        #expect(h.scoresTheNight, "\(h.vm.hero)")
        h.lists()
        await h.nextPoll(after: 20)
        h.scores()
        await h.nextPoll(after: 40)
        #expect(await h.lands())
        _ = await run.value
    }

    @Test func theImportCardHandsOverToThePendingGaugeAfterTheFirstScore() async {
        let h = Harness(firstSync: true)
        let run = Task { await h.pipeline.run(.appActive) }
        #expect(await h.waitsOnTheClock())
        guard case .importing = h.vm.hero else { Issue.record("expected the import card: \(h.vm.hero)"); return }
        // Yesterday is scored, today still pending, the backfill not done: the gauge takes over, scoring the night.
        h.days.put(DailyScore(day: h.yesterday, readiness: 76, state: .balanced, recovery: 75, baselineDays: 30,
                              calibrating: false, computedAt: h.clock.now(), scoringState: .scored))
        h.lists([h.today])
        await h.nextPoll(after: 20)
        // The backfill that follows goes up slowly: the import isn't over while the gauge takes over.
        h.health.pages = [.quantity(.heartRate): [Harness.night()]]
        h.api.beforeSync = { [clock = h.clock] in try? await clock.sleep(for: .seconds(86_400)) }
        #expect(await h.waitsOnTheClock())
        h.clock.advance(by: SyncCoordinator.maximumScoringWait) // the cut-off: the days are refreshed anyway
        #expect(await eventually { h.vm.facts.hasScoredDay })
        #expect(!h.sync.engineState.backfillDone)
        #expect(h.scoresTheNight, "\(h.vm.hero)")
        await h.pipeline.cancel()
        _ = await run.value
    }

    @Test func aSilentPushThatEndsTheWaitLandsACalibratingDayOnTheBaselines() async {
        let h = Harness()
        let run = Task { await h.pipeline.run(.healthKit) }
        #expect(await h.waitsOnTheClock())
        h.lists()
        await h.nextPoll(after: 20) // pending
        #expect(h.scoresTheNight)
        // The first week: scored, calibrating, no readiness. The push ends the wait before the next ask.
        h.scores(readiness: nil, calibrating: true)
        await h.pipeline.run(.silentPush(days: [h.today]))
        _ = await run.value
        #expect(await eventually { h.vm.hero == .calibrating(nights: 2) }, "\(h.vm.hero)")
        #expect(h.state.repository.widgetFacts.scoringState == .scored)
    }

    @Test func aSilentPushWhileNobodyWaitsClearsTodayFromPending() async {
        let h = Harness()
        let run = Task { await h.pipeline.run(.healthKit) }
        #expect(await h.waitsOnTheClock())
        h.lists()
        await h.nextPoll(after: 20)
        #expect(await h.waitsOnTheClock())
        h.clock.advance(by: SyncCoordinator.maximumScoringWait) // the cut-off: still pending
        _ = await run.value
        #expect(h.scoresTheNight)
        h.scores(readiness: nil, calibrating: true)
        await h.pipeline.run(.silentPush(days: [h.today]))
        #expect(await eventually { h.vm.hero == .calibrating(nights: 2) }, "\(h.vm.hero)")
        #expect(h.state.repository.widgetFacts.scoringState == .scored)
    }

    @Test func aDaysChangedRunShowsTheDayBeingScoredUntilItLands() async {
        let h = Harness(night: false)
        h.lists() // the training import was accepted
        let run = Task { await h.pipeline.run(.daysChanged(days: [h.today])) }
        #expect(await h.waitsOnTheClock(phase: false))
        #expect(h.scoresTheNight, "\(h.vm.hero)")
        h.scores()
        await h.nextPoll(after: 30, phase: false)
        #expect(await h.lands())
        _ = await run.value
    }

    @Test func aRelaunchWithTodayStillPendingPollsUntilItLands() async {
        let h = Harness(night: false)
        h.lists()
        await h.pipeline.refreshStatus() // the launch check sees today pending: the first sighting
        let sighted = h.clock.now()
        #expect(h.sync.scoringWaitStart == sighted && h.scoresTheNight)
        h.clock.advance(by: .seconds(5))
        let run = Task { await h.pipeline.run(.appActive) } // nothing new to upload
        #expect(await h.waitsOnTheClock())
        #expect(h.statusReads == 1) // the launch check's answer is 5 s old: the platform would answer from its cache
        #expect(h.sync.scoringWaitStart == sighted) // "Taking longer than usual" keeps its clock
        h.scores() // no push comes
        await h.nextPoll(after: 20)
        #expect(await h.lands())
        _ = await run.value
    }

    /// Review F1: a platform that says it scores within 3 s. Its first ask then could be answered from the status
    /// cache, from before the night went up; the wait asks no sooner than the cache allows.
    @Test func aFastScorerLandsACalibratingDayWithoutAPush() async {
        let h = Harness(expected: 3)
        let run = Task { await h.pipeline.run(.healthKit) }
        #expect(await h.waitsOnTheClock())
        let asked = h.statusReads
        h.scores(readiness: nil, calibrating: true) // scored within the 3 s
        h.clock.advance(by: .seconds(3))
        #expect(await h.waitsOnTheClock()) // still the first wait: no ask yet (an ask would be sent within 0.2 s)
        #expect(!(await eventually(timeout: .milliseconds(200)) { h.statusReads > asked }))
        h.clock.advance(by: .seconds(7))
        #expect(await eventually { h.statusReads == asked + 1 && h.sync.statusReadAt == h.clock.now() })
        _ = await run.value
        #expect(await eventually { h.vm.hero == .calibrating(nights: 2) }, "\(h.vm.hero)")
        #expect(h.sync.scoringLedger.isEmpty && h.state.repository.widgetFacts.scoringState == .scored)
        #expect(h.statusReads == asked + 1) // one ask, at 10 s
    }

    /// Review R1: a poll that joins a flight asked under the cache time after the write (a pull on a slow network)
    /// gets an answer that may be from before the write. The ledger keeps the word, so the wait goes on until a read
    /// asked late enough answers it.
    @Test func aPollThatJoinsAnEarlierFlightKeepsWaitingUntilALateReadAnswers() async {
        let h = Harness(expected: 3)
        let run = Task { await h.pipeline.run(.healthKit) }
        #expect(await h.waitsOnTheClock())
        let reads = h.statusReads
        h.clock.advance(by: .seconds(2))
        // A pull 2 s after the write, on a slow network; the platform answers from its cache, from before the write.
        let cached = SyncStatus(gate: nil, lastSyncAt: nil, lastSyncDevice: nil, latest: [:],
                                today: TodayState(day: h.today, state: .waitingForSleep, scoredAt: nil,
                                                  modelVersion: "2026.10.1"),
                                pendingDays: [], expectedWithinSec: 20, resyncRequestedAt: nil)
        let clock = h.clock
        let pull = Task {
            try await h.state.env.reads.run(ReadKey(.syncStatus)) { () async throws -> SyncStatus in
                try await clock.sleep(for: .seconds(15))
                return cached
            }
        }
        #expect(await eventually { h.clock.pendingSleeps == 2 })
        h.clock.advance(by: .seconds(8)) // the wait's first ask, 10 s after the write: it joins the pull
        // Joined (not merely asked), and the next wait is on the clock.
        #expect(await eventually {
            h.state.env.reads.joiners(for: ReadKey(.syncStatus)) == 1 && h.clock.pendingSleeps == 2
        })
        h.clock.advance(by: .seconds(7)) // the pull lands, 17 s after the write
        _ = try? await pull.value
        #expect(h.statusReads == reads) // the ask joined the pull: no read of its own
        #expect(!(await eventually(timeout: .milliseconds(200)) { h.sync.phase != .awaitingScores }),
                "the wait ended on an answer asked 2 s after the write")
        #expect(h.sync.scoringLedger[h.today]?.kind == .pending && h.scoresTheNight, "\(h.vm.hero)")
        // The next ask, 30 s after the write, is a read of its own: the platform's word.
        h.scores()
        await h.nextPoll(after: 13)
        #expect(await h.lands())
        _ = await run.value
        #expect(h.sync.scoringLedger.isEmpty && h.statusReads == reads + 1)
    }

    /// Review F2: a daytime sync's push for a day the platform scored without a night. "Scored" rules out
    /// "being scored", not "waiting for last night's sleep".
    @Test func aPushOnANightlessDayLeavesItWaitingForSleep() async {
        let h = Harness(night: false)
        h.days.put(DailyScore(day: h.today, readiness: nil, state: nil, recovery: nil, baselineDays: 30, calibrating: false,
                              computedAt: h.clock.now(), scoringState: .waitingForSleep))
        await h.pipeline.refreshStatus()
        h.clock.advance(by: .seconds(30))
        _ = await h.pipeline.run(.appActive)
        let before = h.vm.hero
        guard case .pending(let night) = before, night.waitingForSleep else {
            Issue.record("expected waiting for sleep: \(before)")
            return
        }
        await h.pipeline.run(.silentPush(days: [h.today]))
        #expect(h.sync.scoringLedger[h.today]?.kind == .scored)
        #expect(h.vm.hero == before, "\(h.vm.hero)")
        #expect(h.state.repository.widgetFacts.scoringState == .waitingForSleep)
    }

    /// Review F3: the app opened under 10 s after a background upload. The platform's (cached) answer lists nothing
    /// yet; the phone's word is waited for all the same.
    @Test func openingTheAppRightAfterABackgroundUploadWaitsForItsWord() async {
        let h = Harness(inBackground: true)
        _ = await h.pipeline.run(.healthKit)
        #expect(h.sync.scoringLedger[h.today]?.kind == .pending)
        h.clock.advance(by: .seconds(5))
        await h.pipeline.enterForeground()
        let run = Task { await h.pipeline.run(.appActive) } // the status still says waiting for sleep
        #expect(await h.waitsOnTheClock())
        #expect(h.state.syncStatus?.pendingDays == [] && h.scoresTheNight, "\(h.vm.hero)")
        h.scores()
        await h.nextPoll(after: 20)
        #expect(await h.lands())
        _ = await run.value
    }
}

/// The record itself (`ScoringWord`, `SyncService.scoringLedger`): who answers it, and what it's read as.
@Suite("Scoring ledger")
@MainActor
struct ScoringLedgerTests {
    private let t0 = Harness.now
    private var today: String { DayFormat.string(from: t0) }

    private func status(_ state: ScoringState, pending: [String]) -> SyncStatus {
        SyncStatus(gate: nil, lastSyncAt: nil, lastSyncDevice: nil, latest: [:],
                   today: TodayState(day: today, state: state, scoredAt: nil, modelVersion: "2026.10.1"),
                   pendingDays: pending, expectedWithinSec: 20, resyncRequestedAt: nil)
    }

    @Test func theWordWinsUntilAStatusRequestedAfterTheCacheTimeAnswers() {
        let row = DailyScore(day: today, computedAt: nil, scoringState: .waitingForSleep)
        let waiting = TodayState(day: today, state: .waitingForSleep, scoredAt: nil, modelVersion: "2026.10.1")
        // No word: the status when it's about the day, else the row.
        #expect(ScoringWord.state(day: today, word: nil, status: waiting, row: nil) == .waitingForSleep)
        let yesterday = TodayState(day: "2026-10-18", state: .pending, scoredAt: nil, modelVersion: "2026.10.1")
        #expect(ScoringWord.state(day: today, word: nil, status: yesterday, row: row) == .waitingForSleep)
        #expect(ScoringWord.state(day: today, word: nil, status: nil, row: nil) == nil)
        // A word wins over both.
        let pending = ScoringWord(kind: .pending, at: t0), scored = ScoringWord(kind: .scored, at: t0)
        #expect(ScoringWord.state(day: today, word: pending, status: waiting, row: row) == .pending)
        #expect(ScoringWord.state(day: today, word: scored, status: status(.pending, pending: [today]).today, row: row) == .scored)
        // Answered only by a read asked for at least the cache's 10 s later.
        #expect(!pending.isAnswered(byStatusRequestedAt: t0.addingTimeInterval(9.9)))
        #expect(pending.isAnswered(byStatusRequestedAt: t0.addingTimeInterval(ScoringWord.statusCacheTime)))
        #expect(!pending.isAnswered(byStatusRequestedAt: t0.addingTimeInterval(-1)))
    }

    /// Review R3: a push over a cached `stale` (no new data for 20 h, then the night arrived) says scored. A push over
    /// `waiting_for_sleep` leaves it (F2), and a pending word still wins.
    @Test func aPushOverAStaleDayIsScored() {
        let stale = TodayState(day: today, state: .stale, scoredAt: nil, modelVersion: "2026.10.1")
        let waiting = TodayState(day: today, state: .waitingForSleep, scoredAt: nil, modelVersion: "2026.10.1")
        let pushed = ScoringWord(kind: .scored, at: t0), written = ScoringWord(kind: .pending, at: t0)
        #expect(ScoringWord.state(day: today, word: pushed, status: stale, row: nil) == .scored)
        let staleRow = DailyScore(day: today, computedAt: nil, scoringState: .stale)
        #expect(ScoringWord.state(day: today, word: pushed, status: nil, row: staleRow) == .scored)
        #expect(ScoringWord.state(day: today, word: nil, status: stale, row: nil) == .stale)
        #expect(ScoringWord.state(day: today, word: pushed, status: waiting, row: nil) == .waitingForSleep)
        #expect(ScoringWord.state(day: today, word: written, status: stale, row: nil) == .pending)
    }

    /// Review R4: a word for many days (a resync's) changes the ledger once, so the widget is republished once.
    @Test func aWordForManyDaysRepublishesTheWidgetOnce() {
        let sync = SyncService.ungated(env: AppEnvironment.test(clock: TestClock(now: t0)))
        var changes = 0
        sync.ledgerChanged = { changes += 1 }
        let days = (0..<90).map { DayFormat.string(from: DayFormat.shift(t0, days: -$0)) }
        sync.awaiting(days)
        #expect(changes == 1 && sync.scoringLedger.count == 90)
        sync.scored(Array(days.prefix(3)))
        #expect(changes == 2 && sync.scoringLedger.values.filter { $0.kind == .scored }.count == 3)
        sync.scored([])
        #expect(changes == 2) // nothing changed
    }

    /// Review R6 (N1): a word said after a sign-out (it raced the pipeline's cancel) is nobody's: dropped.
    @Test func aWordSaidAfterASignOutIsDropped() async {
        let env = AppEnvironment.test(clock: TestClock(now: t0))
        let sync = SyncService.ungated(env: env)
        let steps = LiveSyncSteps(state: AppState(env: env), sync: sync)
        steps.awaiting([today])
        #expect(sync.scoringLedger[today]?.kind == .pending)
        await env.auth.signOut()
        steps.awaiting(["2026-10-12"])
        #expect(sync.scoringLedger["2026-10-12"] == nil)
    }

    /// Review R6: an upload that ends after the account went keeps none of its days for whoever comes next
    /// (`touchedSoFar` is empty once the account is gone): cancelled by the account change, failed, or finished.
    @Test(arguments: UploadEnding.allCases)
    func anUploadThatEndsAfterTheAccountWentKeepsNoneOfItsDays(ending: UploadEnding) async {
        let clock = TestClock(now: t0)
        let stream = HealthStream.quantity(.heartRate)
        let health = MockHealthStore(streams: [stream])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: stream)
        health.pages = [stream: [Harness.night(), Harness.night(), Harness.night()]]
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 2, sleep: 0, workouts: 0, daysTouched: [today])
        // The second page is slow to answer.
        api.beforeSync = { [api, clock] in if api.count("sync") == 2 { try? await clock.sleep(for: .seconds(1)) } }
        let env = AppEnvironment.test(api: api, health: health, clock: clock)
        let sync = SyncService.ungated(env: env)
        let run = Task { try await sync.upload() }
        #expect(await eventually { clock.pendingSleeps == 1 && api.count("sync") == 2 }) // the first page accepted
        await env.auth.signOut()
        switch ending {
        case .cancelled: sync.accountChanged() // cancels the upload
        case .failed: api.failNext = APIError.http(422, "bad") // the third page
        case .finished: break // the second and third pages are accepted
        }
        clock.advance(by: .seconds(1))
        let touched = try? await run.value
        #expect(api.syncRequests.count >= 1)
        #expect((touched != nil) == (ending == .finished))
        #expect(sync.lastDaysTouched.isEmpty)
    }

    @Test func aStatusReadAnswersTheWordsItWasRequestedAfter() {
        let clock = TestClock(now: t0)
        let sync = SyncService.ungated(env: AppEnvironment.test(clock: clock))
        sync.awaiting([today, "2026-10-12"])
        #expect(sync.scoringLedger[today] == ScoringWord(kind: .pending, at: t0))
        sync.receive(status(.waitingForSleep, pending: []), requestedAt: t0.addingTimeInterval(5)) // may be cached
        #expect(sync.scoringLedger.count == 2)
        sync.receive(status(.waitingForSleep, pending: [])) // asked at an unknown time (the launch check)
        #expect(sync.scoringLedger.count == 2)
        clock.advance(by: .seconds(12))
        sync.awaiting(["2026-10-12"]) // written again later: its own word
        sync.receive(status(.pending, pending: [today]), requestedAt: t0.addingTimeInterval(10))
        #expect(sync.scoringLedger.keys.sorted() == ["2026-10-12"]) // today's is the platform's again, whatever it says
    }

    @Test func aStatusRequestedBeforeThePushCannotMakeTheDayPendingAgain() async {
        let clock = TestClock(now: t0)
        let api = MockPlatformAPI()
        api.scoringToday = TodayState(day: today, state: .pending, scoredAt: nil, modelVersion: "2026.10.1")
        api.pendingDays = [today]
        let env = AppEnvironment.test(api: api, clock: clock)
        let state = AppState(env: env)
        let sync = SyncService.ungated(env: env)
        let steps = LiveSyncSteps(state: state, sync: sync)
        // A status read in flight (slow network) when the push says today is scored; it lands after the push.
        let read = Task {
            try await env.reads.run(ReadKey(.syncStatus), storeAsked: { (status: SyncStatus, asked: Date) in
                state.syncStatus = status
                sync.receive(status, requestedAt: asked)
            }) {
                try await clock.sleep(for: .seconds(15))
                return try await api.syncStatus()
            }
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(5))
        steps.scored([today])
        clock.advance(by: .seconds(10))
        _ = try? await read.value
        #expect(state.syncStatus?.today.state == .pending) // the raw answer is kept as it came
        #expect(sync.scoringLedger[today]?.kind == .scored)
        #expect(state.repository.widgetFacts.scoringState == .scored)
        // A read asked for 10 s after the push is the platform's word again.
        _ = try? await steps.syncStatus()
        #expect(sync.scoringLedger[today] == nil && state.repository.scoringLedger().isEmpty)
        #expect(state.repository.widgetFacts.scoringState == .pending)
    }

    @Test func theStatusStoreLearnsWhenTheFlightWasAsked() async throws {
        let clock = TestClock(now: t0)
        let env = AppEnvironment.test(clock: clock)
        var asked: [Date] = []
        // The launch check starts the flight without a store; a poll joins it 5 s later with one.
        let first = Task {
            try await env.reads.run(ReadKey(.syncStatus)) { () async throws -> Int in
                try await clock.sleep(for: .seconds(15))
                return 1
            }
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(5))
        let joined = Task {
            try await env.reads.run(ReadKey(.syncStatus), storeAsked: { (_: Int, at: Date) in asked.append(at) }) { 2 }
        }
        await reachesTheFlight()
        clock.advance(by: .seconds(10))
        _ = try await first.value
        #expect(try await joined.value == 1)
        #expect(asked == [t0]) // the flight's start, not the joiner's
    }

    /// A task this (main-actor) test started has run up to its first real suspension: the main actor runs its jobs
    /// in the order they were enqueued, so one enqueued after it runs after.
    private func reachesTheFlight() async {
        await Task { @MainActor in }.value
    }

    /// Review F6, through the real step: a read that joins a flight started under 10 s after the word leaves the word,
    /// though it's asked, and lands, 10 s or more after it.
    @Test func aReadJoiningAnEarlierFlightLeavesTheWordsThatFlightCouldNotAnswer() async throws {
        let clock = TestClock(now: t0)
        let api = MockPlatformAPI()
        api.scoringToday = TodayState(day: today, state: .waitingForSleep, scoredAt: nil, modelVersion: "2026.10.1")
        let env = AppEnvironment.test(api: api, clock: clock)
        let state = AppState(env: env)
        let sync = SyncService.ungated(env: env)
        let steps = LiveSyncSteps(state: state, sync: sync)
        steps.awaiting([today])
        clock.advance(by: .seconds(5))
        // The launch check's read, 5 s after the word, on a slow network.
        let launch = Task {
            try await env.reads.run(ReadKey(.syncStatus)) { () async throws -> SyncStatus in
                try await clock.sleep(for: .seconds(15))
                return try await api.syncStatus()
            }
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(6)) // 11 s after the word: the wait's read joins it
        let joined = Task { try await steps.syncStatus() }
        await reachesTheFlight()
        clock.advance(by: .seconds(9)) // it lands 20 s after the word
        _ = try await launch.value
        #expect(try await joined.value.today.state == .waitingForSleep)
        #expect(api.count("syncStatus") == 1) // one flight: the read joined it
        #expect(sync.statusReadAt == clock.now())
        #expect(sync.scoringLedger[today]?.kind == .pending)
        #expect(state.repository.widgetFacts.scoringState == .pending)
        // Its own read, now: the platform's word again.
        _ = try await steps.syncStatus()
        #expect(sync.scoringLedger.isEmpty && state.repository.widgetFacts.scoringState == .waitingForSleep)
    }

    /// Review R2: `touchedSoFar` is the days of an upload `upload()` started. One it didn't start (signed out, demo
    /// data, no platform) reports none, not the last real upload's.
    @Test func anUploadThatDidNotStartReportsNoDaysTouched() async throws {
        let clock = TestClock(now: t0)
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 2, sleep: 0, workouts: 0, daysTouched: [today])
        let stream = HealthStream.quantity(.heartRate)
        let health = MockHealthStore(streams: [stream])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: stream)
        health.pages = [stream: [Harness.night()]]
        let env = AppEnvironment.test(api: api, health: health, clock: clock)
        let steps = LiveSyncSteps(state: AppState(env: env), sync: SyncService.ungated(env: env))
        #expect(try await steps.upload() == [today])
        #expect(steps.touchedSoFar == [today])
        await env.auth.signOut()
        #expect(try await steps.upload().isEmpty)
        #expect(steps.touchedSoFar.isEmpty)
    }

    @Test func theLedgerIsEmptyAfterAnAccountChangeAndTheWidgetSaysSo() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let env = AppEnvironment.test(clock: TestClock(now: t0))
        let state = AppState(env: env)
        state.repository.widgetFile = file
        state.repository.reloadWidget = {}
        state.syncStatus = status(.waitingForSleep, pending: [])
        let sync = SyncService.ungated(env: env)
        let steps = LiveSyncSteps(state: state, sync: sync)
        state.repository.publishWidget()
        #expect(widgetKind(file) == .waitingForSleep)
        steps.awaiting([today])
        #expect(state.repository.widgetFacts.scoringState == .pending)
        #expect(widgetKind(file) == .pending) // republished with the word
        let generation = steps.ledgerGeneration
        sync.accountChanged()
        #expect(steps.ledgerGeneration != generation) // the days a wait gave up on go too (R5)
        #expect(sync.scoringLedger.isEmpty && state.repository.scoringLedger().isEmpty)
        #expect(state.repository.widgetFacts.scoringState == .waitingForSleep)
        #expect(widgetKind(file) == .waitingForSleep)
    }

    /// What the widget's file shows.
    private func widgetKind(_ file: URL) -> ReadinessSnapshot.Kind? {
        (try? Data(contentsOf: file)).flatMap { try? ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: $0) }?.kind
    }

    @Test func switchingDemoDataOnOrOffForgetsTheWords() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let env = AppEnvironment.test(clock: TestClock(now: t0))
        let state = AppState(env: env)
        state.repository.widgetFile = file
        state.repository.reloadWidget = {}
        state.syncStatus = status(.waitingForSleep, pending: [])
        let sync = SyncService.ungated(env: env)
        let steps = LiveSyncSteps(state: state, sync: sync)
        let profile = ProfileViewModel(state: state, sync: sync, coordinator: SyncCoordinator(steps: steps, clock: env.clock))
        for on in [true, false] {
            steps.awaiting([today])
            #expect(state.repository.widgetFacts.scoringState == .pending)
            #expect(widgetKind(file) == .pending)
            let generation = steps.ledgerGeneration
            profile.demoModeChanged(on)
            #expect(steps.ledgerGeneration != generation, "demo \(on)") // the days a wait gave up on go too (R5)
            #expect(sync.scoringLedger.isEmpty, "demo \(on)")
            #expect(state.repository.widgetFacts.scoringState == .waitingForSleep, "demo \(on)")
            #expect(widgetKind(file) == .waitingForSleep, "demo \(on)") // republished
        }
    }
}

/// The wait's start when the platform already listed the days (no write of this phone's), and who may ask.
@Suite("Scoring ledger: the wait for listed days")
@MainActor
struct ListedDaysWaitTests {
    private let t0 = Harness.now

    private func pending() -> SyncStatus {
        let day = DayFormat.string(from: t0)
        return SyncStatus(gate: nil, lastSyncAt: nil, lastSyncDevice: nil, latest: [:],
                          today: TodayState(day: day, state: .pending, scoredAt: nil, modelVersion: "2026.10.1"),
                          pendingDays: [day], expectedWithinSec: 20, resyncRequestedAt: nil)
    }

    @Test func aWaitForListedDaysKeepsTheFirstSightingAndEndsLikeAnyOther() {
        let clock = TestClock(now: t0)
        let sync = SyncService.ungated(env: AppEnvironment.test(clock: clock))
        sync.receive(pending()) // first sighting
        clock.advance(by: .seconds(400)) // the user comes back later; nothing new to send
        sync.advance(to: .reading)
        sync.advance(to: .awaitingScores)
        #expect(sync.scoringWaitStart == t0)
        // Scored 30 s into this wait: the wait wasn't cut off, so its start goes, however old.
        clock.advance(by: .seconds(30))
        sync.advance(to: .refreshing)
        #expect(sync.scoringWaitStart == nil)
        // A write starts the next wait's clock anew, even after a sighting.
        sync.advance(to: .done)
        sync.receive(pending())
        clock.advance(by: .seconds(5))
        sync.advance(to: .reading)
        sync.awaiting([DayFormat.string(from: t0)])
        sync.advance(to: .awaitingScores)
        #expect(sync.scoringWaitStart == clock.now())
    }

    @Test func onlyAnAccountThatCanReadTheStatusAsks() async {
        let env = AppEnvironment.test(clock: TestClock(now: t0))
        let steps = LiveSyncSteps(state: AppState(env: env), sync: SyncService.ungated(env: env))
        #expect(steps.readsScoringStatus)
        await env.auth.signOut()
        #expect(!steps.readsScoringStatus)
    }
}
