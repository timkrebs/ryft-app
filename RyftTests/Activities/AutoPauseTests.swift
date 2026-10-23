import Foundation
import Testing
@testable import Ryft

/// Auto-pause (design §3.3 step 8): enter after 10 s below the sport's threshold (or 5 s stationary), leave after 3 s
/// at 1.5 × the threshold; backdated both ways.
@Suite("Auto-pause")
struct AutoPauseTests {
    typealias Segment = SyntheticTrack.Segment

    /// The road's 20 s traffic light: one auto-pause, starting when the runner stopped and ending when they ran on.
    /// Measured: enters 1.5 s after the stop begins, leaves 3.5 s after it ends (the filter's lag to 1.5 m/s).
    @Test func trafficLightEntersAndLeaves() throws {
        let road = try TrackFixture.load("road-5k")
        let replay = TrackReplay(road, .gps(.run, barometer: false))
        let light = try #require(road.stops.first)
        #expect(replay.autoPauses.count == 1 && replay.autoResumes.count == 1)
        let entered = try #require(replay.autoPauses.first), left = try #require(replay.autoResumes.first)
        #expect(entered.timeIntervalSince(light.start) > -1 && entered.timeIntervalSince(light.start) < 4)
        #expect(left.timeIntervalSince(light.end) >= 0 && left.timeIntervalSince(light.end) < 6)
        let pauses = replay.pipeline.pauses
        #expect(pauses == [PauseInterval(kind: .auto, start: entered, end: left)])
        let end = try #require(road.fixes.last).timestamp
        let paused = left.timeIntervalSince(entered)
        #expect(abs(replay.pipeline.movingTime(at: end) - (replay.pipeline.elapsedTime(at: end) - paused)) < 1e-6)
    }

