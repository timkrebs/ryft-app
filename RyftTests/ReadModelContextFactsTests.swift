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

    // MARK: T0.1 (F8)
    //
    // F8 as the design states it is wrong on iOS 27.2: where the actor was made doesn't decide the thread. Its
    // `DefaultSerialModelExecutor` runs each job synchronously on the thread that enqueued it, under the context's own
    // queue (the queue label is the `NSManagedObjectContext`'s). Awaited from the main actor, a job runs on the main
    // thread, even for an actor made off it; awaited from a `@concurrent` function, it runs off the main thread, even for
    // an actor made on it.

    @Test func aJobAwaitedFromTheMainActorRunsOnTheMainThreadWhereverTheActorWasMade() async throws {
        let store = TrainStore(inMemory: true)
        let madeOff = await ContextFactsWriter.make(store.container)
        #expect(try await madeOff.upsert(Self.days(3), score: Data("a".utf8), at: Self.now))
        let madeOn = ContextFactsWriter(modelContainer: store.container)
        #expect(try await madeOn.upsert(Self.days(3), score: Data("b".utf8), at: Self.now))
    }

    @Test func aJobAwaitedFromAConcurrentFunctionRunsOffTheMainThread() async throws {
        let store = TrainStore(inMemory: true)
        let madeOff = await ContextFactsWriter.make(store.container)
        #expect(try await !ContextFactsWriter.upsertOffMain(madeOff, Self.days(3), score: Data("a".utf8), at: Self.now))
        // A second job on the same actor stays off it too.
        #expect(try await !ContextFactsWriter.upsertOffMain(madeOff, Self.days(3), score: Data("b".utf8), at: Self.now))
        let madeOn = ContextFactsWriter(modelContainer: store.container)
        #expect(try await !ContextFactsWriter.upsertOffMain(madeOn, Self.days(3), score: Data("c".utf8), at: Self.now))
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
