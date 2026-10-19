// Local-first Train data (SwiftData). A session is logged here first and
// survives app kills; TrainSyncService uploads the whole document. Ids are the
// client-generated UUIDs the API uses.
import Foundation
import SwiftData

@Model
final class LocalSession {
    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var planDayId: UUID?
    var workoutId: UUID?
    var notes: String
    var bodyweightKg: Double?
    var muscularTrimp: Double?
    var strain: Double?
    var volumeKg: Double?
    @Relationship(deleteRule: .cascade, inverse: \LocalSessionExercise.session)
    var exercises: [LocalSessionExercise] = []
    /// Sets removed while logging, so a 409 merge doesn't bring them back.
    var deletedSetIDs: [UUID] = []
    /// Finished offline; `POST …/complete` runs on reconnect ("will sync").
    var pendingCompletion = false
    /// The server has a copy (a discard then needs a `DELETE`).
    var uploaded = false
    /// `[PersonalRecord]` returned by the completion.
    var prsData: Data?
    /// The running rest timer, so it survives the app being killed.
    var restEndsAt: Date?
    var restTotal: Double = 0
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, startedAt: Date = .now, planDayId: UUID? = nil) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.statusRaw = SessionStatus.inProgress.rawValue
        self.planDayId = planDayId
        self.notes = ""
        self.updatedAt = startedAt
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }

    var orderedExercises: [LocalSessionExercise] { exercises.sorted { $0.position < $1.position } }

    var prs: [PersonalRecord] {
        get { prsData.flatMap { try? APIClient.jsonDecoder.decode([PersonalRecord].self, from: $0) } ?? [] }
        set { prsData = try? APIClient.jsonEncoder.encode(newValue) }
    }

    var allSets: [LocalSet] { exercises.flatMap(\.sets) }

    var completedSetCount: Int { allSets.filter { $0.completedAt != nil }.count }

    /// Live volume of the checked-off working sets.
    var liveVolumeKg: Double { Volume.of(allSets.map(\.wire)) }

    /// The whole document for `PUT /v1/sessions/{id}`. The platform takes
    /// `completed` only for a session it already completed, so one finished
    /// here but waiting for `…/complete` goes up as `in_progress`.
    var wire: TrainSession {
        TrainSession(id: id, title: title, startedAt: startedAt, endedAt: endedAt, status: wireStatus,
                     planDayId: planDayId, workoutId: workoutId, notes: notes, bodyweightKg: bodyweightKg,
                     muscularTrimp: muscularTrimp, strain: strain, volumeKg: volumeKg,
                     deviceId: Settings.shared.deviceId, exercises: orderedExercises.map(\.wire), prs: prs)
    }

    var wireStatus: SessionStatus {
        status == .completed && pendingCompletion ? .inProgress : status
    }

    var summary: SessionSummary { SessionSummary(wire) }

    /// Takes a server document into the local copy. Sets and exercises are
    /// upserted by id and never removed: anything logged locally while the
    /// request was in flight stays.
    func apply(_ doc: TrainSession, names: (UUID) -> Exercise?, in context: ModelContext) {
        title = doc.title
        endedAt = doc.endedAt ?? endedAt
        // Never back to in progress: a session finished here goes up as in_progress
        // until `…/complete` (see `wireStatus`).
        if !(status == .completed && doc.status == .inProgress) { status = doc.status }
        if !doc.prs.isEmpty { prs = doc.prs }
        workoutId = doc.workoutId ?? workoutId
        bodyweightKg = doc.bodyweightKg ?? bodyweightKg
        muscularTrimp = doc.muscularTrimp ?? muscularTrimp
        strain = doc.strain ?? strain
        volumeKg = doc.volumeKg ?? volumeKg
        for remote in doc.exercises {
            let local: LocalSessionExercise
            if let existing = exercises.first(where: { $0.id == remote.id }) {
                local = existing
            } else {
                let ex = names(remote.exerciseId)
                local = LocalSessionExercise(id: remote.id, exerciseId: remote.exerciseId,
                                             name: ex?.name ?? String(localized: "Exercise"),
                                             kind: ex?.kind ?? .machine, loadType: ex?.loadType ?? .weight,
                                             position: remote.position)
                context.insert(local)
                exercises.append(local)
            }
            local.position = remote.position
            local.notes = remote.notes
            for set in remote.sets where !deletedSetIDs.contains(set.id) {
                if let existing = local.sets.first(where: { $0.id == set.id }) {
                    existing.update(from: set)
                } else {
                    let s = LocalSet(set)
                    context.insert(s)
                    local.sets.append(s)
                }
            }
        }
    }
}

