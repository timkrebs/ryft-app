import os
import OSLog
import SwiftUI
import UIKit

/// Profile → Data → Export my data: the account's profile, scores, workouts,
/// activities and saved meal diary as one JSON file, plus what the app keeps: the
/// training import's remembered matches and its job not uploaded yet, and the
/// activities and nights on this iPhone the platform hasn't confirmed. Shared
/// through the system share sheet.
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
        /// The training import's job, while some of it isn't on the platform yet (its done items are in `sessions`).
        var pendingImport: PendingImportExport?
        /// Scope and availability of the account's persisted meal snapshots.
        var nutritionDiary: NutritionDiary?
    }

    struct NutritionDiary: Encodable {
        enum Status: String, Encodable { case included, unavailable, partial }
        let status: Status
        let meals: [NutritionMeal]?
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
    private static let maxMealPages = 250
    private static let maxMealItems = 20_000

    private enum MealExportError: Error { case invalidPage }

    /// `activities`: the platform's activities (asked only once it publishes them,
    /// `ActivitiesAPI.publishesActivities`); `onPhone`: the activities and nights on this iPhone of the account it
    /// reads as when the export starts.
    @MainActor
    static func archive(source: RyftDataSource, train: TrainDataSource, rememberedMatches: [ImportMappingRecord] = [],
                        activities: ActivitiesAPI? = nil, onPhone: ActivityStore? = nil,
                        pendingImport: PendingImportExport? = nil, now: Date = .now,
                        meals: (@MainActor (UUID?) async throws -> NutritionMealExportPage)? = nil) async throws -> Archive {
        // The rows on this iPhone are the account's the export started for, whoever is signed in when it ends.
        let phoneAccount = onPhone?.account
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
        if let onPhone, let phoneAccount {
            archive.unconfirmedActivities = onPhone.allSnapshots(ofAccount: phoneAccount).compactMap(UnconfirmedActivity.init)
            archive.manualSleep = onPhone.manualSleeps(ofAccount: phoneAccount).map(ManualNight.init)
        }
        archive.pendingImport = pendingImport
        if let meals { archive.nutritionDiary = try await mealDiary(meals) }
        return archive
    }

    /// The server owns the cursor and the export advertises when its safety bounds limit coverage.
    @MainActor
    private static func mealDiary(
        _ fetch: @MainActor (UUID?) async throws -> NutritionMealExportPage
    ) async throws -> NutritionDiary {
        var cursor: UUID?
        var cursors = Set<UUID>()
        var meals: [NutritionMeal] = []
        var itemCount = 0
        for _ in 0..<maxMealPages {
            let page: NutritionMealExportPage
            do {
                page = try await fetch(cursor)
            } catch let error as APIError where error.status == 404 {
                return cursor == nil
                    ? NutritionDiary(status: .unavailable, meals: nil)
                    : NutritionDiary(status: .partial, meals: meals)
            }
            guard page.meals.count <= NutritionMealExportPage.pageSize else { throw MealExportError.invalidPage }
            let pageItems = page.meals.reduce(0) { $0 + $1.items.count }
            guard pageItems <= maxMealItems - itemCount else {
                return NutritionDiary(status: .partial, meals: meals)
            }
            itemCount += pageItems
            meals += page.meals
            guard let next = page.nextAfter else { return NutritionDiary(status: .included, meals: meals) }
            guard !page.meals.isEmpty, cursors.insert(next).inserted else { throw MealExportError.invalidPage }
            cursor = next
        }
        return NutritionDiary(status: .partial, meals: meals)
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
        // Health data on the pasteboard reaches every app that reads it (and Universal Clipboard): save or send the file.
        controller.excludedActivityTypes = [.copyToPasteboard]
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
    var nutritionDiaryStatus: DataExport.NutritionDiary.Status?
    var id: URL { url }
}

/// An incomplete meal diary is explained before the user shares the rest of the file.
struct DataExportShareSheet: View {
    let file: ExportedFile
    let completion: () -> Void
    @State private var share = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if !share, let status = file.nutritionDiaryStatus, status != .included {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if status == .unavailable {
                        Text("Meal diary unavailable").font(.ryft(.headline))
                        Text("The server could not include your saved meals. You can share the rest of the export or contact support for your meal diary.")
                    } else {
                        Text("Meal diary partially included").font(.ryft(.headline))
                        Text("The export includes only some saved meals. You can share this file or contact support for the complete meal diary.")
                    }
                    PillButton(Text("Share export")) { share = true }
                    PillButton(Text("Cancel"), style: .secondary) { dismiss() }
                }
                .padding(Theme.Metrics.screenPadding)
            }
        } else {
            ShareSheet(items: [file.url], completion: completion)
        }
    }
}

extension DataExport.UnconfirmedActivity {
    /// Nil for a row the platform confirmed: its copy is in `activities`.
    init?(_ row: LocalActivitySnapshot) {
        if row.isTombstone {
            state = "deleting"
        } else if !row.isSaved {
            state = "recording"
        } else if row.needsUpload {
            state = row.lastAttempt?.isRefusal == true ? "refused" : "pending"
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
