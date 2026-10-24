import Foundation

/// A "new" row's custom exercise (design §4): its id is derived (ADR 0007), so a retried import updates the same
/// exercise instead of creating another. The upload (I5) sends it with `POST /v1/exercises`, one at a time, first.
enum ImportCustomExercise {
    /// The platform's limit for `name`.
    static let maxNameLength = 80

    static func id(account: String, source: ImportFormatID, key: SourceExerciseKey) -> UUID {
        ImportIDs.customExercise(account: ImportIDs.account(account), source: source, key: key)
    }

    /// The first kind the equipment allows (named in the field or in the name, as matching reads it); `machine` when
    /// the equipment is unknown, missing or allows none.
    static func kind(for key: SourceExerciseKey, aliases: ExerciseAliases) -> ExerciseKind {
        aliases.allowedKinds(for: aliases.normalizer.matchKey(key).equipment)?.first ?? .machine
    }

    /// `bodyweight` for bodyweight equipment or `+N` sets, else `weight`.
    static func loadType(for key: SourceExerciseKey, hasPlusSets: Bool, aliases: ExerciseAliases) -> LoadType {
        hasPlusSets || kind(for: key, aliases: aliases) == .bodyweight ? .bodyweight : .weight
    }

    /// A name the platform takes (1–80 characters): controls and format characters (Cc, Cf: NUL, soft hyphens,
    /// zero-width and bidi marks, BOM) are dropped, whitespace collapsed, and the text cut to 80 Unicode scalars (the
    /// stricter count) without splitting a character. When nothing is left: the key's display form, then that form
    /// without combining marks, then "Imported exercise".
    static func name(_ text: String, key: SourceExerciseKey) -> String {
        for candidate in [text, key.displayName, withoutMarks(key.displayName)] {
            let result = cut(clean(candidate))
            if !result.isEmpty { return result }
        }
        return String(localized: "Imported exercise",
                      comment: "Training import: the name of a new custom exercise when the file's name can't be used.")
    }

    /// Without Cc and Cf characters; whitespace collapsed to single spaces, trimmed.
    static func clean(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                scalars.append(" ")
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format: continue
            default: scalars.append(scalar)
            }
        }
        return String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// At most `maxNameLength` scalars, whole characters only, trailing spaces trimmed.
    static func cut(_ text: String) -> String {
        var out = ""
        var scalars = 0
        for character in text {
            let count = character.unicodeScalars.count
            guard scalars + count <= maxNameLength else { break }
            out.append(character)
            scalars += count
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static func withoutMarks(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: continue
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// The exercise to create for a step-4 row. The user picks the muscles; everything else comes from the file,
    /// unless the user edited the name (the id stays: it follows the key).
    ///
    /// For I4: remember the "new" row's choice as this exercise's id when Import is tapped
    /// (`ImportMappingStore.remember`). Once I5 has created it, the next import of the same file finds it in the
    /// library and matches it as `.remembered`, so it is neither asked about nor created again.
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
