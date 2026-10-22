import Foundation
import Observation

/// The morning briefing: greeting and state sentence, readiness against the days
/// before, the three tiles, the 7-day trend and one status line. While data is on its
/// way the gauge's place goes to what's true right now (`TodayStates`): the first
/// import, a night being scored, the baseline being learned.
@MainActor
@Observable
final class TodayViewModel {
    private let state: AppState
    private let sync: SyncService
    private let coordinator: SyncCoordinator
    private let apiStatus: APIStatus
    private let push: PushRegistrar?
    private let onboarding: OnboardingCoordinator?

    /// The one message under the cards, in priority order.
    enum Status: Equatable {
        /// Something only the user can do: agree to the policy, enter the invite code.
        case actionNeeded(OnboardingCoordinator.Step, message: String, action: String)
        /// The platform asked to wait (503 / 429), and the app is retrying.
        case retrying(String)
        /// A read kept failing past its threshold, or one the user can act on (`RefreshPolicy`).
        case refreshIssue(RefreshIssue)
        /// HealthKit couldn't be uploaded; the screens still show the platform's data.
        case syncPaused(message: String, details: String?)
    }

    /// First-run coach marks: gauge → physiology → trends.
    let coachMarks: CoachMarks

    /// Last night as Apple Health has it, and the newest record per source (`loadHealthFacts`).
    private(set) var lastNightRaw: RawNight?
    private(set) var freshness: [SourceFreshness] = []

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator, push: PushRegistrar? = nil,
         onboarding: OnboardingCoordinator? = nil, apiStatus: APIStatus? = nil) {
        coachMarks = CoachMarks(defaults: state.env.defaults)
        self.state = state
        self.sync = sync
        self.coordinator = coordinator
        self.push = push
        self.onboarding = onboarding
        self.apiStatus = apiStatus ?? .shared
    }

    private var env: AppEnvironment { state.env }
    /// Today's row, any standing (a demo scenario's in demo mode).
    private var score: DailyScore? { facts.today }

    var hasDataSource: Bool { state.hasDataSource }
    var greeting: String { ReadinessCopy.greeting(at: env.clock.now()) }
    /// Says what the gauge shows, about the same day (ui.md §1.5).
    var sentence: String { content.sentence }
    var isOffline: Bool { !env.connectivity.isOnline }
    var showsHealthHint: Bool { state.hasNoHealthData }

    /// The gauge's number: the readiness of the day it shows (rows A and D), else nil.
    var readiness: Double? { content.readiness }

    /// Only once there's a score to point at.
    var showsCoachMarks: Bool {
        hasDataSource && score.map { $0.standing != .unscored } == true && coachMarks.step != nil
    }
    var readinessWeek: [TrendPoint] { state.readinessWeek?.points ?? [] }
    /// Only for today's settled score (row A): a calibrating or borrowed number has no fair comparison.
    var readinessDelta: MetricDelta? { content.readinessDelta }
    /// "Recalculating your baselines" (row D) or why the baselines can't fill (row B), under the gauge.
    var gaugeNote: TodayPresentation.Note? { content.gaugeNote }
    /// What VoiceOver adds to the readiness gauge's value: the note, and the day when it isn't today.
    var gaugeSpokenNote: String? { content.gaugeSpokenNote }

    // MARK: tiles: one day for all three (ui.md §1)

    /// Hidden while nothing was ever scored (row E), like during the first import.
    var showsTiles: Bool { content.showsTiles }
    var sleepText: String { content.sleepText }
    var recovery: Int? { content.recovery }
    var recoveryText: String { content.recoveryText }
    /// The band word: only for today's score, not for a dimmed or calibrating one.
    var recoveryBand: String? { content.recoveryBand }
    var strainText: String { content.strainText }
    /// Not today's values (the night is being scored, or row D from an earlier day): dimmed and dated.
    var tilesDimmed: Bool { content.tilesDimmed }
    /// Under every tile: the shown day ("Yesterday", "Tue 20 Oct") while dimmed, "calibrating" in row B.
    var tileCaption: String? { content.tileCaption }
    /// Recovery's caption: the day or "calibrating" when there is one, else the band word.
    var recoveryCaption: String? { content.recoveryCaption }

    var status: Status? {
        if let step = gate { return Self.actionNeeded(step) }
        if let notice = apiStatus.retryNotice { return .retrying(notice) }
        if let issue = state.refreshIssue { return .refreshIssue(issue) }
        if !state.isDemo, let syncError = sync.lastError, env.settings.isConfigured {
            return .syncPaused(message: String(localized: "Health sync paused: \(syncError)"),
                               details: sync.lastErrorDetails)
        }
        return nil
    }

    /// The calm error card is on screen: the status line then points to it instead of offering its
    /// own "Try again".
    var showsRefreshIssue: Bool { refreshIssueResource != nil }

    /// The resource the card is about, while it's on screen.
    var refreshIssueResource: ReadResource? {
        if case .refreshIssue(let issue) = status { return issue.resource }
        return nil
    }

    /// Bumped when the line's "Couldn't load today · Details" is tapped: Today scrolls to the card.
    private(set) var scrollToIssue = 0

    /// Sync details as a sheet from Today (the status line's tap).
    var showsSyncDetails = false

    /// The signed-out card's action: back to Welcome to sign in again.
    func signIn() async {
        await env.auth.signOut(reason: .sessionExpired)
    }

    /// With onboarding, its facts decide (a sync paused only until the account is known
    /// isn't the user's to fix); without it, a sync the platform refused at a gate.
    private var gate: OnboardingCoordinator.Step? {
        onboarding.map { $0.pendingGate } ?? sync.pausedFor.map(Self.step(for:))
    }

    var lastUpdated: Date? { state.lastUpdated }
    var isRefreshing: Bool { state.isLoading || sync.isSyncing }
    var isDemo: Bool { state.isDemo }
    var scoredAt: Date? { score?.computedAt }

    // MARK: in-between states

    /// What the states below are decided from: live, or a demo scenario's (`-RyftScenario`).
    var facts: TodaySyncFacts {
        let now = env.clock.now()
        let todayKey = DayFormat.string(from: now)
        let history = state.history
        var f = TodaySyncFacts(now: now)
        f.engine = sync.engineState
        f.phase = sync.phase
        f.activity = sync.activity
        f.waitingForUnlock = sync.waitingForUnlock
        f.online = env.connectivity.isOnline
        f.gate = gate
        f.syncFailed = !state.isDemo && sync.lastError != nil && env.settings.isConfigured
        f.isLoading = state.isLoading
        f.isDemo = state.isDemo
        f.syncs = !state.isDemo && env.auth.isSignedIn && env.settings.isConfigured && env.health.isAvailable
        f.status = state.syncStatus
        // Detail score, else the history list's: the same reads as the widget (`Repository.widgetFacts`).
        f.today = state.repository.score(todayKey)
        f.prior = history.filter { $0.day < todayKey }
        f.hasScoredDay = (history + [f.today].compactMap { $0 }).contains(where: TodayStates.isScored)
        f.lastUpdated = state.lastUpdated
        f.expectedScoringSec = sync.lastScoring?.expectedWithinSec
        f.lastNight = lastNightRaw
        f.freshness = freshness
        if let scenario = state.todayScenario { f = scenario.apply(to: f) }
        return f
    }

    var hero: TodayHero { TodayStates.hero(facts) }
    /// Gauge, tiles and note, decided once from the same facts (`TodayPresentation.decide`).
    var presentation: TodayPresentation { TodayPresentation.decide(facts.scores) }
    /// Everything Today shows about the day from one `facts` build and one `decide`: `TodayView`
    /// takes it once per body (each accessor above builds both again).
    var content: TodayContent {
        let f = facts
        let p = TodayPresentation.decide(f.scores)
        return TodayContent(facts: f, presentation: p, hero: TodayStates.hero(f, presentation: p),
                            hasDataSource: hasDataSource, readinessWeek: readinessWeek,
                            detailSleepMin: state.today?.sleep?.totalMin)
    }
    /// The import's slim row under the header, once a day is scored and the backfill goes on.
    var importRow: ImportProgress? { TodayStates.importRow(facts) }
    var syncLine: SyncLine {
        var signedOut = false
        if case .refreshIssue(let issue) = status { signedOut = issue.reason == .signedOut }
        return TodayStates.line(facts, staleSince: state.staleSince, card: refreshIssueResource, signedOut: signedOut)
    }
    var watchHint: WatchSyncHint? { TodayStates.watchHint(facts) }
    /// Last night from Apple Health beside the pending gauge (raw totals, not a score); not while
    /// waiting for sleep, when no night has arrived.
    var rawNight: RawNight? { content.rawNight }

    /// Reloads `lastNightRaw` and `freshness` when a sync ends or the day is fetched again.
    var healthFactsKey: Date? { sync.engineState.updatedAt ?? state.lastUpdated }

    /// Last night from Apple Health and the newest record per source: HealthKit only (cheap
    /// queries), off the main actor. Locked phone or no access: nothing, quietly.
    func loadHealthFacts() async {
        guard !state.isDemo, env.auth.isSignedIn, env.health.isAvailable else { return }
        let health = env.health
        let now = env.clock.now()
        lastNightRaw = try? await health.lastNight(before: now)
        freshness = (try? await health.newestRecords(since: now.addingTimeInterval(-TodayStates.freshnessWindow))) ?? []
    }

    /// The status line's tap: the gate's screen, else Sync details (nothing while waiting for the unlock).
    func resolveLine() {
        switch syncLine {
        case .actionNeeded(let step): resolve(step)
        case .waitingForUnlock: break
        case .issue: scrollToIssue += 1
        default: showsSyncDetails = true
        }
    }

    /// Try again (the line and the card), like pull to refresh: the upload starts, today and the sync
    /// status load at once, the rest after the upload (`AppState.pullToRefresh`).
    func refresh() async {
        await state.pullToRefresh(coordinator: coordinator)
    }

    func open(_ tab: AppTab) { state.selectedTab = tab }

    /// "Review" / "Enter code": the gate's screen, again.
    func resolve(_ step: OnboardingCoordinator.Step) { onboarding?.show(step) }

    private static func step(for gate: APIErrorCode) -> OnboardingCoordinator.Step {
        gate == .inviteRequired ? .invite : .consent
    }

    private static func actionNeeded(_ step: OnboardingCoordinator.Step) -> Status {
        switch step {
        case .invite:
            return .actionNeeded(.invite, message: String(localized: "Action needed: enter your invite code to use RYFT."),
                                 action: String(localized: "Enter code"))
        case .consent, .aboutYou:
            return .actionNeeded(.consent,
                                 message: String(localized: "Action needed: agree to the privacy policy. Nothing syncs until you do."),
                                 action: String(localized: "Review"))
        }
    }

    // MARK: feature flags

    var showsTrain: Bool { env.flags.isOn(.trainEnabled) }

    /// The redesigned Today, shipped dark behind `today.redesign`: last night's
    /// hypnogram under the tiles.
    var showsRedesign: Bool { env.flags.isOn(.todayRedesign) }
    var lastNight: SleepDetail? { state.today?.sleep }

    // TODO(physiology.card): reserved by the platform; read in Debug → Feature flags, no card yet.

    // MARK: push pre-prompt

    /// After the first sync, before iOS asked; never on top of the coach marks.
    var showsPushPrompt: Bool { (push?.showsPrePrompt ?? false) && !showsCoachMarks }
    /// The import card's question: "Tell me when my first scores are ready".
    var showsImportPushPrompt: Bool {
        if state.todayScenario == .importing { return true }
        return push?.showsImportPrompt ?? false
    }

    func enablePush() async { await push?.accept() }
    func dismissPushPrompt() { push?.dismissPrompt() }
}

