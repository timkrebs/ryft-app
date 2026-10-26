import Foundation
import SwiftData
import Testing
@testable import Ryft

/// Privacy review S1: the job's payload is external storage, so the account wipe deletes the rows one by one and no
/// file of the imported history is left beside the store. Tested on a store on disk in a folder of its own.
@Suite("Import: the wipe leaves no payload file")
@MainActor
struct PendingImportWipeTests {
    /// Sign-out (nil) and a session expiry, which parks the account's activities (but never its import job).
    @Test(arguments: [nil, "account-a"] as [String?])
    func theWipeDeletesThePayloadFile(_ parking: String?) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ryft-import-wipe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainStore(url: folder.appendingPathComponent("Train.store"))
        #expect(store.isDurable)
        // Over 200 KiB of bytes that don't compress: Core Data keeps it in a file of its own.
        var generator = SystemRandomNumberGenerator()
        let payload = Data((0..<(300 * 1_024)).map { _ in UInt8.random(in: 0...255, using: &generator) })
        store.context.insert(PendingImport(account: "account-a", source: .alphaProgression, createdAt: .now,
                                           timeZoneID: "Europe/Berlin", duplicatesChecked: true, payload: payload,
                                           progressData: Data("{}".utf8), sessionsPerRequest: 50))
        store.save()
        #expect(await eventually(timeout: .seconds(10)) { Self.externalFiles(in: folder).count == 1 })

        store.wipe(parkingActivitiesOf: parking)
        store.save()
        let left = try store.context.fetchCount(FetchDescriptor<PendingImport>())
        #expect(left == 0)
        #expect(await eventually(timeout: .seconds(10)) { Self.externalFiles(in: folder).isEmpty })
    }

    /// Files Core Data keeps outside the store (`.<store>_SUPPORT/_EXTERNAL_DATA/`).
    static func externalFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: []) else { return [] }
        return walk.compactMap { $0 as? URL }.filter { url in
            url.path.contains("_EXTERNAL_DATA") && (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true
        }
    }
}

/// Privacy review S2: "Export my data" carries the import job while some of it isn't on the platform yet.
@Suite("Import: the job in the data export")
@MainActor
struct PendingImportExportTests {
    private static let created = Date(timeIntervalSince1970: 1_792_400_000)

