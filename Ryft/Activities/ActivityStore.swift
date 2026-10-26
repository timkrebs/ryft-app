import Foundation
import Observation
import SwiftData
import os

/// The only reader and writer of the activity rows (`LocalActivity`, `ActivityTrackChunk`, `LocalManualSleep`;
/// ADR 0004). It runs on the main context of the account's store, one save per write.
///
/// - **Scoped to the account.** Every fetch is filtered by the signed-in account (design.md §8.4): another
///   account's rows can't be shown or sent, even before `purge(notBelongingTo:)` ran. Signed out, reads return
///   nothing and writes write nothing.
/// - **Demo data** reads and writes a store of its own in memory, as `"demo"`, so nothing typed in demo mode
///   reaches the account's store or its uploads (as the Repository keeps demo's read models apart).
/// - **The queue is the rows.** A row needs uploading while `localRevision > confirmedRevision` or while it's a
///   tombstone (`unconfirmed()`); the uploader (A2) confirms the revision it sent.
/// - **Snapshots out.** Callers get value copies, never the models.
@MainActor
@Observable
final class ActivityStore {
    /// Whose rows demo data's store holds.
    static let demoAccount = "demo"
    static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "activities")

    /// Bumped by every write: whoever read snapshots reads again.
    private(set) var revision = 0

    @ObservationIgnored private let liveStore: Persistence
    @ObservationIgnored private let clock: AppClock
    @ObservationIgnored private let signedInAccount: @MainActor () -> String?
    @ObservationIgnored private let isDemo: @MainActor () -> Bool
    @ObservationIgnored private var demoStoreInstance: TrainStore?

    /// `account` is asked on every call (the signed-in account's id, nil when signed out).
    init(store: Persistence, clock: AppClock, account: @escaping @MainActor () -> String?,
         isDemo: @escaping @MainActor () -> Bool = { false }) {
        liveStore = store
        self.clock = clock
        signedInAccount = account
        self.isDemo = isDemo
    }

    /// The environment's store, account and demo switch (`AppEnvironment.activities`).
    convenience init(env: AppEnvironment) {
        self.init(store: env.persistence, clock: env.clock,
                  account: { [weak env] in env?.auth.accountID },
                  isDemo: { [weak env] in env?.isDemo ?? false })
    }

    /// Whose rows reads see and writes create: the signed-in account, demo data's own, or nobody.
    var account: String? { isDemo() ? Self.demoAccount : signedInAccount() }

    /// False when the store lives in memory only (it couldn't be opened on disk, demo data, tests): a recording
    /// won't survive the app closing, and pre-start says so (design.md §3.9).
    var isDurable: Bool { store.isDurable }

    private var store: Persistence {
        guard isDemo() else { return liveStore }
        if let demo = demoStoreInstance { return demo }
        let demo = TrainStore(inMemory: true)
        demoStoreInstance = demo
        return demo
    }

    private var context: ModelContext { store.context }

    /// Where `account`'s rows live: demo data's store for `demoAccount` (only while it exists), else the account's.
    private func storeHolding(_ account: String) -> Persistence {
        if account == Self.demoAccount, let demo = demoStoreInstance { return demo }
        return liveStore
    }
    private var now: Date { clock.now() }

    // MARK: reads

    /// The account's activities that start on `day` (local, `yyyy-MM-dd`), oldest first: saved documents,
    /// tombstones and recordings. Confirmed rows are included until compaction; `needsUpload` tells them apart.
    func snapshots(onDay day: String) -> [LocalActivitySnapshot] {
        _ = revision
        guard let account, let start = DayFormat.date(from: day) else { return [] }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let d = FetchDescriptor<LocalActivity>(
            predicate: #Predicate { $0.account == account && $0.start >= start && $0.start < end },
            sortBy: [SortDescriptor(\.start)])
        return fetch(d).map(\.snapshot)
    }

    /// The account's activities among `ids`, in no particular order: one fetch, only those rows (My Day: where a
    /// day's platform rows are on this iPhone, wherever they start now).
    func snapshots(ids: [UUID]) -> [LocalActivitySnapshot] {
        _ = revision
        guard let account, !ids.isEmpty else { return [] }
        let d = FetchDescriptor<LocalActivity>(predicate: #Predicate { ids.contains($0.id) && $0.account == account })
        return fetch(d).map(\.snapshot)
    }

    /// One of the account's activities.
    func snapshot(id: UUID) -> LocalActivitySnapshot? {
        _ = revision
        return row(id)?.snapshot
    }

    /// What the uploader sends, in the order the rows were created: edits the platform hasn't confirmed, and
    /// tombstones. A recording isn't here until Save gives it a revision.
    func unconfirmed() -> [LocalActivitySnapshot] {
        _ = revision
        guard let account else { return [] }
        let d = FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.account == account },
                                               sortBy: [SortDescriptor(\.createdAt)])
        return fetch(d).filter { $0.localRevision > $0.confirmedRevision || $0.deletedAt != nil }.map(\.snapshot)
    }

    /// The account's manual sleep for the night that ends on `day`, if any.
    func manualSleep(onDay day: String) -> ManualSleepSnapshot? {
        _ = revision
        return sleepRow(day)?.snapshot
    }

    // MARK: documents

    /// Add activity: a new document at revision 1, waiting for its first upload. Nil when signed out.
    @discardableResult
    func save(manual draft: ActivityDraft) -> LocalActivitySnapshot? {
        guard let account else { return nil }
        let row = LocalActivity(account: account, sport: draft.sport, origin: .manual, start: draft.start,
                                end: draft.end, movingSec: max(0, draft.end.timeIntervalSince(draft.start)),
                                distanceM: draft.distanceM, perceivedEffort: draft.perceivedEffort, notes: draft.notes,
                                localRevision: 1, createdAt: now)
        context.insert(row)
        return wrote(row)
    }

    /// Edit: a manual activity takes every field; a recorded one only its effort, notes and a sport of the same
    /// family (times, distance and route came from the recording). A change bumps the revision, so it's uploaded
    /// again; no change, no new revision. Nil for a tombstone, a recording in progress or another account's id.
    @discardableResult
    func update(_ id: UUID, _ draft: ActivityDraft) -> LocalActivitySnapshot? {
        guard let row = row(id), row.deletedAt == nil, row.phaseRaw == LocalActivity.savedPhase else { return nil }
        var changed = false
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<LocalActivity, T>, _ value: T) {
            guard row[keyPath: keyPath] != value else { return }
            row[keyPath: keyPath] = value
            changed = true
        }
        // A sport this build doesn't know (an adopted row) shows as Other: keeping Other keeps the platform's value.
        let keepsSport = row.unknownSport != nil && draft.sport == .other
        switch row.origin {
        case .manual:
            if !keepsSport { set(\.sportRaw, draft.sport.rawValue) }
            set(\.start, draft.start)
            set(\.end, Optional(draft.end))
            set(\.movingSec, max(0, draft.end.timeIntervalSince(draft.start)))
            set(\.distanceM, draft.distanceM)
        case .recorded:
            if !keepsSport, draft.sport.family == row.sport.family { set(\.sportRaw, draft.sport.rawValue) }
        }
        set(\.perceivedEffort, draft.perceivedEffort)
        set(\.notes, draft.notes)
        guard changed else { return row.snapshot }
        row.localRevision += 1
        row.updatedAt = now
        // A new revision is a new request: the platform's refusal of the last one no longer applies.
        row.lastAttemptData = nil
        return wrote(row)
    }

    /// Edit or delete of one of the platform's activities this iPhone has no row for (recorded or added on another
    /// device, or compacted here): its copy becomes a confirmed row of the account (revision 1 of 1), which
    /// `update(_:_:)` and `tombstone(_:)` then change as usual. An existing row of the account is returned as it is.
    /// Nil when signed out, for an origin this build doesn't know (read-only, code nit 7), or when another account
    /// holds the id (its row is never overwritten).
    @discardableResult
    func adopt(_ activity: SportActivity) -> LocalActivitySnapshot? {
        guard let account, activity.isEditable else { return nil }
        if let row = row(activity.id) { return row.snapshot }
        let id = activity.id
        var taken = FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.id == id })
        taken.fetchLimit = 1
        guard fetch(taken).isEmpty else { return nil }
        let row = LocalActivity(id: id, account: account, sport: activity.sport, origin: activity.origin,
                                start: activity.start, end: activity.end, movingSec: activity.movingSec,
                                distanceM: activity.distanceM, ascentM: activity.ascentM, descentM: activity.descentM,
                                perceivedEffort: activity.perceivedEffort, notes: activity.notes ?? "",
                                splits: activity.splits, localRevision: 1, confirmedRevision: 1, createdAt: now)
        if let unknown = activity.unknownSport { row.sportRaw = unknown }
        row.updatedAt = activity.clientUpdatedAt
        context.insert(row)
        return wrote(row)
    }

    /// Delete: the row stays as a tombstone until the platform confirms the `DELETE` (the uploader then calls
    /// `remove`). Its notes go at once: a `DELETE` needs only the id (privacy review N3). False for another
    /// account's id.
    @discardableResult
    func tombstone(_ id: UUID) -> Bool {
        guard let row = row(id) else { return false }
        if row.deletedAt == nil {
            row.deletedAt = now
            row.updatedAt = now
        }
        row.notes = ""
        _ = wrote(row)
        return true
    }

    /// The platform answered 2xx to the `PUT` of `revision`. An answer for an older revision than one already
    /// confirmed changes nothing; an edit made while the request was out stays unconfirmed (one more `PUT`).
    @discardableResult
    func confirm(_ id: UUID, revision sent: Int) -> Bool {
        guard let row = row(id) else { return false }
        let confirmed = min(sent, row.localRevision)
        guard confirmed > row.confirmedRevision else { return true }
        row.confirmedRevision = confirmed
        if confirmed == row.localRevision {
            row.lastAttemptData = nil
            row.sentAt = nil
        }
        _ = wrote(row)
        return true
    }

    /// The uploader, right before a `PUT` goes out (a date), and after an answer that says nothing was stored
    /// (the value before it): whether the platform may hold a revision (`LocalActivity.sentAt`).
    func setSent(_ id: UUID, _ date: Date?) {
        guard let row = row(id), row.sentAt != date else { return }
        row.sentAt = date
        _ = wrote(row)
    }

    /// Deletes one of the account's activities and its chunks: a confirmed `DELETE`, a tombstone that was never
    /// uploaded, Discard (the uploader's and the recorder's call; nothing else deletes before confirmation).
    func remove(_ id: UUID) {
        guard let row = row(id) else { return }
        // Keys first once routes are sealed (ActivityVault, A3), then the chunks, then the row.
        let account = row.account
        try? context.delete(model: ActivityTrackChunk.self,
                            where: #Predicate { $0.activityID == id && $0.account == account })
        context.delete(row)
        store.save()
        revision += 1
    }

    /// The last failed request for a row (Details; a refusal makes it "failed" until Retry or an edit), or nil
    /// to clear it. The uploader's call; it doesn't change the revision.
    func recordFailure(_ id: UUID, _ attempt: UploadAttempt?) {
        guard let row = row(id) else { return }
        let data = attempt.flatMap { WireCoding.encode($0) }
        guard row.lastAttemptData != data else { return }
        row.lastAttemptData = data
        _ = wrote(row)
    }

    /// Every row of the account, oldest first: documents, tombstones and recordings.
    func allSnapshots() -> [LocalActivitySnapshot] {
        account.map(allSnapshots(ofAccount:)) ?? []
    }

    /// The same for `account`, whoever is signed in now ("Export my data" reads the account it started for):
    /// demo data's own store for `demoAccount`, else the account's store.
    func allSnapshots(ofAccount account: String) -> [LocalActivitySnapshot] {
        _ = revision
        let d = FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.account == account },
                                               sortBy: [SortDescriptor(\.createdAt)])
        return fetch(d, in: storeHolding(account).context).map(\.snapshot)
    }

    // MARK: manual sleep

    /// Add sleep, or its edit: the night that ends on `day`, at the next revision (the first is 1). A deleted
    /// night comes back. No change, no new revision. Nil when signed out.
    @discardableResult
    func saveSleep(day: String, bed: Date, wake: Date) -> ManualSleepSnapshot? {
        guard let account else { return nil }
        guard let night = sleepRow(day) else {
            let night = LocalManualSleep(day: day, account: account, bed: bed, wake: wake)
            context.insert(night)
            return wrote(night)
        }
        guard night.bed != bed || night.wake != wake || night.deletedAt != nil else { return night.snapshot }
        night.bed = bed
        night.wake = wake
        night.deletedAt = nil
        night.localRevision += 1
        night.lastAttemptData = nil
        return wrote(night)
    }

    /// Delete a night: a tombstone until the platform confirms the `DELETE` (the uploader then calls
    /// `removeSleep`). False when the account has no night for `day`.
    @discardableResult
    func tombstoneSleep(day: String) -> Bool {
        guard let night = sleepRow(day) else { return false }
        if night.deletedAt == nil { night.deletedAt = now }
        night.lastAttemptData = nil
        _ = wrote(night)
        return true
    }

    /// The platform answered 2xx to the night's `PUT` of `revision` (as `confirm(_:revision:)`). The row stays:
    /// My Day marks the platform's copy "added by you" by it (until API request R11).
    @discardableResult
    func confirmSleep(day: String, revision sent: Int) -> Bool {
        guard let night = sleepRow(day) else { return false }
        let confirmed = min(sent, night.localRevision)
        guard confirmed > night.confirmedRevision else { return true }
        night.confirmedRevision = confirmed
        if confirmed == night.localRevision {
            night.lastAttemptData = nil
            night.sentAt = nil
        }
        _ = wrote(night)
        return true
    }

    /// As `setSent(_:_:)`, for a night.
    func setSleepSent(day: String, _ date: Date?) {
        guard let night = sleepRow(day), night.sentAt != date else { return }
        night.sentAt = date
        _ = wrote(night)
    }

    /// Deletes the account's night for `day`: a confirmed `DELETE`, or a delete of a night never sent.
    /// `onlyIfDeleted`: only while it's still a tombstone (a confirmed `DELETE` mustn't take a night added again
    /// meanwhile).
    func removeSleep(day: String, onlyIfDeleted: Bool = false) {
        guard let night = sleepRow(day), !onlyIfDeleted || night.deletedAt != nil else { return }
        context.delete(night)
        store.save()
        revision += 1
    }

    /// As `recordFailure(_:_:)`, for a night.
    func recordSleepFailure(day: String, _ attempt: UploadAttempt?) {
        guard let night = sleepRow(day) else { return }
        let data = attempt.flatMap { WireCoding.encode($0) }
        guard night.lastAttemptData != data else { return }
        night.lastAttemptData = data
        _ = wrote(night)
    }

    /// The account's nights the platform hasn't confirmed (edits and deletes), by day.
    func unconfirmedSleeps() -> [ManualSleepSnapshot] {
        manualSleeps().filter(\.needsUpload)
    }

    /// Every night the account added on this iPhone, by day.
    func manualSleeps() -> [ManualSleepSnapshot] {
        account.map(manualSleeps(ofAccount:)) ?? []
    }

    /// The same for `account`, whoever is signed in now ("Export my data").
    func manualSleeps(ofAccount account: String) -> [ManualSleepSnapshot] {
        _ = revision
        let d = FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.account == account },
                                                  sortBy: [SortDescriptor(\.day)])
        return fetch(d, in: storeHolding(account).context).map(\.snapshot)
    }

    // MARK: accounts

    /// How long a session expiry keeps an account's unconfirmed rows (design.md §8.4). An account deleted on the
    /// web looks exactly like an expiry (a final `401`), so this limit is what removes its data from the phone.
    static let parkingLimit: TimeInterval = 30 * 86_400

    /// The same account signed in again after its session expired: its parked rows and nights are its own again
    /// (the uploader then sends them). Always the account's store. Returns how many came back.
    @discardableResult
    func unpark(account: String) -> Int {
        let context = liveStore.context
        let rows = fetch(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.account == account && $0.parkedAt != nil }),
                         in: context)
        let nights = fetch(FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.account == account && $0.parkedAt != nil }),
                           in: context)
        guard !rows.isEmpty || !nights.isEmpty else { return 0 }
        for row in rows { row.parkedAt = nil }
        for night in nights { night.parkedAt = nil }
        liveStore.save()
        revision += 1
        return rows.count + nights.count
    }

    /// Rows and nights parked longer than `parkingLimit`, whoever's, with their chunks (keys first once A3b seals
    /// them). At launch and in the nightly compaction. Returns how many rows and nights went.
    @discardableResult
    func deleteExpiredParked() -> Int {
        let context = liveStore.context
        let cutoff = now.addingTimeInterval(-Self.parkingLimit)
        let rows = fetch(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.parkedAt != nil }), in: context)
            .filter { ($0.parkedAt ?? .distantFuture) < cutoff }
        let nights = fetch(FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.parkedAt != nil }), in: context)
            .filter { ($0.parkedAt ?? .distantFuture) < cutoff }
        guard !rows.isEmpty || !nights.isEmpty else { return 0 }
        deleteWithChunks(rows, nights, in: context)
        return rows.count + nights.count
    }

    /// The account store's rows (keys first once A3b seals chunks, then the chunks) and nights.
    private func deleteWithChunks(_ rows: [LocalActivity], _ nights: [LocalManualSleep], in context: ModelContext) {
        for row in rows {
            let id = row.id, owner = row.account
            try? context.delete(model: ActivityTrackChunk.self,
                                where: #Predicate { $0.activityID == id && $0.account == owner })
            context.delete(row)
        }
        for night in nights { context.delete(night) }
        liveStore.save()
        revision += 1
    }

    /// Rows and nights a session expiry parked on this iPhone, whoever's (signed out, Welcome says so and offers
    /// to delete them: `purgeParked()`). Always the account's store.
    func parkedCount() -> Int {
        _ = revision
        let context = liveStore.context
        let rows = (try? context.fetchCount(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.parkedAt != nil }))) ?? 0
        let nights = (try? context.fetchCount(FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.parkedAt != nil }))) ?? 0
        return rows + nights
    }

    /// When the first parked row or night goes (`deleteExpiredParked`): the earliest `parkedAt` plus
    /// `parkingLimit`; nil when nothing is parked. Welcome says "Log in by {date}" with it.
    func parkedUntil() -> Date? {
        _ = revision
        let context = liveStore.context
        let rows = fetch(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.parkedAt != nil }), in: context)
        let nights = fetch(FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.parkedAt != nil }), in: context)
        let earliest = (rows.compactMap(\.parkedAt) + nights.compactMap(\.parkedAt)).min()
        return earliest?.addingTimeInterval(Self.parkingLimit)
    }

    /// "Delete from this iPhone": every parked row and night, with its chunks (keys first once A3b seals them),
    /// whoever's. Returns how many rows and nights went.
    @discardableResult
    func purgeParked() -> Int {
        let context = liveStore.context
        let rows = fetch(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.parkedAt != nil }), in: context)
        let nights = fetch(FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.parkedAt != nil }), in: context)
        guard !rows.isEmpty || !nights.isEmpty else { return 0 }
        deleteWithChunks(rows, nights, in: context)
        return rows.count + nights.count
    }

    /// What signing out of `account` would delete without the platform having it (the confirmation, §8.4):
    /// activities and nights not confirmed, recordings not saved. Always the account's store, whatever the Demo
    /// data switch says. 0 for nil.
    func unconfirmedCount(ofAccount account: String?) -> Int {
        _ = revision
        guard let account else { return 0 }
        let context = liveStore.context
        let rows = fetch(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.account == account }), in: context)
        let nights = fetch(FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.account == account }),
                           in: context)
        return rows.filter(\.isUnconfirmedOrRecording).count + nights.filter(\.isUnconfirmed).count
    }

    /// Deletes every activity row, chunk and manual sleep of any account but `account` (nil: of every account),
    /// parked or not. Called when another account signs in, before anything reads (A2 wires
    /// `AuthService.onAccountWillChange`). Always the account's store, whatever the Demo data switch says.
    /// Returns the number of activity and sleep rows deleted.
    /// - Important: pass the incoming account's id (`onAccountWillChange`'s `to`), never `self.account`: that's
    ///   `"demo"` while demo data is on, and would purge the signed-in account's own unsent rows.
    @discardableResult
    func purge(notBelongingTo account: String?) -> Int {
        let context = liveStore.context
        let activities: [LocalActivity]
        let sleeps: [LocalManualSleep]
        // Keys first once routes are sealed (ActivityVault, A3), then the chunks, then the rows.
        let chunks: Int
        if let account {
            activities = fetch(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.account != account }),
                               in: context)
            sleeps = fetch(FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.account != account }),
                           in: context)
            chunks = (try? context.fetchCount(FetchDescriptor<ActivityTrackChunk>(predicate: #Predicate { $0.account != account }))) ?? 0
            if chunks > 0 { try? context.delete(model: ActivityTrackChunk.self, where: #Predicate { $0.account != account }) }
        } else {
            activities = fetch(FetchDescriptor<LocalActivity>(), in: context)
            sleeps = fetch(FetchDescriptor<LocalManualSleep>(), in: context)
            chunks = (try? context.fetchCount(FetchDescriptor<ActivityTrackChunk>())) ?? 0
            if chunks > 0 { try? context.delete(model: ActivityTrackChunk.self) }
        }
        // Nothing of anyone else's: no save (the launch runs this on every start, before the first frame).
        guard !activities.isEmpty || !sleeps.isEmpty || chunks > 0 else { return 0 }
        for row in activities { context.delete(row) }
        for row in sleeps { context.delete(row) }
        liveStore.save()
        revision += 1
        return activities.count + sleeps.count
    }

    /// Another account, a sign-out or the Demo data switch (`AppState.reset`): demo data's store starts over, so
    /// nothing typed in demo mode by one account is shown to the next, and readers read again (the sign-out wipe
    /// changed the account's store underneath).
    func accountChanged() {
        demoStoreInstance = nil
        revision += 1
    }

    // MARK: helpers

    private func row(_ id: UUID) -> LocalActivity? {
        guard let account else { return nil }
        var d = FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.id == id && $0.account == account })
        d.fetchLimit = 1
        return fetch(d).first
    }

    private func wrote(_ row: LocalActivity) -> LocalActivitySnapshot {
        store.save()
        revision += 1
        return row.snapshot
    }

    private func sleepRow(_ day: String) -> LocalManualSleep? {
        guard let account else { return nil }
        let key = LocalManualSleep.key(account: account, day: day)
        var d = FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.key == key && $0.account == account })
        d.fetchLimit = 1
        return fetch(d).first
    }

    private func wrote(_ night: LocalManualSleep) -> ManualSleepSnapshot {
        store.save()
        revision += 1
        return night.snapshot
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, in context: ModelContext? = nil) -> [T] {
        do {
            return try (context ?? self.context).fetch(descriptor)
        } catch {
            // Domain and code only: a store error's description can quote values.
            let e = error as NSError
            Self.log.error("activity fetch failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
            return []
        }
    }
}
