import Foundation
@testable import Ryft

extension TrainLibrary {
    /// A library on `store` whose outbox (#126: a custom exercise's `POST` is queued there) is its own, on the same store and
    /// the same platform: demo data's binding, an open gate, no network monitor, as `TrainSyncService.preview` has them. For
    /// tests that build a library by hand; one that checks what the outbox sends builds its service itself.
    static func testing(store: TrainStore, remote: @escaping () -> TrainDataSource, restore: Bool) -> TrainLibrary {
        let outbox = TrainSyncService(store: store, remote: remote, owner: { TrainSyncService.demoOwner }, monitorsNetwork: false)
        outbox.gate = { _ in nil }
        return TrainLibrary(store: store, remote: remote, outbox: { outbox }, restore: restore)
    }
}
