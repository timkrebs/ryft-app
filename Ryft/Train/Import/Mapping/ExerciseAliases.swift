import Foundation

/// The curated vocabulary in `Resources/exercise-aliases.json` (design §4): equipment words and the library kinds each
/// one allows, synonyms, and alias names for built-in exercises by platform slug, in English and German. General
/// gym vocabulary, never anyone's own export. Loaded and checked once; a broken file falls back to the kinds' own
/// names, so matching stays correct, only less helpful.
struct ExerciseAliases: Sendable {
    /// The file's shape.
    struct File: Decodable, Sendable {
        var version: Int
        /// Canonical id → phrases (`"dumbbell": ["dumbbell", "db", "kurzhantel"]`).
        var equipment: [String: [String]]
        /// Canonical id → the `ExerciseKind`s it allows, the custom-exercise kind first. `[]` allows none.
        var kinds: [String: [String]]
        /// Phrase → replacement, applied before equipment words are taken out.
        var synonyms: [String: String]
        var aliases: [Entry]
    }

    struct Entry: Decodable, Equatable, Sendable {
        var slug: String
        /// nil: the names apply with any equipment the target's kind allows (or none).
        var equipment: String?
        var en: [String]?
        var de: [String]?
    }

    /// An alias name, normalised: the name tokens and the equipment it is for (nil: any).
    struct Key: Hashable, Sendable {
        let name: String
        let equipment: String?
    }

    /// What was wrong with the file. Each problem drops only its own part; the shipped file has none (tests).
    struct Issues: Equatable, Sendable {
        var unknownEquipment = 0
        var unknownKinds = 0
        var missingKinds = 0
        var emptyPhrases = 0
        var conflictingPhrases = 0
        var conflictingKeys = 0
        var missingLanguage = 0
        var invalidSlugs = 0

        var total: Int {
            unknownEquipment + unknownKinds + missingKinds + emptyPhrases + conflictingPhrases + conflictingKeys
                + missingLanguage + invalidSlugs
        }
    }

    enum LoadError: Error, Equatable {
        case unsupportedVersion(Int)
    }

    static let version = 1

    let normalizer: ExerciseNormalizer
    /// Equipment id → allowed kinds, the custom-exercise kind first.
    let kinds: [String: [ExerciseKind]]
    /// Alias names → platform slug.
    let index: [Key: String]
    /// Alias entries read (with at least one usable name).
    let entryCount: Int
    let issues: Issues

    // MARK: Loading

