import Foundation

/// A constant-velocity Kalman filter for GPS fixes (ADR 0003, design §3.3 step 3).
///
/// - Two states per axis (position, velocity), east and north in a `LocalTangentPlane` anchored at the first fix
///   and re-anchored every 5 km. The anchor is held in memory only; nothing here is ever checkpointed.
/// - Measurement variance `max(horizontalAccuracy, 3 m)²`; white-acceleration process noise with `sigmaA`
///   (continuous model, so a variable Δt scales correctly).
/// - Innovation gate at 3.5σ (Mahalanobis distance over both axes). A rejected fix leaves the state untouched;
///   three rejections in a row re-initialise at the third measurement (a real jump, a tunnel exit).
/// - Association (ADR 0003 amendment 2, decision 2): after a rejection, a fix the gate would accept still counts as
///   rejected when it lies nearer the last rejected fix, moved on at the filter's velocity, than the prediction. It
///   belongs to the rejected run, so a gate that aged open can't take a ghost with a kick to the velocity.
/// - A re-init takes the rejected run's velocity (decision 3): the line from its first fix to the third, when the
///   middle one lies on it within the accuracies; else 0. A filter restarted on a train or a flying start follows it.
/// - Δt over 15 s resets the velocity variance before predicting, so the next fix sets the velocity again.
///
/// Pure and `Sendable`; a few dozen floating-point operations and no allocation per fix.
struct KalmanTrack: Sendable, LocationRedacting {
    struct Tuning: Sendable, Equatable {
        /// White-acceleration noise, m/s² (the sport's σa).
        var sigmaA: Double
        /// The floor of the measurement sigma, metres.
        var minMeasurementSigma: Double = 3
        /// Innovations beyond this many sigmas are rejected.
        var gateSigmas: Double = 3.5
        /// Consecutive rejections that re-initialise the filter at the measurement.
        var reinitialiseAfter: Int = 3
        /// A gap longer than this resets the velocity variance, seconds.
        var velocityResetAfter: TimeInterval = 15
        /// The velocity sigma at initialisation and after a reset, m/s.
        var initialVelocitySigma: Double = 10
        /// Re-anchor the tangent plane when the position is this far from the anchor, metres.
        var reanchorDistance: Double = 5000
    }

    enum Outcome: Sendable, Equatable {
        /// The first fix: the filter starts at the measurement.
        case initialised
        /// The fix was accepted and the state updated.
        case updated
        /// The innovation was beyond the gate; the state is unchanged.
        case rejected(sigmas: Double)
        /// The gates rejected `reinitialiseAfter` fixes in a row: the filter restarted at this one, with the rejected
        /// run's velocity when its fixes lie on a line.
        case reinitialised
    }

    /// A fix of the current run of rejections. Memory only, like the plane; a coordinate renders nothing.
    private struct Rejected: Sendable {
        let time: Date
        let coordinate: Coordinate
        let accuracy: Double

        init(_ fix: LocationFix) {
            time = fix.timestamp
            coordinate = fix.coordinate
            accuracy = fix.horizontalAccuracy
        }
    }

    /// One axis: position p (m), velocity v (m/s) and their covariance.
    private struct Axis: Sendable {
        var p = 0.0, v = 0.0
        var pp = 0.0, pv = 0.0, vv = 0.0

        mutating func predict(dt: Double, q: Double) {
            p += v * dt
            let dt2 = dt * dt
            pp += 2 * dt * pv + dt2 * vv + q * dt2 * dt / 3
            pv += dt * vv + q * dt2 / 2
            vv += q * dt
        }

        mutating func update(innovation nu: Double, s: Double) {
            let kp = pp / s, kv = pv / s
            p += kp * nu
            v += kv * nu
            let ppOld = pp, pvOld = pv
            pp = (1 - kp) * ppOld
            pv = (1 - kp) * pvOld
            vv -= kv * pvOld
        }
    }

