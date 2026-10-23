import Foundation
import Testing
@testable import Ryft

@Suite("Exercise matcher")
struct ExerciseMatcherTests {
    static let bench = MappingFixture.exercise(1, "Bench press", de: "Bankdrücken", slug: "bench-press", kind: .barbell)
    static let dumbbellBench = MappingFixture.exercise(2, "Dumbbell bench press", de: "Kurzhantel-Bankdrücken",
                                                       slug: "dumbbell-bench-press", kind: .dumbbell)
    static let barbellCurl = MappingFixture.exercise(3, "Barbell curl", kind: .barbell)
    static let dumbbellCurl = MappingFixture.exercise(4, "Dumbbell curl", kind: .dumbbell)
    static let cableCurl = MappingFixture.exercise(5, "Cable curl", kind: .cable)
    static let smithSquat = MappingFixture.exercise(6, "Smith machine squat", kind: .machine)
    static let backSquat = MappingFixture.exercise(7, "Back squat", slug: "back-squat", kind: .barbell)
    static let pulldown = MappingFixture.exercise(8, "Lat pulldown", kind: .cable)
    static let pullUp = MappingFixture.exercise(9, "Pull-up", kind: .bodyweight, load: .bodyweight)
    static let lyingCurl = MappingFixture.exercise(11, "Lying leg curl", kind: .machine)
    static let seatedCurl = MappingFixture.exercise(12, "Seated leg curl", kind: .machine)

    static let library = [bench, dumbbellBench, barbellCurl, dumbbellCurl, cableCurl, smithSquat, backSquat, pulldown,
                          pullUp, lyingCurl, seatedCurl]

    static let aliases = MappingFixture.vocabulary(aliases: [
        .init(slug: "back-squat", equipment: nil, en: ["squat"], de: ["Nackenkniebeuge"]),
        .init(slug: "bench-press", equipment: nil, en: ["flat press"], de: ["Flachdrücken"]),
        .init(slug: "dumbbell-bench-press", equipment: "dumbbell", en: ["flat press"], de: ["Flachdrücken"]),
    ])

    static func matcher(_ library: [Exercise] = library, remembered: [SourceExerciseKey: UUID] = [:]) -> ExerciseMatcher {
        ExerciseMatcher(library: library, aliases: aliases, remembered: remembered)
    }

    // MARK: Tiers

    @Test func exactWithKnownEquipment() {
        let match = Self.matcher().match(name: "Bench Press", equipment: "Barbell")
        #expect(match.exerciseID == Self.bench.id)
        #expect(match.tier == .exact)
        #expect(match.confidence == 1)
        #expect(!match.needsReview)
    }

    @Test func exactByTheGermanName() {
        let match = Self.matcher().match(name: "Bankdrücken", equipment: "Langhantel")
        #expect(match.exerciseID == Self.bench.id)
        #expect(match.tier == .exact)
        let dumbbell = Self.matcher().match(name: "Bankdrücken", equipment: "Kurzhantel")
        #expect(dumbbell.exerciseID == Self.dumbbellBench.id)
        #expect(dumbbell.tier == .exact)
    }

    /// Without equipment there's no filter, only a lower confidence, and only names that name no equipment fit.
    @Test func exactWithoutEquipment() {
        let match = Self.matcher().match(name: "Bench Press", equipment: nil)
        #expect(match.exerciseID == Self.bench.id)
        #expect(match.tier == .exact)
        #expect(match.confidence == ExerciseMatcher.unknownEquipmentFactor)
        #expect(!match.needsReview)
    }

    @Test func equipmentInTheNameCounts() {
        let match = Self.matcher().match(name: "Dumbbell Bench Press", equipment: nil)
        #expect(match.exerciseID == Self.dumbbellBench.id)
        #expect(match.tier == .exact)
        #expect(match.confidence == 1)
    }

    @Test func aliases() {
        let m = Self.matcher()
        let bare = m.match(name: "Squat", equipment: nil)
        #expect(bare.exerciseID == Self.backSquat.id)
        #expect(bare.tier == .alias)
        #expect(abs(bare.confidence - ExerciseMatcher.aliasConfidence * ExerciseMatcher.unknownEquipmentFactor) < 1e-9)
        let barbell = m.match(name: "Squat", equipment: "Barbell")
        #expect(barbell.tier == .alias)
        #expect(barbell.confidence == ExerciseMatcher.aliasConfidence)
        #expect(m.match(name: "Nackenkniebeuge", equipment: nil).exerciseID == Self.backSquat.id)
        // An alias for one equipment wins over one for any.
        #expect(m.match(name: "Flat Press", equipment: "Dumbbell").exerciseID == Self.dumbbellBench.id)
        #expect(m.match(name: "Flat Press", equipment: "Barbell").exerciseID == Self.bench.id)
        #expect(m.match(name: "Flat Press", equipment: nil).exerciseID == Self.bench.id)
    }

