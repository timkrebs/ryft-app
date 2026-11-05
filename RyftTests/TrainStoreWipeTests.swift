import Foundation
import OSLog
import SQLite3
import SwiftData
import Testing
@testable import Ryft

// What a wipe leaves of logged sessions: nothing, on disk, in any state a row can be in, while a session expiry's parked
// activities keep their unsaved changes. Synthetic values only.

/// A store in its own folder, so a test can read the file three ways. The reopened store is bound to a variable: an
/// inline `TrainStore(url:).context` lets the container go while the context is in use, which crashes the test process.
@MainActor
final class StoreOnDisk {
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

    /// A refusal in the file itself, so the app needs no seam for it: a batch delete of `table` throws, and a save with
    /// a row of it to delete fails. A runtime error, as a full disk would be: Core Data takes a `RAISE` (a constraint
    /// error) in a save for an optimistic-locking conflict and aborts the process after its retries. One transaction,
    /// so nothing of a refused save or batch lands.
    func refuseDeletes(of table: WipedTable = .localSet) throws {
        try sql("CREATE TRIGGER wipe_refused BEFORE DELETE ON \(table.inFile) BEGIN SELECT abs(-9223372036854775808); END")
    }

    func allowDeletes() throws { try sql("DROP TRIGGER wipe_refused") }

    /// A fetch of `table` fails while it's away, and its rows come back with it.
    func hide(_ table: WipedTable) throws { try sql("ALTER TABLE \(table.inFile) RENAME TO \(table.inFile)_HIDDEN") }
    func bringBack(_ table: WipedTable) throws { try sql("ALTER TABLE \(table.inFile)_HIDDEN RENAME TO \(table.inFile)") }

    /// A row of every table in `tables`, saved. None of them is parked: their account isn't the one a test parks.
    func fill(_ tables: [WipedTable] = WipedTable.allCases) {
        for table in tables { table.insertRow(into: store.context) }
        store.save()
    }

    /// Tables by what's still in them, through a fresh context, so what was saved and not what the app's context holds.
    var inFile: [WipedTable: Int] {
        get throws {
            let context = ModelContext(store.container)
            return try Dictionary(uniqueKeysWithValues: WipedTable.allCases.map { try ($0, $0.rowCount(in: context)) })
        }
    }

    private func sql(_ statement: String) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        try #require(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
    }

    func expectNothingLeft(sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try inContext == .none, "the app's context", sourceLocation: sourceLocation)
        #expect(try inFreshContext == .none, "the file, through a fresh context", sourceLocation: sourceLocation)
        #expect(try inReopenedStore == .none, "the file, reopened", sourceLocation: sourceLocation)
        #expect(!store.context.hasChanges, "nothing left to write", sourceLocation: sourceLocation)
    }
}

/// Every table of the store, by its model's name.
enum WipedTable: String, CaseIterable {
    case localSession = "LocalSession", localSessionExercise = "LocalSessionExercise", localSet = "LocalSet"
    case cachedExercise = "CachedExercise", cachedPlan = "CachedPlan", pendingTrainOp = "PendingTrainOp"
    case importMapping = "ImportMapping", pendingImport = "PendingImport"
    case cachedDay = "CachedDay", cachedTrend = "CachedTrend", cachedInsight = "CachedInsight", cachedUser = "CachedUser"
    case cachedSleepRange = "CachedSleepRange", cachedWorkout = "CachedWorkout", cachedDocument = "CachedDocument"
    case localActivity = "LocalActivity", activityTrackChunk = "ActivityTrackChunk", localManualSleep = "LocalManualSleep"

    /// The ones `wipe` fetches, whichever way the activities go.
    static let fetched: [WipedTable] = [.localSet, .localSessionExercise, .localSession, .pendingImport, .localActivity,
                                        .localManualSleep]

    var inFile: String { "Z\(rawValue.uppercased())" }

    /// Deleted one by one, so it's the final save that can refuse them: all of them at once.
    func goesInTheSave(parking: String?) -> Bool {
        Self.fetched.contains(self) && (parking != nil || ![.localActivity, .localManualSleep].contains(self))
    }

