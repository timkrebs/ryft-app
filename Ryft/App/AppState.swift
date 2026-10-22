// The read side, as the screens see it: what the platform says, served from
// SwiftData through the Repository (offline-first). Views and view models read
// these properties, which never wait for the network; loads only revalidate.
// SyncService writes HealthKit → platform; this reads platform → UI.
// Each read succeeds or fails on its own (`ReadScheduler`): a failure keeps the cached
// data, and only `RefreshPolicy` decides whether staleness or an error is shown. The
// phone never computes scores itself.
import Foundation
import Observation
import os

enum AppTab: String, CaseIterable, Hashable {
    case today, sleep, strain, insights, profile
}

@MainActor
@Observable
final class AppState {
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
        // Today's inputs follow the read record and the days in the store, not every read.
        env.reads.onChange = { [weak self] change in self?.readsChanged(change) }
        self.repository.onDaysChanged = { [weak self] in self?.readsChanged(.record) }
        readsChanged(.record)
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

    /// The reads behind Today's numbers; one of them in flight is "Updating…".
    private static let loadingResources: Set<ReadResource> = [.today, .history, .me, .syncStatus, .trends, .insights]

    /// A read of today, history, me, sync status, trends or insights is in flight. Stored, and set only
    /// when it changes: a journal's, config's or Train's read doesn't touch Today.
    private(set) var isLoading = false

    /// What Today's card and stale line depend on (`RefreshPolicy.inputs`): today's and history's
    /// states with their store times, and a final "signed out". Stored, replaced only when different;
    /// `refreshIssue` and `staleSince` evaluate it against the time, without SwiftData in `body`.
    private(set) var refreshInputs: [ReadResource: ResourceState] = [:]

    /// The read record or the days changed: recompute what Today shows from them, once, and publish
    /// only what differs (a read that started changes nothing but `isLoading`).
    private func readsChanged(_ change: ReadScheduler.Change) {
        let loading = env.reads.inFlight.contains { Self.loadingResources.contains($0.resource) }
        if loading != isLoading { isLoading = loading }
        guard change == .record else { return }
        let inputs = RefreshPolicy.inputs(resourceStates)
        if inputs != refreshInputs { refreshInputs = inputs }
    }

    /// Pull to refresh: phases 2 and 3 of the last pull (tests await them).
    @ObservationIgnored private(set) var pullPhases: Task<Void, Never>?
    /// The last pull's phase 2; `reset()` cancels it with the phases.
    @ObservationIgnored private var pullNow: Task<Void, Never>?
    /// Ends when the last pull's upload has (or after `uploadWaitCap`): Sync details' "Send
    /// recent days again" reloads its queue then. Nil when the pull sent nothing.
    @ObservationIgnored private(set) var pullUploaded: Task<Void, Never>?
    static let uploadWaitCap: Duration = .seconds(60)

    /// How long the pull's spinner may last, and how long phase 3 waits for the upload.
    static let spinnerCap: Duration = .seconds(3)
    static let uploadHeadStart: Duration = .seconds(2)

