// The read side, as the screens see it: what the platform says, served from
// SwiftData through the Repository (offline-first). Views and view models read
// these properties, which never wait for the network; loads only revalidate.
// SyncService writes HealthKit → platform; this reads platform → UI.
// A failed call keeps the cached data with an inline message; the phone never
// computes scores itself.
import Foundation
import Observation

enum AppTab: String, CaseIterable, Hashable {
    case today, sleep, strain, insights, profile
}

@MainActor
@Observable
final class AppState {
    var error: String?
    /// Status and request ID of `error`, for the inline message's Details.
    var errorDetails: String?
    var isLoading = false
    var selectedTab: AppTab
    /// The platform's latest `GET /v1/me/sync`: what it has, what scoring is doing (pending
    /// days, today's state). Asked at launch and while a sync waits for scores.
    var syncStatus: SyncStatus? {
        didSet { repository.todayStatus = syncStatus?.today }
    }
    /// Today in one in-between state on mock data (previews; `-RyftScenario` in demo mode).
    var todayScenario: TodayScenario?
    private(set) var dismissedInsightIDs: Set<String> = []

    static let historyDays = 90

    let env: AppEnvironment
    let repository: Repository
    private var settings: Settings { env.settings }
    private var auth: AuthService { env.auth }
    private var defaults: UserDefaults { env.defaults }

    init(env: AppEnvironment, repository: Repository? = nil) {
        self.env = env
        self.repository = repository ?? Repository(env: env)
        // `-RyftTab sleep` selects the initial tab (handy for screenshots).
        selectedTab = UserDefaults.standard.string(forKey: "RyftTab").flatMap(AppTab.init(rawValue:)) ?? .today
        #if DEBUG
        // `-RyftScenario import` (or pending, calibrating, watch): screenshots and UI tests, demo mode only.
        if env.isDemo { todayScenario = UserDefaults.standard.string(forKey: "RyftScenario").flatMap(TodayScenario.init) }
        #endif
        dismissedInsightIDs = loadDismissed()
    }

    private var now: Date { env.clock.now() }
    private var todayKey: String { DayFormat.string(from: now) }

    // MARK: what the screens read (SwiftData)

    /// Today's detail. Setting it writes the store (previews, tests).
    var today: DayDetail? {
        get { repository.day(todayKey) }
        set { if let newValue { repository.store(detail: newValue) } }
    }

    /// The last 90 days, oldest first. Setting it replaces the cached scores.
    var history: [DailyScore] {
        get { repository.history(from: DayFormat.shift(now, days: -(Self.historyDays - 1)), to: now) }
        set { repository.replaceScores(newValue) }
    }

    var user: User? {
        get { repository.user() }
        set { if let newValue { repository.store(user: newValue) } }
    }

    var insights: [Insight] {
        get { repository.insights() }
        set { repository.store(insights: newValue) }
    }

    /// Today's "Trends" card: `GET /v1/trends?metric=readiness&range=7d`.
    var readinessWeek: TrendSeries? {
        get { repository.trend(.readiness, .week) }
        set { if let newValue { repository.store(trend: newValue, metric: .readiness, range: .week) } }
    }

    /// When today was last fetched ("Updated 07:15"); survives relaunches.
    var lastUpdated: Date? { repository.detailFetchedAt(todayKey) }

    // MARK: source

    var source: PlatformAPI { env.api }

    /// There's something to load from: a signed-in caller and a server URL, or demo data.
    var hasDataSource: Bool {
        !previewUnconfigured && (env.isDemo || (auth.isSignedIn && settings.isConfigured))
    }

    /// Previews of the empty/unconfigured state.
    private var previewUnconfigured = false

    var isDemo: Bool { env.isDemo }

    // MARK: loading

    /// Revalidates Today: the day, 90 days of scores, the user, the readiness week
    /// and the insights, each only when stale. `force` (pull to refresh) and
    /// `touched` (days a sync queued for rescoring) fetch regardless.
    func refresh(force: Bool = false, touched: [String] = []) async {
        guard hasDataSource else { return }
        // Offline: keep what's on screen (the cache); no request, no error.
        guard isDemo || env.connectivity.isOnline else { return }
        isLoading = true
        defer { isLoading = false }
        let now = now
        let rescored = force || !touched.isEmpty
        do {
            async let day: DayDetail? = repository.refreshDay(now, force: rescored)
            async let days: Void = repository.refreshHistory(from: DayFormat.shift(now, days: -(Self.historyDays - 1)),
                                                             to: now, force: rescored)
            async let me: Void = repository.refreshUser(force: force)
            _ = try await (day, days, me)
            for key in touched where key != DayFormat.string(from: now) {
                if let date = DayFormat.date(from: key) { _ = try? await repository.refreshDay(date, force: true) }
            }
            try? await repository.refreshTrend(.readiness, .week, force: rescored)
            try? await repository.refreshInsights(force: rescored)
            error = nil
            errorDetails = nil
        } catch where error.gate != nil {
            // A gate isn't a failure to show: onboarding asks for it (`APIStatus` saw the code).
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
        }
    }

