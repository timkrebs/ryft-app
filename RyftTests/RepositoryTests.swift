import Foundation
import SwiftData
import Testing
@testable import Ryft

@MainActor
private func makeRepo(api: MockPlatformAPI = MockPlatformAPI(), now: Date = .now, online: Bool = true)
    -> (Repository, TestClock, AppEnvironment) {
    let clock = TestClock(now: now)
    let env = AppEnvironment.test(api: api, clock: clock, online: online)
    return (Repository(env: env), clock, env)
}

private func shift(_ date: Date, _ days: Int) -> Date { DayFormat.shift(date, days: days) }

/// Encoded with sorted keys, so two values compare as JSON.
private func json<T: Encodable>(_ value: T) throws -> Data {
    let e = JSONEncoder()
    e.keyEncodingStrategy = .convertToSnakeCase
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = .sortedKeys
    return try e.encode(value)
}

@Suite("Repository: freshness")
@MainActor
struct RepositoryFreshnessTests {
    @Test func todayIsFreshForFiveMinutes() async throws {
        let api = MockPlatformAPI()
        let (repo, clock, _) = makeRepo(api: api)
        try await repo.refreshDay(clock.now())
        try await repo.refreshDay(clock.now())
        #expect(api.count("day") == 1)
        clock.advance(by: .seconds(4 * 60))
        try await repo.refreshDay(clock.now())
        #expect(api.count("day") == 1)
        clock.advance(by: .seconds(2 * 60))
        try await repo.refreshDay(clock.now())
        #expect(api.count("day") == 2)
    }

    @Test func aPastDayFetchedAfterItEndedIsFreshForADay() async throws {
        let api = MockPlatformAPI()
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let (repo, clock, _) = makeRepo(api: api, now: noon)
        let yesterday = shift(noon, -1)
        try await repo.refreshDay(yesterday)
        clock.advance(by: .seconds(23 * 3600))
        try await repo.refreshDay(yesterday)
        #expect(api.count("day") == 1)
        clock.advance(by: .seconds(2 * 3600))
        try await repo.refreshDay(yesterday)
        #expect(api.count("day") == 2)
    }

    @Test func todaysCopyIsStaleOnceTheDayIsOver() async throws {
        let api = MockPlatformAPI()
        let lateEvening = Calendar.current.date(bySettingHour: 23, minute: 58, second: 0, of: .now)!
        let (repo, clock, _) = makeRepo(api: api, now: lateEvening)
        try await repo.refreshDay(lateEvening)
        clock.advance(by: .seconds(10 * 60)) // 00:08 the next day
        try await repo.refreshDay(lateEvening) // now yesterday, fetched before it ended
        #expect(api.count("day") == 2)
    }

    @Test func browsingCachedHistoryMakesNoRequests() async throws {
        let api = MockPlatformAPI()
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let (repo, clock, _) = makeRepo(api: api, now: noon)
        clock.advance(by: .seconds(60)) // past days were "fetched after they ended"
        for d in 1...5 { try await repo.refreshDay(shift(noon, -d)) }
        try await repo.refreshHistory(from: shift(noon, -89), to: noon)
        let calls = api.calls.count
        clock.advance(by: .seconds(60))
        for d in 1...5 { try await repo.refreshDay(shift(noon, -d)) }
        try await repo.refreshHistory(from: shift(noon, -89), to: noon)
        #expect(api.calls.count == calls)
        #expect(repo.day(DayFormat.string(from: shift(noon, -3))) != nil)
        #expect(!repo.history(from: shift(noon, -89), to: noon).isEmpty)
    }

    @Test func trendsAreFreshForAnHour() async throws {
        let api = MockPlatformAPI()
        let (repo, clock, _) = makeRepo(api: api)
        try await repo.refreshTrend(.hrv, .month)
        clock.advance(by: .seconds(59 * 60))
        try await repo.refreshTrend(.hrv, .month)
        #expect(api.count("trends") == 1)
        clock.advance(by: .seconds(2 * 60))
        try await repo.refreshTrend(.hrv, .month)
        #expect(api.count("trends") == 2)
        #expect(repo.trend(.hrv, .month)?.metric == "hrv")
    }

