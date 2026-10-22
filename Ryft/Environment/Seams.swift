import CryptoKit
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
        // Whatever isn't read stops arriving: a refused status, a body past the limit.
        func stop(_ error: ContentError) -> ContentError {
            bytes.task.cancel()
            return error
        }
        guard let http = response as? HTTPURLResponse else { throw stop(.notHTTP) }
        switch http.statusCode {
        case 304:
            bytes.task.cancel()
            return .notModified
        case 200:
            if http.expectedContentLength > Int64(maxBytes) { throw stop(.tooLarge) }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { throw stop(.tooLarge) }
            }
            return .fetched(data, etag: http.value(forHTTPHeaderField: "ETag"))
        default:
            throw stop(.http(http.statusCode))
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
/// - **Behind `devices.setup`:** with the flag off the bundled copy serves and nothing else is read or asked.
/// - **One attempt when due:** 24 h after the last 200 or 304, 1 h after a failure; on app active after the
///   first frame and when a tracker screen opens. Never in demo mode or offline. No retry loop: the next due
///   time is the retry.
/// - **Untrusted:** a download is used only when `TrackerCatalog.decode` accepts it (off the main actor) and
///   it isn't older than what's shown. A refusal keeps the current copy, records why, and stores no ETag.
/// - **Crash-guarded:** a marker with the body's SHA-256 exists while a copy is decoded. Left over at launch,
///   the last run died decoding: the cache goes, and that body is refused unread from then on.
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
        /// SHA-256 of bodies the decoder died on, newest last (at most `maxRefused`): never decoded again.
        var refused: [String]?
    }

    static let ttl: TimeInterval = 86_400
    static let retryAfterFailure: TimeInterval = 3_600
    static let path = "trackers.json"
    static let maxBytes = TrackerCatalog.maxBytes
    static let documentKey = "content.trackers"
    /// While a copy is decoded: `contentDirectory/trackers.decoding`, holding the body's SHA-256.
    static let markerName = "trackers.decoding"
    static let maxRefused = 8
    /// An ETag longer than this, or with anything but visible ASCII, isn't kept.
    nonisolated static let maxETag = 128

    /// Weak: the environment owns its store.
    @ObservationIgnored private weak var env: AppEnvironment?
    /// A valid download newer than the bundled copy (or the cache's, at launch).
    private var remote: TrackerCatalog?
    /// "invalid text.markup at trackers[3].setup_steps.de[2]", "http 404", "crashed"; nil after a good answer.
    private(set) var lastFailure: String?
    private(set) var checkedAt: Date?
    @ObservationIgnored private var etag: String?
    @ObservationIgnored private var body: Data?
    @ObservationIgnored private var failedAt: Date?
    @ObservationIgnored private var refused: [String] = []
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var inFlight: (task: Task<Void, Never>, force: Bool)?

    init(env: AppEnvironment) {
        self.env = env
    }

    private var isOn: Bool { env?.flags.isOn(.devicesSetup) ?? false }

    /// The bundled copy, unless `devices.setup` is on and a newer valid download arrived.
    var current: TrackerCatalog { isOn ? remote ?? .bundled : .bundled }

    var origin: Origin {
        guard isOn, let remote else { return .bundled(TrackerCatalog.bundled.version) }
        return .remote(remote.version, etag: etag, checkedAt: checkedAt ?? .distantPast)
    }

    /// The bundled copy decoded off the main actor; with the flag on, then the cached download, re-validated
    /// (the rules may have tightened since): the newer of the two is shown. The cache once; later calls wait
    /// for the first, and a call while the flag is off leaves it for the next.
    func load() async {
        _ = await TrackerCatalog.loadBundled()
        guard isOn else { return }
        if loading == nil { loading = Task { await self.loadCache() } }
        await loading?.value
    }

    /// Asks ryftapp.de when due (`force`: whenever; Debug → Feature flags → Reload tracker catalog). One request
    /// at a time: a call waits for the one running, and a forced one then makes its own attempt.
    func refreshIfDue(force: Bool = false) async {
        if let running = inFlight {
            await running.task.value
            guard force, !running.force else { return }
            // Another attempt started meanwhile (not the one just awaited, which may not have cleared itself yet).
            if let again = inFlight, again.task != running.task { return await again.task.value }
        }
        let task = Task { await self.refresh(force: force) }
        inFlight = (task, force)
        await task.value
        if inFlight?.task == task { inFlight = nil }
    }

    /// A clock that went back makes an answer or failure "in the future": then it no longer holds anything back.
    func isDue(at now: Date) -> Bool {
        if let failedAt, now >= failedAt, now.timeIntervalSince(failedAt) < Self.retryAfterFailure { return false }
        if let checkedAt, now >= checkedAt, now.timeIntervalSince(checkedAt) < Self.ttl { return false }
        return true
    }

    /// Signed out or another account: the cache went with the store, so nothing of it stays in memory. Bodies
    /// that crashed the decoder stay refused.
    func accountChanged() {
        remote = nil
        etag = nil
        body = nil
        checkedAt = nil
        failedAt = nil
        lastFailure = nil
        loading = nil
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

    // MARK: private

    private var marker: URL? { env?.contentDirectory.appendingPathComponent(Self.markerName) }

    private func loadCache() async {
        guard let env else { return }
        let cached = env.persistence.document(Cached.self, key: Self.documentKey)
        etag = cached?.etag
        body = cached?.body
        checkedAt = cached?.checkedAt
        failedAt = cached?.failedAt
        lastFailure = cached?.failure
        refused = cached?.refused ?? []
        // The last run died decoding a copy: the cache goes unread, and that body is never decoded again.
        if let marker, let hash = Self.leftover(marker) {
            refuse(hash)
            body = nil
            etag = nil
            checkedAt = nil
            failedAt = env.clock.now()
            lastFailure = "crashed"
            await save()
            return
        }
        guard let body else { return }
        switch await decode(body) {
        case .success(let catalog):
            if TrackerCatalog.isNewer(catalog.version, than: TrackerCatalog.bundled.version) { remote = catalog }
        case .failure(let error):
            // Refused now: dropped with its ETag and its check, so the next check downloads afresh.
            self.body = nil
            etag = nil
            checkedAt = nil
            lastFailure = "cache \(Self.describe(error))"
            await save()
        }
    }

    private func refresh(force: Bool) async {
        await load()
        guard let env, !env.isDemo, env.connectivity.isOnline else { return }
        guard force || (isOn && isDue(at: env.clock.now())) else { return }
        do {
            switch try await env.content.fetch(Self.path, ifNoneMatch: etag, maxBytes: Self.maxBytes) {
            case .notModified:
                await answered(note: nil)
            case .fetched(let data, let newTag):
                guard !refused.contains(Self.hash(data)) else { return await failed("crashed") }
                let shown = remote ?? .bundled
                switch await decode(data) {
                case .success(let catalog) where !TrackerCatalog.isNewer(shown.version, than: catalog.version):
                    remote = catalog
                    body = data
                    etag = Self.storable(newTag)
                    await answered(note: nil)
                case .success(let catalog):
                    // Valid but older than what's shown: never a rollback, and no ETag for it. (The version passed
                    // the validator's pattern.)
                    await answered(note: "older \(catalog.version)")
                case .failure(let error):
                    await failed(Self.describe(error))
                }
            }
        } catch {
            await failed(Self.describe(error))
        }
    }

    /// Validation off the main actor, inside the crash marker.
    private func decode(_ data: Data) async -> Result<TrackerCatalog, CatalogError> {
        let now = env?.clock.now() ?? .now
        guard let marker else { return await Self.validate(data, now: now) }
        Self.mark(marker, hash: Self.hash(data))
        defer { try? FileManager.default.removeItem(at: marker) }
        return await Self.validate(data, now: now)
    }

    private func refuse(_ hash: String) {
        refused = Array((refused.filter { $0 != hash } + [hash]).suffix(Self.maxRefused))
    }

    private func answered(note: String?) async {
        checkedAt = env?.clock.now()
        failedAt = nil
        lastFailure = note
        await save()
    }

    private func failed(_ reason: String) async {
        failedAt = env?.clock.now()
        lastFailure = reason
        await save()
    }

    /// Encoded off the main actor (the body is up to 256 KiB), then stored.
    private func save() async {
        guard let env else { return }
        let cached = Cached(body: body, etag: body == nil ? nil : etag, checkedAt: checkedAt, failedAt: failedAt,
                            failure: lastFailure, refused: refused.isEmpty ? nil : refused)
        guard let data = await Self.encode(cached) else { return }
        env.persistence.saveDocumentData(data, key: Self.documentKey, at: env.clock.now())
    }

    @concurrent
    private static func encode(_ cached: Cached) async -> Data? { WireCoding.encode(cached) }

    /// Validation off the main actor (up to 256 KiB of JSON and every rule).
    @concurrent
    nonisolated static func validate(_ data: Data, now: Date) async -> Result<TrackerCatalog, CatalogError> {
        do throws(CatalogError) {
            return .success(try TrackerCatalog.decode(data, now: now))
        } catch {
            return .failure(error)
        }
    }

    nonisolated static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The marker before a decode, written atomically (never `UserDefaults`, which may not reach the disk
    /// before a crash).
    nonisolated static func mark(_ url: URL, hash: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(hash.utf8).write(to: url, options: .atomic)
    }

    /// A marker the last run left (its hash), removed.
    nonisolated static func leftover(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return String(data: data, encoding: .utf8).map(clean)
    }

    /// An ETag worth sending back: at most 128 visible ASCII characters, no spaces.
    nonisolated static func storable(_ etag: String?) -> String? {
        guard let etag, !etag.isEmpty, etag.count <= maxETag,
              etag.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { return nil }
        return etag
    }

    /// For `lastFailure` and diagnostics: never the body, never a URL; anything from outside cut down to
    /// letters, digits and `_.[]`, at most 80 characters.
    nonisolated static func describe(_ error: any Error) -> String {
        switch error {
        case let e as CatalogError:
            switch e {
            case .tooLarge: return "too large"
            case .notJSON: return "not json"
            case .schema(let n): return "schema \(n)"
            case .invalid(let rule, let path): return "invalid \(clean(rule)) at \(clean(path))"
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

    nonisolated static func clean(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.[]")
        var kept = String.UnicodeScalarView()
        kept.append(contentsOf: text.unicodeScalars.filter { allowed.contains($0) }.prefix(80))
        return String(kept)
    }
}
