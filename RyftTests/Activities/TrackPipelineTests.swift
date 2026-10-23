import Foundation
import Testing
@testable import Ryft

/// The pipeline on the fixture tracks (design §11.1, §11.2) and its gates, pauses, restore and pedometer mode.
/// Measured on the committed fixtures: road-5k +0.31 %, trail-switchbacks −0.28 % (raw fixes +10.5 %), stationary
/// 1.7 m.
@Suite("Track pipeline")
struct TrackPipelineTests {
    typealias Segment = SyntheticTrack.Segment

    static func started(_ configuration: TrackPipeline.Configuration, at time: Date = SyntheticTrack.t0) -> TrackPipeline {
        var pipeline = TrackPipeline(configuration: configuration)
        pipeline.start(at: time)
        return pipeline
    }

    // MARK: Fixture tracks

    @Test func road5kDistanceWithinTwoPercent() throws {
        let road = try TrackFixture.load("road-5k")
        let replay = TrackReplay(road, .gps(.run, barometer: false))
        #expect(abs(replay.distanceError(road)) < 0.02, "error \(replay.distanceError(road) * 100) %")
    }

    @Test func trailDistanceWithinTwoPercent() throws {
        let trail = try TrackFixture.load("trail-switchbacks")
        let replay = TrackReplay(trail, .gps(.trail, barometer: true))
        #expect(abs(replay.distanceError(trail)) < 0.02, "error \(replay.distanceError(trail) * 100) %")
    }

    /// The trail is hard on purpose: summing the fixes the accuracy gate keeps reads more than 5 % long.
    @Test func trailFixtureHasTeeth() throws {
        let trail = try TrackFixture.load("trail-switchbacks")
        #expect(trail.rawDistance > trail.truth.distanceM * 1.05)
    }

    @Test func stationaryPhoneStaysUnder20Metres() throws {
        let still = try TrackFixture.load("stationary")
        let replay = TrackReplay(still, .gps(.run, barometer: false))
        #expect(replay.pipeline.distanceM < 20, "\(replay.pipeline.distanceM) m")
        #expect(replay.splits.isEmpty)
        #expect(replay.pipeline.splits.isEmpty)
    }

