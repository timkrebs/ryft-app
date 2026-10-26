import Foundation

/// Why the pipeline dropped a fix (design §3.3 steps 1–3).
enum FixRejection: String, Codable, Sendable {
    /// Invalid, or worse than 25 m.
    case accuracy
    /// Not after the last accepted fix.
    case outOfOrder
    /// More than 10 s older than the newest time the pipeline has seen.
    case stale
    /// Implies a change of velocity above the sport's maximum: the jump from the filter's predicted position.
    case implausible
    /// Beyond the Kalman filter's innovation gate.
    case innovation
}

/// The GPS indicator (design §3.7): good ≤ 10 m, fair ≤ 25 m, weak (no fix for 10 s), off (no GPS).
enum GPSQuality: String, Codable, Sendable {
    case good, fair, weak, off
}

/// A distance split (design §3.3 step 7). Maps field for field to the wire's `ActivitySplit`
/// (`index`, `distance_m`, `duration_sec`, `ascent_m`); `end` stays on the device.
struct TrackSplit: Codable, Equatable, Sendable {
    /// 1-based: the first kilometre is split 1.
    let index: Int
    /// 1000 m, or the real distance of the partial last split.
    let distanceM: Double
    /// Moving time in the split, seconds.
    let durationSec: Double
    /// Ascent in the split, metres; nil without elevation.
    let ascentM: Double?
    /// When the split was crossed (interpolated between two filtered points) or finished.
    let end: Date
}

/// A pause of the recording. Moving time is elapsed time minus these.
struct PauseInterval: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The user paused.
        case manual
        /// Auto-pause, from the moment the user stopped (backdated) to the moment they moved again (backdated).
        case auto
        /// The app was killed: the time from the last checkpoint to the resume (never bridged, design §3.9).
        case interruption
    }

    let kind: Kind
    let start: Date
    /// Nil while the pause is open.
    var end: Date?
}

/// A lap the user marked (local only, design §13 R7).
struct TrackLap: Codable, Equatable, Sendable {
    let index: Int
    let start: Date
    let end: Date
    let distanceM: Double
    let movingSec: Double
}

/// What one input produced, in order.
enum PipelineEvent: Sendable, Equatable {
    /// The filtered position of an accepted fix (only after Start).
    case route(RoutePoint)
    /// The profile after an accepted fix or pedometer sample (only after Start).
    case profile(ProfilePoint)
    case rejected(FixRejection)
    /// The filter restarted at this fix (three rejections in a row, by either gate); the jump adds no distance. The
    /// re-init is provisional: when its settle window closes, the rejected span is filled from the last settled
    /// position (design §3.3 step 4).
    case reinitialised
    /// Δt over 10 s between accepted fixes; `bridged` when the straight line was counted.
    case gap(seconds: Double, bridged: Bool)
    case split(TrackSplit)
    /// Auto-pause entered; the pause starts at `since` (when the user stopped).
    case autoPaused(since: Date)
    /// Auto-pause left; the pause ends at `since` (when the user started moving).
    case autoResumed(since: Date)
    /// The filter's ground speed has been above the sport's limit for 3 s, since `since` (the first fast step):
    /// no distance, no route points, no current pace or speed. Not a pause: the time runs on (design §3.3 "Too fast").
    case tooFast(since: Date)
    /// 3 s at or below the limit again, since `since` (the first slow step).
    case tooFastEnded(since: Date)
}

/// Counts only: never a coordinate (design §3.3, §8.3). Part of `RecordingDiagnostics` and the checkpoint.
struct PipelineDiagnostics: Codable, Equatable, Sendable {
    var fixesAccepted = 0
    var rejectedAccuracy = 0
    var rejectedOutOfOrder = 0
    var rejectedStale = 0
    var rejectedImplausible = 0
    var rejectedInnovation = 0
    var reinitialisations = 0
    var gapsBridged = 0
    var gapsNotBridged = 0
    var longestGapSec: Double = 0
    var autoPauses = 0
    var pedometerSamples = 0
    /// Re-inits whose rejected run included a speed-gate rejection.
    var speedGateReinits = 0
    /// What each provisional re-init's span became (design §3.3 step 4); each anchor ends as exactly one of these.
    /// Dead-reckoned at the anchor's speed (one re-init, at most 10 s).
    var reinitSpansDeadReckoned = 0
    /// The straight line from the anchor counted (a chain, or a longer span).
    var reinitSpansBridged = 0
    /// Nothing added: the speed was below the dead-band or above the sport's limit, or Pause, a resume, Finish or a
    /// gap inside the window dropped the anchor.
    var reinitSpansDropped = 0
    /// Times the too-fast state was entered (`.tooFast`).
    var tooFastEpisodes = 0
    /// Seconds the sport's limit refused: steps, settle windows and spans faster than `maxSpeed`.
    var tooFastSec: Double = 0
    /// The filter's speed integrated over those seconds. Never distance, never saved or shown as distance: a number
    /// for device tuning (D1) and a later "change sport".
    var tooFastDistanceM: Double = 0

    var rejected: Int {
        rejectedAccuracy + rejectedOutOfOrder + rejectedStale + rejectedImplausible + rejectedInnovation
    }

    fileprivate mutating func count(_ reason: FixRejection) {
        switch reason {
        case .accuracy: rejectedAccuracy += 1
        case .outOfOrder: rejectedOutOfOrder += 1
        case .stale: rejectedStale += 1
        case .implausible: rejectedImplausible += 1
        case .innovation: rejectedInnovation += 1
        }
    }
}

/// The values a recording screen shows (design §3.7, the pipeline's part of `RecorderSnapshot`).
struct TrackSnapshot: Sendable, Equatable {
    let state: TrackPipeline.State
    let movingSec: Double
    let elapsedSec: Double
    let distanceM: Double
    /// Seconds per km over the last 30 s of moving time; nil while stabilising, below 20 m, or not recording.
    let currentPace: Double?
    /// Seconds per km: moving time over distance; nil below 20 m.
    let averagePace: Double?
    /// Metres per second over the same 30 s window (cycling shows speed).
    let currentSpeed: Double?
    let averageSpeed: Double?
    let ascentM: Double?
    let descentM: Double?
    let altitudeM: Double?
    let steps: Int?
    let lastSplit: TrackSplit?
    let gps: GPSQuality
    /// `now − movingSec` while recording, so a clock can tick on its own; nil otherwise.
    let movingAnchor: Date?
    /// Since when the filter's speed is above the sport's limit (`.tooFast`); nil otherwise. Distance pauses
    /// meanwhile, and the current pace and speed are nil.
    let tooFastSince: Date?
}

