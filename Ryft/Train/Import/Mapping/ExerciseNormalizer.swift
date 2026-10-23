import Foundation

/// What a source exercise is **remembered and derived** by (design §4, ADR 0007): the custom-exercise id and the
/// `ImportMapping` row both come from it. It is frozen and doesn't depend on the alias vocabulary at all (equipment
/// words, synonyms, plurals, stop words), so editing `exercise-aliases.json` never changes an id. **Changing
/// `SourceExerciseKey.fold` is a breaking id change** (every earlier import's custom exercises and remembered choices
/// would no longer be found); `SourceExerciseKeyGoldenTests` pins it.
///
/// - `name`: `fold(name)`, the name as the file wrote it.
/// - `equipment`: `fold(field)`, the equipment field as the file wrote it; "" without a field or with an empty one.
///   Matching reads it through the vocabulary (`ExerciseNormalizer.matchKey`); the key never does.
struct SourceExerciseKey: Hashable, Codable, Sendable {
    let name: String
    let equipment: String

    /// The frozen text rule, in this order:
    /// 1. on the raw scalars: whitespace becomes a space; controls, format characters (Cc, Cf) and default-ignorable
    ///    scalars (soft hyphen, zero-width and bidi marks, BOM, variation selectors) and apostrophes
    ///    (`' ‘ ’ ‛ ʹ ʻ ʼ ʽ ´ ′ ` ＇`) are dropped;
    /// 2. NFKC;
    /// 3. lowercase (Unicode default mapping, no locale);
    /// 4. every character that isn't a letter, mark or digit becomes a space; runs of spaces collapse; trimmed.
    static func fold(_ text: String) -> String {
        var cleaned = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                cleaned.append(" ")
            } else if !isDropped(scalar) {
                cleaned.append(scalar)
            }
        }
        let lowered = String(cleaned).precomposedStringWithCompatibilityMapping.lowercased()
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace, !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(scalar)
            } else if !isDropped(scalar) {
                pendingSpace = true
            }
        }
        return String(out)
    }

    /// Dropped without a trace (step 1; again after NFKC, which can produce some).
    static func isDropped(_ scalar: Unicode.Scalar) -> Bool {
        if apostrophes.contains(scalar) { return true }
        switch scalar.properties.generalCategory {
        case .control, .format: return true
        default: return scalar.properties.isDefaultIgnorableCodePoint
        }
    }

    static let apostrophes: Set<Unicode.Scalar> = [
        "'", "`", "\u{00B4}", "\u{02B9}", "\u{02BB}", "\u{02BC}", "\u{02BD}", "\u{2018}", "\u{2019}", "\u{201B}",
        "\u{2032}", "\u{FF07}",
    ]

    /// The name for display when the file's own can't be used (`ImportCustomExercise.name`): words capitalised.
    var displayName: String { name.capitalized(with: Locale(identifier: "en_US_POSIX")) }
}

/// The key the matcher compares (design §4), never stored: the vocabulary may change it at any time.
struct MatchKey: Hashable, Sendable {
    /// The name's tokens without equipment words, sorted and unique, joined by a space.
    let name: String
    /// A canonical equipment id, the normalised text of equipment RYFT doesn't know, or "".
    let equipment: String
}

/// Normalisation for matching (design §4): the frozen fold of `SourceExerciseKey`, then diacritics folded, `ß` → `ss`,
/// stop words dropped, English plurals made singular, the alias file's synonyms applied and equipment words taken out
/// of the name. Matching a raw name and matching its `SourceExerciseKey` give the same result. Pure, deterministic.
struct ExerciseNormalizer: Sendable {
    /// Token sequences to their replacements, both already through `baseTokens`.
    private let synonyms: [[String]: [String]]
    private let longestSynonym: Int
    /// Equipment phrases (after synonyms) to a canonical id.
    private let equipmentPhrases: [[String]: String]
    private let longestEquipmentPhrase: Int
    /// Equipment id → the library kinds it allows, to tell the more specific of two (`matchKey`).
    private let kinds: [String: Set<ExerciseKind>]
    /// The canonical ids, for telling known equipment from free text.
    let equipmentIDs: Set<String>

