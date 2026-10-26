import Foundation
import Testing
@testable import Ryft

/// Profile's side of the remembered import matches: Export my data carries them, demo's go when demo ends.
@MainActor
@Suite("Profile: remembered import matches")
struct ProfileImportMappingTests {
    static let key = SourceExerciseKey(name: "dips", equipment: "bodyweight")
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    func model(_ env: AppEnvironment) -> ProfileViewModel {
        let state = AppState(env: env)
        let sync = SyncService.ungated(env: env)
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock)
        return ProfileViewModel(state: state, sync: sync, coordinator: coordinator, apiStatus: APIStatus())
    }

    /// The export button's path: the signed-in account's matches reach the file.
    @Test func exportCarriesTheAccountsMatches() async throws {
        let env = AppEnvironment.test()
        let account = try #require(env.auth.accountID)
        let exercise = MappingFixture.id(9)
        ImportMappingStore(env: env).remember([Self.key: RememberedMatch(exerciseID: exercise, bodyweight: .ignore)],
                                              source: .alphaProgression, account: account, at: Self.date)
        let vm = model(env)
        await vm.export()
        let url = try #require(vm.exported?.url)
        defer { try? FileManager.default.removeItem(at: url) }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let object = try #require(json as? [String: Any])
        let matches = try #require(object["remembered_matches"] as? [[String: Any]])
        #expect(matches.count == 1)
        #expect(matches.first?["exercise_id"] as? String == exercise.uuidString)
        #expect(matches.first?["name"] as? String == "dips")
    }

    /// Demo off: demo's matches go, the account's stay. Demo on: nothing goes.
    @Test func demoEndingForgetsDemosMatches() throws {
        let env = AppEnvironment.test()
        let account = try #require(env.auth.accountID)
        let demo = ImportMappingStore(persistence: env.persistence) { ImportMappingStore.demoAccount }
        let real = ImportMappingStore(env: env)
        demo.remember([Self.key: RememberedMatch(exerciseID: MappingFixture.id(1), bodyweight: nil)],
                      source: .alphaProgression, account: ImportMappingStore.demoAccount, at: Self.date)
        real.remember([Self.key: RememberedMatch(exerciseID: MappingFixture.id(2), bodyweight: nil)],
                      source: .alphaProgression, account: account, at: Self.date)
        let vm = model(env)
        vm.demoModeChanged(true)
        #expect(demo.hasEntries)
        vm.demoModeChanged(false)
        #expect(!demo.hasEntries)
        #expect(real.remembered(source: .alphaProgression)[Self.key]?.exerciseID == MappingFixture.id(2))
    }
}
