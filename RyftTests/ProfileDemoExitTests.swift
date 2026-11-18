import Foundation
import SwiftData
import Testing
@testable import Ryft

// P1b ticket 3 (docs/work/2026-11-18-ios17-demo-exit/design.md §6.1, §6.4, ADR 0019): Profile's Demo data switch going
// off. What it would discard is asked, never stored; nothing changes until the exit runs; the exit discards, switches
// off, and the account's first write after it lands. Each graph has a Demo data setting of its own, never the test
// host's. Synthetic values only.

@Suite("P1b: turning Demo data off", .serialized)
@MainActor
struct ProfileDemoExitTests {
    /// Profile on `graph`, with Train on the same store as the rig.
    private func profile(_ graph: DemoExitGraph, train: DemoTrainRig) -> ProfileViewModel {
        let sync = SyncService.ungated(env: graph.env)
        return ProfileViewModel(state: graph.state, sync: sync,
                                coordinator: SyncCoordinator(steps: LiveSyncSteps(state: graph.state, sync: sync),
                                                             clock: graph.env.clock),
                                apiStatus: APIStatus(), train: train.coordinator)
    }

    /// AC6: what the switch would discard is computed from the store; asking changes nothing, so a cancelled dialog
    /// leaves the demo running with its workout, its ops and the list.
    @Test func askingWhatWouldGoChangesNothing() throws {
        let rig = DemoTrainRig()
        let graph = try DemoExitGraph(persistence: rig.store, demo: true)
        let model = profile(graph, train: rig)
        let live = rig.startWorkout("Live")
        let ops = rig.ops([live.id]).map(\.seq)
        let list = rig.list

        #expect(model.demoWorkouts == DemoWorkouts(count: 1, inProgress: true))
        #expect(model.demoWorkouts == DemoWorkouts(count: 1, inProgress: true))

        #expect(model.demoMode)
        #expect(graph.settings.demoMode)
        #expect(try rig.storedSessions([live.id]) == 1)
        #expect(rig.coordinator.active?.id == live.id)
        #expect(rig.coordinator.live?.session.id == live.id)
        #expect(rig.ops([live.id]).map(\.seq) == ops)
        #expect(rig.list == list)
        #expect(rig.activity.ends == 0)
    }

    /// AC7 through the exit: a finished and a live demo workout go, the switch is off, Train has no workout, nothing
    /// is left to confirm, and the account's first write after the demo lands in its store on disk.
    @Test func theExitDiscardsThenTheAccountsFirstWriteLands() async throws {
        let disk = try DemoExitDisk()
        let rig = DemoTrainRig(store: TrainStore(url: disk.url))
        let graph = try DemoExitGraph(persistence: rig.store, demo: true)
        let model = profile(graph, train: rig)
        let finished = rig.startWorkout("Finished")
        rig.finishLocally(finished)
        let live = rig.startWorkout("Live")
        let ids: Set<UUID> = [finished.id, live.id]
        #expect(model.demoWorkouts == DemoWorkouts(count: 2, inProgress: true))
        let ends = rig.activity.ends

        await model.endDemo()
        rig.demo = false // RyftApp's `.onChange(of: settings.demoMode)` on the next render
        let after = await graph.repository.store(scores: [DailyScore(day: "2026-11-10", strain: 6)]).committed()

        #expect(!graph.settings.demoMode)
        #expect(!model.demoMode)
        #expect(try rig.storedSessions(ids) == 0)
        #expect(rig.ops(ids).isEmpty)
        #expect(rig.list.isEmpty)
        #expect(rig.coordinator.active == nil && rig.coordinator.live == nil)
        #expect(rig.activity.ends == ends + 1) // the live workout's Live Activity
        #expect(model.demoWorkouts == nil)
        #expect(after.saved)
        #expect(try rig.store.stored(CachedDay.self, where: #Predicate { $0.day == "2026-11-10" }) == 1)
    }

    /// AC8: with no demo workout there's nothing to confirm, and the exit is today's switch-off. The switch's setter
    /// off is the exit.
    @Test func withoutDemoWorkoutsTheSwitchOffIsTheExit() async throws {
        let disk = try DemoExitDisk()
        let rig = DemoTrainRig(store: TrainStore(url: disk.url))
        let graph = try DemoExitGraph(persistence: rig.store, demo: true)
        let model = profile(graph, train: rig)
        #expect(model.demoWorkouts == nil)
        #expect(graph.repository.score("2026-11-01") == nil) // the demo's read-model store, made

        await model.setDemoMode(false)

        #expect(!graph.settings.demoMode)
        #expect(!model.demoMode)
        let written = await graph.repository.store(scores: [DailyScore(day: "2026-11-11", strain: 4)]).committed()
        #expect(written.saved)
        // The refresh after the exit writes the account's days too: this one is the test's.
        #expect(try rig.store.stored(CachedDay.self, where: #Predicate { $0.day == "2026-11-11" }) == 1)
    }

    /// Turning the demo on changes nothing about Train: no discard.
    @Test func turningTheDemoOnDiscardsNothing() async throws {
        let disk = try DemoExitDisk()
        let rig = DemoTrainRig(store: TrainStore(url: disk.url))
        rig.demo = false
        let graph = try DemoExitGraph(persistence: rig.store, demo: false)
        let model = profile(graph, train: rig)
        let account = rig.startWorkout("Account")

        await model.setDemoMode(true)

        #expect(graph.settings.demoMode)
        #expect(try rig.storedSessions([account.id]) == 1)
        #expect(rig.coordinator.active?.id == account.id)
    }
}
