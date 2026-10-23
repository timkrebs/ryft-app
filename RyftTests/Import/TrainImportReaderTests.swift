import Foundation
import Testing
@testable import Ryft

@Suite("Import reader")
struct TrainImportReaderTests {
    @Test func plansAndWorkoutsMerge() async throws {
        let files = try [ImportFixture.file("ap-plans"), ImportFixture.file("ap-workouts")]
        let bundle = try await TrainImportReader.read(files)
        #expect(bundle.format == .alphaProgression)
        #expect(bundle.plans.count == 1)
        #expect(bundle.sessions.count == 6)
        #expect(bundle.plans.first?.source == SourceLine(file: 0, line: 1))
        #expect(bundle.sessions.map(\.source.file) == [1, 1, 1, 1, 1, 1])
        #expect(bundle.lineCount == 95)
        #expect(bundle.warnings.isEmpty)
    }

    @Test func theSameWorkoutInTwoFilesIsKeptOnce() async throws {
        let files = try [ImportFixture.file("ap-workouts"), ImportFixture.file("ap-workouts-plus1")]
        let bundle = try await TrainImportReader.read(files)
        #expect(bundle.sessions.count == 7)
        #expect(bundle.sessions.last?.start.key == "2026-03-18T18:00")
        #expect(bundle.sessions.last?.source == SourceLine(file: 1, line: 1))
        #expect(bundle.warnings.map(\.at) == [7, 23, 40, 51, 71, 87].map { SourceLine(file: 1, line: $0) })
        #expect(Set(bundle.warnings.map(\.kind)) == [.duplicateInFiles])
    }

