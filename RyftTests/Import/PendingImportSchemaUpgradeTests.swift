import Foundation
import SwiftData
import Testing
@testable import Ryft

/// I5 adds one entity, `PendingImport`, to `TrainStore.schema`. A store an earlier build left on disk must open with the
/// new schema (a lightweight migration: a new entity) and keep everything in it, and the new entity must be writable.
/// Configured as `TrainStore.init` configures its own (see `TrainOutboxSchemaUpgradeTests`).
@Suite("Import: the I5 schema opens an earlier store")
@MainActor
struct PendingImportSchemaUpgradeTests {
    @Test func anEarlierStoreOpensAndTakesAJob() throws {
        let name = "Train-import-upgrade-\(UUID().uuidString)"
        let session = UUID()
        let created = Date(timeIntervalSince1970: 1_792_390_000)
        var files: [URL] = []
        defer {
            for file in files {
                for suffix in ["", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(at: URL(fileURLWithPath: file.path + suffix))
                }
            }
        }
        let key = SourceExerciseKey(name: "bench press", equipment: "barbell")

        // The schema before I5: everything but `PendingImport`.
        do {
            let schema = Schema([LocalSession.self, LocalSessionExercise.self, LocalSet.self, CachedExercise.self,
                                 CachedPlan.self, PendingTrainOp.self, ImportMapping.self]
                                + TrainStore.readModels + TrainStore.activityModels)
            let names = schema.entities.map(\.name)
            #expect(!names.contains("PendingImport"))
            let configuration = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: false,
                                                   groupContainer: .automatic, cloudKitDatabase: .none)
            files.append(configuration.url)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = container.mainContext
            context.insert(PendingTrainOp(seq: 1, kind: .put, sessionId: session, account: "account-a"))
            context.insert(ImportMapping(account: "account-a", source: .alphaProgression, key: key,
                                         choice: RememberedMatch(exerciseID: session, bodyweight: .addedWeight), at: created))
            try context.save()
        }

        // As `TrainStore.init` opens its own: by name, the App Group when there is one, never CloudKit.
        let configuration = ModelConfiguration(name, schema: TrainStore.schema, isStoredInMemoryOnly: false,
                                               groupContainer: .automatic, cloudKitDatabase: .none)
        let container = try ModelContainer(for: TrainStore.schema, configurations: configuration)
        #expect(container.configurations.first?.url == files.first)
        let context = container.mainContext
        let ops = try context.fetch(FetchDescriptor<PendingTrainOp>())
        #expect(ops.map(\.sessionId) == [session] && ops.first?.account == "account-a")
        let mappings = try context.fetch(FetchDescriptor<ImportMapping>())
        #expect(mappings.map(\.key) == [key] && mappings.first?.choice.bodyweight == .addedWeight)
        let none = try context.fetchCount(FetchDescriptor<PendingImport>())
        #expect(none == 0)
        // And it stores a job.
        context.insert(PendingImport(account: "account-a", source: .alphaProgression, createdAt: created,
                                     timeZoneID: "Europe/Berlin", duplicatesChecked: false, payload: Data([1, 2, 3]),
                                     progressData: Data("{}".utf8), sessionsPerRequest: 50))
        try context.save()
        let jobs = try context.fetch(FetchDescriptor<PendingImport>())
        #expect(jobs.map(\.account) == ["account-a"] && jobs.first?.payload == Data([1, 2, 3]))
        #expect(jobs.first?.finishedAt == nil && jobs.first?.resultSeen == false)
    }

    /// The wipe at sign-out takes the job with the rest (design §7, §10).
    @Test func theWipeDeletesTheJob() throws {
        let store = TrainStore(inMemory: true)
        store.context.insert(PendingImport(account: "account-a", source: .alphaProgression, createdAt: .now,
                                           timeZoneID: "Europe/Berlin", duplicatesChecked: true, payload: Data(),
                                           progressData: Data(), sessionsPerRequest: 50))
        store.save()
        store.wipe(parkingActivitiesOf: "account-a")
        let left = try store.context.fetchCount(FetchDescriptor<PendingImport>())
        #expect(left == 0)
    }
}
