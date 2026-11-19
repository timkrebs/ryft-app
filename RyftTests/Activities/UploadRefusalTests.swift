import Foundation
import Testing
@testable import Ryft

/// ADR 0022 §1: what's a refusal and what's a hold, the one definition both outboxes use (`UploadAttempt.isRefusal`),
/// as API.md → Errors says: the listed refusals, "any other `4xx` … is like `400`", and a request this build couldn't
/// make. Then each outbox: the activities uploader and Train's, and the export's state for each.
@Suite("Refusals and holds (ADR 0022 §1)")
@MainActor
struct UploadRefusalTests {
    private static let requests: [UploadAttempt.Request] = [.put, .delete, .complete, .create]

    /// The attempt an outbox records for `error`.
    private static func attempt(_ error: Error, _ request: UploadAttempt.Request) -> UploadAttempt {
        let api = error as? APIError
        return UploadAttempt(at: Date(timeIntervalSince1970: 1_795_000_000), request: request, status: api?.status,
                             code: api?.code?.rawValue, requestID: api?.requestID, kind: FailureKind.of(error))
    }

    /// A body this build can't encode (a weight that isn't finite): thrown before any request goes.
    private static var unencodable: Error {
        EncodingError.invalidValue(Double.infinity, EncodingError.Context(codingPath: [], debugDescription: "inf"))
    }

    @Test(arguments: [400, 405, 409, 410, 411, 413, 415, 422, 431, 451, 499])
    func anyOther4xxIsARefusal(_ status: Int) {
        for request in Self.requests {
            #expect(Self.attempt(APIError.http(status, "refused"), request).isRefusal, "\(status) \(request)")
        }
    }

    /// What the contract says to wait out or send again: a sign-out, every `403`, `408`, `426` (app-too-old, reserved),
    /// `429`, every `5xx`; and no `2xx` or `3xx` is one either.
    @Test(arguments: [401, 403, 408, 426, 429, 500, 501, 502, 503, 504, 599, 200, 201, 204, 301, 304])
    func holdsAreNoRefusal(_ status: Int) {
        for request in Self.requests {
            #expect(!Self.attempt(APIError.http(status, "held"), request).isRefusal, "\(status) \(request)")
        }
        let gate = Self.attempt(APIError.http(403, "consent", code: .consentRequired), .put)
        #expect(gate.kind == .gate && !gate.isRefusal)
    }

    /// A `404` is a refusal only on `complete` (the platform has no such session); on a `PUT`, `DELETE` or `POST` it's
    /// a route that isn't there.
    @Test func a404IsARefusalOnlyOnComplete() {
        let refused = Self.requests.filter { Self.attempt(APIError.http(404, "not found"), $0).isRefusal }
        #expect(refused == [.complete])
    }

    /// No answer: a request this build couldn't make is a refusal; no network, a cancellation or no session isn't.
    @Test func withoutAnAnswerOnlyAnUnencodableBodyIsARefusal() {
        for request in Self.requests {
            #expect(Self.attempt(Self.unencodable, request).isRefusal)
            #expect(!Self.attempt(APIError.transport(URLError(.notConnectedToInternet)), request).isRefusal)
            #expect(!Self.attempt(URLError(.timedOut), request).isRefusal)
            #expect(!Self.attempt(CancellationError(), request).isRefusal)
            #expect(!Self.attempt(APIError.signedOut, request).isRefusal)
        }
    }

    @Test func an2xxTheAppCantReadWasDelivered() {
        #expect(APIError.http(200, "unreadable").wasDelivered && APIError.http(204, "").wasDelivered)
        #expect(APIError.http(299, "").wasDelivered)
        #expect(!APIError.http(300, "").wasDelivered && !APIError.http(199, "").wasDelivered)
        #expect(!APIError.http(422, "").wasDelivered && !APIError.signedOut.wasDelivered)
        #expect(!APIError.transport(URLError(.timedOut)).wasDelivered && !APIError.notConfigured.wasDelivered)
    }

    /// Train's outbox reads the same definition; no server configured holds (nothing went out, nothing is wrong
    /// with the document), and a `2xx` it can't read was delivered.
    @Test func trainsDispositionFollowsTheDefinition() {
        let at = Date(timeIntervalSince1970: 1_795_000_000)
        func disposition(_ error: Error, _ kind: PendingTrainOp.Kind = .put) -> TrainSyncService.Disposition {
            TrainSyncService.disposition(of: kind, error, at: at)
        }
        #expect(disposition(APIError.http(200, "unreadable")) == .delivered)
        #expect(disposition(APIError.http(201, "unreadable"), .exercise) == .delivered)
        #expect(disposition(APIError.notConfigured) == .hold)
        #expect(disposition(APIError.signedOut) == .hold)
        #expect(disposition(APIError.transport(URLError(.timedOut))) == .hold)
        for status in [403, 408, 426, 429, 501, 503] {
            #expect(disposition(APIError.http(status, "")) == .hold, "\(status)")
        }
        #expect(disposition(APIError.http(404, "")) == .hold)
        #expect(disposition(APIError.http(404, ""), .complete) == .refused(Self.attempt(APIError.http(404, ""), .complete)))
        #expect(disposition(APIError.http(405, "")) == .refused(Self.attempt(APIError.http(405, ""), .put)))
        #expect(disposition(Self.unencodable) == .refused(Self.attempt(Self.unencodable, .put)))
        #expect(disposition(Self.unencodable, .exercise) == .refused(Self.attempt(Self.unencodable, .create)))
    }

    // MARK: the activities uploader

