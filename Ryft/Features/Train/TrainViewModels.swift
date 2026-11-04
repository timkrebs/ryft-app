import Foundation
import Observation

// View models for the Train screens. The live session's is `SessionController`;
// `TrainLibrary` (offline library + platform) and `TrainSyncService` (outbox) are
// the services these read from.

/// Finished sessions grouped by calendar week, newest first.
@MainActor
@Observable
final class TrainHistoryViewModel {
    private let library: TrainLibrary

    private(set) var sessions: [SessionSummary] = []
    private(set) var loaded = false

    struct Week: Identifiable, Equatable {
        let start: Date
        let sessions: [SessionSummary]
        var id: Date { start }
        var volume: Double { sessions.compactMap(\.volumeKg).reduce(0, +) }
        var load: Double? {
            let loads = sessions.compactMap(\.muscularTrimp)
            return loads.isEmpty ? nil : loads.reduce(0, +)
        }
        var title: String { String(localized: "Week of \(start.formatted(.dateTime.day().month(.abbreviated)))") }
        var summary: String { "\(sessions.count) · \(Fmt.volume(volume)) · " + String(localized: "load \(Fmt.load(load))") }
    }

    init(library: TrainLibrary) {
        self.library = library
    }

    var weeks: [Week] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: sessions) { cal.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start ?? $0.startedAt }
        return grouped.map { Week(start: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.start > $1.start }
    }

    var isEmpty: Bool { sessions.isEmpty }

    /// Cached at once, then the platform's.
    func load() async {
        sessions = library.cachedSessions()
        sessions = await library.sessions()
        loaded = true
    }

    func refresh() async { sessions = await library.sessions() }
}

/// One exercise: e1RM over the last 90 days, records, recent sets.
@MainActor
@Observable
final class ExerciseDetailViewModel {
    let exerciseID: UUID
    private let fallbackName: String?
    private let library: TrainLibrary
    private let clock: AppClock

    private(set) var history: ExerciseHistory?
    private(set) var loaded = false

    init(exerciseID: UUID, name: String? = nil, library: TrainLibrary, clock: AppClock) {
        self.exerciseID = exerciseID
        fallbackName = name
        self.library = library
        self.clock = clock
    }

    var exercise: Exercise? { library.exercise(id: exerciseID) }
    var title: String { exercise?.name ?? fallbackName ?? "" }

    /// The chart window: the last 90 days.
    var points: [E1RMPoint] {
        let from = DayFormat.string(from: DayFormat.shift(clock.now(), days: -89))
        return (history?.e1rm ?? []).filter { $0.day >= from }
    }

    var current: String { points.last.map { Fmt.kg($0.value) } ?? Fmt.placeholder }

    /// "Barbell · Chest · Triceps".
    var subtitle: String? {
        exercise.map { ([$0.kind.title] + $0.primaryMuscles.map(\.title)).joined(separator: " · ") }
    }

    /// "+6.5 kg in 90 days".
    var change: String? {
        guard let first = points.first?.value, let last = points.last?.value, points.count > 1 else { return nil }
        let delta = last - first
        return String(localized: "\(delta >= 0 ? "+" : "−")\(Fmt.kg(abs(delta))) in 90 days")
    }

    var bestE1RM: Double? { history?.prs.first { $0.kind == .e1rm }?.value }
    var records: [PersonalRecord] { history?.prs ?? [] }

    /// The newest session against the one before.
    var lastDelta: MetricDelta? {
        guard points.count >= 2 else { return nil }
        return MetricDelta(current: points[points.count - 1].value, reference: points[points.count - 2].value)
    }

    var hasTrend: Bool { points.count >= 2 }
    var emptyChartText: String {
        loaded ? String(localized: "Log this exercise twice to see a trend.") : String(localized: "Loading…")
    }
    var emptySetsText: String {
        loaded ? String(localized: "No sets logged for this exercise yet.") : String(localized: "Loading…")
    }

