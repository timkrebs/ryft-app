// HTTP client for the RYFT platform (one host in production; ingest may sit
// on its own port in a compose stack). The bearer is the Supabase access
// token (AuthService). Status handling follows API.md → Errors:
//   401 → refresh the session once, retry once; a second 401 signs out.
//   403 + code → a gate (invite, consent), reported to `APIStatus`; never "log in again".
//   503 → never sign out; wait `Retry-After`, retry (sync is idempotent).
//   429 → wait `Retry-After`, retry once.
//   413 → thrown; SyncService halves the page size.
// A scheduled read (`singleAttempt`, set by `ReadScheduler`) makes one attempt: no 429/503
// loop, `Retry-After` on the error, the fail-fast session (ADR 0001). A cancelled request
// throws `CancellationError`; a request without an answer is recorded with status 0.
// Every failure keeps the platform's request ID (`X-Request-ID` / `request_id`).
// Every request carries `X-RYFT-Device-ID`; `X-RYFT-Gate` on any response (a gate
// in warn mode) is reported like a refusal's code.
import Foundation
import zlib

enum APIError: LocalizedError {
    case notConfigured
    case signedOut
    /// `retryAfter`: the response's `Retry-After` in whole seconds, when it sent one.
    case http(Int, String, requestID: String? = nil, code: APIErrorCode? = nil, retryAfter: Int? = nil)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return SupabaseConfig.problem ?? String(localized: "This build has no RYFT server configured.")
        case .signedOut: return String(localized: "You're signed out. Log in to continue.")
        case .http(401, _, _, _, _): return String(localized: "Your session has ended. Log in again to continue.")
        case .http(403, _, _, .inviteRequired?, _):
            return String(localized: "RYFT is invite-only during the beta. Enter your invite code to continue.")
        case .http(403, _, _, .consentRequired?, _):
            return String(localized: "RYFT needs your consent before it can sync your health data.")
        // API.md: without a code, a 403 means changing something built in (exercise, plan, behavior).
        case .http(403, _, _, nil, _): return String(localized: "This is built into RYFT and can't be changed.")
        case .http(429, _, _, _, _): return String(localized: "Too many requests. Try again in a minute.")
        case .http(500, _, _, _, _): return String(localized: "Something went wrong on RYFT's side. Try again later.")
        case .http(503, _, _, _, _): return String(localized: "RYFT is catching up. Try again in a moment.")
        case .http(let code, let message, _, _, _):
            return message.isEmpty ? String(localized: "The server returned \(code).") : message
        case .transport(let e): return e.localizedDescription
        }
    }

    var status: Int? {
        if case .http(let code, _, _, _, _) = self { return code }
        return nil
    }

    var requestID: String? {
        if case .http(_, _, let id, _, _) = self { return id }
        return nil
    }

    /// The error body's `code`, if the platform sent one this build knows.
    var code: APIErrorCode? {
        if case .http(_, _, _, let code, _) = self { return code }
        return nil
    }

    /// `Retry-After` in whole seconds, as the response sent it.
    var retryAfter: Int? {
        if case .http(_, _, _, _, let seconds) = self { return seconds }
        return nil
    }

    /// A `403` with a gate code: route to the invite or consent screen, never show it as a failure.
    var gate: APIErrorCode? { status == 403 ? code : nil }

    /// `422`: well-formed but invalid (a field, a value, a day not editable).
    /// Shown inline next to what caused it; never retried, never a sign-out.
    var isFieldError: Bool { status == 422 }

    /// `409` on `POST /v1/behaviors`: the app-generated id belongs to someone
    /// else (distinct from `PUT /v1/sessions`'s 409, which carries the server copy).
    var isIDTaken: Bool { status == 409 }

    /// A route the app knows answered `404`: that feature isn't deployed yet
    /// (`.notLive`), so it hides instead of showing an error.
    var isNotLive: Bool { isNotFound }

    /// The platform doesn't serve this endpoint (yet) — callers degrade gracefully.
    var isNotFound: Bool {
        if case .http(let code, _, _, _, _) = self { return code == 404 || code == 405 || code == 501 }
        return false
    }
}

