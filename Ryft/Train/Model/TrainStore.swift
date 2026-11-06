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
    /// Every route to the store passes the launch's store step first: an owed wipe that can't wait for the object wipe
    /// replaces the files before the container opens (`StoreReset`).
    static let shared = TrainStore(opening: liveConfiguration(), ledger: .live, orphans: .current(), now: Date())

    static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "train")
    static let schema = Schema([LocalSession.self, LocalSessionExercise.self, LocalSet.self,
                                CachedExercise.self, CachedPlan.self, PendingTrainOp.self,
                                ImportMapping.self, PendingImport.self] + readModels + activityModels)

    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    /// On disk. False in memory: asked for (tests, previews, demo data), or the file couldn't be opened.
    let isDurable: Bool
    /// Asked for a file and got memory (`init`): what's in that file is out of reach, so a wipe can't take it.
    private let lostItsFile: Bool

    convenience init(inMemory: Bool = false) {
        self.init(configuration: Self.liveConfiguration(inMemory: inMemory))
    }

    private static func liveConfiguration(inMemory: Bool = false) -> ModelConfiguration {
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
        ModelConfiguration(inMemory ? "Train-\(UUID().uuidString)" : "Train", schema: schema, isStoredInMemoryOnly: inMemory,
                           groupContainer: .automatic, cloudKitDatabase: .none)
    }

    /// Tests: a store on disk at `url` (its own folder), never CloudKit. What only a file shows (external storage,
    /// a wipe's leftovers) is tested on it, never on the app's own store.
    convenience init(url: URL) {
        self.init(configuration: ModelConfiguration(schema: Self.schema, url: url, cloudKitDatabase: .none))
    }

    /// Tests: the launch's way in, on a store of their own.
    convenience init(url: URL, ledger: WipeLedger, orphans: OrphanedStoreCleanup.Locations, now: Date) {
        self.init(opening: ModelConfiguration(schema: Self.schema, url: url, cloudKitDatabase: .none), ledger: ledger,
                  orphans: orphans, now: now)
    }

    private convenience init(opening config: ModelConfiguration, ledger: WipeLedger,
                             orphans: OrphanedStoreCleanup.Locations, now: Date) {
        StoreReset.run(entry: ledger.forStoreStep, store: config.url, orphans: orphans, now: now)
        self.init(configuration: config)
    }

    private init(configuration config: ModelConfiguration) {
        do {
            container = try ModelContainer(for: Self.schema, configurations: config)
            isDurable = !config.isStoredInMemoryOnly
            lostItsFile = false
        } catch {
            // A store that can't be opened must not keep the app from launching.
            // Domain and code only: a store error's description can quote values.
            let e = error as NSError
            Self.log.error("Train store unavailable, using memory: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            let memory = ModelConfiguration("TrainFallback", schema: Self.schema, isStoredInMemoryOnly: true,
                                            cloudKitDatabase: .none)
            isDurable = false
            lostItsFile = true
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

    /// False when the store refused: the changes stay pending in the context, and aren't in the file.
    @discardableResult
    func save() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            // Domain and code only: a store error's description can quote values.
            let e = error as NSError
            Self.log.error("Train save failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            return false
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

    /// `account`: whose op it is (`PendingTrainOp.account`).
    func enqueue(_ kind: PendingTrainOp.Kind, sessionID: UUID, bodyweightKg: Double? = nil, account: String? = nil) {
        let next = (pendingOps().last?.seq ?? 0) + 1
        context.insert(PendingTrainOp(seq: next, kind: kind, sessionId: sessionID, bodyweightKg: bodyweightKg,
                                      account: account))
        save()
    }

    func dequeue(_ op: PendingTrainOp) {
        context.delete(op)
        save()
    }

    /// Every op of one binding (`PendingTrainOp.account`).
    func dropOps(account: String) {
        let owner: String? = account
        try? context.delete(model: PendingTrainOp.self, where: #Predicate { $0.account == owner })
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

    @discardableResult
    func wipe() -> Bool {
        wipe(parkingActivitiesOf: nil, at: Date())
    }

    /// One owed wipe, the only way an account's wipe reaches the store: what it parks, dated from its first attempt.
    @discardableResult
    func wipe(_ wipe: AuthService.Wipe) -> Bool {
        self.wipe(parkingActivitiesOf: wipe.parking, at: wipe.since)
    }

    /// The same, keeping what a session expiry parks (design.md §8.4): of the activity tables, exactly `account`'s
    /// unconfirmed or recording `LocalActivity` rows and their chunks, and its unconfirmed `LocalManualSleep`, marked
    /// `parkedAt` (`now` unless already parked, so the 30-day limit never restarts). Every other row of those tables
    /// goes, any account's. `nil`: they all go (sign-out, deletion, another account). A5 parks the account's
    /// `LocalPrivacyZone` rows too; A3b deletes vault keys first.
    ///
    /// True when the store took every step: each delete and fetch here succeeded, the final save was accepted, and the
    /// store is on the file it was asked for. False: the file may still hold the account's data, and `AuthService` keeps
    /// the account's id so the next account wipes again. A step that fails doesn't stop the ones after it, with one
    /// exception: when parking can't read the activities, every chunk stays, because a kept chunk is the only copy of a
    /// track. Those rows carry no `parkedAt`, so the 30-day limit doesn't reach them until an account signs in.
    ///
    /// True doesn't prove the rows are gone: nothing counts them afterwards, and a row only inserted into a table that
    /// goes by batch delete survives it and is written by the final save. Parked rows stay, as they should. Nothing
    /// outside this store is covered. A store that was asked to run in memory reports true: it has no file to reach.
    @discardableResult
    func wipe(parkingActivitiesOf account: String?, at now: Date) -> Bool {
        epoch += 1
        // An array, so every step runs, in this order, whatever the ones before it did.
        let steps = [
            // One by one, the way `PendingImport` goes below. A batch delete of `LocalSet` or `LocalSessionExercise`
            // throws on saved rows (their inverse), and none sees a session that was only inserted, which the `save()`
            // below would then write. Children first, orphans included: the save is measurably faster than when the
            // sessions' cascade finds them.
            deleteEach(LocalSet.self),
            deleteEach(LocalSessionExercise.self),
            deleteEach(LocalSession.self) { session in
                // Read now: a live workout still holds this row until the account change, and reading either list on
                // a deleted row is a fatal error unless it was resolved before the delete.
                _ = (session.deletedSetIDs, session.deletedExerciseIDs)
            },
            batchDelete(CachedExercise.self),
            batchDelete(CachedPlan.self),
            batchDelete(PendingTrainOp.self),
            // The import's remembered matches are the account's too (training import design §4, §10).
            batchDelete(ImportMapping.self),
            // And its import job, never uploaded for another account (design §7). One by one: its payload is external
            // storage, and only deleting the object is sure to take that file (the whole imported history) with it. On
            // the iOS 27 simulator SwiftData's batch delete removed it too, but the app runs from iOS 17.
            deleteEach(PendingImport.self),
            batchDelete(CachedDay.self),
            batchDelete(CachedTrend.self),
            batchDelete(CachedInsight.self),
            batchDelete(CachedUser.self),
            batchDelete(CachedSleepRange.self),
            batchDelete(CachedWorkout.self),
            batchDelete(CachedDocument.self),
            wipeActivities(parking: account, at: now),
            // Last, and not a reason to skip it: with nothing pending it succeeds with nothing to do, so it can't
            // stand for the steps above.
            save(),
        ]
        return steps.allSatisfy { $0 } && !lostItsFile
    }

    private func wipeActivities(parking account: String?, at now: Date) -> Bool {
        // Chunks have no relationship to their row (batch deletes skip cascades), so they go explicitly, orphans
        // included.
        guard let account else {
            return [batchDelete(ActivityTrackChunk.self), batchDelete(LocalActivity.self),
                    batchDelete(LocalManualSleep.self)].allSatisfy { $0 }
        }
        var kept: [UUID] = []
        let rows = fetched(LocalActivity.self)
        for row in rows ?? [] {
            if row.account == account, row.isUnconfirmedOrRecording {
                row.parkedAt = row.parkedAt ?? now
                kept.append(row.id)
            } else {
                context.delete(row)
            }
        }
        // Without the rows nothing says which chunks are parked work, so a failed read takes none of them.
        let chunks = rows != nil && batchDelete(ActivityTrackChunk.self,
                                                where: #Predicate { $0.account != account || !kept.contains($0.activityID) })
        let nights = fetched(LocalManualSleep.self)
        for night in nights ?? [] {
            if night.account == account, night.isUnconfirmed {
                night.parkedAt = night.parkedAt ?? now
            } else {
                context.delete(night)
            }
        }
        return chunks && nights != nil
    }

    /// The wipe's steps report instead of `try?`, and log domain and code only (a store error's description can quote
    /// values).
    private func batchDelete<T: PersistentModel>(_ type: T.Type, where predicate: Predicate<T>? = nil) -> Bool {
        do {
            try context.delete(model: type, where: predicate)
            return true
        } catch {
            logWipeFailure(of: type, error)
            return false
        }
    }

    private func deleteEach<T: PersistentModel>(_ type: T.Type, resolving resolve: (T) -> Void = { _ in }) -> Bool {
        guard let rows = fetched(type) else { return false }
        for row in rows {
            resolve(row)
            context.delete(row)
        }
        return true
    }

    private func fetched<T: PersistentModel>(_ type: T.Type) -> [T]? {
        do {
            return try context.fetch(FetchDescriptor<T>())
        } catch {
            logWipeFailure(of: type, error)
            return nil
        }
    }

    private func logWipeFailure<T: PersistentModel>(of type: T.Type, _ error: Error) {
        let e = error as NSError
        Self.log.error("Train wipe of \(String(describing: type), privacy: .public): \(e.domain, privacy: .public) \(e.code, privacy: .public)")
    }
}
