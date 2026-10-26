import Foundation
import SwiftData
import Testing
@testable import Ryft

/// The activity models as A1 shipped them (before `sentAt`), to write a store the way an A1 build did.
private enum ActivitySchemaA1 {
    @Model
    final class LocalActivity {
        @Attribute(.unique) var id: UUID
        var account: String
        var parkedAt: Date?
        var sportRaw: String
        var originRaw: String
        var phaseRaw: String
        var start: Date
        var end: Date?
        var movingSec: Double
        var distanceM: Double?
        var ascentM: Double?
        var descentM: Double?
        var perceivedEffort: Int?
        var notes: String
        var recordRoute: Bool
        var zoneCountAtRecording: Int
        var routeWithheld: Bool
        var routeDroppedAt: Date?
        var splitsData: Data?
        var pausesData: Data?
        var headerData: Data?
        var localRevision: Int
        var confirmedRevision: Int
        var deletedAt: Date?
        var lastAttemptData: Data?
        var healthStateRaw: String?
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID, account: String, start: Date, notes: String, localRevision: Int) {
            self.id = id
            self.account = account
            sportRaw = "running"
            originRaw = "manual"
            phaseRaw = "saved"
            self.start = start
            end = start.addingTimeInterval(1_800)
            movingSec = 1_800
            self.notes = notes
            recordRoute = false
            zoneCountAtRecording = 0
            routeWithheld = false
            self.localRevision = localRevision
            confirmedRevision = 0
            createdAt = start
            updatedAt = start
        }
    }

    @Model
    final class LocalManualSleep {
        @Attribute(.unique) var key: String
        var day: String
        var account: String
        var parkedAt: Date?
        var bed: Date
        var wake: Date
        var localRevision: Int
        var confirmedRevision: Int
        var deletedAt: Date?
        var lastAttemptData: Data?

        init(day: String, account: String, bed: Date, wake: Date) {
            key = "\(account)|\(day)"
            self.day = day
            self.account = account
            self.bed = bed
            self.wake = wake
            localRevision = 1
            confirmedRevision = 0
        }
    }
}

/// A2 adds `sentAt` to `LocalActivity` and `LocalManualSleep`. The store a build from A1 left on disk must open with
/// the new schema (a lightweight migration: an added optional attribute), keep every row, and read `sentAt` as nil.
@Suite("Activities: the A2 schema opens an A1 store")
@MainActor
struct ActivitySchemaUpgradeTests {
    @Test func anA1StoreOpensWithEveryRowAndNoSentMarker() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ryft-upgrade-\(UUID().uuidString)",
                                                                                  isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Train.store")
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_792_390_000)

        // An A1 build writes the store (its activity tables).
        do {
            let schema = Schema([ActivitySchemaA1.LocalActivity.self, ActivitySchemaA1.LocalManualSleep.self,
                                 ActivityTrackChunk.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = container.mainContext
            context.insert(ActivitySchemaA1.LocalActivity(id: id, account: "account-a", start: start, notes: "Hills",
                                                          localRevision: 2))
            context.insert(ActivitySchemaA1.LocalManualSleep(day: "2026-10-19", account: "account-a",
                                                             bed: start.addingTimeInterval(-28_800), wake: start))
            try context.save()
        }

        // This build opens it with the whole app schema.
        let container = try ModelContainer(for: TrainStore.schema,
                                           configurations: ModelConfiguration(schema: TrainStore.schema, url: url))
        let context = container.mainContext
        let rows = try context.fetch(FetchDescriptor<LocalActivity>())
        let nights = try context.fetch(FetchDescriptor<LocalManualSleep>())
        #expect(rows.map(\.id) == [id])
        #expect(rows.first?.notes == "Hills" && rows.first?.localRevision == 2 && rows.first?.sentAt == nil)
        #expect(nights.map(\.day) == ["2026-10-19"] && nights.first?.sentAt == nil)
        // And writes the new attribute.
        rows.first?.sentAt = start
        try context.save()
        #expect(try context.fetch(FetchDescriptor<LocalActivity>()).first?.sentAt == start)
    }
}