    /// One recent session: its day, the working sets, their best e1RM.
    struct RecentRow: Identifiable, Equatable {
        let id: Int
        let date: String
        let sets: String
        let best: Double?
        var bestText: String? { best.map { Fmt.kgNumber(E1RM.rounded($0)) } }
        var bestSpoken: String? { best.map { String(localized: "e1RM \(Fmt.kg(E1RM.rounded($0)))") } }
    }

    /// The last ten sessions with this exercise.
    var recentRows: [RecentRow] {
        (history?.sessions ?? []).prefix(10).enumerated().map { i, entry in
            let working = entry.sets.filter { !$0.isWarmup }
            return RecentRow(id: i, date: entry.startedAt.formatted(.dateTime.day().month(.abbreviated)),
                             sets: working.map(SetText.short).joined(separator: "  ·  "),
                             best: E1RM.best(of: working))
        }
    }

    func load() async {
        history = library.cachedHistory(for: exerciseID)
        history = await library.history(for: exerciseID) ?? history
        loaded = true
    }
}

/// Built-in templates, the user's plans and the current (active or paused) enrolment.
@MainActor
@Observable
final class PlansViewModel {
    private let library: TrainLibrary
    private(set) var working = false

    init(library: TrainLibrary) {
        self.library = library
    }

    /// The plan the card is about: the active one, else the paused one.
    var currentPlanID: UUID? { library.activeEnrollment?.planId ?? library.pausedPlanID }
    var isPaused: Bool { library.isPaused }
    var currentName: String {
        guard let id = currentPlanID else { return String(localized: "Your plan") }
        return library.catalog?.summary(id: id)?.name ?? library.plan(id: id)?.name ?? String(localized: "Your plan")
    }
    var currentWeekText: String? { library.activeEnrollment.map { String(localized: "Week \($0.currentWeek)") } }
    /// "Resume continues where you stopped." / "Next: Upper A".
    var currentDetail: String? {
        if isPaused { return String(localized: "Resume continues where you stopped.") }
        return library.today.map { String(localized: "Next: \($0.day.name)") }
    }

    var builtin: [PlanSummary] { library.catalog?.builtin ?? [] }
    var mine: [PlanSummary] { library.catalog?.mine ?? [] }
    var error: String? { library.error }
    var errorDetails: String? { library.errorDetails }

    /// Only the first visit loads; pull to refresh reloads.
    func loadIfNeeded() async { if library.catalog == nil { await library.refresh() } }
    func refresh() async { await library.refresh() }

    func togglePause() async {
        working = true
        _ = await library.setPaused(!library.isPaused)
        working = false
    }
}

/// A plan's weeks → days → exercises, and enrol / switch / pause / delete.
@MainActor
@Observable
final class PlanDetailViewModel {
    let planID: UUID
    private let library: TrainLibrary

    private(set) var plan: Plan?
    var week = 1
    private(set) var working = false

    init(planID: UUID, library: TrainLibrary) {
        self.planID = planID
        self.library = library
    }

    /// Active or paused: this plan is the one the user is on.
    var isCurrent: Bool { (library.activeEnrollment?.planId ?? library.pausedPlanID) == planID }
    var isPaused: Bool { library.isPaused }
    var hasEnrollment: Bool { library.activeEnrollment != nil }
    var currentPlanName: String { library.activePlanName ?? String(localized: "Your current plan") }
    var error: String? { library.error }
    var errorDetails: String? { library.errorDetails }

    var weeks: [Int] { Array(Set(plan?.days.compactMap(\.week) ?? [])).sorted() }

    var shownDays: [PlanDay] {
        guard let plan else { return [] }
        let days = weeks.isEmpty ? plan.days : plan.days.filter { $0.week == nil || $0.week == week }
        return days.sorted { $0.dayIndex < $1.dayIndex }
    }

    func load() async {
        plan = await library.loadPlan(id: planID)
        if !weeks.contains(week) { week = weeks.first ?? 1 }
    }

    func enroll() async {
        guard let plan else { return }
        working = true
        _ = await library.enroll(in: plan)
        working = false
    }

    func togglePause() async {
        working = true
        _ = await library.setPaused(!library.isPaused)
        working = false
    }

    /// `true` when it's gone (the screen closes).
    func delete() async -> Bool {
        guard let plan else { return false }
        return await library.deletePlan(plan)
    }
}

