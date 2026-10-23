import Foundation

/// A WGS84 latitude and longitude in degrees. Never rendered (design §8.3).
struct Coordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

extension Coordinate: LocationRedacting {
    var description: String { "coordinate" }
}

/// East and north metres in a local tangent plane. Never rendered: a privacy zone's offset is one (design §8.2).
struct Displacement: Codable, Hashable, Sendable {
    var east: Double
    var north: Double

    var length: Double { (east * east + north * north).squareRoot() }
}

extension Displacement: LocationRedacting {
    var description: String { "displacement" }
}

/// WGS84 geodesy: Vincenty's inverse and direct solutions and the radii of curvature (ADR 0003).
enum Geodesy {
    static let semiMajorAxis = 6_378_137.0
    static let flattening = 1 / 298.257_223_563
    static let semiMinorAxis = semiMajorAxis * (1 - flattening)
    static let eccentricitySquared = flattening * (2 - flattening)

    /// The meridional radius of curvature M at a latitude in degrees: metres per radian of latitude.
    static func meridionalRadius(latitude: Double) -> Double {
        let s = sin(latitude * .pi / 180)
        let w = 1 - eccentricitySquared * s * s
        return semiMajorAxis * (1 - eccentricitySquared) / (w * w.squareRoot())
    }

    /// The prime-vertical radius of curvature N at a latitude in degrees.
    static func primeVerticalRadius(latitude: Double) -> Double {
        let s = sin(latitude * .pi / 180)
        return semiMajorAxis / (1 - eccentricitySquared * s * s).squareRoot()
    }

    struct Inverse: Sendable, Equatable {
        /// Metres along the ellipsoid.
        let distance: Double
        /// Degrees clockwise from north, in [0, 360).
        let initialBearing: Double
        let finalBearing: Double
    }

