import Foundation
import Testing
@testable import Ryft

/// A "new" row's exercise (design §4).
@Suite("Import custom exercise")
struct ImportCustomExerciseTests {
    let aliases = ExerciseAliases.bundled

    func key(_ name: String, _ equipment: String?) -> SourceExerciseKey {
        aliases.normalizer.key(name: name, equipment: equipment)
    }

    @Test func kindComesFromTheEquipment() {
        #expect(ImportCustomExercise.kind(for: key("Zottman Curl", "Dumbbell"), aliases: aliases) == .dumbbell)
        #expect(ImportCustomExercise.kind(for: key("JM Press", "EZ Bar"), aliases: aliases) == .barbell)
        #expect(ImportCustomExercise.kind(for: key("Pendulum Squat", "Machine"), aliases: aliases) == .machine)
        #expect(ImportCustomExercise.kind(for: key("Ring Muscle-Up", "Bodyweight"), aliases: aliases) == .bodyweight)
        // Unknown, missing or allowing none: machine.
        #expect(ImportCustomExercise.kind(for: key("Banded Walk", "Band"), aliases: aliases) == .machine)
        #expect(ImportCustomExercise.kind(for: key("Sandbag Carry", "Sandbag"), aliases: aliases) == .machine)
        #expect(ImportCustomExercise.kind(for: key("Sandbag Carry", nil), aliases: aliases) == .machine)
        // Equipment named only in the name counts, as matching reads it.
        #expect(ImportCustomExercise.kind(for: key("Trap Bar Deadlift", nil), aliases: aliases) == .barbell)
        #expect(ImportCustomExercise.kind(for: key("Kettlebell Halo", nil), aliases: aliases) == .kettlebell)
    }

    @Test func loadType() {
        #expect(ImportCustomExercise.loadType(for: key("Ring Muscle-Up", "Bodyweight"), hasPlusSets: false, aliases: aliases) == .bodyweight)
        #expect(ImportCustomExercise.loadType(for: key("Weighted Step", "Machine"), hasPlusSets: true, aliases: aliases) == .bodyweight)
        #expect(ImportCustomExercise.loadType(for: key("Zottman Curl", "Dumbbell"), hasPlusSets: false, aliases: aliases) == .weight)
    }

    @Test func namesAreTrimmedAndCut() {
        let key = key("x", nil)
        #expect(ImportCustomExercise.name("  Zottman   Curl \n", key: key) == "Zottman Curl")
        // Nothing left: the key's display form.
        #expect(ImportCustomExercise.name("   ", key: key) == "X")
        let long = String(repeating: "a", count: 120)
        #expect(ImportCustomExercise.name(long, key: key).count == 80)
        // Counted in Unicode scalars, never cutting a character: "é" as e + U+0301 is two.
        let combining = String(repeating: "e\u{301}", count: 50)
        let cut = ImportCustomExercise.name(combining, key: key)
        #expect(cut.unicodeScalars.count == 80)
        #expect(cut.count == 40)
        let flags = String(repeating: "🇩🇪", count: 50)
        #expect(ImportCustomExercise.name(flags, key: key).unicodeScalars.count == 80)
    }

    /// Controls and format characters never reach the platform: NUL, bidi overrides, soft hyphens, zero-width marks.
    @Test func controlAndFormatCharactersAreDropped() {
        let key = key("Zottman Curl", nil)
        #expect(ImportCustomExercise.name("Zottman\u{0}Curl", key: key) == "ZottmanCurl")
        #expect(ImportCustomExercise.name("\u{202E}Zottman Curl\u{202C}", key: key) == "Zottman Curl")
        #expect(ImportCustomExercise.name("Zott\u{AD}man\u{200B} Curl\u{FEFF}", key: key) == "Zottman Curl")
        #expect(ImportCustomExercise.name("\u{2066}Zottman\u{2069}\tCurl", key: key) == "Zottman Curl")
        let cleaned = ImportCustomExercise.name("\u{202E}\u{0}\u{200F}", key: key)
        #expect(cleaned == "Zottman Curl")
        let left = cleaned.unicodeScalars.filter { [.control, .format].contains($0.properties.generalCategory) }
        #expect(left.isEmpty)
    }

    /// One character longer than the limit can't be cut: the key's display form, then without combining marks.
    @Test func overLongGraphemeFallsBack() {
        let giant = "e" + String(repeating: "\u{301}", count: 100)
        #expect(giant.count == 1)
        let key = key(giant, nil)
        let name = ImportCustomExercise.name(giant, key: key)
        #expect(name == "\u{C9}")
        #expect(name.unicodeScalars.count <= ImportCustomExercise.maxNameLength)
    }

    @Test func nothingUsableIsAnImportedExercise() {
        let empty = SourceExerciseKey(name: "", equipment: "")
        let name = ImportCustomExercise.name("\u{0}\u{202E}", key: empty)
        #expect(name == String(localized: "Imported exercise"))
        #expect(!name.isEmpty)
    }

    @Test func makesTheExercise() {
        let key = key("Zottman Curl", "Dumbbell")
        let row = ImportedExerciseSource(key: key, name: "Zottman Curl", equipment: "Dumbbell")
        let exercise = ImportCustomExercise.make(row, account: "demo", source: .alphaProgression,
                                                 primaryMuscles: [.biceps, .forearms], aliases: aliases)
        #expect(exercise.id == ImportCustomExercise.id(account: "demo", source: .alphaProgression, key: key))
        #expect(exercise.name == "Zottman Curl")
        #expect(exercise.slug == "zottman-curl")
        #expect(exercise.kind == .dumbbell)
        #expect(exercise.loadType == .weight)
        #expect(exercise.primaryMuscles == [.biceps, .forearms])
        #expect(exercise.isCustom)
        #expect(exercise.bodyweightFactor == 0)
        // A retried flow, or a renamed one, makes the same exercise.
        let again = ImportCustomExercise.make(row, name: "My Zottman", account: "demo", source: .alphaProgression,
                                              primaryMuscles: [.biceps], aliases: aliases)
        #expect(again.id == exercise.id)
        #expect(again.name == "My Zottman")
        let input = ExerciseInput(exercise)
        #expect(input.id == exercise.id)
    }

    @Test func plusSetsMakeABodyweightExercise() {
        var row = ImportedExerciseSource(key: key("Weighted Step", "Machine"), name: "Weighted Step", equipment: "Machine")
        row.plusLoads = PlusLoadSummary(kilograms: [20])
        let exercise = ImportCustomExercise.make(row, account: "demo", source: .alphaProgression, primaryMuscles: [.quads],
                                                 aliases: aliases)
        #expect(exercise.kind == .machine)
        #expect(exercise.loadType == .bodyweight)
        #expect(exercise.bodyweightFactor == 1)
    }
}
