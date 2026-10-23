import Foundation
import OSLog

/// The copy of the SwiftData store that builds from before the App Group left in the app's own container.
///
/// `TrainStore` keeps the account's read models, logged sessions and pending Train uploads in a store named
/// "Train" with `groupContainer: .automatic`. Since the app has the `group.dev.timkrebs.ryft` entitlement, SwiftData
/// opens `<group>/Library/Application Support/Train.store`. Earlier builds wrote the same name into the app
/// container's Application Support. That copy holds whichever account was signed in then, and `TrainStore.wipe()`
/// (sign-out, account deletion) never reaches it.
///
/// When the group container has no store yet, SwiftData copies the app container's into it as it opens (seen on the
/// simulator, 2026-10-23). That's how the first launch with the entitlement carried the data over, and how a copy left
/// behind could come back. So this runs after the container opened, never before: on an update straight from a build
/// without the App Group, the old copy is the account's current data until SwiftData has copied it.
///
/// It's deleted only when it provably isn't the live store: the group container resolves, the open store is a file
/// inside it, and the old files are somewhere else (by path, and by folder identity on disk). In any doubt nothing is
/// deleted and the next launch decides again. Once nothing is left, a marker ends it.
enum OrphanedStoreCleanup {
    /// Set once the old files are gone, or there never were any.
    static let doneKey = "cleanup.appContainerStore"
    static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "storage")

    /// The old store as SwiftData (SQLite in WAL mode) writes it: the database, its write-ahead log and the
    /// shared-memory index. "TrainFallback" has always been in memory (`isStoredInMemoryOnly`, so never a file);
    /// it's checked anyway.
    static let fileNames: [String] = ["Train", "TrainFallback"].flatMap { name in
        ["", "-wal", "-shm"].map { "\(name).store\($0)" }
    }

    enum Decision: Equatable, Sendable {
        case delete
        case keep(Doubt)
    }

    /// Why nothing is deleted.
    enum Doubt: String, Sendable {
        /// The App Group container doesn't resolve (a build without the entitlement).
        case noGroupContainer
        /// No store file is open: the in-memory fallback (`TrainStore.init`), e.g. before the first unlock.
        case noLiveStore
        /// The open store is at the old path itself, as after a move to `groupContainer: .none`.
        case sameAsLive
        /// The open store isn't inside the group container.
        case liveOutsideGroup
        /// The old path is inside the group container.
        case orphanInsideGroup
        /// The old folder is the open store's folder on disk (a link), or that couldn't be ruled out.
        case sameFolder
    }

    /// Pure: whether the store file at `orphan` may be deleted while `live` is the open one. `groupContainer` is the
    /// App Group's container, `nil` when it doesn't resolve.
    static func decide(live: URL?, orphan: URL, groupContainer: URL?) -> Decision {
        guard let groupContainer else { return .keep(.noGroupContainer) }
        guard let live, live.isFileURL else { return .keep(.noLiveStore) }
        let group = components(groupContainer), livePath = components(live), orphanPath = components(orphan)
        guard livePath != orphanPath else { return .keep(.sameAsLive) }
        guard isInside(livePath, group) else { return .keep(.liveOutsideGroup) }
        guard !isInside(orphanPath, group) else { return .keep(.orphanInsideGroup) }
        return .delete
    }

    /// Path components with `.`, `..` and links resolved. `/var` and `/tmp` link into `/private`, and Foundation drops
    /// `/private` only from paths that exist, so it's always dropped here.
    static func components(_ url: URL) -> [String] {
        var parts = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        if parts.count > 2, parts[0] == "/", parts[1] == "private" { parts.remove(at: 1) }
        return parts
    }

    private static func isInside(_ path: [String], _ folder: [String]) -> Bool {
        path.count > folder.count && Array(path.prefix(folder.count)) == folder
    }

    struct Outcome: Equatable, Sendable {
        var decision: Decision
        /// Files removed, and their size.
        var files = 0
        var bytes: Int64 = 0
        /// Files that couldn't be removed.
        var failures = 0

        /// Nothing of the old store is left: it needn't run again.
        var finished: Bool { decision == .delete && failures == 0 }
    }

    /// Deletes the old store's files in `orphanFolder` when `decide` allows it and that folder isn't the open store's
    /// folder on disk. Running it again is harmless.
    static func run(live: URL?, orphanFolder: URL, groupContainer: URL?) -> Outcome {
        let orphan = orphanFolder.appendingPathComponent("Train.store")
        var outcome = Outcome(decision: decide(live: live, orphan: orphan, groupContainer: groupContainer))
        guard outcome.decision == .delete, let live else { return outcome }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: orphanFolder.path) else { return outcome }
        // Paths can be spelled differently; the folders' identities on disk can't.
        guard let liveFolder = identity(of: live.deletingLastPathComponent()), let oldFolder = identity(of: orphanFolder),
              !liveFolder.isEqual(oldFolder) else {
            outcome.decision = .keep(.sameFolder)
            return outcome
        }
        for name in fileNames {
            let file = orphanFolder.appendingPathComponent(name)
            // The item itself (a link isn't followed), and nothing to do when it isn't there.
            guard let attributes = try? fileManager.attributesOfItem(atPath: file.path) else { continue }
            do {
                try fileManager.removeItem(at: file)
                outcome.files += 1
                outcome.bytes += (attributes[.size] as? NSNumber)?.int64Value ?? 0
            } catch {
                outcome.failures += 1
                let e = error as NSError
                log.error("Removing an old store file failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            }
        }
        return outcome
    }

    private static func identity(of folder: URL) -> (any NSObjectProtocol)? {
        // A fresh URL: resource values are cached per instance.
        let url = URL(fileURLWithPath: folder.path, isDirectory: true)
        return (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
    }

    struct Locations: Sendable {
        /// Where builds before the App Group kept the store: the app container's Application Support.
        var orphanFolder: URL
        var groupContainer: URL?

        static func current() -> Locations {
            Locations(orphanFolder: .applicationSupportDirectory,
                      groupContainer: FileManager.default.containerURL(
                          forSecurityApplicationGroupIdentifier: ReadinessSnapshot.appGroup))
        }
    }

    /// At launch, off the main actor; `live` is the open store's file (`TrainStore.storeURL`). Once per install, or
    /// again at the next launch while in doubt.
    @concurrent
    @discardableResult
    static func runOnce(live: URL?, defaults: UserDefaults = .standard,
                        locations: @Sendable () -> Locations = { .current() }) async -> Outcome? {
        guard !defaults.bool(forKey: doneKey) else { return nil }
        let signpost = Signposts.launch.beginInterval("orphaned-store", id: Signposts.launch.makeSignpostID())
        let at = locations()
        let outcome = run(live: live, orphanFolder: at.orphanFolder, groupContainer: at.groupContainer)
        Signposts.launch.endInterval("orphaned-store", signpost, "\(outcome.files) files")
        switch outcome.decision {
        case .keep(let doubt):
            log.info("Old store in the app container kept: \(doubt.rawValue, privacy: .public)")
        case .delete where outcome.files + outcome.failures > 0:
            log.notice("""
                Removed the store left behind by the App Group move: \(outcome.files, privacy: .public) files, \
                \(outcome.bytes, privacy: .public) bytes, \(outcome.failures, privacy: .public) failed
                """)
        case .delete:
            break
        }
        if outcome.finished { defaults.set(true, forKey: doneKey) }
        return outcome
    }
}
