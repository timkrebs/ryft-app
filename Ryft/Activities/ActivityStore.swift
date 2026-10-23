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
        guard let account else { return nil }
        let key = LocalManualSleep.key(account: account, day: day)
        var d = FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.key == key && $0.account == account })
        d.fetchLimit = 1
        return fetch(d).first?.snapshot
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
        switch row.origin {
        case .manual:
            set(\.sportRaw, draft.sport.rawValue)
            set(\.start, draft.start)
            set(\.end, Optional(draft.end))
            set(\.movingSec, max(0, draft.end.timeIntervalSince(draft.start)))
            set(\.distanceM, draft.distanceM)
        case .recorded:
            if draft.sport.family == row.sport.family { set(\.sportRaw, draft.sport.rawValue) }
        }
        set(\.perceivedEffort, draft.perceivedEffort)
        set(\.notes, draft.notes)
        guard changed else { return row.snapshot }
        row.localRevision += 1
        row.updatedAt = now
        return wrote(row)
    }

    /// Delete: the row stays as a tombstone until the platform confirms the `DELETE` (the uploader then calls
    /// `remove`). False for another account's id.
    @discardableResult
    func tombstone(_ id: UUID) -> Bool {
        guard let row = row(id) else { return false }
        if row.deletedAt == nil {
            row.deletedAt = now
            row.updatedAt = now
        }
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
        if confirmed == row.localRevision { row.lastAttemptData = nil }
        _ = wrote(row)
        return true
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

    // MARK: accounts

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
        if let account {
            activities = fetch(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.account != account }),
                               in: context)
            sleeps = fetch(FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.account != account }),
                           in: context)
            try? context.delete(model: ActivityTrackChunk.self, where: #Predicate { $0.account != account })
        } else {
            activities = fetch(FetchDescriptor<LocalActivity>(), in: context)
            sleeps = fetch(FetchDescriptor<LocalManualSleep>(), in: context)
            try? context.delete(model: ActivityTrackChunk.self)
        }
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
