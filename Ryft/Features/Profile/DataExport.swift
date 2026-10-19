import SwiftUI
import UIKit

/// Profile → Data → Export my data: everything the platform holds for the
/// account as one JSON file (`/v1/me`, `/v1/days`, `/v1/workouts`,
/// `/v1/sessions`), shared through the system share sheet. Not an Apple rule —
/// GDPR art. 20 (data portability).
enum DataExport {
    struct Archive: Encodable {
        let exportedAt: Date
        let app: String
        let user: User?
        let days: [DailyScore]
        let workouts: [Workout]
        let sessions: [SessionSummary]
    }

    /// Ranges are fetched in 180-day chunks back from today until a chunk is
    /// empty twice in a row (or five years).
    static let chunkDays = 180
    static let maxYears = 5

    @MainActor
    static func archive(source: RyftDataSource, train: TrainDataSource, now: Date = .now) async throws -> Archive {
        let user = try await source.me()
        var days: [DailyScore] = [], workouts: [Workout] = [], sessions: [SessionSummary] = []
        var end = now, emptyChunks = 0
        let oldest = DayFormat.shift(now, days: -365 * maxYears)
        while end > oldest && emptyChunks < 2 {
            let start = DayFormat.shift(end, days: -(chunkDays - 1))
            let d = try await source.days(from: start, to: end)
            let w = try await source.workouts(from: start, to: end)
            let s = try await train.sessions(from: start, to: end)
            emptyChunks = d.isEmpty && w.isEmpty && s.isEmpty ? emptyChunks + 1 : 0
            days += d
            workouts += w
            sessions += s
            end = DayFormat.shift(start, days: -1)
        }
        return Archive(exportedAt: now, app: "RYFT \(ProfileView.version)", user: user,
                       days: days.sorted { $0.day < $1.day },
                       workouts: Self.unique(workouts.sorted { $0.start < $1.start }),
                       sessions: sessions.sorted { $0.startedAt < $1.startedAt })
    }

    private static func unique(_ ws: [Workout]) -> [Workout] {
        var seen = Set<UUID>()
        return ws.filter { seen.insert($0.id).inserted }
    }

    /// Writes the archive to a temporary file named `RYFT-export-YYYY-MM-DD.json`.
    static func write(_ archive: Archive) throws -> URL {
        // Its own encoder: the shared one is used by requests concurrently.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RYFT-export-\(DayFormat.string(from: archive.exportedAt)).json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

/// The system share sheet for a file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// An exported file waiting for the share sheet.
struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
