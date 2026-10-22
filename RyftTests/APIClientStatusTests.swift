import Foundation
import Testing
@testable import Ryft

/// Serves scripted responses in order and records the requests it saw.
final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data("{}".utf8)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [Reply] = []
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static func script(_ r: [Reply]) {
        lock.withLock { replies = r; seen = [] }
    }

    static var requests: [URLRequest] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.lock.withLock { () -> Reply in
            Self.seen.append(request)
            return Self.replies.isEmpty ? Reply(status: 500) : Self.replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class FakeTokens: AccessTokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _refreshes = 0
    private var _rejections = 0
    var refreshes: Int { lock.withLock { _refreshes } }
    var rejections: Int { lock.withLock { _rejections } }

    func accessToken() async throws -> String { "token-1" }
    func refreshedAccessToken() async throws -> String {
        lock.withLock { _refreshes += 1 }
        return "token-2"
    }
    func rejectedAfterRefresh() async { lock.withLock { _rejections += 1 } }
}

final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _waits: [Int] = []
    var waits: [Int] { lock.withLock { _waits } }
    func record(_ s: Int) { lock.withLock { _waits.append(s) } }
}

/// APIClient status handling per API.md → Errors, against a stub URLProtocol.
@Suite("APIClient status handling", .serialized)
struct APIClientStatusTests {
    let tokens = FakeTokens()
    let sleeps = SleepLog()
    let base = URL(string: "https://api.test")!

    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let sleeps = self.sleeps
        return APIClient(session: URLSession(configuration: config), tokens: tokens,
                         sleep: { sleeps.record($0) }, baseURL: base)
    }

    private func get(_ c: APIClient) async throws -> Data {
        try await c.data("GET", path: "/v1/me", body: Optional<Int>.none, base: base)
    }

    private var bearers: [String?] {
        StubURLProtocol.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
    }

    private static func errorBody(_ message: String, requestID: String? = nil) -> Data {
        var json: [String: String] = ["error": message]
        json["request_id"] = requestID
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func successUsesTheSessionToken() async throws {
        StubURLProtocol.script([.init(status: 200)])
        _ = try await get(client())
        #expect(bearers == ["Bearer token-1"])
        #expect(tokens.refreshes == 0)
    }

    @Test func unauthorizedRefreshesOnceAndRetries() async throws {
        StubURLProtocol.script([.init(status: 401, headers: ["WWW-Authenticate": #"Bearer realm="ryft", error="invalid_token""#]),
                                .init(status: 200)])
        _ = try await get(client())
        #expect(bearers == ["Bearer token-1", "Bearer token-2"])
        #expect(tokens.refreshes == 1)
        #expect(tokens.rejections == 0)
    }

    @Test func secondUnauthorizedSignsOut() async {
        StubURLProtocol.script([.init(status: 401), .init(status: 401)])
        await #expect {
            try await get(client())
        } throws: { ($0 as? APIError)?.status == 401 }
        #expect(StubURLProtocol.requests.count == 2)
        #expect(tokens.refreshes == 1)
        #expect(tokens.rejections == 1)
    }

    @Test func unavailableWaitsRetryAfterAndNeverSignsOut() async throws {
        StubURLProtocol.script([.init(status: 503, headers: ["Retry-After": "7"]), .init(status: 200)])
        _ = try await get(client())
        #expect(sleeps.waits == [7])
        #expect(tokens.refreshes == 0)
        #expect(tokens.rejections == 0)
        #expect(await APIStatus.shared.retryNotice == nil)
    }

    @Test func unavailableGivesUpAfterThreeRetriesWithTheRequestID() async {
        StubURLProtocol.script(Array(repeating: .init(status: 503, headers: ["Retry-After": "120", "X-Request-ID": "rid-503"],
                                                      body: Self.errorBody("request timed out", requestID: "rid-503")),
                                     count: 4))
        await #expect {
            try await get(client())
        } throws: { error in
            let e = error as? APIError
            return e?.status == 503 && e?.requestID == "rid-503"
        }
        #expect(StubURLProtocol.requests.count == 1 + APIClient.maxUnavailableRetries)
        #expect(sleeps.waits == [30, 30, 30]) // Retry-After capped
        #expect(tokens.rejections == 0)
        let latest = await APIStatus.shared.failures.first
        #expect(latest?.status == 503)
        #expect(latest?.requestID == "rid-503")
        #expect(await APIStatus.shared.retryNotice == nil)
    }

    @Test func unavailableWithoutRetryAfterWaitsFiveSeconds() async throws {
        StubURLProtocol.script([.init(status: 503), .init(status: 200)])
        _ = try await get(client())
        #expect(sleeps.waits == [5])
    }

    @Test func rateLimitWaitsAndRetriesOnce() async {
        StubURLProtocol.script([.init(status: 429, headers: ["Retry-After": "2"]),
                                .init(status: 429, headers: ["Retry-After": "2"])])
        await #expect {
            try await get(client())
        } throws: { ($0 as? APIError)?.status == 429 }
        #expect(StubURLProtocol.requests.count == 2)
        #expect(sleeps.waits == [2])
        #expect(tokens.rejections == 0)
    }

    @Test func rateLimitThenSuccess() async throws {
        StubURLProtocol.script([.init(status: 429, headers: ["Retry-After": "1"]), .init(status: 200)])
        _ = try await get(client())
        #expect(sleeps.waits == [1])
    }

    @Test func plainTextRateLimitFromTheEdgeIsHandled() async throws {
        // The per-IP limit answers before any token check, with a text body.
        StubURLProtocol.script([.init(status: 429, headers: ["Retry-After": "3", "Content-Type": "text/plain"],
                                      body: Data("Too Many Requests".utf8)),
                                .init(status: 200)])
        _ = try await get(client())
        #expect(sleeps.waits == [3])
    }

    @Test func plainTextRateLimitTwiceSurfacesTheCalmMessage() async {
        StubURLProtocol.script(Array(repeating: .init(status: 429, headers: ["Retry-After": "1"],
                                                      body: Data("Too Many Requests".utf8)), count: 2))
        await #expect {
            try await get(client())
        } throws: { error in
            (error as? APIError)?.status == 429
                && error.localizedDescription == "Too many requests. Try again in a minute."
        }
    }

    @Test func conflictOnASessionPutReturnsTheServerCopy() async throws {
        let server = try Fixture.data("train_session")
        StubURLProtocol.script([.init(status: 409, body: server)])
        let local = try Fixture.decode(TrainSession.self, "train_session")
        let result = try await client().putSession(local)
        guard case .conflict(let copy) = result else {
            Issue.record("expected .conflict, got \(result)")
            return
        }
        #expect(copy.id == local.id)
        #expect(StubURLProtocol.requests.first?.httpMethod == "PUT")
        #expect(tokens.rejections == 0)
    }

    @Test func requestsCarryAcceptLanguage() async throws {
        StubURLProtocol.script([.init(status: 200)])
        _ = try await get(client())
        #expect(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Accept-Language")?.isEmpty == false)
    }

    @Test func appleAuthorizationRetriesA503OnlyOnce() async {
        StubURLProtocol.script(Array(repeating: .init(status: 503, headers: ["Retry-After": "2"]), count: 3))
        await #expect {
            try await client().postAppleAuthorization(code: "c1b2")
        } throws: { ($0 as? APIError)?.status == 503 }
        #expect(StubURLProtocol.requests.count == 2)
        #expect(sleeps.waits == [2])
    }

    @Test func payloadTooLargeIsThrownForSyncToShrink() async {
        // No X-Request-ID header: the ID comes from the body.
        StubURLProtocol.script([.init(status: 413, body: Self.errorBody("request body too large", requestID: "rid-413"))])
        await #expect {
            try await get(client())
        } throws: { error in
            let e = error as? APIError
            return e?.status == 413 && e?.requestID == "rid-413"
        }
        #expect(StubURLProtocol.requests.count == 1)
        #expect(sleeps.waits.isEmpty)
    }

    @Test func detailsCarryStatusAndRequestID() {
        #expect(APIError.http(500, "internal error", requestID: "abc").diagnosticDetails == "HTTP 500 · Request ID abc")
        #expect(APIError.http(404, "").diagnosticDetails == "HTTP 404")
        #expect(APIError.signedOut.diagnosticDetails == nil)
    }

    @Test func errorBodyDecodesRequestID() throws {
        let body = try APIClient.jsonDecoder.decode(APIErrorBody.self, from: Self.errorBody("x", requestID: "r1"))
        #expect(body.requestId == "r1")
        let bare = try APIClient.jsonDecoder.decode(APIErrorBody.self, from: Data(#"{"error":"x"}"#.utf8))
        #expect(bare.requestId == nil)
    }
}

// MARK: - 422 / 409 / 404 / 204 (API.md → Errors)

extension APIClientStatusTests {
    private func put(_ c: APIClient, _ path: String) async throws -> Data {
        try await c.data("PUT", path: path, body: JournalPut(entries: []), base: base)
    }

    @Test func fieldErrorIsInlineNeverRetriedNeverASignOut() async {
        StubURLProtocol.script([.init(status: 422, headers: ["X-Request-ID": "rid-422"],
                                      body: Self.fieldBody("day 2026-09-01 is not editable", requestID: "rid-422"))])
        await #expect {
            try await put(client(), "/v1/journal/2026-09-01")
        } throws: { error in
            let e = error as? APIError
            return e?.isFieldError == true && e?.requestID == "rid-422"
                && e?.localizedDescription == "day 2026-09-01 is not editable"
                && error.diagnosticDetails?.contains("rid-422") == true
        }
        #expect(StubURLProtocol.requests.count == 1)
        #expect(tokens.refreshes == 0 && tokens.rejections == 0)
        #expect(sleeps.waits.isEmpty)
    }

    @Test func takenBehaviorIDIsItsOwnCase() async {
        StubURLProtocol.script([.init(status: 409, body: Self.fieldBody("id taken"))])
        await #expect {
            _ = try await client().createBehavior(BehaviorInput(id: UUID(), name: "Sauna", kind: .yesNo))
        } throws: { ($0 as? APIError)?.isIDTaken == true }
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test func aKnownRouteThatIsNotDeployedIsNotLive() async {
        StubURLProtocol.script([.init(status: 404, body: Self.fieldBody("not found"))])
        await #expect {
            _ = try await client().behaviors()
        } throws: { error in
            (error as? APIError)?.isNotLive == true && error.isEndpointMissing
        }
        #expect(StubURLProtocol.requests.count == 1 && tokens.rejections == 0)
    }

    @Test func noPlanTodayIsStillNoPlan() async throws {
        StubURLProtocol.script([.init(status: 204, body: Data())])
        #expect(try await client().planToday() == nil)
    }

    private static func fieldBody(_ message: String, requestID: String? = nil) -> Data {
        var json: [String: String] = ["error": message]
        json["request_id"] = requestID
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }
}

