import Foundation
import Testing
@testable import Ryft

@Suite("Import line reader and fields")
struct LineReaderTests {
    private func lines(_ bytes: [UInt8], maxLineBytes: Int = 4_096) -> [String] {
        let reader = LineReader(Data(bytes), maxLineBytes: maxLineBytes)
        return reader.map { $0.isTooLong ? "<too long>" : reader.text(of: $0).text }
    }

    private func lines(_ text: String) -> [String] { lines(Array(text.utf8)) }

    @Test func everyLineEndEndsALine() {
        #expect(lines("a\nb\r\nc\rd") == ["a", "b", "c", "d"])
        #expect(lines("a\r\r\nb") == ["a", "", "b"])
        #expect(lines("a\n\rb") == ["a", "", "b"]) // LF then a lone CR
    }

    @Test func aFinalLineEndAddsNoLine() {
        #expect(lines("a\n") == ["a"])
        #expect(lines("a\r\n") == ["a"])
        #expect(lines("a\n\n") == ["a", ""])
        #expect(lines("") == [])
        #expect(lines("\r\n") == [""])
        #expect(lines("last line without an end") == ["last line without an end"])
    }

    @Test func numbersAreOneBasedAndCountEveryLine() {
        let reader = LineReader(Data("a\r\n\r\nb".utf8), maxLineBytes: 4_096)
        #expect(reader.map(\.number) == [1, 2, 3])
    }

    @Test func aUTF8BOMIsSkipped() {
        #expect(lines([0xEF, 0xBB, 0xBF] + Array("a\nb".utf8)) == ["a", "b"])
        #expect(lines([0xEF, 0xBB, 0xBF]) == [])
        // A stray BOM at a later line's start (two exports glued together) is dropped too.
        #expect(lines(Array("a\n".utf8) + [0xEF, 0xBB, 0xBF] + Array("b".utf8)) == ["a", "b"])
    }

    @Test func longLinesAreSkippedNotRead() {
        let exact = [UInt8](repeating: 0x61, count: 4_096)
        let over = [UInt8](repeating: 0x61, count: 4_097)
        #expect(lines(exact + [0x0A] + Array("next".utf8)) == [String(repeating: "a", count: 4_096), "next"])
        #expect(lines(over + [0x0D, 0x0A] + Array("next".utf8)) == ["<too long>", "next"])
        #expect(lines(Array("abc\ndefgh\nij".utf8), maxLineBytes: 3) == ["abc", "<too long>", "ij"])
    }

    @Test func invalidUTF8DecodesLossilyAndSaysSo() {
        let reader = LineReader(Data([0x61, 0xFF, 0x62, 0x0A, 0x63, 0xC3]), maxLineBytes: 4_096)
        let decoded = reader.map { reader.text(of: $0) }
        #expect(decoded.map(\.text) == ["a\u{FFFD}b", "c\u{FFFD}"])
        #expect(decoded.map(\.isInvalid) == [true, true])
        let valid = LineReader(Data("Bankdrücken".utf8), maxLineBytes: 4_096)
        #expect(valid.map { valid.text(of: $0).isInvalid } == [false])
    }