    private static func insertJob(into store: TrainStore, account: String, plan: ImportUploadPlan,
                                  progress: ImportJobProgress) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        store.context.insert(PendingImport(account: account, source: .alphaProgression, createdAt: created,
                                           timeZoneID: "Europe/Berlin", duplicatesChecked: true,
                                           payload: try APIClient.jsonEncoder.encode(plan),
                                           progressData: try encoder.encode(progress), sessionsPerRequest: 50))
        store.save()
    }

    @Test func theExportCarriesWhatIsntOnThePlatform() async throws {
        let store = TrainStore(inMemory: true)
        let sessions = ImportUploadHarness.sessions(4)
        let plan = ImportUploadPlan(exercises: [ImportUploadHarness.custom(1)], plans: [ImportUploadHarness.plan(1)],
                                    sessions: sessions)
        var progress = ImportJobProgress()
        progress[ImportUploadHarness.custom(1).id] = ImportJobProgress.Item(phase: .done, result: "created")
        progress[ImportUploadHarness.plan(1).id] = ImportJobProgress.Item(phase: .done, result: "created")
        progress[sessions[0].id] = ImportJobProgress.Item(phase: .done, result: "created")
        progress[sessions[1].id] = ImportJobProgress.Item(phase: .rejected, reason: "invalid")
        progress[sessions[2].id] = ImportJobProgress.Item(phase: .duplicate, related: ImportBuildFixture.id(900))
        try Self.insertJob(into: store, account: "account-a", plan: plan, progress: progress)

        let made = await PendingImportExport.make(persistence: store, account: "account-a")
        let export = try #require(made)
        #expect(export.source == "alpha_progression" && export.timeZone == "Europe/Berlin" && export.createdAt == Self.created)
        #expect(export.items.map(\.kind) == ["session", "session", "session"])
        #expect(export.items.map(\.state) == ["refused", "skipped_duplicate", "pending"])
        #expect(export.items.map(\.item) == [.session(sessions[1]), .session(sessions[2]), .session(sessions[3])])
        // Another binding's export never carries it.
        #expect(await PendingImportExport.make(persistence: store, account: "account-b") == nil)
        #expect(await PendingImportExport.make(persistence: store, account: nil) == nil)

        let api = MockPlatformAPI()
        let archive = try await DataExport.archive(source: api, train: api, pendingImport: export, now: Self.created)
        let url = try DataExport.write(archive)
        defer { try? FileManager.default.removeItem(at: url) }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let object = try #require(json as? [String: Any])
        let pending = try #require(object["pending_import"] as? [String: Any])
        #expect(pending["source"] as? String == "alpha_progression")
        #expect(pending["time_zone"] as? String == "Europe/Berlin")
        #expect(pending["created_at"] is String)
        let items = try #require(pending["items"] as? [[String: Any]])
        #expect(items.map { $0["state"] as? String } == ["refused", "skipped_duplicate", "pending"])
        let first = try #require(items.first?["item"] as? [String: Any])
        #expect(first["id"] as? String == sessions[1].id.uuidString)
        #expect(first["started_at"] is String && first["exercises"] is [Any])
    }

    @Test func aJobWithNothingLeftIsNotExported() async throws {
        let store = TrainStore(inMemory: true)
        let sessions = ImportUploadHarness.sessions(1)
        var progress = ImportJobProgress()
        progress[sessions[0].id] = ImportJobProgress.Item(phase: .done, result: "created")
        try Self.insertJob(into: store, account: "account-a", plan: ImportUploadPlan(sessions: sessions), progress: progress)
        #expect(await PendingImportExport.make(persistence: store, account: "account-a") == nil)
        let api = MockPlatformAPI()
        let archive = try await DataExport.archive(source: api, train: api, now: Self.created)
        #expect(archive.pendingImport == nil)
    }

    /// An exercise and a plan that aren't on the platform are exported as they'd be sent.
    @Test func exercisesAndPlansAreExportedToo() async throws {
        let store = TrainStore(inMemory: true)
        let exercise = ImportUploadHarness.custom(1)
        let plan = ImportUploadHarness.plan(1, exercise: exercise)
        var progress = ImportJobProgress()
        progress[exercise.id] = ImportJobProgress.Item(phase: .rejected, reason: "name")
        progress[plan.id] = ImportJobProgress.Item(phase: .blocked, related: exercise.id)
        try Self.insertJob(into: store, account: "demo", plan: ImportUploadPlan(exercises: [exercise], plans: [plan]),
                           progress: progress)
        let made = await PendingImportExport.make(persistence: store, account: "demo")
        let export = try #require(made)
        #expect(export.items.map(\.kind) == ["exercise", "plan"])
        #expect(export.items.map(\.state) == ["refused", "blocked"])
        #expect(export.items.map(\.item) == [.exercise(exercise), .plan(plan)])
    }
}

/// Privacy review, low: demo's custom exercises never land in the account's library cache.
@Suite("Import: demo stays demo's")
@MainActor
struct PendingImportDemoCacheTests {
    @Test func demoExercisesAreNotCached() async throws {
        let demo = ImportUploadHarness(demo: true)
        #expect(await demo.run(ImportUploadPlan(exercises: [ImportUploadHarness.custom(1)])))
        #expect(demo.uploader.status?.exercises.done == 1)
        #expect(demo.persistence.exercise(id: ImportUploadHarness.custom(1).id) == nil)
        let account = ImportUploadHarness()
        #expect(await account.run(ImportUploadPlan(exercises: [ImportUploadHarness.custom(1)])))
        #expect(account.persistence.exercise(id: ImportUploadHarness.custom(1).id) != nil)
    }
}
