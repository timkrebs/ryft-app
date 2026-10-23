import Foundation
@testable import Ryft

private final class MappingFixtureToken {}

/// Libraries and vocabularies for the mapping tests (I3).
enum MappingFixture {
    /// `Fixtures/Import/builtin-exercises.json`: the platform's built-in library in the `GET /v1/exercises` shape, with
    /// its fixed ids (`uuid5(namespace, "exercise:<slug>")`, `backend/internal/train/train.go`). A snapshot of the seed
    /// on 2026-10-23 (173 exercises); regenerate it when the platform adds built-ins.
    static func builtins() throws -> [Exercise] {
        let bundle = Bundle(for: MappingFixtureToken.self)
        guard let url = bundle.url(forResource: "builtin-exercises", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "builtin-exercises.json"])
        }
        return try APIClient.jsonDecoder.decode([Exercise].self, from: Data(contentsOf: url))
    }

    /// The shipped `exercise-aliases.json`, as the app bundle holds it.
    static func shippedData() throws -> Data {
        guard let url = Bundle.main.url(forResource: ExerciseAliases.resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "exercise-aliases.json"])
        }
        return try Data(contentsOf: url)
    }

    static func shippedFile() throws -> ExerciseAliases.File {
        try JSONDecoder().decode(ExerciseAliases.File.self, from: shippedData())
    }

    static func id(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-4000-8000-\(ImportPad.digits(n, 12))") ?? UUID()
    }

    static func exercise(_ n: Int, _ name: String, de: String? = nil, slug: String? = nil, kind: ExerciseKind,
                         load: LoadType = .weight, custom: Bool = false, archived: Bool = false) -> Exercise {
        Exercise(id: id(n), slug: slug ?? name.lowercased().replacingOccurrences(of: " ", with: "-"), name: name,
                 nameDe: de, kind: kind, primaryMuscles: [.chest], loadType: load, isCustom: custom, archived: archived)
    }

    /// A small vocabulary: three equipment words, a synonym and one alias.
    static func file(aliases: [ExerciseAliases.Entry] = [],
                     synonyms: [String: String] = ["db": "dumbbell", "pullup": "pull up"]) -> ExerciseAliases.File {
        ExerciseAliases.File(
            version: 1,
            equipment: ["barbell": ["barbell", "Langhantel"], "dumbbell": ["dumbbell", "Kurzhantel"],
                        "cable": ["cable", "Kabel"], "machine": ["machine", "Maschine"],
                        "smith_machine": ["smith machine"], "bodyweight": ["bodyweight"], "band": ["band"]],
            kinds: ["barbell": ["barbell"], "dumbbell": ["dumbbell"], "cable": ["cable"],
                    "machine": ["machine", "cable", "cardio"], "smith_machine": ["machine"],
                    "bodyweight": ["bodyweight"], "band": []],
            synonyms: synonyms,
            aliases: aliases)
    }

    static func vocabulary(aliases: [ExerciseAliases.Entry] = []) -> ExerciseAliases {
        ExerciseAliases(file: file(aliases: aliases))
    }
}
