import SwiftUI
import UIKit

/// Profile → Data → Export my data: everything the platform holds for the
/// account as one JSON file (`/v1/me`, `/v1/days`, `/v1/workouts`,
/// `/v1/sessions`, `/v1/activities`), plus what the app keeps for it: the
/// training import's remembered matches, and the activities and nights on this
/// iPhone the platform hasn't confirmed. Shared through the system share sheet.
/// Not an Apple rule — GDPR art. 15 and 20 (access, data portability).
enum DataExport {
    struct Archive: Encodable {
        let exportedAt: Date
        let app: String
        let user: User?
        let days: [DailyScore]
        let workouts: [Workout]
        let sessions: [SessionSummary]
        /// The training import's remembered exercise matches (`ImportMappingStore.records()`).
        let rememberedMatches: [ImportMappingRecord]
        /// The platform's activities (`GET /v1/activities`), with their splits. Without routes and heart-rate
        /// samples: list reads carry none (API request R16); routes join with the route opt-in (A5, R14).
        var activities: [SportActivity] = []
        /// Activities on this iPhone the platform hasn't confirmed (design.md §8.7).
        var unconfirmedActivities: [UnconfirmedActivity] = []
        /// Nights the user added on this iPhone ("Add sleep"), confirmed or not. Which of the platform's nights
        /// were added by hand isn't in its days yet (API request R11).
        var manualSleep: [ManualNight] = []
    }

    /// One activity the platform hasn't confirmed, as this iPhone would send it.
    struct UnconfirmedActivity: Encodable {
        /// `pending` (saved, not uploaded yet), `refused` (the platform didn't accept it), `deleting` (deleted here,
        /// the platform not told yet), `recording` (not saved yet).
        let state: String
        let activity: SportActivity
    }

    /// A night the user added.
    struct ManualNight: Encodable {
        /// The wake day.
        let day: String
        let bed: Date
        let wake: Date
        /// `pending`, `confirmed`, `deleting`.
        let state: String
    }

    /// Ranges are fetched in 180-day chunks back from today until a chunk is
    /// empty twice in a row (or five years).
    static let chunkDays = 180
    static let maxYears = 5

    /// `activities`: the platform's activities (asked only once it publishes them,
    /// `ActivitiesAPI.publishesActivities`); `onPhone`: the account's activities and nights on this iPhone.
    @MainActor
    static func archive(source: RyftDataSource, train: TrainDataSource, rememberedMatches: [ImportMappingRecord] = [],
                        activities: ActivitiesAPI? = nil, onPhone: ActivityStore? = nil,
                        now: Date = .now) async throws -> Archive {
        let user = try await source.me()
        let platform = activities?.publishesActivities == true ? activities : nil
        var days: [DailyScore] = [], workouts: [Workout] = [], sessions: [SessionSummary] = []
        var sportActivities: [SportActivity] = []
        var end = now, emptyChunks = 0
        let oldest = DayFormat.shift(now, days: -365 * maxYears)
        let calendar = Calendar.current
        while end > oldest && emptyChunks < 2 {
            let start = DayFormat.shift(end, days: -(chunkDays - 1))
            let d = try await source.days(from: start, to: end)
            let w = try await source.workouts(from: start, to: end)
            let s = try await train.sessions(from: start, to: end)
            // `[from, to)` by start: the chunk's first midnight to the midnight after its last day.
            let from = calendar.startOfDay(for: start)
            let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
            let a = try await platform?.activities(from: from, to: to) ?? []
            emptyChunks = d.isEmpty && w.isEmpty && s.isEmpty && a.isEmpty ? emptyChunks + 1 : 0
            days += d
            workouts += w
            sessions += s
            sportActivities += a
            end = DayFormat.shift(start, days: -1)
        }
        var archive = Archive(exportedAt: now, app: "RYFT \(ProfileView.version)", user: user,
                              days: days.sorted { $0.day < $1.day },
                              workouts: Self.unique(workouts.sorted { $0.start < $1.start }),
                              sessions: sessions.sorted { $0.startedAt < $1.startedAt },
                              rememberedMatches: rememberedMatches)
        var seen = Set<UUID>()
        archive.activities = sportActivities.sorted { $0.start < $1.start }
            .filter { seen.insert($0.id).inserted }
            .map(\.withoutRouteOrHeartRate)
        if let onPhone {
            archive.unconfirmedActivities = onPhone.allSnapshots().compactMap(UnconfirmedActivity.init)
            archive.manualSleep = onPhone.manualSleeps().map(ManualNight.init)
        }
        return archive
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

extension DataExport.UnconfirmedActivity {
    /// Nil for a row the platform confirmed: its copy is in `activities`.
    init?(_ row: LocalActivitySnapshot) {
        if row.isTombstone {
            state = "deleting"
        } else if !row.isSaved {
            state = "recording"
        } else if row.needsUpload {
            state = row.lastAttempt.map { $0.kind == .other || $0.kind == .appTooOld } == true ? "refused" : "pending"
        } else {
            return nil
        }
        activity = row.activity
    }
}

extension DataExport.ManualNight {
    init(_ night: ManualSleepSnapshot) {
        day = night.day
        bed = night.bed
        wake = night.wake
        state = night.isTombstone ? "deleting" : night.needsUpload ? "pending" : "confirmed"
    }
}
