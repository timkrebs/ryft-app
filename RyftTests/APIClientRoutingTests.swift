import Foundation
import Testing
@testable import Ryft

/// Answers every request `200` with its route's body (`[]` when none is given) and records where it went.
final class RoutingStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var bodies: [String: Data] = [:]
    nonisolated(unsafe) private static var seen: [String] = []

    /// `bodies` by path, e.g. `"/v1/sync"`.
    static func reset(_ bodies: [String: Data] = [:]) {
        lock.withLock { self.bodies = bodies; seen = [] }
    }

    /// Every request's absolute URL, in order.
    static var urls: [String] { lock.withLock { seen } }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url?.absoluteURL else { return }
        let body = Self.lock.withLock { () -> Data in
            Self.seen.append(url.absoluteString)
            return Self.bodies[url.path] ?? Data("[]".utf8)
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Two production hosts (API.md): `POST /v1/sync` only at ingest, every other route only at the API. Each answers
/// `404` to the other's routes, so nothing falls back from one to the other.
@Suite("APIClient routing: ingest and API hosts", .serialized)
struct APIClientRoutingTests {
    let api = URL(string: "https://api.test")!
    let ingest = URL(string: "https://ingest.test")!

    init() throws {
        RoutingStubURLProtocol.reset(["/v1/sync": try Fixture.data("sync_response"), "/v1/me": try Fixture.data("me")])
    }

    private func client(api: URL?, ingest: URL?, settings: Settings? = nil) async -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RoutingStubURLProtocol.self]
        return APIClient(session: URLSession(configuration: config), tokens: FakeTokens(), sleep: { _ in },
                         baseURL: api, ingestURL: ingest, status: await APIStatus(), settings: settings)
    }

    /// Settings of their own, never `Settings.shared` (the host app's).
    private static func settings(api: String = "", ingest: String = "") throws -> Settings {
        let defaults = try #require(UserDefaults(suiteName: "ryft.test.routing.\(UUID().uuidString)"))
        let settings = Settings(defaults: defaults)
        settings.devAPIURLOverride = api
        settings.devIngestURLOverride = ingest
        return settings
    }

    private static func isNotConfigured(_ error: Error) -> Bool {
        if case .notConfigured? = error as? APIError { return true }
        return false
    }

    @Test func theSyncGoesToTheIngestHost() async throws {
        let c = await client(api: api, ingest: ingest)
        let answer = try await c.sync(encoded: Data("{}".utf8), contentEncoding: "gzip")
        #expect(answer.samples == 1380)
        #expect(RoutingStubURLProtocol.urls == ["https://ingest.test/v1/sync"])
    }

    @Test func everyOtherRouteGoesToTheAPIHost() async throws {
        let c = await client(api: api, ingest: ingest)
        _ = try await c.me()
        let day = Date(timeIntervalSince1970: 1_763_200_000) // 2025-11-15
        _ = try await c.days(from: day, to: day)
        _ = try await c.data("GET", path: "/v1/me/sync", body: Optional<Int>.none)
        _ = try await c.data("POST", path: "/v1/recompute", body: ["from": "2026-11-15"])
        let urls = RoutingStubURLProtocol.urls
        #expect(urls.count == 4)
        #expect(urls.first == "https://api.test/v1/me")
        let allOnTheAPIHost = urls.allSatisfy { $0.hasPrefix("https://api.test/") }
        #expect(allOnTheAPIHost, "\(urls)")
        #expect(urls.dropFirst().first?.hasPrefix("https://api.test/v1/days?from=") == true)
    }

    /// The route is the path without its query; the method counts too.
    @Test func onlyAPostToTheSyncPathGoesToIngest() async throws {
        let c = await client(api: api, ingest: ingest)
        _ = try await c.data("POST", path: "/v1/sync?x=1", body: ["a": 1])
        _ = try await c.data("GET", path: "/v1/sync", body: Optional<Int>.none)
        #expect(RoutingStubURLProtocol.urls == ["https://ingest.test/v1/sync?x=1", "https://api.test/v1/sync"])
    }

    /// The test seam: a caller's `base:` wins over the route's host.
    @Test func anExplicitBaseWins() async throws {
        let c = await client(api: api, ingest: ingest)
        _ = try await c.data("POST", path: "/v1/sync", body: ["a": 1], base: URL(string: "https://elsewhere.test"))
        #expect(RoutingStubURLProtocol.urls == ["https://elsewhere.test/v1/sync"])
    }

    /// No ingest URL: the sync throws `notConfigured` before anything is sent, never falling back to the API host.
    /// An API override alone (Profile → Developer) is that case: the overrides come as a pair.
    @Test func withoutAnIngestURLTheSyncSendsNothing() async throws {
        let settings = try Self.settings(api: "http://192.168.1.20:8082")
        let c = await client(api: nil, ingest: nil, settings: settings)
        do {
            _ = try await c.sync(encoded: Data("{}".utf8), contentEncoding: nil)
            Issue.record("expected notConfigured")
        } catch {
            #expect(Self.isNotConfigured(error), "\(error)")
        }
        #expect(RoutingStubURLProtocol.urls.isEmpty)
        // Reads still go to the API override.
        _ = try await c.me()
        #expect(RoutingStubURLProtocol.urls == ["http://192.168.1.20:8082/v1/me"])
    }

    /// The compose pair: each route reaches its own port.
    @Test func theComposePairSendsEachRouteToItsPort() async throws {
        let settings = try Self.settings(api: "http://192.168.1.20:8082", ingest: "http://192.168.1.20:8081")
        let c = await client(api: nil, ingest: nil, settings: settings)
        _ = try await c.sync(encoded: Data("{}".utf8), contentEncoding: nil)
        _ = try await c.me()
        #expect(RoutingStubURLProtocol.urls == ["http://192.168.1.20:8081/v1/sync", "http://192.168.1.20:8082/v1/me"])
    }

    @Test func theRouteDecidesTheHost() {
        let api = api, ingest = ingest
        func root(_ method: String, _ path: String) -> URL? {
            APIClient.root(method: method, path: path, api: api, ingest: ingest)
        }
        #expect(root("POST", "/v1/sync") == ingest)
        #expect(root("POST", "/v1/sync?gzip=1") == ingest)
        #expect(root("GET", "/v1/sync") == api)
        #expect(root("GET", "/v1/me/sync") == api)
        #expect(root("POST", "/v1/recompute") == api)
        #expect(root("POST", "/v1/train/import") == api)
        #expect(root("GET", "/v1/days?from=2026-11-01&to=2026-11-15") == api)
        // No fallback either way.
        #expect(APIClient.root(method: "POST", path: "/v1/sync", api: api, ingest: nil) == nil)
        #expect(APIClient.root(method: "GET", path: "/v1/me", api: nil, ingest: ingest) == nil)
        #expect(APIClient.root(method: "POST", path: "/v1/sync", api: nil, ingest: ingest) == ingest)
    }
}

