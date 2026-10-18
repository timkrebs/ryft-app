// Words on the Today screen: greeting by time of day and the state sentence.
import Foundation

enum ReadinessCopy {
    /// "Good morning," (05–12), "Good afternoon," (12–18), "Good evening," otherwise.
    static func greeting(at date: Date = .now, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return String(localized: "Good morning,")
        case 12..<18: return String(localized: "Good afternoon,")
        default: return String(localized: "Good evening,")
        }
    }

    static func sentence(for state: ReadinessState?, nightsToGo: Int = 1) -> String {
        switch state {
        case .balanced: return String(localized: "Your health is in balance.")
        case .strained: return String(localized: "Take it a little easier today.")
        case .depleted: return String(localized: "Your body is asking for rest.")
        case .calibrating:
            return nightsToGo == 1
                ? String(localized: "Learning your baseline — 1 night to go.")
                : String(localized: "Learning your baseline — \(nightsToGo) nights to go.")
        case nil: return String(localized: "Your scores appear after the first synced night.")
        }
    }

    static func sentence(score: DailyScore?) -> String {
        guard let score else { return sentence(for: ReadinessState?.none) }
        return sentence(for: score.resolvedState, nightsToGo: score.nightsToGo)
    }
}
