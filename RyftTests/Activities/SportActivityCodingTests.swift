import Foundation
import Testing
@testable import Ryft

/// The wire draft (design.md §2.2), from the platform brief's shapes until API.md → Activities is published
/// (C1 adds one fixture test per shape from its examples).
@Suite("Activities: wire draft")
struct SportActivityCodingTests {
    /// The brief's `Activity`, as the platform answers it (server fields included).
    static let answer = """
    {
      "id": "6f1c2a9e-3b7d-4c8e-9a1f-2d4e6b8c0a12",
      "sport": "trail_running", "origin": "recorded",
      "start": "2026-10-22T05:12:00Z", "end": "2026-10-22T06:20:31.250Z", "moving_sec": 3890.5,
      "distance_m": 10240.7, "ascent_m": 412, "descent_m": 398.5,
      "perceived_effort": 7, "notes": "Foggy ridge",
      "splits": [{"index": 1, "distance_m": 1000, "duration_sec": 371.2, "ascent_m": 38},
                 {"index": 11, "distance_m": 240.7, "duration_sec": 92, "ascent_m": null}],
      "route": "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
      "hr_samples": [{"t": "2026-10-22T05:12:05Z", "bpm": 121}, {"t": "2026-10-22T05:12:10Z", "bpm": 124.5}],
      "client_updated_at": "2026-10-22T06:25:00Z",
      "strain": 11.4, "strain_source": "heart_rate", "hr_source": "Garmin Connect",
      "merged_with": "00000000-0000-4000-8000-000000000011", "scoring_state": "scored"
    }
    """

    private static func decode(_ json: String) throws -> SportActivity {
        try APIClient.jsonDecoder.decode(SportActivity.self, from: Data(json.utf8))
    }

    /// The keys of `value` encoded with the app's coder.
    private static func keys<T: Encodable>(_ value: T) throws -> Set<String> {
        let data = try APIClient.jsonEncoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Set((object ?? [:]).keys)
    }

