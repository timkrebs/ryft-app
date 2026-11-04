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

        /// The setup says the signals can't arrive (the app doesn't share them, or just the iPhone): waiting
        /// won't fill the baseline, whatever the history's length (F3's N1 early).
        var isKnownNotToSend: Bool {
            switch self {
            case .notShared, .phoneOnly: return true
            case .unexpected, .unknown: return false
            }
        }
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

/// A baseline still learning (`short_history`, S1 / S2): its nights, which baseline it is when the row says, and the
/// signal that isn't arriving when only one of the two fills (F3).
struct CalibrationProgress: Equatable, Sendable {
    /// `baseline_days`; with `absent`, the filling signal's own count (`baseline_rhr_days` or `baseline_hrv_days`).
    let nights: Int
    /// `DailyScore.fillingSignals`: none named when the row doesn't say. With `absent`, the one signal counted.
    let signals: [CalibrationSignal]
    /// The other signal, none of which reached RYFT (window and day): the counter counts `signals` instead of
    /// `baseline_days`, which can't move without it. Its source as `CalibrationBlocker.resolve` knows it (never one
    /// that is known not to share it: that row is N1).
    var absent: CalibrationBlocker?

    var text: String {
        let required = DailyScore.baselineNightsRequired
        let nights = min(max(nights, 0), required)
        if absent != nil {
            switch signals {
            case [.restingHR]:
                // swiftlint:disable:next line_length
                return String(localized: "Learning your resting heart rate baseline: \(nights) of \(required) nights. No HRV has reached RYFT yet, so recovery uses resting heart rate and sleep.",
                              comment: "Note under Today's gauge: only resting HR fills, no HRV arrived. Arguments: nights so far, nights needed (7).")
            case [.hrv]:
                // swiftlint:disable:next line_length
                return String(localized: "Learning your HRV baseline: \(nights) of \(required) nights. No resting heart rate has reached RYFT yet, so recovery uses HRV and sleep.",
                              comment: "Note under Today's gauge: only HRV fills, no resting HR arrived. Arguments: nights so far, nights needed (7).")
            default: break
            }
        }
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

    /// Signals neither the window nor the day has (F3): a count of 0 and no `hrv_ms` / `rhr` today. Nothing if
    /// either count is unknown. On a `short_history` row in the first week (`W < 7`) these are what `no_*` will
    /// say later; the first morning a source arrives has its value on the day, so it isn't absent.
    var absentSignals: [CalibrationSignal] {
        guard let hrv = baselineHrvDays, let rhr = baselineRhrDays else { return [] }
        var signals: [CalibrationSignal] = []
        if hrv == 0, hrvMs == nil { signals.append(.hrv) }
        if rhr == 0, self.rhr == nil { signals.append(.restingHR) }
        return signals
    }

    /// The one signal still filling while the other is absent (F3), and its count: R when no HRV ever arrived, H when
    /// no resting HR did. Nil when both or neither are absent, or the other has no night yet (a first night: 0 of 7
    /// moves tomorrow either way).
    var onlyFillingSignal: (signal: CalibrationSignal, nights: Int)? {
        guard let hrv = baselineHrvDays, let rhr = baselineRhrDays else { return nil }
        switch absentSignals {
        case [.hrv] where rhr > 0: return (.restingHR, rhr)
        case [.restingHR] where hrv > 0: return (.hrv, hrv)
        default: return nil
        }
    }

    /// The calibration note may name the chosen tracker (`CalibrationBlocker.resolve`): a `no_*` row, or a
    /// `short_history` row with an absent signal (N1 early, or the filling note). The facts builders read the
    /// choice and the catalog only for these.
    var calibrationNamesTracker: Bool {
        guard calibrating else { return false }
        return !waitingEndsCalibration || (calibratingReason == .shortHistory && !absentSignals.isEmpty)
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