    /// Names longer than this are cut for matching. No exercise name needs more words, and it bounds every loop.
    static let maxTokens = 32

    init(synonyms: [[String]: [String]], equipmentPhrases: [[String]: String], kinds: [String: [ExerciseKind]] = [:]) {
        self.synonyms = synonyms
        self.equipmentPhrases = equipmentPhrases
        self.kinds = kinds.mapValues(Set.init)
        longestSynonym = synonyms.keys.map(\.count).max() ?? 0
        longestEquipmentPhrase = equipmentPhrases.keys.map(\.count).max() ?? 0
        equipmentIDs = Set(equipmentPhrases.values)
    }

    // MARK: Keys

    /// The frozen key of a name and an equipment field as a file writes them (`SourceExerciseKey`). No vocabulary.
    func key(name: String, equipment: String?) -> SourceExerciseKey {
        SourceExerciseKey(name: SourceExerciseKey.fold(name), equipment: SourceExerciseKey.fold(equipment ?? ""))
    }

    /// The match key of a stored key: the same as for the raw name and field it came from.
    func matchKey(_ key: SourceExerciseKey) -> MatchKey {
        matchKey(name: key.name, equipment: key.equipment.isEmpty ? nil : key.equipment)
    }

    /// Equipment for matching, from the field and the words of the name:
    /// - both name known equipment and they differ: the more specific (`isMoreSpecific`: "Trap Bar Deadlift · Barbell"
    ///   is trap bar, "Cable Crossover · Machine" is cable); when neither is, the field's, and the name keeps its
    ///   equipment words, so a contradiction ("Dumbbell Curl · Barbell") never matches exactly;
    /// - otherwise known equipment in the field, then in the name, then the field's unknown text.
    func matchKey(name: String, equipment: String?) -> MatchKey {
        let tokens = applySynonyms(Self.baseTokens(name))
        let (rest, found) = extractEquipment(tokens)
        let inName = found.first
        let stripped = Self.sortedUnique(rest.isEmpty ? tokens : rest)
        switch equipmentField(equipment) {
        case let .known(field):
            guard let inName, inName != field else { return MatchKey(name: Self.joined(stripped), equipment: field) }
            if isMoreSpecific(inName, than: field) { return MatchKey(name: Self.joined(stripped), equipment: inName) }
            if isMoreSpecific(field, than: inName) { return MatchKey(name: Self.joined(stripped), equipment: field) }
            return MatchKey(name: Self.joined(Self.sortedUnique(tokens)), equipment: field)
        case let .unknown(text):
            return MatchKey(name: Self.joined(stripped), equipment: inName ?? text)
        case .none:
            return MatchKey(name: Self.joined(stripped), equipment: inName ?? "")
        }
    }

    /// A name's tokens without equipment words (sorted, unique) and the first equipment it names. A name made only of
    /// equipment words keeps them, so it never becomes empty.
    func analyse(_ text: String) -> (tokens: [String], equipment: String?) {
        let tokens = applySynonyms(Self.baseTokens(text))
        let (rest, found) = extractEquipment(tokens)
        return (Self.sortedUnique(rest.isEmpty ? tokens : rest), found.first)
    }

    enum EquipmentField: Equatable {
        case none
        case known(String)
        case unknown(String)
    }

    /// An equipment field: the first known equipment phrase in it, else its normalised text.
    func equipmentField(_ text: String?) -> EquipmentField {
        guard let text else { return .none }
        let tokens = applySynonyms(Self.baseTokens(text))
        guard !tokens.isEmpty else { return .none }
        if let id = extractEquipment(tokens).found.first { return .known(id) }
        return .unknown(Self.joined(Self.sortedUnique(tokens)))
    }

