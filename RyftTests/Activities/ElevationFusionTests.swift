import Foundation
import Testing
@testable import Ryft

/// Elevation (design §3.4). Measured on the committed trail: barometric ascent 400.5 m and descent 399.8 m (truth
/// 399.9 m); GPS-only ascent 388.0 m (−3.0 %).
@Suite("Elevation fusion")
struct ElevationFusionTests {
    static let t0 = SyntheticTrack.t0

    static func fix(_ seconds: Double, altitude: Double, verticalAccuracy: Double) -> LocationFix {
        LocationFix(timestamp: t0.addingTimeInterval(seconds), latitude: 47.87, longitude: 8.0, altitude: altitude,
                    horizontalAccuracy: 5, verticalAccuracy: verticalAccuracy)
    }

    @Test func trailBarometricAscentWithinThreeMetres() throws {
        let trail = try TrackFixture.load("trail-switchbacks")
        let replay = TrackReplay(trail, .gps(.trail, barometer: true))
        #expect(replay.pipeline.configuration.elevation == .barometric)
        let ascent = try #require(replay.pipeline.ascentM), descent = try #require(replay.pipeline.descentM)
        #expect(abs(ascent - trail.truth.ascentM) <= 3, "ascent \(ascent)")
        #expect(abs(descent - trail.truth.descentM) <= 3, "descent \(descent)")
    }

    @Test func trailGPSOnlyAscentWithinTenPercent() throws {
        let trail = try TrackFixture.load("trail-switchbacks")
        let replay = TrackReplay(trail, .gps(.trail, barometer: false))
        #expect(replay.pipeline.configuration.elevation == .gps)
        let ascent = try #require(replay.pipeline.ascentM)
        #expect(abs(ascent - trail.truth.ascentM) / trail.truth.ascentM <= 0.10, "ascent \(ascent)")
    }

    @Test func modeFollowsTheProfile() {
        #expect(TrackPipeline.Configuration.gps(.run, barometer: true).elevation == .barometric)
        #expect(TrackPipeline.Configuration.gps(.run, barometer: false).elevation == .gps)
        #expect(TrackPipeline.Configuration.indoor(.indoorRun, pedometer: true).elevation == .none)
        var none = ElevationFusion(mode: .none)
        none.add(AltitudeSample(timestamp: Self.t0, relativeAltitude: 12))
        none.add(fix: Self.fix(0, altitude: 400, verticalAccuracy: 3))
        #expect(none.altitudeM == nil && none.ascent == nil && none.descent == nil)
    }

    /// Unknown until an altitude was counted, never a false 0 (splits mustn't send `ascent_m: 0`).
    @Test func ascentIsNilUntilAnAltitudeIsCounted() {
        var e = ElevationFusion(mode: .barometric)
        #expect(e.ascent == nil && e.descent == nil)
        e.setCounting(false)
        e.add(AltitudeSample(timestamp: Self.t0, relativeAltitude: 3))
        #expect(e.ascent == nil, "followed while paused, not counted")
        e.setCounting(true)
        e.add(AltitudeSample(timestamp: Self.t0, relativeAltitude: 3))
        #expect(e.ascent == 0 && e.descent == 0)
        #expect(ElevationFusion(mode: .gps, ascentM: nil, descentM: nil).ascent == nil)
        #expect(ElevationFusion(mode: .gps, ascentM: 12, descentM: 3).ascent == 12)
    }

    @Test func hysteresisIgnoresNoiseAndKeepsTheWholeClimb() {
        var counter = HysteresisCounter(threshold: 2)
        var up = 0.0, down = 0.0
        func feed(_ values: [Double]) {
            for v in values {
                let change = counter.add(v)
                up += change.ascent
                down += change.descent
            }
        }
        // ±0.9 m of noise around a flat line: nothing.
        feed((0 ..< 200).map { sin(Double($0)) * 0.9 })
        #expect(up == 0 && down == 0)
        // Up 50 m, down 30 m: counted in full, nothing lost at the turn.
        feed(stride(from: 0.0, through: 50, by: 0.5).map { $0 })
        feed(stride(from: 50.0, through: 20, by: -0.5).map { $0 })
        #expect(abs(up - 50) < 1 && abs(down - 30) < 1, "up \(up) down \(down)")
    }

    /// Absolute altitude = relative + the median of (GPS − relative) over good fixes; one wild GPS altitude and fixes
    /// worse than 10 m vertical don't move it.
    @Test func barometricOffsetIsAMedianOfGoodFixes() throws {
        var e = ElevationFusion(mode: .barometric)
        for i in 0 ..< 60 {
            let relative = Double(i) * 0.5
            e.add(AltitudeSample(timestamp: Self.t0.addingTimeInterval(Double(i)), relativeAltitude: relative))
            let gps = i == 31 ? 900.0 : 500 + relative + (i.isMultiple(of: 2) ? 1.5 : -1.5)
            e.add(fix: Self.fix(Double(i), altitude: gps, verticalAccuracy: i % 5 == 0 ? 14 : 6))
        }
        let offset = try #require(e.offset), altitude = try #require(e.altitudeM)
        #expect(abs(offset - 500) < 1.6)
        #expect(abs(altitude - 529.5) < 1.6)
    }

    /// The offset window is 5 min: weather drift in the barometer is absorbed by newer GPS fixes.
    @Test func barometricOffsetFollowsDrift() throws {
        var e = ElevationFusion(mode: .barometric)
        for i in 0 ..< 900 {
            // The barometer drifts 10 m over 15 min while the runner stays level at 300 m.
            let relative = Double(i) / 90
            e.add(AltitudeSample(timestamp: Self.t0.addingTimeInterval(Double(i)), relativeAltitude: relative))
            e.add(fix: Self.fix(Double(i), altitude: 300, verticalAccuracy: 5))
        }
        let altitude = try #require(e.altitudeM)
        #expect(abs(altitude - 300) < 2)
    }

    @Test func gpsMedianDropsASpike() throws {
        var e = ElevationFusion(mode: .gps)
        for i in 0 ..< 20 {
            e.add(fix: Self.fix(Double(i), altitude: i == 10 ? 340 : 300, verticalAccuracy: 8))
        }
        #expect(e.ascentM == 0 && e.descentM == 0)
        #expect(e.altitudeM == 300)
        // Fixes worse than 15 m vertical are ignored.
        e.add(fix: Self.fix(21, altitude: 200, verticalAccuracy: 16))
        #expect(e.altitudeM == 300)
    }

    @Test func aClimbWhilePausedAddsNothing() {
        var e = ElevationFusion(mode: .barometric)
        for i in 0 ... 20 { e.add(AltitudeSample(timestamp: Self.t0, relativeAltitude: Double(i))) }
        #expect(e.ascentM == 20)
        e.setCounting(false)
        for i in 21 ... 60 { e.add(AltitudeSample(timestamp: Self.t0, relativeAltitude: Double(i))) }
        e.setCounting(true)
        for i in 61 ... 70 { e.add(AltitudeSample(timestamp: Self.t0, relativeAltitude: Double(i))) }
        #expect(e.ascentM == 29) // 20 before, 9 after (from 61): the 40 m while paused don't count
    }
}
