// Train mock data for previews and the simulator demo mode: a library, the
// four built-in templates from the platform brief plus one custom plan, an
// active Upper/Lower enrolment and 90 days of progressive history (linked to
// MockData's strength workouts via `session_id`).
import Foundation

enum MockTrain {
    // MARK: ids

    static func uuid(_ group: Int, _ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-%04d-%012d", 9000 + group, n)) ?? UUID()
    }

    /// The history session on MockData's day `index` (0 = 89 days ago).
    static func historySessionID(dayIndex: Int) -> UUID { uuid(5, dayIndex) }

    /// MockData logs a strength workout on these days; each has a session.
    static func hasHistorySession(dayIndex: Int) -> Bool {
        let offset = MockData.historyDays - 1 - dayIndex
        return offset > 0 && [1, 5].contains(dayIndex % 7)
    }

    // MARK: library

    private static func ex(_ n: Int, _ slug: String, _ name: String, _ de: String, _ kind: ExerciseKind,
                           _ primary: [Muscle], _ secondary: [Muscle] = [], equipment: [String] = [],
                           load: LoadType = .weight, bw: Double = 0, unilateral: Bool = false) -> Exercise {
        Exercise(id: uuid(1, n), slug: slug, name: name, nameDe: de, kind: kind, primaryMuscles: primary,
                 secondaryMuscles: secondary, equipment: equipment.isEmpty ? [kind.rawValue] : equipment,
                 loadType: load, bodyweightFactor: bw, isUnilateral: unilateral)
    }

    static let squat = ex(1, "back-squat", "Back squat", "Kniebeuge", .barbell, [.quads, .glutes], [.hamstrings, .adductors, .lowerBack], equipment: ["barbell", "rack"])
    static let bench = ex(2, "bench-press", "Bench press", "Bankdrücken", .barbell, [.chest], [.triceps, .frontDelts], equipment: ["barbell", "bench"])
    static let deadlift = ex(3, "deadlift", "Deadlift", "Kreuzheben", .barbell, [.hamstrings, .glutes, .lowerBack], [.forearms, .traps])
    static let ohp = ex(4, "overhead-press", "Overhead press", "Schulterdrücken", .barbell, [.frontDelts], [.triceps, .sideDelts])
    static let row = ex(5, "barbell-row", "Barbell row", "Langhantelrudern", .barbell, [.upperBack, .lats], [.biceps, .rearDelts])
    static let pullUp = ex(6, "pull-up", "Pull-up", "Klimmzug", .bodyweight, [.lats], [.biceps, .upperBack], equipment: ["pullup_bar"], load: .bodyweight, bw: 1)
    static let dip = ex(7, "dip", "Dip", "Dip", .bodyweight, [.chest, .triceps], [.frontDelts], equipment: ["dip_bars"], load: .bodyweight, bw: 1)
    static let inclineDB = ex(8, "incline-dumbbell-press", "Incline dumbbell press", "Schrägbankdrücken mit Kurzhanteln", .dumbbell, [.chest], [.frontDelts, .triceps], equipment: ["dumbbells", "bench"])
    static let dbRow = ex(9, "dumbbell-row", "One-arm dumbbell row", "Einarmiges Kurzhantelrudern", .dumbbell, [.lats, .upperBack], [.biceps], unilateral: true)
    static let lateral = ex(10, "lateral-raise", "Lateral raise", "Seitheben", .dumbbell, [.sideDelts])
    static let curl = ex(11, "biceps-curl", "Biceps curl", "Bizepscurl", .dumbbell, [.biceps], [.forearms])
    static let pushdown = ex(12, "triceps-pushdown", "Triceps pushdown", "Trizepsdrücken am Kabel", .cable, [.triceps])
    static let facePull = ex(13, "face-pull", "Face pull", "Face Pull", .cable, [.rearDelts], [.traps, .upperBack])
    static let pulldown = ex(14, "lat-pulldown", "Lat pulldown", "Latziehen", .cable, [.lats], [.biceps])
    static let legPress = ex(15, "leg-press", "Leg press", "Beinpresse", .machine, [.quads], [.glutes])
    static let rdl = ex(16, "romanian-deadlift", "Romanian deadlift", "Rumänisches Kreuzheben", .barbell, [.hamstrings], [.glutes, .lowerBack])
    static let splitSquat = ex(17, "bulgarian-split-squat", "Bulgarian split squat", "Bulgarische Kniebeuge", .dumbbell, [.quads, .glutes], unilateral: true)
    static let legCurl = ex(18, "leg-curl", "Leg curl", "Beinbeuger", .machine, [.hamstrings])
    static let calfRaise = ex(19, "calf-raise", "Standing calf raise", "Wadenheben stehend", .machine, [.calves])
    static let frontSquat = ex(20, "front-squat", "Front squat", "Frontkniebeuge", .barbell, [.quads], [.abs, .glutes])
    static let snatch = ex(21, "snatch", "Snatch", "Reißen", .barbell, [.quads, .glutes, .frontDelts], [.traps, .upperBack])
    static let cleanJerk = ex(22, "clean-and-jerk", "Clean & jerk", "Stoßen", .barbell, [.quads, .glutes, .frontDelts], [.traps, .triceps])
    static let swing = ex(23, "kettlebell-swing", "Kettlebell swing", "Kettlebell-Swing", .kettlebell, [.glutes, .hamstrings], [.abs])
    static let plank = ex(24, "plank", "Plank", "Unterarmstütz", .bodyweight, [.abs], [.obliques], equipment: ["mat"], load: .time, bw: 0.5)
    static let erg = ex(25, "rowing-erg", "Rowing erg", "Rudergerät", .cardio, [.lats, .quads], equipment: ["rower"], load: .distance)
    static let hipThrust = ex(26, "hip-thrust", "Hip thrust", "Hip Thrust", .barbell, [.glutes], [.hamstrings])
    static let pushUp = ex(27, "push-up", "Push-up", "Liegestütz", .bodyweight, [.chest], [.triceps, .frontDelts], equipment: ["mat"], load: .bodyweight, bw: 0.64)
    static let cableFly = ex(28, "cable-fly", "Cable fly", "Kabelzug-Fliegende", .cable, [.chest])