    /// Pull to refresh, Try again, Sync now. In order instead of a fan-out:
    /// 1. the upload starts (the coordinator's run; never awaited here);
    /// 2. at once, at high priority: today and `GET /v1/me/sync`;
    /// 3. when the upload ended or after 2 s, whichever is first: history, me, the readiness week
    ///    and insights. The journal, config and Train revalidate on their own triggers.
    /// Returns when phase 2 has settled or after 3 s; the status line carries the rest. Phases 2
    /// and 3 belong to this object, so a cancelled `.refreshable` cancels neither. Offline, or
    /// without a data source, nothing is sent.
    func pullToRefresh(coordinator: SyncCoordinator) async {
        pullUploaded = nil
        guard hasDataSource, isDemo || env.connectivity.isOnline else { return }
        let signposts = Signposts.reads
        let spinner = signposts.beginInterval("pull", id: signposts.makeSignpostID())
        let clock = env.clock, account = env.auth.accountID
        let (uploaded, upload) = AsyncStream<Void>.makeStream()
        let (uploadEnded, endUpload) = AsyncStream<Void>.makeStream()
        Task {
            await coordinator.run(.userInitiated, afterUpload: {
                upload.yield()
                upload.finish()
                endUpload.finish()
            })
        }
        pullUploaded = Task {
            await Self.firstOf({ for await _ in uploadEnded {} }, { try? await clock.sleep(for: Self.uploadWaitCap) })
        }
        let now = now
        // Phase 2's end as a stream: iterating it stops on cancellation, `Task.value` would not,
        // and the spinner cap below must be able to stop waiting.
        let (settled, settle) = AsyncStream<Void>.makeStream()
        let phase2 = Task { [self] in
            let interval = signposts.beginInterval("pull-now", id: signposts.makeSignpostID())
            async let today: Void = refreshToday(now)
            async let status: Void = coordinator.refreshStatus()
            _ = await (today, status)
            signposts.endInterval("pull-now", interval)
            settle.finish()
        }
        let phases = Task { [self] in
            // Instruments: the whole pull (the spinner's `pull` ends at 3 s at most), and phase 3's gate.
            let total = signposts.beginInterval("pull-total", id: signposts.makeSignpostID())
            defer { signposts.endInterval("pull-total", total) }
            let gate = signposts.beginInterval("pull-gate", id: signposts.makeSignpostID())
            await Self.firstOf({ for await _ in uploaded { break } }, { try? await clock.sleep(for: Self.uploadHeadStart) })
            signposts.endInterval("pull-gate", gate)
            // Reset (sign-out, another account, demo switched) meanwhile: the rest isn't this pull's.
            guard !Task.isCancelled, hasDataSource, isDemo || env.auth.accountID == account else {
                await phase2.value
                return
            }
            let interval = signposts.beginInterval("pull-rest", id: signposts.makeSignpostID())
            await withTaskGroup(of: Void.self) { group in
                let from = DayFormat.shift(now, days: -(Self.historyDays - 1))
                group.addTask { try? await self.repository.refreshHistory(from: from, to: now, mode: .latest, userInitiated: true) }
                group.addTask { try? await self.repository.refreshUser(mode: .latest, userInitiated: true) }
                group.addTask { try? await self.repository.refreshTrend(.readiness, .week, mode: .latest, userInitiated: true) }
                group.addTask { try? await self.repository.refreshInsights(mode: .latest, userInitiated: true) }
            }
            signposts.endInterval("pull-rest", interval)
            await phase2.value
        }
        pullNow = phase2
        pullPhases = phases
        await Self.firstOf({ for await _ in settled {} }, { try? await clock.sleep(for: Self.spinnerCap) })
        signposts.endInterval("pull", spinner)
    }

    private func refreshToday(_ now: Date) async {
        _ = try? await repository.refreshDay(now, mode: .latest, userInitiated: true)
    }

