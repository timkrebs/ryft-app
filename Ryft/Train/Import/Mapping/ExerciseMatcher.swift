import Foundation

/// How one source exercise maps to the library (design §4).
struct ExerciseMatch: Equatable, Sendable {
    let key: SourceExerciseKey
    /// nil: nothing fits, the row offers a new custom exercise.
    let exerciseID: UUID?
    let tier: Tier?
    /// 0…1. Shown only as words (`isLikely`), never as a number (ui.md 7.2).
    let confidence: Double
    /// Up to three runners-up, best first.
    let alternatives: [UUID]

    enum Tier: String, Codable, Sendable {
        case remembered, exact, alias, fuzzy
    }

    /// A fuzzy suggestion is never accepted without a tap, whatever its score; no match needs a new exercise.
    var needsReview: Bool { tier == .fuzzy || exerciseID == nil }

    /// A check row's words: "Likely match" when true, else "Possible match".
    var isLikely: Bool { confidence >= ExerciseMatcher.likelyThreshold }
}

/// Matches source exercises to the library (design §4). Pure, `Sendable` and deterministic: the first tier that hits
/// wins (remembered → exact → alias → fuzzy), and ties break by score, then custom before built-in, then name, then id.
///
/// **The equipment filter is hard.** A key with known equipment only reaches exercises whose `kind` that equipment
/// allows (`ExerciseAliases.kinds`); unknown or missing equipment means no filter and confidence × 0.8. An exact or
/// alias name that fits several exercises when the equipment is unknown is a guess, so it comes back as `.fuzzy`.
struct ExerciseMatcher: Sendable {
    static let fuzzyThreshold = 0.5
    static let likelyThreshold = 0.7
    static let unknownEquipmentFactor = 0.8
    static let exactConfidence = 1.0
    static let aliasConfidence = 0.95
    static let maxAlternatives = 3

    let normalizer: ExerciseNormalizer
    /// Distinct alias slugs this library doesn't have (or has only as a custom exercise): ignored, counted.
    let unknownAliasSlugs: Int

    private let aliases: ExerciseAliases
    private let library: Set<UUID>
    /// Library name key → the exercises with that name, and the equipment their name names (nil: none).
    private let exactIndex: [String: [Named]]
    /// Alias name key → target exercises, and the equipment the alias is for (nil: any).
    private let aliasIndex: [String: [Named]]
    /// Token → the names (library and alias) that contain it.
    private let fuzzyIndex: [String: [FuzzyName]]
    private let remembered: [SourceExerciseKey: UUID]

    private struct Candidate: Hashable, Sendable {
        let id: UUID
        let isCustom: Bool
        let name: String
        let kind: ExerciseKind
    }

    private struct Named: Hashable, Sendable {
        let candidate: Candidate
        let equipment: String?
    }

    private struct FuzzyName: Sendable {
        let serial: Int
        let candidate: Candidate
        let tokenCount: Int
        /// An alias name for one equipment only; nil for library names and alias names for any equipment.
        let aliasEquipment: String?
    }

    private struct Scored {
        let candidate: Candidate
        let score: Double
    }

