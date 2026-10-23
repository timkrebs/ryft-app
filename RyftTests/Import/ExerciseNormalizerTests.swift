import Foundation
import Testing
@testable import Ryft

@Suite("Exercise normaliser")
struct ExerciseNormalizerTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let equipment: String?
        let keyName: String
        let keyEquipment: String

        init(_ name: String, _ equipment: String?, _ keyName: String, _ keyEquipment: String) {
            self.name = name
            self.equipment = equipment
            self.keyName = keyName
            self.keyEquipment = keyEquipment
        }

        var testDescription: String { "\(name) · \(equipment ?? "–")" }
    }

    /// The design's rule table (§4), with the small vocabulary of `MappingFixture.file()`.
    static let cases: [Case] = [
        // Case, diacritics, ß, NFKC.
        Case("BANKDRÜCKEN", nil, "bankdrucken", ""),
        Case("Fußheben", nil, "fussheben", ""),
        Case("Ｂench　Ｐress", nil, "bench press", ""),
        // Punctuation separates words; apostrophes join them.
        Case("Pull-Up", nil, "pull up", ""),
        Case("Curl/Press (Combo)", nil, "combo curl press", ""),
        Case("Bench Press · Barbell", nil, "bench press", "barbell"),
        Case("Farmer's Walk", nil, "farmer walk", ""),
        Case("Farmer’s Walk", nil, "farmer walk", ""),
        Case("Clean & Jerk", nil, "clean jerk", ""),
        // Stop words, en and de.
        Case("Row with the Bar", nil, "bar row", ""),
        Case("Rudern am Kabel", nil, "rudern", "cable"),
        Case("Curl mit der Kurzhantel", nil, "curl", "dumbbell"),
        // English plurals.
        Case("Presses", nil, "press", ""),
        Case("Crunches", nil, "crunch", ""),
        Case("Flies", nil, "fly", ""),
        Case("Lunges", nil, "lunge", ""),
        Case("Triceps", nil, "tricep", ""),
        Case("Abs", nil, "ab", ""),
        Case("Press", nil, "press", ""),
        Case("Plus", nil, "plus", ""),
        Case("Ties", nil, "tie", ""),
        // Synonyms (one token to several), then sorted unique tokens.
        Case("Pullups", nil, "pull up", ""),
        Case("Squat Squat", nil, "squat", ""),
        Case("Row Bent Over", nil, "bent over row", ""),
        // Equipment: the field, a word in the name (also through a synonym), field before name.
        Case("Curl", "Dumbbells", "curl", "dumbbell"),
        Case("DB Curl", nil, "curl", "dumbbell"),
        Case("Dumbbell Curl", "Barbell", "curl", "barbell"),
        Case("Squat", "Smith Machine", "squat", "smith_machine"),
        Case("Smith Machine Squat", nil, "squat", "smith_machine"),
        Case("Curl", "Cable - Straight Bar", "curl", "cable"),
        // Unknown equipment keeps its normalised text; a known word in the name wins over it.
        Case("Pull-Up", "Resistance Tube", "pull up", "resistance tube"),
        Case("Dumbbell Lunge", "Weighted", "lunge", "dumbbell"),
        Case("Lunge", "Weighted", "lunge", "weighted"),
        // A name made only of equipment words keeps them.
        Case("Kabel", nil, "kabel", "cable"),
        // Empty and punctuation-only.
        Case("", nil, "", ""),
        Case("·–·", "  ", "", ""),
    ]

    @Test(arguments: cases)
    func keys(_ c: Case) {
        let key = MappingFixture.vocabulary().normalizer.key(name: c.name, equipment: c.equipment)
        #expect(key == SourceExerciseKey(name: c.keyName, equipment: c.keyEquipment))
    }

    @Test func singularIsIdempotent() {
        for word in ["presses", "crunches", "boxes", "flies", "ties", "lunges", "abs", "bus", "chess", "series", "s", "is"] {
            let once = ExerciseNormalizer.singular(word)
            #expect(ExerciseNormalizer.singular(once) == once, "\(word)")
        }
    }

    @Test func longNamesAreCut() {
        let name = (1...100).map { "w\($0)" }.joined(separator: " ")
        let key = MappingFixture.vocabulary().normalizer.key(name: name, equipment: nil)
        #expect(key.name.split(separator: " ").count == ExerciseNormalizer.maxTokens)
    }

    /// A key read back gives itself, for every built-in name and every shipped alias (design §4).
    @Test func keysAreIdempotent() throws {
        let aliases = ExerciseAliases.bundled
        let library = try MappingFixture.builtins()
        let file = try MappingFixture.shippedFile()
        var names = library.flatMap { [$0.nameEn, $0.nameDe] }
        names += file.aliases.flatMap { ($0.en ?? []) + ($0.de ?? []) }
        var changed: [String] = []
        for name in names {
            let key = aliases.normalizer.key(name: name, equipment: nil)
            let again = aliases.normalizer.key(name: key.name, equipment: key.equipment)
            if again != key { changed.append(name) }
        }
        #expect(changed == [])
    }

    @Test func equipmentIDsReadBackAsThemselves() {
        let aliases = ExerciseAliases.bundled
        for id in aliases.kinds.keys.sorted() {
            #expect(aliases.normalizer.equipmentField(id) == .known(id), "\(id)")
        }
    }
}
