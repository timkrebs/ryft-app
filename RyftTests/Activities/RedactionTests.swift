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

    @Test func mirrorsHaveNoChildren() {
        #expect(Mirror(reflecting: Self.fix).children.isEmpty)
        #expect(Mirror(reflecting: Self.point).children.isEmpty)
        #expect(Mirror(reflecting: Self.fix.coordinate).children.isEmpty)
        #expect(Mirror(reflecting: Displacement(east: 1, north: 2)).children.isEmpty)
    }
}
