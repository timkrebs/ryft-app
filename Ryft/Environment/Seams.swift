import Foundation
import SwiftData
import UIKit
import UserNotifications

// MARK: - persistence

/// The SwiftData container behind a seam: on disk in the app, in memory for tests
/// and previews. `TrainStore` is the live one (§3 extends it to every read model).
@MainActor
protocol Persistence: AnyObject {
    var container: ModelContainer { get }
    var context: ModelContext { get }
    func save()
    /// Everything the signed-in user left behind (sign-out, account switch).
    func wipe()
    /// Small keyed documents (`CachedDocument`), wiped with the rest.
    func document<T: Decodable>(_ type: T.Type, key: String) -> T?
    func saveDocument<T: Encodable>(_ value: T, key: String, at date: Date)
    /// The same, for a document encoded elsewhere (off the main actor).
    func saveDocumentData(_ data: Data, key: String, at date: Date)
    func removeDocument(key: String)
}

extension TrainStore: Persistence {}

// MARK: - connectivity

/// Whether there's a network path. `ConnectivityMonitor` is the live one; its
/// `preview(online:)` is the fixed one for tests and previews.
@MainActor
protocol Connectivity: AnyObject {
    var isOnline: Bool { get }
}

extension ConnectivityMonitor: Connectivity {}

// MARK: - notifications

/// Local and remote notifications behind a seam: `SystemNotifier` talks to
/// `UNUserNotificationCenter` and APNs registration, `MockNotifier` records.
@MainActor
protocol Notifier: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    /// `true` when the user allowed alerts.
    func requestAuthorization() async throws -> Bool
    func setCategories(_ categories: Set<UNNotificationCategory>)
    func add(_ request: UNNotificationRequest) async throws
    func removePending(ids: [String])
    func pendingIDs() async -> [String]
    func registerForRemoteNotifications()
    func unregisterForRemoteNotifications()
}

final class SystemNotifier: Notifier {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) { center.setNotificationCategories(categories) }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePending(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func pendingIDs() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func registerForRemoteNotifications() { UIApplication.shared.registerForRemoteNotifications() }
    func unregisterForRemoteNotifications() { UIApplication.shared.unregisterForRemoteNotifications() }
}

final class MockNotifier: Notifier {
    var status: UNAuthorizationStatus = .notDetermined
    /// What the user answers when asked.
    var grants = true

    private(set) var requests: [UNNotificationRequest] = []
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) var registeredForRemote = false
    private(set) var authorizationPrompts = 0

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        authorizationPrompts += 1
        status = grants ? .authorized : .denied
        return grants
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) { self.categories = categories }

    func add(_ request: UNNotificationRequest) async throws {
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }

    func removePending(ids: [String]) { requests.removeAll { ids.contains($0.identifier) } }
    func pendingIDs() async -> [String] { requests.map(\.identifier) }
    func registerForRemoteNotifications() { registeredForRemote = true }
    func unregisterForRemoteNotifications() { registeredForRemote = false }
}

// MARK: - feature flags

/// Every flag the app reads (`GET /v1/config` keys are open; these are the ones we know).
enum FeatureFlag: String, CaseIterable, Identifiable, Sendable {
    case trainEnabled = "train.enabled"
    case sleepPlanner = "sleep.planner"
    case todayRedesign = "today.redesign"
    // TODO(coach.enabled): reserved; no coach feature yet.
    case coachEnabled = "coach.enabled"
    case pushEnabled = "push.enabled"
    // TODO(physiology.card): reserved; no physiology card yet.
    case physiologyCard = "physiology.card"
    /// Sync bodies go up gzipped. Off until the platform takes `Content-Encoding: gzip` and
    /// turns this on (`docs/API_REQUESTS.md`); a refusal falls back to plain JSON.
    case syncGzip = "sync.gzip"
    /// "What do you wear?", the setup cards, Profile → Devices & sync, the sync check and the tracker
    /// catalog's download. Dark until the platform turns it on (design.md §3.3).
    case devicesSetup = "devices.setup"

    var id: String { rawValue }

    /// Compiled in, used until (and whenever) the platform's answer is missing.
    var compiledDefault: Bool {
        switch self {
        case .trainEnabled, .sleepPlanner: return true
        case .todayRedesign, .coachEnabled, .pushEnabled, .physiologyCard, .syncGzip, .devicesSetup: return false
        }
    }
}