extension Error {
    var isEndpointMissing: Bool { (self as? APIError)?.isNotFound ?? false }

    /// The caller's task was cancelled (`CancellationError`, or `URLError.cancelled` from a raw
    /// session): nothing failed, so nothing is shown, dropped or counted.
    var isCancellation: Bool { FailureKind.of(self) == .cancelled }

    /// The gate behind a refused call (`403 invite_required` / `consent_required`), if any.
    var gate: APIErrorCode? { (self as? APIError)?.gate }

    /// "HTTP 403 · consent_required · Request ID 01a1…" for an inline message's Details,
    /// or `nil`. The request ID is exactly as the platform sent it: support searches for it.
    var diagnosticDetails: String? {
        guard let e = self as? APIError, let status = e.status else { return nil }
        let head = e.code.map { "HTTP \(status) · \($0.rawValue)" } ?? "HTTP \(status)"
        guard let id = e.requestID else { return head }
        return String(localized: "\(head) · Request ID \(id)")
    }
}

/// An error from outside the platform's API (the auth SDK) that knows whether trying again can help.
protocol TransientClassifiable: Error {
    var isTransientFailure: Bool { get }
}

/// What a failed read means for the read pipeline (`ReadScheduler`): retried, ignored, counted,
/// or the user's to act on. Pure; classification table in the refresh-resilience design (§3).
enum FailureKind: String, Codable, Sendable {
    /// No answer, a timeout, `408`, `429`, `5xx` (not `501`): retried, counted after the retries.
    case transient
    /// The task was cancelled (`.refreshable`, `.task(id:)`, sign-out): never retried, recorded or counted.
    case cancelled
    /// A final `401` (after `APIClient`'s refresh-once), or no session.
    case signedOut
    /// `403 invite_required` / `consent_required`: onboarding shows it; never counted.
    case gate
    /// Reserved: `API.md` has no signal for an outdated app yet, so nothing produces it.
    case appTooOld
    /// Anything else (`400`, `404`, `422`, a decoding failure…): not retried, counted.
    case other

    var isActionable: Bool { self == .signedOut || self == .gate || self == .appTooOld }

    static func of(_ error: Error) -> FailureKind {
        if error is CancellationError { return .cancelled }
        if let url = error as? URLError { return url.code == .cancelled ? .cancelled : .transient }
        // The auth SDK's own refresh failing without ending the session (5xx, 408, 429, a refresh
        // another one replaced): try again, like the platform's own transient answers.
        if let classified = error as? any TransientClassifiable { return classified.isTransientFailure ? .transient : .other }
        guard let api = error as? APIError else { return .other }
        switch api {
        case .transport(let inner):
            if inner is CancellationError || (inner as? URLError)?.code == .cancelled { return .cancelled }
            return .transient
        case .signedOut: return .signedOut
        case .notConfigured: return .other
        case .http(let status, _, _, let code, _):
            switch status {
            case 401: return .signedOut
            case 403 where code == .inviteRequired || code == .consentRequired: return .gate
            case 408, 429: return .transient
            case 501: return .other
            case 500...599: return .transient
            default: return .other
            }
        }
    }
}

/// How often and how long a scheduled read waits before trying again (`ReadScheduler`).
/// Full jitter: retry `n` waits `random(0 ... min(maxBackoff, base · 2^(n−1)))`. A `Retry-After`
/// up to `retryAfterCap` is waited out (at least); beyond it there's no retry now.
struct RetryPolicy: Equatable, Sendable {
    var maxRetries: Int
    var base: Duration
    var maxBackoff: Duration
    var retryAfterCap: Duration
    /// Whether a request that timed out is tried again: not in the background, where the system's
    /// time is short (a timeout already took most of it).
    var retriesTimeouts = true

