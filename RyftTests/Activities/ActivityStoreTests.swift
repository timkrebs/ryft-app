import Foundation
import SwiftData
import Testing
@testable import Ryft

/// A store on an in-memory `TrainStore`, whose signed-in account a test switches.
@MainActor
private final class Harness {
    var account: String? = "account-a"
    var demo = false
    let clock = TestClock()
    let persistence = TrainStore(inMemory: true)
    private(set) lazy var store = ActivityStore(store: persistence, clock: clock,
                                                account: { [unowned self] in self.account },
                                                isDemo: { [unowned self] in self.demo })

    /// `hour:minute` local time on the test clock's day, `days` later.
    func at(_ hour: Int, _ minute: Int = 0, days: Int = 0) -> Date {
        let day = DayFormat.shift(clock.now(), days: days)
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    func day(_ days: Int = 0) -> String { DayFormat.string(from: DayFormat.shift(clock.now(), days: days)) }

    func run(_ hour: Int, minutes: Int = 30, days: Int = 0, notes: String = "") -> ActivityDraft {
        let start = at(hour, days: days)
        return ActivityDraft(sport: .running, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                             distanceM: 5_000, perceivedEffort: 5, notes: notes)
    }

    /// A recorded run saved by A4's finish, written straight into the store.
    @discardableResult
    func insertRecorded(account: String? = nil, sport: Sport = .trailRunning, revision: Int = 1,
                        phase: String = LocalActivity.savedPhase) -> UUID {
        let start = at(7)
        let row = LocalActivity(account: account ?? self.account ?? "-", sport: sport, origin: .recorded, phase: phase,
                                start: start, end: start.addingTimeInterval(3_600), movingSec: 3_300, distanceM: 10_200,
                                ascentM: 240, localRevision: revision, createdAt: clock.now())
        persistence.context.insert(row)
        persistence.save()
        return row.id
    }

    func insertChunks(for id: UUID, account: String, count: Int = 3) {
        for seq in 0..<count {
            persistence.context.insert(ActivityTrackChunk(activityID: id, account: account, seq: seq, kind: .profile,
                                                          data: Data([1, 2, 3]), count: 30, first: clock.now(),
                                                          last: clock.now()))
        }
        persistence.save()
    }

    func insertSleep(day: String, account: String) {
        let wake = at(7)
        persistence.context.insert(LocalManualSleep(day: day, account: account, bed: wake.addingTimeInterval(-8 * 3600),
                                                    wake: wake))
        persistence.save()
    }

    func count<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? persistence.context.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    func chunks(of id: UUID) -> Int {
        (try? persistence.context.fetchCount(FetchDescriptor<ActivityTrackChunk>(
            predicate: #Predicate { $0.activityID == id }))) ?? -1
    }
}

@Suite("Activity store: documents")
@MainActor
struct ActivityStoreDocumentTests {
    @Test func aManualSaveIsARevisionOneDocumentOnItsDay() throws {
        let h = Harness()
        let saved = try #require(h.store.save(manual: h.run(7, notes: "Easy loop")))
        #expect(saved.account == "account-a" && saved.origin == .manual && saved.sport == .running)
        #expect(saved.isSaved && saved.localRevision == 1 && saved.confirmedRevision == 0 && saved.needsUpload)
        #expect(saved.movingSec == 1_800 && saved.distanceM == 5_000 && saved.perceivedEffort == 5)
        #expect(saved.createdAt == h.clock.now() && saved.updatedAt == h.clock.now())
        #expect(saved.storedUploadState == .pending(.queued))
        #expect(h.store.snapshots(onDay: h.day()) == [saved])
        #expect(h.store.snapshot(id: saved.id) == saved)
        #expect(h.store.unconfirmed() == [saved])
        #expect(h.store.snapshots(onDay: h.day(1)).isEmpty)
    }

    @Test func anActivityBelongsToTheDayItStarts() throws {
        let h = Harness()
        let late = try #require(h.store.save(manual: ActivityDraft(sport: .walking, start: h.at(23, 30),
                                                                    end: h.at(0, 30, days: 1))))
        let early = try #require(h.store.save(manual: h.run(6, days: 1)))
        #expect(h.store.snapshots(onDay: h.day()).map(\.id) == [late.id])
        #expect(h.store.snapshots(onDay: h.day(1)).map(\.id) == [early.id])
        #expect(h.store.snapshots(onDay: "not a day").isEmpty)
    }

    @Test func theDaysSnapshotsAreInStartOrder() {
        let h = Harness()
        let evening = h.store.save(manual: h.run(18))
        let morning = h.store.save(manual: h.run(6))
        #expect(h.store.snapshots(onDay: h.day()).map(\.id) == [morning?.id, evening?.id].compactMap { $0 })
    }

    @Test func anEditBumpsTheRevisionOnlyWhenSomethingChanged() throws {
        let h = Harness()
        let draft = h.run(7)
        let saved = try #require(h.store.save(manual: draft))
        h.clock.advance(by: .seconds(60))
        let same = try #require(h.store.update(saved.id, draft))
        #expect(same.localRevision == 1 && same.updatedAt == saved.updatedAt)
        var edited = draft
        edited.sport = .cycling
        edited.end = draft.end.addingTimeInterval(600)
        edited.notes = "With the club"
        let updated = try #require(h.store.update(saved.id, edited))
        #expect(updated.localRevision == 2 && updated.updatedAt == h.clock.now())
        #expect(updated.sport == .cycling && updated.movingSec == 2_400 && updated.notes == "With the club")
        #expect(h.store.unconfirmed().map(\.localRevision) == [2])
    }

    @Test func aRecordedActivityKeepsWhatWasMeasured() throws {
        let h = Harness()
        let id = h.insertRecorded(sport: .trailRunning)
        let recorded = try #require(h.store.snapshot(id: id))
        // Another family, other times and distance: only effort and notes are taken.
        let other = ActivityDraft(sport: .cycling, start: h.at(9), end: h.at(10), distanceM: 1,
                                  perceivedEffort: 8, notes: "Muddy")
        let edited = try #require(h.store.update(id, other))
        #expect(edited.sport == .trailRunning && edited.start == recorded.start && edited.end == recorded.end)
        #expect(edited.distanceM == 10_200 && edited.movingSec == 3_300)
        #expect(edited.perceivedEffort == 8 && edited.notes == "Muddy" && edited.localRevision == 2)
        // The same family: the sport changes too.
        var sameFamily = other
        sameFamily.sport = .hiking
        #expect(h.store.update(id, sameFamily)?.sport == .hiking)
    }

    @Test func aRecordingInProgressCantBeEditedAndIsntUploaded() {
        let h = Harness()
        let id = h.insertRecorded(revision: 0, phase: "recording")
        #expect(h.store.update(id, h.run(7)) == nil)
        #expect(h.store.unconfirmed().isEmpty)
        #expect(h.store.snapshot(id: id)?.storedUploadState == nil)
        #expect(h.store.snapshots(onDay: h.day()).map(\.id) == [id])
    }

    @Test func confirmRecordsTheSentRevisionAndAnEditInFlightStaysUnconfirmed() throws {
        let h = Harness()
        let saved = try #require(h.store.save(manual: h.run(7)))
        // Revision 1 goes out; the user edits meanwhile.
        var draft = h.run(7)
        draft.notes = "Edited during the upload"
        h.store.update(saved.id, draft)
        #expect(h.store.confirm(saved.id, revision: 1))
        let afterFirst = try #require(h.store.snapshot(id: saved.id))
        #expect(afterFirst.confirmedRevision == 1 && afterFirst.needsUpload)
        #expect(h.store.unconfirmed().map(\.id) == [saved.id])
        // Revision 2's answer; a late answer for revision 1 changes nothing.
        #expect(h.store.confirm(saved.id, revision: 2))
        #expect(h.store.confirm(saved.id, revision: 1))
        let confirmed = try #require(h.store.snapshot(id: saved.id))
        #expect(confirmed.confirmedRevision == 2 && !confirmed.needsUpload && confirmed.storedUploadState == .confirmed)
        #expect(h.store.unconfirmed().isEmpty)
        // An answer can't confirm more than was saved.
        #expect(h.store.confirm(saved.id, revision: 9))
        #expect(h.store.snapshot(id: saved.id)?.confirmedRevision == 2)
    }

    @Test func aConfirmationClearsTheLastFailure() throws {
        let h = Harness()
        let saved = try #require(h.store.save(manual: h.run(7)))
        let row = try #require(try h.persistence.context.fetch(FetchDescriptor<LocalActivity>()).first)
        let attempt = UploadAttempt(at: h.clock.now(), request: .put, status: 503, code: nil, requestID: "req-1",
                                    kind: .transient)
        row.lastAttemptData = WireCoding.encode(attempt)
        h.persistence.save()
        #expect(h.store.snapshot(id: saved.id)?.lastAttempt == attempt)
        h.store.confirm(saved.id, revision: 1)
        #expect(h.store.snapshot(id: saved.id)?.lastAttempt == nil)
    }

    @Test func aTombstoneStaysUntilRemovedAndIsUploaded() throws {
        let h = Harness()
        let saved = try #require(h.store.save(manual: h.run(7)))
        h.store.confirm(saved.id, revision: 1)
        #expect(h.store.unconfirmed().isEmpty)
        h.clock.advance(by: .seconds(30))
        #expect(h.store.tombstone(saved.id))
        let tombstone = try #require(h.store.snapshot(id: saved.id))
        #expect(tombstone.isTombstone && tombstone.deletedAt == h.clock.now() && tombstone.needsUpload)
        #expect(tombstone.storedUploadState == .pending(.queued))
        #expect(h.store.unconfirmed().map(\.id) == [saved.id])
        // Still on its day (My Day hides it), and no longer editable.
        #expect(h.store.snapshots(onDay: h.day()).map(\.id) == [saved.id])
        #expect(h.store.update(saved.id, h.run(8)) == nil)
        // A second delete keeps the first time.
        h.clock.advance(by: .seconds(30))
        h.store.tombstone(saved.id)
        #expect(h.store.snapshot(id: saved.id)?.deletedAt == tombstone.deletedAt)
        h.store.remove(saved.id)
        #expect(h.store.snapshot(id: saved.id) == nil && h.store.unconfirmed().isEmpty)
    }

    @Test func unconfirmedIsInCreationOrder() {
        let h = Harness()
        let first = h.store.save(manual: h.run(18))
        h.clock.advance(by: .seconds(5))
        let second = h.store.save(manual: h.run(6))
        h.clock.advance(by: .seconds(5))
        let third = h.store.save(manual: h.run(12))
        #expect(h.store.unconfirmed().map(\.id) == [first?.id, second?.id, third?.id].compactMap { $0 })
    }

    @Test func removeDeletesTheRowAndOnlyItsChunks() {
        let h = Harness()
        let id = h.insertRecorded()
        let other = h.insertRecorded()
        h.insertChunks(for: id, account: "account-a")
        h.insertChunks(for: other, account: "account-a", count: 2)
        h.store.remove(id)
        #expect(h.store.snapshot(id: id) == nil && h.chunks(of: id) == 0)
        #expect(h.store.snapshot(id: other) != nil && h.chunks(of: other) == 2)
    }

    @Test func everyWriteBumpsTheRevision() throws {
        let h = Harness()
        var seen = h.store.revision
        func bumped() -> Bool {
            defer { seen = h.store.revision }
            return h.store.revision > seen
        }
        let saved = try #require(h.store.save(manual: h.run(7)))
        #expect(bumped())
        var draft = h.run(7)
        draft.notes = "x"
        h.store.update(saved.id, draft)
        #expect(bumped())
        h.store.confirm(saved.id, revision: 2)
        #expect(bumped())
        h.store.tombstone(saved.id)
        #expect(bumped())
        h.store.remove(saved.id)
        #expect(bumped())
        h.store.purge(notBelongingTo: "account-a")
        #expect(bumped())
    }

    @Test func theSnapshotsDocumentIsTheWireActivity() throws {
        let h = Harness()
        let saved = try #require(h.store.save(manual: h.run(7, notes: "Loop")))
        let a = saved.activity
        #expect(a.id == saved.id && a.sport == .running && a.origin == .manual)
        #expect(a.start == saved.start && a.end == saved.end && a.movingSec == 1_800 && a.distanceM == 5_000)
        #expect(a.perceivedEffort == 5 && a.notes == "Loop" && a.clientUpdatedAt == saved.updatedAt)
        #expect(a.route == nil && a.hrSamples == nil && a.splits == nil && a.strain == nil)
        let empty = try #require(h.store.save(manual: h.run(9)))
        #expect(empty.activity.notes == nil)
    }
}

@Suite("Activity store: accounts")
@MainActor
struct ActivityStoreAccountTests {
    @Test func anotherAccountsRowsAreInvisible() throws {
        let h = Harness()
        let a = try #require(h.store.save(manual: h.run(7)))
        let aRecorded = h.insertRecorded()
        h.insertSleep(day: h.day(), account: "account-a")
        h.account = "account-b"
        #expect(h.store.snapshots(onDay: h.day()).isEmpty)
        #expect(h.store.unconfirmed().isEmpty)
        #expect(h.store.snapshot(id: a.id) == nil && h.store.snapshot(id: aRecorded) == nil)
        #expect(h.store.manualSleep(onDay: h.day()) == nil)
        // B can't write to A's rows either.
        #expect(h.store.update(a.id, h.run(8)) == nil)
        #expect(!h.store.tombstone(a.id))
        #expect(!h.store.confirm(a.id, revision: 1))
        h.store.remove(a.id)
        let b = try #require(h.store.save(manual: h.run(9)))
        #expect(b.account == "account-b")
        #expect(h.store.snapshots(onDay: h.day()).map(\.id) == [b.id])
        h.account = "account-a"
        #expect(Set(h.store.snapshots(onDay: h.day()).map(\.id)) == [a.id, aRecorded])
        #expect(h.store.snapshot(id: a.id)?.isTombstone == false && h.store.snapshot(id: a.id)?.confirmedRevision == 0)
        #expect(h.store.manualSleep(onDay: h.day())?.day == h.day())
    }

