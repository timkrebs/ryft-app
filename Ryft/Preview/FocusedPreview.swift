import Foundation

/// Mock sessions for the Focused layout's previews and shots: synthetic values only (day "Upper", 75 × 10, 80 × 6). Each
/// has its own store and sync, so a scenario's rows can't reach another's context. 102.5 is the widest number the table has
/// to hold (design.md §2.5).
@MainActor
enum FocusedPreview {
    enum Scenario {
        /// The first exercise done, the second on screen with last time, 75 × 10 and 80 × 6.
        case midSession
        /// `midSession` with the third set tapped, so the second is upcoming with a typed value.
        case tappedRow
        /// Every set checked, the last exercise on screen.
        case allDone
        /// The superset's first exercise on screen.
        case superset
        /// Two warm-ups on the page, folded or open.
        case warmups, warmupsOpen
        case bodyweight, timeAndDistance
        /// Every row state of the fourth column: 75 × 10 and 80 × 6 done, a ghost active, a typed 15-rep set the cap reads
        /// as 12, and last time. The column comes from `controller(_:column:)`.
        case estimates
        /// A bodyweight page: done with no load, done with added load, then ghosts.
        case bodyweightEstimates
        /// `midSession` with a note far longer than its one line.
        case longNote
        case oneExercise, manyExercises
        case offline
        case empty
        /// `midSession` with a rest running, 1:54 left.
        case restRunning
        /// `midSession` the moment a rest ended. Its "Rest over" holds: see `HeldClock`.
        case restOver
    }

    /// Never reaches the end of a wait: a shot of "Rest over" can't miss its one second on a slow Mac.
    private final class HeldClock: AppClock {
        func now() -> Date { Date() }
        func sleep(for duration: Duration) async throws { try await Task.sleep(for: .seconds(3600)) }
    }

    static let lastTimeDate = DateComponents(calendar: .current, year: 2026, month: 11, day: 3, hour: 18).date ?? .now

    /// Last time's working sets, as the platform sends them.
    static var lastTime: [SessionSet] {
        [SessionSet(setIndex: 0, reps: 10, weightKg: 75, rpe: 8, completedAt: lastTimeDate),
         SessionSet(setIndex: 1, reps: 6, weightKg: 80, rpe: 9, completedAt: lastTimeDate),
         SessionSet(setIndex: 2, reps: 6, weightKg: 80, completedAt: lastTimeDate),
         SessionSet(setIndex: 3, reps: 5, weightKg: 102.5, completedAt: lastTimeDate)]
    }

    /// `column`: as if picked with the header. `nil`: never picked, the default rule decides.
    /// `connectivity`: one the caller flips, so the offline banner can appear under a test.
    static func controller(_ scenario: Scenario, column: SetColumn? = nil, connectivity: ConnectivityMonitor? = nil) -> SessionController {
        let store = TrainStore(inMemory: true)
        let monitor = connectivity ?? (scenario == .offline ? ConnectivityMonitor.preview(online: false) : nil)
        let sync = TrainSyncService(store: store, remote: { MockTrainSource.shared }, owner: { TrainSyncService.demoOwner },
                                    monitorsNetwork: monitor != nil, connectivity: monitor)
        sync.gate = { _ in nil }
        let session = make(scenario, in: store)
        store.save()
        // Settings of its own, so the mocks can't read or write what the header stored in this simulator.
        let settings = Settings(defaults: UserDefaults(suiteName: "ryft.focused.preview") ?? .standard)
        settings.setColumn = column
        let controller = SessionController(session: session, sync: sync, liveActivity: nil,
                                           clock: scenario == .restOver ? HeldClock() : SystemClock(), layout: .focused, settings: settings)
        if scenario == .warmupsOpen, let ex = controller.pageExercise { controller.setWarmups(expanded: true, for: ex) }
        if scenario == .longNote {
            controller.pageExercise?.notes = "Slow on the way down, pause at the bottom and keep the elbows in the whole way up"
        }
        if scenario == .tappedRow, let ex = controller.pageExercise {
            ex.orderedSets[1].reps = 7
            controller.activate(ex.orderedSets[2])
        }
        if scenario == .restRunning, let ex = controller.pageExercise { controller.startRest(for: ex, seconds: 114) }
        if scenario == .restOver, let ex = controller.pageExercise {
            controller.startRest(for: ex, seconds: 15)
            controller.adjustRest(by: -RestTimer.maxRest)
        }
        return controller
    }

    private static func make(_ scenario: Scenario, in store: TrainStore) -> LocalSession {
        switch scenario {
        case .midSession, .offline, .tappedRow, .restRunning, .restOver, .longNote:
            return midSession(in: store)
        case .allDone:
            return allDone(in: store)
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
        case .estimates:
            return estimates(in: store)
        case .bodyweightEstimates:
            return bodyweightEstimates(in: store)
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

    private static func estimates(in store: TrainStore) -> LocalSession {
        let s = upper(in: store)
        let ex = s.orderedExercises[1]
        ex.lastTime = lastTime
        let sets = ex.orderedSets
        log(sets[0], reps: 10, kg: 75)
        log(sets[1], reps: 6, kg: 80)
        sets[1].rpe = 8.5
        if sets.count > 3 {
            sets[3].reps = 15
            sets[3].weightKg = 102.5
        }
        s.currentExerciseID = ex.id
        return s
    }

    private static func bodyweightEstimates(in store: TrainStore) -> LocalSession {
        let s = single(MockTrain.pullUp, in: store)
        let ex = s.orderedExercises[0]
        ex.lastTime = [SessionSet(setIndex: 0, reps: 8, completedAt: lastTimeDate),
                       SessionSet(setIndex: 1, reps: 6, weightKg: 10, completedAt: lastTimeDate)]
        let sets = ex.orderedSets
        log(sets[0], reps: 8, kg: nil)
        log(sets[1], reps: 6, kg: 10)
        return s
    }

    private static func log(_ set: LocalSet, reps: Int, kg: Double?) {
        set.reps = reps
        set.weightKg = kg
        set.completedAt = .now.addingTimeInterval(Double(set.setIndex) * 150 - 900)
    }

    private static func allDone(in store: TrainStore) -> LocalSession {
        let s = upper(in: store)
        for ex in s.orderedExercises {
            for set in ex.orderedSets {
                let ghost = ex.ghost(forSetAt: set.setIndex)
                set.reps = ghost.reps ?? 10
                set.weightKg = ghost.kg ?? 75
                set.completedAt = .now.addingTimeInterval(Double(set.setIndex) * 150 - 900)
            }
        }
        s.orderedExercises.last?.lastTime = lastTime
        s.currentExerciseID = s.orderedExercises.last?.id
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