/// The Beta gates and the account headers (API.md → Errors, Conventions → Device).
extension APIClientStatusTests {
    private func gatedClient(_ status: APIStatus) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let sleeps = self.sleeps
        return APIClient(session: URLSession(configuration: config), tokens: tokens,
                         sleep: { sleeps.record($0) }, baseURL: base, status: status)
    }

    private static func codeBody(_ code: String, requestID: String = "01a15a69-7142-7a8b-aba2-c099a5fcd1e4") -> Data {
        try! JSONSerialization.data(withJSONObject: ["error": code.replacingOccurrences(of: "_", with: " "),
                                                     "code": code, "request_id": requestID])
    }

    @Test func everyRequestCarriesTheDeviceID() async throws {
        StubURLProtocol.script([.init(status: 200), .init(status: 200)])
        let c = client()
        _ = try await get(c)
        _ = try await c.data("POST", path: "/v1/sync", body: ["a": 1], base: base)
        let ids = StubURLProtocol.requests.map { $0.value(forHTTPHeaderField: "X-RYFT-Device-ID") }
        #expect(ids == Array(repeating: Settings.shared.deviceId.uuidString.lowercased(), count: 2))
    }

    @Test func consentRequiredIsAGateNotASignInProblem() async {
        let status = await APIStatus()
        StubURLProtocol.script([.init(status: 403, body: Self.codeBody("consent_required"))])
        await #expect {
            try await gatedClient(status).data("POST", path: "/v1/sync", body: ["a": 1], base: base)
        } throws: { error in
            let e = error as? APIError
            return e?.gate == .consentRequired && e?.requestID == "01a15a69-7142-7a8b-aba2-c099a5fcd1e4"
                && e?.localizedDescription.contains("Log in") == false
        }
        #expect(tokens.refreshes == 0 && tokens.rejections == 0) // never a refresh, never a sign-out
        #expect(await status.gates == [.consentRequired])
        #expect(await !status.inviteBlocked) // reads keep working
        #expect(await status.failures.first?.code == "consent_required")
    }

    @Test func everyAnsweredRequestIsLoggedForSyncDetails() async throws {
        let status = await APIStatus()
        StubURLProtocol.script([.init(status: 200, headers: ["X-Request-ID": "rid-ok"]),
                                .init(status: 403, body: Self.codeBody("consent_required"))])
        _ = try await gatedClient(status).data("GET", path: "/v1/me", body: Optional<Int>.none, base: base)
        _ = try? await gatedClient(status).data("POST", path: "/v1/sync", body: ["a": 1], base: base)
        let requests = await status.requests
        #expect(requests.map(\.status) == [403, 200]) // newest first
        #expect(requests.last?.requestID == "rid-ok" && requests.last?.path == "/v1/me")
        #expect(requests.first?.code == "consent_required")
        #expect(await status.failures.count == 1) // the served one isn't a failure
    }

    @Test func theRequestLogKeepsTheNewestTwenty() async {
        let status = await APIStatus()
        for i in 0..<25 {
            await status.served(.init(date: .now, method: "GET", path: "/v1/days/\(i)", status: 200, requestID: nil))
        }
        let requests = await status.requests
        let limit = await APIStatus.maxFailures
        #expect(requests.count == limit)
        #expect(requests.first?.path == "/v1/days/24")
    }

    @Test func inviteRequiredStopsEverythingButOnboarding() async throws {
        let status = await APIStatus()
        StubURLProtocol.script([.init(status: 403, body: Self.codeBody("invite_required")), .init(status: 200)])
        let c = gatedClient(status)
        await #expect { try await c.data("GET", path: "/v1/days/2026-10-21", body: Optional<Int>.none, base: base) }
            throws: { ($0 as? APIError)?.gate == .inviteRequired }
        #expect(await status.inviteBlocked)
        // Behind the gate the next read isn't sent at all…
        await #expect { try await c.data("GET", path: "/v1/insights", body: Optional<Int>.none, base: base) }
            throws: { ($0 as? APIError)?.gate == .inviteRequired }
        #expect(StubURLProtocol.requests.count == 1)
        // …but onboarding's calls are.
        _ = try await c.data("GET", path: "/v1/me/sync", body: Optional<Int>.none, base: base)
        #expect(StubURLProtocol.requests.count == 2)
        await status.resolved(.inviteRequired)
        #expect(await !status.inviteBlocked)
        #expect(await status.gates.isEmpty)
    }

    @Test func aWarnModeHeaderReportsTheGateOnAServedRequest() async throws {
        let status = await APIStatus()
        StubURLProtocol.script([.init(status: 200, headers: ["X-RYFT-Gate": "invite_required, consent_required"])])
        _ = try await gatedClient(status).data("POST", path: "/v1/sync", body: ["a": 1], base: base)
        #expect(await status.gates == [.inviteRequired, .consentRequired])
        #expect(await !status.inviteBlocked) // a warning blocks nothing
    }

    @Test func aForbiddenWithoutCodeIsAPermissionMessage() async {
        StubURLProtocol.script([.init(status: 403, body: Self.errorBody("built-in plan"))])
        await #expect {
            try await get(client())
        } throws: { error in
            let e = error as? APIError
            return e?.status == 403 && e?.gate == nil
                && e?.localizedDescription == String(localized: "This is built into RYFT and can't be changed.")
        }
        #expect(tokens.rejections == 0)
    }

    @Test func statusMatrixMessages() {
        func text(_ e: APIError) -> String { e.localizedDescription }
        let unauthorized = text(.http(401, ""))
        let invite = text(.http(403, "", code: .inviteRequired))
        let consent = text(.http(403, "", code: .consentRequired))
        let forbidden = text(.http(403, ""))
        // Each status says its own thing; only a 401 asks to log in again.
        #expect(Set([unauthorized, invite, consent, forbidden]).count == 4)
        #expect(unauthorized.contains("Log in"))
        #expect(![invite, consent, forbidden].contains { $0.contains("Log in") })
        #expect(text(.http(429, "")) != text(.http(503, "")))
        #expect(APIError.http(403, "", code: .consentRequired).gate == .consentRequired)
        #expect(APIError.http(409, "", code: .consentRequired).gate == nil) // only a 403 is a gate
    }

    @Test func detailsCarryStatusCodeAndTheRequestIDAsSent() {
        let id = "01a15a69-7142-7a8b-aba2-c099a5fcd1e4"
        let details = APIError.http(403, "", requestID: id, code: .consentRequired).diagnosticDetails
        #expect(details?.contains("HTTP 403") == true && details?.contains("consent_required") == true)
        #expect(details?.hasSuffix(id) == true) // exactly as received: support searches for it
        #expect(APIError.http(500, "").diagnosticDetails == "HTTP 500")
    }

    @Test func openRoutesBehindTheInviteGate() {
        #expect(APIClient.isOpenBehindInviteGate("GET", "/v1/me"))
        #expect(APIClient.isOpenBehindInviteGate("POST", "/v1/me/consent"))
        #expect(APIClient.isOpenBehindInviteGate("GET", "/v1/config?x=1"))
        #expect(!APIClient.isOpenBehindInviteGate("PATCH", "/v1/me"))
        #expect(!APIClient.isOpenBehindInviteGate("POST", "/v1/sync"))
    }
}

