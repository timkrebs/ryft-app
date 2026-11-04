import Foundation
import SwiftData
import Testing
@testable import Ryft

/// Train's outbox op and logged session as builds before P2 wrote them (no `account`, no `uploadedTo`).
private enum TrainOutboxSchemaBeforeP2 {
    @Model
    final class LocalSession {
        @Attribute(.unique) var id: UUID
        var title: String
        var startedAt: Date
        var endedAt: Date?
        var statusRaw: String
        var planDayId: UUID?
        var workoutId: UUID?
        var notes: String
        var bodyweightKg: Double?
        var muscularTrimp: Double?
        var strain: Double?
        var volumeKg: Double?
        @Relationship(deleteRule: .cascade, inverse: \LocalSessionExercise.session)
        var exercises: [LocalSessionExercise] = []
        var deletedSetIDs: [UUID] = []
        var pendingCompletion = false
        var uploaded = false
        var prsData: Data?
        var restEndsAt: Date?
        var restTotal: Double = 0
        var updatedAt: Date

        init(id: UUID, title: String, startedAt: Date) {
            self.id = id
            self.title = title
            self.startedAt = startedAt
            statusRaw = "completed"
            notes = ""
            uploaded = true
            updatedAt = startedAt
        }
    }

    @Model
    final class LocalSessionExercise {
        @Attribute(.unique) var id: UUID
        var exerciseId: UUID
        var name: String
        var kindRaw: String
        var loadTypeRaw: String
        var position: Int
        var notes: String
        var restSec: Int
        var supersetGroup: Int?
        var planExerciseId: UUID?
        var targetSets: Int?
        var targetRepsMin: Int?
        var targetRepsMax: Int?
        var targetKg: Double?
        var targetKindRaw: String?
        var targetValue: Double?
        var lastTimeData: Data?
        var session: LocalSession?
        @Relationship(deleteRule: .cascade, inverse: \LocalSet.exercise)
        var sets: [LocalSet] = []

        init(id: UUID, name: String) {
            self.id = id
            exerciseId = UUID()
            self.name = name
            kindRaw = "barbell"
            loadTypeRaw = "weight"
            position = 0
            notes = ""
            restSec = 120
        }
    }

    @Model
    final class LocalSet {
        @Attribute(.unique) var id: UUID
        var setIndex: Int
        var reps: Int?
        var weightKg: Double?
        var rpe: Double?
        var durationSec: Int?
        var distanceM: Double?
        var isWarmup: Bool
        var completedAt: Date?
        var updatedAt: Date
        var exercise: LocalSessionExercise?

        init(id: UUID, reps: Int, weightKg: Double, updatedAt: Date) {
            self.id = id
            setIndex = 0
            self.reps = reps
            self.weightKg = weightKg
            isWarmup = false
            self.updatedAt = updatedAt
        }
    }

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

/// P2 adds `account` to `PendingTrainOp` and `uploadedTo` to `LocalSession` (ADR 0008: every op bound to its account
/// or demo, a delete to where the uploads went). A store an earlier build left on disk must open with the new schema
/// (a lightweight migration: added optional attributes) and keep every queued op and logged session, unbound:
/// `TrainSyncService` counts those as the signed-in account's. Configured as `TrainStore.init` configures its own (see
/// `ActivitySchemaUpgradeTests`).
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

        // An earlier build logs a session (one exercise, one set) and queues a put and a complete.
        do {
            let schema = Schema([TrainOutboxSchemaBeforeP2.LocalSession.self, TrainOutboxSchemaBeforeP2.LocalSessionExercise.self,
                                 TrainOutboxSchemaBeforeP2.LocalSet.self, TrainOutboxSchemaBeforeP2.PendingTrainOp.self])
            let configuration = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: false)
            files.append(configuration.url)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = container.mainContext
            let logged = TrainOutboxSchemaBeforeP2.LocalSession(id: session, title: "Upper A", startedAt: created)
            let exercise = TrainOutboxSchemaBeforeP2.LocalSessionExercise(id: UUID(), name: "Bench press")
            let set = TrainOutboxSchemaBeforeP2.LocalSet(id: UUID(), reps: 5, weightKg: 100, updatedAt: created)
            context.insert(logged)
            exercise.session = logged
            set.exercise = exercise
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
        // The session and its sets are all there, with no binding yet.
        let sessions = try context.fetch(FetchDescriptor<LocalSession>())
        #expect(sessions.map(\.id) == [session] && sessions.first?.uploaded == true && sessions.first?.uploadedTo == nil)
        #expect(sessions.first?.allSets.map(\.weightKg) == [100])
        // Beta feedback 2 (ADR 0009): the exercise tombstones open empty.
        #expect(sessions.first?.deletedExerciseIDs == [])
        // And it writes the new attributes.
        first.account = "account-a"
        sessions.first?.uploadedTo = "account-a"
        let tombstone = UUID()
        sessions.first?.deletedExerciseIDs = [tombstone]
        try context.save()
        #expect(try context.fetch(FetchDescriptor<LocalSession>()).first?.uploadedTo == "account-a")
        #expect(try context.fetch(FetchDescriptor<LocalSession>()).first?.deletedExerciseIDs == [tombstone])
        #expect(try context.fetch(FetchDescriptor<PendingTrainOp>(sortBy: [SortDescriptor(\.seq)])).first?.account == "account-a")
    }
}
