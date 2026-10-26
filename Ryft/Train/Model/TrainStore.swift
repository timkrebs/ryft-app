import Foundation
import SwiftData
import OSLog

/// The app's SwiftData container: Train's sessions being logged, its offline
/// library and upload outbox, (`ReadModels.swift`) every platform read model
/// the Repository caches, and (`LocalActivity.swift`) the activities and manual
/// sleep not yet confirmed. On disk in the App Group container (`init`), in memory for
/// tests, previews and demo data. Everything runs on the main context; documents are small.
@MainActor
final class TrainStore {
    static let shared = TrainStore()

    static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "train")
    static let schema = Schema([LocalSession.self, LocalSessionExercise.self, LocalSet.self,
                                CachedExercise.self, CachedPlan.self, PendingTrainOp.self,
                                ImportMapping.self] + readModels + activityModels)

    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    /// On disk. False in memory: asked for (tests, previews, demo data), or the file couldn't be opened.
    let isDurable: Bool

    init(inMemory: Bool = false) {
        // In memory, each instance gets its own name, so tests and previews never share a store.
        //
        // On disk the store lives in the App Group container: the app has the `group.dev.timkrebs.ryft` entitlement,
        // so `.automatic` resolves to `<group>/Library/Application Support/Train.store`. Builds from before the
        // entitlement wrote the same name into the app container, which `OrphanedStoreCleanup` deletes at launch.
        // A move to `groupContainer: .none` resolves to exactly that old path: it must delete (or deliberately migrate)
        // whatever is there before the container opens, or it reopens an earlier account's read models and pending
        // uploads, which sign-out never wiped.
        //
        // Never CloudKit: `.automatic` would start mirroring the health read models to iCloud the day the app gets an
        // iCloud capability.
        let config = ModelConfiguration(inMemory ? "Train-\(UUID().uuidString)" : "Train", schema: Self.schema,
                                        isStoredInMemoryOnly: inMemory, groupContainer: .automatic, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: Self.schema, configurations: config)
            isDurable = !inMemory
        } catch {
            // A store that can't be opened must not keep the app from launching.
            // Domain and code only: a store error's description can quote values.
            let e = error as NSError
            Self.log.error("Train store unavailable, using memory: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            let memory = ModelConfiguration("TrainFallback", schema: Self.schema, isStoredInMemoryOnly: true,
                                            cloudKitDatabase: .none)
            isDurable = false
            do {
                container = try ModelContainer(for: Self.schema, configurations: memory)
            } catch {
                fatalError("SwiftData can't create an in-memory store: \(error)")
            }
        }
        context.autosaveEnabled = true
    }

    /// The open store's file; `nil` in memory (tests, previews, and the fallback when the file couldn't open).
    var storeURL: URL? {
        container.configurations.first { !$0.isStoredInMemoryOnly }?.url
    }

    func save() {
        do {
            try context.save()
        } catch {
            Self.log.error("Train save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: sessions

    func session(id: UUID) -> LocalSession? {
        var d = FetchDescriptor<LocalSession>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// The workout being logged, if any (the newest one if several survived).
    func activeSession() -> LocalSession? {
        let raw = SessionStatus.inProgress.rawValue
        var d = FetchDescriptor<LocalSession>(predicate: #Predicate { $0.statusRaw == raw },
                                              sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// Finished sessions, newest first.
    func completedSessions(from: Date = .distantPast, to: Date = .distantFuture) -> [LocalSession] {
        let raw = SessionStatus.completed.rawValue
        let d = FetchDescriptor<LocalSession>(
            predicate: #Predicate { $0.statusRaw == raw && $0.startedAt >= from && $0.startedAt <= to },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    func insert(_ s: LocalSession) {
        context.insert(s)
        save()
    }

    func delete(_ s: LocalSession) {
        context.delete(s)
        save()
    }

    // MARK: library

    func exercises() -> [Exercise] {
        let d = FetchDescriptor<CachedExercise>(sortBy: [SortDescriptor(\.name)])
        return ((try? context.fetch(d)) ?? []).compactMap(\.exercise).filter { !$0.archived }
    }

    func exercise(id: UUID) -> Exercise? {
        var d = FetchDescriptor<CachedExercise>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.exercise
    }

    func cache(exercises: [Exercise]) {
        let existing = Dictionary(((try? context.fetch(FetchDescriptor<CachedExercise>())) ?? []).map { ($0.id, $0) },
                                  uniquingKeysWith: { a, _ in a })
        for e in exercises {
            if let row = existing[e.id] {
                row.name = e.name
                row.kindRaw = e.kind.rawValue
                row.isCustom = e.isCustom
                row.payload = (try? APIClient.jsonEncoder.encode(e)) ?? row.payload
                row.updatedAt = .now
            } else {
                context.insert(CachedExercise(e))
            }
        }
        save()
    }

    func plans() -> [Plan] {
        let d = FetchDescriptor<CachedPlan>(sortBy: [SortDescriptor(\.name)])
        return ((try? context.fetch(d)) ?? []).compactMap(\.plan)
    }

    func plan(id: UUID) -> Plan? {
        var d = FetchDescriptor<CachedPlan>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.plan
    }

    func cache(plans: [Plan]) {
        let existing = Dictionary(((try? context.fetch(FetchDescriptor<CachedPlan>())) ?? []).map { ($0.id, $0) },
                                  uniquingKeysWith: { a, _ in a })
        for p in plans {
            if let row = existing[p.id] { row.update(p) } else { context.insert(CachedPlan(p)) }
        }
        save()
    }

    func removePlan(id: UUID) {
        try? context.delete(model: CachedPlan.self, where: #Predicate { $0.id == id })
        save()
    }

    // MARK: outbox

    func pendingOps() -> [PendingTrainOp] {
        (try? context.fetch(FetchDescriptor<PendingTrainOp>(sortBy: [SortDescriptor(\.seq)]))) ?? []
    }

    func enqueue(_ kind: PendingTrainOp.Kind, sessionID: UUID, bodyweightKg: Double? = nil) {
        let next = (pendingOps().last?.seq ?? 0) + 1
        context.insert(PendingTrainOp(seq: next, kind: kind, sessionId: sessionID, bodyweightKg: bodyweightKg))
        save()
    }

    func dequeue(_ op: PendingTrainOp) {
        context.delete(op)
        save()
    }

    func dropOps(for sessionID: UUID) {
        try? context.delete(model: PendingTrainOp.self, where: #Predicate { $0.sessionId == sessionID })
        save()
    }

    // MARK: account

    /// Log out / account switch: everything Train goes.
    /// Bumped by `wipe()`: work started before it (an upload's answer) must not write into rows the
    /// wipe deleted (`TrainSyncService.Generation`).
    private(set) var epoch = 0

    func wipe() {
        wipe(parkingActivitiesOf: nil)
    }

    /// The same, keeping what a session expiry parks (design.md §8.4): of the activity tables, exactly `account`'s
    /// unconfirmed or recording `LocalActivity` rows and their chunks, and its unconfirmed `LocalManualSleep`, marked
    /// `parkedAt` (`now` unless already parked, so the 30-day limit never restarts). Every other row of those tables
    /// goes, any account's. `nil`: they all go (sign-out, deletion, another account). A5 parks the account's
    /// `LocalPrivacyZone` rows too; A3b deletes vault keys first.
    func wipe(parkingActivitiesOf account: String?, at now: Date = Date()) {
        epoch += 1
        // Batch deletes skip cascade rules, so children go explicitly.
        try? context.delete(model: LocalSet.self)
        try? context.delete(model: LocalSessionExercise.self)
        try? context.delete(model: LocalSession.self)
        try? context.delete(model: CachedExercise.self)
        try? context.delete(model: CachedPlan.self)
        try? context.delete(model: PendingTrainOp.self)
        // The import's remembered matches are the account's too (training import design §4, §10).
        try? context.delete(model: ImportMapping.self)
        try? context.delete(model: CachedDay.self)
        try? context.delete(model: CachedTrend.self)
        try? context.delete(model: CachedInsight.self)
        try? context.delete(model: CachedUser.self)
        try? context.delete(model: CachedSleepRange.self)
        try? context.delete(model: CachedWorkout.self)
        try? context.delete(model: CachedDocument.self)
        wipeActivities(parking: account, at: now)
        save()
    }

    private func wipeActivities(parking account: String?, at now: Date) {
        // Chunks have no relationship to their row (batch deletes skip cascades), so they go explicitly, orphans
        // included.
        guard let account else {
            try? context.delete(model: ActivityTrackChunk.self)
            try? context.delete(model: LocalActivity.self)
            try? context.delete(model: LocalManualSleep.self)
            return
        }
        var kept: [UUID] = []
        for row in (try? context.fetch(FetchDescriptor<LocalActivity>())) ?? [] {
            if row.account == account, row.isUnconfirmedOrRecording {
                row.parkedAt = row.parkedAt ?? now
                kept.append(row.id)
            } else {
                context.delete(row)
            }
        }
        try? context.delete(model: ActivityTrackChunk.self,
                            where: #Predicate { $0.account != account || !kept.contains($0.activityID) })
        for night in (try? context.fetch(FetchDescriptor<LocalManualSleep>())) ?? [] {
            if night.account == account, night.isUnconfirmed {
                night.parkedAt = night.parkedAt ?? now
            } else {
                context.delete(night)
            }
        }
    }
}
