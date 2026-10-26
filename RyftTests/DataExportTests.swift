import Auth
import Foundation
import Testing
import UIKit
@testable import Ryft

/// A folder of the test's own: other tests (and sign-out wipes) sweep the shared temporary folder.
private func makeFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func exportFiles(in folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix(DataExport.filePrefix) }
}

private let emptyArchive = DataExport.Archive(exportedAt: .now, app: "RYFT test", user: nil, days: [], workouts: [], sessions: [],
                                          rememberedMatches: [])

@Suite("Data export: temporary files")
struct DataExportFileTests {
    @Test func removesOnlyExportFiles() throws {
        let folder = try makeFolder()
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
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try DataExport.write(emptyArchive, to: folder)
        #expect(url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(url.lastPathComponent.hasPrefix(DataExport.filePrefix))

        #expect(DataExport.removeFiles(in: folder) == 1)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func theLaunchSweepLeavesWhatThisRunWrote() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let leftover = folder.appendingPathComponent("RYFT-export-2020-01-01.json")
        try Data("{}".utf8).write(to: leftover)
        let mine = try DataExport.write(emptyArchive, to: folder)

        await DataExport.removeLeftoverFiles(in: folder)

        #expect(exportFiles(in: folder) == [mine.lastPathComponent])
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
    }
}

@Suite("Data export: the share sheet")
struct ShareSheetTests {
    /// Mail → Cancel returns to the open sheet, where Save to Files still needs the file.
    @Test func onlyAFinishedActivityOrAClosedSheetIsDone() {
        #expect(ShareSheet.isDone(activity: nil, completed: false))
        #expect(ShareSheet.isDone(activity: .mail, completed: true))
        #expect(!ShareSheet.isDone(activity: .mail, completed: false))
        #expect(!ShareSheet.isDone(activity: .airDrop, completed: false))
    }
}

@Suite("Data export: bound to the account")
@MainActor
struct DataExportAccountTests {
    struct Setup {
        let profile: ProfileViewModel
        let api: MockPlatformAPI
        let client: MockAuthClient
        let auth: AuthService
        let clock: TestClock
        let folder: URL
    }

    private func setup() throws -> Setup {
        let api = MockPlatformAPI()
        let clock = TestClock()
        let client = MockAuthClient(session: .preview())
        let auth = AuthService(client: client, defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard,
                               wipeLocalData: { _ in },
                               deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
        let env = AppEnvironment.test(api: api, clock: clock, auth: auth)
        let state = AppState(env: env)
        let sync = SyncService(env: env)
        let profile = ProfileViewModel(state: state, sync: sync,
                                       coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: clock),
                                       apiStatus: APIStatus())
        let folder = try makeFolder()
        profile.exportFolder = folder
        return Setup(profile: profile, api: api, client: client, auth: auth, clock: clock, folder: folder)
    }

    @Test(.timeLimit(.minutes(1))) func theAccountGetsItsOwnExport() async throws {
        let s = try setup()
        defer { try? FileManager.default.removeItem(at: s.folder) }

        await s.profile.export()

        #expect(s.profile.exportError == nil)
        #expect(s.profile.exported != nil)
        #expect(exportFiles(in: s.folder).count == 1)
    }

    @Test(.timeLimit(.minutes(1))) func anArchiveThatFinishesForAnotherAccountIsDropped() async throws {
        let s = try setup()
        defer { try? FileManager.default.removeItem(at: s.folder) }
        let clock = s.clock
        s.api.beforeMe = { try? await clock.sleep(for: .seconds(1)) }
        let exporting = Task { await s.profile.export() }
        #expect(await eventually { clock.pendingSleeps == 1 })

        let other = UUID()
        s.client.emit(.signedIn, .preview(id: other))
        #expect(await eventually { s.auth.accountID == other.uuidString })
        clock.advance(by: .seconds(1))
        await exporting.value

        #expect(s.profile.exported == nil && s.profile.exportError == nil)
        #expect(exportFiles(in: s.folder).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func anAccountChangeClosesTheSheetAndRemovesTheFile() async throws {
        let s = try setup()
        defer { try? FileManager.default.removeItem(at: s.folder) }
        await s.profile.export()
        #expect(exportFiles(in: s.folder).count == 1)

        s.profile.accountChanged(from: s.auth.accountID)

        #expect(s.profile.exported == nil)
        #expect(exportFiles(in: s.folder).isEmpty)
    }
}

@Suite("Account binding")
@MainActor
struct AccountBindingTests {
    @Test func demoDataIsntTheAccount() {
        let auth = AuthService.preview()
        let live = AppEnvironment.test(auth: auth)
        let demo = AppEnvironment.preview(auth: auth)

        let owner = AccountBinding(live)
        #expect(owner.account == auth.accountID && owner.account != nil && !owner.demo)
        #expect(owner.isCurrent(in: live))
        #expect(!owner.isCurrent(in: demo))
        #expect(AccountBinding(demo).demo)
    }
}