    @Test func otherEncodingsAreRefused() throws {
        let utf16 = try #require("\"Day 1 · Push\"".data(using: .utf16))
        #expect(ImportHygiene.isUnsupportedEncoding(utf16)) // with a BOM
        #expect(ImportHygiene.isUnsupportedEncoding(Data([0xFE, 0xFF, 0x00, 0x41])))
        #expect(ImportHygiene.isUnsupportedEncoding(Data([0x00, 0x00, 0xFE, 0xFF])))
        #expect(ImportHygiene.isUnsupportedEncoding(Data("a\u{0}b".utf8)))
        #expect(!ImportHygiene.isUnsupportedEncoding(Data("a;b".utf8)))
        // NUL after the first 64 KiB isn't looked for.
        let late = Data(repeating: 0x61, count: ImportHygiene.headBytes) + Data([0x00])
        #expect(!ImportHygiene.isUnsupportedEncoding(late))
        #expect(throws: ImportError.unsupportedEncoding) {
            try AlphaProgressionFormat().parse(utf16, limits: .standard)
        }
        let utf16LE = try #require("#;KG;REPS".data(using: .utf16LittleEndian))
        #expect(throws: ImportError.unsupportedEncoding) {
            try AlphaProgressionFormat().parse(utf16LE, limits: .standard)
        }
    }

    @Test func theHeadIsCutAtALineEnd() {
        let line = Data(String(repeating: "x", count: 99).utf8) + Data([0x0A])
        let data = Data((0..<1_000).flatMap { _ in line }) // 100 KB
        let head = ImportHygiene.head(of: data)
        #expect(head.count <= ImportHygiene.headBytes)
        #expect(head.count % 100 == 0)
        #expect(head.last == 0x0A)
        #expect(ImportHygiene.head(of: Data("short".utf8)) == Data("short".utf8))
    }

    @Test func blankFiles() {
        #expect(ImportHygiene.isBlank(Data()))
        #expect(ImportHygiene.isBlank(Data([0xEF, 0xBB, 0xBF, 0x0D, 0x0A, 0x20, 0x09])))
        #expect(!ImportHygiene.isBlank(Data(";".utf8)))
    }

    // MARK: Fields

    @Test func fieldsSplitAtSemicolons() {
        let cases: [(String, [String])] = [
            ("\"a\";\"b\";\"c\"", ["a", "b", "c"]),
            ("1;60;10", ["1", "60", "10"]),
            ("a;b;", ["a", "b"]),
            ("a;;b", ["a", "", "b"]),
            ("\"x;y\";z", ["x;y", "z"]),
            ("\"say \"\"hi\"\"\";b", ["say \"hi\"", "b"]),
            ("\"unclosed;rest of the line", ["unclosed;rest of the line"]),
            ("  a  ;  \"b\"  ", ["a", "b"]),
            ("\"a\"x;b", ["ax", "b"]),
            ("ab\"c;d", ["ab\"c", "d"]),
            ("\" padded \"", ["padded"]),
            (";;;", []),
            ("", []),
            ("\"\"", []),
            ("1;60;10;;", ["1", "60", "10"]),
        ]
        for (line, expected) in cases {
            let split = CSVFields.split(line)
            #expect(split.fields == expected, "\(line)")
            #expect(!split.hasMore, "\(line)")
        }
    }

    @Test func atMostThreeFieldsAreKept() {
        let wide = CSVFields.split("#;KG;REPS;RPE")
        #expect(wide.fields == ["#", "KG", "REPS"])
        #expect(wide.hasMore)
        let padded = CSVFields.split("1;2;3;;;  ;4")
        #expect(padded.fields == ["1", "2", "3"])
        #expect(padded.hasMore)
        #expect(CSVFields.split("a;\"\";\"\";x").fields == ["a", "", ""])
    }

    @Test func quotedFieldsAreMarked() {
        #expect(CSVFields.split("\"a · b\";1;x").quoted == [true, false, false])
        #expect(CSVFields.split("x").field(1) == nil)
        #expect(CSVFields.split("x").field(-1) == nil)
    }

    @Test func innerParts() {
        #expect(CSVFields.parts("Upper · Day 1 · Week 2") == ["Upper", "Day 1", "Week 2"])
        #expect(CSVFields.parts("A·B") == ["A·B"])
        #expect(CSVFields.parts("A ·B") == ["A ·B"])
        #expect(CSVFields.parts("Push-Ups · Bodyweight") == ["Push-Ups", "Bodyweight"])
        #expect(CSVFields.parts("A\u{00A0}·\u{00A0}B\t·  C") == ["A", "B", "C"])
        #expect(CSVFields.parts("") == [""])
        #expect(CSVFields.parts(" · ") == ["", ""])
    }

    @Test func controlAndFormatCharactersAreStripped() {
        let line = CSVFields.split("\"a\u{0}b\u{1F}c\u{202E}d\u{FEFF}\";\"tab\there\";x\u{7F}y")
        #expect(line.fields == ["abcd", "tab\there", "xy"])
        #expect(CSVFields.split("\"\u{200B}\";1").fields == ["", "1"])
        #expect(CSVFields.split("Bankdrücken · Langhantel").fields == ["Bankdrücken · Langhantel"])
    }

    @Test func theSplitCountsTheBytesItVisits() {
        #expect(CSVFields.split("").visited == 1)
        #expect(CSVFields.split("1;60;10").visited == 8) // every byte once, plus the line end
        let wide = String(repeating: ";", count: 4_000)
        let visited = CSVFields.split(wide).visited
        #expect(visited >= 4_000 && visited <= 8_002)
    }
}
