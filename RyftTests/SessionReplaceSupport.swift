import Foundation
import Testing
@testable import Ryft

/// A `SessionLibrary` that records what the live session asks of it (design.md §1, §5).
@MainActor
final class FakeSessionLibrary: SessionLibrary {
    var cached: [UUID: [SessionSet]] = [:]
    var fresh: [UUID: [SessionSet]] = [:]
    var plan: Plan?
    var saveSucceeds = true
    private(set) var savedPlans: [Plan] = []

    func cachedLastTime(for exerciseID: UUID) -> [SessionSet] { cached[exerciseID] ?? [] }
    func lastTime(for exerciseID: UUID) async -> [SessionSet] { fresh[exerciseID] ?? cached[exerciseID] ?? [] }
    func editablePlan(containing planExerciseID: UUID) -> Plan? {
        guard let plan, !plan.isBuiltin,
              plan.days.contains(where: { $0.exercises.contains { $0.id == planExerciseID } }) else { return nil }
        return plan
    }
    func savePlan(_ plan: Plan) async -> Bool {
        savedPlans.append(plan)
        if saveSucceeds { self.plan = plan }
        return saveSucceeds
    }
}

/// One live session on an in-memory store:
/// `Row` (0) · `Bench` (1, superset 1, planned, 4 sets) · `Lateral` (2, superset 1, 3 sets) · `Curl` (3).
/// Synthetic values only.
@MainActor
final class ReplaceRig {
    let store = TrainStore(inMemory: true)
    let api = MockPlatformAPI()
    let sync: TrainSyncService
    let clock = TestClock()
    let library = FakeSessionLibrary()
    let session: LocalSession
    let controller: SessionController
    let peBench = UUID(), peRow = UUID()
    let plan: Plan
    let row: LocalSessionExercise, x: LocalSessionExercise, lateral: LocalSessionExercise, curl: LocalSessionExercise

    /// The exercise a replace picks.
    let incline = MockTrain.inclineDB
    let other = MockTrain.dip

    init(builtinPlan: Bool = false) {
        sync = TrainSyncService(store: store, remote: { [api] in api }, owner: { "test" }, debounce: .seconds(3600),
                                monitorsNetwork: false)
        sync.gate = { _ in nil }
        let day = PlanDay(dayIndex: 0, name: "Upper", exercises: [
            PlanExercise(id: peRow, exercise: MockTrain.row, position: 0, sets: 3, repsMin: 8, repsMax: 8,
                         targetKind: .kg, targetValue: 60, restSec: 150),
            PlanExercise(id: peBench, exercise: MockTrain.bench, position: 1, sets: 4, repsMin: 5, repsMax: 5,
                         targetKind: .kg, targetValue: 80, restSec: 180, supersetGroup: 1, notes: "pause on chest"),
        ])
        plan = Plan(name: "Upper/Lower", goal: .strength, weeks: nil, daysPerWeek: 4, description: "",
                    progression: nil, isBuiltin: builtinPlan, days: [day])
        library.plan = plan

        session = SessionFactory.empty(in: store)
        session.planDayId = day.id
        row = SessionFactory.add(MockTrain.row, to: session, sets: 3, in: store)
        x = SessionFactory.add(MockTrain.bench, to: session, sets: 4, rest: 180, in: store)
        lateral = SessionFactory.add(MockTrain.lateral, to: session, sets: 3, in: store)
        curl = SessionFactory.add(MockTrain.curl, to: session, sets: 3, in: store)
        row.planExerciseId = peRow
        x.supersetGroup = 1
        lateral.supersetGroup = 1
        x.planExerciseId = peBench
        x.targetSets = 4
        x.targetRepsMin = 5
        x.targetRepsMax = 5
        x.targetKg = 80
        x.targetKindRaw = TargetKind.kg.rawValue
        x.targetValue = 80
        x.notes = "pause on chest"
        x.lastTime = [SessionSet(setIndex: 0, reps: 5, weightKg: 77.5, updatedAt: clock.now())]
        for (i, s) in x.orderedSets.enumerated() {
            s.reps = [5, 5, nil, nil][i]
            s.weightKg = [80, 80, nil, nil][i]
        }
        store.save()
        controller = SessionController(session: session, sync: sync, liveActivity: nil, clock: clock, library: library)
    }

    deinit { MainActor.assumeIsolated { controller.stop() } }

    /// Checks the first `n` sets of `ex` without queuing an upload (the rig's baseline has none).
    func complete(_ n: Int, of ex: LocalSessionExercise) {
        for s in ex.orderedSets.prefix(n) {
            s.reps = s.reps ?? 5
            s.weightKg = s.weightKg ?? 80
            s.completedAt = clock.now()
        }
        store.save()
    }

    var puts: [PendingTrainOp] { store.pendingOps().filter { $0.kind == .put } }

    /// Lets queued tasks (the undo window's sleep) run.
    func settle(until condition: () -> Bool = { false }) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    /// Runs the clock past the undo window.
    func expireUndoWindow() async {
        await settle { self.clock.pendingSleeps > 0 }
        clock.advance(by: .seconds(5))
        await settle { self.controller.undo == nil }
    }

    func uploaded() async -> TrainSession? {
        await sync.flush()
        return try? await api.session(id: session.id)
    }
}

/// An exercise row as values, for "exactly as before". Set stamps are left out on purpose: a restore is a new
/// edit and carries newer ones (design.md §3).
struct RowShape: Equatable {
    struct SetShape: Equatable {
        let id: UUID; let setIndex: Int; let reps: Int?; let weightKg: Double?; let isWarmup: Bool; let completedAt: Date?
    }
    let id, exerciseId: UUID
    let name: String
    let position, restSec: Int
    let supersetGroup: Int?
    let planExerciseId: UUID?
    let targetSets, targetRepsMin, targetRepsMax: Int?
    let targetKg, targetValue: Double?
    let notes: String
    let lastTime: [SessionSet]
    let sets: [SetShape]

    @MainActor
    init(_ e: LocalSessionExercise) {
        id = e.id; exerciseId = e.exerciseId; name = e.name; position = e.position; restSec = e.restSec
        supersetGroup = e.supersetGroup; planExerciseId = e.planExerciseId
        targetSets = e.targetSets; targetRepsMin = e.targetRepsMin; targetRepsMax = e.targetRepsMax
        targetKg = e.targetKg; targetValue = e.targetValue; notes = e.notes; lastTime = e.lastTime
        sets = e.orderedSets.map { SetShape(id: $0.id, setIndex: $0.setIndex, reps: $0.reps, weightKg: $0.weightKg,
                                           isWarmup: $0.isWarmup, completedAt: $0.completedAt) }
    }
}

extension ReplaceRig {
    /// The whole list as values: order, positions, groups.
    var layout: [RowShape] { session.orderedExercises.map(RowShape.init) }
}
