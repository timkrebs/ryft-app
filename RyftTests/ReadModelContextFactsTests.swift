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
    // - iOS 17.0: the thread that made the actor. One made off the main actor runs off it even when awaited from main;
    //   one made on the main actor runs on it even when awaited from a `@concurrent` function.
    // - iOS 27.2: the thread that awaits it. Its `DefaultSerialModelExecutor` runs each job synchronously on the thread
    //   that enqueued it, under the context's own queue (the queue label is the `NSManagedObjectContext`'s). Awaited
    //   from the main actor, a job runs on the main thread even for an actor made off it; awaited from a `@concurrent`
    //   function, it runs off the main thread even for an actor made on it.
    // - iOS 18–26: not measured, so the two observations below assert nothing there.
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
        if #unavailable(iOS 18) { // the making thread decides
            #expect(!madeOffRanOnMain)
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
        if #unavailable(iOS 18) { #expect(ranOnMain) } // the making thread decides
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

    // MARK: T0.6: two containers of the schema in one process (the demo store beside the account's)
    //
    // Observation. iOS 17.0: only the container made last takes inserts. A save of a new row in any context of an
    // older one (fresh or main, on disk or in memory) fails with 134020, "the object's persistent store is not
    // reachable", even after the newer one is released; reopening the older store makes it the newest instead. So after
    // a demo session on 17.0 the account's store takes no new rows until a relaunch, whoever writes them. iOS 27.2:
    // both take inserts. iOS 18–26: not measured.

    @Test func insertsIntoTheOlderOfTwoContainers() throws {
        let older = TrainStore(inMemory: true)
        let newer = TrainStore(inMemory: true)
        func insert(_ day: String, into store: TrainStore) -> Int? {
            let context = ModelContext(store.container)
            context.insert(CachedDay(day: day, date: Self.now))
            do {
                try context.save()
                return nil
            } catch {
                return (error as NSError).code
            }
        }
        let olderFailure = insert("2026-01-01", into: older)
        let newerFailure = insert("2026-01-02", into: newer)
        if #available(iOS 27, *) {
            #expect(olderFailure == nil)
            #expect(newerFailure == nil)
        }
        if #unavailable(iOS 18) {
            #expect(olderFailure == 134_020)
            #expect(newerFailure == nil)
        }
    }
}
