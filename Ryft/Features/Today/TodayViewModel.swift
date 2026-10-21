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
        case error(message: String, details: String?)
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
    private var score: DailyScore? { facts.today }

    var hasDataSource: Bool { state.hasDataSource }
    var greeting: String { ReadinessCopy.greeting(at: env.clock.now()) }
    var sentence: String {
        guard hasDataSource else { return String(localized: "Let's get you set up.") }
        switch hero {
        case .importing: return String(localized: "Your history is on its way.")
        case .pending(let night):
            if night.waitingForSleep { return String(localized: "Last night hasn't reached RYFT yet.") }
            // The gauge and the line say it's scoring; this says what the dimmed number is.
            return night.previousReadiness == nil ? String(localized: "Your night is being scored.")
                : String(localized: "Yesterday's readiness, until last night is scored.")
        case .calibrating, .score: return ReadinessCopy.sentence(score: score)
        }
    }
    var isOffline: Bool { !env.connectivity.isOnline }
    var showsHealthHint: Bool { state.hasNoHealthData }

    var readiness: Double? { score?.readiness.map(Double.init) }

    /// Only once there's a score to point at.
    var showsCoachMarks: Bool { hasDataSource && score != nil && coachMarks.step != nil }
    var readinessWeek: [TrendPoint] { state.readinessWeek?.points ?? [] }
    var readinessDelta: MetricDelta? { .vsSevenDayMean(readinessWeek) }

    /// Not while the night is pending: last night's raw sleep shows beside the gauge, unscored.
    var sleepText: String {
        if hero.isPending { return Fmt.placeholder }
        return Fmt.duration(minutes: score?.sleepActualMin ?? state.today?.sleep?.totalMin)
    }
    var recovery: Int? { score?.recovery }
    var recoveryText: String { Fmt.percent(recovery) }
    var recoveryBand: String? { recovery.map { MetricSpec.scoreBand(Double($0)).label } }
    var strainText: String { Fmt.strain(score?.strain) }

    var status: Status? {
        if let step = gate { return Self.actionNeeded(step) }
        if let notice = apiStatus.retryNotice { return .retrying(notice) }
        if let error = state.error {
            // With data on screen, the failure only means it's not the latest.
            return .error(message: state.today == nil
                          ? error
                          : String(localized: "Couldn't refresh just now — showing your last loaded data."),
                          details: state.errorDetails)
        }
        if !state.isDemo, let syncError = sync.lastError, env.settings.isConfigured {
            return .syncPaused(message: String(localized: "Health sync paused: \(syncError)"),
                               details: sync.lastErrorDetails)
        }
        return nil
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
        f.today = state.today?.score
        f.previous = history.last { $0.day < todayKey && $0.readiness != nil }
        f.hasScoredDay = (history + [f.today].compactMap { $0 }).contains(where: TodayStates.isScored)
        f.lastUpdated = state.lastUpdated
        f.expectedScoringSec = sync.lastScoring?.expectedWithinSec
        f.lastNight = lastNightRaw
        f.freshness = freshness
        if let scenario = state.todayScenario { f = scenario.apply(to: f) }
        return f
    }

    var hero: TodayHero { TodayStates.hero(facts) }
    /// The import's slim row under the header, once a day is scored and the backfill goes on.
    var importRow: ImportProgress? { TodayStates.importRow(facts) }
    var syncLine: SyncLine { TodayStates.line(facts) }
    var watchHint: WatchSyncHint? { TodayStates.watchHint(facts) }
    /// Last night from Apple Health beside the pending gauge (raw totals, not a score).
    var rawNight: RawNight? {
        guard case .pending = hero else { return nil }
        return facts.lastNight
    }

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

    /// The status line's action: the gate's screen.
    func resolveLine() {
        if case .actionNeeded(let step) = syncLine { resolve(step) }
    }

    /// Pull to refresh and Retry: upload what HealthKit has, wait for scoring, reload.
    func refresh() async {
        await coordinator.run(.userInitiated)
        // Nothing new uploaded still means "show me the latest".
        await state.refresh(force: true)
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
    /// The latest day before today with a readiness.
    var previous: DailyScore?
    /// Some day was scored already (the first import is over for the gauge).
    var hasScoredDay = false
    var lastUpdated: Date?
    /// The last upload's `scoring.expected_within_sec`, until `GET /v1/me/sync` says.
    var expectedScoringSec: Int?
    var lastNight: RawNight?
    var freshness: [SourceFreshness] = []
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
struct PendingNight: Equatable {
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
        case .paused: return String(localized: "Health sync paused")
        case .upToDate(let date, let demo):
            let prefix = demo ? String(localized: "Demo data · ") : ""
            guard let date else { return prefix + String(localized: "Not updated yet") }
            if now.timeIntervalSince(date) < 60 { return prefix + String(localized: "Up to date · just now") }
            let ago = date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
            return prefix + String(localized: "Up to date · \(ago)")
        }
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
    static func isScored(_ score: DailyScore) -> Bool {
        score.readiness != nil || (score.computedAt ?? .distantPast) > Date(timeIntervalSince1970: 0)
    }

    /// The account's first pass over the backfill window is still going.
    static func isImporting(_ f: TodaySyncFacts) -> Bool { f.syncs && !f.engine.backfillDone }

    /// Today's scoring state: the platform's latest word (`GET /v1/me/sync`) when it's about
    /// today, else the cached score's.
    static func todayState(_ f: TodaySyncFacts) -> ScoringState? {
        if let status = f.status, status.today.day == DayFormat.string(from: f.now) { return status.today.state }
        return f.today?.scoringState
    }

    /// Import before anything is scored; then a night not scored yet; then the baseline
    /// being learned; else the score.
    static func hero(_ f: TodaySyncFacts) -> TodayHero {
        if isImporting(f), !f.hasScoredDay { return .importing(progress(f)) }
        if f.today?.readiness == nil, let state = todayState(f), state == .pending || state == .waitingForSleep {
            let waiting = state == .waitingForSleep
            return .pending(PendingNight(waitingForSleep: waiting,
                                         expectedWithinSec: waiting ? nil : f.status?.expectedWithinSec ?? f.expectedScoringSec,
                                         previousReadiness: f.previous?.readiness.map(Double.init),
                                         previousDay: f.previous.flatMap { DayFormat.date(from: $0.day) }))
        }
        if let today = f.today, today.calibrating { return .calibrating(nights: today.baselineDays) }
        return .score
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
    /// then what moves, then how fresh it is.
    static func line(_ f: TodaySyncFacts) -> SyncLine {
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

/// `-RyftScenario import` (or pending, calibrating, watch) in demo mode, and previews: one
/// in-between state on mock data, for screenshots and UI tests.
enum TodayScenario: String, CaseIterable {
    case importing = "import", pending, calibrating, watch

    func apply(to base: TodaySyncFacts) -> TodaySyncFacts {
        var f = base
        f.isDemo = true
        let now = f.now
        switch self {
        case .importing:
            f.syncs = true
            f.hasScoredDay = false
            f.today = nil
            f.engine = Self.importingEngine(now: now)
            f.phase = .uploading
            f.activity = .uploading(.quantity(.heartRate), records: 12_400)
        case .pending:
            f.syncs = true
            f.engine.backfillDone = true
            f.hasScoredDay = true
            f.today = nil
            f.status = SyncStatus(gate: nil, lastSyncAt: now, lastSyncDevice: "iPhone", latest: [:],
                                  today: TodayState(day: DayFormat.string(from: now), state: .pending, scoredAt: nil,
                                                    modelVersion: "2026.10.1"),
                                  pendingDays: [DayFormat.string(from: now)], expectedWithinSec: 20,
                                  resyncRequestedAt: nil)
            let wake = Calendar.current.date(bySettingHour: 6, minute: 52, second: 0, of: now) ?? now
            f.lastNight = RawNight(asleepMin: 437, bedtime: wake.addingTimeInterval(-8 * 3_600 + 25 * 60), wake: wake,
                                   source: "Garmin Connect")
        case .calibrating:
            f.engine.backfillDone = true
            f.today = MockData.calibratingScore
        case .watch:
            f.syncs = true
            f.engine.backfillDone = true
            f.freshness = [SourceFreshness(source: "Garmin Connect", bundleID: "com.garmin.connect.mobile",
                                           newest: now.addingTimeInterval(-14 * 3_600))]
        }
        return f
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