/// Create or edit a plan: live validation, a new day, renumbering, save.
@MainActor
@Observable
final class PlanBuilderViewModel {
    private let library: TrainLibrary
    let original: Plan

    var plan: Plan
    /// Issues show only after the first Save.
    private(set) var attempted = false
    private(set) var saving = false

    init(plan: Plan, library: TrainLibrary) {
        self.plan = plan
        original = plan
        self.library = library
    }

    var issues: [PlanIssue] { PlanValidation.issues(in: plan) }
    var shownIssues: [PlanIssue] { attempted ? issues : [] }
    var isNew: Bool { original.name.isEmpty }
    var hasChanges: Bool { plan != original }

    /// "Day C" after A and B.
    func addDay() {
        let i = (plan.days.map(\.dayIndex).max() ?? -1) + 1
        let letter = String(UnicodeScalar(UInt8(65 + min(i, 25))))
        plan.days.append(PlanDay(dayIndex: i, name: String(localized: "Day \(letter)"), exercises: []))
    }

    func removeDay(_ id: UUID) {
        plan.days.removeAll { $0.id == id }
    }

    /// A new exercise with defaults for its load type: 3 × 8–10 @ RPE 8, or 3 × 10–12 bodyweight.
    func add(_ e: Exercise, toDay dayID: UUID) {
        guard let d = plan.days.firstIndex(where: { $0.id == dayID }) else { return }
        let weighted = e.loadType == .weight
        plan.days[d].exercises.append(PlanExercise(
            exercise: e, position: plan.days[d].exercises.count, sets: 3,
            repsMin: weighted ? 8 : 10, repsMax: weighted ? 10 : 12,
            targetKind: weighted ? .rpe : .bodyweight, targetValue: weighted ? 8 : nil,
            restSec: SessionFactory.defaultRest(for: e)))
    }

    /// Whether exercise `i` is in a superset with the next one.
    func isLinked(dayID: UUID, _ i: Int) -> Bool {
        guard let day = plan.days.first(where: { $0.id == dayID }),
              i + 1 < day.exercises.count, let g = day.exercises[i].supersetGroup else { return false }
        return day.exercises[i + 1].supersetGroup == g
    }

    /// Superset with the next exercise (or split it off).
    func link(dayID: UUID, _ i: Int, _ on: Bool) {
        guard let d = plan.days.firstIndex(where: { $0.id == dayID }), i + 1 < plan.days[d].exercises.count else { return }
        if on {
            let group = plan.days[d].exercises[i].supersetGroup
                ?? plan.days[d].exercises[i + 1].supersetGroup
                ?? ((plan.days[d].exercises.compactMap(\.supersetGroup).max() ?? 0) + 1)
            plan.days[d].exercises[i].supersetGroup = group
            plan.days[d].exercises[i + 1].supersetGroup = group
        } else {
            plan.days[d].exercises[i + 1].supersetGroup = nil
            if i == 0 || !isLinked(dayID: dayID, i - 1) { plan.days[d].exercises[i].supersetGroup = nil }
        }
    }

    func remove(dayID: UUID, _ i: Int) {
        guard let d = plan.days.firstIndex(where: { $0.id == dayID }), plan.days[d].exercises.indices.contains(i) else { return }
        plan.days[d].exercises.remove(at: i)
        renumber(dayID: dayID)
    }

    func move(dayID: UUID, _ i: Int, by delta: Int) {
        guard let d = plan.days.firstIndex(where: { $0.id == dayID }) else { return }
        let j = i + delta
        guard plan.days[d].exercises.indices.contains(i), plan.days[d].exercises.indices.contains(j) else { return }
        plan.days[d].exercises.swapAt(i, j)
        renumber(dayID: dayID)
    }

    /// Positions follow the order; a superset left with one member isn't one.
    func renumber(dayID: UUID) {
        guard let d = plan.days.firstIndex(where: { $0.id == dayID }) else { return }
        for i in plan.days[d].exercises.indices { plan.days[d].exercises[i].position = i }
        let counts = Dictionary(grouping: plan.days[d].exercises.compactMap(\.supersetGroup), by: { $0 }).mapValues(\.count)
        for i in plan.days[d].exercises.indices {
            if let g = plan.days[d].exercises[i].supersetGroup, counts[g, default: 0] < 2 {
                plan.days[d].exercises[i].supersetGroup = nil
            }
        }
    }