    @Test func fuzzySuggestsAndNeedsATap() {
        let match = Self.matcher().match(name: "Leg Curl", equipment: "Machine")
        #expect(match.tier == .fuzzy)
        #expect(match.needsReview)
        // Dice({curl, leg}, {curl, leg, lying}) = 4 / 5; both leg curls tie, the name decides.
        #expect(abs(match.confidence - 0.8) < 1e-9)
        #expect(match.isLikely)
        #expect(match.exerciseID == Self.lyingCurl.id)
        #expect(match.alternatives.first == Self.seatedCurl.id)
    }

    @Test func belowTheThresholdIsNew() {
        let match = Self.matcher().match(name: "Zercher Carry", equipment: nil)
        #expect(match.exerciseID == nil)
        #expect(match.tier == nil)
        #expect(match.confidence == 0)
        #expect(match.alternatives == [])
        #expect(match.needsReview)
        #expect(Self.matcher().match(name: "", equipment: nil).exerciseID == nil)
    }

    // MARK: The equipment filter

    @Test func equipmentIsAHardFilter() {
        let m = Self.matcher()
        // Never the barbell or dumbbell bench for a cable one, whatever the name says.
        let cable = m.match(name: "Bench Press", equipment: "Cable")
        #expect(cable.exerciseID == nil)
        // The alias's target is a barbell exercise: not for a dumbbell source.
        let dumbbellSquat = m.match(name: "Squat", equipment: "Dumbbell")
        #expect(dumbbellSquat.exerciseID != Self.backSquat.id)
        // Equipment that allows no kind: always new.
        #expect(m.match(name: "Pull-Up", equipment: "Band").exerciseID == nil)
        // Its alternatives pass the filter too.
        let curl = m.match(name: "Curl", equipment: "Cable")
        let ids = [curl.exerciseID].compactMap { $0 } + curl.alternatives
        #expect(ids == [Self.cableCurl.id])
    }

    /// An alias for one equipment suggests nothing for another, even where that equipment's filter would let the
    /// exercise through (machine allows cable stations; this name is only a cable one).
    @Test func aliasesForOtherEquipmentSuggestNothing() {
        let aliases = MappingFixture.vocabulary(aliases: [
            .init(slug: "lat-pulldown", equipment: "cable", en: ["wide pull"], de: ["Breitzug"]),
        ])
        let matcher = ExerciseMatcher(library: Self.library, aliases: aliases, remembered: [:])
        #expect(matcher.match(name: "Wide Pull", equipment: "Cable").exerciseID == Self.pulldown.id)
        let machine = matcher.match(name: "Wide Pull", equipment: "Machine")
        #expect(machine.exerciseID == nil)
        #expect(machine.alternatives == [])
    }

    @Test func machineAllowsCableStations() {
        let match = Self.matcher().match(name: "Lat Pulldown", equipment: "Machine")
        #expect(match.exerciseID == Self.pulldown.id)
        #expect(match.tier == .exact)
    }

    // MARK: Never accepted without a tap

    struct FuzzyCase: CustomTestStringConvertible, Sendable {
        let name: String
        let equipment: String?
        var testDescription: String { "\(name) · \(equipment ?? "–")" }
    }

    static let fuzzyCases = [
        // Score 1: the same words, but the library name names other equipment.
        FuzzyCase(name: "Squat", equipment: "Machine"),
        // Score 40/41 ≈ 0.976.
        FuzzyCase(name: (1...20).map { "t\($0)" }.joined(separator: " ") + " extra", equipment: nil),
        FuzzyCase(name: "Leg Curl", equipment: "Machine"),
        FuzzyCase(name: "Bicep Curl", equipment: "Dumbbell"),
    ]

