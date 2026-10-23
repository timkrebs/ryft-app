import Foundation
import Testing
@testable import Ryft

/// No coordinate in any rendering of a location type (design §8.3): `print`, `debugPrint`, `dump` and string
/// interpolation show accuracy at most. A3b adds `PrivacyZone`.
@Suite("Location redaction")
struct RedactionTests {
    static let fix = LocationFix(timestamp: .now, latitude: 52.473_137_24, longitude: 13.401_510_65, altitude: 38.5,
                                 horizontalAccuracy: 6.4, verticalAccuracy: 4, speed: 3.1)
    static let point = RoutePoint(time: .now, latitude: 52.473_137_24, longitude: 13.401_510_65, horizontalAccuracy: 4.2,
                                  altitude: 38.5)

    static func renderings(_ value: some Any) -> [String] {
        var dumped = ""
        dump(value, to: &dumped)
        var printed = ""
        print(value, to: &printed)
        var debugPrinted = ""
        debugPrint(value, to: &debugPrinted)
        return [String(describing: value), String(reflecting: value), "\(value)", dumped, printed, debugPrinted]
    }

    @Test func locationTypesNeverRenderCoordinates() {
        let values: [Any] = [Self.fix, Self.point, Self.fix.coordinate, Displacement(east: 123.456, north: -78.9),
                             [Self.point], Optional(Self.fix) as Any]
        for value in values {
            for text in Self.renderings(value) {
                for digits in ["52.47", "13.40", "52,47", "13,40", "123.4", "78.9", "38.5"] {
                    #expect(!text.contains(digits), "\(type(of: value)) rendered \(digits)")
                }
            }
        }
        #expect(String(describing: Self.fix) == "fix(±6 m)")
        #expect(String(describing: Self.point) == "routePoint(±4 m)")
    }

    /// The logging-safe path must never trap: NaN and ±∞ accuracy render as "?".
    @Test(arguments: [Double.nan, .infinity, -.infinity, 1e300])
    func descriptionsSurviveNonFiniteAccuracy(_ accuracy: Double) {
        let fix = LocationFix(timestamp: .now, latitude: 52.47, longitude: 13.4, horizontalAccuracy: accuracy)
        let point = RoutePoint(time: .now, latitude: 52.47, longitude: 13.4, horizontalAccuracy: accuracy, altitude: nil)
        #expect(String(describing: fix) == "fix(±? m)")
        #expect(String(describing: point) == "routePoint(±? m)")
    }

    /// The tangent plane's east scale (N·cos φ) gives its anchor's latitude back exactly, so the plane, the filter
    /// and the pipeline holding them render nothing of it either.
    @Test func filterPlaneAndPipelineRenderNoLocation() {
        var p = TrackPipeline(configuration: .gps(.run, barometer: false))
        p.start(at: SyntheticTrack.t0)
        _ = SyntheticTrack.run(&p, SyntheticTrack.fixes([SyntheticTrack.Segment(seconds: 5, speed: 3)]))
        let plane = LocalTangentPlane(anchor: SyntheticTrack.origin)
        var kalman = KalmanTrack(tuning: KalmanTrack.Tuning(sigmaA: 1.5))
        _ = kalman.update(Self.fix)
        let values: [Any] = [plane, kalman, p]
        for value in values {
            for text in Self.renderings(value) {
                for digits in ["52.47", "13.40", "52,47", "13,40"] {
                    #expect(!text.contains(digits), "\(type(of: value)) rendered \(digits)")
                }
            }
        }
    }

    @Test func mirrorsHaveNoChildren() {
        #expect(Mirror(reflecting: Self.fix).children.isEmpty)
        #expect(Mirror(reflecting: Self.point).children.isEmpty)
        #expect(Mirror(reflecting: Self.fix.coordinate).children.isEmpty)
        #expect(Mirror(reflecting: Displacement(east: 1, north: 2)).children.isEmpty)
    }
}