    @Test func forceFetchesEvenWhenFresh() async throws {
        let api = MockPlatformAPI()
        let (repo, clock, _) = makeRepo(api: api)
        try await repo.refreshDay(clock.now())
        try await repo.refreshDay(clock.now(), force: true)
        #expect(api.count("day") == 2)
    }
}

@Suite("Repository: offline and failures")
@MainActor
struct RepositoryOfflineTests {
    @Test func offlineRequestsNothingAndServesTheCache() async throws {
        let api = MockPlatformAPI()
        // Mid-morning, so the hour below never crosses midnight.
        let (repo, clock, env) = makeRepo(api: api, now: Date(timeIntervalSince1970: 1_792_400_000))
        try await repo.refreshDay(clock.now())
        env.connectivityMonitor.update(false)
        clock.advance(by: .seconds(3600)) // stale
        let d = try await repo.refreshDay(clock.now())
        #expect(d != nil)
        #expect(api.count("day") == 1)
    }

    @Test func offlineWithoutACopyHasNothing() async {
        let api = MockPlatformAPI()
        let (_, clock, env) = makeRepo(api: api, online: false)
        let state = AppState(env: env)
        await #expect(throws: APIError.self) { _ = try await state.dayDetail(for: clock.now()) }
        #expect(api.calls.isEmpty)
    }

    @Test func aFailureKeepsTheCachedCopy() async throws {
        let api = MockPlatformAPI()
        let (repo, clock, _) = makeRepo(api: api)
        try await repo.refreshDay(clock.now())
        api.failure = APIError.http(503, "")
        let d = try await repo.refreshDay(clock.now(), force: true)
        #expect(d != nil)
    }

    @Test func aFailureWithoutACopyThrows() async {
        let api = MockPlatformAPI()
        api.failure = APIError.http(500, "")
        let (repo, clock, _) = makeRepo(api: api)
        await #expect(throws: APIError.self) { try await repo.refreshDay(clock.now()) }
    }
}

@Suite("Repository: storage")
@MainActor
struct RepositoryStorageTests {
    @Test func historyIsRangedSortedAndCapped() {
        let (repo, clock, _) = makeRepo()
        let now = clock.now()
        repo.store(scores: (0..<450).map { DailyScore(day: DayFormat.string(from: shift(now, -$0)), strain: Double($0 % 21)) })
        let week = repo.history(from: shift(now, -6), to: now)
        #expect(week.count == 7)
        #expect(week.map(\.day) == week.map(\.day).sorted())
        #expect(repo.history(from: shift(now, -449), to: now).count == Repository.maxHistoryRows)
    }

    @Test func aDetailWinsOverTheListScore() {
        let (repo, clock, _) = makeRepo()
        let key = DayFormat.string(from: clock.now())
        repo.store(scores: [DailyScore(day: key, strain: 4)])
        var detail = MockData.todayDetail
        detail.score = DailyScore(day: key, strain: 12)
        repo.store(detail: detail)
        #expect(repo.score(key)?.strain == 12)
    }

    @Test func readsAreObservableThroughTheRevision() {
        let (repo, clock, _) = makeRepo()
        let before = repo.revision
        repo.store(scores: [DailyScore(day: DayFormat.string(from: clock.now()), strain: 4)])
        #expect(repo.revision == before + 1)
    }

    @Test func wipingTheStoreEmptiesEveryReadModel() throws {
        let (repo, clock, env) = makeRepo()
        repo.store(detail: MockData.todayDetail)
        repo.store(user: MockData.user)
        repo.store(insights: MockData.insights)
        env.persistence.wipe()
        repo.invalidate()
        #expect(repo.day(DayFormat.string(from: clock.now())) == nil)
        #expect(repo.user() == nil && repo.insights().isEmpty)
    }

    @Test func demoDataNeverReachesTheAccountStore() throws {
        let env = AppEnvironment.preview()   // demo on
        let repo = Repository(env: env)
        repo.store(detail: MockData.todayDetail)
        #expect(repo.day(MockData.todayDetail.score.day) != nil)
        let rows = try env.persistence.context.fetch(FetchDescriptor<CachedDay>())
        #expect(rows.isEmpty)
    }

