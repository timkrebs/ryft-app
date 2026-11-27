#if DEBUG
import Foundation
import Testing
@testable import Ryft

struct LocalGarminTests {
    private let pin = String(repeating: "a", count: 64)
    private let token = String(repeating: "b", count: 64)

    @Test func pairingTargetsOnlyTheLocalActivitiesEndpoint() throws {
        let pairing = try #require(LocalGarminPairing("https://192.168.1.31:8785#\(pin).\(token)\n"))
        #expect(pairing.endpoint.absoluteString == "https://192.168.1.31:8785/v1/local/garmin/activities")
        #expect(pairing.fingerprint == pin && pairing.token == token)
    }

    @Test(arguments: [
        "http://192.168.1.31:8785",
        "https://api.ryftlab.de:8785",
        "https://172.15.10.11:8785",
        "https://192.168.1.31:443",
        "https://user@192.168.1.31:8785",
        "https://192.168.1.31:8785/other",
        "https://192.168.1.31:8785?extra=1",
    ])
    func rejectsOtherOriginsAndRoutes(_ origin: String) {
        #expect(LocalGarminPairing("\(origin)#\(pin).\(token)") == nil)
    }

    @Test func decodesTheLocalGarminSnapshot() throws {
        let json = #"""
        {"provider":"garmin","fetched_at":"2026-11-25T08:00:09.111111+00:00",
         "activities":[{"sport":"running","started_at_local":"2026-11-25 08:45:33","duration_seconds":1800,"distance_meters":5000}]}
        """#
        let value = try APIClient.jsonDecoder.decode(LocalGarminSnapshot.self, from: Data(json.utf8))
        #expect(value.provider == "garmin" && value.activities.count == 1)
        #expect(value.activities.first?.durationSeconds == 1800 && value.activities.first?.distanceMeters == 5000)
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .cannotConnectToHost, .timedOut])
    func reportsUnreachableMacSeparatelyFromCertificateErrors(_ code: URLError.Code) {
        #expect(LocalGarminFailure(transport: code) == .network)
        #expect(LocalGarminFailure(transport: .serverCertificateUntrusted) == .certificate)
        #expect(LocalGarminFailure(transport: .cancelled) == .certificate)
    }

    @Test func loadsRecentUSBPreviewAndRejectsStaleCopy() throws {
        let data = Data(#"{"provider":"garmin","fetched_at":"2026-11-25T08:00:00+00:00","activities":[]}"#.utf8)
        let fetched = try #require(DateParsing.rfc3339("2026-11-25T08:00:00+00:00"))
        #expect(try LocalGarminSnapshot.decodeUSB(data, now: fetched.addingTimeInterval(10)).activities.isEmpty)
        #expect(throws: LocalGarminFailure.usbExpired) {
            try LocalGarminSnapshot.decodeUSB(data, now: fetched.addingTimeInterval(1801))
        }
    }
}
#endif
