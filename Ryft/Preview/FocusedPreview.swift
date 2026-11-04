import Foundation

/// Mock sessions for the Focused layout's previews and shots: synthetic values only (day "Upper", 75 × 10, 80 × 6). Each
/// has its own store and sync, so a scenario's rows can't reach another's context. 102.5 is the widest number the table has
/// to hold (design.md §2.5).
@MainActor
enum FocusedPreview {
    enum Scenario {
        /// The first exercise done, the second on screen with last time, 75 × 10 and 80 × 6.
        case midSession
        /// The superset's first exercise on screen.
        case superset
        /// Two warm-ups on the page, folded or open.
        case warmups, warmupsOpen
        case bodyweight, timeAndDistance
        case oneExercise, manyExercises
        case offline
        case empty
    }

    static let lastTimeDate = DateComponents(calendar: .current, year: 2026, month: 11, day: 3, hour: 18).date ?? .now

    /// Last time's working sets, as the platform sends them.
    static var lastTime: [SessionSet] {
        [SessionSet(setIndex: 0, reps: 10, weightKg: 75, rpe: 8, completedAt: lastTimeDate),
         SessionSet(setIndex: 1, reps: 6, weightKg: 80, rpe: 9, completedAt: lastTimeDate),
         SessionSet(setIndex: 2, reps: 6, weightKg: 80, completedAt: lastTimeDate),
         SessionSet(setIndex: 3, reps: 5, weightKg: 102.5, completedAt: lastTimeDate)]
    }

    static func controller(_ scenario: Scenario) -> SessionController {
        let store = TrainStore(inMemory: true)
        let offline = scenario == .offline
        let sync = TrainSyncService(store: store, remote: { MockTrainSource.shared }, owner: { TrainSyncService.demoOwner },
                                    monitorsNetwork: offline, connectivity: offline ? .preview(online: false) : nil)
        sync.gate = { _ in nil }
        let session = make(scenario, in: store)
        store.save()
        let controller = SessionController(session: session, sync: sync, liveActivity: nil, layout: { .focused })
        if scenario == .warmupsOpen, let ex = controller.pageExercise { controller.setWarmups(expanded: true, for: ex) }
        return controller
    }

    private static func make(_ scenario: Scenario, in store: TrainStore) -> LocalSession {
        switch scenario {
        case .midSession, .offline:
            return midSession(in: store)
        case .superset:
            let s = midSession(in: store)
            s.currentExerciseID = s.orderedExercises[3].id
            return s
        case .warmups, .warmupsOpen:
            return warmups(in: store)
        case .bodyweight:
            return single(MockTrain.pullUp, in: store)
        case .timeAndDistance:
            return timeAndDistance(in: store)
        case .oneExercise:
            return single(MockTrain.bench, in: store)
        case .manyExercises:
            let s = SessionFactory.empty(in: store)
            for ex in MockTrain.exercises.prefix(12) { SessionFactory.add(ex, to: s, in: store) }
            s.currentExerciseID = s.orderedExercises[9].id
            return s
        case .empty:
            return SessionFactory.empty(in: store)
        }
    }

    private static func upper(in store: TrainStore) -> LocalSession {
        let s = SessionFactory.fromPlan(day: MockTrain.upperA, today: MockTrain.planToday, library: MockTrain.exercises, in: store)
        s.title = "Upper"
        s.startedAt = .now.addingTimeInterval(-23 * 60)
        return s
    }

    private static func midSession(in store: TrainStore) -> LocalSession {
        let s = upper(in: store)
        let list = s.orderedExercises
        for set in list[0].orderedSets {
            let ghost = list[0].ghost(forSetAt: set.setIndex)
            set.reps = ghost.reps
            set.weightKg = ghost.kg
            set.completedAt = .now.addingTimeInterval(Double(set.setIndex) * 150 - 900)
        }
        list[1].lastTime = lastTime
        list[1].notes = "Slow on the way down"
        s.currentExerciseID = list[1].id
        return s
    }

    private static func warmups(in store: TrainStore) -> LocalSession {
        let s = upper(in: store)
        let ex = s.orderedExercises[0]
        ex.lastTime = lastTime
        for (i, kg) in [40.0, 60.0].enumerated() {
            let set = SessionFactory.appendSet(index: ex.sets.count, to: ex, in: store)
            set.isWarmup = true
            set.weightKg = kg
            set.reps = 10 - i * 2
        }
        s.currentExerciseID = ex.id
        return s
    }

    private static func single(_ exercise: Exercise, in store: TrainStore) -> LocalSession {
        let s = SessionFactory.empty(in: store)
        s.title = "Upper"
        let ex = SessionFactory.add(exercise, to: s, sets: 4, in: store)
        s.currentExerciseID = ex.id
        return s
    }

    /// A plank with a stored time and an erg with a stored distance, as an import or another client leaves them.
    private static func timeAndDistance(in store: TrainStore) -> LocalSession {
        let s = SessionFactory.empty(in: store)
        s.title = "Upper"
        let plank = SessionFactory.add(MockTrain.plank, to: s, sets: 3, in: store)
        plank.orderedSets[0].durationSec = 45
        plank.orderedSets[0].completedAt = .now.addingTimeInterval(-300)
        plank.lastTime = [SessionSet(setIndex: 0, durationSec: 45, completedAt: lastTimeDate),
                          SessionSet(setIndex: 1, durationSec: 40, completedAt: lastTimeDate)]
        let erg = SessionFactory.add(MockTrain.erg, to: s, sets: 2, in: store)
        erg.orderedSets[0].distanceM = 5_000
        s.currentExerciseID = plank.id
        return s
    }
}