    /// Someone watching: two retries, waits of 0–1 s and 0–2 s, `Retry-After` up to 5 s.
    static let foreground = RetryPolicy(maxRetries: 2, base: .seconds(1), maxBackoff: .seconds(4),
                                        retryAfterCap: .seconds(5))
    /// The system woke the app: one retry (not after a timeout), `Retry-After` up to 2 s.
    static let background = RetryPolicy(maxRetries: 1, base: .seconds(1), maxBackoff: .seconds(2),
                                        retryAfterCap: .seconds(2), retriesTimeouts: false)

    /// Wait before retry `attempt` (1-based), or nil: don't retry (not transient, out of retries,
    /// or a `Retry-After` beyond the cap).
    func delay(before attempt: Int, after error: Error, random: (ClosedRange<Double>) -> Double) -> Duration? {
        guard attempt >= 1, attempt <= maxRetries, FailureKind.of(error) == .transient else { return nil }
        if !retriesTimeouts, Self.isTimeout(error) { return nil }
        let ceiling = min(maxBackoff, base * (1 << min(attempt - 1, 16)))
        let jitter = Duration.seconds(random(0...ceiling.timeInterval))
        guard let seconds = Self.retryAfter(error) else { return jitter }
        let retryAfter = Duration.seconds(seconds)
        guard retryAfter <= retryAfterCap else { return nil }
        return max(retryAfter, jitter)
    }

    /// No answer in time (`URLError.timedOut`, also wrapped in `APIError.transport`).
    static func isTimeout(_ error: Error) -> Bool {
        if let url = error as? URLError { return url.code == .timedOut }
        if case .transport(let inner)? = error as? APIError { return (inner as? URLError)?.code == .timedOut }
        return false
    }

    /// The error's `Retry-After`; a `429` without one counts as 1 s.
    static func retryAfter(_ error: Error) -> Int? {
        guard let api = error as? APIError else { return nil }
        if let seconds = api.retryAfter { return seconds }
        return api.status == 429 ? 1 : nil
    }
}

extension URLError.Code {
    /// "timedOut", "notConnectedToInternet": for diagnostics, never shown as a sentence.
    var name: String {
        switch self {
        case .timedOut: return "timedOut"
        case .notConnectedToInternet: return "notConnectedToInternet"
        case .networkConnectionLost: return "networkConnectionLost"
        case .cannotFindHost: return "cannotFindHost"
        case .cannotConnectToHost: return "cannotConnectToHost"
        case .dnsLookupFailed: return "dnsLookupFailed"
        case .secureConnectionFailed: return "secureConnectionFailed"
        case .serverCertificateUntrusted: return "serverCertificateUntrusted"
        case .dataNotAllowed: return "dataNotAllowed"
        case .internationalRoamingOff: return "internationalRoamingOff"
        case .cancelled: return "cancelled"
        case .badServerResponse: return "badServerResponse"
        default: return "urlError\(rawValue)"
        }
    }
}

/// Supplies the bearer token. `AuthService` in the app, a stub in tests.
protocol AccessTokenProvider: AnyObject, Sendable {
    func accessToken() async throws -> String
    /// Forces a refresh, for the retry after a 401.
    func refreshedAccessToken() async throws -> String
    /// Called when the retry was rejected too.
    func rejectedAfterRefresh() async
}

/// Everything the UI reads. `APIClient` talks to the platform; `MockDataSource`
/// serves the realistic history used by previews and the simulator demo mode.
protocol RyftDataSource {
    func me() async throws -> User
    func patchMe(_ p: UserPatch) async throws -> User
    func days(from: Date, to: Date) async throws -> [DailyScore]
    func day(_ date: Date) async throws -> DayDetail
    func sleep(range: SleepRangeKind) async throws -> SleepRange
    func workouts(from: Date, to: Date) async throws -> [Workout]
    func workout(id: UUID) async throws -> WorkoutDetail
    func trends(metric: TrendMetric, range: TrendRange) async throws -> TrendSeries
    func insights() async throws -> [Insight]
    func recompute(from: Date, to: Date) async throws
    /// Erases the account (data, then the Supabase user).
    func deleteMe() async throws -> AccountDeleted
}

