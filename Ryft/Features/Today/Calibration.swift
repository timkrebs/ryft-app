import Foundation

// Today's honest calibration (design.md §7 rev. 2): what a calibrating row's `calibrating_reason` means for the
// line under the gauge. Values only: `TodayPresentation.decide` picks them, `TodayView` shows them.

/// A signal a baseline is built from, as Today names it in a sentence.
enum CalibrationSignal: String, Equatable, Sendable {
    case hrv, restingHR

    /// Inside a sentence ("No HRV has reached RYFT …"): lower case where the language has it, never a title
    /// (Check sync's "Resting heart rate" is one).
    var inSentence: String {
        switch self {
        case .hrv:
            return String(localized: "calibration.signal.hrv", defaultValue: "HRV",
                          comment: "Heart-rate variability inside a sentence on Today, e.g. “No HRV has reached RYFT from your nights.”")
        case .restingHR:
            return String(localized: "calibration.signal.restingHR", defaultValue: "resting heart rate",
                          comment: "Resting heart rate inside a sentence on Today, e.g. “Oura doesn't share HRV or resting heart rate with Apple Health.”")
        }
    }

    /// The tracker catalog's name for it: what a tracker shares with Apple Health.
    var trackerSignal: TrackerSignal {
        switch self {
        case .hrv: return .hrv
        case .restingHR: return .restingHR
        }
    }

    /// "HRV", "HRV or resting heart rate": in the app's language.
    static func list(_ signals: [CalibrationSignal]) -> String {
        signals.map(\.inSentence).formatted(.list(type: .or))
    }
}

/// Where the note's link goes (§2): a sheet with "Done" over Today.
enum CalibrationLink: Hashable, Identifiable, Sendable {
    /// The tracker's card: "How to set up Garmin Connect".
    case setup(trackerID: String, app: String)
    /// Check sync on the chosen trackers.
    case checkSync
    /// Profile → Devices & sync.
    case devices

    var id: Self { self }

    var title: String {
        switch self {
        case .setup(_, let app):
            return String(localized: "How to set up \(app)",
                          comment: "Link under Today's gauge: opens the tracker's setup card. The argument is its app, e.g. Garmin Connect.")
        case .checkSync: return String(localized: "Check sync")
        case .devices: return String(localized: "Devices & sync")
        }
    }
}

/// A baseline that waiting won't finish (`no_hrv` / `no_rhr`): the signals missing from the window, what RYFT can
/// honestly say about why, and where to fix it. Never a count.
struct CalibrationBlocker: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// The one chosen tracker's app doesn't share them with Apple Health (its catalog says `no`).
        case notShared(app: String)
        /// "Just my iPhone", which records neither.
        case phoneOnly
        /// A chosen tracker should send one of them (`yes` / `partial`): something in the sync is off.
        case unexpected
        /// Nothing more is known: the flag is off, nothing or several chosen, unverified, no app of its own.
        case unknown
    }

    let signals: [CalibrationSignal]
    let source: Source
    /// nil while `devices.setup` is off.
    let link: CalibrationLink?

    /// §2's table, the first matching row wins. `trackers`: the chosen catalog entries, `[]` while the flag is off.
    static func resolve(_ signals: [CalibrationSignal], trackers: [Tracker], devicesSetup: Bool) -> CalibrationBlocker {
        // 1: without the flag, only what the platform said: no such signal in the window.
        guard devicesSetup else { return CalibrationBlocker(signals: signals, source: .unknown, link: nil) }
        let missing = signals.map(\.trackerSignal)
        // 2: a chosen tracker should send one of them (an Apple Watch always does).
        let expected: Set<Capability> = [.yes, .partial]
        if trackers.contains(where: { tracker in missing.contains { expected.contains(tracker.capabilities[$0] ?? .unverified) } }) {
            return CalibrationBlocker(signals: signals, source: .unexpected, link: .checkSync)
        }
        if trackers.count == 1, let tracker = trackers.first {
            // 3: one tracker with an app of its own that shares none of them: name the app, link its card.
            if tracker.integration == .vendorApp, !missing.isEmpty, missing.allSatisfy({ tracker.capabilities[$0] == .no }) {
                return CalibrationBlocker(signals: signals, source: .notShared(app: tracker.appTitle),
                                          link: .setup(trackerID: tracker.id, app: tracker.appTitle))
            }
            // 4: Just my iPhone.
            if tracker.isJustIPhone { return CalibrationBlocker(signals: signals, source: .phoneOnly, link: .devices) }
        }
        // 5: nothing chosen, several, unverified, no app of its own (Samsung, Other): the generic note.
        return CalibrationBlocker(signals: signals, source: .unknown, link: .devices)
    }

    /// The note under the gauge: the signals, and the app when the catalog knows it doesn't share them. No digit.
    var text: String {
        // Both: written out, never a formatted list, so German can say "weder … noch".
        if Set(signals) == [.hrv, .restingHR] { return bothText }
        let signal = CalibrationSignal.list(signals)
        switch source {
        case .notShared(let app):
            return String(localized: "\(app) doesn't share \(signal) with Apple Health.",
                          comment: "Under Today's gauge: the app doesn't write it to Apple Health. Args: app (Garmin Connect), one signal (HRV).")
        case .phoneOnly:
            return String(localized: "An iPhone on its own doesn't record \(signal).",
                          comment: "Note under Today's gauge for “Just my iPhone”. The argument is one signal, e.g. “HRV”.")
        case .unexpected, .unknown:
            return String(localized: "No \(signal) has reached RYFT from your nights.",
                          comment: "Under Today's gauge: no such signal in the baseline window. The argument is one signal, e.g. “HRV”.")
        }
    }

    /// HRV and resting heart rate both missing.
    private var bothText: String {
        switch source {
        case .notShared(let app):
            return String(localized: "\(app) doesn't share HRV or resting heart rate with Apple Health.",
                          comment: "Under Today's gauge: the app writes neither to Apple Health. The argument is the app, e.g. Oura.")
        case .phoneOnly:
            return String(localized: "An iPhone on its own doesn't record HRV or resting heart rate.",
                          comment: "Note under Today's gauge for “Just my iPhone”: neither signal reaches RYFT.")
        case .unexpected, .unknown:
            return String(localized: "No HRV or resting heart rate has reached RYFT from your nights.",
                          comment: "Under Today's gauge: neither signal is in the baseline window.")
        }
    }
}

