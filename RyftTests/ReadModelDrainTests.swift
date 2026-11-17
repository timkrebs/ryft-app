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
func repositoryWithAHeldWrite(clock: TestClock = TestClock()) async -> (repository: Repository, hold: WriterHold) {
    let repository = Repository(env: .test(clock: clock))
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

/// The users a fresh context finds.
@MainActor
private func cachedUsers(in store: any Persistence) throws -> [User] {
    try ModelContext(store.container).fetch(FetchDescriptor<CachedUser>()).compactMap { WireCoding.decode(User.self, $0.data) }
}

/// A row's strain as `Repository.score` reads it: the detail's when opened, else the list's.
private func strain(of row: CachedDay) -> Double? {
    WireCoding.decode(DayDetail.self, row.detailData)?.score.strain ?? WireCoding.decode(DailyScore.self, row.scoreData)?.strain
}

/// `eventually` for a condition that awaits (the drain's state): polled, never a fixed sleep.
private func eventuallyAwaiting(timeout: Duration = .seconds(30), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return await condition()
}

/// A flag the writer's hooks read from their thread.
private final class Armed: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: false)
    var isOn: Bool { value.withLock { $0 } }
    func arm() { value.withLock { $0 = true } }
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

        #expect(hold.entered == 4) // the held job, then demo, account, demo
        #expect(writers.count == 2) // one writer per store
        #expect(repo.day(a) != nil && repo.day(c) != nil && repo.day(b) == nil)
        let accountDays = try cachedDays(in: env.persistence).map(\.day)
        withKnownIssue("T0.6: on iOS 17 the account's store is the older of two containers, and takes no inserts") {
            #expect(account?.saved == true)
            #expect(accountDays == [b])
        } when: {
            if #unavailable(iOS 18) { return true }
            return false
        }
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

    /// 200 writes from ten main-actor tasks and a sign-out among them, five times, without and with demo data on. The
    /// sign-out starts once 30, 55, … are in, and each writer's last five wait for its wipe, so writes are pending on
    /// both sides of it; the sign-out's own last write is held in the writer across the wipe, so at least one from
    /// before it is dropped, not only overwritten. Days repeat (60 for 200 writes) and every seventh write is the
    /// user's; with demo data on, every other one goes to the account's store, the rest to demo data's (which the
    /// sign-out's reset replaces). Each store ends with exactly what was submitted to it after its wipe or its
    /// replacement, the last of it per user, and no value from before.
    @Test(.timeLimit(.minutes(1)), arguments: 0..<5, [false, true]) // a lock held across an await would hang here
    func manyWritersAndASignOutLeaveOnlyWhatCameAfterIt(round: Int, demo: Bool) async throws {
        let h = WipeHarness(demo: demo)
        let start = h.clock.now()
        let epoch = h.persistence.epoch.current
        let account = h.persistence.epoch.store
        let log = SubmitLog()
        let armed = Armed(), held = WriterHold()
        h.repository.writeHooks.job = { _ in if armed.isOn { held.pass() } }
        func submit(_ n: Int, toAccount: Bool) {
            let day = DayFormat.string(from: DayFormat.shift(start, days: -(n % 60)))
            var ticket: WriteTicket?
            let write = {
                if n % 7 == 3 {
                    var user = MockData.user
                    user.birthYear = 1800 + n
                    ticket = h.repository.store(user: user)
                } else {
                    // Unique per write: a value from before the wipe can't pass for one after it.
                    let strain = Double(n)
                    ticket = n % 3 == 0
                        ? h.repository.store(detail: detail(day, strain: strain))
                        : h.repository.store(scores: [DailyScore(day: day, strain: strain)])
                }
            }
            if toAccount, demo { h.repository.writingToAccountStore(write) } else { write() }
            let store = toAccount ? account : h.repository.storeID
            log.submitted.append(.init(n: n, day: day, user: n % 7 == 3, store: store,
                                       afterWipe: h.persistence.epoch.current != epoch))
            if let ticket { log.tickets.append(ticket) }
        }
        // Main-actor tasks (this suite is `@MainActor`), interleaved at their awaits.
        var tasks = (0..<10).map { writer in
            Task {
                for i in 0..<20 {
                    while i >= 15, h.persistence.epoch.current == epoch { await Task.yield() }
                    let n = writer * 20 + i
                    submit(n, toAccount: !demo || n % 2 == 0)
                    if (i + round) % 4 == 0 { await Task.yield() }
                }
            }
        }
        tasks.append(Task {
            while log.submitted.count < 30 + round * 25 { await Task.yield() }
            // The next batch to reach the writer, this write's or one before it, waits there for the wipe.
            armed.arm()
            submit(200, toAccount: true)
            await h.auth.signOut()
            held.open()
        })
        for task in tasks { await task.value }
        var receipts: [WriteReceipt] = []
        for ticket in log.tickets { receipts.append(await ticket.committed()) }

        #expect(h.persistence.epoch.current == epoch + 1)
        #expect(log.submitted.count == 201)
        let before = log.submitted.filter { !$0.afterWipe }
        #expect(before.count >= 31 + round * 25)
        #expect(log.submitted.filter(\.afterWipe).count >= 50) // the sign-out landed among the writes
        let accountBefore = Set(log.submitted.enumerated().filter { $0.element.store == account && !$0.element.afterWipe }
            .map(\.offset))
        #expect(receipts.enumerated().contains { accountBefore.contains($0.offset) && $0.element.dropped })

        // The account's store: what came after the wipe.
        let accountAfter = log.submitted.filter { $0.store == account && $0.afterWipe }
        let rows = try cachedDays(in: h.persistence)
        #expect(Set(rows.map(\.day)) == Set(accountAfter.filter { !$0.user }.map(\.day)))
        for row in rows {
            let allowed = Set(accountAfter.filter { !$0.user && $0.day == row.day }.map { Double($0.n) })
            #expect(strain(of: row).map { allowed.contains($0) } == true, "\(row.day): \(String(describing: strain(of: row)))")
        }
        let lastAccountUser = accountAfter.last(where: \.user).map { 1800 + $0.n }
        #expect(try cachedUsers(in: h.persistence).map(\.birthYear) == [lastAccountUser].compactMap { $0 })

        // What reads see: the account's store, or with demo data on demo data's newest store.
        let read = demo ? h.repository.storeID : account
        let readable = log.submitted.filter { $0.store == read && ($0.store != account || $0.afterWipe) }
        for day in Set(log.submitted.filter { !$0.user }.map(\.day)) {
            let allowed = Set(readable.filter { !$0.user && $0.day == day }.map { Double($0.n) })
            if allowed.isEmpty {
                #expect(h.repository.score(day) == nil, "\(day)")
            } else {
                #expect(h.repository.score(day)?.strain.map { allowed.contains($0) } == true, "\(day)")
            }
        }
        #expect(h.repository.user()?.birthYear == readable.last(where: \.user).map { 1800 + $0.n })
    }
}