    /// `equipment` is one of the alias file's ids (so the equipment filter applies).
    func isKnown(equipment: String) -> Bool { equipmentIDs.contains(equipment) }

    /// `a` names a narrower kind of equipment than `b`: it allows fewer library kinds (Smith machine or cable within
    /// machine), or the same ones while `b` is a kind's own name (trap bar or EZ bar within barbell).
    func isMoreSpecific(_ a: String, than b: String) -> Bool {
        guard let small = kinds[a], let large = kinds[b] else { return false }
        if small != large { return small.isSubset(of: large) }
        return ExerciseKind(rawValue: a) == nil && ExerciseKind(rawValue: b) != nil
    }

    // MARK: Steps

    /// `SourceExerciseKey.fold`, then diacritics folded and `ß` → `ss`.
    static func fold(_ text: String) -> String {
        SourceExerciseKey.fold(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ß", with: "ss")
            .lowercased()
    }

    /// Folded words, at most `maxTokens`.
    static func words(_ text: String) -> [String] {
        Array(fold(text).split(separator: " ").prefix(maxTokens).map(String.init))
    }

    /// Words without stop words, plurals made singular. Synonyms and equipment come after.
    static func baseTokens(_ text: String) -> [String] {
        words(text).filter { !stopWords.contains($0) }.map(singular).filter { !$0.isEmpty }
    }

    /// English plurals, one token at a time (design §4). German plurals are synonyms in the alias file.
    static func singular(_ token: String) -> String {
        if token.hasSuffix("sses") { return String(token.dropLast(2)) }
        if token.hasSuffix("ches") || token.hasSuffix("shes") || token.hasSuffix("xes") { return String(token.dropLast(2)) }
        if token.hasSuffix("ies"), token.count > 4 { return String(token.dropLast(3)) + "y" }
        if token.hasSuffix("s"), token.count >= 3, !token.hasSuffix("ss"), !token.hasSuffix("us"), !token.hasSuffix("is") {
            return String(token.dropLast())
        }
        return token
    }

    /// en `with the a an on of and`, de `mit am an der die das und im zum` ("an" is in both).
    static let stopWords: Set<String> = Set([
        "with", "the", "a", "an", "on", "of", "and",
        "mit", "am", "an", "der", "die", "das", "und", "im", "zum",
    ])

    static func sortedUnique(_ tokens: [String]) -> [String] { Array(Set(tokens)).sorted() }

    static func joined(_ tokens: [String]) -> String { tokens.joined(separator: " ") }

    /// Longest phrase first, left to right.
    func applySynonyms(_ tokens: [String]) -> [String] {
        guard longestSynonym > 0 else { return tokens }
        var out: [String] = []
        var rest = ArraySlice(tokens)
        while let first = rest.first {
            var consumed = 0
            for length in stride(from: min(longestSynonym, rest.count), through: 1, by: -1) {
                if let replacement = synonyms[Array(rest.prefix(length))] {
                    out += replacement
                    consumed = length
                    break
                }
            }
            if consumed == 0 {
                out.append(first)
                consumed = 1
            }
            rest = rest.dropFirst(consumed)
        }
        return out
    }

    /// The tokens without equipment phrases, and the equipment ids found, in order.
    private func extractEquipment(_ tokens: [String]) -> (rest: [String], found: [String]) {
        guard longestEquipmentPhrase > 0 else { return (tokens, []) }
        var rest: [String] = []
        var found: [String] = []
        var remaining = ArraySlice(tokens)
        while let first = remaining.first {
            var consumed = 0
            for length in stride(from: min(longestEquipmentPhrase, remaining.count), through: 1, by: -1) {
                if let id = equipmentPhrases[Array(remaining.prefix(length))] {
                    if !found.contains(id) { found.append(id) }
                    consumed = length
                    break
                }
            }
            if consumed == 0 {
                rest.append(first)
                consumed = 1
            }
            remaining = remaining.dropFirst(consumed)
        }
        return (rest, found)
    }
}
