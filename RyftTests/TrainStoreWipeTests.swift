import Foundation
import OSLog
import SwiftData
import Testing
@testable import Ryft

// What a wipe leaves of logged sessions: nothing, on disk, in any state a row can be in, while a session expiry's parked
// activities keep their unsaved changes. Synthetic values only.

/// A store in its own folder, so a test can read the file three ways. The reopened store is bound to a variable: an
/// inline `TrainStore(url:).context` lets the container go while the context is in use, which crashes the test process.
@MainActor
private final class StoreOnDisk {
    struct Rows: Equatable {
        var sessions: Int, exercises: Int, sets: Int
        static let none = Rows(sessions: 0, exercises: 0, sets: 0)
    }

    let folder: URL
    let url: URL
    private(set) var store: TrainStore

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ryft-train-wipe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("Train.store")
        store = TrainStore(url: url)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    /// A relaunch: the rows of the next fetch hold no values yet.
    func relaunch() { store = TrainStore(url: url) }

    static func rows(in context: ModelContext) throws -> Rows {
        try Rows(sessions: context.fetchCount(FetchDescriptor<LocalSession>()),
                 exercises: context.fetchCount(FetchDescriptor<LocalSessionExercise>()),
                 sets: context.fetchCount(FetchDescriptor<LocalSet>()))
    }

    var inContext: Rows { get throws { try Self.rows(in: store.context) } }
    /// A second context reads what was saved, not what the app's context holds.
    var inFreshContext: Rows { get throws { try Self.rows(in: ModelContext(store.container)) } }
    var inReopenedStore: Rows {
        get throws {
            let reopened = TrainStore(url: url)
            let rows = try Self.rows(in: reopened.context)
            return withExtendedLifetime(reopened) { rows }
        }
    }

    /// Two exercises of three sets each.
    @discardableResult
    func session(checked: Bool = false, saved: Bool = true) -> LocalSession {
        let session = LocalSession(title: "Upper")
        store.context.insert(session)
        for exercise in [MockTrain.bench, MockTrain.row] {
            let added = SessionFactory.add(exercise, to: session, sets: 3, in: store)
            guard checked else { continue }
            for set in added.orderedSets {
                set.reps = 5
                set.weightKg = 80
                set.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
            }
        }
        if saved { store.save() }
        return session
    }

    func expectNothingLeft(sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try inContext == .none, "the app's context", sourceLocation: sourceLocation)
        #expect(try inFreshContext == .none, "the file, through a fresh context", sourceLocation: sourceLocation)
        #expect(try inReopenedStore == .none, "the file, reopened", sourceLocation: sourceLocation)
        #expect(!store.context.hasChanges, "nothing left to write", sourceLocation: sourceLocation)
    }
}

private enum WipeValues {
    /// `nil`: sign-out, deletion, another account. An account: a session expiry parking its activities.
    static let parkings: [String?] = [nil, "account-a"]
    static let account = "account-a"
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let earlier = Date(timeIntervalSince1970: 1_799_000_000)
}

@MainActor
struct TrainStoreWipeTests {
    // MARK: every state a row can be in

    @Test(arguments: WipeValues.parkings)
    func savedRowsGo(_ parking: String?) throws {
        let disk = try StoreOnDisk()
        disk.session()
        #expect(try disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6))
        disk.store.wipe(parkingActivitiesOf: parking)
        try disk.expectNothingLeft()
    }

    @Test(arguments: WipeValues.parkings)
    func checkedSetsGo(_ parking: String?) throws {
        let disk = try StoreOnDisk()
        disk.session(checked: true)
        #expect(try disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6))
        disk.store.wipe(parkingActivitiesOf: parking)
        try disk.expectNothingLeft()
    }

    @Test(arguments: WipeValues.parkings)
    func anUnsavedEditGoes(_ parking: String?) throws {
        let disk = try StoreOnDisk()
        let set = disk.session().orderedExercises[0].orderedSets[0]
        set.reps = 9
        set.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(disk.store.context.hasChanges)
        disk.store.wipe(parkingActivitiesOf: parking)
        try disk.expectNothingLeft()
    }

    @Test(arguments: WipeValues.parkings)
    func anUnsavedNewSetGoes(_ parking: String?) throws {
        let disk = try StoreOnDisk()
        SessionFactory.appendSet(index: 9, to: disk.session().orderedExercises[0], in: disk.store)
        #expect(try disk.inContext.sets == 7)
        #expect(try disk.inFreshContext.sets == 6)
        disk.store.wipe(parkingActivitiesOf: parking)
        try disk.expectNothingLeft()
    }

    /// A batch delete acts on the store, so this one stayed in the context and the wipe's own `save()` wrote it.
    @Test(arguments: WipeValues.parkings)
    func aSessionNeverSavedGoes(_ parking: String?) throws {
        let disk = try StoreOnDisk()
        disk.session(checked: true, saved: false)
        #expect(try disk.inContext == .init(sessions: 1, exercises: 2, sets: 6))
        #expect(try disk.inFreshContext == .none)
        disk.store.wipe(parkingActivitiesOf: parking)
        try disk.expectNothingLeft()
    }

