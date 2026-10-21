import Foundation
import Observation
import SwiftData
import WidgetKit

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
            // Today must be fresh; past days need a score fetched after they ended. A cache
            // with no past day never had the history: only today, cached by a screen's own
            // load (Strain, Sleep) before this ran, as the demo's instant answers always do.
            let todayFresh = rows.first { $0.day == todayKey }.map { isFresh(day: $0.day, fetchedAt: $0.scoreFetchedAt) } ?? false
            let past = rows.filter { $0.day != todayKey }
            let pastFresh = past.allSatisfy { isFresh(day: $0.day, fetchedAt: $0.scoreFetchedAt) }
            if todayFresh, pastFresh, !past.isEmpty { return }
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

    /// After a write of `kinds`: saved, their decoded values dropped, their readers told.
    private func changed(_ kinds: Kind...) {
        store.save()
        forget(kinds)
    }

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
        let snapshot = ReadinessSnapshot.make(day: DayFormat.string(from: now), presentation: .decide(widgetFacts),
                                              now: now, bedtime: tonightBedtime)
        if ReadinessSnapshot.publish(snapshot, to: file) { reloadWidget() }
    }

    /// The facts Today decides from (`TodayViewModel.facts.scores`), read from the store: today's
    /// row, `GET /v1/me/sync`'s word when it's about today, and the same history window.
    var widgetFacts: TodayScoreFacts {
        let key = DayFormat.string(from: now)
        let today = score(key)
        return TodayScoreFacts(day: key, today: today,
                               scoringState: todayStatus?.day == key ? todayStatus?.state : today?.scoringState,
                               prior: history(from: DayFormat.shift(now, days: -(AppState.historyDays - 1)), to: now)
                                   .filter { $0.day < key })
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

    /// Today's gauge as `TodayPresentation.decide` picked it, in the widget's kinds (the JSON is
    /// unchanged): today's readiness; a night pending or awaited, or another day's readiness,
    /// dimmed; the baselines; `nil` with nothing scored at all.
    static func make(day: String, presentation p: TodayPresentation, now: Date,
                     bedtime: Date? = nil) -> ReadinessSnapshot? {
        var s = ReadinessSnapshot(day: day, kind: .waitingForSleep, readiness: nil, previousReadiness: nil,
                                  baselineNights: nil, updatedAt: now, bedtime: bedtime.flatMap { $0 > now ? $0 : nil })
        switch p.gauge {
        case .readiness(let readiness?) where !p.tiles.isEarlierDay:
            s.kind = .score
            s.readiness = readiness
        case .readiness(let readiness):
            // Row D from an earlier day (the widget has no note), or no readiness: the last one, dimmed.
            s.previousReadiness = readiness
        case .baselines(let nights):
            s.kind = .calibrating
            s.baselineNights = nights
        case .pending(let night):
            s.kind = night.waitingForSleep ? .waitingForSleep : .pending
            s.previousReadiness = night.previousReadiness.map { Int($0.rounded()) }
        case .firstImport:
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
