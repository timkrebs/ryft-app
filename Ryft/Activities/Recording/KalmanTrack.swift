import Foundation

/// A constant-velocity Kalman filter for GPS fixes (ADR 0003, design §3.3 step 3).
///
/// - Two states per axis (position, velocity), east and north in a `LocalTangentPlane` anchored at the first fix
///   and re-anchored every 5 km. The anchor is held in memory only; nothing here is ever checkpointed.
/// - Measurement variance `max(horizontalAccuracy, 3 m)²`; white-acceleration process noise with `sigmaA`
///   (continuous model, so a variable Δt scales correctly).
/// - Innovation gate at 3.5σ (Mahalanobis distance over both axes). A rejected fix leaves the state untouched;
///   three rejections in a row re-initialise at the third measurement (a real jump, a tunnel exit).
/// - Δt over 15 s resets the velocity variance before predicting, so the next fix sets the velocity again.
///
/// Pure and `Sendable`; a few dozen floating-point operations and no allocation per fix.
struct KalmanTrack: Sendable {
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
        /// The gate rejected `reinitialiseAfter` fixes in a row: the filter restarted at this one.
        case reinitialised
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

    init(tuning: Tuning) {
        self.tuning = tuning
    }

    var isInitialised: Bool { plane != nil }

    /// The filtered position at `lastTime`.
    var position: Coordinate? {
        plane?.unproject(Displacement(east: east.p, north: north.p))
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

    /// Forgets everything: the next fix initialises (a resume after a kill, design §3.9).
    mutating func reset() {
        plane = nil
        east = Axis()
        north = Axis()
        lastTime = nil
        consecutiveRejections = 0
    }

    mutating func update(_ fix: LocationFix) -> Outcome {
        let r = pow(max(fix.horizontalAccuracy, tuning.minMeasurementSigma), 2)
        guard let plane, let lastTime else {
            initialise(at: fix, variance: r)
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
        if sigmas > tuning.gateSigmas {
            consecutiveRejections += 1
            if consecutiveRejections >= tuning.reinitialiseAfter {
                initialise(at: fix, variance: r)
                return .reinitialised
            }
            return .rejected(sigmas: sigmas)
        }
        e.update(innovation: nuE, s: sE)
        n.update(innovation: nuN, s: sN)
        east = e
        north = n
        self.lastTime = fix.timestamp
        consecutiveRejections = 0
        reanchorIfFar()
        return .updated
    }

    private mutating func initialise(at fix: LocationFix, variance r: Double) {
        plane = LocalTangentPlane(anchor: fix.coordinate)
        let vv = tuning.initialVelocitySigma * tuning.initialVelocitySigma
        east = Axis(p: 0, v: 0, pp: r, pv: 0, vv: vv)
        north = Axis(p: 0, v: 0, pp: r, pv: 0, vv: vv)
        lastTime = fix.timestamp
        consecutiveRejections = 0
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
