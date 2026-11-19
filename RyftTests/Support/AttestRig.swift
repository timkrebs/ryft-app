import CryptoKit
import Foundation
@testable import Ryft

// What the App Attest acceptance tests (docs/work/2026-11-19-app-attest/plan.md, AC1-AC10) stand on: a scripted
// platform behind `URLProtocol` (one host per test, so suites run in parallel), a fake App Attest service that logs
// into the same event list as the platform, a Keychain spy, and a rig that wires an `AppAttestor` into an `APIClient`.

/// What happened, in order, across the platform and the device ("net challenge", "dc generateKey" …).
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func add(_ event: String) { lock.withLock { items.append(event) } }
    var all: [String] { lock.withLock { items } }
}

/// A scripted platform for one test. Routes answer by `"METHOD /path"`; a reply is computed when the request arrives
/// and may be held back until `releaseHeld()` (a request in flight).
final class AttestServer: @unchecked Sendable {
    static let challenge = "POST /v1/app-attest/challenge"
    static let keys = "POST /v1/app-attest/keys"
    static let token = "POST /v1/app-attest/token"
    static let appAttestRoutes = [challenge, keys, token]
    static let me = "GET /v1/me"
    static let sync = "POST /v1/sync"

    struct Request: Sendable {
        let method: String
        let host: String
        let path: String
        let headers: [String: String]
        let body: Data

        var key: String { "\(method) \(path)" }

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        var appToken: String? { header("X-RYFT-App-Token") }

        /// A string field of the JSON body.
        func field(_ name: String) -> String? {
            ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?[name] as? String
        }
    }

    struct Reply: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data("{}".utf8)

        static func json(_ status: Int, _ text: String, headers: [String: String] = [:]) -> Reply {
            Reply(status: status, headers: headers, body: Data(text.utf8))
        }

        /// The platform's error body (`error`, `code`, `request_id`) and headers.
        static func refusal(_ status: Int, code: String? = nil, requestID: String? = nil, retryAfter: Int? = nil) -> Reply {
            var body: [String: String] = ["error": "refused"]
            body["code"] = code
            body["request_id"] = requestID
            var headers: [String: String] = [:]
            headers["X-Request-ID"] = requestID
            headers["Retry-After"] = retryAfter.map(String.init)
            return Reply(status: status, headers: headers, body: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
        }

        static let ok = Reply(status: 200)

        /// `200` of `POST /v1/app-attest/token`.
        static func token(_ token: String, ttl: Int = 3600) -> Reply {
            .json(200, #"{"token":"\#(token)","expires_at":"2026-11-19T11:06:12Z","ttl_sec":\#(ttl)}"#)
        }

        /// `201` of `POST /v1/app-attest/keys`: the key ID it was sent.
        static func keyCreated(_ request: Request) -> Reply {
            .json(201, #"{"key_id":"\#(request.field("key_id") ?? "")"}"#)
        }
    }

    typealias Handler = @Sendable (Request, Int) -> Reply

    let host: String
    var ingestHost: String { "ingest.\(host)" }
    private let events: EventLog
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    private var counts: [String: Int] = [:]
    private var log: [Request] = []
    private var holds: [String: Int] = [:]
    private var held: [@Sendable () -> Void] = []

    init(host: String, events: EventLog) {
        self.host = host
        self.events = events
        AttestServerProtocol.register(self, hosts: [host, ingestHost])
    }

    // MARK: scripting

    /// `handler(request, n)`: `n` counts this route's requests, from 0.
    func route(_ key: String, _ handler: @escaping Handler) {
        lock.withLock { handlers[key] = handler }
    }

    /// The route's replies in order; the last one repeats.
    func reply(_ key: String, _ replies: Reply...) {
        route(key) { _, n in replies[min(n, replies.count - 1)] }
    }

    /// The next `count` replies of the route are withheld until `releaseHeld()`.
    func hold(_ key: String, next count: Int = 1) {
        lock.withLock { holds[key, default: 0] += count }
    }

    var heldCount: Int { lock.withLock { held.count } }

    func releaseHeld() {
        let release = lock.withLock { () -> [@Sendable () -> Void] in
            defer { held = [] }
            return held
        }
        for send in release { send() }
    }

    /// A served platform: a challenge each time (`challenges[n]`, else `chal-<n+1>`), `201` for a key echoing its ID,
    /// a token (`tokenFor`, else `tok-<n+1>`) living `ttl` seconds.
    func serveAppAttest(challenges: [String] = [], ttl: Int = 3600,
                        tokenFor: @escaping @Sendable (Request, Int) -> String = { _, n in "tok-\(n + 1)" }) {
        route(Self.challenge) { _, n in
            let challenge = n < challenges.count ? challenges[n] : "chal-\(n + 1)"
            return .json(200, #"{"challenge":"\#(challenge)","expires_at":"2026-11-19T10:05:00Z"}"#)
        }
        route(Self.keys) { request, _ in
            .json(201, #"{"key_id":"\#(request.field("key_id") ?? "")"}"#)
        }
        route(Self.token) { request, n in
            .json(200, #"{"token":"\#(tokenFor(request, n))","expires_at":"2026-11-19T11:06:12Z","ttl_sec":\#(ttl)}"#)
        }
    }

    // MARK: what it saw

    var requests: [Request] { lock.withLock { log } }
    func requests(_ key: String) -> [Request] { requests.filter { $0.key == key } }
    func count(_ key: String) -> Int { requests(key).count }
    /// `X-RYFT-App-Token` of each request to the route, nil when it had none.
    func appTokens(_ key: String) -> [String?] { requests(key).map(\.appToken) }
    /// Every request to one of the three App Attest routes.
    var appAttestRequests: Int { Self.appAttestRoutes.reduce(0) { $0 + count($1) } }

    // MARK: serving

    fileprivate func receive(_ request: Request) -> (reply: Reply, held: Bool) {
        let label = request.path.hasPrefix("/v1/app-attest/")
            ? "net \(request.path.split(separator: "/").last ?? "")" : "net \(request.key)"
        let (handler, n, hold) = lock.withLock { () -> (Handler?, Int, Bool) in
            log.append(request)
            let n = counts[request.key, default: 0]
            counts[request.key] = n + 1
            let hold = holds[request.key, default: 0] > 0
            if hold { holds[request.key, default: 0] -= 1 }
            return (handlers[request.key], n, hold)
        }
        events.add(label)
        let reply = handler?(request, n)
            ?? (request.path.hasPrefix("/v1/app-attest/") ? .refusal(500, requestID: "unscripted") : .ok)
        return (reply, hold)
    }

    fileprivate func park(_ send: @escaping @Sendable () -> Void) {
        lock.withLock { held.append(send) }
    }
}

/// Routes every request to the `AttestServer` registered for its host.
final class AttestServerProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: AttestServer] = [:]

    static func register(_ server: AttestServer, hosts: [String]) {
        lock.withLock { for host in hosts { servers[host] = server } }
    }

    static func unregister(_ hosts: [String]) {
        lock.withLock { for host in hosts { servers[host] = nil } }
    }

    /// Answers once, and not after the loader was stopped (a cancelled request).
    private final class Sender: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        private let loader: URLProtocol

        init(_ loader: URLProtocol) { self.loader = loader }

        func stop() { lock.withLock { stopped = true } }

        func send(_ reply: AttestServer.Reply) {
            guard !lock.withLock({ stopped }), let url = loader.request.url,
                  let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                                 headerFields: reply.headers) else { return }
            loader.client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed)
            loader.client?.urlProtocol(loader, didLoad: reply.body)
            loader.client?.urlProtocolDidFinishLoading(loader)
        }
    }