/// What Today shows about the day, from one read of its facts and one decision. A value: `TodayView`
/// takes it once per body and its sections read from it.
struct TodayContent {
    let facts: TodaySyncFacts
    let presentation: TodayPresentation
    let hero: TodayHero
    let hasDataSource: Bool
    /// The 7-day readiness trend, for row A's delta and the Trends card.
    let readinessWeek: [TrendPoint]
    /// Today's opened night, for a row from before `sleep_actual_min`.
    let detailSleepMin: Int?

    private var tiles: TodayPresentation.Tiles { presentation.tiles }

    /// Says what the gauge shows, about the same day (ui.md §1.5).
    var sentence: String {
        guard hasDataSource else { return String(localized: "Let's get you set up.") }
        if hero.isImporting { return String(localized: "Your history is on its way.") }
        let p = presentation
        switch p.gauge {
        case .pending(let night):
            if night.waitingForSleep { return String(localized: "Last night hasn't reached RYFT yet.") }
            // The gauge and the line say it's scoring; this says what the dimmed number is, and from which day.
            guard night.previousReadiness != nil else { return String(localized: "Your night is being scored.") }
            if let day = night.previousDay,
               !Calendar.current.isDate(day, inSameDayAs: DayFormat.shift(facts.now, days: -1)) {
                // A gap day before last night (a night without the watch): its date, as the gauge and tiles have it.
                let date = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                return String(localized: "Readiness from \(date), until last night is scored.")
            }
            return String(localized: "Yesterday's readiness, until last night is scored.")
        case .baselines:
            return String(localized: "Your baselines are still forming.")
        case .readiness where p.note == .needsVitals:
            // The platform's readiness while its baselines can't fill; the note under the gauge says why.
            return String(localized: "Your baselines are still forming.")
        case .readiness where p.row == .recalculating:
            guard p.tiles.isEarlierDay, let day = p.tiles.source?.date else {
                return String(localized: "Your baselines are being recalculated.")
            }
            // A date, never "Yesterday": the sentence reads "Readiness from Tue 20 Oct, …" in both languages.
            let date = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return String(localized: "Readiness from \(date), while your baselines are recalculated.")
        case .readiness, .firstImport:
            return ReadinessCopy.sentence(score: facts.today)
        }
    }

