import Foundation

/// What a source exercise is matched and remembered by (design §4), and part of the derived custom-exercise id
/// (ADR 0007): never change how it is built once it has shipped.
///
/// - `name`: the name's tokens without equipment words, sorted and unique, joined by a space.
/// - `equipment`: a canonical id from the alias file (`barbell`, `ez_bar`, …); the normalised text when the file names
///   equipment RYFT doesn't know; "" when it names none.
struct SourceExerciseKey: Hashable, Codable, Sendable {
    let name: String
    let equipment: String
}

/// One normalisation for source names, library names and aliases (design §4): fold the text, split it into words,
/// drop stop words, make English plurals singular, apply the alias file's synonyms, then take equipment words out of
/// the name. Pure and deterministic.
struct ExerciseNormalizer: Sendable {
    /// Token sequences to their replacements, both already through `baseTokens`.
    private let synonyms: [[String]: [String]]
    private let longestSynonym: Int
    /// Equipment phrases (after synonyms) to a canonical id.
    private let equipmentPhrases: [[String]: String]
    private let longestEquipmentPhrase: Int
    /// The canonical ids, for telling known equipment from free text.
    let equipmentIDs: Set<String>

    /// Names longer than this are cut. No exercise name needs more words, and it bounds every loop.
    static let maxTokens = 32

    init(synonyms: [[String]: [String]], equipmentPhrases: [[String]: String]) {
        self.synonyms = synonyms
        self.equipmentPhrases = equipmentPhrases
        longestSynonym = synonyms.keys.map(\.count).max() ?? 0
        longestEquipmentPhrase = equipmentPhrases.keys.map(\.count).max() ?? 0
        equipmentIDs = Set(equipmentPhrases.values)
    }

    // MARK: Keys

    /// The key of a name and an equipment field as a file writes them. Known equipment in the field wins, then known
    /// equipment named in the name ("Dumbbell Curl"), then the field's unknown text.
    func key(name: String, equipment: String?) -> SourceExerciseKey {
        let parsed = analyse(name)
        let resolved = switch equipmentField(equipment) {
        case let .known(id): id
        case let .unknown(text): parsed.equipment ?? text
        case .none: parsed.equipment ?? ""
        }
        return SourceExerciseKey(name: Self.joined(parsed.tokens), equipment: resolved)
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

    /// `key.equipment` is one of the alias file's ids (so the equipment filter applies).
    func isKnown(equipment: String) -> Bool { equipmentIDs.contains(equipment) }

    // MARK: Steps

    /// NFKC, case and diacritics folded, `ß` → `ss`.
    static func fold(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ß", with: "ss")
            .lowercased()
    }

    /// Folded words: apostrophes are dropped ("Farmer's" → "farmers"), every other character that isn't a letter or
    /// a digit separates words (`-`, `/`, `·`, brackets, `&`, `+`, …).
    static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in fold(text).unicodeScalars {
            if apostrophes.contains(scalar) { continue }
            if CharacterSet.alphanumerics.contains(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                words.append(String(current))
                current = String.UnicodeScalarView()
                if words.count >= maxTokens { return words }
            }
        }
        if !current.isEmpty { words.append(String(current)) }
        return words
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

    private static let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2019}", "\u{2018}", "`", "\u{00B4}", "\u{02BC}"]

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
