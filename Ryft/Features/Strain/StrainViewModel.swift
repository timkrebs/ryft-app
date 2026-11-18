import Foundation
import Observation

/// Strain for the selected day (Nocturne, design.md §P5-3): the week strip, the board (numeral, ruler, zones, tiles) with
/// its 7-day comparison, and the day's activities (workouts merged with logged sessions, or My Day's rows behind
/// `today.my_day`). "Today" comes from the environment's clock. What the screen shows is decided here and in `StrainBoard`,
/// so the view only lays it out.
@MainActor
@Observable
final class StrainViewModel {
    private let state: AppState
    private let store: TrainStore

    var date: Date
    /// A deep link's Train screen; the view pushes it and clears it.
    var requestedRoute: TrainRoute?
    private(set) var isLoading = false
    /// The shown day couldn't load and nothing is cached: the app's calm sentence, its Details and its button (never the
    /// system's error text, R3-N3). Another day's failure is not shown.
    var failure: SleepLoadFailure? { failed?.day == date ? failed?.failure : nil }
    private var failed: (day: Date, failure: SleepLoadFailure)?
    /// The failure's sentence, nil without one.
    var error: String? { failure?.message }
    /// The day whose load finished (with or without data): before it, an uncached day shows its outlines, not "no strain".
    private var loadedDay: Date?
    /// Counts `load()` calls. SwiftUI starts the next `.task(id:)` before the cancelled one has finished, so a load writes
    /// `isLoading`, `failed` and `loadedDay` only while it is the latest: an older day's late answer changes nothing.
    private var generation = 0
    /// A strip tap changed the day: once it has loaded, VoiceOver hears the new day (`takeStepAnnouncement`).
    private var announcesStep = false

    /// One day of the week strip (`DateStrip`, shared with My Day).
    typealias StripDay = DateStrip.Day