    static let exercises: [Exercise] = [
        squat, bench, deadlift, ohp, row, pullUp, dip, inclineDB, dbRow, lateral, curl, pushdown, facePull, pulldown,
        legPress, rdl, splitSquat, legCurl, calfRaise, frontSquat, snatch, cleanJerk, swing, plank, erg, hipThrust,
        pushUp, cableFly,
    ]

    // MARK: plans

    private static func pe(_ n: Int, _ e: Exercise, _ pos: Int, _ sets: Int, _ lo: Int, _ hi: Int,
                           _ kind: TargetKind, _ value: Double?, rest: Int, superset: Int? = nil,
                           notes: String = "") -> PlanExercise {
        PlanExercise(id: uuid(3, n), exercise: e, position: pos, sets: sets, repsMin: lo, repsMax: hi,
                     targetKind: kind, targetValue: value, restSec: rest, supersetGroup: superset, notes: notes)
    }

    static let upperA = PlanDay(id: uuid(2, 1), dayIndex: 0, name: "Upper A", exercises: [
        pe(1, bench, 0, 4, 5, 5, .kg, 80, rest: 180),
        pe(2, row, 1, 4, 8, 8, .kg, 62.5, rest: 150),
        pe(3, ohp, 2, 3, 8, 8, .kg, 45, rest: 150),
        pe(4, pulldown, 3, 3, 10, 12, .rpe, 8, rest: 120, superset: 1),
        pe(5, facePull, 4, 3, 15, 15, .rpe, 8, rest: 90, superset: 1),
    ])

    static let lowerA = PlanDay(id: uuid(2, 2), dayIndex: 1, name: "Lower A", exercises: [
        pe(6, squat, 0, 3, 5, 5, .kg, 100, rest: 180),
        pe(7, rdl, 1, 3, 8, 8, .kg, 80, rest: 150),
        pe(8, splitSquat, 2, 3, 10, 10, .rpe, 8, rest: 90),
        pe(9, calfRaise, 3, 3, 12, 15, .rpe, 8, rest: 60),
    ])

    static let upperB = PlanDay(id: uuid(2, 3), dayIndex: 2, name: "Upper B", exercises: [
        pe(10, ohp, 0, 4, 5, 5, .kg, 50, rest: 180),
        pe(11, pullUp, 1, 4, 6, 8, .bodyweight, nil, rest: 150),
        pe(12, inclineDB, 2, 3, 8, 12, .rpe, 8, rest: 120),
        pe(13, curl, 3, 3, 10, 12, .rpe, 9, rest: 60, superset: 1),
        pe(14, pushdown, 4, 3, 10, 12, .rpe, 9, rest: 60, superset: 1),
    ])

