import Foundation
import OSLog

// Replacing an exercise mid-session, Undo, "Also change the plan" and Edit targets
// (docs/work/2026-10-29-beta-feedback-2/design.md §1–3, §5, §6; ADR 0009).
//
//   nothing done (warm-ups count) ──▶ the row is mutated in place: same id and set ids, new exercise, no plan link
//   some sets done                ──▶ split: the done sets stay on the old row (with its plan link), its open sets
//                                     are tombstoned, a new row right after it gets as many fresh sets
//   either                        ──▶ saved now; the upload waits for the undo window (5 s, 10 s with VoiceOver),
//                                     `pause()` or another edit, so a quick Undo never reaches the server

extension SessionController {
    /// What a replace does with the exercise's sets.
    enum ReplaceKind: Equatable {
        /// No set is done (warm-ups count): the row takes the new exercise.
        case inPlace
        /// `done` sets stay with the old exercise; the new one continues with `remaining`.
        case split(done: Int, remaining: Int)
    }
}

/// "Also change the plan" in the replace sheet: the plan day it changes, and whether it can now (online only).
struct PlanChangeOption: Equatable {
    let dayName: String
    let isAvailable: Bool
}

/// Every stored field of a `LocalSessionExercise`, as values: what Undo writes back.
struct ExerciseSnapshot: Equatable {
    let id: UUID
    let exerciseId: UUID
    let name: String
    let kindRaw: String
    let loadTypeRaw: String
    let notes: String
    let position: Int
    let restSec: Int
    let supersetGroup: Int?
    let planExerciseId: UUID?
    let targetSets: Int?
    let targetRepsMin: Int?
    let targetRepsMax: Int?
    let targetKg: Double?
    let targetValue: Double?
    let targetKindRaw: String?
    let lastTimeData: Data?
    /// In set order, ids included.
    let sets: [SessionSet]

    init(_ ex: LocalSessionExercise) {
        id = ex.id
        exerciseId = ex.exerciseId
        name = ex.name
        kindRaw = ex.kindRaw
        loadTypeRaw = ex.loadTypeRaw
        notes = ex.notes
        position = ex.position
        restSec = ex.restSec
        supersetGroup = ex.supersetGroup
        planExerciseId = ex.planExerciseId
        targetSets = ex.targetSets
        targetRepsMin = ex.targetRepsMin
        targetRepsMax = ex.targetRepsMax
        targetKg = ex.targetKg
        targetValue = ex.targetValue
        targetKindRaw = ex.targetKindRaw
        lastTimeData = ex.lastTimeData
        sets = ex.orderedSets.map(\.wire)
    }
}

/// The replace that the toast can still take back.
struct ReplaceUndo: Identifiable {
    let id: UUID
    let expiresAt: Date
    /// "Replaced with Bench press", with the split or plan sentence.
    var message: String
    /// The exercise's name before ("Restored Incline bench press.").
    let restoredName: String
    /// The exercise it was replaced with.
    let newName: String
    let before: ExerciseSnapshot
    /// The row a split inserted.
    let inserted: UUID?
    let focus: SetFocus?
    /// The plan before "Also change the plan" changed it.
    let planBefore: Plan?

    /// The replaced row or the one it inserted.
    func touches(_ exerciseID: UUID?) -> Bool {
        guard let exerciseID else { return false }
        return exerciseID == before.id || exerciseID == inserted
    }
}

/// A toast without Undo.
struct SessionNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// Edit targets: session-only numbers of one exercise (design.md §6).
struct SessionTargets: Equatable {
    var sets: Int
    var repsMin: Int?
    var repsMax: Int?
    var kg: Double?
    var restSec: Int

    static let reps = 1...100
    static let kgRange = 0.0...500.0
    static let rest = 0...900
    static let kgStep = 2.5
    static let restStep = 15
    /// Where a rep range starts when there is none.
    static let defaultReps = (min: 8, max: 12)

    /// Moving "from" above "to" moves "to" with it.
    mutating func stepRepsMin(_ delta: Int) {
        let lo = Self.clamp((repsMin ?? Self.defaultReps.min - delta) + delta, Self.reps)
        repsMin = lo
        repsMax = max(lo, repsMax ?? max(lo, Self.defaultReps.max))
    }

