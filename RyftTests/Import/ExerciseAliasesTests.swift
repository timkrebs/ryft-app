import Foundation
import Testing
@testable import Ryft

@Suite("Exercise aliases")
struct ExerciseAliasesTests {
    // MARK: The shipped file

    @Test func shippedFileIsBundledAndClean() throws {
        let data = try MappingFixture.shippedData()
        let aliases = try ExerciseAliases(data: data)
        #expect(aliases.issues == ExerciseAliases.Issues())
        #expect(aliases.entryCount >= 100)
        #expect(ExerciseAliases.bundled.index == aliases.index)
    }

    /// Every entry has English and German names, a well-formed slug and known equipment; every equipment word has its
    /// kinds; the kinds are library kinds.
    @Test func shippedEntriesAreComplete() throws {
        let file = try MappingFixture.shippedFile()
        #expect(file.version == ExerciseAliases.version)
        let withoutEnglish = file.aliases.filter { ($0.en ?? []).isEmpty }.map(\.slug)
        let withoutGerman = file.aliases.filter { ($0.de ?? []).isEmpty }.map(\.slug)
        #expect(withoutEnglish == [])
        #expect(withoutGerman == [])
        let badSlugs = file.aliases.map(\.slug).filter { !ExerciseAliases.isSlug($0) }
        #expect(badSlugs == [])
        let unknownEquipment = file.aliases.compactMap(\.equipment).filter { file.equipment[$0] == nil }
        #expect(unknownEquipment == [])
        #expect(Set(file.kinds.keys) == Set(file.equipment.keys))
        let badKinds = file.kinds.values.joined().filter { ExerciseKind(rawValue: $0) == nil }
        #expect(badKinds == [])
    }

    /// One entry per slug and equipment, so a reviewer finds an exercise's names in one place.
    @Test func entriesAreUniquePerSlugAndEquipment() throws {
        let file = try MappingFixture.shippedFile()
        let ids = file.aliases.map { "\($0.slug)|\($0.equipment ?? "")" }
        #expect(ids.count == Set(ids).count)
    }

