import Foundation
import SwiftData
@testable import Ryft

// Shared by the P1b suites (docs/work/2026-11-18-ios17-demo-exit/design.md §9): the account's store on disk, an
// environment whose Demo data switch is its own setting, never `Settings.shared` (the test host's), and Train wired as
// the app wires it. Synthetic values only.

/// A store on disk in a folder of its own, removed afterwards.
final class DemoExitDisk {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ryft-p1b-\(UUID().uuidString)")
    var url: URL { folder.appendingPathComponent("Train.store") }

    init() throws { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

    deinit { try? FileManager.default.removeItem(at: folder) }
}

/// An app graph on `persistence` with a Demo data switch of its own (`settings.demoMode`), as the live one has: the
/// Repository's first read in demo makes the demo's store.
@MainActor
struct DemoExitGraph {
    let defaults: UserDefaults
    let settings: Settings
    let api: MockPlatformAPI
    /// Train on the demo's platform: its own, never `MockTrainSource.shared` (the test host's).
    let platform = MockTrainSource()
    let env: AppEnvironment
    let state: AppState

    init(persistence: Persistence, demo: Bool, clock: TestClock = TestClock(now: Date(timeIntervalSince1970: 1_794_000_000)),
         auth: AuthService? = nil) throws {
        defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        settings = Settings(defaults: defaults)
        settings.demoMode = demo
        api = MockPlatformAPI(train: platform)
        api.now = { clock.now() }
        env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: api, demoAPI: api,
                             auth: auth ?? .preview(), persistence: persistence, clock: clock, notifier: MockNotifier(),
                             flags: StaticFlags([:]), connectivity: .preview(online: true), defaults: defaults,
                             demoOverride: nil)
        env.reads.random = { $0.lowerBound }
        env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
        state = AppState(env: env)
        // A graph that follows a Demo data switch shares the widget's file; this one's writes are nobody's.
        state.repository.widgetFile = nil
    }

    var repository: Repository { state.repository }
}

extension TrainStore {
    /// Rows of `T` a fresh context on the container finds: what the store has, not a context's pending ones.
    func stored<T: PersistentModel>(_ type: T.Type, where predicate: Predicate<T>? = nil) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<T>(predicate: predicate))
    }
}

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
/// signed in), and one recording platform answers both bindings (or `platform`, for Train's reads too). The list lives
/// in a defaults suite of its own.
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
    /// Uploads and Train's reads go here instead of `source` (a graph's demo platform).
    private let platform: (any TrainDataSource)?
    private(set) var sync: TrainSyncService
    private(set) var coordinator: TrainCoordinator

    /// `store`: in memory when nil (a default can't call the main actor's initializer).
    init(store: TrainStore? = nil, platform: (any TrainDataSource)? = nil) {
        let store = store ?? TrainStore(inMemory: true)
        self.store = store
        self.platform = platform
        defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        (sync, coordinator) = Self.make(store: store, defaults: defaults, remote: platform ?? source, reads: platform,
                                        binding: binding, activity: activity)
    }

    private static func make(store: TrainStore, defaults: UserDefaults, remote: any TrainDataSource,
                             reads: (any TrainDataSource)?, binding: Binding,
                             activity: RecordingLiveActivity) -> (TrainSyncService, TrainCoordinator) {
        let sync = TrainSyncService(store: store, remote: { remote }, owner: { binding.owner },
                                    debounce: .seconds(3600), monitorsNetwork: false, defaults: defaults)
        sync.gate = { _ in nil }
        let library = reads.map { r in TrainLibrary(store: store, remote: { r }, restore: false) }
            ?? TrainLibrary.preview(store: store)
        let coordinator = TrainCoordinator(sync: sync, library: library, liveActivities: false, liveActivity: activity)
        // Not the live graph's flags: their first use opens `TrainStore.shared` mid-test. On iOS 17.0, still the
        // deployment target, that newer container stops a set made after it joining a session made before
        // (NSInvalidArgumentException).
        coordinator.sessionLayout = { .list }
        coordinator.jumpToNext = { false }
        return (sync, coordinator)
    }

    /// A new process on the same store and defaults: a new outbox and coordinator, as at launch.
    func relaunch() {
        (sync, coordinator) = Self.make(store: store, defaults: defaults, remote: platform ?? source, reads: platform,
                                        binding: binding, activity: activity)
    }

    /// A session as a build before the list logged it: stored, never listed.
    @discardableResult
    func storeUnlisted(_ title: String, finished: Bool) -> LocalSession {
        let s = SessionFactory.empty(in: store)
        s.title = title
        if finished {
            s.status = .completed
            s.endedAt = s.startedAt.addingTimeInterval(1_800)
        }
        store.save()
        return s
    }

    var seeded: Bool { defaults.bool(forKey: TrainSyncService.demoSessionsSeededKey) }

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
