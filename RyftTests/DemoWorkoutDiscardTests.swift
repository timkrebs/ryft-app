import Foundation
import SwiftData
import Testing
@testable import Ryft

// P1b ticket 2 (docs/work/2026-11-18-ios17-demo-exit/design.md §6.2, §6.3, §6.9, ADR 0019): the workouts started in the
// demo are on one list, and ending the demo discards them with their ops, sending nothing; an account's workout stays.
// The list is seeded once for workouts logged before it. Synthetic values only.

/// Thrown by a store that can't be read (`TrainSyncService.fetchSessions`).
private struct StoreUnreadable: Error {}

@Suite("P1b: the demo's workouts are discarded when it ends", .serialized)
@MainActor
struct DemoWorkoutDiscardTests {
    // MARK: the list

    @Test func aSessionStartedInTheDemoIsOnTheListAndOneStartedForTheAccountIsNot() throws {
        let rig = DemoTrainRig()
        let demo = rig.startWorkout("Demo")
        #expect(rig.list == [demo.id.uuidString])
        rig.finishLocally(demo)

        rig.demo = false
        let account = rig.startWorkout("Account")
        #expect(rig.list == [demo.id.uuidString])
        #expect(try rig.sync.fetchDemoSessions().map(\.id) == [demo.id])
        #expect(try !rig.sync.fetchDemoSessions().contains { $0.id == account.id })
    }

    /// The list is never trusted on its own: an id the store doesn't have isn't a workout.
    @Test func theListCountsOnlyWhatTheStoreHas() throws {
        let rig = DemoTrainRig()
        rig.defaults.set([UUID().uuidString], forKey: TrainSyncService.demoSessionsKey)
        rig.relaunch()
        #expect(rig.sync.hasDemoSessions)
        #expect(try rig.sync.fetchDemoSessions().isEmpty)
        #expect(rig.coordinator.demoWorkouts == nil)
    }

    @Test func theWorkoutsCountFinishedOnesAndTheOneInProgress() {
        let rig = DemoTrainRig()
        #expect(rig.coordinator.demoWorkouts == nil)
        rig.finishLocally(rig.startWorkout("One"))
        #expect(rig.coordinator.demoWorkouts == DemoWorkouts(count: 1))
        rig.startWorkout("Two")
        #expect(rig.coordinator.demoWorkouts == DemoWorkouts(count: 2))
    }

