// Read-side cache of what the API returns. Views bind to this; SyncService
// writes to HealthKit→backend, this reads backend→UI.
//
// The last successful Today payload is persisted to Caches/ so the app renders
// instantly at launch and offline. Endpoints the platform doesn't serve yet
// (trends, sleep ranges, insights, workout detail) fall back to data derived
// from `/v1/days` — see Derived.swift.
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
    /// False when insights were computed on-device because `/v1/insights` is missing.
    @Published var insightsFromPlatform = true
    @Published var error: String?
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
            await loadInsights(from: src)
            error = nil
            lastUpdated = .now
            if !isDemo {
                cache.save(TodaySnapshot(today: d, history: history, user: u, insights: insights, fetchedAt: .now),
                           as: Self.snapshotKey)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Pull-to-refresh: upload new Health data, then reload.
    func syncAndRefresh(using sync: SyncService) async {
        if !isDemo && auth.isSignedIn && settings.isConfigured { await sync.syncNow() }
        await refresh()
    }

    /// `GET /v1/me` on its own. Called once right after sign-in, before the
    /// first sync: the platform creates the user row there.
    func loadUser() async {
        guard hasDataSource else { return }
        do {
            user = try await source.me()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Forget everything (account, server or demo mode changed).
    func reset() {
        today = nil
        history = []
        user = nil
        insights = []
        error = nil
        lastUpdated = nil
        invalidateCaches()
        cache.clear()
    }

    func updateUser(_ patch: UserPatch) async {
        do {
            user = try await source.patchMe(patch)
        } catch {
            self.error = error.localizedDescription
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

    func sleepRange(_ kind: SleepRangeKind) async -> SleepRange {
        if let cached = sleepCache[kind] { return cached }
        let r: SleepRange
        do {
            r = try await source.sleep(range: kind)
        } catch {
            r = .derived(from: history, kind: kind)
        }
        sleepCache[kind] = r
        return r
    }

    func trend(_ metric: TrendMetric, range: TrendRange) async -> TrendSeries {
        let key = "\(metric.rawValue)-\(range.rawValue)"
        if let cached = trendCache[key] { return cached }
        let s: TrendSeries
        do {
            s = try await source.trends(metric: metric, range: range)
        } catch {
            s = .derived(from: history, metric: metric, range: range)
        }
        trendCache[key] = s
        return s
    }

    /// Synchronous fallback series from the loaded history (no network).
    func derivedTrend(_ metric: TrendMetric, range: TrendRange) -> TrendSeries {
        trendCache["\(metric.rawValue)-\(range.rawValue)"] ?? .derived(from: history, metric: metric, range: range)
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

    private func loadInsights(from src: RyftDataSource) async {
        do {
            insights = try await src.insights()
            insightsFromPlatform = true
        } catch {
            insights = Insight.derived(from: history)
            insightsFromPlatform = false
        }
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
