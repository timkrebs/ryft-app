import Foundation
import Testing
@testable import Ryft

/// Design §5: what `+N` becomes, by the matched exercise's `load_type`.
@Suite("Bodyweight answers")
struct BodyweightAnswerTests {
    static func plus(_ kilograms: [Double]) throws -> PlusLoadSummary {
        try #require(PlusLoadSummary(kilograms: kilograms))
    }

    @Test func optionsByLoadType() throws {
        let plausible = try Self.plus([80, 80, 80])
        #expect(BodyweightAnswer.options(for: .bodyweight, plus: plausible) == [.addedWeight, .bodyWeight, .ignore])
        #expect(BodyweightAnswer.options(for: .weight, plus: plausible) == [.addedWeight, .ignore])
        #expect(BodyweightAnswer.options(for: .time, plus: plausible) == [])
        #expect(BodyweightAnswer.options(for: .distance, plus: plausible) == [])
        // "Body weight" only for 30…300 kg.
        let light = try Self.plus([20, 20])
        #expect(BodyweightAnswer.options(for: .bodyweight, plus: light) == [.addedWeight, .ignore])
        let lowest = try Self.plus([30]), highest = try Self.plus([300]), over = try Self.plus([300.5])
        #expect(BodyweightAnswer.options(for: .bodyweight, plus: lowest).contains(.bodyWeight))
        #expect(BodyweightAnswer.options(for: .bodyweight, plus: highest).contains(.bodyWeight))
        #expect(!BodyweightAnswer.options(for: .bodyweight, plus: over).contains(.bodyWeight))
    }

    @Test func defaults() throws {
        let uniform = try Self.plus([82, 82, 82]), mixed = try Self.plus([82, 82, 84]), light = try Self.plus([10, 10])
        let single = try Self.plus([82])
        // The same plausible N on every set: the body weight.
        #expect(BodyweightAnswer.defaultAnswer(for: .bodyweight, plus: uniform) == .bodyWeight)
        // Different values, or implausible: added weight.
        #expect(BodyweightAnswer.defaultAnswer(for: .bodyweight, plus: mixed) == .addedWeight)
        #expect(BodyweightAnswer.defaultAnswer(for: .bodyweight, plus: light) == .addedWeight)
        #expect(BodyweightAnswer.defaultAnswer(for: .weight, plus: single) == .addedWeight)
        #expect(BodyweightAnswer.defaultAnswer(for: .time, plus: single) == nil)
        #expect(BodyweightAnswer.defaultAnswer(for: .distance, plus: single) == nil)
    }

    /// A remembered answer is used while it's still offered; otherwise the default.
    @Test func resolvedAnswers() throws {
        let uniform = try Self.plus([80, 80])
        #expect(BodyweightAnswer.resolved(.ignore, for: .bodyweight, plus: uniform) == .ignore)
        #expect(BodyweightAnswer.resolved(nil, for: .bodyweight, plus: uniform) == .bodyWeight)
        // "Body weight" isn't offered for a `weight` exercise.
        #expect(BodyweightAnswer.resolved(.bodyWeight, for: .weight, plus: uniform) == .addedWeight)
        #expect(BodyweightAnswer.resolved(.addedWeight, for: .time, plus: uniform) == nil)
    }

    struct Outcome: CustomTestStringConvertible, Sendable {
        let load: LoadType
        let answer: BodyweightAnswer
        let weight: Double?
        let bodyweight: Double?
        var testDescription: String { "\(load.rawValue) · \(answer.rawValue)" }
    }

    /// The table of design §5 for `+80`.
    static let outcomes: [Outcome] = [
        Outcome(load: .bodyweight, answer: .addedWeight, weight: 80, bodyweight: nil),
        Outcome(load: .bodyweight, answer: .bodyWeight, weight: nil, bodyweight: 80),
        Outcome(load: .bodyweight, answer: .ignore, weight: nil, bodyweight: nil),
        Outcome(load: .weight, answer: .addedWeight, weight: 80, bodyweight: nil),
        Outcome(load: .weight, answer: .ignore, weight: nil, bodyweight: nil),
        Outcome(load: .weight, answer: .bodyWeight, weight: nil, bodyweight: nil),
        Outcome(load: .time, answer: .addedWeight, weight: nil, bodyweight: nil),
        Outcome(load: .distance, answer: .bodyWeight, weight: nil, bodyweight: nil),
    ]

    @Test(arguments: outcomes)
    func setOutcomes(_ c: Outcome) {
        #expect(c.answer.outcome(plusKg: 80, loadType: c.load) == PlusSetOutcome(weightKg: c.weight, bodyweightKg: c.bodyweight))
    }

    @Test func bodyWeightOutsideTheRangeIsNotABodyWeight() {
        #expect(BodyweightAnswer.bodyWeight.outcome(plusKg: 12, loadType: .bodyweight) == PlusSetOutcome(weightKg: nil, bodyweightKg: nil))
    }

    @Test func mostCommonTiesGoToTheFirst() throws {
        #expect(PlusLoadSummary.mostCommon([]) == nil)
        #expect(PlusLoadSummary.mostCommon([80, 82, 82, 80]) == 80)
        #expect(PlusLoadSummary.mostCommon([82, 80, 80]) == 80)
        let summary = try Self.plus([82, 80, 80])
        #expect(summary.setCount == 3)
        #expect(summary.mostCommonKg == 80)
        #expect(!summary.isUniform)
        #expect(PlusLoadSummary(kilograms: []) == nil)
    }

    /// Stored in `ImportMapping.bodyweightRaw`: the raw values never change.
    @Test func rawValuesAreStable() {
        #expect(BodyweightAnswer.addedWeight.rawValue == "addedWeight")
        #expect(BodyweightAnswer.bodyWeight.rawValue == "bodyWeight")
        #expect(BodyweightAnswer.ignore.rawValue == "ignore")
    }
}