    @Test func signedOutReadsNothingAndWritesNothing() {
        let h = Harness()
        h.store.save(manual: h.run(7))
        h.insertSleep(day: h.day(), account: "account-a")
        h.account = nil
        #expect(h.store.account == nil)
        #expect(h.store.snapshots(onDay: h.day()).isEmpty)
        #expect(h.store.unconfirmed().isEmpty)
        #expect(h.store.manualSleep(onDay: h.day()) == nil)
        #expect(h.store.save(manual: h.run(9)) == nil)
        #expect(h.count(LocalActivity.self) == 1)
    }

    @Test func purgeDeletesEveryOtherAccountsRowsChunksAndSleep() throws {
        let h = Harness()
        let a = try #require(h.store.save(manual: h.run(7)))
        let aRecorded = h.insertRecorded(account: "account-a")
        h.insertChunks(for: aRecorded, account: "account-a")
        h.insertSleep(day: h.day(-1), account: "account-a")
        let bRecorded = h.insertRecorded(account: "account-b")
        h.insertChunks(for: bRecorded, account: "account-b", count: 2)
        h.insertSleep(day: h.day(), account: "account-b")

        let removed = h.store.purge(notBelongingTo: "account-b")
        #expect(removed == 3)
        h.account = "account-b"
        #expect(h.store.snapshots(onDay: h.day()).map(\.id) == [bRecorded])
        #expect(h.store.manualSleep(onDay: h.day()) != nil)
        #expect(h.chunks(of: bRecorded) == 2 && h.chunks(of: aRecorded) == 0)
        #expect(h.count(LocalActivity.self) == 1 && h.count(LocalManualSleep.self) == 1)
        #expect(h.count(ActivityTrackChunk.self) == 2)
        h.account = "account-a"
        #expect(h.store.snapshot(id: a.id) == nil && h.store.manualSleep(onDay: h.day(-1)) == nil)
    }