    init(state: AppState, store: TrainStore) {
        self.state = state
        self.store = store
        date = Calendar.current.startOfDay(for: state.env.clock.now())
    }

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: state.env.clock.now()) }
    /// The strip's first day: today and the six before it.
    private var oldestDay: Date { DayFormat.shift(today, days: -(DateStrip.length - 1)) }

    /// The selected day as cached (SwiftData); `load()` revalidates it.
    var detail: DayDetail? { state.cachedDayDetail(for: date) }

    var isToday: Bool { calendar.isDate(date, inSameDayAs: today) }
    /// Strength training behind `train.enabled`.
    var showsTrain: Bool { state.env.flags.isOn(.trainEnabled) }
    /// The Train section: today only (§P5-3.7 "Another day").
    var showsTrainSection: Bool { isToday && showsTrain }
    /// "Today", "Yesterday", "Mon, 16 Nov": the header's spoken day and the step announcement.
    var title: String { Fmt.dayTitle(date, today: today) }
    var hasNoHealthData: Bool { state.hasNoHealthData }
    var isDemo: Bool { state.isDemo }
    /// The hero numeral's style (Profile's "Hero numbers": Dots or Thin).
    var numeralStyle: DotNumeral.Style { state.env.settings.heroNumerals.style }

    private var score: DailyScore? { detail?.score ?? state.score(for: date) }
    var strain: Double? { score?.strain }

    /// The strains of the seven days before the selected one, those that are cached.
    private var priorStrains: [Double] {
        (1...7).compactMap { state.score(for: DayFormat.shift(date, days: -$0))?.strain }
    }

    /// Against the mean of the seven days before the selected one; only with 3 or more of them (D5-4).
    var strainDelta: MetricDelta? { StrainHero.delta(strain, prior: priorStrains) }

    var week: [StripDay] {
        DateStrip.week(endingAt: today, selected: date) { state.score(for: $0) }
    }

    /// "Cardio 9.2 · Strength 4.1": the day's strain split in proportion to the
    /// heart-rate TRIMP and the strength sessions' muscular TRIMP (the platform
    /// compresses their sum into one strain, so the split is by load). Nil
    /// without a strength session.
    var strainSplit: (cardio: Double, strength: Double)? {
        guard let strain, let d = detail?.strain, let muscular = d.muscularTrimp, muscular > 0 else { return nil }
        let total = Double(d.trimp + muscular)
        guard total > 0 else { return nil }
        let strength = (strain * Double(muscular) / total * 10).rounded() / 10
        // The two parts add up to the shown strain (one decimal).
        return (((strain - strength) * 10).rounded() / 10, strength)
    }

    var strainSplitText: String? {
        strainSplit.map {
            String(localized: "Cardio \(Fmt.strain($0.cardio)) · Strength \(Fmt.strain($0.strength))")
        }
    }

    /// Nothing cached for the day and its load hasn't answered yet (running, or not started: the first frame).
    private var awaitsDay: Bool {
        detail == nil && state.hasDataSource && (isLoading || loadedDay != date)
    }

    /// The day's scoring state. Today's is Today's and Sleep's (`ScoringWord.state`: this phone's word since its last
    /// write or push, then `GET /v1/me/sync`'s, then the row); another day's is its row's. Read in the board, so a new
    /// word or status redraws it.
    var scoringState: ScoringState? {
        guard isToday else { return score?.scoringState }
        let key = DayFormat.string(from: date)
        return ScoringWord.state(day: key, word: state.repository.scoringLedger()[key], status: state.syncStatus?.today,
                                 row: score)
    }

    /// The board for the selected day (§P5-3.1, §P5-3.7).
    var board: StrainBoard {
        StrainBoard(detail: detail, score: score, prior: priorStrains, split: strainSplitText, isLoading: awaitsDay,
                    failure: failure, scoring: StrainBoard.DayScoring(scoringState, isToday: isToday))
    }

    /// The refresh card or the one-line status under the strip (§P5-3.7).
    var status: StrainStatus? {
        StrainStatus.decide(issue: state.refreshIssue, isOnline: state.env.connectivity.isOnline, isDemo: state.isDemo,
                            hasDataSource: state.hasDataSource, hasCachedDay: detail != nil, staleSince: state.staleSince)
    }

    // MARK: the list

    /// The list is My Day's rows without the night (`today.my_day`, ADR 0006): RYFT's activities show too.
    var showsMyDayList: Bool { state.env.flags.isOn(.todayMyDay) }
    /// The tracker catalog was parsed off the main actor (`load`): until then the list shows HealthKit's source
    /// names (as `MyDayViewModel.namesTrackers`).
    private(set) var namesTrackers = false

    /// The day's rows as My Day builds them, without the sleep rows (behind `today.my_day`).
    var dayItems: [MyDayItem] {
        let input = MyDayInput.cached(day: date, state: state, store: store, includingSleep: false)
        return MyDayAssembler.items(input, catalog: input.catalog(state.env, ready: namesTrackers),
                                    now: state.env.clock.now(), includingSleep: false)
    }

    /// The workout behind one of `dayItems`.
    func workout(_ id: UUID) -> Workout? { detail?.workouts.first { $0.id == id } }

    /// The day's workouts, each merged with its logged session (`session_id`),
    /// then sessions without a workout yet (e.g. still syncing). The list without `today.my_day`.
    var activities: [ActivityItem] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let local = store.completedSessions(from: start, to: end).map(\.summary)
        let sessions = TrainLibrary.merged(local: local, remote: detail?.strain?.sessions ?? [])
        var linked = Set<UUID>()
        var items: [ActivityItem] = (detail?.workouts ?? []).map { w in
            let s = sessions.first { $0.id == w.sessionId || $0.workoutId == w.id }
            if let s { linked.insert(s.id) }
            return .workout(w, s)
        }
        items += sessions.filter { !linked.contains($0.id) }.map(ActivityItem.session)
        return items.sorted { $0.start < $1.start }
    }

    /// The rows Strain shows (§P5-3.6): My Day's behind `today.my_day`, else the workouts merged with their sessions; one
    /// row look for every kind.
    func rows(locale: Locale = .autoupdatingCurrent) -> [StrainRow] {
        if showsMyDayList {
            let day = date
            return dayItems.compactMap { item in
                StrainRow(item, day: day, workout: { [self] in workout($0) }, locale: locale)
            }
        }
        return activities.map { StrainRow($0, locale: locale) }
    }

    // MARK: selection

    /// A deep link's day: shows it, never past today; an older day than the strip's opens too (no strip cell is selected,
    /// the date line under the header names it). Announced once it has loaded.
    func select(_ day: Date) {
        show(min(calendar.startOfDay(for: day), today))
    }

    /// A strip tap: the day, kept within the strip's week (today and the six days before); announced once it has loaded.
    func step(to day: Date) {
        show(min(max(calendar.startOfDay(for: day), oldestDay), today))
    }

    private func show(_ day: Date) {
        guard day != date else { return }
        date = day
        announcesStep = true
    }

    /// Under the header on another day than today: "Mon 16 Nov" (the header's title stays "Strain"); nil today.
    var dateLine: String? { StrainPageContent.dateLine(date, today: today, calendar: calendar) }

    /// "Yesterday. Strain 9.8 of 21"; "Mon, 16 Nov. No strain recorded for this day."
    var stepAnnouncement: String {
        let board = board
        if let failure = board.failure { return "\(title). \(failure.message)" }
        return "\(title). \(board.hero.numeralLabel ?? board.hero.caption)"
    }

    /// The announcement a strip tap asked for, once; nil otherwise.
    func takeStepAnnouncement() -> String? {
        guard announcesStep else { return nil }
        announcesStep = false
        return stepAnnouncement
    }

    // MARK: loading

    private func refreshActivities() async {
        guard showsMyDayList else { return }
        _ = try? await state.repository.refreshActivities(DayFormat.string(from: date))
    }

    /// My Day's list has workouts to name: the catalog's first parse off the main actor, then names by it.
    private func nameTrackers() async {
        guard showsMyDayList, !namesTrackers, detail?.workouts.isEmpty == false else { return }
        _ = await TrackerCatalog.loadBundled()
        namesTrackers = true
    }

    /// Revalidates the selected day (no request when it's cached and fresh).
    func load() async {
        generation += 1
        let mine = generation
        failed = nil
        loadedDay = nil
        guard state.hasDataSource else {
            // Signed out meanwhile: an earlier load that is still out no longer ends the loading.
            isLoading = false
            return
        }
        let day = date
        isLoading = detail == nil
        defer { if mine == generation { isLoading = false } }
        // My Day's list needs the day's activities as well, side by side (cached and fresh: nothing is sent).
        async let activities: Void = refreshActivities()
        do {
            _ = try await state.dayDetail(for: day)
            await activities
            await nameTrackers()
            guard mine == generation else { return }
            loadedDay = day
        } catch where error.isCancellation {
            // `.task(id:)` restarted (another day, new data): the next load says what's true.
            return
        } catch {
            guard mine == generation else { return }
            loadedDay = day
            if state.cachedDayDetail(for: day) == nil {
                failed = (day, SleepLoadFailure(error, isOnline: state.isDemo || state.env.connectivity.isOnline,
                                                isDemo: state.isDemo, at: state.env.clock.now()))
            }
        }
    }

    /// A signed-out failure's "Sign in": Today's (`AppState.signInAgain`).
    func signIn() async {
        await state.signInAgain()
    }
}