/// The stress test's submissions, in main-actor order.
@MainActor
private final class SubmitLog {
    struct Submitted {
        let n: Int
        let day: String
        let user: Bool
        let store: StoreID
        let afterWipe: Bool
    }

    var submitted: [Submitted] = []
    var tickets: [WriteTicket] = []
}

@Suite("Read-model writes: the epoch's locks, the drain's priority, the stores")
@MainActor
struct ReadModelLockAndPriorityTests {
    /// The main actor reads the epoch at every submit: a save in progress (held inside its critical section) holds up
    /// neither the read nor the submit. `current` takes a lock of its own, never the save gate.
    @Test func neitherTheEpochNorASubmitWaitsForASaveInProgress() async {
        let env = AppEnvironment.test()
        let repo = Repository(env: env)
        let hold = WriterHold()
        repo.writeHooks = .init(insideSave: { hold.pass() })
        let key = DayFormat.string(from: .now)
        let first = repo.store(detail: detail(key, strain: 1))
        #expect(await eventually { hold.entered == 1 })
        // Opens it anyway, so a reader that does wait (the bug) is measured, not hung.
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) { hold.open() }

        let start = ContinuousClock.now
        let epoch = env.persistence.epoch.current
        let ticket = repo.store(scores: [DailyScore(day: DayFormat.string(from: DayFormat.shift(.now, days: -1)), strain: 2)])
        let blocked = ContinuousClock.now - start
        hold.open()

