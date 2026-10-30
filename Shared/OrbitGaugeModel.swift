// The values and modes of `OrbitGauge`. Shared by the app and the widget (ADR 0010): Foundation only, no Theme,
// no strings, no app types.
//
// `CalibrationProgress` is app-only, so the calibrating case carries a small value type of its own,
// `OrbitGaugeCalibration`: the nights counted, the nights required and which signal is being counted. The app's
// one mapping (`OrbitGaugeMode+Today.swift`) fills it from `TodayPresentation`; the widget reads it from the snapshot.
import Foundation

/// The scores one gauge draws. A missing score is `nil` and draws a hollow dot at the orbit's start, never a zero.
struct OrbitGaugeValues: Hashable, Sendable {
    /// Centre ring and number, 0–100.
    var readiness: Int?
    /// Inner orbit, counter-clockwise from the top, 0–1.
    var recovery: Double?
    /// Inner orbit, clockwise from the top, 0–1.
    var sleep: Double?
    /// Outer orbit, clockwise from the top, on the platform's 0–21 scale.
    var strain: Double?
    /// Today's recommended strain range on the 0–21 scale: drawn as a rail inside the outer orbit, with the arc shifting
    /// toward alert past its upper end (PR 4, design.md §11). Production passes nil until the platform serves it.
    var strainBand: ClosedRange<Double>?

    static let strainScale = 21.0

    init(readiness: Int? = nil, recovery: Double? = nil, sleep: Double? = nil, strain: Double? = nil,
         strainBand: ClosedRange<Double>? = nil) {
        self.readiness = readiness
        self.recovery = recovery
        self.sleep = sleep
        self.strain = strain
        self.strainBand = strainBand
    }

    /// From the platform's numbers (`readiness`, `recovery` and `sleep_performance` 0–100, `strain` 0–21): the one
    /// place they become the orbit's fractions, for the app and the widget alike.
    init(readiness: Int?, recoveryScore: Int?, sleepPerformance: Int?, strain: Double?) {
        self.init(readiness: readiness, recovery: recoveryScore.map { Double($0) / 100 },
                  sleep: sleepPerformance.map { Double($0) / 100 }, strain: strain)
    }

    static let empty = OrbitGaugeValues()

    /// Strain as 0–1 of the outer orbit.
    var strainFraction: Double? { strain.map { min(max($0 / Self.strainScale, 0), 1) } }
    var recoveryFraction: Double? { recovery.map { min(max($0, 0), 1) } }
    var sleepFraction: Double? { sleep.map { min(max($0, 0), 1) } }

    /// Nothing to draw but tracks and hollow dots.
    var isEmpty: Bool { readiness == nil && recovery == nil && sleep == nil && strain == nil }
}

/// Which nights the calibrating gauge counts.
struct OrbitGaugeCalibration: Hashable, Sendable {
    /// What the count counts. The raw values are stored in the widget's snapshot: only add cases.
    enum Signal: String, Codable, Hashable, Sendable {
        /// `baseline_days`: nights with what a baseline needs (S1, path L's short history).
        case anyNight
        /// Nights with HRV and resting heart rate in a long history (path L, `.needsVitals`).
        case heartRateNights
        /// Only HRV fills while resting heart rate is absent (F3).
        case hrv
        /// Only resting heart rate fills while HRV is absent (F3).
        case restingHR
    }

    static let defaultRequired = 7

    var nights: Int
    var required: Int = Self.defaultRequired
    var signal: Signal = .anyNight

    /// Nights counted, never above the nights required.
    var counted: Int { min(max(nights, 0), required) }
}

/// What the gauge shows. Data only: the launch entrance is presentation (PR 3), not a mode.
enum OrbitGaugeMode: Hashable, Sendable {
    /// The scores of the day. Fully drawn. `learning`: a readiness while the baselines still fill (S2); PR 2 decides
    /// whether the count is drawn, PR 1 ignores it.
    case scored(OrbitGaugeValues, learning: OrbitGaugeCalibration? = nil)
    /// Baselines still learning: the outer orbit is `required` segments, `counted` of them filled; inner orbit and
    /// centre are tracks, the three dots hollow at their starts.
    case calibrating(OrbitGaugeCalibration)
    /// Last night is being scored; `previous` is the latest scored day before it (nil: none), drawn dimmed. Without
    /// one: tracks and hollow dots.
    case pending(previous: OrbitGaugeValues?)

    /// The scores of the day drawn in full, or nil: only `.scored` has any.
    var scoredValues: OrbitGaugeValues? {
        if case .scored(let values, _) = self { return values }
        return nil
    }

    /// The scores the drawing puts arcs and dots for: the day's, or while pending the previous day's (dimmed).
    var drawnValues: OrbitGaugeValues? {
        switch self {
        case .scored(let values, _): return values
        case .pending(let previous): return previous
        case .calibrating: return nil
        }
    }

    /// Drawn dimmed, the previous day's scores waiting for today's.
    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}
