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
                         sleep: { sleeps.record($0) })
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
