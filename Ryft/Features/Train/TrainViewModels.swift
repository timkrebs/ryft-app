import Foundation
import Observation

// View models for the Train screens. The live session's is `SessionController`;
// `TrainLibrary` (offline library + platform) and `TrainSyncService` (outbox) are
// the services these read from.

/// Finished sessions of the last 90 days grouped by calendar week, newest first.
@MainActor
@Observable
final class TrainHistoryViewModel {
    /// History shows the last 90 days: the window the platform's list is read for.
    nonisolated static let windowDays = 90

    private let library: TrainLibrary
    private let now: () -> Date

    private(set) var sessions: [SessionSummary] = []
    private(set) var loaded = false
    /// The last read reached the platform.
    private(set) var fresh = false
    /// When the list on screen was fetched: the offline line's time.
    private(set) var fetchedAt: Date?

    /// What the page shows. `empty` only after the platform answered with no session (now, or in the copy on this phone);
    /// a failed read with nothing cached is `failed`, never "No workouts logged yet".
    enum State: Equatable {
        case loading, failed, empty, list
    }

    struct Week: Identifiable, Equatable {
        let start: Date
        let sessions: [SessionSummary]
        var id: Date { start }
        var volume: Double { sessions.compactMap(\.volumeKg).reduce(0, +) }
        var load: Double? {
            let loads = sessions.compactMap(\.muscularTrimp)
            return loads.isEmpty ? nil : loads.reduce(0, +)
        }

        /// "Week of Nov 8".
        func title(locale: Locale = .autoupdatingCurrent) -> String {
            String(localized: "Week of \(start.formatted(.dateTime.day().month(.abbreviated).locale(locale)))")
        }

        /// "2 sessions · 12.2 t · load 126" (PR 6 B §7.1): the week's load summed, without decimals.
        var summary: String {
            StrainRows.join([Self.sessionCount(sessions.count), Fmt.volume(volume),
                             String(localized: "load \(Self.loadText(load))")])
        }

        /// "2 sessions, 12,200 kilograms, muscular load 126" (VoiceOver).
        func spokenSummary(locale: Locale = .autoupdatingCurrent) -> String {
            [Self.sessionCount(sessions.count), HistorySpeech.kilograms(volume, locale: locale),
             String(localized: "Muscular load \(Self.loadText(load))")].joined(separator: ", ")
        }

        static func sessionCount(_ n: Int) -> String {
            String(localized: "\(n) sessions", comment: "History's week header: how many sessions that week (\"2 sessions\").")
        }

        /// The week's load: "126"; "–" without one.
        static func loadText(_ load: Double?) -> String {
            load.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? Fmt.placeholder
        }
    }

    init(library: TrainLibrary, now: @escaping () -> Date = { .now }) {
        self.library = library
        self.now = now
    }

    /// A list already read (previews, tests): `fresh` false is the copy on this phone after a failed read.
    convenience init(library: TrainLibrary, sessions: [SessionSummary], fresh: Bool, fetchedAt: Date? = nil) {
        self.init(library: library)
        self.sessions = sessions
        self.fresh = fresh
        self.fetchedAt = fetchedAt
        loaded = true
    }

