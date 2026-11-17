import Foundation
import os
import SwiftData
import Testing
@testable import Ryft

// The read models' writer and its queue (ADR 0018): off the main thread, in submit order, one save per batch, never
// across a store or an epoch, and nothing of a wiped account written after its wipe. Synthetic values only.

/// Holds the writer in a hook, on the writer's thread, until `open()`. The main thread never waits on it: tests poll
/// `entered`.
final class WriterHold: Sendable {
    private struct State {
        var entered = 0
        var open = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let gate = DispatchSemaphore(value: 0)

    /// Hook calls so far.
    var entered: Int { state.withLock { $0.entered } }

    /// The hook: waits for `open()` (10 s at most, so a failing test still ends) unless it's open already.
    func pass() {
        let wait = state.withLock { s -> Bool in
            s.entered += 1
            return !s.open
        }
        if wait { _ = gate.wait(timeout: .now() + 10) }
    }

    func open() {
        let first = state.withLock { s -> Bool in
            defer { s.open = true }
            return !s.open
        }
        if first { gate.signal() }
    }
}

/// What the writer's hooks saw, from any thread.
final class Recorded<T: Sendable>: Sendable {
    private let values = OSAllocatedUnfairLock<[T]>(initialState: [])
    func append(_ value: T) { values.withLock { $0.append(value) } }
    var all: [T] { values.withLock { $0 } }
    var count: Int { all.count }
}

/// A Repository whose first write is held in the writer: its `settled()` returns once the test opens `hold`.
@MainActor
func repositoryWithAHeldWrite() async -> (repository: Repository, hold: WriterHold) {
    let repository = Repository(env: .test())
    let hold = WriterHold()
    repository.writeHooks.job = { _ in hold.pass() }
    repository.store(detail: DayDetail(score: DailyScore(day: "2026-10-19", strain: 7), sleep: nil, workouts: []))
    _ = await eventually { hold.entered == 1 }
    return (repository, hold)
}

private func detail(_ day: String, strain: Double) -> DayDetail {
    DayDetail(score: DailyScore(day: day, strain: strain), sleep: nil, workouts: [])
}

/// The rows a fresh context finds (what the store holds, not a memo or a context's registered objects).
@MainActor
private func cachedDays(in store: any Persistence) throws -> [CachedDay] {
    try ModelContext(store.container).fetch(FetchDescriptor<CachedDay>()).sorted { $0.day < $1.day }
}

@Suite("Read-model writes: off the main thread")
@MainActor
struct ReadModelOffMainTests {
    /// The proof the design rests on (T0.1, decision 8): a write submitted from the main actor, through the Repository,
    /// gets a writer made off the main thread and runs its SwiftData job off it, and the main actor only awaits a
    /// continuation. Both halves, because the OS decides by the maker on iOS 17.0 and by the awaiter on 27.2.
    @Test func aWriteSubmittedFromTheMainActorRunsOffIt() async {
        let repo = Repository(env: .test())
        let made = Recorded<Bool>(), jobs = Recorded<Bool>()
        repo.writeHooks = .init(job: { jobs.append($0) }, writerMade: { made.append($0) })
        #expect(MainThread.isCurrent)

        let receipt = await repo.store(detail: detail(DayFormat.string(from: .now), strain: 7)).committed()

        #expect(receipt.saved && !receipt.dropped)
        #expect(made.all == [false])
        #expect(jobs.all == [false])
    }

