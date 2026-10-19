import Foundation
import Observation
import SwiftData

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
    /// Bumped on every write; reads touch it so views re-render when the store changes.
    private(set) var revision = 0
    /// Decoded values for the current revision (decoding JSON on every read would add up).
    @ObservationIgnored private var memo: [String: Any] = [:]

    /// Longest range the history query returns (no full-table loads).
    static let maxHistoryRows = 400

    init(env: AppEnvironment, store: Persistence? = nil, policy: Policy = Policy()) {
        self.env = env
        liveStore = store ?? env.persistence
        self.policy = policy
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

    private func memoized<T>(_ key: String, _ make: () -> T) -> T {
        _ = revision
        // Look the key up first: a missing entry cast `as? T` with an Optional `T`
        // "succeeds" as `.some(nil)` and would hide the value.
        if let entry = memo[key], let hit = entry as? T { return hit }
        let value = make()
        memo[key] = value
        return value
    }

    private func dayRow(_ key: String) -> CachedDay? {
        var d = FetchDescriptor<CachedDay>(predicate: #Predicate { $0.day == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    func day(_ key: String) -> DayDetail? {
        memoized("day.\(key)") { WireCoding.decode(DayDetail.self, dayRow(key)?.detailData) }
    }

    /// The day's score: from its detail when opened (newer), else from the history list.
    func score(_ key: String) -> DailyScore? {
        memoized("score.\(key)") {
            let row = dayRow(key)
            return WireCoding.decode(DayDetail.self, row?.detailData)?.score
                ?? WireCoding.decode(DailyScore.self, row?.scoreData)
        }
    }

    /// Scored days in `[from, to]`, oldest first.
    func history(from: Date, to: Date) -> [DailyScore] {
        let lo = calendar.startOfDay(for: from), hi = calendar.startOfDay(for: to)
        return memoized("history.\(DayFormat.string(from: lo)).\(DayFormat.string(from: hi))") {
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
        return memoized("trend.\(key)") {
            var d = FetchDescriptor<CachedTrend>(predicate: #Predicate { $0.key == key })
            d.fetchLimit = 1
            return WireCoding.decode(TrendSeries.self, (try? context.fetch(d))?.first?.data)
        }
    }

    func insights() -> [Insight] {
        memoized("insights") {
            var d = FetchDescriptor<CachedInsight>(sortBy: [SortDescriptor(\.position)])
            d.fetchLimit = 50
            return ((try? context.fetch(d)) ?? []).compactMap { WireCoding.decode(Insight.self, $0.data) }
        }
    }

    func user() -> User? {
        memoized("user") {
            var d = FetchDescriptor<CachedUser>(sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)])
            d.fetchLimit = 1
            return WireCoding.decode(User.self, (try? context.fetch(d))?.first?.data)
        }
    }

    func sleepRange(_ kind: SleepRangeKind) -> SleepRange? {
        let k = kind.rawValue
        return memoized("sleep.\(k)") {
            var d = FetchDescriptor<CachedSleepRange>(predicate: #Predicate { $0.kind == k })
            d.fetchLimit = 1
            return WireCoding.decode(SleepRange.self, (try? context.fetch(d))?.first?.data)
        }
    }

    func workout(_ id: UUID) -> WorkoutDetail? {
        memoized("workout.\(id)") {
            var d = FetchDescriptor<CachedWorkout>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            return WireCoding.decode(WorkoutDetail.self, (try? context.fetch(d))?.first?.data)
        }
    }

    /// When the day's detail was last fetched ("Updated 07:15").
    func detailFetchedAt(_ key: String) -> Date? {
        _ = revision
        return dayRow(key)?.detailFetchedAt
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

    /// Runs `fetch` unless offline; drops the answer if the account changed meanwhile.
    private func fetching<T>(_ fetch: () async throws -> T) async throws -> T? {
        guard canFetch else { return nil }
        let account = env.auth.accountID
        let value = try await fetch()
        guard env.auth.accountID == account else { return nil }
        return value
    }

    /// The day's detail: cached and fresh → no request. A failure with a cached
    /// copy keeps the copy (offline browsing); without one it throws.
    @discardableResult
    func refreshDay(_ date: Date, force: Bool = false) async throws -> DayDetail? {
        let key = DayFormat.string(from: date)
        if !force, isDetailFresh(key) { return day(key) }
        do {
            guard let d = try await fetching({ try await env.api.day(date) }) else { return day(key) }
            store(detail: d)
            return d
        } catch {
            if let cached = day(key) { return cached }
            throw error
        }
    }

    /// Scores for `[from, to]`: skipped when every day in the range is cached and fresh.
    func refreshHistory(from: Date, to: Date, force: Bool = false) async throws {
        if !force {
            let lo = calendar.startOfDay(for: from), hi = calendar.startOfDay(for: to)
            var d = FetchDescriptor<CachedDay>(predicate: #Predicate { $0.date >= lo && $0.date <= hi })
            d.fetchLimit = Self.maxHistoryRows
            let rows = (try? context.fetch(d)) ?? []
            let todayKey = DayFormat.string(from: now)
            // Today must be fresh; past days need a score fetched after they ended.
            let todayFresh = rows.first { $0.day == todayKey }.map { isFresh(day: $0.day, fetchedAt: $0.scoreFetchedAt) } ?? false
            let pastFresh = rows.filter { $0.day != todayKey }.allSatisfy { isFresh(day: $0.day, fetchedAt: $0.scoreFetchedAt) }
            if todayFresh, pastFresh, !rows.isEmpty { return }
        }
        guard let scores = try await fetching({ try await env.api.days(from: from, to: to) }) else { return }
        store(scores: scores)
    }

    func refreshTrend(_ metric: TrendMetric, _ range: TrendRange, force: Bool = false) async throws {
        let key = Self.trendKey(metric, range)
        if !force {
            var d = FetchDescriptor<CachedTrend>(predicate: #Predicate { $0.key == key })
            d.fetchLimit = 1
            if fresh((try? context.fetch(d))?.first?.fetchedAt, ttl: policy.trend) { return }
        }
        guard let s = try await fetching({ try await env.api.trends(metric: metric, range: range) }) else { return }
        store(trend: s, metric: metric, range: range)
    }

    func refreshInsights(force: Bool = false) async throws {
        if !force {
            var d = FetchDescriptor<CachedInsight>()
            d.fetchLimit = 1
            if let row = (try? context.fetch(d))?.first, fresh(row.fetchedAt, ttl: policy.insights) { return }
        }
        guard let list = try await fetching({ try await env.api.insights() }) else { return }
        store(insights: list)
    }

    func refreshUser(force: Bool = false) async throws {
        if !force {
            var d = FetchDescriptor<CachedUser>()
            d.fetchLimit = 1
            if fresh((try? context.fetch(d))?.first?.fetchedAt, ttl: policy.user) { return }
        }
        guard let u = try await fetching({ try await env.api.me() }) else { return }
        store(user: u)
    }

    func refreshSleepRange(_ kind: SleepRangeKind, force: Bool = false) async throws {
        let k = kind.rawValue
        if !force {
            var d = FetchDescriptor<CachedSleepRange>(predicate: #Predicate { $0.kind == k })
            d.fetchLimit = 1
            if fresh((try? context.fetch(d))?.first?.fetchedAt, ttl: policy.sleepRange) { return }
        }
        guard let r = try await fetching({ try await env.api.sleep(range: kind) }) else { return }
        store(sleepRange: r)
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

    private func changed() {
        store.save()
        memo = [:]
        revision += 1
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
        changed()
    }

    func store(scores: [DailyScore]) {
        for s in scores {
            let r = row(for: s.day)
            r.scoreData = WireCoding.encode(s)
            r.scoreFetchedAt = now
        }
        changed()
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
        changed()
    }

    /// Replaces the cards (the platform's list is the whole truth).
    func store(insights: [Insight]) {
        try? context.delete(model: CachedInsight.self)
        for (i, insight) in insights.enumerated() {
            guard let data = WireCoding.encode(insight) else { continue }
            context.insert(CachedInsight(id: insight.id, position: i, data: data, fetchedAt: now))
        }
        changed()
    }

    func store(user: User) {
        guard let data = WireCoding.encode(user) else { return }
        try? context.delete(model: CachedUser.self)
        context.insert(CachedUser(id: user.id, data: data, fetchedAt: now))
        changed()
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
        changed()
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
        changed()
    }

    /// Every cached series refetches the next time it's shown (new scores came in).
    func markTrendsStale() {
        var d = FetchDescriptor<CachedTrend>()
        d.fetchLimit = 500
        for row in (try? context.fetch(d)) ?? [] { row.fetchedAt = .distantPast }
        changed()
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
        changed()
        return removed
    }

    /// The store changed underneath (sign-out wiped it): forget decoded values.
    func invalidate() {
        memo = [:]
        revision += 1
    }

    /// Every read model (demo toggle; sign-out wipes the whole store via `Persistence.wipe`).
    func clear() {
        try? context.delete(model: CachedDay.self)
        try? context.delete(model: CachedTrend.self)
        try? context.delete(model: CachedInsight.self)
        try? context.delete(model: CachedUser.self)
        try? context.delete(model: CachedSleepRange.self)
        try? context.delete(model: CachedWorkout.self)
        changed()
    }

    /// Runs `body` against the account's store, whatever the Demo data switch says.
    func writingToAccountStore(_ body: () -> Void) {
        forceLive = true
        defer { forceLive = false; memo = [:]; revision += 1 }
        body()
    }

    static func trendKey(_ metric: TrendMetric, _ range: TrendRange) -> String {
        "\(metric.rawValue)-\(range.rawValue)"
    }
}