    /// One night per account and day: another account's row for the same day is a second row, not overwritten
    /// (privacy S-1).
    @Test func twoAccountsCanEachHaveTheSameNight() {
        let h = Harness()
        h.insertSleep(day: h.day(), account: "account-a")
        h.insertSleep(day: h.day(), account: "account-b")
        #expect(h.count(LocalManualSleep.self) == 2)
        #expect(h.store.manualSleep(onDay: h.day())?.day == h.day())
        h.account = "account-b"
        #expect(h.store.manualSleep(onDay: h.day())?.day == h.day())
        h.store.purge(notBelongingTo: "account-b")
        #expect(h.count(LocalManualSleep.self) == 1)
        h.account = "account-a"
        #expect(h.store.manualSleep(onDay: h.day()) == nil)
    }

    @Test func purgeOfNobodyDeletesEverything() {
        let h = Harness()
        h.store.save(manual: h.run(7))
        let recorded = h.insertRecorded(account: "account-b")
        h.insertChunks(for: recorded, account: "account-b")
        h.insertSleep(day: h.day(), account: "account-b")
        #expect(h.store.purge(notBelongingTo: nil) == 3)
        #expect(h.count(LocalActivity.self) == 0 && h.count(ActivityTrackChunk.self) == 0)
        #expect(h.count(LocalManualSleep.self) == 0)
    }

