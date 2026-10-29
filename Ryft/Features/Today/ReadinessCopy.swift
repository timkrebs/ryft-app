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

    /// The state sentence. `calibrating` covers two cases (API.md, D4): the
    /// baseline is still being built (`baselineReady == false`, "N nights to
    /// go"), or it's complete but today has no readiness yet (no recovery).
    static func sentence(for state: ReadinessState?, nightsToGo: Int = 1, baselineReady: Bool = false) -> String {
        switch state {
        case .balanced: return String(localized: "Your health is in balance.")
        case .strained: return String(localized: "Take it a little easier today.")
        case .depleted: return String(localized: "Your body is asking for rest.")
        case .calibrating:
            if baselineReady {
                return String(localized: "No readiness yet today. It appears once last night has synced.")
            }
            // Singular/plural forms live in Localizable.xcstrings.
            return String(localized: "Learning your baseline — \(nightsToGo) nights to go.")
        case nil: return String(localized: "Your scores appear after the first synced night.")
        }
    }

    /// An unscored row (the platform's placeholder, `DailyScore.empty`) has no readiness yet: its
    /// `state: calibrating` is never a baseline being learned, whatever its flag says. A scored row whose
    /// calibration waiting won't end (`no_hrv` / `no_rhr`) never counts nights to go either.
    static func sentence(score: DailyScore?) -> String {
        guard let score else { return sentence(for: ReadinessState?.none) }
        let unscored = score.standing == .unscored
        if !unscored, score.calibrating, !score.waitingEndsCalibration {
            return blockedSentence(readiness: score.readiness)
        }
        return sentence(for: score.resolvedState, nightsToGo: score.nightsToGo, baselineReady: unscored || !score.calibrating)
    }

    /// A baseline waiting won't fill (N1 / N2, `no_*` or known early from the tracker setup): never nights to go.
    static func blockedSentence(readiness: Int?) -> String {
        // N1: the platform's readiness, from what arrived; N2: no night yet, so no readiness.
        guard readiness != nil else { return sentence(for: .calibrating, baselineReady: true) }
        return String(localized: "Readiness from the signals that reached RYFT.",
                      comment: "Today's sentence: a baseline can't fill (no HRV or resting HR), readiness is from the signals that arrived.")
    }
}