    /// Every target is a built-in exercise of the platform's library (non-custom), and every entry's equipment allows
    /// its kind.
    @Test func everyTargetIsABuiltIn() throws {
        let file = try MappingFixture.shippedFile()
        let aliases = try ExerciseAliases(data: MappingFixture.shippedData())
        let library = try MappingFixture.builtins()
        let bySlug = Dictionary(library.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        let missing = file.aliases.map(\.slug).filter { bySlug[$0]?.isCustom != false }
        #expect(missing == [])
        var blocked: [String] = []
        for entry in file.aliases {
            guard let equipment = entry.equipment, let kind = bySlug[entry.slug]?.kind else { continue }
            if aliases.allowedKinds(for: equipment)?.contains(kind) != true { blocked.append(entry.slug) }
        }
        #expect(blocked == [])
        let matcher = ExerciseMatcher(library: library, aliases: aliases, remembered: [:])
        #expect(matcher.unknownAliasSlugs == 0)
    }

    /// Every alias name, with its entry's equipment, reaches its slug: as an alias, or as an exact library name of the
    /// same exercise. An alias another exercise's exact name would shadow fails here.
    @Test func everyAliasResolvesToItsSlug() throws {
        let file = try MappingFixture.shippedFile()
        let library = try MappingFixture.builtins()
        let bySlug = Dictionary(library.map { ($0.slug, $0.id) }, uniquingKeysWith: { a, _ in a })
        let matcher = ExerciseMatcher(library: library, aliases: ExerciseAliases.bundled, remembered: [:])
        var wrong: [String] = []
        var viaAlias = 0
        for entry in file.aliases {
            for name in (entry.en ?? []) + (entry.de ?? []) {
                let match = matcher.match(name: name, equipment: entry.equipment)
                let reached = match.exerciseID == bySlug[entry.slug] && (match.tier == .exact || match.tier == .alias)
                if !reached { wrong.append("\(entry.slug) ← \(name)") }
                if match.tier == .alias { viaAlias += 1 }
            }
        }
        #expect(wrong == [])
        #expect(viaAlias >= 400)
    }

    /// No normalised name and equipment points at two slugs (design §4).
    @Test func noKeyPointsAtTwoSlugs() throws {
        let file = try MappingFixture.shippedFile()
        let normalizer = ExerciseAliases.bundled.normalizer
        var owners: [ExerciseAliases.Key: Set<String>] = [:]
        for entry in file.aliases {
            for name in (entry.en ?? []) + (entry.de ?? []) {
                let parsed = normalizer.analyse(name)
                let key = ExerciseAliases.Key(name: ExerciseNormalizer.joined(parsed.tokens),
                                              equipment: entry.equipment ?? parsed.equipment)
                owners[key, default: []].insert(entry.slug)
            }
        }
        let shared = owners.filter { $0.value.count > 1 }.map { "\($0.key.name)|\($0.key.equipment ?? "")" }
        #expect(shared == [])
    }

    /// Synonyms are applied once, so none may produce another synonym, and none may hide an equipment word.
    @Test func synonymsDontChain() throws {
        let file = try MappingFixture.shippedFile()
        let keys = Set(file.synonyms.keys.map { ExerciseNormalizer.baseTokens($0) })
        var chained: [String] = []
        for (from, to) in file.synonyms {
            let output = ExerciseNormalizer.baseTokens(to)
            for start in output.indices {
                for end in output.indices where end >= start && keys.contains(Array(output[start...end])) {
                    chained.append(from)
                }
            }
        }
        #expect(chained == [])
        let phrases = Set(file.equipment.values.joined().map { ExerciseNormalizer.baseTokens($0) })
        let overlapping = file.synonyms.keys.filter { phrases.contains(ExerciseNormalizer.baseTokens($0)) }
        #expect(overlapping == [])
    }

    /// The built-ins never share a key with the same kind: an exact match is never a coin toss between two of them.
    @Test func builtInsHaveDistinctKeys() throws {
        let normalizer = ExerciseAliases.bundled.normalizer
        var owners: [String: Set<String>] = [:]
        let library = try MappingFixture.builtins()
        for exercise in library {
            for name in Set([exercise.nameEn, exercise.nameDe]) {
                let key = normalizer.key(name: name, equipment: nil)
                owners["\(key.name)|\(key.equipment)|\(exercise.kind.rawValue)", default: []].insert(exercise.slug)
            }
        }
        let shared = owners.filter { $0.value.count > 1 }.map(\.key)
        #expect(shared == [])
    }

    // MARK: Validation and fallback

    @Test func malformedDataFallsBack() {
        let broken = ExerciseAliases.load(Data("{ not json".utf8))
        #expect(broken.index.isEmpty)
        #expect(broken.normalizer.isKnown(equipment: "barbell"))
        #expect(broken.allowedKinds(for: "dumbbell") == [.dumbbell])
        let missing = ExerciseAliases.load(nil)
        #expect(missing.index.isEmpty)
        #expect(missing.entryCount == 0)
    }

    @Test func otherVersionsAreRefused() throws {
        let data = try MappingFixture.shippedData()
        var json = try #require(String(data: data, encoding: .utf8))
        json = json.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")
        #expect(throws: ExerciseAliases.LoadError.unsupportedVersion(2)) { _ = try ExerciseAliases(data: Data(json.utf8)) }
        #expect(ExerciseAliases.load(Data(json.utf8)).index.isEmpty)
    }

    /// Each problem drops only its own part and is counted.
    @Test func problemsAreDroppedAndCounted() {
        var file = MappingFixture.file(aliases: [
            .init(slug: "bench-press", equipment: nil, en: ["flat bench"], de: ["Flachbank"]),
            .init(slug: "dumbbell-bench-press", equipment: nil, en: ["flat bench"], de: ["Flachbank Kurzhantel"]),
            .init(slug: "Bad Slug", equipment: nil, en: ["x"], de: ["y"]),
            .init(slug: "leg-press", equipment: "hoverboard", en: ["sled press"], de: ["Schlitten"]),
            .init(slug: "lat-pulldown", equipment: nil, en: ["pulldown", "···"], de: nil),
        ])
        file.kinds["barbell"] = ["barbell", "spaceship"]
        file.kinds["cable"] = nil
        let aliases = ExerciseAliases(file: file)
        #expect(aliases.issues.conflictingKeys == 1)
        #expect(aliases.issues.invalidSlugs == 1)
        #expect(aliases.issues.unknownEquipment == 1)
        #expect(aliases.issues.missingLanguage == 1)
        #expect(aliases.issues.emptyPhrases == 1)
        #expect(aliases.issues.unknownKinds == 1)
        #expect(aliases.issues.missingKinds == 1)
        // The clash is dropped for both slugs; the rest of those entries stays.
        #expect(aliases.index[ExerciseAliases.Key(name: "bench flat", equipment: nil)] == nil)
        #expect(aliases.index[ExerciseAliases.Key(name: "flachbank", equipment: nil)] == "bench-press")
        #expect(aliases.index[ExerciseAliases.Key(name: "flachbank", equipment: "dumbbell")] == "dumbbell-bench-press")
        #expect(aliases.index[ExerciseAliases.Key(name: "pulldown", equipment: nil)] == "lat-pulldown")
        #expect(aliases.allowedKinds(for: "barbell") == [.barbell])
        #expect(aliases.allowedKinds(for: "cable") == [])
    }

    @Test func conflictingEquipmentPhrasesAreDropped() {
        var file = MappingFixture.file()
        file.equipment["dumbbell"] = ["dumbbell", "bar"]
        file.equipment["barbell"] = ["barbell", "bar"]
        let aliases = ExerciseAliases(file: file)
        #expect(aliases.issues.conflictingPhrases == 1)
        #expect(aliases.normalizer.equipmentField("bar") == .unknown("bar"))
        #expect(aliases.normalizer.equipmentField("barbell") == .known("barbell"))
    }
}