    /// The paths the app writes through: a refresh's flight store, `AppState.patchUser`, the trends stage; and the
    /// writer a sign-out's wipe replaces.
    @Test func everyWriterOfTheAppWritesOffTheMainThread() async throws {
        let clock = TestClock(now: ReadModelReaderTests.morning)
        let env = AppEnvironment.test(api: MockPlatformAPI(screens: HeldDayAnswers(detail: [12], list: 4)), clock: clock)
        let state = AppState(env: env)
        let made = Recorded<Bool>(), jobs = Recorded<Bool>()
        state.repository.writeHooks = .init(job: { jobs.append($0) }, writerMade: { made.append($0) })

        try await state.repository.refreshDay(clock.now())
        try await state.repository.refreshHistory(from: DayFormat.shift(clock.now(), days: -4), to: clock.now())
        try await state.patchUser(UserPatch(birthYear: 1990))
        await state.repository.markTrendsStale().committed()
        env.persistence.wipe() // the store's wipe, as a sign-out runs it
        await state.repository.store(scores: [DailyScore(day: DayFormat.string(from: clock.now()), strain: 3)]).committed()

        #expect(jobs.count >= 5)
        #expect(jobs.all.allSatisfy { !$0 })
        #expect(made.all == [false, false]) // the first writer, and the one after the wipe
    }
}

@Suite("Read-model writes: the queue")
@MainActor
struct ReadModelQueueTests {
    /// Everything submitted while a job runs is the next batch: one save, one revision bump per kind.
    @Test func answersQueuedBehindAJobSaveOnceAndBumpEachKindOnce() async {
        let repo = Repository(env: .test())
        let hold = WriterHold(), saves = Recorded<Bool>()
        repo.writeHooks = .init(job: { _ in hold.pass() }, saved: { saves.append(true) })
        let today = DayFormat.string(from: .now)
        let held = repo.store(detail: detail(today, strain: 5))
        #expect(await eventually { hold.entered == 1 })
        let revisions = (days: repo.daysRevision, trends: repo.trendsRevision, insights: repo.insightsRevision,
                         sleep: repo.sleepRevision)

        for back in 1...3 {
            repo.store(scores: [DailyScore(day: DayFormat.string(from: DayFormat.shift(.now, days: -back)), strain: 3)])
        }
        repo.store(trend: MockData.trend(.hrv, range: .week), metric: .hrv, range: .week)
        repo.store(insights: MockData.insights)
        let last = repo.store(insights: MockData.insights)
        hold.open()
        #expect(await held.committed().saved)
        #expect(await last.committed().saved)

        #expect(hold.entered == 2) // two jobs
        #expect(saves.count == 2) // two saves
        #expect(repo.daysRevision == revisions.days + 2) // the held batch's, then the queued batch's
        #expect(repo.trendsRevision == revisions.trends + 1)
        #expect(repo.insightsRevision == revisions.insights + 1)
        #expect(repo.sleepRevision == revisions.sleep)
        #expect(repo.history(from: DayFormat.shift(.now, days: -3), to: .now).count == 4)
        // The second list replaced the first, unsaved, in the same context: one set of cards.
        #expect(repo.insights().map(\.id) == MockData.insights.map(\.id))
    }

    /// A clear (the demo switch) behind writes of the same batch: their unsaved rows go too, none is saved after it.
    @Test func aClearRemovesWhatItsBatchInsertedBeforeIt() async throws {
        let h = WipeHarness()
        let hold = WriterHold()
        h.repository.writeHooks.job = { _ in hold.pass() }
        h.repository.store(detail: detail(DayFormat.string(from: DayFormat.shift(h.clock.now(), days: -9)), strain: 1))
        #expect(await eventually { hold.entered == 1 })

        h.repository.store(detail: detail(h.today, strain: 12))
        h.repository.store(insights: MockData.insights)
        h.repository.store(user: MockData.user)
        h.repository.store(trend: MockData.trend(.hrv, range: .week), metric: .hrv, range: .week)
        h.repository.store(sleepRange: MockData.sleepRange(.week))
        h.repository.store(workout: MockData.workoutDetail(MockData.todayDetail.workouts[0]))
        h.repository.store(activities: [], day: h.today)
        let cleared = h.repository.clear()
        hold.open()

        #expect(await cleared.committed().saved)
        #expect(hold.entered == 2)
        #expect(try h.rowCount() == 0)
    }

    /// One batch, one context: the later write for a day finds the row the earlier one inserted, unsaved.
    @Test func twoWritesForOneDayInOneBatchTheLaterWins() async throws {
        let env = AppEnvironment.test()
        let repo = Repository(env: env)
        let hold = WriterHold()
        repo.writeHooks.job = { _ in hold.pass() }
        let key = DayFormat.string(from: env.clock.now())
        repo.store(detail: detail(DayFormat.string(from: DayFormat.shift(env.clock.now(), days: -9)), strain: 1))
        #expect(await eventually { hold.entered == 1 })

        repo.store(detail: detail(key, strain: 4))
        repo.store(detail: detail(key, strain: 12))
        repo.store(scores: [DailyScore(day: key, strain: 3)]) // a list score never replaces the detail's
        let last = repo.store(detail: detail(key, strain: 14))
        hold.open()
        await last.committed()

        #expect(hold.entered == 2)
        #expect(try cachedDays(in: env.persistence).filter { $0.day == key }.count == 1)
        #expect(repo.day(key)?.score.strain == 14 && repo.score(key)?.strain == 14)
    }

    /// Submit order, whatever the submitters' priorities (an actor runs its jobs by priority, not first in, first out).
    @Test func writesLandInSubmitOrderWhateverTheirPriority() async {
        let env = AppEnvironment.test()
        let repo = Repository(env: env)
        let hold = WriterHold()
        repo.writeHooks.job = { _ in hold.pass() }
        let key = DayFormat.string(from: env.clock.now())
        repo.store(detail: detail(key, strain: 1))
        #expect(await eventually { hold.entered == 1 })

        let low = Task(priority: .background) { @MainActor in repo.store(detail: detail(key, strain: 2)) }
        let lowTicket = await low.value
        let high = Task(priority: .userInitiated) { @MainActor in repo.store(detail: detail(key, strain: 3)) }
        let highTicket = await high.value
        hold.open()
        await lowTicket.committed()
        await highTicket.committed()

        #expect(repo.day(key)?.score.strain == 3)
    }