    var weeks: [Week] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: sessions) { cal.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start ?? $0.startedAt }
        return grouped.map { Week(start: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.start > $1.start }
    }

    var state: State {
        if !sessions.isEmpty { return .list }
        if !loaded { return .loading }
        return fresh || fetchedAt != nil ? .empty : .failed
    }

    /// The first visit with nothing cached: outline rows, not a spinner.
    var isLoading: Bool { state == .loading }
    /// The platform answered: no session in 90 days.
    var isEmpty: Bool { state == .empty }
    /// The read failed and nothing is cached: the message with Try again.
    var failed: Bool { state == .failed }
    /// The copy on this phone after a failed read: the quiet "Offline · as of 14:05" line.
    var isOffline: Bool { loaded && !fresh && (!sessions.isEmpty || fetchedAt != nil) }

    /// The header's subtitle, "25 workouts · last 90 days"; nil while there are none.
    var subtitle: String? {
        guard !sessions.isEmpty else { return nil }
        let window = String(localized: "last 90 days",
                            comment: "History's subtitle after the count: the list covers the last 90 days (\"25 workouts · last 90 days\").")
        return StrainRows.join([String(localized: "\(sessions.count) workouts"), window])
    }

    /// The 90 days cached at once (nothing the read would drop), then the platform's.
    func load() async {
        if sessions.isEmpty { sessions = library.cachedSessions(days: Self.windowDays, now: now()) }
        await read()
    }

    /// Pull to refresh, and the failure's Try again.
    func refresh() async { await read() }

    private func read() async {
        let read = await library.sessionsRead(days: Self.windowDays, now: now())
        sessions = read.value
        fresh = read.fresh
        fetchedAt = read.fetchedAt
        loaded = true
    }
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
    /// The last read reached the platform.
    private(set) var fresh = false
    /// When the history on screen was fetched: the offline line's time.
    private(set) var fetchedAt: Date?

    /// What leads the page (PR 6 B §7.3, review S6): the estimate (hero and chart); for a bodyweight exercise without
    /// added weight the unlit hero and why; for a timed or distance exercise, which has no 1RM, the recent sets.
    enum Lead: Equatable {
        case estimate, noAddedWeight, sets
    }

    init(exerciseID: UUID, name: String? = nil, library: TrainLibrary, clock: AppClock) {
        self.exerciseID = exerciseID
        fallbackName = name
        self.library = library
        self.clock = clock
    }

    /// A history already read (previews, tests): the page draws it as loaded; `fresh` false is the copy on this phone after
    /// a failed read.
    convenience init(exerciseID: UUID, history: ExerciseHistory?, library: TrainLibrary, clock: AppClock, fresh: Bool = true,
                     fetchedAt: Date? = nil) {
        self.init(exerciseID: exerciseID, library: library, clock: clock)
        self.history = history
        self.fresh = fresh
        self.fetchedAt = fetchedAt
        loaded = true
    }

    var exercise: Exercise? { library.exercise(id: exerciseID) }
    var title: String { exercise?.name ?? fallbackName ?? "" }

    /// Every estimate, oldest first.
    var allPoints: [E1RMPoint] { (history?.e1rm ?? []).sorted { $0.day < $1.day } }

    /// The chart window: the last 90 days, today and the 89 before.
    var points: [E1RMPoint] {
        let from = DayFormat.string(from: DayFormat.shift(clock.now(), days: -89))
        return allPoints.filter { $0.day >= from }
    }

    /// The hero's estimate: the newest in the window, or, when the last one is older, the newest of all (with its date).
    var heroPoint: E1RMPoint? { points.last ?? allPoints.last }

    /// The hero's number (PR 6 B §7.3); nil without any estimate.
    var latest: Double? { heroPoint?.value }

    /// The hero's caption when its estimate is older than the window: "As of Jul 28" ("As of Jul 28, 2025" from another
    /// year); nil inside it.
    func heroDate(locale: Locale = .autoupdatingCurrent) -> String? {
        guard points.isEmpty, let point = allPoints.last else { return nil }
        let sameYear = Calendar.current.isDate(point.date, equalTo: clock.now(), toGranularity: .year)
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
        // The key Sleep's planner and Insights use too ("As of %@").
        return String(localized: "As of \(point.date.formatted(sameYear ? style : style.year()))")
    }

    /// Now, by the app's clock: the chart's window ends here.
    var now: Date { clock.now() }

    /// "Barbell · Chest · Triceps".
    var subtitle: String? {
        exercise.map { ([$0.kind.title] + $0.primaryMuscles.map(\.title)).joined(separator: " · ") }
    }

    var lead: Lead {
        switch exercise?.loadType {
        case .time?, .distance?: return .sets
        case .bodyweight? where history != nil && allPoints.isEmpty: return .noAddedWeight
        default: return .estimate
        }
    }

    /// The change over the window, first estimate to the newest, in kg ("▲ 11.6 kg in 90 days"); nil with fewer than two.
    var change: Double? {
        guard let first = points.first?.value, let last = points.last?.value, points.count > 1 else { return nil }
        return last - first
    }

    var bestE1RM: Double? { history?.prs.first { $0.kind == .e1rm }?.value }
    var records: [PersonalRecord] { history?.prs ?? [] }

    /// The newest session against the one before, in kg ("▲ 2.9 kg vs last").
    var lastChange: Double? {
        guard points.count >= 2 else { return nil }
        return points[points.count - 1].value - points[points.count - 2].value
    }

    var hasTrend: Bool { points.count >= 2 }
    /// The first visit with nothing cached: outline cards, not "Loading…".
    var isLoading: Bool { !loaded && history == nil }
    /// The read failed and nothing is cached (the platform sends empty arrays for "no history"): the message with Try
    /// again, never "No sets logged" or an unlit hero.
    var failed: Bool { loaded && history == nil }
    /// The copy on this phone after a failed read: the quiet "Offline · as of 14:05" line.
    var isOffline: Bool { loaded && !fresh && history != nil }

    var emptyChartText: String {
        String(localized: "Log this exercise a few more times to see a trend.",
               comment: "The exercise page's chart card with fewer than two estimates in 90 days (PR 6 B §7.3).")
    }

    var emptySetsText: String { String(localized: "No sets logged for this exercise yet.") }

    /// Under the unlit hero of a bodyweight exercise logged without added weight.
    var noAddedWeightText: String {
        String(localized: "An estimated 1RM needs sets with added weight.",
               comment: "The exercise page of a bodyweight exercise with no weighted set: why there is no estimated 1RM.")
    }

    /// One recent session: its day, the working sets, their best e1RM.
    struct RecentRow: Identifiable, Equatable {
        let id: Int
        let date: String
        let sets: String
        /// "5 reps at 80 kilograms, 5 reps at 80 kilograms", "45 seconds, 45 seconds" (VoiceOver).
        let spokenSets: String
        let best: Double?
        /// "93.3": to the tenth, as the API's estimates and the chart are.
        var bestText: String? { best.map { E1RMChange.number(E1RMChange.rounded($0)) } }
        var bestSpoken: String? { best.map { String(localized: "e1RM \(Fmt.kg(E1RMChange.rounded($0)))") } }
    }

    /// The last ten sessions with this exercise; a set as the session detail draws it ("80 kg × 5", "0:45", "3.1 mi").
    func recentRows(locale: Locale = .autoupdatingCurrent) -> [RecentRow] {
        (history?.sessions ?? []).prefix(10).enumerated().map { i, entry in
            let working = entry.sets.filter { !$0.isWarmup }
            return RecentRow(id: i, date: entry.startedAt.formatted(.dateTime.day().month(.abbreviated).locale(locale)),
                             sets: StrainRows.join(working.map { SessionDetailContent.text($0) }),
                             spokenSets: working.map { SessionDetailContent.spoken($0, locale: locale) }.joined(separator: ", "),
                             best: E1RM.best(of: working))
        }
    }

    /// The cached copy at once, then the platform's; a failed read keeps the copy and says so.
    func load() async {
        if history == nil { history = library.cachedHistory(for: exerciseID) }
        let read = await library.historyRead(for: exerciseID)
        history = read.value ?? history
        fresh = read.fresh
        fetchedAt = read.fetchedAt
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

    /// The plan the tile is about: the active one, else the paused one.
    var currentPlanID: UUID? { library.activeEnrollment?.planId ?? library.pausedPlanID }
    var isPaused: Bool { library.isPaused }
    var currentName: String {
        guard let id = currentPlanID else { return String(localized: "Your plan") }
        return library.catalog?.summary(id: id)?.name ?? library.plan(id: id)?.name ?? String(localized: "Your plan")
    }

    /// The active plan's glow tile, or the paused plan's outline (PR 6 B §6.1). Active: the week, and the next day from
    /// today's prescription, else (only then: it reads the cached plan) the enrolment's day in it. Paused: neither, since
    /// `GET /v1/plans` reports no paused enrolment (API_REQUESTS Train #2).
    var tile: PlanTileContent? {
        guard let id = currentPlanID else { return nil }
        if isPaused { return PlanTileContent(planID: id, paused: true, name: currentName, week: nil, nextDay: nil) }
        let enrollment = library.activeEnrollment
        let next = library.today?.day.name
            ?? PlanTileContent.nextDayName(plan: library.plan(id: id), enrollment: enrollment)
        return PlanTileContent(planID: id, paused: false, name: currentName, week: enrollment?.currentWeek, nextDay: next)
    }

    var builtin: [PlanSummary] { library.catalog?.builtin ?? [] }
    var mine: [PlanSummary] { library.catalog?.mine ?? [] }
    var builtinRows: [PlanRowContent] { builtin.map { PlanRowContent($0, status: status(of: $0.id)) } }
    var mineRows: [PlanRowContent] { mine.map { PlanRowContent($0, status: status(of: $0.id)) } }

    private func status(of id: UUID) -> PlanTileContent.State? {
        guard id == currentPlanID else { return nil }
        return isPaused ? .paused : .active
    }

    /// Whether the first load has started: until then, as while it runs, the outline rows show.
    private(set) var startedLoading = false

    var hasCatalog: Bool { library.catalog != nil }
    /// The first load, with nothing cached: three outline rows instead of a spinner. Only while a load runs (or is about to).
    var isLoading: Bool { !hasCatalog && (library.isLoading || !startedLoading) }
    /// Nothing cached and no load running, without a failure to show: offline, or the reads are held back for a retry.
    var isOffline: Bool { !hasCatalog && !isLoading && library.error == nil }
    var error: String? { library.error }
    var errorDetails: String? { library.errorDetails }

    /// Only the first visit loads; pull to refresh reloads.
    func loadIfNeeded() async {
        startedLoading = true
        if library.catalog == nil { await library.refresh() }
    }
    func refresh() async {
        startedLoading = true
        await library.refresh()
    }

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
    /// The last load came back without the plan (not cached, and the platform failed).
    private(set) var loadFailed = false

    init(planID: UUID, library: TrainLibrary) {
        self.planID = planID
        self.library = library
    }

    /// Active or paused: this plan is the one the user is on.
    var isCurrent: Bool { (library.activeEnrollment?.planId ?? library.pausedPlanID) == planID }
    var isPaused: Bool { library.isPaused }
    /// The enrolment's week on this plan, when it is the active one ("Active · week 6").
    var activeWeek: Int? { isCurrent && !isPaused ? library.activeEnrollment?.currentWeek : nil }
    /// The header's title before the detail has loaded: the name from the plans overview.
    var name: String? { plan?.name ?? library.catalog?.summary(id: planID)?.name }
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

    /// The failure to show instead of the outlines: the plan couldn't be loaded and nothing is cached.
    var failure: String? { plan == nil && loadFailed ? library.error : nil }

    func load() async {
        loadFailed = false
        let loaded = await library.loadPlan(id: planID)
        if loaded != nil || plan == nil { plan = loaded }
        loadFailed = plan == nil && !Task.isCancelled
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
        // Unlinking A from B in A→B→C leaves C alone in the group: a lonely superset isn't one.
        renumber(dayID: dayID)
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

    /// The platform's limit for an exercise's name: 80 Unicode scalars. It counts runes and refuses a longer name (422), so
    /// the count is `unicodeScalars`, not Characters (a family emoji is one Character and 7 scalars).
    static let maxNameLength = ImportCustomExercise.maxNameLength

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Longer than the platform takes: Save stays off and the form says why.
    var nameIsTooLong: Bool { trimmedName.unicodeScalars.count > Self.maxNameLength }
    var canSave: Bool { !trimmedName.isEmpty && !nameIsTooLong && muscle != nil }

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
