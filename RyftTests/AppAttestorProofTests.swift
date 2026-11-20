import Foundation
import Testing
@testable import Ryft

/// Answers by path (each path's replies in order) and records every request; its own state, so it never meets
/// `StubURLProtocol`'s in a parallel suite.
final class AttestStubProtocol: URLProtocol {
    struct Reply {
        var status: Int
        var body = Data("{}".utf8)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: [Reply]] = [:]
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static func script(_ r: [String: [Reply]]) {
        lock.withLock { replies = r; seen = [] }
    }

    static var requests: [URLRequest] { lock.withLock { seen } }

    static func count(_ path: String) -> Int { requests.filter { $0.url?.path == path }.count }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.lock.withLock { () -> Reply in
            Self.seen.append(request)
            let path = request.url?.path ?? ""
            guard var queue = Self.replies[path], !queue.isEmpty else { return Reply(status: 200) }
            let next = queue.removeFirst()
            Self.replies[path] = queue
            return next
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// T2's proof that the seams carry a run through the real `exchange` (the AC suite is T3's).
@Suite("AppAttestor through exchange", .serialized)
@MainActor
struct AppAttestorProofTests {
    let base = URL(string: "https://api.test")!
    let clock = TestClock()
    let service = FakeAppAttestService()
    let keys = MemoryAppAttestKeys()
    let defaults = UserDefaults(suiteName: "appattest-proof-\(UUID().uuidString)")!
    let status = APIStatus()

    private func attestor() -> AppAttestor {
        let status = status
        return AppAttestor(service: service, keys: keys, clock: clock, defaults: defaults,
                           stamp: { AttestStamp(account: "account-a", epoch: status.epoch) })
    }

    private func client(_ attestor: AppAttestor) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AttestStubProtocol.self]
        return APIClient(session: URLSession(configuration: config), tokens: FakeTokens(), sleep: { _ in },
                         baseURL: base, status: status, appAttest: attestor)
    }

    private static func json(_ s: String) -> Data { Data(s.utf8) }

    private func appTokens(_ path: String) -> [String?] {
        AttestStubProtocol.requests.filter { $0.url?.path == path }
            .map { $0.value(forHTTPHeaderField: "X-RYFT-App-Token") }
    }

    @Test func servedRoutesAttestOnceAndTheRequestCarriesTheToken() async throws {
        defaults.set(try JSONEncoder().encode(AppAttestor.Backoff(servedSeen: true)), forKey: AppAttestor.defaultsKey)
        AttestStubProtocol.script([
            "/v1/app-attest/challenge": [
                .init(status: 200, body: Self.json(#"{"challenge":"c-1","expires_at":"2026-11-19T10:05:00Z"}"#)),
                .init(status: 200, body: Self.json(#"{"challenge":"c-2","expires_at":"2026-11-19T10:05:00Z"}"#)),
            ],
            "/v1/app-attest/keys": [.init(status: 201, body: Self.json(#"{"key_id":"key-1"}"#))],
            "/v1/app-attest/token": [.init(status: 200, body: Self.json(
                #"{"token":"app-token-1","expires_at":"2026-11-19T11:06:12Z","ttl_sec":3600}"#))],
        ])
        let attestor = attestor()
        let api = client(attestor)
        _ = try await api.data("GET", path: "/v1/me", body: Optional<Int>.none)

        #expect(AttestStubProtocol.requests.map { $0.url?.path ?? "" } == [
            "/v1/app-attest/challenge", "/v1/app-attest/keys", "/v1/app-attest/challenge", "/v1/app-attest/token",
            "/v1/me",
        ])
        #expect(appTokens("/v1/me") == ["app-token-1"])
        for route in ["/v1/app-attest/challenge", "/v1/app-attest/keys", "/v1/app-attest/token"] {
            #expect(appTokens(route).allSatisfy { $0 == nil }, "\(route)")
        }
        #expect(service.calls == [.generateKey, .attestKey("key-1", AppAttestor.clientDataHash("c-1")),
                                  .generateAssertion("key-1", AppAttestor.clientDataHash("c-2"))])
        #expect(keys.stored == StoredAppAttestKey(account: "account-a", keyId: "key-1", attested: true))
        let keyBody = try #require(AttestStubProtocol.requests.first { $0.url?.path == "/v1/app-attest/keys" })
        #expect(keyBody.value(forHTTPHeaderField: "Content-Type") == "application/json")

        // The next request reuses the token: no new run.
        _ = try await api.data("GET", path: "/v1/me", body: Optional<Int>.none)
        #expect(appTokens("/v1/me") == ["app-token-1", "app-token-1"])
        #expect(AttestStubProtocol.count("/v1/app-attest/token") == 1)
    }

    @Test func notServedSendsNoHeaderAndNoSecondProbe() async throws {
        AttestStubProtocol.script(["/v1/app-attest/challenge": [.init(status: 404, body: Self.json(#"{"error":"not found"}"#))]])
        let attestor = attestor()
        let api = client(attestor)
        _ = try await api.data("GET", path: "/v1/me", body: Optional<Int>.none)
        while await attestor.isRenewing { await Task.yield() }
        _ = try await api.data("GET", path: "/v1/me", body: Optional<Int>.none)
        // The next launch, inside the 6 h: no probe either.
        _ = try await client(self.attestor()).data("GET", path: "/v1/me", body: Optional<Int>.none)

        #expect(AttestStubProtocol.count("/v1/app-attest/challenge") == 1)
        #expect(appTokens("/v1/me") == [nil, nil, nil])
        #expect(service.calls.isEmpty)
        #expect(keys.stored == nil)
    }
}
