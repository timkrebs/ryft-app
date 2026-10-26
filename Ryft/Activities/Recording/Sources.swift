import Foundation

// The values the recording sources deliver (design §3.2). Plain values, no Core Location or Core Motion types:
// the live sources (A3b) map `CLLocationUpdate`, `CMAltitudeData` and `CMPedometerData` to them, and tests and
// fixtures build them directly. The source protocols and `ActivitySensors` follow in A3b.

/// One location fix. Never renders its coordinates (design §8.3): `print`, `dump`, `debugPrint`, string
/// interpolation and the debugger summary show the accuracy only.
struct LocationFix: Sendable, Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    /// Metres above the WGS84 ellipsoid or sea level, as Core Location reports it; nil when unknown.
    let altitude: Double?
    /// Metres; negative means invalid (Core Location's convention).
    let horizontalAccuracy: Double
    /// Metres; nil or negative means no valid altitude.
    let verticalAccuracy: Double?
    /// Metres per second as reported by the source (Core Location's Doppler speed); nil when unknown, negative when
    /// invalid. The pipeline measures with its own filter's speed; it asks this one only whether "too fast" is real,
    /// because multipath moves positions and not the Doppler speed (design §3.3).
    let speed: Double?
    /// The speed's accuracy, metres per second; negative means the speed is invalid (`CLLocation.speedAccuracy`),
    /// nil that the source didn't say.
    let speedAccuracy: Double?
    /// `CLLocationUpdate.isStationary`: Core Location thinks the device isn't moving (and pauses its updates).
    let isStationary: Bool

    init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double? = nil, horizontalAccuracy: Double,
         verticalAccuracy: Double? = nil, speed: Double? = nil, speedAccuracy: Double? = nil, isStationary: Bool = false) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.isStationary = isStationary
    }

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }

    /// The Doppler speed when the source reported a valid one: finite, not negative, and with an accuracy that isn't
    /// negative (an unknown accuracy doesn't invalidate it).
    var dopplerSpeed: Double? {
        guard let speed, speed.isFinite, speed >= 0, (speedAccuracy ?? 0) >= 0 else { return nil }
        return speed
    }
}

extension LocationFix: LocationRedacting {
    var description: String { "fix(±\(Self.metres(horizontalAccuracy)) m)" }

    /// Whole metres for a redacted description; "?" for NaN or ±∞, which `Int(_:)` would trap on.
    static func metres(_ value: Double) -> String {
        value.isFinite && abs(value) < 1e15 ? String(Int(value.rounded())) : "?"
    }
}

/// A barometric altitude reading: metres relative to where the altimeter started (`CMAltimeter`).
struct AltitudeSample: Sendable, Equatable {
    let timestamp: Date
    let relativeAltitude: Double
}

/// A pedometer reading, cumulative since the activity's start (`CMPedometer.startUpdates(from:)`).
struct PedometerSample: Sendable, Equatable {
    let timestamp: Date
    let steps: Int
    /// Metres since the start; nil when the pedometer can't estimate distance.
    let distanceM: Double?
    /// Steps per second; nil when Core Motion has no current cadence.
    let cadence: Double?

    init(timestamp: Date, steps: Int, distanceM: Double?, cadence: Double? = nil) {
        self.timestamp = timestamp
        self.steps = steps
        self.distanceM = distanceM
        self.cadence = cadence
    }
}

/// One heart-rate measurement from a BLE sensor (characteristic 0x2A37; RR intervals are ignored).
struct HeartRateReading: Sendable, Equatable {
    let timestamp: Date
    let bpm: Int
}
