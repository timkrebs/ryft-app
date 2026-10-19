import Foundation
import Observation

/// The morning briefing: greeting and state sentence, readiness against the days
/// before, the three tiles, the 7-day trend and one status line.
@MainActor
@Observable
final class TodayViewModel {
    private let state: AppState
    private let sync: SyncService
    private let coordinator: SyncCoordinator
    private let apiStatus: APIStatus
    private let push: PushRegistrar?

    /// The one message under the cards, in priority order.
    enum Status: Equatable {
        /// The platform asked to wait (503 / 429), and the app is retrying.
        case retrying(String)
        case error(message: String, details: String?)
        /// HealthKit couldn't be uploaded; the screens still show the platform's data.
        case syncPaused(message: String, details: String?)
    }

    /// First-run coach marks: gauge → physiology → trends.
    let coachMarks: CoachMarks

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator, push: PushRegistrar? = nil,
         apiStatus: APIStatus? = nil) {
        coachMarks = CoachMarks(defaults: state.env.defaults)
        self.state = state
        self.sync = sync
        self.coordinator = coordinator
        self.push = push
        self.apiStatus = apiStatus ?? .shared
    }

    private var env: AppEnvironment { state.env }
    private var score: DailyScore? { state.today?.score }

    var hasDataSource: Bool { state.hasDataSource }
    var greeting: String { ReadinessCopy.greeting(at: env.clock.now()) }
    var sentence: String {
        hasDataSource ? ReadinessCopy.sentence(score: score) : String(localized: "Let's get you set up.")
    }
    var isOffline: Bool { !env.connectivity.isOnline }
    var showsHealthHint: Bool { state.hasNoHealthData }

    var readiness: Double? { score?.readiness.map(Double.init) }

    /// Only once there's a score to point at.
    var showsCoachMarks: Bool { hasDataSource && score != nil && coachMarks.step != nil }
    var readinessWeek: [TrendPoint] { state.readinessWeek?.points ?? [] }
    var readinessDelta: MetricDelta? { .vsSevenDayMean(readinessWeek) }

    var sleepText: String { Fmt.duration(minutes: score?.sleepActualMin ?? state.today?.sleep?.totalMin) }
    var recovery: Int? { score?.recovery }
    var recoveryText: String { Fmt.percent(recovery) }
    var recoveryBand: String? { recovery.map { MetricSpec.scoreBand(Double($0)).label } }
    var strainText: String { Fmt.strain(score?.strain) }

    var status: Status? {
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

    var lastUpdated: Date? { state.lastUpdated }
    var isRefreshing: Bool { state.isLoading || sync.isSyncing }
    var isDemo: Bool { state.isDemo }
    var scoredAt: Date? { score?.computedAt }

    /// Pull to refresh and Retry: upload what HealthKit has, wait for scoring, reload.
    func refresh() async {
        await coordinator.run(.userInitiated)
        // Nothing new uploaded still means "show me the latest".
        await state.refresh(force: true)
    }

    func open(_ tab: AppTab) { state.selectedTab = tab }

    // MARK: feature flags

    var showsTrain: Bool { env.flags.isOn(.trainEnabled) }

    /// The redesigned Today, shipped dark behind `today.redesign`: last night's
    /// hypnogram under the tiles.
    var showsRedesign: Bool { env.flags.isOn(.todayRedesign) }
    var lastNight: SleepDetail? { state.today?.sleep }

    /// `physiology.card`: HRV and resting HR against their 30-day range.
    var showsPhysiology: Bool { env.flags.isOn(.physiologyCard) && hasDataSource }
    var hrv: Double? { score?.hrvMs }
    var rhr: Double? { score?.rhr }
    var hrvSeries: TrendSeries? { state.cachedTrend(.hrv, range: .month) }
    var rhrSeries: TrendSeries? { state.cachedTrend(.rhr, range: .month) }

    /// The 30-day series behind the physiology card (cached, revalidated by TTL).
    func loadPhysiology() async {
        guard showsPhysiology else { return }
        _ = await state.trend(.hrv, range: .month)
        _ = await state.trend(.rhr, range: .month)
    }

    // MARK: push pre-prompt

    /// After the first sync, before iOS asked; never on top of the coach marks.
    var showsPushPrompt: Bool { (push?.showsPrePrompt ?? false) && !showsCoachMarks }

    func enablePush() async { await push?.accept() }
    func dismissPushPrompt() { push?.dismissPrompt() }
}
