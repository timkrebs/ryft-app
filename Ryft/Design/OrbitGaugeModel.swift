// The values and modes of `OrbitGauge`. Foundation only, no Theme, no app types: this file is meant to be
// compiled by the app and the widget alike (ios-architect decides where it lives; moving it changes nothing).
//
// `CalibrationProgress` is app-only today, so the calibrating case carries a small value type of its own,
// `OrbitGaugeCalibration`: the nights counted, the nights required and which signal is being counted. The caller
// maps `CalibrationProgress` / `countsHeartRateNights` onto it.
import Foundation

/// The scores one gauge draws. A missing score is `nil` and draws a hollow dot at the orbit's start, never a zero.
struct OrbitGaugeValues: Hashable, Sendable {
    /// Centre ring and number, 1–100.
    var readiness: Int?
    /// Inner orbit, counter-clockwise from the top, 0–1.
    var recovery: Double?
    /// Inner orbit, clockwise from the top, 0–1.
    var sleep: Double?
    /// Outer orbit, clockwise from the top, on the platform's 0–21 scale.
    var strain: Double?
    /// Today's recommended strain range on the 0–21 scale. Not drawn yet (PR 4).
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

    /// Strain as 0–1 of the outer orbit.
    var strainFraction: Double? { strain.map { min(max($0 / Self.strainScale, 0), 1) } }
    var recoveryFraction: Double? { recovery.map { min(max($0, 0), 1) } }
    var sleepFraction: Double? { sleep.map { min(max($0, 0), 1) } }

    /// Nothing to draw but tracks and hollow dots.
    var isEmpty: Bool { readiness == nil && recovery == nil && sleep == nil && strain == nil }
}

/// Which nights the calibrating gauge counts: any night with data, or only nights with heart-rate data
/// (HRV and resting heart rate; `TodayPresentation.Note.needsVitals`).
struct OrbitGaugeCalibration: Hashable, Sendable {
    enum Signal: Hashable, Sendable { case anyNight, heartRateNights }

    static let defaultRequired = 7

    var nights: Int
    var required: Int = Self.defaultRequired
    var signal: Signal = .anyNight

    /// Nights counted, never above the nights required.
    var counted: Int { min(max(nights, 0), required) }
}

enum OrbitGaugeMode: Hashable, Sendable {
    /// The scores of the day. Fully drawn.
    case scored(OrbitGaugeValues)
    /// Baselines still learning: PR 2 draws the outer orbit as segments. Until then: tracks only.
    case calibrating(OrbitGaugeCalibration)
    /// Launch: PR 3. Until then: tracks only.
    case assembling
    /// Last night is being scored; `previous` is the readiness before it. PR 2 draws it dimmed. Until then: tracks only.
    case pending(previous: Int?)
}