    @Test func everyCachedTypeRoundTrips() throws {
        let (repo, _, _) = makeRepo()
        let detail = try Fixture.decode(DayDetail.self, "day_detail")
        repo.store(detail: detail)
        #expect(try json(repo.day(detail.score.day)) == json(detail))

        let days = try Fixture.decode([DailyScore].self, "days")
        repo.store(scores: days)
        #expect(try json(days.compactMap { repo.score($0.day) }) == json(days.map { d in
            d.day == detail.score.day ? detail.score : d
        }))

        let trend = try Fixture.decode(TrendSeries.self, "trends")
        repo.store(trend: trend, metric: .hrv, range: .week)
        #expect(try json(repo.trend(.hrv, .week)) == json(trend))

        let insights = try Fixture.decode([Insight].self, "insights")
        repo.store(insights: insights)
        #expect(try json(repo.insights()) == json(insights))

        let user = try Fixture.decode(User.self, "me")
        repo.store(user: user)
        #expect(try json(repo.user()) == json(user))

        let sleep = try Fixture.decode(SleepRange.self, "sleep_range")
        repo.store(sleepRange: sleep)
        #expect(try json(repo.sleepRange(SleepRangeKind(rawValue: sleep.range) ?? .week)) == json(sleep))

        let workout = try Fixture.decode(WorkoutDetail.self, "workout_detail")
        repo.store(workout: workout)
        #expect(try json(repo.workout(workout.workout.id)) == json(workout))
    }

    @Test func trainDocumentsRoundTrip() throws {
        let store = TrainStore(inMemory: true)
        let plans = try Fixture.decode(PlansOverview.self, "train_plans")
        store.saveDocument(plans, key: "train.plans")
        #expect(try json(store.document(PlansOverview.self, key: "train.plans")) == json(plans))
        let today = try Fixture.decode(PlanToday.self, "train_plan_today")
        store.saveDocument(today, key: "train.today")
        #expect(try json(store.document(PlanToday.self, key: "train.today")) == json(today))
        let history = try Fixture.decode(ExerciseHistory.self, "train_exercise_history")
        store.saveDocument(history, key: "h")
        #expect(try json(store.document(ExerciseHistory.self, key: "h")) == json(history))
        let sessions = try Fixture.decode([SessionSummary].self, "train_sessions")
        store.saveDocument(sessions, key: "s")
        #expect(try json(store.document([SessionSummary].self, key: "s")) == json(sessions))
        store.removeDocument(key: "s")
        #expect(store.document([SessionSummary].self, key: "s") == nil)
    }
}

@Suite("Legacy cache migration")
@MainActor
struct LegacyCacheMigrationTests {
    @Test func importsOnceAndDeletesTheFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let snapshot = LegacyCacheMigration.TodaySnapshot(
            today: MockData.todayDetail, history: Array(MockData.history.suffix(10)), user: MockData.user,
            insights: MockData.insights, readinessWeek: MockData.trend(.readiness, range: .week), fetchedAt: .now)
        try APIClient.jsonEncoder.encode(snapshot).write(to: dir.appendingPathComponent("today.json"))
        try APIClient.jsonEncoder.encode(Fixture.decode(PlansOverview.self, "train_plans"))
            .write(to: dir.appendingPathComponent("train.plans.json"))

        let (repo, _, env) = makeRepo()
        let store = TrainStore(inMemory: true)
        let defaults = env.defaults
        LegacyCacheMigration.runOnce(into: repo, train: store, defaults: defaults, directory: dir)

        #expect(repo.day(MockData.todayDetail.score.day) != nil)
        #expect(repo.user()?.id == MockData.user.id)
        #expect(repo.insights().count == MockData.insights.count)
        #expect(repo.trend(.readiness, .week) != nil)
        #expect(store.document(PlansOverview.self, key: "train.plans") != nil)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        #expect(defaults.bool(forKey: LegacyCacheMigration.doneKey))

        // A second launch doesn't touch anything.
        repo.clear()
        LegacyCacheMigration.runOnce(into: repo, train: store, defaults: defaults, directory: dir)
        #expect(repo.user() == nil)
    }
}