    /// ui.md G3: the shown time never steps back. From the first slow fix the clock holds; the confirmed pause is
    /// backdated to exactly that moment, and auto-resume steps it forward by its 3 s.
    @Test func theClockNeverStepsBackAtTheTrafficLight() throws {
        let road = try TrackFixture.load("road-5k")
        let replay = TrackReplay(road, .gps(.run, barometer: false))
        let shown = replay.trace.map(\.shownMovingSec)
        for (a, b) in zip(shown, shown.dropFirst()) { #expect(b >= a - 1e-9) }
        let entered = try #require(replay.autoPauses.first), light = try #require(road.stops.first)
        // It also holds, rightly, at the start (speed 0 until the filter converges) and at the finish stop.
        let atTheLight = replay.trace.filter { $0.held && abs($0.time.timeIntervalSince(light.start)) < 60 }
        #expect(!atTheLight.isEmpty, "the clock held before the auto-pause confirmed")
        #expect(atTheLight.allSatisfy { $0.time >= entered && $0.time < entered.addingTimeInterval(11) })
    }

    /// A manual pause while an auto-pause is pending starts at the pending moment, where the clock already holds.
    @Test func aManualPauseWhilePendingStartsThere() throws {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 60, speed: 3), Segment(seconds: 30, speed: 0)])
        var p = TrackPipeline(configuration: .gps(.run, barometer: false))
        p.start(at: SyntheticTrack.t0)
        _ = SyntheticTrack.run(&p, Array(fixes[0 ... 67]))
        let now = fixes[67].timestamp
        let pending = try #require(p.pendingAutoPause(at: now))
        let shown = p.snapshot(at: now).movingSec
        #expect(p.state == .recording && p.snapshot(at: now).movingAnchor == nil)
        p.pause(at: now)
        #expect(p.pauses == [PauseInterval(kind: .manual, start: pending)])
        #expect(p.snapshot(at: now.addingTimeInterval(5)).movingSec == shown)
    }

    /// A split crossed while slowing down, inside the 10 s the auto-pause is then backdated over: its duration is
    /// revised to moving time (`splits` and the checkpoint; the `.split` event carried the first value). A sport
    /// with a 2 m/s threshold, so the crossing happens at 1.5 m/s, below it.
    @Test func aSplitInsideABackdatedPauseIsRevised() throws {
        let segments = [Segment(seconds: 330, speed: 3), Segment(seconds: 30, speed: 1.5)]
        let fixes = SyntheticTrack.fixes(segments)
        let profile = TrackProfile(maxSpeed: 9, sigmaA: 1.5, autoPauseThreshold: 2, autoPauseDefault: true,
                                   elevation: .none, paceStyle: .pace)
        var p = TrackPipeline(configuration: .gps(profile, barometer: false))
        p.start(at: SyntheticTrack.t0)
        let events = SyntheticTrack.run(&p, fixes)
        let emitted = try #require(events.compactMap { if case let .split(s) = $0 { s } else { nil } }.first)
        let entered = try #require(events.compactMap { if case let .autoPaused(since) = $0 { since } else { nil } }.first)
        #expect(entered < emitted.end, "the pause is backdated over the crossing")
        let revised = try #require(p.splits.first)
        #expect(revised.durationSec < emitted.durationSec)
        #expect(abs(revised.durationSec - p.movingTime(at: revised.end)) < 1e-9)
        #expect(p.checkpoint?.splits.first == revised)
    }

    @Test func offMeansNeverAutoPaused() throws {
        let road = try TrackFixture.load("road-5k")
        let replay = TrackReplay(road, .gps(.run, autoPause: false, barometer: false))
        #expect(replay.autoPauses.isEmpty && replay.pipeline.pauses.isEmpty)
    }

    /// A phone on a table: auto-paused from its first fix, entered within 10 s.
    @Test func stationaryPhoneIsAutoPausedWithinTenSeconds() throws {
        let still = try TrackFixture.load("stationary")
        let replay = TrackReplay(still, .gps(.run, barometer: false))
        let index = try #require(replay.events.firstIndex { $0.contains { if case .autoPaused = $0 { true } else { false } } })
        #expect(still.fixes[index].timestamp.timeIntervalSince(still.start) <= 10)
        #expect(replay.autoPauses == [still.start])
        #expect(replay.autoResumes.isEmpty)
        #expect(replay.pipeline.movingTime(at: still.fixes[599].timestamp) == 0)
    }

    /// Run 60 s, stand 30 s, run 60 s: the 10 s of confirmation aren't moving time, and the 3 s of leaving count.
    @Test func backdatingKeepsMovingTimeAndDistance() {
        let segments = [Segment(seconds: 60, speed: 3), Segment(seconds: 30, speed: 0), Segment(seconds: 60, speed: 3)]
        let fixes = SyntheticTrack.fixes(segments)
        var p = TrackPipeline(configuration: .gps(.run, barometer: false))
        p.start(at: SyntheticTrack.t0)
        let events = SyntheticTrack.run(&p, fixes)
        #expect(events.filter { if case .autoPaused = $0 { true } else { false } }.count == 1)
        #expect(events.filter { if case .autoResumed = $0 { true } else { false } }.count == 1)
        #expect(abs(p.movingTime(at: fixes[150].timestamp) - 120) < 4, "\(p.movingTime(at: fixes[150].timestamp)) s")
        #expect(abs(p.distanceM - 360) < 4, "\(p.distanceM) m")
        #expect(p.state == .recording)
    }

    /// Core Location's stationary flag pauses after 5 s, also when the fixes stop (liveUpdates pauses itself).
    @Test func stationaryFlagPausesAfterFiveSeconds() {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 30, speed: 3), Segment(seconds: 2, speed: 0, stationary: true)])
        var p = TrackPipeline(configuration: .gps(.run, barometer: false))
        p.start(at: SyntheticTrack.t0)
        _ = SyntheticTrack.run(&p, fixes)
        #expect(p.state == .recording)
        // No fixes after t = 32; the first stationary fix was at t = 31.
        #expect(p.advance(to: SyntheticTrack.t0.addingTimeInterval(35)).isEmpty)
        let events = p.advance(to: SyntheticTrack.t0.addingTimeInterval(36))
        #expect(events == [.autoPaused(since: SyntheticTrack.t0.addingTimeInterval(31))])
        #expect(p.state == .autoPaused)
    }

    @Test func manualPauseDuringAutoPauseStaysManual() {
        let segments = [Segment(seconds: 40, speed: 3), Segment(seconds: 20, speed: 0), Segment(seconds: 30, speed: 3)]
        let fixes = SyntheticTrack.fixes(segments)
        var p = TrackPipeline(configuration: .gps(.run, barometer: false))
        p.start(at: SyntheticTrack.t0)
        _ = SyntheticTrack.run(&p, Array(fixes[0 ... 58]))
        #expect(p.state == .autoPaused)
        p.pause(at: fixes[58].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes[59...]))
        #expect(p.state == .paused, "moving again doesn't end a manual pause")
        #expect(p.pauses.map(\.kind) == [.auto, .manual])
        p.resume(at: fixes[90].timestamp)
        #expect(p.state == .recording && p.pauses.allSatisfy { $0.end != nil })
    }

    @Test func resumeButtonEndsAnAutoPause() {
        let fixes = SyntheticTrack.fixes([Segment(seconds: 40, speed: 3), Segment(seconds: 20, speed: 0)])
        var p = TrackPipeline(configuration: .gps(.run, barometer: false))
        p.start(at: SyntheticTrack.t0)
        _ = SyntheticTrack.run(&p, fixes)
        #expect(p.state == .autoPaused)
        p.resume(at: fixes[60].timestamp)
        #expect(p.state == .recording)
        #expect(p.pauses.last?.end == fixes[60].timestamp)
    }
}
