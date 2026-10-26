import Foundation

/// A file's workouts as completed RYFT sessions (design §5, §6, §8), and each one's verdict: history off, outside the
/// range, in the future, already imported, nothing performed, a duplicate of a session logged in RYFT, or new.
enum ImportSessionAssembly {
    /// The duration when the file names none (`.durationAssumed`).
    static let assumedMinutes = 60
    /// What the platform keeps of a session (API.md → Sessions); more is dropped with `.overPlatformLimit`.
    static let maxExercises = 50
    static let maxSetsPerExercise = 50
    /// The platform clamps larger values; the app sends them clamped (`.overPlatformLimit`), so a re-send is identical
    /// (T10).
    static let maxReps = 100
    static let maxWeightKg = 500.0

    /// The plan day a session names, resolved to the file's plan (`ImportPlanAssembly.planIndex`).
    struct DayRef: Equatable, Sendable {
        let planIndex: Int
        let dayNumber: Int
    }

    struct Result: Sendable {
        var sessions: [ImportSessionPreview]
        /// The builder's notes for the sessions that can be sent (new and duplicates).
        var warnings: [ImportWarning]
        /// By session id.
        var refs: [UUID: DayRef]
    }

    static func build(_ context: ImportBuildContext, plans: [ImportPlanAssembly.Draft], now: Date) throws -> Result {
        var previews: [ImportSessionPreview] = []
        var notes: [UUID: [ImportWarning]] = [:]
        var refs: [UUID: DayRef] = [:]
        let history = context.decisions.history
        for (index, file) in context.bundle.sessions.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            guard context.sessionIDs.indices.contains(index) else { break }
            let id = context.sessionIDs[index]
            let resolution = context.resolver.resolve(file.start)
            let day = file.start.date
            let ref = file.plan.flatMap { ref in
                ImportPlanAssembly.planIndex(for: ref, on: day, plans: context.bundle.plans)
                    .map { DayRef(planIndex: $0, dayNumber: ref.dayNumber) }
            }
            refs[id] = ref
            func preview(_ verdict: ImportSessionPreview.Verdict, _ built: Built? = nil) -> ImportSessionPreview {
                ImportSessionPreview(index: index, id: id, verdict: verdict, session: built?.session,
                                     startedAt: resolution.instant, day: day, exerciseCount: built?.session.exercises.count ?? 0,
                                     setCount: built?.setCount ?? 0, skippedSetCount: built?.skippedSets ?? 0,
                                     volumeKg: built?.volumeKg ?? 0, clockChange: resolution.note)
            }
            guard history.included else {
                previews.append(preview(.historyOff))
                continue
            }
            guard history.contains(day) else {
                previews.append(preview(.outsideRange))
                continue
            }
            guard resolution.instant <= now else {
                previews.append(preview(.inFuture))
                continue
            }
            let built = session(file, id: id, start: resolution.instant, ref: ref, plans: plans, context: context)
            var kinds = built.notes
            if let note = resolution.note { kinds.insert(note, at: 0) }
            notes[id] = kinds.map { ImportWarning(at: file.source, kind: $0) }
            if context.existing.sessionIDs.contains(id) {
                previews.append(preview(.alreadyImported, built))
            } else if built.setCount == 0 {
                previews.append(preview(.empty, built))
            } else {
                previews.append(preview(.new, built))
            }
        }
        previews = markDuplicates(previews, context: context)
        var warnings: [ImportWarning] = []
        for preview in previews {
            switch preview.verdict {
            case .new, .duplicate: warnings += notes[preview.id] ?? []
            case .alreadyImported, .outsideRange, .inFuture, .empty, .historyOff: break
            }
        }
        return Result(sessions: previews, warnings: warnings, refs: refs)
    }

    // MARK: one session

    struct Built: Sendable {
        let session: TrainSession
        /// Performed sets sent.
        let setCount: Int
        /// Sets with no reps (or zero) of the exercises that are imported.
        let skippedSets: Int
        let volumeKg: Double
        /// `.durationAssumed`, `.assistedLoad`, `.overPlatformLimit`, each at most once.
        let notes: [ImportWarning.Kind]
    }

    private struct PendingSet {
        let ordinal: Int
        let reps: Int
        let weightKg: Double?
    }

    private struct PendingExercise {
        let id: UUID
        let exerciseID: UUID
        let planExerciseID: UUID?
        let sets: [PendingSet]
    }

    /// The completed session (design §8): performed sets only, the `+N` answers applied, the body weight the answers
    /// name (the most common in the session), and `completed_at` spread over the duration so a re-send is identical.
    static func session(_ file: ImportedSession, id: UUID, start: Date, ref: DayRef?, plans: [ImportPlanAssembly.Draft],
                        context: ImportBuildContext) -> Built {
        var notes: [ImportWarning.Kind] = []
        func note(_ kind: ImportWarning.Kind) { if !notes.contains(kind) { notes.append(kind) } }
        let minutes: Int
        if let given = file.durationMinutes {
            minutes = max(0, given)
        } else {
            minutes = assumedMinutes
            note(.durationAssumed)
        }
        let link = ref.flatMap { linkablePlan(ref: $0, plans: plans, context: context) }
        let dayID = link.flatMap { link in ref.flatMap { link.links.days[$0.dayNumber] } }
        var pending: [PendingExercise] = []
        var occurrences: [SourceExerciseKey: Int] = [:]
        var skipped = 0
        var bodyweights: [Double] = []
        for row in file.exercises {
            let key = ImportBuildContext.key(row.name, row.equipment)
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            guard let exercise = context.exercise(for: key) else { continue }
            let answer = context.bodyweightAnswer(for: key, loadType: exercise.loadType)
            var sets: [PendingSet] = []
            for set in row.sets {
                guard let given = set.reps, given > 0 else {
                    skipped += 1
                    continue
                }
                guard sets.count < maxSetsPerExercise else {
                    note(.overPlatformLimit)
                    break
                }
                var reps = given
                if reps > maxReps {
                    reps = maxReps
                    note(.overPlatformLimit)
                }
                var weight: Double?
                switch set.load {
                case nil:
                    break
                case let .weight(kg):
                    // A `time` or `distance` exercise records no weight: the load is dropped, reps kept (design §5).
                    if exercise.loadType == .weight || exercise.loadType == .bodyweight { weight = kg }
                case let .plus(kg):
                    if let outcome = answer?.outcome(plusKg: kg, loadType: exercise.loadType) {
                        weight = outcome.weightKg
                        if let bodyweight = outcome.bodyweightKg { bodyweights.append(bodyweight) }
                    }
                case .minus:
                    // Assistance can't be stored (T4): reps only.
                    note(.assistedLoad)
                }
                if let kg = weight, kg > maxWeightKg {
                    weight = maxWeightKg
                    note(.overPlatformLimit)
                }
                sets.append(PendingSet(ordinal: set.ordinal, reps: reps, weightKg: weight))
            }
            guard !sets.isEmpty else { continue }
            guard pending.count < maxExercises else {
                note(.overPlatformLimit)
                break
            }
            let rowID = ImportIDs.sessionExercise(session: id, key: key, occurrence: occurrence)
            let planExercise = dayID.flatMap { link?.links.exercises[$0]?[key]?[occurrence] }
            pending.append(PendingExercise(id: rowID, exerciseID: exercise.id, planExerciseID: planExercise, sets: sets))
        }
        // The k-th of n performed sets (exercise, then row order) completes at start + duration × (k + 1) / n, in whole
        // seconds; `updated_at` is the same, so sending it again is identical (T10).
        let total = pending.reduce(0) { $0 + $1.sets.count }
        let seconds = minutes * 60
        var k = 0
        var volume = 0.0
        var exercises: [SessionExercise] = []
        for (position, row) in pending.enumerated() {
            var sets: [SessionSet] = []
            for (index, set) in row.sets.enumerated() {
                k += 1
                let at = start.addingTimeInterval(TimeInterval(seconds * k / max(total, 1)))
                if let kg = set.weightKg { volume += Double(set.reps) * kg }
                sets.append(SessionSet(id: ImportIDs.set(exercise: row.id, ordinal: set.ordinal), setIndex: index,
                                       reps: set.reps, weightKg: set.weightKg, completedAt: at, updatedAt: at))
            }
            exercises.append(SessionExercise(id: row.id, exerciseId: row.exerciseID, planExerciseId: row.planExerciseID,
                                             position: position, sets: sets))
        }
        let session = TrainSession(id: id, title: ImportText.title(file.title, max: ImportBuilder.maxTitleLength),
                                   startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(seconds)),
                                   status: .completed, planDayId: dayID,
                                   bodyweightKg: PlusLoadSummary.mostCommon(bodyweights), exercises: exercises)
        return Built(session: session, setCount: total, skippedSets: skipped, volumeKg: volume, notes: notes)
    }

    /// The plan a session may point into: one that's sent, or one already in RYFT whose copy still has that day (the
    /// user may have edited it). A plan that's skipped or can't be imported gets no links (design §7).
    private static func linkablePlan(ref: DayRef, plans: [ImportPlanAssembly.Draft],
                                     context: ImportBuildContext) -> ImportPlanAssembly.Draft? {
        guard let draft = plans.first(where: { $0.index == ref.planIndex }), draft.plan != nil else { return nil }
        if draft.willBeSent { return draft }
        // The copy as read (an entry whose copy couldn't be read is `.some(nil)`).
        guard draft.state == .alreadyInRYFT, let entry = context.existing.plans[draft.id], let copy = entry,
              let dayID = draft.links.days[ref.dayNumber], copy.days.contains(where: { $0.id == dayID }) else { return nil }
        // Only the rows RYFT's copy still has.
        var links = ImportPlanAssembly.Links()
        links.days[ref.dayNumber] = dayID
        let rows = Set(copy.days.flatMap(\.exercises).map(\.id))
        links.exercises[dayID] = draft.links.exercises[dayID]?.mapValues { $0.filter { rows.contains($0.value) } }
        return ImportPlanAssembly.Draft(index: draft.index, id: draft.id, state: draft.state, plan: draft.plan,
                                        willBeSent: false, skippedExerciseNames: [], links: links)
    }

    // MARK: duplicates

    /// New sessions that look like one already logged in RYFT become `.duplicate` (off by default).
    private static func markDuplicates(_ previews: [ImportSessionPreview], context: ImportBuildContext) -> [ImportSessionPreview] {
        let derived = Set(context.sessionIDs)
        let logged = context.existing.logged.filter { !derived.contains($0.id) }
        let candidates = previews.compactMap { preview -> DuplicateDetector.Candidate? in
            guard preview.verdict == .new, let session = preview.session else { return nil }
            return DuplicateDetector.Candidate(id: preview.id, day: preview.day.key,
                                               exerciseIDs: Set(session.exercises.map(\.exerciseId)))
        }
        let found = DuplicateDetector.duplicates(of: candidates, against: logged, zone: context.decisions.zone)
        guard !found.isEmpty else { return previews }
        return previews.map { preview in
            guard let match = found[preview.id] else { return preview }
            return ImportSessionPreview(index: preview.index, id: preview.id, verdict: .duplicate(of: match),
                                        session: preview.session, startedAt: preview.startedAt, day: preview.day,
                                        exerciseCount: preview.exerciseCount, setCount: preview.setCount,
                                        skippedSetCount: preview.skippedSetCount, volumeKg: preview.volumeKg,
                                        clockChange: preview.clockChange)
        }
    }
}
