import Foundation

/// One distinct exercise of an import: every spelling with the same key is one row in step 4 and is matched once.
struct ImportedExerciseSource: Equatable, Sendable {
    let key: SourceExerciseKey
    /// The first spelling in the files, as written: shown in step 4 only, never stored or logged.
    let name: String
    let equipment: String?
    var inPlan = false
    var inHistory = false
    /// The `+N` loads (the bodyweight question, design §5); nil when there are none.
    var plusLoads: PlusLoadSummary?
    /// Some sets log assistance (`-N`): imported as reps only (`.assistedLoad`).
    var hasAssistedSets = false

    /// " · Machine" after the name; empty without equipment. Step 4's row title draws it in a second colour.
    var equipmentSuffix: String { equipment.map { " · \($0)" } ?? "" }
    /// "Reverse Fly · Machine": the row title as one string, for naming the row elsewhere ("Also used for …").
    var displayName: String { name + equipmentSuffix }
}

extension ExerciseNormalizer {
    /// The bundle's distinct exercises in first-seen order: plans, then sessions, in file order.
    func sources(in bundle: ImportBundle) -> [ImportedExerciseSource] {
        var sources: [ImportedExerciseSource] = []
        var position: [SourceExerciseKey: Int] = [:]
        var plus: [SourceExerciseKey: [Double]] = [:]

        func entry(_ name: String, _ equipment: String?) -> SourceExerciseKey {
            let found = self.key(name: name, equipment: equipment)
            if position[found] == nil {
                position[found] = sources.count
                sources.append(ImportedExerciseSource(key: found, name: name, equipment: equipment))
            }
            return found
        }
        func update(_ key: SourceExerciseKey, _ change: (inout ImportedExerciseSource) -> Void) {
            guard let index = position[key], sources.indices.contains(index) else { return }
            change(&sources[index])
        }

        for plan in bundle.plans {
            for day in plan.days {
                for exercise in day.exercises {
                    update(entry(exercise.name, exercise.equipment)) { $0.inPlan = true }
                }
            }
        }
        for session in bundle.sessions {
            for exercise in session.exercises {
                let key = entry(exercise.name, exercise.equipment)
                var assisted = false
                for set in exercise.sets {
                    switch set.load {
                    case let .plus(kg): plus[key, default: []].append(kg)
                    case .minus: assisted = true
                    case .weight, nil: break
                    }
                }
                update(key) {
                    $0.inHistory = true
                    $0.hasAssistedSets = $0.hasAssistedSets || assisted
                }
            }
        }
        for (key, kilograms) in plus {
            update(key) { $0.plusLoads = PlusLoadSummary(kilograms: kilograms) }
        }
        return sources
    }
}
