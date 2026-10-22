import Foundation
import Observation
import SwiftData
import WidgetKit
import os

/// Offline-first access to the platform's read models.
///
/// Reads come from SwiftData only and never wait for the network. Refreshes
/// fetch from the API and write to the store:
/// - **Cache-first.** Something cached and fresh: no request.
/// - **Stale-while-revalidate.** Cached but stale: the stale copy stays readable
///   while the new one loads.
/// - **TTLs per entity** (`Policy`): today 5 min, past days 24 h, trends 1 h.
///   Browsing history never asks again for a day that is cached and fresh.
///
/// Offline nothing is requested. A response that arrives after the account
/// changed is dropped. Demo data lives in its own in-memory store, so it never
/// mixes with an account's.
@MainActor
@Observable
final class Repository {
    struct Policy {
        var today: TimeInterval = 5 * 60
        var pastDay: TimeInterval = 24 * 3600
        var trend: TimeInterval = 3600
        var insights: TimeInterval = 5 * 60
        var user: TimeInterval = 3600
        var sleepRange: TimeInterval = 3600
        var workout: TimeInterval = 24 * 3600
    }

    let policy: Policy
    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let liveStore: Persistence
    @ObservationIgnored private var demoStoreInstance: TrainStore?
    /// Set while importing the legacy cache: writes go to the account's store even in demo mode.
    @ObservationIgnored private var forceLive = false
    /// What a write changes. Each kind has its own revision and memo entries, so a
    /// trends write neither re-decodes the days nor re-renders a view that only shows days.
    enum Kind: String, CaseIterable {
        case days, trends, insights, user, sleep, workouts
    }

    // One observed revision per kind; reads touch theirs, writes bump theirs.
    private(set) var daysRevision = 0
    private(set) var trendsRevision = 0
    private(set) var insightsRevision = 0
    private(set) var userRevision = 0
    private(set) var sleepRevision = 0
    private(set) var workoutsRevision = 0

    /// Every write so far, of any kind.
    var revision: Int {
        daysRevision + trendsRevision + insightsRevision + userRevision + sleepRevision + workoutsRevision
    }

    /// Decoded values per kind (decoding JSON on every read would add up), until that kind changes.
    @ObservationIgnored private var memo: [String: Any] = [:]
    /// JSON decodes behind the memo (tests and the perf notes count them).
    @ObservationIgnored private(set) var decodes = 0

    /// Longest range the history query returns (no full-table loads).
    static let maxHistoryRows = 400

    init(env: AppEnvironment, store: Persistence? = nil, policy: Policy = Policy()) {
        self.env = env
        liveStore = store ?? env.persistence
        self.policy = policy
        widgetFile = env.sharesWithWidget ? ReadinessSnapshot.sharedFile : nil
    }

    private var store: Persistence {
        guard env.isDemo, !forceLive else { return liveStore }
        if let s = demoStoreInstance { return s }
        let s = TrainStore(inMemory: true)
        demoStoreInstance = s
        return s
    }

    private var context: ModelContext { store.context }
    private var now: Date { env.clock.now() }
    private var calendar: Calendar { .current }
    private var canFetch: Bool { env.isDemo || env.connectivity.isOnline }

    // MARK: reads

    private func memoized<T>(_ kind: Kind, _ key: String, _ make: () -> T) -> T {
        touch(kind)
        let key = "\(kind.rawValue).\(key)"
        // Look the key up first: a missing entry cast `as? T` with an Optional `T`
        // "succeeds" as `.some(nil)` and would hide the value.
        if let entry = memo[key], let hit = entry as? T { return hit }
        decodes += 1
        let value = make()
        memo[key] = value
        return value
    }

    /// Makes the caller depend on `kind` (SwiftUI re-renders it when that kind changes).
    private func touch(_ kind: Kind) {
        switch kind {
        case .days: _ = daysRevision
        case .trends: _ = trendsRevision
        case .insights: _ = insightsRevision
        case .user: _ = userRevision
        case .sleep: _ = sleepRevision
        case .workouts: _ = workoutsRevision
        }
    }

    private func dayRow(_ key: String) -> CachedDay? {
        var d = FetchDescriptor<CachedDay>(predicate: #Predicate { $0.day == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    func day(_ key: String) -> DayDetail? {
        memoized(.days, "day.\(key)") { WireCoding.decode(DayDetail.self, dayRow(key)?.detailData) }
    }

    /// The day's score: from its detail when opened (newer), else from the history list.
    func score(_ key: String) -> DailyScore? {
        memoized(.days, "score.\(key)") {
            let row = dayRow(key)
            return WireCoding.decode(DayDetail.self, row?.detailData)?.score
                ?? WireCoding.decode(DailyScore.self, row?.scoreData)
        }
    }

    /// Scored days in `[from, to]`, oldest first.
    func history(from: Date, to: Date) -> [DailyScore] {
        let lo = calendar.startOfDay(for: from), hi = calendar.startOfDay(for: to)
        return memoized(.days, "history.\(DayFormat.string(from: lo)).\(DayFormat.string(from: hi))") {
            var d = FetchDescriptor<CachedDay>(predicate: #Predicate { $0.date >= lo && $0.date <= hi },
                                               sortBy: [SortDescriptor(\.date)])
            d.fetchLimit = Self.maxHistoryRows
            return ((try? context.fetch(d)) ?? []).compactMap { row in
                WireCoding.decode(DayDetail.self, row.detailData)?.score ?? WireCoding.decode(DailyScore.self, row.scoreData)
            }
        }
    }

    func trend(_ metric: TrendMetric, _ range: TrendRange) -> TrendSeries? {
        let key = Self.trendKey(metric, range)
        return memoized(.trends, key) {
            var d = FetchDescriptor<CachedTrend>(predicate: #Predicate { $0.key == key })
            d.fetchLimit = 1
            return WireCoding.decode(TrendSeries.self, (try? context.fetch(d))?.first?.data)
        }
    }

    func insights() -> [Insight] {
        memoized(.insights, "all") {
            var d = FetchDescriptor<CachedInsight>(sortBy: [SortDescriptor(\.position)])
            d.fetchLimit = 50
            return ((try? context.fetch(d)) ?? []).compactMap { WireCoding.decode(Insight.self, $0.data) }
        }
    }

    func user() -> User? {
        memoized(.user, "current") {
            var d = FetchDescriptor<CachedUser>(sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)])
            d.fetchLimit = 1
            return WireCoding.decode(User.self, (try? context.fetch(d))?.first?.data)
        }
    }

