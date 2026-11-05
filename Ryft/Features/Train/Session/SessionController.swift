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
    /// List or Focused, set when the controller is built. It holds while the session is on screen; reopening builds a new
    /// controller and picks up the flag, which suits a rollback.
    let layout: SessionLayout
    /// The fourth column's stored choice (SessionController+Column.swift).
    @ObservationIgnored let settings: Settings

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
    /// Ends the pill's "Rest over" (`settleRestOver`).
    @ObservationIgnored private var restOverTask: Task<Void, Never>?
    /// How long the pill says "Rest over" (design.md §2.7).
    static let restOverHold: Duration = .seconds(1)
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
         clock: AppClock = SystemClock(), library: SessionLibrary? = nil, layout: SessionLayout = .list,
         settings: Settings = .shared) {
        self.session = session
        self.sessionID = session.id
        self.sync = sync
        self.clock = clock
        self.library = library
        self.layout = layout
        self.settings = settings
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
    private(set) var lastActivityNext: String?

    // MARK: jump-to-next state (SessionController+Advance.swift)
    // Set only from that file (an extension elsewhere can't reach `private(set)`).

    /// Cards collapsed after their last set; shown through `isCollapsed(_:)`. UI state, not persisted.
    var collapsed: Set<UUID> = []
    /// The latest jump for the view to perform (scroll, highlight).
    var advance: AdvanceRequest?
    /// Profile → Training → Jump to next exercise; the coordinator wires the setting.
    @ObservationIgnored var jumpToNext: @MainActor () -> Bool = { true }
    @ObservationIgnored var userExpanded: Set<UUID> = []
    @ObservationIgnored var advanceTask: Task<Void, Never>?
    /// Checks waiting for the delay (the latest per exercise): a second check inside 0.6 s keeps the first's collapse.
    @ObservationIgnored var pendingChecks: [SessionAdvance.SetRef] = []
    /// Collapses decided while the list stayed put: applied with the next jump, so rows never move under the thumb.
    @ObservationIgnored var carriedCollapse: [UUID] = []
    @ObservationIgnored var lastManualScroll: Date?
    /// The exercise of the last check: the current-set highlight follows its `nextUp(after:)`.
    var lastCheckedExercise: UUID?

    // MARK: focused page state (SessionController+Page.swift)

    /// The row the user made active, over the first open set; a page change, a check or a fold clears it. UI state,
    /// not persisted.
    var tappedSet: UUID?
    /// Exercises whose warm-up group is open. Starts folded (L6); UI state, not persisted: a rebuild folds them again.
    var expandedWarmups: Set<UUID> = []
    /// The latest group that folded itself, for the view.
    var autoFold: AutoFold?
    /// The latest check that opened the keypad instead of logging, for the view.
    var emptyCheck: EmptyCheck?

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
        restOverTask?.cancel()
        restOverTask = nil
        cancelAdvance()
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

    /// "Bench press · set 3 of 4" — the next set to do after the last check (`SessionAdvance.next`).
    var nextUp: (exercise: LocalSessionExercise, set: LocalSet)? { nextUp(after: nil) }

    func nextLabel(after ex: LocalSessionExercise? = nil) -> String {
        guard !exercises.isEmpty else { return String(localized: "Add an exercise") }
        guard let next = nextUp(after: ex) else { return String(localized: "Last set done — finish when ready") }
        let at = position(of: next.set, in: next.exercise)
        let label = at.isWarmup
            ? String(localized: "\(next.exercise.name) · warm-up \(at.number) of \(at.count)",
                     comment: "Next set in the rest timer when it is a warm-up, e.g. Bench press · warm-up 1 of 2.")
            : String(localized: "\(next.exercise.name) · set \(at.number) of \(at.count)",
                     comment: "Next set in the rest timer, e.g. Bench press · set 3 of 4.")
        // "· 5 × 80 kg" when the set is filled in (from the plan or the last time). A read-only row still counts: it is
        // on screen and gets checked, and what it holds is its stored time or distance.
        let stored = isReadOnly(next.set)
            ? SetStoredValue(reps: next.set.reps, durationSec: next.set.durationSec, distanceM: next.set.distanceM)?.text
            : nil
        guard let target = stored ?? Self.target(reps: next.set.reps, kg: next.set.weightKg) else { return label }
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

    /// After `ex` (default: the exercise checked last): a superset's partner first, then the list below, wrapping
    /// to the top; an exercise without an open working set is skipped (`SessionAdvance.next`, lead decision D-a).
    /// Focused with no check to follow (a relaunch on page 3, or the checked exercise was removed): the row on the page. The
    /// planner's "after" means "just checked", which would skip that row for its superset partner.
    func nextUp(after ex: LocalSessionExercise?) -> (exercise: LocalSessionExercise, set: LocalSet)? {
        if let id = ex?.id ?? lastCheckedExercise { return nextOpenSet(after: id) }
        guard layout == .focused else { return nextOpenSet(after: nil) }
        if let page = pageExercise, Self.hasOpenWorkingSet(page), let set = activeSet(in: page) { return (page, set) }
        return nextOpenSet(after: pageExerciseID)
    }

    // MARK: sets

    func toggleCheck(_ set: LocalSet, in ex: LocalSessionExercise) {
        if set.isCompleted {
            set.completedAt = nil
            checkUndone(in: ex)
            // An unchecked set is the one to do again; a keypad on another row would type into a row that isn't active.
            if layout == .focused {
                tappedSet = set.id
                if focus?.setID != set.id { focus = nil }
            }
        } else {
            let g = ghost(for: set, in: ex)
            if set.reps == nil { set.reps = g.reps }
            if set.weightKg == nil, ex.loadType == .weight { set.weightKg = g.kg }
            set.completedAt = .now
            setsChecked += 1
            if layout == .focused {
                focus = nil
                tappedSet = nil
            } else if focus?.setID == set.id {
                focus = nil
            }
            // First: it sets the exercise checked last, so the rest's lock-screen "next" is right at once.
            scheduleAdvance(after: set, in: ex)
            startRest(after: ex)
            foldWarmupsIfDone(after: set, in: ex)
        }
        changed(set)
    }

    func toggleWarmup(_ set: LocalSet) {
        // Focused: a row that becomes a warm-up stays on screen, in its open group.
        if layout == .focused, !set.isWarmup, let ex = set.exercise { expandedWarmups.insert(ex.id) }
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
        pruneCollapsed()
        sync.sessionChanged(session)
        // Focused hides the pill with nothing left to do, so a rest would run on with no Skip and no ±15, and end on the
        // lock screen alone. As after the last set's check; a delete, a warm-up or a remove gets here too. List keeps its bar.
        if layout == .focused, rest.isRunning, exercises.isEmpty || isAllDone { skipRest() }
        refreshActivity()
    }

    // MARK: keypad

    func edit(_ set: LocalSet, _ field: SetFocus.Field) {
        focus = SetFocus(setID: set.id, field: field)
        // The active row follows the keypad.
        if layout == .focused {
            tappedSet = set.id
            activeRowChanged()
        }
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

    /// kg → reps → the next set's kg. In Focused the next set is the next row of the table (`nextRow`).
    func nextField() {
        guard let focus, let target = focusedSet else { return }
        let set = target.set, ex = target.exercise
        switch focus.field {
        case .kg where !isReadOnly(set): edit(set, .reps)
        case .kg, .reps, .rpe:
            if let next = nextRow(after: set, in: ex) {
                edit(next, ex.loadType == .weight ? .kg : .reps)
            } else {
                self.focus = nil
                // Focused: off the end of the table the first open set is active again.
                if layout == .focused {
                    tappedSet = nil
                    activeRowChanged()
                }
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

    @discardableResult
    func add(_ exercise: Exercise) -> LocalSessionExercise {
        dropUndo()
        let row = SessionFactory.add(exercise, to: session, sets: 3, in: store)
        edited()
        return row
    }

    func remove(_ ex: LocalSessionExercise) {
        dropUndo()
        leavePage(of: ex)
        session.deletedSetIDs.append(contentsOf: ex.sets.map(\.id))
        session.deletedExerciseIDs.append(ex.id)
        if let group = ex.supersetGroup { ungroup(group, leaving: ex) }
        session.exercises.removeAll { $0.id == ex.id }
        // The planner reads an id it can't find as nil, from the top, so List sees no change; Focused gets its page fallback.
        if lastCheckedExercise == ex.id { lastCheckedExercise = nil }
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
        // The last working set: nothing follows, so no rest (no countdown on the lock screen, no "Rest over" later),
        // and one still running from before stops.
        if isAllDone {
            skipRest()
            return
        }
        // Inside a superset the partner follows straight away while it has an open working set (an open warm-up
        // doesn't count, as in `SessionAdvance`); rest after the round.
        if let group = ex.supersetGroup {
            let partners = exercises.filter { $0.supersetGroup == group }
            if let i = partners.firstIndex(where: { $0.id == ex.id }), i + 1 < partners.count,
               partners[(i + 1)...].contains(where: { p in p.sets.contains { !$0.isWarmup && !$0.isCompleted } }) {
                skipRest()
                return
            }
        }
        startRest(for: ex)
    }

    /// A rest with no set checked (the rest sheet's Start), and the last step of a rest after a check. `seconds` is the
    /// sheet's value, else the exercise's rest. Nothing else moves: no check counted, no advance, the active row stays,
    /// and `persistRest` writes only the rest's own fields, so nothing is uploaded.
    func startRest(for ex: LocalSessionExercise, seconds: Int? = nil) {
        rest.start(seconds: seconds ?? ex.restSec, now: .now)
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
        settleRestOver()
    }

    /// Focused: the pill says "Rest over" for a moment and goes back to idle by itself. Here, not on the pill: the rest can
    /// end behind a sheet. List keeps its banner until it is dismissed. `dismiss` leaves a rest started since alone.
    private func settleRestOver() {
        guard layout == .focused else { return }
        restOverTask?.cancel()
        restOverTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: Self.restOverHold) } catch { return }
            guard !Task.isCancelled else { return }
            self?.dismissRestBanner()
        }
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
