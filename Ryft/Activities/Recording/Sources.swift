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
    /// Metres per second as reported by the source; nil when unknown. The pipeline uses its own filter's speed.
    let speed: Double?
    /// `CLLocationUpdate.isStationary`: Core Location thinks the device isn't moving (and pauses its updates).
    let isStationary: Bool

    init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double? = nil, horizontalAccuracy: Double,
         verticalAccuracy: Double? = nil, speed: Double? = nil, isStationary: Bool = false) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.isStationary = isStationary
    }

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

extension LocationFix: LocationRedacting {
    var description: String { "fix(±\(Int(horizontalAccuracy)) m)" }
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