    static let lowerB = PlanDay(id: uuid(2, 4), dayIndex: 3, name: "Lower B", exercises: [
        pe(15, deadlift, 0, 3, 5, 5, .kg, 130, rest: 210),
        pe(16, frontSquat, 1, 3, 6, 6, .pct1rm, 70, rest: 180),
        pe(17, legCurl, 2, 3, 10, 12, .rpe, 8, rest: 90),
        pe(18, plank, 3, 3, 1, 1, .bodyweight, nil, rest: 60, notes: "45 s holds"),
    ])

    static let upperLower = Plan(id: uuid(4, 1), name: "Upper/Lower 4×", goal: .hypertrophy, weeks: nil, daysPerWeek: 4,
                                 description: "Four days, upper and lower body alternating. Heavy compound lifts first, accessories in supersets.",
                                 progression: .linear, isBuiltin: true, days: [upperA, lowerA, upperB, lowerB])

    static let fullBody = Plan(id: uuid(4, 2), name: "Full Body 3×", goal: .strength, weeks: 12, daysPerWeek: 3,
                               description: "The classic 5×5. Squat every session, add 2.5 kg whenever all sets are done.",
                               progression: .linear, isBuiltin: true, days: [
        PlanDay(id: uuid(2, 10), dayIndex: 0, name: "Day A", exercises: [
            pe(30, squat, 0, 5, 5, 5, .kg, 100, rest: 180), pe(31, bench, 1, 5, 5, 5, .kg, 80, rest: 180),
            pe(32, row, 2, 5, 5, 5, .kg, 65, rest: 150),
        ]),
        PlanDay(id: uuid(2, 11), dayIndex: 1, name: "Day B", exercises: [
            pe(33, squat, 0, 5, 5, 5, .kg, 100, rest: 180), pe(34, ohp, 1, 5, 5, 5, .kg, 50, rest: 180),
            pe(35, deadlift, 2, 1, 5, 5, .kg, 130, rest: 240),
        ]),
    ])

    static let weightlifting = Plan(id: uuid(4, 3), name: "Weightlifting 4×", goal: .weightlifting, weeks: 8, daysPerWeek: 4,
                                    description: "Snatch, clean & jerk, squats and pulls at a percentage of your 1RM, building over each block.",
                                    progression: .percent, isBuiltin: true, days: (1...3).flatMap { week -> [PlanDay] in
        let pct = Double(65 + week * 5)
        return [
            PlanDay(id: uuid(2, 20 + week * 2), week: week, dayIndex: 0, name: "Snatch day", exercises: [
                pe(40 + week * 10, snatch, 0, 6, 2, 2, .pct1rm, pct, rest: 120),
                pe(41 + week * 10, frontSquat, 1, 4, 3, 3, .pct1rm, pct + 5, rest: 180),
            ]),
            PlanDay(id: uuid(2, 21 + week * 2), week: week, dayIndex: 1, name: "Clean & jerk day", exercises: [
                pe(42 + week * 10, cleanJerk, 0, 5, 2, 2, .pct1rm, pct, rest: 150),
                pe(43 + week * 10, squat, 1, 4, 4, 4, .pct1rm, pct + 5, rest: 180),
            ]),
        ]
    })

    static let fiveThreeOne = Plan(id: uuid(4, 4), name: "5/3/1 4×", goal: .strength, weeks: 4, daysPerWeek: 4,
                                   description: "Wendler's 5/3/1: one main lift a day at 65–85 % of a training max, then assistance work.",
                                   progression: .percent, isBuiltin: true, days: [
        (squat, "Squat day"), (bench, "Bench day"), (deadlift, "Deadlift day"), (ohp, "Press day"),
    ].enumerated().map { i, item in
        PlanDay(id: uuid(2, 40 + i), dayIndex: i, name: item.1, exercises: [
            pe(80 + i * 3, item.0, 0, 3, 5, 5, .pct1rm, 75, rest: 180),
            pe(81 + i * 3, i % 2 == 0 ? rdl : dbRow, 1, 5, 10, 10, .rpe, 7, rest: 90),
            pe(82 + i * 3, i % 2 == 0 ? plank : pullUp, 2, 3, 1, 8, .bodyweight, nil, rest: 60),
        ])
    })

