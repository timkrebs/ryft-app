import Foundation
import GameplayKit
import SwiftUI

/// Which number the keypad is editing.
struct SetFocus: Hashable {
    enum Field: Hashable { case kg, reps, rpe }
    let setID: UUID
    let field: Field
}

/// The live session's logic: checking off sets, the rest timer, the keypad,
/// editing the exercise list. Every change is saved to SwiftData at once and
/// queued for upload (TrainSyncService).
@MainActor
@Observable
final class SessionController: Identifiable {
    let session: LocalSession
    let sync: TrainSyncService
    var store: TrainStore { sync.store }
    /// "Now" and waits (the undo window, the jump to the next exercise): tests move it by hand.
    let clock: AppClock
    /// Last time for a replacement and the plan for "Also change the plan"; nil in previews without a library.
    let library: SessionLibrary?

    /// The workout's phase (`LiveSessionMachine`): active, resting, paused, finishing,
    /// completed or discarded. The rest timer moves it between active and resting.
    private(set) var phase: LiveSessionPhase = .idle
    @ObservationIgnored private var machine: GKTableMachine<LiveSessionPhase>!
    var isFinishing: Bool { phase == .finishing }

    private(set) var rest: RestTimer
    var focus: SetFocus?
    /// What the keypad shows while typing ("82." mid-entry).
    private(set) var buffer = ""
    /// `buffer` with the locale's decimal separator ("82,5").
    var displayBuffer: String {
        buffer.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
    /// Bumped for haptics.
    private(set) var setsChecked = 0
    private(set) var restsEnded = 0

    private var ticker: Task<Void, Never>?
    private let liveActivity: RestActivityController?

    // MARK: replace and undo state (SessionController+Replace.swift)

    /// The last replace while it can still be undone (one level deep). Set only by the replace extension.
    var undo: ReplaceUndo?
    /// A short note without Undo ("Your plan couldn't be changed"); cleared after its window.
    var notice: SessionNotice?
    /// Ends the undo window (`clock.sleep`), then commits: the held upload goes.
    @ObservationIgnored var undoTask: Task<Void, Never>?
    @ObservationIgnored var noticeTask: Task<Void, Never>?
    /// The last plan save of "Also change the plan" or of its Undo; each one waits for the one before. A forward
    /// save returns the plan as it was before it (nil: nothing was saved), which its Undo saves back.
    @ObservationIgnored var planTask: Task<Plan?, Never>?
    /// Replaces taken back with Undo (by `ReplaceUndo.id`): their late plan saves change nothing more.
    @ObservationIgnored var undoneReplaces: Set<UUID> = []
    /// The keypad's field when Replace was chosen (the sheet closes the keypad); Undo puts it back.
    @ObservationIgnored var focusBeforeReplace: SetFocus?

    nonisolated var id: UUID { sessionID }
    private nonisolated let sessionID: UUID

    /// `liveActivity` is nil in previews and tests.
    init(session: LocalSession, sync: TrainSyncService, liveActivity: RestActivityController?,
         clock: AppClock = SystemClock(), library: SessionLibrary? = nil) {
        self.session = session
        self.sessionID = session.id
        self.sync = sync
        self.clock = clock
        self.library = library
        self.liveActivity = liveActivity
        rest = RestTimer(endsAt: session.restEndsAt, total: session.restTotal, now: .now)
        machine = LiveSessionMachine.make { [weak self] to, _ in self?.phase = to }
        machine.enter(.active)
        followRest()
        startTicker()
        // On the lock screen from the start: the workout, or the rest it was in.
        if rest.isRunning { persistRest(exercise: nil) } else { showWorkout() }
    }

    /// The Live Activity's workout view: elapsed time and the next set.
    private func showWorkout() {
        lastActivityNext = nextLabel()
        liveActivity?.workout(session: session.id, title: session.title, startedAt: session.startedAt,
                              next: lastActivityNext ?? "")
    }

    /// What the lock screen says comes next, so a change that doesn't move it sends nothing.
    private var lastActivityNext: String?

    // MARK: jump-to-next state (SessionController+Advance.swift)

    /// After an edit (a set checked, unchecked, added, deleted or changed; an exercise added,
    /// removed or moved): the lock screen's next set follows.
    func refreshActivity() {
        guard nextLabel() != lastActivityNext else { return }
        if rest.isRunning { persistRest(exercise: nil) } else { showWorkout() }
    }

    /// Resting while the timer runs, active otherwise (unless paused or ending).
    private func followRest() {
        guard let machine else { return }
        if rest.isRunning {
            if phase == .active { machine.enter(.resting) }
        } else if phase == .resting {
            machine.enter(.active)
        }
    }

    /// The app went to the background mid-workout.
    func pause() {
        commitUndo()
        machine.enter(.paused)
    }

    /// Back in the app: resting again if the timer still runs.
    func resume() {
        guard phase == .paused else { return }
        machine.enter(.active)
        followRest()
    }

    /// Finish, discard or an account change: an open undo goes without a write (nothing commits it later).
    func stop() {
        ticker?.cancel()
        ticker = nil
        dropUndo()
    }

    // MARK: derived

    var exercises: [LocalSessionExercise] { session.orderedExercises }

    func elapsed(at now: Date) -> TimeInterval { now.timeIntervalSince(session.startedAt) }

    /// Ghost values for a set: last time / the target, else the set above it.
    func ghost(for set: LocalSet, in ex: LocalSessionExercise) -> (reps: Int?, kg: Double?) {
        let g = ex.ghost(forSetAt: workingIndex(of: set, in: ex))
        if g.reps != nil || g.kg != nil { return g }
        let above = ex.orderedSets.last { $0.setIndex < set.setIndex && ($0.reps != nil || $0.weightKg != nil) }
        return (above?.reps, above?.weightKg)
    }

    /// Index among the working sets (warm-ups don't shift last time's numbers).
    private func workingIndex(of set: LocalSet, in ex: LocalSessionExercise) -> Int {
        ex.orderedSets.filter { !$0.isWarmup && $0.setIndex < set.setIndex }.count
    }

    /// "Bench press · set 3 of 4" — the next set to do, in order (supersets alternate).
    var nextUp: (exercise: LocalSessionExercise, set: LocalSet)? {
        for ex in exercises {
            if let set = ex.orderedSets.first(where: { !$0.isCompleted }) { return (ex, set) }
        }
        return nil
    }

    func nextLabel(after ex: LocalSessionExercise? = nil) -> String {
        guard !exercises.isEmpty else { return String(localized: "Add an exercise") }
        guard let next = nextUp(after: ex) else { return String(localized: "Last set done — finish when ready") }
        let sets = next.exercise.orderedSets
        let n = (sets.firstIndex { $0.id == next.set.id } ?? 0) + 1
        let label = String(localized: "\(next.exercise.name) · set \(n) of \(sets.count)",
                           comment: "Next set in the rest timer, e.g. Bench press · set 3 of 4.")
        // "· 5 × 80 kg" when the set is filled in (from the plan or the last time).
        guard let target = Self.target(reps: next.set.reps, kg: next.set.weightKg) else { return label }
        return "\(label) · \(target)"
    }

    /// "5 × 80 kg", "5 reps", "80 kg"; `nil` with neither.
    static func target(reps: Int?, kg: Double?) -> String? {
        switch (reps, kg) {
        case let (r?, w?): return "\(r) × \(Fmt.kg(w))"
        case let (r?, nil): return String(localized: "\(r) reps")
        case let (nil, w?): return Fmt.kg(w)
        case (nil, nil): return nil
        }
    }

    /// Within a superset the partner comes next; otherwise the first open set.
    func nextUp(after ex: LocalSessionExercise?) -> (exercise: LocalSessionExercise, set: LocalSet)? {
        if let ex, let group = ex.supersetGroup {
            let partners = exercises.filter { $0.supersetGroup == group }
            if let i = partners.firstIndex(where: { $0.id == ex.id }) {
                for partner in partners[(i + 1)...] + partners[..<i] {
                    if let set = partner.orderedSets.first(where: { !$0.isCompleted }) { return (partner, set) }
                }
            }
        }
        return nextUp
    }

    // MARK: sets

    func toggleCheck(_ set: LocalSet, in ex: LocalSessionExercise) {
        if set.isCompleted {
            set.completedAt = nil
        } else {
            let g = ghost(for: set, in: ex)
            if set.reps == nil { set.reps = g.reps }
            if set.weightKg == nil, ex.loadType == .weight { set.weightKg = g.kg }
            set.completedAt = .now
            setsChecked += 1
            if focus?.setID == set.id { focus = nil }
            startRest(after: ex)
        }
        changed(set)
    }

    func toggleWarmup(_ set: LocalSet) {
        set.isWarmup.toggle()
        changed(set)
    }

    @discardableResult
    func addSet(to ex: LocalSessionExercise) -> LocalSet {
        let index = (ex.sets.map(\.setIndex).max() ?? -1) + 1
        let set = SessionFactory.appendSet(index: index, to: ex, in: store)
        changed(set)
        return set
    }

    func delete(_ set: LocalSet, from ex: LocalSessionExercise) {
        dropUndo(touching: ex.id)
        session.deletedSetIDs.append(set.id)
        if focus?.setID == set.id { focus = nil }
        ex.sets.removeAll { $0.id == set.id }
        store.context.delete(set)
        for (i, s) in ex.orderedSets.enumerated() where s.setIndex != i {
            s.setIndex = i
            s.updatedAt = .now
        }
        edited()
    }

    func changed(_ set: LocalSet) {
        dropUndo(touching: set.exercise?.id)
        set.updatedAt = .now
        edited()
    }

    /// Any change: the upload follows (debounced), and the lock screen's next set.
    func edited() {
        sync.sessionChanged(session)
        refreshActivity()
    }

    // MARK: keypad

    func edit(_ set: LocalSet, _ field: SetFocus.Field) {
        focus = SetFocus(setID: set.id, field: field)
        buffer = text(for: set, field)
    }

    private func text(for set: LocalSet, _ field: SetFocus.Field) -> String {
        switch field {
        case .kg: return set.weightKg.map(Self.plain) ?? ""
        case .reps: return set.reps.map(String.init) ?? ""
        case .rpe: return set.rpe.map(Self.plain) ?? ""
        }
    }

    /// 82.5 → "82.5" without grouping or locale (keypad input).
    static func plain(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(v)
    }

    var focusedSet: (set: LocalSet, exercise: LocalSessionExercise)? {
        guard let focus else { return nil }
        for ex in exercises {
            if let s = ex.sets.first(where: { $0.id == focus.setID }) { return (s, ex) }
        }
        return nil
    }

    func type(_ key: String) {
        guard let focus else { return }
        var next = buffer
        if key == "." {
            guard focus.field != .reps, !next.contains(".") else { return }
            next = (next.isEmpty ? "0" : next) + "."
        } else {
            next = next == "0" ? key : next + key
        }
        guard Self.accepts(next, field: focus.field) else { return }
        buffer = next
        commitBuffer()
    }

    func backspace() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
        commitBuffer()
    }

