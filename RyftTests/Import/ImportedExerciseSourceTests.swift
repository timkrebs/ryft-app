import Foundation
import Testing
@testable import Ryft

/// Step 4's rows: each distinct exercise once, with where it appears and its `+N` loads.
@Suite("Imported exercise sources")
struct ImportedExerciseSourceTests {
    let normalizer = ExerciseAliases.bundled.normalizer

    static let text = """
    "Upper · Standalone workout";"2026-02-01 6:00 pm";"40 min"
    "1. Bench Press · Barbell · 8 reps"
    #;KG;REPS
    1;60;8
    "2. Dips · Bodyweight · 10 reps"
    #;KG;REPS
    1;+80;10
    2;+82;8
    3;+80;8
    "3. Assisted Pull-Up · Machine · 8 reps"
    #;KG;REPS
    1;-20;8

    "Upper again · Standalone workout";"2026-02-03 6:00 pm";"40 min"
    "1. bench press · Langhantel · 8 reps"
    #;KG;REPS
    1;62.5;8
    "2. Dips · Bodyweight · 10 reps"
    #;KG;REPS
    1;-;-
    """

    @Test func oneRowPerKeyInFirstSeenOrder() throws {
        let bundle = try ImportFixture.parse(text: Self.text)
        let sources = normalizer.sources(in: bundle)
        // "bench press · Langhantel" is "Bench Press · Barbell" again: one row.
        #expect(sources.map(\.key) == [SourceExerciseKey(name: "bench press", equipment: "barbell"),
                                        SourceExerciseKey(name: "dips", equipment: "bodyweight"),
                                        SourceExerciseKey(name: "assisted pull up", equipment: "machine")])
        // The first spelling, as written.
        #expect(sources.first?.name == "Bench Press")
        #expect(sources.first?.equipment == "Barbell")
        #expect(sources.allSatisfy(\.inHistory) == true)
        #expect(sources.contains(where: \.inPlan) == false)
    }

    @Test func plusLoadsAndAssistance() throws {
        let bundle = try ImportFixture.parse(text: Self.text)
        let sources = normalizer.sources(in: bundle)
        let dips = try #require(sources.first { $0.key.name == "dips" })
        #expect(dips.plusLoads == PlusLoadSummary(kilograms: [80, 82, 80]))
        #expect(dips.plusLoads?.mostCommonKg == 80)
        #expect(dips.plusLoads?.isUniform == false)
        #expect(!dips.hasAssistedSets)
        let pullUp = try #require(sources.first { $0.key.name == "assisted pull up" })
        #expect(pullUp.hasAssistedSets)
        #expect(pullUp.plusLoads == nil)
    }

    /// Plans and history together: every row says where it came from, and nothing is counted twice.
    @Test func plansAndHistory() throws {
        let plans = try ImportFixture.parse("ap-plans")
        let workouts = try ImportFixture.parse("ap-workouts")
        let sources = normalizer.sources(in: plans.merging(workouts))
        let planKeys = Set(plans.plans.flatMap(\.days).flatMap(\.exercises).map { normalizer.key(name: $0.name, equipment: $0.equipment) })
        let historyKeys = Set(workouts.sessions.flatMap(\.exercises).map { normalizer.key(name: $0.name, equipment: $0.equipment) })
        #expect(sources.count == planKeys.union(historyKeys).count)
        #expect(Set(sources.filter(\.inPlan).map(\.key)) == planKeys)
        #expect(Set(sources.filter(\.inHistory).map(\.key)) == historyKeys)
        let withPlus = sources.filter { $0.plusLoads != nil }.map(\.key.name)
        #expect(withPlus.count == 2)
    }
}