    /// The gauge's number: the readiness of the day it shows, else nil.
    var readiness: Double? {
        guard case .readiness(let value) = presentation.gauge else { return nil }
        return value.map(Double.init)
    }

    /// Only for today's settled score (row A): a calibrating or borrowed number has no fair comparison.
    var readinessDelta: MetricDelta? { presentation.showsDelta ? .vsSevenDayMean(readinessWeek) : nil }

    /// "Recalculating your baselines" (row D) or why the baselines can't fill (row B), under the gauge.
    var gaugeNote: TodayPresentation.Note? { hero.isImporting ? nil : presentation.note }

    /// What VoiceOver adds to the readiness gauge's value (rows D and B with a readiness): the note, and the
    /// day when it isn't today. Under the baselines gauge the note is read on its own.
    var gaugeSpokenNote: String? {
        let p = presentation
        guard case .readiness = p.gauge, let note = gaugeNote else { return nil }
        guard p.tiles.isEarlierDay, let day = p.tiles.source?.date else { return note.text }
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return note.text + ". " + String(localized: "From \(date)")
    }

    /// Hidden while nothing was ever scored (row E), like during the first import.
    var showsTiles: Bool { !hero.isImporting && presentation.row != .firstImport }
    var sleepText: String {
        guard let day = tiles.source else { return Fmt.placeholder }
        // Today's detail has the night when the row predates `sleep_actual_min`; an earlier day stands alone.
        return Fmt.duration(minutes: day.sleepActualMin ?? (tiles.isEarlierDay ? nil : detailSleepMin))
    }
    var recovery: Int? { tiles.source?.recovery }
    var recoveryText: String { Fmt.percent(recovery) }
    /// The band word: only for today's score, not for a dimmed or calibrating one.
    var recoveryBand: String? {
        guard !tiles.isEarlierDay, !tiles.calibrating else { return nil }
        return recovery.map { MetricSpec.scoreBand(Double($0)).label }
    }
    var strainText: String { Fmt.strain(tiles.source?.strain) }
    /// Not today's values (the night is being scored, or row D from an earlier day): dimmed and dated.
    var tilesDimmed: Bool { tiles.source != nil && tiles.isEarlierDay }
    /// Under every tile: the shown day ("Yesterday", "Tue 20 Oct") while dimmed, "calibrating" in row B.
    var tileCaption: String? {
        guard let day = tiles.source else { return nil }
        if tiles.isEarlierDay { return Fmt.dayTitle(day.date, today: facts.now) }
        if tiles.calibrating {
            return String(localized: "today.tile.calibrating", defaultValue: "calibrating",
                          comment: "Under each of Today's tiles while the baselines fill (still calibrating, not done).")
        }
        return nil
    }
    /// Recovery's caption: the day or "calibrating" when there is one, else the band word.
    var recoveryCaption: String? { tileCaption ?? recoveryBand }

