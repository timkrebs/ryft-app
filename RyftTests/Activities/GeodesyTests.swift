import Foundation
import Testing
@testable import Ryft

/// Reference values from GeographicLib 2.1 (`Geodesic.WGS84.Inverse` / `.Direct`, Karney's algorithm, accurate to
/// nanometres), an implementation independent of ours. Vincenty agrees with it to well under a millimetre.
@Suite("Geodesy")
struct GeodesyTests {
    struct InverseCase: CustomTestStringConvertible, Sendable {
        let name: String
        let from: Coordinate
        let to: Coordinate
        let distance: Double
        let initialBearing: Double
        let finalBearing: Double
        var testDescription: String { name }

        init(_ name: String, _ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double, _ distance: Double,
             _ initialBearing: Double, _ finalBearing: Double) {
            self.name = name
            from = Coordinate(latitude: lat1, longitude: lon1)
            to = Coordinate(latitude: lat2, longitude: lon2)
            self.distance = distance
            self.initialBearing = initialBearing
            self.finalBearing = finalBearing
        }
    }

    static let inverseCases: [InverseCase] = [
        InverseCase("equator, 1° east", 0, 0, 0, 1, 111_319.490793, 90.0000000000, 90.0000000000),
        InverseCase("equator, short", 0, 10, 0.001, 10.001, 156.903472, 45.1924232116, 45.1924232203),
        InverseCase("equator to 0.5° north-east", 0, 0, 0.5, 0.5, 78451.248031, 45.1913275112, 45.1935092007),
        InverseCase("50° N, 10 m", 50, 8, 50.00009, 8, 10.010616, 0.0000000000, 0.0000000000),
        InverseCase("50° N, 100 km east-ish", 50, 8, 50.1, 9.4, 100_883.447727, 83.1337031851, 84.2069727980),
        InverseCase("50° N, 425 km", 50.1, 8.68, 52.52, 13.4, 425_063.269699, 48.8903125902, 52.5760982138),
        InverseCase("70° N, 771 m", 70, 20, 70.006, 20.01, 770.609273, 29.6957702415, 29.7051673468),
        InverseCase("70° N, 50 km", 70, 20, 70.3, 21.0, 50570.650002, 48.0919667612, 49.0325575473),
        InverseCase("70° N, along the parallel", 70, 0, 70, 10, 381_437.422272, 85.3001419949, 94.6998580051),
    ]

    @Test(arguments: inverseCases)
    func vincentyInverseMatchesReference(_ c: InverseCase) throws {
        let solved = try #require(Geodesy.inverse(c.from, c.to))
        #expect(abs(solved.distance - c.distance) < 0.001, "distance \(solved.distance) vs \(c.distance)")
        // 1e-5° is 0.04″: a few micrometres sideways on the short lines.
        #expect(abs(solved.initialBearing - c.initialBearing) < 1e-5)
        #expect(abs(solved.finalBearing - c.finalBearing) < 1e-5)
        #expect(abs(Geodesy.distance(c.from, c.to) - c.distance) < 0.001)
    }

    struct DirectCase: CustomTestStringConvertible, Sendable {
        let name: String
        let from: Coordinate
        let bearing: Double
        let distance: Double
        let to: Coordinate
        var testDescription: String { name }
    }

    static let directCases: [DirectCase] = [
        DirectCase(name: "50° N, 1 km at 30°", from: Coordinate(latitude: 50, longitude: 8), bearing: 30, distance: 1000,
                   to: Coordinate(latitude: 50.007785748379, longitude: 8.006975040204)),
        DirectCase(name: "70° N, 20 km at 250°", from: Coordinate(latitude: 70, longitude: 20), bearing: 250,
                   distance: 20000, to: Coordinate(latitude: 69.938007187219, longitude: 19.509293010113)),
        DirectCase(name: "0°, 5 km due north", from: Coordinate(latitude: 0, longitude: 0), bearing: 0, distance: 5000,
                   to: Coordinate(latitude: 0.045218473758, longitude: 0)),
    ]

    @Test(arguments: directCases)
    func vincentyDirectMatchesReference(_ c: DirectCase) {
        let to = Geodesy.destination(from: c.from, bearing: c.bearing, distance: c.distance)
        // 1e-9° is about 0.1 mm.
        #expect(abs(to.latitude - c.to.latitude) < 1e-9)
        #expect(abs(to.longitude - c.to.longitude) < 1e-9)
    }

    @Test func directAndInverseAreInverses() throws {
        let from = Coordinate(latitude: 47.87, longitude: 8.0)
        for bearing in stride(from: 0.0, to: 360, by: 37) {
            let to = Geodesy.destination(from: from, bearing: bearing, distance: 1234.5)
            let back = try #require(Geodesy.inverse(from, to))
            #expect(abs(back.distance - 1234.5) < 1e-4) // Vincenty's own precision is about 0.1 mm
            #expect(abs(back.initialBearing - bearing) < 1e-6)
        }
    }

    @Test func coincidentPointsAreZeroApart() {
        let here = Coordinate(latitude: 52.47, longitude: 13.40)
        #expect(Geodesy.distance(here, here) == 0)
    }

    /// Vincenty doesn't converge for nearly antipodal points; the fallback is a great circle (≤ 0.5 % off).
    @Test func nearlyAntipodalFallsBackToAGreatCircle() {
        let a = Coordinate(latitude: 0, longitude: 0), b = Coordinate(latitude: 0.5, longitude: 179.7)
        #expect(Geodesy.inverse(a, b) == nil)
        let reference = 19_944_127.420750
        #expect(abs(Geodesy.distance(a, b) - reference) / reference < 0.005)
    }

    @Test func radiiOfCurvature() {
        let cases: [(latitude: Double, m: Double, n: Double)] = [
            (0, 6_335_439.3272928, 6_378_137.0),
            (50, 6_372_955.9257352, 6_390_702.0441947),
            (70, 6_392_033.1923205, 6_397_072.4882005),
        ]
        for c in cases {
            #expect(abs(Geodesy.meridionalRadius(latitude: c.latitude) - c.m) < 1e-6)
            #expect(abs(Geodesy.primeVerticalRadius(latitude: c.latitude) - c.n) < 1e-6)
        }
    }

    @Test(arguments: [0.0, 50.0, 70.0])
    func tangentPlaneRoundTripsAndMeasuresMetres(latitude: Double) {
        let plane = LocalTangentPlane(anchor: Coordinate(latitude: latitude, longitude: 179.999))
        for d in [Displacement(east: 100, north: 0), Displacement(east: 0, north: -250), Displacement(east: 70, north: 70)] {
            let c = plane.unproject(d)
            let back = plane.project(c)
            #expect(abs(back.east - d.east) < 1e-6 && abs(back.north - d.north) < 1e-6)
            // At the anchor, plane metres are geodesic metres.
            #expect(abs(Geodesy.distance(plane.anchor, c) - d.length) < 0.001)
        }
    }
}