    /// `library`: what `GET /v1/exercises` returned, custom exercises included; archived ones are left out.
    /// `remembered`: this account's earlier choices for this source (`ImportMappingStore`).
    init(library: [Exercise], aliases: ExerciseAliases, remembered: [SourceExerciseKey: UUID]) {
        let signpost = ImportLog.signposter.beginInterval("match index", id: ImportLog.signposter.makeSignpostID())
        defer { ImportLog.signposter.endInterval("match index", signpost) }
        let normalizer = aliases.normalizer
        var ids: Set<UUID> = []
        var bySlug: [String: Candidate] = [:]
        var exact: [String: Set<Named>] = [:]
        var fuzzy: [String: [FuzzyName]] = [:]
        var serial = 0
        func addFuzzy(_ tokens: [String], _ candidate: Candidate, aliasEquipment: String?) {
            let name = FuzzyName(serial: serial, candidate: candidate, tokenCount: tokens.count, aliasEquipment: aliasEquipment)
            serial += 1
            for token in tokens { fuzzy[token, default: []].append(name) }
        }
        for exercise in library where !exercise.archived && !ids.contains(exercise.id) {
            ids.insert(exercise.id)
            let candidate = Candidate(id: exercise.id, isCustom: exercise.isCustom, name: exercise.name, kind: exercise.kind)
            if !exercise.isCustom, !exercise.slug.isEmpty, bySlug[exercise.slug] == nil { bySlug[exercise.slug] = candidate }
            for name in Set([exercise.name, exercise.nameEn, exercise.nameDe]).sorted() {
                let parsed = normalizer.analyse(name)
                guard !parsed.tokens.isEmpty else { continue }
                exact[ExerciseNormalizer.joined(parsed.tokens), default: []]
                    .insert(Named(candidate: candidate, equipment: parsed.equipment))
                addFuzzy(parsed.tokens, candidate, aliasEquipment: nil)
            }
        }
        var aliasIndex: [String: Set<Named>] = [:]
        var unknown: Set<String> = []
        for (key, slug) in aliases.index.sorted(by: { ($0.key.name, $0.key.equipment ?? "") < ($1.key.name, $1.key.equipment ?? "") }) {
            guard let candidate = bySlug[slug] else {
                unknown.insert(slug)
                continue
            }
            aliasIndex[key.name, default: []].insert(Named(candidate: candidate, equipment: key.equipment))
            addFuzzy(key.name.split(separator: " ").map(String.init), candidate, aliasEquipment: key.equipment)
        }
        self.normalizer = normalizer
        self.aliases = aliases
        self.library = ids
        exactIndex = exact.mapValues { Array($0) }
        self.aliasIndex = aliasIndex.mapValues { Array($0) }
        fuzzyIndex = fuzzy
        self.remembered = remembered
        unknownAliasSlugs = unknown.count
    }

    // MARK: Matching

    func key(name: String, equipment: String?) -> SourceExerciseKey {
        normalizer.key(name: name, equipment: equipment)
    }

    func match(name: String, equipment: String?) -> ExerciseMatch {
        match(key: key(name: name, equipment: equipment))
    }

    /// Many at once (the import's distinct exercises), as one signposted interval.
    func match(_ keys: [SourceExerciseKey]) -> [ExerciseMatch] {
        let signpost = ImportLog.signposter.beginInterval("match", id: ImportLog.signposter.makeSignpostID())
        defer { ImportLog.signposter.endInterval("match", signpost) }
        return keys.map { match(key: $0) }
    }

    func match(key: SourceExerciseKey) -> ExerciseMatch {
        let allowed = aliases.allowedKinds(for: key.equipment)
        let factor = allowed == nil ? Self.unknownEquipmentFactor : 1
        let ranked = rankedByTokens(key, allowed: allowed)

        if let id = remembered[key], library.contains(id) {
            return ExerciseMatch(key: key, exerciseID: id, tier: .remembered, confidence: 1,
                                 alternatives: alternatives(ranked.map(\.candidate), excluding: id))
        }
        if let found = decide(exactHits(key, allowed: allowed), tier: .exact, base: Self.exactConfidence,
                              factor: factor, ranked: ranked, key: key) {
            return found
        }
        if let found = decide(aliasHits(key, allowed: allowed), tier: .alias, base: Self.aliasConfidence,
                              factor: factor, ranked: ranked, key: key) {
            return found
        }
        if let best = ranked.first {
            return ExerciseMatch(key: key, exerciseID: best.candidate.id, tier: .fuzzy, confidence: best.score * factor,
                                 alternatives: alternatives(ranked.dropFirst().map(\.candidate), excluding: best.candidate.id))
        }
        return ExerciseMatch(key: key, exerciseID: nil, tier: nil, confidence: 0, alternatives: [])
    }

    // MARK: Tiers

