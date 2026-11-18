import Foundation
import SwiftData
@testable import Ryft

// Shared by the P1b suites (docs/work/2026-11-18-ios17-demo-exit/design.md §9): the account's store on disk, and an
// environment whose Demo data switch is its own setting, never `Settings.shared` (the test host's). Synthetic values
// only.

/// A store on disk in a folder of its own, removed afterwards.
final class DemoExitDisk {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ryft-p1b-\(UUID().uuidString)")
    var url: URL { folder.appendingPathComponent("Train.store") }

    init() throws { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

    deinit { try? FileManager.default.removeItem(at: folder) }
}

/// An app graph on `persistence` with a Demo data switch of its own (`settings.demoMode`), as the live one has: the
/// Repository's first read in demo makes the demo's store.
@MainActor
struct DemoExitGraph {
    let defaults: UserDefaults
    let settings: Settings
    let api: MockPlatformAPI
    let env: AppEnvironment
    let state: AppState

    init(persistence: Persistence, demo: Bool, clock: TestClock = TestClock(now: Date(timeIntervalSince1970: 1_794_000_000)),
         auth: AuthService? = nil) throws {
        defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        settings = Settings(defaults: defaults)
        settings.demoMode = demo
        api = MockPlatformAPI()
        api.now = { clock.now() }
        env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: api, demoAPI: api,
                             auth: auth ?? .preview(), persistence: persistence, clock: clock, notifier: MockNotifier(),
                             flags: StaticFlags([:]), connectivity: .preview(online: true), defaults: defaults,
                             demoOverride: nil)
        env.reads.random = { $0.lowerBound }
        env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
        state = AppState(env: env)
        // A graph that follows a Demo data switch shares the widget's file; this one's writes are nobody's.
        state.repository.widgetFile = nil
    }

    var repository: Repository { state.repository }
}

extension TrainStore {
    /// Rows of `T` a fresh context on the container finds: what the store has, not a context's pending ones.
    func stored<T: PersistentModel>(_ type: T.Type, where predicate: Predicate<T>? = nil) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<T>(predicate: predicate))
    }
}
