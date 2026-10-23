import Foundation

/// Why the pipeline dropped a fix (design §3.3 steps 1–3).
enum FixRejection: String, Codable, Sendable {
    /// Invalid, or worse than 25 m.
    case accuracy
    /// Not after the last accepted fix.
    case outOfOrder
    /// More than 10 s older than the newest time the pipeline has seen.
    case stale
    /// Implies a speed above the sport's maximum from the last filtered position.
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
    /// The filter restarted at this fix (three innovation rejections in a row); the jump adds no distance.
    case reinitialised
    /// Δt over 10 s between accepted fixes; `bridged` when the straight line was counted.
    case gap(seconds: Double, bridged: Bool)
    case split(TrackSplit)
    /// Auto-pause entered; the pause starts at `since` (when the user stopped).
    case autoPaused(since: Date)
    /// Auto-pause left; the pause ends at `since` (when the user started moving).
    case autoResumed(since: Date)
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
}

/// The location pipeline (design §3.3, ADR 0003): gates, the Kalman filter, distance, gaps, rolling pace, splits
/// and auto-pause, plus elevation (§3.4) and pedometer distance (§3.5).
///
/// Distance integrates the filter's ground speed between accepted fixes while recording and moving (above the
/// sport's dead-band, not flagged stationary); gaps over 10 s are bridged by the straight line when the implied speed
/// is plausible (`Tuning.distanceFromVelocity` explains why not position steps). After the filter (re)starts or
/// resets its velocity, the first 10 s settle as a whole at their end (`Tuning.settleWindow`). Auto-pause is
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
    }

    /// The fixes since the filter (re)started, held until the settle window ends. Memory only, never checkpointed.
    private struct Settling: Sendable {
        let since: Date
        var fixes: [(time: Date, coordinate: Coordinate, isStationary: Bool)]
        /// The filtered track's length over the window, from `lastFiltered`.
        var path: Double = 0
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

    /// Metres per second over the last 30 s of moving time; nil unless recording with ≥ 10 s and ≥ 20 m.
    var currentSpeed: Double? {
        guard state == .recording, let last = paceSamples.last, let first = paceSamples.first else { return nil }
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
            movingAnchor: state == .recording && held == nil ? time.addingTimeInterval(-moving) : nil
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
        // A filter still settling from the warm-up settles on the fixes after Start only.
        if settling != nil { settling = Settling(since: time, fixes: [], lastFiltered: kalman.position) }
        paceSamples = [PaceSample(time: time, moving: 0, distance: 0)]
        lastStepping = time
        if configuration.distance == .pedometer { pedometer = PedometerReading(time: time, distance: 0, steps: 0) }
        resetMotion()
    }

    /// recording or auto-paused → paused. A manual pause during auto-pause becomes manual (ui.md G3).
    mutating func pause(at time: Date) {
        observe(time)
        switch state {
        case .recording:
            var events: [PipelineEvent] = []
            settle(&events)
            // While an auto-pause is pending the clock already holds at its start: the pause starts there too.
            let from = max(pendingAutoPause(at: time) ?? time, pauses.last?.end ?? .distantPast, start ?? .distantPast)
            openPause(.manual, at: from)
            if from < time { reviseAfterBackdating(from: from) }
        case .autoPaused:
            closeOpenPause(at: time)
            openPause(.manual, at: time)
        case .ready, .paused, .finished:
            return
        }
        state = .paused
        elevation.setCounting(false)
        resetMotion()
    }

    /// paused or auto-paused → recording. Distance restarts at the next fix: nothing is bridged across a pause.
    mutating func resume(at time: Date) {
        guard state == .paused || state == .autoPaused else { return }
        observe(time)
        closeOpenPause(at: time)
        state = .recording
        elevation.setCounting(true)
        stepFrom = nil
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
        var implausibleJump = false

        // 2 Speed gate, from the last filtered position.
        if let maxSpeed = configuration.profile.maxSpeed, let from = kalman.position, let since = kalman.lastTime,
           let last = lastAccepted {
            let dt = max(t.timeIntervalSince(since), tuning.minSpeedGateInterval)
            let reach = Geodesy.distance(from, fix.coordinate) - fix.horizontalAccuracy - last.accuracy
            if reach / dt > maxSpeed {
                // The gate ages open as Δt grows; counting its rejections toward the re-init keeps a sustained
                // multipath offset from being accepted later with a kick to the velocity (design §3.3 step 3).
                guard kalman.rejectedElsewhere(fix) == .reinitialised else { return reject(.implausible) }
                implausibleJump = true
            }
        }

        // 3 Filter.
        var events: [PipelineEvent] = []
        let previousFixTime = kalman.lastTime
        let outcome: KalmanTrack.Outcome = implausibleJump ? .reinitialised : kalman.update(fix)
        switch outcome {
        case .rejected:
            return reject(.innovation)
        case .reinitialised:
            diagnostics.reinitialisations += 1
            events.append(.reinitialised)
            beginSettling(with: fix)
        case .initialised:
            beginSettling(with: fix)
        case .updated:
            settling?.fixes.append((t, fix.coordinate, fix.isStationary))
        }
        if let here = kalman.position, settling != nil {
            if let previous = settling?.lastFiltered { settling?.path += Geodesy.distance(previous, here) }
            settling?.lastFiltered = here
        }
        diagnostics.fixesAccepted += 1
        lastAccepted = (t, fix.horizontalAccuracy, fix.isStationary)
        elevation.add(fix: fix)
        guard let position = kalman.position else { return events }
        let groundSpeed = kalman.groundSpeed
        defer { stepFrom = settling == nil ? (position, t, groundSpeed) : nil }

        // 4–5 Distance and gaps. While the filter settles, nothing accrues until its window ends.
        var step: Step?
        if let window = settling, t.timeIntervalSince(window.since) >= tuning.settleWindow,
           window.fixes.count >= tuning.settleMinFixes || t.timeIntervalSince(window.since) >= 3 * tuning.settleWindow
           || window.fixes.count >= 64 {
            step = settledStep(window)
            settling = nil
        } else if outcome == .updated, settling == nil, let from = stepFrom {
            let dt = t.timeIntervalSince(from.time)
            diagnostics.longestGapSec = max(diagnostics.longestGapSec, dt)
            var length: Double
            var counts: Bool
            if dt > tuning.gapAfter {
                length = Geodesy.distance(from.position, position)
                let implied = length / dt
                let bridged = implied <= (configuration.profile.maxSpeed ?? .infinity)
                if bridged { diagnostics.gapsBridged += 1 } else { diagnostics.gapsNotBridged += 1 }
                events.append(.gap(seconds: dt, bridged: bridged))
                counts = bridged && implied >= movingSpeed
            } else if tuning.distanceFromVelocity, t > positionStepsUntil ?? .distantPast {
                let mean = (from.speed + groundSpeed) / 2
                length = mean * dt
                counts = mean >= movingSpeed
            } else {
                length = Geodesy.distance(from.position, position)
                counts = kalman.speed >= movingSpeed
            }
            // Core Location says the phone isn't moving: nothing accrues, even with auto-pause off.
            if fix.isStationary { counts = false }
            step = Step(from: from.time, to: t, distance: counts ? length : 0)
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
            if let step, let counted = clipped(step) { accrue(counted, &events) }
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
        // Where the user went while paused isn't the activity's route (design §3.3, ADR 0005).
        if state == .recording {
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
                            lastFiltered: kalman.position)
        positionStepsUntil = nil
    }

    /// The distance of a settle window: the shorter of a Theil–Sen line through its fixes (the median of the pairwise
    /// velocities per axis, over the window's span) and the filtered track's length. They fail in opposite
    /// directions: a coarse first fix lengthens the track as the filter walks back from it, and one bad fix can't tilt
    /// a median; an acceleration (a standing start) lengthens the line, and the track follows it. Nil with fewer than
    /// three fixes.
    private func settledStep(_ window: Settling) -> Step? {
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
        let moving = speed >= movingSpeed && !still
        let line = speed * last.time.timeIntervalSince(first.time)
        return Step(from: first.time, to: last.time, distance: moving ? min(line, window.path) : 0)
    }

    /// Ends a settle window early (Pause, Finish): its fixes so far count if there are enough of them.
    private mutating func settle(_ events: inout [PipelineEvent]) {
        guard let window = settling else { return }
        settling = nil
        if state == .recording, let step = settledStep(window), let counted = clipped(step) {
            accrue(counted, &events)
        }
    }

    /// The part of a step after the last Start or resume: a fix delivered late never counts time before them.
    private func clipped(_ step: Step) -> Step? {
        guard step.distance > 0, let start else { return nil }
        let from = max(start, pauses.last?.end ?? start)
        guard step.to > from else { return nil }
        guard step.from < from else { return step }
        let span = step.to.timeIntervalSince(step.from)
        return Step(from: from, to: step.to, distance: step.distance * step.to.timeIntervalSince(from) / span)
    }

    /// Adds a step's distance and emits every split it crosses, interpolating the crossing time along the step.
    private mutating func accrue(_ step: Step, _ events: inout [PipelineEvent]) {
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
            if step.distance > 0 { accrue(step, &events) }
            recordPaceSample(at: step.to)
        }
    }
}