    @Test func theBriefsActivityDecodes() throws {
        let a = try Self.decode(Self.answer)
        #expect(a.id == UUID(uuidString: "6f1c2a9e-3b7d-4c8e-9a1f-2d4e6b8c0a12"))
        #expect(a.sport == .trailRunning && a.origin == .recorded)
        #expect(a.end.timeIntervalSince(a.start) == 4_111.25 && a.movingSec == 3_890.5)
        #expect(a.distanceM == 10_240.7 && a.ascentM == 412 && a.descentM == 398.5)
        #expect(a.perceivedEffort == 7 && a.notes == "Foggy ridge")
        #expect(a.splits == [ActivitySplit(index: 1, distanceM: 1000, durationSec: 371.2, ascentM: 38),
                             ActivitySplit(index: 11, distanceM: 240.7, durationSec: 92, ascentM: nil)])
        #expect(a.route == "_p~iF~ps|U_ulLnnqC_mqNvxq`@" && a.hrSamples?.map(\.bpm) == [121, 124.5])
        #expect(a.strain == 11.4 && a.strainSource == .heartRate && a.hrSource == "Garmin Connect")
        #expect(a.mergedWith == UUID(uuidString: "00000000-0000-4000-8000-000000000011"))
        #expect(a.scoringState == "scored")
    }

    @Test func aMinimalActivityDecodes() throws {
        let a = try Self.decode("""
        {"id": "6f1c2a9e-3b7d-4c8e-9a1f-2d4e6b8c0a12", "sport": "yoga", "origin": "manual",
         "start": "2026-10-22T17:00:00Z", "end": "2026-10-22T18:00:00Z", "moving_sec": 3600,
         "client_updated_at": "2026-10-22T18:05:00Z", "scoring_state": "pending"}
        """)
        #expect(a.sport == .yoga && a.distanceM == nil && a.splits == nil && a.route == nil && a.hrSamples == nil)
        #expect(a.strain == nil && a.strainSource == nil && a.mergedWith == nil && a.scoringState == "pending")
    }

    @Test func unknownValuesFallBackInsteadOfFailing() throws {
        var json = Self.answer.replacingOccurrences(of: "\"trail_running\"", with: "\"kitesurfing\"")
        json = json.replacingOccurrences(of: "\"recorded\"", with: "\"imported\"")
        json = json.replacingOccurrences(of: "\"heart_rate\"", with: "\"power_meter\"")
        let a = try Self.decode(json)
        #expect(a.sport == .other)
        #expect(a.origin == .manual)
        // An unknown source is shown like a missing one, never as "no heart rate".
        #expect(a.strainSource == nil && a.strain == 11.4)
        let none = try Self.decode(Self.answer.replacingOccurrences(of: "\"heart_rate\"", with: "\"none\""))
        #expect(none.strainSource == .noSource)
        let effort = try Self.decode(Self.answer.replacingOccurrences(of: "\"heart_rate\"", with: "\"perceived_effort\""))
        #expect(effort.strainSource == .perceivedEffort)
    }

    @Test func thePutBodyLeavesOutWhatThePlatformSets() throws {
        let a = try Self.decode(Self.answer)
        let keys = try Self.keys(SportActivityPut(a))
        #expect(keys == ["id", "sport", "origin", "start", "end", "moving_sec", "distance_m", "ascent_m", "descent_m",
                         "perceived_effort", "notes", "splits", "route", "hr_samples", "client_updated_at"])
        for server in ["strain", "strain_source", "hr_source", "merged_with", "scoring_state"] {
            #expect(!keys.contains(server), "\(server)")
        }
        // Absent optionals are left out, not sent as null.
        var minimal = a
        minimal.distanceM = nil
        minimal.notes = nil
        minimal.splits = nil
        minimal.route = nil
        minimal.hrSamples = nil
        #expect(try Self.keys(SportActivityPut(minimal)) == ["id", "sport", "origin", "start", "end", "moving_sec",
                                                              "ascent_m", "descent_m", "perceived_effort",
                                                              "client_updated_at"])
    }

    @Test func thePutBodyDecodesBackWithoutServerFields() throws {
        let a = try Self.decode(Self.answer)
        let data = try APIClient.jsonEncoder.encode(SportActivityPut(a))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"sport\":\"trail_running\"") && json.contains("\"id\":\"6F1C2A9E"))
        let back = try APIClient.jsonDecoder.decode(SportActivity.self, from: data)
        #expect(back.sport == a.sport && back.splits == a.splits && back.route == a.route)
        #expect(back.strain == nil && back.strainSource == nil && back.mergedWith == nil && back.scoringState == nil)
    }

    /// The read model caches the platform's answer whole: the strain and the merge survive a round trip.
    @Test func theCachedCopyKeepsTheServerFields() throws {
        // The app's coder writes whole seconds (`.iso8601`), as for every cached wire value.
        let whole = Self.answer.replacingOccurrences(of: "06:20:31.250Z", with: "06:20:31Z")
        let a = try Self.decode(whole).withoutRouteOrHeartRate
        let back = try #require(WireCoding.decode(SportActivity.self, WireCoding.encode(a)))
        #expect(back == a)
        #expect(back.route == nil && back.hrSamples == nil && back.strain == 11.4 && back.mergedWith != nil)
    }

    @Test func manualSleepPutEncodesBedAndWake() throws {
        let bed = Date(timeIntervalSince1970: 1_792_450_800)
        let body = ManualSleepPut(bed: bed, wake: bed.addingTimeInterval(7.5 * 3600))
        #expect(try Self.keys(body) == ["bed", "wake"])
        let back = try APIClient.jsonDecoder.decode(ManualSleepPut.self, from: APIClient.jsonEncoder.encode(body))
        #expect(back == body)
    }

    @Test func anUploadAttemptKeepsItsRequestID() throws {
        let attempt = UploadAttempt(at: Date(timeIntervalSince1970: 1_792_450_800), request: .delete, status: 422,
                                    code: "validation_failed", requestID: "01HZX-req", kind: .other)
        let data = try #require(WireCoding.encode(attempt))
        #expect(String(bytes: data, encoding: .utf8)?.contains("\"request_id\":\"01HZX-req\"") == true)
        #expect(WireCoding.decode(UploadAttempt.self, data) == attempt)
    }
}
