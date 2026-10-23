import Foundation

/// A "new" row's custom exercise (design §4): its id is derived (ADR 0007), so a retried import updates the same
/// exercise instead of creating another. The upload (I5) sends it with `POST /v1/exercises`, one at a time, first.
enum ImportCustomExercise {
    /// The platform's limit for `name`.
    static let maxNameLength = 80

    static func id(account: String, source: ImportFormatID, key: SourceExerciseKey) -> UUID {
        ImportIDs.customExercise(account: ImportIDs.account(account), source: source, key: key)
    }

    /// The equipment's first allowed kind; `machine` when the equipment is unknown, missing or allows none.
    static func kind(for key: SourceExerciseKey, aliases: ExerciseAliases) -> ExerciseKind {
        aliases.allowedKinds(for: key.equipment)?.first ?? .machine
    }

    /// `bodyweight` for bodyweight equipment or `+N` sets, else `weight`.
    static func loadType(for key: SourceExerciseKey, hasPlusSets: Bool, aliases: ExerciseAliases) -> LoadType {
        hasPlusSets || kind(for: key, aliases: aliases) == .bodyweight ? .bodyweight : .weight
    }

    /// The file's name, trimmed and cut to the platform's 80 characters (counted as Unicode scalars, the stricter
    /// count, and never inside a character). Falls back to the key's name.
    static func name(_ text: String, key: SourceExerciseKey) -> String {
        let trimmed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let source = trimmed.isEmpty ? key.name : trimmed
        var out = ""
        var scalars = 0
        for character in source {
            let count = character.unicodeScalars.count
            guard scalars + count <= maxNameLength else { break }
            out.append(character)
            scalars += count
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// The exercise to create for a step-4 row. The user picks the muscles; everything else comes from the file,
    /// unless the user edited the name (the id stays: it follows the key).
    static func make(_ row: ImportedExerciseSource, name edited: String? = nil, account: String, source: ImportFormatID,
                     primaryMuscles: [Muscle], aliases: ExerciseAliases) -> Exercise {
        let key = row.key
        let title = Self.name(edited ?? row.name, key: key)
        let exerciseKind = Self.kind(for: key, aliases: aliases)
        let load = Self.loadType(for: key, hasPlusSets: row.plusLoads != nil, aliases: aliases)
        // As the custom-exercise form makes them (`CustomExerciseDraft`); the platform derives its own slug.
        let slug = title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        return Exercise(id: Self.id(account: account, source: source, key: key), slug: slug, name: title,
                        kind: exerciseKind, primaryMuscles: primaryMuscles, equipment: [exerciseKind.rawValue],
                        loadType: load, bodyweightFactor: load == .bodyweight ? 1 : 0, isCustom: true)
    }
}