    /// Moving "to" below "from" moves "from" with it.
    mutating func stepRepsMax(_ delta: Int) {
        let hi = Self.clamp((repsMax ?? Self.defaultReps.max - delta) + delta, Self.reps)
        repsMax = hi
        repsMin = min(hi, repsMin ?? min(hi, Self.defaultReps.min))
    }

    /// From nothing, the first step lands on `start`.
    mutating func stepKg(_ direction: Double, from start: Double) {
        guard let kg else {
            self.kg = min(max(start, Self.kgRange.lowerBound), Self.kgRange.upperBound)
            return
        }
        self.kg = min(max(kg + Self.kgStep * direction, Self.kgRange.lowerBound), Self.kgRange.upperBound)
    }

    mutating func stepRest(_ direction: Int, in range: ClosedRange<Int> = 15...600) {
        restSec = Self.clamp(restSec + Self.restStep * direction, range)
    }

    static func clamp(_ v: Int, _ range: ClosedRange<Int>) -> Int { min(max(v, range.lowerBound), range.upperBound) }
}

extension SessionController {
    nonisolated static let undoWindow: Duration = .seconds(5)
    /// With VoiceOver the toast is reached by swiping, which takes longer (plan.md, lead decision 2).
    nonisolated static let undoWindowVoiceOver: Duration = .seconds(10)
    nonisolated static let noticeWindow: Duration = .seconds(5)
    private static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "train.replace")

    // MARK: replace

    func replaceKind(for ex: LocalSessionExercise) -> ReplaceKind {
        let done = ex.sets.filter(\.isCompleted).count
        return done == 0 ? .inPlace : .split(done: done, remaining: ex.sets.count - done)
    }

    /// Nothing is left to continue when every set is done.
    func canReplace(_ ex: LocalSessionExercise) -> Bool {
        if case .split(_, 0) = replaceKind(for: ex) { return false }
        return true
    }

    /// Shown for a plan session's planned exercise whose plan is the user's own and cached; nil otherwise.
    func planChangeOption(for ex: LocalSessionExercise) -> PlanChangeOption? {
        guard session.planDayId != nil, let pe = ex.planExerciseId,
              let plan = library?.editablePlan(containing: pe),
              let day = plan.days.first(where: { $0.exercises.contains { $0.id == pe } }) else { return nil }
        return PlanChangeOption(dayName: day.name, isAvailable: sync.isOnline)
    }

    /// The menu's Replace: the keypad closes for the sheet; Undo brings it back.
    func beginReplace() {
        focusBeforeReplace = focus
        focus = nil
    }

    /// Replaces `ex` with `new` (in place or split), saves, and opens the undo window at once; then waits for the
    /// new exercise's fresh "Last time" and, with `alsoChangePlan` (and a `planChangeOption`), for the plan save that
    /// changes the plan day's exercise from the next session on.
    func replace(_ ex: LocalSessionExercise, with new: Exercise, alsoChangePlan: Bool = false,
                 window: Duration = SessionController.undoWindow) async {
        guard canReplace(ex), new.id != ex.exerciseId else { return }
        commitUndo()   // a second replace commits the first
        let focusBefore = focusBeforeReplace ?? focus
        focusBeforeReplace = nil
        focus = nil
        let before = ExerciseSnapshot(ex)
        let kind = replaceKind(for: ex)
        // Read before the row changes: an in-place replace drops the plan link.
        let option = alsoChangePlan ? planChangeOption(for: ex) : nil
        let plan = option?.isAvailable == true ? before.planExerciseId.flatMap { library?.editablePlan(containing: $0) } : nil

        let target: LocalSessionExercise
        var inserted: UUID?
        switch kind {
        case .inPlace:
            mutate(ex, into: new)
            target = ex
        case .split:
            target = split(ex, into: new)
            inserted = target.id
        }
        target.lastTime = library?.cachedLastTime(for: new.id) ?? []
        store.save()
        refreshActivity()

        let id = UUID()
        undo = ReplaceUndo(id: id, expiresAt: clock.now().addingTimeInterval(window.timeInterval),
                           message: Self.message(replacedWith: new.name, kind: kind, oldName: before.name,
                                                 planDay: plan == nil ? nil : option?.dayName),
                           restoredName: before.name, newName: new.name, before: before, inserted: inserted, focus: focusBefore,
                           planBefore: plan)
        undoTask?.cancel()
        undoTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: window) } catch { return }
            guard let self, self.undo?.id == id else { return }
            self.commitUndo()
        }
        var planSave: Task<Bool, Never>?
        if let plan, let pe = before.planExerciseId {
            planSave = changePlan(plan, replacing: pe, with: new, undoID: id, dayName: option?.dayName ?? "")
        }
        await loadLastTime(row: target.id, exerciseID: new.id)
        _ = await planSave?.value
    }

    /// The toast's Undo: the row (and a split's open sets) as they were, the inserted row gone, the keypad back.
    /// Restored sets get a fresh `updatedAt`: Undo is a new edit, so it wins over a server copy of the replace.
    func undoReplace() {
        guard let u = undo else { return }
        undoTask?.cancel()
        undoTask = nil
        undo = nil
        guard let x = session.exercises.first(where: { $0.id == u.before.id }) else { return }
        let now = Date.now

        if let yID = u.inserted, let y = session.exercises.first(where: { $0.id == yID }) {
            session.deletedSetIDs.append(contentsOf: y.sets.map(\.id))
            session.deletedExerciseIDs.append(y.id)
            if let f = focus, y.sets.contains(where: { $0.id == f.setID }) { focus = nil }
            session.exercises.removeAll { $0.id == yID }
            store.context.delete(y)
        }

        let b = u.before
        x.exerciseId = b.exerciseId
        x.name = b.name
        x.kindRaw = b.kindRaw
        x.loadTypeRaw = b.loadTypeRaw
        x.notes = b.notes
        x.position = b.position
        x.restSec = b.restSec
        x.supersetGroup = b.supersetGroup
        // After a plan change the old plan exercise exists again only once the plan is saved back.
        x.planExerciseId = u.planBefore == nil ? b.planExerciseId : nil
        x.targetSets = b.targetSets
        x.targetRepsMin = b.targetRepsMin
        x.targetRepsMax = b.targetRepsMax
        x.targetKg = b.targetKg
        x.targetValue = b.targetValue
        x.targetKindRaw = b.targetKindRaw
        x.lastTimeData = b.lastTimeData
        var restored: Set<UUID> = []
        for saved in b.sets {
            var value = saved
            value.updatedAt = now
            if let set = x.sets.first(where: { $0.id == saved.id }) {
                set.update(from: value)
            } else {
                // Deleted by the split (and saved): back with its old id.
                let set = LocalSet(value)
                store.context.insert(set)
                x.sets.append(set)
                restored.insert(saved.id)
            }
        }
        session.deletedSetIDs.removeAll { restored.contains($0) }
        renumber()
        if let f = u.focus, let set = x.sets.first(where: { $0.id == f.setID }) { edit(set, f.field) }
        store.save()
        edited()

        if let planBefore = u.planBefore {
            revertPlan(to: planBefore, row: x.id, link: b.planExerciseId, name: b.name)
        }
    }

    /// The window is over (or the app went to the background): the replace stays and its upload goes.
    func commitUndo() {
        undoTask?.cancel()
        undoTask = nil
        guard undo != nil else { return }
        undo = nil
        sync.sessionChanged(session)
    }

    /// Swiped away: the same as the window running out.
    func dismissUndo() { commitUndo() }

    /// An edit that Undo would overwrite (a set of the replaced or inserted row, or a structural change with
    /// `nil`): the undo goes; the edit's own upload carries the replace.
    func dropUndo(touching exerciseID: UUID?) {
        guard let undo, undo.touches(exerciseID) else { return }
        dropUndo()
    }

    func dropUndo() {
        undoTask?.cancel()
        undoTask = nil
        undo = nil
    }

    /// Finish or discard: nothing is held back any more (Finish uploads the whole session itself).
    func endUndo() {
        dropUndo()
        noticeTask?.cancel()
        notice = nil
    }

    // MARK: notes and rest

    func setRest(_ seconds: Int, for ex: LocalSessionExercise) {
        dropUndo(touching: ex.id)
        ex.restSec = SessionTargets.clamp(seconds, SessionTargets.rest)
        edited()
    }

    func setNotes(_ notes: String, for ex: LocalSessionExercise) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != ex.notes else { return }
        dropUndo(touching: ex.id)
        ex.notes = trimmed
        edited()
    }

    // MARK: edit targets

    func targets(of ex: LocalSessionExercise) -> SessionTargets {
        SessionTargets(sets: ex.sets.count, repsMin: ex.targetRepsMin, repsMax: ex.targetRepsMax, kg: ex.targetKg,
                       restSec: ex.restSec)
    }

    /// The sets Edit targets may remove: from the end, while they are open and empty.
    func removableSets(of ex: LocalSessionExercise) -> [LocalSet] {
        Array(ex.orderedSets.reversed().prefix { !$0.isCompleted && !$0.hasValues })
    }

    /// The stepper's floor: what stays when every removable set goes (at least one set).
    func minSets(for ex: LocalSessionExercise) -> Int {
        max(min(1, ex.sets.count), ex.sets.count - removableSets(of: ex).count)
    }

    /// Why the floor is where it is: done sets, or a set with values that isn't checked.
    enum SetsFloor: Equatable { case done(Int), values }

    func setsFloor(for ex: LocalSessionExercise) -> SetsFloor? {
        let removable = removableSets(of: ex).count
        guard removable < ex.sets.count, let blocker = ex.orderedSets.reversed().dropFirst(removable).first
        else { return nil }
        return blocker.isCompleted ? .done(ex.sets.filter(\.isCompleted).count) : .values
    }

    /// Done in the sheet: one write, one upload. Sets are added at the end or removed from the end (open and
    /// empty only); never a done or filled set.
    func setTargets(_ t: SessionTargets, for ex: LocalSessionExercise) {
        dropUndo(touching: ex.id)
        let count = ex.sets.count
        if t.sets > count {
            var next = (ex.sets.map(\.setIndex).max() ?? -1) + 1
            for _ in count..<t.sets {
                SessionFactory.appendSet(index: next, to: ex, in: store).updatedAt = .now
                next += 1
            }
        } else if t.sets < count {
            let removable = removableSets(of: ex)
            for set in removable.prefix(min(count - t.sets, removable.count)) {
                session.deletedSetIDs.append(set.id)
                if focus?.setID == set.id { focus = nil }
                ex.sets.removeAll { $0.id == set.id }
                store.context.delete(set)
            }
        }
        let lo = t.repsMin.map { SessionTargets.clamp($0, SessionTargets.reps) }
        let hi = t.repsMax.map { SessionTargets.clamp($0, SessionTargets.reps) }
        ex.targetRepsMin = lo.map { min($0, hi ?? $0) }
        ex.targetRepsMax = hi.map { max($0, lo ?? $0) }
        if ex.targetSets != nil || ex.targetRepsMin != nil { ex.targetSets = ex.sets.count }
        ex.targetKg = t.kg.map { min(max($0, SessionTargets.kgRange.lowerBound), SessionTargets.kgRange.upperBound) }
        ex.restSec = SessionTargets.clamp(t.restSec, SessionTargets.rest)
        edited()
    }

    /// Where Target weight starts when there is none: the last weight in the card, last time's top set, or 20 kg.
    func suggestedKg(for ex: LocalSessionExercise) -> Double {
        ex.orderedSets.last { $0.weightKg != nil }?.weightKg
            ?? ex.lastTime.compactMap(\.weightKg).max()
            ?? 20
    }

    // MARK: - private

    /// §1: the same row takes the new exercise; values typed for the old lift go.
    private func mutate(_ ex: LocalSessionExercise, into new: Exercise) {
        ex.exerciseId = new.id
        ex.name = new.name
        ex.kindRaw = new.kind.rawValue
        ex.loadTypeRaw = new.loadType.rawValue
        ex.planExerciseId = nil
        ex.targetKg = nil
        if ex.targetKind != .rpe { ex.targetValue = nil }
        let now = Date.now
        for set in ex.sets {
            set.reps = nil
            set.weightKg = nil
            set.rpe = nil
            set.durationSec = nil
            set.distanceM = nil
            set.updatedAt = now
        }
    }

    /// §2: the old row keeps its done sets; its open sets are tombstoned (never moved) and the new row right after
    /// it gets as many fresh ones, in the same superset.
    private func split(_ ex: LocalSessionExercise, into new: Exercise) -> LocalSessionExercise {
        let open = ex.orderedSets.filter { !$0.isCompleted }
        for other in exercises where other.position > ex.position { other.position += 1 }
        let y = LocalSessionExercise(exerciseId: new.id, name: new.name, kind: new.kind, loadType: new.loadType,
                                     position: ex.position + 1, restSec: ex.restSec, supersetGroup: ex.supersetGroup)
        store.context.insert(y)
        session.exercises.append(y)
        y.targetSets = open.count
        y.targetRepsMin = ex.targetRepsMin
        y.targetRepsMax = ex.targetRepsMax
        y.targetKindRaw = ex.targetKindRaw
        y.targetValue = ex.targetKind == .rpe ? ex.targetValue : nil
        for (i, old) in open.enumerated() {
            SessionFactory.appendSet(index: i, to: y, in: store).isWarmup = old.isWarmup
        }
        let now = Date.now
        for set in open {
            session.deletedSetIDs.append(set.id)
            ex.sets.removeAll { $0.id == set.id }
            store.context.delete(set)
        }
        for (i, set) in ex.orderedSets.enumerated() where set.setIndex != i {
            set.setIndex = i
            set.updatedAt = now
        }
        renumber()
        return y
    }

    /// The cached "Last time" is shown at once; the fresh one only if the row still has that exercise.
    private func loadLastTime(row: UUID, exerciseID: UUID) async {
        guard let library else { return }
        let sets = await library.lastTime(for: exerciseID)
        guard let row = session.exercises.first(where: { $0.id == row }), row.exerciseId == exerciseID,
              row.lastTime != sets else { return }
        row.lastTime = sets
        store.save()
    }

    /// §5: links to the old plan exercise go first (a session `PUT` naming a deleted one is a 422), then the plan
    /// is saved with a new plan exercise for the new lift. A failed save puts the links back.
    private func changePlan(_ plan: Plan, replacing pe: UUID, with new: Exercise, undoID: UUID,
                            dayName: String) -> Task<Bool, Never>? {
        guard let library else { return nil }
        let unlinked = session.exercises.filter { $0.planExerciseId == pe }.map(\.id)
        for ex in session.exercises where ex.planExerciseId == pe { ex.planExerciseId = nil }
        store.save()
        planTask = Task { [weak self] in
            let last = await library.lastTime(for: new.id)
            let kg = Self.planKg(from: last)
            let ok = await library.savePlan(Self.replacing(pe, with: new, kg: kg, in: plan))
            guard let self else { return ok }
            if ok {
                Self.log.info("Plan exercise replaced from the session")
                if kg == nil, Self.target(of: pe, in: plan)?.targetKind == .kg, self.undo?.id == undoID {
                    self.undo?.message = String(
                        localized: "Replaced with \(new.name). Changed in your plan from the next \(dayName) day. Check its target weight there.",
                        comment: "Undo toast after replacing an exercise and its plan entry; the new exercise has no history, so the plan kept the old weight. 1: new exercise, 2: plan day name, e.g. Upper.")
                }
            } else {
                Self.log.error("Plan change after a replace failed")
                for id in unlinked {
                    guard let ex = self.session.exercises.first(where: { $0.id == id }), ex.exerciseId != new.id
                    else { continue }
                    ex.planExerciseId = pe
                }
                self.store.save()
                let failed = String(localized: "Replaced with \(new.name). Your plan couldn't be changed.",
                                    comment: "Undo toast: the exercise was replaced in the workout, but saving the plan failed. 1: new exercise.")
                if self.undo?.id == undoID {
                    self.undo?.message = failed
                } else if self.session.exercises.contains(where: { $0.exerciseId == new.id }) {
                    // The window is over and the replace stands (after an Undo there is nothing to say).
                    self.show(notice: failed)
                }
            }
            return ok
        }
        return planTask
    }

    /// Undo after a plan change: once the forward save is over, the plan goes back too, and the row's link with it.
    private func revertPlan(to planBefore: Plan, row: UUID, link: UUID?, name: String) {
        guard let library else { return }
        let forward = planTask
        Task { [weak self] in
            let changed = await forward?.value ?? false
            let ok = changed ? await library.savePlan(planBefore) : true
            guard let self else { return }
            if ok, let ex = self.session.exercises.first(where: { $0.id == row }), ex.exerciseId == planBefore.exerciseID(of: link) {
                ex.planExerciseId = link
                self.store.save()
                self.edited()
            } else if !ok {
                Self.log.error("Plan revert after Undo failed")
                self.show(notice: String(localized: "Restored \(name). Your plan still has the new exercise.",
                                         comment: "Toast after Undo: the workout is back, but the plan could not be changed back. 1: exercise name."))
            }
        }
    }

    private func show(notice message: String) {
        let n = SessionNotice(message: message)
        notice = n
        noticeTask?.cancel()
        noticeTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: Self.noticeWindow) } catch { return }
            guard let self, self.notice?.id == n.id else { return }
            self.notice = nil
        }
    }

    static func message(replacedWith new: String, kind: ReplaceKind, oldName: String, planDay: String?) -> String {
        if let planDay {
            return String(localized: "Replaced with \(new). Changed in your plan from the next \(planDay) day.",
                          comment: "Undo toast after replacing an exercise in the workout and in the plan. 1: new exercise, 2: plan day name, e.g. Upper.")
        }
        switch kind {
        case .inPlace:
            return String(localized: "Replaced with \(new)", comment: "Undo toast after replacing an exercise. 1: new exercise.")
        case .split(1, _):
            return String(localized: "Replaced with \(new). Your done set stays as \(oldName).",
                          comment: "Undo toast after replacing an exercise with one set done. 1: new exercise, 2: old exercise.")
        case .split(let done, _):
            return String(localized: "Replaced with \(new). Your \(done) done sets stay as \(oldName).",
                          comment: "Undo toast after replacing an exercise with several sets done. 1: new exercise, 2: number of sets, 3: old exercise.")
        }
    }

    // MARK: plan (pure)

    /// The plan with plan exercise `pe` now the new exercise, under a **new** id (so the old lift's attempts don't
    /// drive the new lift's progression). Position, sets, reps, rest, superset, notes and target kind stay; a kg
    /// target becomes `kg` when known, a bodyweight target none.
    static func replacing(_ pe: UUID, with new: Exercise, kg: Double?, in plan: Plan) -> Plan {
        var p = plan
        for d in p.days.indices {
            p.days[d].exercises = p.days[d].exercises.map { old in
                guard old.id == pe else { return old }
                var value = old.targetValue
                switch old.targetKind {
                case .rpe, .pct1rm: break
                case .bodyweight: value = nil
                case .kg: value = kg ?? old.targetValue
                }
                return PlanExercise(exercise: new, position: old.position, sets: old.sets, repsMin: old.repsMin,
                                    repsMax: old.repsMax, targetKind: old.targetKind, targetValue: value,
                                    restSec: old.restSec, supersetGroup: old.supersetGroup, notes: old.notes)
            }
        }
        return p
    }

    /// The top working weight of last time, to the nearest 2.5 kg; nil without one.
    static func planKg(from last: [SessionSet]) -> Double? {
        guard let top = last.filter({ !$0.isWarmup }).compactMap(\.weightKg).max(), top > 0 else { return nil }
        return (top / 2.5).rounded() * 2.5
    }

    private static func target(of pe: UUID, in plan: Plan) -> PlanExercise? {
        plan.days.lazy.flatMap(\.exercises).first { $0.id == pe }
    }
}

private extension Plan {
    /// The exercise a plan exercise names; nil for none.
    func exerciseID(of pe: UUID?) -> UUID? {
        guard let pe else { return nil }
        return days.lazy.flatMap(\.exercises).first { $0.id == pe }?.exerciseId
    }
}