/// The location pipeline (design §3.3, ADR 0003): gates, the Kalman filter, distance, gaps, rolling pace, splits
/// and auto-pause, plus elevation (§3.4) and pedometer distance (§3.5).
///
/// Distance integrates the filter's ground speed between accepted fixes while recording and moving (above the
/// sport's dead-band, not flagged stationary); gaps over 10 s are bridged by the straight line when the implied speed
/// is plausible (`Tuning.distanceFromVelocity` explains why not position steps). After the filter (re)starts or
/// resets its velocity, the first 10 s settle as a whole at their end (`Tuning.settleWindow`). A re-init is
/// provisional: when its window closes, the rejected span is filled from the last settled position (`Anchor`). A
/// step faster than the sport's limit adds nothing, and 3 s of them are the too-fast state. Auto-pause is
/// backdated: it starts when the user stopped and ends when they moved again, so the 10 s and 3 s confirmations are
/// neither moving time nor lost distance, and the snapshot's clock holds while one is pending.
///
/// A pure value type: the recorder actor owns one and feeds it fixes, altitude and pedometer samples and its
/// control calls with their times. It reads no clock, so tests drive it with fixture arrays on the fixes' own
/// timestamps. Every time it is given counts as "now seen" for the 10 s staleness rule.
struct TrackPipeline: Sendable {
    enum State: String, Codable, Sendable {
        /// Before Start: fixes warm the filter and the GPS indicator; nothing is recorded.
        case ready
        case recording
        case autoPaused
        case paused
        case finished
    }

    enum DistanceSource: String, Codable, Sendable {
        case gps
        /// Indoor runs, or foot sports recorded without location (design §3.5, §3.10).
        case pedometer
        case none
    }

    /// Every number of design §3.3 in one place, for tests and device tuning (D1).
    struct Tuning: Sendable, Equatable {
        var maxAccuracy = 25.0
        var staleAfter: TimeInterval = 10
        var minSpeedGateInterval: TimeInterval = 1
        /// The floor of the moving gate, m/s (design §3.3 step 4).
        var minMovingSpeed = 0.3
        /// The still-phone dead-band, the backstop behind Core Location's stationary flag: a step counts only from
        /// this share of the sport's auto-pause threshold, between `minMovingSpeed` and `maxDeadBand`. A drifting
        /// fix on a still phone reads as slow motion; runners and riders are never that slow, walkers and hikers can
        /// be, so their sports keep the floor and rely on the flag.
        var deadBandShareOfAutoPause = 0.5
        var maxDeadBand = 0.5
        var gapAfter: TimeInterval = 10
        var paceWindow: TimeInterval = 30
        var paceMinDistance = 20.0
        var paceMinDuration: TimeInterval = 10
        var splitDistance = 1000.0
        /// A partial last split shorter than this share of a split isn't added at Finish: at a round-number finish
        /// the remainder is GPS overshoot, not a split. Its distance and time stay in the totals.
        var minPartialSplitFraction = 0.05
        var autoPauseAfter: TimeInterval = 10
        var autoPauseStationaryAfter: TimeInterval = 5
        var autoResumeAfter: TimeInterval = 3
        var autoResumeFactor = 1.5
        var weakAfter: TimeInterval = 10
        var goodAccuracy = 10.0
        /// Distance from the filter's ground speed (trapezoid between fixes) rather than from the steps between
        /// filtered positions (ADR 0003 as written). Gaps are bridged by the straight line either way. On the
        /// fixtures, position steps read 1–4 % long under canopy: measurement jitter reaches the position through the
        /// filter's position gain, and a lagging estimate overshoots a hairpin and comes back, which a position sum
        /// counts twice. The velocity state takes far less jitter and doesn't double back. Its lag behind an
        /// acceleration is covered by the settle window (a start) and the auto-resume position steps (after a stop).
        var distanceFromVelocity = true
        /// After the user moves off from an auto-pause, distance comes from position steps for this long: the filter
        /// is settled, and the steps recover its velocity's lag behind the acceleration, which integrating the
        /// velocity would lose.
        var positionStepsAfterRestart: TimeInterval = 10
        /// After the filter starts or restarts (Start, a resume after a kill, a real jump), the first fix may be tens
        /// of metres off and the filter's way back from it isn't distance. So nothing accrues for this long; then the
        /// window's distance is a robust (Theil–Sen) line through its fixes: a flying start keeps its speed, one bad
        /// fix tilts nothing. With fewer than `settleMinFixes` fixes it waits up to 3× as long.
        var settleWindow: TimeInterval = 10
        var settleMinFixes = 4
        /// A provisional re-init with one re-init and its anchor at most this long before it is dead-reckoned at the
        /// anchor's speed; a chain or a longer span takes the gap rule's straight line (ADR 0003 amendment 2).
        var maxDeadReckoning: TimeInterval = 10
        /// This long above the sport's limit enters the too-fast state, and this long at or below it leaves.
        var tooFastAfter: TimeInterval = 3

        static let standard = Tuning()
    }

    struct Configuration: Sendable, Equatable {
        var profile: TrackProfile
        var autoPause: Bool
        var distance: DistanceSource
        var elevation: ElevationFusion.Mode
        var tuning: Tuning = .standard

        /// An outdoor GPS recording. Elevation per design §3.4: barometric when the altimeter is usable for this
        /// sport (`barometer`: primary sports, or secondary ones with Motion allowed), else GPS altitude.
        static func gps(_ profile: TrackProfile, autoPause: Bool? = nil, barometer: Bool,
                        tuning: Tuning = .standard) -> Configuration {
            let mode: ElevationFusion.Mode = switch profile.elevation {
            case .none: .none
            case .primary, .secondary: barometer ? .barometric : .gps
            }
            return Configuration(profile: profile, autoPause: autoPause ?? profile.autoPauseDefault,
                                 distance: .gps, elevation: mode, tuning: tuning)
        }

        /// A recording without GPS: pedometer distance (indoor run, or a foot sport without location) or none.
        static func indoor(_ profile: TrackProfile, autoPause: Bool? = nil, pedometer: Bool,
                           tuning: Tuning = .standard) -> Configuration {
            Configuration(profile: profile, autoPause: autoPause ?? profile.autoPauseDefault,
                          distance: pedometer ? .pedometer : .none, elevation: .none, tuning: tuning)
        }
    }

    /// What a checkpoint keeps of the pipeline (part of `RecordingHeader`, design §3.9). No coordinate: no Kalman
    /// anchor, no last position. A restored pipeline re-initialises its filter at the first new fix, and the time
    /// from the last checkpoint to the resume is a pause that adds no distance.
    struct Resume: Codable, Equatable, Sendable {
        var start: Date
        var pauses: [PauseInterval]
        var distanceM: Double
        var splits: [TrackSplit]
        var splitStartMovingSec: Double
        var splitStartAscentM: Double
        /// Nil until an altitude was counted.
        var ascentM: Double?
        var descentM: Double?
        var laps: [TrackLap]
        var lapStartDistanceM: Double
        var lastSampleTime: Date?
        var pedometerDistanceM: Double?
        var pedometerSteps: Int?
        var diagnostics: PipelineDiagnostics
    }

