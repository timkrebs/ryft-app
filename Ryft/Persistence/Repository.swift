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
/// - **No route at rest.** Activities are cached per day without `route` and
///   `hr_samples` (`store(activities:day:)`, ADR 0006).
///
/// Offline nothing is requested. A response that arrives after the account
/// changed is dropped. Demo data lives in its own in-memory store, so it never
/// mixes with an account's.
///
/// **Writes run off the main actor** (ADR 0018). A write is submitted as a value (`ReadModelWrite`) in the same
/// main-actor step that checked the account, and `ReadModelDrain` applies it in submit order on the store's writer. The
/// returned `WriteTicket` resolves at the commit: then the store has it, its kinds' memo entries are gone and their
/// revisions bumped once per batch, and reads go through a new read context. A refresh awaits its ticket, so it returns
/// with its rows readable. `.user` is written through: the memo takes it at submit, because the upload gate reads it
/// back in that step (ADR 0008). `seed` writes at once on the main actor, for previews, tests and the legacy import.
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
    /// What a write changes (`ReadModelKind`).
    typealias Kind = ReadModelKind

    /// The write queue and the stores' writers (ADR 0018).
    @ObservationIgnored private let drain: ReadModelDrain
    /// What the Repository reads through, one per store: a context of its own that nothing writes, replaced at every
    /// commit and at `invalidate()`, so no row it fetched before a write or a wipe survives them.
    @ObservationIgnored private var readContexts: [StoreID: ModelContext] = [:]
    /// `seed`s per store: the writer after one is a new one (it may hold rows the seed changed).
    @ObservationIgnored private var seeds: [StoreID: Int] = [:]
    /// The last user submitted (`store(user:)`, `seed`) and the store it went to, until `invalidate()`: the upload gate
    /// reads it back in the same step. Only reads of that store return it.
    @ObservationIgnored private var writtenThroughUser: (store: StoreID, user: User)?
    /// When this phone last changed the user (`store(user:asOf:)`: a `PATCH /v1/me` answer, the withdrawal). A
    /// `GET /v1/me` asked for before it may answer with the user from before the change (`store(fetchedUser:askedAt:)`).
    @ObservationIgnored private var lastUserChange: Date?
    /// The changes of the user stored so far (`noteUserChange()`), never reset: a `UserChange` taken before the last
    /// of them began before it (`store(user:asOf:)`). A count, not a time: two changes in one tick of the clock still
    /// differ.
    @ObservationIgnored private var userChanges = 0
    /// A refused save of the user went again (`committed`): a second refusal in a row isn't retried.
    @ObservationIgnored private var resubmittedUser = false
    /// A misuse Debug builds stop at (`seed` while writes are pending, a preview setter on the live graph); tests
    /// record it instead.
    @ObservationIgnored var onMisuse: (String) -> Void = { assertionFailure($0) }
    /// Tests watch and hold the writer through these.
    @ObservationIgnored var writeHooks = ReadModelDrain.Hooks() {
        didSet { drain.setHooks(writeHooks) }
    }

    // One observed revision per kind; reads touch theirs, writes bump theirs.
    private(set) var daysRevision = 0
    private(set) var trendsRevision = 0
    private(set) var insightsRevision = 0
    private(set) var userRevision = 0
    private(set) var sleepRevision = 0
    private(set) var workoutsRevision = 0
    private(set) var activitiesRevision = 0

    /// Every write so far, of any kind.
    var revision: Int {
        daysRevision + trendsRevision + insightsRevision + userRevision + sleepRevision + workoutsRevision
            + activitiesRevision
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
        let link = RepositoryLink()
        drain = ReadModelDrain { receipt, target, epoch in
            link.repository?.committed(receipt, store: target.store, current: target.epoch.current == epoch)
        }
        link.repository = self
    }

    private var store: Persistence {
        guard env.isDemo, !forceLive else { return liveStore }
        if let s = demoStoreInstance { return s }
        let s = TrainStore(inMemory: true)
        demoStoreInstance = s
        return s
    }

    /// The store reads and writes go to now (tests).
    var storeID: StoreID { store.epoch.store }

    /// The epoch of each store's cached writer (tests).
    func writerEpochs() async -> [StoreID: Int] { await drain.writerEpochs }

    /// The current store's read context (never written).
    private var context: ModelContext {
        let s = store
        let id = s.epoch.store
        if let c = readContexts[id] { return c }
        let c = ModelContext(s.container)
        c.autosaveEnabled = false
        readContexts[id] = c
        return c
    }

    private var now: Date { env.clock.now() }
    private var calendar: Calendar { .current }
    private var canFetch: Bool { env.isDemo || env.connectivity.isOnline }

    // MARK: reads

    /// `decoded: false` for a plain fetch (it isn't a JSON decode the counter is about).
    private func memoized<T>(_ kind: Kind, _ key: String, decoded: Bool = true, _ make: () -> T) -> T {
        touch(kind)
        let key = "\(kind.rawValue).\(key)"
        // Look the key up first: a missing entry cast `as? T` with an Optional `T`
        // "succeeds" as `.some(nil)` and would hide the value.
        if let entry = memo[key], let hit = entry as? T { return hit }
        if decoded { decodes += 1 }
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
        case .activities: _ = activitiesRevision
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
        if let written = writtenThroughUser, written.store == store.epoch.store {
            touch(.user)
            return written.user
        }
        return memoized(.user, "current") {
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

    /// The platform's activities that start on `day` (`yyyy-MM-dd`), oldest first, as last fetched; empty until
    /// then. Never with `route` or `hr_samples`.
    func activities(day: String) -> [SportActivity] {
        memoized(.activities, day) {
            WireCoding.decode([SportActivity].self, activitiesDocument(day)?.data) ?? []
        }
    }

    /// When `day`'s activities were last fetched; nil when they never were.
    func activitiesFetchedAt(day: String) -> Date? {
        memoized(.activities, "fetchedAt.\(day)", decoded: false) { activitiesDocument(day)?.fetchedAt }
    }

    /// `CachedDocument` key of `day`'s activities: "activities.2026-10-22".
    nonisolated static func activitiesKey(_ day: String) -> String { "\(activitiesPrefix)\(day)" }
    nonisolated static let activitiesPrefix = "activities."

    private func activitiesDocument(_ day: String) -> CachedDocument? {
        let key = Self.activitiesKey(day)
        var d = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// When the day's detail was last fetched ("Updated 07:15"). Today reads it on every body
    /// (`AppState.lastUpdated`): one SwiftData fetch per change of the days, not one per read.
    func detailFetchedAt(_ key: String) -> Date? {
        memoized(.days, "fetchedAt.\(key)", decoded: false) { dayRow(key)?.detailFetchedAt }
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
    /// meanwhile is dropped unwritten. It submits at once and awaits the commit, so the flight
    /// ends with its rows readable.
    private func scheduled<T: Sendable>(_ key: ReadKey, mode: ReadMode, userInitiated: Bool,
                                        fetch: @escaping @MainActor () async throws -> T,
                                        store: @escaping @MainActor (T) async -> Void) async throws -> T? {
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
                                              store: { [weak self] in await self?.store(detail: $0).committed() })
            // What the store has: the flight resolved for this account only (`ReadScheduler.start`). The answer
            // itself only if the store refused the save.
            return day(key) ?? fetched
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
                                store: { [weak self] in await self?.store(scores: $0).committed() })
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
                                store: { [weak self] in
                                    await self?.store(trend: $0, metric: metric, range: range).committed()
                                })
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
                                store: { [weak self] in await self?.store(insights: $0).committed() })
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
        _ = try await env.reads.run(ReadKey(.me), mode: mode, userInitiated: userInitiated,
                                    storeAsked: { [weak self] (user: User, asked: Date) in
                                        await self?.store(fetchedUser: user, askedAt: asked).committed()
                                    }, { [env] in try await env.api.me() })
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
                                store: { [weak self] in await self?.store(sleepRange: $0).committed() })
    }

    func refreshSleepRange(_ kind: SleepRangeKind, force: Bool) async throws {
        try await refreshSleepRange(kind, mode: force ? .latest : .ifStale)
    }

    /// `day`'s activities (`GET /v1/activities?from&to`, the local day): cached and fresh → no request
    /// (`.ifStale`; the day's TTLs: 5 min today, 24 h for a past day). A failure with a cached copy keeps the
    /// copy; without one it throws. Before the contract is published (`publishesActivities`) nothing is asked,
    /// recorded or budgeted: the cache is returned.
    @discardableResult
    func refreshActivities(_ day: String, mode: ReadMode = .ifStale, userInitiated: Bool = false) async throws
        -> [SportActivity] {
        guard let start = DayFormat.date(from: day) else { return [] }
        guard env.api.publishesActivities else { return activities(day: day) }
        if mode == .ifStale, isFresh(day: day, fetchedAt: activitiesFetchedAt(day: day)) { return activities(day: day) }
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        do {
            _ = try await scheduled(ReadKey(.activities, id: day), mode: mode, userInitiated: userInitiated,
                                    fetch: { [env] in try await env.api.activities(from: start, to: end) },
                                    store: { [weak self] in await self?.store(activities: $0, day: day).committed() })
            // What was stored (stripped), not the answer itself: no caller holds a route from a list read.
            return activities(day: day)
        } catch {
            if activitiesFetchedAt(day: day) != nil { return activities(day: day) }
            throw error
        }
    }

    func refreshWorkout(_ id: UUID, force: Bool = false) async throws {
        if !force {
            var d = FetchDescriptor<CachedWorkout>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            if fresh((try? context.fetch(d))?.first?.fetchedAt, ttl: policy.workout) { return }
        }
        guard let w = try await fetching({ try await env.api.workout(id: id) }) else { return }
        // `fetching` checked the account; no await since.
        await store(workout: w).committed()
    }

    // MARK: writes

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
            case .activities: activitiesRevision += 1
            }
        }
        if kinds.contains(.days) { onDaysChanged?() }
    }

    /// Queues `op` for the current store, at `epoch` (its current one when nil). Never awaits: the caller's account
    /// check and this are one step.
    private func submit(_ op: ReadModelWrite, at epoch: Int? = nil) -> WriteTicket {
        let s = store
        return drain.submit(op, to: ReadModelDrain.Target(container: s.container, epoch: s.epoch,
                                                          generation: seeds[s.epoch.store, default: 0]),
                            at: epoch, now: now)
    }

    /// A batch landed in `store` (the drain, on the main actor; `seed`): reads see it from here on. `current`: no wipe
    /// since its save (one after it deleted what it saved, and the widget isn't published from that).
    fileprivate func committed(_ receipt: WriteReceipt, store id: StoreID, current: Bool = true) {
        // A wipe came first: `invalidate()` already replaced the contexts and forgot everything.
        guard !receipt.dropped else { return }
        readContexts[id] = nil
        if receipt.kinds.contains(.user) { resubmitUserIfRefused(receipt, store: id, current: current) }
        let kinds = Kind.allCases.filter(receipt.kinds.contains)
        guard !kinds.isEmpty else { return }
        forget(kinds)
        if receipt.publishesWidget, current { publishWidget() }
    }

    /// A refused save of the user: the store keeps the one before it (a withdrawal's consent with it), and a relaunch
    /// would read that. The user written through is the newest, so it goes again, once; not after a wipe (`current`
    /// false), whose account it was.
    private func resubmitUserIfRefused(_ receipt: WriteReceipt, store id: StoreID, current: Bool) {
        guard !receipt.saved, current, !resubmittedUser, let written = writtenThroughUser, written.store == id,
              store.epoch.store == id else {
            resubmittedUser = false
            return
        }
        resubmittedUser = true
        _ = submit(.user(written.user))
    }

    /// Every write submitted so far has committed or was dropped.
    func settled() async {
        await drain.lastSubmitted?.committed()
    }

    /// The longest `settledBeforeCompletion()` waits: iOS may end the app's background time soon after.
    static let completionWait: Duration = .seconds(2)

    /// `settled()` before a system completion (a background task, a silent push, the app's background time): for at
    /// most `completionWait`, and not at all once the caller is cancelled (the system's time ran out). A write still
    /// pending lands when the app runs next.
    func settledBeforeCompletion() async {
        guard let last = drain.lastSubmitted else { return }
        let clock = env.clock, limit = Self.completionWait
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await last.committedUnlessCancelled() }
            group.addTask { try? await clock.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    /// `ops` written at once on a context of their own, then committed as one batch: previews, tests and the legacy
    /// import, never the app's own writes. Only while no write is pending (two contexts must not write one row).
    func seed(_ ops: ReadModelWrite...) {
        seed(ops)
    }

    func seed(_ ops: [ReadModelWrite]) {
        if !drain.isIdle { onMisuse("Repository.seed while read-model writes are pending: await settled() first") }
        let s = store
        let id = s.epoch.store
        let context = ModelContext(s.container)
        context.autosaveEnabled = false
        var receipt = WriteReceipt()
        let at = now
        for op in ops { ReadModelWrites.apply(op, in: context, now: at, into: &receipt) }
        do {
            try context.save()
            receipt.saved = true
        } catch {
            let e = error as NSError
            TrainStore.log.error("Read-model seed failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
        }
        // The writer may hold rows this context changed: the next write gets a new one.
        seeds[id, default: 0] += 1
        // The seeded user is the newest, written through as `store(user:)` writes it (a user written before is older);
        // a seeded clear leaves none.
        for op in ops {
            switch op {
            case .user(let user): writtenThroughUser = (id, user)
            case .clear: writtenThroughUser = nil
            default: break
            }
        }
        committed(receipt, store: id)
    }

    @discardableResult
    func store(detail: DayDetail) -> WriteTicket { submit(.detail(detail)) }

    @discardableResult
    func store(scores: [DailyScore]) -> WriteTicket { submit(.scores(scores)) }

    // MARK: widget

    /// Today's scoring state from `GET /v1/me/sync` (AppState sets it): fresher than the
    /// cached score's while a night is being scored.
    var todayStatus: TodayState? {
        didSet { if todayStatus != oldValue { publishWidget() } }
    }

    /// The phone's word about the days being scored, read from its one store (`SyncService.scoringLedger`;
    /// `LiveSyncSteps` connects it, and SyncService republishes the widget when it changes): today's adjusts
    /// `todayStatus` as on Today (`ScoringWord.state`). None in tests and previews that don't connect it.
    @ObservationIgnored var scoringLedger: @MainActor () -> [String: ScoringWord] = { [:] }

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

    /// The tracker ids chosen in the setup (`TrackerSelectionStore.trackers`; `ScreenModels` connects it). None in
    /// tests and previews that don't.
    @ObservationIgnored var chosenTrackers: @MainActor () -> [String] = { [] }

    /// The facts Today decides from (`TodayViewModel.facts.scores`), read from the store: today's
    /// row, `GET /v1/me/sync`'s word when it's about today, the same history window, and, for a row whose
    /// calibration note may name it, the tracker setup (a counter on the widget only where Today has one, F3).
    var widgetFacts: TodayScoreFacts {
        let key = DayFormat.string(from: now)
        let today = score(key)
        var facts = TodayScoreFacts(day: key, today: today,
                                    scoringState: ScoringWord.state(day: key, word: scoringLedger()[key], status: todayStatus,
                                                                    row: today),
                                    prior: history(from: DayFormat.shift(now, days: -(AppState.historyDays - 1)), to: now)
                                        .filter { $0.day < key })
        facts.devicesSetup = env.flags.isOn(.devicesSetup)
        if facts.devicesSetup, today?.calibrationNamesTracker == true {
            let ids = chosenTrackers()
            if !ids.isEmpty {
                let catalog = env.trackerCatalog
                facts.trackers = ids.compactMap(catalog.tracker)
            }
        }
        return facts
    }

    @discardableResult
    func store(trend: TrendSeries, metric: TrendMetric, range: TrendRange) -> WriteTicket {
        submit(.trend(trend, key: Self.trendKey(metric, range)))
    }

    /// Replaces the cards (the platform's list is the whole truth).
    @discardableResult
    func store(insights: [Insight]) -> WriteTicket { submit(.insights(insights)) }

    /// Written through (ADR 0018 decision 5): `user()` returns it from this step on, before the commit, because the
    /// upload gate decides from it in the same step (ADR 0008). A commit never replaces it; `invalidate()` does.
    @discardableResult
    func store(user: User) -> WriteTicket {
        writtenThroughUser = (store.epoch.store, user)
        forget([.user])
        return submit(.user(user))
    }

    /// Where this phone's own change of the user began, before its request's first await: whose it was, what the
    /// store held then, and how many changes of the user were stored before it (`userChange()`, `store(user:asOf:)`).
    struct UserChange: Sendable {
        fileprivate let binding: AccountBinding
        fileprivate let store: StoreID
        fileprivate let epoch: Int
        fileprivate let began: Int
    }

    /// Taken before a request that changes the user (`PATCH /v1/me`, the withdrawal): its answer is stored `asOf` it.
    func userChange() -> UserChange {
        let s = store
        return UserChange(binding: AccountBinding(env), store: s.epoch.store, epoch: s.epoch.current, began: userChanges)
    }

    /// The change is stored: a `GET /v1/me` asked for before now (`lastUserChange`) and a change begun before it
    /// (`userChanges`) may answer with the user from before it.
    private func noteUserChange() {
        userChanges += 1
        lastUserChange = now
    }

    /// The change for `change` is current: the same account, Demo data switch position and store contents. Demo data
    /// switched on and off again while the request was out passes (the same account's store, its epoch unchanged).
    private func isCurrent(_ change: UserChange) -> Bool {
        let s = store
        return change.binding.isCurrent(in: env) && change.store == s.epoch.store && change.epoch == s.epoch.current
    }

    /// The platform's answer to this phone's change of the user, begun at `change`: written through as `store(user:)`
    /// writes it, and newer than any `GET /v1/me` asked for before now (`store(fetchedUser:askedAt:)`). Dropped, unwritten:
    /// - when the account, demo data or the store's contents changed since `change` (`isCurrent`): a sign-out (another
    ///   account) while the request was out makes the answer someone else's;
    /// - when another change of the user was stored since `change` began (the withdrawal, another `PATCH`): the platform
    ///   may have read the user before that one, a withdrawn consent with it. It's no change of its own then (a `/v1/me`
    ///   asked after the newer one still counts), and the user is asked again, so what the request changed shows.
    @discardableResult
    func store(user: User, asOf change: UserChange) -> WriteTicket {
        guard isCurrent(change) else { return .dropped }
        guard change.began == userChanges else {
            let since = now
            Task { [weak self] in try? await self?.refreshUser(mode: .changed(since: since)) }
            return .dropped
        }
        noteUserChange()
        writtenThroughUser = (change.store, user)
        forget([.user])
        return submit(.user(user), at: change.epoch)
    }

    /// The withdrawal (`DELETE /v1/me/consent` answered), begun at `change`: the user as this phone has it, without the
    /// consent, written through, so every upload gate closes in this step (ADR 0008). A change of the user of its own:
    /// an answer begun or asked for before it is dropped (`store(user:asOf:)`, `store(fetchedUser:askedAt:)`). Dropped
    /// when the account, demo data or the store changed since `change`; with no user cached, nothing is written (the
    /// consent's own record holds the gate: `ConsentState.withdrew`).
    @discardableResult
    func storeConsentWithdrawn(asOf change: UserChange) -> WriteTicket {
        guard isCurrent(change) else { return .dropped }
        noteUserChange()
        guard var user = user() else { return .dropped }
        user.consent = nil
        writtenThroughUser = (change.store, user)
        forget([.user])
        return submit(.user(user), at: change.epoch)
    }

    /// A `GET /v1/me` answer, asked for at `askedAt` (its flight's start). Dropped, unwritten, when this phone changed
    /// the user after that (`lastUserChange`): the platform may have read the user before the change, and a withdrawn
    /// consent would come back with it. One that's written may end this phone's withdrawal (`ConsentState.heard`).
    @discardableResult
    func store(fetchedUser user: User, askedAt: Date) -> WriteTicket {
        if let changed = lastUserChange, askedAt < changed { return .dropped }
        let ticket = store(user: user)
        env.consent.heard(user, askedAt: askedAt)
        return ticket
    }

    @discardableResult
    func store(sleepRange: SleepRange) -> WriteTicket { submit(.sleepRange(sleepRange)) }

    @discardableResult
    func store(workout: WorkoutDetail) -> WriteTicket { submit(.workout(workout)) }

    /// `day`'s activities as the platform listed them, replacing the cached ones. `route` and `hr_samples`
    /// are dropped first: list reads are expected without them (R16), and none is kept at rest if one
    /// arrives anyway (ADR 0006).
    @discardableResult
    func store(activities: [SportActivity], day: String) -> WriteTicket { submit(.activities(activities, day: day)) }

    /// One activity the platform answered (a confirmed `PUT`, a detail read), into the list of the day it
    /// starts on, without `route` and `hr_samples`. A copy cached under another day (its start was edited)
    /// is removed there. `cachedUnder[activity.id]`: the day whose list held it before, its own day first, then My
    /// Day's strip (the day an edit moved it from, rescored too).
    @discardableResult
    func store(activity: SportActivity) -> WriteTicket {
        submit(.activity(activity, strip: DayFormat.days(endingAt: now, count: DateStrip.length)))
    }

    /// A deleted activity (the platform confirmed the `DELETE`): out of every cached day. `cachedUnder[id]`: the day
    /// whose list held it, `hint` first, then My Day's strip.
    @discardableResult
    func forget(activity id: UUID, hint: String? = nil) -> WriteTicket {
        submit(.forgetActivity(id, strip: DayFormat.days(endingAt: now, count: DateStrip.length), hint: hint))
    }

    /// Every cached series refetches the next time it's shown (new scores came in).
    @discardableResult
    func markTrendsStale() -> WriteTicket { submit(.markTrendsStale) }

    /// Nightly (`BGProcessingTask`): days beyond a year, workouts and Train
    /// documents nobody opened for 30 days, series older than a week. What's
    /// gone is fetched again when needed. Returns once it's committed.
    @discardableResult
    func compact() async -> Int {
        let cutoffDay = calendar.startOfDay(for: DayFormat.shift(now, days: -365))
        let month = now.addingTimeInterval(-30 * 86_400)
        let week = now.addingTimeInterval(-7 * 86_400)
        // Train's exercise histories are the main context's documents (design.md §5.1).
        let s = store
        let prefix = "train.history."
        let oldDocs = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key.starts(with: prefix) && $0.fetchedAt < month })
        var removed = (try? s.context.fetchCount(oldDocs)) ?? 0
        try? s.context.delete(model: CachedDocument.self, where: #Predicate { $0.key.starts(with: prefix) && $0.fetchedAt < month })
        if removed > 0 { s.save() }
        removed += await submit(.compact(dayCutoff: cutoffDay, month: month, week: week)).committed().removed
        return removed
    }

    /// The store changed underneath (sign-out wiped it): forget decoded values, the read contexts and the user
    /// written through.
    func invalidate() {
        readContexts = [:]
        writtenThroughUser = nil
        lastUserChange = nil
        resubmittedUser = false
        forget(Kind.allCases)
        // A wipe's writer goes now, not at the next write: its context registered the account's rows.
        drain.retireWiped()
    }

    /// `AppState.reset` (another account, the Demo data switch): demo data's store starts over, empty at once, so no
    /// read decides from (or shows) rows a queued clear would still have to delete; its next use makes a new one. Then
    /// everything is read again (`invalidate()`).
    func reset() {
        if let demo = demoStoreInstance {
            demoStoreInstance = nil
            readContexts[demo.epoch.store] = nil
            seeds[demo.epoch.store] = nil
            drain.retire(store: demo.epoch.store)
        }
        invalidate()
    }

    /// Every read model of the current store, as one write after those queued (sign-out wipes the whole store via
    /// `Persistence.wipe`, the Demo data switch replaces demo's: `reset()`). Nothing decoded before it is read again
    /// from here on; the store is empty at the commit.
    @discardableResult
    func clear() -> WriteTicket {
        let ticket = submit(.clear)
        invalidate()
        return ticket
    }

    /// Runs `body` against the account's store, whatever the Demo data switch says (its `seed`s land there).
    func writingToAccountStore(_ body: () -> Void) {
        forceLive = true
        defer { forceLive = false; forget(Kind.allCases) }
        body()
    }

    static func trendKey(_ metric: TrendMetric, _ range: TrendRange) -> String {
        "\(metric.rawValue)-\(range.rawValue)"
    }
}

