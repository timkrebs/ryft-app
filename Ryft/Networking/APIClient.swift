// HTTP client for the RYFT platform (one host in production; ingest may sit
// on its own port in a compose stack). The bearer is the Supabase access
// token (AuthService). Status handling follows API.md → Errors:
//   401 → refresh the session once, retry once; a second 401 signs out.
//   403 + code → a gate (invite, consent), reported to `APIStatus`; never "log in again".
//   503 → never sign out; wait `Retry-After`, retry (sync is idempotent).
//   429 → wait `Retry-After`, retry once.
//   413 → thrown; SyncService halves the page size.
// Every failure keeps the platform's request ID (`X-Request-ID` / `request_id`).
// Every request carries `X-RYFT-Device-ID`; `X-RYFT-Gate` on any response (a gate
// in warn mode) is reported like a refusal's code.
import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case signedOut
    case http(Int, String, requestID: String? = nil, code: APIErrorCode? = nil)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return SupabaseConfig.problem ?? String(localized: "This build has no RYFT server configured.")
        case .signedOut: return String(localized: "You're signed out. Log in to continue.")
        case .http(401, _, _, _): return String(localized: "Your session has ended. Log in again to continue.")
        case .http(403, _, _, .inviteRequired?):
            return String(localized: "RYFT is invite-only during the beta. Enter your invite code to continue.")
        case .http(403, _, _, .consentRequired?):
            return String(localized: "RYFT needs your consent before it can sync your health data.")
        // API.md: without a code, a 403 means changing something built in (exercise, plan, behavior).
        case .http(403, _, _, nil): return String(localized: "This is built into RYFT and can't be changed.")
        case .http(429, _, _, _): return String(localized: "Too many requests. Try again in a minute.")
        case .http(500, _, _, _): return String(localized: "Something went wrong on RYFT's side. Try again later.")
        case .http(503, _, _, _): return String(localized: "RYFT is catching up. Try again in a moment.")
        case .http(let code, let message, _, _):
            return message.isEmpty ? String(localized: "The server returned \(code).") : message
        case .transport(let e): return e.localizedDescription
        }
    }

    var status: Int? {
        if case .http(let code, _, _, _) = self { return code }
        return nil
    }

    var requestID: String? {
        if case .http(_, _, let id, _) = self { return id }
        return nil
    }

    /// The error body's `code`, if the platform sent one this build knows.
    var code: APIErrorCode? {
        if case .http(_, _, _, let code) = self { return code }
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
        if case .http(let code, _, _, _) = self { return code == 404 || code == 405 || code == 501 }
        return false
    }
}

extension Error {
    var isEndpointMissing: Bool { (self as? APIError)?.isNotFound ?? false }

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

    /// `POST /v1/sync` with a body `SyncEngine` encoded off the main actor.
    func sync(encoded body: Data) async throws -> SyncResponse {
        let data = try await exchange("POST", path: "/v1/sync", encodedBody: body, base: settings.ingestURL).data
        return try Self.jsonDecoder.decode(SyncResponse.self, from: data)
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
        let data = try await data(method, path: path, body: body, base: base)
        return try Self.jsonDecoder.decode(R.self, from: data)
    }

    func data<B: Encodable>(_ method: String, path: String, body: B?, base: URL? = nil) async throws -> Data {
        try await exchange(method, path: path, body: body, base: base).data
    }

    /// Like `data`, but statuses in `accepting` are returned instead of thrown —
    /// e.g. `409` on `PUT /v1/sessions/{id}`, whose body is the server's copy.
    func exchange<B: Encodable>(_ method: String, path: String, body: B?, base: URL? = nil,
                                accepting: Set<Int> = [],
                                unavailableRetries: Int = APIClient.maxUnavailableRetries) async throws -> (status: Int, data: Data) {
        try await exchange(method, path: path, encodedBody: body.map { try Self.jsonEncoder.encode($0) }, base: base,
                           accepting: accepting, unavailableRetries: unavailableRetries)
    }

    /// The request with an already encoded JSON body (or none).
    func exchange(_ method: String, path: String, encodedBody: Data?, base: URL? = nil,
                  accepting: Set<Int> = [],
                  unavailableRetries: Int = APIClient.maxUnavailableRetries) async throws -> (status: Int, data: Data) {
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
            req.httpBody = encodedBody
        }
        let tokens = await tokenProvider()
        var bearer = try await tokens.accessToken()
        var refreshed = false, rateLimited = false, unavailable = 0
        while true {
            let (data, response) = try await perform(req, bearer: bearer)
            let code = response?.statusCode ?? 0
            if (200..<300).contains(code) || accepting.contains(code) {
                if unavailable > 0 { await status.finishedWaiting() }
                // Served, but a gate in warn mode would have refused it: prompt for what's missing.
                if let warned = response.map(Self.gates), !warned.isEmpty {
                    await status.observe(warned, enforced: false)
                }
                return (code, data)
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
            case 429 where !rateLimited:
                rateLimited = true
                let wait = min(retryAfter ?? 1, Self.maxRateLimitWait)
                APIStatus.log.notice("429 on \(method, privacy: .public) \(path, privacy: .public); retrying in \(wait) s")
                try await sleep(wait)
                continue
            case 503 where unavailable < unavailableRetries:
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
            let error = APIError.http(code, message, requestID: requestID, code: body?.code)
            APIStatus.log.error("\(code) \(body?.code?.rawValue ?? "", privacy: .public) on \(method, privacy: .public) \(path, privacy: .public), request \(requestID ?? "-", privacy: .public)")
            if let gate = error.gate { await status.observe([gate], enforced: true) }
            await status.record(.init(date: .now, method: method, path: path, status: code,
                                      code: body?.code?.rawValue, requestID: requestID))
            throw error
        }
    }

    /// `Retry-After` in whole seconds (the platform never sends an HTTP date).
    static func retryAfter(_ response: HTTPURLResponse) -> Int? {
        response.value(forHTTPHeaderField: "Retry-After")
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .map { max(0, $0) }
    }

    private func perform(_ request: URLRequest, bearer: String) async throws -> (Data, HTTPURLResponse?) {
        var req = request
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await (Self.runsInBackground ? backgroundSession : session).data(for: req)
            return (data, resp as? HTTPURLResponse)
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