    private struct PaceSample: Sendable {
        let time: Date
        var moving: Double
        let distance: Double
    }

    private struct Step: Sendable {
        let from: Date
        let to: Date
        let distance: Double
        /// What the sport's limit refused: the length of a step, window or span faster than `maxSpeed`. Never
        /// distance; `PipelineDiagnostics.tooFastSec` and `tooFastDistanceM` count it.
        var refused: Double = 0
    }

    /// The last settled point before a provisional re-init (ADR 0003 amendment 2, decision 4): the filtered
    /// position, its time and its ground speed. Memory only, never checkpointed; its coordinate renders nothing.
    private struct Anchor: Sendable {
        let position: Coordinate
        let time: Date
        let speed: Double
        /// Re-inits since the anchor; two or more before a window closes are a chain.
        var reinits: Int
    }

    /// The fixes since the filter (re)started, held until the settle window ends. Memory only, never checkpointed.
    private struct Settling: Sendable {
        let since: Date
        var fixes: [(time: Date, coordinate: Coordinate, isStationary: Bool)]
        /// The filtered track's length over the window, from `firstFiltered` to `lastFiltered`.
        var path: Double = 0
        var firstFiltered: Coordinate?
        var lastFiltered: Coordinate?
    }

    private struct PedometerReading: Sendable {
        let time: Date
        let distance: Double
        let steps: Int
    }

    let configuration: Configuration
    private var tuning: Tuning { configuration.tuning }

    private(set) var state: State = .ready
    private(set) var start: Date?
    private(set) var finishedAt: Date?
    /// Sorted and disjoint; only the last can be open. Changed only through `openPause` and `closeOpenPause`.
    private(set) var pauses: [PauseInterval] = []
    /// `pausedBefore[i]`: the total length of `pauses[0 ..< i]`, kept as pauses open and close (O(1) each).
    private var pausedBefore: [Double] = [0]
    private(set) var distanceM: Double = 0
    private(set) var splits: [TrackSplit] = []
    private(set) var laps: [TrackLap] = []
    private(set) var diagnostics = PipelineDiagnostics()
    /// The accuracy of the newest fix, accepted or not (pre-start shows it: "Ready" at ≤ 20 m).
    private(set) var lastReportedAccuracy: Double?

    private var kalman: KalmanTrack
    private var elevation: ElevationFusion
    private var latestSeen: Date?
    private var lastAccepted: (time: Date, accuracy: Double, isStationary: Bool)?
    /// The filtered position distance steps start from; nil after a resume, so nothing is bridged across a pause.
    private var stepFrom: (position: Coordinate, time: Date, speed: Double)?
    /// Until this time, distance comes from position steps (`Tuning.positionStepsAfterRestart`).
    private var positionStepsUntil: Date?
    /// Set while the filter settles after a (re)start (`Tuning.settleWindow`).
    private var settling: Settling?

    private var splitStartMoving: Double = 0
    private var splitStartAscent: Double = 0
    private var lapStartDistance: Double = 0
    private var paceSamples: [PaceSample] = []

    private var slowSince: Date?
    private var stationarySince: Date?
    private var fastSince: Date?
    private var pending: [Step] = []

    private var pedometer: PedometerReading?
    private var lastStepping: Date?

    /// Set from a provisional re-init until its settle window closes; then its span is filled. Only while recording or
    /// auto-paused, so Start never finds one, and Pause, a resume and Finish drop it.
    private var anchor: Anchor?
    /// Whether the current run of rejections included a speed-gate rejection (`speedGateReinits`).
    private var rejectedRunHadSpeedGate = false
    /// Since when the filter's speed is above the sport's limit (`.tooFast`); nil otherwise. Judged only while
    /// recording; Pause and a resume keep it.
    private(set) var tooFastSince: Date?
    /// The first step on the other side of the limit than the state, not yet confirmed by `Tuning.tooFastAfter`.
    private var limitCrossedAt: Date?

    init(configuration: Configuration) {
        self.configuration = configuration
        kalman = KalmanTrack(tuning: KalmanTrack.Tuning(sigmaA: configuration.profile.sigmaA ?? 1.5))
        elevation = ElevationFusion(mode: configuration.elevation)
        elevation.setCounting(false)
    }

    /// Rebuilds a pipeline from a checkpoint. It starts paused: an open manual pause stays; otherwise the time from
    /// `interruptedAt` (the last checkpoint) is an interruption pause until `resume(at:)` or `finish(at:)`.
    init(configuration: Configuration, restoring saved: Resume, interruptedAt: Date) {
        self.init(configuration: configuration)
        start = saved.start
        distanceM = saved.distanceM
        splits = saved.splits
        splitStartMoving = saved.splitStartMovingSec
        splitStartAscent = saved.splitStartAscentM
        laps = saved.laps
        lapStartDistance = saved.lapStartDistanceM
        diagnostics = saved.diagnostics
        elevation = ElevationFusion(mode: configuration.elevation, ascentM: saved.ascentM, descentM: saved.descentM)
        elevation.setCounting(false)
        pauses = saved.pauses
        pausedBefore = Self.prefixSums(pauses)
        if let distance = saved.pedometerDistanceM, let steps = saved.pedometerSteps {
            pedometer = PedometerReading(time: saved.lastSampleTime ?? interruptedAt, distance: distance, steps: steps)
        }
        let resumeFrom = max(interruptedAt, saved.start)
        if let last = pauses.last, last.end == nil {
            if last.kind != .manual {
                closeOpenPause(at: resumeFrom)
                openPause(.interruption, at: resumeFrom)
            }
        } else {
            openPause(.interruption, at: resumeFrom)
        }
        state = .paused
        latestSeen = resumeFrom
    }

    // MARK: - Reads

    var ascentM: Double? { elevation.ascent }
    var descentM: Double? { elevation.descent }
    var altitudeM: Double? { elevation.altitudeM }
    var steps: Int? { pedometer?.steps }
    /// Samples held besides the output (splits, laps, pauses): bounded by time windows, never by the recording's
    /// length. Every input touches only these, plus an O(log pauses) search: O(1) per input. For the cost test.
    var retainedSampleCount: Int {
        paceSamples.count + pending.count + (settling?.fixes.count ?? 0) + elevation.retainedSampleCount
    }
    /// The speed a step needs to count: the dead-band for this sport (`Tuning.deadBandShareOfAutoPause`).
    var movingSpeed: Double {
        let share = tuning.deadBandShareOfAutoPause * (configuration.profile.autoPauseThreshold ?? 0)
        return max(tuning.minMovingSpeed, min(tuning.maxDeadBand, share))
    }

    private var autoPauseEnabled: Bool {
        guard configuration.autoPause else { return false }
        switch configuration.distance {
        case .gps: return configuration.profile.autoPauseThreshold != nil
        case .pedometer: return true
        case .none: return false
        }
    }

