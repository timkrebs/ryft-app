import Foundation

/// A file's plans as RYFT plans (design §8): derived ids, days in the file's order of day numbers, rows the user left
/// out dropped, sets and reps within the plan builder's limits, and targets from the imported history.
enum ImportPlanAssembly {
    /// The plan builder's defaults where the file names no reps, and the target without history (design §8: the plan
    /// checks refuse a `kg` target without a value, and RPE shows no weight).
    static let defaultReps = 8...12
    static let defaultRPE = 8.0
    /// The most days a RYFT plan has.
    static let maxDays = 7

    /// A plan before its targets: what sessions need to point into it.
    struct Draft: Sendable {
        let index: Int
        let id: UUID
        let state: ImportPlanPreview.State
        let plan: Plan?
        let willBeSent: Bool
        let skippedExerciseNames: [String]
        let links: Links
    }

    /// The ids a session links to, derived the same way whether the plan is sent or already in RYFT.
    struct Links: Sendable {
        /// Day number → the first day with that number.
        var days: [Int: UUID] = [:]
        /// Plan day id → source exercise → its plan exercise ids by occurrence (rows left out have none).
        var exercises: [UUID: [SourceExerciseKey: [Int: UUID]]] = [:]
    }

    static func plans(_ context: ImportBuildContext) throws -> [Draft] {
        try context.bundle.plans.enumerated().map { index, plan in
            try Task.checkCancellation()
            return draft(plan, index: index, context: context)
        }
    }

    private static func draft(_ file: ImportedPlan, index: Int, context: ImportBuildContext) -> Draft {
        let id = ImportIDs.plan(account: context.account, source: context.source, name: file.name,
                                startDate: file.startDate)
        let choice = context.decisions.plans.indices.contains(index) ? context.decisions.plans[index] : ImportPlanChoice()
        var links = Links()
        var days: [PlanDay] = []
        var skipped: [String] = []
        var dayOccurrences: [Int: Int] = [:]
        // The file's order of day numbers; days with the same number keep their order.
        let ordered = file.days.enumerated().sorted { ($0.element.number, $0.offset) < ($1.element.number, $1.offset) }
        for (_, day) in ordered {
            let occurrence = dayOccurrences[day.number, default: 0]
            dayOccurrences[day.number] = occurrence + 1
            let dayID = ImportIDs.planDay(plan: id, number: day.number, occurrence: occurrence)
            if links.days[day.number] == nil { links.days[day.number] = dayID }
            var exercises: [PlanExercise] = []
            var keyOccurrences: [SourceExerciseKey: Int] = [:]
            for row in day.exercises {
                let key = ImportBuildContext.key(row.name, row.equipment)
                let occurrence = keyOccurrences[key, default: 0]
                keyOccurrences[key] = occurrence + 1
                guard let exercise = context.exercise(for: key) else {
                    skipped.append(row.name)
                    continue
                }
                let rowID = ImportIDs.planExercise(day: dayID, key: key, occurrence: occurrence)
                links.exercises[dayID, default: [:]][key, default: [:]][occurrence] = rowID
                let reps = row.targetReps ?? defaultReps
                let repsMin = min(max(reps.lowerBound, 1), PlanValidation.maxReps)
                let repsMax = min(max(reps.upperBound, repsMin), PlanValidation.maxReps)
                exercises.append(PlanExercise(id: rowID, exercise: exercise, position: exercises.count,
                                              sets: min(max(row.sets, 1), PlanValidation.maxSets), repsMin: repsMin,
                                              repsMax: repsMax, targetKind: target(for: exercise, lastKg: nil).kind,
                                              targetValue: target(for: exercise, lastKg: nil).value,
                                              restSec: SessionFactory.defaultRest(for: exercise)))
            }
            // A day whose every row was left out can't be a RYFT plan day (`PlanValidation`): it goes.
            guard !exercises.isEmpty else { continue }
            days.append(PlanDay(id: dayID, week: nil, dayIndex: days.count,
                                name: ImportText.title(day.name, max: ImportBuilder.maxPlanNameLength), exercises: exercises))
        }
        let weeks = file.weeks.flatMap { (1...52).contains($0) ? $0 : nil }
        let plan = Plan(id: id, name: ImportText.title(file.name, max: ImportBuilder.maxPlanNameLength), goal: .general,
                        weeks: weeks, daysPerWeek: days.count, description: "", progression: .linear, isBuiltin: false,
                        days: days)
        let refusal: ImportPlanRefusal? = if days.count > maxDays {
            .tooManyDays(days.count)
        } else if days.isEmpty {
            .noExercises
        } else if case let issues = PlanValidation.issues(in: plan), !issues.isEmpty {
            .invalid(issues)
        } else {
            nil
        }
        let state: ImportPlanPreview.State = if let refusal {
            .cannotImport(refusal)
        } else if context.existing.plans[id] != nil {
            .alreadyInRYFT
        } else {
            .new
        }
        let sent = refusal == nil && choice.included && (state == .new || choice.replaceExisting)
        return Draft(index: index, id: id, state: state, plan: refusal == nil ? plan : nil, willBeSent: sent,
                     skippedExerciseNames: skipped, links: links)
    }