    @Test func gateCountsOnTheTrail() throws {
        let trail = try TrackFixture.load("trail-switchbacks")
        let replay = TrackReplay(trail, .gps(.trail, barometer: true))
        let d = replay.pipeline.diagnostics
        #expect(trail.expected.fixes == trail.fixes.count)
        #expect(d.rejectedAccuracy == trail.expected.accuracyRejections)
        for i in trail.faults.outliers { #expect(replay.rejection(at: i) == .accuracy, "outlier \(i)") }
        for i in trail.faults.multipath {
            let reason = replay.rejection(at: i)
            #expect(reason == .implausible || reason == .innovation, "multipath \(i): \(String(describing: reason))")
        }
        // Only the multipath fixes fail the speed or innovation gate: no clean fix is lost.
        #expect(d.rejectedImplausible + d.rejectedInnovation == trail.faults.multipath.count)
        #expect(d.rejectedOutOfOrder == 0 && d.rejectedStale == 0 && d.reinitialisations == 0)
        #expect(d.fixesAccepted + d.rejected == trail.fixes.count)
    }

    @Test func gateCountsOnTheRoad() throws {
        let road = try TrackFixture.load("road-5k")
        let replay = TrackReplay(road, .gps(.run, barometer: false))
        let d = replay.pipeline.diagnostics
        #expect(road.faults.outliers.count == 2)
        #expect(d.rejectedAccuracy == road.expected.accuracyRejections)
        for i in road.faults.outliers { #expect(replay.rejection(at: i) == .accuracy) }
        #expect(d.rejectedImplausible + d.rejectedInnovation + d.rejectedStale + d.rejectedOutOfOrder == 0)
    }

    /// The 25 s tunnel is bridged by the straight line, which is the road there: 26 s at 3 m/s.
    @Test func tunnelGapIsBridged() throws {
        let road = try TrackFixture.load("road-5k")
        let replay = TrackReplay(road, .gps(.run, barometer: false))
        let gaps = replay.gaps
        #expect(gaps.count == 1)
        #expect(gaps.first?.bridged == true)
        #expect((gaps.first?.seconds ?? 0) >= 25)
        let tunnel = try #require(road.faults.gaps.first)
        let entry = Date(timeIntervalSince1970: tunnel[0] - 1), exit = Date(timeIntervalSince1970: tunnel[0] + tunnel[1])
        let across = replay.distance(at: exit) - replay.distance(at: entry)
        #expect(abs(across - 3.0 * (tunnel[1] + 1)) < 5, "\(across) m across the tunnel")
        #expect(replay.pipeline.diagnostics.gapsBridged == 1 && replay.pipeline.diagnostics.gapsNotBridged == 0)
    }

    @Test func trailGapIsBridged() throws {
        let trail = try TrackFixture.load("trail-switchbacks")
        let replay = TrackReplay(trail, .gps(.trail, barometer: true))
        #expect(replay.gaps.contains { $0.seconds >= 45 && $0.bridged })
        #expect(replay.pipeline.diagnostics.longestGapSec >= 45)
    }

    // MARK: Gates

    @Test func accuracyGate() {
        var p = Self.started(.gps(.run, barometer: false))
        let base = SyntheticTrack.fixes([Segment(seconds: 5, speed: 3)])
        func with(_ fix: LocationFix, accuracy: Double) -> LocationFix {
            LocationFix(timestamp: fix.timestamp, latitude: fix.latitude, longitude: fix.longitude,
                        horizontalAccuracy: accuracy)
        }
        #expect(p.ingest(with(base[0], accuracy: -1)) == [.rejected(.accuracy)])
        #expect(p.ingest(with(base[1], accuracy: 25.1)) == [.rejected(.accuracy)])
        #expect(p.ingest(with(base[2], accuracy: .nan)) == [.rejected(.accuracy)])
        #expect(!p.ingest(with(base[3], accuracy: 25)).contains(.rejected(.accuracy)))
        #expect(p.diagnostics.rejectedAccuracy == 3 && p.diagnostics.fixesAccepted == 1)
        #expect(p.lastReportedAccuracy == 25)
    }

    @Test func outOfOrderAndStaleFixesAreDropped() {
        var p = Self.started(.gps(.run, barometer: false))
        let fixes = SyntheticTrack.fixes([Segment(seconds: 40, speed: 3)])
        _ = p.ingest(fixes[10])
        #expect(p.ingest(fixes[10]) == [.rejected(.outOfOrder)])
        #expect(p.ingest(fixes[9]) == [.rejected(.outOfOrder)])
        // Received 12 s after it was taken: Core Location handed over a cached fix.
        #expect(p.ingest(fixes[11], receivedAt: fixes[11].timestamp.addingTimeInterval(12)) == [.rejected(.stale)])
        // More than 10 s behind a newer fix the gate dropped.
        let late = LocationFix(timestamp: fixes[30].timestamp, latitude: fixes[30].latitude,
                               longitude: fixes[30].longitude, horizontalAccuracy: 40)
        #expect(p.ingest(late) == [.rejected(.accuracy)])
        #expect(p.ingest(fixes[15]) == [.rejected(.stale)])
        #expect(p.ingest(fixes[25]).contains { if case .route = $0 { true } else { false } })
        #expect(p.diagnostics.rejectedOutOfOrder == 2 && p.diagnostics.rejectedStale == 2)
    }

    /// 16 m/s is implausible for a run (max 9 m/s) and fine for a ride (max 25 m/s).
    @Test func speedGateUsesTheProfile() {
        let fast = SyntheticTrack.fixes([Segment(seconds: 30, speed: 16)], accuracy: 3)
        var run = Self.started(.gps(.run, barometer: false))
        var bike = Self.started(.gps(.bike, barometer: false))
        _ = SyntheticTrack.run(&run, fast)
        _ = SyntheticTrack.run(&bike, fast)
        #expect(run.diagnostics.rejectedImplausible == 30 && run.diagnostics.fixesAccepted == 1)
        #expect(bike.diagnostics.rejected == 0)
        #expect(abs(bike.distanceM - 480) < 2)
    }

    // MARK: Lifecycle

    @Test func beforeStartFixesWarmTheFilterAndRecordNothing() {
        var p = TrackPipeline(configuration: .gps(.run, barometer: false))
        let fixes = SyntheticTrack.fixes([Segment(seconds: 60, speed: 3)], accuracy: 8)
        let warm = fixes.prefix(20).flatMap { p.ingest($0) }
        #expect(warm.isEmpty)
        #expect(p.state == .ready && p.distanceM == 0 && p.resume == nil)
        #expect(p.gpsQuality(at: fixes[19].timestamp) == .good)
        #expect(p.lastReportedAccuracy == 8)
        p.start(at: fixes[20].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes.dropFirst(20)))
        #expect(abs(p.distanceM - 120) < 1.5, "\(p.distanceM) m")
    }

    /// A noiseless run at full speed from the first fix: the position steps after the filter starts recover the
    /// converging velocity's lag, which integrating the velocity alone would lose.
    @Test func flyingStartLosesNothing() {
        let segments = [Segment(seconds: 400, speed: 3)]
        for accuracy in [5.0, 25.0] {
            let fixes = SyntheticTrack.fixes(segments, accuracy: accuracy)
            var p = Self.started(.gps(.run, autoPause: false, barometer: false))
            _ = SyntheticTrack.run(&p, fixes)
            #expect(abs(p.distanceM - 1200) < 2.5, "accuracy \(accuracy): \(p.distanceM) m")

            var tuning = TrackPipeline.Tuning.standard
            tuning.positionStepsAfterRestart = 0
            var velocityOnly = Self.started(.gps(.run, autoPause: false, barometer: false, tuning: tuning))
            _ = SyntheticTrack.run(&velocityOnly, fixes)
            #expect(velocityOnly.distanceM < p.distanceM - 2, "accuracy \(accuracy)")
        }
    }

    @Test func manualPauseExcludesDistanceAndTime() {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 150, speed: 3)])
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, Array(fixes[0 ... 60]))
        p.pause(at: fixes[60].timestamp)
        // Still moving while paused: walking to a café.
        _ = SyntheticTrack.run(&p, Array(fixes[61 ... 90]))
        p.resume(at: fixes[90].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes[91...]))
        #expect(abs(p.distanceM - 360) < 4, "\(p.distanceM) m")
        #expect(p.movingTime(at: fixes[150].timestamp) == 120)
        #expect(p.pauses == [PauseInterval(kind: .manual, start: fixes[60].timestamp, end: fixes[90].timestamp)])
    }

    /// No fixes during the pause (the source stopped): the 90 m walked meanwhile are never bridged.
    @Test func nothingIsBridgedAcrossAPause() {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 150, speed: 3)])
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, Array(fixes[0 ... 60]))
        p.pause(at: fixes[60].timestamp)
        p.resume(at: fixes[90].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes[91...]))
        #expect(abs(p.distanceM - 357) < 4, "\(p.distanceM) m")
    }

    /// Core Location's stationary flag stops distance even with auto-pause off.
    @Test func stationaryFlagAddsNoDistance() {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 60, speed: 0.6, stationary: true)])
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, fixes)
        #expect(p.distanceM == 0)
    }

    @Test func gpsQuality() {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 10, speed: 3)])
        var p = Self.started(.gps(.run, barometer: false))
        #expect(p.gpsQuality(at: fixes[0].timestamp) == .weak)
        _ = p.ingest(LocationFix(timestamp: fixes[1].timestamp, latitude: fixes[1].latitude,
                                 longitude: fixes[1].longitude, horizontalAccuracy: 8))
        #expect(p.gpsQuality(at: fixes[1].timestamp) == .good)
        _ = p.ingest(LocationFix(timestamp: fixes[2].timestamp, latitude: fixes[2].latitude,
                                 longitude: fixes[2].longitude, horizontalAccuracy: 20))
        #expect(p.gpsQuality(at: fixes[2].timestamp) == .fair)
        #expect(p.gpsQuality(at: fixes[2].timestamp.addingTimeInterval(10.5)) == .weak)
        _ = p.ingest(LocationFix(timestamp: fixes[3].timestamp, latitude: fixes[3].latitude,
                                 longitude: fixes[3].longitude, horizontalAccuracy: 8, isStationary: true))
        // Core Location stops sending fixes while the phone is still: that isn't a weak signal.
        #expect(p.gpsQuality(at: fixes[3].timestamp.addingTimeInterval(60)) == .good)
        #expect(TrackPipeline(configuration: .indoor(.indoorRun, pedometer: true)).gpsQuality(at: .now) == .off)
    }

    @Test func snapshotValues() {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 120, speed: 3)])
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, fixes)
        let now = fixes[120].timestamp
        let s = p.snapshot(at: now)
        #expect(s.state == .recording && s.movingSec == 120 && s.elapsedSec == 120)
        #expect(s.movingAnchor == SyntheticTrack.t0)
        #expect(abs((s.currentPace ?? 0) - 333.3) < 3)
        #expect(abs((s.averagePace ?? 0) - 333.3) < 4)
        #expect(abs((s.currentSpeed ?? 0) - 3) < 0.03)
        #expect(s.gps == .good && s.lastSplit == nil && s.steps == nil)
        p.pause(at: now)
        let paused = p.snapshot(at: now.addingTimeInterval(30))
        #expect(paused.movingAnchor == nil && paused.currentPace == nil && paused.movingSec == 120)
        #expect(paused.elapsedSec == 150)
    }

    @Test func laps() throws {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 300, speed: 3)])
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, Array(fixes[0 ... 100]))
        let firstLap = p.lap(at: fixes[100].timestamp)
        let first = try #require(firstLap)
        _ = SyntheticTrack.run(&p, Array(fixes[101 ... 250]))
        let secondLap = p.lap(at: fixes[250].timestamp)
        let second = try #require(secondLap)
        #expect(first.index == 1 && first.movingSec == 100 && abs(first.distanceM - 300) < 2)
        #expect(second.index == 2 && second.start == fixes[100].timestamp && second.movingSec == 150)
        #expect(abs(second.distanceM - 450) < 2)
    }

    // MARK: Restore (design §3.9)

    /// The checkpoint state holds no coordinate: no Kalman anchor, no last position.
    @Test func resumeStateHoldsNoCoordinate() throws {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 400, speed: 3)])
        var p = Self.started(.gps(.run, barometer: false))
        _ = SyntheticTrack.run(&p, fixes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let resume = try #require(p.resume)
        let json = try #require(String(bytes: encoder.encode(resume), encoding: .utf8))
        for key in ["latitude", "longitude", "coordinate", "anchor", "position", "lat", "lon"] {
            #expect(!json.lowercased().contains("\"\(key)\""), "key \(key)")
        }
        #expect(!json.contains(String(format: "%.4f", fixes[400].latitude)))
    }

    /// A kill is never bridged: the time since the last checkpoint is a pause, and distance continues from the
    /// first new fix, wherever the runner is now.
    @Test func restoreNeverBridgesTheKill() throws {
        let before = SyntheticTrack.fixes([Segment(seconds: 400, speed: 3)])
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, before)
        let checkpoint = try #require(p.resume)
        let data = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(TrackPipeline.Resume.self, from: data)
        #expect(decoded == checkpoint)

        let lastCheckpoint = before[400].timestamp
        var restored = TrackPipeline(configuration: .gps(.run, autoPause: false, barometer: false), restoring: decoded,
                                     interruptedAt: lastCheckpoint)
        #expect(restored.state == .paused)
        #expect(restored.pauses.last == PauseInterval(kind: .interruption, start: lastCheckpoint))
        #expect(restored.distanceM == p.distanceM && restored.splits == p.splits)

        // Relaunched 5 min later, 900 m further on.
        let resumeAt = lastCheckpoint.addingTimeInterval(300)
        restored.resume(at: resumeAt)
        let after = SyntheticTrack.fixes([Segment(seconds: 300, speed: 3)], start: resumeAt,
                                         from: Geodesy.destination(from: SyntheticTrack.origin, bearing: 60, distance: 2100))
        _ = SyntheticTrack.run(&restored, after)
        #expect(abs(restored.distanceM - (p.distanceM + 900)) < 3, "\(restored.distanceM) m")
        #expect(restored.movingTime(at: after[300].timestamp) == 700)
        #expect(restored.splits.map(\.index) == [1, 2])
    }

    @Test func restoreKeepsAManualPause() throws {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 100, speed: 3)])
        var p = Self.started(.gps(.run, barometer: false))
        _ = SyntheticTrack.run(&p, fixes)
        p.pause(at: fixes[100].timestamp)
        let restored = TrackPipeline(configuration: .gps(.run, barometer: false), restoring: try #require(p.resume),
                                     interruptedAt: fixes[100].timestamp.addingTimeInterval(20))
        #expect(restored.state == .paused)
        #expect(restored.pauses.count == 1 && restored.pauses[0].kind == .manual && restored.pauses[0].end == nil)
    }

    // MARK: Pedometer (design §3.5)

    static func pedometer(_ seconds: Double, steps: Int, metres: Double, cadence: Double? = 2.8) -> PedometerSample {
        PedometerSample(timestamp: SyntheticTrack.t0.addingTimeInterval(seconds), steps: steps, distanceM: metres,
                        cadence: cadence)
    }

    @Test func pedometerDistanceAutoPauseAndManualPause() {
        var p = Self.started(.indoor(.indoorRun, pedometer: true))
        var events: [PipelineEvent] = []
        // 60 s at 2.5 m/s, a sample every 2 s.
        for i in 1 ... 30 { events += p.ingest(Self.pedometer(Double(2 * i), steps: 6 * i, metres: 5.0 * Double(i))) }
        #expect(p.distanceM == 150)
        #expect(events.contains { if case .split = $0 { true } else { false } } == false)
        // On the treadmill's rails for 12 s: no samples (Core Motion only reports steps).
        events = p.advance(to: SyntheticTrack.t0.addingTimeInterval(72))
        #expect(events == [.autoPaused(since: SyntheticTrack.t0.addingTimeInterval(60))])
        #expect(p.state == .autoPaused)
        // Back to running: auto-resume after 3 s of steps, counting them.
        for i in 0 ... 2 {
            events = p.ingest(Self.pedometer(Double(80 + 2 * i), steps: 186 + 6 * i, metres: 155.0 + 5 * Double(i)))
        }
        #expect(p.state == .recording)
        #expect(p.pauses.last == PauseInterval(kind: .auto, start: SyntheticTrack.t0.addingTimeInterval(60),
                                               end: SyntheticTrack.t0.addingTimeInterval(80)))
        #expect(p.distanceM == 165)
        p.pause(at: SyntheticTrack.t0.addingTimeInterval(85))
        _ = p.ingest(Self.pedometer(95, steps: 250, metres: 200))
        p.resume(at: SyntheticTrack.t0.addingTimeInterval(96))
        _ = p.ingest(Self.pedometer(100, steps: 262, metres: 210))
        #expect(p.distanceM == 175, "the 35 m while paused are left out")
        #expect(p.steps == 262)
    }

    /// After a kill the new pedometer session counts from the start again: the steps during the kill count.
    @Test func pedometerRestoreIsLossless() throws {
        var p = Self.started(.indoor(.indoorRun, autoPause: false, pedometer: true))
        _ = p.ingest(Self.pedometer(100, steps: 300, metres: 250))
        let restored0 = try #require(p.resume)
        var restored = TrackPipeline(configuration: .indoor(.indoorRun, autoPause: false, pedometer: true),
                                     restoring: restored0, interruptedAt: SyntheticTrack.t0.addingTimeInterval(100))
        restored.resume(at: SyntheticTrack.t0.addingTimeInterval(400))
        _ = restored.ingest(Self.pedometer(402, steps: 1200, metres: 1000))
        #expect(restored.distanceM == 1000)
    }

    // MARK: Cost

    /// Every step is O(1) amortised (O(log pauses) for moving time). Bounded against the algorithmic failure, not
    /// against this Mac: 8× the fixes must cost well under 24× the time (quadratic would be 64×).
    @Test func costIsLinearInRecordingLength() {
        func stopAndGo(_ n: Int) -> [LocationFix] {
            // 280 s at 3 m/s, then a 20 s stop: an auto-pause every 5 min.
            let block = [Segment(seconds: 280, speed: 3), Segment(seconds: 20, speed: 0)]
            return SyntheticTrack.fixes(Array(repeating: block, count: n / 300 + 1).flatMap { $0 }).prefix(n).map { $0 }
        }
        func cost(_ fixes: [LocationFix]) -> Duration {
            ContinuousClock().measure {
                var p = Self.started(.gps(.run, barometer: false))
                for fix in fixes { _ = p.ingest(fix) }
                #expect(p.diagnostics.autoPauses > 0)
            }
        }
        // Runs of tens of milliseconds, best of several, so a busy runner's hiccup doesn't decide the ratio.
        let small = stopAndGo(4000), large = stopAndGo(32000)
        let smallCost = (0 ..< 3).map { _ in cost(small) }.min() ?? .zero
        let largeCost = (0 ..< 2).map { _ in cost(large) }.min() ?? .zero
        #expect(largeCost / smallCost < 24, "8× the fixes cost \(largeCost / smallCost)×")
    }
}
