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

    // MARK: The match key

    /// The design's rule table (§4) for matching, with the small vocabulary of `MappingFixture.file()`.
    static let matchCases: [Case] = [
        // Case, diacritics, ß, NFKC.
        Case("BANKDRÜCKEN", nil, "bankdrucken", ""),
        Case("Fußheben", nil, "fussheben", ""),
        Case("Ｂench　Ｐress", nil, "bench press", ""),
        // Punctuation separates words; apostrophes join them, also ´ (which NFKC would turn into a space and a mark).
        Case("Pull-Up", nil, "pull up", ""),
        Case("Curl/Press (Combo)", nil, "combo curl press", ""),
        Case("Bench Press · Barbell", nil, "bench press", "barbell"),
        Case("Farmer's Walk", nil, "farmer walk", ""),
        Case("Farmer’s Walk", nil, "farmer walk", ""),
        Case("Farmer´s Walk", nil, "farmer walk", ""),
        Case("Clean & Jerk", nil, "clean jerk", ""),
        // Default-ignorable and format characters vanish before anything else.
        Case("Bank\u{AD}drücken", nil, "bankdrucken", ""),
        Case("Bench\u{200B}Press", nil, "benchpress", ""),
        Case("\u{202E}Curl", nil, "curl", ""),
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
        // Equipment: the field, a word in the name (also through a synonym).
        Case("Curl", "Dumbbells", "curl", "dumbbell"),
        Case("DB Curl", nil, "curl", "dumbbell"),
        Case("Squat", "Smith Machine", "squat", "smith_machine"),
        Case("Smith Machine Squat", nil, "squat", "smith_machine"),
        Case("Curl", "Cable - Straight Bar", "curl", "cable"),
        // Field and name disagree: a refinement wins, from either side.
        Case("Smith Machine Squat", "Machine", "squat", "smith_machine"),
        // Anything else is a contradiction: the field's, and the name keeps its equipment words. Cable isn't a kind
        // of machine, even though machine allows cable stations.
        Case("Dumbbell Curl", "Barbell", "curl dumbbell", "barbell"),
        Case("Cable Fly", "Machine", "cable fly", "machine"),
        Case("Machine Fly", "Cable", "fly machine", "cable"),
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

    @Test(arguments: matchCases)
    func matchKeys(_ c: Case) {
        let key = MappingFixture.vocabulary().normalizer.matchKey(name: c.name, equipment: c.equipment)
        #expect(key == MatchKey(name: c.keyName, equipment: c.keyEquipment))
    }

    /// The shipped vocabulary's specific equipment: trap and EZ bars within barbell, either side.
    @Test func specificEquipmentWins() {
        let normalizer = ExerciseAliases.bundled.normalizer
        #expect(normalizer.matchKey(name: "Trap Bar Deadlift", equipment: "Barbell") == MatchKey(name: "deadlift", equipment: "trap_bar"))
        #expect(normalizer.matchKey(name: "Barbell Deadlift", equipment: "Trap Bar") == MatchKey(name: "deadlift", equipment: "trap_bar"))
        #expect(normalizer.matchKey(name: "EZ Bar Curl", equipment: "Barbell") == MatchKey(name: "curl", equipment: "ez_bar"))
        #expect(normalizer.matchKey(name: "Assisted Dip", equipment: "Machine") == MatchKey(name: "dip", equipment: "assisted"))
        #expect(normalizer.isMoreSpecific("trap_bar", than: "barbell"))
        #expect(normalizer.isMoreSpecific("ez_bar", than: "barbell"))
        #expect(normalizer.isMoreSpecific("smith_machine", than: "machine"))
        #expect(normalizer.isMoreSpecific("assisted", than: "machine"))
        #expect(!normalizer.isMoreSpecific("barbell", than: "trap_bar"))
        #expect(!normalizer.isMoreSpecific("ez_bar", than: "trap_bar"))
        #expect(!normalizer.isMoreSpecific("dumbbell", than: "barbell"))
        // Machine allows cable stations for the filter; a cable exercise still isn't a machine one.
        #expect(!normalizer.isMoreSpecific("cable", than: "machine"))
        #expect(!normalizer.isMoreSpecific("machine", than: "cable"))
        #expect(normalizer.matchKey(name: "Crunch Machine", equipment: "Cable") == MatchKey(name: "crunch machine", equipment: "cable"))
    }

    @Test func singularIsIdempotent() {
        for word in ["presses", "crunches", "boxes", "flies", "ties", "lunges", "abs", "bus", "chess", "series", "s", "is"] {
            let once = ExerciseNormalizer.singular(word)
            #expect(ExerciseNormalizer.singular(once) == once, "\(word)")
        }
    }

    @Test func longNamesAreCutForMatching() {
        let name = (1...100).map { "w\($0)" }.joined(separator: " ")
        let normalizer = MappingFixture.vocabulary().normalizer
        #expect(normalizer.matchKey(name: name, equipment: nil).name.split(separator: " ").count == ExerciseNormalizer.maxTokens)
        // The stored key isn't cut: it is the file's name.
        #expect(normalizer.key(name: name, equipment: nil).name == name)
    }

    /// A match key read back gives itself, for every built-in name and every shipped alias (design §4).
    @Test func matchKeysAreIdempotent() throws {
        let normalizer = ExerciseAliases.bundled.normalizer
        var changed: [String] = []
        for name in try Self.allNames() {
            let key = normalizer.matchKey(name: name, equipment: nil)
            let again = normalizer.matchKey(name: key.name, equipment: key.equipment.isEmpty ? nil : key.equipment)
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

    // MARK: The stored key

    /// The frozen rule (ADR 0007): no vocabulary at all, so no equipment ids, synonyms, plurals, stop words, sorting
    /// or diacritic folding. Name and equipment field are each `SourceExerciseKey.fold`ed.
    static let keyCases: [Case] = [
        Case("Bench Press", "Barbell", "bench press", "barbell"),
        Case("bench-press", "Langhantel", "bench press", "langhantel"),
        Case("  BENCH   PRESS ", "BARBELL", "bench press", "barbell"),
        Case("Pullups", nil, "pullups", ""),
        Case("Row Bent Over", nil, "row bent over", ""),
        Case("Bankdrücken", "Kurzhantel", "bankdrücken", "kurzhantel"),
        Case("Curl", "Dumbbells", "curl", "dumbbells"),
        Case("Squat", "Smith-Machine", "squat", "smith machine"),
        Case("Straße", nil, "straße", ""),
        Case("Farmer's Walk", nil, "farmers walk", ""),
        Case("Farmer´s Walk", nil, "farmers walk", ""),
        Case("Bank\u{AD}drücken", nil, "bankdrücken", ""),
        Case("Bench\u{0}Press", nil, "benchpress", ""),
        Case("\u{202E}Curl\u{202C}", nil, "curl", ""),
        Case("Ｂench　Ｐress", nil, "bench press", ""),
        Case("Dumbbell Curl", nil, "dumbbell curl", ""),
        Case("Curl", "Cable - Straight Bar", "curl", "cable straight bar"),
        Case("Pull-Up", "Resistance Tube", "pull up", "resistance tube"),
        Case("Lunge", "  Weighted  ", "lunge", "weighted"),
        Case("Curl", "", "curl", ""),
        Case("", nil, "", ""),
        // The rule's own clauses (the golden file pins more).
        Case("ΟΔΟΣ", nil, "οδοσ", ""),
        Case("Rock\u{149}Roll", nil, "rocknroll", ""),
        Case("Bench\u{1F}Press", nil, "benchpress", ""),
        Case("Bench\u{85}Press", nil, "bench press", ""),
    ]

    @Test(arguments: keyCases)
    func storedKeys(_ c: Case) {
        let key = ExerciseAliases.bundled.normalizer.key(name: c.name, equipment: c.equipment)
        #expect(key == SourceExerciseKey(name: c.keyName, equipment: c.keyEquipment))
    }

    /// The stored key doesn't depend on the vocabulary: one without equipment words, synonyms or aliases gives the
    /// same key for every name and every equipment spelling.
    @Test func storedKeysIgnoreTheVocabulary() throws {
        let bare = ExerciseAliases.fallback.normalizer
        let full = ExerciseAliases.bundled.normalizer
        let file = try MappingFixture.shippedFile()
        var pairs = try Self.allNames().map { ($0, String?.none) }
        pairs += try Self.fixturePairs()
        for (id, phrases) in file.equipment { pairs += ([id] + phrases).map { ("x", Optional($0)) } }
        var differ: [String] = []
        for (name, equipment) in pairs where bare.key(name: name, equipment: equipment) != full.key(name: name, equipment: equipment) {
            differ.append("\(name) · \(equipment ?? "–")")
        }
        #expect(differ == [])
    }

    /// Matching a stored key is matching the file's name and field: the key loses nothing matching reads.
    @Test func matchingAStoredKeyEqualsMatchingTheFile() throws {
        let normalizer = ExerciseAliases.bundled.normalizer
        var pairs = try Self.allNames().map { ($0, String?.none) }
        pairs += try Self.fixturePairs()
        pairs += [("Trap Bar Deadlift", "Barbell"), ("Dumbbell Curl", "Barbell"), ("Farmer´s Walk", nil),
                  ("Bank\u{AD}drücken", "LH"), ("Lunge", "Weighted"), ("Curl", "Cable - Straight Bar")]
        var differ: [String] = []
        for (name, equipment) in pairs {
            let direct = normalizer.matchKey(name: name, equipment: equipment)
            let stored = normalizer.matchKey(normalizer.key(name: name, equipment: equipment))
            if direct != stored { differ.append("\(name) · \(equipment ?? "–")") }
        }
        #expect(differ == [])
    }

    /// `fold(fold(x)) == fold(x)` for every assigned scalar of the BMP and a stride through the rest, alone and
    /// between letters (the harness checks all 0x10FFFF in three contexts).
    @Test func foldIsIdempotent() {
        var codes = Array(0...0xFFFF)
        codes += Array(stride(from: 0x10000, through: 0x10FFFF, by: 7))
        codes += Array(0xE0000...0xE01EF)
        var bad: [String] = []
        var checked = 0
        for code in codes {
            guard let scalar = Unicode.Scalar(UInt32(code)) else { continue }
            switch scalar.properties.generalCategory {
            case .unassigned, .surrogate, .privateUse: continue
            default: break
            }
            for text in ["a\(Character(scalar))b", String(Character(scalar))] {
                checked += 1
                let once = SourceExerciseKey.fold(text)
                if SourceExerciseKey.fold(once) != once { bad.append(String(format: "U+%04X", code)) }
            }
        }
        #expect(checked > 100_000)
        #expect(bad == [])
    }

    @Test func storedKeysAreIdempotent() throws {
        let normalizer = ExerciseAliases.bundled.normalizer
        for (name, equipment) in try Self.fixturePairs() {
            let key = normalizer.key(name: name, equipment: equipment)
            #expect(normalizer.key(name: key.name, equipment: key.equipment.isEmpty ? nil : key.equipment) == key)
        }
    }

    @Test func displayName() {
        #expect(SourceExerciseKey(name: "zottman curl", equipment: "").displayName == "Zottman Curl")
    }

    // MARK: Inputs

    /// Every built-in name and every shipped alias name.
    static func allNames() throws -> [String] {
        let file = try MappingFixture.shippedFile()
        let library = try MappingFixture.builtins()
        return library.flatMap { [$0.nameEn, $0.nameDe] } + file.aliases.flatMap { ($0.en ?? []) + ($0.de ?? []) }
    }

    /// Every exercise name and equipment field in the synthetic fixtures.
    static func fixturePairs() throws -> [(String, String?)] {
        var pairs: [(String, String?)] = []
        for name in ImportFixture.alphaProgression {
            let bundle = try ImportFixture.parse(name)
            pairs += bundle.plans.flatMap(\.days).flatMap(\.exercises).map { ($0.name, $0.equipment) }
            pairs += bundle.sessions.flatMap(\.exercises).map { ($0.name, $0.equipment) }
        }
        return pairs
    }
}
