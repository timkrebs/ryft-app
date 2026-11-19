// Words on the Today screen: greeting by time of day and the state sentence.
import Foundation

enum ReadinessCopy {
    /// "Good morning, Alex" (05–12), "Good afternoon, Alex" (12–18), "Good evening, Alex" otherwise (Nocturne, design.md
    /// §P4-1 row 2). Without a name (`firstName(_:)` found none: Sign in with Apple may deliver none, R-N2) the same words
    /// with no comma: "Good evening".
    static func greeting(at date: Date = .now, name: String? = nil, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        guard let name else {
            switch hour {
            case 5..<12:
                return String(localized: "Good morning", comment: "Today's greeting before 12:00 when no first name is known.")
            case 12..<18:
                return String(localized: "Good afternoon", comment: "Today's greeting from 12:00 to 18:00 when no first name is known.")
            default:
                return String(localized: "Good evening", comment: "Today's greeting from 18:00 (and before 05:00) when no first name is known.")
            }
        }
        switch hour {
        case 5..<12:
            return String(localized: "Good morning, \(name)", comment: "Today's greeting before 12:00, with the user's first name.")
        case 12..<18:
            return String(localized: "Good afternoon, \(name)", comment: "Today's greeting from 12:00 to 18:00, with the user's first name.")
        default:
            return String(localized: "Good evening, \(name)",
                          comment: "Today's greeting from 18:00 (and before 05:00), with the user's first name.")
        }
    }

    /// The first word of the account's name (`User.name`, the sign-in's `full_name`), trimmed: "Alex" of "Alex Doe".
    /// nil for an empty or blank name, so the greeting goes without one (R-N2).
    static func firstName(_ fullName: String?) -> String? {
        guard let word = fullName?.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).first else { return nil }
        return String(word)
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