/// Where a flag's value came from, for Profile → Developer.
enum FlagSource: String, Sendable {
    case compiled, remote, override
}

@MainActor
protocol FeatureFlagProvider: AnyObject {
    func isOn(_ flag: FeatureFlag) -> Bool
    func source(of flag: FeatureFlag) -> FlagSource
}

/// Compiled defaults plus local overrides: previews, tests, and the fallback before §8's remote flags.
final class StaticFlags: FeatureFlagProvider {
    var overrides: [FeatureFlag: Bool]

    init(_ overrides: [FeatureFlag: Bool] = [:]) {
        self.overrides = overrides
    }

    func isOn(_ flag: FeatureFlag) -> Bool { overrides[flag] ?? flag.compiledDefault }
    func source(of flag: FeatureFlag) -> FlagSource { overrides[flag] == nil ? .compiled : .override }
}

// MARK: - web content (ryftapp.de)

/// Static website content, not the API: no auth, no cookies, no `APIClient`, no `ReadScheduler` (ADR 0002).
protocol ContentSource: Sendable {
    func fetch(_ path: String, ifNoneMatch etag: String?, maxBytes: Int) async throws -> ContentFetch
}

enum ContentFetch: Equatable, Sendable {
    case notModified
    case fetched(Data, etag: String?)
}

/// Why a download of web content didn't arrive.
enum ContentError: Error, Equatable {
    /// Any status but 200 and 304 (a refused redirect arrives as its 3xx).
    case http(Int)
    /// More than `maxBytes`: the rest isn't read.
    case tooLarge
    case notHTTP
}

/// `https://ryftapp.de/<path>`: an ephemeral session (no URL cache, no cookies), 15 s, no waiting for
/// connectivity, redirects only within ryftapp.de over HTTPS, reading stops past `maxBytes`. 200 → `fetched`,
/// 304 → `notModified`, anything else throws.
final class WebContentSource: ContentSource {
    static let host = "ryftapp.de"
    static let timeout: TimeInterval = 15

    private let session: URLSession

    /// Tests pass a configuration with a stub `URLProtocol`.
    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        session = URLSession(configuration: configuration)
    }

    func fetch(_ path: String, ifNoneMatch etag: String?, maxBytes: Int) async throws -> ContentFetch {
        guard let url = URL(string: "https://\(Self.host)/\(path)") else { throw ContentError.http(400) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        return try await Self.load(request, session: session, maxBytes: maxBytes)
    }

    /// Off the main actor: the bytes are counted as they arrive.
    @concurrent
    private static func load(_ request: URLRequest, session: URLSession, maxBytes: Int) async throws -> ContentFetch {
        let (bytes, response) = try await session.bytes(for: request, delegate: SameHostRedirects.shared)
        guard let http = response as? HTTPURLResponse else { throw ContentError.notHTTP }
        switch http.statusCode {
        case 304:
            return .notModified
        case 200:
            if http.expectedContentLength > Int64(maxBytes) { throw ContentError.tooLarge }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { throw ContentError.tooLarge }
            }
            return .fetched(data, etag: http.value(forHTTPHeaderField: "ETag"))
        default:
            throw ContentError.http(http.statusCode)
        }
    }

    /// Follows a redirect only to `https://ryftapp.de`; anything else ends the request with its 3xx.
    private final class SameHostRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        static let shared = SameHostRedirects()

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            WebContentSource.allows(request.url) ? request : nil
        }
    }

    /// HTTPS on ryftapp.de itself, with no user info and no port.
    static func allows(_ url: URL?) -> Bool {
        guard let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return c.scheme?.lowercased() == "https" && c.host?.lowercased() == host && c.user == nil && c.password == nil
            && c.port == nil
    }
}

/// Scripted answers, in order, and the requests asked: previews, tests and every graph that isn't live (no
/// network unless told). Unscripted, it answers like a phone without a connection.
final class MockContentSource: ContentSource, @unchecked Sendable {
    struct Request: Equatable, Sendable {
        let path: String
        let etag: String?
        let maxBytes: Int
    }

    private let lock = NSLock()
    private var answers: [Result<ContentFetch, any Error>] = []
    private var asked: [Request] = []

