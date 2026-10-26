import Foundation
@testable import Ryft

/// Decisions and a library for the synthetic fixtures (`ap-plans.csv`, `ap-workouts.csv`, `-plus1.csv`): every source
/// exercise mapped to an invented library exercise, pull-ups and push-ups as bodyweight exercises.
enum ImportBuildFixture {
    static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    /// After every workout in the fixtures.
    static let now = Date(timeIntervalSince1970: 1_792_400_000) // 2026-10-19

    /// Source name and equipment → kind and load type of the library exercise it maps to.
    static let sources: [(name: String, equipment: String, kind: ExerciseKind, load: LoadType)] = [
        ("Overhead Press", "Barbell", .barbell, .weight),
        ("Push-Ups", "Bodyweight", .bodyweight, .bodyweight),
        ("Cable Fly", "Cable", .cable, .weight),
        ("Deadlift", "Barbell", .barbell, .weight),
        ("Pull-Ups", "Bodyweight", .bodyweight, .bodyweight),
        ("Seated Cable Row", "Cable", .cable, .weight),
        ("Walking Lunges", "Dumbbells", .dumbbell, .weight),
        ("Goblet Squat", "Kettlebell", .kettlebell, .weight),
        ("Hip Thrust", "Barbell", .barbell, .weight),
        ("Arnold Press", "Dumbbells", .dumbbell, .weight),
    ]

    static func key(_ name: String, _ equipment: String? = nil) -> SourceExerciseKey {
        ImportBuildContext.key(name, equipment ?? sources.first { $0.name == name }?.equipment)
    }

    /// A stable library exercise per source exercise.
    static func exercise(_ name: String) -> Exercise {
        let index = sources.firstIndex { $0.name == name } ?? 99
        let kind = sources.indices.contains(index) ? sources[index].kind : .machine
        let load = sources.indices.contains(index) ? sources[index].load : .weight
        return Exercise(id: id(index + 1), slug: name.lowercased(), name: name, kind: kind,
                        primaryMuscles: [.chest], loadType: load, bodyweightFactor: load == .bodyweight ? 1 : 0)
    }

    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n)) ?? UUID()
    }

    /// Plans then workouts, as two picked files.
    static func bundle(workouts: String = "ap-workouts", plans: Bool = true) throws -> ImportBundle {
        let sessions = try ImportFixture.parse(workouts)
        guard plans else { return sessions }
        return try ImportFixture.parse("ap-plans").merging(sessions.inFile(1))
    }

    /// Every source mapped to its library exercise, except `skipping`; `answers` for the `+N` question.
    static func decisions(account: String = "demo", zone: TimeZone = berlin, skipping: Set<String> = [],
                          answers: [String: BodyweightAnswer] = [:], plans: [ImportPlanChoice] = [],
                          history: ImportHistoryChoice = ImportHistoryChoice(), enrol: Int? = nil) -> ImportDecisions {
        var exercises: [SourceExerciseKey: ImportExerciseChoice] = [:]
        for source in sources {
            let target: ImportExerciseChoice.Target = skipping.contains(source.name) ? .skip : .library(exercise(source.name))
            exercises[key(source.name, source.equipment)] = ImportExerciseChoice(target, bodyweight: answers[source.name])
        }
        return ImportDecisions(account: account, zone: zone, exercises: exercises, plans: plans, history: history,
                               enrolPlanIndex: enrol)
    }

    static func build(_ bundle: ImportBundle, _ decisions: ImportDecisions, existing: ImportExisting = .unchecked,
                      now: Date = now) throws -> ImportBuild {
        try ImportBuilder.buildNow(bundle, decisions: decisions, existing: existing, now: now)
    }

    static func date(_ text: String) -> LocalDate? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return LocalDate(year: parts[0], month: parts[1], day: parts[2])
    }

    static func time(_ day: String, _ hour: Int, _ minute: Int) -> LocalDateTime? {
        date(day).flatMap { LocalDateTime(date: $0, hour: hour, minute: minute) }
    }

    /// A one-session bundle built by hand: exercises as (name, sets of (load, reps)).
    static func session(title: String = "Upper", day: String = "2026-03-14", hour: Int = 18, minute: Int = 0,
                        minutes: Int? = 60, plan: ImportedSession.PlanRef? = nil,
                        exercises: [(String, [(ImportedLoad?, Int?)])]) -> ImportedSession? {
        guard let start = time(day, hour, minute) else { return nil }
        let rows = exercises.enumerated().map { index, row in
            ImportedSessionExercise(order: index + 1, name: row.0, equipment: sources.first { $0.name == row.0 }?.equipment,
                                    targetReps: nil, unit: .kg,
                                    sets: row.1.enumerated().map { ImportedSet(ordinal: $0.offset, load: $0.element.0, reps: $0.element.1) })
        }
        return ImportedSession(title: title, plan: plan, start: start, durationMinutes: minutes, exercises: rows,
                               source: SourceLine(file: 0, line: 1))
    }

    static func bundle(_ sessions: [ImportedSession?], plans: [ImportedPlan] = []) -> ImportBundle {
        ImportBundle(format: .alphaProgression, plans: plans, sessions: sessions.compactMap { $0 }, warnings: [],
                     suppressedWarnings: 0, lineCount: 1)
    }
}
