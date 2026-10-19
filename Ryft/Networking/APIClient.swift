// HTTP client for the RYFT platform (one host in production; ingest may sit
// on its own port in a compose stack). The bearer is the Supabase access
// token (AuthService). Status handling follows API.md → Errors:
//   401 → refresh the session once, retry once; a second 401 signs out.
//   503 → never sign out; wait `Retry-After`, retry (sync is idempotent).
//   429 → wait `Retry-After`, retry once.
//   413 → thrown; SyncService halves the page size.
// Every failure keeps the platform's request ID (`X-Request-ID` / `request_id`).
import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case signedOut
    case http(Int, String, requestID: String? = nil)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return SupabaseConfig.problem ?? String(localized: "This build has no RYFT server configured.")
        case .signedOut: return String(localized: "You're signed out. Log in to continue.")
        case .http(401, _, _), .http(403, _, _): return String(localized: "RYFT didn't accept your sign-in. Log in again.")
        case .http(429, _, _): return String(localized: "Too many requests. Try again in a minute.")
        case .http(500, _, _): return String(localized: "Something went wrong on RYFT's side. Try again later.")
        case .http(503, _, _): return String(localized: "RYFT is catching up. Try again in a moment.")
        case .http(let code, let message, _):
            return message.isEmpty ? String(localized: "The server returned \(code).") : message
        case .transport(let e): return e.localizedDescription
        }
    }

    var status: Int? {
        if case .http(let code, _, _) = self { return code }
        return nil
    }

    var requestID: String? {
        if case .http(_, _, let id) = self { return id }
        return nil
    }

    /// The platform doesn't serve this endpoint (yet) — callers degrade gracefully.
    var isNotFound: Bool {
        if case .http(let code, _, _) = self { return code == 404 || code == 405 || code == 501 }
        return false
    }
}

extension Error {
    var isEndpointMissing: Bool { (self as? APIError)?.isNotFound ?? false }

    /// "HTTP 503 · Request ID 01a1…" for an inline message's Details, or `nil`.
    var diagnosticDetails: String? {
        guard let e = self as? APIError, let status = e.status else { return nil }
        guard let id = e.requestID else { return String(localized: "HTTP \(status)") }
        return String(localized: "HTTP \(status) · Request ID \(id)")
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
    private let tokens: AccessTokenProvider?
    private let sleep: @Sendable (Int) async throws -> Void
    /// Replaces the configured API URL (tests).
    private let baseURL: URL?

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

    /// `tokens` defaults to `AuthService.shared`, resolved per request on the
    /// main actor. `sleep` waits out `Retry-After` (tests skip the wait).
    init(session: URLSession = URLSession(configuration: APIClient.defaultConfiguration),
         tokens: AccessTokenProvider? = nil,
         sleep: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         baseURL: URL? = nil) {
        self.session = session
        self.baseURL = baseURL
        self.tokens = tokens
        self.sleep = sleep
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

    func sync(_ req: SyncRequest) async throws -> SyncResponse {
        try await send("POST", path: "/v1/sync", body: req, base: settings.ingestURL)
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
                                accepting: Set<Int> = []) async throws -> (status: Int, data: Data) {
        guard let root = base ?? baseURL ?? settings.apiURL, root.host != nil,
              let url = URL(string: path, relativeTo: root) else {
            throw APIError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.jsonEncoder.encode(body)
        }
        let tokens = await tokenProvider()
        var bearer = try await tokens.accessToken()
        var refreshed = false, rateLimited = false, unavailable = 0
        while true {
            let (data, response) = try await perform(req, bearer: bearer)
            let code = response?.statusCode ?? 0
            if (200..<300).contains(code) || accepting.contains(code) {
                if unavailable > 0 { await APIStatus.shared.finishedWaiting() }
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
            case 503 where unavailable < Self.maxUnavailableRetries:
                // Not a sign-in problem (API.md): keep the session, wait, retry.
                unavailable += 1
                let wait = min(retryAfter ?? 5, Self.maxUnavailableWait)
                await APIStatus.shared.waiting(seconds: wait)
                try await sleep(wait)
                continue
            default:
                break
            }
            if unavailable > 0 { await APIStatus.shared.finishedWaiting() }
            let body = try? Self.jsonDecoder.decode(APIErrorBody.self, from: data)
            let message = body?.error
                ?? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let requestID = response?.value(forHTTPHeaderField: "X-Request-ID") ?? body?.requestId
            APIStatus.log.error("\(code) on \(method, privacy: .public) \(path, privacy: .public), request \(requestID ?? "-", privacy: .public)")
            await APIStatus.shared.record(.init(date: .now, method: method, path: path, status: code, requestID: requestID))
            throw APIError.http(code, message, requestID: requestID)
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
            let (data, resp) = try await session.data(for: req)
            return (data, resp as? HTTPURLResponse)
        } catch {
            throw APIError.transport(error)
        }
    }

    private func tokenProvider() async -> AccessTokenProvider {
        if let tokens { return tokens }
        return await AuthService.shared
    }

    static func dayString(_ d: Date) -> String {
        DayFormat.string(from: d)
    }
}
