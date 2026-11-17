import os

/// Which contents of a store are current: bumped by its wipe (sign-out, account change), so work started before it
/// can't write into the next account's store (ADR 0018).
///
/// - The wipe's first step is `advance()`.
/// - The read-model writer saves inside `ifCurrent(batchEpoch)`: the check and the save are one critical section, so a
///   wipe either waits for a save that started before it (and then deletes what it saved) or makes the save drop.
/// - Train's replay and the uploads compare `current` (`TrainSyncService.Generation`, `ActivityUploader`).
///
/// Bodies never await and never hop to the main actor; main holds the lock only for `advance()`, which waits for at
/// most one writer save.
final class StoreEpoch: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: 0)

    var current: Int { value.withLock { $0 } }

    func advance() {
        value.withLock { $0 += 1 }
    }

    /// Runs `body` while no wipe can start, if the store is still at `epoch`; nil (and `body` never ran) when a wipe
    /// came in between.
    func ifCurrent<R>(_ epoch: Int, _ body: () throws -> R) rethrows -> R? {
        // Unchecked: `body` runs synchronously on this thread under the lock and never escapes it.
        try value.withLockUnchecked { current in
            guard current == epoch else { return nil }
            return try body()
        }
    }
}
