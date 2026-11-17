import Foundation
import SwiftData

// What a read-model write is, as values, and the one implementation of each (ADR 0018). The Repository submits these;
// `ReadModelDrain`'s writer applies them off the main actor, and `Repository.seed` on a context of its own (previews,
// tests, the one-time legacy import). Nothing here is a `@Model` that leaves its context.

/// What a write changes. Each kind has its own revision and memo entries in the Repository, so a trends write neither
/// re-decodes the days nor re-renders a view that only shows days.
enum ReadModelKind: String, CaseIterable, Sendable {
    case days, trends, insights, user, sleep, workouts, activities
}

/// One write of the platform's read models.
enum ReadModelWrite: Sendable {
    /// `GET /v1/days/{day}`: the detail and its score.
    case detail(DayDetail)
    /// `GET /v1/days`: scores only; an opened detail stays.
    case scores([DailyScore])
    /// The cached scores become exactly these (previews and tests: `AppState.history`'s setter); opened details stay.
    case replaceScores([DailyScore])
    case trend(TrendSeries, key: String)
    /// The platform's list is the whole truth: the cards are replaced.
    case insights([Insight])
    case user(User)
    case sleepRange(SleepRange)
    case workout(WorkoutDetail)
    /// `day`'s activities as listed, replacing the cached ones, without `route` and `hr_samples` (ADR 0006).
    case activities([SportActivity], day: String)
    /// One answered activity into the list of the day it starts on, out of any other day's. Read, modified and
    /// written in one job: `strip` is where else it may have been cached (My Day's strip), for `cachedUnder`.
    case activity(SportActivity, strip: [String])
    /// A confirmed delete: out of every cached day. `hint`, then `strip`, are searched for `cachedUnder`.
    case forgetActivity(UUID, strip: [String], hint: String?)
    /// Every cached series refetches the next time it's shown (new scores came in).
    case markTrendsStale
    /// Nightly: days before `dayCutoff`, workouts unopened since `month`, series older than `week`, and the
    /// activities of the days that go. Train's documents are the main context's (`Repository.compact`).
    case compact(dayCutoff: Date, month: Date, week: Date)
    /// Every read model (the demo switch; a sign-out wipes the whole store instead).
    case clear
}

/// What a batch of writes did.
struct WriteReceipt: Sendable, Equatable {
    /// The kinds whose revisions to bump.
    var kinds: Set<ReadModelKind> = []
    /// The store took the batch.
    var saved = false
    /// Its epoch was over (a wipe came first): nothing was written.
    var dropped = false
    /// Rows `compact` removed.
    var removed = 0
    /// The day an activity's cached list held it in before the write (`activity`, `forgetActivity`): its old day is
    /// rescored too.
    var cachedUnder: [UUID: String] = [:]
    /// Days the widget shows were written (a detail, scores): it's republished after the commit.
    var publishesWidget = false
}

/// The one implementation of every write, for whichever context runs it. Batch fetches: one `#Predicate` per op, not
/// one fetch per day.
enum ReadModelWrites {
    /// Keys per `contains` predicate (T0.5 proved 450 in one on iOS 27; SQLite allows far more).
    static let keysPerFetch = 400

