import Foundation
@testable import Ryft

/// Tracks for the speed-gate guard's acceptance (design §11.1, rev. A3a.2): per-second speeds along `SyntheticTrack`'s
/// straight line, seeded drifting noise and ghost offsets, plus a turning path for the manoeuvres. No JSON fixture.
enum GuardTrack {
    /// A linear speed change over `seconds`; each second moves at the speed at its middle.
    struct Ramp {
        let seconds: Int
        let from: Double
        let to: Double

        init(_ seconds: Int, _ from: Double, _ to: Double) {
            self.seconds = seconds
            self.from = from
            self.to = to
        }

        static func hold(_ seconds: Int, _ speed: Double) -> Ramp { Ramp(seconds, speed, speed) }
    }

    /// Fixes `from ..< from + count` sit `offset` away from the truth with a falsely good accuracy: multipath.
    struct Ghost {
        let from: Int
        let count: Int
        let offset: Displacement
        var accuracy = 10.0
    }

    /// The design's three ghost directions, 60 m each from a track at 60°: sideways and 30 m behind (the existing
    /// multipath tests' offset), straight sideways, and straight ahead.
    static let ghostOffsets = [
        Displacement(east: -52, north: 30),
        Displacement(east: -30, north: 51.96),
        Displacement(east: 51.96, north: 30)
    ]

    static func speeds(_ ramps: [Ramp]) -> [Double] {
        ramps.flatMap { ramp in
            (0 ..< ramp.seconds).map { ramp.from + (ramp.to - ramp.from) * (Double($0) + 0.5) / Double(ramp.seconds) }
        }
    }

    /// The distance of the seconds whose speed is at most `limit`.
    static func distance(_ speeds: [Double], atMost limit: Double = .infinity) -> Double {
        speeds.filter { $0 <= limit }.reduce(0, +)
    }

    /// When the truth passes `limit`: the start of the first second faster than it, and of the first second at or below
    /// it after that (nil if it stays above).
    static func crossings(_ speeds: [Double], limit: Double) -> (above: Date, below: Date?)? {
        guard let up = speeds.firstIndex(where: { $0 > limit }) else { return nil }
        let down = speeds[up...].firstIndex { $0 <= limit }
        return (SyntheticTrack.t0.addingTimeInterval(Double(up)), down.map { SyntheticTrack.t0.addingTimeInterval(Double($0)) })
    }

    /// 1 Hz fixes from `SyntheticTrack.t0`: fix i is where second i ends, so second i moves at `speeds[i]`. With a
    /// seed, drifting noise: Gauss–Markov per axis (τ 60 s, σ = accuracy / 2) plus 0.4 m of white jitter.
    static func fixes(_ speeds: [Double], accuracy: Double = 5, seed: UInt64? = nil, sigma: Double? = nil,
                      ghost: Ghost? = nil) -> [LocationFix] {
        let clean = SyntheticTrack.fixes(speeds.map { SyntheticTrack.Segment(seconds: 1, speed: $0) }, accuracy: accuracy)
        return perturbed(clean, accuracy: accuracy, seed: seed, sigma: sigma, ghost: ghost)
    }

    /// The same along a path whose heading turns by `turns[i]` degrees during second i (in 20 sub-steps).
    static func turning(_ speeds: [Double], turns: [Int: Double], accuracy: Double = 5, seed: UInt64? = nil) -> [LocationFix] {
        var position = SyntheticTrack.origin, heading = 60.0
        var clean = [fix(at: 0, position, accuracy)]
        for (i, speed) in speeds.enumerated() {
            for _ in 0 ..< 20 {
                position = Geodesy.destination(from: position, bearing: heading, distance: speed / 20)
                heading += (turns[i] ?? 0) / 20
            }
            clean.append(fix(at: i + 1, position, accuracy))
        }
        return perturbed(clean, accuracy: accuracy, seed: seed, sigma: nil, ghost: nil)
    }

    /// Feeds `fixes` to a pipeline started at the fix `startIndex` (the ones before warm the filter), then finishes at
    /// the last fix. Returns the pipeline and every event, Finish's included.
    static func record(_ configuration: TrackPipeline.Configuration, _ fixes: [LocationFix],
                       startIndex: Int = 0) -> (pipeline: TrackPipeline, events: [PipelineEvent]) {
        var p = TrackPipeline(configuration: configuration)
        for fix in fixes[..<startIndex] { _ = p.ingest(fix) }
        p.start(at: fixes[startIndex].timestamp)
        var events: [PipelineEvent] = []
        for fix in fixes[startIndex...] { events += p.ingest(fix) }
        if let last = fixes.last { events += p.finish(at: last.timestamp) }
        return (p, events)
    }

    static func tooFast(_ events: [PipelineEvent]) -> [Date] {
        events.compactMap { if case let .tooFast(since) = $0 { since } else { nil } }
    }

    static func tooFastEnded(_ events: [PipelineEvent]) -> [Date] {
        events.compactMap { if case let .tooFastEnded(since) = $0 { since } else { nil } }
    }

    static func routes(_ events: [PipelineEvent]) -> Int {
        events.filter { if case .route = $0 { true } else { false } }.count
    }

    private static func fix(at second: Int, _ c: Coordinate, _ accuracy: Double) -> LocationFix {
        LocationFix(timestamp: SyntheticTrack.t0.addingTimeInterval(Double(second)), latitude: c.latitude,
                    longitude: c.longitude, horizontalAccuracy: accuracy)
    }

    private static func perturbed(_ clean: [LocationFix], accuracy: Double, seed: UInt64?, sigma: Double?,
                                  ghost: Ghost?) -> [LocationFix] {
        var rng = SeededGenerator(seed: (seed ?? 0) &* 7919 &+ 13)
        let sigma = seed == nil ? 0 : sigma ?? accuracy / 2, jitter = seed == nil ? 0 : 0.4
        let rho = exp(-1 / 60.0)
        var drift = (east: rng.gaussian() * sigma, north: rng.gaussian() * sigma)
        return clean.enumerated().map { i, fix in
            drift.east = rho * drift.east + (1 - rho * rho).squareRoot() * sigma * rng.gaussian()
            drift.north = rho * drift.north + (1 - rho * rho).squareRoot() * sigma * rng.gaussian()
            var off = Displacement(east: drift.east + jitter * rng.gaussian(), north: drift.north + jitter * rng.gaussian())
            var reported = accuracy
            if let ghost, i >= ghost.from, i < ghost.from + ghost.count {
                off = Displacement(east: off.east + ghost.offset.east, north: off.north + ghost.offset.north)
                reported = ghost.accuracy
            }
            let c = LocalTangentPlane(anchor: fix.coordinate).unproject(off)
            return LocationFix(timestamp: fix.timestamp, latitude: c.latitude, longitude: c.longitude,
                               horizontalAccuracy: reported)
        }
    }
}
