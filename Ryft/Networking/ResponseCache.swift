// Last successful API responses as Codable files in Caches/, so Today renders
// instantly at launch and the app stays readable offline.
import Foundation

struct ResponseCache {
    static let shared = ResponseCache()

    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = base.appendingPathComponent("ryft-responses", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func save<T: Encodable>(_ value: T, as key: String) {
        guard let data = try? APIClient.jsonEncoder.encode(value) else { return }
        try? data.write(to: url(key), options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? APIClient.jsonDecoder.decode(T.self, from: data)
    }

    func remove(_ key: String) {
        try? FileManager.default.removeItem(at: url(key))
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(_ key: String) -> URL {
        directory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".json")
    }
}

/// What Today needs to render at launch.
struct TodaySnapshot: Codable {
    var today: DayDetail?
    var history: [DailyScore]
    var user: User?
    var insights: [Insight]
    var readinessWeek: TrendSeries?
    var fetchedAt: Date
}