    /// Last night from Apple Health beside the pending gauge (raw totals, not a score); not while
    /// waiting for sleep, when no night has arrived.
    var rawNight: RawNight? {
        guard case .pending = hero else { return nil }
        return presentation.rawNight
    }
    /// The import's slim row under the header, once a day is scored and the backfill goes on.
    var importRow: ImportProgress? { TodayStates.importRow(facts) }
    var watchHint: WatchSyncHint? { TodayStates.watchHint(facts) }
}

// MARK: - in-between states (what's true while data is on its way)

/// What Today's in-between states are decided from: the sync engine, the platform's
/// `GET /v1/me/sync`, the cache and Apple Health. Live it's gathered by
/// `TodayViewModel.facts`; tests and demo scenarios build it directly.
struct TodaySyncFacts: Equatable {
    var now: Date
    var engine = SyncEngineState()
    var phase: SyncPhase = .idle
    var activity: SyncActivity?
    var waitingForUnlock = false
    var online = true
    /// The gate the account is behind (onboarding's word, or a refused upload's).
    var gate: OnboardingCoordinator.Step?
    var syncFailed = false
    var isLoading = false
    var isDemo = false
    /// A signed-in account on a configured platform with Apple Health: its data syncs.
    var syncs = true
    var status: SyncStatus?
    var today: DailyScore?
    /// The cached days before today, oldest first (`AppState.history`), any standing:
    /// `TodayPresentation.decide` filters them.
    var prior: [DailyScore] = []
    /// Some day was scored already (the first import is over for the gauge).
    var hasScoredDay = false
    var lastUpdated: Date?
    /// The last upload's `scoring.expected_within_sec`, until `GET /v1/me/sync` says.
    var expectedScoringSec: Int?
    var lastNight: RawNight?
    var freshness: [SourceFreshness] = []

    /// What the day's numbers are decided from (`TodayPresentation.decide`).
    var scores: TodayScoreFacts {
        TodayScoreFacts(day: DayFormat.string(from: now), today: today, scoringState: TodayStates.todayState(self),
                        prior: prior, expectedWithinSec: status?.expectedWithinSec ?? expectedScoringSec,
                        lastNight: lastNight)
    }
}

/// What takes the readiness gauge's place.
enum TodayHero: Equatable {
    /// The first import, before any day was scored: the "Setting up RYFT" card.
    case importing(ImportProgress)
    /// Today's night isn't scored yet: the gauge in outline, with the day before dimmed.
    case pending(PendingNight)
    /// Fewer than 7 nights behind the baselines: a ring segment per night.
    case calibrating(nights: Int)
    case score
}

/// The first import, in real counts: no percent it can't back.
struct ImportProgress: Equatable {
    enum Step: Int, CaseIterable, Comparable {
        case reading, uploading, scoring

        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .reading: return String(localized: "Reading Apple Health")
            case .uploading: return String(localized: "Uploading")
            case .scoring: return String(localized: "Scoring")
            }
        }
    }

    var step: Step
    /// Nights of sleep sent (by their wake day).
    var nights = 0
    var heartRateReadings = 0
    var workouts = 0
    /// Days of the window with any record sent, and the oldest of them.
    var coveredDays = 0
    var oldestDay: Date?

    /// `AppState.historyDays`: the 90 days the backfill reads.
    static let windowDays = 90

    /// "Imported through 14 Sep · 61 of 90 days".
    var coverageText: String {
        guard let oldestDay, coveredDays > 0 else { return String(localized: "Starting with your last few days") }
        let day = oldestDay.formatted(.dateTime.day().month(.abbreviated))
        return String(localized: "Imported through \(day) · \(coveredDays) of \(Self.windowDays) days")
    }

    var fraction: Double { min(1, Double(coveredDays) / Double(Self.windowDays)) }
}

/// The night that isn't scored yet.
struct PendingNight: Equatable, Sendable {
    /// `waiting_for_sleep`: no night has arrived; otherwise it's being scored.
    var waitingForSleep: Bool
    /// When to expect it (`expected_within_sec`), while scoring.
    var expectedWithinSec: Int?
    /// The latest readiness before today, dimmed in the gauge, and its day.
    var previousReadiness: Double?
    var previousDay: Date?

    var title: String {
        waitingForSleep ? String(localized: "Waiting for last night's sleep") : String(localized: "Scoring your night…")
    }

    var detail: String {
        if waitingForSleep { return String(localized: "It's scored as soon as Apple Health has it.") }
        guard let seconds = expectedWithinSec, seconds > 0 else { return String(localized: "Usually ready within a minute.") }
        if seconds < 90 { return String(localized: "Usually ready within \(seconds) s.") }
        return String(localized: "Usually ready within \((seconds + 59) / 60) min.")
    }
}

