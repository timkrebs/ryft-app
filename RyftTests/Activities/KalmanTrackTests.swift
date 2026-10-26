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

    /// A real jump: 300 m away, consistent from now on. The filter restarts at the third fix with the rejected run's
    /// velocity (its three fixes lie on a line): 3 m/s at 60°, not at rest (ADR 0003 amendment 2, decision 3).
    @Test func reinitialisesAfterThreeRejectionsInARow() throws {
        var k = Self.filter()
        for i in 0 ... 20 { _ = k.update(Self.fix(Double(i), along: 3.0 * Double(i))) }
        let jump = Displacement(east: 300, north: -50)
        let first = k.update(Self.fix(21, along: 63, offset: jump))
        let second = k.update(Self.fix(22, along: 66, offset: jump))
        let third = Self.fix(23, along: 69, offset: jump)
        #expect(first != .updated && second != .updated)
        #expect(k.update(third) == .reinitialised)
        let position = try #require(k.position)
        #expect(Geodesy.distance(position, third.coordinate) < 0.001)
        let heading = atan2(k.velocity.east, k.velocity.north) * 180 / .pi
        #expect(abs(k.speed - 3) < 0.01 && abs(heading - 60) < 0.5, "\(k.speed) m/s at \(heading)°")
        #expect(k.update(Self.fix(24, along: 72, offset: jump)) == .updated)
    }

    /// The middle fix must lie on the line from the first to the third within its accuracy plus the larger end's
    /// (here 5 + 5 m): 9.5 m off keeps the line's velocity, 10.5 m off restarts at rest.
    @Test(arguments: [(9.5, true), (10.5, false)])
    func theReinitVelocityNeedsTheMiddleFixOnTheLine(off metres: Double, keepsVelocity: Bool) {
        var k = Self.filter()
        for i in 0 ... 20 { _ = k.update(Self.fix(Double(i), along: 3.0 * Double(i))) }
        let jump = Displacement(east: 300, north: -50)
        // Across the track (60°): east −sin 30°, north cos 30°.
        let middle = Displacement(east: jump.east - 0.5 * metres, north: jump.north + 0.866_025 * metres)
        _ = k.update(Self.fix(21, along: 63, offset: jump))
        _ = k.update(Self.fix(22, along: 66, offset: middle))
        #expect(k.update(Self.fix(23, along: 69, offset: jump)) == .reinitialised)
        if keepsVelocity {
            #expect(abs(k.speed - 3) < 0.01, "\(k.speed) m/s")
        } else {
            #expect(k.speed == 0)
        }
    }

    /// `predictedPosition(at:)` is the position moved on at the velocity; nil before the first fix.
    @Test func predictedPositionIsPositionPlusVelocityTimesDeltaT() throws {
        var k = Self.filter()
        #expect(k.predictedPosition(at: Self.t0) == nil)
        for i in 0 ... 60 { _ = k.update(Self.fix(Double(i), along: 3.0 * Double(i))) }
        let position = try #require(k.position)
        let now = try #require(k.predictedPosition(at: Self.t0.addingTimeInterval(60)))
        #expect(Geodesy.distance(now, position) < 1e-6)
        let later = try #require(k.predictedPosition(at: Self.t0.addingTimeInterval(65)))
        let heading = atan2(k.velocity.east, k.velocity.north) * 180 / .pi
        let expected = Geodesy.destination(from: position, bearing: heading, distance: k.speed * 5)
        #expect(Geodesy.distance(later, expected) < 0.01)
        #expect(abs(Geodesy.distance(later, position) - 15) < 0.1)
        // Never backwards in time: a fix older than the state predicts the position itself.
        let earlier = try #require(k.predictedPosition(at: Self.t0.addingTimeInterval(50)))
        #expect(Geodesy.distance(earlier, position) < 1e-6)
    }

    /// Association (ADR 0003 amendment 2, decision 2). Fixes reported at 20 m open the gate wide enough to take a ghost
    /// 55 m off; after a rejection, one nearer the last rejected fix than the prediction joins the rejected run, and
    /// one nearer the prediction is accepted.
    @Test func aFixNearerTheRejectedRunJoinsIt() {
        func rejectedOnce() -> KalmanTrack {
            var k = Self.filter()
            for i in 0 ... 20 { _ = k.update(Self.fix(Double(i), along: 3.0 * Double(i))) }
            let ghost = Displacement(east: -52, north: 30)
            #expect(k.update(Self.fix(21, along: 63, offset: ghost)) != .updated)
            return k
        }
        let nearTheGhost = Self.fix(22, along: 66, accuracy: 20, offset: Displacement(east: -47.6, north: 27.5))
        var fresh = Self.filter()
        for i in 0 ... 20 { _ = fresh.update(Self.fix(Double(i), along: 3.0 * Double(i))) }
        #expect(fresh.update(nearTheGhost) == .updated, "without a rejection before, the wide gate takes it")
        var joined = rejectedOnce()
        #expect(joined.update(nearTheGhost) != .updated)
        #expect(joined.consecutiveRejections == 2)
        var accepted = rejectedOnce()
        #expect(accepted.update(Self.fix(22, along: 66, accuracy: 20, offset: Displacement(east: -8.7, north: 5))) == .updated)
        #expect(accepted.consecutiveRejections == 0)
    }

    /// Association compares with the run's latest rejected fix: in GPS trouble the offsets hop, and a fix near the newest
    /// hop belongs to the run even when it is far from the first.
    @Test func associationUsesTheLatestRejectedFix() {
        var k = Self.filter()
        for i in 0 ... 20 { _ = k.update(Self.fix(Double(i), along: 3.0 * Double(i))) }
        #expect(k.update(Self.fix(21, along: 63, offset: Displacement(east: 52, north: -30))) != .updated)
        #expect(k.update(Self.fix(22, along: 66, offset: Displacement(east: -52, north: 30))) != .updated)
        // 50 m toward the second hop, reported at 20 m: inside the aged gate, nearer that hop than the prediction.
        let third = Self.fix(23, along: 69, accuracy: 20, offset: Displacement(east: -43.3, north: 25))
        #expect(k.update(third) == .reinitialised)
    }

    /// A filter holding only its very first fix can't tell which side is the ghost (a coarse first fix is the
    /// outlier), so association waits for the first update: after the pipeline's speed gate rejected a true fix,
    /// the next true one is accepted, as before A3a.2.
    @Test func aFirstFixAloneDoesNotAssociate() {
        let coarse = Self.fix(0, along: 0, accuracy: 25, offset: Displacement(east: -20, north: 34.6))
        var k = Self.filter()
        #expect(k.update(coarse) == .initialised)
        #expect(k.rejectedElsewhere(Self.fix(1, along: 3)) != .reinitialised)
        #expect(k.update(Self.fix(2, along: 6)) == .updated)
        // With history, the same geometry joins the rejected run.
        var settled = Self.filter()
        _ = settled.update(coarse)
        _ = settled.update(Self.fix(0.5, along: 0, accuracy: 25, offset: Displacement(east: -20, north: 34.6)))
        #expect(settled.rejectedElsewhere(Self.fix(1, along: 3)) != .reinitialised)
        #expect(settled.update(Self.fix(2, along: 6)) != .updated)
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