    func script(_ answers: [Result<ContentFetch, any Error>]) {
        lock.withLock { self.answers = answers }
    }

    var requests: [Request] { lock.withLock { asked } }

    func fetch(_ path: String, ifNoneMatch etag: String?, maxBytes: Int) async throws -> ContentFetch {
        let next = lock.withLock { () -> Result<ContentFetch, any Error>? in
            asked.append(Request(path: path, etag: etag, maxBytes: maxBytes))
            return answers.isEmpty ? nil : answers.removeFirst()
        }
        guard let next else { throw URLError(.notConnectedToInternet) }
        return try next.get()
    }
}

/// The tracker catalog every screen reads (`env.trackerCatalog`): the bundled copy, or the newest valid copy
/// of `https://ryftapp.de/trackers.json` (design.md §2.6, ADR 0002).
///
/// - **One attempt when due:** 24 h after the last 200 or 304, 1 h after a failure; on app active after the
///   first frame and when a tracker screen opens. Never in demo mode, offline, or behind `devices.setup`.
///   No retry loop: the next due time is the retry.
/// - **Untrusted:** a download is used only when `TrackerCatalog.decode` accepts it (off the main actor) and
///   it isn't older than what's shown. A refusal keeps the current copy, records why, and stores no ETag.
/// - **Cached** as `CachedDocument` "content.trackers" (body, ETag, when it was checked), re-validated at
///   launch; sign-out wipes it and the bundled copy serves until the next check.
@MainActor
@Observable
final class TrackerCatalogStore {
    enum Origin: Equatable, Sendable {
        case bundled(String)
        case remote(String, etag: String?, checkedAt: Date)
    }

    /// What's kept between launches.
    struct Cached: Codable, Equatable, Sendable {
        /// The newest valid download, as it came; nil after a refusal of the cached copy.
        var body: Data?
        var etag: String?
        /// The last 200 or 304.
        var checkedAt: Date?
        var failedAt: Date?
        var failure: String?
    }

    static let ttl: TimeInterval = 86_400
    static let retryAfterFailure: TimeInterval = 3_600
    static let path = "trackers.json"
    static let maxBytes = TrackerCatalog.maxBytes
    static let documentKey = "content.trackers"

    /// Weak: the environment owns its store.
    @ObservationIgnored private weak var env: AppEnvironment?
    /// A valid download newer than the bundled copy (or the cache's, at launch).
    private var remote: TrackerCatalog?
    /// "invalid text.markup at trackers[3].setup_steps.de[2]", "http 404"; nil after a good answer.
    private(set) var lastFailure: String?
    private(set) var checkedAt: Date?
    @ObservationIgnored private var etag: String?
    @ObservationIgnored private var body: Data?
    @ObservationIgnored private var failedAt: Date?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    init(env: AppEnvironment) {
        self.env = env
    }

    /// Before `load()` (and in a preview that never calls it) the bundled copy.
    var current: TrackerCatalog { remote ?? .bundled }

    var origin: Origin {
        guard let remote else { return .bundled(TrackerCatalog.bundled.version) }
        return .remote(remote.version, etag: etag, checkedAt: checkedAt ?? .distantPast)
    }

    /// The bundled copy decoded off the main actor, then the cached download, re-validated (the rules may have
    /// tightened since): the newer of the two is shown. Once; later calls wait for the first.
    func load() async {
        if loading == nil { loading = Task { await self.loadCache() } }
        await loading?.value
    }

