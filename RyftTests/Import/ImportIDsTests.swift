import Foundation
import Testing
@testable import Ryft

/// ADR 0007's recipe. The vectors were computed independently (Python's `uuid.uuid5`); a change to the namespace, the
/// separator, the field order or the key normalisation fails here, and would duplicate every earlier import.
@Suite("Import ids")
struct ImportIDsTests {
    @Test func rfc9562Vector() throws {
        let dns = try #require(UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8"))
        #expect(ImportIDs.v5(namespace: dns, name: "www.example.com").uuidString.lowercased()
            == "2ed6657d-e927-568b-95e1-2665a8aea6a2")
    }

    @Test func namespace() {
        #expect(ImportIDs.namespace.uuidString.lowercased() == "aed18370-8351-4f38-9f14-af711a508076")
        #expect(ImportIDs.separator == "\u{1F}")
    }

    @Test func accounts() {
        #expect(ImportIDs.account("demo").uuidString.lowercased() == "e62a23e6-b89b-5e0b-af84-f3e1ef110388")
        // Supabase ids are lowercased first, so either spelling gives one id.
        #expect(ImportIDs.account("8F7C2A1E-3B4D-4C5E-9F60-1A2B3C4D5E6F").uuidString.lowercased()
            == "d7a397c9-2b3d-57f9-a754-4f4d9d76ef4b")
        #expect(ImportIDs.account("8f7c2a1e-3b4d-4c5e-9f60-1a2b3c4d5e6f") == ImportIDs.account("8F7C2A1E-3B4D-4C5E-9F60-1A2B3C4D5E6F"))
    }

    @Test func customExercises() {
        let bench = SourceExerciseKey(name: "bench press", equipment: "barbell")
        let unknown = SourceExerciseKey(name: "curl zottman", equipment: "")
        #expect(ImportCustomExercise.id(account: "demo", source: .alphaProgression, key: bench).uuidString.lowercased()
            == "fc6311d5-344f-5d54-ad65-40c48383dd8e")
        #expect(ImportCustomExercise.id(account: "demo", source: .alphaProgression, key: unknown).uuidString.lowercased()
            == "94f03e81-1189-5884-9f8e-40e2453fb53c")
    }

    /// The same name and equipment field, in any case, spacing or punctuation: one id, again and again. Accounts,
    /// sources and equipment keep ids apart, and so does a different wording or another spelling of the same
    /// equipment (the key is the file's text, never the matcher's reading of it).
    @Test func derivedIDsAreStable() {
        let normalizer = ExerciseAliases.bundled.normalizer
        func id(_ name: String, _ equipment: String?, account: String = "demo", source: ImportFormatID = .alphaProgression) -> UUID {
            ImportCustomExercise.id(account: account, source: source, key: normalizer.key(name: name, equipment: equipment))
        }
        let bench = id("Bench Press", "Barbell")
        #expect(id("bench-press", "BARBELL") == bench)
        #expect(id("Bench Press", "Langhantel") != bench)
        #expect(id("Bench Press", "Barbells") != bench)
        #expect(id("  BENCH  PRESS ", "barbell") == bench)
        #expect(id("Bench Press", "Barbell") == bench)
        #expect(id("Bench Press", "Barbell", account: "other") != bench)
        #expect(id("Bench Press", "Barbell", source: ImportFormatID(rawValue: "other_app")) != bench)
        #expect(id("Bench Press", "Dumbbell") != bench)
        #expect(id("Press, Bench", "Barbell") != bench)
        #expect(id("Bench Presses", "Barbell") != bench)
    }

    /// Editing the alias vocabulary (equipment words, synonyms, plurals, alias names) never moves an id: a file's
    /// custom exercises and remembered choices stay found after an app update.
    @Test func idsDontDependOnTheVocabulary() throws {
        let bare = ExerciseAliases.fallback.normalizer
        let full = ExerciseAliases.bundled.normalizer
        var moved: [String] = []
        for (name, equipment) in try ExerciseNormalizerTests.fixturePairs() {
            let a = ImportCustomExercise.id(account: "demo", source: .alphaProgression, key: bare.key(name: name, equipment: equipment))
            let b = ImportCustomExercise.id(account: "demo", source: .alphaProgression, key: full.key(name: name, equipment: equipment))
            if a != b { moved.append(name) }
        }
        #expect(moved == [])
    }

    @Test func version5AndVariant() {
        let id = ImportIDs.account("demo").uuid
        #expect(id.6 >> 4 == 5)
        #expect(id.8 >> 6 == 0b10)
    }
}