    /// Throws for a file that isn't JSON of this shape or version; smaller problems are dropped and counted.
    init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.version == Self.version else { throw LoadError.unsupportedVersion(file.version) }
        self.init(file: file)
    }

    init(file: File) {
        var issues = Issues()

        // Synonyms first: equipment phrases and alias names are read through them.
        var synonyms: [[String]: [String]] = [:]
        for (phrase, replacement) in file.synonyms.sorted(by: { $0.key < $1.key }) {
            let from = ExerciseNormalizer.baseTokens(phrase)
            let to = ExerciseNormalizer.baseTokens(replacement)
            guard !from.isEmpty, !to.isEmpty else {
                issues.emptyPhrases += 1
                continue
            }
            if let existing = synonyms[from], existing != to {
                issues.conflictingPhrases += 1
                continue
            }
            synonyms[from] = to
        }
        let reader = ExerciseNormalizer(synonyms: synonyms, equipmentPhrases: [:])

        // Equipment phrases; the id itself is one ("ez_bar" → "ez bar"), so a key's equipment reads back as itself.
        var phrases: [[String]: String] = [:]
        var conflicted: Set<[String]> = []
        for (id, list) in file.equipment.sorted(by: { $0.key < $1.key }) {
            for phrase in [id.replacingOccurrences(of: "_", with: " ")] + list {
                let tokens = reader.applySynonyms(ExerciseNormalizer.baseTokens(phrase))
                guard !tokens.isEmpty else {
                    issues.emptyPhrases += 1
                    continue
                }
                if let owner = phrases[tokens], owner != id {
                    conflicted.insert(tokens)
                    issues.conflictingPhrases += 1
                }
                phrases[tokens] = id
            }
        }
        for tokens in conflicted { phrases[tokens] = nil }

        var kinds: [String: [ExerciseKind]] = [:]
        for id in file.equipment.keys {
            guard let raw = file.kinds[id] else {
                issues.missingKinds += 1
                kinds[id] = []
                continue
            }
            var list: [ExerciseKind] = []
            for value in raw {
                guard let kind = ExerciseKind(rawValue: value) else {
                    issues.unknownKinds += 1
                    continue
                }
                if !list.contains(kind) { list.append(kind) }
            }
            kinds[id] = list
        }
        let normalizer = ExerciseNormalizer(synonyms: synonyms, equipmentPhrases: phrases, kinds: kinds)

        // Alias names. A key that two slugs claim is dropped: an alias must never be a guess.
        var index: [Key: String] = [:]
        var clashes: Set<Key> = []
        var entries = 0
        for entry in file.aliases {
            guard Self.isSlug(entry.slug) else {
                issues.invalidSlugs += 1
                continue
            }
            if let equipment = entry.equipment, kinds[equipment] == nil {
                issues.unknownEquipment += 1
                continue
            }
            let en = entry.en ?? [], de = entry.de ?? []
            if en.isEmpty || de.isEmpty { issues.missingLanguage += 1 }
            var used = false
            for name in en + de {
                // Keyed as a file's exercise with this name and equipment field would be.
                let match = normalizer.matchKey(name: name, equipment: entry.equipment)
                guard !match.name.isEmpty else {
                    issues.emptyPhrases += 1
                    continue
                }
                let key = Key(name: match.name, equipment: match.equipment.isEmpty ? nil : match.equipment)
                if let owner = index[key], owner != entry.slug {
                    clashes.insert(key)
                    issues.conflictingKeys += 1
                }
                index[key] = entry.slug
                used = true
            }
            if used { entries += 1 }
        }
        for key in clashes { index[key] = nil }

        self.normalizer = normalizer
        self.kinds = kinds
        self.index = index
        entryCount = entries
        self.issues = issues
    }

    /// The bundled file, else `fallback`. A broken file is logged (counts only) and never stops an import.
    static func load(_ data: Data?) -> ExerciseAliases {
        guard let data else {
            ImportLog.logger.error("Exercise aliases missing; using the kinds only")
            return .fallback
        }
        do {
            let aliases = try ExerciseAliases(data: data)
            if aliases.issues.total > 0 {
                ImportLog.logger.error("Exercise aliases: \(aliases.issues.total) problems dropped")
            }
            return aliases
        } catch {
            ImportLog.logger.error("Exercise aliases unreadable; using the kinds only")
            return .fallback
        }
    }

    /// Each library kind is its own equipment word; no synonyms, no aliases.
    static let fallback: ExerciseAliases = {
        let ids = ExerciseKind.allCases.filter { $0 != .cardio }.map(\.rawValue)
        let pairs = ids.map { ($0, [$0]) }
        return ExerciseAliases(file: File(version: ExerciseAliases.version, equipment: Dictionary(uniqueKeysWithValues: pairs),
                                          kinds: Dictionary(uniqueKeysWithValues: pairs), synonyms: [:], aliases: []))
    }()

    static let resourceName = "exercise-aliases"

    /// Read once, on first use. The import flow reaches it through `loadBundled()`, off the main actor.
    static let bundled: ExerciseAliases = {
        let signpost = ImportLog.signposter.beginInterval("aliases", id: ImportLog.signposter.makeSignpostID())
        defer { ImportLog.signposter.endInterval("aliases", signpost) }
        let url = Bundle.main.url(forResource: ExerciseAliases.resourceName, withExtension: "json")
        return ExerciseAliases.load(url.flatMap { try? Data(contentsOf: $0) })
    }()

    @concurrent
    static func loadBundled() async -> ExerciseAliases {
        MainThread.assertOff("Loading the exercise aliases")
        return bundled
    }

    // MARK: Helpers

    /// The kinds an equipment id allows; nil for equipment the file doesn't know (no filter).
    func allowedKinds(for equipment: String) -> [ExerciseKind]? { kinds[equipment] }

    /// `a-z`, digits and `-`, as the platform's slugs.
    static func isSlug(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }
}