        #expect(blocked < .milliseconds(100), "main waited \(blocked)")
        #expect(epoch == env.persistence.epoch.current)
        let saved = (await first.committed().saved, await ticket.committed().saved)
        #expect(saved == (true, true))
    }

    /// The drain runs at `.userInitiated`, whoever submitted first: a background sync's first write doesn't hold the
    /// queue (a pull's write behind it included) at its own priority, and awaiting a ticket doesn't raise it.
    @Test func theDrainRunsAtUserInitiatedWhoeverSubmittedFirst() async {
        let repo = Repository(env: .test())
        let priorities = Recorded<TaskPriority>()
        repo.writeHooks.job = { _ in priorities.append(Task.currentPriority) }
        let key = DayFormat.string(from: .now)
        let ticket = await Task(priority: .utility) { @MainActor in repo.store(detail: detail(key, strain: 1)) }.value
        await ticket.committed()
        #expect(priorities.count == 1)
        #expect(priorities.all.allSatisfy { $0 >= .userInitiated }, "\(priorities.all)")
    }

    /// A seeded user is the newest, written through as `store(user:)` writes it: read back without a decode.
    @Test func aSeededUserIsWrittenThrough() {
        let repo = Repository(env: .test())
        var user = MockData.user
        user.birthYear = 1977
        repo.seed(.user(user))
        let decodes = repo.decodes
        #expect(repo.user()?.birthYear == 1977)
        #expect(repo.decodes == decodes)
    }

    /// The legacy import seeds the account's store while demo data is on: its user is the account's, never demo's.
    @Test func theAccountStoresSeedIsntDemoDatasUser() async {
        let repo = Repository(env: .preview()) // demo on
        repo.widgetFile = nil
        var demo = MockData.user
        demo.birthYear = 1980
        await repo.store(user: demo).committed()
        var account = MockData.user
        account.birthYear = 1990
        repo.writingToAccountStore { repo.seed(.user(account)) }
        #expect(repo.user()?.birthYear == 1980)
        var read: Int?
        repo.writingToAccountStore { read = repo.user()?.birthYear }
        #expect(read == 1990)
    }

    /// Writers, read contexts and seeds are keyed per store by an ID no other store gets (an object's address can
    /// come back as another's).
    @Test func everyStoreHasAnIDOfItsOwn() {
        let ids = (0..<100).map { _ in StoreEpoch().store }
        #expect(Set(ids).count == 100)
    }
}

@Suite("Read-model writes: the Demo data switch")
@MainActor
struct ReadModelDemoSwitchTests {
    private func demo() async -> (AppState, String) {
        let env = AppEnvironment.preview() // demo on
        let state = AppState(env: env)
        state.repository.widgetFile = nil
        await state.refresh()
        return (state, DayFormat.string(from: env.clock.now()))
    }

    /// `ProfileViewModel.setDemoMode` resets, then refreshes. The refresh mustn't find demo data's old rows fresh (and
    /// skip its reads) while a clear of them is still queued: Today fills again, every time (a queued clear lost every
    /// one of 20 runs).
    @Test func aRefreshAfterTheSwitchFillsTodayAgain() async {
        var empty = 0
        for _ in 0..<5 {
            let (state, key) = await demo()
            #expect(state.repository.day(key) != nil)
            state.reset()
            await state.refresh()
            await state.repository.settled()
            if state.repository.day(key) == nil { empty += 1 }
        }
        #expect(empty == 0)
    }

    /// The same with the refresh's writes held in the writer: they land in demo data's new store.
    @Test func aRefreshHeldInTheWriterAfterTheSwitchFillsToday() async {
        let (state, key) = await demo()
        let hold = WriterHold()
        state.repository.writeHooks.job = { _ in hold.pass() }
        state.reset()
        let refresh = Task { await state.refresh() }
        #expect(await eventually { hold.entered >= 1 })
        hold.open()
        await refresh.value
        await state.repository.settled()
        #expect(state.repository.day(key) != nil)
    }

    /// Nothing of demo data's old rows shows between the switch and the next refresh: its store is empty at once.
    @Test func demoDatasOldRowsAreGoneAtTheSwitch() async {
        let (state, key) = await demo()
        #expect(state.repository.day(key) != nil && !state.history.isEmpty)
        state.reset()
        #expect(state.repository.day(key) == nil)
        #expect(state.history.isEmpty)
    }