    /// Every way a workout starts: what the factory saves first already finds its id on the list (review R4). A kill in
    /// between leaves an id the store doesn't have, which nothing counts.
    @Test(arguments: ["empty", "today", "planDay", "repeat"])
    func theIdIsListedBeforeTheRowIsSaved(_ start: String) throws {
        let rig = DemoTrainRig()
        let listed = Recorded<[String]>()
        // Posted on the saving thread, the main one here.
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: rig.store.context,
                                                              queue: nil) { _ in
            MainActor.assumeIsolated { listed.append(rig.list) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        switch start {
        case "empty": rig.coordinator.startEmpty()
        case "today": rig.coordinator.startFromToday()
        case "planDay": rig.coordinator.start(day: MockTrain.lowerA)
        default: rig.coordinator.repeatSession(try #require(MockTrain.history.last))
        }
        let id = try #require(rig.coordinator.active?.id)
        #expect(!listed.all.isEmpty)
        #expect(listed.all.first == [id.uuidString])
        #expect(rig.list == [id.uuidString])
    }

    // MARK: the discard (AC7)

    @Test func theDiscardTakesTheLiveWorkoutAndTheFinishedOnesSentOrNotAndSendsNothing() async throws {
        let rig = DemoTrainRig()
        // Finished and sent to the demo's platform.
        let sent = rig.startWorkout("Sent")
        await rig.sync.flush()
        #expect(sent.uploaded && sent.uploadedTo == TrainSyncService.demoOwner)
        rig.finishLocally(sent)
        // Finished, never sent: its PUT still queued.
        let unsent = rig.startWorkout("Unsent")
        rig.finishLocally(unsent)
        // In progress, open.
        let live = rig.startWorkout("Live")
        #expect(rig.coordinator.live?.session.id == live.id)
        #expect(rig.coordinator.active?.id == live.id)
        let ids: Set<UUID> = [sent.id, unsent.id, live.id]
        #expect(!rig.ops(ids).isEmpty)
        let before = await rig.source.calls.count

        rig.coordinator.discardDemoWorkouts()

        #expect(try rig.storedSessions(ids) == 0)
        #expect(rig.ops(ids).isEmpty)
        #expect(!rig.store.pendingOps().contains { $0.kind == .delete }) // no DELETE queued
        #expect(rig.coordinator.active == nil)
        #expect(rig.coordinator.live == nil)
        #expect(rig.activity.ends == 1)
        #expect(rig.list.isEmpty)
        #expect(rig.store.completedSessions().isEmpty) // Strain, My Day and Train's history read these
        #expect(rig.coordinator.demoWorkouts == nil)

        // Nothing for them reaches the platform afterwards, signed out or signed in.
        rig.demo = false
        rig.account = nil
        await rig.sync.flush()
        rig.account = DemoTrainRig.account
        await rig.sync.flush()
        #expect(await rig.source.calls.count == before)
        #expect(await rig.source.requests(for: ids).count == 1) // the PUT the demo's platform got before
    }

    @Test func theSummaryOfAFinishedDemoWorkoutGoesToo() {
        let rig = DemoTrainRig()
        let s = rig.startWorkout("Done")
        rig.finishLocally(s)
        rig.coordinator.summary = FinishSummary(sessionID: s.id, completed: nil)
        rig.coordinator.discardDemoWorkouts()
        #expect(rig.coordinator.summary == nil)
    }

    /// What's open is checked against the list, not against what the store found (review R6): a summary of a listed
    /// workout whose row is already gone closes too.
    @Test func aSummaryGoesByTheListEvenWhenTheStoreHasNoRow() {
        let rig = DemoTrainRig()
        let s = rig.startWorkout("Gone")
        rig.finishLocally(s)
        let id = s.id
        rig.store.dropOps(for: id)
        rig.store.delete(s)
        rig.store.save()
        rig.coordinator.summary = FinishSummary(sessionID: id, completed: nil)

        #expect(rig.coordinator.discardDemoWorkouts())

        #expect(rig.coordinator.summary == nil)
        #expect(rig.list.isEmpty)
    }

    /// Fails closed (review R6): a store that can't be read changes nothing, open workout, rows, ops and list alike.
    @Test func aStoreThatCantBeReadDiscardsNothing() throws {
        let rig = DemoTrainRig()
        let finished = rig.startWorkout("Finished")
        rig.finishLocally(finished)
        let live = rig.startWorkout("Live")
        let ids: Set<UUID> = [finished.id, live.id]
        let ops = rig.ops(ids).map(\.seq)
        let list = rig.list
        rig.sync.fetchSessions = { _, _ in throw StoreUnreadable() }

        #expect(!rig.coordinator.discardDemoWorkouts())
        #expect(rig.coordinator.demoWorkouts == nil) // nothing to count: the switch goes straight to the exit

        #expect(rig.coordinator.live?.session.id == live.id)
        #expect(rig.coordinator.active?.id == live.id)
        #expect(rig.activity.ends == 0)
        #expect(try rig.storedSessions(ids) == 2)
        #expect(rig.ops(ids).map(\.seq) == ops)
        #expect(rig.list == list)
    }

    /// In memory after the file failed to open, the store can't say what the file still holds (review R5): the discard
    /// takes what it finds and drops only those ids; the rest stay listed for a launch that opens the file.
    @Test func aStoreThatLostItsFileDropsOnlyWhatItDeleted() throws {
        let disk = try DemoExitDisk()
        let inTheWay = disk.folder.appendingPathComponent("file")
        try Data([1]).write(to: inTheWay)
        let lost = TrainStore(url: inTheWay.appendingPathComponent("Train.store"))
        #expect(lost.lostItsFile)
        let rig = DemoTrainRig(store: lost)
        let found = rig.startWorkout("Found")
        rig.finishLocally(found)
        let onlyInTheFile = UUID()
        rig.defaults.set([found.id.uuidString, onlyInTheFile.uuidString], forKey: TrainSyncService.demoSessionsKey)
        rig.relaunch()

        #expect(rig.coordinator.discardDemoWorkouts())

        #expect(try rig.storedSessions([found.id]) == 0)
        #expect(rig.list == [onlyInTheFile.uuidString])
        #expect(rig.sync.demoSessionIDs == [onlyInTheFile])
    }

    /// On its file, an id the store doesn't have (a kill before the row was saved) is pruned with the rest.
    @Test func onItsFileTheListKeepsNothingTheStoreDoesntHave() throws {
        let disk = try DemoExitDisk()
        let rig = DemoTrainRig(store: TrainStore(url: disk.url))
        let s = rig.startWorkout("Saved")
        rig.finishLocally(s)
        rig.defaults.set([s.id.uuidString, UUID().uuidString], forKey: TrainSyncService.demoSessionsKey)
        rig.relaunch()

        #expect(rig.coordinator.discardDemoWorkouts())

        #expect(try rig.storedSessions([s.id]) == 0)
        #expect(rig.list.isEmpty)
        #expect(!rig.sync.hasDemoSessions)
    }

    /// The replay stops before anything is deleted: a demo `PUT` answered after the discard (with a 409, whose merge
    /// would read the deleted row's lists, a fatal error) touches nothing, and nothing goes after it.
    @Test func aDemoAnswerInFlightAtTheDiscardTouchesNothing() async throws {
        let rig = DemoTrainRig()
        await rig.source.holdPuts()
        let s = rig.startWorkout("Held")
        let doc = s.wire
        let id = s.id
        let replay = Task { await rig.sync.flush() }
        #expect(await eventually { rig.sync.isFlushing })
        var held = 0
        for _ in 0..<5_000 where held == 0 {
            held = await rig.source.heldCount
            if held == 0 { try? await Task.sleep(for: .milliseconds(2)) }
        }
        #expect(held == 1)

        rig.coordinator.discardDemoWorkouts()
        #expect(try rig.storedSessions([id]) == 0)
        await rig.source.release({ .conflict($0) }, for: doc)
        await replay.value
        // The answer resumed on the main actor and was dropped: no second round, no row brought back.
        for _ in 0..<20 { await Task.yield() }
        #expect(await rig.source.answered == 1)
        #expect(await rig.source.requests(for: [id]) == [.put(id)])
        #expect(try rig.storedSessions([id]) == 0)
        #expect(rig.store.pendingOps().isEmpty)
    }

    // MARK: the account's workout (AC9)

    /// A workout started for the account before Demo data was turned on, and logged during the demo, isn't on the list:
    /// beside a demo workout that goes, it stays, open, with its ops for the account.
    @Test func anAccountsWorkoutThatWentOnDuringTheDemoStays() throws {
        let rig = DemoTrainRig()
        rig.demo = false
        let account = rig.startWorkout("Account")
        let accountOps = rig.ops([account.id]).map(\.seq)
        #expect(!accountOps.isEmpty)
        rig.demo = true // Demo data on while it runs
        rig.sync.sessionChanged(account)
        let demo = rig.startWorkout("Demo")
        rig.finishLocally(demo)
        rig.coordinator.resume()
        #expect(rig.coordinator.live?.session.id == account.id)
        #expect(rig.list == [demo.id.uuidString])

        rig.coordinator.discardDemoWorkouts()

        #expect(try rig.storedSessions([demo.id]) == 0)
        #expect(try rig.storedSessions([account.id]) == 1)
        #expect(rig.coordinator.active?.id == account.id)
        #expect(rig.coordinator.live?.session.id == account.id)
        #expect(rig.activity.ends == 0)
        #expect(Set(rig.ops([account.id]).map(\.seq)).isSuperset(of: accountOps))
        #expect(rig.list.isEmpty)
    }

    // MARK: the launch sweep (AC10)

    @Test func theLaunchSweepDiscardsWhatTheListNamesWithoutAsking() throws {
        let rig = DemoTrainRig()
        let s = rig.startWorkout("Left over")
        rig.finishLocally(s)
        // The demo ended outside the switch (a launch argument): the next launch has Demo data off.
        rig.demo = false
        rig.relaunch()
        #expect(rig.coordinator.demoWorkouts == DemoWorkouts(count: 1))

        rig.coordinator.demoAtLaunch(demoMode: false, signedIn: false)

        #expect(try rig.storedSessions([s.id]) == 0)
        #expect(rig.list.isEmpty)
    }

    /// The launch condition (review R8): with Demo data still on (a kill inside the exit, or a launch in the demo) the
    /// demo's workouts stay, the one in progress too.
    @Test func aLaunchInTheDemoDiscardsNothing() throws {
        let rig = DemoTrainRig()
        let finished = rig.startWorkout("Finished")
        rig.finishLocally(finished)
        let live = rig.startWorkout("Live")
        let list = rig.list
        rig.relaunch()

        rig.coordinator.demoAtLaunch(demoMode: true, signedIn: false)

        #expect(try rig.storedSessions([finished.id, live.id]) == 2)
        #expect(rig.coordinator.active?.id == live.id)
        #expect(rig.list == list)
    }

    /// With the list empty the sweep reads nothing and writes nothing: no save at launch.
    @Test func theLaunchSweepWithAnEmptyListChangesNothing() throws {
        let rig = DemoTrainRig()
        rig.demo = false
        let account = rig.startWorkout("Account")
        let saves = Recorded<Bool>()
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: rig.store.context,
                                                              queue: nil) { _ in saves.append(true) }
        defer { NotificationCenter.default.removeObserver(observer) }
        #expect(!rig.sync.hasDemoSessions)

        rig.coordinator.demoAtLaunch(demoMode: false, signedIn: true)

        #expect(saves.all.isEmpty)
        #expect(rig.coordinator.active?.id == account.id)
        #expect(rig.coordinator.live != nil)
        #expect(try rig.storedSessions([account.id]) == 1)
    }

    // MARK: the seed for upgraders (review R1, design §6.9)

    /// In the demo with nobody signed in, every stored session is the demo's: the first launch with the list puts them
    /// all on it, finished or in progress, and the exit can discard them.
    @Test func signedOutInTheDemoTheFirstLaunchListsEveryStoredSession() throws {
        let rig = DemoTrainRig()
        let finished = rig.storeUnlisted("Before the list", finished: true)
        let live = rig.storeUnlisted("Still going", finished: false)
        rig.relaunch()
        #expect(rig.list.isEmpty && !rig.seeded)

        rig.coordinator.demoAtLaunch(demoMode: true, signedIn: false)

        #expect(Set(rig.list) == [finished.id.uuidString, live.id.uuidString])
        #expect(rig.seeded)
        #expect(rig.coordinator.demoWorkouts == DemoWorkouts(count: 2))
        #expect(rig.coordinator.discardDemoWorkouts())
        #expect(try rig.storedSessions([finished.id, live.id]) == 0)
    }

    /// Signed in, the account's sessions are there too and can't be told apart: none is listed (STATUS, Known issues).
    @Test func signedInTheSeedListsNothing() throws {
        let rig = DemoTrainRig()
        let s = rig.storeUnlisted("Maybe the account's", finished: true)
        rig.relaunch()

        rig.coordinator.demoAtLaunch(demoMode: true, signedIn: true)

        #expect(rig.list.isEmpty)
        #expect(rig.seeded)
        #expect(try rig.storedSessions([s.id]) == 1)
    }

    /// Demo data off: the sessions are the account's, or were left by a demo no list knows. None is listed, none goes.
    @Test func withDemoDataOffTheSeedListsNothing() throws {
        let rig = DemoTrainRig()
        rig.demo = false
        let s = rig.storeUnlisted("The account's", finished: true)
        rig.relaunch()

        rig.coordinator.demoAtLaunch(demoMode: false, signedIn: false)

        #expect(rig.list.isEmpty)
        #expect(rig.seeded)
        #expect(try rig.storedSessions([s.id]) == 1)
    }

    /// Once: a later launch, in the demo and signed out again, adds nothing the store got meanwhile.
    @Test func theSeedRunsOnce() throws {
        let rig = DemoTrainRig()
        let first = rig.storeUnlisted("Before the list", finished: true)
        rig.relaunch()
        rig.coordinator.demoAtLaunch(demoMode: true, signedIn: false)
        #expect(rig.list == [first.id.uuidString])
        let later = rig.storeUnlisted("After the seed", finished: true)

        rig.relaunch()
        rig.coordinator.demoAtLaunch(demoMode: true, signedIn: false)

        #expect(rig.list == [first.id.uuidString])
        #expect(try rig.storedSessions([later.id]) == 1)
    }

    /// A store that can't be read, or memory in place of the file, can't say what's stored: no seed yet, and the next
    /// launch tries again.
    @Test func theSeedWaitsForAStoreItCanRead() throws {
        let rig = DemoTrainRig()
        let s = rig.storeUnlisted("Before the list", finished: true)
        rig.relaunch()
        rig.sync.fetchSessions = { _, _ in throw StoreUnreadable() }
        rig.coordinator.demoAtLaunch(demoMode: true, signedIn: false)
        #expect(rig.list.isEmpty && !rig.seeded)

        let disk = try DemoExitDisk()
        let inTheWay = disk.folder.appendingPathComponent("file")
        try Data([1]).write(to: inTheWay)
        let lost = DemoTrainRig(store: TrainStore(url: inTheWay.appendingPathComponent("Train.store")))
        lost.storeUnlisted("In memory", finished: true)
        lost.relaunch()
        lost.coordinator.demoAtLaunch(demoMode: true, signedIn: false)
        #expect(lost.list.isEmpty && !lost.seeded)

        rig.relaunch()
        rig.coordinator.demoAtLaunch(demoMode: true, signedIn: false)
        #expect(rig.list == [s.id.uuidString] && rig.seeded)
    }
}
