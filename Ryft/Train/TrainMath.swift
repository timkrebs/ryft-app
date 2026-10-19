// Display maths for Train. The platform scores load and PRs; the phone only
// estimates what it shows while logging (e1RM of a set, volume, plates).
import Foundation

enum E1RM {
    /// Reps above this are capped, like the platform's scoring (`strength.go`).
    static let maxReps = 12

    /// Epley: `weight × (1 + reps / 30)`.
    static func estimate(weightKg: Double?, reps: Int?) -> Double? {
        guard let w = weightKg, w > 0, let r = reps, r > 0 else { return nil }
        return w * (1 + Double(min(r, maxReps)) / 30)
    }

    /// Best estimate over the working sets (warm-ups don't count).
    static func best(of sets: [SessionSet]) -> Double? {
        sets.filter { !$0.isWarmup }.compactMap { estimate(weightKg: $0.weightKg, reps: $0.reps) }.max()
    }

    /// Rounded to the nearest 0.5 kg for display.
    static func rounded(_ v: Double) -> Double { (v * 2).rounded() / 2 }
}

enum Volume {
    /// Σ reps × kg over completed working sets.
    static func of(_ sets: [SessionSet]) -> Double {
        sets.filter { !$0.isWarmup && $0.completedAt != nil }
            .reduce(0) { $0 + Double($1.reps ?? 0) * ($1.weightKg ?? 0) }
    }
}

extension Fmt {
    /// 100 → "100", 82.5 → "82.5", nil → "–".
    static func kgNumber(_ kg: Double?) -> String {
        guard let kg else { return placeholder }
        return kg.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "82.5 kg".
    static func kg(_ kg: Double?) -> String {
        guard let kg else { return placeholder }
        return String(localized: "\(kgNumber(kg)) kg", comment: "A weight in kilograms, e.g. 82.5 kg.")
    }

    /// Volume: "4,250 kg"; tonnes above 10 t ("12.4 t").
    static func volume(_ kg: Double?) -> String {
        guard let kg else { return placeholder }
        if kg >= 10_000 {
            return String(localized: "\((kg / 1000).formatted(.number.precision(.fractionLength(1)))) t",
                          comment: "Training volume in tonnes, e.g. 12.4 t.")
        }
        return String(localized: "\(kg.formatted(.number.precision(.fractionLength(0)))) kg",
                      comment: "Training volume in kilograms, e.g. 4,250 kg.")
    }

    /// Muscular load: one decimal like strain ("11.2").
    static func load(_ v: Double?) -> String { strain(v) }

    /// Elapsed workout time: "23:05" or "1:02:10".
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// "3 × 5", "3 × 8–12".
    static func prescription(sets: Int, repsMin: Int, repsMax: Int) -> String {
        let reps = repsMin == repsMax ? "\(repsMin)" : "\(repsMin)–\(repsMax)"
        return "\(sets) × \(reps)"
    }
}

/// What to put on each side of the bar (kg only: 20 kg bar, 2.5–25 kg plates).
struct PlateLoad: Equatable {
    /// Heaviest first, one side.
    let perSide: [Double]
    let bar: Double
    /// What the bar weighs as loaded.
    var total: Double { bar + 2 * perSide.reduce(0, +) }
}

enum PlateCalculator {
    static let barKg = 20.0
    static let plates: [Double] = [25, 20, 15, 10, 5, 2.5]

    /// The closest load at or below `target` (an empty bar below 20 kg).
    static func load(for target: Double, bar: Double = barKg, plates: [Double] = plates) -> PlateLoad {
        var side = max(0, (target - bar) / 2)
        var out: [Double] = []
        // Greedy is exact for this plate set: every size is a multiple of the smallest.
        for plate in plates.sorted(by: >) {
            while side + 1e-9 >= plate {
                out.append(plate)
                side -= plate
            }
        }
        return PlateLoad(perSide: out, bar: bar)
    }
}

/// Rough duration of a prescription: work plus rest per set.
enum SessionEstimate {
    static let secondsPerSet = 45.0

    static func minutes(for exercises: [PlanExercise]) -> Int {
        let seconds = exercises.reduce(0.0) { $0 + Double($1.sets) * (secondsPerSet + Double($1.restSec)) }
        return Int((seconds / 60 / 5).rounded()) * 5 // to the nearest 5 min, like "~55 min"
    }
}