    /// A batch is one store's: the demo store and the account's never share a save.
    @Test func aBatchNeverSpansTwoStores() async throws {
        let env = AppEnvironment.preview() // demo on
        let repo = Repository(env: env)
        let hold = WriterHold(), writers = Recorded<Bool>()
        repo.writeHooks = .init(job: { _ in hold.pass() }, writerMade: { _ in writers.append(true) })
        let a = "2026-11-01", b = "2026-11-02", c = "2026-11-03"
        repo.store(detail: detail("2026-10-01", strain: 1))
        #expect(await eventually { hold.entered == 1 })

        repo.store(detail: detail(a, strain: 2))
        var toAccount: WriteTicket?
        repo.writingToAccountStore { toAccount = repo.store(detail: detail(b, strain: 3)) }
        let last = repo.store(detail: detail(c, strain: 4))
        hold.open()
        let account = await toAccount?.committed()
        await last.committed()

        #expect(account?.saved == true)
        #expect(hold.entered == 4) // the held job, then demo, account, demo
        #expect(writers.count == 2) // one writer per store
        #expect(try cachedDays(in: env.persistence).map(\.day) == [b])
        #expect(repo.day(a) != nil && repo.day(c) != nil && repo.day(b) == nil)
    }

    /// `seed` writes on a context of its own: never while the writer may hold the same rows.
    @Test func aSeedWhileWritesArePendingIsAMisuse() async {
        let repo = Repository(env: .test())
        var misuses: [String] = []
        repo.onMisuse = { misuses.append($0) }
        let hold = WriterHold(), writers = Recorded<Bool>()
        repo.writeHooks = .init(job: { _ in hold.pass() }, writerMade: { _ in writers.append(true) })
        let key = DayFormat.string(from: .now)
        let held = repo.store(detail: detail(key, strain: 4))
        #expect(await eventually { hold.entered == 1 })

        repo.seed(.detail(detail(key, strain: 5)))
        #expect(misuses.count == 1)

        hold.open()
        await held.committed()
        // Idle once the last ticket is resolved: no misuse, and the next write gets a new writer.
        repo.seed(.detail(detail(key, strain: 6)))
        #expect(misuses.count == 1)
        #expect(repo.day(key)?.score.strain == 6)
        await repo.store(scores: [DailyScore(day: key, strain: 2)]).committed()
        #expect(writers.count == 2)
        #expect(repo.day(key)?.score.strain == 6)
    }

    @Test func settledReturnsOnceEveryWriteSubmittedIsReadable() async {
        let repo = Repository(env: .test())
        await repo.settled() // nothing submitted
        let hold = WriterHold()
        repo.writeHooks.job = { _ in hold.pass() }
        let key = DayFormat.string(from: .now)
        repo.store(detail: detail(key, strain: 4))
        #expect(await eventually { hold.entered == 1 })
        repo.store(insights: MockData.insights)
        let settled = Task { await repo.settled() }
        hold.open()
        await settled.value
        #expect(repo.day(key) != nil && !repo.insights().isEmpty)
    }

    /// Durable: a write that committed is in the file the next launch opens.
    @Test func aCommittedWriteSurvivesARelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ryft-reads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Train.store")
        let h = WipeHarness(persistence: TrainStore(url: url))
        let key = h.today

        #expect(await h.repository.store(detail: detail(key, strain: 9)).committed().saved)

        let reopened = TrainStore(url: url)
        let rows = try ModelContext(reopened.container).fetch(FetchDescriptor<CachedDay>())
        withExtendedLifetime(reopened) {
            #expect(rows.map(\.day) == [key])
            #expect(rows.first?.detailData != nil)
        }
    }
}

@Suite("Read-model writes: the wipe and the writer")
@MainActor
struct ReadModelWipeRaceTests {
    /// Queued (one held, one behind it) when the account signs out: neither writes a row.
    @Test func writesQueuedBeforeTheSignOutLeaveNoRow() async throws {
        let h = WipeHarness()
        let hold = WriterHold()
        h.repository.writeHooks.job = { _ in hold.pass() }
        let held = h.repository.store(detail: detail(h.today, strain: 12))
        #expect(await eventually { hold.entered == 1 })
        let queued = h.repository.store(scores: [DailyScore(day: DayFormat.string(from: DayFormat.shift(h.clock.now(), days: -1)),
                                                            strain: 4)])
        let user = h.repository.store(user: MockData.user)

        await h.auth.signOut()
        hold.open()

        #expect(await held.committed().dropped)
        #expect(await queued.committed().dropped)
        #expect(await user.committed().dropped)
        #expect(hold.entered == 1) // the batch behind it never reached the writer
        #expect(try h.rowCount() == 0)
        #expect(h.repository.day(h.today) == nil && h.repository.user() == nil)
    }

