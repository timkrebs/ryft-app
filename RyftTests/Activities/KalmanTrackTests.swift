import Foundation
import Testing
@testable import Ryft

@Suite("Kalman track")
struct KalmanTrackTests {
    static let t0 = Date(timeIntervalSince1970: 1_781_420_400)
    static let origin = Coordinate(latitude: 52.47, longitude: 13.40)

    /// A fix `metres` along `bearing` from the origin at `seconds`, optionally pushed sideways (east, north).
    static func fix(_ seconds: Double, along metres: Double, bearing: Double = 60, accuracy: Double = 5,
                    offset: Displacement = Displacement(east: 0, north: 0)) -> LocationFix {
        let onTrack = Geodesy.destination(from: origin, bearing: bearing, distance: metres)
        let c = LocalTangentPlane(anchor: onTrack).unproject(offset)
        return LocationFix(timestamp: t0.addingTimeInterval(seconds), latitude: c.latitude, longitude: c.longitude,
                           horizontalAccuracy: accuracy)
    }

    static func filter() -> KalmanTrack { KalmanTrack(tuning: KalmanTrack.Tuning(sigmaA: 1.5)) }

    /// White noise of 1 m reported as 5 m. One velocity sample still carries a few tenths of a m/s of noise, so the
    /// check averages the last minute.
    @Test func convergesOnConstantVelocity() throws {
        var k = Self.filter()
        var rng = SeededGenerator(seed: 7)
        var east = 0.0, north = 0.0
        for i in 0 ... 120 {
            let noise = Displacement(east: rng.gaussian(), north: rng.gaussian())
            _ = k.update(Self.fix(Double(i), along: 3.0 * Double(i), offset: noise))
            if i > 60 {
                east += k.velocity.east / 60
                north += k.velocity.north / 60
            }
        }
        let speed = Displacement(east: east, north: north).length
        let heading = atan2(east, north) * 180 / .pi
        #expect(abs(speed - 3.0) < 0.15, "speed \(speed)")
        #expect(abs(heading - 60) < 3, "heading \(heading)")
        let truth = Geodesy.destination(from: Self.origin, bearing: 60, distance: 360)
        let position = try #require(k.position)
        #expect(Geodesy.distance(position, truth) < 3)
        #expect(k.positionSigma < 5)
    }

    @Test func outlierIsRejectedAndLeavesTheStateAlone() throws {
        var k = Self.filter()
        for i in 0 ... 20 { _ = k.update(Self.fix(Double(i), along: 3.0 * Double(i))) }
        let before = try #require(k.position)
        let velocity = k.velocity
        // 60 m sideways with a falsely good 5 m accuracy: multipath.
        let outcome = k.update(Self.fix(21, along: 63, offset: Displacement(east: -52, north: 30)))
        guard case let .rejected(sigmas) = outcome else {
            Issue.record("expected a rejection, got \(outcome)")
            return
        }
        #expect(sigmas > 3.5)
        #expect(k.position == before)
        #expect(k.velocity == velocity)
        #expect(k.lastTime == Self.t0.addingTimeInterval(20))
        // The next good fix is accepted, predicted over 2 s.
        #expect(k.update(Self.fix(22, along: 66)) == .updated)
        #expect(k.consecutiveRejections == 0)
    }

    @Test func reinitialisesAfterThreeRejectionsInARow() throws {
        var k = Self.filter()
        for i in 0 ... 20 { _ = k.update(Self.fix(Double(i), along: 3.0 * Double(i))) }
        // A real jump: 300 m away, consistent from now on.
        let jump = Displacement(east: 300, north: -50)
        let first = k.update(Self.fix(21, along: 63, offset: jump))
        let second = k.update(Self.fix(22, along: 66, offset: jump))
        let third = Self.fix(23, along: 69, offset: jump)
        #expect(first != .updated && second != .updated)
        #expect(k.update(third) == .reinitialised)
        let position = try #require(k.position)
        #expect(Geodesy.distance(position, third.coordinate) < 0.001)
        #expect(k.speed == 0)
        #expect(k.update(Self.fix(24, along: 72, offset: jump)) == .updated)
    }

    @Test func variableTimeStepsTrackTheSameMotion() {
        var k = Self.filter()
        var t = 0.0
        for dt in [0.5, 1, 1, 3, 0.7, 2, 5, 1, 1, 4, 0.3, 1, 2, 2, 6, 1, 1, 1, 3, 1, 1, 2, 1, 1] {
            t += dt
            #expect(k.update(Self.fix(t, along: 2.5 * t)) != .reinitialised)
        }
        #expect(abs(k.speed - 2.5) < 0.1, "speed \(k.speed)")
    }

    /// Over 15 s the velocity variance resets, so the first fix after the gap sets the velocity to the gap's average
    /// (here: east, after running north) instead of blending it into the old one.
    @Test func aLongGapResetsTheVelocity() {
        var reset = Self.filter()
        var noReset = KalmanTrack(tuning: KalmanTrack.Tuning(sigmaA: 1.5, velocityResetAfter: .infinity))
        for i in 0 ... 30 {
            let fix = Self.fix(Double(i), along: 3.0 * Double(i), bearing: 0)
            _ = reset.update(fix)
            _ = noReset.update(fix)
        }
        // 20 s later the runner is 60 m east of the last fix.
        let corner = Geodesy.destination(from: Self.origin, bearing: 0, distance: 90)
        let c = Geodesy.destination(from: corner, bearing: 90, distance: 60)
        let after = LocationFix(timestamp: Self.t0.addingTimeInterval(50), latitude: c.latitude, longitude: c.longitude,
                                horizontalAccuracy: 5)
        #expect(reset.update(after) == .updated)
        #expect(noReset.update(after) == .updated)
        func miss(_ k: KalmanTrack) -> Double { Displacement(east: k.velocity.east - 3, north: k.velocity.north).length }
        #expect(miss(reset) < 0.5, "velocity off by \(miss(reset)) m/s")
        #expect(miss(noReset) > 1, "without the reset the old velocity lingers")
    }

    @Test func reanchorsBeyondFiveKilometres() throws {
        var k = Self.filter()
        for i in 0 ... 2200 { _ = k.update(Self.fix(Double(i), along: 3.0 * Double(i), accuracy: 3)) }
        let anchor = try #require(k.plane?.anchor)
        #expect(Geodesy.distance(anchor, Self.origin) > 5000)
        let truth = Geodesy.destination(from: Self.origin, bearing: 60, distance: 6600)
        let position = try #require(k.position)
        #expect(Geodesy.distance(position, truth) < 1)
        #expect(abs(k.groundSpeed - 3) < 0.01)
    }

    /// Rejections by the pipeline's speed gate count toward the re-init like innovation rejections (design §3.3).
    @Test func eitherGateCountsTowardTheReinit() throws {
        var k = Self.filter()
        for i in 0 ... 20 { _ = k.update(Self.fix(Double(i), along: 3.0 * Double(i))) }
        let jump = Displacement(east: 300, north: -50)
        #expect(k.rejectedElsewhere(Self.fix(21, along: 63, offset: jump)) != .reinitialised)
        #expect(k.update(Self.fix(22, along: 66, offset: jump)) != .updated)
        let third = Self.fix(23, along: 69, offset: jump)
        #expect(k.rejectedElsewhere(third) == .reinitialised)
        let position = try #require(k.position)
        #expect(Geodesy.distance(position, third.coordinate) < 0.001)
        #expect(k.consecutiveRejections == 0)
    }
}