    let tuning: Tuning
    private(set) var plane: LocalTangentPlane?
    private var east = Axis()
    private var north = Axis()
    /// The time of the last accepted (or initialising) fix.
    private(set) var lastTime: Date?
    private(set) var consecutiveRejections = 0
    /// The run's first rejected fix, and its latest one after that (the middle fix of three).
    private var runFirst: Rejected?
    private var runLatest: Rejected?
    /// The filter holds only its very first fix: no velocity and no history, so it can't tell which side of a
    /// disagreement is the ghost (a coarse first fix is the outlier). Association waits for the first update, and a
    /// fresh filter gates as before (ADR 0003 amendment 2, decision 1).
    private var holdsOnlyFirstFix = false

    init(tuning: Tuning) {
        self.tuning = tuning
    }

    /// The filtered position at `lastTime`.
    var position: Coordinate? {
        plane?.unproject(Displacement(east: east.p, north: north.p))
    }

    /// Where the filter expects a fix at `time`: the position moved on at the velocity (constant velocity). The
    /// pipeline's speed gate measures from here (design §3.3 step 2).
    func predictedPosition(at time: Date) -> Coordinate? {
        guard let plane, let lastTime else { return nil }
        let dt = max(time.timeIntervalSince(lastTime), 0)
        return plane.unproject(Displacement(east: east.p + east.v * dt, north: north.p + north.v * dt))
    }

    /// The filtered velocity, east and north m/s.
    var velocity: Displacement { Displacement(east: east.v, north: north.v) }

    /// The filtered speed, m/s, as the plane measures it.
    var speed: Double { velocity.length }

    /// The filtered speed over the ground, m/s: the plane's velocity rescaled by the radii of curvature at the
    /// current position (the plane's scale is exact only at its anchor; 5 km north at 50° it is 0.09 % off east).
    var groundSpeed: Double {
        guard let plane, let here = position else { return 0 }
        let anchor = plane.anchor
        let north = Geodesy.meridionalRadius(latitude: here.latitude) / Geodesy.meridionalRadius(latitude: anchor.latitude)
        let east = Geodesy.primeVerticalRadius(latitude: here.latitude) * cos(here.latitude * .pi / 180)
            / (Geodesy.primeVerticalRadius(latitude: anchor.latitude) * cos(anchor.latitude * .pi / 180))
        let ve = self.east.v * east, vn = self.north.v * north
        return (ve * ve + vn * vn).squareRoot()
    }

    /// The one-sigma position uncertainty, metres (the larger axis).
    var positionSigma: Double { max(east.pp, north.pp).squareRoot() }

    /// Never renders its state: the plane's anchor and the positions in it give the location back (design §8.3).
    var description: String { "kalman(±\(LocationFix.metres(positionSigma)) m)" }

    /// A fix another gate rejected (the pipeline's speed gate). It counts toward the re-initialisation like an
    /// innovation rejection: three in a row, by either gate, restart the filter at the third fix.
    mutating func rejectedElsewhere(_ fix: LocationFix) -> Outcome {
        reject(fix, variance: pow(max(fix.horizontalAccuracy, tuning.minMeasurementSigma), 2), sigmas: .infinity)
    }

    mutating func update(_ fix: LocationFix) -> Outcome {
        let r = pow(max(fix.horizontalAccuracy, tuning.minMeasurementSigma), 2)
        guard let plane, let lastTime else {
            initialise(at: fix, variance: r)
            holdsOnlyFirstFix = true
            return .initialised
        }
        let dt = max(fix.timestamp.timeIntervalSince(lastTime), 0.001)
        var e = east, n = north
        if dt > tuning.velocityResetAfter {
            let vv = tuning.initialVelocitySigma * tuning.initialVelocitySigma
            e.vv = vv; e.pv = 0
            n.vv = vv; n.pv = 0
        }
        let q = tuning.sigmaA * tuning.sigmaA
        e.predict(dt: dt, q: q)
        n.predict(dt: dt, q: q)

        let z = plane.project(fix.coordinate)
        let nuE = z.east - e.p, nuN = z.north - n.p
        let sE = e.pp + r, sN = n.pp + r
        let sigmas = (nuE * nuE / sE + nuN * nuN / sN).squareRoot()
        if sigmas > tuning.gateSigmas || joinsRejectedRun(z, predicted: (e, n), plane: plane, at: fix.timestamp,
                                                          innovation: nuE * nuE + nuN * nuN) {
            return reject(fix, variance: r, sigmas: sigmas)
        }
        e.update(innovation: nuE, s: sE)
        n.update(innovation: nuN, s: sN)
        east = e
        north = n
        self.lastTime = fix.timestamp
        consecutiveRejections = 0
        runFirst = nil
        runLatest = nil
        holdsOnlyFirstFix = false
        reanchorIfFar()
        return .updated
    }

