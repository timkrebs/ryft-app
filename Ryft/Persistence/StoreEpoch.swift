import os

/// One store for the life of the process: never reused, unlike an object's address (`ObjectIdentifier` of a container
/// that's gone can come back as a new one's). The read models' queue, writers and read contexts are keyed by it.
struct StoreID: Hashable, Sendable {
    private static let next = OSAllocatedUnfairLock(initialState: 0)

    let raw: Int

    static func make() -> StoreID {
        StoreID(raw: next.withLock { n in
            n += 1
            return n
        })
    }
}

/// Which contents of a store are current: bumped by its wipe (sign-out, account change), so work started before it
/// can't write into the next account's store (ADR 0018).
///
/// - The wipe's first step is `advance()`.
/// - The read-model writer saves inside `ifCurrent(batchEpoch)`: the check and the save are one critical section, so a
///   wipe either waits for a save that started before it (and then deletes what it saved) or makes the save drop.
/// - Train's replay, the uploads and every read-model submit compare `current` (`TrainSyncService.Generation`,
///   `ActivityUploader`, `ReadModelDrain.submit`).
///
/// Two locks, always taken in this order: the save gate (`advance()` and `ifCurrent`), then the value. `current` takes
/// only the value, so a reader never waits for a save in progress; main waits for one only in `advance()`, at the wipe.
/// Bodies never await and never hop to the main actor.
final class StoreEpoch: Sendable {
    let store = StoreID.make()
    private let gate = OSAllocatedUnfairLock()
    private let value = OSAllocatedUnfairLock(initialState: 0)

    var current: Int { value.withLock { $0 } }

    /// Waits for a save in progress, then moves on: every `ifCurrent` after it runs nothing for an earlier epoch.
    func advance() {
        gate.withLock {
            value.withLock { $0 += 1 }
        }
    }

    /// Runs `body` while no wipe can start, if the store is still at `epoch`; nil (and `body` never ran) when a wipe
    /// came in between.
    func ifCurrent<R>(_ epoch: Int, _ body: () throws -> R) rethrows -> R? {
        // Unchecked: `body` runs synchronously on this thread under the gate and never escapes it.
        try gate.withLockUnchecked {
            guard current == epoch else { return nil }
            return try body()
        }
    }
}