/// What Strain says about the data's freshness, under the header (§P5-3.7): Today's refresh card when a refresh needs the
/// user (signed out, an outdated app, failures with old data), else a one-line status while the day's cache is shown
/// offline or stale.
enum StrainStatus: Equatable {
    case issue(RefreshIssue)
    case line(SyncLine)

    static func decide(issue: RefreshIssue?, isOnline: Bool, isDemo: Bool, hasDataSource: Bool, hasCachedDay: Bool,
                       staleSince: Date?) -> StrainStatus? {
        if let issue { return .issue(issue) }
        guard hasDataSource, !isDemo else { return nil }
        // Offline with nothing cached is the board's own failure sentence; with the day cached, the line says why it
        // doesn't change.
        if !isOnline { return hasCachedDay ? .line(.offline) : nil }
        return staleSince.map { .line(.stale(since: $0)) }
    }
}

/// One row of Strain's list: what it says, where it goes and how UI tests find it.
struct StrainRow: Identifiable, Equatable {
    enum Destination: Equatable {
        case workout(Workout)
        case session(UUID)
        case activity(ActivityRoute)
        /// A My Day item without a detail of its own: the same row, not a link.
        case none
    }

    /// "workout.<uuid>", "session.<uuid>", "activity.<uuid>": the same in both list modes.
    let id: String
    let content: ActivityListRow.Content
    let destination: Destination

    /// `strain.row.workout.<uuid>`.
    var identifier: String { "strain.row.\(id)" }

    /// What the row opens, for VoiceOver; nil when it opens nothing.
    var hint: String? {
        switch destination {
        case .workout: return String(localized: "Opens the workout", comment: "VoiceOver hint: the row opens the workout's detail.")
        case .session: return String(localized: "Opens the session", comment: "VoiceOver: a My Day row opens the Train session.")
        case .activity: return String(localized: "Opens the activity", comment: "VoiceOver hint: a My Day row opens the activity's detail.")
        case .none: return nil
        }
    }

    /// The list without `today.my_day`.
    init(_ item: ActivityItem, locale: Locale) {
        switch item {
        case .workout(let w, let session):
            id = "workout.\(w.id.uuidString)"
            content = StrainRows.workout(w, session: session, locale: locale)
            destination = .workout(w)
        case .session(let s):
            id = "session.\(s.id.uuidString)"
            content = StrainRows.session(s, locale: locale)
            destination = .session(s.id)
        }
    }

    /// A My Day row; nil for a workout the day no longer holds (and for the night, which Strain doesn't list).
    init?(_ item: MyDayItem, day: Date, workout: (UUID) -> Workout?, locale: Locale) {
        switch item.kind {
        case .workout(let wid):
            guard let w = workout(wid) else { return nil }
            destination = .workout(w)
        case .session(let sid):
            destination = .session(sid)
        case .activity(let aid):
            destination = item.opensDetail ? .activity(ActivityRoute(id: aid, day: day)) : .none
        case .sleep, .missingSleep:
            return nil
        }
        id = item.id
        content = StrainRows.myDay(item, locale: locale)
    }
}
