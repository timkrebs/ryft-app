import Foundation
import Observation
import SwiftData
import Testing
@testable import Ryft

// P1b ticket 3 (docs/work/2026-11-18-ios17-demo-exit/design.md §6.1, §6.4, ADR 0019): Profile's Demo data switch going
// off. What it would discard is asked, never stored; nothing changes until the exit runs; the exit discards, switches
// off, and the account's first write after it lands. Each graph has a Demo data setting of its own, never the test
// host's. Synthetic values only.

/// Thrown by a store that can't be read (`TrainSyncService.fetchSessions`).
private struct StoreUnreadable: Error {}

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

        #expect(model.switchingDemoOff() == .confirm(DemoWorkouts(count: 1)))
        #expect(model.switchingDemoOff() == .confirm(DemoWorkouts(count: 1)))

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
        #expect(model.switchingDemoOff() == .confirm(DemoWorkouts(count: 2)))
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
        #expect(model.switchingDemoOff() == .exit)
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
        #expect(model.switchingDemoOff() == .exit)
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

    /// Fails closed (review R6): a store that can't be read leaves Demo data on and the demo's workout open, so nothing
    /// half-happens.
    @Test func aStoreThatCantBeReadLeavesDemoDataOn() async throws {
        let rig = DemoTrainRig()
        let graph = try DemoExitGraph(persistence: rig.store, demo: true)
        let model = profile(graph, train: rig)
        let live = rig.startWorkout("Live")
        rig.sync.fetchSessions = { _, _ in throw StoreUnreadable() }
        #expect(model.demoExitError == nil)
        // The error is what the switch re-renders on: it reads on again, with the message under it (review R11).
        let refused = Recorded<Bool>()
        withObservationTracking { _ = model.demoExitError } onChange: { refused.append(true) }

        await model.setDemoMode(false)

        #expect(graph.settings.demoMode)
        #expect(model.demoMode)
        #expect(model.demoExitError == ProfileViewModel.demoExitFailed)
        #expect(refused.count == 1)
        #expect(rig.coordinator.live?.session.id == live.id)
        #expect(try rig.storedSessions([live.id]) == 1)
        #expect(rig.list == [live.id.uuidString])

        // The store reads again: the next toggle that works clears it.
        rig.sync.fetchSessions = { try $0.context.fetch($1) }
        await model.setDemoMode(false)
        #expect(!graph.settings.demoMode)
        #expect(model.demoExitError == nil)
        #expect(try rig.storedSessions([live.id]) == 0)
    }

    /// Review R12: the list names a workout but the store can't be read. That isn't "nothing to discard": no dialog, no
    /// exit, and the switch says why. Turning Demo data on (here: again) clears the message.
    @Test func aReadFailureWithListedWorkoutsNeitherAsksNorExits() async throws {
        let rig = DemoTrainRig()
        let graph = try DemoExitGraph(persistence: rig.store, demo: true)
        let model = profile(graph, train: rig)
        let finished = rig.startWorkout("Finished")
        rig.finishLocally(finished)
        let ops = rig.ops([finished.id]).map(\.seq)
        rig.sync.fetchSessions = { _, _ in throw StoreUnreadable() }

        #expect(model.switchingDemoOff() == .refused)

        #expect(model.demoExitError == ProfileViewModel.demoExitFailed)
        #expect(graph.settings.demoMode)
        #expect(try rig.storedSessions([finished.id]) == 1)
        #expect(rig.ops([finished.id]).map(\.seq) == ops)
        #expect(rig.list == [finished.id.uuidString])

        await model.setDemoMode(true)
        #expect(model.demoExitError == nil)
        // Nothing listed: nothing to read, so a store that can't be read doesn't stop the exit.
        let empty = DemoTrainRig()
        empty.sync.fetchSessions = { _, _ in throw StoreUnreadable() }
        let other = try DemoExitGraph(persistence: empty.store, demo: true)
        #expect(profile(other, train: empty).switchingDemoOff() == .exit)
    }

    /// The switch's VoiceOver hint follows the list while Profile is alive (review R3): a demo workout started from
    /// elsewhere brings it, the discard takes it, and each change reaches an observer.
    @Test func theHintFollowsTheListWhileProfileIsOpen() async throws {
        let rig = DemoTrainRig()
        let graph = try DemoExitGraph(persistence: rig.store, demo: true)
        let model = profile(graph, train: rig)
        #expect(!model.showsDemoExitHint)

        let started = Recorded<Bool>()
        withObservationTracking { _ = model.showsDemoExitHint } onChange: { started.append(true) }
        rig.startWorkout("From a quick action")
        #expect(started.count == 1)
        #expect(model.showsDemoExitHint)

        let discarded = Recorded<Bool>()
        withObservationTracking { _ = model.showsDemoExitHint } onChange: { discarded.append(true) }
        #expect(rig.coordinator.discardDemoWorkouts())
        #expect(discarded.count == 1)
        #expect(!model.showsDemoExitHint)

        // Outside the demo there's nothing to hint, whatever the list says.
        rig.startWorkout("Again")
        #expect(model.showsDemoExitHint)
        graph.settings.demoMode = false
        #expect(!model.showsDemoExitHint)
    }

    /// Review R2: after the exit Train's history and "Last: …" name no discarded workout, offline (the cached list) or
    /// read again, and the demo's platform started over, so Demo data on again in the same run shows none either.
    @Test func afterTheExitTrainShowsNoDiscardedWorkoutNotEvenInTheDemoAgain() async throws {
        let disk = try DemoExitDisk()
        let store = TrainStore(url: disk.url)
        let graph = try DemoExitGraph(persistence: store, demo: true)
        let rig = DemoTrainRig(store: store, platform: graph.api)
        let model = profile(graph, train: rig)
        let s = rig.startWorkout("Demo squat")
        let id = s.id
        let completed = await rig.sync.finish(s)
        #expect(completed != nil) // on the demo's platform
        rig.coordinator.close()
        rig.coordinator.refreshActive()
        let library = rig.coordinator.library
        let history = TrainHistoryViewModel(library: library)
        let today = TrainTodayViewModel(library: library, store: store, clock: graph.env.clock)
        await history.load() // the platform's list, cached for offline
        #expect(history.sessions.contains { $0.id == id })
        #expect(today.historyDetail?.hasPrefix("Last: Demo squat") == true)
        let before = try await graph.platform.sessions(from: .distantPast, to: .distantFuture)
        #expect(before.contains { $0.id == id })

        await model.endDemo()

        #expect(!library.cachedSessions().contains { $0.id == id })
        #expect(today.historyDetail?.contains("Demo squat") != true)
        let after = try await graph.platform.sessions(from: .distantPast, to: .distantFuture)
        #expect(!after.contains { $0.id == id })
        // The rest of the cached list stays: the demo platform's own history isn't the discard's.
        #expect(!library.cachedSessions().isEmpty)

        await model.setDemoMode(true)
        await history.load()

        #expect(!history.sessions.contains { $0.id == id })
        #expect(today.historyDetail?.contains("Demo squat") != true)
    }

    /// Review R7: the lock-screen widget doesn't keep the demo's score after the exit, even when the account's first
    /// read fails.
    @Test func theWidgetLetsGoOfTheDemosScoreAtTheExit() async throws {
        let disk = try DemoExitDisk()
        let rig = DemoTrainRig(store: TrainStore(url: disk.url))
        let graph = try DemoExitGraph(persistence: rig.store, demo: true)
        let model = profile(graph, train: rig)
        let file = disk.folder.appendingPathComponent("readiness.json")
        graph.repository.widgetFile = file
        graph.repository.reloadWidget = {}
        func written() -> ReadinessSnapshot? {
            (try? Data(contentsOf: file)).flatMap { try? ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: $0) }
        }
        let day = DayFormat.string(from: graph.env.clock.now())
        let demoDay = DayDetail(score: DailyScore(day: day, readiness: 71, strain: 9), sleep: nil, workouts: [])
        await graph.repository.store(detail: demoDay).committed()
        #expect(written()?.kind == .score && written()?.readiness == 71)
        // What the widget takes from the demo besides the store (review R16): its sync status (today being scored) and
        // tonight's bedtime.
        let bedtime = graph.env.clock.now().addingTimeInterval(3 * 3_600)
        graph.state.syncStatus = SyncStatus(gate: nil, lastSyncAt: graph.env.clock.now(), lastSyncDevice: "iPhone",
                                            latest: [:], today: TodayState(day: day, state: .pending, scoredAt: nil,
                                                                           modelVersion: "demo"),
                                            pendingDays: [day], expectedWithinSec: 60, resyncRequestedAt: nil)
        graph.repository.tonightBedtime = bedtime
        #expect(written()?.bedtime != nil)
        #expect(graph.repository.todayStatus != nil)
        graph.api.failure = APIError.http(503, "down")

        await model.endDemo()

        #expect(!graph.settings.demoMode)
        #expect(written()?.readiness == nil)
        #expect(written()?.bedtime == nil)
        #expect(written()?.kind != .pending)
        #expect(graph.state.syncStatus == nil)
        #expect(graph.repository.todayStatus == nil)
        #expect(graph.repository.tonightBedtime == nil)
    }

    /// Review R14: the exercise's detail after the exit shows nothing of the discarded workout, not its session, its
    /// records or its chart point: in memory, for a new library on the store (a relaunch, offline), and on disk.
    @Test func afterTheExitTheExerciseDetailShowsNoDiscardedWorkout() async throws {
        let disk = try DemoExitDisk()
        let store = TrainStore(url: disk.url)
        let graph = try DemoExitGraph(persistence: store, demo: true)
        let rig = DemoTrainRig(store: store, platform: graph.api)
        let model = profile(graph, train: rig)
        let bench = MockTrain.bench.id
        let s = rig.startWorkout("Demo bench")
        let id = s.id, day = DayFormat.string(from: s.startedAt)
        // Heavier than the demo's own history: the records are this workout's.
        let set = try #require(s.orderedExercises.first?.orderedSets.first)
        set.reps = 3
        set.weightKg = 300
        set.completedAt = .now
        let completed = await rig.sync.finish(s)
        #expect(completed != nil) // on the demo's platform
        rig.coordinator.close()
        rig.coordinator.refreshActive()
        let library = rig.coordinator.library
        let detail = ExerciseDetailViewModel(exerciseID: bench, library: library, clock: graph.env.clock)
        await detail.load() // the platform's history, cached for offline
        func shows(_ h: ExerciseHistory?) -> Bool {
            guard let h else { return false }
            return h.sessions.contains { $0.sessionId == id } || h.prs.contains { $0.sessionId == id }
                || h.e1rm.contains { $0.day == day }
        }
        #expect(detail.history?.sessions.contains { $0.sessionId == id } == true)
        #expect(detail.records.contains { $0.sessionId == id })
        #expect(detail.history?.e1rm.contains { $0.day == day } == true)
        let others = detail.history?.sessions.filter { $0.sessionId != id }.count ?? 0
        #expect(others > 0) // the demo's own history

        await model.endDemo()

        let cached = library.cachedHistory(for: bench)
        #expect(cached != nil && !shows(cached))
        // The rest of it stays.
        #expect(cached?.sessions.count == others)
        let outbox = TrainSyncService.preview(store: store)
        let relaunched = TrainLibrary(store: store, remote: { RecordingTrainSource() }, outbox: { outbox }, restore: false)
        let offline = ExerciseDetailViewModel(exerciseID: bench, library: relaunched, clock: graph.env.clock)
        await offline.load() // the platform can't be reached: the store's copy
        #expect(offline.history != nil && !shows(offline.history))
        #expect(!offline.records.contains { $0.sessionId == id })
        let key = "train.history.\(bench.uuidString)"
        let rows = try ModelContext(store.container).fetch(FetchDescriptor<CachedDocument>(predicate: #Predicate {
            $0.key == key
        }))
        let onDisk = WireCoding.decode(ExerciseHistory.self, rows.first?.data)
        #expect(onDisk != nil && !shows(onDisk))
    }
}