    /// Asks ryftapp.de when due (`force`: whenever; Debug → Feature flags → Reload tracker catalog). One request
    /// at a time: a second call waits for the first.
    func refreshIfDue(force: Bool = false) async {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.refresh(force: force) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    func isDue(at now: Date) -> Bool {
        if let failedAt, now.timeIntervalSince(failedAt) < Self.retryAfterFailure { return false }
        if let checkedAt, now.timeIntervalSince(checkedAt) < Self.ttl { return false }
        return true
    }

    /// Copy diagnostics: "catalog remote 2026-10-22.1 etag W/"5f2" checked 2026-10-22T08:12:03Z failure -".
    var diagnosticLine: String {
        let kind: String
        switch origin {
        case .bundled(let version): kind = "bundled \(version)"
        case .remote(let version, _, _): kind = "remote \(version)"
        }
        return "catalog \(kind) etag \(etag ?? "-") checked \(checkedAt.map { $0.ISO8601Format() } ?? "-") failure \(lastFailure ?? "-")"
    }

    /// Previews and screenshot runs (`-RyftCatalog preview`, Debug): show this copy.
    func stage(_ catalog: TrackerCatalog) {
        remote = catalog
    }

    // MARK: private

    private func loadCache() async {
        let bundled = await TrackerCatalog.loadBundled()
        guard let env, let cached = env.persistence.document(Cached.self, key: Self.documentKey) else { return }
        etag = cached.etag
        body = cached.body
        checkedAt = cached.checkedAt
        failedAt = cached.failedAt
        lastFailure = cached.failure
        guard let body = cached.body else { return }
        switch await Self.validate(body, now: env.clock.now()) {
        case .success(let catalog):
            if Self.isNewer(catalog.version, than: bundled.version) { remote = catalog }
        case .failure(let error):
            // Refused now: dropped with its ETag, so the next check downloads afresh.
            self.body = nil
            etag = nil
            lastFailure = "cache \(Self.describe(error))"
            save()
        }
    }

    private func refresh(force: Bool) async {
        await load()
        guard let env, !env.isDemo, env.connectivity.isOnline else { return }
        guard force || (env.flags.isOn(.devicesSetup) && isDue(at: env.clock.now())) else { return }
        do {
            switch try await env.content.fetch(Self.path, ifNoneMatch: etag, maxBytes: Self.maxBytes) {
            case .notModified:
                answered(at: env.clock.now(), note: nil)
            case .fetched(let data, let newTag):
                switch await Self.validate(data, now: env.clock.now()) {
                case .success(let catalog) where !Self.isNewer(current.version, than: catalog.version):
                    remote = catalog
                    body = data
                    etag = newTag
                    answered(at: env.clock.now(), note: nil)
                case .success(let catalog):
                    // Valid but older than what's shown: never a rollback, and no ETag for it.
                    answered(at: env.clock.now(), note: "older \(catalog.version)")
                case .failure(let error):
                    failed(Self.describe(error), at: env.clock.now())
                }
            }
        } catch {
            failed(Self.describe(error), at: env.clock.now())
        }
    }

    private func answered(at now: Date, note: String?) {
        checkedAt = now
        failedAt = nil
        lastFailure = note
        save()
    }

    private func failed(_ reason: String, at now: Date) {
        failedAt = now
        lastFailure = reason
        save()
    }

    private func save() {
        guard let env else { return }
        let cached = Cached(body: body, etag: body == nil ? nil : etag, checkedAt: checkedAt, failedAt: failedAt,
                            failure: lastFailure)
        env.persistence.saveDocument(cached, key: Self.documentKey, at: env.clock.now())
    }

    /// Validation off the main actor (up to 256 KiB of JSON and every rule).
    @concurrent
    nonisolated static func validate(_ data: Data, now: Date) async -> Result<TrackerCatalog, CatalogError> {
        do throws(CatalogError) {
            return .success(try TrackerCatalog.decode(data, now: now))
        } catch {
            return .failure(error)
        }
    }

    /// "2026-10-22.10" is newer than "2026-10-22.9": the day first, then the number after it.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> (day: String, n: Int) {
            let p = v.split(separator: ".", maxSplits: 1)
            return (String(p.first ?? ""), p.count > 1 ? Int(p[1]) ?? 0 : 0)
        }
        let x = parts(a), y = parts(b)
        return x.day != y.day ? x.day > y.day : x.n > y.n
    }

    /// For `lastFailure` and diagnostics: never the body, never a URL.
    nonisolated static func describe(_ error: any Error) -> String {
        switch error {
        case let e as CatalogError:
            switch e {
            case .tooLarge: return "too large"
            case .notJSON: return "not json"
            case .schema(let n): return "schema \(n)"
            case .invalid(let rule, let path): return "invalid \(rule) at \(path)"
            }
        case let e as ContentError:
            switch e {
            case .http(let status): return "http \(status)"
            case .tooLarge: return "too large"
            case .notHTTP: return "not http"
            }
        case let e as URLError:
            return e.code == .notConnectedToInternet ? "offline" : "network \(e.code.rawValue)"
        default:
            return "error"
        }
    }
}