    @Test func purgeActsOnTheAccountsStoreInDemoMode() {
        let h = Harness()
        h.insertRecorded(account: "account-b")
        h.demo = true
        h.store.save(manual: h.run(7))
        #expect(h.store.purge(notBelongingTo: "account-a") == 1)
        #expect(h.count(LocalActivity.self) == 0)
        // Demo's own row is untouched.
        #expect(h.store.snapshots(onDay: h.day()).count == 1)
    }

    @Test func theSignOutWipeDeletesActivitiesChunksAndSleep() {
        let h = Harness()
        h.store.save(manual: h.run(7))
        let recorded = h.insertRecorded()
        h.insertChunks(for: recorded, account: "account-a")
        // An orphan: its row is gone already.
        h.insertChunks(for: UUID(), account: "account-a")
        h.insertSleep(day: h.day(), account: "account-a")
        h.persistence.wipe()
        h.store.accountChanged()
        #expect(h.count(LocalActivity.self) == 0 && h.count(ActivityTrackChunk.self) == 0)
        #expect(h.count(LocalManualSleep.self) == 0)
        #expect(h.store.snapshots(onDay: h.day()).isEmpty)
    }
}

@Suite("Activity store: storage")
@MainActor
struct ActivityStoreStorageTests {
    @Test func anInMemoryStoreIsNotDurable() {
        let h = Harness()
        #expect(!h.persistence.isDurable)
        #expect(!h.store.isDurable)
    }

