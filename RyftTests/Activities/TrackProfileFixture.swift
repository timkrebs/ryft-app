@testable import Ryft

/// The track tests' profiles, straight from the sport catalogue (`Sport.swift`), so the pipeline's tests guard the
/// values the app records with. Short names, so the tests read as before.
extension TrackProfile {
    /// `running`: max 9 m/s, σa 1.5, auto-pause on at 1.0 m/s, elevation secondary.
    static var run: TrackProfile { Sport.running.trackProfile }
    /// `trail_running`: max 8 m/s, σa 1.5, auto-pause on at 0.8 m/s, elevation primary.
    static var trail: TrackProfile { Sport.trailRunning.trackProfile }
    /// `cycling`: max 36 m/s (road descents), σa 3.0, auto-pause on at 1.5 m/s, elevation secondary, speed.
    static var bike: TrackProfile { Sport.cycling.trackProfile }
    /// `mountain_biking`: max 25 m/s, σa 3.0, auto-pause on at 1.2 m/s, elevation primary, speed.
    static var mtb: TrackProfile { Sport.mountainBiking.trackProfile }
    /// `walking`: max 6 m/s (a run for the bus stays a walk), σa 1.0, auto-pause off (0.4 m/s), elevation secondary.
    static var walk: TrackProfile { Sport.walking.trackProfile }
    /// `hiking`: max 6 m/s, σa 1.0, auto-pause off (0.3 m/s), elevation primary.
    static var hike: TrackProfile { Sport.hiking.trackProfile }
    /// `indoor_running`: no GPS; auto-pause on cadence 0 (the catalogue's threshold is 0, not nil: the pipeline
    /// reads it only as `?? 0` and for GPS).
    static var indoorRun: TrackProfile { Sport.indoorRunning.trackProfile }
}
