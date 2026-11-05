import Foundation

/// The fourth column of the Focused table (design.md §7): an estimate from `E1RM`, or the set's RPE. Pure; the controller
/// says which one an exercise shows and with which numbers.
enum SetColumn: String, CaseIterable, Sendable {
    case e1rm
    case tenRM = "10rm"
    case rpe

    /// The header's tap.
    var next: SetColumn {
        switch self {
        case .e1rm: .tenRM
        case .tenRM: .rpe
        case .rpe: .e1rm
        }
    }

    /// An estimate needs a load and reps, so time and distance have RPE only and a plain header (design.md §3.2).
    static func offersEstimates(for loadType: LoadType) -> Bool {
        loadType == .weight || loadType == .bodyweight
    }

    /// What an exercise shows. A choice the user made stands; before one, RPE wherever RPE is in use, so it isn't hidden
    /// from whoever logs it, else E1RM (design.md §7).
    static func shown(chosen: SetColumn?, loadType: LoadType, targetKind: TargetKind?, sessionHasRPE: Bool) -> SetColumn {
        guard offersEstimates(for: loadType) else { return .rpe }
        if let chosen { return chosen }
        return targetKind == .rpe || sessionHasRPE ? .rpe : .e1rm
    }

    /// The column's header, uppercase as it stands: `SetTableHeader` can't use `textCase` on it.
    var title: String {
        switch self {
        case .e1rm:
            String(localized: "E1RM", comment: "Set table's column in a workout: the set's estimated one-rep max. Keep it short, the column is 48 pt wide.")
        case .tenRM:
            String(localized: "10RM", comment: "Set table's column in a workout: the load the set puts at ten reps. Keep it short, the column is 48 pt wide.")
        case .rpe: String(localized: "RPE")
        }
    }

    /// The header's VoiceOver value.
    var spokenTitle: String {
        switch self {
        case .e1rm: String(localized: "Estimated 1RM")
        case .tenRM: String(localized: "Estimated 10RM", comment: "VoiceOver: what the set table's column shows in a workout.")
        case .rpe: String(localized: "RPE")
        }
    }

    /// The estimate in kg, rounded once and last: the 10RM comes from the exact e1RM, not from the one on screen.
    func estimate(weightKg: Double?, reps: Int?) -> Double? {
        switch self {
        case .e1rm: E1RM.estimate(weightKg: weightKg, reps: reps).map(E1RM.rounded)
        case .tenRM: E1RM.tenRM(weightKg: weightKg, reps: reps).map(E1RM.rounded)
        case .rpe: nil
        }
    }

    /// The cell: a dash where there is no estimate (no load, no reps, a bodyweight set without added load, a set only
    /// assisted), and an empty RPE stays empty, as in `SetRow`'s field.
    func text(weightKg: Double?, reps: Int?, rpe: Double?) -> String {
        if self == .rpe { return rpe.map(Fmt.kgNumber) ?? "" }
        return estimate(weightKg: weightKg, reps: reps).map(Fmt.kgNumber) ?? Fmt.placeholder
    }

    /// What VoiceOver adds to a set for this column; `nil` with nothing to say.
    func spoken(weightKg: Double?, reps: Int?, rpe: Double?) -> String? {
        switch self {
        case .rpe:
            return rpe.map { String(localized: "RPE \(Fmt.kgNumber($0))") }
        case .e1rm:
            return estimate(weightKg: weightKg, reps: reps).map {
                String(localized: "estimated one-rep max \(Fmt.kgNumber($0)) kilograms",
                       comment: "VoiceOver: a set's estimate in a workout, e.g. estimated one-rep max 100 kilograms.")
            }
        case .tenRM:
            return estimate(weightKg: weightKg, reps: reps).map {
                String(localized: "estimated ten-rep max \(Fmt.kgNumber($0)) kilograms",
                       comment: "VoiceOver: a set's estimate in a workout, e.g. estimated ten-rep max 75 kilograms.")
            }
        }
    }
}
