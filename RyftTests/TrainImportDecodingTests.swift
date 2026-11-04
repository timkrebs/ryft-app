import Foundation
import Testing
@testable import Ryft

/// The training import's shapes (C2), with fixtures cut from the JSON examples in `../plattform/docs/API.md` →
/// `POST /v1/train/import`, `Session`, `SessionSummary` (ids written out where the doc abbreviates).
@Suite("Training import contract")
struct TrainImportDecodingTests {
    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func fullResponse() throws {
        let r = try Fixture.decode(TrainImportResponse.self, "train_import_response")
        #expect(r.results.count == 5)
        #expect(r.results[0].kind == .plan && r.results[0].status == .created && r.results[0].code == nil)
        #expect(r.results.dropFirst().map(\.status) == [.created, .unchanged, .updated, .rejected])
        let rejected = r.results[4]
        #expect(rejected.code == "unknown_exercise")
        #expect(rejected.message?.hasPrefix("exercise 4f6a1b30") == true)
        #expect(r.daysTouched == ["2026-06-08", "2026-06-10"])
        #expect(r.scoring == SyncScoring(queuedDays: ["2026-06-08", "2026-06-10"], expectedWithinSec: 40))
        #expect(r.requestID == nil)
    }

    @Test func unknownKindIsLenientAndUnknownCodeSurvives() throws {
        let json = #"""
        {"results":[{"kind":"exercise","id":"6a1f3c7e-1b52-5d0a-9c34-7e2b8d4f1a09","status":"created"},
                    {"kind":"routine","id":"3d8c5a21-7e4f-5b96-a0d3-c18f2e6b9047","status":"rejected",
                     "code":"brand_new_reason","message":"field x"}],
         "days_touched":[],"scoring":{"queued_days":[],"expected_within_sec":30}}
        """#
        let r = try APIClient.jsonDecoder.decode(TrainImportResponse.self, from: Data(json.utf8))
        #expect(r.results[0].kind == .exercise)
        #expect(r.results[1].kind == .unknown)
        #expect(r.results[1].code == "brand_new_reason" && r.results[1].status == .rejected)
        #expect(r.daysTouched.isEmpty)
    }

    @Test func emptyRequestAnswer() throws {
        let json = #"{"results":[],"days_touched":[],"scoring":{"queued_days":[],"expected_within_sec":30}}"#
        let r = try APIClient.jsonDecoder.decode(TrainImportResponse.self, from: Data(json.utf8))
        #expect(r.results.isEmpty)
    }

    @Test func importedSessionAndAssistedSet() throws {
        let s = try Fixture.decode(TrainSession.self, "train_session_imported")
        #expect(s.origin == .import && s.importSource == "alpha_progression")
        #expect(s.muscularTrimp == nil && s.workoutId == nil) // not scored yet
        let set = try #require(s.exercises.first?.sets.first)
        #expect(set.assistKg == 20 && set.weightKg == nil)
    }

    @Test func summariesCarryOrigin() throws {
        let list = try Fixture.decode([SessionSummary].self, "train_sessions_origin")
        #expect(list.map(\.origin) == [.app, .import])
        #expect(list[0].importSource == nil && list[1].importSource == "alpha_progression")
        #expect(SessionSummary(try Fixture.decode(TrainSession.self, "train_session_imported")).origin == .import)
    }

    @Test func missingOrUnknownOriginReadsAsApp() throws {
        // Servers before 2026-10-26 send neither field.
        let old = try Fixture.decode(TrainSession.self, "train_session_completed")
        #expect(old.origin == nil && old.resolvedOrigin == .app && old.importSource == nil)
        let sessions = try Fixture.decode([SessionSummary].self, "train_sessions")
        #expect(sessions.allSatisfy { $0.resolvedOrigin == .app && $0.importSource == nil })
        let odd = #"{"id":"a7f2c3d4-5e6f-4a7b-8c9d-0e1f2a3b4c5d","started_at":"2026-10-18T17:02:00Z","origin":"sync"}"#
        #expect(try APIClient.jsonDecoder.decode(TrainSession.self, from: Data(odd.utf8)).origin == .app)
        // A set without assist_kg.
        let set = #"{"id":"a7f2c3d4-5e6f-4a7b-8c9d-0e1f2a3b4c5d","set_index":0}"#
        #expect(try APIClient.jsonDecoder.decode(SessionSet.self, from: Data(set.utf8)).assistKg == nil)
    }

    @Test func requestFixtureRoundTripOmitsOriginAndImportSource() throws {
        // The request's plans are the `PUT /v1/plans/{id}` shape without the resolved `exercise`, which `Plan`
        // (a response shape) requires: decode the fixture's source and sessions, and check the plan keys raw.
        let raw = try object(Fixture.data("train_import_request"))
        #expect(raw["source"] as? String == "alpha_progression" && (raw["plans"] as? [Any])?.count == 1)
        let sessionsJSON = try JSONSerialization.data(withJSONObject: try #require(raw["sessions"]))
        let decoded = try APIClient.jsonDecoder.decode([TrainSession].self, from: sessionsJSON)
        let request = TrainImportRequest(source: try #require(TrainImportSource(rawValue: "alpha_progression")),
                                         plans: [], sessions: decoded)
        #expect(request.sessions.count == 1)
        // The fixture's session has none, and the encoded request must not carry one.
        #expect(request.sessions[0].origin == nil)
        let body = try object(APIClient.jsonEncoder.encode(request))
        #expect(Set(body.keys) == ["source", "plans", "sessions"] && body["source"] as? String == "alpha_progression")
        let session = try #require((body["sessions"] as? [[String: Any]])?.first)
        #expect(session["origin"] == nil && session["import_source"] == nil)
        #expect((session["plan_day_id"] as? String)?.lowercased() == "0c5e9b2a-3d71-5f48-a6b0-91c4e7d2f385")
        let sets = try #require(((session["exercises"] as? [[String: Any]])?[1]["sets"]) as? [[String: Any]])
        #expect(sets[0]["assist_kg"] as? Double == 20)

        // Even a session that came back from the server with an origin is sent without.
        var imported = try Fixture.decode(TrainSession.self, "train_session_imported")
        imported.importSource = "alpha_progression"
        let again = try object(APIClient.jsonEncoder.encode(
            TrainImportRequest(source: .alphaProgression, plans: [], sessions: [imported])))
        let sent = try #require((again["sessions"] as? [[String: Any]])?.first)
        #expect(sent["origin"] == nil && sent["import_source"] == nil)
    }

    @Test func enrollPostEncodesOnlyWhatIsSet() throws {
        #expect(try object(APIClient.jsonEncoder.encode(EnrollPost())).isEmpty)
        let some = try object(APIClient.jsonEncoder.encode(EnrollPost(currentWeek: 3, currentDayIndex: 1)))
        #expect(Set(some.keys) == ["current_week", "current_day_index"])
        #expect(some["current_week"] as? Int == 3)
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let all = try object(APIClient.jsonEncoder.encode(EnrollPost(startedAt: started, currentWeek: 2, currentDayIndex: 0)))
        #expect(Set(all.keys) == ["started_at", "current_week", "current_day_index"])
        #expect(all["started_at"] is String)
    }

    @Test func importErrorCodes() throws {
        #expect(APIErrorCode(rawValue: "import_in_progress") == .importInProgress)
        #expect(APIErrorCode(rawValue: "import_not_enabled") == .importNotEnabled)
        let busy = #"{"error":"import running","code":"import_in_progress","request_id":"r1"}"#
        #expect(try APIClient.jsonDecoder.decode(APIErrorBody.self, from: Data(busy.utf8)).code == .importInProgress)
        let off = #"{"error":"not enabled","code":"import_not_enabled"}"#
        #expect(try APIClient.jsonDecoder.decode(APIErrorBody.self, from: Data(off.utf8)).code == .importNotEnabled)
        // Only the beta gates are gates: a 403 import_not_enabled is not the invite or consent screen.
        #expect(APIError.http(403, "x", code: .importNotEnabled).gate == nil)
        #expect(APIError.http(403, "x", code: .consentRequired).gate == .consentRequired)
        #expect(APIError.http(429, "x", code: .importInProgress, retryAfter: 10).retryAfter == 10)
        #expect(APIErrorCode.allCases.filter(\.isGate) == [.inviteRequired, .consentRequired])
    }
}