    private var sender: Sender?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host,
              let server = Self.lock.withLock({ Self.servers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        // URLSession moves the body into a stream before it reaches a protocol.
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let seen = AttestServer.Request(method: request.httpMethod ?? "", host: host, path: url.path,
                                        headers: request.allHTTPHeaderFields ?? [:], body: body)
        let sender = Sender(self)
        self.sender = sender
        let answer = server.receive(seen)
        if answer.held {
            server.park { sender.send(answer.reply) }
        } else {
            sender.send(answer.reply)
        }
    }

    override func stopLoading() { sender?.stop() }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            guard n > 0 else { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

/// `FakeAppAttestService` that logs into the event list, can answer with chosen bytes, and can hold an assertion open.
final class ScriptedAppAttestService: AppAttestService, @unchecked Sendable {
    let fake: FakeAppAttestService
    private let events: EventLog
    private let lock = NSLock()
    private var _keyID: String?
    private var _attestation: Data?
    private var _assertion: Data?
    private var _assertionHold: RequestHold?

    init(supported: Bool, events: EventLog) {
        fake = FakeAppAttestService(supported: supported)
        self.events = events
    }

    var isSupported: Bool { fake.isSupported }
    var calls: [FakeAppAttestService.Call] { fake.calls }
    func count(_ method: String) -> Int {
        calls.filter {
            switch ($0, method) {
            case (.generateKey, "generateKey"), (.attestKey, "attestKey"), (.generateAssertion, "generateAssertion"): return true
            default: return false
            }
        }.count
    }

    func failNext(_ method: String, with error: Error) { fake.failNext(method, with: error) }

    /// Every key is this ID (standard base64, as `generateKey` returns it).
    var keyID: String? {
        get { lock.withLock { _keyID } }
        set { lock.withLock { _keyID = newValue } }
    }

    var attestation: Data? {
        get { lock.withLock { _attestation } }
        set { lock.withLock { _attestation = newValue } }
    }

    var assertion: Data? {
        get { lock.withLock { _assertion } }
        set { lock.withLock { _assertion = newValue } }
    }

    /// The next assertion is made, then waits for `hold.release()`.
    func holdAssertion(_ hold: RequestHold) { lock.withLock { _assertionHold = hold } }

    func generateKey() async throws -> String {
        events.add("dc generateKey")
        let made = try await fake.generateKey()
        return keyID ?? made
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        events.add("dc attestKey")
        let made = try await fake.attestKey(keyId, clientDataHash: clientDataHash)
        return attestation ?? made
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        events.add("dc generateAssertion")
        let made = try await fake.generateAssertion(keyId, clientDataHash: clientDataHash)
        if let hold = lock.withLock({ () -> RequestHold? in defer { _assertionHold = nil }; return _assertionHold }) {
            await hold.wait()
        }
        return assertion ?? made
    }
}

/// The Keychain item in memory, with its history: every save, and how often it was removed.
final class SpyAppAttestKeys: AppAttestKeyStore, @unchecked Sendable {
    private let base: MemoryAppAttestKeys
    private let lock = NSLock()
    private var _saved: [StoredAppAttestKey] = []
    private var _removals = 0

    init(_ stored: StoredAppAttestKey? = nil) { base = MemoryAppAttestKeys(stored) }

    var stored: StoredAppAttestKey? { base.stored }
    var locked: Bool {
        get { base.locked }
        set { base.locked = newValue }
    }
    var saved: [StoredAppAttestKey] { lock.withLock { _saved } }
    var removals: Int { lock.withLock { _removals } }

    func load() throws -> StoredAppAttestKey? { try base.load() }

    func save(_ key: StoredAppAttestKey) throws {
        try base.save(key)
        lock.withLock { _saved.append(key) }
    }

    func remove() {
        base.remove()
        lock.withLock { _removals += 1 }
    }
}

/// An `AppAttestor` wired into an `APIClient` against one `AttestServer`; `launch()` makes another process on the same
/// device (service, Keychain, defaults and clock stay). The account the stamp reads is `account`.
@MainActor
final class AttestRig {
    static let header = "X-RYFT-App-Token"
    nonisolated static let a = "account-a"
    nonisolated static let b = "account-b"

    let events = EventLog()
    let server: AttestServer
    let clock = TestClock()
    let service: ScriptedAppAttestService
    let keys: SpyAppAttestKeys
    let defaults: UserDefaults
    let status = APIStatus()
    var account = AttestRig.a
    private(set) var attestor: AppAttestor!
    private(set) var api: APIClient!

    /// `served`: this install has seen the challenge route answer `200` (a request without a token waits for one).
    /// The server is scripted as served with `serveAppAttest()` unless `served` is nil.
    init(served: Bool = true, supported: Bool = true, storedKey: StoredAppAttestKey? = nil,
         scripted: Bool = true) {
        server = AttestServer(host: "attest-\(UUID().uuidString.lowercased()).test", events: events)
        service = ScriptedAppAttestService(supported: supported, events: events)
        keys = SpyAppAttestKeys(storedKey)
        defaults = UserDefaults(suiteName: "ryft.test.appattest.\(UUID().uuidString)") ?? .standard
        if served {
            defaults.set(try? JSONEncoder().encode(AppAttestor.Backoff(servedSeen: true)), forKey: AppAttestor.defaultsKey)
        }
        if scripted { server.serveAppAttest() }
        launch()
    }

    /// A new process: a fresh attestor (nothing in memory) and client over the same device.
    @discardableResult
    func launch() -> AppAttestor {
        let made = AppAttestor(service: service, keys: keys, clock: clock, defaults: defaults,
                               stamp: { [weak self] in self.map { AttestStamp(account: $0.account, epoch: $0.status.epoch) } })
        attestor = made
        api = client(for: made)
        return made
    }

    func client(for attestor: AppAttestor) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AttestServerProtocol.self]
        return APIClient(session: URLSession(configuration: config), tokens: FakeTokens(), sleep: { _ in },
                         baseURL: URL(string: "https://\(server.host)"), ingestURL: URL(string: "https://\(server.ingestHost)"),
                         status: status, settings: Settings(defaults: defaults), appAttest: attestor)
    }

    @discardableResult
    func getMe(_ client: APIClient? = nil) async throws -> Data {
        try await (client ?? api).data("GET", path: "/v1/me", body: Optional<Int>.none)
    }

    /// `ingest`'s `POST /v1/sync`, as `SyncEngine` sends a page (the body isn't looked at).
    @discardableResult
    func postSync() async throws -> APIClient.Answer {
        try await api.exchange("POST", path: "/v1/sync", encodedBody: Data("{}".utf8))
    }

    /// Another account signs in: the wipe (`AuthService.wipeSharedLocalData`), the request log forgotten (the epoch
    /// moves), then the stamp reads the new account.
    func switchAccount(to next: String) {
        attestor.wipe()
        status.forgetRequests()
        account = next
    }

    /// Polls (bounded, never a fixed sleep) a condition that awaits the attestor's state.
    func until(timeout: Duration = .seconds(30), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await condition()
    }

    /// The renewal in flight (if any) has ended.
    func renewalEnded(_ attestor: AppAttestor? = nil) async -> Bool {
        let target = attestor ?? self.attestor!
        return await until { await !target.isRenewing }
    }

    /// The persisted backoff (`appAttest.backoff`).
    var backoff: AppAttestor.Backoff? {
        defaults.data(forKey: AppAttestor.defaultsKey).flatMap { try? JSONDecoder().decode(AppAttestor.Backoff.self, from: $0) }
    }

    deinit {
        AttestServerProtocol.unregister([server.host, server.ingestHost])
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