    @Test(arguments: fuzzyCases)
    func fuzzyIsNeverAccepted(_ c: FuzzyCase) {
        let long = MappingFixture.exercise(20, (1...20).map { "T\($0)" }.joined(separator: " "), kind: .machine)
        let match = Self.matcher(Self.library + [long]).match(name: c.name, equipment: c.equipment)
        #expect(match.tier == .fuzzy)
        #expect(match.confidence >= ExerciseMatcher.fuzzyThreshold)
        #expect(match.needsReview)
    }

    @Test func fuzzyAtFullScoreStillNeedsATap() {
        let match = Self.matcher().match(name: "Squat", equipment: "Machine")
        #expect(match.exerciseID == Self.smithSquat.id)
        #expect(match.confidence == 1)
        #expect(match.needsReview)
    }

    /// Several exercises fit an exact name and the file names no equipment: a guess, so it's a check.
    @Test func ambiguousWithoutEquipmentIsACheck() {
        let custom = MappingFixture.exercise(30, "Bench Press", kind: .machine, custom: true)
        let m = Self.matcher(Self.library + [custom])
        let bare = m.match(name: "Bench Press", equipment: nil)
        #expect(bare.tier == .fuzzy)
        #expect(bare.needsReview)
        #expect(bare.exerciseID == custom.id)
        #expect(bare.alternatives.first == Self.bench.id)
        // With equipment the filter decides, and it's exact.
        let barbell = m.match(name: "Bench Press", equipment: "Barbell")
        #expect(barbell.tier == .exact)
        #expect(barbell.exerciseID == Self.bench.id)
        // Curls name their equipment: without it all three are equally good.
        let curl = m.match(name: "Curl", equipment: nil)
        #expect(curl.tier == .fuzzy)
        #expect(curl.exerciseID == Self.barbellCurl.id)
        // The other two curls, then the leg curls at 0.5.
        #expect(Array(curl.alternatives.prefix(2)) == [Self.cableCurl.id, Self.dumbbellCurl.id])
    }

    // MARK: Ties

    @Test func customBeforeBuiltIn() {
        let custom = MappingFixture.exercise(31, "Bench press", kind: .barbell, custom: true)
        let match = Self.matcher(Self.library + [custom]).match(name: "Bench Press", equipment: "Barbell")
        #expect(match.tier == .exact)
        #expect(match.exerciseID == custom.id)
        #expect(match.alternatives.first == Self.bench.id)
    }

    @Test func thenNameThenID() {
        let upper = MappingFixture.exercise(41, "Bench Press", kind: .barbell)
        let twinA = MappingFixture.exercise(43, "Bench press", kind: .barbell)
        let byName = Self.matcher([Self.bench, upper]).match(name: "bench press", equipment: "barbell")
        #expect(byName.exerciseID == upper.id) // "P" sorts before "p"
        // Two built-ins fit: the order picks the suggestion, never the answer.
        #expect(byName.tier == .fuzzy)
        #expect(byName.needsReview)
        let byID = Self.matcher([twinA, Self.bench]).match(name: "bench press", equipment: "barbell")
        #expect(byID.exerciseID == Self.bench.id) // same name: the smaller id
        #expect(byID.alternatives == [twinA.id])
    }

    @Test func libraryOrderDoesntMatter() {
        let names = ["Bench Press · Barbell", "Bench Press", "Curl", "Leg Curl · Machine", "Squat", "Squat · Machine",
                     "Flat Press · Dumbbell", "Pull-Up · Bodyweight", "Row"]
        let forward = Self.matcher(Self.library)
        let backward = Self.matcher(Self.library.reversed())
        for spec in names {
            let parts = spec.components(separatedBy: " · ")
            let name = parts.first ?? spec
            let equipment = parts.count > 1 ? parts.last : nil
            #expect(forward.match(name: name, equipment: equipment) == backward.match(name: name, equipment: equipment), "\(spec)")
        }
    }

    @Test func alternativesAreAtMostThreeAndNeverTheMatch() {
        let extra = (50..<56).map { MappingFixture.exercise($0, "Curl variant \($0)", kind: .cable) }
        let match = Self.matcher(Self.library + extra).match(name: "Curl", equipment: "Cable")
        #expect(match.alternatives.count == ExerciseMatcher.maxAlternatives)
        #expect(!match.alternatives.contains { $0 == match.exerciseID })
        #expect(Set(match.alternatives).count == match.alternatives.count)
    }

    // MARK: Remembered choices

