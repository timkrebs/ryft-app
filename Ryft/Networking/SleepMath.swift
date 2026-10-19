// Pure sleep maths: stage percentages and bedtime consistency. The platform
// sends whole percentages (0–100, never fractions); these fill in only what's missing.
import Foundation

enum SleepMath {
    /// One share per display stage (deep, light, rem, awake — always all four,
    /// in that order). Percentages are of all stage minutes and are rounded with
    /// the largest-remainder method so they always sum to exactly 100.
    static func shares(_ minutes: [SleepStageKind: Int]) -> [StageShare] {
        let order = SleepStageKind.allCases
        let values = order.map { max(0, minutes[$0] ?? 0) }
        let total = values.reduce(0, +)
        guard total > 0 else { return order.map { StageShare(stage: $0, min: 0, pct: 0) } }

        let exact = values.map { Double($0) * 100 / Double(total) }
        var rounded = exact.map { Int($0.rounded(.down)) }
        var leftover = 100 - rounded.reduce(0, +)
        // Hand the remaining points to the largest fractional parts (ties: earlier stage).
        let byRemainder = exact.indices.sorted {
            let a = exact[$0] - exact[$0].rounded(.down), b = exact[$1] - exact[$1].rounded(.down)
            return a == b ? $0 < $1 : a > b
        }
        for i in byRemainder where leftover > 0 {
            rounded[i] += 1
            leftover -= 1
        }
        return order.indices.map { StageShare(stage: order[$0], min: values[$0], pct: Double(rounded[$0])) }
    }

    /// Standard deviation of bedtimes in minutes. Times are measured from noon
    /// so 23:30 and 00:30 are 60 minutes apart, not 23 hours. Nil for < 3 nights.
    static func bedtimeDeviation(_ starts: [Date], calendar: Calendar = .current) -> Double? {
        guard starts.count >= 3 else { return nil }
        let minutes = starts.map { d -> Double in
            let c = calendar.dateComponents([.hour, .minute], from: d)
            let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            return m < 12 * 60 ? m + 12 * 60 : m - 12 * 60
        }
        let mean = minutes.reduce(0, +) / Double(minutes.count)
        let variance = minutes.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(minutes.count)
        return variance.squareRoot()
    }

    /// Short hint for the Week/Month view.
    static func consistencyHint(deviation: Double?) -> String {
        guard let deviation else { return String(localized: "Not enough nights yet to judge consistency.") }
        let m = Int(deviation.rounded())
        switch deviation {
        case ..<30: return String(localized: "Very consistent — bedtime varies by about \(m) min.")
        case ..<60: return String(localized: "Fairly consistent — bedtime varies by about \(m) min.")
        default: return String(localized: "Irregular — bedtime varies by about \(m) min. A steadier rhythm helps recovery.")
        }
    }
}
