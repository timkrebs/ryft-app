// Read-side cache of what the API returns. Views bind to this; SyncService
// writes to HealthKit→backend, this reads backend→UI.
//
// The last successful Today payload (with its 7-day readiness trend) is
// persisted to Caches/ so the app renders instantly at launch and offline.
// Every endpoint exists on the platform; a failed call leaves the screen
// empty with an inline message instead of computing numbers on the phone.
import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case today, sleep, strain, insights, profile
}

@MainActor
final class AppState: ObservableObject {
    @Published var today: DayDetail?
    @Published var history: [DailyScore] = []   // last 90 days, oldest first
    @Published var user: User?
    @Published var insights: [Insight] = []
    /// Today's "Trends" card: `GET /v1/trends?metric=readiness&range=7d`.
    @Published var readinessWeek: TrendSeries?
    @Published var error: String?
    /// Status and request ID of `error`, for the inline message's Details.
    @Published var errorDetails: String?
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var selectedTab: AppTab
    @Published private(set) var dismissedInsightIDs: Set<String> = []

    static let historyDays = 90

    private let settings: Settings
    private let auth: AuthService
    private let cache: ResponseCache
    private let sourceOverride: RyftDataSource?
    private var dayCache: [String: DayDetail] = [:]
    private var trendCache: [String: TrendSeries] = [:]
    private var sleepCache: [SleepRangeKind: SleepRange] = [:]
    private var workoutCache: [UUID: WorkoutDetail] = [:]
    private let defaults = UserDefaults.standard

    init(settings: Settings = .shared, auth: AuthService? = nil, source: RyftDataSource? = nil,
         cache: ResponseCache = .shared, restoreCache: Bool = true) {
        self.settings = settings
        self.auth = auth ?? .shared
        self.cache = cache
        self.sourceOverride = source
        // `-RyftTab sleep` selects the initial tab (handy for screenshots).
        selectedTab = UserDefaults.standard.string(forKey: "RyftTab").flatMap(AppTab.init(rawValue:)) ?? .today
        dismissedInsightIDs = loadDismissed()
        if restoreCache, source == nil, !settings.demoMode,
           let snap = cache.load(TodaySnapshot.self, key: Self.snapshotKey) {
            apply(snap)
        }
    }

    // MARK: source

    var source: RyftDataSource {
        sourceOverride ?? (settings.demoMode ? MockDataSource.shared : APIClient.shared)
    }

    /// There's something to load from: a signed-in caller and a server URL, demo mode or an injected source.
    var hasDataSource: Bool {
        !previewUnconfigured && (sourceOverride != nil || settings.demoMode || (auth.isSignedIn && settings.isConfigured))
    }

    /// Previews of the empty/unconfigured state.
    private var previewUnconfigured = false

    var isDemo: Bool { sourceOverride is MockDataSource || (sourceOverride == nil && settings.demoMode) }

    // MARK: loading

    func refresh() async {
        guard hasDataSource else { return }
        // Offline: keep what's on screen (the cached snapshot); no request, no error.
        guard isDemo || ConnectivityMonitor.shared.isOnline else { return }
        isLoading = true
        defer { isLoading = false }
        let src = source
        let account = auth.accountID
        do {
            let from = DayFormat.shift(.now, days: -(Self.historyDays - 1))
            async let detail = src.day(.now)
            async let days = src.days(from: from, to: .now)
            async let me = src.me()
            let (d, h, u) = try await (detail, days, me)
            // Signed out (or switched account) while this was in flight: drop it.
            guard auth.accountID == account else { return }
            today = d
            history = h.sorted { $0.day < $1.day }
            user = u
            invalidateCaches()
            dayCache[d.score.day] = d
            async let week = try? src.trends(metric: .readiness, range: .week)
            await loadInsights(from: src)
            if let w = await week {
                readinessWeek = w
                trendCache[Self.trendKey(.readiness, .week)] = w
            }
            error = nil
            errorDetails = nil
            lastUpdated = .now
            if !isDemo {
                cache.save(TodaySnapshot(today: d, history: history, user: u, insights: insights,
                                         readinessWeek: readinessWeek, fetchedAt: .now),
                           as: Self.snapshotKey)
            }
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
        }
    }

    /// Pull-to-refresh: upload new Health data, then reload.
    func syncAndRefresh(using sync: SyncService) async {
        if !isDemo && auth.isSignedIn && settings.isConfigured { await sync.syncNow() }
        await refresh()
    }

    /// Right after sign-in, before the first sync: `GET /v1/me` creates the
    /// user on the platform, then `PATCH /v1/me` sets the phone's timezone
    /// (new users start in Europe/Berlin, which defines every day boundary).
    func loadUserAfterSignIn() async {
        guard hasDataSource else { return }
        do {
            var u = try await source.me()
            let tz = TimeZone.current.identifier
            if u.tz != tz {
                u = try await source.patchMe(UserPatch(tz: tz))
            }
            user = u
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
        }
    }

