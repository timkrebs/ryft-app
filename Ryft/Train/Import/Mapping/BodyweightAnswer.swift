import Foundation

/// What `+N` on a bodyweight-style source exercise means (design §5): asked once per source exercise and remembered
/// (`ImportMapping.bodyweightRaw`). The raw values are stored, so they never change.
enum BodyweightAnswer: String, Codable, Sendable {
    /// N kg on top of the body (a belt, a vest), or the weight itself for a `weight` exercise.
    case addedWeight
    /// N is the user's own body weight: the sets log no added load, and the session notes N as its body weight.
    case bodyWeight
    /// Reps only.
    case ignore

    /// "Body weight" is offered only for a plausible body weight.
    static let bodyWeightRange: ClosedRange<Double> = 30...300

    /// The answers offered for a match with this `load_type`: none for `time` and `distance` (not asked: the load is
    /// dropped, reps kept).
    static func options(for loadType: LoadType, plus: PlusLoadSummary) -> [BodyweightAnswer] {
        switch loadType {
        case .bodyweight:
            bodyWeightRange.contains(plus.mostCommonKg) ? [.addedWeight, .bodyWeight, .ignore] : [.addedWeight, .ignore]
        case .weight:
            [.addedWeight, .ignore]
        case .time, .distance:
            []
        }
    }

    /// The pre-selected answer: "body weight" when N is the same on every set and plausible, else "added weight".
    static func defaultAnswer(for loadType: LoadType, plus: PlusLoadSummary) -> BodyweightAnswer? {
        switch loadType {
        case .bodyweight:
            plus.isUniform && bodyWeightRange.contains(plus.mostCommonKg) ? .bodyWeight : .addedWeight
        case .weight:
            .addedWeight
        case .time, .distance:
            nil
        }
    }

    /// A chosen or remembered answer while it is still offered (the match may have changed since), else the default.
    static func resolved(_ answer: BodyweightAnswer?, for loadType: LoadType, plus: PlusLoadSummary) -> BodyweightAnswer? {
        if let answer, options(for: loadType, plus: plus).contains(answer) { return answer }
        return defaultAnswer(for: loadType, plus: plus)
    }

    /// What one `+N` set becomes: its `weight_kg`, and the body weight it tells its session (I5 takes the most common
    /// per session, `PlusLoadSummary.mostCommon`).
    func outcome(plusKg kg: Double, loadType: LoadType) -> PlusSetOutcome {
        switch (loadType, self) {
        case (.time, _), (.distance, _), (_, .ignore), (.weight, .bodyWeight):
            PlusSetOutcome(weightKg: nil, bodyweightKg: nil)
        case (_, .addedWeight):
            PlusSetOutcome(weightKg: kg, bodyweightKg: nil)
        case (.bodyweight, .bodyWeight):
            PlusSetOutcome(weightKg: nil, bodyweightKg: Self.bodyWeightRange.contains(kg) ? kg : nil)
        }
    }
}

/// A `+N` set under an answer.
struct PlusSetOutcome: Equatable, Sendable {
    /// The set's `weight_kg`: the added load for `bodyweight`, the load for `weight`; nil for none.
    let weightKg: Double?
    /// N as the session's `bodyweight_kg`, when the answer says it is the body weight.
    let bodyweightKg: Double?
}

/// The `+N` loads of one source exercise, for the question's wording and its default (ui.md 7.4).
struct PlusLoadSummary: Equatable, Sendable {
    /// Sets with a `+N` load.
    let setCount: Int
    /// The most frequent N (ties: the first seen). The question names it.
    let mostCommonKg: Double
    /// N is the same on every such set.
    let isUniform: Bool

    /// nil when no set has a `+N` load.
    init?(kilograms: [Double]) {
        guard let common = Self.mostCommon(kilograms) else { return nil }
        setCount = kilograms.count
        mostCommonKg = common
        isUniform = kilograms.allSatisfy { $0 == common }
    }

    /// The most frequent value; ties go to the one seen first. nil for none.
    static func mostCommon(_ values: [Double]) -> Double? {
        var counts: [Double: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        var best: (value: Double, count: Int)?
        for value in values {
            let count = counts[value] ?? 0
            if count > (best?.count ?? 0) { best = (value, count) }
        }
        return best?.value
    }
}
