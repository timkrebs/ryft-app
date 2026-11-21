import Foundation
@testable import Ryft

extension TrainLibrary {
    /// A library on `store` whose outbox (#126: a custom exercise's `POST` is queued there) is its own, on the same store and
    /// the same platform: demo data's binding, an open gate, no network monitor, as `TrainSyncService.preview` has them. For
    /// tests that build a library by hand; one that checks what the outbox sends builds its service itself. `defaults`: where
    /// it remembers a paused plan, a suite of its own unless the test hands one in (`UserDefaults.isolated`).
    static func testing(store: TrainStore, remote: @escaping () -> TrainDataSource, restore: Bool,
                        defaults: UserDefaults = .isolated()) -> TrainLibrary {
        let outbox = TrainSyncService(store: store, remote: remote, owner: { TrainSyncService.demoOwner }, monitorsNetwork: false)
        outbox.gate = { _ in nil }
        return TrainLibrary(store: store, remote: remote, outbox: { outbox }, restore: restore, defaults: defaults)
    }
}

extension UserDefaults {
    /// A suite of its own for one test's library, with `pausedPlan` remembered as paused (`train.pausedPlanID`; nil: none).
    /// The Unit plan runs suites side by side, so a test never shares `UserDefaults.standard`'s paused plan with another, and
    /// has nothing to put back.
    static func isolated(pausedPlan: UUID? = nil) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "test-" + UUID().uuidString)!
        if let pausedPlan { defaults.set(pausedPlan.uuidString, forKey: "train.pausedPlanID") }
        return defaults
    }
}