/// `Settings.ingestURL`: the build's ingest host, or the Debug override; never the API host.
@Suite("Settings: the ingest host")
struct SettingsIngestHostTests {
    private static func settings(api: String = "", ingest: String = "") throws -> Settings {
        let defaults = try #require(UserDefaults(suiteName: "ryft.test.hosts.\(UUID().uuidString)"))
        let settings = Settings(defaults: defaults)
        settings.devAPIURLOverride = api
        settings.devIngestURLOverride = ingest
        return settings
    }

    @Test func withoutOverridesItIsTheBuildsIngestHost() throws {
        let s = try Self.settings()
        #expect(s.ingestURL == PlatformConfig.ingestURL)
        #expect(s.ingestURL != nil && s.ingestURL != s.apiURL)
    }

    @Test func theIngestOverrideWins() throws {
        let ingest = URL(string: "http://192.168.1.20:8081")
        let alone = try Self.settings(ingest: "http://192.168.1.20:8081")
        let paired = try Self.settings(api: "http://192.168.1.20:8082", ingest: " http://192.168.1.20:8081 ")
        #expect(alone.ingestURL == ingest)
        #expect(paired.ingestURL == ingest)
    }

    /// The overrides come as a pair: a compose stack's dev bearer never reaches production ingest.
    @Test func anAPIOverrideAloneLeavesNoIngestHost() throws {
        let s = try Self.settings(api: "http://192.168.1.20:8082")
        #expect(s.ingestURL == nil)
        #expect(s.apiURL == URL(string: "http://192.168.1.20:8082"))
        #expect(s.isConfigured) // so the sync fails `notConfigured` loudly instead of being skipped
        // An ingest override that isn't a URL counts as none.
        let invalidIngest = try Self.settings(api: "http://192.168.1.20:8082", ingest: "not a url")
        #expect(invalidIngest.ingestURL == nil)
        // Neither is an API override that isn't one.
        let blankAPI = try Self.settings(api: "   ")
        #expect(blankAPI.ingestURL == PlatformConfig.ingestURL)
    }
}
