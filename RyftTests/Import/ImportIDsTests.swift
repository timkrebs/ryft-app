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

    /// The same spelling, any spelling of the same key, again and again: one id. Accounts, sources and equipment
    /// keep them apart.
    @Test func derivedIDsAreStable() {
        let normalizer = ExerciseAliases.bundled.normalizer
        let a = normalizer.key(name: "Bench Press", equipment: "Barbell")
        let b = normalizer.key(name: "bench-press", equipment: "Langhantel")
        let c = normalizer.key(name: "Press, Bench (Barbell)", equipment: nil)
        let id = ImportCustomExercise.id(account: "demo", source: .alphaProgression, key: a)
        #expect(ImportCustomExercise.id(account: "demo", source: .alphaProgression, key: b) == id)
        #expect(ImportCustomExercise.id(account: "demo", source: .alphaProgression, key: c) == id)
        #expect(ImportCustomExercise.id(account: "demo", source: .alphaProgression, key: a) == id)
        #expect(ImportCustomExercise.id(account: "other", source: .alphaProgression, key: a) != id)
        #expect(ImportCustomExercise.id(account: "demo", source: ImportFormatID(rawValue: "other_app"), key: a) != id)
        let dumbbell = normalizer.key(name: "Bench Press", equipment: "Dumbbell")
        #expect(ImportCustomExercise.id(account: "demo", source: .alphaProgression, key: dumbbell) != id)
    }

    @Test func version5AndVariant() {
        let id = ImportIDs.account("demo").uuid
        #expect(id.6 >> 4 == 5)
        #expect(id.8 >> 6 == 0b10)
    }
}
