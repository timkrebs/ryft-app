import Foundation
import Testing
@testable import Ryft

/// One import flow for the app (ui.md §2, §3): the entry points behind `train.import`, and "Open in" routed by what
/// the app is doing (E5 to E10). The system share sheet isn't UI-tested; these call the same handler with a file URL.
@MainActor
@Suite("Import coordinator")
struct ImportCoordinatorTests {
    final class Opened {
        var routes: [TrainRoute] = []
        var strainShown = 0
    }

    let opened = Opened()
    let library = TrainLibrary.preview(store: TrainStore(inMemory: true), enrolled: false)

    func coordinator(_ env: AppEnvironment) -> ImportCoordinator {
        ImportCoordinator(env: env, library: library, uploader: TrainImportUploader(env: env),
                          showStrain: { [opened] in opened.strainShown += 1 },
                          openRoute: { [opened] in opened.routes.append($0) })
    }

    /// A CSV the import reads, in the temporary directory (read, then removed as an app-owned copy).
    func csv(_ data: Data = ImportMockData.plans) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("open-in-\(UUID().uuidString).csv")
        try data.write(to: url)
        return url
    }

    @Test func entryPointsFollowTheFlag() {
        let off = coordinator(.test())
        #expect(!off.isEnabled)
        off.start()
        #expect(off.flow == nil)
        let on = coordinator(.test(flags: [.trainImport: true]))
        on.start()
        #expect(on.flow?.step == .pick)
    }

    /// E10: the flag off: a calm sheet, nothing read.
    @Test func openInWithTheFlagOff() async throws {
        let importer = coordinator(.test())
        let url = try csv()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await importer.open([url]))
        #expect(importer.showsUnavailable)
        #expect(importer.flow == nil)
        #expect(FileManager.default.fileExists(atPath: url.path)) // not read, not removed
    }

    @Test func notAFileIsntOurs() async throws {
        let importer = coordinator(.test(flags: [.trainImport: true]))
        let link = try #require(URL(string: "ryft://train/history"))
        #expect(await importer.open([link]) == false)
    }

    /// E5: Strain shows, the cover opens at step 2 with the file read.
    @Test func openInLandsOnStepTwo() async throws {
        let importer = coordinator(.test(flags: [.trainImport: true]))
        let url = try csv()
        #expect(await importer.open([url]))
        #expect(opened.strainShown == 1)
        #expect(importer.flow?.path == [.detected])
        #expect(importer.flow?.detection.isPlanOnly == true)
    }

    /// E6: signed out, the file waits in memory; after sign-in the flow opens with it.
    @Test func signedOutFileWaitsForTheSignIn() async throws {
        let auth = AuthService.preview(signedIn: false)
        let env = AppEnvironment.test(auth: auth, flags: [.trainImport: true])
        let importer = coordinator(env)
        let url = try csv()
        #expect(await importer.open([url]))
        #expect(importer.flow == nil)
        #expect(importer.hasFileForSignIn)
        #expect(await auth.logIn(email: "tim@example.com", password: "secret"))
        await importer.accountChanged(signedIn: true)
        #expect(importer.flow?.path == [.detected])
        #expect(!importer.hasFileForSignIn)
    }

    /// E7: never over a workout; "Open now" once it's finished.
    @Test func aWorkoutKeepsTheFileWaiting() async throws {
        let importer = coordinator(.test(flags: [.trainImport: true]))
        var workout = true
        importer.isWorkoutActive = { workout }
        let url = try csv()
        await importer.open([url])
        #expect(importer.flow == nil)
        #expect(importer.waitingFor == .workout)
        #expect(importer.waitingFileName?.hasSuffix(".csv") == true)
        #expect(!importer.canOpenWaitingFile)
        workout = false
        #expect(importer.canOpenWaitingFile)
        await importer.openWaitingFile()
        #expect(importer.flow?.path == [.detected])
        #expect(importer.waitingFileName == nil)
    }

    /// E8: another import is being set up: Replace starts over with the new file, Keep current drops it.
    @Test func replaceOrKeepTheImportBeingSetUp() async throws {
        let importer = coordinator(.test(flags: [.trainImport: true]))
        importer.start()
        let first = try #require(importer.flow)
        let url = try csv(ImportMockData.workouts)
        await importer.open([url])
        #expect(importer.replacement != nil)
        #expect(importer.flow === first)
        importer.keepCurrent()
        #expect(importer.replacement == nil && importer.flow === first)
        let again = try csv(ImportMockData.workouts)
        await importer.open([again])
        await importer.replaceCurrent()
        #expect(importer.flow !== first)
        #expect(importer.flow?.detection.isWorkoutsOnly == true)
    }

    /// Open plan and Open history close the cover onto Strain.
    @Test func finishingOpensStrain() throws {
        let importer = coordinator(.test(flags: [.trainImport: true]))
        importer.start()
        let id = UUID()
        importer.flow?.finish(.openPlan(id))
        #expect(importer.flow == nil)
        importer.start()
        importer.flow?.finish(.openHistory)
        importer.start()
        importer.flow?.finish(.close)
        #expect(opened.routes == [.plan(id), .history])
    }

    /// Signing out (or another account) forgets the flow and any waiting file.
    @Test func anAccountChangeForgetsTheFlow() async throws {
        let importer = coordinator(.test(flags: [.trainImport: true]))
        importer.start()
        await importer.accountChanged(signedIn: false)
        #expect(importer.flow == nil)
    }

    /// `train.import` is a key the platform accepts, dark by default, and on only in a Debug demo.
    @Test func theFlag() {
        #expect(FeatureFlag.trainImport.rawValue == "train.import")
        #expect(!FeatureFlag.trainImport.compiledDefault)
        #if DEBUG
        #expect(MockPlatformAPI.demoFlags["train.import"] == true)
        #else
        #expect(MockPlatformAPI.demoFlags["train.import"] == nil)
        #endif
    }
}