    @Test func rememberedBeatsExact() {
        let key = Self.aliases.normalizer.key(name: "Bench Press", equipment: "Barbell")
        // The user's own pick wins, even across the equipment filter.
        let match = Self.matcher(remembered: [key: Self.dumbbellBench.id]).match(name: "Bench Press", equipment: "Barbell")
        #expect(match.tier == .remembered)
        #expect(match.exerciseID == Self.dumbbellBench.id)
        #expect(match.confidence == 1)
        #expect(!match.needsReview)
    }

    @Test func rememberedArchivedOrGoneIsIgnored() {
        let archived = MappingFixture.exercise(60, "Old bench", kind: .barbell, custom: true, archived: true)
        let key = Self.aliases.normalizer.key(name: "Bench Press", equipment: "Barbell")
        let toArchived = Self.matcher(Self.library + [archived], remembered: [key: archived.id])
            .match(name: "Bench Press", equipment: "Barbell")
        #expect(toArchived.tier == .exact)
        #expect(toArchived.exerciseID == Self.bench.id)
        let toMissing = Self.matcher(remembered: [key: MappingFixture.id(999)]).match(name: "Bench Press", equipment: "Barbell")
        #expect(toMissing.tier == .exact)
    }

    @Test func archivedExercisesAreNotCandidates() {
        let archived = MappingFixture.exercise(61, "Hack squat", kind: .machine, archived: true)
        let match = Self.matcher(Self.library + [archived]).match(name: "Hack Squat", equipment: "Machine")
        #expect(match.exerciseID != archived.id)
        #expect(!match.alternatives.contains(archived.id))
    }

    @Test func unknownAliasSlugsAreCounted() {
        let aliases = MappingFixture.vocabulary(aliases: [
            .init(slug: "no-such-exercise", equipment: nil, en: ["ghost"], de: ["Geist"]),
            .init(slug: "my-own", equipment: nil, en: ["mine"], de: ["meins"]),
        ])
        let custom = MappingFixture.exercise(70, "My own", slug: "my-own", kind: .machine, custom: true)
        let matcher = ExerciseMatcher(library: Self.library + [custom], aliases: aliases, remembered: [:])
        #expect(matcher.unknownAliasSlugs == 2)
        #expect(matcher.match(name: "Mine", equipment: nil).tier != .alias)
    }

    @Test func batchMatchesEachKey() {
        let m = Self.matcher()
        let keys = ["Bench Press", "Curl", "Squat"].map { m.key(name: $0, equipment: nil) }
        #expect(m.match(keys) == keys.map { m.match(key: $0) })
    }

    // MARK: The built-in library

    struct LibraryCase: CustomTestStringConvertible, Sendable {
        let name: String
        let equipment: String?
        /// The slug accepted without a tap; nil: must need a tap.
        let accepted: String?
        var testDescription: String { "\(name) · \(equipment ?? "–")" }
    }

    /// A specific built-in wins over the generic one, from the field or the name, in either direction; a contradiction
    /// is never accepted (code review of I3).
    static let libraryCases = [
        LibraryCase(name: "Trap Bar Deadlift", equipment: "Trap Bar", accepted: "trap-bar-deadlift"),
        LibraryCase(name: "Deadlift", equipment: "Trap Bar", accepted: "trap-bar-deadlift"),
        LibraryCase(name: "Hex Bar Deadlift", equipment: nil, accepted: "trap-bar-deadlift"),
        LibraryCase(name: "Kreuzheben", equipment: "Trap Bar", accepted: "trap-bar-deadlift"),
        LibraryCase(name: "Trap Bar Deadlift", equipment: "Barbell", accepted: "trap-bar-deadlift"),
        LibraryCase(name: "Barbell Deadlift", equipment: "Trap Bar", accepted: "trap-bar-deadlift"),
        LibraryCase(name: "EZ Bar Curl", equipment: "Barbell", accepted: "ez-bar-curl"),
        LibraryCase(name: "SZ-Curl", equipment: "Langhantel", accepted: "ez-bar-curl"),
        LibraryCase(name: "Curl", equipment: "EZ Bar", accepted: "ez-bar-curl"),
        LibraryCase(name: "Squat", equipment: "Smith Machine", accepted: "smith-machine-squat"),
        LibraryCase(name: "Barbell Curl", equipment: "EZ Bar", accepted: "ez-bar-curl"),
        LibraryCase(name: "Assisted Dip", equipment: "Machine", accepted: "assisted-dip"),
        LibraryCase(name: "Deadlift", equipment: "Barbell", accepted: "deadlift"),
        LibraryCase(name: "Curl", equipment: "Barbell", accepted: "barbell-curl"),
        LibraryCase(name: "Lat Pulldown", equipment: "Machine", accepted: "lat-pulldown"),
        LibraryCase(name: "Farmer´s Walk", equipment: nil, accepted: "farmers-walk"),
        LibraryCase(name: "Bank\u{AD}drücken", equipment: "Langhantel", accepted: "bench-press"),
        LibraryCase(name: "Smith Machine Squat", equipment: "Barbell", accepted: nil),
        LibraryCase(name: "Dumbbell Curl", equipment: "Barbell", accepted: nil),
        LibraryCase(name: "Squat", equipment: "Machine", accepted: nil),
        // A machine exercise is never its cable version, nor the reverse (re-review N1).
        LibraryCase(name: "Crunch machine", equipment: "Cable", accepted: nil),
        LibraryCase(name: "Lateral raise machine", equipment: "Cable", accepted: nil),
        LibraryCase(name: "Glute kickback machine", equipment: "Cable", accepted: nil),
        LibraryCase(name: "Machine row", equipment: "Cable", accepted: nil),
        LibraryCase(name: "Cable Crossover", equipment: "Machine", accepted: nil),
        LibraryCase(name: "Cable Curl", equipment: "Machine", accepted: nil),
    ]