/// The one line under the greeting: what the sync is doing, in a few words.
enum SyncLine: Equatable {
    case actionNeeded(OnboardingCoordinator.Step)
    case offline
    case waitingForUnlock
    case reading(HealthStream)
    case uploading(records: Int)
    /// Waiting for the platform: last night (`night`) or newer data.
    case scoring(night: Bool)
    case updating
    /// Idle, and what's on screen is older than its threshold after a refresh that didn't succeed
    /// (`RefreshPolicy.staleSince`): "Showing data from 14:05 · Try again".
    case stale(since: Date)
    /// The error card is on screen, last on Today: "Couldn't load today · Details" points to it
    /// (tapping scrolls there); "You're signed out · Details" when that's the card's reason.
    case issue(ReadResource, signedOut: Bool = false)
    /// The upload failed; the message under the cards says why.
    case paused
    case upToDate(Date?, demo: Bool)

    var systemImage: String {
        switch self {
        case .actionNeeded: return "hand.raised"
        case .offline: return "wifi.slash"
        case .waitingForUnlock: return "lock"
        case .reading: return "heart.text.square"
        case .uploading: return "arrow.up.circle"
        case .scoring: return "waveform.path.ecg"
        case .updating: return "arrow.triangle.2.circlepath"
        case .stale: return "clock"
        case .issue: return "exclamationmark.circle"
        case .paused: return "exclamationmark.circle"
        case .upToDate: return "checkmark.circle"
        }
    }

    /// Something happening right now (the icon pulses unless motion is reduced).
    var isActive: Bool {
        switch self {
        case .reading, .uploading, .scoring, .updating: return true
        default: return false
        }
    }

    func text(now: Date) -> String {
        switch self {
        case .actionNeeded(.invite): return String(localized: "Action needed: enter your invite code")
        case .actionNeeded: return String(localized: "Action needed: agree to the privacy policy")
        case .offline: return String(localized: "Offline — will sync when back")
        case .waitingForUnlock: return String(localized: "Waiting for you to unlock your iPhone")
        case .reading(let stream): return SyncActivity.reading(stream).text
        case .uploading(let records): return String(localized: "Uploading \(records.formatted()) readings")
        case .scoring(night: true): return String(localized: "Scoring your night")
        case .scoring(night: false): return String(localized: "Scoring your latest data")
        case .updating: return String(localized: "Updating…")
        case .stale(let since): return String(localized: "Showing data from \(Self.dataTime(since, now: now))")
        case .issue(_, signedOut: true): return String(localized: "You're signed out · Details")
        case .issue(.today, _): return String(localized: "Couldn't load today · Details")
        case .issue(.history, _): return String(localized: "Couldn't load your history · Details")
        case .issue: return String(localized: "Couldn't load your data · Details")
        case .paused: return String(localized: "Health sync paused")
        case .upToDate(let date, let demo):
            let prefix = demo ? String(localized: "Demo data · ") : ""
            guard let date else { return prefix + String(localized: "Not updated yet") }
            if now.timeIntervalSince(date) < 60 { return prefix + String(localized: "Up to date · just now") }
            let ago = date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
            return prefix + String(localized: "Up to date · \(ago)")
        }
    }

    /// When the data on screen was loaded, never relative: "14:05", "Yesterday 14:05", "Tue 14:05",
    /// then the date.
    static func dataTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return Fmt.time(date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday \(Fmt.time(date))")
        }
        if now.timeIntervalSince(date) < 6 * 86_400 {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}

/// "Nothing new from Garmin Connect since 23:40": the source's own name, from HealthKit.
struct WatchSyncHint: Equatable {
    let source: String
    let since: Date
    /// An app that syncs to Apple Health only while it runs (open it); else an Apple device.
    let isApp: Bool

    func text(now: Date, calendar: Calendar = .current) -> String {
        let time = calendar.isDate(since, inSameDayAs: now) ? Fmt.time(since)
            : since.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        if isApp {
            return String(localized: "Nothing new from \(source) since \(time). Open the \(source) app to sync it to Apple Health.")
        }
        return String(localized: "Nothing new from \(source) since \(time). Wear it and keep it near your iPhone so it syncs.")
    }
}

/// Which in-between state wins, from the facts alone (tested in `TodayStatesTests`).
enum TodayStates {
    /// Sources quiet for longer than this aren't the user's current watch.
    static let freshnessWindow: TimeInterval = 14 * 86_400

    /// The platform scored the day (readiness, or a `computed_at` past `0001-01-01`).
    static func isScored(_ score: DailyScore) -> Bool { score.standing != .unscored }

    /// The account's first pass over the backfill window is still going.
    static func isImporting(_ f: TodaySyncFacts) -> Bool { f.syncs && !f.engine.backfillDone }

    /// Today's scoring state: the platform's latest word (`GET /v1/me/sync`) when it's about
    /// today, else the cached score's.
    static func todayState(_ f: TodaySyncFacts) -> ScoringState? {
        if let status = f.status, status.today.day == DayFormat.string(from: f.now) { return status.today.state }
        return f.today?.scoringState
    }

    /// The import before anything is scored; otherwise the gauge `TodayPresentation.decide`
    /// picks: a night not scored yet, the baselines being learned, or the score.
    static func hero(_ f: TodaySyncFacts) -> TodayHero {
        hero(f, presentation: .decide(f.scores))
    }

    /// The same, from `f`'s decision already made (`TodayContent`).
    static func hero(_ f: TodaySyncFacts, presentation p: TodayPresentation) -> TodayHero {
        if isImporting(f), !f.hasScoredDay { return .importing(progress(f)) }
        switch p.gauge {
        case .pending(let night): return .pending(night)
        case .baselines(let nights): return .calibrating(nights: nights)
        // Nothing scored and no import running: the empty gauge, "Your scores appear after the first synced night".
        case .readiness, .firstImport: return .score
        }
    }

