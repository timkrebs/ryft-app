import Foundation

/// Creates local sessions: from a plan day (with today's targets), as a repeat
/// of an earlier session, or empty.
@MainActor
enum SessionFactory {
    static func fromPlan(day: PlanDay, today: PlanToday?, library: [Exercise], in store: TrainStore) -> LocalSession {
        let s = LocalSession(title: day.name, planDayId: day.id)
        store.context.insert(s)
        for pe in day.exercises.sorted(by: { $0.position < $1.position }) {
            let e = add(pe.exercise, to: s, sets: 0, rest: pe.restSec, in: store)
            e.supersetGroup = pe.supersetGroup
            e.notes = pe.notes
            let target = today?.target(for: pe)
            e.planExerciseId = pe.id
            e.targetSets = target?.sets ?? pe.sets
            e.targetRepsMin = target?.repsMin ?? pe.repsMin
            e.targetRepsMax = target?.repsMax ?? pe.repsMax
            e.targetKindRaw = pe.targetKind.rawValue
            e.targetValue = pe.targetValue
            e.targetKg = target?.targetKg ?? (pe.targetKind == .kg ? pe.targetValue : nil)
            // The platform's list holds every occurrence of the exercise; each row gets its own.
            e.lastTime = LastTimeOccurrence.sets(target?.lastTime ?? [], for: pe, in: day.exercises)
            for i in 0..<(e.targetSets ?? pe.sets) { appendSet(index: i, to: e, in: store) }
        }
        store.save()
        return s
    }

    /// Same exercises and number of sets; last time's numbers appear ghosted.
    static func repeating(_ last: TrainSession, library: [Exercise], in store: TrainStore) -> LocalSession {
        let s = LocalSession(title: last.title.isEmpty ? String(localized: "Workout") : last.title)
        store.context.insert(s)
        for old in last.exercises.sorted(by: { $0.position < $1.position }) {
            guard let ex = library.first(where: { $0.id == old.exerciseId }) else { continue }
            let working = old.sets.filter { !$0.isWarmup }
            let e = add(ex, to: s, sets: max(1, working.count), in: store)
            e.lastTime = working
        }
        store.save()
        return s
    }

    static func empty(in store: TrainStore) -> LocalSession {
        let s = LocalSession(title: String(localized: "Workout"))
        store.insert(s)
        return s
    }

    /// Appends an exercise with `sets` empty rows.
    @discardableResult
    static func add(_ ex: Exercise, to s: LocalSession, sets: Int = 3, rest: Int? = nil,
                    in store: TrainStore) -> LocalSessionExercise {
        let position = (s.exercises.map(\.position).max() ?? -1) + 1
        let e = LocalSessionExercise(exerciseId: ex.id, name: ex.name, kind: ex.kind, loadType: ex.loadType,
                                     position: position, restSec: rest ?? defaultRest(for: ex))
        store.context.insert(e)
        s.exercises.append(e)
        for i in 0..<sets { appendSet(index: i, to: e, in: store) }
        return e
    }

    @discardableResult
    static func appendSet(index: Int, to e: LocalSessionExercise, in store: TrainStore) -> LocalSet {
        let set = LocalSet(setIndex: index)
        store.context.insert(set)
        e.sets.append(set)
        return set
    }

    /// Heavier lifts rest longer.
    nonisolated static func defaultRest(for ex: Exercise) -> Int {
        switch ex.kind {
        case .barbell: return 180
        case .dumbbell, .kettlebell, .bodyweight: return 90
        case .machine, .cable: return 75
        case .cardio: return 60
        }
    }
}
