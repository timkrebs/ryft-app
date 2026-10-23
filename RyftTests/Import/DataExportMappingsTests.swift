import Foundation
import Testing
@testable import Ryft

/// "Export my data" includes the remembered import matches (plan.md → Decisions).
@MainActor
@Suite("Data export: remembered matches")
struct DataExportMappingsTests {
    @Test func archiveCarriesTheRememberedMatches() async throws {
        let persistence = TrainStore(inMemory: true)
        let store = ImportMappingStore(persistence: persistence) { "account-a" }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let exercise = MappingFixture.id(7)
        store.remember([SourceExerciseKey(name: "dip", equipment: "bodyweight"):
                            RememberedMatch(exerciseID: exercise, bodyweight: .bodyWeight)],
                       source: .alphaProgression, account: "account-a", at: date)
        let api = MockPlatformAPI()
        let archive = try await DataExport.archive(source: api, train: api, rememberedMatches: store.records(), now: date)
        #expect(archive.rememberedMatches == store.records())

        let url = try DataExport.write(archive)
        defer { try? FileManager.default.removeItem(at: url) }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let object = try #require(json as? [String: Any])
        let matches = try #require(object["remembered_matches"] as? [[String: Any]])
        #expect(matches.count == 1)
        let first = try #require(matches.first)
        #expect(first["source"] as? String == "alpha_progression")
        #expect(first["name"] as? String == "dip")
        #expect(first["equipment"] as? String == "bodyweight")
        #expect(first["exercise_id"] as? String == exercise.uuidString)
        #expect(first["bodyweight_answer"] as? String == "bodyWeight")
        #expect(first["updated_at"] is String)
    }

    @Test func noMatchesIsAnEmptyList() async throws {
        let api = MockPlatformAPI()
        let archive = try await DataExport.archive(source: api, train: api, now: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(archive.rememberedMatches.isEmpty)
    }
}
