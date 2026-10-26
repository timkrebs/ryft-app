import Foundation
import Testing
@testable import Ryft

/// The speed-gate guard (ADR 0003 amendment 2; design §11.1 rev. A3a.2, the acceptance table). The speed gate measures
/// from the filter's prediction; a fix nearer a rejected run joins it; a re-init takes the run's velocity and is
/// provisional until its settle window closes, then its span is filled from the anchor; the sport's limit applies to
/// the filter's speed, with a too-fast state. Noiseless tracks check the rules exactly; drifting noise (Gauss–Markov,
/// τ 60 s, σ = accuracy / 2, plus 0.4 m of jitter) checks them against the same seed without the fault.
@Suite("Speed-gate guard")
struct SpeedGateGuardTests {
    typealias Ramp = GuardTrack.Ramp

    struct Mover: CustomTestStringConvertible, Sendable {
        let name: String
        let profile: TrackProfile
        let speed: Double
        var testDescription: String { name }
    }

    static let ghostMovers = [
        Mover(name: "run 3 m/s", profile: .run, speed: 3),
        Mover(name: "ride 8 m/s", profile: .bike, speed: 8),
        Mover(name: "walk 1.4 m/s", profile: .walk, speed: 1.4),
        Mover(name: "MTB 5 m/s", profile: .mtb, speed: 5)
    ]

    static func noAutoPause(_ profile: TrackProfile) -> TrackPipeline.Configuration {
        .gps(profile, autoPause: false, barometer: false)
    }

    static func spans(_ d: PipelineDiagnostics) -> [Int] {
        [d.reinitSpansDeadReckoned, d.reinitSpansBridged, d.reinitSpansDropped]
    }

    // MARK: Ghosts

    /// A 60 m ghost at a falsely good 10 m from fix 100, three directions, 2–15 fixes. Two fixes are rejected and the
    /// true third is accepted. 3–12 fixes are a chain of two re-inits (out and back), bridged once from the anchor;
    /// from 13 the ghost's own window closes inside it, so two single re-inits, each dead-reckoned. `main` lost
    /// 18–45 m on a run and gained up to 68 m on a ride.
    @Test(arguments: ghostMovers)
    func ghostsCostNothing(_ mover: Mover) {
        let speeds = GuardTrack.speeds([.hold(300, mover.speed)])
        let truth = GuardTrack.distance(speeds)
        for count in 2 ... 15 {
            for offset in GuardTrack.ghostOffsets {
                let ghost = GuardTrack.Ghost(from: 100, count: count, offset: offset)
                let (p, events) = GuardTrack.record(Self.noAutoPause(mover.profile), GuardTrack.fixes(speeds, ghost: ghost))
                let d = p.diagnostics
                #expect(abs(p.distanceM - truth) < 1, "\(count) fixes: \(p.distanceM - truth) m")
                switch count {
                case 2: #expect(d.reinitialisations == 0 && Self.spans(d) == [0, 0, 0], "\(count) fixes")
                case 3 ... 12: #expect(d.reinitialisations == 2 && Self.spans(d) == [0, 1, 0], "\(count) fixes")
                default: #expect(d.reinitialisations == 2 && Self.spans(d) == [2, 0, 0], "\(count) fixes")
                }
                // Each run of rejections began at the speed gate (a 60 m jump in 1 s), whichever gate took the rest.
                #expect(d.speedGateReinits == d.reinitialisations)
                #expect(GuardTrack.tooFast(events).isEmpty && d.tooFastSec == 0)
            }
        }
    }

    /// The same under drifting noise, 5 seeds × 3 directions: within 5 m of the same seed without the ghost.
    /// Measured: −3.9 … +1.6 m.
    @Test(arguments: ghostMovers)
    func ghostsInDriftingNoiseCostLittle(_ mover: Mover) {
        let speeds = GuardTrack.speeds([.hold(300, mover.speed)])
        let configuration = Self.noAutoPause(mover.profile)
        for seed in UInt64(1) ... 5 {
            let clean = GuardTrack.record(configuration, GuardTrack.fixes(speeds, seed: seed)).pipeline.distanceM
            for count in 2 ... 15 {
                for offset in GuardTrack.ghostOffsets {
                    let ghost = GuardTrack.Ghost(from: 100, count: count, offset: offset)
                    let fixes = GuardTrack.fixes(speeds, seed: seed, ghost: ghost)
                    let ghosted = GuardTrack.record(configuration, fixes).pipeline.distanceM
                    #expect(abs(ghosted - clean) < 5, "seed \(seed), \(count) fixes: \(ghosted - clean) m")
                }
            }
        }
    }