    /// ±2.5 kg, ±1 rep, ±0.5 RPE, starting from the ghost when empty.
    func step(_ direction: Double) {
        guard let focus, let target = focusedSet else { return }
        let set = target.set, ex = target.exercise
        let g = ghost(for: set, in: ex)
        switch focus.field {
        case .kg:
            let v = max(0, (set.weightKg ?? g.kg ?? 0) + 2.5 * direction)
            set.weightKg = v
            buffer = Self.plain(v)
        case .reps:
            let v = max(0, (set.reps ?? g.reps ?? 0) + Int(direction))
            set.reps = v
            buffer = String(v)
        case .rpe:
            let v = min(10, max(1, (set.rpe ?? 7.5) + 0.5 * direction))
            set.rpe = v
            buffer = Self.plain(v)
        }
        changed(set)
    }

    /// kg → reps → the next set's kg.
    func advance() {
        guard let focus, let target = focusedSet else { return }
        let set = target.set, ex = target.exercise
        switch focus.field {
        case .kg: edit(set, .reps)
        case .reps, .rpe:
            if let next = ex.orderedSets.first(where: { $0.setIndex > set.setIndex }) {
                edit(next, ex.loadType == .weight ? .kg : .reps)
            } else {
                self.focus = nil
            }
        }
    }

