import Foundation
import OSLog

/// What a launch does about an owed wipe, the launch table of design.md §4. Pure, so the table is tested as a table.
enum WipeResume: Equatable {
    /// The stored session's rows are live: the entry ends, and nothing is wiped.
    case forget
    /// Replace the files, then nothing but ending the entry.
    case scrub
    /// Replace the files, then run the wipe before anything is published.
    case wipeNow(narrow: Bool, endSession: Bool)
    /// Keep the files: parked rows are the only copy of unsent work, so the object wipe runs after the first frame.
    case wipeAfterFirstFrame(endSession: Bool)

    /// `stored`: the stored session's account.
    static func decide(_ owed: OwedWipe, stored: String?, now: Date) -> WipeResume {
        if owed.scrubOnly { return stored == nil ? .scrub : .forget }
        let own = stored != nil && stored == owed.wipe.account
        if own, owed.publishedOver || (!owed.endsOwnSession && owed.wipe.reason?.isDeletion != true) { return .forget }
        let another = stored != nil && !own
        if owed.wipe.parking == nil { return .wipeNow(narrow: false, endSession: own) }
        if another || isPastParkingLimit(owed, now: now) { return .wipeNow(narrow: true, endSession: own) }
        return .wipeAfterFirstFrame(endSession: own)
    }

    /// Only past the limit: a clock behind `since` doesn't expire anything.
    static func isPastParkingLimit(_ owed: OwedWipe, now: Date) -> Bool {
        now > owed.since.addingTimeInterval(ActivityStore.parkingLimit)
    }
}

/// Removes the store's files before the container opens. It's the only code that deletes a live store, so it runs on
/// nothing but an entry `AuthService` resolved at this launch, and never over rows that are parked within their limit.
/// A replace doesn't depend on the delete that failed, and takes the WAL, free pages and history with it. The wipe still
/// runs afterwards: a file that couldn't go, or a copy SwiftData brought back, is caught there.
enum StoreReset {
    struct Outcome: Equatable, Sendable {
        var replaced = false
        /// The store's own files and support folder.
        var files = 0
        var failures = 0
        /// The app container's copy; nil when nothing was replaced.
        var orphan: OrphanedStoreCleanup.Outcome?

        /// Something of the store is still on disk.
        var leftFiles: Bool { failures > 0 || (orphan?.failures ?? 0) > 0 }
    }

    /// Whether `entry` may take the files.
    static func replaces(_ entry: OwedWipe?, now: Date) -> Bool {
        guard let entry else { return false }
        return entry.scrubOnly || entry.wipe.parking == nil || WipeResume.isPastParkingLimit(entry, now: now)
    }

    /// Removes `store`, its `-wal`, `-shm` and support folder, then the app container's copy through
    /// `OrphanedStoreCleanup`: SwiftData would copy that one into the empty group container as it opens.
    @discardableResult
    static func run(entry: OwedWipe?, store: URL, orphans: OrphanedStoreCleanup.Locations, now: Date) -> Outcome {
        var outcome = Outcome()
        guard replaces(entry, now: now) else { return outcome }
        // The name too: only the app's store file, never the `/dev/null` of a store in memory.
        guard store.isFileURL, store.lastPathComponent == "Train.store" else {
            OrphanedStoreCleanup.log.error("Store reset refused: that isn't the store's file")
            return outcome
        }
        let signpost = Signposts.launch.beginInterval("store-reset", id: Signposts.launch.makeSignpostID())
        defer { Signposts.launch.endInterval("store-reset", signpost, "\(outcome.files) files") }
        outcome.replaced = true
        let folder = store.deletingLastPathComponent()
        let names = OrphanedStoreCleanup.fileNames + [OrphanedStoreCleanup.supportFolderName]
        for name in names {
            do {
                try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
                outcome.files += 1
            } catch where OrphanedStoreCleanup.isMissing(error) {
                // Nothing to remove.
            } catch {
                outcome.failures += 1
                let e = error as NSError
                OrphanedStoreCleanup.log.error("Replacing a store file failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            }
        }
        outcome.orphan = OrphanedStoreCleanup.run(live: store, orphanFolder: orphans.orphanFolder,
                                                  groupContainer: orphans.groupContainer)
        return outcome
    }
}
