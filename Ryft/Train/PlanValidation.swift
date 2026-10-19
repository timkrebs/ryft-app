import Foundation

/// What the plan builder refuses to save. Limits mirror what the platform clamps
/// (reps ≤ 100, kg ≤ 500, RPE 1–10) plus what makes a plan usable.
enum PlanIssue: Hashable, Identifiable {
    case missingName
    case daysPerWeek
    case weeks
    case noDays
    case emptyDay(dayID: UUID)
    case sets(exerciseID: UUID)
    case reps(exerciseID: UUID)
    case target(exerciseID: UUID)
    case rest(exerciseID: UUID)
    /// A superset group with only one exercise in it.
    case lonelySuperset(dayID: UUID, group: Int)

    var id: Self { self }

    var message: String {
        switch self {
        case .missingName: return String(localized: "Give the plan a name.")
        case .daysPerWeek: return String(localized: "Days per week must be 1 to 7.")
        case .weeks: return String(localized: "A plan runs 1 to 52 weeks, or repeats.")
        case .noDays: return String(localized: "Add at least one training day.")
        case .emptyDay: return String(localized: "Every day needs at least one exercise.")
        case .sets: return String(localized: "Sets must be 1 to 20.")
        case .reps: return String(localized: "Reps must be 1 to 100, and the minimum can't exceed the maximum.")
        case .target: return String(localized: "Check the target: % 1RM 30–110, RPE 1–10, kg 0–500.")
        case .rest: return String(localized: "Rest must be 0 to 15 minutes.")
        case .lonelySuperset: return String(localized: "A superset needs at least two exercises.")
        }
    }
}

enum PlanValidation {
    static let maxSets = 20
    static let maxReps = 100
    static let maxRestSec = 900

    static func issues(in plan: Plan) -> [PlanIssue] {
        var out: [PlanIssue] = []
        if plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.missingName) }
        if !(1...7).contains(plan.daysPerWeek) { out.append(.daysPerWeek) }
        if let w = plan.weeks, !(1...52).contains(w) { out.append(.weeks) }
        if plan.days.isEmpty { out.append(.noDays) }
        for day in plan.days {
            if day.exercises.isEmpty { out.append(.emptyDay(dayID: day.id)) }
            for e in day.exercises {
                if !(1...maxSets).contains(e.sets) { out.append(.sets(exerciseID: e.id)) }
                if !(1...maxReps).contains(e.repsMin) || !(1...maxReps).contains(e.repsMax) || e.repsMin > e.repsMax {
                    out.append(.reps(exerciseID: e.id))
                }
                if !targetIsValid(e.targetKind, e.targetValue) { out.append(.target(exerciseID: e.id)) }
                if !(0...maxRestSec).contains(e.restSec) { out.append(.rest(exerciseID: e.id)) }
            }
            let groups = Dictionary(grouping: day.exercises.compactMap(\.supersetGroup), by: { $0 })
            for (group, members) in groups.sorted(by: { $0.key < $1.key }) where members.count < 2 {
                out.append(.lonelySuperset(dayID: day.id, group: group))
            }
        }
        return out
    }

    static func targetIsValid(_ kind: TargetKind, _ value: Double?) -> Bool {
        switch kind {
        case .pct1rm: return value.map { (30...110).contains($0) } ?? false
        case .rpe: return value.map { (1...10).contains($0) } ?? false
        case .kg: return value.map { $0 > 0 && $0 <= 500 } ?? false
        case .bodyweight: return value.map { $0 >= 0 && $0 <= 500 } ?? true // optional added load
        }
    }
}
