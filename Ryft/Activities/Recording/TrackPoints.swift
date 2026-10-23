import Foundation

// The records a recording produces (design §2.3): `ProfilePoint` (no coordinates) and `RoutePoint` (a filtered
// position), plus the redaction every location type shares (design §8.3).

/// A type that holds a location and must never render it. `description` shows accuracy or nothing;
/// `debugDescription` repeats it, and the mirror has no children, so `print`, `dump`, `debugPrint`, string
/// interpolation and the debugger's summary never show a coordinate.
protocol LocationRedacting: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}

extension LocationRedacting {
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// One point of the profile: what charts, splits and resume need, with no coordinate. 16 bytes in `TrackCodec`.
struct ProfilePoint: Sendable, Equatable {
    let time: Date
    /// Cumulative recorded distance, metres.
    let distanceM: Double
    /// Fused altitude, metres; nil without elevation.
    let altitudeM: Double?
    /// The filter's (or the pedometer's) speed, metres per second; nil when unknown.
    let speedMps: Double?
}

/// One point of the route: a filtered position. Written only with the route opt-in, trimmed and sealed
/// (design §2.3, §8.2). 28 bytes in `TrackCodec`.
struct RoutePoint: Sendable, Equatable {
    let time: Date
    let latitude: Double
    let longitude: Double
    /// The filter's one-sigma position uncertainty, metres.
    let horizontalAccuracy: Double
    /// Fused altitude, metres; nil without elevation.
    let altitude: Double?

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

extension RoutePoint: LocationRedacting {
    var description: String { "routePoint(±\(Int(horizontalAccuracy)) m)" }
}