    static func apply(_ op: ReadModelWrite, in context: ModelContext, now: Date, into receipt: inout WriteReceipt) {
        switch op {
        case .detail(let detail):
            guard let row = dayRows([detail.score.day], in: context, now: now)[detail.score.day] else { return }
            row.detailData = WireCoding.encode(detail)
            row.detailFetchedAt = now
            row.scoreData = WireCoding.encode(detail.score)
            row.scoreFetchedAt = now
            receipt.kinds.insert(.days)
            receipt.publishesWidget = true
        case .scores(let scores):
            store(scores, in: context, now: now)
            receipt.kinds.insert(.days)
            receipt.publishesWidget = true
        case .replaceScores(let scores):
            let keep = Set(scores.map(\.day))
            var d = FetchDescriptor<CachedDay>()
            d.fetchLimit = 10_000
            for row in (try? context.fetch(d)) ?? [] where !keep.contains(row.day) {
                if row.detailData == nil { context.delete(row) } else { row.scoreData = nil }
            }
            store(scores, in: context, now: now)
            receipt.kinds.insert(.days)
            receipt.publishesWidget = true
        case .trend(let trend, let key):
            guard let data = WireCoding.encode(trend) else { return }
            var d = FetchDescriptor<CachedTrend>(predicate: #Predicate { $0.key == key })
            d.fetchLimit = 1
            if let row = (try? context.fetch(d))?.first {
                row.data = data
                row.fetchedAt = now
            } else {
                context.insert(CachedTrend(key: key, data: data, fetchedAt: now))
            }
            receipt.kinds.insert(.trends)
        case .insights(let insights):
            deleteAll(CachedInsight.self, in: context)
            for (i, insight) in insights.enumerated() {
                guard let data = WireCoding.encode(insight) else { continue }
                context.insert(CachedInsight(id: insight.id, position: i, data: data, fetchedAt: now))
            }
            receipt.kinds.insert(.insights)
        case .user(let user):
            guard let data = WireCoding.encode(user) else { return }
            deleteAll(CachedUser.self, in: context)
            context.insert(CachedUser(id: user.id, data: data, fetchedAt: now))
            receipt.kinds.insert(.user)
        case .sleepRange(let range):
            guard let data = WireCoding.encode(range) else { return }
            let kind = range.range
            var d = FetchDescriptor<CachedSleepRange>(predicate: #Predicate { $0.kind == kind })
            d.fetchLimit = 1
            if let row = (try? context.fetch(d))?.first {
                row.data = data
                row.fetchedAt = now
            } else {
                context.insert(CachedSleepRange(kind: kind, data: data, fetchedAt: now))
            }
            receipt.kinds.insert(.sleep)
        case .workout(let workout):
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
            receipt.kinds.insert(.workouts)
        case .activities(let activities, let day):
            let list = activities.map(\.withoutRouteOrHeartRate).sorted { $0.start < $1.start }
            guard let data = WireCoding.encode(list) else { return }
            writeActivities(data, day: day, fetchedAt: now, in: context)
            receipt.kinds.insert(.activities)
        case .activity(let activity, let strip):
            let day = DayFormat.string(from: activity.start)
            let id = activity.id
            if let left = cachedDay(of: id, startingOn: day, strip: strip, in: context) { receipt.cachedUnder[id] = left }
            removeCached(id, keeping: Repository.activitiesKey(day), in: context)
            let existing = activitiesDocument(day, in: context)
            var list = (WireCoding.decode([SportActivity].self, existing?.data) ?? []).filter { $0.id != id }
            list.append(activity.withoutRouteOrHeartRate)
            list.sort { $0.start < $1.start }
            guard let data = WireCoding.encode(list) else { return }
            // A single answer doesn't make the day's list fresh: its fetch time stays (a new row's is the past).
            writeActivities(data, day: day, fetchedAt: existing?.fetchedAt ?? .distantPast, in: context)
            receipt.kinds.insert(.activities)
        case .forgetActivity(let id, let strip, let hint):
            if let left = cachedDay(of: id, startingOn: hint, strip: strip, in: context) { receipt.cachedUnder[id] = left }
            if removeCached(id, keeping: nil, in: context) { receipt.kinds.insert(.activities) }
        case .markTrendsStale:
            var d = FetchDescriptor<CachedTrend>()
            d.fetchLimit = 500
            for row in (try? context.fetch(d)) ?? [] { row.fetchedAt = .distantPast }
            receipt.kinds.insert(.trends)
        case .compact(let cutoffDay, let month, let week):
            receipt.removed += compact(before: cutoffDay, month: month, week: week, in: context)
            receipt.kinds.formUnion([.days, .trends, .workouts, .activities])
        case .clear:
            deleteAll(CachedDay.self, in: context)
            deleteAll(CachedTrend.self, in: context)
            deleteAll(CachedInsight.self, in: context)
            deleteAll(CachedUser.self, in: context)
            deleteAll(CachedSleepRange.self, in: context)
            deleteAll(CachedWorkout.self, in: context)
            let prefix = Repository.activitiesPrefix
            deleteAll(CachedDocument.self, where: #Predicate { $0.key.starts(with: prefix) }, in: context)
            receipt.kinds.formUnion(ReadModelKind.allCases)
        }
    }

    // MARK: days

    /// The rows of `keys`, inserted where missing: one fetch per `keysPerFetch` keys. Pending inserts of the same batch
    /// are found too (`includePendingChanges`), so two answers for one day in a batch write one row, the later last.
    private static func dayRows(_ keys: [String], in context: ModelContext, now: Date) -> [String: CachedDay] {
        var unique: [String] = []
        var seen = Set<String>()
        for key in keys where seen.insert(key).inserted { unique.append(key) }
        var rows: [String: CachedDay] = [:]
        var start = 0
        while start < unique.count {
            let chunk = Array(unique[start..<min(start + keysPerFetch, unique.count)])
            let d = FetchDescriptor<CachedDay>(predicate: #Predicate { chunk.contains($0.day) })
            for row in (try? context.fetch(d)) ?? [] where rows[row.day] == nil { rows[row.day] = row }
            start += keysPerFetch
        }
        for key in unique where rows[key] == nil {
            let row = CachedDay(day: key, date: DayFormat.date(from: key) ?? now)
            context.insert(row)
            rows[key] = row
        }
        return rows
    }

    private static func store(_ scores: [DailyScore], in context: ModelContext, now: Date) {
        let rows = dayRows(scores.map(\.day), in: context, now: now)
        for score in scores {
            guard let row = rows[score.day] else { continue }
            row.scoreData = WireCoding.encode(score)
            row.scoreFetchedAt = now
        }
    }

    // MARK: activities

    private static func activitiesDocument(_ day: String, in context: ModelContext) -> CachedDocument? {
        let key = Repository.activitiesKey(day)
        var d = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    private static func writeActivities(_ data: Data, day: String, fetchedAt: Date, in context: ModelContext) {
        if let row = activitiesDocument(day, in: context) {
            row.data = data
            row.fetchedAt = fetchedAt
        } else {
            context.insert(CachedDocument(key: Repository.activitiesKey(day), data: data, fetchedAt: fetchedAt))
        }
    }

    /// The day whose cached list holds `id`: `day` (where it starts now) when that list has it, else one of `strip`'s
    /// days (the day an edit moved it from, rescored too). Bounded: at most the strip's lists are read, and only those
    /// that mention the id are decoded.
    private static func cachedDay(of id: UUID, startingOn day: String?, strip: [String], in context: ModelContext)
        -> String? {
        if let day, let row = activitiesDocument(day, in: context),
           WireCoding.decode([SportActivity].self, row.data)?.contains(where: { $0.id == id }) == true {
            return day
        }
        let needle = Data(id.uuidString.utf8)
        for candidate in strip where candidate != day {
            guard let row = activitiesDocument(candidate, in: context), row.data.range(of: needle) != nil,
                  WireCoding.decode([SportActivity].self, row.data)?.contains(where: { $0.id == id }) == true
            else { continue }
            return candidate
        }
        return nil
    }

    /// Takes `id` out of every cached day's list but `keeping`'s. Only lists that mention it are decoded. True when one
    /// changed.
    @discardableResult
    private static func removeCached(_ id: UUID, keeping key: String?, in context: ModelContext) -> Bool {
        let needle = Data(id.uuidString.utf8)
        let prefix = Repository.activitiesPrefix
        let keep = key ?? ""
        let docs = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key.starts(with: prefix) && $0.key != keep })
        var removed = false
        for row in (try? context.fetch(docs)) ?? [] where row.data.range(of: needle) != nil {
            guard let list = WireCoding.decode([SportActivity].self, row.data) else { continue }
            let kept = list.filter { $0.id != id }
            guard kept.count != list.count, let data = WireCoding.encode(kept) else { continue }
            row.data = data
            removed = true
        }
        return removed
    }

    // MARK: deletes

    /// Deletes every `T` matching `predicate` in `context`, this batch's unsaved inserts included, as part of the batch's
    /// one save. Never `delete(model:)`: a batch delete misses unsaved inserts (the save would write them after it) and
    /// may reach the store at once, outside the save and its epoch check (T0, F4). Returns how many.
    @discardableResult
    private static func deleteAll<T: PersistentModel>(_: T.Type, where predicate: Predicate<T>? = nil,
                                                      in context: ModelContext) -> Int {
        let rows = (try? context.fetch(FetchDescriptor<T>(predicate: predicate))) ?? []
        for row in rows { context.delete(row) }
        return rows.count
    }

    // MARK: compaction

    private static func compact(before cutoffDay: Date, month: Date, week: Date, in context: ModelContext) -> Int {
        var removed = deleteAll(CachedDay.self, where: #Predicate { $0.date < cutoffDay }, in: context)
        removed += deleteAll(CachedWorkout.self, where: #Predicate { $0.fetchedAt < month }, in: context)
        removed += deleteAll(CachedTrend.self, where: #Predicate { $0.fetchedAt < week }, in: context)
        // Activities go with their days (keys sort by day: "activities.2025-10-22").
        let cutoffKey = Repository.activitiesKey(DayFormat.string(from: cutoffDay))
        let prefix = Repository.activitiesPrefix
        let docs = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key.starts(with: prefix) })
        for row in (try? context.fetch(docs)) ?? [] where row.key < cutoffKey {
            context.delete(row)
            removed += 1
        }
        return removed
    }
}