    /// The offset held for 15 and 30 s on a run and a ride: two single re-inits, each dead-reckoned (`main`: run
    /// −18.0 m, ride +55 … +65 m). Noiseless within 1 m; with noise within 5 m of the same seed.
    @Test(arguments: [15, 30])
    func sustainedMultipathIsDeadReckonedBothWays(seconds: Int) {
        for mover in Self.ghostMovers.prefix(2) {
            let speeds = GuardTrack.speeds([.hold(300, mover.speed)])
            let ghost = GuardTrack.Ghost(from: 100, count: seconds, offset: GuardTrack.ghostOffsets[0])
            let configuration = Self.noAutoPause(mover.profile)
            let (p, _) = GuardTrack.record(configuration, GuardTrack.fixes(speeds, ghost: ghost))
            #expect(abs(p.distanceM - GuardTrack.distance(speeds)) < 1, "\(mover.name): \(p.distanceM) m")
            #expect(p.diagnostics.reinitialisations == 2 && Self.spans(p.diagnostics) == [2, 0, 0], "\(mover.name)")
            for seed in UInt64(1) ... 5 {
                let clean = GuardTrack.record(configuration, GuardTrack.fixes(speeds, seed: seed)).pipeline.distanceM
                let held = GuardTrack.record(configuration, GuardTrack.fixes(speeds, seed: seed, ghost: ghost)).pipeline
                #expect(abs(held.distanceM - clean) < 5, "\(mover.name) seed \(seed): \(held.distanceM - clean) m")
            }
        }
    }

    // MARK: Descents and the limit

    /// 120 s at 10, +1 m/s² to 33, 120 s at 33, −1.9 m/s² to 10, 120 s at 10 m/s: 7,112.5 m.
    static let descent = GuardTrack.speeds([.hold(120, 10), Ramp(23, 10, 33), .hold(120, 33), Ramp(12, 33, 10),
                                            .hold(120, 10)])

    /// A road descent at 33 m/s is cycling (limit 36): counted in full, no too-fast, no re-init. At the old limit of
    /// 25 the speed gate made it −58.8 % at a reported 2 m and 0.0 % at 5 m, silently. Measured: −0.0 … +0.0 %.
    @Test(arguments: [2.0, 3.0, 5.0])
    func aDescentAt33MetresPerSecondCountsInFull(accuracy: Double) {
        let truth = GuardTrack.distance(Self.descent)
        for seed in [nil, 1, 2] as [UInt64?] {
            let (p, events) = GuardTrack.record(.gps(.bike, barometer: false),
                                                GuardTrack.fixes(Self.descent, accuracy: accuracy, seed: seed))
            let error = (p.distanceM - truth) / truth
            #expect(abs(error) < 0.01, "seed \(String(describing: seed)): \(error * 100) %")
            #expect(GuardTrack.tooFast(events).isEmpty && p.diagnostics.reinitialisations == 0)
            #expect(p.diagnostics.rejectedImplausible == 0)
        }
    }