    /// `true` when saved (the sheet closes); validation failures keep it open.
    func save() async -> Bool {
        attempted = true
        plan.name = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard issues.isEmpty else { return false }
        saving = true
        defer { saving = false }
        return await library.savePlan(plan)
    }
}

/// Train on Today and the start sheet: today's prescription, the session done
/// today, the last session to repeat, the active plan's days.
@MainActor
@Observable
final class TrainTodayViewModel {
    private let library: TrainLibrary
    private let store: TrainStore
    private let clock: AppClock

    private(set) var lastSession: TrainSession?
    private(set) var activePlan: Plan?

    init(library: TrainLibrary, store: TrainStore, clock: AppClock) {
        self.library = library
        self.store = store
        self.clock = clock
    }

    var today: PlanToday? { library.today }
    var todayText: String? { today.map { "\($0.day.name) · \(TodayPlanText.detail($0))" } }

    /// Strain → Train: "Today's plan: Upper A".
    var todayLinkTitle: String? { today.map { String(localized: "Today's plan: \($0.day.name)") } }
    var todayLinkDetail: String? { today.map(TodayPlanText.detail) }

    /// "Upper/Lower 4× · week 6", "… · paused", or an invitation.
    var plansDetail: String {
        if let e = library.activeEnrollment, e.status == .active {
            return String(localized: "\(library.activePlanName ?? "") · week \(e.currentWeek)")
        }
        if let paused = library.pausedPlanID {
            let name = library.catalog?.summary(id: paused)?.name ?? library.plan(id: paused)?.name ?? ""
            return String(localized: "\(name) · paused")
        }
        return String(localized: "Pick a plan or build your own")
    }

    /// "Last: Upper A · Yesterday".
    var historyDetail: String? {
        guard let last = library.cachedSessions().first else { return nil }
        return String(localized: "Last: \(last.title) · \(Fmt.dayTitle(last.startedAt, today: clock.now()))")
    }

    var doneToday: LocalSession? {
        store.completedSessions(from: Calendar.current.startOfDay(for: clock.now())).first
    }

    /// "Done · load 11.2 · 2 PRs": the session's `strain`, the muscular load on the strain scale.
    static func doneText(_ s: LocalSession) -> String {
        var parts = [String(localized: "Done")]
        if let load = s.strain { parts.append(String(localized: "load \(Fmt.load(load))")) }
        let prs = s.prs.count
        if prs > 0 { parts.append(String(localized: "\(prs) PRs")) }
        return parts.joined(separator: " · ")
    }

    /// The active plan's days, ordered by week then day.
    var planDays: [PlanDay] {
        (activePlan?.days ?? []).sorted { ($0.week ?? 0, $0.dayIndex) < ($1.week ?? 0, $1.dayIndex) }
    }

    func loadStartOptions() async {
        lastSession = await library.lastSession()
        if let id = library.activeEnrollment?.planId { activePlan = await library.loadPlan(id: id) }
    }
}

/// The custom-exercise form's values and the exercise they make.
struct CustomExerciseDraft: Equatable {
    var name: String
    var kind: ExerciseKind = .dumbbell
    /// nil until chosen (the import leaves it empty); the form's own default is chest.
    var muscle: Muscle? = .chest
    var loadType: LoadType = .weight
    var unilateral = false

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSave: Bool { !trimmedName.isEmpty && muscle != nil }

    /// "Landmine press" → slug `landmine-press`.
    var slug: String {
        trimmedName.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
    }

    var exercise: Exercise {
        Exercise(slug: slug, name: trimmedName, kind: kind, primaryMuscles: muscle.map { [$0] } ?? [],
                 equipment: [kind.rawValue], loadType: loadType,
                 bodyweightFactor: loadType == .bodyweight ? 1 : 0, isUnilateral: unilateral, isCustom: true)
    }
}