    /// A save in progress when the wipe starts: the wipe waits for it (one critical section with the epoch), then
    /// deletes what it saved. Without the lock the wipe would delete first and the save write the row after it.
    @Test func aSaveInProgressIsDeletedByTheWipeThatWaitsForIt() async throws {
        let h = WipeHarness()
        let hold = WriterHold(), saves = Recorded<Bool>()
        h.repository.writeHooks = .init(insideSave: { hold.pass() }, saved: { saves.append(true) })
        let written = h.repository.store(detail: detail(h.today, strain: 12))
        #expect(await eventually { hold.entered == 1 })

        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(150)) { hold.open() }
        h.persistence.wipe(parkingActivitiesOf: nil, at: h.clock.now()) // the sign-out's wipe, synchronous
        h.repository.invalidate()

        #expect(saves.count == 1) // the wipe returned after the save it waited for
        let receipt = await written.committed()
        #expect(receipt.saved && !receipt.dropped)
        #expect(try h.rowCount() == 0)
        #expect(h.repository.day(h.today) == nil)
    }

    /// The first write after a wipe gets a new writer: no context keeps a row the wipe deleted.
    @Test func aWriteAfterTheWipeGoesToANewWriter() async throws {
        let h = WipeHarness()
        let writers = Recorded<Bool>()
        h.repository.writeHooks.writerMade = { _ in writers.append(true) }
        await h.repository.store(detail: detail(h.today, strain: 12)).committed()
        await h.repository.store(user: MockData.user).committed()
        #expect(writers.count == 1)

        await h.auth.signOut()
        await h.signIn(WipeHarness.b)
        let after = await h.repository.store(scores: [DailyScore(day: h.today, strain: 3)]).committed()

        #expect(after.saved && writers.count == 2)
        let rows = try cachedDays(in: h.persistence)
        #expect(rows.count == 1 && rows.first?.detailData == nil)
        #expect(h.repository.day(h.today) == nil) // the first account's detail never comes back
        #expect(h.repository.score(h.today)?.strain == 3)
        #expect(h.repository.user() == nil)
    }

    /// 200 writes from ten main-actor tasks and a sign-out among them, five times. The sign-out starts once 30, 55, …
    /// are in, and each writer's last five wait for its wipe, so writes are pending on both sides of it. Exactly the
    /// days submitted after the wipe are in the store, none from before it.
    @Test(.timeLimit(.minutes(1)), arguments: 0..<5) // a lock held across an await would hang here
    func manyWritersAndASignOutLeaveOnlyWhatCameAfterIt(round: Int) async throws {
        let h = WipeHarness()
        let start = h.clock.now()
        let epoch = h.persistence.epoch.current
        let log = SubmitLog()
        // Main-actor tasks (this suite is `@MainActor`), interleaved at their awaits.
        var tasks = (0..<10).map { writer in
            Task {
                for i in 0..<20 {
                    while i >= 15, h.persistence.epoch.current == epoch { await Task.yield() }
                    let n = writer * 20 + i
                    let day = DayFormat.string(from: DayFormat.shift(start, days: -n))
                    let ticket = n % 3 == 0
                        ? h.repository.store(detail: detail(day, strain: Double(n % 21)))
                        : h.repository.store(scores: [DailyScore(day: day, strain: Double(n % 21))])
                    log.submitted.append((day, h.persistence.epoch.current != epoch))
                    log.tickets.append(ticket)
                    if (i + round) % 4 == 0 { await Task.yield() }
                }
            }
        }
        tasks.append(Task {
            while log.submitted.count < 30 + round * 25 { await Task.yield() }
            await h.auth.signOut()
        })
        for task in tasks { await task.value }
        for ticket in log.tickets { await ticket.committed() }

        let expected = Set(log.submitted.filter(\.afterWipe).map(\.day))
        #expect(h.persistence.epoch.current == epoch + 1)
        #expect(Set(try cachedDays(in: h.persistence).map(\.day)) == expected)
        #expect(log.submitted.count == 200)
        #expect(log.submitted.filter { !$0.afterWipe }.count >= 30 + round * 25)
        #expect(expected.count >= 50) // the sign-out landed among the writes, not after the last one
        for (day, afterWipe) in log.submitted where !afterWipe {
            #expect(h.repository.score(day) == nil)
        }
    }
}

/// The stress test's submissions, in main-actor order.
@MainActor
private final class SubmitLog {
    var submitted: [(day: String, afterWipe: Bool)] = []
    var tickets: [WriteTicket] = []
}