    /// The same descent on a test profile limited to 25 m/s: the part above the limit adds nothing, and says so.
    /// `.tooFast` within 3 s after the truth passes 25 m/s, `.tooFastEnded` within 4 s after it drops below, and the
    /// distance is the part at or below 25 m/s (2,803.8 m) ±1 %, at every accuracy. Measured noiseless: since +1 s,
    /// ended +1 … +2 s, −0.0 … +0.0 %. Under drifting noise each second the boundaries move is 25 m (0.9 %): at a
    /// reported 5 m (σ 2.5 m) 20 seeds read −1.21 … +1.09 %, so the noisy bound is ±1.5 % (2 and 3 m: within ±0.3 %).
    @Test(arguments: [2.0, 3.0, 5.0])
    func aDescentAboveTheLimitPausesDistanceAndSaysSo(accuracy: Double) throws {
        var limited = TrackProfile.bike
        limited.maxSpeed = 25
        let crossing = try #require(GuardTrack.crossings(Self.descent, limit: 25))
        let below = try #require(crossing.below)
        let allowed = GuardTrack.distance(Self.descent, atMost: 25)
        for seed in [nil, 1, 2, 3, 4, 5] as [UInt64?] {
            let (p, events) = GuardTrack.record(.gps(limited, barometer: false),
                                                GuardTrack.fixes(Self.descent, accuracy: accuracy, seed: seed))
            let entered = GuardTrack.tooFast(events), ended = GuardTrack.tooFastEnded(events)
            #expect(entered.count == 1 && ended.count == 1, "seed \(String(describing: seed))")
            let since = try #require(entered.first), endedSince = try #require(ended.first)
            #expect(since.timeIntervalSince(crossing.above) >= 0 && since.timeIntervalSince(crossing.above) <= 3,
                    "since \(since.timeIntervalSince(crossing.above)) s after the truth")
            #expect(endedSince.timeIntervalSince(below) >= 0 && endedSince.timeIntervalSince(below) <= 4,
                    "ended \(endedSince.timeIntervalSince(below)) s after the truth")
            let error = (p.distanceM - allowed) / allowed
            #expect(abs(error) < (seed == nil ? 0.01 : 0.015), "seed \(String(describing: seed)): \(error * 100) %")
            #expect(p.diagnostics.reinitialisations == 0 && p.tooFastSince == nil)
        }
    }

    /// "Running" chosen on a bike: a 15 s ramp from 0, then 300 s at 15 m/s (4,612.5 m). At most 80 m (the ramp below
    /// 9 m/s is 40.5 m) and one `.tooFast` within 4 s after the truth passes 9 m/s, at every reported accuracy. `main`
    /// recorded 67–90 m at 2–3 m and all of it at 4–5 m, silently. Measured: 55–59 m, since +2 s.
    @Test(arguments: [2.0, 3.0, 4.0, 5.0])
    func runningChosenOnABikeSaysTooFast(accuracy: Double) throws {
        let speeds = GuardTrack.speeds([Ramp(15, 0, 15), .hold(300, 15)])
        let passes = try #require(GuardTrack.crossings(speeds, limit: 9)).above
        for seed in [nil, 1, 2] as [UInt64?] {
            let (p, events) = GuardTrack.record(.gps(.run, barometer: false),
                                                GuardTrack.fixes(speeds, accuracy: accuracy, seed: seed))
            #expect(p.distanceM <= 80, "\(p.distanceM) m")
            let entered = GuardTrack.tooFast(events)
            #expect(entered.count == 1 && GuardTrack.tooFastEnded(events).isEmpty)
            let since = try #require(entered.first)
            #expect(since.timeIntervalSince(passes) >= 0 && since.timeIntervalSince(passes) <= 4,
                    "since \(since.timeIntervalSince(passes)) s after the truth")
            #expect(p.diagnostics.reinitialisations == 0 && p.diagnostics.tooFastEpisodes == 1)
        }
    }

    /// The same with a flying start: 30 s at 15 m/s before Start. Nothing counts, and `.tooFast` comes within 15 s of
    /// Start: the first window's line is faster, so the state starts with it. `main`: 0 m at 2–3 m, 4,498 m at 5 m,
    /// silently. Measured: 0 m, emitted 10 s after Start, since Start.
    @Test(arguments: [2.0, 3.0, 4.0, 5.0])
    func aFlyingStartTooFastCountsNothing(accuracy: Double) {
        let speeds = GuardTrack.speeds([.hold(330, 15)])
        for seed in [nil, 1, 2] as [UInt64?] {
            let fixes = GuardTrack.fixes(speeds, accuracy: accuracy, seed: seed)
            var p = TrackPipeline(configuration: .gps(.run, barometer: false))
            for fix in fixes[..<30] { _ = p.ingest(fix) }
            let start = fixes[30].timestamp
            p.start(at: start)
            var emitted: [Date] = []
            for fix in fixes[30...] {
                let events = p.ingest(fix)
                if !GuardTrack.tooFast(events).isEmpty { emitted.append(fix.timestamp) }
            }
            #expect(p.distanceM == 0, "\(p.distanceM) m")
            #expect(emitted.count == 1)
            #expect((emitted.first?.timeIntervalSince(start) ?? .infinity) <= 15)
            #expect(p.tooFastSince == start)
        }
    }

    /// A train after a run, auto-pause on: 300 s at 3 m/s (903 m with the stop), 120 s still, the train at +0.7 m/s²
    /// to 33 m/s, 300 s, −1 m/s² to 0, 60 s still. At most 120 m added (its acceleration and braking below 9 m/s are
    /// 58 + 41 m) and one episode, from within 3 s after it passes 9 m/s to within 4 s after it drops below. `main`:
    /// +243 … +334 m, silently. Measured noiseless: +105 / +109 m, since +1 s, ended +2 s. Under drifting noise
    /// "added" is against the same seed with the train left out (the run's own noise reads +0.5 … +13 m): 20 seeds
    /// +91 … +118 m.
    @Test(arguments: [3.0, 5.0])
    func aTrainAfterARunIsOneEpisode(accuracy: Double) throws {
        let run = GuardTrack.speeds([.hold(300, 3), Ramp(2, 3, 0)])
        let train = GuardTrack.speeds([.hold(120, 0), Ramp(47, 0, 33), .hold(300, 33), Ramp(33, 33, 0), .hold(60, 0)])
        let speeds = run + train
        let crossing = try #require(GuardTrack.crossings(speeds, limit: 9))
        let below = try #require(crossing.below)
        for seed in [nil, 1, 2, 3, 4, 5] as [UInt64?] {
            let (p, events) = GuardTrack.record(.gps(.run, barometer: false),
                                                GuardTrack.fixes(speeds, accuracy: accuracy, seed: seed))
            let withoutTrain = run + Array(repeating: 0.0, count: train.count)
            let baseline = seed == nil ? GuardTrack.distance(run)
                : GuardTrack.record(.gps(.run, barometer: false),
                                    GuardTrack.fixes(withoutTrain, accuracy: accuracy, seed: seed)).pipeline.distanceM
            let added = p.distanceM - baseline
            #expect(added >= 0 && added <= 120, "seed \(String(describing: seed)): +\(added) m")
            if seed == nil {
                // The design's probe: +105 / +109 m. Position steps after the auto-resume are refused by the filter's
                // speed now; judged by the mean of the step's ends they'd add a step more (+119 m at 5 m).
                #expect(abs(added - (accuracy == 3 ? 105 : 109)) < 3, "+\(added) m")
            }
            let entered = GuardTrack.tooFast(events), ended = GuardTrack.tooFastEnded(events)
            #expect(entered.count == 1 && ended.count == 1)
            let since = try #require(entered.first), endedSince = try #require(ended.first)
            #expect(since.timeIntervalSince(crossing.above) >= 0 && since.timeIntervalSince(crossing.above) <= 3,
                    "since \(since.timeIntervalSince(crossing.above)) s after the truth")
            #expect(endedSince.timeIntervalSince(below) >= 0 && endedSince.timeIntervalSince(below) <= 4,
                    "ended \(endedSince.timeIntervalSince(below)) s after the truth")
        }
    }

    // MARK: Guards

    /// GPS trouble: offsets of 40–70 m hop every 3–5 fixes for 40 s, at a reported 8 m, 10 seeds. No `.tooFast` (the
    /// hops look like 15–20 m/s to a gate, not to the filter); weak GPS exactly while a chain of re-inits is open; never
    /// more than 25 m above the same seed without trouble. Measured: run −44 … +1, walk −9 … +1, ride −98 … +20 m.
    @Test(arguments: Array(ghostMovers.prefix(3)))
    func gpsTroubleIsWeakNeverTooFast(_ mover: Mover) {
        let speeds = GuardTrack.speeds([.hold(300, mover.speed)])
        let configuration = Self.noAutoPause(mover.profile)
        var chainsSeen = 0
        for seed in UInt64(1) ... 10 {
            let clean = GuardTrack.fixes(speeds, seed: seed)
            var fixes = clean
            var hops = SeededGenerator(seed: seed &* 31)
            var i = 100
            while i < 140 {
                let length = 3 + Int(hops.next() % 3)
                let angle = Double(hops.next() % 360) * .pi / 180
                let metres = 40 + Double(hops.next() % 30)
                let offset = Displacement(east: metres * sin(angle), north: metres * cos(angle))
                for j in i ..< min(i + length, 140) {
                    let c = LocalTangentPlane(anchor: clean[j].coordinate).unproject(offset)
                    fixes[j] = LocationFix(timestamp: clean[j].timestamp, latitude: c.latitude, longitude: c.longitude,
                                           horizontalAccuracy: 8)
                }
                i += length
            }
            var p = TrackPipeline(configuration: configuration)
            p.start(at: fixes[0].timestamp)
            var events: [PipelineEvent] = []
            var open = 0, closed = 0
            for fix in fixes {
                let new = p.ingest(fix)
                events += new
                let d = p.diagnostics
                if Self.spans(d).reduce(0, +) != closed {
                    closed = Self.spans(d).reduce(0, +)
                    open = 0
                }
                open += new.filter { $0 == .reinitialised }.count
                let weak = p.gpsQuality(at: fix.timestamp) == .weak
                #expect(weak == (open >= 2), "seed \(seed) at \(fix.timestamp.timeIntervalSince(fixes[0].timestamp)) s")
                if open >= 2 { chainsSeen += 1 }
            }
            _ = p.finish(at: fixes[fixes.count - 1].timestamp)
            let baseline = GuardTrack.record(configuration, clean).pipeline.distanceM
            #expect(p.distanceM - baseline <= 25, "seed \(seed): \(p.distanceM - baseline) m")
            #expect(GuardTrack.tooFast(events).isEmpty, "seed \(seed)")
        }
        #expect(chainsSeen > 0, "the trouble opened a chain")
    }

    struct Sprint: CustomTestStringConvertible, Sendable {
        let name: String
        let profile: TrackProfile
        let ramps: [GuardTrack.Ramp]
        var testDescription: String { name }
    }

    /// Fast but on foot: a walk with 60 s at 4.5 m/s, a run with a 12 s sprint at 8.5 m/s. Within 10 m, no
    /// `.tooFast`: the limits are the fastest each sport is done. At the old walking limit of 4 m/s the walk lost 272 m.
    @Test(arguments: [
        Sprint(name: "walk with a jog at 4.5 m/s", profile: .walk,
               ramps: [.hold(120, 1.4), Ramp(5, 1.4, 4.5), .hold(60, 4.5), Ramp(5, 4.5, 1.4), .hold(120, 1.4)]),
        Sprint(name: "run with a sprint at 8.5 m/s", profile: .run,
               ramps: [.hold(120, 3), Ramp(4, 3, 8.5), .hold(12, 8.5), Ramp(6, 8.5, 3), .hold(120, 3)])
    ])
    func fastButOnFootIsNotTooFast(_ sprint: Sprint) {
        let speeds = GuardTrack.speeds(sprint.ramps)
        let truth = GuardTrack.distance(speeds)
        for seed in [nil, 1, 2, 3, 4, 5] as [UInt64?] {
            let (p, events) = GuardTrack.record(Self.noAutoPause(sprint.profile), GuardTrack.fixes(speeds, seed: seed))
            #expect(abs(p.distanceM - truth) < 10, "seed \(String(describing: seed)): \(p.distanceM - truth) m")
            #expect(GuardTrack.tooFast(events).isEmpty && p.diagnostics.tooFastSec == 0)
        }
    }

    struct Manoeuvre: CustomTestStringConvertible, Sendable {
        let name: String
        let profile: TrackProfile
        let ramps: [GuardTrack.Ramp]
        let turn: (at: Int, seconds: Int, degrees: Double)?
        var testDescription: String { name }
    }

    /// Legitimate manoeuvres cause no rejection, so association and the provisional re-init never meet them, and the
    /// result is `main`'s (probe: identical). 5 seeds each: no fix rejected by either gate, no re-init, no too-fast.
    @Test(arguments: [
        Manoeuvre(name: "U-turn at 3 m/s, 180° in 2 s", profile: .run, ramps: [.hold(300, 3)], turn: (150, 2, 180)),
        Manoeuvre(name: "U-turn slowing to 1 m/s", profile: .run,
                  ramps: [.hold(148, 3), Ramp(2, 3, 1), .hold(2, 1), Ramp(2, 1, 3), .hold(146, 3)], turn: (150, 2, 180)),
        Manoeuvre(name: "hairpin at 10 m/s, 180° in 4 s", profile: .bike, ramps: [.hold(300, 10)], turn: (150, 4, 180)),
        Manoeuvre(name: "90° corner at 12 m/s in 1 s", profile: .bike, ramps: [.hold(300, 12)], turn: (150, 1, 90)),
        Manoeuvre(name: "emergency stop 12 → 0 in 3 s", profile: .bike,
                  ramps: [.hold(150, 12), Ramp(3, 12, 0), .hold(20, 0), Ramp(6, 0, 12), .hold(120, 12)], turn: nil)
    ])
    func manoeuvresAreNeverRejected(_ manoeuvre: Manoeuvre) {
        let speeds = GuardTrack.speeds(manoeuvre.ramps)
        var turns: [Int: Double] = [:]
        if let turn = manoeuvre.turn {
            for i in turn.at ..< turn.at + turn.seconds { turns[i] = turn.degrees / Double(turn.seconds) }
        }
        for seed in UInt64(1) ... 5 {
            let (p, events) = GuardTrack.record(Self.noAutoPause(manoeuvre.profile),
                                                GuardTrack.turning(speeds, turns: turns, seed: seed))
            let d = p.diagnostics
            #expect(d.rejectedImplausible == 0 && d.rejectedInnovation == 0 && d.reinitialisations == 0, "seed \(seed)")
            #expect(GuardTrack.tooFast(events).isEmpty)
            #expect(abs(p.distanceM - GuardTrack.distance(speeds)) < 15, "seed \(seed): \(p.distanceM) m")
        }
    }

    // MARK: The state and the anchor

    /// The too-fast state in the snapshot: `tooFastSince` set and cleared with the events; meanwhile no route point, no
    /// current pace or speed, and the clock runs on (it isn't a pause).
    @Test func theSnapshotFollowsTheTooFastState() throws {
        let speeds = GuardTrack.speeds([.hold(60, 3), Ramp(4, 3, 12), .hold(40, 12), Ramp(4, 12, 3), .hold(80, 3)])
        let fixes = GuardTrack.fixes(speeds)
        var p = TrackPipeline(configuration: Self.noAutoPause(.run))
        p.start(at: fixes[0].timestamp)
        var entered: Date?, ended: Date?, tooFastFixes = 0
        for fix in fixes {
            let events = p.ingest(fix)
            let snapshot = p.snapshot(at: fix.timestamp)
            // Each change is confirmed by 3 s of steps on the other side and backdated to the first of them.
            if let since = GuardTrack.tooFast(events).first {
                entered = since
                #expect(snapshot.tooFastSince == since && fix.timestamp.timeIntervalSince(since) == 3)
            }
            if let since = GuardTrack.tooFastEnded(events).first {
                ended = since
                #expect(snapshot.tooFastSince == nil && fix.timestamp.timeIntervalSince(since) == 3)
            }
            #expect(snapshot.tooFastSince == p.tooFastSince)
            if p.tooFastSince != nil {
                tooFastFixes += 1
                #expect(GuardTrack.routes(events) == 0)
                #expect(snapshot.currentPace == nil && snapshot.currentSpeed == nil)
                #expect(snapshot.state == .recording && snapshot.movingSec == snapshot.elapsedSec)
                #expect(snapshot.movingAnchor != nil)
            } else {
                #expect(GuardTrack.routes(events) == 1)
            }
        }
        let since = try #require(entered), endedSince = try #require(ended)
        #expect(tooFastFixes > 30)
        // Every refused second lies inside the episode (noiseless: no blip outside it).
        #expect(abs(p.diagnostics.tooFastSec - endedSince.timeIntervalSince(since)) < 1e-6)
        let last = try #require(fixes.last)
        #expect(p.snapshot(at: last.timestamp).currentPace != nil)
        #expect(p.diagnostics.tooFastEpisodes == 1)
    }

    /// Pause and Finish drop a provisional re-init's anchor: its span isn't filled across them. A 3-fix ghost from
    /// fix 100 re-initialises at fix 102, anchored at fix 99.
    @Test func pauseAndFinishDropTheAnchor() {
        let speeds = GuardTrack.speeds([.hold(200, 3)])
        let ghost = GuardTrack.Ghost(from: 100, count: 3, offset: GuardTrack.ghostOffsets[0])
        let fixes = GuardTrack.fixes(speeds, ghost: ghost)

        var paused = TrackPipeline(configuration: Self.noAutoPause(.run))
        paused.start(at: fixes[0].timestamp)
        _ = SyntheticTrack.run(&paused, Array(fixes[...104]))
        #expect(paused.diagnostics.reinitialisations == 1 && Self.spans(paused.diagnostics) == [0, 0, 0])
        paused.pause(at: fixes[104].timestamp)
        #expect(Self.spans(paused.diagnostics) == [0, 0, 1])
        _ = SyntheticTrack.run(&paused, Array(fixes[105 ... 129]))
        paused.resume(at: fixes[130].timestamp)
        _ = SyntheticTrack.run(&paused, Array(fixes[130...]))
        #expect(Self.spans(paused.diagnostics) == [0, 0, 1])
        // Up to fix 99, then from fix 130 on: nothing between them.
        #expect(abs(paused.distanceM - (297 + 210)) < 0.5, "\(paused.distanceM) m")

        var finished = TrackPipeline(configuration: Self.noAutoPause(.run))
        finished.start(at: fixes[0].timestamp)
        _ = SyntheticTrack.run(&finished, Array(fixes[...104]))
        _ = finished.finish(at: fixes[104].timestamp)
        #expect(Self.spans(finished.diagnostics) == [0, 0, 1])
        #expect(abs(finished.distanceM - 297) < 0.5, "\(finished.distanceM) m")
    }

    /// A resume drops it too. An anchor can be open at Resume only during an auto-pause; here the user walks on at
    /// 1.2 m/s, below auto-resume (1.5 m/s) and above the dead-band (0.5), so the span would be dead-reckoned.
    @Test func resumeDropsTheAnchor() {
        let speeds = GuardTrack.speeds([.hold(100, 3), .hold(20, 0), .hold(80, 1.2)])
        let ghost = GuardTrack.Ghost(from: 150, count: 3, offset: GuardTrack.ghostOffsets[0])
        let fixes = GuardTrack.fixes(speeds, ghost: ghost)
        var p = TrackPipeline(configuration: .gps(.run, autoPause: true, barometer: false))
        p.start(at: fixes[0].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes[...152]))
        #expect(p.state == .autoPaused && p.diagnostics.reinitialisations == 1)
        p.resume(at: fixes[153].timestamp)
        #expect(Self.spans(p.diagnostics) == [0, 0, 1])
        _ = SyntheticTrack.run(&p, Array(fixes[153...]))
        #expect(Self.spans(p.diagnostics) == [0, 0, 1])
    }

    /// A single re-init dead-reckons only when its anchor is at most 10 s before it; further back, the gap rule's
    /// straight line. Fixes every 3 s put the anchor 9 s back (each way of a long ghost dead-reckoned, exact); every
    /// 4 s, 12 s back (both bridged).
    @Test(arguments: [3, 4])
    func deadReckoningCoversAtMostTenSeconds(every seconds: Int) {
        let speeds = GuardTrack.speeds([.hold(300, 3)])
        let ghost = GuardTrack.Ghost(from: 100, count: 21 + seconds, offset: GuardTrack.ghostOffsets[0])
        let sparse = GuardTrack.fixes(speeds, ghost: ghost).enumerated().filter { $0.offset % seconds == 0 }.map(\.element)
        let (p, _) = GuardTrack.record(Self.noAutoPause(.run), sparse)
        #expect(p.diagnostics.reinitialisations == 2)
        if seconds == 3 {
            #expect(Self.spans(p.diagnostics) == [2, 0, 0])
            #expect(abs(p.distanceM - GuardTrack.distance(speeds)) < 1, "\(p.distanceM) m")
        } else {
            #expect(Self.spans(p.diagnostics) == [0, 2, 0])
        }
    }

    /// A span counts only between the dead-band and the sport's limit: a 3-fix ghost (a chain) on "running" at 15 m/s
    /// is refused as too fast (its 90 m go to the too-fast numbers), and at 0.4 m/s, below the run's 0.5 m/s dead-band,
    /// adds nothing.
    @Test func aSpanCountsOnlyBetweenTheDeadBandAndTheLimit() {
        let ghost = GuardTrack.Ghost(from: 100, count: 3, offset: GuardTrack.ghostOffsets[0])
        let (fast, _) = GuardTrack.record(Self.noAutoPause(.run),
                                          GuardTrack.fixes(GuardTrack.speeds([.hold(200, 15)]), ghost: ghost))
        #expect(fast.distanceM == 0 && Self.spans(fast.diagnostics) == [0, 0, 1])
        #expect(fast.diagnostics.reinitialisations == 2 && fast.diagnostics.tooFastDistanceM > 90)
        let (slow, _) = GuardTrack.record(Self.noAutoPause(.run),
                                          GuardTrack.fixes(GuardTrack.speeds([.hold(200, 0.4)]), ghost: ghost))
        #expect(slow.distanceM == 0 && Self.spans(slow.diagnostics) == [0, 0, 1])
    }

    /// A gap inside the provisional window drops the anchor: the gap rule bridges from the window's start, and the
    /// chain's span before it isn't filled on top (that would count the gap twice).
    @Test func aGapInsideTheWindowDropsTheAnchor() {
        let speeds = GuardTrack.speeds([.hold(300, 3)])
        let ghost = GuardTrack.Ghost(from: 100, count: 3, offset: GuardTrack.ghostOffsets[0])
        let all = GuardTrack.fixes(speeds, ghost: ghost)
        let (p, events) = GuardTrack.record(Self.noAutoPause(.run), Array(all[...105]) + Array(all[121...]))
        #expect(Self.spans(p.diagnostics) == [0, 0, 1])
        #expect(events.contains(.gap(seconds: 16, bridged: true)))
        // Everything but the chain's span from fix 99 to fix 105: 18 m.
        #expect(abs(p.distanceM - (GuardTrack.distance(speeds) - 18)) < 1, "\(p.distanceM) m")
    }

    /// No anchor while paused: a long ghost during a manual pause re-initialises the filter twice, and no span is
    /// filled or counted.
    @Test func aGhostWhilePausedKeepsNoAnchor() {
        let speeds = GuardTrack.speeds([.hold(300, 3)])
        let ghost = GuardTrack.Ghost(from: 100, count: 15, offset: GuardTrack.ghostOffsets[0])
        let fixes = GuardTrack.fixes(speeds, ghost: ghost)
        var p = TrackPipeline(configuration: Self.noAutoPause(.run))
        p.start(at: fixes[0].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes[...90]))
        p.pause(at: fixes[90].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes[91 ... 150]))
        p.resume(at: fixes[150].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes[151...]))
        #expect(p.diagnostics.reinitialisations == 2 && Self.spans(p.diagnostics) == [0, 0, 0])
    }

    /// The counters count each case once: a re-init counts toward `speedGateReinits` only when its run had a
    /// speed-gate rejection (here a 25 m offset at 3 m on a ride: well inside 36 m/s, far outside the innovation
    /// gate), and the too-fast numbers are the refused seconds and the filter's speed over them.
    @Test func diagnosticsCountEachCaseOnce() {
        let ride = GuardTrack.speeds([.hold(300, 8)])
        let near = GuardTrack.Ghost(from: 100, count: 5, offset: Displacement(east: -21.65, north: 12.5), accuracy: 3)
        let (p, _) = GuardTrack.record(Self.noAutoPause(.bike), GuardTrack.fixes(ride, accuracy: 3, ghost: near))
        #expect(p.diagnostics.reinitialisations == 2 && p.diagnostics.speedGateReinits == 0)
        #expect(p.diagnostics.rejectedImplausible == 0 && p.diagnostics.rejectedInnovation == 4)
        #expect(Self.spans(p.diagnostics) == [0, 1, 0] && abs(p.distanceM - 2400) < 1)

        var limited = TrackProfile.bike
        limited.maxSpeed = 25
        let (q, events) = GuardTrack.record(.gps(limited, barometer: false), GuardTrack.fixes(Self.descent))
        let d = q.diagnostics
        #expect(d.tooFastEpisodes == 1 && GuardTrack.tooFast(events).count == 1)
        if let since = GuardTrack.tooFast(events).first, let ended = GuardTrack.tooFastEnded(events).first {
            #expect(abs(d.tooFastSec - ended.timeIntervalSince(since)) < 1e-6)
        }
        // The filter's speed over the refused seconds: about the descent above 25 m/s (4,308.7 m), never distance.
        let above = GuardTrack.distance(Self.descent) - GuardTrack.distance(Self.descent, atMost: 25)
        #expect(abs(d.tooFastDistanceM - above) / above < 0.02, "\(d.tooFastDistanceM) m of \(above) m")
        #expect(abs(q.distanceM + d.tooFastDistanceM - GuardTrack.distance(Self.descent)) < 10)
        #expect(Self.spans(d) == [0, 0, 0] && d.speedGateReinits == 0)
    }
}