    @MainActor
    func insertRow(into context: ModelContext) {
        let account = "account-b", date = WipeValues.earlier, data = Data([1]), id = WipeValues.accountB
        switch self {
        case .localSession:
            context.insert(LocalSession(title: "Upper"))
        case .localSessionExercise:
            context.insert(LocalSessionExercise(exerciseId: id, name: "Row", kind: .machine, loadType: .weight, position: 0))
        case .localSet:
            context.insert(LocalSet(setIndex: 0))
        case .cachedExercise:
            context.insert(CachedExercise(MockTrain.bench))
        case .cachedPlan:
            context.insert(CachedPlan(MockTrain.upperLower))
        case .pendingTrainOp:
            context.insert(PendingTrainOp(seq: 1, kind: .put, sessionId: id, account: account))
        case .importMapping:
            context.insert(ImportMapping(account: account, source: .alphaProgression,
                                         key: SourceExerciseKey(name: "bench press", equipment: "barbell"),
                                         choice: RememberedMatch(exerciseID: id, bodyweight: nil), at: date))
        case .pendingImport:
            context.insert(PendingImport(account: account, source: .alphaProgression, createdAt: date, timeZoneID: "UTC",
                                         duplicatesChecked: true, payload: data, progressData: data, sessionsPerRequest: 1))
        case .cachedDay:
            context.insert(CachedDay(day: "2026-10-01", date: date))
        case .cachedTrend:
            context.insert(CachedTrend(key: "hrv", data: data, fetchedAt: date))
        case .cachedInsight:
            context.insert(CachedInsight(id: "insight", position: 0, data: data, fetchedAt: date))
        case .cachedUser:
            context.insert(CachedUser(id: id, data: data, fetchedAt: date))
        case .cachedSleepRange:
            context.insert(CachedSleepRange(kind: "week", data: data, fetchedAt: date))
        case .cachedWorkout:
            context.insert(CachedWorkout(id: id, data: data, fetchedAt: date))
        case .cachedDocument:
            context.insert(CachedDocument(key: "report", data: data, fetchedAt: date))
        case .localActivity:
            context.insert(LocalActivity(account: account, sport: .running, origin: .manual, start: date, end: WipeValues.now,
                                         movingSec: 1_800, localRevision: 1, confirmedRevision: 1, createdAt: date))
        case .activityTrackChunk:
            context.insert(ActivityTrackChunk(activityID: id, account: account, seq: 0, kind: .profile, data: data, count: 1,
                                              first: date, last: WipeValues.now))
        case .localManualSleep:
            context.insert(LocalManualSleep(day: "2026-10-01", account: account, bed: date, wake: WipeValues.now,
                                            localRevision: 1, confirmedRevision: 1))
        }
    }

    @MainActor
    func rowCount(in context: ModelContext) throws -> Int {
        func count<T: PersistentModel>(_: T.Type) throws -> Int { try context.fetchCount(FetchDescriptor<T>()) }
        switch self {
        case .localSession: return try count(LocalSession.self)
        case .localSessionExercise: return try count(LocalSessionExercise.self)
        case .localSet: return try count(LocalSet.self)
        case .cachedExercise: return try count(CachedExercise.self)
        case .cachedPlan: return try count(CachedPlan.self)
        case .pendingTrainOp: return try count(PendingTrainOp.self)
        case .importMapping: return try count(ImportMapping.self)
        case .pendingImport: return try count(PendingImport.self)
        case .cachedDay: return try count(CachedDay.self)
        case .cachedTrend: return try count(CachedTrend.self)
        case .cachedInsight: return try count(CachedInsight.self)
        case .cachedUser: return try count(CachedUser.self)
        case .cachedSleepRange: return try count(CachedSleepRange.self)
        case .cachedWorkout: return try count(CachedWorkout.self)
        case .cachedDocument: return try count(CachedDocument.self)
        case .localActivity: return try count(LocalActivity.self)
        case .activityTrackChunk: return try count(ActivityTrackChunk.self)
        case .localManualSleep: return try count(LocalManualSleep.self)
        }
    }
}

