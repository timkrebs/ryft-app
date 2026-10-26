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

    /// The same descent on a test profile limited to 25 m/s: the part above the limit adds nothing, and says so. The
    /// state enters above the entry speed (26.25 m/s, review S1) and leaves at or below 25. So `.tooFast` within 3 s
    /// after the truth passes the entry speed, `.tooFastEnded` within 4 s after it drops to 25, and the distance is what
    /// that hysteresis allows (up the ramp to 26.25, then from 25 down: 2,829 m; 2,804 m at or below 25) ±1 %, at every
    /// accuracy. Measured noiseless: since +1 s, ended +1 … +2 s, +0.00 … +0.04 %. Under drifting noise each second a
    /// boundary moves is 25 m (0.9 %): 20 seeds read −1.19 … +1.15 %, so the noisy bound is ±1.5 %.
    @Test(arguments: [2.0, 3.0, 5.0])
    func aDescentAboveTheLimitPausesDistanceAndSaysSo(accuracy: Double) throws {
        var limited = TrackProfile.bike
        limited.maxSpeed = 25
        let entry = try #require(GuardTrack.crossings(Self.descent, limit: GuardTrack.entrySpeed(25)))
        let below = try #require(GuardTrack.crossings(Self.descent, limit: 25)?.below)
        let up = Int(entry.above.timeIntervalSince(SyntheticTrack.t0)), down = Int(below.timeIntervalSince(SyntheticTrack.t0))
        let allowed = Self.descent[..<up].reduce(0, +) + Self.descent[down...].reduce(0, +)
        for seed in [nil, 1, 2, 3, 4, 5] as [UInt64?] {
            let (p, events) = GuardTrack.record(.gps(limited, barometer: false),
                                                GuardTrack.fixes(Self.descent, accuracy: accuracy, seed: seed))
            let entered = GuardTrack.tooFast(events), ended = GuardTrack.tooFastEnded(events)
            #expect(entered.count == 1 && ended.count == 1, "seed \(String(describing: seed))")
            let since = try #require(entered.first), endedSince = try #require(ended.first)
            #expect(since.timeIntervalSince(entry.above) >= 0 && since.timeIntervalSince(entry.above) <= 3,
                    "since \(since.timeIntervalSince(entry.above)) s after the truth")
            #expect(endedSince.timeIntervalSince(below) >= 0 && endedSince.timeIntervalSince(below) <= 4,
                    "ended \(endedSince.timeIntervalSince(below)) s after the truth")
            let error = (p.distanceM - allowed) / allowed
            #expect(abs(error) < (seed == nil ? 0.01 : 0.015), "seed \(String(describing: seed)): \(error * 100) %")
            #expect(p.diagnostics.reinitialisations == 0 && p.tooFastSince == nil)
        }
    }

    /// "Running" chosen on a bike: a 15 s ramp from 0, then 300 s at 15 m/s (4,612.5 m). At most 80 m (the ramp below
    /// 9 m/s is 40.5 m) and one `.tooFast` within 4 s after the truth passes 9 m/s, at every reported accuracy. `main`
    /// recorded 67–90 m at 2–3 m and all of it at 4–5 m, silently. Measured over the implementer's and the review's
    /// runs: 54–68 m, since +2 … +3 s (the state enters above 9.6 m/s).
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
    /// to 33 m/s, 300 s, −1 m/s² to 0, 60 s still. One episode, from within 3 s after the train passes the entry speed
    /// (9.6 m/s) to within 4 s after it drops to 9. At most 135 m added: its acceleration to the entry speed and its
    /// braking below 9 m/s are 66 + 41 m, and the filter crosses the entry speed 1–3 s late (A3a.2 had 120 m with the
    /// state entering at 9 m/s; review S1 moved it). `main`: +243 … +334 m, silently. Measured noiseless: +114 /
    /// +128 m, since +0 … +2 s, ended +1 … +3 s. Under drifting noise "added" is against the same seed with the train
    /// left out (the run's own noise reads +0.5 … +13 m): 20 seeds +102 … +131 m (the review's seeds: +107 … +131 m).
    @Test(arguments: [3.0, 5.0])
    func aTrainAfterARunIsOneEpisode(accuracy: Double) throws {
        let run = GuardTrack.speeds([.hold(300, 3), Ramp(2, 3, 0)])
        let train = GuardTrack.speeds([.hold(120, 0), Ramp(47, 0, 33), .hold(300, 33), Ramp(33, 33, 0), .hold(60, 0)])
        let speeds = run + train
        let entry = try #require(GuardTrack.crossings(speeds, limit: GuardTrack.entrySpeed(9))).above
        let below = try #require(GuardTrack.crossings(speeds, limit: 9)?.below)
        for seed in [nil, 1, 2, 3, 4, 5] as [UInt64?] {
            let (p, events) = GuardTrack.record(.gps(.run, barometer: false),
                                                GuardTrack.fixes(speeds, accuracy: accuracy, seed: seed))
            let withoutTrain = run + Array(repeating: 0.0, count: train.count)
            let baseline = seed == nil ? GuardTrack.distance(run)
                : GuardTrack.record(.gps(.run, barometer: false),
                                    GuardTrack.fixes(withoutTrain, accuracy: accuracy, seed: seed)).pipeline.distanceM
            let added = p.distanceM - baseline
            #expect(added >= 0 && added <= 135, "seed \(String(describing: seed)): +\(added) m")
            if seed == nil {
                // Measured +114 / +128 m. Position steps after the auto-resume are judged by the filter's speed now;
                // judged by the mean of the step's ends they'd add a step more.
                #expect(abs(added - (accuracy == 3 ? 113.7 : 128.2)) < 3, "+\(added) m")
            }
            let entered = GuardTrack.tooFast(events), ended = GuardTrack.tooFastEnded(events)
            #expect(entered.count == 1 && ended.count == 1)
            let since = try #require(entered.first), endedSince = try #require(ended.first)
            #expect(since.timeIntervalSince(entry) >= 0 && since.timeIntervalSince(entry) <= 3,
                    "since \(since.timeIntervalSince(entry)) s after the truth")
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

    /// Fast but on foot: a walk with 60 s at 4.5 m/s, a run with a 12 s sprint at 8.5 m/s, 30 seeds. Within 10 m, no
    /// `.tooFast` and nothing refused: the limits are the fastest each sport is done. At the old walking limit of 4 m/s
    /// the walk lost 272 m; before the review's hold and hysteresis (S1) the sprint lost −12.1 m on seed 9 and −18.3 m
    /// on seed 28, silently. Measured: −4.9 … +8.9 m.
    @Test(arguments: [
        Sprint(name: "walk with a jog at 4.5 m/s", profile: .walk,
               ramps: [.hold(120, 1.4), Ramp(5, 1.4, 4.5), .hold(60, 4.5), Ramp(5, 4.5, 1.4), .hold(120, 1.4)]),
        Sprint(name: "run with a sprint at 8.5 m/s", profile: .run,
               ramps: [.hold(120, 3), Ramp(4, 3, 8.5), .hold(12, 8.5), Ramp(6, 8.5, 3), .hold(120, 3)])
    ])
    func fastButOnFootIsNotTooFast(_ sprint: Sprint) {
        let speeds = GuardTrack.speeds(sprint.ramps)
        let truth = GuardTrack.distance(speeds)
        let seeds: [UInt64?] = [nil] + (1 ... 30).map { UInt64($0) }
        for seed in seeds {
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
        // The way back re-initialises inside the window the dropped anchor left, so that window's first position (the
        // ghost) anchors it (review S3); the line from the ghost is too fast, so that span is dropped as well, and a
        // dropped span adds nothing later either (the part after Resume isn't released as distance).
        #expect(p.diagnostics.reinitialisations == 2 && Self.spans(p.diagnostics) == [0, 0, 2])
        var clean = TrackPipeline(configuration: .gps(.run, autoPause: true, barometer: false))
        let truth = GuardTrack.fixes(speeds)
        clean.start(at: truth[0].timestamp)
        _ = SyntheticTrack.run(&clean, Array(truth[...152]))
        clean.resume(at: truth[153].timestamp)
        _ = SyntheticTrack.run(&clean, Array(truth[153...]))
        #expect(abs(p.distanceM - clean.distanceM) < 5, "\(p.distanceM) m, without the ghost \(clean.distanceM) m")
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

    /// A gap inside the provisional window is bridged from the anchor (review N-e): the chain's span and the silence
    /// in one straight line, fix 99 to fix 121, and the anchor ends as one bridged span. (A3a.2 dropped the span: −18 m.)
    @Test func aGapInsideTheWindowIsBridgedFromTheAnchor() {
        let speeds = GuardTrack.speeds([.hold(300, 3)])
        let ghost = GuardTrack.Ghost(from: 100, count: 3, offset: GuardTrack.ghostOffsets[0])
        let all = GuardTrack.fixes(speeds, ghost: ghost)
        let (p, events) = GuardTrack.record(Self.noAutoPause(.run), Array(all[...105]) + Array(all[121...]))
        #expect(Self.spans(p.diagnostics) == [0, 1, 0])
        #expect(events.contains(.gap(seconds: 16, bridged: true)) && p.diagnostics.gapsBridged == 1)
        #expect(abs(p.distanceM - GuardTrack.distance(speeds)) < 1, "\(p.distanceM) m")
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
        // The filter's speed over the refused seconds: about the descent the hysteresis refuses (above 26.25 m/s going
        // up, above 25 going down: 4,283.6 m), never distance.
        let up = Self.descent.firstIndex { $0 > GuardTrack.entrySpeed(25) } ?? 0
        let down = Self.descent[up...].firstIndex { $0 <= 25 } ?? 0
        let above = Self.descent[up ..< down].reduce(0, +)
        #expect(abs(d.tooFastDistanceM - above) / above < 0.02, "\(d.tooFastDistanceM) m of \(above) m")
        #expect(abs(q.distanceM + d.tooFastDistanceM - GuardTrack.distance(Self.descent)) < 10)
        #expect(Self.spans(d) == [0, 0, 0] && d.speedGateReinits == 0)
    }

    // MARK: Review fixes (S1–S3, N-a, N-d)

    struct NearLimit: CustomTestStringConvertible, Sendable {
        let name: String
        let profile: TrackProfile
        let ramps: [GuardTrack.Ramp]
        var testDescription: String { name }
    }

    /// Near the limit the filter's noise neither flaps the state nor loses distance (review S1): the state enters only
    /// above the entry speed (5 % or 0.6 m/s above the limit), and a refused step waits for the state, which never
    /// confirms here, so it counts. 20 seeds at a reported 5 and 8 m. Before: up to 25 episodes in 20 seeds and
    /// −621 m (a ride at 35.5 m/s), silent refusals in up to 11. Measured: none, within −7.6 … +10.1 m.
    @Test(arguments: [
        NearLimit(name: "run 12 s at 8.7 m/s", profile: .run,
                  ramps: [.hold(120, 3), Ramp(4, 3, 8.7), .hold(12, 8.7), Ramp(6, 8.7, 3), .hold(120, 3)]),
        NearLimit(name: "walk 60 s at 5.4 m/s", profile: .walk,
                  ramps: [.hold(120, 1.4), Ramp(5, 1.4, 5.4), .hold(60, 5.4), Ramp(5, 5.4, 1.4), .hold(120, 1.4)]),
        NearLimit(name: "MTB 60 s at 24.5 m/s", profile: .mtb,
                  ramps: [.hold(120, 8), Ramp(17, 8, 24.5), .hold(60, 24.5), Ramp(9, 24.5, 8), .hold(120, 8)]),
        NearLimit(name: "ride 60 s at 35.5 m/s", profile: .bike,
                  ramps: [.hold(120, 10), Ramp(25, 10, 35.5), .hold(60, 35.5), Ramp(13, 35.5, 10), .hold(120, 10)])
    ])
    func nearTheLimitNothingFlapsOrIsLost(_ near: NearLimit) {
        let speeds = GuardTrack.speeds(near.ramps)
        let truth = GuardTrack.distance(speeds)
        for accuracy in [5.0, 8.0] {
            for seed in UInt64(1) ... 20 {
                let (p, events) = GuardTrack.record(Self.noAutoPause(near.profile),
                                                    GuardTrack.fixes(speeds, accuracy: accuracy, seed: seed))
                #expect(GuardTrack.tooFast(events).isEmpty && p.diagnostics.tooFastSec == 0, "\(accuracy) m, seed \(seed)")
                #expect(abs(p.distanceM - truth) < 15, "\(accuracy) m, seed \(seed): \(p.distanceM - truth) m")
            }
        }
    }

    /// A burst above the entry speed shorter than 3 s is held and then released: it counts as distance, without an
    /// episode or a refused second; so does a burst still held when the user pauses or finishes, or in a checkpoint
    /// taken meanwhile. A burst of 3 s or more
    /// is the state, backdated to its first step, and what was held is refused.
    @Test func aShortBurstIsHeldAndReleased() throws {
        let short = GuardTrack.speeds([.hold(60, 3), Ramp(2, 3, 20), Ramp(2, 20, 3), .hold(60, 3)])
        let fixes = GuardTrack.fixes(short)
        let (p, events) = GuardTrack.record(Self.noAutoPause(.run), fixes)
        #expect(GuardTrack.tooFast(events).isEmpty && p.diagnostics.tooFastSec == 0)
        #expect(abs(p.distanceM - GuardTrack.distance(short)) < 1, "\(p.distanceM - GuardTrack.distance(short)) m")

        // Paused or finished while a step is held: it counts, as on a run without a limit.
        var unlimited = TrackProfile.run
        unlimited.maxSpeed = 100
        for finish in [false, true] {
            var held = TrackPipeline(configuration: Self.noAutoPause(.run))
            var free = TrackPipeline(configuration: Self.noAutoPause(unlimited))
            held.start(at: fixes[0].timestamp)
            free.start(at: fixes[0].timestamp)
            var heldAt: Int?
            for (i, fix) in fixes.enumerated() {
                let before = held.distanceM
                _ = held.ingest(fix)
                _ = free.ingest(fix)
                if i > 60, held.distanceM == before {
                    heldAt = i
                    break
                }
            }
            let at = try #require(heldAt)
            #expect(free.distanceM > held.distanceM + 5, "a step is held at fix \(at)")
            // A checkpoint now counts it too (review X3): a restore can't confirm it.
            let saved = try #require(held.checkpoint)
            #expect(abs(saved.distanceM - free.distanceM) < 0.01 && saved.diagnostics.tooFastSec == 0)
            #expect(free.distanceM > held.distanceM + 5, "taking the checkpoint changes nothing live")
            if finish {
                _ = held.finish(at: fixes[at].timestamp)
                _ = free.finish(at: fixes[at].timestamp)
            } else {
                held.pause(at: fixes[at].timestamp)
                free.pause(at: fixes[at].timestamp)
            }
            #expect(abs(held.distanceM - free.distanceM) < 0.01, "finish \(finish): \(held.distanceM) m, \(free.distanceM) m")
            #expect(held.diagnostics.tooFastSec == 0)
        }

        let long = GuardTrack.speeds([.hold(60, 3), Ramp(3, 3, 13), .hold(6, 13), Ramp(3, 13, 3), .hold(60, 3)])
        let (q, longEvents) = GuardTrack.record(Self.noAutoPause(.run), GuardTrack.fixes(long))
        let since = try #require(GuardTrack.tooFast(longEvents).first)
        let ended = try #require(GuardTrack.tooFastEnded(longEvents).first)
        #expect(abs(q.diagnostics.tooFastSec - ended.timeIntervalSince(since)) < 1e-6)
        #expect(abs(q.distanceM + q.diagnostics.tooFastDistanceM - GuardTrack.distance(long)) < 2)
    }

    /// Sliding multipath (review S2): offsets of 20–40 m that slide in 6–10 s or 10–20 s for 180 s, at a reported 10 m,
    /// are slow enough for the gates, so the filter's speed carries the slide. Core Location's Doppler speed doesn't
    /// move with multipath, and it has to agree before anything counts as too fast. 20 seeds per foot sport: no
    /// `.tooFast` (without Doppler: up to 33 episodes in 20 seeds for walkers).
    @Test(arguments: [
        Mover(name: "walk 1.4 m/s", profile: .walk, speed: 1.4),
        Mover(name: "hike 1.0 m/s", profile: .hike, speed: 1.0),
        Mover(name: "trail 2.2 m/s", profile: .trail, speed: 2.2),
        Mover(name: "run 3 m/s", profile: .run, speed: 3)
    ])
    func slidingMultipathIsNeverTooFastWithDoppler(_ mover: Mover) {
        let speeds = GuardTrack.speeds([.hold(400, mover.speed)])
        for hop in [6 ... 10, 10 ... 20] {
            for seed in UInt64(1) ... 20 {
                let clean = GuardTrack.fixes(speeds, seed: seed, doppler: .all)
                let sliding = GuardTrack.sliding(clean, from: 100, until: 280, hop: hop, seed: seed)
                let (p, events) = GuardTrack.record(Self.noAutoPause(mover.profile), sliding)
                #expect(GuardTrack.tooFast(events).isEmpty && p.diagnostics.tooFastSec == 0, "\(hop) s, seed \(seed)")
            }
        }
    }

    struct DopplerCase: CustomTestStringConvertible, Sendable {
        let name: String
        let speed: Double?
        let accuracy: Double?
        let tooFast: Bool
        var testDescription: String { name }
    }

    /// The Doppler speed decides only when it's valid, for steps and for settle windows: "running" on a bike at 15 m/s,
    /// from a standing start (steps) and a flying start (the first window). It agrees above 0.9 × the limit (8.1 m/s);
    /// a negative speed, a negative accuracy or one worse than 2 m/s (review X2) is no Doppler speed, and the filter
    /// decides alone.
    @Test(arguments: [
        DopplerCase(name: "Doppler 15 m/s agrees", speed: 15, accuracy: 0.5, tooFast: true),
        DopplerCase(name: "Doppler 8.5 m/s agrees (0.94 × the limit)", speed: 8.5, accuracy: 0.5, tooFast: true),
        DopplerCase(name: "Doppler 7.7 m/s vetoes (0.86 × the limit)", speed: 7.7, accuracy: 0.5, tooFast: false),
        DopplerCase(name: "Doppler 3 m/s, accuracy unknown, vetoes", speed: 3, accuracy: nil, tooFast: false),
        DopplerCase(name: "invalid speed: the filter decides", speed: -1, accuracy: 0.5, tooFast: true),
        DopplerCase(name: "invalid accuracy: the filter decides", speed: 3, accuracy: -1, tooFast: true),
        DopplerCase(name: "Doppler 3 m/s ± 1.9 m/s vetoes", speed: 3, accuracy: 1.9, tooFast: false),
        DopplerCase(name: "Doppler 3 m/s ± 2.1 m/s is too inaccurate: the filter decides", speed: 3, accuracy: 2.1,
                    tooFast: true)
    ])
    func dopplerDecidesWhenValid(_ doppler: DopplerCase) {
        let standing = GuardTrack.speeds([Ramp(15, 0, 15), .hold(120, 15)])
        let fixes = GuardTrack.fixes(standing).map { $0.with(speed: doppler.speed, accuracy: doppler.accuracy) }
        let (p, events) = GuardTrack.record(.gps(.run, barometer: false), fixes)
        #expect(!GuardTrack.tooFast(events).isEmpty == doppler.tooFast, "steps")
        if !doppler.tooFast {
            // Vetoed, it counts what a run without a limit counts.
            var unlimited = TrackProfile.run
            unlimited.maxSpeed = 100
            let free = GuardTrack.record(.gps(unlimited, barometer: false), fixes).pipeline.distanceM
            #expect(abs(p.distanceM - free) < 0.01 && free > 1800, "\(p.distanceM) m, unlimited \(free) m")
        }

        let flying = GuardTrack.fixes(GuardTrack.speeds([.hold(60, 15)])).map {
            $0.with(speed: doppler.speed, accuracy: doppler.accuracy)
        }
        var q = TrackPipeline(configuration: .gps(.run, barometer: false))
        for fix in flying[..<30] { _ = q.ingest(fix) }
        q.start(at: flying[30].timestamp)
        // The first window closes 10 s after Start: its line decides.
        let windowEvents = flying[30 ... 40].flatMap { q.ingest($0) }
        #expect(!GuardTrack.tooFast(windowEvents).isEmpty == doppler.tooFast, "window")
    }

    /// A ghost inside a settle window that has no anchor (review S3): Start's, or the one after a velocity reset.
    /// The window's start is the anchor, so its fixes aren't thrown away: a 3-fix ghost at 3, 6 and 9 s after Start is
    /// a chain bridged from the window's first position (before: −24, −33, −42 m).
    @Test(arguments: [3, 6, 9])
    func aGhostInTheStartWindowLosesNothing(at second: Int) {
        let speeds = GuardTrack.speeds([.hold(200, 3)])
        let ghost = GuardTrack.Ghost(from: second, count: 3, offset: GuardTrack.ghostOffsets[0])
        let (p, _) = GuardTrack.record(Self.noAutoPause(.run), GuardTrack.fixes(speeds, ghost: ghost))
        #expect(abs(p.distanceM - GuardTrack.distance(speeds)) < 1, "\(p.distanceM - GuardTrack.distance(speeds)) m")
        #expect(p.diagnostics.reinitialisations == 2 && Self.spans(p.diagnostics) == [0, 1, 0])
    }

    /// A single re-init inside Start's window is dead-reckoned at the window's line speed (5 fixes at 3 m/s before a
    /// 14-fix ghost); the way back from the ghost, anchored at its settled position, likewise.
    @Test func aLongGhostInTheStartWindowIsDeadReckoned() {
        let speeds = GuardTrack.speeds([.hold(200, 3)])
        let ghost = GuardTrack.Ghost(from: 5, count: 14, offset: GuardTrack.ghostOffsets[0])
        let (p, _) = GuardTrack.record(Self.noAutoPause(.run), GuardTrack.fixes(speeds, ghost: ghost))
        #expect(abs(p.distanceM - GuardTrack.distance(speeds)) < 1, "\(p.distanceM - GuardTrack.distance(speeds)) m")
        #expect(p.diagnostics.reinitialisations == 2 && Self.spans(p.diagnostics) == [2, 0, 0])
    }

    /// The same 4 s after a 20 s tunnel: the gap is bridged, the velocity reset opens a window, and a 3-fix ghost in
    /// it is a chain from the tunnel exit (before: −27 m).
    @Test func aGhostAfterATunnelLosesNothing() {
        let speeds = GuardTrack.speeds([.hold(200, 3)])
        let fixes = GuardTrack.fixes(speeds, ghost: GuardTrack.Ghost(from: 124, count: 3, offset: GuardTrack.ghostOffsets[0]))
        let (p, events) = GuardTrack.record(Self.noAutoPause(.run), Array(fixes[...100]) + Array(fixes[120...]))
        #expect(events.contains(.gap(seconds: 20, bridged: true)))
        #expect(abs(p.distanceM - GuardTrack.distance(speeds)) < 1, "\(p.distanceM - GuardTrack.distance(speeds)) m")
        #expect(Self.spans(p.diagnostics) == [0, 1, 0])
    }

    /// A pause or an auto-pause ends the too-fast state (review N-a). A car at 15 m/s stops hard; Core Location flags
    /// the phone stationary and stops sending fixes, so no slow steps arrive: the auto-pause ends it, from where the
    /// speed dropped. A manual pause while too fast ends it at the pause.
    @Test func pausesEndTheTooFastState() throws {
        let speeds = GuardTrack.speeds([.hold(60, 3), Ramp(10, 3, 15), .hold(60, 15), Ramp(4, 15, 0)])
        var fixes = GuardTrack.fixes(speeds)
        let last = try #require(fixes.last)
        fixes.append(LocationFix(timestamp: last.timestamp.addingTimeInterval(1), latitude: last.latitude,
                                 longitude: last.longitude, horizontalAccuracy: 5, isStationary: true))
        var p = TrackPipeline(configuration: .gps(.run, autoPause: true, barometer: false))
        p.start(at: fixes[0].timestamp)
        var events = fixes.flatMap { p.ingest($0) }
        #expect(p.tooFastSince != nil, "no slow steps confirmed the end")
        let end = try #require(fixes.last).timestamp
        for second in 1 ... 10 { events += p.advance(to: end.addingTimeInterval(Double(second))) }
        let ended = try #require(GuardTrack.tooFastEnded(events).first)
        let paused = try #require(events.compactMap { if case let .autoPaused(since) = $0 { since } else { nil } }.first)
        // From the first slow step of the stop, before the stationary fix the auto-pause starts at.
        #expect(ended < paused && ended > end.addingTimeInterval(-6))
        #expect(p.state == .autoPaused && p.snapshot(at: end.addingTimeInterval(10)).tooFastSince == nil)

        let cruise = GuardTrack.fixes(GuardTrack.speeds([.hold(60, 3), Ramp(10, 3, 15), .hold(60, 15)]))
        var q = TrackPipeline(configuration: Self.noAutoPause(.run))
        q.start(at: cruise[0].timestamp)
        _ = SyntheticTrack.run(&q, cruise)
        #expect(q.tooFastSince != nil)
        let pauseAt = try #require(cruise.last).timestamp
        #expect(q.pause(at: pauseAt).contains(.tooFastEnded(since: pauseAt)))
        #expect(q.tooFastSince == nil)
    }

    /// A checkpoint taken while a chain is open counts its anchor as dropped (review N-d): a restore can't fill the
    /// span, and each anchor ends exactly once in the restored counts. The live pipeline still bridges it.
    @Test func aCheckpointCountsAnOpenAnchorAsDropped() throws {
        let speeds = GuardTrack.speeds([.hold(200, 3)])
        let fixes = GuardTrack.fixes(speeds, ghost: GuardTrack.Ghost(from: 100, count: 3, offset: GuardTrack.ghostOffsets[0]))
        var p = TrackPipeline(configuration: Self.noAutoPause(.run))
        p.start(at: fixes[0].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes[...106]))
        let saved = try #require(p.checkpoint)
        #expect(saved.diagnostics.reinitialisations == 2 && Self.spans(saved.diagnostics) == [0, 0, 1])
        #expect(Self.spans(p.diagnostics) == [0, 0, 0])
        let restored = TrackPipeline(configuration: Self.noAutoPause(.run), restoring: saved,
                                     interruptedAt: fixes[106].timestamp)
        #expect(Self.spans(restored.diagnostics) == [0, 0, 1])
        _ = SyntheticTrack.run(&p, Array(fixes[107...]))
        let later = try #require(p.checkpoint)
        #expect(Self.spans(p.diagnostics) == [0, 1, 0] && Self.spans(later.diagnostics) == [0, 1, 0])
    }

    /// A fast window closed early by Pause is judged like one that closes on its own (6 s of a flying start at 15 m/s
    /// on "running"): it's the state, refused, and the pause then ends it. Nothing is released as distance.
    @Test func aFastWindowClosedByPauseIsRefused() throws {
        let fixes = GuardTrack.fixes(GuardTrack.speeds([.hold(60, 15)]))
        var p = TrackPipeline(configuration: Self.noAutoPause(.run))
        for fix in fixes[..<30] { _ = p.ingest(fix) }
        p.start(at: fixes[30].timestamp)
        _ = SyntheticTrack.run(&p, Array(fixes[30 ... 36]))
        #expect(p.distanceM == 0 && p.tooFastSince == nil)
        let events = p.pause(at: fixes[36].timestamp)
        #expect(GuardTrack.tooFast(events) == [fixes[30].timestamp])
        #expect(GuardTrack.tooFastEnded(events) == [fixes[36].timestamp])
        #expect(p.distanceM == 0 && p.diagnostics.tooFastSec > 5)
    }

    struct Entry: CustomTestStringConvertible, Sendable {
        let name: String
        let profile: TrackProfile
        let start: Double
        let speed: Double
        let tooFast: Bool
        var testDescription: String { name }
    }

    /// The entry speed is the larger of 5 % and 0.6 m/s above the limit: 9.6 m/s for a run (the margin), 26.25 m/s
    /// for mountain biking (the factor). Noiseless, after a gentle ramp: just below it, no episode and every metre
    /// counts; just above it, one episode.
    @Test(arguments: [
        Entry(name: "run at 9.5", profile: .run, start: 3, speed: 9.5, tooFast: false),
        Entry(name: "run at 9.75", profile: .run, start: 3, speed: 9.75, tooFast: true),
        Entry(name: "MTB at 26.0", profile: .mtb, start: 10, speed: 26.0, tooFast: false),
        Entry(name: "MTB at 26.5", profile: .mtb, start: 10, speed: 26.5, tooFast: true)
    ])
    func theEntrySpeedIsTheLargerMargin(_ entry: Entry) {
        let speeds = GuardTrack.speeds([.hold(60, entry.start), Ramp(30, entry.start, entry.speed), .hold(60, entry.speed),
                                        Ramp(30, entry.speed, entry.start), .hold(60, entry.start)])
        let (p, events) = GuardTrack.record(Self.noAutoPause(entry.profile), GuardTrack.fixes(speeds))
        #expect(GuardTrack.tooFast(events).count == (entry.tooFast ? 1 : 0))
        if !entry.tooFast {
            #expect(abs(p.distanceM - GuardTrack.distance(speeds)) < 2, "\(p.distanceM - GuardTrack.distance(speeds)) m")
        }
    }

    /// Doppler missing on some fixes (review X1): a fix without a usable Doppler speed takes the last one for up to 8 s,
    /// raised by 0.5 m/s² for its age, so the veto doesn't fail open on every gap. Sliding multipath (6–10 s slides,
    /// 20 seeds × walk, hike, trail, run): with Doppler on 70 % of the fixes no false episode; on 30 % at most 4 in 80
    /// runs; in 5-fix gaps (about 40 % missing) at most 8. Measured 0, 2 and 5; failing open: 4, 34 and 49.
    @Test(arguments: [70, 30, 0])
    func partialDopplerStillVetoesSlidingMultipath(percent: Int) {
        let doppler: GuardTrack.Doppler = percent == 0 ? .gaps(5, share: 0.7) : .share(Double(percent) / 100)
        let bound = [70: 0, 30: 4, 0: 8][percent] ?? 0
        var episodes = 0
        for mover in [Mover(name: "walk", profile: .walk, speed: 1.4), Mover(name: "hike", profile: .hike, speed: 1.0),
                      Mover(name: "trail", profile: .trail, speed: 2.2), Mover(name: "run", profile: .run, speed: 3)] {
            for seed in UInt64(1) ... 20 {
                let clean = GuardTrack.fixes(GuardTrack.speeds([.hold(400, mover.speed)]), seed: seed, doppler: doppler)
                let sliding = GuardTrack.sliding(clean, from: 100, until: 280, hop: 6 ... 10, seed: seed)
                episodes += GuardTrack.tooFast(GuardTrack.record(Self.noAutoPause(mover.profile), sliding).events).count
            }
        }
        #expect(episodes <= bound, "\(episodes) false episodes in 80 runs")
    }

    /// The held-over Doppler speed never holds back a real acceleration: with Doppler on 30 % of the fixes, or missing
    /// in 5-fix gaps, the train after a run stays within 135 m and "running" on a bike says `.tooFast` within 4 s of
    /// passing 9 m/s, over 20 seeds. Without the age allowance a stale reading from the slow start vetoed them: +171 m
    /// and 7 s late. Measured: +112 … +127 m, +2 … +3 s.
    @Test(arguments: [30, 0])
    func aHeldOverDopplerSpeedDoesNotHoldBackAnAcceleration(percent: Int) throws {
        let doppler: GuardTrack.Doppler = percent == 0 ? .gaps(5, share: 0.7) : .share(Double(percent) / 100)
        let run = GuardTrack.speeds([.hold(300, 3), Ramp(2, 3, 0)])
        let train = GuardTrack.speeds([.hold(120, 0), Ramp(47, 0, 33), .hold(300, 33), Ramp(33, 33, 0), .hold(60, 0)])
        let bike = GuardTrack.speeds([Ramp(15, 0, 15), .hold(120, 15)])
        let passes = try #require(GuardTrack.crossings(bike, limit: 9)).above
        for seed in UInt64(1) ... 20 {
            let ride = GuardTrack.record(.gps(.run, barometer: false),
                                         GuardTrack.fixes(run + train, seed: seed, doppler: doppler)).pipeline
            let still = run + Array(repeating: 0.0, count: train.count)
            let baseline = GuardTrack.record(.gps(.run, barometer: false),
                                             GuardTrack.fixes(still, seed: seed, doppler: doppler)).pipeline
            #expect(ride.distanceM - baseline.distanceM <= 135, "seed \(seed): +\(ride.distanceM - baseline.distanceM) m")
            let events = GuardTrack.record(.gps(.run, barometer: false), GuardTrack.fixes(bike, seed: seed, doppler: doppler)).events
            let since = try #require(GuardTrack.tooFast(events).first, "seed \(seed)")
            #expect(since.timeIntervalSince(passes) <= 4, "seed \(seed): \(since.timeIntervalSince(passes)) s")
        }
    }

    /// Doppler vetoes entering the state only: during a real episode the filter's speed decides when steps count again,
    /// so braking doesn't add the filter's lag (Doppler falls below the limit first). The train with Doppler on every
    /// fix adds what it adds without (noiseless +128 m at 5 m); vetoing in the episode too added up to +141 m.
    @Test func dopplerDoesNotEndAnEpisode() throws {
        let run = GuardTrack.speeds([.hold(300, 3), Ramp(2, 3, 0)])
        let train = GuardTrack.speeds([.hold(120, 0), Ramp(47, 0, 33), .hold(300, 33), Ramp(33, 33, 0), .hold(60, 0)])
        let without = GuardTrack.record(.gps(.run, barometer: false), GuardTrack.fixes(run + train)).pipeline
        let with = GuardTrack.record(.gps(.run, barometer: false), GuardTrack.fixes(run + train, doppler: .all)).pipeline
        #expect(abs(with.distanceM - without.distanceM) < 0.5, "\(with.distanceM) m, without Doppler \(without.distanceM) m")
        #expect(with.diagnostics.tooFastEpisodes == 1)
    }

    /// A step is judged by its mean ground speed also in the 10 s of position steps after an auto-resume (review X4): a
    /// runner stops for 30 s, then a ride pulls away at 1.5 m/s² to 15 m/s. The entry speed is crossed inside that
    /// window; judged by the speed at the step's end, the state would start a second earlier (98 s) and 13 m more
    /// would be refused.
    @Test func positionStepsAreJudgedByTheirMeanSpeed() throws {
        let speeds = GuardTrack.speeds([.hold(60, 3), .hold(30, 0), Ramp(10, 0, 15), .hold(30, 15)])
        let (p, events) = GuardTrack.record(.gps(.run, autoPause: true, barometer: false), GuardTrack.fixes(speeds))
        let resumed = try #require(events.compactMap { if case let .autoResumed(since) = $0 { since } else { nil } }.first)
        let since = try #require(GuardTrack.tooFast(events).first)
        #expect(since.timeIntervalSince(resumed) < 10, "inside the position steps")
        #expect(since == SyntheticTrack.t0.addingTimeInterval(99))
        #expect(abs(p.distanceM - 239.1) < 1, "\(p.distanceM) m")
    }
}
