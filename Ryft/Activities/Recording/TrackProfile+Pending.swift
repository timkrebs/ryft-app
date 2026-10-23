// A1 defines this in Sport.swift; delete on merge.
//
// A temporary copy so `feat/track-pipeline` compiles on its own. The shape is frozen by the lead (design §2.1):
// the GPS pipeline is parameterised by it and never depends on `Sport`.

/// The per-sport values the track pipeline needs (design §2.1).
struct TrackProfile: Equatable, Sendable {
    enum Elevation: Sendable { case primary, secondary, none }
    enum PaceStyle: Sendable { case pace, speed }
    var maxSpeed: Double?
    var sigmaA: Double?
    var autoPauseThreshold: Double?
    var autoPauseDefault: Bool
    var elevation: Elevation
    var paceStyle: PaceStyle
}