    static let homeDumbbells = Plan(id: uuid(4, 5), name: "Home dumbbells", goal: .general, weeks: nil, daysPerWeek: 2,
                                    description: "Short sessions for travel weeks.", progression: Progression.none, isBuiltin: false, days: [
        PlanDay(id: uuid(2, 60), dayIndex: 0, name: "Full body", exercises: [
            pe(100, splitSquat, 0, 3, 10, 12, .rpe, 8, rest: 60, superset: 1),
            pe(101, pushUp, 1, 3, 12, 20, .bodyweight, nil, rest: 60, superset: 1),
            pe(102, dbRow, 2, 3, 10, 12, .rpe, 8, rest: 60),
            pe(103, swing, 3, 3, 15, 15, .kg, 24, rest: 60),
        ]),
    ])

    static let plans = [upperLower, fullBody, weightlifting, fiveThreeOne, homeDumbbells]

    static let enrollment = Enrollment(id: uuid(6, 1), planId: upperLower.id,
                                       startedAt: DayFormat.shift(Calendar.current.startOfDay(for: .now), days: -38),
                                       currentWeek: 6, currentDayIndex: 0, status: .active)

    static func catalog(enrolled: Bool = true) -> PlansOverview {
        PlansOverview(builtin: plans.filter(\.isBuiltin).map(PlanSummary.init),
                      mine: plans.filter { !$0.isBuiltin }.map(PlanSummary.init),
                      active: enrolled ? enrollment : nil)
    }

    static var planToday: PlanToday { planToday(for: upperA, enrollment: enrollment) }

    static func planToday(for day: PlanDay, enrollment: Enrollment) -> PlanToday {
        let targets = day.exercises.map { e in
            let last = lastSets(for: e.exercise.id)
            let kg: Double? = switch e.targetKind {
            case .kg: (last.compactMap(\.weightKg).max()).map { max($0, e.targetValue ?? 0) } ?? e.targetValue
            case .pct1rm: bestE1RM(for: e.exercise.id).map { Self.roundTo2_5($0 * (e.targetValue ?? 70) / 100) }
            default: last.compactMap(\.weightKg).max()
            }
            return PlanTarget(planExerciseId: e.id, exerciseId: e.exerciseId, sets: e.sets, repsMin: e.repsMin,
                              repsMax: e.repsMax, targetKind: e.targetKind,
                              targetKg: e.targetKind == .rpe || e.targetKind == .bodyweight ? nil : kg,
                              restSec: e.restSec, lastTime: last.filter { !$0.isWarmup })
        }
        return PlanToday(enrollment: enrollment, day: day, targets: targets)
    }

    static func roundTo2_5(_ kg: Double) -> Double { (kg / 2.5).rounded() * 2.5 }

    // MARK: history

