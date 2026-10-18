// HTTP client for the Go backend. Two base URLs because ingest and api are
// separate services; behind the Ingress they share one host, so by default
// `ingestURL` falls back to `apiURL`. The bearer is the Supabase access token
// (AuthService); a 401 forces one token refresh and one retry.
import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case signedOut
    case http(Int, String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return SupabaseConfig.problem ?? String(localized: "This build has no RYFT server configured.")
        case .signedOut: return String(localized: "You're signed out. Sign in to continue.")
        case .http(401, _), .http(403, _): return String(localized: "The server didn't accept your sign-in.")
        case .http(let code, let message):
            return message.isEmpty ? String(localized: "The server returned \(code).") : message
        case .transport(let e): return e.localizedDescription
        }
    }

    /// The platform doesn't serve this endpoint (yet) — callers degrade gracefully.
    var isNotFound: Bool {
        if case .http(let code, _) = self { return code == 404 || code == 405 || code == 501 }
        return false
    }
}

extension Error {
    var isEndpointMissing: Bool { (self as? APIError)?.isNotFound ?? false }
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

    static let defaultConfiguration: URLSessionConfiguration = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 300 // first backfill can be tens of MB
        c.waitsForConnectivity = true
        return c
    }()

    /// `tokens` defaults to `AuthService.shared`, resolved per request on the main actor.
    init(session: URLSession = URLSession(configuration: APIClient.defaultConfiguration),
         tokens: AccessTokenProvider? = nil) {
        self.session = session
        self.tokens = tokens
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

    private func send<B: Encodable, R: Decodable>(_ method: String, path: String, body: B?, base: URL? = nil) async throws -> R {
        let data = try await data(method, path: path, body: body, base: base)
        return try Self.jsonDecoder.decode(R.self, from: data)
    }

    func data<B: Encodable>(_ method: String, path: String, body: B?, base: URL? = nil) async throws -> Data {
        guard let root = base ?? settings.apiURL, root.host != nil,
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
        var (data, code) = try await perform(req, bearer: try await tokens.accessToken())
        if code == 401 {
            // The token may have been revoked or rotated server-side: refresh once and retry once.
            (data, code) = try await perform(req, bearer: try await tokens.refreshedAccessToken())
            if code == 401 { await tokens.rejectedAfterRefresh() }
        }
        guard (200..<300).contains(code) else {
            let message = (try? Self.jsonDecoder.decode(APIErrorBody.self, from: data))?.error
                ?? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw APIError.http(code, message)
        }
        return data
    }

    private func perform(_ request: URLRequest, bearer: String) async throws -> (Data, Int) {
        var req = request
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await session.data(for: req)
            return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
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
