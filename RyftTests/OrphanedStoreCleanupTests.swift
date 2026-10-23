import Foundation
import Testing
@testable import Ryft

@Suite("Orphaned store: the decision")
struct OrphanedStoreDecisionTests {
    let group = URL(fileURLWithPath: "/var/mobile/Containers/Shared/AppGroup/6B1E", isDirectory: true)
    let appSupport = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/9F2C/Library/Application Support",
                         isDirectory: true)
    var live: URL { group.appendingPathComponent("Library/Application Support/Train.store") }
    var orphan: URL { appSupport.appendingPathComponent("Train.store") }

    @Test func deletesTheAppContainerCopyWhileTheGroupStoreIsOpen() {
        #expect(OrphanedStoreCleanup.decide(live: live, orphan: orphan, groupContainer: group) == .delete)
    }

    @Test func keepsWithoutTheGroupContainer() {
        #expect(OrphanedStoreCleanup.decide(live: live, orphan: orphan, groupContainer: nil) == .keep(.noGroupContainer))
    }

    @Test func keepsWithoutAnOpenStoreFile() throws {
        #expect(OrphanedStoreCleanup.decide(live: nil, orphan: orphan, groupContainer: group) == .keep(.noLiveStore))
        let remote = try #require(URL(string: "https://example.com/Train.store"))
        #expect(OrphanedStoreCleanup.decide(live: remote, orphan: orphan, groupContainer: group) == .keep(.noLiveStore))
    }

    @Test func keepsWhenTheLiveStoreIsTheOldPath() {
        #expect(OrphanedStoreCleanup.decide(live: orphan, orphan: orphan, groupContainer: group) == .keep(.sameAsLive))
        // The same file spelled differently: `/private/var` for `/var`, and `.` and `..` on the way.
        let spelled = URL(fileURLWithPath:
            "/private/var/mobile/Containers/Data/Application/9F2C/Library/./Caches/../Application Support/Train.store")
        #expect(OrphanedStoreCleanup.decide(live: spelled, orphan: orphan, groupContainer: group) == .keep(.sameAsLive))
    }

    @Test func keepsWhenTheLiveStoreIsOutsideTheGroup() {
        // The in-memory fallback's URL.
        let memory = URL(fileURLWithPath: "/dev/null")
        #expect(OrphanedStoreCleanup.decide(live: memory, orphan: orphan, groupContainer: group) == .keep(.liveOutsideGroup))
        // A sibling folder whose name only starts like the group's.
        let sibling = URL(fileURLWithPath: "/var/mobile/Containers/Shared/AppGroup/6B1E2/Library/Application Support/Train.store")
        #expect(OrphanedStoreCleanup.decide(live: sibling, orphan: orphan, groupContainer: group) == .keep(.liveOutsideGroup))
    }

    @Test func keepsWhenTheOldPathIsInsideTheGroup() {
        let inGroup = group.appendingPathComponent("Library/Train.store")
        #expect(OrphanedStoreCleanup.decide(live: live, orphan: inGroup, groupContainer: group) == .keep(.orphanInsideGroup))
    }
}

/// An app container and an App Group container in a temporary folder.
private struct Containers {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("orphaned-store-\(UUID().uuidString)",
                                                                              isDirectory: true)
    var group: URL { root.appendingPathComponent("AppGroup/6B1E", isDirectory: true) }
    var groupStoreFolder: URL { group.appendingPathComponent("Library/Application Support", isDirectory: true) }
    var live: URL { groupStoreFolder.appendingPathComponent("Train.store") }
    var appSupport: URL { root.appendingPathComponent("Application/9F2C/Library/Application Support", isDirectory: true) }

    /// The old store's sizes, as on the iPhone (about 2.2 MB in all).
    static let orphanSizes = ["Train.store": 2_154_496, "Train.store-wal": 32_992, "Train.store-shm": 32_768]