/// Never answers, so a test can cancel the task that waits for it.
final class HangingURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

@Suite("T0: APIClient cancellation")
struct APIClientCancellationTests {
    /// What `.refreshable` does to the task awaiting a request: `URLSession` throws `URLError.cancelled`, and
    /// `APIClient.perform` rethrows it as `CancellationError`, so nothing downstream mistakes it for a failure.
    @Test func aCancelledTaskThrowsCancellationError() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingURLProtocol.self]
        let client = APIClient(session: URLSession(configuration: config), tokens: FakeTokens(), sleep: { _ in },
                               baseURL: URL(string: "https://api.test")!, status: await APIStatus())
        let task = Task { () -> Error? in
            do {
                _ = try await client.data("GET", path: "/v1/me", body: Optional<Int>.none)
                return nil
            } catch { return error }
        }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let error = await task.value

        #expect(error is CancellationError, "got \(String(describing: error))")
        #expect(FailureKind.of(error ?? APIError.notConfigured) == .cancelled)
    }
}

/// One retry layer for reads (ADR 0001): a scheduled read makes one attempt.
extension APIClientStatusTests {
    @Test func aScheduledReadMakesOneAttemptAndKeepsRetryAfter() async {
        StubURLProtocol.script([.init(status: 429, headers: ["Retry-After": "7"], body: Data("slow down".utf8)),
                                .init(status: 200)])
        let c = client()
        do {
            _ = try await APIClient.$singleAttempt.withValue(true) { try await get(c) }
            Issue.record("expected a 429")
        } catch {
            #expect((error as? APIError)?.status == 429 && (error as? APIError)?.retryAfter == 7)
            #expect(FailureKind.of(error) == .transient)
        }
        #expect(StubURLProtocol.requests.count == 1 && sleeps.waits.isEmpty)
    }