    /// A `403` without a gate code and a `426` hold: the row backs off and goes again on the clock, never refused.
    @Test(arguments: [403, 426])
    func activityHolds(_ status: Int) async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = APIError.http(status, "held", requestID: "req-\(status)")
        await h.uploader.flush()
        let attempt = try #require(h.store.snapshot(id: id)?.lastAttempt)
        #expect(attempt.status == status && attempt.requestID == "req-\(status)" && !attempt.isRefusal)
        #expect(h.uploader.state(of: id) == .pending(.retrying(at: h.clock.now().addingTimeInterval(30))))
        #expect(h.uploader.retryAt == h.clock.now().addingTimeInterval(30))
        #expect(await eventually { h.clock.pendingSleeps == 1 }) // the retry is waiting on the clock
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { h.uploader.state(of: id) == .confirmed })
        #expect(h.puts() == 2)
    }

    /// A `405` (a `4xx` the contract doesn't list) and a body this build can't encode are refusals: kept with Retry,
    /// never sent again on their own, and the next row still goes.
    @Test(arguments: [0, 405])
    func activityRefusals(_ status: Int) async throws {
        let h = UploadHarness()
        let refused = try #require(h.save(minutesAgo: 120))
        let next = try #require(h.save(minutesAgo: 60))
        h.api.failNext = status == 0 ? Self.unencodable : APIError.http(status, "method not allowed", requestID: "req-405")
        await h.uploader.flush()
        let attempt = try #require(h.store.snapshot(id: refused)?.lastAttempt)
        #expect(attempt.status == (status == 0 ? nil : status) && attempt.kind == .other && attempt.isRefusal)
        #expect(h.uploader.state(of: refused) == .failed(attempt))
        #expect(h.store.snapshot(id: refused)?.sentAt == nil)  // nothing was stored there
        #expect(h.uploader.state(of: next) == .confirmed)
        #expect(h.uploader.retryAt == nil && h.uploader.backoffs.isEmpty)
        await h.uploader.flush()
        #expect(h.puts() == 2)
        await h.uploader.retry(refused)
        #expect(h.puts() == 3 && h.uploader.state(of: refused) == .confirmed)
    }

    /// S2: a `2xx` this build couldn't read was delivered. The row is confirmed with the document sent (no attempt, no
    /// backoff), My Day hears of it, and it isn't sent again; a delete of it then goes to the platform.
    @Test func anUnreadableAnswerToAnActivityIsDelivered() async throws {
        let h = UploadHarness()
        var confirmed: [(SportActivity, [String])] = []
        h.uploader.onConfirmed = { confirmed.append(($0, $1)) }
        let id = try #require(h.save(notes: "Hill reps"))
        h.api.failNext = APIError.http(200, "unreadable", requestID: "req-200")
        await h.uploader.flush()
        let row = try #require(h.store.snapshot(id: id))
        #expect(row.confirmedRevision == 1 && !row.needsUpload && row.lastAttempt == nil)
        #expect(h.uploader.state(of: id) == .confirmed)
        #expect(h.uploader.retryAt == nil && h.uploader.backoffs.isEmpty)
        #expect(confirmed.map { $0.0.id } == [id] && confirmed.first?.0.notes == "Hill reps")
        #expect(confirmed.first?.1 == [h.today])
        await h.uploader.flush()
        #expect(h.puts() == 1)

        h.uploader.deleted(id)
        #expect(h.store.snapshot(id: id)?.isTombstone == true)
        h.api.failNext = APIError.http(200, "unreadable")
        await h.uploader.flush()
        #expect(h.deletes() == 1 && h.store.snapshot(id: id) == nil)
        #expect(h.uploader.backoffs.isEmpty)
    }

    /// The same for a night: confirmed, not sent again.
    @Test func anUnreadableAnswerToANightIsDelivered() async throws {
        let h = UploadHarness()
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        h.api.failNext = APIError.http(200, "unreadable")
        await h.uploader.flush()
        let kept = try #require(h.store.manualSleep(onDay: night.day))
        #expect(!kept.needsUpload && kept.lastAttempt == nil)
        #expect(h.uploader.backoffs.isEmpty && h.uploader.pendingCount == 0)
        await h.uploader.flush()
        #expect(h.api.count("putManualSleep") == 1)
    }

    // MARK: the export

    /// "Export my data" names each state as the uploader has it: refused (`405`, a body this build can't encode),
    /// pending (a `403` without a code, `426`: held), and a delivered one isn't among the unconfirmed rows.
    @Test func theExportNamesEachState() async throws {
        let h = UploadHarness()
        var ids: [String: UUID] = [:]
        let errors: [(String, Error)] = [("405", APIError.http(405, "")), ("unencodable", Self.unencodable),
                                         ("403", APIError.http(403, "forbidden")), ("426", APIError.http(426, "")),
                                         ("200", APIError.http(200, "unreadable"))]
        for (index, (name, error)) in errors.enumerated() {
            let id = try #require(h.save(minutesAgo: Double(500 - index * 60)))
            ids[name] = id
            h.api.failNext = error
            await h.uploader.flush()
        }
        let archive = try await DataExport.archive(source: h.api, train: h.api, activities: h.api, onPhone: h.store,
                                                   now: h.clock.now())
        let states = Dictionary(uniqueKeysWithValues: archive.unconfirmedActivities.map { ($0.activity.id, $0.state) })
        let r405 = try #require(ids["405"]), unencodable = try #require(ids["unencodable"])
        let r403 = try #require(ids["403"]), r426 = try #require(ids["426"])
        let expected: [UUID: String] = [r405: "refused", unencodable: "refused", r403: "pending", r426: "pending"]
        #expect(states == expected)
    }
}