    /// Forget everything (account, server or demo mode changed).
    func reset() {
        today = nil
        history = []
        user = nil
        insights = []
        readinessWeek = nil
        error = nil
        errorDetails = nil
        lastUpdated = nil
        invalidateCaches()
        cache.clear()
    }

    func updateUser(_ patch: UserPatch) async {
        do {
            user = try await source.patchMe(patch)
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
        }
    }

    // MARK: per-screen data (cached, with fallbacks)

    func dayDetail(for date: Date) async throws -> DayDetail {
        let key = DayFormat.string(from: date)
        if let cached = dayCache[key] { return cached }
        let d = try await source.day(date)
        dayCache[key] = d
        return d
    }

    /// Cached day detail without hitting the network (for instant first paint).
    func cachedDayDetail(for date: Date) -> DayDetail? {
        dayCache[DayFormat.string(from: date)]
    }

    /// `nil` when the platform couldn't be reached; the screen says so.
    func sleepRange(_ kind: SleepRangeKind) async -> SleepRange? {
        if let cached = sleepCache[kind] { return cached }
        guard let r = try? await source.sleep(range: kind) else { return nil }
        sleepCache[kind] = r
        return r
    }

    /// An empty series (not cached) when the platform couldn't be reached.
    func trend(_ metric: TrendMetric, range: TrendRange) async -> TrendSeries {
        let key = Self.trendKey(metric, range)
        if let cached = trendCache[key] { return cached }
        guard let s = try? await source.trends(metric: metric, range: range) else {
            return TrendSeries(metric: metric.rawValue, range: range.rawValue, points: [],
                               avg: nil, min: nil, max: nil, baseline: nil)
        }
        trendCache[key] = s
        return s
    }

    /// Already-loaded series, for instant paint.
    func cachedTrend(_ metric: TrendMetric, range: TrendRange) -> TrendSeries? {
        trendCache[Self.trendKey(metric, range)]
    }

    private static func trendKey(_ metric: TrendMetric, _ range: TrendRange) -> String {
        "\(metric.rawValue)-\(range.rawValue)"
    }

    func workoutDetail(_ w: Workout) async -> WorkoutDetail {
        if let cached = workoutCache[w.id] { return cached }
        do {
            let d = try await source.workout(id: w.id)
            workoutCache[w.id] = d
            return d
        } catch {
            // No detail endpoint: show what the list gave us.
            return WorkoutDetail(workout: w)
        }
    }

    func score(for date: Date) -> DailyScore? {
        let key = DayFormat.string(from: date)
        return history.last { $0.day == key }
    }

    // MARK: insights

    var visibleInsights: [Insight] {
        insights.filter { !dismissedInsightIDs.contains($0.id) }
    }

    /// Hides an insight for the rest of the day.
    func dismiss(_ insight: Insight) {
        dismissedInsightIDs.insert(insight.id)
        defaults.set(["day": DayFormat.string(from: .now), "ids": Array(dismissedInsightIDs)] as [String: Any],
                     forKey: Self.dismissedKey)
    }

    /// Keeps the previous cards if the call fails.
    private func loadInsights(from src: RyftDataSource) async {
        if let fresh = try? await src.insights() { insights = fresh }
    }

    private func loadDismissed() -> Set<String> {
        guard let stored = defaults.dictionary(forKey: Self.dismissedKey),
              stored["day"] as? String == DayFormat.string(from: .now),
              let ids = stored["ids"] as? [String] else { return [] }
        return Set(ids)
    }

    // MARK: private

    private static let snapshotKey = "today"
    private static let dismissedKey = "insights.dismissed"

    private func apply(_ snap: TodaySnapshot) {
        today = snap.today
        history = snap.history
        user = snap.user
        insights = snap.insights
        readinessWeek = snap.readinessWeek
        if let w = snap.readinessWeek { trendCache[Self.trendKey(.readiness, .week)] = w }
        lastUpdated = snap.fetchedAt
        if let d = snap.today { dayCache[d.score.day] = d }
    }

    private func invalidateCaches() {
        dayCache = [:]
        trendCache = [:]
        sleepCache = [:]
        workoutCache = [:]
    }
}

// MARK: - previews

extension AppState {
    /// Pre-filled with mock data so previews render without awaiting anything.
    static func preview(empty: Bool = false, calibrating: Bool = false) -> AppState {
        let s = AppState(source: MockDataSource.shared, restoreCache: false)
        guard !empty else {
            s.previewUnconfigured = true
            return s
        }
        s.history = MockData.history
        s.user = MockData.user
        s.insights = MockData.insights
        s.readinessWeek = MockData.trend(.readiness, range: .week)
        s.lastUpdated = .now.addingTimeInterval(-300)
        var detail = MockData.todayDetail
        if calibrating {
            detail.score = MockData.calibratingScore
            s.history = Array(MockData.history.suffix(4))
        }
        s.today = detail
        s.dayCache[detail.score.day] = detail
        return s
    }
}