    static func importRow(_ f: TodaySyncFacts) -> ImportProgress? {
        guard isImporting(f), f.hasScoredDay else { return nil }
        return progress(f)
    }

    static func progress(_ f: TodaySyncFacts) -> ImportProgress {
        let step: ImportProgress.Step
        switch f.phase {
        case .reading: step = .reading
        case .uploading: step = .uploading
        case .awaitingScores, .refreshing: step = .scoring
        default:
            if !(f.status?.pendingDays.isEmpty ?? true) { step = .scoring }
            else { step = f.engine.streams.isEmpty ? .reading : .uploading }
        }
        let first = DayFormat.string(from: DayFormat.shift(f.now, days: -(ImportProgress.windowDays - 1)))
        let today = DayFormat.string(from: f.now)
        let covered = f.engine.coveredDays.filter { $0 >= first && $0 <= today }
        let streams = f.engine.streams
        return ImportProgress(step: step,
                              nights: streams[HealthStream.sleep.anchorID]?.days.count ?? 0,
                              heartRateReadings: streams[HealthStream.quantity(.heartRate).anchorID]?.sent ?? 0,
                              workouts: streams[HealthStream.workouts.anchorID]?.sent ?? 0,
                              coveredDays: covered.count,
                              oldestDay: covered.min().flatMap(DayFormat.date(from:)))
    }

    /// What the line says, most urgent first: the user's to do, then why nothing moves,
    /// then what moves, then how fresh it is. `staleSince` (`RefreshPolicy`) only shows when
    /// idle; while the error card is on screen (`card`), the line points to it instead.
    static func line(_ f: TodaySyncFacts, staleSince: Date? = nil, card: ReadResource? = nil,
                     signedOut: Bool = false) -> SyncLine {
        if let gate = f.gate { return .actionNeeded(gate) }
        if !f.online { return .offline }
        if f.waitingForUnlock { return .waitingForUnlock }
        switch f.activity {
        case .reading(let stream): return .reading(stream)
        case .uploading(_, let records): return .uploading(records: records)
        case nil: break
        }
        let night: Bool
        if case .pending = hero(f) { night = true } else { night = false }
        if f.phase == .awaitingScores { return .scoring(night: night) }
        if f.phase == .refreshing || f.isLoading { return .updating }
        if let card { return .issue(card, signedOut: signedOut) }
        if let since = staleSince { return .stale(since: since) }
        if f.syncFailed { return .paused }
        if case .pending(let p) = hero(f), !p.waitingForSleep { return .scoring(night: true) }
        return .upToDate(f.lastUpdated, demo: f.isDemo)
    }

    /// The freshest source of heart rate (or sleep) has been quiet for over 6 h in the
    /// morning (05–12) or 12 h otherwise.
    static func watchHint(_ f: TodaySyncFacts, calendar: Calendar = .current) -> WatchSyncHint? {
        guard f.syncs, !f.waitingForUnlock, !isImporting(f),
              let newest = f.freshness.max(by: { $0.newest < $1.newest }) else { return nil }
        let morning = (5..<12).contains(calendar.component(.hour, from: f.now))
        let quiet: TimeInterval = (morning ? 6 : 12) * 3_600
        guard f.now.timeIntervalSince(newest.newest) > quiet else { return nil }
        return WatchSyncHint(source: newest.source, since: newest.newest, isApp: newest.isApp)
    }
}

// MARK: - one decision for gauge, tiles and note

/// What the day's numbers are decided from: a subset of `TodaySyncFacts`, also built by the
/// widget snapshot (`Repository.publishWidget`), so the two can't disagree.
struct TodayScoreFacts: Equatable, Sendable {
    /// Today, `yyyy-MM-dd`.
    var day: String
    /// Today's row (detail score, else list), any standing.
    var today: DailyScore?
    /// `GET /v1/me/sync`'s today when it's about `day`, else the row's.
    var scoringState: ScoringState?
    /// Days before `day`, oldest first, as cached; `decide` filters them.
    var prior: [DailyScore] = []
    var expectedWithinSec: Int?
    /// Last night from Apple Health, unscored (`RawNightCard`).
    var lastNight: RawNight?
}

/// Gauge, tiles and note from one source (brief §2, ui.md §1), decided once; tested as the
/// decision table (design.md §7).
struct TodayPresentation: Equatable, Sendable {
    /// ui.md's rows: A scored, B calibrating, C pending, D recalculating, E first import.
    enum Row: Equatable, Sendable { case scored, calibrating, pending, recalculating, firstImport }

    enum Gauge: Equatable, Sendable {
        /// The source day's readiness (rows A, D; B when the platform computed one, with `needsVitals`).
        case readiness(Int?)
        /// Row B: today's `baseline_days`; with `needsVitals`, the nights with HRV and resting HR instead.
        case baselines(nights: Int)
        /// The outline, the latest readiness dimmed and dated (C).
        case pending(PendingNight)
        /// Nothing scored ever (E).
        case firstImport
    }

    struct Tiles: Equatable, Sendable {
        /// The one day all three tiles show; nil: placeholders ("–", no caption).
        var source: DailyScore?
        /// `source` isn't today: dimmed, caption = its date.
        var isEarlierDay = false
        /// Row B: "calibrating" under all three.
        var calibrating = false
    }

    /// The line under the gauge (`GaugeNote`), with its reason.
    enum Note: Equatable, Sendable {
        /// Row D: the platform says calibrating while the history has the nights a baseline needs.
        case recalculating
        /// Row B with a long history but under 7 nights with HRV and resting HR in it (lead decision 2,
        /// amended): under today's readiness, or under the baselines counting those nights.
        case needsVitals
    }

