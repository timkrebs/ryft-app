import Foundation
import Testing
@testable import Ryft

private final class GoldenToken {}

/// **Changing what this pins is a breaking id change (ADR 0007).** `SourceExerciseKey` derives every imported custom
/// exercise's id and every remembered choice, and it is `SourceExerciseKey.fold` of the file's name and of its equipment
/// field, nothing else: no alias vocabulary, so editing `exercise-aliases.json` never changes a pinned key (a new alias
/// name only needs pinning, `everyNameIsPinned`). Only a change to `fold` itself does, and that would mean duplicate
/// custom exercises and forgotten matches for everyone who imported before. `Fixtures/Import/source-keys.golden.json` holds the key of every alias name, built-in name, synthetic-fixture
/// exercise and equipment spelling (checked against an independent implementation of `fold` when written). If a change
/// here is intended, it needs an ADR amendment and a migration of stored keys, not a regenerated golden file.
@Suite("Source exercise key: golden")
struct SourceExerciseKeyGoldenTests {
    struct Golden: Decodable {
        let name: String
        let equipment: String?
        let key: String
        let keyEquipment: String
    }

    static func golden() throws -> [Golden] {
        let bundle = Bundle(for: GoldenToken.self)
        guard let url = bundle.url(forResource: "source-keys.golden", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "source-keys.golden.json"])
        }
        return try JSONDecoder().decode([Golden].self, from: Data(contentsOf: url))
    }

    @Test func pinnedKeysDontChange() throws {
        let normalizer = ExerciseAliases.bundled.normalizer
        let golden = try Self.golden()
        var changed: [String] = []
        for entry in golden {
            let key = normalizer.key(name: entry.name, equipment: entry.equipment)
            if key != SourceExerciseKey(name: entry.key, equipment: entry.keyEquipment) {
                changed.append("\(entry.name) · \(entry.equipment ?? "–") → \(key.name) · \(key.equipment)")
            }
        }
        #expect(golden.count > 1_000)
        #expect(changed == [])
    }

    /// New alias names, built-ins, fixtures and equipment spellings get pinned too: add the missing lines (printed in
    /// the failure, computed by today's rule) to the golden file.
    @Test func everyNameIsPinned() throws {
        let normalizer = ExerciseAliases.bundled.normalizer
        let file = try MappingFixture.shippedFile()
        let pinned = Set(try Self.golden().map { "\($0.name)\u{1F}\($0.equipment ?? "\u{0}")" })
        var inputs = try ExerciseNormalizerTests.allNames().map { ($0, String?.none) }
        inputs += try ExerciseNormalizerTests.fixturePairs()
        for (id, phrases) in file.equipment {
            inputs += ([id] + phrases).map { ("x", Optional($0)) }
        }
        var missing: [String] = []
        for (name, equipment) in inputs where !pinned.contains("\(name)\u{1F}\(equipment ?? "\u{0}")") {
            let key = normalizer.key(name: name, equipment: equipment)
            let field = equipment.map { "\"\($0)\"" } ?? "null"
            missing.append(#"{"equipment":\#(field),"key":"\#(key.name)","keyEquipment":"\#(key.equipment)","name":"\#(name)"}"#)
        }
        #expect(Set(missing).sorted() == [])
    }
}