enum WipeValues {
    /// `nil`: sign-out, deletion, another account. An account: a session expiry parking its activities.
    static let parkings: [String?] = [nil, "account-a"]
    static let account = "account-a"
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let earlier = Date(timeIntervalSince1970: 1_799_000_000)
    /// How a session ends with nobody signed in afterwards.
    static let endings: [AuthService.SignOutReason] = [.user, .sessionExpired, .accountDeleted(background: false)]
    static let accountA = UUID(uuidString: "0000000A-0000-4000-8000-0000000000D1") ?? UUID()
    static let accountB = UUID(uuidString: "0000000B-0000-4000-8000-0000000000D2") ?? UUID()
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
        disk.session(saved: false)
        #expect(try disk.inContext.sessions == 2)
        #expect(try disk.inFreshContext.sessions == 1)
        let unsaved = activity()
        context.insert(unsaved)
        edited.notes = "Hills"
        editedNight.wake = WipeValues.now.addingTimeInterval(60)
        let ids = (edited: edited.id, parked: alreadyParked.id, unsaved: unsaved.id)

        #expect(disk.store.wipe(parkingActivitiesOf: WipeValues.account, at: WipeValues.now), "parked rows aren't a failure")

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
    /// delete after the wipe is the control: it proves the log shows such a line. Markers in the same log split the two,
    /// because a log entry's date runs milliseconds behind `Date()`, which put the wipe's lines before a date taken
    /// first and hid them.
    @Test func noBatchDeleteIsTriedOnSessionRows() async throws {
        let run = UUID().uuidString
        let disk = try StoreOnDisk()
        disk.session(checked: true)
        let control = try StoreOnDisk()
        control.session()

        Self.log.notice("\(run, privacy: .public) wipe")
        disk.store.wipe()
        Self.log.notice("\(run, privacy: .public) control")
        do {
            try control.store.context.delete(model: LocalSet.self)
            withKnownIssue("This OS doesn't refuse the batch delete, so this guard has no line to look for") {
                Issue.record("`everyRowGoesThroughTheContext` still runs; look at this test again")
            }
            return
        } catch {}
        Self.log.notice("\(run, privacy: .public) end")

        let lines = await Self.logLines(of: run)
        let wipeLine = try #require(lines.firstIndex(of: "\(run) wipe"))
        let controlLine = try #require(lines.firstIndex(of: "\(run) control"))
        #expect(wipeLine < controlLine)
        #expect(!lines[wipeLine..<controlLine].contains(where: Self.isFailedBatchDelete), "no line from the wipe")
        #expect(lines[controlLine...].contains(where: Self.isFailedBatchDelete), "the control's line")
    }

    private static let log = Logger(subsystem: "dev.timkrebs.ryft.tests", category: "wipe")

    private nonisolated static func isFailedBatchDelete(_ line: String) -> Bool { line.contains("Batch delete failed") }