    func setWeight(_ kg: Double) {
        guard let set = focusedSet?.set else { return }
        set.weightKg = kg
        buffer = Self.plain(kg)
        changed(set)
    }

    private func commitBuffer() {
        guard let focus, let set = focusedSet?.set else { return }
        switch focus.field {
        case .kg: set.weightKg = Double(buffer)
        case .reps: set.reps = Int(buffer)
        case .rpe: set.rpe = Double(buffer)
        }
        changed(set)
    }

    /// Keeps entries in the platform's clamps: kg ≤ 500 (2 decimals), reps ≤ 100, RPE ≤ 10.
    static func accepts(_ text: String, field: SetFocus.Field) -> Bool {
        if text.isEmpty { return true }
        switch field {
        case .reps:
            guard let v = Int(text) else { return false }
            return v <= 100
        case .kg:
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count <= 2, (parts.count < 2 || parts[1].count <= 2),
                  let v = Double(text.hasSuffix(".") ? String(text.dropLast()) : text) else { return false }
            return v <= 500
        case .rpe:
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count <= 2, (parts.count < 2 || parts[1].count <= 1),
                  let v = Double(text.hasSuffix(".") ? String(text.dropLast()) : text) else { return false }
            return v <= 10
        }
    }

    // MARK: exercises

    func add(_ exercise: Exercise) {
        dropUndo()
        SessionFactory.add(exercise, to: session, sets: 3, in: store)
        edited()
    }