    @Test func warningsSortByFileThenLine() async throws {
        let files = try [ImportFixture.file("ap-workouts-edge"), ImportFixture.file("ap-workouts-edge")]
        let bundle = try await TrainImportReader.read(files)
        #expect(bundle.sessions.count == 4)
        #expect(bundle.warnings.count == 16 + 16 + 4)
        #expect(bundle.warnings.map(\.at) == bundle.warnings.map(\.at).sorted())
        #expect(bundle.warnings.filter { $0.kind == .duplicateInFiles }.map(\.at.line) == [4, 15, 27, 36])
        // On one line, warnings keep the order they were found in.
        #expect(bundle.warnings.filter { $0.at == SourceLine(file: 1, line: 27) }.map(\.kind)
            == [.meridiemConflict, .unreadableDuration, .duplicateInFiles])
    }

    @Test func mergedWarningsKeepTheCap() async throws {
        var limits = ImportLimits.standard
        limits.maxWarnings = 10
        let files = try [ImportFixture.file("ap-workouts-edge"), ImportFixture.file("ap-workouts-edge")]
        let bundle = try await TrainImportReader.read(files, limits: limits)
        #expect(bundle.warnings.count == 10)
        #expect(bundle.warnings.count + bundle.suppressedWarnings == 36)
    }

    @Test func oneFileAtItsIndex() async throws {
        let file = try ImportFixture.file("ap-workouts-lbs")
        let bundle = try await TrainImportReader.read(file, index: 3)
        #expect(bundle.sessions.first?.source == SourceLine(file: 3, line: 1))
        #expect(bundle.warnings.map(\.at) == [SourceLine(file: 3, line: 10)])
    }

    @Test func mergingCountsOccurrences() throws {
        // Two workouts that share a start in one file both survive; a copy in another file is dropped per occurrence.
        let text = """
        "A · Standalone workout";"2026-01-05 10:00";"30 min"
        "B · Standalone workout";"2026-01-05 10:00";"30 min"
        """
        let one = try ImportFixture.parse(text: text)
        let other = try ImportFixture.parse(text: text + "\n\"C · Standalone workout\";\"2026-01-05 10:00\";\"30 min\"").inFile(1)
        let merged = one.merging(other)
        #expect(one.sessions.count == 2)
        #expect(merged.sessions.map(\.title) == ["A", "B", "C"])
        #expect(merged.warnings.map(\.at) == [SourceLine(file: 1, line: 1), SourceLine(file: 1, line: 2)])
        #expect(merged.lineCount == 5)
    }

    @Test func refusals() async throws {
        let workouts = try ImportFixture.file("ap-workouts")
        let headerRow = try ImportFixture.file("header-row")
        let utf16 = try #require("#;KG;REPS".data(using: .utf16))
        await #expect(throws: ImportError.empty) { try await TrainImportReader.read([]) }
        await #expect(throws: ImportError.empty) { try await TrainImportReader.read([ImportFile(name: "a.csv", data: Data())]) }
        await #expect(throws: ImportError.empty) {
            try await TrainImportReader.read([ImportFile(name: "a.csv", data: Data("\u{FEFF}\r\n \r\n".utf8))])
        }
        await #expect(throws: ImportError.notRecognised) { try await TrainImportReader.read([headerRow]) }
        await #expect(throws: ImportError.notRecognised) { try await TrainImportReader.read([workouts, headerRow]) }
        await #expect(throws: ImportError.notRecognised) { try await TrainImportReader.read(headerRow, index: 0) }
        await #expect(throws: ImportError.unsupportedEncoding) {
            try await TrainImportReader.read([ImportFile(name: "a.csv", data: utf16)])
        }
        var small = ImportLimits.standard
        small.maxFileBytes = 1_000
        await #expect(throws: ImportError.tooLarge(bytes: workouts.data.count)) {
            try await TrainImportReader.read([workouts], limits: small)
        }
    }

    @Test func aRecognisedFileWithNothingInItIsAnEmptyBundleNotAnError() async throws {
        // ui.md D7 ("no plan and no workouts") needs the bundle and its warnings; P6 (a blank file) stays `.empty`.
        let nothing = ImportFile(name: "a.csv", data: Data("#;KG;REPS\n1;60;10".utf8))
        let one = try await TrainImportReader.read(nothing, index: 2)
        #expect(one.isEmpty)
        #expect(one.warnings.map(\.at) == [SourceLine(file: 2, line: 1), SourceLine(file: 2, line: 2)])
        let both = try await TrainImportReader.read([nothing, nothing])
        #expect(both.isEmpty)
        #expect(both.warnings.count == 4)
        await #expect(throws: ImportError.empty) {
            try await TrainImportReader.read(ImportFile(name: "b.csv", data: Data("\r\n".utf8)), index: 0)
        }
    }

    @Test func thePickedFilesAreCappedInNumberAndSize() async throws {
        let plans = try ImportFixture.file("ap-plans")
        await #expect(throws: ImportError.tooManyFiles(count: 7)) {
            try await TrainImportReader.read(Array(repeating: plans, count: 7))
        }
        let six = try await TrainImportReader.read(Array(repeating: plans, count: 6))
        #expect(six.plans.count == 6)
        var limits = ImportLimits.standard
        limits.maxTotalBytes = plans.data.count * 2
        let two = try await TrainImportReader.read([plans, plans], limits: limits)
        #expect(two.plans.count == 2)
        await #expect(throws: ImportError.tooLarge(bytes: plans.data.count * 3)) {
            try await TrainImportReader.read([plans, plans, plans], limits: limits)
        }
    }

    @Test func mergingCapsWarningsItself() throws {
        let edge = try ImportFixture.parse("ap-workouts-edge")
        let merged = edge.merging(edge.inFile(1), maxWarnings: 20)
        #expect(merged.warnings.count == 20)
        #expect(merged.warnings.count + merged.suppressedWarnings == 16 + 16 + 4)
        #expect(merged.warnings.map(\.at) == merged.warnings.map(\.at).sorted())
        // The default cap is the standard one.
        var many = edge
        many.warnings = Array(repeating: ImportWarning(at: SourceLine(file: 0, line: 1), kind: .unrecognisedLine), count: 150)
        let capped = many.merging(many.inFile(1))
        #expect(capped.warnings.count == ImportLimits.standard.maxWarnings)
        #expect(capped.suppressedWarnings == 300 + 4 - ImportLimits.standard.maxWarnings)
    }

    @Test func cancellationStopsTheRead() async throws {
        let files = try [ImportFixture.file("ap-workouts")]
        let task = Task { () async throws -> ImportBundle in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await TrainImportReader.read(files)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancellationIsCheckedWhileParsing() async {
        let data = Data(String(repeating: "junk\n", count: 2_000).utf8)
        let task = Task { () throws -> ImportBundle in
            withUnsafeCurrentTask { $0?.cancel() }
            return try AlphaProgressionFormat().parse(data, limits: .standard)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// `read` asserts in Debug builds that it isn't on the main thread: called from the main actor, it hops off.
    @MainActor @Test func readsOffTheMainActor() async throws {
        let files = try [ImportFixture.file("ap-workouts")]
        let bundle = try await TrainImportReader.read(files)
        #expect(bundle.sessions.count == 6)
    }
}
