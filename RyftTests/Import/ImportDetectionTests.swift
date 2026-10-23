import Foundation
import Testing
@testable import Ryft

@Suite("Import format detection")
struct ImportDetectionTests {
    private let format = AlphaProgressionFormat()

    private func detect(_ text: String) -> ImportConfidence { format.detect(Data(text.utf8)) }

    @Test func everyExportFixtureIsStrong() throws {
        for name in ImportFixture.alphaProgression {
            let data = try ImportFixture.data(name)
            #expect(format.detect(data) == .strong, "\(name)")
        }
    }

    @Test func aHeaderRowFileIsNotOurs() throws {
        let headerRow = try ImportFixture.data("header-row")
        #expect(format.detect(headerRow) == .none)
        // Even when Alpha Progression lines follow: the first line decides.
        #expect(detect("Date,Workout Name,Exercise Name\n#;KG;REPS\n1;60;10") == .none)
        #expect(TrainImportFormats.best(for: headerRow) == nil)
    }

    @Test func strongSignals() {
        #expect(detect("#;KG;REPS") == .strong)
        #expect(detect("#;lbs;Wdh") == .strong)
        #expect(detect("\"Base · 5 weeks\";2026-01-05\n\"1. Front Squat · Barbell\";\"3 sets\";\"5 reps\"") == .strong)
        #expect(detect("\"Base · 5 weeks\";2026-01-05\n\"Day 1\"\n\"1. Front Squat · Barbell\";\"3 sets\"") == .strong)
    }

    @Test func weakWithoutAHeader() {
        let text = """
        "Upper · Standalone workout";"2026-01-05 9:00 am";"30 min"
        "1. Floor Press · Barbell · 5 reps"
        1;60;5
        """
        #expect(detect(text) == .weak)
        // The parser still reads it, with the missing header said.
        let bundle = try? AlphaProgressionFormat().parse(Data(text.utf8), limits: .standard)
        #expect(bundle?.sessions.count == 1)
        #expect(bundle?.warningList == ["3 missingTableHeader.kg"])
    }

    @Test func nothingFamiliar() {
        #expect(detect("") == .none)
        #expect(detect("hello world\nsecond line") == .none)
        #expect(detect("\"Base · 5 weeks\";2026-01-05") == .none) // a plan header alone
        #expect(detect("1;60;10\n2;60;10") == .none)               // set rows alone
        #expect(detect("#;SEC;REPS") == .none)                     // a table header we can't read
        #expect(format.detect(Data([0xFF, 0xFE, 0x23, 0x00])) == .none)
    }

    @Test func onlyTheHeadIsRead() {
        let filler = String(repeating: "filler line\n", count: 6_000) // 72 KB
        #expect(detect(filler + "#;KG;REPS\n") == .none)
        #expect(detect("#;KG;REPS\n" + filler) == .strong)
    }

    @Test func theRegistryPicksTheMostConfidentFormat() throws {
        let workouts = try ImportFixture.data("ap-workouts")
        let best = try #require(TrainImportFormats.best(for: workouts))
        #expect(best.0.id == .alphaProgression)
        #expect(best.1 == .strong)
        #expect(TrainImportFormats.all.map(\.id) == [.alphaProgression])
        #expect(ImportFormatID.alphaProgression.rawValue == "alpha_progression") // the platform's `source`; never renamed
        #expect(ImportConfidence.none < .weak && ImportConfidence.weak < .strong)
    }
}
