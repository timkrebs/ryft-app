import Foundation
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
    private var store: TrainStore { sync.store }

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

    nonisolated var id: UUID { sessionID }
    private nonisolated let sessionID: UUID

    /// `liveActivity` is nil in previews and tests.
    init(session: LocalSession, sync: TrainSyncService, liveActivity: RestActivityController?) {
        self.session = session
        self.sessionID = session.id
        self.sync = sync
        self.liveActivity = liveActivity
        rest = RestTimer(endsAt: session.restEndsAt, total: session.restTotal, now: .now)
        startTicker()
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
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
        guard let next = nextUp(after: ex) else { return String(localized: "Last set done — finish when ready") }
        let sets = next.exercise.orderedSets
        let n = (sets.firstIndex { $0.id == next.set.id } ?? 0) + 1
        return String(localized: "\(next.exercise.name) · set \(n) of \(sets.count)",
                      comment: "Next set in the rest timer, e.g. Bench press · set 3 of 4.")
    }

    /// Within a superset the partner comes next; otherwise the first open set.
    private func nextUp(after ex: LocalSessionExercise?) -> (exercise: LocalSessionExercise, set: LocalSet)? {
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
        session.deletedSetIDs.append(set.id)
        if focus?.setID == set.id { focus = nil }
        ex.sets.removeAll { $0.id == set.id }
        store.context.delete(set)
        for (i, s) in ex.orderedSets.enumerated() where s.setIndex != i {
            s.setIndex = i
            s.updatedAt = .now
        }
        sync.sessionChanged(session)
    }

    private func changed(_ set: LocalSet) {
        set.updatedAt = .now
        sync.sessionChanged(session)
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
        SessionFactory.add(exercise, to: session, sets: 3, in: store)
        sync.sessionChanged(session)
    }

    func remove(_ ex: LocalSessionExercise) {
        session.deletedSetIDs.append(contentsOf: ex.sets.map(\.id))
        if let group = ex.supersetGroup { ungroup(group, leaving: ex) }
        session.exercises.removeAll { $0.id == ex.id }
        store.context.delete(ex)
        renumber()
        sync.sessionChanged(session)
    }

    func move(from source: IndexSet, to destination: Int) {
        var list = exercises
        list.move(fromOffsets: source, toOffset: destination)
        for (i, ex) in list.enumerated() { ex.position = i }
        sync.sessionChanged(session)
    }

    /// Links an exercise with the one below it, or takes it out of its superset.
    func toggleSuperset(_ ex: LocalSessionExercise) {
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
        sync.sessionChanged(session)
    }

    /// A superset left with one exercise isn't one any more.
    private func ungroup(_ group: Int, leaving ex: LocalSessionExercise) {
        let rest = exercises.filter { $0.supersetGroup == group && $0.id != ex.id }
        if rest.count < 2 { rest.forEach { $0.supersetGroup = nil } }
    }

    private func renumber() {
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
        persistRest(exercise: ex.name)
    }

    func adjustRest(by delta: TimeInterval) {
        if rest.adjust(by: delta, now: .now) {
            restEnded()
        } else {
            persistRest(exercise: nil)
        }
    }

    func skipRest() {
        rest.skip()
        session.restEndsAt = nil
        session.restTotal = 0
        liveActivity?.end()
    }

    func dismissRestBanner() {
        rest.dismiss()
    }

    private func persistRest(exercise: String?) {
        session.restEndsAt = rest.endsAt
        session.restTotal = rest.total
        store.save()
        guard let end = rest.endsAt else { return }
        liveActivity?.show(session: session.title, endsAt: end, total: rest.total,
                           exercise: exercise ?? nextUp?.exercise.name ?? session.title,
                           next: nextLabel())
    }

    private func restEnded() {
        restsEnded += 1
        session.restEndsAt = nil
        session.restTotal = 0
        store.save()
        liveActivity?.finish(next: nextLabel())
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                if self.rest.isRunning, self.rest.endsAt.map({ $0 <= .now }) == true {
                    self.rest.tick(now: .now)
                    self.restEnded()
                }
            }
        }
    }

    // MARK: finish

    /// The server's numbers, or `nil` when offline ("will sync").
    func finish(bodyweightKg: Double? = nil) async -> TrainSession? {
        stop()
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
        stop()
        liveActivity?.end()
        sync.discard(session)
    }
}