    @Test func aScheduledReadDoesNotWaitOutA503() async {
        let status = await APIStatus()
        StubURLProtocol.script([.init(status: 503, headers: ["Retry-After": "2"],
                                      body: Self.errorBody("request timed out", requestID: "rid-503"))])
        let c = gatedClient(status)
        do {
            _ = try await APIClient.$singleAttempt.withValue(true) {
                try await c.data("GET", path: "/v1/me", body: Optional<Int>.none, base: base)
            }
            Issue.record("expected a 503")
        } catch {
            #expect((error as? APIError)?.requestID == "rid-503" && (error as? APIError)?.retryAfter == 2)
        }
        #expect(StubURLProtocol.requests.count == 1 && sleeps.waits.isEmpty)
        #expect(await status.retryNotice == nil)
        #expect(await status.requests.first?.durationMs != nil)
    }
}

/// Fails every request as a timeout would.
final class TimingOutURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)) }
    override func stopLoading() {}
}

@Suite("APIClient transport failures")
struct APIClientTransportTests {
    /// Criterion 12: a request without an answer is recorded, with its duration and the URLError's name.
    @Test func aRequestWithoutAnAnswerIsRecorded() async {
        let status = await APIStatus()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TimingOutURLProtocol.self]
        let client = APIClient(session: URLSession(configuration: config), tokens: FakeTokens(), sleep: { _ in },
                               baseURL: URL(string: "https://api.test")!, status: status)
        do {
            _ = try await client.data("GET", path: "/v1/days?from=a&to=b", body: Optional<Int>.none)
            Issue.record("expected a timeout")
        } catch {
            #expect(FailureKind.of(error) == .transient)
        }
        let request = await status.requests.first
        #expect(request?.status == 0 && request?.transport == "timedOut" && request?.durationMs != nil)
        #expect(request?.path == "/v1/days?from=a&to=b")
        #expect(await status.failures.count == 1)
    }
}

