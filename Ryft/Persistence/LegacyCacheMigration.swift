import Foundation

/// Before SwiftData held the read models, the last responses lived as JSON files
/// in Caches/ryft-responses (the `ResponseCache`). On the first launch with the
/// Repository they are imported once, then the directory is deleted.
@MainActor
enum LegacyCacheMigration {
    static let doneKey = "migrated.responseCacheToSwiftData"

    /// Today's payload as the old cache stored it.
    struct TodaySnapshot: Codable {
        var today: DayDetail?
        var history: [DailyScore]
        var user: User?
        var insights: [Insight]
        var readinessWeek: TrendSeries?
        var fetchedAt: Date
    }

    nonisolated static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ryft-responses", isDirectory: true)
    }

    /// Imports what's there (once per install) and removes the old files.
    static func runOnce(into repository: Repository, train store: TrainStore, defaults: UserDefaults,
                        directory: URL = defaultDirectory()) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            let url = directory.appendingPathComponent(name + ".json")
            return (try? Data(contentsOf: url)).flatMap { WireCoding.decode(T.self, $0) }
        }

        repository.writingToAccountStore {
            if let snap = load(TodaySnapshot.self, "today") {
                repository.store(scores: snap.history)
                if let d = snap.today { repository.store(detail: d) }
                if let u = snap.user { repository.store(user: u) }
                repository.store(insights: snap.insights)
                if let w = snap.readinessWeek { repository.store(trend: w, metric: .readiness, range: .week) }
            }
        }
        if let c = load(PlansOverview.self, "train.plans") { store.saveDocument(c, key: "train.plans") }
        if let t = load(PlanToday.self, "train.today") { store.saveDocument(t, key: "train.today") }
        if let s = load([SessionSummary].self, "train.sessions") { store.saveDocument(s, key: "train.sessions") }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix("train.history.") && file.hasSuffix(".json") {
            let name = String(file.dropLast(5))
            if let h = load(ExerciseHistory.self, name) { store.saveDocument(h, key: name) }
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