/// The drain's way back to its Repository (weak: the Repository owns the drain).
@MainActor
private final class RepositoryLink {
    weak var repository: Repository?
}

// MARK: - widget snapshot

/// The app's half of the widget's snapshot (`Shared/ReadinessSnapshot.swift`): what Today decided, written into the
/// App Group container when it changed.
extension ReadinessSnapshot {
    /// Today's gauge as `TodayPresentation.decide` picked it, in the widget's kinds: today's readiness; a night
    /// pending or awaited, or another day's readiness, dimmed; the baselines; `nil` with nothing scored at all. The
    /// latest readiness before today goes along in every kind: tomorrow shows it dimmed until its night is scored
    /// (`asOf`). The orbit is `OrbitGaugeMode(p)`'s: the tiles' scores and what a baselines count counts.
    static func make(day: String, presentation p: TodayPresentation, now: Date,
                     bedtime: Date? = nil) -> ReadinessSnapshot? {
        let mode = OrbitGaugeMode(p)
        var s = ReadinessSnapshot(day: day, kind: .waitingForSleep, readiness: nil, previousReadiness: p.previousReadiness,
                                  baselineNights: nil, updatedAt: now, bedtime: bedtime.flatMap { $0 > now ? $0 : nil },
                                  orbit: Orbit(recovery: p.tiles.recovery, sleepPerformance: p.tiles.source?.sleepPerformance,
                                               strain: p.tiles.source?.strain, counted: mode.calibration?.signal))
        switch p.gauge {
        case .readiness(let readiness?) where !p.tiles.isEarlierDay:
            s.kind = .score
            s.readiness = readiness
            // S2: the baselines still learning beside the readiness.
            s.baselineNights = mode.calibration?.nights
        case .readiness:
            // Row D from an earlier day (the widget has no note; its readiness is the latest one), or no readiness:
            // the last one, dimmed. The orbit only when the tiles show that day (D); otherwise they show today's
            // unscored night, not the dimmed readiness's day.
            if !p.tiles.isEarlierDay { s.orbit = nil }
        case .baselines(let nights):
            s.kind = .calibrating
            s.baselineNights = nights
            // The counter draws no scores (and Recovery is withheld beside it): only what it counts, so a strain
            // synced while calibrating doesn't reload the widget.
            s.orbit = Orbit(counted: mode.calibration?.signal)
        case .pending(let night):
            s.kind = night.waitingForSleep ? .waitingForSleep : .pending
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
        guard let data = try? encoder.encode(snapshot),
              (try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
        else { return false }
        // Health scores: readable by the widget after the first unlock, never in a device backup.
        var url = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return true
    }

    /// Sign-out: the next account's readiness, or none, never this one's on the lock screen.
    static func clear() {
        guard let file = sharedFile, publish(nil, to: file) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Everything but `updatedAt`: every field counts, so a file written before a new field (the orbit) is
    /// rewritten by the first publish after the update.
    private var shown: ReadinessSnapshot {
        var s = self
        s.updatedAt = .distantPast
        return s
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
    case activities   // GET /v1/activities?from&to, one local day (My Day)

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
        case .activities: return String(localized: "Activities")
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

    /// Writes an answer into the read models; any caller's, since every store for one key is the same. With the
    /// flight's start: when the answer was asked for, on this phone's clock (retries only ask later). It submits
    /// before its first await (the account was checked in that step) and returns once the write is readable.
    typealias Store = @MainActor (any Sendable, Date) async -> Void

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
        /// Callers that joined it in progress (`joiners(for:)`).
        var joiners = 0

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
                          store: (@MainActor (T) async -> Void)? = nil,
                          _ fetch: @escaping @MainActor () async throws -> T) async throws -> T? {
        // Cancelled already (a screen that went away, a deadline that passed): no flight for it.
        try Task.checkCancellation()
        guard let outcome = enter(key, mode: mode, userInitiated: userInitiated, store: Self.erase(store), fetch) else {
            return nil
        }
        return try await outcome.value() as? T
    }

    /// The same, and `store` learns when the flight that answered was started: a caller that joined a flight gets
    /// that flight's start, not its own (`SyncService.receive(_:requestedAt:)`).
    @discardableResult
    func run<T: Sendable>(_ key: ReadKey, mode: ReadMode = .latest, userInitiated: Bool = false,
                          storeAsked: @escaping @MainActor (T, Date) async -> Void,
                          _ fetch: @escaping @MainActor () async throws -> T) async throws -> T? {
        try Task.checkCancellation()
        let store: Store = { value, started in if let value = value as? T { await storeAsked(value, started) } }
        guard let outcome = enter(key, mode: mode, userInitiated: userInitiated, store: store, fetch) else { return nil }
        return try await outcome.value() as? T
    }

    /// How many callers joined `key`'s flight in progress (none when nothing is in flight). For tests that need a read
    /// to have joined an earlier flight, not started its own; nothing in the app decides by it.
    func joiners(for key: ReadKey) -> Int { flights[key]?.joiners ?? 0 }

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
            flight.joiners += 1
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
                // `attempts` checked the account and cancellation; no await since. The store submits before its
                // first await, then waits for the commit.
                if let store = flight.store {
                    let signposts = Signposts.reads
                    let interval = signposts.beginInterval("store", id: signposts.makeSignpostID(),
                                                           "\(key.resource.rawValue, privacy: .public)")
                    await store(value, flight.started)
                    signposts.endInterval("store", interval)
                    // The commit was awaited: signed out, another account or a reset meanwhile, and the answer (its
                    // write dropped by the wipe) isn't for whoever waits now.
                    guard self.env?.auth.accountID == account, !Task.isCancelled else { throw CancellationError() }
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

    private static func erase<T: Sendable>(_ store: (@MainActor (T) async -> Void)?) -> Store? {
        guard let store else { return nil }
        return { value, _ in if let value = value as? T { await store(value) } }
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
