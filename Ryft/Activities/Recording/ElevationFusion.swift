import Foundation

/// Altitude, ascent and descent from the barometer and GPS (design §3.4).
///
/// - **Barometric:** `CMAltimeter`'s relative altitude carries the shape; absolute altitude is
///   `relative + offset`, the offset being the median of `gpsAltitude − relative` over the last 5 min of fixes
///   with `verticalAccuracy` ≤ 10 m (it absorbs slow weather drift). Ascent and descent accumulate on the
///   relative altitude with a 2 m hysteresis.
/// - **GPS only:** altitude from fixes with `verticalAccuracy` ≤ 15 m, the median of the last 5, with a 5 m
///   hysteresis.
/// - **None:** indoor sports and sports without GPS.
///
/// Counting can be suspended (paused, auto-paused): the altitude keeps updating, and the next count starts from
/// wherever the altitude is when counting resumes, so a climb during a pause adds nothing.
struct ElevationFusion: Sendable {
    enum Mode: String, Codable, Sendable { case barometric, gps, none }

    struct Tuning: Sendable, Equatable {
        var barometricHysteresis: Double = 2
        var gpsHysteresis: Double = 5
        var offsetMaxVerticalAccuracy: Double = 10
        var offsetWindow: TimeInterval = 300
        var gpsMaxVerticalAccuracy: Double = 15
        var gpsMedianCount: Int = 5
    }

    let mode: Mode
    let tuning: Tuning
    private(set) var ascentM: Double = 0
    private(set) var descentM: Double = 0
    /// Whether changes are counted (recording) or only followed (paused).
    private(set) var isCounting = true

    private var counter: HysteresisCounter
    private var latestRelative: Double?
    private var offsetSamples: [(time: Date, offset: Double)] = []
    private var gpsWindow: [Double] = []
    private var gpsAltitude: Double?
    /// The median of `offsetSamples`, kept as they change (read once per fix).
    private(set) var offset: Double?

    init(mode: Mode, tuning: Tuning = Tuning(), ascentM: Double = 0, descentM: Double = 0) {
        self.mode = mode
        self.tuning = tuning
        self.ascentM = ascentM
        self.descentM = descentM
        counter = HysteresisCounter(threshold: mode == .gps ? tuning.gpsHysteresis : tuning.barometricHysteresis)
    }

    /// Absolute altitude, metres; nil until known (barometric: until the first usable GPS altitude arrives).
    var altitudeM: Double? {
        switch mode {
        case .none: return nil
        case .gps: return gpsAltitude
        case .barometric:
            guard let relative = latestRelative, let offset = offset else { return nil }
            return relative + offset
        }
    }

    /// Ascent for the record: nil when the mode has no elevation.
    var ascent: Double? { mode == .none ? nil : ascentM }
    var descent: Double? { mode == .none ? nil : descentM }

    mutating func setCounting(_ counting: Bool) {
        guard counting != isCounting else { return }
        isCounting = counting
        if counting { counter.restart() }
    }

    /// A barometric reading. Ignored unless the mode is barometric.
    mutating func add(_ sample: AltitudeSample) {
        guard mode == .barometric else { return }
        latestRelative = sample.relativeAltitude
        feed(sample.relativeAltitude)
    }

    /// A fix's GPS altitude: the barometric offset, or the GPS-only altitude.
    mutating func add(fix: LocationFix) {
        guard let altitude = fix.altitude, let vAcc = fix.verticalAccuracy, vAcc >= 0 else { return }
        switch mode {
        case .none:
            return
        case .barometric:
            guard vAcc <= tuning.offsetMaxVerticalAccuracy, let relative = latestRelative else { return }
            offsetSamples.append((fix.timestamp, altitude - relative))
            let cutoff = fix.timestamp.addingTimeInterval(-tuning.offsetWindow)
            if let firstKept = offsetSamples.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
                offsetSamples.removeFirst(firstKept)
            }
            offset = Self.median(offsetSamples.map(\.offset))
        case .gps:
            guard vAcc <= tuning.gpsMaxVerticalAccuracy else { return }
            gpsWindow.append(altitude)
            if gpsWindow.count > tuning.gpsMedianCount { gpsWindow.removeFirst() }
            let smoothed = Self.median(gpsWindow)
            gpsAltitude = smoothed
            feed(smoothed)
        }
    }

    private mutating func feed(_ value: Double) {
        let change = counter.add(value)
        guard isCounting else { return }
        ascentM += change.ascent
        descentM += change.descent
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}

/// Counts ascent and descent with a hysteresis: a trend is counted continuously from its extreme, and the
/// direction flips only after a move of `threshold` against it (counted in full when it flips). Noise smaller
/// than the threshold adds nothing; nothing of a real climb is lost at a turn.
struct HysteresisCounter: Sendable, Equatable {
    enum Direction: Sendable, Equatable { case none, up, down }

    let threshold: Double
    private(set) var direction: Direction = .none
    private(set) var reference: Double?

    init(threshold: Double) {
        self.threshold = threshold
    }

    /// Forget the reference: the next value starts a new count (after a pause).
    mutating func restart() {
        direction = .none
        reference = nil
    }

    mutating func add(_ value: Double) -> (ascent: Double, descent: Double) {
        guard let ref = reference else {
            reference = value
            return (0, 0)
        }
        switch direction {
        case .up:
            if value > ref {
                reference = value
                return (value - ref, 0)
            }
            if ref - value >= threshold {
                direction = .down
                reference = value
                return (0, ref - value)
            }
        case .down:
            if value < ref {
                reference = value
                return (0, ref - value)
            }
            if value - ref >= threshold {
                direction = .up
                reference = value
                return (value - ref, 0)
            }
        case .none:
            if value - ref >= threshold {
                direction = .up
                reference = value
                return (value - ref, 0)
            }
            if ref - value >= threshold {
                direction = .down
                reference = value
                return (0, ref - value)
            }
        }
        return (0, 0)
    }
}