    func remove(_ ex: LocalSessionExercise) {
        dropUndo()
        session.deletedSetIDs.append(contentsOf: ex.sets.map(\.id))
        session.deletedExerciseIDs.append(ex.id)
        if let group = ex.supersetGroup { ungroup(group, leaving: ex) }
        session.exercises.removeAll { $0.id == ex.id }
        store.context.delete(ex)
        renumber()
        edited()
    }

    func move(from source: IndexSet, to destination: Int) {
        dropUndo()
        var list = exercises
        list.move(fromOffsets: source, toOffset: destination)
        for (i, ex) in list.enumerated() { ex.position = i }
        edited()
    }

    /// Links an exercise with the one below it, or takes it out of its superset.
    func toggleSuperset(_ ex: LocalSessionExercise) {
        dropUndo()
        if let group = ex.supersetGroup {
            ex.supersetGroup = nil
            ungroup(group, leaving: ex)
        } else {
            let list = exercises
            guard let i = list.firstIndex(where: { $0.id == ex.id }), i + 1 < list.count else { return }
            let group = list[i + 1].supersetGroup ?? ((list.compactMap(\.supersetGroup).max() ?? 0) + 1)
            ex.supersetGroup = group
            list[i + 1].supersetGroup = group
        }
        edited()
    }

    /// A superset left with one exercise isn't one any more.
    func ungroup(_ group: Int, leaving ex: LocalSessionExercise) {
        let rest = exercises.filter { $0.supersetGroup == group && $0.id != ex.id }
        if rest.count < 2 { rest.forEach { $0.supersetGroup = nil } }
    }

    func renumber() {
        for (i, ex) in exercises.enumerated() { ex.position = i }
    }

    func canLinkBelow(_ ex: LocalSessionExercise) -> Bool {
        guard let i = exercises.firstIndex(where: { $0.id == ex.id }) else { return false }
        return i + 1 < exercises.count
    }

    // MARK: rest timer

    private func startRest(after ex: LocalSessionExercise) {
        // Inside a superset the partner follows straight away; rest after the round.
        if let group = ex.supersetGroup {
            let partners = exercises.filter { $0.supersetGroup == group }
            if let i = partners.firstIndex(where: { $0.id == ex.id }), i + 1 < partners.count,
               partners[(i + 1)...].contains(where: { p in p.sets.contains { !$0.isCompleted } }) {
                skipRest()
                return
            }
        }
        rest.start(seconds: ex.restSec, now: .now)
        followRest()
        persistRest(exercise: ex.name)
    }

    func adjustRest(by delta: TimeInterval) {
        let ranOut = rest.adjust(by: delta, now: .now)
        followRest()
        if ranOut {
            restEnded()
        } else {
            persistRest(exercise: nil)
        }
    }

    func skipRest() {
        rest.skip()
        followRest()
        session.restEndsAt = nil
        session.restTotal = 0
        showWorkout()
    }

    func dismissRestBanner() {
        rest.dismiss()
        followRest()
    }

    private func persistRest(exercise: String?) {
        session.restEndsAt = rest.endsAt
        session.restTotal = rest.total
        store.save()
        guard let end = rest.endsAt else { return }
        lastActivityNext = nextLabel()
        liveActivity?.show(session: session.id, title: session.title, startedAt: session.startedAt, endsAt: end,
                           total: rest.total, exercise: exercise ?? nextUp?.exercise.name ?? session.title,
                           next: lastActivityNext ?? "")
    }

    private func restEnded() {
        restsEnded += 1
        session.restEndsAt = nil
        session.restTotal = 0
        store.save()
        lastActivityNext = nextLabel()
        liveActivity?.finish(session: session.id, next: lastActivityNext ?? "")
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                if self.rest.isRunning, self.rest.endsAt.map({ $0 <= .now }) == true {
                    self.rest.tick(now: .now)
                    self.followRest()
                    self.restEnded()
                }
            }
        }
    }

    // MARK: finish

    /// The server's numbers, or `nil` when offline ("will sync").
    func finish(bodyweightKg: Double? = nil) async -> TrainSession? {
        guard machine.enter(.finishing) else { return nil }
        defer { machine.enter(.completed) }
        stop()
        endUndo()
        rest.skip()
        liveActivity?.end()
        focus = nil
        // Empty rows aren't sets.
        for ex in session.exercises {
            for set in ex.sets where !set.isCompleted && set.reps == nil && set.weightKg == nil {
                session.deletedSetIDs.append(set.id)
                ex.sets.removeAll { $0.id == set.id }
                store.context.delete(set)
            }
        }
        return await sync.finish(session, bodyweightKg: bodyweightKg)
    }

    func discard() {
        machine.enter(.discarded)
        stop()
        endUndo()
        liveActivity?.end()
        sync.discard(session)
    }
}
