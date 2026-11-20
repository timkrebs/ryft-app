import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Ryft

// The account wipe (design.md in docs/work/2026-11-05-wipe-recovery, ADR 0020) and the demo's exit (ADR 0019) each
// delete Train rows that a screen may still hold, and each can happen while the other is under way: a wipe with Demo
// data on, and the demo ending while a sign-in is held over an owed wipe. Each still does all it does alone. Synthetic
// values only.

@Suite("The wipe and the demo's exit, each with the other", .serialized)
@MainActor
struct WipeAndDemoExitTests {
    // MARK: the open workout

    /// The demo's discard lets go of its open workout as the wipe does (`TrainCoordinator.releaseRows`): the controller
    /// stops for good and its screen draws none of the rows that go. Ending the Live Activity, as before.
    @Test func theDemosDiscardReleasesItsOpenWorkoutAsTheWipeDoes() throws {
        let rig = DemoTrainRig()
        let live = rig.startWorkout("Live")
        let controller = try #require(rig.coordinator.live)

        #expect(rig.coordinator.discardDemoWorkouts())

        #expect(controller.isReleased)
        #expect(rig.coordinator.live == nil && rig.coordinator.active == nil)
        #expect(rig.activity.ends == 1)
        #expect(try rig.storedSessions([live.id]) == 0)
    }