    /// After a sync (or a silent push): the touched days, today and the 90-day
    /// scores, regardless of their TTL. Errors show like a refresh's.
    func refreshDays(_ touched: [String]) async throws {
        guard hasDataSource else { return }
        let now = now
        do {
            _ = try await repository.refreshDay(now, force: true)
            for key in Set(touched) where key != DayFormat.string(from: now) {
                if let date = DayFormat.date(from: key) { _ = try await repository.refreshDay(date, force: true) }
            }
            try await repository.refreshHistory(from: DayFormat.shift(now, days: -(Self.historyDays - 1)), to: now,
                                                force: true)
            error = nil
            errorDetails = nil
        } catch where error.gate != nil {
            throw error
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
            throw error
        }
    }

    /// Forget what's shown (account changed, demo mode switched). Sign-out wipes
    /// the account's store; demo data is cleared here.
    func reset() {
        error = nil
        errorDetails = nil
        if isDemo { repository.clear() } else { repository.invalidate() }
    }

    /// `PATCH /v1/me`; a failure is the caller's to show (the setting's form, inline).
    func patchUser(_ patch: UserPatch) async throws {
        user = try await source.patchMe(patch)
    }

    // MARK: per-screen data (cache-first, revalidated)

    /// The day's detail: the cached copy when fresh, else the platform's. Offline
    /// with a cached copy it returns the copy; without one it throws.
    func dayDetail(for date: Date) async throws -> DayDetail {
        if let d = try await repository.refreshDay(date) { return d }
        throw APIError.transport(URLError(.notConnectedToInternet))
    }

    /// The cached detail (stale or not), without the network.
    func cachedDayDetail(for date: Date) -> DayDetail? {
        repository.day(DayFormat.string(from: date))
    }

    func cachedSleepRange(_ kind: SleepRangeKind) -> SleepRange? { repository.sleepRange(kind) }

    /// Revalidates a sleep range; `nil` when there's none cached and the platform couldn't be reached.
    func sleepRange(_ kind: SleepRangeKind) async -> SleepRange? {
        try? await repository.refreshSleepRange(kind)
        return repository.sleepRange(kind)
    }

    /// Revalidates a series; an empty one when there's none cached and the platform couldn't be reached.
    func trend(_ metric: TrendMetric, range: TrendRange) async -> TrendSeries {
        try? await repository.refreshTrend(metric, range)
        return repository.trend(metric, range)
            ?? TrendSeries(metric: metric.rawValue, range: range.rawValue, points: [],
                           avg: nil, min: nil, max: nil, baseline: nil)
    }

    /// The cached series, for instant paint.
    func cachedTrend(_ metric: TrendMetric, range: TrendRange) -> TrendSeries? {
        repository.trend(metric, range)
    }

    func cachedWorkoutDetail(_ w: Workout) -> WorkoutDetail? { repository.workout(w.id) }

    /// The workout's curve and zones; without them (no endpoint, offline) the list's fields.
    func workoutDetail(_ w: Workout) async -> WorkoutDetail {
        try? await repository.refreshWorkout(w.id)
        return repository.workout(w.id) ?? WorkoutDetail(workout: w)
    }

    /// Loaded, and nothing in the history came from Apple Health: access may be
    /// off or the watch isn't writing to Health (HealthKit never says which).
    var hasNoHealthData: Bool {
        guard !isDemo, lastUpdated != nil, !isLoading else { return false }
        return history.allSatisfy { $0.sleepActualMin == nil && $0.steps == nil && $0.hrvMs == nil && $0.strain == nil }
            && (today?.workouts.isEmpty ?? true)
    }

    func score(for date: Date) -> DailyScore? {
        repository.score(DayFormat.string(from: date))
    }

    // MARK: insights

    var visibleInsights: [Insight] {
        insights.filter { !dismissedInsightIDs.contains($0.id) }
    }

    /// Hides an insight for the rest of the day.
    func dismiss(_ insight: Insight) {
        dismissedInsightIDs.insert(insight.id)
        defaults.set(["day": DayFormat.string(from: env.clock.now()), "ids": Array(dismissedInsightIDs)] as [String: Any],
                     forKey: Self.dismissedKey)
    }

    /// Keeps the previous cards if the call fails.
    private func loadInsights(from src: PlatformAPI) async {
        if let fresh = try? await src.insights() { insights = fresh }
    }

    private func loadDismissed() -> Set<String> {
        guard let stored = defaults.dictionary(forKey: Self.dismissedKey),
              stored["day"] as? String == DayFormat.string(from: env.clock.now()),
              let ids = stored["ids"] as? [String] else { return [] }
        return Set(ids)
    }

    // MARK: private

    private static let dismissedKey = "insights.dismissed"
}

// MARK: - previews

extension AppState {
    /// Pre-filled with mock data so previews render without awaiting anything.
    static func preview(empty: Bool = false, calibrating: Bool = false, online: Bool = true,
                        auth: AuthService? = nil, coachMarks: Bool = false,
                        flags: [FeatureFlag: Bool] = [:], scenario: TodayScenario? = nil,
                        notifier: MockNotifier? = nil) -> AppState {
        let s = AppState(env: .preview(online: online, auth: auth, flags: flags, coachMarks: coachMarks,
                                       notifier: notifier))
        s.todayScenario = scenario
        guard !empty else {
            s.previewUnconfigured = true
            return s
        }
        s.history = MockData.history
        s.user = MockData.user
        s.insights = MockData.insights
        s.readinessWeek = MockData.trend(.readiness, range: .week)
        var detail = MockData.todayDetail
        if calibrating {
            detail.score = MockData.calibratingScore
            s.history = Array(MockData.history.suffix(4))
        }
        s.today = detail
        return s
    }
}