    /// Completed sessions over the last 90 days, oldest first.
    static let history: [TrainSession] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let rotation = [upperA, lowerA, upperB, lowerB]
        var out: [TrainSession] = []
        var count = 0
        var rng = SeededRandom(seed: 314)
        for i in 0..<MockData.historyDays where hasHistorySession(dayIndex: i) {
            let offset = MockData.historyDays - 1 - i
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let start = cal.date(bySettingHour: 18, minute: 12, second: 0, of: date) ?? date
            let day = rotation[count % rotation.count]
            // +~12 % over the 90 days, rounded to plates.
            let progress = 0.88 + 0.12 * Double(i) / Double(MockData.historyDays)
            var t = start
            var exercises: [SessionExercise] = []
            for (pos, pe) in day.exercises.enumerated() {
                let base = pe.targetValue.flatMap { pe.targetKind == .kg ? $0 : nil } ?? workingWeight(for: pe.exercise)
                let kg = base.map { roundTo2_5($0 * progress) }
                var sets: [SessionSet] = []
                if pos == 0, let kg {
                    t += 90
                    sets.append(SessionSet(id: uuid(7, count * 100 + pos * 10), setIndex: 0, reps: 5, weightKg: roundTo2_5(kg * 0.6),
                                         isWarmup: true, completedAt: t, updatedAt: t))
                }
                for n in 0..<pe.sets {
                    t += 45 + Double(pe.restSec)
                    let missed = n == pe.sets - 1 && rng.next(in: 0...1) < 0.2
                    let reps = missed ? max(1, pe.repsMin - 1) : (rng.next(in: 0...1) < 0.5 ? pe.repsMin : pe.repsMax)
                    sets.append(SessionSet(id: uuid(7, count * 100 + pos * 10 + n + 1), setIndex: sets.count, reps: reps,
                                         weightKg: kg, rpe: n == pe.sets - 1 ? 8.5 : nil,
                                         durationSec: pe.exercise.loadType == .time ? 45 : nil,
                                         completedAt: t, updatedAt: t))
                }
                exercises.append(SessionExercise(id: uuid(8, count * 10 + pos), exerciseId: pe.exercise.id,
                                                      position: pos, sets: sets))
            }
            var s = TrainSession(id: historySessionID(dayIndex: i), title: day.name, startedAt: start, endedAt: t + 60,
                                 status: .completed, planDayId: day.id,
                                 workoutId: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", i * 10 + 1)),
                                 bodyweightKg: 80, exercises: exercises)
            let load = MockTrainScoring.load(of: s)
            s.muscularTrimp = load
            s.strain = MockTrainScoring.strain(forTrimp: load)
            s.volumeKg = Volume.of(exercises.flatMap(\.sets))
            out.append(s)
            count += 1
        }
        return out
    }()

    /// Typical working weight where the plan prescribes by RPE / %.
    private static func workingWeight(for e: Exercise) -> Double? {
        switch e.slug {
        case "lat-pulldown": return 60
        case "face-pull": return 20
        case "bulgarian-split-squat": return 20
        case "standing-calf-raise", "calf-raise": return 80
        case "incline-dumbbell-press": return 26
        case "biceps-curl": return 14
        case "triceps-pushdown": return 30
        case "front-squat": return 80
        case "leg-curl": return 45
        case "pull-up", "plank": return nil
        default: return 40
        }
    }

    static func lastSets(for exerciseID: UUID) -> [SessionSet] {
        history.last { $0.exercises.contains { $0.exerciseId == exerciseID } }?
            .exercises.first { $0.exerciseId == exerciseID }?.sets ?? []
    }

    static func bestE1RM(for exerciseID: UUID) -> Double? {
        E1RM.best(of: history.flatMap { $0.exercises.filter { $0.exerciseId == exerciseID }.flatMap(\.sets) })
    }

    static func sessions(on day: String) -> [SessionSummary] {
        history.filter { DayFormat.string(from: $0.startedAt) == day }.map(SessionSummary.init)
    }

    static func exerciseHistory(for id: UUID, sessions: [TrainSession]) -> ExerciseHistory {
        let relevant = sessions.filter { $0.status == .completed && $0.exercises.contains { $0.exerciseId == id } }
            .sorted { $0.startedAt < $1.startedAt }
        let entries = relevant.map { s in
            ExerciseHistorySession(sessionId: s.id, date: DayFormat.string(from: s.startedAt), startedAt: s.startedAt,
                                   sets: s.exercises.filter { $0.exerciseId == id }.flatMap(\.sets))
        }
        let points = entries.compactMap { e in
            E1RM.best(of: e.sets).map { E1RMPoint(day: e.date, value: ($0 * 10).rounded() / 10) }
        }
        return ExerciseHistory(exerciseId: id, prs: MockTrainScoring.records(for: id, in: entries),
                               sessions: entries.reversed(), e1rm: points)
    }

    // MARK: previews

    /// An in-progress Upper A with two sets checked off, as on the gym floor.
    @MainActor
    static func liveSession(in store: TrainStore, started: TimeInterval = -23 * 60) -> LocalSession {
        let s = SessionFactory.fromPlan(day: upperA, today: planToday, library: exercises, in: store)
        s.startedAt = Date.now.addingTimeInterval(started)
        let first = s.orderedExercises[0]
        for set in first.orderedSets.prefix(2) {
            let ghost = first.ghost(forSetAt: set.setIndex)
            set.reps = ghost.reps
            set.weightKg = ghost.kg
            set.completedAt = .now.addingTimeInterval(-200 + Double(set.setIndex) * 150)
        }
        s.restEndsAt = .now.addingTimeInterval(95)
        s.restTotal = 180
        store.save()
        return s
    }

    /// A finished session as `…/complete` returns it, for the summary sheet.
    static var completed: TrainSession {
        var s = history[history.count - 1]
        s.notes = "Felt strong, last set grindy."
        s.prs = [
            PersonalRecord(exerciseId: bench.id, kind: .e1rm, value: 96.5, sessionId: s.id, achievedAt: .now),
            PersonalRecord(exerciseId: row.id, kind: .maxWeight, value: 70, sessionId: s.id, achievedAt: .now),
        ]
        return s
    }
}