    /// A plan exercise's target (design §8): a `weight` exercise with history starts at its last weight, without it
    /// at RPE 8; a bodyweight exercise is `bodyweight` without a value (API.md; T11); `time` and `distance` RPE 8.
    static func target(for exercise: Exercise, lastKg: Double?) -> (kind: TargetKind, value: Double?) {
        switch exercise.loadType {
        case .weight:
            if let lastKg, lastKg > 0, lastKg <= ImportSessionAssembly.maxWeightKg { return (.kg, lastKg) }
            return (.rpe, defaultRPE)
        case .bodyweight:
            return (.bodyweight, nil)
        case .time, .distance:
            return (.rpe, defaultRPE)
        }
    }

    /// The drafts with their "last time" targets: the heaviest performed set of the most recent imported session with
    /// the exercise and a weight, the same plan day first (design §8). Imported means in the chosen history: new,
    /// duplicates and those already imported.
    static func withLastTime(_ drafts: [Draft], sessions: [ImportSessionPreview], refs: [UUID: ImportSessionAssembly.DayRef],
                             context: ImportBuildContext) throws -> [ImportPlanPreview] {
        let history = sessions.filter { preview in
            switch preview.verdict {
            case .new, .duplicate, .alreadyImported: preview.session != nil
            case .outsideRange, .inFuture, .empty, .historyOff: false
            }
        }
        .sorted { ($0.startedAt, $0.id.uuidString) > ($1.startedAt, $1.id.uuidString) }
        return try drafts.map { draft in
            try Task.checkCancellation()
            guard var plan = draft.plan else {
                return ImportPlanPreview(index: draft.index, id: draft.id, state: draft.state, plan: nil,
                                         willBeSent: false, lastTime: [:], skippedExerciseNames: draft.skippedExerciseNames)
            }
            var lastTime: [UUID: ImportLastTime] = [:]
            let dayNumbers = Dictionary(draft.links.days.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
            for (d, day) in plan.days.enumerated() {
                let number = dayNumbers[day.id]
                for (e, row) in day.exercises.enumerated() where row.exercise.loadType == .weight {
                    let sameDay = history.filter { preview in
                        guard let number, let ref = refs[preview.id] else { return false }
                        return ref.planIndex == draft.index && ref.dayNumber == number
                    }
                    guard let last = latestWeight(of: row.exerciseId, in: sameDay) ?? latestWeight(of: row.exerciseId, in: history)
                    else { continue }
                    let target = target(for: row.exercise, lastKg: last.kg)
                    plan.days[d].exercises[e].targetKind = target.kind
                    plan.days[d].exercises[e].targetValue = target.value
                    if target.kind == .kg { lastTime[row.id] = last }
                }
            }
            return ImportPlanPreview(index: draft.index, id: draft.id, state: draft.state, plan: plan,
                                     willBeSent: draft.willBeSent, lastTime: lastTime,
                                     skippedExerciseNames: draft.skippedExerciseNames)
        }
    }

    /// The first session (newest first) where the exercise has a set with a weight: its heaviest.
    private static func latestWeight(of exercise: UUID, in sessions: [ImportSessionPreview]) -> ImportLastTime? {
        for preview in sessions {
            guard let session = preview.session else { continue }
            let weights = session.exercises.filter { $0.exerciseId == exercise }.flatMap(\.sets).compactMap(\.weightKg)
            if let heaviest = weights.max(), heaviest > 0 {
                return ImportLastTime(kg: heaviest, day: preview.day, sessionID: preview.id)
            }
        }
        return nil
    }

    /// The plan of the file a session names (design §8): by name; with several of that name, the one whose
    /// `start ≤ day < start + weeks`, else the latest that started by then, else the first.
    static func planIndex(for ref: ImportedSession.PlanRef, on day: LocalDate, plans: [ImportedPlan]) -> Int? {
        let name = SourceExerciseKey.fold(ref.planName)
        let candidates = plans.indices.filter { SourceExerciseKey.fold(plans[$0].name) == name }
        guard candidates.count > 1 else { return candidates.first }
        for index in candidates {
            guard let start = plans[index].startDate, let weeks = plans[index].weeks else { continue }
            if start <= day, day.dayNumber < start.dayNumber + weeks * 7 { return index }
        }
        let started = candidates.filter { plans[$0].startDate.map { $0 <= day } ?? false }
        func start(_ index: Int) -> Int { plans[index].startDate?.dayNumber ?? Int.min }
        if let latest = started.max(by: { (start($0), $0) < (start($1), $1) }) { return latest }
        return candidates.first
    }
}