    /// The cascade can't reach a row without a parent.
    @Test(arguments: WipeValues.parkings)
    func orphansGo(_ parking: String?) throws {
        let disk = try StoreOnDisk()
        let context = disk.store.context
        let exercise = { LocalSessionExercise(exerciseId: UUID(), name: "Row", kind: .machine, loadType: .weight, position: 0) }
        // An exercise without a session, a set under it, and a set without an exercise; saved, and not.
        for saved in [true, false] {
            let orphan = exercise()
            context.insert(orphan)
            let child = LocalSet(setIndex: 0)
            context.insert(child)
            child.exercise = orphan
            context.insert(LocalSet(setIndex: 1))
            if saved { disk.store.save() }
        }
        #expect(try disk.inContext == .init(sessions: 0, exercises: 2, sets: 4))
        #expect(try disk.inFreshContext == .init(sessions: 0, exercises: 1, sets: 2))
        disk.store.wipe(parkingActivitiesOf: parking)
        try disk.expectNothingLeft()
    }

    // MARK: a session expiry's parked activities

    private func activity(_ account: String = WipeValues.account, revision: Int = 2, confirmed: Int = 1) -> LocalActivity {
        LocalActivity(account: account, sport: .running, origin: .manual, start: WipeValues.earlier, end: WipeValues.now,
                      movingSec: 1_800, localRevision: revision, confirmedRevision: confirmed, createdAt: WipeValues.earlier)
    }

    private func night(_ day: String, _ account: String = WipeValues.account, revision: Int = 2, confirmed: Int = 1) -> LocalManualSleep {
        LocalManualSleep(day: day, account: account, bed: WipeValues.earlier, wake: WipeValues.now, localRevision: revision,
                         confirmedRevision: confirmed)
    }

    private func chunk(of activity: LocalActivity) -> ActivityTrackChunk {
        ActivityTrackChunk(activityID: activity.id, account: activity.account, seq: 0, kind: .profile, data: Data([1]),
                           count: 1, first: WipeValues.earlier, last: WipeValues.now)
    }

    @Test func aSessionExpiryKeepsParkedRowsWithTheirUnsavedChanges() throws {
        let disk = try StoreOnDisk()
        let context = disk.store.context
        disk.session(checked: true)
        disk.session(saved: false)

        let edited = activity(), alreadyParked = activity(), confirmed = activity(revision: 1), theirs = activity("account-b")
        let keptChunk = chunk(of: edited), goneChunk = chunk(of: confirmed)
        alreadyParked.parkedAt = WipeValues.earlier
        let editedNight = night("2026-10-01"), confirmedNight = night("2026-10-02", revision: 1)
        let theirNight = night("2026-10-03", "account-b")
        for row in [edited, alreadyParked, confirmed, theirs] { context.insert(row) }
        for row in [keptChunk, goneChunk] { context.insert(row) }
        for row in [editedNight, confirmedNight, theirNight] { context.insert(row) }
        disk.store.save()
        // Never saved, and edits nothing has saved: a rollback would take these.
        let unsaved = activity()
        context.insert(unsaved)
        edited.notes = "Hills"
        editedNight.wake = WipeValues.now.addingTimeInterval(60)
        let ids = (edited: edited.id, parked: alreadyParked.id, unsaved: unsaved.id)

        disk.store.wipe(parkingActivitiesOf: WipeValues.account, at: WipeValues.now)

        try disk.expectNothingLeft()
        let reopened = TrainStore(url: disk.url)
        for label in ["same context", "reopened"] {
            let context = label == "same context" ? disk.store.context : reopened.context
            let rows = try context.fetch(FetchDescriptor<LocalActivity>())
            #expect(Set(rows.map(\.id)) == [ids.edited, ids.parked, ids.unsaved], "\(label)")
            #expect(rows.first { $0.id == ids.edited }?.notes == "Hills", "\(label)")
            #expect(rows.first { $0.id == ids.edited }?.parkedAt == WipeValues.now, "\(label)")
            #expect(rows.first { $0.id == ids.unsaved }?.parkedAt == WipeValues.now, "\(label)")
            #expect(rows.first { $0.id == ids.parked }?.parkedAt == WipeValues.earlier, "\(label): the limit never restarts")
            #expect(try context.fetch(FetchDescriptor<ActivityTrackChunk>()).map(\.activityID) == [ids.edited], "\(label)")
            let nights = try context.fetch(FetchDescriptor<LocalManualSleep>())
            #expect(nights.map(\.day) == ["2026-10-01"], "\(label)")
            #expect(nights.first?.wake == WipeValues.now.addingTimeInterval(60), "\(label)")
            #expect(nights.first?.parkedAt == WipeValues.now, "\(label)")
        }
        withExtendedLifetime(reopened) {}
    }

