import os
import OSLog
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

    static let filePrefix = "RYFT-export-"
    private static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "export")
    /// The export files this process wrote, by path: the launch sweep leaves them. (Not by file dates: those are a
    /// required-reason API, and the privacy manifest declares none.)
    private static let writtenHere = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Writes the archive to a temporary file named `RYFT-export-YYYY-MM-DD.json` in `folder`. It goes when the
    /// share sheet is done, at an account change or sign-out, and at the next launch (`removeFiles`).
    static func write(_ archive: Archive, to folder: URL = FileManager.default.temporaryDirectory) throws -> URL {
        // Its own encoder: the shared one is used by requests concurrently.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        let url = folder.appendingPathComponent("\(filePrefix)\(DayFormat.string(from: archive.exportedAt)).json")
        // Recorded before the file exists: a launch sweep running meanwhile never takes it.
        writtenHere.withLock { _ = $0.insert(url.standardizedFileURL.path) }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Removes the export files in `folder` but those in `kept` (paths): all of an account's data shouldn't outlive
    /// the share sheet, the account on this iPhone, or a crash before either. Returns how many went.
    @discardableResult
    static func removeFiles(in folder: URL = FileManager.default.temporaryDirectory, keeping kept: Set<String> = []) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var removed = 0
        for name in names where name.hasPrefix(filePrefix) && name.hasSuffix(".json") {
            let file = folder.appendingPathComponent(name)
            guard !kept.contains(file.standardizedFileURL.path) else { continue }
            do {
                try FileManager.default.removeItem(at: file)
                removed += 1
            } catch {
                let e = error as NSError
                log.error("Removing an export file failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            }
        }
        if removed > 0 { log.info("Removed \(removed, privacy: .public) export files") }
        return removed
    }

    /// At launch, off the main actor: what earlier runs left, never a file this run wrote.
    @concurrent
    static func removeLeftoverFiles(in folder: URL = FileManager.default.temporaryDirectory) async {
        removeFiles(in: folder, keeping: writtenHere.withLock { $0 })
    }
}

/// The system share sheet for a file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// After an activity finished with the items, or the sheet was closed without one (`isDone`).
    var completion: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { [completion] activity, completed, _, _ in
            if Self.isDone(activity: activity, completed: completed) { completion?() }
        }
        return controller
    }

    /// A cancelled activity (Mail → Cancel) returns to the open sheet, where another one (Save to Files) still needs
    /// the items; the sheet's own dismissal covers the rest.
    static func isDone(activity: UIActivity.ActivityType?, completed: Bool) -> Bool {
        completed || activity == nil
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// An exported file waiting for the share sheet.
struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