    /// Library names equal to the key's name. Known equipment: the kind passes and the name names no other equipment.
    /// Unknown equipment: only names that name no equipment ("Bench Press" is "Bench press", not "Dumbbell bench press").
    private func exactHits(_ key: SourceExerciseKey, allowed: [ExerciseKind]?) -> [Candidate] {
        let named = exactIndex[key.name] ?? []
        let hits = named.filter { entry in
            guard let allowed else { return entry.equipment == nil }
            return allowed.contains(entry.candidate.kind) && (entry.equipment == nil || entry.equipment == key.equipment)
        }
        return unique(hits.map(\.candidate))
    }

    /// Alias names equal to the key's name: for its equipment first, then for any equipment; the kind must pass.
    /// Unknown equipment: only aliases for any equipment.
    private func aliasHits(_ key: SourceExerciseKey, allowed: [ExerciseKind]?) -> [Candidate] {
        let named = aliasIndex[key.name] ?? []
        guard let allowed else { return unique(named.filter { $0.equipment == nil }.map(\.candidate)) }
        let passes = named.filter { allowed.contains($0.candidate.kind) }
        let specific = passes.filter { $0.equipment == key.equipment }
        return unique((specific.isEmpty ? passes.filter { $0.equipment == nil } : specific).map(\.candidate))
    }

    private func decide(_ hits: [Candidate], tier: ExerciseMatch.Tier, base: Double, factor: Double,
                        ranked: [Scored], key: SourceExerciseKey) -> ExerciseMatch? {
        let sorted = hits.sorted(by: Self.precedes)
        guard let first = sorted.first else { return nil }
        let others = alternatives(Array(sorted.dropFirst()) + ranked.map(\.candidate), excluding: first.id)
        let ambiguous = sorted.count > 1 && factor < 1
        return ExerciseMatch(key: key, exerciseID: first.id, tier: ambiguous ? .fuzzy : tier, confidence: base * factor,
                             alternatives: others)
    }

    /// Token Dice `2|A∩B| / (|A|+|B|)` ≥ 0.5 over the exercises the filter allows, each by its best name.
    private func rankedByTokens(_ key: SourceExerciseKey, allowed: [ExerciseKind]?) -> [Scored] {
        let tokens = Set(key.name.split(separator: " ").map(String.init))
        guard !tokens.isEmpty else { return [] }
        var shared: [Int: (name: FuzzyName, common: Int)] = [:]
        for token in tokens {
            for name in fuzzyIndex[token] ?? [] { shared[name.serial, default: (name, 0)].common += 1 }
        }
        var best: [Candidate: Double] = [:]
        for (name, common) in shared.values {
            if let allowed {
                guard allowed.contains(name.candidate.kind) else { continue }
                if let only = name.aliasEquipment, only != key.equipment { continue }
            }
            let score = 2 * Double(common) / Double(tokens.count + name.tokenCount)
            guard score >= Self.fuzzyThreshold else { continue }
            best[name.candidate] = max(best[name.candidate] ?? 0, score)
        }
        return best.map { Scored(candidate: $0.key, score: $0.value) }.sorted { a, b in
            a.score != b.score ? a.score > b.score : Self.precedes(a.candidate, b.candidate)
        }
    }

    /// Custom before built-in, then name, then id: the order for equal scores.
    private static func precedes(_ x: Candidate, _ y: Candidate) -> Bool {
        if x.isCustom != y.isCustom { return x.isCustom }
        if x.name != y.name { return x.name < y.name }
        return x.id.uuidString < y.id.uuidString
    }

    private func alternatives(_ candidates: [Candidate], excluding id: UUID) -> [UUID] {
        var seen: Set<UUID> = [id]
        var out: [UUID] = []
        for candidate in candidates where out.count < Self.maxAlternatives && seen.insert(candidate.id).inserted {
            out.append(candidate.id)
        }
        return out
    }

    private func unique(_ candidates: [Candidate]) -> [Candidate] {
        var seen: Set<UUID> = []
        return candidates.filter { seen.insert($0.id).inserted }
    }
}
