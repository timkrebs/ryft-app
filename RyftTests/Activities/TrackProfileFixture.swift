@testable import Ryft

/// Design §2.1's values for the sports the track tests use. Test-only: A1 defines `TrackProfile` in `Sport.swift`
/// and derives each sport's profile from the catalogue; these copies keep the pipeline's tests independent of `Sport`.
extension TrackProfile {
    /// `running`: max 9 m/s, σa 1.5, auto-pause on at 1.0 m/s, elevation secondary.
    static let run = TrackProfile(maxSpeed: 9, sigmaA: 1.5, autoPauseThreshold: 1.0, autoPauseDefault: true,
                                  elevation: .secondary, paceStyle: .pace)
    /// `trail_running`: max 8 m/s, σa 1.5, auto-pause on at 0.8 m/s, elevation primary.
    static let trail = TrackProfile(maxSpeed: 8, sigmaA: 1.5, autoPauseThreshold: 0.8, autoPauseDefault: true,
                                    elevation: .primary, paceStyle: .pace)
    /// `cycling`: max 25 m/s, σa 3.0, auto-pause on at 1.5 m/s, elevation secondary, speed.
    static let bike = TrackProfile(maxSpeed: 25, sigmaA: 3.0, autoPauseThreshold: 1.5, autoPauseDefault: true,
                                   elevation: .secondary, paceStyle: .speed)
    /// `walking`: max 4 m/s, σa 1.0, auto-pause off (0.4 m/s), elevation secondary.
    static let walk = TrackProfile(maxSpeed: 4, sigmaA: 1.0, autoPauseThreshold: 0.4, autoPauseDefault: false,
                                   elevation: .secondary, paceStyle: .pace)
    /// `hiking`: max 4 m/s, σa 1.0, auto-pause off (0.3 m/s), elevation primary.
    static let hike = TrackProfile(maxSpeed: 4, sigmaA: 1.0, autoPauseThreshold: 0.3, autoPauseDefault: false,
                                   elevation: .primary, paceStyle: .pace)
    /// `indoor_running`: no GPS; auto-pause on cadence 0.
    static let indoorRun = TrackProfile(maxSpeed: nil, sigmaA: nil, autoPauseThreshold: nil, autoPauseDefault: true,
                                        elevation: .none, paceStyle: .pace)
}