/// A baseline still learning under a readiness the platform already computed (S2): its nights, and which
/// baseline it is when the row says.
struct CalibrationProgress: Equatable, Sendable {
    /// `baseline_days`.
    let nights: Int
    /// `DailyScore.fillingSignals`: none named when the row doesn't say.
    let signals: [CalibrationSignal]

    var text: String {
        let required = DailyScore.baselineNightsRequired
        let nights = min(max(nights, 0), required)
        switch signals {
        case [.hrv]:
            return String(localized: "Learning your HRV baseline: \(nights) of \(required) nights.",
                          comment: "Note under Today's gauge while the HRV baseline fills. Arguments: nights so far, nights needed (7).")
        case [.restingHR]:
            return String(localized: "Learning your resting heart rate baseline: \(nights) of \(required) nights.",
                          comment: "Note under Today's gauge while the resting heart rate baseline fills. Arguments: nights so far, nights needed (7).")
        default:
            return String(localized: "Learning your baselines: \(nights) of \(required) nights.",
                          comment: "Note under Today's gauge while the baselines fill. Arguments: nights so far, nights needed (7).")
        }
    }
}

// Here, not in Models.swift (the contract keeper's): what Today reads from the row's reason and counts.
extension DailyScore {
    /// More nights end the calibration: not for `no_hrv` / `no_rhr`, where the window has no such signal at all.
    var waitingEndsCalibration: Bool { calibratingReason != .noHrv && calibratingReason != .noRhr }

    /// What a `no_*` row's note names (§1): `no_hrv` names HRV, and resting HR too when R is 0 (API.md's second
    /// gap: the day then has no `rhr` either); `no_rhr` names resting HR. Nothing for any other row.
    var missingSignals: [CalibrationSignal] {
        switch calibratingReason {
        case .noHrv?: return baselineRhrDays == 0 ? [.hrv, .restingHR] : [.hrv]
        case .noRhr?: return [.restingHR]
        case .shortHistory?, nil: return []
        }
    }

    /// The baselines still learning (§1): HRV if H < 7, resting HR if R < 7; nothing if either count is unknown.
    var fillingSignals: [CalibrationSignal] {
        guard let hrv = baselineHrvDays, let rhr = baselineRhrDays else { return [] }
        var signals: [CalibrationSignal] = []
        if hrv < Self.baselineNightsRequired { signals.append(.hrv) }
        if rhr < Self.baselineNightsRequired { signals.append(.restingHR) }
        return signals
    }
}
