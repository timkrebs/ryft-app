import Foundation
import SwiftData
import Testing
@testable import Ryft

/// Train's outbox op as builds before P2 wrote it (no `account`).
private enum TrainOutboxSchemaBeforeP2 {
    @Model
    final class PendingTrainOp {
        var seq: Int
        var kindRaw: String
        var sessionId: UUID
        var bodyweightKg: Double?
        var createdAt: Date

        init(seq: Int, kindRaw: String, sessionId: UUID, createdAt: Date) {
            self.seq = seq
            self.kindRaw = kindRaw
            self.sessionId = sessionId
            self.createdAt = createdAt
        }
    }
}

/// P2 adds `account` to `PendingTrainOp` (ADR 0008: every op bound to its account or demo). A store an earlier build
/// left on disk must open with the new schema (a lightweight migration: an added optional attribute) and keep every
/// queued op, unbound: `TrainSyncService` counts those as the signed-in account's. Configured as `TrainStore.init`
/// configures its own (see `ActivitySchemaUpgradeTests`).
@Suite("Train: the P2 schema opens an earlier outbox")
@MainActor
struct TrainOutboxSchemaUpgradeTests {
    @Test func queuedOpsSurviveUnbound() throws {
        let name = "Train-outbox-upgrade-\(UUID().uuidString)"
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

        // An earlier build queues a put and a complete.
        do {
            let schema = Schema([TrainOutboxSchemaBeforeP2.PendingTrainOp.self])
            let configuration = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: false)
            files.append(configuration.url)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = container.mainContext
            context.insert(TrainOutboxSchemaBeforeP2.PendingTrainOp(seq: 1, kindRaw: "put", sessionId: session,
                                                                    createdAt: created))
            context.insert(TrainOutboxSchemaBeforeP2.PendingTrainOp(seq: 2, kindRaw: "complete", sessionId: session,
                                                                    createdAt: created))
            try context.save()
        }

        // This build opens it as `TrainStore` does: by name, with the whole app schema, on disk.
        let configuration = ModelConfiguration(name, schema: TrainStore.schema, isStoredInMemoryOnly: false)
        let container = try ModelContainer(for: TrainStore.schema, configurations: configuration)
        #expect(container.configurations.allSatisfy { !$0.isStoredInMemoryOnly })
        #expect(container.configurations.first?.url == files.first)
        let context = container.mainContext
        let ops = try context.fetch(FetchDescriptor<PendingTrainOp>(sortBy: [SortDescriptor(\.seq)]))
        #expect(ops.map(\.kind) == [.put, .complete] && ops.allSatisfy { $0.sessionId == session })
        #expect(ops.allSatisfy { $0.account == nil })
        // Unbound: the account's, never demo's.
        let first = try #require(ops.first)
        #expect(TrainSyncService.belongs(first, to: "account-a"))
        #expect(!TrainSyncService.belongs(first, to: TrainSyncService.demoOwner))
        // And it writes the new attribute.
        first.account = "account-a"
        try context.save()
        #expect(try context.fetch(FetchDescriptor<PendingTrainOp>(sortBy: [SortDescriptor(\.seq)])).first?.account == "account-a")
    }
}