/// Demo-only stand-in for the platform's scoring (`strength.go`), relative to
/// each exercise's best set: a typical mock session (heavy compounds plus
/// accessories) lands near the platform's reference (load ≈ 85, strain ≈ 11).
enum MockTrainScoring {
    static func load(of s: TrainSession) -> Double {
        var total = 0.0
        for e in s.exercises {
            guard let best = E1RM.best(of: e.sets), best > 0 else {
                total += Double(e.sets.filter { $0.completedAt != nil }.count) * 1.2 // bodyweight/time
                continue
            }
            for set in e.sets where set.completedAt != nil {
                let intensity = (set.weightKg ?? 0) / best
                let l = Double(set.reps ?? 0) * intensity * intensity
                total += set.isWarmup ? l * 0.25 : l
            }
        }
        return (total * 0.95).rounded()
    }

    static func strain(forTrimp t: Double) -> Double {
        ((21 * (1 - exp(-t / 120))) * 10).rounded() / 10
    }

    static func records(for id: UUID, in entries: [ExerciseHistorySession]) -> [PersonalRecord] {
        var out: [PersonalRecord] = []
        let all = entries.flatMap { e in e.sets.filter { !$0.isWarmup }.map { (e.startedAt, $0) } }
        if let best = all.max(by: { (E1RM.estimate(weightKg: $0.1.weightKg, reps: $0.1.reps) ?? 0)
                                    < (E1RM.estimate(weightKg: $1.1.weightKg, reps: $1.1.reps) ?? 0) }),
           let v = E1RM.estimate(weightKg: best.1.weightKg, reps: best.1.reps) {
            out.append(PersonalRecord(exerciseId: id, kind: .e1rm, value: E1RM.rounded(v), achievedAt: best.0))
        }
        if let heavy = all.max(by: { ($0.1.weightKg ?? 0) < ($1.1.weightKg ?? 0) }), let kg = heavy.1.weightKg {
            out.append(PersonalRecord(exerciseId: id, kind: .maxWeight, value: kg, achievedAt: heavy.0))
        }
        if let reps = all.max(by: { ($0.1.reps ?? 0) < ($1.1.reps ?? 0) }), let r = reps.1.reps {
            out.append(PersonalRecord(exerciseId: id, kind: .maxReps, value: Double(r), achievedAt: reps.0))
        }
        return out
    }
}