    /// The workout's screen through the demo's exit, a rest running, on rows read back from the file: the rest bar draws
    /// twice a second and reads the next set, a relationship of a row the exit deletes, and on iOS 18 and 26 reading one
    /// is a fatal error. Released, the screen draws none of them (the wipe's twin is `anOpenWorkoutDrawsNoDeletedRow`).
    @Test func anOpenDemoWorkoutDrawsNoDeletedRowAtTheExit() async throws {
        let disk = try DemoExitDisk()
        let id = try Self.demoWorkoutOnDisk(at: disk.url)
        let rig = DemoTrainRig(store: TrainStore(url: disk.url))
        rig.defaults.set([id.uuidString], forKey: TrainSyncService.demoSessionsKey)
        rig.relaunch() // the outbox reads the list as it starts
        rig.coordinator.resume()
        let controller = try #require(rig.coordinator.live)
        try #require(controller.session.id == id)
        let exercise = try #require(controller.exercises.first)

        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: controller)) { w in
            controller.startRest(for: exercise, seconds: 120)
            try await w.wait("the rest bar") { w.node("Skip rest", exactly: true) != nil }
            #expect(rig.coordinator.discardDemoWorkouts())
            // The released screen has drawn, and nothing on it moves any more.
            try await w.wait("the released screen") { w.nodes().isEmpty }
            try await w.settle()
        }

        #expect(controller.isReleased)
        #expect(rig.coordinator.live == nil)
        #expect(try rig.storedSessions([id]) == 0)
        #expect(rig.list.isEmpty)
    }

    /// A demo workout with a set, saved in a store of its own that's gone afterwards, as a last process left it.
    private static func demoWorkoutOnDisk(at url: URL) throws -> UUID {
        let rig = DemoTrainRig(store: TrainStore(url: url))
        let live = rig.startWorkout("Live")
        rig.store.save()
        try #require(try rig.storedSessions([live.id]) == 1)
        return live.id
    }

    // MARK: a workout still opening

    /// What may come while a workout started from the sheet waits for it to go (`TrainCoordinator.open`).
    enum Interruption: String, CaseIterable, Sendable {
        case nothing, wipe, demoExit, accountChange
    }

    /// The workout's screen waits for the start sheet to go. A wipe, the demo's exit or an account change in that wait
    /// lets go of it: it never appears, over deleted rows or after its account, so nothing can be logged in it and
    /// nothing is queued. Released when its rows went. With nothing in between it appears once the wait is over.
    @Test(arguments: Interruption.allCases)
    func aWorkoutStillOpeningIsDroppedByWhatComesFirst(_ interruption: Interruption) async throws {
        let clock = TestClock()
        let rig = DemoTrainRig()
        rig.demo = interruption == .demoExit
        let coordinator = TrainCoordinator(sync: rig.sync, library: TrainLibrary.preview(store: rig.store, outbox: rig.sync),
                                           liveActivities: false, clock: clock, liveActivity: rig.activity)
        coordinator.sessionLayout = { .list }
        coordinator.jumpToNext = { false }
        coordinator.showsStart = true

        coordinator.startEmpty()
        let opening = try #require(coordinator.opening)
        let presenting = try #require(coordinator.presenting)
        let id = try #require(coordinator.active?.id)
        #expect(coordinator.live == nil && !coordinator.showsStart)
        #expect(await eventually { clock.pendingSleeps == 1 }, "the wait for the sheet")

        switch interruption {
        case .nothing:
            break
        case .wipe:
            #expect(rig.store.wipe(parkingActivitiesOf: nil, at: WipeValues.now))
            coordinator.releaseRows()
            coordinator.accountChanged()
        case .demoExit:
            #expect(coordinator.discardDemoWorkouts())
        case .accountChange:
            coordinator.accountChanged()
        }
        clock.advance(by: .seconds(1))
        await presenting.value

        #expect(coordinator.opening == nil)
        if interruption == .nothing {
            #expect(coordinator.live === opening)
        } else {
            #expect(coordinator.live == nil)
        }
        #expect(opening.isReleased == [.wipe, .demoExit].contains(interruption))
        #expect(rig.store.pendingOps().isEmpty)
        #expect(try rig.storedSessions([id]) == ([.nothing, .accountChange].contains(interruption) ? 1 : 0))
    }

    // MARK: a wipe with Demo data on

    /// The account's sign-out while the demo runs a workout: the wipe takes every session, the demo's too, and its turn
    /// lets go of the open one; the account change ends the Live Activity. The list isn't the wipe's, so the exit after
    /// it finds nothing to ask about or delete, sends nothing, and leaves the list empty.
    @Test func aWipeWithDemoDataOnTakesTheDemosWorkoutsAndTheExitFindsNothing() async throws {
        let disk = try DemoExitDisk()
        let rig = DemoTrainRig(store: TrainStore(url: disk.url))
        let finished = rig.startWorkout("Finished")
        rig.finishLocally(finished)
        let live = rig.startWorkout("Live")
        let controller = try #require(rig.coordinator.live)
        let ids: Set<UUID> = [finished.id, live.id]

        // The wipe's store step, then the app's account-change handler a runloop later.
        #expect(rig.store.wipe(parkingActivitiesOf: nil, at: WipeValues.now))
        rig.coordinator.releaseRows()
        rig.coordinator.accountChanged()

        #expect(controller.isReleased)
        #expect(rig.coordinator.live == nil && rig.coordinator.active == nil)
        #expect(rig.activity.ends == 1)
        #expect(try rig.storedSessions(ids) == 0)
        #expect(rig.store.pendingOps().isEmpty)
        #expect(try rig.coordinator.demoWorkouts() == nil, "nothing to confirm: the list alone isn't trusted")

        #expect(rig.coordinator.discardDemoWorkouts())

        #expect(rig.list.isEmpty)
        #expect(rig.activity.ends == 1)
        #expect(rig.store.pendingOps().isEmpty, "no DELETE queued")
        await rig.sync.flush()
        #expect(await rig.source.calls.isEmpty)
    }

    // MARK: the demo ending while a sign-in is held

    /// A's sign-out was refused and B's sign-in is held; the demo, still allowed over the debt (W11), logs a workout and
    /// is then switched off in Profile. The exit discards its workout, with its own save, and resets the app's state: none
    /// of that touches the ledger or the hold, even when the store takes deletes again and that save lands the wipe's
    /// pending ones, because no pass of this process can prove the wipe. The next launch still runs it, and publishes B.
    @Test(arguments: [true, false])
    func theDemoEndingWhileASignInIsHeldKeepsTheHoldAndTheDebt(_ stillRefusing: Bool) async throws {
        let a = WipeValues.accountA.uuidString, b = WipeValues.accountB.uuidString
        let rig = try WipingAuth(signedInAs: WipeValues.accountA)
        rig.disk.session(checked: true)
        try rig.disk.refuseDeletes()
        await rig.end(.user)
        await rig.signIn(WipeValues.accountB)
        try #require(rig.auth.errorMessage == AuthMessage.signInHeld)
        if !stillRefusing { try rig.disk.allowDeletes() }

        let demo = try await endTheDemo(over: rig)

        #expect(rig.auth.accountID == nil)
        #expect(rig.auth.errorMessage == AuthMessage.signInHeld)
        #expect(rig.client.currentSession?.user.id == WipeValues.accountB, "the next launch publishes it")
        #expect(rig.ledgerOnDisk?.wipe.account == a)
        #expect(rig.lastUser == a)
        #expect(demo.storedAfterTheExit == 0, "the demo's workout went, or never reached the file")
        #expect(demo.listAfterTheExit.isEmpty, "the list keeps only what the file still has")
        #expect(demo.sent == 0)

        rig.relaunch(signedInAs: WipeValues.accountB)
        await rig.settle()

        #expect(rig.auth.accountID == b)
        #expect(rig.ledgerOnDisk == nil)
        try rig.disk.expectNothingLeft()
    }

    /// What the demo's exit left: the demo's workout in the file, the list, and requests to the demo's platform.
    private struct DemoExit {
        let storedAfterTheExit: Int
        let listAfterTheExit: [String]
        let sent: Int
    }

    /// Demo data on over `rig`'s store, a workout started in it, then Profile's switch off with its confirmation
    /// (`ProfileViewModel.endDemo`). Everything it made goes with this function, as with the process at a relaunch.
    private func endTheDemo(over rig: WipingAuth) async throws -> DemoExit {
        let train = DemoTrainRig(store: rig.disk.store)
        train.account = nil
        let graph = try DemoExitGraph(persistence: rig.disk.store, demo: true, auth: rig.auth)
        let sync = SyncService.ungated(env: graph.env)
        let model = ProfileViewModel(state: graph.state, sync: sync,
                                     coordinator: SyncCoordinator(steps: LiveSyncSteps(state: graph.state, sync: sync),
                                                                  clock: graph.env.clock),
                                     apiStatus: APIStatus(), train: train.coordinator)
        let workout = train.startWorkout("Demo")
        #expect(model.switchingDemoOff() == .confirm(DemoWorkouts(count: 1)))

        await model.endDemo()
        train.demo = false

        #expect(!graph.settings.demoMode)
        #expect(train.coordinator.live == nil && train.coordinator.active == nil)
        return DemoExit(storedAfterTheExit: try train.storedSessions([workout.id]), listAfterTheExit: train.list,
                        sent: await train.source.calls.count)
    }
}
