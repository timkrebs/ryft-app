import Foundation
import SwiftData
import Testing
@testable import Ryft

// T0 of the read-model writer (docs/work/2026-11-17-persistence-off-main/design.md §7.1): the SwiftData facts the design
// assumes (F8–F10), checked on the runtime before anything is built on them. A probe actor of its own, so these stay true
// statements about the platform whatever the app's writer becomes. Synthetic values only.

/// A `@ModelActor` on the store's own container, like the app's writer: upserts `CachedDay` rows by a batch fetch, and
/// says which thread it ran on.
@ModelActor
actor ContextFactsWriter {
    /// Built off the main actor, as design.md §5.2 planned against F8.
    @concurrent static func make(_ container: ModelContainer) async -> ContextFactsWriter {
        ContextFactsWriter(modelContainer: container)
    }

    /// The same upsert, awaited from a `@concurrent` function: the job is enqueued from a cooperative thread.
    @concurrent static func upsertOffMain(_ writer: ContextFactsWriter, _ days: [String], score: Data,
                                          at date: Date) async throws -> Bool {
        try await writer.upsert(days, score: score, at: date)
    }

    /// Upserts `days` with `score` as their score bytes, in one fetch and one save. True when it ran on the main thread.
    func upsert(_ days: [String], score: Data, at date: Date) throws -> Bool {
        modelContext.autosaveEnabled = false
        let keys = days
        let rows = try modelContext.fetch(FetchDescriptor<CachedDay>(predicate: #Predicate { keys.contains($0.day) }))
        var byDay = Dictionary(rows.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        for day in days {
            let row: CachedDay
            if let existing = byDay[day] {
                row = existing
            } else {
                row = CachedDay(day: day, date: DayFormat.date(from: day) ?? date)
                modelContext.insert(row)
                byDay[day] = row
            }
            row.scoreData = score
            row.scoreFetchedAt = date
        }
        try modelContext.save()
        return MainThread.isCurrent
    }

    @concurrent static func countOffMain(_ writer: ContextFactsWriter, _ keys: [String]) async throws -> Int {
        try await writer.count(keys)
    }

    /// How many of `keys` one `contains` predicate finds.
    func count(_ keys: [String]) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<CachedDay>(predicate: #Predicate { keys.contains($0.day) }))
    }
}

@Suite("T0: two contexts on one container")
@MainActor
struct ReadModelContextFactsTests {
    /// Day keys from 2026-01-01 on.
    static func days(_ count: Int) -> [String] {
        let start = DayFormat.date(from: "2026-01-01") ?? .distantPast
        return (0..<count).map { DayFormat.string(from: DayFormat.shift(start, days: $0)) }
    }

    static let now = Date(timeIntervalSince1970: 1_794_000_000)

    private static func scores(in context: ModelContext, _ days: [String]) throws -> [String: Data] {
        let keys = days
        let rows = try context.fetch(FetchDescriptor<CachedDay>(predicate: #Predicate { keys.contains($0.day) }))
        return Dictionary(rows.compactMap { row in row.scoreData.map { (row.day, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// A store on disk in a folder of its own.
    final class Disk {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ryft-t0-\(UUID().uuidString)")
        var url: URL { folder.appendingPathComponent("Train.store") }
        init() throws { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: T0.1 (F8): which thread a model actor's job runs on
    //
    // The OS decides differently, so both the place an actor is made and the place it's awaited matter:
    // - iOS 17.0, measured before ADR 0021: the thread that made the actor. One made off the main actor runs off it
    //   even when awaited from main; one made on the main actor runs on it even when awaited from a `@concurrent`
    //   function.
    // - iOS 27.2: the thread that awaits it. Its `DefaultSerialModelExecutor` runs each job synchronously on the thread
    //   that enqueued it, under the context's own queue (the queue label is the `NSManagedObjectContext`'s). Awaited
    //   from the main actor, a job runs on the main thread even for an actor made off it; awaited from a `@concurrent`
    //   function, it runs off the main thread even for an actor made on it.
    // - iOS 18.6–26: not measured, so the two observations below assert nothing there.
    // The invariant holds on both measured OSes, and it's the one the app relies on (`ReadModelDrain` makes and awaits
    // its writer on its own executor): an actor made off the main actor and awaited off it runs its jobs off it.

    @Test func aJobOfAnActorMadeAndAwaitedOffTheMainActorRunsOffTheMainThread() async throws {
        let store = TrainStore(inMemory: true)
        let writer = await ContextFactsWriter.make(store.container)
        #expect(try await !ContextFactsWriter.upsertOffMain(writer, Self.days(3), score: Data("a".utf8), at: Self.now))
        // A second job on the same actor stays off it too.
        #expect(try await !ContextFactsWriter.upsertOffMain(writer, Self.days(3), score: Data("b".utf8), at: Self.now))
    }

    /// Observation: a job awaited from the main actor.
    @Test func aJobAwaitedFromTheMainActor() async throws {
        let store = TrainStore(inMemory: true)
        let madeOff = await ContextFactsWriter.make(store.container)
        let madeOffRanOnMain = try await madeOff.upsert(Self.days(3), score: Data("a".utf8), at: Self.now)
        let madeOn = ContextFactsWriter(modelContainer: store.container)
        let madeOnRanOnMain = try await madeOn.upsert(Self.days(3), score: Data("b".utf8), at: Self.now)
        if #available(iOS 27, *) { // the awaiting thread decides
            #expect(madeOffRanOnMain)
            #expect(madeOnRanOnMain)
        }
    }

    /// Observation: a job of an actor made on the main actor, awaited from a `@concurrent` function.
    @Test func aJobOfAnActorMadeOnTheMainActorAwaitedOffIt() async throws {
        let store = TrainStore(inMemory: true)
        let madeOn = ContextFactsWriter(modelContainer: store.container)
        let ranOnMain = try await ContextFactsWriter.upsertOffMain(madeOn, Self.days(3), score: Data("c".utf8),
                                                                   at: Self.now)
        if #available(iOS 27, *) { #expect(!ranOnMain) } // the awaiting thread decides
    }

    // MARK: T0.2 (F9, F10)

    @Test func aFreshContextSeesTheWritersCommitInMemory() async throws {
        let store = TrainStore(inMemory: true)
        let writer = await ContextFactsWriter.make(store.container)
        let days = Self.days(5)
        _ = try await ContextFactsWriter.upsertOffMain(writer, days, score: Data("in memory".utf8), at: Self.now)
        let fresh = ModelContext(store.container)
        #expect(try Self.scores(in: fresh, days) == Dictionary(uniqueKeysWithValues: days.map { ($0, Data("in memory".utf8)) }))
    }

    @Test func aFreshContextSeesTheWritersCommitOnDisk() async throws {
        let disk = try Disk()
        let store = TrainStore(url: disk.url)
        #expect(store.isDurable)
        let writer = await ContextFactsWriter.make(store.container)
        let days = Self.days(5)
        _ = try await ContextFactsWriter.upsertOffMain(writer, days, score: Data("on disk".utf8), at: Self.now)
        let fresh = ModelContext(store.container)
        #expect(try Self.scores(in: fresh, days).values.allSatisfy { $0 == Data("on disk".utf8) })
        #expect(try Self.scores(in: fresh, days).count == days.count)
        // And a relaunch reads it from the file.
        let reopened = TrainStore(url: disk.url)
        let rows = try Self.scores(in: ModelContext(reopened.container), days)
        withExtendedLifetime(reopened) { #expect(rows.count == days.count) }
    }

    // MARK: T0.3 (F9): what a context that fetched before the commit sees
    //
    // iOS 27.2: after the writer's commit, a refetch in the early context returns the new bytes, and the object it held
    // shows them too; so does the container's main context. Not relied on: the Repository replaces its read context at
    // every commit, and a fresh context has the new bytes, which is what this pins.

    @Test func aFreshContextAfterTheCommitHasTheNewBytes() async throws {
        let store = TrainStore(inMemory: true)
        let writer = await ContextFactsWriter.make(store.container)
        let days = Self.days(1)
        _ = try await ContextFactsWriter.upsertOffMain(writer, days, score: Data("old".utf8), at: Self.now)
        let early = ModelContext(store.container)
        #expect(try Self.scores(in: early, days)[days[0]] == Data("old".utf8))

        _ = try await ContextFactsWriter.upsertOffMain(writer, days, score: Data("new".utf8), at: Self.now)

        #expect(try Self.scores(in: ModelContext(store.container), days)[days[0]] == Data("new".utf8))
        withExtendedLifetime(early) {}
    }

    // MARK: T0.4: the wipe deletes rows the writer's context has registered

    @Test func aWipeOfRowsTheWriterHoldsLeavesItAbleToUpsertThemAgain() async throws {
        let disk = try Disk()
        let store = TrainStore(url: disk.url)
        let writer = await ContextFactsWriter.make(store.container)
        let days = Self.days(10)
        _ = try await ContextFactsWriter.upsertOffMain(writer, days, score: Data("account A".utf8), at: Self.now)
        #expect(try ModelContext(store.container).fetchCount(FetchDescriptor<CachedDay>()) == days.count)

        // Batch deletes and a save on the main context, while the writer's context still has the rows registered.
        #expect(store.wipe())
        #expect(try ModelContext(store.container).fetchCount(FetchDescriptor<CachedDay>()) == 0)

        // The same unique days again, through the same writer: no error, one row each, the new bytes.
        _ = try await ContextFactsWriter.upsertOffMain(writer, Array(days.prefix(4)), score: Data("account B".utf8),
                                                       at: Self.now)
        let fresh = ModelContext(store.container)
        #expect(try fresh.fetchCount(FetchDescriptor<CachedDay>()) == 4)
        #expect(try Self.scores(in: fresh, days).values.allSatisfy { $0 == Data("account B".utf8) })
    }

    // MARK: T0.5: one `contains` predicate with 400 keys

    @Test func fourHundredKeysInOnePredicate() async throws {
        let store = TrainStore(inMemory: true)
        let writer = await ContextFactsWriter.make(store.container)
        let days = Self.days(450)
        _ = try await ContextFactsWriter.upsertOffMain(writer, days, score: Data("x".utf8), at: Self.now)
        #expect(try await ContextFactsWriter.countOffMain(writer, Array(days.prefix(400))) == 400)
        #expect(try await ContextFactsWriter.countOffMain(writer, days) == 450)
        #expect(try ModelContext(store.container).fetchCount(FetchDescriptor<CachedDay>()) == 450)
    }
}

// MARK: - T0.6: two containers of the schema in one process (the demo store beside the account's)
//
// iOS 17.0, measured: only the container made last takes inserts. A save of a new row in any context of an older one
// (fresh or main, on disk or in memory) fails with 134020, "the object's persistent store is not reachable", even after
// the newer one is released; reopening the older store makes it the newest instead. So after a demo session the
// account's store takes no new rows until a relaunch, whoever writes them. iOS 27.2, measured: both take inserts.
// Every other version is unmeasured: there these tests pass when every insert lands, and fail with their one line when
// one doesn't. Each prints that line (`T0.6 …`) on every OS, so one run of this suite on a runtime is the answer:
//
//     xcodebuild test -only-testing:RyftTests/ReadModelContextFactsTests/TwoContainers …
//
// Serialized: a container another test makes in between would be the newest.

extension ReadModelContextFactsTests {
    @Suite("T0.6: two containers of the schema in one process", .serialized)
    @MainActor
    struct TwoContainers {
        /// What has been measured, and where this runtime stands.
        enum Runtime: Equatable {
            /// iOS 17.0.
            case onlyTheNewestTakesInserts
            /// iOS 27.2.
            case everyContainerTakesInserts
            case unmeasured

            static var current: Runtime {
                let v = ProcessInfo.processInfo.operatingSystemVersion
                switch (v.majorVersion, v.minorVersion) {
                case (17, 0): return .onlyTheNewestTakesInserts
                case (27, 2): return .everyContainerTakesInserts
                default: return .unmeasured
                }
            }

            static var name: String {
                let v = ProcessInfo.processInfo.operatingSystemVersion
                return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            }
        }

        /// The observation in one line, printed on every OS; on an unmeasured one it's also the failure, if an insert
        /// failed.
        private func report(_ line: String, anInsertFailed: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
            print(line)
            if Runtime.current == .unmeasured, anInsertFailed {
                Issue.record(Comment(rawValue: line), sourceLocation: sourceLocation)
            }
        }

        private static func saved(_ saved: Bool) -> String { saved ? "saved" : "NOT saved" }

        /// Two containers made one after the other, a new row saved into each through a fresh context.
        @Test func insertsIntoTheOlderOfTwoContainers() {
            let older = TrainStore(inMemory: true)
            let newer = TrainStore(inMemory: true)
            func insert(_ day: String, into store: TrainStore) -> Int? {
                let context = ModelContext(store.container)
                context.insert(CachedDay(day: day, date: ReadModelContextFactsTests.now))
                do {
                    try context.save()
                    return nil
                } catch {
                    return (error as NSError).code
                }
            }
            let olderFailure = insert("2026-01-01", into: older)
            let newerFailure = insert("2026-01-02", into: newer)

            func outcome(_ failure: Int?) -> String { failure.map { "fails (\($0))" } ?? "lands" }
            report("T0.6 probe, \(Runtime.name): an insert into the older container \(outcome(olderFailure)), "
                + "into the newer \(outcome(newerFailure))",
                anInsertFailed: olderFailure != nil || newerFailure != nil)
            switch Runtime.current {
            case .onlyTheNewestTakesInserts:
                #expect(olderFailure == 134_020)
                #expect(newerFailure == nil)
            case .everyContainerTakesInserts:
                #expect(olderFailure == nil)
                #expect(newerFailure == nil)
            case .unmeasured:
                break
            }
        }

        /// A graph on `account` with the Demo data switch at `demo`, as the app's: the demo's store is made by the
        /// Repository's first read in demo mode.
        private func graph(_ account: TrainStore, demo: Bool) throws -> (Repository, Settings) {
            let defaults = try #require(UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)"))
            let settings = Settings(defaults: defaults)
            settings.demoMode = demo
            let api = MockPlatformAPI()
            let env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: api, demoAPI: api,
                                     auth: .preview(), persistence: account,
                                     clock: TestClock(now: ReadModelContextFactsTests.now), notifier: MockNotifier(),
                                     flags: StaticFlags([:]), connectivity: .preview(online: true), defaults: defaults,
                                     demoOverride: nil)
            let repo = Repository(env: env)
            repo.widgetFile = nil
            return (repo, settings)
        }

        /// The account's user, a row its store has from a launch before, changed after a demo (as a withdrawal or a
        /// `PATCH` changes it: a delete and an insert). On iOS 17.0 that save fails in the older container, and the
        /// app must not crash there (a rollback of it traps inside SwiftData): the store keeps the user from before,
        /// the next write goes on. Elsewhere it saves.
        @Test func theAccountsUserChangedAfterTheDemo() async throws {
            let disk = try ReadModelContextFactsTests.Disk()
            var user = MockData.user
            user.birthYear = 1981
            do {
                let (first, _) = try graph(TrainStore(url: disk.url), demo: false)
                #expect(await first.store(user: user).committed().saved)
            }

            let account = TrainStore(url: disk.url)
            let (repo, settings) = try graph(account, demo: true)
            #expect(repo.score("2026-01-01") == nil) // the demo's store made: the newest container
            settings.demoMode = false
            #expect(repo.user()?.birthYear == 1981)
            user.birthYear = 1982
            let changed = await repo.store(user: user).committed()
            #expect(repo.user()?.birthYear == 1982) // written through, whatever the store took
            let next = await repo.store(scores: [DailyScore(day: "2026-01-03", strain: 3)]).committed()
            await repo.settled()
            repo.invalidate()
            let stored = repo.user()?.birthYear

            report("T0.6 changed user, \(Runtime.name): the user's save \(Self.saved(changed.saved)), the next write "
                + "\(Self.saved(next.saved)); the store has birth year \(stored.map(String.init) ?? "none")",
                anInsertFailed: !changed.saved || !next.saved || stored != 1982)
            switch Runtime.current {
            case .onlyTheNewestTakesInserts:
                #expect(!changed.saved && !next.saved)
                #expect(stored == 1981) // the user from before: nothing of the change saved, nothing lost
            case .everyContainerTakesInserts:
                #expect(changed.saved && next.saved)
                #expect(stored == 1982)
            case .unmeasured:
                break
            }
        }

        /// The path every new user may take, as the app takes it: the account's store opened on disk first (at
        /// launch), the demo's store made by the Repository's first read in demo mode, then the demo switched off and
        /// the account's first read-model write and Train row. This is the test that decides P1b (design.md,
        /// decision 11).
        @Test func theAccountsFirstWritesAfterTheDemo() async throws {
            let disk = try ReadModelContextFactsTests.Disk()
            let account = TrainStore(url: disk.url)
            #expect(account.isDurable)
            let defaults = try #require(UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)"))
            let settings = Settings(defaults: defaults)
            settings.demoMode = true
            let api = MockPlatformAPI()
            let env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: api, demoAPI: api,
                                     auth: .preview(), persistence: account,
                                     clock: TestClock(now: ReadModelContextFactsTests.now), notifier: MockNotifier(),
                                     flags: StaticFlags([:]), connectivity: .preview(online: true), defaults: defaults,
                                     demoOverride: nil)
            let repo = Repository(env: env)
            // A graph with the Demo data switch shares the widget's file; this one's writes are nobody's.
            repo.widgetFile = nil

            // The demo: its first read makes its store, the newest container, and it writes there.
            #expect(repo.score("2026-01-01") == nil)
            let demo = await repo.store(scores: [DailyScore(day: "2026-01-01", strain: 1)]).committed()

            // The demo ends; the account's first writes.
            settings.demoMode = false
            let day = "2026-01-02"
            let readModel = await repo.store(scores: [DailyScore(day: day, strain: 2)]).committed()
            let session = LocalSession(title: "Upper")
            account.context.insert(session)
            let trainSaved = account.save()

            // Read back through the Repository, and from the store itself (a fresh context, not the inserting one).
            let id = session.id
            let fresh = ModelContext(account.container)
            let days = try fresh.fetchCount(FetchDescriptor<CachedDay>(predicate: #Predicate { $0.day == day }))
            let sessions = try fresh.fetchCount(FetchDescriptor<LocalSession>(predicate: #Predicate { $0.id == id }))
            let readsBack = repo.score(day)?.strain == 2

            report("T0.6 app path, \(Runtime.name): the demo's write \(Self.saved(demo.saved)); then the account's "
                + "read-model write \(Self.saved(readModel.saved)), its Train row \(Self.saved(trainSaved)); "
                + "the store has \(days) day(s) and \(sessions) session(s); the Repository reads the day back: "
                + (readsBack ? "yes" : "no"),
                anInsertFailed: !demo.saved || !readModel.saved || !trainSaved || days != 1 || sessions != 1
                    || !readsBack)
            switch Runtime.current {
            case .onlyTheNewestTakesInserts:
                #expect(demo.saved)
                #expect(!readModel.saved)
                #expect(!trainSaved)
                #expect(days == 0 && sessions == 0 && !readsBack)
            case .everyContainerTakesInserts:
                #expect(demo.saved)
                #expect(readModel.saved && trainSaved)
                #expect(days == 1 && sessions == 1 && readsBack)
            case .unmeasured:
                break
            }
        }
    }
}