    var row: Row
    var gauge: Gauge
    var tiles: Tiles
    var note: Note?
    /// Row C while scoring (not waiting for sleep): last night from Apple Health for `RawNightCard`.
    var rawNight: RawNight?
    /// The latest scored day's readiness before today, whatever the row: the widget's dimmed number,
    /// and tomorrow's until it's scored (`ReadinessSnapshot.asOf`).
    var previousReadiness: Int?

    /// The gauge's "vs 7 d" delta: only beside today's settled readiness, row A with a number (ui.md §4).
    /// Never next to an empty gauge ("—", a scored day without a readiness), a night being scored, the
    /// baselines or the import; nor beside a calibrating or borrowed number (B, D), which has no fair comparison.
    var showsDelta: Bool {
        guard row == .scored, case .readiness(.some) = gauge else { return false }
        return true
    }

    /// Nights with HRV and resting HR among the 30 scored days before, as `baseline_days` counts them.
    static let vitalsWindow = 30

    /// First match wins (design.md §7's table, ui.md's letter in brackets):
    /// 1 (E) nothing scored, no night being scored · 2 (C) no readiness for today yet · 3 (D) the
    /// platform says calibrating, the history has the nights · 4 (B) calibrating · 5 (A) scored.
    static func decide(_ f: TodayScoreFacts) -> TodayPresentation {
        let prior = f.prior.filter { $0.day < f.day && $0.standing != .unscored }
        let latestPrior = prior.last { $0.readiness != nil }
        var p = pick(f, prior: prior, latestPrior: latestPrior)
        p.previousReadiness = latestPrior?.readiness
        return p
    }

    private static func pick(_ f: TodayScoreFacts, prior: [DailyScore], latestPrior: DailyScore?) -> TodayPresentation {
        let vitals = prior.suffix(vitalsWindow).count { $0.hrvMs != nil && $0.rhr != nil }
        let scoredToday = f.today.flatMap { $0.standing == .unscored ? nil : $0 }
        let scoring = f.scoringState == .pending || f.scoringState == .waitingForSleep

        // 1 (E): the platform isn't scoring a night either (else it's C with nothing to dim).
        if scoredToday == nil, prior.isEmpty, !scoring {
            return TodayPresentation(row: .firstImport, gauge: .firstImport, tiles: Tiles(), note: nil)
        }
        // 2 (C): never "0 of 7" from a day that isn't scored.
        if scoredToday?.readiness == nil, scoredToday == nil || scoring {
            // Scoring only on the platform's word (`pending`, or `scored` before the row is here). Without
            // it (`waiting_for_sleep`, `stale`, no word yet), nothing claims a night is being scored.
            let waiting = f.scoringState != .pending && f.scoringState != .scored
            let night = PendingNight(waitingForSleep: waiting, expectedWithinSec: waiting ? nil : f.expectedWithinSec,
                                     previousReadiness: latestPrior?.readiness.map(Double.init),
                                     previousDay: latestPrior.flatMap { DayFormat.date(from: $0.day) })
            return TodayPresentation(row: .pending, gauge: .pending(night),
                                     tiles: Tiles(source: latestPrior, isEarlierDay: true), note: nil,
                                     rawNight: waiting ? nil : f.lastNight)
        }
        guard let today = scoredToday else {
            return TodayPresentation(row: .firstImport, gauge: .firstImport, tiles: Tiles(), note: nil) // not reached
        }
        // 3 (D): the platform's flag against its own history; the latest scored day stands in.
        if today.calibrating, vitals >= DailyScore.baselineNightsRequired {
            let source = today.readiness != nil ? today : latestPrior
            return TodayPresentation(row: .recalculating, gauge: .readiness(source?.readiness),
                                     tiles: Tiles(source: source, isEarlierDay: today.readiness == nil),
                                     note: .recalculating)
        }
        // 4 (B), a long history without the heart-rate nights a baseline needs (a phone without a watch):
        // the platform's readiness when it computed one, else the baselines counting those nights. The
        // note says why, so the tiles don't add "calibrating" (lead decision 2, amended in review).
        if today.calibrating, prior.count >= DailyScore.baselineNightsRequired {
            return TodayPresentation(row: .calibrating, gauge: today.readiness.map { .readiness($0) } ?? .baselines(nights: vitals),
                                     tiles: Tiles(source: today), note: .needsVitals)
        }
        // 4 (B), a short history: `baseline_days` of today, the latest scored day here.
        if today.calibrating {
            return TodayPresentation(row: .calibrating, gauge: .baselines(nights: today.baselineDays),
                                     tiles: Tiles(source: today, calibrating: true), note: nil)
        }
        // 5 (A)
        return TodayPresentation(row: .scored, gauge: .readiness(today.readiness), tiles: Tiles(source: today), note: nil)
    }
}

extension TodayPresentation.Note {
    var text: String {
        switch self {
        case .recalculating: return String(localized: "Recalculating your baselines")
        case .needsVitals:
            return String(localized: "Baselines need heart-rate variability and resting heart rate from nights with your watch.")
        }
    }

