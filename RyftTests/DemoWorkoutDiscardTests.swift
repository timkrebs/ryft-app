import Foundation
import SwiftData
import Testing
@testable import Ryft

// P1b ticket 2 (docs/work/2026-11-18-ios17-demo-exit/design.md §6.2, §6.3, ADR 0019): the workouts started in the demo
// are on one list, and ending the demo discards them with their ops, sending nothing; an account's workout stays.
// Synthetic values only.

/// Train's platform as both bindings see it: records each session request by id, and can hold a `PUT` until the test
/// answers it.
actor RecordingTrainSource: TrainDataSource {
    enum Call: Equatable {
        case put(UUID), complete(UUID), delete(UUID)

        var id: UUID {
            switch self {
            case .put(let id), .complete(let id), .delete(let id): id
            }
        }
    }

    private(set) var calls: [Call] = []
    private var holdsPuts = false
    private var held: [CheckedContinuation<SessionPutResult, Never>] = []
    /// Held `PUT`s answered so far.
    private(set) var answered = 0

    func holdPuts() { holdsPuts = true }
    var heldCount: Int { held.count }

    /// Answers the held `PUT`s with `result`, and lets later ones through.
    func release(_ result: @Sendable (TrainSession) -> SessionPutResult, for doc: TrainSession) {
        holdsPuts = false
        let waiting = held
        held = []
        for c in waiting { c.resume(returning: result(doc)) }
        answered += waiting.count
    }

    func requests(for ids: Set<UUID>) -> [Call] { calls.filter { ids.contains($0.id) } }

    func putSession(_ s: TrainSession) async throws -> SessionPutResult {
        calls.append(.put(s.id))
        guard holdsPuts else { return .saved(s) }
        return await withCheckedContinuation { held.append($0) }
    }

    func completeSession(id: UUID, _ body: SessionComplete) async throws -> TrainSession {
        calls.append(.complete(id))
        throw APIError.http(404, "not here")
    }

    func deleteSession(id: UUID) async throws { calls.append(.delete(id)) }

    func exercises() async throws -> [Exercise] { MockTrain.exercises }
    func createExercise(_ e: Exercise) async throws -> Exercise { e }
    func exerciseHistory(id: UUID) async throws -> ExerciseHistory { throw APIError.http(404, "not here") }
    func plans() async throws -> PlansOverview { throw APIError.http(404, "not here") }
    func plan(id: UUID) async throws -> Plan { throw APIError.http(404, "not here") }
    func savePlan(_ p: Plan) async throws -> Plan { p }
    func deletePlan(id: UUID) async throws {}
    func enroll(planID: UUID) async throws -> Enrollment { throw APIError.http(404, "not here") }
    func pauseEnrollment() async throws {}
    func planToday() async throws -> PlanToday? { nil }
    func sessions(from: Date, to: Date) async throws -> [SessionSummary] { [] }
    func session(id: UUID) async throws -> TrainSession { throw APIError.http(404, "not here") }
}

/// What the coordinator asked of the Live Activity.
@MainActor
final class RecordingLiveActivity: WorkoutLiveActivity {
    private(set) var ends = 0
    private(set) var shown: [UUID] = []

    func workout(session: UUID, title: String, startedAt: Date, next: String) { shown.append(session) }
    // swiftlint:disable:next function_parameter_count
    func show(session: UUID, title: String, startedAt: Date, endsAt: Date, total: TimeInterval, exercise: String,
              next: String) { shown.append(session) }
    func finish(session: UUID, next: String) {}
    func end() { ends += 1 }
    func endAll(except session: UUID?) {}
}

/// Train as the app wires it, on one store: the binding follows `demo` (the Demo data switch) and `account` (who is
/// signed in), and one recording platform answers both bindings. The list lives in a defaults suite of its own.
@MainActor
final class DemoTrainRig {
    nonisolated static let account = "account-a"

    /// The Demo data switch and who is signed in, as the binding reads them.
    final class Binding {
        var demo = true
        var account: String? = DemoTrainRig.account
        var owner: String? { demo ? TrainSyncService.demoOwner : account }
    }

    let store: TrainStore
    let defaults: UserDefaults
    let source = RecordingTrainSource()
    let activity = RecordingLiveActivity()
    let binding = Binding()
    var demo: Bool {
        get { binding.demo }
        set { binding.demo = newValue }
    }
    var account: String? {
        get { binding.account }
        set { binding.account = newValue }
    }
    private(set) var sync: TrainSyncService
    private(set) var coordinator: TrainCoordinator

    /// `store`: in memory when nil (a default can't call the main actor's initializer).
    init(store: TrainStore? = nil) {
        let store = store ?? TrainStore(inMemory: true)
        self.store = store
        defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        (sync, coordinator) = Self.make(store: store, defaults: defaults, source: source, binding: binding,
                                        activity: activity)
    }