@Model
final class LocalSessionExercise {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    /// Cached so the session renders offline without the library.
    var name: String
    var kindRaw: String
    var loadTypeRaw: String
    var position: Int
    var notes: String
    var restSec: Int
    var supersetGroup: Int?
    // The plan's prescription, from `/v1/plans/today` (local only).
    var planExerciseId: UUID?
    var targetSets: Int?
    var targetRepsMin: Int?
    var targetRepsMax: Int?
    var targetKg: Double?
    var targetKindRaw: String?
    var targetValue: Double?
    /// `[SessionSet]` from last time, shown ghosted.
    var lastTimeData: Data?
    var session: LocalSession?
    @Relationship(deleteRule: .cascade, inverse: \LocalSet.exercise)
    var sets: [LocalSet] = []

    init(id: UUID = UUID(), exerciseId: UUID, name: String, kind: ExerciseKind, loadType: LoadType,
         position: Int, restSec: Int = 120, supersetGroup: Int? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.kindRaw = kind.rawValue
        self.loadTypeRaw = loadType.rawValue
        self.position = position
        self.notes = ""
        self.restSec = restSec
        self.supersetGroup = supersetGroup
    }

    var kind: ExerciseKind { ExerciseKind(rawValue: kindRaw) ?? .machine }
    var loadType: LoadType { LoadType(rawValue: loadTypeRaw) ?? .weight }
    var targetKind: TargetKind? { targetKindRaw.flatMap(TargetKind.init(rawValue:)) }

    var orderedSets: [LocalSet] { sets.sorted { $0.setIndex < $1.setIndex } }

    var lastTime: [SessionSet] {
        get { lastTimeData.flatMap { try? APIClient.jsonDecoder.decode([SessionSet].self, from: $0) } ?? [] }
        set { lastTimeData = newValue.isEmpty ? nil : try? APIClient.jsonEncoder.encode(newValue) }
    }

    /// "3 × 5 @ 100 kg", "3 × 8–12 @ RPE 8"; nil without a plan.
    var targetText: String? {
        guard let sets = targetSets, let lo = targetRepsMin, let hi = targetRepsMax else { return nil }
        let base = Fmt.prescription(sets: sets, repsMin: lo, repsMax: hi)
        if let kg = targetKg { return "\(base) @ \(Fmt.kg(kg))" }
        switch targetKind {
        case .rpe: return targetValue.map { "\(base) @ RPE \(Fmt.kgNumber($0))" } ?? base
        case .pct1rm: return targetValue.map { "\(base) @ \(Fmt.kgNumber($0)) % 1RM" } ?? base
        default: return base
        }
    }

    /// Ghost values for set `index`: last time's set, else the target.
    func ghost(forSetAt index: Int) -> (reps: Int?, kg: Double?) {
        let last = lastTime.filter { !$0.isWarmup }
        if index < last.count { return (last[index].reps, last[index].weightKg) }
        return (targetRepsMin, targetKg ?? last.last?.weightKg)
    }

    var wire: SessionExercise {
        SessionExercise(id: id, exerciseId: exerciseId, planExerciseId: planExerciseId, position: position,
                        notes: notes, sets: orderedSets.map(\.wire))
    }
}

@Model
final class LocalSet {
    @Attribute(.unique) var id: UUID
    var setIndex: Int
    var reps: Int?
    var weightKg: Double?
    var rpe: Double?
    var durationSec: Int?
    var distanceM: Double?
    var isWarmup: Bool
    var completedAt: Date?
    var updatedAt: Date
    var exercise: LocalSessionExercise?

    init(id: UUID = UUID(), setIndex: Int, reps: Int? = nil, weightKg: Double? = nil, isWarmup: Bool = false,
         updatedAt: Date = .now) {
        self.id = id
        self.setIndex = setIndex
        self.reps = reps
        self.weightKg = weightKg
        self.isWarmup = isWarmup
        self.updatedAt = updatedAt
    }

    convenience init(_ s: SessionSet) {
        self.init(id: s.id, setIndex: s.setIndex)
        update(from: s)
    }

    var isCompleted: Bool { completedAt != nil }

    func update(from s: SessionSet) {
        setIndex = s.setIndex
        reps = s.reps
        weightKg = s.weightKg
        rpe = s.rpe
        durationSec = s.durationSec
        distanceM = s.distanceM
        isWarmup = s.isWarmup
        completedAt = s.completedAt
        updatedAt = s.updatedAt
    }

    var wire: SessionSet {
        SessionSet(id: id, setIndex: setIndex, reps: reps, weightKg: weightKg, rpe: rpe, durationSec: durationSec,
                 distanceM: distanceM, isWarmup: isWarmup, completedAt: completedAt, updatedAt: updatedAt)
    }
}
