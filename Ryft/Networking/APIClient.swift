// HTTP client for the Go backend. Two base URLs because ingest and api are
// separate services; behind the Ingress they share one host, so by default
// `ingestURL` falls back to `apiURL`.
import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return String(localized: "Add your server URL and API key in Profile.")
        case .http(401, _), .http(403, _): return String(localized: "The server didn't accept the API key.")
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
}

final class APIClient: RyftDataSource {
    static let shared = APIClient()

    private let settings = Settings.shared
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 300 // first backfill can be tens of MB
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

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

    private func data<B: Encodable>(_ method: String, path: String, body: B?, base: URL? = nil) async throws -> Data {
        guard let root = base ?? settings.apiURL, let key = settings.apiKey, !key.isEmpty,
              let url = URL(string: path, relativeTo: root) else {
            throw APIError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.jsonEncoder.encode(body)
        }
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let message = (try? Self.jsonDecoder.decode(APIErrorBody.self, from: data))?.error
                ?? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw APIError.http(code, message)
        }
        return data
    }

    static func dayString(_ d: Date) -> String {
        DayFormat.string(from: d)
    }
}