    @Test func aSignOutTakesTheActivitiesToo() throws {
        let disk = try StoreOnDisk()
        let context = disk.store.context
        disk.session()
        let row = activity()
        context.insert(row)
        context.insert(chunk(of: row))
        context.insert(night("2026-10-01"))
        disk.store.save()

        disk.store.wipe()

        try disk.expectNothingLeft()
        let fresh = ModelContext(disk.store.container)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalActivity>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<ActivityTrackChunk>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalManualSleep>()) == 0)
    }

    // MARK: no batch delete

    /// A batch delete works on the store behind the context's back, so its rows never reach this notification. It
    /// catches `LocalSession`, whose batch delete succeeds; the next test catches the two that throw.
    @Test(arguments: WipeValues.parkings)
    func everyRowGoesThroughTheContext(_ parking: String?) throws {
        let disk = try StoreOnDisk()
        let session = disk.session(checked: true)
        let rows = [session.persistentModelID] + session.exercises.map(\.persistentModelID) + session.allSets.map(\.persistentModelID)
        #expect(rows.count == 9)
        var deleted: Set<PersistentIdentifier> = []
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: disk.store.context,
                                                              queue: nil) { note in
            let key = ModelContext.NotificationKey.deletedIdentifiers.rawValue
            deleted.formUnion(note.userInfo?[key] as? [PersistentIdentifier] ?? [])
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        disk.store.wipe(parkingActivitiesOf: parking)

        #expect(deleted.isSuperset(of: rows))
    }

    /// The throw behind `try?` leaves nothing but this log line, so the log is where it can be seen. A failed batch
    /// delete after the wipe is the control: the log is read, and once that line shows, so would one from the wipe.
    @Test func noBatchDeleteIsTriedOnSessionRows() async throws {
        let disk = try StoreOnDisk()
        disk.session(checked: true)
        let start = Date()
        disk.store.wipe()
        let end = Date()

        let control = try StoreOnDisk()
        control.session()
        do {
            try control.store.context.delete(model: LocalSet.self)
            return // Not refused on this OS: there is no line to look for, and `everyRowGoesThroughTheContext` still runs.
        } catch {}
        #expect(await eventually(timeout: .seconds(10)) { !Self.failedBatchDeletes(since: end).isEmpty })
        #expect(Self.failedBatchDeletes(since: start).allSatisfy { $0 >= end })
    }

    private static func failedBatchDeletes(since start: Date) -> [Date] {
        guard let log = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? log.getEntries(at: log.position(date: start),
                                                matching: NSPredicate(format: "composedMessage CONTAINS %@", "Batch delete failed"))
        else { return [] }
        return entries.map(\.date).filter { $0 >= start }
    }

    // MARK: what still holds a row

    /// Until the app's account-change handler runs, a live workout's controller and screens hold deleted rows, and
    /// deleting the object tells their observers, which a batch delete didn't. SwiftData answers for a deleted row from
    /// what it resolved, and `deletedSetIDs` and `deletedExerciseIDs` are a fatal error unless the wipe read them.
    @Test(arguments: WipeValues.parkings)
    func aRowStillHeldStaysUsableAndNothingComesBack(_ parking: String?) throws {
        let disk = try StoreOnDisk()
        disk.session(checked: true)
        disk.relaunch()
        let context = disk.store.context
        let session = try #require(try context.fetch(FetchDescriptor<LocalSession>()).first)
        let exercise = try #require(try context.fetch(FetchDescriptor<LocalSessionExercise>()).first)
        let set = try #require(try context.fetch(FetchDescriptor<LocalSet>()).first)

        disk.store.wipe(parkingActivitiesOf: parking)

        // Its relationships may answer empty or with the deleted rows, so only the reads themselves are pinned.
        #expect(session.title == "Upper")
        #expect(session.wire.id == session.id)
        #expect(session.deletedSetIDs.isEmpty && session.deletedExerciseIDs.isEmpty)
        #expect(exercise.wire.id == exercise.id)
        #expect(set.wire.id == set.id)
        // What `SessionController` does with a row a sheet still shows.
        session.deletedSetIDs.append(set.id)
        session.deletedExerciseIDs.append(exercise.id)
        session.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        exercise.notes = "Late"
        set.reps = 3
        disk.store.save()
        try disk.expectNothingLeft()
    }

    // MARK: the sync side

    @Test(arguments: WipeValues.parkings)
    func aWipeQueuesNoUploadAndMovesTheGeneration(_ parking: String?) async {
        let rig = ReplaceRig()
        rig.session.uploaded = true
        rig.session.uploadedTo = "test"
        rig.session.deletedSetIDs = [UUID()]
        rig.store.save()
        let generation = rig.sync.generation
        let epoch = rig.store.epoch

        rig.store.wipe(parkingActivitiesOf: parking)

        #expect(rig.store.epoch == epoch + 1)
        #expect(rig.sync.generation != generation)
        #expect(rig.store.pendingOps().isEmpty)
        await rig.sync.flush()
        #expect(rig.api.count("putSession") == 0)
        #expect(rig.api.count("deleteSession") == 0)
    }
}