@Suite("Read retry policy")
struct RetryPolicyTests {
    private let top: (ClosedRange<Double>) -> Double = { $0.upperBound }
    private let bottom: (ClosedRange<Double>) -> Double = { $0.lowerBound }

    @Test func classification() {
        let rows: [(Error, FailureKind)] = [
            (CancellationError(), .cancelled),
            (APIError.transport(URLError(.cancelled)), .cancelled),
            (URLError(.cancelled), .cancelled),
            (APIError.transport(URLError(.timedOut)), .transient),
            (APIError.transport(URLError(.notConnectedToInternet)), .transient),
            (URLError(.networkConnectionLost), .transient),
            (APIError.http(408, ""), .transient),
            (APIError.http(429, ""), .transient),
            (APIError.http(500, ""), .transient),
            (APIError.http(503, ""), .transient),
            (APIError.http(501, ""), .other),
            (APIError.http(401, ""), .signedOut),
            (APIError.signedOut, .signedOut),
            (APIError.http(403, "", code: .inviteRequired), .gate),
            (APIError.http(403, "", code: .consentRequired), .gate),
            (APIError.http(403, ""), .other),
            (APIError.http(404, ""), .other),
            (APIError.http(422, ""), .other),
            (APIError.notConfigured, .other),
            (DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")), .other),
        ]
        for (error, kind) in rows { #expect(FailureKind.of(error) == kind, "\(error)") }
        #expect(FailureKind.signedOut.isActionable && FailureKind.gate.isActionable && !FailureKind.transient.isActionable)
    }

    @Test func backoffIsFullJitterWithinItsBounds() {
        let p = RetryPolicy.foreground
        let error = APIError.http(503, "")
        #expect(p.delay(before: 1, after: error, random: top) == .seconds(1))
        #expect(p.delay(before: 2, after: error, random: top) == .seconds(2))
        #expect(p.delay(before: 1, after: error, random: bottom) == .zero)
        #expect(p.delay(before: 3, after: error, random: top) == nil)   // two retries at most
        #expect(RetryPolicy.background.delay(before: 2, after: error, random: top) == nil)
    }

    @Test func retryAfterIsHonouredUpToTheCap() {
        let p = RetryPolicy.foreground
        #expect(p.delay(before: 1, after: APIError.http(429, "", retryAfter: 3), random: bottom) == .seconds(3))
        #expect(p.delay(before: 1, after: APIError.http(429, ""), random: bottom) == .seconds(1))   // 429 without: 1 s
        #expect(p.delay(before: 2, after: APIError.http(503, "", retryAfter: 1), random: top) == .seconds(2))
        #expect(p.delay(before: 1, after: APIError.http(503, "", retryAfter: 7), random: bottom) == nil)
        #expect(RetryPolicy.background.delay(before: 1, after: APIError.http(503, "", retryAfter: 3), random: bottom) == nil)
    }

    @Test func onlyTransientFailuresRetry() {
        let p = RetryPolicy.foreground
        for error: Error in [APIError.http(404, ""), APIError.http(401, ""), CancellationError(),
                             APIError.http(403, "", code: .consentRequired)] {
            #expect(p.delay(before: 1, after: error, random: top) == nil, "\(error)")
        }
    }
}

/// Ends every request as a cancelled task's does.
final class CancellingURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.cancelled)) }
    override func stopLoading() {}
}