    func sleepRange(_ kind: SleepRangeKind) -> SleepRange? {
        let k = kind.rawValue
        return memoized(.sleep, k) {
            var d = FetchDescriptor<CachedSleepRange>(predicate: #Predicate { $0.kind == k })
            d.fetchLimit = 1
            return WireCoding.decode(SleepRange.self, (try? context.fetch(d))?.first?.data)
        }
    }

    func workout(_ id: UUID) -> WorkoutDetail? {
        memoized(.workouts, id.uuidString) {
            var d = FetchDescriptor<CachedWorkout>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            return WireCoding.decode(WorkoutDetail.self, (try? context.fetch(d))?.first?.data)
        }
    }

    /// When the day's detail was last fetched ("Updated 07:15").
    func detailFetchedAt(_ key: String) -> Date? {
        touch(.days)
        return dayRow(key)?.detailFetchedAt
    }

    /// When the newest past day's score in the store was fetched: the history's age, also for a
    /// cache older than the read record (the first launch of a build with `ReadScheduler`). Today's
    /// row is left out, so a fresh today can't hide a history that keeps failing.
    func newestPastScoreFetchedAt(before todayKey: String) -> Date? {
        touch(.days)
        var d = FetchDescriptor<CachedDay>(predicate: #Predicate { $0.day != todayKey && $0.scoreFetchedAt != nil },
                                           sortBy: [SortDescriptor(\.scoreFetchedAt, order: .reverse)])
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.scoreFetchedAt
    }

    // MARK: freshness

    private func fresh(_ fetchedAt: Date?, ttl: TimeInterval) -> Bool {
        guard let fetchedAt else { return false }
        return now.timeIntervalSince(fetchedAt) < ttl
    }

    /// Today: 5 min. A past day: 24 h, and only if it was fetched after it ended
    /// (a copy taken while it was still "today" is as stale as today's).
    func isFresh(day key: String, fetchedAt: Date?) -> Bool {
        guard let fetchedAt, let date = DayFormat.date(from: key) else { return false }
        let today = DayFormat.string(from: now)
        if key == today { return fresh(fetchedAt, ttl: policy.today) }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        if fetchedAt < end { return fresh(fetchedAt, ttl: policy.today) }
        return fresh(fetchedAt, ttl: policy.pastDay)
    }

    func isDetailFresh(_ key: String) -> Bool { isFresh(day: key, fetchedAt: dayRow(key)?.detailFetchedAt) }

    // MARK: refresh (network → store)

    /// Runs `fetch` unless offline; drops the answer if the account changed meanwhile. For reads the
    /// pipeline doesn't schedule yet (a workout's detail).
    private func fetching<T>(_ fetch: () async throws -> T) async throws -> T? {
        guard canFetch else { return nil }
        let account = env.auth.accountID
        let value = try await fetch()
        guard env.auth.accountID == account else { return nil }
        return value
    }

    /// `fetch` through the read pipeline (`env.reads`): coalesced, retried, budgeted and recorded per
    /// resource; offline nothing is sent. `store` runs inside the flight, once, whoever started or
    /// joined it and even if this caller is cancelled; an answer for an account that's gone
    /// meanwhile is dropped unwritten.
    private func scheduled<T: Sendable>(_ key: ReadKey, mode: ReadMode, userInitiated: Bool,
                                        fetch: @escaping @MainActor () async throws -> T,
                                        store: @escaping @MainActor (T) -> Void) async throws -> T? {
        try await env.reads.run(key, mode: mode, userInitiated: userInitiated, store: store, fetch)
    }

    /// The day's detail: cached and fresh → no request (`.ifStale`). A failure with a cached
    /// copy keeps the copy (offline browsing); without one it throws.
    @discardableResult
    func refreshDay(_ date: Date, mode: ReadMode = .ifStale, userInitiated: Bool = false) async throws -> DayDetail? {
        let key = DayFormat.string(from: date)
        if mode == .ifStale, isDetailFresh(key) { return day(key) }
        let resource: ReadResource = key == DayFormat.string(from: now) ? .today : .day
        do {
            let fetched = try await scheduled(ReadKey(resource, id: key), mode: mode, userInitiated: userInitiated,
                                              fetch: { [env] in try await env.api.day(date) },
                                              store: { [weak self] in self?.store(detail: $0) })
            return fetched ?? day(key)
        } catch {
            if let cached = day(key) { return cached }
            throw error
        }
    }

    @discardableResult
    func refreshDay(_ date: Date, force: Bool) async throws -> DayDetail? {
        try await refreshDay(date, mode: force ? .latest : .ifStale)
    }

    /// Scores for `[from, to]`: skipped (`.ifStale`) when every day in the range is cached and fresh.
    func refreshHistory(from: Date, to: Date, mode: ReadMode = .ifStale, userInitiated: Bool = false) async throws {
        if mode == .ifStale {
            let lo = calendar.startOfDay(for: from), hi = calendar.startOfDay(for: to)
            var d = FetchDescriptor<CachedDay>(predicate: #Predicate { $0.date >= lo && $0.date <= hi })
            d.fetchLimit = Self.maxHistoryRows
            let rows = (try? context.fetch(d)) ?? []
            let todayKey = DayFormat.string(from: now)
            // Today must be fresh; past days need a score fetched after they ended. A cache
            // with no past day never had the history: only today, cached by a screen's own
            // load (Strain, Sleep) before this ran, as the demo's instant answers always do.
            let todayFresh = rows.first { $0.day == todayKey }.map { isFresh(day: $0.day, fetchedAt: $0.scoreFetchedAt) } ?? false
            let past = rows.filter { $0.day != todayKey }
            let pastFresh = past.allSatisfy { isFresh(day: $0.day, fetchedAt: $0.scoreFetchedAt) }
            if todayFresh, pastFresh, !past.isEmpty { return }
        }
        let id = "\(DayFormat.string(from: from))…\(DayFormat.string(from: to))"
        _ = try await scheduled(ReadKey(.history, id: id), mode: mode, userInitiated: userInitiated,
                                fetch: { [env] in try await env.api.days(from: from, to: to) },
                                store: { [weak self] in self?.store(scores: $0) })
    }

    func refreshHistory(from: Date, to: Date, force: Bool) async throws {
        try await refreshHistory(from: from, to: to, mode: force ? .latest : .ifStale)
    }

    func refreshTrend(_ metric: TrendMetric, _ range: TrendRange, mode: ReadMode = .ifStale,
                      userInitiated: Bool = false) async throws {
        let key = Self.trendKey(metric, range)
        if mode == .ifStale {
            var d = FetchDescriptor<CachedTrend>(predicate: #Predicate { $0.key == key })
            d.fetchLimit = 1
            if fresh((try? context.fetch(d))?.first?.fetchedAt, ttl: policy.trend) { return }
        }
        _ = try await scheduled(ReadKey(.trends, id: key), mode: mode, userInitiated: userInitiated,
                                fetch: { [env] in try await env.api.trends(metric: metric, range: range) },
                                store: { [weak self] in self?.store(trend: $0, metric: metric, range: range) })
    }

    func refreshTrend(_ metric: TrendMetric, _ range: TrendRange, force: Bool) async throws {
        try await refreshTrend(metric, range, mode: force ? .latest : .ifStale)
    }

    func refreshInsights(mode: ReadMode = .ifStale, userInitiated: Bool = false) async throws {
        if mode == .ifStale {
            var d = FetchDescriptor<CachedInsight>()
            d.fetchLimit = 1
            if let row = (try? context.fetch(d))?.first, fresh(row.fetchedAt, ttl: policy.insights) { return }
        }
        _ = try await scheduled(ReadKey(.insights), mode: mode, userInitiated: userInitiated,
                                fetch: { [env] in try await env.api.insights() },
                                store: { [weak self] in self?.store(insights: $0) })
    }

    func refreshInsights(force: Bool) async throws {
        try await refreshInsights(mode: force ? .latest : .ifStale)
    }

    func refreshUser(mode: ReadMode = .ifStale, userInitiated: Bool = false) async throws {
        if mode == .ifStale {
            var d = FetchDescriptor<CachedUser>()
            d.fetchLimit = 1
            if fresh((try? context.fetch(d))?.first?.fetchedAt, ttl: policy.user) { return }
        }
        _ = try await scheduled(ReadKey(.me), mode: mode, userInitiated: userInitiated,
                                fetch: { [env] in try await env.api.me() },
                                store: { [weak self] in self?.store(user: $0) })
    }

    func refreshUser(force: Bool) async throws {
        try await refreshUser(mode: force ? .latest : .ifStale)
    }

    func refreshSleepRange(_ kind: SleepRangeKind, mode: ReadMode = .ifStale) async throws {
        let k = kind.rawValue
        if mode == .ifStale {
            var d = FetchDescriptor<CachedSleepRange>(predicate: #Predicate { $0.kind == k })
            d.fetchLimit = 1
            if fresh((try? context.fetch(d))?.first?.fetchedAt, ttl: policy.sleepRange) { return }
        }
        _ = try await scheduled(ReadKey(.sleepRange, id: k), mode: mode, userInitiated: false,
                                fetch: { [env] in try await env.api.sleep(range: kind) },
                                store: { [weak self] in self?.store(sleepRange: $0) })
    }

    func refreshSleepRange(_ kind: SleepRangeKind, force: Bool) async throws {
        try await refreshSleepRange(kind, mode: force ? .latest : .ifStale)
    }

    func refreshWorkout(_ id: UUID, force: Bool = false) async throws {
        if !force {
            var d = FetchDescriptor<CachedWorkout>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            if fresh((try? context.fetch(d))?.first?.fetchedAt, ttl: policy.workout) { return }
        }
        guard let w = try await fetching({ try await env.api.workout(id: id) }) else { return }
        store(workout: w)
    }

    // MARK: writes

    /// After a write of `kinds`: saved, their decoded values dropped, their readers told.
    private func changed(_ kinds: Kind...) {
        store.save()
        forget(kinds)
    }

    /// The days changed (a score or a day's detail stored, the cache cleared): AppState recomputes
    /// what Today's card and stale line read from them.
    @ObservationIgnored var onDaysChanged: (() -> Void)?

    private func forget(_ kinds: [Kind]) {
        for kind in kinds {
            let prefix = kind.rawValue + "."
            memo = memo.filter { !$0.key.hasPrefix(prefix) }
            switch kind {
            case .days: daysRevision += 1
            case .trends: trendsRevision += 1
            case .insights: insightsRevision += 1
            case .user: userRevision += 1
            case .sleep: sleepRevision += 1
            case .workouts: workoutsRevision += 1
            }
        }
        if kinds.contains(.days) { onDaysChanged?() }
    }

    private func row(for key: String) -> CachedDay {
        if let row = dayRow(key) { return row }
        let row = CachedDay(day: key, date: DayFormat.date(from: key) ?? now)
        context.insert(row)
        return row
    }

    func store(detail: DayDetail) {
        let r = row(for: detail.score.day)
        r.detailData = WireCoding.encode(detail)
        r.detailFetchedAt = now
        r.scoreData = WireCoding.encode(detail.score)
        r.scoreFetchedAt = now
        changed(.days)
        publishWidget()
    }

    func store(scores: [DailyScore]) {
        for s in scores {
            let r = row(for: s.day)
            r.scoreData = WireCoding.encode(s)
            r.scoreFetchedAt = now
        }
        changed(.days)
        publishWidget()
    }

    // MARK: widget

    /// Today's scoring state from `GET /v1/me/sync` (AppState sets it): fresher than the
    /// cached score's while a night is being scored.
    var todayStatus: TodayState? {
        didSet { if todayStatus != oldValue { publishWidget() } }
    }

    /// Tonight's bedtime from Bedtime & wake (`BedtimePlanner`): "Bed by 22:41" on the widget
    /// in the evening.
    var tonightBedtime: Date? {
        didSet { if tonightBedtime != oldValue { publishWidget() } }
    }

    /// Where the readiness widget reads from; tests point it elsewhere. `nil` without the
    /// App Group capability: nothing is written.
    @ObservationIgnored var widgetFile: URL?
    @ObservationIgnored var reloadWidget: () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: ReadinessSnapshot.widgetKind) }

    /// What Today shows, for the home- and lock-screen widget: written when it changed, and
    /// only then is the widget reloaded (a new score, a night pending, the next day).
    func publishWidget() {
        guard let file = widgetFile else { return }
        let key = DayFormat.string(from: now)
        let previous = history(from: DayFormat.shift(now, days: -7), to: DayFormat.shift(now, days: -1))
            .last { $0.readiness != nil }
        let state = todayStatus?.day == key ? todayStatus?.state : score(key)?.scoringState
        let snapshot = ReadinessSnapshot.make(day: key, today: score(key), previous: previous, state: state, now: now,
                                              bedtime: tonightBedtime)
        if ReadinessSnapshot.publish(snapshot, to: file) { reloadWidget() }
    }

    /// The cached scores become exactly `scores` (previews, tests); opened details stay.
    func replaceScores(_ scores: [DailyScore]) {
        let keep = Set(scores.map(\.day))
        var d = FetchDescriptor<CachedDay>()
        d.fetchLimit = 10_000
        for row in (try? context.fetch(d)) ?? [] where !keep.contains(row.day) {
            if row.detailData == nil { context.delete(row) } else { row.scoreData = nil }
        }
        store(scores: scores)
    }

    func store(trend: TrendSeries, metric: TrendMetric, range: TrendRange) {
        guard let data = WireCoding.encode(trend) else { return }
        let key = Self.trendKey(metric, range)
        var d = FetchDescriptor<CachedTrend>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        if let row = (try? context.fetch(d))?.first {
            row.data = data
            row.fetchedAt = now
        } else {
            context.insert(CachedTrend(key: key, data: data, fetchedAt: now))
        }
        changed(.trends)
    }

    /// Replaces the cards (the platform's list is the whole truth).
    func store(insights: [Insight]) {
        try? context.delete(model: CachedInsight.self)
        for (i, insight) in insights.enumerated() {
            guard let data = WireCoding.encode(insight) else { continue }
            context.insert(CachedInsight(id: insight.id, position: i, data: data, fetchedAt: now))
        }
        changed(.insights)
    }

    func store(user: User) {
        guard let data = WireCoding.encode(user) else { return }
        try? context.delete(model: CachedUser.self)
        context.insert(CachedUser(id: user.id, data: data, fetchedAt: now))
        changed(.user)
    }

    func store(sleepRange: SleepRange) {
        guard let data = WireCoding.encode(sleepRange) else { return }
        let k = sleepRange.range
        var d = FetchDescriptor<CachedSleepRange>(predicate: #Predicate { $0.kind == k })
        d.fetchLimit = 1
        if let row = (try? context.fetch(d))?.first {
            row.data = data
            row.fetchedAt = now
        } else {
            context.insert(CachedSleepRange(kind: k, data: data, fetchedAt: now))
        }
        changed(.sleep)
    }

    func store(workout: WorkoutDetail) {
        guard let data = WireCoding.encode(workout) else { return }
        let id = workout.workout.id
        var d = FetchDescriptor<CachedWorkout>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        if let row = (try? context.fetch(d))?.first {
            row.data = data
            row.fetchedAt = now
        } else {
            context.insert(CachedWorkout(id: id, data: data, fetchedAt: now))
        }
        changed(.workouts)
    }

    /// Every cached series refetches the next time it's shown (new scores came in).
    func markTrendsStale() {
        var d = FetchDescriptor<CachedTrend>()
        d.fetchLimit = 500
        for row in (try? context.fetch(d)) ?? [] { row.fetchedAt = .distantPast }
        changed(.trends)
    }

    /// Nightly (`BGProcessingTask`): days beyond a year, workouts and Train
    /// documents nobody opened for 30 days, series older than a week. What's
    /// gone is fetched again when needed.
    @discardableResult
    func compact() -> Int {
        let cutoffDay = calendar.startOfDay(for: DayFormat.shift(now, days: -365))
        let month = now.addingTimeInterval(-30 * 86_400)
        let week = now.addingTimeInterval(-7 * 86_400)
        var removed = 0
        func count<T: PersistentModel>(_ d: FetchDescriptor<T>) -> Int { (try? context.fetchCount(d)) ?? 0 }
        let oldDays = FetchDescriptor<CachedDay>(predicate: #Predicate { $0.date < cutoffDay })
        removed += count(oldDays)
        try? context.delete(model: CachedDay.self, where: #Predicate { $0.date < cutoffDay })
        let oldWorkouts = FetchDescriptor<CachedWorkout>(predicate: #Predicate { $0.fetchedAt < month })
        removed += count(oldWorkouts)
        try? context.delete(model: CachedWorkout.self, where: #Predicate { $0.fetchedAt < month })
        let oldTrends = FetchDescriptor<CachedTrend>(predicate: #Predicate { $0.fetchedAt < week })
        removed += count(oldTrends)
        try? context.delete(model: CachedTrend.self, where: #Predicate { $0.fetchedAt < week })
        let prefix = "train.history."
        let oldDocs = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key.starts(with: prefix) && $0.fetchedAt < month })
        removed += count(oldDocs)
        try? context.delete(model: CachedDocument.self, where: #Predicate { $0.key.starts(with: prefix) && $0.fetchedAt < month })
        changed(.days, .trends, .workouts)
        return removed
    }

    /// The store changed underneath (sign-out wiped it): forget decoded values.
    func invalidate() {
        forget(Kind.allCases)
    }

    /// Every read model (demo toggle; sign-out wipes the whole store via `Persistence.wipe`).
    func clear() {
        try? context.delete(model: CachedDay.self)
        try? context.delete(model: CachedTrend.self)
        try? context.delete(model: CachedInsight.self)
        try? context.delete(model: CachedUser.self)
        try? context.delete(model: CachedSleepRange.self)
        try? context.delete(model: CachedWorkout.self)
        changed(.days, .trends, .insights, .user, .sleep, .workouts)
    }

    /// Runs `body` against the account's store, whatever the Demo data switch says.
    func writingToAccountStore(_ body: () -> Void) {
        forceLive = true
        defer { forceLive = false; forget(Kind.allCases) }
        body()
    }

    static func trendKey(_ metric: TrendMetric, _ range: TrendRange) -> String {
        "\(metric.rawValue)-\(range.rawValue)"
    }
}

// MARK: - widget snapshot

/// What the readiness widget shows, written into the App Group container by the app.
/// Keep identical to `RyftWidgets/ReadinessSnapshot.swift`: the widget decodes this JSON.
struct ReadinessSnapshot: Codable, Equatable {
    enum Kind: String, Codable {
        /// Today's readiness.
        case score
        /// The night is being scored.
        case pending
        /// No night has arrived for today.
        case waitingForSleep
        /// Fewer than 7 nights behind the baselines.
        case calibrating
    }

    /// The day it's about, `yyyy-MM-dd`; another day on the widget is "waiting for sleep".
    var day: String
    var kind: Kind
    var readiness: Int?
    /// The latest readiness before `day`, dimmed while the night isn't scored.
    var previousReadiness: Int?
    /// While calibrating.
    var baselineNights: Int?
    var updatedAt: Date
    /// Tonight's bedtime (Bedtime & wake): "Bed by 22:41" in the evening.
    var bedtime: Date?

    static let appGroup = "group.dev.timkrebs.ryft"
    static let widgetKind = "ReadinessWidget"

    static var sharedFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("readiness.json")
    }

    /// Today's state as Today decides it (`TodayStates.hero`): a score; else a night pending
    /// or awaited; else the baselines; `nil` with nothing to show at all.
    static func make(day: String, today: DailyScore?, previous: DailyScore?, state: ScoringState?,
                     now: Date, bedtime: Date? = nil) -> ReadinessSnapshot? {
        var s = ReadinessSnapshot(day: day, kind: .waitingForSleep, readiness: nil,
                                  previousReadiness: previous?.readiness, baselineNights: nil, updatedAt: now,
                                  bedtime: bedtime.flatMap { $0 > now ? $0 : nil })
        if let readiness = today?.readiness {
            s.kind = .score
            s.readiness = readiness
        } else if state == .pending {
            s.kind = .pending
        } else if state == .waitingForSleep {
            s.kind = .waitingForSleep
        } else if let today, today.calibrating {
            s.kind = .calibrating
            s.baselineNights = today.baselineDays
        } else if today == nil, previous == nil {
            return nil
        }
        return s
    }

    /// Writes `snapshot` (or removes the file for `nil`) when what it shows changed; `true`
    /// when it did, so the caller reloads the widget.
    @discardableResult
    static func publish(_ snapshot: ReadinessSnapshot?, to file: URL) -> Bool {
        let current = (try? Data(contentsOf: file)).flatMap { try? decoder.decode(ReadinessSnapshot.self, from: $0) }
        guard current?.shown != snapshot?.shown else { return false }
        guard let snapshot else {
            try? FileManager.default.removeItem(at: file)
            return true
        }
        guard let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: file, options: .atomic)) != nil
    }

    /// Sign-out: the next account's readiness, or none, never this one's on the lock screen.
    static func clear() {
        guard let file = sharedFile, publish(nil, to: file) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Everything but `updatedAt`.
    private var shown: [String?] {
        [day, kind.rawValue, readiness.map(String.init), previousReadiness.map(String.init), baselineNights.map(String.init),
         bedtime.map { String($0.timeIntervalSince1970) }]
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - read pipeline

/// What the app reads from the platform, as the read pipeline (`ReadScheduler`) tracks it.
enum ReadResource: String, Codable, CaseIterable, Sendable {
    case today        // GET /v1/days/{today}
    case day          // GET /v1/days/{day}, a past day (Sleep, Strain, touched days)
    case history      // GET /v1/days?from&to (AppState.historyDays)
    case me           // GET /v1/me
    case syncStatus   // GET /v1/me/sync
    case trends       // GET /v1/trends (Today's readiness week, Insights' series)
    case insights     // GET /v1/insights
    case journal      // GET /v1/behaviors, /v1/journal/{day}, /v1/behaviors/impact
    case config       // GET /v1/config
    case train        // TrainLibrary: exercises, plans, plans/today
    case sleepRange   // GET /v1/sleep

    var priority: RequestBudget.Priority { self == .today || self == .syncStatus ? .high : .normal }

    /// Sync details → Loaded data; nil for `day` and `sleepRange`, which appear in Copy diagnostics only.
    var displayName: String? {
        switch self {
        case .today: return String(localized: "Today")
        case .history: return String(localized: "History")
        case .me: return String(localized: "Profile")
        case .syncStatus: return String(localized: "Sync status")
        case .trends: return String(localized: "Trends")
        case .insights: return String(localized: "Insights")
        case .journal: return String(localized: "Journal")
        case .config: return String(localized: "Remote settings")
        case .train: return String(localized: "Train")
        case .day, .sleepRange: return nil
        }
    }
}

/// One request's identity for coalescing: `ReadKey(.trends, id: "readiness-7d")`, `ReadKey(.day, id: "2026-10-19")`.
struct ReadKey: Hashable, Sendable {
    let resource: ReadResource
    var id = ""

    init(_ resource: ReadResource, id: String = "") {
        self.resource = resource
        self.id = id
    }
}

/// How fresh the caller needs it.
enum ReadMode: Equatable, Sendable {
    /// `Repository.Policy` TTLs: nothing is sent while fresh.
    case ifStale
    /// Pull to refresh: fetch now, or join a fetch already in flight.
    case latest
    /// The server's data changed at `since` (scores landed, a push): only a fetch started at or after
    /// `since` counts; an older one in flight gets one shared follow-up.
    case changed(since: Date)
}

/// A read's last failure, after its retries. No health values: statuses, codes, IDs and times.
struct ResourceError: Codable, Equatable, Sendable {
    let kind: FailureKind
    /// HTTP status; nil without a response.
    let status: Int?
    /// The error body's `code` as sent.
    let code: String?
    /// Exactly as received.
    let requestID: String?
    /// `URLError` code name ("timedOut") when there was no response.
    let transport: String?
    /// 1 + retries.
    let attempts: Int
    /// The last failed attempt.
    let at: Date

    /// Persisted through `WireCoding` (snake_case both ways): `requestID` must round-trip as `request_id`.
    private enum CodingKeys: String, CodingKey {
        case kind, status, code, requestID = "requestId", transport, attempts, at
    }

    init(kind: FailureKind, status: Int?, code: String?, requestID: String?, transport: String?, attempts: Int,
         at: Date) {
        self.kind = kind
        self.status = status
        self.code = code
        self.requestID = requestID
        self.transport = transport
        self.attempts = attempts
        self.at = at
    }

    init(_ error: Error, kind: FailureKind, attempts: Int, at: Date) {
        let api = error as? APIError
        var transport: String?
        if case .transport(let inner)? = api { transport = (inner as? URLError)?.code.name ?? "transport" }
        if let url = error as? URLError { transport = url.code.name }
        self.init(kind: kind, status: api?.status, code: api?.code?.rawValue, requestID: api?.requestID,
                  transport: transport, attempts: attempts, at: at)
    }

    /// "503", "timedOut", or the kind: what the status column shows.
    var statusText: String { status.map(String.init) ?? transport ?? kind.rawValue }
}

/// What the read pipeline knows about one resource.
struct ResourceState: Codable, Equatable, Sendable {
    /// The last successful fetch. AppState's snapshot replaces it for `.today` with the row's
    /// `detailFetchedAt` (exact for the current day, also across midnight).
    var fetchedAt: Date?
    var lastError: ResourceError?
    /// Failed fetches in a row, after retries. A success resets it. Cancellation and gates never count.
    var consecutiveFailures = 0
    /// Retry-After beyond what a refresh waits: automatic refreshes send nothing before this.
    var retryNotBefore: Date?

    init(fetchedAt: Date? = nil, lastError: ResourceError? = nil, consecutiveFailures: Int = 0,
         retryNotBefore: Date? = nil) {
        self.fetchedAt = fetchedAt
        self.lastError = lastError
        self.consecutiveFailures = consecutiveFailures
        self.retryNotBefore = retryNotBefore
    }

    /// Copy diagnostics (`resource | fetched_at | last_error status code request_id at | consecutive_failures`):
    /// "today | 2026-10-21T14:05:12Z | 503 - 01a14ffa-… 2026-10-21T16:11:02Z | 3". Never a health value.
    func diagnosticLine(_ resource: ReadResource) -> String {
        let fetched = fetchedAt.map { $0.ISO8601Format() } ?? "-"
        let error = lastError.map { e in
            "\(e.statusText) \(e.code ?? "-") \(e.requestID ?? "-") \(e.at.ISO8601Format())"
        } ?? "-"
        return "\(resource.rawValue) | \(fetched) | \(error) | \(consecutiveFailures)"
    }
}

/// The one retry layer for reads (ADR 0001), one per `AppEnvironment` (`env.reads`):
///
/// - **Coalesces** by `ReadKey`: a second read of a key in flight joins it (`ReadMode`).
/// - **Retries** transient failures (`FailureKind`) by `RetryPolicy` (foreground, or background
///   while `APIClient.runsInBackground`), honouring `Retry-After` up to the cap. `APIClient` makes
///   one attempt per try (`singleAttempt`), so no request sees two retry layers.
/// - **Budgets** every try through `RequestBudget` (3 in flight, 5 starts a second), releasing
///   the slot during a backoff.
/// - **Records** per resource: last success, last error, failures in a row (`ResourceState`),
///   persisted for the signed-in account (`CachedDocument` "reads.state", with its account ID).
/// - **Owns** each fetch in an unstructured task. Every caller waits through its own continuation:
///   a caller's cancellation (`.refreshable`, `.task(id:)`, a deadline) releases that caller at once
///   with `CancellationError`, while the fetch goes on for the others and stores its answer
///   (the flight's `store`, whoever started it). Only `cancelAll()` stops a fetch.
///
/// Offline or signed out (not demo) nothing is sent and nothing is recorded. Cancellation is never
/// a failure.
@MainActor
@Observable
final class ReadScheduler {
    /// Not observed: every read changes these (a journal's, config's or Train's too). Screens read
    /// what they need through `onChange` (AppState's stored summary) or `revision` (Sync details).
    @ObservationIgnored private(set) var states: [ReadResource: ResourceState] = [:]
    @ObservationIgnored private(set) var inFlight: Set<ReadKey> = []
    /// Bumped when the record changes (a read landed, a reset): what Sync details observes.
    private(set) var revision = 0
    /// What changed: `.inFlight` when a read started, `.record` when one landed or the record was
    /// replaced. AppState recomputes Today's inputs from it.
    enum Change { case inFlight, record }
    @ObservationIgnored var onChange: ((Change) -> Void)?
    /// The record waits this long for more changes before it's saved: one save per pull, not six.
    static let persistDelay: Duration = .milliseconds(1500)
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// Jitter source; tests set a fixed one.
    @ObservationIgnored var random: @Sendable (ClosedRange<Double>) -> Double = { .random(in: $0) }
    /// Admission for every try; tests may swap in their own limits.
    @ObservationIgnored var budget: RequestBudget

    /// Nothing was sent: offline, or the platform asked to wait longer than a refresh waits.
    struct NotSent: Error {}

    static let documentKey = "reads.state"
    /// `Retry-After` beyond the policy's cap holds automatic refreshes back for at most this long.
    static let maxHoldBack: TimeInterval = 300

    /// Weak: the environment owns its scheduler.
    @ObservationIgnored private weak var env: AppEnvironment?
    @ObservationIgnored private let clock: AppClock
    @ObservationIgnored private var flights: [ReadKey: Flight] = [:]
    /// Bumped by `cancelAll()`: a follow-up queued before it doesn't start after it.
    @ObservationIgnored private var generation = 0

    /// A result many callers wait for. Each waiter has its own continuation: its cancellation
    /// releases only that waiter (`CancellationError`); the work behind it goes on.
    @MainActor
    private final class Outcome {
        private var result: Result<(any Sendable)?, Error>?
        private var waiters: [UUID: CheckedContinuation<(any Sendable)?, Error>] = [:]

        func value() async throws -> (any Sendable)? {
            if let result { return try result.get() }
            let id = UUID()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if let result {
                        continuation.resume(with: result)
                    } else if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiters[id] = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor in self.release(id) }
            }
        }

        /// The first result wins; every waiter gets it.
        func resolve(_ result: Result<(any Sendable)?, Error>) {
            guard self.result == nil else { return }
            self.result = result
            let pending = waiters
            waiters = [:]
            for continuation in pending.values { continuation.resume(with: result) }
        }

        private func release(_ id: UUID) {
            waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }
    }

    /// Writes an answer into the read models; any caller's, since every store for one key is the same.
    typealias Store = @MainActor (any Sendable) -> Void

    @MainActor
    private final class Flight {
        let id = UUID()
        let started: Date
        let outcome = Outcome()
        var task: Task<Void, Never>?
        /// Run once on success, whoever started or joined the flight (the first store given wins).
        var store: Store?
        /// One shared rerun for `.changed` callers that need data newer than this flight, and its store.
        var followUp: Outcome?
        var followUpStore: Store?

        init(started: Date) {
            self.started = started
        }
    }

    /// What's persisted: the record and whose it is (a mismatch on load is ignored).
    private struct Saved: Codable {
        let account: String
        let states: [String: ResourceState]
    }

    init(env: AppEnvironment) {
        self.env = env
        clock = env.clock
        budget = RequestBudget(clock: env.clock)
        states = load()
    }

    /// Runs `fetch` for `key`, or joins the fetch in flight (see `ReadMode`). Offline or signed out
    /// (not demo): nothing is sent, returns nil, nothing is recorded. Retries per `RetryPolicy`
    /// (`.background` while `APIClient.runsInBackground`). Records the outcome for `key.resource`;
    /// `store` writes the answer inside the flight, so it lands even if this caller is cancelled or
    /// joined a flight another caller started without one. Throws the last error when it failed,
    /// `CancellationError` when this caller (or the flight) was cancelled. `userInitiated` (pull,
    /// Try again) ignores `retryNotBefore`.
    @discardableResult
    func run<T: Sendable>(_ key: ReadKey, mode: ReadMode = .latest, userInitiated: Bool = false,
                          store: (@MainActor (T) -> Void)? = nil,
                          _ fetch: @escaping @MainActor () async throws -> T) async throws -> T? {
        // Cancelled already (a screen that went away, a deadline that passed): no flight for it.
        try Task.checkCancellation()
        guard let outcome = enter(key, mode: mode, userInitiated: userInitiated, store: Self.erase(store), fetch) else {
            return nil
        }
        return try await outcome.value() as? T
    }

    /// Cancels every read in flight (sign-out, account change): their callers are released with
    /// `CancellationError`, nothing is recorded or stored for them.
    func cancelAll() {
        generation += 1
        let stopped = Array(flights.values)
        flights = [:]
        inFlight = []
        for flight in stopped {
            flight.task?.cancel()
            flight.outcome.resolve(.failure(CancellationError()))
            flight.followUp?.resolve(.failure(CancellationError()))
        }
        changed(.record)
    }

    /// Another account, a sign-in or demo data: reads in flight stop, and what's known is the
    /// signed-in account's own record (none for demo data). A save still pending is the old one's.
    func reset() {
        pendingSave?.cancel()
        pendingSave = nil
        cancelAll()
        states = load()
        changed(.record)
    }

    /// Replaces what's known (previews, tests); nothing is sent or persisted.
    func seed(_ states: [ReadResource: ResourceState]) {
        self.states = states
        changed(.record)
    }

    private func changed(_ change: Change) {
        if change == .record { revision += 1 }
        onChange?(change)
    }

    /// Copy diagnostics: one line per resource, no health values.
    var diagnosticLines: [String] {
        ReadResource.allCases.map { (states[$0] ?? ResourceState()).diagnosticLine($0) }
    }

    // MARK: flights

    /// The outcome to wait on: the flight for `key` (joined), its follow-up, or a new flight; nil
    /// when nothing is sent (offline, signed out, held back). No await: two callers can't both start one.
    private func enter<T: Sendable>(_ key: ReadKey, mode: ReadMode, userInitiated: Bool, store: Store?,
                                    _ fetch: @escaping @MainActor () async throws -> T) -> Outcome? {
        guard let env, env.isDemo || (env.connectivity.isOnline && env.auth.accountID != nil) else { return nil }
        if !userInitiated, let notBefore = states[key.resource]?.retryNotBefore, clock.now() < notBefore { return nil }
        if let flight = flights[key] {
            if case .changed(let since) = mode, flight.started < since {
                if flight.followUpStore == nil { flight.followUpStore = store }
                return flight.followUp ?? followUp(after: flight, key, userInitiated: userInitiated, fetch)
            }
            if flight.store == nil { flight.store = store }
            return flight.outcome
        }
        return start(key, store: store, fetch).outcome
    }

    private func start<T: Sendable>(_ key: ReadKey, store: Store?,
                                    _ fetch: @escaping @MainActor () async throws -> T) -> Flight {
        let flight = Flight(started: clock.now())
        flight.store = store
        let account = env?.auth.accountID
        flights[key] = flight
        inFlight.insert(key)
        changed(.inFlight)
        // Inherits the task-locals (`runsInBackground`); never detached.
        flight.task = Task { [weak self] in
            let result: Result<(any Sendable)?, Error>
            do {
                guard let self else { throw CancellationError() }
                let value = try await self.attempts(key, account: account, fetch)
                // `attempts` checked the account and cancellation; no await since.
                if let store = flight.store {
                    let signposts = Signposts.reads
                    let interval = signposts.beginInterval("store", id: signposts.makeSignpostID(),
                                                           "\(key.resource.rawValue, privacy: .public)")
                    store(value)
                    signposts.endInterval("store", interval)
                }
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            self?.landed(key, flight.id)
            flight.outcome.resolve(result)
        }
        return flight
    }

    /// One shared rerun after `flight`, for `.changed` callers that need data newer than it.
    private func followUp<T: Sendable>(after flight: Flight, _ key: ReadKey, userInitiated: Bool,
                                       _ fetch: @escaping @MainActor () async throws -> T) -> Outcome {
        let outcome = Outcome()
        flight.followUp = outcome
        let generation = generation
        Task { [weak self] in
            _ = try? await flight.outcome.value()
            guard let self, self.generation == generation else {
                outcome.resolve(.failure(CancellationError()))
                return
            }
            guard let next = self.enter(key, mode: .latest, userInitiated: userInitiated, store: flight.followUpStore, fetch)
            else {
                outcome.resolve(.success(nil))
                return
            }
            do {
                outcome.resolve(.success(try await next.value()))
            } catch {
                outcome.resolve(.failure(error))
            }
        }
        return outcome
    }

    private func landed(_ key: ReadKey, _ id: UUID) {
        guard flights[key]?.id == id else { return }
        flights[key] = nil
        inFlight.remove(key)
        changed(.record)
    }

    private static func erase<T: Sendable>(_ store: (@MainActor (T) -> Void)?) -> Store? {
        guard let store else { return nil }
        return { value in if let value = value as? T { store(value) } }
    }

    /// The tries for one flight: single attempts through the budget, backoff between them.
    private func attempts<T: Sendable>(_ key: ReadKey, account: String?,
                                       _ fetch: @escaping @MainActor () async throws -> T) async throws -> T {
        let policy: RetryPolicy = APIClient.runsInBackground ? .background : .foreground
        var attempt = 0
        while true {
            try Task.checkCancellation()
            // Instruments: how long a try queued for the budget, and how long its request took.
            let signposts = Signposts.reads
            let queued = signposts.beginInterval("budget", id: signposts.makeSignpostID(),
                                                 "\(key.resource.rawValue, privacy: .public)")
            do {
                try await budget.acquire(key.resource.priority, maxHold: policy.retryAfterCap)
            } catch let held as RequestBudget.HeldBack {
                signposts.endInterval("budget", queued)
                guard env?.auth.accountID == account, !Task.isCancelled else { throw CancellationError() }
                // The rate limit holds every start back longer than this read may wait: it fails as the
                // 429 behind the hold would (the busy card, `retryNotBefore` for automatic reads).
                let error = APIError.http(429, "", retryAfter: held.seconds)
                failed(key.resource, error, kind: .transient, attempts: attempt + 1, cap: policy.retryAfterCap)
                throw error
            } catch {
                signposts.endInterval("budget", queued)
                throw error
            }
            signposts.endInterval("budget", queued)
            let request = signposts.beginInterval("fetch", id: signposts.makeSignpostID(),
                                                  "\(key.resource.rawValue, privacy: .public) try \(attempt + 1)")
            let outcome: Result<T, Error>
            do {
                outcome = .success(try await APIClient.$singleAttempt.withValue(true) { try await fetch() })
            } catch {
                outcome = .failure(error)
            }
            signposts.endInterval("fetch", request)
            // The rate limits are per user and per IP, not per resource: a 429 holds every start back,
            // set together with this slot's release so a parked read can't slip through.
            var holdBack: Int?
            if case .failure(let error) = outcome, (error as? APIError)?.status == 429 {
                holdBack = RetryPolicy.retryAfter(error) ?? 1
            }
            await budget.release(holdBack: holdBack)
            // Signed out or another account meanwhile: the answer isn't theirs, and neither is its outcome.
            // Stopped by `cancelAll()` (a reset): nothing is recorded or stored.
            guard env?.auth.accountID == account, !Task.isCancelled else { throw CancellationError() }
            switch outcome {
            case .success(let value):
                succeeded(key.resource)
                return value
            case .failure(let error):
                let kind = FailureKind.of(error)
                if kind == .cancelled || Task.isCancelled { throw CancellationError() }
                attempt += 1
                if let wait = policy.delay(before: attempt, after: error, random: random) {
                    // The slot is free while waiting; the retry takes a new one.
                    try await clock.sleep(for: wait)
                    continue
                }
                failed(key.resource, error, kind: kind, attempts: attempt, cap: policy.retryAfterCap)
                throw error
            }
        }
    }

    // MARK: outcomes

    private func succeeded(_ resource: ReadResource) {
        let now = clock.now()
        var s = states[resource] ?? ResourceState()
        // Today's and history's times live in their SwiftData rows (AppState.resourceStates): only a
        // change of failures is worth a save for them.
        let moved = !Self.storeOwnsFetchedAt.contains(resource)
            && (s.fetchedAt.map { now.timeIntervalSince($0) > 60 } ?? true)
        let changed = s.consecutiveFailures != 0 || s.retryNotBefore != nil
        s.fetchedAt = now
        s.consecutiveFailures = 0
        s.retryNotBefore = nil
        states[resource] = s
        if moved || changed { persist() }
    }

    private func failed(_ resource: ReadResource, _ error: Error, kind: FailureKind, attempts: Int, cap: Duration) {
        let now = clock.now()
        var s = states[resource] ?? ResourceState()
        s.lastError = ResourceError(error, kind: kind, attempts: attempts, at: now)
        if kind != .gate { s.consecutiveFailures += 1 }
        if let seconds = RetryPolicy.retryAfter(error), Duration.seconds(seconds) > cap {
            s.retryNotBefore = now.addingTimeInterval(min(TimeInterval(seconds), Self.maxHoldBack))
        }
        states[resource] = s
        persist()
    }

    /// Resources whose `fetchedAt` the store already keeps (`detailFetchedAt`, `scoreFetchedAt`).
    private static let storeOwnsFetchedAt: Set<ReadResource> = [.today, .history]

    /// The signed-in account's record survives a force-quit (a report sent afterwards still says
    /// what failed); demo data and a signed-out record never persist. One save per `persistDelay`
    /// (real time, not the app clock: it's housekeeping, not behaviour).
    private func persist() {
        guard let env, !env.isDemo, env.auth.accountID != nil, pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.persistDelay)
            guard !Task.isCancelled else { return }
            await self?.savePending()
        }
    }

    /// Saves the record now (the pending save fires this; tests call it). Encoded off the main actor.
    func savePending() async {
        pendingSave?.cancel()
        pendingSave = nil
        guard let env, !env.isDemo, let account = env.auth.accountID else { return }
        guard let data = await Self.encode(saved(account)), env.auth.accountID == account else { return }
        env.persistence.saveDocumentData(data, key: Self.documentKey, at: clock.now())
    }

    /// A save is waiting and the app may be suspended next (going to the background, the end of a
    /// silent push): it's written at once, on the main actor, with no await before it's done.
    func savePendingNow() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        guard let env, !env.isDemo, let account = env.auth.accountID else { return }
        env.persistence.saveDocument(saved(account), key: Self.documentKey, at: clock.now())
    }

    private func saved(_ account: String) -> Saved {
        Saved(account: account, states: Dictionary(uniqueKeysWithValues: states.map { ($0.key.rawValue, $0.value) }))
    }

    @concurrent
    private static func encode(_ saved: Saved) async -> Data? {
        WireCoding.encode(saved)
    }

    /// The signed-in account's own record; another account's (or an older format) is ignored. A
    /// "signed out" from before is over: whoever loads this is signed in again.
    private func load() -> [ReadResource: ResourceState] {
        guard let env, !env.isDemo, let account = env.auth.accountID,
              let saved = env.persistence.document(Saved.self, key: Self.documentKey), saved.account == account
        else { return [:] }
        var states: [ReadResource: ResourceState] = [:]
        for (key, value) in saved.states {
            guard let resource = ReadResource(rawValue: key) else { continue }
            var state = value
            if state.lastError?.kind == .signedOut {
                state.lastError = nil
                state.consecutiveFailures = 0
            }
            states[resource] = state
        }
        return states
    }
}