    /// The checkpoint state (part of `RecordingHeader`); nil before Start.
    var checkpoint: Resume? {
        guard let start else { return nil }
        return Resume(start: start, pauses: pauses, distanceM: distanceM, splits: splits,
                      splitStartMovingSec: splitStartMoving, splitStartAscentM: splitStartAscent,
                      ascentM: elevation.ascent, descentM: elevation.descent, laps: laps,
                      lapStartDistanceM: lapStartDistance, lastSampleTime: lastAccepted?.time ?? pedometer?.time,
                      pedometerDistanceM: pedometer?.distance, pedometerSteps: pedometer?.steps,
                      diagnostics: diagnostics)
    }

    /// Elapsed time minus every pause, up to `time` (and never past Finish). O(log pauses): pauses are sorted and
    /// disjoint, and the closed ones are summed as they close.
    func movingTime(at time: Date) -> Double {
        guard let start else { return 0 }
        let t = min(time, finishedAt ?? time)
        guard t > start else { return 0 }
        var lo = 0, hi = pauses.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if pauses[mid].start < t { lo = mid + 1 } else { hi = mid }
        }
        var paused = 0.0
        if lo > 0 {
            let last = pauses[lo - 1]
            paused = pausedBefore[lo - 1]
            let to = min(last.end ?? t, t)
            if to > last.start { paused += to.timeIntervalSince(last.start) }
        }
        return max(0, t.timeIntervalSince(start) - paused)
    }

    func elapsedTime(at time: Date) -> Double {
        guard let start else { return 0 }
        return max(0, min(time, finishedAt ?? time).timeIntervalSince(start))
    }

    /// Seconds per km over the last 30 s of moving time (design §3.3 step 6); nil unless recording with ≥ 10 s and
    /// ≥ 20 m in the window.
    var currentPace: Double? {
        guard let speed = currentSpeed, speed > 0 else { return nil }
        return 1000 / speed
    }

    /// Metres per second over the last 30 s of moving time; nil unless recording with ≥ 10 s and ≥ 20 m, and nil while
    /// too fast (the window's distance stands still then).
    var currentSpeed: Double? {
        guard state == .recording, tooFastSince == nil, let last = paceSamples.last, let first = paceSamples.first
        else { return nil }
        let windowStart = last.moving - tuning.paceWindow
        var then = (moving: first.moving, distance: first.distance)
        if first.moving < windowStart {
            for (a, b) in zip(paceSamples, paceSamples.dropFirst()) where a.moving <= windowStart && b.moving >= windowStart {
                let span = b.moving - a.moving
                let f = span > 0 ? (windowStart - a.moving) / span : 1
                then = (windowStart, a.distance + f * (b.distance - a.distance))
                break
            }
        }
        let dt = last.moving - then.moving, dd = last.distance - then.distance
        guard dt >= tuning.paceMinDuration, dd >= tuning.paceMinDistance else { return nil }
        return dd / dt
    }

    func averagePace(at time: Date) -> Double? {
        let moving = movingTime(at: time)
        guard distanceM >= tuning.paceMinDistance, moving > 0 else { return nil }
        return moving / distanceM * 1000
    }

    func gpsQuality(at time: Date) -> GPSQuality {
        guard configuration.distance == .gps else { return .off }
        guard let last = lastAccepted else { return .weak }
        // A chain of re-inits is open: the fixes disagree with each other ("Distance may be low", ui.md G4).
        if let anchor, anchor.reinits >= 2 { return .weak }
        if time.timeIntervalSince(last.time) > tuning.weakAfter, !last.isStationary { return .weak }
        return last.accuracy <= tuning.goodAccuracy ? .good : .fair
    }

    /// When an auto-pause is pending: the first slow, stationary or step-less input that hasn't been confirmed or
    /// denied yet. Nil when auto-pause is off, not recording, or the GPS turned weak meanwhile.
    func pendingAutoPause(at time: Date) -> Date? {
        guard state == .recording, autoPauseEnabled else { return nil }
        switch configuration.distance {
        case .gps:
            guard gpsQuality(at: time) != .weak else { return nil }
            return [slowSince, stationarySince].compactMap { $0 }.min()
        case .pedometer:
            guard let since = lastStepping, time.timeIntervalSince(since) >= tuning.autoResumeAfter else { return nil }
            return since
        case .none:
            return nil
        }
    }

    /// The screen's values. While an auto-pause is pending the clock holds at its start (no moving anchor), so a
    /// confirmed auto-pause, backdated to that moment, never moves the shown time back (design §3.3, ui.md G3).
    func snapshot(at time: Date) -> TrackSnapshot {
        let held = pendingAutoPause(at: time)
        let moving = movingTime(at: held ?? time)
        let average = averagePace(at: time)
        return TrackSnapshot(
            state: state, movingSec: moving, elapsedSec: elapsedTime(at: time), distanceM: distanceM,
            currentPace: currentPace, averagePace: average, currentSpeed: currentSpeed,
            averageSpeed: average.flatMap { $0 > 0 ? 1000 / $0 : nil }, ascentM: ascentM, descentM: descentM, altitudeM: altitudeM,
            steps: steps, lastSplit: splits.last, gps: gpsQuality(at: time),
            movingAnchor: state == .recording && held == nil ? time.addingTimeInterval(-moving) : nil,
            tooFastSince: tooFastSince
        )
    }

    // MARK: - Control

    /// ready → recording.
    mutating func start(at time: Date) {
        guard state == .ready else { return }
        observe(time)
        start = time
        state = .recording
        elevation.setCounting(true)
        // Counts begin at Start, and nothing is bridged from a fix before it ("Start anyway" after a silent GPS).
        diagnostics = PipelineDiagnostics()
        stepFrom = nil
        // The first seconds after Start always settle, on post-Start fixes only: a warmed-up filter has the user's
        // position, but its velocity lags a standing start (it read 0 while they waited for "Ready").
        settling = Settling(since: time, fixes: [])
        positionStepsUntil = nil
        paceSamples = [PaceSample(time: time, moving: 0, distance: 0)]
        lastStepping = time
        if configuration.distance == .pedometer { pedometer = PedometerReading(time: time, distance: 0, steps: 0) }
        resetMotion()
    }

    /// recording or auto-paused → paused. A manual pause during auto-pause becomes manual (ui.md G3). Returns what
    /// closing an open settle window produced (its distance can complete a split).
    @discardableResult
    mutating func pause(at time: Date) -> [PipelineEvent] {
        observe(time)
        var events: [PipelineEvent] = []
        if state == .recording || state == .autoPaused {
            dropAnchor()
            limitCrossedAt = nil
        }
        switch state {
        case .recording:
            settle(&events)
            // While an auto-pause is pending the clock already holds at its start: the pause starts there too.
            let from = max(pendingAutoPause(at: time) ?? time, pauses.last?.end ?? .distantPast, start ?? .distantPast)
            openPause(.manual, at: from)
            if from < time { reviseAfterBackdating(from: from) }
        case .autoPaused:
            closeOpenPause(at: time)
            openPause(.manual, at: time)
        case .ready, .paused, .finished:
            return []
        }
        state = .paused
        elevation.setCounting(false)
        resetMotion()
        return events
    }

    /// paused or auto-paused → recording. Distance restarts at the next fix: nothing is bridged across a pause.
    mutating func resume(at time: Date) {
        guard state == .paused || state == .autoPaused else { return }
        observe(time)
        closeOpenPause(at: time)
        state = .recording
        elevation.setCounting(true)
        stepFrom = nil
        dropAnchor()
        limitCrossedAt = nil
        lastStepping = time
        if let last = paceSamples.last { paceSamples.append(PaceSample(time: time, moving: last.moving, distance: distanceM)) }
        resetMotion()
    }

    /// Marks a lap: the distance and moving time since the previous lap (or the start).
    @discardableResult
    mutating func lap(at time: Date) -> TrackLap? {
        guard let start, state != .ready, state != .finished else { return nil }
        observe(time)
        let lapStart = laps.last?.end ?? start
        let lap = TrackLap(index: laps.count + 1, start: lapStart, end: time, distanceM: distanceM - lapStartDistance,
                           movingSec: movingTime(at: time) - movingTime(at: lapStart))
        laps.append(lap)
        lapStartDistance = distanceM
        return lap
    }

    /// Ends the recording at `time`: closes any open pause and adds the partial last split.
    mutating func finish(at time: Date) -> [PipelineEvent] {
        guard state != .finished else { return [] }
        guard let start else {
            state = .finished
            return []
        }
        observe(time)
        var events: [PipelineEvent] = []
        dropAnchor()
        if state == .recording { settle(&events) }
        settling = nil
        let end = max(time, start)
        closeOpenPause(at: end)
        finishedAt = end
        state = .finished
        elevation.setCounting(false)
        pending = []
        let partial = distanceM - Double(splits.count) * tuning.splitDistance
        guard partial >= tuning.minPartialSplitFraction * tuning.splitDistance else { return events }
        events.append(.split(makeSplit(distance: partial, at: end)))
        return events
    }

    /// Time passing without input: auto-pause when Core Location said "stationary" (it then stops sending fixes)
    /// or the pedometer stopped counting steps.
    mutating func advance(to time: Date) -> [PipelineEvent] {
        observe(time)
        guard state == .recording, autoPauseEnabled else { return [] }
        var events: [PipelineEvent] = []
        switch configuration.distance {
        case .gps:
            if let since = stationarySince, lastAccepted?.isStationary == true,
               time.timeIntervalSince(since) >= tuning.autoPauseStationaryAfter {
                enterAutoPause(since: since, &events)
            }
        case .pedometer:
            if let since = lastStepping, time.timeIntervalSince(since) >= tuning.autoPauseAfter {
                enterAutoPause(since: since, &events)
            }
        case .none:
            break
        }
        return events
    }

    // MARK: - Inputs

    /// A fix, received at `receivedAt` (the recorder's clock), for the staleness rule.
    mutating func ingest(_ fix: LocationFix, receivedAt: Date) -> [PipelineEvent] {
        observe(receivedAt)
        return ingest(fix)
    }

    /// The pipeline's entry point (design §3.3, frozen): gates, filter, distance, splits, pace, auto-pause.
    mutating func ingest(_ fix: LocationFix) -> [PipelineEvent] {
        guard configuration.distance == .gps, state != .finished else { return [] }
        let t = fix.timestamp
        if fix.horizontalAccuracy.isFinite, fix.horizontalAccuracy >= 0 { lastReportedAccuracy = fix.horizontalAccuracy }

        // 1 Pre-gate. Only a fix that passes it moves the staleness clock: one bad timestamp can't age the rest.
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= tuning.maxAccuracy,
              fix.latitude.isFinite, fix.longitude.isFinite, abs(fix.latitude) <= 90
        else { return reject(.accuracy) }
        if let last = lastAccepted, t <= last.time { return reject(.outOfOrder) }
        if let latestSeen, t < latestSeen.addingTimeInterval(-tuning.staleAfter) { return reject(.stale) }
        observe(t)
        // The last settled point: a provisional re-init keeps it as its anchor (design §3.3 step 4).
        let settled = settling == nil ? stepFrom : nil
        let limit = configuration.profile.maxSpeed ?? .infinity

        // 2 Speed gate: an outlier gate on the jump from the filter's prediction, minus both accuracies. It limits
        // the change of velocity a fix implies; the sport's limit on the speed itself is step 4's.
        var speedGated = false
        if let last = lastAccepted, let since = kalman.lastTime, let predicted = kalman.predictedPosition(at: t) {
            let dt = max(t.timeIntervalSince(since), tuning.minSpeedGateInterval)
            let reach = Geodesy.distance(predicted, fix.coordinate) - fix.horizontalAccuracy - last.accuracy
            // The gate ages open as Δt grows; counting its rejections toward the re-init keeps a sustained
            // multipath offset from being accepted later with a kick to the velocity (design §3.3 step 3).
            speedGated = reach / dt > limit
        }

        // 3 Filter.
        var events: [PipelineEvent] = []
        let previousFixTime = kalman.lastTime
        let outcome = speedGated ? kalman.rejectedElsewhere(fix) : kalman.update(fix)
        switch outcome {
        case .rejected:
            if speedGated { rejectedRunHadSpeedGate = true }
            return reject(speedGated ? .implausible : .innovation)
        case .reinitialised:
            diagnostics.reinitialisations += 1
            if speedGated || rejectedRunHadSpeedGate { diagnostics.speedGateReinits += 1 }
            events.append(.reinitialised)
            beginProvisional(from: settled)
            beginSettling(with: fix)
        case .initialised:
            beginSettling(with: fix)
        case .updated:
            settling?.fixes.append((t, fix.coordinate, fix.isStationary))
        }
        rejectedRunHadSpeedGate = false
        if let here = kalman.position, settling != nil {
            if let previous = settling?.lastFiltered { settling?.path += Geodesy.distance(previous, here) }
            settling?.lastFiltered = here
            if settling?.firstFiltered == nil { settling?.firstFiltered = here }
        }
        if outcome == .updated, let previousFixTime {
            diagnostics.longestGapSec = max(diagnostics.longestGapSec, t.timeIntervalSince(previousFixTime))
        }
        diagnostics.fixesAccepted += 1
        lastAccepted = (t, fix.horizontalAccuracy, fix.isStationary)
        elevation.add(fix: fix)
        guard let position = kalman.position else { return events }
        let groundSpeed = kalman.groundSpeed
        defer { stepFrom = settling == nil ? (position, t, groundSpeed) : nil }

        // 4–5 Distance and gaps. While the filter settles, nothing accrues until its window ends.
        var step: Step?
        // The rejected span of a provisional re-init whose window closes now, and which side of the sport's limit
        // this fix's step (or closed window) was on, from when.
        var span: Step?
        var limitSide: (fast: Bool, from: Date)?
        if let window = settling, outcome == .updated, window.fixes.count >= 2, let previousFixTime,
           t.timeIntervalSince(previousFixTime) > tuning.gapAfter {
            // A gap inside the window breaks its line: the gap rule from the window's first filtered position, and
            // a fresh window from this fix. A provisional re-init's span isn't filled across it.
            step = bridge(from: (window.firstFiltered, window.fixes[0].time), to: (position, t),
                          gap: t.timeIntervalSince(previousFixTime), stationary: fix.isStationary, &events)
            dropAnchor()
            beginSettling(with: fix)
        } else if let window = settling, t.timeIntervalSince(window.since) >= tuning.settleWindow,
                  window.fixes.count >= tuning.settleMinFixes || t.timeIntervalSince(window.since) >= 3 * tuning.settleWindow
                  || window.fixes.count >= 64 {
            span = spanStep(to: window)
            let closed = closedStep(window, &events)
            step = closed.step
            if let fast = closed.fast { limitSide = (fast, window.since) }
            settling = nil
        } else if outcome == .updated, settling == nil, let from = stepFrom {
            let dt = t.timeIntervalSince(from.time)
            var length: Double
            var counts: Bool
            var fast = false
            if dt > tuning.gapAfter {
                length = Geodesy.distance(from.position, position)
                let implied = length / dt
                let bridged = implied <= limit
                if bridged { diagnostics.gapsBridged += 1 } else { diagnostics.gapsNotBridged += 1 }
                events.append(.gap(seconds: dt, bridged: bridged))
                counts = bridged && implied >= movingSpeed
            } else {
                let speed: Double
                if tuning.distanceFromVelocity, t > positionStepsUntil ?? .distantPast {
                    speed = (from.speed + groundSpeed) / 2
                    length = speed * dt
                    counts = speed >= movingSpeed
                } else {
                    // Position steps judge by the filter's speed now, as their dead-band does.
                    speed = groundSpeed
                    length = Geodesy.distance(from.position, position)
                    counts = kalman.speed >= movingSpeed
                }
                // The sport's limit applies to the filter's ground speed, at any reported accuracy.
                fast = speed > limit && !fix.isStationary
                limitSide = (fast, from.time)
            }
            // Core Location says the phone isn't moving: nothing accrues, even with auto-pause off.
            if fix.isStationary { counts = false }
            step = Step(from: from.time, to: t, distance: counts && !fast ? length : 0, refused: fast ? length : 0)
            // After a gap long enough to reset the velocity, the gap is bridged above and the next seconds settle
            // like a start: the velocity converges again, and the position came mostly from this one fix.
            if let previousFixTime, t.timeIntervalSince(previousFixTime) > kalman.tuning.velocityResetAfter {
                beginSettling(with: fix)
            }
        } else if outcome == .updated, settling == nil, stepFrom == nil, let previousFixTime,
                  t.timeIntervalSince(previousFixTime) > kalman.tuning.velocityResetAfter {
            // The same without a step to bridge (the first fix after Start or a resume, after a silent GPS).
            beginSettling(with: fix)
        }
        guard state != .ready else { return events }

        // 6–8 Pace, splits, auto-pause.
        let speed = kalman.speed
        let threshold = configuration.profile.autoPauseThreshold ?? 0
        switch state {
        case .recording:
            if let span, let counted = clipped(span) { accrue(counted, &events) }
            if let step, let counted = clipped(step) { accrue(counted, &events) }
            if let limitSide { trackLimit(fast: limitSide.fast, from: limitSide.from, to: t, &events) }
            recordPaceSample(at: t)
            if autoPauseEnabled {
                slowSince = speed < threshold ? (slowSince ?? t) : nil
                stationarySince = fix.isStationary ? (stationarySince ?? t) : nil
                if let since = slowSince, t.timeIntervalSince(since) >= tuning.autoPauseAfter {
                    enterAutoPause(since: since, &events)
                } else if let since = stationarySince, t.timeIntervalSince(since) >= tuning.autoPauseStationaryAfter {
                    enterAutoPause(since: since, &events)
                }
            }
        case .autoPaused:
            if speed >= tuning.autoResumeFactor * threshold, !fix.isStationary {
                if let since = fastSince {
                    if let span { pending.append(span) }
                    if let step { pending.append(step) }
                    if t.timeIntervalSince(since) >= tuning.autoResumeAfter { leaveAutoPause(since: since, &events) }
                } else {
                    fastSince = t
                    pending = []
                    positionStepsUntil = t.addingTimeInterval(tuning.positionStepsAfterRestart)
                }
            } else {
                fastSince = nil
                pending = []
            }
        case .ready, .paused, .finished:
            break
        }

        let altitude = elevation.altitudeM
        // Where the user went while paused isn't the activity's route (design §3.3, ADR 0005), nor where a vehicle
        // went while too fast.
        if state == .recording, tooFastSince == nil {
            events.append(.route(RoutePoint(time: t, latitude: position.latitude, longitude: position.longitude,
                                            horizontalAccuracy: kalman.positionSigma, altitude: altitude)))
        }
        events.append(.profile(ProfilePoint(time: t, distanceM: distanceM, altitudeM: altitude, speedMps: groundSpeed)))
        return events
    }

    /// A barometric reading (design §3.4).
    mutating func ingest(_ sample: AltitudeSample) {
        guard state != .finished else { return }
        elevation.add(sample)
    }

    /// A cumulative pedometer reading since the start (design §3.5): distance from its deltas, auto-pause when the
    /// steps stop for 10 s. Deltas while paused are left out.
    mutating func ingest(_ sample: PedometerSample) -> [PipelineEvent] {
        guard configuration.distance == .pedometer, state != .finished, state != .ready,
              let previous = pedometer, sample.timestamp > previous.time
        else { return [] }
        let t = sample.timestamp
        observe(t)
        diagnostics.pedometerSamples += 1
        let distance = max(sample.distanceM ?? previous.distance, previous.distance)
        let step = Step(from: previous.time, to: t, distance: distance - previous.distance)
        let stepping = sample.steps > previous.steps || (sample.cadence ?? 0) > 0
        pedometer = PedometerReading(time: t, distance: distance, steps: max(sample.steps, previous.steps))

        var events: [PipelineEvent] = []
        switch state {
        case .recording:
            if step.distance > 0 { accrue(step, &events) }
            recordPaceSample(at: t)
            if stepping {
                lastStepping = t
            } else if autoPauseEnabled, let since = lastStepping, t.timeIntervalSince(since) >= tuning.autoPauseAfter {
                enterAutoPause(since: since, &events)
            }
        case .autoPaused:
            if stepping {
                if fastSince == nil { fastSince = t }
                pending.append(step)
                if let since = fastSince, t.timeIntervalSince(since) >= tuning.autoResumeAfter {
                    leaveAutoPause(since: since, &events)
                    lastStepping = t
                }
            } else {
                fastSince = nil
                pending = []
            }
        case .ready, .paused, .finished:
            break
        }
        events.append(.profile(ProfilePoint(time: t, distanceM: distanceM, altitudeM: nil, speedMps: currentSpeed)))
        return events
    }

    // MARK: - Internals

    private static func prefixSums(_ pauses: [PauseInterval]) -> [Double] {
        var sums = [0.0]
        sums.reserveCapacity(pauses.count + 1)
        for pause in pauses {
            guard let end = pause.end else { break }
            sums.append(sums[sums.count - 1] + max(0, end.timeIntervalSince(pause.start)))
        }
        return sums
    }

    private mutating func observe(_ time: Date) {
        latestSeen = max(latestSeen ?? time, time)
    }

    private mutating func reject(_ reason: FixRejection) -> [PipelineEvent] {
        diagnostics.count(reason)
        return [.rejected(reason)]
    }

    private mutating func resetMotion() {
        slowSince = nil
        stationarySince = nil
        fastSince = nil
        pending = []
    }

    private mutating func openPause(_ kind: PauseInterval.Kind, at time: Date) {
        pauses.append(PauseInterval(kind: kind, start: time))
    }

    private mutating func closeOpenPause(at time: Date) {
        guard let last = pauses.indices.last, pauses[last].end == nil else { return }
        let end = max(time, pauses[last].start)
        pauses[last].end = end
        pausedBefore.append(pausedBefore[pausedBefore.count - 1] + end.timeIntervalSince(pauses[last].start))
    }

    /// A pause just opened at `from`, before now: what was computed since then without it is revised. The pace
    /// window's moving times, and the duration of a split crossed in between (its `.split` event carried the
    /// provisional value; `splits` and the checkpoint hold the revised one).
    private mutating func reviseAfterBackdating(from: Date) {
        let moving = movingTime(at: from)
        for i in paceSamples.indices where paceSamples[i].time > from {
            paceSamples[i].moving = min(paceSamples[i].moving, moving)
        }
        guard let start, let last = splits.indices.last, splits[last].end > from else { return }
        for i in splits.indices where splits[i].end > from {
            let previous = i > 0 ? splits[i - 1].end : start
            let s = splits[i]
            splits[i] = TrackSplit(index: s.index, distanceM: s.distanceM,
                                   durationSec: movingTime(at: s.end) - movingTime(at: previous), ascentM: s.ascentM,
                                   end: s.end)
        }
        splitStartMoving = movingTime(at: splits[last].end)
    }

    /// Starts a settle window at this fix (`Tuning.settleWindow`): a (re)initialised filter, or a reset velocity.
    private mutating func beginSettling(with fix: LocationFix) {
        settling = Settling(since: fix.timestamp, fixes: [(fix.timestamp, fix.coordinate, fix.isStationary)],
                            firstFiltered: kalman.position, lastFiltered: kalman.position)
        positionStepsUntil = nil
    }

    /// The distance of a settle window: the shorter of a Theil–Sen line through its fixes (the median of the pairwise
    /// velocities per axis, over the window's span) and the filtered track's length. They fail in opposite
    /// directions: a coarse first fix lengthens the track as the filter walks back from it, and one bad fix can't tilt
    /// a median; an acceleration (a standing start) lengthens the line, and the track follows it. A line faster than
    /// the sport's limit adds nothing (`fast`). Nil with fewer than three fixes.
    private func settledStep(_ window: Settling) -> (step: Step, fast: Bool)? {
        let fixes = window.fixes
        guard fixes.count >= 3, let first = fixes.first, let last = fixes.last, last.time > first.time else { return nil }
        let plane = LocalTangentPlane(anchor: first.coordinate)
        let points = fixes.map { (t: $0.time.timeIntervalSince(first.time), d: plane.project($0.coordinate)) }
        var east: [Double] = [], north: [Double] = []
        east.reserveCapacity(points.count * (points.count - 1) / 2)
        north.reserveCapacity(points.count * (points.count - 1) / 2)
        for i in points.indices {
            for j in points.indices where j > i {
                let dt = points[j].t - points[i].t
                guard dt > 0 else { continue }
                east.append((points[j].d.east - points[i].d.east) / dt)
                north.append((points[j].d.north - points[i].d.north) / dt)
            }
        }
        guard !east.isEmpty else { return nil }
        let speed = Displacement(east: ElevationFusion.median(east), north: ElevationFusion.median(north)).length
        let still = fixes.filter(\.isStationary).count * 2 > fixes.count
        let fast = speed > (configuration.profile.maxSpeed ?? .infinity) && !still
        let moving = speed >= movingSpeed && !still && !fast
        let length = min(speed * last.time.timeIntervalSince(first.time), window.path)
        return (Step(from: first.time, to: last.time, distance: moving ? length : 0, refused: fast ? length : 0), fast)
    }

    /// Ends a settle window early (Pause, Finish).
    private mutating func settle(_ events: inout [PipelineEvent]) {
        guard let window = settling else { return }
        settling = nil
        if state == .recording, let step = closedStep(window, &events).step, let counted = clipped(step) {
            accrue(counted, &events)
        }
    }

    /// A closing window's step: the settled line, or with fewer than three fixes the gap rule over the window. `fast`
    /// says which side of the sport's limit the line was on; nil for the gap rule.
    private mutating func closedStep(_ window: Settling, _ events: inout [PipelineEvent]) -> (step: Step?, fast: Bool?) {
        if let settled = settledStep(window) { return (settled.step, settled.fast) }
        guard let first = window.fixes.first, let last = window.fixes.last, let to = window.lastFiltered else {
            return (nil, nil)
        }
        let step = bridge(from: (window.firstFiltered, first.time), to: (to, last.time),
                          gap: last.time.timeIntervalSince(first.time), stationary: last.isStationary, &events)
        return (step, nil)
    }

    /// A re-init: the first since the last settled position keeps that position as the anchor (while recording or
    /// auto-paused, where its span can count); another before the window closes makes a chain.
    private mutating func beginProvisional(from settled: (position: Coordinate, time: Date, speed: Double)?) {
        if anchor != nil {
            anchor?.reinits += 1
        } else if let settled, state == .recording || state == .autoPaused {
            anchor = Anchor(position: settled.position, time: settled.time, speed: settled.speed, reinits: 1)
        }
    }

    /// A provisional re-init's window closes: its rejected span, from the anchor to the window's first position
    /// (ADR 0003 amendment 2, decision 4). One re-init with the anchor at most `maxDeadReckoning` before it is
    /// dead-reckoned at the anchor's speed, as the filter does over one rejected fix. A chain or a longer span takes
    /// the gap rule's straight line; a train's is too fast. Either counts only between the dead-band and the limit.
    private mutating func spanStep(to window: Settling) -> Step? {
        guard let anchor else { return nil }
        self.anchor = nil
        let span = window.since.timeIntervalSince(anchor.time)
        guard span > 0, let to = window.firstFiltered else {
            diagnostics.reinitSpansDropped += 1
            return nil
        }
        let deadReckoned = anchor.reinits == 1 && span <= tuning.maxDeadReckoning
        let speed = deadReckoned ? anchor.speed : Geodesy.distance(anchor.position, to) / span
        let tooFast = speed > (configuration.profile.maxSpeed ?? .infinity)
        guard speed >= movingSpeed, !tooFast else {
            diagnostics.reinitSpansDropped += 1
            return Step(from: anchor.time, to: window.since, distance: 0, refused: tooFast ? speed * span : 0)
        }
        if deadReckoned { diagnostics.reinitSpansDeadReckoned += 1 } else { diagnostics.reinitSpansBridged += 1 }
        return Step(from: anchor.time, to: window.since, distance: speed * span)
    }

    /// Start, Pause, a resume, Finish or a gap inside the window: the span isn't filled across them.
    private mutating func dropAnchor() {
        guard anchor != nil else { return }
        anchor = nil
        diagnostics.reinitSpansDropped += 1
    }

    /// The too-fast state (design §3.3 "Too fast"): `Tuning.tooFastAfter` of steps on the other side of the sport's
    /// limit switch it, backdated to the first of them. A closed settle window is one step from its start.
    private mutating func trackLimit(fast: Bool, from: Date, to: Date, _ events: inout [PipelineEvent]) {
        guard fast != (tooFastSince != nil) else {
            limitCrossedAt = nil
            return
        }
        let since = limitCrossedAt ?? max(from, countsFrom ?? from)
        guard to.timeIntervalSince(since) >= tuning.tooFastAfter else {
            limitCrossedAt = since
            return
        }
        limitCrossedAt = nil
        if fast {
            tooFastSince = since
            diagnostics.tooFastEpisodes += 1
            events.append(.tooFast(since: since))
        } else {
            tooFastSince = nil
            events.append(.tooFastEnded(since: since))
        }
    }

    /// The gap rule (design §3.3 step 5): the straight line, counted when its speed is at most the sport's maximum
    /// and at least the dead-band. A `.gap` event when the silence was longer than `gapAfter`.
    private mutating func bridge(from start: (position: Coordinate?, time: Date), to end: (position: Coordinate, time: Date),
                                 gap: TimeInterval, stationary: Bool, _ events: inout [PipelineEvent]) -> Step? {
        let span = end.time.timeIntervalSince(start.time)
        guard let from = start.position, span > 0 else { return nil }
        let length = Geodesy.distance(from, end.position)
        let implied = length / span
        let bridged = implied <= (configuration.profile.maxSpeed ?? .infinity)
        if gap > tuning.gapAfter {
            if bridged { diagnostics.gapsBridged += 1 } else { diagnostics.gapsNotBridged += 1 }
            events.append(.gap(seconds: gap, bridged: bridged))
        }
        return Step(from: start.time, to: end.time, distance: bridged && implied >= movingSpeed && !stationary ? length : 0)
    }

    /// The last Start or resume (manual or auto): nothing counts before it.
    private var countsFrom: Date? {
        guard let start else { return nil }
        return max(start, pauses.last?.end ?? start)
    }

    /// The part of a step after the last Start or resume: a fix delivered late never counts time before them.
    private func clipped(_ step: Step) -> Step? {
        guard step.distance > 0 || step.refused > 0, let from = countsFrom, step.to > from else { return nil }
        guard step.from < from else { return step }
        let share = step.to.timeIntervalSince(from) / step.to.timeIntervalSince(step.from)
        return Step(from: from, to: step.to, distance: step.distance * share, refused: step.refused * share)
    }

    /// Adds a step's distance and emits every split it crosses, interpolating the crossing time along the step. What
    /// the sport's limit refused goes to the diagnostics only.
    private mutating func accrue(_ step: Step, _ events: inout [PipelineEvent]) {
        if step.refused > 0 {
            diagnostics.tooFastSec += step.to.timeIntervalSince(step.from)
            diagnostics.tooFastDistanceM += step.refused
        }
        let before = distanceM
        distanceM += step.distance
        var next = Double(splits.count + 1) * tuning.splitDistance
        while distanceM >= next {
            let fraction = step.distance > 0 ? (next - before) / step.distance : 1
            let crossing = step.from.addingTimeInterval(fraction * step.to.timeIntervalSince(step.from))
            events.append(.split(makeSplit(distance: tuning.splitDistance, at: crossing)))
            next = Double(splits.count + 1) * tuning.splitDistance
        }
    }

    private mutating func makeSplit(distance: Double, at time: Date) -> TrackSplit {
        let moving = movingTime(at: time)
        let ascent = elevation.ascent
        let split = TrackSplit(index: splits.count + 1, distanceM: distance, durationSec: moving - splitStartMoving,
                               ascentM: ascent.map { max(0, $0 - splitStartAscent) }, end: time)
        splits.append(split)
        splitStartMoving = moving
        splitStartAscent = ascent ?? 0
        return split
    }

    private mutating func recordPaceSample(at time: Date) {
        paceSamples.append(PaceSample(time: time, moving: movingTime(at: time), distance: distanceM))
        let windowStart = (paceSamples.last?.moving ?? 0) - tuning.paceWindow
        // Keep one sample before the window for the interpolation.
        var drop = 0
        while drop + 1 < paceSamples.count, paceSamples[drop + 1].moving <= windowStart { drop += 1 }
        if drop > 0 { paceSamples.removeFirst(drop) }
    }

    /// Enters auto-pause, backdated to when the user stopped: the slow seconds aren't moving time.
    private mutating func enterAutoPause(since: Date, _ events: inout [PipelineEvent]) {
        let from = max(since, pauses.last?.end ?? since, start ?? since)
        openPause(.auto, at: from)
        state = .autoPaused
        elevation.setCounting(false)
        diagnostics.autoPauses += 1
        reviseAfterBackdating(from: from)
        resetMotion()
        events.append(.autoPaused(since: from))
    }

    /// Leaves auto-pause, backdated to when the user started moving; the distance since then is counted.
    private mutating func leaveAutoPause(since: Date, _ events: inout [PipelineEvent]) {
        closeOpenPause(at: since)
        state = .recording
        elevation.setCounting(true)
        events.append(.autoResumed(since: since))
        let replay = pending
        resetMotion()
        for step in replay {
            if step.distance > 0 || step.refused > 0 { accrue(step, &events) }
            recordPaceSample(at: step.to)
        }
    }
}
