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
/// inside it, and the old files are somewhere else: by path, and separately by the folders' identities on disk, links
/// followed. In any doubt nothing is deleted and the next launch decides again. Once nothing is left, a marker ends it.
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
        /// Files (and the empty support folder) removed, and their size.
        var files = 0
        var bytes: Int64 = 0
        /// Items of the old store still there: not removable, unreadable, or a support folder with files in it.
        var failures = 0

        /// Nothing of the old store is left: it needn't run again.
        var finished: Bool { decision == .delete && failures == 0 }
    }

    /// Core Data's folder beside a store for data kept outside it. No model has external storage, so it's at most
    /// empty folders; with files in it, it stays (and counts as left over).
    static let supportFolderName = ".Train_SUPPORT"

    /// Deletes the old store's files in `orphanFolder` when `decide` allows it and that folder isn't the open store's
    /// folder on disk. Running it again is harmless. `identity` is a folder's identity on disk (`identity(of:)`).
    static func run(live: URL?, orphanFolder: URL, groupContainer: URL?,
                    identity: (URL) -> AnyHashable? = identity(of:)) -> Outcome {
        let orphan = orphanFolder.appendingPathComponent("Train.store")
        var outcome = Outcome(decision: decide(live: live, orphan: orphan, groupContainer: groupContainer))
        guard outcome.decision == .delete, let live else { return outcome }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: orphanFolder.path) else { return outcome }
        // A second check that doesn't depend on `decide`'s paths: the folders themselves, links followed.
        guard let liveFolder = identity(live.deletingLastPathComponent()), let oldFolder = identity(orphanFolder),
              liveFolder != oldFolder else {
            outcome.decision = .keep(.sameFolder)
            return outcome
        }

        func failed(_ error: Error) {
            outcome.failures += 1
            let e = error as NSError
            log.error("Removing an old store file failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
        }
        /// The item itself (a link isn't followed); `nil` when it isn't there, or when it can't be read (a failure).
        func attributes(_ item: URL) -> [FileAttributeKey: Any]? {
            do {
                return try fileManager.attributesOfItem(atPath: item.path)
            } catch {
                if !isMissing(error) { failed(error) }
                return nil
            }
        }

        for name in fileNames {
            let file = orphanFolder.appendingPathComponent(name)
            guard let found = attributes(file) else { continue }
            do {
                try fileManager.removeItem(at: file)
                outcome.files += 1
                outcome.bytes += (found[.size] as? NSNumber)?.int64Value ?? 0
            } catch {
                failed(error)
            }
        }

        let support = orphanFolder.appendingPathComponent(supportFolderName, isDirectory: true)
        if let found = attributes(support) {
            if found[.type] as? FileAttributeType == .typeDirectory, holdsOnlyFolders(support) {
                do {
                    try fileManager.removeItem(at: support)
                    outcome.files += 1
                } catch {
                    failed(error)
                }
            } else {
                outcome.failures += 1
                log.error("The old store's support folder holds files: kept")
            }
        }
        return outcome
    }

    /// Whether `error` says the item doesn't exist (and nothing else, e.g. no permission to look).
    static func isMissing(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain, e.code == NSFileReadNoSuchFileError || e.code == NSFileNoSuchFileError { return true }
        if e.domain == NSPOSIXErrorDomain, e.code == Int(ENOENT) { return true }
        return (e.userInfo[NSUnderlyingErrorKey] as? NSError).map(isMissing) ?? false
    }

    /// Only (empty) folders below `folder`; a link counts as a file, and so does anything that can't be read.
    private static func holdsOnlyFolders(_ folder: URL) -> Bool {
        var unreadable = false
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                         errorHandler: { _, _ in
                                                             unreadable = true
                                                             return false
                                                         }) else { return false }
        for case let item as URL in items where (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true {
            return false
        }
        return !unreadable
    }

    /// A folder's identity on disk, links followed: two spellings of one folder (a link to it, `/private/var` for
    /// `/var`) have the same. `nil` when it can't be read.
    static func identity(of folder: URL) -> AnyHashable? {
        // A fresh URL (resource values are cached per instance), resolved first: a link's own identifier is the
        // link's, not its target's.
        let url = URL(fileURLWithPath: folder.resolvingSymlinksInPath().path, isDirectory: true)
        let id = (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
        return (id as? NSObject).map(AnyHashable.init)
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