/// `TrainDataSource` for previews and demo mode: the platform's behaviour in memory.
actor MockTrainSource: TrainDataSource {
    static let shared = MockTrainSource()

    private var customExercises: [Exercise] = []
    private var myPlans: [Plan] = MockTrain.plans.filter { !$0.isBuiltin }
    private var enrollment: Enrollment? = MockTrain.enrollment
    private var sessions: [UUID: TrainSession] = Dictionary(MockTrain.history.map { ($0.id, $0) },
                                                             uniquingKeysWith: { a, _ in a })

    func exercises() async throws -> [Exercise] { MockTrain.exercises + customExercises }

    func createExercise(_ e: Exercise) async throws -> Exercise {
        var custom = e
        custom.isCustom = true
        customExercises.removeAll { $0.id == e.id }
        customExercises.append(custom)
        return custom
    }

    func exerciseHistory(id: UUID) async throws -> ExerciseHistory {
        MockTrain.exerciseHistory(for: id, sessions: Array(sessions.values))
    }

    private var allPlans: [Plan] { MockTrain.plans.filter(\.isBuiltin) + myPlans }

    func plans() async throws -> PlansOverview {
        PlansOverview(builtin: allPlans.filter(\.isBuiltin).map(PlanSummary.init),
                      mine: myPlans.map(PlanSummary.init),
                      active: enrollment?.status == .active ? enrollment : nil)
    }

    func plan(id: UUID) async throws -> Plan {
        guard let p = allPlans.first(where: { $0.id == id }) else { throw APIError.http(404, "plan not found") }
        return p
    }

    func savePlan(_ p: Plan) async throws -> Plan {
        var mine = p
        mine.isBuiltin = false
        myPlans.removeAll { $0.id == p.id }
        myPlans.append(mine)
        return mine
    }

    func deletePlan(id: UUID) async throws {
        myPlans.removeAll { $0.id == id }
        if enrollment?.planId == id { enrollment = nil }
    }

    /// A paused enrolment in the same plan resumes where it stopped (200), else week 1 day 0 (201).
    func enroll(planID: UUID) async throws -> Enrollment {
        if var e = enrollment, e.planId == planID {
            e.status = .active
            enrollment = e
            return e
        }
        let e = Enrollment(id: UUID(), planId: planID, startedAt: .now, currentWeek: 1, currentDayIndex: 0, status: .active)
        enrollment = e
        return e
    }

    func pauseEnrollment() async throws {
        enrollment?.status = .paused
    }

    func planToday() async throws -> PlanToday? {
        guard let e = enrollment, e.status == .active,
              let plan = allPlans.first(where: { $0.id == e.planId }) else { return nil }
        let days = plan.days.filter { $0.week == nil || $0.week == e.currentWeek }
        guard !days.isEmpty else { return nil }
        // Done for today once a session of this plan finished today.
        let doneToday = sessions.values.contains { s in
            s.status == .completed && Calendar.current.isDateInToday(s.startedAt)
                && plan.days.contains { $0.id == s.planDayId }
        }
        guard !doneToday else { return nil }
        let day = days[e.currentDayIndex % days.count]
        return MockTrain.planToday(for: day, enrollment: e)
    }

    func sessions(from: Date, to: Date) async throws -> [SessionSummary] {
        sessions.values.filter { $0.startedAt >= from && $0.startedAt <= to }
            .sorted { $0.startedAt > $1.startedAt }.map(SessionSummary.init)
    }

    func session(id: UUID) async throws -> TrainSession {
        guard let s = sessions[id] else { throw APIError.http(404, "session not found") }
        return s
    }

    func putSession(_ s: TrainSession) async throws -> SessionPutResult {
        // `completed` only for a session that already is (API.md); finishing is `…/complete`.
        if s.status == .completed, sessions[s.id]?.status != .completed {
            throw APIError.http(422, "use /complete to finish a session")
        }
        // The platform merges by set id while in progress.
        let merged = sessions[s.id].map { SessionMerge.merge(local: s, server: $0) } ?? s
        sessions[s.id] = merged
        return .saved(merged)
    }

    func completeSession(id: UUID, _ body: SessionComplete) async throws -> TrainSession {
        guard var s = sessions[id] else { throw APIError.http(404, "session not found") }
        guard s.status != .discarded else { throw APIError.http(409, "session discarded") }
        let before = Array(sessions.values.filter { $0.id != id && $0.status == .completed })
        s.status = .completed
        s.endedAt = body.endedAt ?? s.endedAt ?? .now
        s.bodyweightKg = body.bodyweightKg ?? s.bodyweightKg
        let load = MockTrainScoring.load(of: s)
        s.muscularTrimp = load
        s.strain = MockTrainScoring.strain(forTrimp: load)
        s.volumeKg = Volume.of(s.exercises.flatMap(\.sets))
        sessions[id] = s
        var prs: [PersonalRecord] = []
        for e in s.exercises {
            let earlier = before.flatMap { $0.exercises.filter { $0.exerciseId == e.exerciseId }.flatMap(\.sets) }
            let working = e.sets.filter { !$0.isWarmup && $0.completedAt != nil }
            if let now = E1RM.best(of: working), now > (E1RM.best(of: earlier) ?? 0) {
                prs.append(PersonalRecord(exerciseId: e.exerciseId, kind: .e1rm, value: (now * 10).rounded() / 10,
                                          sessionId: id, achievedAt: .now))
            }
            if let kg = working.compactMap(\.weightKg).max(), kg > (earlier.filter { !$0.isWarmup }.compactMap(\.weightKg).max() ?? 0) {
                prs.append(PersonalRecord(exerciseId: e.exerciseId, kind: .maxWeight, value: kg, sessionId: id, achievedAt: .now))
            }
        }
        if var e = enrollment, let day = s.planDayId,
           let plan = allPlans.first(where: { $0.id == e.planId }), plan.days.contains(where: { $0.id == day }) {
            e.currentDayIndex += 1
            enrollment = e
        }
        s.prs = prs
        sessions[id] = s
        return s
    }

    func deleteSession(id: UUID) async throws { sessions[id] = nil }
}