    /// Whichever ends first; the other is cancelled.
    private static func firstOf(_ a: @escaping @Sendable () async -> Void, _ b: @escaping @Sendable () async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await a() }
            group.addTask { await b() }
            await group.next()
            group.cancelAll()
        }
    }

    /// Revalidates Today: the day, 90 days of scores, the user, the readiness week and the
    /// insights, each only when stale and each on its own (one failing leaves the others updated).
    /// `force` fetches regardless; `touched` (days a sync queued for rescoring) asks for data newer
    /// than now. Bootstrap, app active, the demo toggle, a rescore. Shows no error itself.
    func refresh(force: Bool = false, touched: [String] = []) async {
        guard hasDataSource else { return }
        // Offline: keep what's on screen (the cache); no request, no error.
        guard isDemo || env.connectivity.isOnline else { return }
        let now = now
        let todayKey = DayFormat.string(from: now)
        let days: ReadMode = !touched.isEmpty ? .changed(since: now) : force ? .latest : .ifStale
        let other: ReadMode = force ? .latest : .ifStale
        let from = DayFormat.shift(now, days: -(Self.historyDays - 1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await self.repository.refreshDay(now, mode: days) }
            group.addTask { try? await self.repository.refreshHistory(from: from, to: now, mode: days) }
            group.addTask { try? await self.repository.refreshUser(mode: other) }
            group.addTask { try? await self.repository.refreshTrend(.readiness, .week, mode: days) }
            group.addTask { try? await self.repository.refreshInsights(mode: days) }
            for key in Set(touched) where key != todayKey {
                guard let date = DayFormat.date(from: key) else { continue }
                group.addTask { _ = try? await self.repository.refreshDay(date, mode: .changed(since: now)) }
            }
        }
    }

    /// After a sync (or a silent push): today, the touched days and the 90-day scores, newer than
    /// now, each on its own. A failed read is recorded per resource and never thrown; only a
    /// cancellation is (the coordinator then reports idle).
    func refreshDays(_ touched: [String]) async throws {
        guard hasDataSource else { return }
        let now = now
        let since = ReadMode.changed(since: now)
        let todayKey = DayFormat.string(from: now)
        let from = DayFormat.shift(now, days: -(Self.historyDays - 1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await self.repository.refreshDay(now, mode: since) }
            for key in Set(touched) where key != todayKey {
                guard let date = DayFormat.date(from: key) else { continue }
                group.addTask { _ = try? await self.repository.refreshDay(date, mode: since) }
            }
            group.addTask { try? await self.repository.refreshHistory(from: from, to: now, mode: since) }
        }
        try Task.checkCancellation()
    }

    // MARK: staleness and the error card

    /// What the read pipeline knows per resource. Today's `fetchedAt` is the current day's row's
    /// (exact across midnight and relaunches); history's is the later of the record's and the
    /// store's newest past score, so a cache from before the record isn't "never loaded".
    /// Two SwiftData fetches: for Sync details and `readsChanged`, never in Today's `body`.
    var resourceStates: [ReadResource: ResourceState] {
        _ = env.reads.revision                  // Sync details re-renders when the record changes
        var states = env.reads.states
        states[.today, default: ResourceState()].fetchedAt = repository.detailFetchedAt(todayKey)
        if let stored = repository.newestPastScoreFetchedAt(before: todayKey) {
            let recorded = states[.history]?.fetchedAt
            states[.history, default: ResourceState()].fetchedAt = max(recorded ?? stored, stored)
        }
        return states
    }

    private var readsOnline: Bool { isDemo || env.connectivity.isOnline }

    /// The calm card on Today, or nil (`RefreshPolicy.issue`).
    var refreshIssue: RefreshIssue? {
        guard hasDataSource else { return nil }
        return RefreshPolicy.issue(for: refreshInputs, now: now, online: readsOnline)
    }

    /// "Showing data from 14:05" on the status line, or nil (`RefreshPolicy.staleSince`).
    var staleSince: Date? {
        guard hasDataSource else { return nil }
        return RefreshPolicy.staleSince(for: refreshInputs, now: now, online: readsOnline)
    }

    /// Forget what's shown (account changed, demo mode switched): reads in flight stop, their
    /// record goes. Sign-out wipes the account's store; demo data is cleared here.
    func reset() {
        pullNow?.cancel()
        pullPhases?.cancel()
        env.reads.reset()
        if isDemo { repository.clear() } else { repository.invalidate() }
        readsChanged(.record)
    }

    /// Signed out, signed in, or another account (`auth.accountID` changed from `old`). Leaving an
    /// account forgets its screens; every change, a sign-in after an expired session included,
    /// gives the read record to the account now signed in (never what failed while signed out).
    func accountChanged(from old: String?) {
        if old != nil { reset() } else { env.reads.reset() }
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

// MARK: - refresh issues

/// Why Today shows the calm error card (ui.md §3): one resource, what failed, since when.
struct RefreshIssue: Equatable, Sendable {
    /// ui.md §3.3 classes. busy: 429/5xx/408 after retries; unreachable: no response; unexpected: `other`.
    enum Reason: Equatable, Sendable { case busy, unreachable, unexpected, signedOut, appTooOld }
    let reason: Reason
    let resource: ReadResource
    /// "Showing data from 14:05"; nil: nothing cached.
    let dataFrom: Date?
    let failures: Int
    let error: ResourceError

    static func reason(for error: ResourceError) -> Reason {
        switch error.kind {
        case .signedOut: return .signedOut
        case .appTooOld: return .appTooOld
        case .transient: return error.status == nil ? .unreachable : .busy
        case .gate, .cancelled, .other: return .unexpected
        }
    }

    /// "Today", "History": what failed, as the Details sheet names it.
    var resourceName: String { resource.displayName ?? resource.rawValue }

    /// "503", or nil without a response.
    var statusText: String? { error.status.map(String.init) }

    /// The Details sheet's rows as plain text (Copy details): what failed, status, code, request ID,
    /// time, data from, failed in a row. No health values.
    @MainActor var copyText: String {
        let none = "—"
        var rows = [
            String(localized: "What failed") + ": " + resourceName,
            String(localized: "HTTP status") + ": " + (statusText ?? "\(none) (\(error.transport ?? String(localized: "No response")))"),
            String(localized: "Code") + ": " + (error.code ?? none),
            String(localized: "Request ID") + ": " + (error.requestID ?? String(localized: "Not available")),
            String(localized: "Time") + ": " + error.at.ISO8601Format(),
            String(localized: "Showing data from") + ": " + (dataFrom?.ISO8601Format() ?? none),
            String(localized: "Failed in a row") + ": " + failures.formatted(),
        ]
        rows.append("RYFT \(AppInfo.version) · \(AppInfo.osVersion)")
        return rows.joined(separator: "\n")
    }
}

/// Whether a failed read shows at all (ADR 0001 §5): pure functions over the recorded states.
/// Under the thresholds a failure changes nothing on screen; offline is never an error.
enum RefreshPolicy {
    static let failuresBeforeIssue = 3

    /// The part of the record `issue` and `staleSince` read: today, history, and any resource whose
    /// last answer says the person can act (signed out, an outdated app). Other resources' reads
    /// change nothing here, so Today doesn't re-render for them.
    static func inputs(_ states: [ReadResource: ResourceState]) -> [ReadResource: ResourceState] {
        states.filter { resource, state in
            resource == .today || resource == .history
                || (state.consecutiveFailures >= 1 && (state.lastError?.kind == .signedOut || state.lastError?.kind == .appTooOld))
        }
    }
    /// What's on screen counts as stale after this long without a successful fetch.
    static let staleAfter: [ReadResource: TimeInterval] = [.today: 2 * 3600, .history: 24 * 3600]

    /// ui.md §2.1 line 7: today's data time, when today (or history) is older than its threshold and
    /// its last fetch failed. nil when offline, fresh, nothing is cached, or the last fetch succeeded.
    static func staleSince(for states: [ReadResource: ResourceState], now: Date, online: Bool) -> Date? {
        guard online, let today = states[.today]?.fetchedAt else { return nil }
        if isStale(.today, states, now: now, minimumFailures: 1) || isStale(.history, states, now: now, minimumFailures: 1) {
            return today
        }
        return nil
    }

    /// ui.md §3.1, in order: offline → nil; signed out (or an outdated app) → that; gates → nil (the
    /// "Action needed" line owns them); today, then history: 3 failures in a row and older than its
    /// threshold, or (nothing cached at all) 1 failure. Other resources never show the card.
    static func issue(for states: [ReadResource: ResourceState], now: Date, online: Bool) -> RefreshIssue? {
        guard online else { return nil }
        for resource in ReadResource.allCases {
            guard let s = states[resource], let error = s.lastError, s.consecutiveFailures >= 1,
                  error.kind == .signedOut || error.kind == .appTooOld else { continue }
            return make(resource, s, error)
        }
        let nothingCached = states[.today]?.fetchedAt == nil && states[.history]?.fetchedAt == nil
        for resource in [ReadResource.today, .history] {
            guard let s = states[resource], let error = s.lastError, error.kind != .gate, error.kind != .cancelled
            else { continue }
            if isStale(resource, states, now: now, minimumFailures: failuresBeforeIssue)
                || (nothingCached && s.consecutiveFailures >= 1) {
                return make(resource, s, error)
            }
        }
        return nil
    }

    /// `minimumFailures` in a row, and no data or data older than the resource's threshold.
    private static func isStale(_ resource: ReadResource, _ states: [ReadResource: ResourceState], now: Date,
                                minimumFailures: Int) -> Bool {
        guard let s = states[resource], s.consecutiveFailures >= minimumFailures,
              let threshold = staleAfter[resource] else { return false }
        guard let fetchedAt = s.fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) > threshold
    }

    private static func make(_ resource: ReadResource, _ s: ResourceState, _ error: ResourceError) -> RefreshIssue {
        RefreshIssue(reason: RefreshIssue.reason(for: error), resource: resource, dataFrom: s.fetchedAt,
                     failures: s.consecutiveFailures, error: error)
    }
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