/// Answers 200 with a request ID and a body no model decodes from.
final class UnreadableAnswerURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["X-Request-ID": "rid-200"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"unexpected":true}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("APIClient: cancellation, unreadable answers, redaction")
struct APIClientReviewFixTests {
    private func client(_ protocolClass: URLProtocol.Type, _ status: APIStatus) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [protocolClass]
        return APIClient(session: URLSession(configuration: config), tokens: FakeTokens(), sleep: { _ in },
                         baseURL: URL(string: "https://api.test")!, status: status)
    }

    /// Nit 10: a cancelled request isn't a warning and takes none of the report's 20 slots.
    @Test func aCancelledRequestTakesNoSlot() async {
        let status = await APIStatus()
        await #expect(throws: CancellationError.self) {
            _ = try await client(CancellingURLProtocol.self, status).data("GET", path: "/v1/me", body: Optional<Int>.none)
        }
        #expect(await status.requests.isEmpty)
        #expect(await status.failures.isEmpty)
        #expect(await status.cancelledCount == 1)
    }

    /// Nit 9: a 200 this build can't decode keeps its status and request ID (not retried: `.other`).
    @Test func anUnreadableAnswerKeepsItsStatusAndRequestID() async {
        let status = await APIStatus()
        do {
            _ = try await client(UnreadableAnswerURLProtocol.self, status).me()
            Issue.record("expected a decoding failure")
        } catch {
            let api = error as? APIError
            #expect(api?.status == 200 && api?.requestID == "rid-200")
            #expect(FailureKind.of(error) == .other)
            let recorded = ResourceError(error, kind: FailureKind.of(error), attempts: 1, at: .now)
            #expect(recorded.status == 200 && recorded.requestID == "rid-200")
        }
    }

    /// Security should-fix 2: no query, no IDs; day segments stay.
    @Test func pathsAreRedacted() {
        #expect(redactedPath("/v1/sleep/plan?wake=06:30") == "/v1/sleep/plan")
        #expect(redactedPath("/v1/devices/3F2504E0-4F89-41D3-9A0C-0305E82C3301/push") == "/v1/devices/{id}/push")
        #expect(redactedPath("/v1/sessions/3f2504e0-4f89-41d3-9a0c-0305e82c3301/complete") == "/v1/sessions/{id}/complete")
        #expect(redactedPath("/v1/days/2026-10-21") == "/v1/days/2026-10-21")
        #expect(redactedPath("/v1/days?from=2026-07-24&to=2026-10-21") == "/v1/days")
        #expect(redactedPath("/v1/me#x") == "/v1/me")
    }
}