    /// `run`'s markers and every failed batch delete, oldest first, up to the `end` marker that says the snapshot is
    /// complete. Off the main actor: reading the log takes seconds, which real-clock tests beside this one would feel.
    @concurrent
    private nonisolated static func logLines(of run: String) async -> [String] {
        let since = Date().addingTimeInterval(-60)
        let matching = NSPredicate(format: "composedMessage CONTAINS %@ OR composedMessage CONTAINS %@", run, "Batch delete failed")
        var lines: [String] = []
        for _ in 0..<10 {
            if let store = try? OSLogStore(scope: .currentProcessIdentifier),
               let entries = try? store.getEntries(at: store.position(date: since), matching: matching) {
                lines = entries.map(\.composedMessage)
            }
            if lines.contains("\(run) end") { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return lines
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
        rig.store.enqueue(.put, sessionID: rig.session.id, account: "test")
        #expect(rig.store.pendingOps().count == 1)
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

    // MARK: a wipe that doesn't reach the file

    @Test(arguments: WipeValues.parkings)
    func aRefusedSaveIsReported(_ parking: String?) throws {
        let disk = try StoreOnDisk()
        disk.session(checked: true)
        try disk.refuseDeletes()
        #expect(!disk.store.wipe(parkingActivitiesOf: parking))
        #expect(try disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6), "the refusal held")
        try disk.allowDeletes()
        #expect(disk.store.wipe(parkingActivitiesOf: parking), "what's pending goes with the next one")
        try disk.expectNothingLeft()
    }

    // MARK: what the result says

    /// Every table with a row, as a real account's store can be, and then with nothing to do. A table whose delete always
    /// threw (the session tables' does) would report every sign-out as failed.
    @Test(arguments: WipeValues.parkings)
    func aHealthyStoreReportsAWipe(_ parking: String?) throws {
        let disk = try StoreOnDisk()
        #expect(Set(WipedTable.allCases.map(\.rawValue)) == Set(TrainStore.schema.entities.map(\.name)), "every table is here")
        disk.fill()
        #expect(try disk.inFile.allSatisfy { $0.value == 1 }, "a row of each")

        #expect(disk.store.wipe(parkingActivitiesOf: parking))
        #expect(try disk.inFile.allSatisfy { $0.value == 0 })
        #expect(disk.store.wipe(parkingActivitiesOf: parking), "and a store with nothing in it")
    }

    /// The case the final save can't speak for: it has nothing to do and succeeds, while the file holds the rows. A
    /// HealthKit-only account has only these.
    @Test(arguments: [WipedTable.cachedDay, .cachedDocument], WipeValues.parkings)
    func aRefusedDeleteIsReportedWithNothingToSave(_ table: WipedTable, _ parking: String?) throws {
        let disk = try StoreOnDisk()
        disk.fill([table])
        try disk.refuseDeletes(of: table)

        #expect(!disk.store.wipe(parkingActivitiesOf: parking))
        #expect(!disk.store.context.hasChanges, "the save had nothing to do")
        #expect(try disk.inFile[table] == 1, "the refusal held")

        try disk.allowDeletes()
        #expect(disk.store.wipe(parkingActivitiesOf: parking))
        #expect(try disk.inFile[table] == 0)
    }

    /// No table's result goes unread, whatever else there is to save, and a refusal stops nothing after it.
    @Test(arguments: WipedTable.allCases, WipeValues.parkings)
    func aRefusalOfAnyTableIsReportedAndTheRestGoes(_ table: WipedTable, _ parking: String?) throws {
        let disk = try StoreOnDisk()
        disk.fill()
        try disk.refuseDeletes(of: table)

        #expect(!disk.store.wipe(parkingActivitiesOf: parking))

        let left = try disk.inFile
        if table.goesInTheSave(parking: parking) {
            #expect(left[table] == 1, "the refusal held")
        } else {
            #expect(left.filter { $0.value != 0 } == [table: 1], "the rest went, and the final save landed")
        }
    }

    @Test(arguments: WipedTable.fetched, WipeValues.parkings)
    func aFetchThatFailsIsReported(_ table: WipedTable, _ parking: String?) throws {
        let disk = try StoreOnDisk()
        try disk.hide(table)
        #expect(!disk.store.wipe(parkingActivitiesOf: parking))
        try disk.bringBack(table)
        #expect(disk.store.wipe(parkingActivitiesOf: parking))
    }

    /// Which chunks are parked work is read from the activities, so with no answer every chunk stays, the other
    /// account's too, until another account's wipe or this account's return. A kept chunk is the only copy of that track.
    @Test func aFailedReadTakesNoParkedTrack() throws {
        let disk = try StoreOnDisk()
        let unsent = activity(), theirs = activity("account-b")
        disk.store.context.insert(unsent)
        disk.store.context.insert(theirs)
        disk.store.context.insert(chunk(of: unsent))
        disk.store.context.insert(chunk(of: theirs))
        disk.store.save()
        let id = unsent.id
        try disk.hide(.localActivity)

        #expect(!disk.store.wipe(parkingActivitiesOf: WipeValues.account, at: WipeValues.now))
        try disk.bringBack(.localActivity)
        #expect(try disk.inFile[.activityTrackChunk] == 2)

        #expect(disk.store.wipe(parkingActivitiesOf: WipeValues.account, at: WipeValues.now))
        let chunks = try ModelContext(disk.store.container).fetch(FetchDescriptor<ActivityTrackChunk>())
        #expect(chunks.map(\.activityID) == [id])
    }

    /// Parked marks wait for the final save like everything else, and a failed delete must not cost them.
    @Test func aRefusalStillParksTheActivities() throws {
        let disk = try StoreOnDisk()
        let unsent = activity(), night = night("2026-10-01")
        disk.store.context.insert(unsent)
        disk.store.context.insert(night)
        disk.fill([.cachedDay])
        try disk.refuseDeletes(of: .cachedDay)

        #expect(!disk.store.wipe(parkingActivitiesOf: WipeValues.account, at: WipeValues.now))

        let context = ModelContext(disk.store.container)
        #expect(try context.fetch(FetchDescriptor<LocalActivity>()).first?.parkedAt == WipeValues.now)
        #expect(try context.fetch(FetchDescriptor<LocalManualSleep>()).first?.parkedAt == WipeValues.now)
    }

    /// Memory that was asked for has no file to leave behind; memory after a failed open does.
    @Test func aStoreThatLostItsFileNeverReportsAWipe() throws {
        let disk = try StoreOnDisk()
        let inTheWay = disk.folder.appendingPathComponent("file")
        try Data([1]).write(to: inTheWay)
        let lost = TrainStore(url: inTheWay.appendingPathComponent("Train.store"))
        #expect(!lost.isDurable)
        #expect(!lost.wipe())
        #expect(!lost.wipe(parkingActivitiesOf: "account-a"))
        #expect(TrainStore(inMemory: true).wipe())
        #expect(disk.store.wipe())
    }

    @Test(arguments: WipeValues.endings)
    func aWipeThatReachesTheFileClearsTheAccount(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        await rig.end(ending)
        #expect(rig.lastUser == nil)
        try rig.disk.expectNothingLeft()
    }

    /// The app acts wiped, and may be killed before anything saves again. The kept id is all that's left to say so: a
    /// sign-in that found none wouldn't wipe, and the next account would get this workout and upload it as its own.
    @Test(arguments: WipeValues.endings)
    func aRefusedWipeKeepsTheAccountSoTheNextOneWipesAgain(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try rig.disk.refuseDeletes()

        await rig.end(ending)
        #expect(rig.auth.accountID == nil)
        #expect(rig.lastUser == WipeValues.accountA.uuidString)
        #expect(try rig.disk.inFreshContext == .init(sessions: 1, exercises: 2, sets: 6))

        rig.relaunch(signedInAs: nil)
        try rig.disk.allowDeletes()
        await rig.signIn(WipeValues.accountB)

        #expect(rig.auth.accountID == WipeValues.accountB.uuidString)
        #expect(rig.lastUser == WipeValues.accountB.uuidString)
        try rig.disk.expectNothingLeft()
    }

    /// Nothing for the save to fail on: the account's day stays in the file and the next account must not find it.
    @Test(arguments: WipeValues.endings)
    func aRefusedDeleteKeepsTheAccountSoTheNextOneWipesAgain(_ ending: AuthService.SignOutReason) async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.fill([.cachedDay])
        try rig.disk.refuseDeletes(of: .cachedDay)

        await rig.end(ending)
        #expect(rig.auth.accountID == nil)
        #expect(rig.lastUser == WipeValues.accountA.uuidString)
        #expect(try rig.disk.inFile[.cachedDay] == 1)

        rig.relaunch(signedInAs: nil)
        try rig.disk.allowDeletes()
        await rig.signIn(WipeValues.accountB)

        #expect(rig.auth.accountID == WipeValues.accountB.uuidString)
        #expect(rig.lastUser == WipeValues.accountB.uuidString)
        #expect(try rig.disk.inFile[.cachedDay] == 0)
    }

    /// Signed in over another account: a token refresh must not write the new id over the one that makes the next
    /// launch wipe again.
    @Test func aRefusedWipeAtSignInIsTriedAgainAtTheNextLaunch() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try rig.disk.refuseDeletes()

        await rig.signIn(WipeValues.accountB)
        #expect(rig.auth.accountID == WipeValues.accountB.uuidString)
        #expect(rig.lastUser == WipeValues.accountA.uuidString)
        rig.client.emit(.tokenRefreshed, .preview(id: WipeValues.accountB))
        await rig.settle()
        #expect(rig.lastUser == WipeValues.accountA.uuidString)

        rig.relaunch(signedInAs: WipeValues.accountB)
        try rig.disk.allowDeletes()
        rig.relaunch(signedInAs: WipeValues.accountB)
        #expect(rig.lastUser == WipeValues.accountB.uuidString)
        try rig.disk.expectNothingLeft()
    }

    /// The session ended while the platform deleted: its wipe cleared the id, and the deletion's own wipe, refused,
    /// puts it back.
    @Test func aRefusedWipeAfterADeletionKeepsTheAccount() async throws {
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.duringDeletion = { [weak rig] in
            await rig?.auth.rejectedAfterRefresh()
            #expect(rig?.lastUser == nil)
            rig?.disk.session(checked: true)
            try? rig?.disk.refuseDeletes()
        }
        #expect(await rig.auth.deleteAccount())
        #expect(rig.lastUser == WipeValues.accountA.uuidString)
    }
}

/// A real `AuthService` on a store on disk, and a relaunch: a new service and store on the same file and defaults, as
/// after a kill. Nothing of the old process's pending changes carries over.
@MainActor
final class WipingAuth {
    let disk: StoreOnDisk
    let defaults = UserDefaults(suiteName: "ryft.tests.wipe.\(UUID().uuidString)") ?? .standard
    let clock = TestClock(now: WipeValues.now)
    private(set) var client: MockAuthClient
    private(set) var auth: AuthService
    var duringDeletion: (@MainActor () async -> Void)?
    /// Runs as the store's wipe starts, with what it was asked for.
    var atTheWipe: (@MainActor (AuthService.Wipe) -> Void)?

