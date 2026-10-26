import Foundation

/// What every step of a build reads: the bundle, the decisions, what exists, and lookups derived once.
struct ImportBuildContext: Sendable {
    let bundle: ImportBundle
    let decisions: ImportDecisions
    let existing: ImportExisting
    /// `ImportIDs.account(decisions.account)`: the parent of every top-level id.
    let account: UUID
    let resolver: ImportTimeResolver
    /// The derived session ids, in the bundle's order.
    let sessionIDs: [UUID]
    /// Every source exercise in first-seen order (plans, then sessions): a stable order for custom exercises.
    let exerciseOrder: [SourceExerciseKey]
    /// The `+N` loads per source exercise, for the bodyweight answer's default (design §5).
    let plusLoads: [SourceExerciseKey: PlusLoadSummary]

    var source: ImportFormatID { bundle.format }

    init(bundle: ImportBundle, decisions: ImportDecisions, existing: ImportExisting) {
        self.bundle = bundle
        self.decisions = decisions
        self.existing = existing
        account = ImportIDs.account(decisions.account)
        resolver = ImportTimeResolver(zone: decisions.zone)
        sessionIDs = ImportBuilder.sessionIDs(of: bundle, account: account)
        var order: [SourceExerciseKey] = []
        var seen = Set<SourceExerciseKey>()
        var plus: [SourceExerciseKey: [Double]] = [:]
        for plan in bundle.plans {
            for day in plan.days {
                for exercise in day.exercises {
                    let key = Self.key(exercise.name, exercise.equipment)
                    if seen.insert(key).inserted { order.append(key) }
                }
            }
        }
        for session in bundle.sessions {
            for exercise in session.exercises {
                let key = Self.key(exercise.name, exercise.equipment)
                if seen.insert(key).inserted { order.append(key) }
                for set in exercise.sets {
                    if case let .plus(kg)? = set.load { plus[key, default: []].append(kg) }
                }
            }
        }
        exerciseOrder = order
        plusLoads = plus.compactMapValues(PlusLoadSummary.init(kilograms:))
    }

    /// The frozen key of a name and equipment field (`ExerciseNormalizer.key`, ADR 0007 Amendment 1).
    static func key(_ name: String, _ equipment: String?) -> SourceExerciseKey {
        SourceExerciseKey(name: SourceExerciseKey.fold(name), equipment: SourceExerciseKey.fold(equipment ?? ""))
    }

    /// The RYFT exercise a source exercise became; nil when it's left out.
    func exercise(for key: SourceExerciseKey) -> Exercise? {
        decisions.exercises[key]?.exercise
    }

    /// The answer that applies to `+N` sets of this source exercise for its match's load type: the user's while it's
    /// still offered, else the default; nil for `time` and `distance`.
    func bodyweightAnswer(for key: SourceExerciseKey, loadType: LoadType) -> BodyweightAnswer? {
        guard let plus = plusLoads[key] else { return nil }
        return BodyweightAnswer.resolved(decisions.exercises[key]?.bodyweight, for: loadType, plus: plus)
    }
}

/// Names and titles as the platform takes them.
enum ImportText {
    /// At most `max` Unicode scalars, whole characters only, trailing spaces trimmed (as `ImportCustomExercise.cut`).
    static func cut(_ text: String, max: Int) -> String {
        var out = ""
        var scalars = 0
        for character in text {
            let count = character.unicodeScalars.count
            guard scalars + count <= max else { break }
            out.append(character)
            scalars += count
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Cleaned (`ImportCustomExercise.clean`) and cut.
    static func title(_ text: String, max: Int) -> String {
        cut(ImportCustomExercise.clean(text), max: max)
    }
}

extension LocalDate {
    /// Days since 1970-01-01 (proleptic Gregorian).
    var dayNumber: Int { ImportTimeResolver.daysFromCivil(year: year, month: month, day: day) }
}