    /// Static: neither is progress.
    var systemImage: String {
        switch self {
        case .recalculating: return "arrow.triangle.2.circlepath"
        case .needsVitals: return "info.circle"
        }
    }
}

/// `-RyftScenario import` (or pending, calibrating, watch, recalculating, …) in demo mode, and
/// previews: one in-between state on mock data, for screenshots and UI tests. Each Today row
/// has one (ui.md §1.6).
enum TodayScenario: String, CaseIterable {
    case importing = "import", pending, calibrating, watch
    /// Row C without a night yet; row C with nothing scored before.
    case waitingForSleep, pendingNoPrevious
    /// Row D: the screenshot's row (80 · 75 % · 0.9, calibrating, 0 baseline days) over a full history;
    /// the same with today scored but without a readiness.
    case recalculating, recalculatingYesterday
    /// Row B with a long history that has no HRV or resting HR (a phone-only account): the platform's
    /// readiness with the note; the same without a readiness, the baselines counting heart-rate nights.
    case needsVitals, needsVitalsBaselines

    func apply(to base: TodaySyncFacts) -> TodaySyncFacts {
        var f = base
        f.isDemo = true
        let now = f.now
        let key = DayFormat.string(from: now)
        switch self {
        case .importing:
            f.syncs = true
            f.hasScoredDay = false
            f.today = nil
            f.engine = Self.importingEngine(now: now)
            f.phase = .uploading
            f.activity = .uploading(.quantity(.heartRate), records: 12_400)
        case .pending, .waitingForSleep, .pendingNoPrevious:
            let waiting = self == .waitingForSleep
            f.syncs = true
            f.engine.backfillDone = true
            f.hasScoredDay = self != .pendingNoPrevious
            f.today = nil
            f.prior = self == .pendingNoPrevious ? [] : Self.prior(now: now)
            f.status = Self.status(now: now, waiting ? .waitingForSleep : .pending)
            let wake = Calendar.current.date(bySettingHour: 6, minute: 52, second: 0, of: now) ?? now
            f.lastNight = waiting ? nil : RawNight(asleepMin: 437, bedtime: wake.addingTimeInterval(-8 * 3_600 + 25 * 60),
                                                   wake: wake, source: "Garmin Connect")
        case .calibrating:
            f.engine.backfillDone = true
            f.today = MockData.calibratingScore
            f.prior = Array(Self.prior(now: now).suffix(3)) // a new account: the history is short
            f.status = Self.status(now: now, .scored)
        case .watch:
            f.syncs = true
            f.engine.backfillDone = true
            f.freshness = [SourceFreshness(source: "Garmin Connect", bundleID: "com.garmin.connect.mobile",
                                           newest: now.addingTimeInterval(-14 * 3_600))]
        case .recalculating, .recalculatingYesterday, .needsVitals, .needsVitalsBaselines:
            f.engine.backfillDone = true
            f.hasScoredDay = true
            let withReadiness = self != .recalculatingYesterday && self != .needsVitalsBaselines
            f.today = DailyScore(day: key, readiness: withReadiness ? 80 : nil, state: withReadiness ? .balanced : .calibrating,
                                 recovery: withReadiness ? 75 : nil, strain: withReadiness ? 0.9 : nil,
                                 sleepActualMin: withReadiness ? 437 : nil, baselineDays: 0, calibrating: true,
                                 computedAt: now.addingTimeInterval(-3_600), scoringState: .scored)
            f.prior = Self.prior(now: now, vitals: self != .needsVitals && self != .needsVitalsBaselines)
            if self == .needsVitalsBaselines {
                // Two recent nights with the watch: "2 of 7 nights with heart-rate data".
                for i in f.prior.indices.suffix(2) { f.prior[i].hrvMs = 52; f.prior[i].rhr = 51 }
            }
            f.status = Self.status(now: now, .scored)
        }
        return f
    }

    /// The demo history before today, with yesterday as ui.md §1.6 has it (76 · 75 % · 7h 10m · 0.9).
    /// `vitals: false`: the same days without HRV and resting HR, as a phone without a watch scores them.
    static func prior(now: Date, vitals: Bool = true) -> [DailyScore] {
        let key = DayFormat.string(from: now)
        let yesterday = DayFormat.string(from: DayFormat.shift(now, days: -1))
        return MockData.history.filter { $0.day < key }.map { d in
            var d = d
            if d.day == yesterday {
                d.readiness = 76
                d.recovery = 75
                d.sleepActualMin = 430
                d.strain = 0.9
            }
            if !vitals {
                d.hrvMs = nil
                d.rhr = nil
            }
            return d
        }
    }

    /// `GET /v1/me/sync` saying `state` about today.
    static func status(now: Date, _ state: ScoringState) -> SyncStatus {
        let key = DayFormat.string(from: now)
        return SyncStatus(gate: nil, lastSyncAt: now, lastSyncDevice: "iPhone", latest: [:],
                          today: TodayState(day: key, state: state, scoredAt: state == .scored ? now : nil,
                                            modelVersion: "2026.10.1"),
                          pendingDays: state == .pending ? [key] : [], expectedWithinSec: 20, resyncRequestedAt: nil)
    }

    /// 61 of 90 days in: nights, heart rate and workouts as a real import counts them.
    static func importingEngine(now: Date) -> SyncEngineState {
        func days(_ n: Int) -> Set<String> {
            Set((0..<n).map { DayFormat.string(from: DayFormat.shift(now, days: -$0)) })
        }
        var e = SyncEngineState()
        e.phase = .backfill
        e.recentDone = true
        var sleep = SyncEngineState.StreamProgress()
        sleep.records = 1_250
        sleep.days = days(58)
        var hr = SyncEngineState.StreamProgress()
        hr.records = 84_213
        hr.days = days(61)
        var workouts = SyncEngineState.StreamProgress()
        workouts.records = 41
        workouts.days = days(55)
        e.streams = ["sleep": sleep, "heart_rate": hr, "workouts": workouts]
        return e
    }
}