    /// Demo data's old store is let go of: a write still queued for it drops, and its writer goes.
    @Test func theOldStoresQueuedWriteDropsAndItsWriterGoes() async {
        let repo = Repository(env: .preview())
        repo.widgetFile = nil
        let hold = WriterHold()
        repo.writeHooks.job = { _ in hold.pass() }
        let old = repo.storeID
        let held = repo.store(detail: detail("2026-11-01", strain: 1))
        #expect(await eventually { hold.entered == 1 })
        let queued = repo.store(detail: detail("2026-11-02", strain: 2))

        repo.reset()
        #expect(repo.storeID != old)
        hold.open()

        #expect(!(await held.committed()).dropped) // in the writer already: saved into the old store
        #expect(await queued.committed().dropped)
        #expect(hold.entered == 1)
        #expect(await repo.writerEpochs()[old] == nil)
        #expect(repo.day("2026-11-01") == nil && repo.day("2026-11-02") == nil)
    }
}

extension ReadModelWipeRaceTests {
    /// The wiped epoch's writer goes at the invalidate, not at the next write: its context registered the account's
    /// rows.
    @Test func theWipedWriterGoesAtTheInvalidate() async throws {
        let h = WipeHarness()
        let store = h.persistence.epoch.store
        let epoch = h.persistence.epoch.current
        await h.repository.store(detail: detail(h.today, strain: 12)).committed()
        #expect(await h.repository.writerEpochs()[store] == epoch)

        h.persistence.wipe(parkingActivitiesOf: nil, at: h.clock.now())
        h.repository.invalidate()

        #expect(await eventuallyAwaiting(timeout: .seconds(5)) { await h.repository.writerEpochs()[store] == nil })
    }

    /// A batch saved before the wipe and committed after it: its rows are gone, so it doesn't publish the widget (the
    /// sign-out's own publish does).
    @Test func aCommitAfterTheWipeDoesntPublishTheWidget() async throws {
        let h = WipeHarness()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ryft-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        h.repository.widgetFile = file
        var reloads = 0
        h.repository.reloadWidget = { reloads += 1 }
        let hold = WriterHold()
        h.repository.writeHooks.beforeCommit = { hold.pass() }
        let written = h.repository.store(detail: detail(h.today, strain: 12))
        #expect(await eventually { hold.entered == 1 })

        h.persistence.wipe(parkingActivitiesOf: nil, at: h.clock.now())
        h.repository.invalidate()
        hold.open()

        let receipt = await written.committed()
        #expect(receipt.saved && !receipt.dropped)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(reloads == 0)
    }
}

@Suite("Read-model writes: before a system completion")
@MainActor
struct ReadModelCompletionWaitTests {
    /// A write that hangs holds a completion for 2 s at most: iOS may end the app's time soon after.
    @Test func theWaitEndsAtTwoSeconds() async {
        let clock = TestClock()
        let (repository, hold) = await repositoryWithAHeldWrite(clock: clock)
        let ended = Recorded<Bool>()
        let wait = Task {
            await repository.settledBeforeCompletion()
            ended.append(true)
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .milliseconds(1_500))
        #expect(await eventually(timeout: .milliseconds(200)) { ended.count == 1 } == false)
        clock.advance(by: .milliseconds(500))
        #expect(await eventually(timeout: .seconds(2)) { ended.count == 1 })
        #expect(hold.entered == 1) // still held
        hold.open()
        await wait.value
    }

    @Test func theWaitEndsWhenTheWritesSettle() async {
        let clock = TestClock()
        let (repository, hold) = await repositoryWithAHeldWrite(clock: clock)
        let wait = Task { await repository.settledBeforeCompletion() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        hold.open()
        await wait.value
        #expect(repository.day("2026-10-19") != nil)
        #expect(await eventually { clock.pendingSleeps == 0 }) // the bound's sleep ended with it
    }

    /// The system's time ran out (the caller is cancelled): the wait ends at once.
    @Test func aCancelledWaitEndsAtOnce() async {
        let clock = TestClock()
        let (repository, hold) = await repositoryWithAHeldWrite(clock: clock)
        let ended = Recorded<Bool>()
        let wait = Task {
            await repository.settledBeforeCompletion()
            ended.append(true)
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        wait.cancel()
        #expect(await eventually(timeout: .seconds(2)) { ended.count == 1 })
        hold.open()
        await wait.value
    }
}
