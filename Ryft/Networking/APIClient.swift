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
        case .notConfigured: return "Set the server URL and API key in Settings."
        case .http(let code, let body): return "Server returned \(code): \(body)"
        case .transport(let e): return e.localizedDescription
        }
    }
}

final class APIClient {
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
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = frac.date(from: s) ?? plain.date(from: s) { return date }
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

    func recompute(from: Date, to: Date) async throws {
        struct Ack: Decodable { let status: String }
        let _: Ack = try await send("POST", path: "/v1/recompute",
                                    body: RecomputeRequest(from: Self.dayString(from), to: Self.dayString(to)))
    }

    // MARK: plumbing

    private func send<B: Encodable, R: Decodable>(_ method: String, path: String, body: B?, base: URL? = nil) async throws -> R {
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
            throw APIError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.jsonDecoder.decode(R.self, from: data)
    }

    static func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: d)
    }
}
