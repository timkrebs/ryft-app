import Foundation
import Testing
@testable import Ryft

/// The pipeline on the fixture tracks (design §11.1, §11.2) and its gates, pauses, restore and pedometer mode.
/// Measured on the committed fixtures: road-5k +0.31 %, trail-switchbacks −0.34 % (raw fixes +10.5 %), stationary
/// 0.0 m (auto-pause on or off, flag or not).
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
        // An invalid fix doesn't move the staleness clock, even dated far ahead.
        let invalid = LocationFix(timestamp: fixes[39].timestamp.addingTimeInterval(100), latitude: fixes[39].latitude,
                                  longitude: fixes[39].longitude, horizontalAccuracy: -1)
        #expect(p.ingest(invalid) == [.rejected(.accuracy)])
        #expect(p.ingest(fixes[14]).contains { if case .route = $0 { true } else { false } })
        // More than 10 s behind a newer valid fix (here one the speed gate dropped) is stale.
        let jump = Geodesy.destination(from: fixes[30].coordinate, bearing: 0, distance: 500)
        #expect(p.ingest(LocationFix(timestamp: fixes[30].timestamp, latitude: jump.latitude, longitude: jump.longitude,
                                     horizontalAccuracy: 5)) == [.rejected(.implausible)])
        #expect(p.ingest(fixes[15]) == [.rejected(.stale)])
        #expect(p.ingest(fixes[25]).contains { if case .route = $0 { true } else { false } })
        #expect(p.diagnostics.rejectedOutOfOrder == 2 && p.diagnostics.rejectedStale == 2)
    }

    /// 16 m/s is implausible for a run (max 9 m/s) and fine for a ride (max 25 m/s). Speed-gate rejections count
    /// toward the re-init, so the run restarts at every third fix and never settles: it records nothing.
    @Test func speedGateUsesTheProfile() {
        let fast = SyntheticTrack.fixes([Segment(seconds: 30, speed: 16)], accuracy: 3)
        var run = Self.started(.gps(.run, barometer: false))
        var bike = Self.started(.gps(.bike, barometer: false))
        _ = SyntheticTrack.run(&run, fast)
        _ = SyntheticTrack.run(&bike, fast)
        #expect(run.diagnostics.rejectedImplausible == 20 && run.diagnostics.reinitialisations == 10)
        #expect(run.distanceM == 0)
        #expect(bike.diagnostics.rejected == 0)
        #expect(abs(bike.distanceM - 480) < 2, "\(bike.distanceM) m")
    }

    /// A 60 m multipath offset held for 15 s (design §3.3 step 3): three rejections by either gate re-initialise
    /// at the offset, and three more on the way back. Counting only the innovation gate let the aged-open speed
    /// gate accept the offset with a kick to the velocity: +75 m.
    @Test func sustainedMultipathCostsLittle() {
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        let offset = Displacement(east: -52, north: 30)
        for fix in SyntheticTrack.fixes([Segment(seconds: 300, speed: 3)]) {
            let i = Int(fix.timestamp.timeIntervalSince(SyntheticTrack.t0))
            guard (100 ..< 115).contains(i) else {
                _ = p.ingest(fix)
                continue
            }
            let c = LocalTangentPlane(anchor: fix.coordinate).unproject(offset)
            _ = p.ingest(LocationFix(timestamp: fix.timestamp, latitude: c.latitude, longitude: c.longitude,
                                     horizontalAccuracy: 10))
        }
        #expect(p.diagnostics.reinitialisations == 2)
        #expect(p.distanceM - 900 > -25 && p.distanceM - 900 < 5, "\(p.distanceM - 900) m")
    }

    // MARK: Lifecycle

    @Test func beforeStartFixesWarmTheFilterAndRecordNothing() {
        var p = TrackPipeline(configuration: .gps(.run, barometer: false))
        let fixes = SyntheticTrack.fixes([Segment(seconds: 60, speed: 3)], accuracy: 8)
        let warm = fixes.prefix(20).flatMap { p.ingest($0) }
        #expect(warm.isEmpty)
        #expect(p.state == .ready && p.distanceM == 0 && p.checkpoint == nil)
        #expect(p.gpsQuality(at: fixes[19].timestamp) == .good)
        #expect(p.lastReportedAccuracy == 8)
        p.start(at: fixes[20].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes.dropFirst(20)))
        #expect(abs(p.distanceM - 120) < 1.5, "\(p.distanceM) m")
    }

    /// The first 10 s after Start settle on the shorter of a robust line and the filtered track: a flying start
    /// keeps its speed while the velocity converges, and a standing start isn't lengthened by the line.
    @Test(arguments: [5.0, 25.0])
    func flyingAndStandingStartsLoseNothing(accuracy: Double) {
        let flying = SyntheticTrack.fixes([Segment(seconds: 400, speed: 3)], accuracy: accuracy)
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, flying)
        #expect(abs(p.distanceM - 1200) < 2.5, "flying: \(p.distanceM) m")
        let standing = [Segment(seconds: 1, speed: 1), Segment(seconds: 1, speed: 2), Segment(seconds: 398, speed: 3)]
        var q = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&q, SyntheticTrack.fixes(standing, accuracy: accuracy))
        #expect(abs(q.distanceM - SyntheticTrack.distance(standing)) < 2.5, "standing: \(q.distanceM) m")
    }

    /// The first fix 20 or 40 m off (reported ±25 m), the next ones good: the filter's way back to the truth isn't
    /// distance (review: +20 m and +42 m for a still phone before the settle window).
    @Test(arguments: [(20.0, 0.0), (40.0, 0.0), (20.0, 3.0), (40.0, 3.0)])
    func aCoarseFirstFixAddsNothing(offBy metres: Double, speed: Double) {
        for autoPause in [false, true] {
            var fixes = SyntheticTrack.fixes([Segment(seconds: 120, speed: speed)])
            let off = LocalTangentPlane(anchor: fixes[0].coordinate)
                .unproject(Displacement(east: -metres / 2, north: metres * 0.866))
            fixes[0] = LocationFix(timestamp: fixes[0].timestamp, latitude: off.latitude, longitude: off.longitude,
                                   horizontalAccuracy: 25)
            var p = Self.started(.gps(.run, autoPause: autoPause, barometer: false))
            _ = SyntheticTrack.run(&p, fixes)
            #expect(abs(p.distanceM - speed * 120) < 1.5, "auto-pause \(autoPause): \(p.distanceM) m")
        }
    }

    /// "Start anyway" after 50 s without fixes: nothing is bridged from the last fix before Start.
    @Test func startBridgesNothingFromBefore() {
        var p = TrackPipeline(configuration: .gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, SyntheticTrack.fixes([Segment(seconds: 9, speed: 0)]))
        let start = SyntheticTrack.t0.addingTimeInterval(60)
        p.start(at: start)
        // The runner walked 50 m meanwhile, then runs 300 m from Start.
        let away = Geodesy.destination(from: SyntheticTrack.origin, bearing: 60, distance: 53)
        _ = SyntheticTrack.run(&p, SyntheticTrack.fixes([Segment(seconds: 99, speed: 3)],
                                                      start: start.addingTimeInterval(1), from: away))
        #expect(abs(p.distanceM - 297) < 2, "\(p.distanceM) m")
    }

    @Test func diagnosticsCountFromStart() {
        var p = TrackPipeline(configuration: .gps(.run, barometer: false))
        let fixes = SyntheticTrack.fixes([Segment(seconds: 20, speed: 3)])
        _ = SyntheticTrack.run(&p, Array(fixes[0 ... 9]))
        _ = p.ingest(LocationFix(timestamp: fixes[10].timestamp, latitude: fixes[10].latitude,
                                 longitude: fixes[10].longitude, horizontalAccuracy: 40))
        #expect(p.diagnostics.fixesAccepted == 10 && p.diagnostics.rejectedAccuracy == 1)
        p.start(at: fixes[10].timestamp)
        #expect(p.diagnostics == PipelineDiagnostics())
        _ = SyntheticTrack.run(&p, Array(fixes[11...]))
        #expect(p.diagnostics.fixesAccepted == 10 && p.diagnostics.rejected == 0)
    }

    /// Route points only while recording (design §3.3): not before Start, not paused, not auto-paused.
    @Test func routePointsOnlyWhileRecording() {
        let segments = [Segment(seconds: 60, speed: 3), Segment(seconds: 40, speed: 0), Segment(seconds: 40, speed: 3)]
        let fixes = SyntheticTrack.fixes(segments)
        var p = TrackPipeline(configuration: .gps(.run, barometer: false))
        func routes(_ events: [PipelineEvent]) -> Int { events.filter { if case .route = $0 { true } else { false } }.count }
        func profiles(_ events: [PipelineEvent]) -> Int { events.filter { if case .profile = $0 { true } else { false } }.count }
        #expect(routes(SyntheticTrack.run(&p, Array(fixes[0 ... 4]))) == 0)
        p.start(at: fixes[5].timestamp)
        var routed = 0, profiled = 0
        for fix in fixes[5 ... 130] {
            let events = p.ingest(fix)
            if p.state != .recording { #expect(routes(events) == 0, "state \(p.state)") }
            routed += routes(events)
            profiled += profiles(events)
        }
        #expect(p.pauses.count == 1 && p.pauses[0].kind == .auto)
        #expect(routed < profiled)
        p.pause(at: fixes[130].timestamp)
        let events = SyntheticTrack.run(&p, Array(fixes[131 ... 140]))
        #expect(routes(events) == 0 && profiles(events) == 10)
    }

    /// The design's position sum (`distanceFromVelocity = false`) stays available for D1's comparison.
    @Test func positionStepsStillWork() throws {
        var tuning = TrackPipeline.Tuning.standard
        tuning.distanceFromVelocity = false
        let road = try TrackFixture.load("road-5k")
        let replay = TrackReplay(road, .gps(.run, barometer: false, tuning: tuning))
        #expect(abs(replay.distanceError(road)) < 0.02, "error \(replay.distanceError(road) * 100) %")
        var p = Self.started(.gps(.run, autoPause: false, barometer: false, tuning: tuning))
        _ = SyntheticTrack.run(&p, SyntheticTrack.fixes([Segment(seconds: 400, speed: 3)]))
        #expect(abs(p.distanceM - 1200) < 1.5, "\(p.distanceM) m")
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
        let resume = try #require(p.checkpoint)
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
        let checkpoint = try #require(p.checkpoint)
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

    /// Resumed after a kill, standing still, with a coarse first fix: still nothing (review: +31 m before).
    @Test func aCoarseFixAfterARestoreAddsNothing() throws {
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, SyntheticTrack.fixes([Segment(seconds: 300, speed: 3)]))
        let killedAt = SyntheticTrack.t0.addingTimeInterval(300), back = killedAt.addingTimeInterval(60)
        var restored = TrackPipeline(configuration: .gps(.run, autoPause: false, barometer: false),
                                     restoring: try #require(p.checkpoint), interruptedAt: killedAt)
        restored.resume(at: back)
        let here = Geodesy.destination(from: SyntheticTrack.origin, bearing: 60, distance: 1000)
        var still = SyntheticTrack.fixes([Segment(seconds: 120, speed: 0)], start: back.addingTimeInterval(1), from: here)
        let off = LocalTangentPlane(anchor: here).unproject(Displacement(east: 26, north: 15))
        still[0] = LocationFix(timestamp: still[0].timestamp, latitude: off.latitude, longitude: off.longitude,
                               horizontalAccuracy: 25)
        _ = SyntheticTrack.run(&restored, still)
        #expect(abs(restored.distanceM - p.distanceM) < 0.5, "+\(restored.distanceM - p.distanceM) m")
    }

    /// A fix taken before Resume but delivered after it counts only from Resume on.
    @Test func aLateFixCountsFromResumeOnly() {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 150, speed: 3)])
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, Array(fixes[0 ... 60]))
        p.pause(at: fixes[60].timestamp)
        p.resume(at: fixes[90].timestamp)
        _ = p.ingest(fixes[80])
        _ = SyntheticTrack.run(&p, Array(fixes[91...]))
        #expect(abs(p.distanceM - 360) < 3, "\(p.distanceM) m")
    }

    /// With distance and no moving time (paused since Start), there is no average pace, never an infinite speed.
    @Test func averagesNeedMovingTime() {
        var p = Self.started(.gps(.run, autoPause: false, barometer: false))
        _ = SyntheticTrack.run(&p, SyntheticTrack.fixes([Segment(seconds: 60, speed: 3)]))
        guard var checkpoint = p.checkpoint else { return }
        checkpoint.pauses = []
        let restored = TrackPipeline(configuration: .gps(.run, barometer: false), restoring: checkpoint,
                                     interruptedAt: SyntheticTrack.t0)
        let s = restored.snapshot(at: SyntheticTrack.t0.addingTimeInterval(90))
        #expect(s.distanceM > 100 && s.movingSec == 0)
        #expect(s.averagePace == nil && s.averageSpeed == nil)
    }

    @Test func restoreKeepsAManualPause() throws {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 100, speed: 3)])
        var p = Self.started(.gps(.run, barometer: false))
        _ = SyntheticTrack.run(&p, fixes)
        p.pause(at: fixes[100].timestamp)
        let restored = TrackPipeline(configuration: .gps(.run, barometer: false), restoring: try #require(p.checkpoint),
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
        let restored0 = try #require(p.checkpoint)
        var restored = TrackPipeline(configuration: .indoor(.indoorRun, autoPause: false, pedometer: true),
                                     restoring: restored0, interruptedAt: SyntheticTrack.t0.addingTimeInterval(100))
        restored.resume(at: SyntheticTrack.t0.addingTimeInterval(400))
        _ = restored.ingest(Self.pedometer(402, steps: 1200, metres: 1000))
        #expect(restored.distanceM == 1000)
    }

    // MARK: Cost

    /// Every input touches only time-bounded buffers plus an O(log pauses) search, so a long recording costs the
    /// same per fix as a short one. Structural, not a stopwatch: 90 min of stop-and-go (an auto-pause every 5 min,
    /// barometer and GPS altitude at 1 Hz; every buffer's window is at most 5 min) hold no more samples in the last
    /// half hour than in the first.
    @Test func memoryStaysBoundedOverHours() {
        let block = [Segment(seconds: 280, speed: 3), Segment(seconds: 20, speed: 0)]
        let fixes = SyntheticTrack.fixes(Array(repeating: block, count: 18).flatMap { $0 }).map {
            LocationFix(timestamp: $0.timestamp, latitude: $0.latitude, longitude: $0.longitude, altitude: 40,
                        horizontalAccuracy: 5, verticalAccuracy: 5)
        }
        var p = Self.started(.gps(.run, barometer: true))
        var firstHalfHour = 0, lastHalfHour = 0
        for (i, fix) in fixes.enumerated() {
            p.ingest(AltitudeSample(timestamp: fix.timestamp, relativeAltitude: 0.1 * sin(Double(i))))
            _ = p.ingest(fix)
            if i < 1800 { firstHalfHour = max(firstHalfHour, p.retainedSampleCount) }
            if i >= fixes.count - 1800 { lastHalfHour = max(lastHalfHour, p.retainedSampleCount) }
        }
        #expect(p.diagnostics.autoPauses == 18 && p.pauses.count == 18)
        #expect(lastHalfHour <= firstHalfHour + 2, "first \(firstHalfHour), last \(lastHalfHour)")
        #expect(lastHalfHour < 450)
    }

    // MARK: A still phone (design §3.3 step 4)

    /// The still fixture: 10 min, error level 5 → 30 → 5 m, flagged isStationary after 15 s (as liveUpdates does).
    @Test func stillPhoneWithAutoPauseOffAddsNothing() throws {
        let still = try TrackFixture.load("stationary")
        #expect(still.fixes.map(\.horizontalAccuracy).max() == 30 && still.fixes.map(\.horizontalAccuracy).min() == 5)
        let flagged = TrackReplay(still, .gps(.run, autoPause: false, barometer: false))
        #expect(flagged.pipeline.distanceM < 1, "\(flagged.pipeline.distanceM) m")
    }

    /// Without the flag the dead-band is the backstop: 0.5 m/s for a run. Measured: 0.0 m here; over 5 seeds each,
    /// at most 4.7 m at the fixture's 300 s error correlation, 18 m at 60 s, 70 m at 30 s.
    @Test func stillPhoneWithoutTheFlagStaysUnderTheDeadBand() throws {
        let still = try TrackFixture.load("stationary")
        let unflagged = TrackFixture(name: still.name, start: still.start, truth: still.truth, expected: still.expected,
                                     faults: still.faults, fixes: still.fixes.map {
                                         LocationFix(timestamp: $0.timestamp, latitude: $0.latitude, longitude: $0.longitude,
                                                     altitude: $0.altitude, horizontalAccuracy: $0.horizontalAccuracy,
                                                     verticalAccuracy: $0.verticalAccuracy)
                                     }, altimeter: still.altimeter)
        let replay = TrackReplay(unflagged, .gps(.run, autoPause: false, barometer: false))
        #expect(replay.pipeline.distanceM < 5, "\(replay.pipeline.distanceM) m")
    }

    /// Half the sport's auto-pause threshold, between 0.3 and 0.5 m/s: slow sports keep the floor.
    @Test func deadBandFollowsTheSport() {
        #expect(TrackPipeline(configuration: .gps(.run, barometer: false)).movingSpeed == 0.5)
        #expect(TrackPipeline(configuration: .gps(.bike, barometer: false)).movingSpeed == 0.5)
        #expect(TrackPipeline(configuration: .gps(.trail, barometer: false)).movingSpeed == 0.4)
        #expect(TrackPipeline(configuration: .gps(.walk, barometer: false)).movingSpeed == 0.3)
        #expect(TrackPipeline(configuration: .gps(.hike, barometer: false)).movingSpeed == 0.3)
    }
}