    @Test func demoDataUsesAStoreOfItsOwn() throws {
        let h = Harness()
        let real = try #require(h.store.save(manual: h.run(7)))
        h.demo = true
        #expect(h.store.account == ActivityStore.demoAccount)
        #expect(h.store.snapshots(onDay: h.day()).isEmpty)
        let demo = try #require(h.store.save(manual: h.run(9)))
        #expect(demo.account == ActivityStore.demoAccount)
        #expect(h.store.snapshots(onDay: h.day()).map(\.id) == [demo.id])
        #expect(!h.store.isDurable)
        // Nothing typed in demo mode reaches the account's store.
        #expect(h.count(LocalActivity.self) == 1)
        h.demo = false
        #expect(h.store.snapshots(onDay: h.day()).map(\.id) == [real.id])
    }

    @Test func anAccountChangeStartsDemoDataOver() throws {
        let h = Harness()
        h.demo = true
        _ = try #require(h.store.save(manual: h.run(7, notes: "A's note")))
        let revision = h.store.revision
        h.store.accountChanged()
        #expect(h.store.revision > revision)
        #expect(h.store.snapshots(onDay: h.day()).isEmpty)
    }

    /// Privacy S-3: what account A typed in demo mode, on the phone and on the demo platform, is gone when A
    /// signs out (`AppState.reset`), before anyone else uses demo data.
    @Test func aDemoNoteIsGoneAfterTheReset() async throws {
        let clock = TestClock()
        let api = MockPlatformAPI(activities: .demoSource())
        api.now = { clock.now() }
        let env = AppEnvironment(
            settings: .shared, health: MockHealthStore(), liveAPI: api, demoAPI: api, auth: .preview(),
            persistence: TrainStore(inMemory: true), clock: clock, notifier: MockNotifier(), flags: StaticFlags(),
            connectivity: .preview(online: true),
            defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard, demoOverride: true)
        let state = AppState(env: env)
        let start = clock.now().addingTimeInterval(-3_600)
        let note = try #require(env.activities.save(manual: ActivityDraft(sport: .yoga, start: start,
                                                                           end: start.addingTimeInterval(1_800),
                                                                           notes: "A's private note")))
        _ = try await api.putActivity(note.activity)
        let day = DayFormat.string(from: start)
        #expect(env.activities.snapshots(onDay: day).map(\.id) == [note.id])
        state.accountChanged(from: "account-a")
        #expect(env.activities.snapshots(onDay: day).isEmpty)
        await #expect(throws: APIError.self) { try await api.activity(id: note.id) }
        #expect(api.activitySource.puts.isEmpty)
    }

    @Test func theEnvironmentsStoreFollowsTheSignedInAccount() {
        let env = AppEnvironment.test()
        #expect(env.activities.account == env.auth.accountID)
        #expect(env.activities.account != nil)
        #expect(env.activities.save(manual: ActivityDraft(sport: .yoga, start: env.clock.now(),
                                                          end: env.clock.now().addingTimeInterval(1_800))) != nil)
        #expect(env.activities.unconfirmed().count == 1)
        #expect(!env.activities.isDurable)
        let signedOut = AppEnvironment.test(auth: .preview(signedIn: false))
        #expect(signedOut.activities.account == nil)
        #expect(signedOut.activities.unconfirmed().isEmpty)
    }
}