    init() throws {
        try FileManager.default.createDirectory(at: groupStoreFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        for (name, size) in Self.orphanSizes { try write(name, in: appSupport, bytes: size, fill: 0x0A) }
        for name in ["Train.store", "Train.store-wal", "Train.store-shm"] { try write(name, in: groupStoreFolder, bytes: 4096, fill: 0x6C) }
        // Other files in the app container stay.
        try write("Notes.store", in: appSupport, bytes: 10, fill: 0x01)
        try write("readiness.json", in: appSupport, bytes: 10, fill: 0x01)
    }

    func write(_ name: String, in folder: URL, bytes: Int, fill: UInt8) throws {
        try Data(repeating: fill, count: bytes).write(to: folder.appendingPathComponent(name))
    }

    func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    var liveIsIntact: Bool {
        ["Train.store", "Train.store-wal", "Train.store-shm"].allSatisfy { name in
            (try? Data(contentsOf: groupStoreFolder.appendingPathComponent(name))) == Data(repeating: 0x6C, count: 4096)
        }
    }

    var orphanIsIntact: Bool {
        Self.orphanSizes.allSatisfy { name, size in
            (try? Data(contentsOf: appSupport.appendingPathComponent(name)))?.count == size
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@Suite("Orphaned store: files")
struct OrphanedStoreFileTests {
    @Test func removesTheOldFilesAndLeavesTheLiveStore() throws {
        let c = try Containers()
        defer { c.remove() }

        let outcome = OrphanedStoreCleanup.run(live: c.live, orphanFolder: c.appSupport, groupContainer: c.group)

        let bytes = Int64(Containers.orphanSizes.values.reduce(0, +))
        #expect(outcome == OrphanedStoreCleanup.Outcome(decision: .delete, files: 3, bytes: bytes, failures: 0))
        #expect(outcome.finished)
        #expect(c.names(in: c.appSupport) == ["Notes.store", "readiness.json"])
        #expect(c.liveIsIntact)
    }

    @Test func runningAgainIsHarmless() throws {
        let c = try Containers()
        defer { c.remove() }
        _ = OrphanedStoreCleanup.run(live: c.live, orphanFolder: c.appSupport, groupContainer: c.group)

        let again = OrphanedStoreCleanup.run(live: c.live, orphanFolder: c.appSupport, groupContainer: c.group)

        #expect(again == OrphanedStoreCleanup.Outcome(decision: .delete))
        #expect(again.finished)
        #expect(c.names(in: c.appSupport) == ["Notes.store", "readiness.json"])
        #expect(c.liveIsIntact)
    }

    @Test func alsoRemovesAFallbackStoreOnDisk() throws {
        let c = try Containers()
        defer { c.remove() }
        try c.write("TrainFallback.store", in: c.appSupport, bytes: 100, fill: 0x02)

        let outcome = OrphanedStoreCleanup.run(live: c.live, orphanFolder: c.appSupport, groupContainer: c.group)

        #expect(outcome.files == 4)
        #expect(c.names(in: c.appSupport) == ["Notes.store", "readiness.json"])
    }

    @Test func deletesNothingWithoutTheGroupContainer() throws {
        let c = try Containers()
        defer { c.remove() }

        let outcome = OrphanedStoreCleanup.run(live: c.live, orphanFolder: c.appSupport, groupContainer: nil)

        #expect(outcome == OrphanedStoreCleanup.Outcome(decision: .keep(.noGroupContainer)))
        #expect(!outcome.finished)
        #expect(c.orphanIsIntact)
        #expect(c.liveIsIntact)
    }

    @Test func deletesNothingWhenThePathsAreEqual() throws {
        let c = try Containers()
        defer { c.remove() }
        // The store opened in the app container (as after a move to `groupContainer: .none`).
        let live = c.appSupport.appendingPathComponent("Train.store")

        let outcome = OrphanedStoreCleanup.run(live: live, orphanFolder: c.appSupport, groupContainer: c.group)

        #expect(outcome == OrphanedStoreCleanup.Outcome(decision: .keep(.sameAsLive)))
        #expect(c.orphanIsIntact)
    }

    @Test func deletesNothingWhenTheOldFolderLinksToTheLiveOne() throws {
        let c = try Containers()
        defer { c.remove() }
        let link = c.root.appendingPathComponent("Application/LINK", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: c.groupStoreFolder)

        let outcome = OrphanedStoreCleanup.run(live: c.live, orphanFolder: link, groupContainer: c.group)

        #expect(outcome.decision != .delete)
        #expect(outcome.files == 0)
        #expect(c.liveIsIntact)
    }

    @Test func deletesNothingWhenTheLiveFolderCantBeCompared() throws {
        let c = try Containers()
        defer { c.remove() }
        // Inside the group by path, but not on disk: whether it's the old folder can't be ruled out.
        let missing = c.group.appendingPathComponent("Missing/Train.store")

        let outcome = OrphanedStoreCleanup.run(live: missing, orphanFolder: c.appSupport, groupContainer: c.group)

        #expect(outcome == OrphanedStoreCleanup.Outcome(decision: .keep(.sameFolder)))
        #expect(c.orphanIsIntact)
    }

    @Test func nothingThereIsFinished() throws {
        let c = try Containers()
        defer { c.remove() }
        let empty = c.root.appendingPathComponent("Fresh/Library/Application Support", isDirectory: true)

        let outcome = OrphanedStoreCleanup.run(live: c.live, orphanFolder: empty, groupContainer: c.group)

        #expect(outcome == OrphanedStoreCleanup.Outcome(decision: .delete))
        #expect(outcome.finished)
    }
}

@Suite("Orphaned store: once per install")
struct OrphanedStoreOnceTests {
    @Test func runsOnceThenNeverAgain() async throws {
        let c = try Containers()
        defer { c.remove() }
        let defaults = try #require(UserDefaults(suiteName: "ryft.test.orphan.\(UUID().uuidString)"))
        let at = OrphanedStoreCleanup.Locations(orphanFolder: c.appSupport, groupContainer: c.group)

        let first = await OrphanedStoreCleanup.runOnce(live: c.live, defaults: defaults) { at }
        #expect(first?.files == 3)
        #expect(defaults.bool(forKey: OrphanedStoreCleanup.doneKey))

        // Whatever appears there later isn't this cleanup's business any more.
        try c.write("Train.store", in: c.appSupport, bytes: 10, fill: 0x03)
        let second = await OrphanedStoreCleanup.runOnce(live: c.live, defaults: defaults) { at }
        #expect(second == nil)
        #expect(c.names(in: c.appSupport).contains("Train.store"))
    }

    @Test func inDoubtItRunsAgainAtTheNextLaunch() async throws {
        let c = try Containers()
        defer { c.remove() }
        let defaults = try #require(UserDefaults(suiteName: "ryft.test.orphan.\(UUID().uuidString)"))
        let orphanFolder = c.appSupport, group = c.group

        let locked = await OrphanedStoreCleanup.runOnce(live: nil, defaults: defaults) {
            .init(orphanFolder: orphanFolder, groupContainer: group)
        }
        #expect(locked?.decision == .keep(.noLiveStore))
        #expect(!defaults.bool(forKey: OrphanedStoreCleanup.doneKey))
        #expect(c.orphanIsIntact)

        let unlocked = await OrphanedStoreCleanup.runOnce(live: c.live, defaults: defaults) {
            .init(orphanFolder: orphanFolder, groupContainer: group)
        }
        #expect(unlocked?.files == 3)
        #expect(defaults.bool(forKey: OrphanedStoreCleanup.doneKey))
    }
}

@Suite("Data export: temporary files")
struct DataExportFileTests {
    @Test func removesOnlyExportFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // (The simulator's file system ignores case, so no lower-case twin.)
        let names = ["RYFT-export-2026-10-22.json", "RYFT-export-2026-10-23.json", "RYFT-export-notes.txt", "other.json",
                     "RYFT-export-2026-10-24.jsonl"]
        for name in names { try Data("{}".utf8).write(to: folder.appendingPathComponent(name)) }

        #expect(DataExport.removeFiles(in: folder) == 2)
        let left = try Set(FileManager.default.contentsOfDirectory(atPath: folder.path))
        #expect(left == ["RYFT-export-notes.txt", "other.json", "RYFT-export-2026-10-24.jsonl"])
        #expect(DataExport.removeFiles(in: folder) == 0)
    }

    @Test func aWrittenExportIsRemoved() throws {
        let archive = DataExport.Archive(exportedAt: .now, app: "RYFT test", user: nil, days: [], workouts: [], sessions: [])
        let url = try DataExport.write(archive)
        #expect(url.lastPathComponent.hasPrefix(DataExport.filePrefix))

        DataExport.removeFiles(in: url.deletingLastPathComponent())

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
