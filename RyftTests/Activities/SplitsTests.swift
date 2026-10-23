import Foundation
import Testing
@testable import Ryft

/// Splits (design §3.3 step 7) and rolling pace (step 6).
///
/// The split logic itself is checked on noiseless tracks, to a tenth of a second. On the fixtures a crossing can't be
/// more exact than the GPS error along the track allows: open-sky error of σ ≈ 3 m is ±1 s at 3 m/s (1σ). Over 20
/// seeds of road-5k the worst of km 1–4 lies between 1.0 and 4.6 s, so the fixture bound is 5 s. The committed
/// fixture measures −2.2 to −2.8 s.
@Suite("Splits and pace")
struct SplitsTests {
    typealias Segment = SyntheticTrack.Segment

    @Test func noiselessSplitsAreExact() {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 1170, speed: 3)])
        var p = TrackPipeline(configuration: .gps(.run, autoPause: false, barometer: false))
        p.start(at: SyntheticTrack.t0)
        let events = SyntheticTrack.run(&p, fixes) + p.finish(at: fixes[1170].timestamp)
        let splits = events.compactMap { if case let .split(s) = $0 { s } else { nil } }
        #expect(splits == p.splits)
        #expect(splits.map(\.index) == [1, 2, 3, 4])
        for split in splits.prefix(3) {
            let expected = SyntheticTrack.t0.addingTimeInterval(1000 / 3 * Double(split.index))
            #expect(abs(split.end.timeIntervalSince(expected)) < 0.1, "split \(split.index)")
            #expect(abs(split.durationSec - 1000 / 3) < 0.1)
            #expect(split.distanceM == 1000)
            #expect(split.ascentM == nil) // GPS elevation, but no altitude in these fixes: unknown, not 0
        }
        // Finish adds the partial last split with its real distance.
        let last = splits[3]
        #expect(abs(last.distanceM - 510) < 0.5 && abs(last.durationSec - 170) < 0.2)
        #expect(last.end == fixes[1170].timestamp)
        #expect(abs(splits.map(\.durationSec).reduce(0, +) - 1170) < 1e-6)
    }

    /// A remainder under 5 % of a split at Finish is GPS overshoot at a round-number finish, not a split.
    @Test(arguments: [(343, 1), (353, 2)])
    func partialSplitNeedsFivePercent(seconds: Int, count: Int) {
        let fixes = SyntheticTrack.fixes([Segment(seconds: seconds, speed: 3)])
        var p = TrackPipeline(configuration: .gps(.run, autoPause: false, barometer: false))
        p.start(at: SyntheticTrack.t0)
        _ = SyntheticTrack.run(&p, fixes)
        _ = p.finish(at: fixes[seconds].timestamp)
        #expect(p.splits.count == count)
    }

    @Test func road5kSplits() throws {
        let road = try TrackFixture.load("road-5k")
        let replay = TrackReplay(road, .gps(.run, barometer: false))
        let splits = replay.splits
        #expect(splits.count == 5)
        #expect(splits.allSatisfy { $0.distanceM == 1000 })
        for (split, truth) in zip(splits.prefix(4), road.splitTimes) {
            let error = split.end.timeIntervalSince(truth)
            #expect(abs(error) < 5, "km \(split.index): \(error) s")
            // The crossing is where the recorded distance passes the kilometre: its error is the distance error.
            let distanceError = replay.distance(at: truth) - Double(split.index) * 1000
            #expect(abs(error + distanceError / 3) < 1.5, "km \(split.index)")
        }
    }

    /// Split durations are moving time: the traffic light's 20 s and the auto-pause around them are left out.
    @Test func splitDurationsAreMovingTime() throws {
        let road = try TrackFixture.load("road-5k")
        let replay = TrackReplay(road, .gps(.run, barometer: false))
        let splits = replay.splits
        let total = splits.map(\.durationSec).reduce(0, +)
        #expect(abs(total - replay.pipeline.movingTime(at: splits[4].end)) < 1e-6)
        let light = try #require(road.stops.first)
        let third = try #require(splits.first { $0.end > light.end })
        let truth = road.splitTimes[2].timeIntervalSince(road.splitTimes[1]) - light.duration
        #expect(abs(third.durationSec - truth) < 4, "\(third.durationSec) s vs \(truth) s")
    }

    @Test func splitAscentFollowsTheClimb() throws {
        let trail = try TrackFixture.load("trail-switchbacks")
        let replay = TrackReplay(trail, .gps(.trail, barometer: true))
        let ascents = replay.splits.map { $0.ascentM ?? -1 }
        // 400 m up over the first 4 km (100 m per km), then down.
        #expect(abs(ascents.prefix(4).reduce(0, +) - 400) < 10, "\(ascents)")
        #expect(ascents.dropFirst(5).allSatisfy { $0 < 3 }, "\(ascents)")
    }

    // MARK: Rolling pace

    @Test func noiselessPaceIsExact() {
        let segments = [Segment(seconds: 60, speed: 3), Segment(seconds: 90, speed: 4)]
        let fixes = SyntheticTrack.fixes(segments, accuracy: 3)
        var p = TrackPipeline(configuration: .gps(.run, autoPause: false, barometer: false))
        p.start(at: SyntheticTrack.t0)
        var paces: [Double?] = []
        for fix in fixes {
            _ = p.ingest(fix)
            paces.append(p.currentPace)
        }
        // Not before 10 s of data.
        #expect(paces[0 ..< 9].allSatisfy { $0 == nil })
        // 30 s after each change of speed, the window holds one speed only.
        for i in 40 ... 60 { #expect(abs((paces[i] ?? 0) - 1000 / 3) / (1000 / 3) < 0.005, "t \(i)") }
        for i in 110 ... 150 { #expect(abs((paces[i] ?? 0) - 250) / 250 < 0.005, "t \(i)") }
    }

    /// On the road's constant 3 m/s stretch: the mean within 1 %, 95 % of samples within 3 %. Single samples reach
    /// 3.6 % on the committed fixture: open-sky multipath alone moves a 90 m window by about 1 m (1σ).
    @Test func roadPaceOnAConstantStretch() throws {
        let road = try TrackFixture.load("road-5k")
        let replay = TrackReplay(road, .gps(.run, barometer: false))
        let stretch = try #require(road.constantSpeed.first)
        let truth = 1000 / stretch.speed
        // From 35 s in, the 30 s window lies inside the stretch.
        let errors = replay.trace
            .filter { $0.time >= stretch.window.start.addingTimeInterval(35) && $0.time <= stretch.window.end }
            .compactMap { $0.pace.map { ($0 - truth) / truth } }
        #expect(errors.count > 400)
        let mean = errors.reduce(0, +) / Double(errors.count)
        let p95 = errors.map(abs).sorted()[Int(Double(errors.count) * 0.95)]
        #expect(abs(mean) < 0.01, "mean \(mean * 100) %")
        #expect(p95 < 0.03, "p95 \(p95 * 100) %")
    }

    @Test func paceNeedsTwentyMetres() {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 40, speed: 0.5)], accuracy: 3)
        var p = TrackPipeline(configuration: .gps(.run, autoPause: false, barometer: false))
        p.start(at: SyntheticTrack.t0)
        _ = SyntheticTrack.run(&p, fixes)
        #expect(p.currentPace == nil) // 15 m in the window
    }
}