    init(signedInAs account: UUID) throws {
        let disk = try StoreOnDisk()
        self.disk = disk
        client = MockAuthClient(session: .preview(id: account))
        auth = AuthService(client: client, settings: Settings(defaults: defaults), defaults: defaults,
                           wipeLocalData: { _ in true },
                           deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                           postAppleAuthorization: { _ in })
        rewire()
    }

    var lastUser: String? { defaults.string(forKey: AccountScope.defaultsKey) }

    /// In the store's folder, so it goes with it.
    var ledgerFile: URL { disk.folder.appendingPathComponent("account-wipe.json") }
    /// What the next launch would read.
    var ledgerOnDisk: OwedWipe? { WipeLedger(file: ledgerFile).entry }

    /// The hooks read `duringDeletion` and `atTheWipe` when they run. A new ledger, as in a new process: nothing of the
    /// old one's memory carries over.
    private func rewire() {
        let disk = disk, clock = clock
        auth = AuthService(client: client, settings: Settings(defaults: defaults), defaults: defaults,
                           wipeLocalData: { [weak self] wipe in
                               self?.atTheWipe?(wipe)
                               return disk.store.wipe(parkingActivitiesOf: wipe.parking, at: wipe.since)
                           },
                           deleteRemoteAccount: { [weak self] in
                               await self?.duringDeletion?()
                               return AccountDeleted(status: "deleted", authUserDeleted: true)
                           },
                           postAppleAuthorization: { _ in },
                           ledger: WipeLedger(file: ledgerFile), now: { clock.now() })
    }

    func relaunch(signedInAs account: UUID?) {
        disk.relaunch()
        client = MockAuthClient(session: account.map { .preview(id: $0) })
        rewire()
    }

    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func signIn(_ id: UUID) async {
        client.signInSession = .preview(id: id)
        _ = await auth.logIn(email: "synthetic@example.com", password: "0123456789")
        await settle()
    }

    func end(_ ending: AuthService.SignOutReason) async {
        if case .accountDeleted = ending {
            await auth.deleteAccount()
        } else {
            await auth.signOut(reason: ending)
        }
        await settle()
    }
}
