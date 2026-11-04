import Foundation
import Testing
@testable import Ryft

/// Reading picked and opened files (design §9): the size cap before and during the read, the reasons, and that a copy
/// in the app's own container is deleted once read while the user's own file is never touched.
@Suite("Import file access")
struct ImportFileAccessTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("import-access-\(UUID().uuidString)",
                                                                                  isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ name: String, _ data: Data, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? directory).appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    @Test func readsIntoMemoryAndLeavesTheFile() async throws {
        let url = try write("plans.csv", ImportMockData.plans)
        let loaded = await ImportFileAccess.load([url], owned: [])
        #expect(loaded.first?.name == "plans.csv")
        #expect(loaded.first?.file?.data == ImportMockData.plans)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// Over the cap: refused from its size, before reading.
    @Test func refusedOverTheCap() async throws {
        let url = try write("big.csv", Data(repeating: 0x41, count: 2_000))
        var limits = ImportLimits.standard
        limits.maxFileBytes = 1_000
        let loaded = await ImportFileAccess.load([url], limits: limits, owned: [])
        #expect(loaded.first?.result == .failure(.tooLarge))
    }

    /// While reading: at most cap + 1 bytes are read, so a file that grew is refused too.
    @Test func theReadStopsAfterTheCap() throws {
        let url = try write("grown.csv", Data(repeating: 0x41, count: 5_000))
        #expect(ImportFileAccess.readCapped(url, cap: 4_999) == .failure(.tooLarge))
        #expect(ImportFileAccess.readCapped(url, cap: 5_000) == .success(Data(repeating: 0x41, count: 5_000)))
    }

    @Test func reasons() async throws {
        let empty = try write("blank.csv", Data())
        let image = try write("photo.png", Data([0x89, 0x50, 0x4E, 0x47]))
        let missing = directory.appendingPathComponent("gone.csv")
        let loaded = await ImportFileAccess.load([empty, image, missing], owned: [])
        #expect(loaded.map(\.result) == [.failure(.empty), .failure(.notText), .failure(.unreadable)])
    }

    /// A copy iOS put in the app's own container (an Inbox copy) goes once read; a file elsewhere stays.
    @Test func anInboxCopyIsDeleted() async throws {
        let inbox = directory.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let copy = try write("workouts.csv", ImportMockData.workouts, in: inbox)
        let own = try write("plans.csv", ImportMockData.plans)
        let loaded = await ImportFileAccess.load([copy, own], owned: [inbox])
        #expect(loaded.compactMap(\.file).count == 2)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(FileManager.default.fileExists(atPath: own.path))
    }

    @Test func insideComparesResolvedPaths() {
        let base = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application/X/Documents/Inbox")
        #expect(ImportFileAccess.isInside(base.appendingPathComponent("a.csv"), [base]))
        #expect(!ImportFileAccess.isInside(URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application/X/Documents/Inbox2/a.csv"),
                                           [base]))
    }

    /// The flow's reasons for each refusal (ui.md P3 to P6, D5).
    @Test func problemsMapToTheFlowsReasons() {
        #expect(ImportFileProblem(.notText) == .notCSV)
        #expect(ImportFileProblem(ImportFileAccess.Problem.tooLarge) == .tooLarge)
        #expect(ImportFileProblem(ImportError.unsupportedEncoding) == .notCSV)
        #expect(ImportFileProblem(ImportError.notRecognised) == .notSupported)
        #expect(ImportFileProblem(ImportError.empty) == .empty)
        #expect(!ImportFileProblem.notSupported.isPickProblem)
    }
}