    @Test(arguments: libraryCases)
    func builtInLibrary(_ c: LibraryCase) throws {
        let library = try MappingFixture.builtins()
        let match = ExerciseMatcher(library: library, aliases: ExerciseAliases.bundled, remembered: [:])
            .match(name: c.name, equipment: c.equipment)
        let slug = library.first { $0.id == match.exerciseID }?.slug
        if let accepted = c.accepted {
            #expect(slug == accepted)
            #expect(!match.needsReview)
        } else {
            #expect(match.needsReview)
        }
    }

    @Test func apostrophesAndInvisibleCharactersDontMatter() throws {
        let library = try MappingFixture.builtins()
        let matcher = ExerciseMatcher(library: library, aliases: ExerciseAliases.bundled, remembered: [:])
        let acute = matcher.match(name: "Farmer´s Walk", equipment: nil)
        let plain = matcher.match(name: "Farmer's Walk", equipment: nil)
        #expect(acute.tier == .exact)
        #expect(acute == plain)
        #expect(matcher.match(name: "Bank\u{AD}drücken", equipment: nil).exerciseID
            == matcher.match(name: "Bankdrücken", equipment: nil).exerciseID)
    }

    /// The library comes in the phone's language (`name`); ties never depend on it.
    @Test func tiesDontDependOnTheLanguage() throws {
        let english = try MappingFixture.builtins()
        let german = english.map { exercise in
            var copy = exercise
            copy.name = exercise.nameDe
            return copy
        }
        let a = ExerciseMatcher(library: english, aliases: ExerciseAliases.bundled, remembered: [:])
        let b = ExerciseMatcher(library: german, aliases: ExerciseAliases.bundled, remembered: [:])
        let specs: [(String, String?)] = [("Curl", nil), ("Row", nil), ("Bench Press", nil), ("Leg Curl", "Machine"),
                                          ("Squat", "Machine"), ("Shoulder Press", nil), ("Bicep Curl", nil), ("Fly", nil)]
        for (name, equipment) in specs {
            #expect(a.match(name: name, equipment: equipment) == b.match(name: name, equipment: equipment), "\(name)")
        }
    }

    // MARK: The synthetic fixtures

    /// Every exercise in the synthetic exports matches the built-in library without a check.
    @Test(arguments: ["ap-plans", "ap-workouts", "ap-workouts-de", "ap-workouts-lbs"])
    func fixturesMatchWithoutReview(_ name: String) throws {
        let bundle = try ImportFixture.parse(name)
        let aliases = ExerciseAliases.bundled
        let library = try MappingFixture.builtins()
        let matcher = ExerciseMatcher(library: library, aliases: aliases, remembered: [:])
        let sources = aliases.normalizer.sources(in: bundle)
        let matches = matcher.match(sources.map(\.key))
        let unmatched = matches.filter(\.needsReview).map(\.key.name)
        #expect(!sources.isEmpty)
        #expect(unmatched == [])
    }
}