    private static func make(store: TrainStore, defaults: UserDefaults, source: RecordingTrainSource, binding: Binding,
                             activity: RecordingLiveActivity) -> (TrainSyncService, TrainCoordinator) {
        let sync = TrainSyncService(store: store, remote: { source }, owner: { binding.owner },
                                    debounce: .seconds(3600), monitorsNetwork: false, defaults: defaults)
        sync.gate = { _ in nil }
        let coordinator = TrainCoordinator(sync: sync, library: TrainLibrary.preview(store: store), liveActivities: false,
                                           liveActivity: activity)
        // Not the live graph's flags: their first use opens `TrainStore.shared` mid-test. On iOS 17.0, still the
        // deployment target, that newer container stops a set made after it joining a session made before
        // (NSInvalidArgumentException).
        coordinator.sessionLayout = { .list }
        coordinator.jumpToNext = { false }
        return (sync, coordinator)
    }

    /// A new process on the same store and defaults: a new outbox and coordinator, as at launch.
    func relaunch() {
        (sync, coordinator) = Self.make(store: store, defaults: defaults, source: source, binding: binding,
                                        activity: activity)
    }

    /// A session started the way every production one is (`TrainCoordinator.start`), with one bench set logged and
    /// its `PUT` queued.
    @discardableResult
    func startWorkout(_ title: String) -> LocalSession {
        coordinator.startEmpty()
        let s = coordinator.active ?? SessionFactory.empty(in: store)
        s.title = title
        SessionFactory.add(MockTrain.bench, to: s, sets: 1, in: store)
        sync.sessionChanged(s)
        return s
    }

    /// The live workout finished here, and closed: completed, its ops as `uploaded` says.
    func finishLocally(_ s: LocalSession) {
        s.status = .completed
        s.endedAt = s.startedAt.addingTimeInterval(1_800)
        store.save()
        coordinator.close()
        coordinator.refreshActive()
    }

    var list: [String] { defaults.stringArray(forKey: TrainSyncService.demoSessionsKey) ?? [] }

    func storedSessions(_ ids: Set<UUID>) throws -> Int {
        try store.stored(LocalSession.self, where: #Predicate { ids.contains($0.id) })
    }

    func ops(_ ids: Set<UUID>) -> [PendingTrainOp] { store.pendingOps().filter { ids.contains($0.sessionId) } }
}

@Suite("P1b: the demo's workouts are discarded when it ends", .serialized)
@MainActor
struct DemoWorkoutDiscardTests {
    // MARK: the list

    @Test func aSessionStartedInTheDemoIsOnTheListAndOneStartedForTheAccountIsNot() {
        let rig = DemoTrainRig()
        let demo = rig.startWorkout("Demo")
        #expect(rig.list == [demo.id.uuidString])
        rig.finishLocally(demo)

        rig.demo = false
        let account = rig.startWorkout("Account")
        #expect(rig.list == [demo.id.uuidString])
        #expect(rig.sync.demoSessions().map(\.id) == [demo.id])
        #expect(!rig.sync.demoSessions().contains { $0.id == account.id })
    }

    /// The list is never trusted on its own: an id the store doesn't have isn't a workout.
    @Test func theListCountsOnlyWhatTheStoreHas() {
        let rig = DemoTrainRig()
        rig.defaults.set([UUID().uuidString], forKey: TrainSyncService.demoSessionsKey)
        #expect(rig.sync.hasDemoSessions)
        #expect(rig.sync.demoSessions().isEmpty)
        #expect(rig.coordinator.demoWorkouts == nil)
    }

    @Test func theWorkoutsCountFinishedOnesAndSayWhetherOneIsInProgress() {
        let rig = DemoTrainRig()
        #expect(rig.coordinator.demoWorkouts == nil)
        rig.finishLocally(rig.startWorkout("One"))
        #expect(rig.coordinator.demoWorkouts == DemoWorkouts(count: 1, inProgress: false))
        rig.startWorkout("Two")
        #expect(rig.coordinator.demoWorkouts == DemoWorkouts(count: 2, inProgress: true))
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
        #expect(rig.coordinator.demoWorkouts == DemoWorkouts(count: 1, inProgress: false))

        rig.coordinator.discardDemoWorkouts()

        #expect(try rig.storedSessions([s.id]) == 0)
        #expect(rig.list.isEmpty)
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

        rig.coordinator.discardDemoWorkouts()

        #expect(saves.all.isEmpty)
        #expect(rig.coordinator.active?.id == account.id)
        #expect(rig.coordinator.live != nil)
        #expect(try rig.storedSessions([account.id]) == 1)
    }
}