final class APIClient: RyftDataSource {
    static let shared = APIClient()

    private let settings = Settings.shared
    private let session: URLSession
    private let backgroundSession: URLSession
    private let tokens: AccessTokenProvider?
    private let sleep: @Sendable (Int) async throws -> Void
    /// Replaces the configured API URL (tests).
    private let baseURL: URL?
    /// Where gates, 503 waits and failures are reported; `APIStatus.shared` unless a test injects one.
    private let status: APIStatus?

    /// 503 retries per request before giving up, and the longest wait honoured.
    static let maxUnavailableRetries = 3
    static let maxUnavailableWait = 30
    static let maxRateLimitWait = 60

    static let defaultConfiguration: URLSessionConfiguration = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 300 // first backfill can be tens of MB
        c.waitsForConnectivity = true
        return c
    }()

    /// For runs the system woke the app for (HealthKit delivery, BG tasks, silent push):
    /// fail fast instead of waiting for a network, so the run ends before iOS ends it.
    static let backgroundConfiguration: URLSessionConfiguration = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 25
        c.waitsForConnectivity = false
        return c
    }()

    /// Set by `SyncCoordinator` for a background run: its requests use `backgroundSession`.
    @TaskLocal static var runsInBackground = false

    /// One attempt: no `429`/`503` loop (the error carries `Retry-After` instead), the fail-fast
    /// session, no `APIStatus.retryNotice`. Set by `ReadScheduler`, the one retry layer for reads
    /// (ADR 0001), so a scheduled read never sees two. The `401` refresh-once stays: that's auth.
    @TaskLocal static var singleAttempt = false

    /// `tokens` defaults to `AuthService.shared`, resolved per request on the
    /// main actor. `sleep` waits out `Retry-After` (tests skip the wait).
    /// `session` (tests: a stubbed one) serves background runs too unless `backgroundSession` is given.
    init(session: URLSession? = nil, backgroundSession: URLSession? = nil,
         tokens: AccessTokenProvider? = nil,
         sleep: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         baseURL: URL? = nil, status: APIStatus? = nil) {
        self.session = session ?? URLSession(configuration: APIClient.defaultConfiguration)
        self.backgroundSession = backgroundSession ?? session
            ?? URLSession(configuration: APIClient.backgroundConfiguration)
        self.baseURL = baseURL
        self.tokens = tokens
        self.sleep = sleep
        self.status = status
    }

    /// Routes the invite gate leaves open (API.md → Errors): the onboarding calls.
    static let openBehindInviteGate: Set<String> = [
        "GET /v1/me", "GET /v1/me/sync", "GET /v1/config", "GET /v1/model", "POST /v1/me/invite",
        "POST /v1/me/consent", "DELETE /v1/me/consent", "POST /v1/feedback", "DELETE /v1/me",
    ]

    static func isOpenBehindInviteGate(_ method: String, _ path: String) -> Bool {
        let route = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        return openBehindInviteGate.contains("\(method) \(route)")
    }

    /// `X-RYFT-Gate: invite_required, consent_required` (comma-separated, or repeated,
    /// which URLSession joins with commas). Unknown codes are dropped.
    static func gates(_ response: HTTPURLResponse) -> Set<APIErrorCode> {
        guard let value = response.value(forHTTPHeaderField: "X-RYFT-Gate") else { return [] }
        return Set(value.split(separator: ",").compactMap {
            APIErrorCode(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }

    // Go emits RFC3339 with nanoseconds; Foundation's default .iso8601 rejects fractions.
    static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = DateParsing.rfc3339(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: endpoints

    /// `POST /v1/sync` with a body `SyncEngine` encoded off the main actor (and gzipped,
    /// `contentEncoding: "gzip"`, when the platform takes it).
    func sync(encoded body: Data, contentEncoding: String?) async throws -> SyncResponse {
        let answer = try await exchange("POST", path: "/v1/sync", encodedBody: body, contentEncoding: contentEncoding,
                                        base: settings.ingestURL)
        return try Self.decode(SyncResponse.self, from: answer)
    }

    func me() async throws -> User {
        try await send("GET", path: "/v1/me", body: Optional<Int>.none)
    }

    func patchMe(_ p: UserPatch) async throws -> User {
        try await send("PATCH", path: "/v1/me", body: p)
    }

    func deleteMe() async throws -> AccountDeleted {
        try await send("DELETE", path: "/v1/me", body: Optional<Int>.none)
    }

    /// `204`. The code is single-use and lives five minutes, so a `503` is retried once only.
    func postAppleAuthorization(code: String) async throws {
        _ = try await exchange("POST", path: "/v1/me/apple-authorization", body: AppleAuthorization(code: code),
                               unavailableRetries: 1)
    }

    func days(from: Date, to: Date) async throws -> [DailyScore] {
        try await send("GET", path: "/v1/days?from=\(Self.dayString(from))&to=\(Self.dayString(to))", body: Optional<Int>.none)
    }

    func day(_ date: Date) async throws -> DayDetail {
        try await send("GET", path: "/v1/days/\(Self.dayString(date))", body: Optional<Int>.none)
    }

    func sleep(range: SleepRangeKind) async throws -> SleepRange {
        try await send("GET", path: "/v1/sleep?range=\(range.rawValue)", body: Optional<Int>.none)
    }

    func workouts(from: Date, to: Date) async throws -> [Workout] {
        try await send("GET", path: "/v1/workouts?from=\(Self.dayString(from))&to=\(Self.dayString(to))", body: Optional<Int>.none)
    }

    func workout(id: UUID) async throws -> WorkoutDetail {
        try await send("GET", path: "/v1/workouts/\(id.uuidString.lowercased())", body: Optional<Int>.none)
    }

    func trends(metric: TrendMetric, range: TrendRange) async throws -> TrendSeries {
        try await send("GET", path: "/v1/trends?metric=\(metric.rawValue)&range=\(range.rawValue)", body: Optional<Int>.none)
    }

    func insights() async throws -> [Insight] {
        try await send("GET", path: "/v1/insights", body: Optional<Int>.none)
    }

    /// 202 Accepted; the body (if any) is ignored.
    func recompute(from: Date, to: Date) async throws {
        _ = try await data("POST", path: "/v1/recompute",
                           body: RecomputeRequest(from: Self.dayString(from), to: Self.dayString(to)))
    }

    // MARK: plumbing

    func send<B: Encodable, R: Decodable>(_ method: String, path: String, body: B?, base: URL? = nil) async throws -> R {
        try Self.decode(R.self, from: try await exchange(method, path: path, body: body, base: base))
    }

    /// The answer's body, or — when this build can't read it — an `APIError` that keeps the status
    /// and request ID it came with (a report can find it; never retried, `FailureKind.other`).
    static func decode<R: Decodable>(_ type: R.Type, from answer: Answer) throws -> R {
        do {
            return try jsonDecoder.decode(R.self, from: answer.data)
        } catch is DecodingError {
            throw APIError.http(answer.status, String(localized: "RYFT sent an answer this version of the app can't read."),
                                requestID: answer.requestID)
        }
    }

    /// A served request: its status, body and `X-Request-ID`.
    typealias Answer = (status: Int, data: Data, requestID: String?)

    func data<B: Encodable>(_ method: String, path: String, body: B?, base: URL? = nil) async throws -> Data {
        try await exchange(method, path: path, body: body, base: base).data
    }

    /// Like `data`, but statuses in `accepting` are returned instead of thrown —
    /// e.g. `409` on `PUT /v1/sessions/{id}`, whose body is the server's copy.
    func exchange<B: Encodable>(_ method: String, path: String, body: B?, base: URL? = nil,
                                accepting: Set<Int> = [],
                                unavailableRetries: Int = APIClient.maxUnavailableRetries) async throws -> Answer {
        try await exchange(method, path: path, encodedBody: body.map { try Self.jsonEncoder.encode($0) }, base: base,
                           accepting: accepting, unavailableRetries: unavailableRetries)
    }

    /// The request with an already encoded JSON body (or none).
    func exchange(_ method: String, path: String, encodedBody: Data?, contentEncoding: String? = nil, base: URL? = nil,
                  accepting: Set<Int> = [],
                  unavailableRetries: Int = APIClient.maxUnavailableRetries) async throws -> Answer {
        guard let root = base ?? baseURL ?? settings.apiURL, root.host != nil,
              let url = URL(string: path, relativeTo: root) else {
            throw APIError.notConfigured
        }
        let status = await statusSink()
        // One gate, not twenty failed requests: behind the invite gate only onboarding goes out.
        if await status.inviteBlocked, !Self.isOpenBehindInviteGate(method, path) {
            throw APIError.http(403, "invite required", code: .inviteRequired)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Exercise names follow it (`de…` → German).
        req.setValue(Self.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        // The install's id (as in POST /v1/sync): GET /v1/me derives `account_hint` from it.
        req.setValue(settings.deviceId.uuidString.lowercased(), forHTTPHeaderField: "X-RYFT-Device-ID")
        if let encodedBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(contentEncoding, forHTTPHeaderField: "Content-Encoding")
            req.httpBody = encodedBody
        }
        let tokens = await tokenProvider()
        var bearer = try await tokens.accessToken()
        let single = Self.singleAttempt
        var refreshed = false, rateLimited = false, unavailable = 0
        while true {
            let started = Date()
            let data: Data, response: HTTPURLResponse?
            do {
                (data, response) = try await perform(req, bearer: bearer)
            } catch {
                // No response: recorded with its duration and URLError name (status 0), so Sync
                // details and Copy diagnostics show timeouts too. A cancellation isn't a failure.
                let transport = (error as? APIError).flatMap { e -> String? in
                    if case .transport(let inner) = e { return (inner as? URLError)?.code.name ?? "transport" }
                    return nil
                } ?? "cancelled"
                if error is CancellationError {
                    await status.cancelled()
                } else {
                    await status.record(APIStatus.RequestFailure(date: .now, method: method, path: path, status: 0,
                                                                 requestID: nil, durationMs: Self.milliseconds(since: started),
                                                                 transport: transport))
                }
                if unavailable > 0 { await status.finishedWaiting() }
                throw error
            }
            let durationMs = Self.milliseconds(since: started)
            let code = response?.statusCode ?? 0
            if (200..<300).contains(code) || accepting.contains(code) {
                if unavailable > 0 { await status.finishedWaiting() }
                // Served, but a gate in warn mode would have refused it: prompt for what's missing.
                if let warned = response.map(Self.gates), !warned.isEmpty {
                    await status.observe(warned, enforced: false)
                }
                let requestID = response?.value(forHTTPHeaderField: "X-Request-ID")
                await status.served(.init(date: .now, method: method, path: path, status: code, requestID: requestID,
                                          durationMs: durationMs))
                return (code, data, requestID)
            }
            let retryAfter = response.flatMap(Self.retryAfter)
            switch code {
            case 401 where !refreshed:
                // The token may have been revoked or rotated: refresh once, retry once.
                refreshed = true
                bearer = try await tokens.refreshedAccessToken()
                continue
            case 401:
                await tokens.rejectedAfterRefresh()
            case 429 where !rateLimited && !single:
                rateLimited = true
                let wait = min(retryAfter ?? 1, Self.maxRateLimitWait)
                APIStatus.log.notice("429 on \(method, privacy: .public) \(redactedPath(path), privacy: .public); retrying in \(wait) s")
                try await sleep(wait)
                continue
            case 503 where unavailable < unavailableRetries && !single:
                // Not a sign-in problem (API.md): keep the session, wait, retry.
                unavailable += 1
                let wait = min(retryAfter ?? 5, Self.maxUnavailableWait)
                await status.waiting(seconds: wait)
                try await sleep(wait)
                continue
            default:
                break
            }
            if unavailable > 0 { await status.finishedWaiting() }
            let body = try? Self.jsonDecoder.decode(APIErrorBody.self, from: data)
            let message = body?.error
                ?? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let requestID = response?.value(forHTTPHeaderField: "X-Request-ID") ?? body?.requestId
            let error = APIError.http(code, message, requestID: requestID, code: body?.code, retryAfter: retryAfter)
            APIStatus.log.error("\(code) \(body?.code?.rawValue ?? "", privacy: .public) on \(method, privacy: .public) \(redactedPath(path), privacy: .public), request \(requestID ?? "-", privacy: .public)")
            if let gate = error.gate { await status.observe([gate], enforced: true) }
            await status.record(.init(date: .now, method: method, path: path, status: code,
                                      code: body?.code?.rawValue, requestID: requestID, durationMs: durationMs))
            throw error
        }
    }

    private static func milliseconds(since start: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(start) * 1000).rounded()))
    }

    /// `Retry-After` in whole seconds (the platform never sends an HTTP date).
    static func retryAfter(_ response: HTTPURLResponse) -> Int? {
        response.value(forHTTPHeaderField: "Retry-After")
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .map { max(0, $0) }
    }

    /// One round trip. A scheduled read (`singleAttempt`) uses the fail-fast session like a background
    /// run: 20 s, and no waiting for a network that isn't there (the scheduler retries). A cancelled
    /// task's `URLError.cancelled` comes back as `CancellationError`: cancelling isn't failing.
    private func perform(_ request: URLRequest, bearer: String) async throws -> (Data, HTTPURLResponse?) {
        var req = request
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let failFast = Self.runsInBackground || Self.singleAttempt
        do {
            let (data, resp) = try await (failFast ? backgroundSession : session).data(for: req)
            return (data, resp as? HTTPURLResponse)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.transport(error)
        }
    }

    private func tokenProvider() async -> AccessTokenProvider {
        if let tokens { return tokens }
        return await AuthService.shared
    }

    private func statusSink() async -> APIStatus {
        if let status { return status }
        return await APIStatus.shared
    }

    static var acceptLanguage: String {
        Locale.preferredLanguages.prefix(3).joined(separator: ", ")
    }

    static func dayString(_ d: Date) -> String {
        DayFormat.string(from: d)
    }
}

/// gzip (RFC 1952) for upload bodies, `Content-Encoding: gzip`: a sync page's JSON repeats
/// the same keys and source names in every record and shrinks about tenfold.
enum Gzip {
    enum Failure: Error, Equatable { case zlib(Int32) }

    static func compress(_ data: Data) throws -> Data {
        var stream = z_stream()
        // 15 + 16: a gzip header and trailer instead of zlib's.
        var status = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY,
                                   ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw Failure.zlib(status) }
        defer { deflateEnd(&stream) }
        var output = Data(count: Int(deflateBound(&stream, uLong(data.count))))
        try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            try output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = out.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(out.count)
                status = deflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END else { throw Failure.zlib(status) }
            }
        }
        output.count = Int(stream.total_out)
        return output
    }

    static func decompress(_ data: Data) throws -> Data {
        var stream = z_stream()
        // 15 + 32: gzip or zlib, whichever the header says.
        var status = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw Failure.zlib(status) }
        defer { inflateEnd(&stream) }
        var output = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            repeat {
                try chunk.withUnsafeMutableBufferPointer { out in
                    stream.next_out = out.baseAddress
                    stream.avail_out = uInt(out.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                    guard status == Z_OK || status == Z_STREAM_END else { throw Failure.zlib(status) }
                    output.append(out.baseAddress!, count: out.count - Int(stream.avail_out))
                }
            } while status != Z_STREAM_END
        }
        return output
    }
}