    /// Vincenty's inverse solution. Nil when the iteration doesn't converge (nearly antipodal points).
    static func inverse(_ from: Coordinate, _ to: Coordinate) -> Inverse? {
        let a = semiMajorAxis, b = semiMinorAxis, f = flattening
        let lon = normalisedRadians((to.longitude - from.longitude) * .pi / 180)
        let u1 = atan((1 - f) * tan(from.latitude * .pi / 180))
        let u2 = atan((1 - f) * tan(to.latitude * .pi / 180))
        let sinU1 = sin(u1), cosU1 = cos(u1), sinU2 = sin(u2), cosU2 = cos(u2)

        var lambda = lon
        var iterations = 0
        var sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0, cosSqAlpha = 0.0, cos2SigmaM = 0.0
        var sinLambda = 0.0, cosLambda = 0.0
        while true {
            sinLambda = sin(lambda)
            cosLambda = cos(lambda)
            let t1 = cosU2 * sinLambda
            let t2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda
            sinSigma = (t1 * t1 + t2 * t2).squareRoot()
            if sinSigma == 0 { return Inverse(distance: 0, initialBearing: 0, finalBearing: 0) }
            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
            sigma = atan2(sinSigma, cosSigma)
            let sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
            cosSqAlpha = 1 - sinAlpha * sinAlpha
            // On the equator cos²α is 0 and cos 2σm is undefined; its term vanishes with C.
            cos2SigmaM = cosSqAlpha == 0 ? 0 : cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha
            let c = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha))
            let previous = lambda
            lambda = lon + (1 - c) * f * sinAlpha
                * (sigma + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
            iterations += 1
            if abs(lambda - previous) <= 1e-12 { break }
            if iterations >= 200 { return nil }
        }
        let uSq = cosSqAlpha * (a * a - b * b) / (b * b)
        let bigA = 1 + uSq / 16_384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let bigB = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))
        let deltaSigma = bigB * sinSigma * (cos2SigmaM + bigB / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
                - bigB / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
        let distance = b * bigA * (sigma - deltaSigma)
        let alpha1 = atan2(cosU2 * sinLambda, cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
        let alpha2 = atan2(cosU1 * sinLambda, -sinU1 * cosU2 + cosU1 * sinU2 * cosLambda)
        return Inverse(distance: distance, initialBearing: degrees0to360(alpha1), finalBearing: degrees0to360(alpha2))
    }

    /// The geodesic distance in metres. Falls back to a great circle on the mean radius for the rare nearly
    /// antipodal pair Vincenty can't solve (never the case for steps between fixes).
    static func distance(_ from: Coordinate, _ to: Coordinate) -> Double {
        if let solved = inverse(from, to) { return solved.distance }
        let phi1 = from.latitude * .pi / 180, phi2 = to.latitude * .pi / 180
        let dPhi = phi2 - phi1, dLambda = (to.longitude - from.longitude) * .pi / 180
        let h = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        let meanRadius = (2 * semiMajorAxis + semiMinorAxis) / 3
        return 2 * meanRadius * asin(min(1, h.squareRoot()))
    }

    /// Vincenty's direct solution: the point `distance` metres from `from` along the initial bearing (degrees).
    static func destination(from: Coordinate, bearing: Double, distance: Double) -> Coordinate {
        let a = semiMajorAxis, b = semiMinorAxis, f = flattening
        let alpha1 = bearing * .pi / 180
        let sinAlpha1 = sin(alpha1), cosAlpha1 = cos(alpha1)
        let tanU1 = (1 - f) * tan(from.latitude * .pi / 180)
        let cosU1 = 1 / (1 + tanU1 * tanU1).squareRoot(), sinU1 = tanU1 * cosU1
        let sigma1 = atan2(tanU1, cosAlpha1)
        let sinAlpha = cosU1 * sinAlpha1
        let cosSqAlpha = 1 - sinAlpha * sinAlpha
        let uSq = cosSqAlpha * (a * a - b * b) / (b * b)
        let bigA = 1 + uSq / 16_384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let bigB = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))

        var sigma = distance / (b * bigA)
        var cos2SigmaM = 0.0, sinSigma = 0.0, cosSigma = 0.0
        for _ in 0 ..< 200 {
            cos2SigmaM = cos(2 * sigma1 + sigma)
            sinSigma = sin(sigma)
            cosSigma = cos(sigma)
            let deltaSigma = bigB * sinSigma * (cos2SigmaM + bigB / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
                    - bigB / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
            let next = distance / (b * bigA) + deltaSigma
            if abs(next - sigma) <= 1e-12 { sigma = next; break }
            sigma = next
        }
        cos2SigmaM = cos(2 * sigma1 + sigma)
        sinSigma = sin(sigma)
        cosSigma = cos(sigma)
        let t = sinU1 * sinSigma - cosU1 * cosSigma * cosAlpha1
        let phi2 = atan2(sinU1 * cosSigma + cosU1 * sinSigma * cosAlpha1,
                         (1 - f) * (sinAlpha * sinAlpha + t * t).squareRoot())
        let lambda = atan2(sinSigma * sinAlpha1, cosU1 * cosSigma - sinU1 * sinSigma * cosAlpha1)
        let c = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha))
        let l = lambda - (1 - c) * f * sinAlpha
            * (sigma + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
        let longitude = normalisedRadians(from.longitude * .pi / 180 + l) * 180 / .pi
        return Coordinate(latitude: phi2 * 180 / .pi, longitude: longitude)
    }

    /// An angle in radians folded into (−π, π].
    static func normalisedRadians(_ angle: Double) -> Double {
        var x = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x <= -.pi { x += 2 * .pi }
        return x
    }

    private static func degrees0to360(_ radians: Double) -> Double {
        let d = (radians * 180 / .pi).truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }
}

/// East and north metres around an anchor: WGS84 meridional and prime-vertical radii at the anchor's latitude
/// (ADR 0003). The mapping is linear, so `unproject(project(c)) == c` up to rounding; distances are measured
/// geodesically on the unprojected coordinates, never in the plane.
struct LocalTangentPlane: Sendable, Equatable {
    let anchor: Coordinate
    private let metresPerRadianNorth: Double
    private let metresPerRadianEast: Double

    init(anchor: Coordinate) {
        self.anchor = anchor
        metresPerRadianNorth = Geodesy.meridionalRadius(latitude: anchor.latitude)
        metresPerRadianEast = Geodesy.primeVerticalRadius(latitude: anchor.latitude) * cos(anchor.latitude * .pi / 180)
    }

    func project(_ c: Coordinate) -> Displacement {
        let dLat = (c.latitude - anchor.latitude) * .pi / 180
        let dLon = Geodesy.normalisedRadians((c.longitude - anchor.longitude) * .pi / 180)
        return Displacement(east: dLon * metresPerRadianEast, north: dLat * metresPerRadianNorth)
    }

    func unproject(_ d: Displacement) -> Coordinate {
        let lat = anchor.latitude + d.north / metresPerRadianNorth * 180 / .pi
        let lonRadians = Geodesy.normalisedRadians(anchor.longitude * .pi / 180 + d.east / metresPerRadianEast)
        return Coordinate(latitude: lat, longitude: lonRadians * 180 / .pi)
    }
}
