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
/// Distance integrates the filter's ground speed between accepted fixes while recording and moving (≥ 0.3 m/s, not
/// flagged stationary); gaps over 10 s are bridged by the straight line when the implied speed is plausible
/// (`Tuning.distanceFromVelocity` explains why not position steps). Auto-pause is backdated: it starts when the
/// user stopped and ends when they moved again, so the 10 s and 3 s confirmations are neither moving time nor lost
/// distance.
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
        var minMovingSpeed = 0.3
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
        /// counts twice. The velocity state takes far less jitter and doesn't double back. Its cost: lag at an
        /// acceleration isn't recovered (about 5–10 m at a standing start, 3 m after a stop).
        var distanceFromVelocity = true
        /// After the filter (re)starts, its velocity resets, or the user moves off from an auto-pause, distance comes
        /// from position steps for this long: they recover the lag of a converging velocity, which integrating the
        /// velocity would lose (a standing or flying start, a tunnel exit).
        var positionStepsAfterRestart: TimeInterval = 10

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
        var ascentM: Double
        var descentM: Double
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
    private(set) var pauses: [PauseInterval] = [] {
        didSet { pausedBefore = Self.prefixSums(pauses) }
    }
    /// `pausedBefore[i]`: the total length of `pauses[0 ..< i]` (all closed; only the last pause can be open).
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
        pauses = saved.pauses
        distanceM = saved.distanceM
        splits = saved.splits
        splitStartMoving = saved.splitStartMovingSec
        splitStartAscent = saved.splitStartAscentM
        laps = saved.laps
        lapStartDistance = saved.lapStartDistanceM
        diagnostics = saved.diagnostics
        elevation = ElevationFusion(mode: configuration.elevation, ascentM: saved.ascentM, descentM: saved.descentM)
        elevation.setCounting(false)
        if let distance = saved.pedometerDistanceM, let steps = saved.pedometerSteps {
            pedometer = PedometerReading(time: saved.lastSampleTime ?? interruptedAt, distance: distance, steps: steps)
        }
        let resumeFrom = max(interruptedAt, saved.start)
        if let last = pauses.indices.last, pauses[last].end == nil {
            if pauses[last].kind != .manual {
                pauses[last].end = max(pauses[last].start, resumeFrom)
                pauses.append(PauseInterval(kind: .interruption, start: resumeFrom))
            }
        } else {
            pauses.append(PauseInterval(kind: .interruption, start: resumeFrom))
        }
        pausedBefore = Self.prefixSums(pauses)
        state = .paused
        latestSeen = resumeFrom
    }

    // MARK: - Reads

    var ascentM: Double? { elevation.ascent }
    var descentM: Double? { elevation.descent }
    var altitudeM: Double? { elevation.altitudeM }
    var steps: Int? { pedometer?.steps }
    private var autoPauseEnabled: Bool {
        guard configuration.autoPause else { return false }
        switch configuration.distance {
        case .gps: return configuration.profile.autoPauseThreshold != nil
        case .pedometer: return true
        case .none: return false
        }
    }

    /// The checkpoint state; nil before Start.
    var resume: Resume? {
        guard let start else { return nil }
        return Resume(start: start, pauses: pauses, distanceM: distanceM, splits: splits,
                      splitStartMovingSec: splitStartMoving, splitStartAscentM: splitStartAscent,
                      ascentM: elevation.ascentM, descentM: elevation.descentM, laps: laps,
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
        guard distanceM >= tuning.paceMinDistance else { return nil }
        return movingTime(at: time) / distanceM * 1000
    }

    func gpsQuality(at time: Date) -> GPSQuality {
        guard configuration.distance == .gps else { return .off }
        guard let last = lastAccepted else { return .weak }
        if time.timeIntervalSince(last.time) > tuning.weakAfter, !last.isStationary { return .weak }
        return last.accuracy <= tuning.goodAccuracy ? .good : .fair
    }

    func snapshot(at time: Date) -> TrackSnapshot {
        let moving = movingTime(at: time)
        let average = averagePace(at: time)
        return TrackSnapshot(
            state: state, movingSec: moving, elapsedSec: elapsedTime(at: time), distanceM: distanceM,
            currentPace: currentPace, averagePace: average, currentSpeed: currentSpeed,
            averageSpeed: average.map { 1000 / $0 }, ascentM: ascentM, descentM: descentM, altitudeM: altitudeM,
            steps: steps, lastSplit: splits.last, gps: gpsQuality(at: time),
            movingAnchor: state == .recording ? time.addingTimeInterval(-moving) : nil
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
            pauses.append(PauseInterval(kind: .manual, start: max(time, start ?? time)))
        case .autoPaused:
            closeOpenPause(at: time)
            pauses.append(PauseInterval(kind: .manual, start: time))
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
        let end = max(time, start)
        closeOpenPause(at: end)
        finishedAt = end
        state = .finished
        elevation.setCounting(false)
        pending = []
        let partial = distanceM - Double(splits.count) * tuning.splitDistance
        guard partial >= tuning.minPartialSplitFraction * tuning.splitDistance else { return [] }
        let split = makeSplit(distance: partial, at: end)
        return [.split(split)]
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
        let stale = latestSeen.map { t < $0.addingTimeInterval(-tuning.staleAfter) } ?? false
        observe(t)
        lastReportedAccuracy = fix.horizontalAccuracy

        // 1 Pre-gate.
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= tuning.maxAccuracy,
              fix.latitude.isFinite, fix.longitude.isFinite, abs(fix.latitude) <= 90
        else { return reject(.accuracy) }
        if let last = lastAccepted, t <= last.time { return reject(.outOfOrder) }
        if stale { return reject(.stale) }

        // 2 Speed gate, from the last filtered position.
        if let maxSpeed = configuration.profile.maxSpeed, let from = kalman.position, let since = kalman.lastTime,
           let last = lastAccepted {
            let dt = max(t.timeIntervalSince(since), tuning.minSpeedGateInterval)
            let reach = Geodesy.distance(from, fix.coordinate) - fix.horizontalAccuracy - last.accuracy
            if reach / dt > maxSpeed { return reject(.implausible) }
        }

        // 3 Filter.
        var events: [PipelineEvent] = []
        let previousFixTime = kalman.lastTime
        let outcome = kalman.update(fix)
        switch outcome {
        case .rejected:
            return reject(.innovation)
        case .reinitialised:
            diagnostics.reinitialisations += 1
            events.append(.reinitialised)
            positionStepsUntil = t.addingTimeInterval(tuning.positionStepsAfterRestart)
        case .initialised:
            positionStepsUntil = t.addingTimeInterval(tuning.positionStepsAfterRestart)
        case .updated:
            if let previousFixTime, t.timeIntervalSince(previousFixTime) > kalman.tuning.velocityResetAfter {
                positionStepsUntil = t.addingTimeInterval(tuning.positionStepsAfterRestart)
            }
        }
        diagnostics.fixesAccepted += 1
        lastAccepted = (t, fix.horizontalAccuracy, fix.isStationary)
        elevation.add(fix: fix)
        guard let position = kalman.position else { return events }
        let groundSpeed = kalman.groundSpeed
        defer { stepFrom = (position, t, groundSpeed) }

        // 4–5 Distance and gaps.
        var step: Step?
        if outcome == .updated, let from = stepFrom {
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
                counts = bridged && implied >= tuning.minMovingSpeed
            } else if tuning.distanceFromVelocity, t > positionStepsUntil ?? .distantPast {
                let mean = (from.speed + groundSpeed) / 2
                length = mean * dt
                counts = mean >= tuning.minMovingSpeed
            } else {
                length = Geodesy.distance(from.position, position)
                counts = kalman.speed >= tuning.minMovingSpeed
            }
            // Core Location says the phone isn't moving: nothing accrues, even with auto-pause off.
            if fix.isStationary { counts = false }
            step = Step(from: from.time, to: t, distance: counts ? length : 0)
        }
        guard state != .ready else { return events }

        // 6–8 Pace, splits, auto-pause.
        let speed = kalman.speed
        let threshold = configuration.profile.autoPauseThreshold ?? 0
        switch state {
        case .recording:
            if let step, step.distance > 0, t > (start ?? t) { accrue(step, &events) }
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
        events.append(.route(RoutePoint(time: t, latitude: position.latitude, longitude: position.longitude,
                                        horizontalAccuracy: kalman.positionSigma, altitude: altitude)))
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
            let length = pause.end.map { max(0, $0.timeIntervalSince(pause.start)) } ?? 0
            sums.append(sums[sums.count - 1] + length)
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

    private mutating func closeOpenPause(at time: Date) {
        guard let last = pauses.indices.last, pauses[last].end == nil else { return }
        pauses[last].end = max(time, pauses[last].start)
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
        pauses.append(PauseInterval(kind: .auto, start: from))
        state = .autoPaused
        elevation.setCounting(false)
        diagnostics.autoPauses += 1
        let moving = movingTime(at: from)
        for i in paceSamples.indices where paceSamples[i].time > from {
            paceSamples[i].moving = min(paceSamples[i].moving, moving)
        }
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