    /// One more rejection: noted for the run, or the re-init at the `reinitialiseAfter`-th.
    private mutating func reject(_ fix: LocationFix, variance r: Double, sigmas: Double) -> Outcome {
        consecutiveRejections += 1
        guard consecutiveRejections >= tuning.reinitialiseAfter else {
            if runFirst == nil { runFirst = Rejected(fix) } else { runLatest = Rejected(fix) }
            return .rejected(sigmas: sigmas)
        }
        reinitialise(at: fix, variance: r)
        return .reinitialised
    }

    /// Whether a fix lies nearer the last rejected fix, moved on at the predicted velocity, than the prediction: it
    /// belongs to the rejected run. Only after a rejection; turns and stops cause none, so they never meet it.
    private func joinsRejectedRun(_ z: Displacement, predicted: (east: Axis, north: Axis), plane: LocalTangentPlane,
                                  at time: Date, innovation: Double) -> Bool {
        guard !holdsOnlyFirstFix, consecutiveRejections > 0, let last = runLatest ?? runFirst else { return false }
        let lag = time.timeIntervalSince(last.time)
        let r = plane.project(last.coordinate)
        let de = z.east - (r.east + predicted.east.v * lag), dn = z.north - (r.north + predicted.north.v * lag)
        return de * de + dn * dn < innovation
    }

    /// Restarts at `fix` with the rejected run's velocity: the line from its first fix to this one, when the middle
    /// fix lies on it within the accuracies (the sum of its own and the larger end's); else at rest, as `initialise`.
    private mutating func reinitialise(at fix: LocationFix, variance r: Double) {
        let first = runFirst, middle = runLatest
        initialise(at: fix, variance: r)
        holdsOnlyFirstFix = false
        guard let first, let plane else { return }
        // Over less than half a second the line is mostly the fixes' error.
        let dt = fix.timestamp.timeIntervalSince(first.time)
        guard dt > 0.5 else { return }
        // In the new plane the fix is the origin: the velocity carries the first fix to it.
        let a = plane.project(first.coordinate)
        if let middle {
            let f = middle.time.timeIntervalSince(first.time) / dt
            let m = plane.project(middle.coordinate)
            let off = Displacement(east: a.east * (1 - f) - m.east, north: a.north * (1 - f) - m.north)
            guard off.length <= middle.accuracy + max(first.accuracy, fix.horizontalAccuracy) else { return }
        }
        // The two ends' variances over Δt², plus 1 (m/s)² for the motion's own change.
        let vv = (pow(max(first.accuracy, tuning.minMeasurementSigma), 2) + r) / (dt * dt) + 1
        east.v = -a.east / dt
        north.v = -a.north / dt
        east.vv = vv
        north.vv = vv
    }

    private mutating func initialise(at fix: LocationFix, variance r: Double) {
        plane = LocalTangentPlane(anchor: fix.coordinate)
        let vv = tuning.initialVelocitySigma * tuning.initialVelocitySigma
        east = Axis(p: 0, v: 0, pp: r, pv: 0, vv: vv)
        north = Axis(p: 0, v: 0, pp: r, pv: 0, vv: vv)
        lastTime = fix.timestamp
        consecutiveRejections = 0
        runFirst = nil
        runLatest = nil
    }

    /// Keeps the plane's scale error negligible: beyond 5 km the anchor moves to the current position. The
    /// velocity and covariance carry over (the axes turn by well under a millidegree over 5 km).
    private mutating func reanchorIfFar() {
        guard let plane, (east.p * east.p + north.p * north.p) > tuning.reanchorDistance * tuning.reanchorDistance
        else { return }
        let here = plane.unproject(Displacement(east: east.p, north: north.p))
        self.plane = LocalTangentPlane(anchor: here)
        east.p = 0
        north.p = 0
    }
}
