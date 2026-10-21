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

    @Test func todayCachedByAScreenDoesNotStandInForTheHistory() async throws {
        let api = MockPlatformAPI()
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let (repo, _, _) = makeRepo(api: api, now: noon)
        try await repo.refreshDay(noon) // Strain's own load, first
        try await repo.refreshHistory(from: shift(noon, -89), to: noon)
        #expect(api.count("days") == 1)
        #expect(repo.history(from: shift(noon, -89), to: noon).count > 1)
        try await repo.refreshHistory(from: shift(noon, -89), to: noon)
        #expect(api.count("days") == 1) // now it is cached and fresh
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

@Suite("Repository: invalidation per kind")
@MainActor
struct RepositoryInvalidationTests {
    @Test func aTrendsWriteKeepsTheDecodedDays() {
        let env = AppEnvironment.test()
        let repo = Repository(env: env)
        let key = DayFormat.string(from: env.clock.now())
        repo.store(detail: MockData.todayDetail.with(day: key))
        _ = repo.day(key)
        let decoded = repo.decodes
        let days = repo.daysRevision

        repo.store(trend: MockData.trend(.readiness, range: .week), metric: .readiness, range: .week)

        _ = repo.day(key)
        #expect(repo.decodes == decoded) // the day wasn't decoded again
        #expect(repo.daysRevision == days) // and a view showing only days isn't re-rendered
        #expect(repo.trendsRevision > 0)
    }

    @Test func aDayWriteDecodesThatKindAgain() {
        let env = AppEnvironment.test()
        let repo = Repository(env: env)
        let key = DayFormat.string(from: env.clock.now())
        repo.store(detail: MockData.todayDetail.with(day: key))
        _ = repo.day(key)
        _ = repo.user()
        let decoded = repo.decodes

        repo.store(scores: [DailyScore(day: key, strain: 3)])
        _ = repo.day(key)
        _ = repo.user()

        #expect(repo.decodes == decoded + 1) // the day again, not the user
    }

    @Test func invalidatingForgetsEveryKind() {
        let env = AppEnvironment.test()
        let repo = Repository(env: env)
        repo.store(user: MockData.user)
        _ = repo.user()
        let before = repo.revision
        repo.invalidate()
        #expect(repo.revision == before + Repository.Kind.allCases.count)
        let decoded = repo.decodes
        _ = repo.user()
        #expect(repo.decodes == decoded + 1)
    }
}

private extension DayDetail {
    func with(day: String) -> DayDetail {
        var d = self
        d.score = DailyScore(day: day, readiness: score.readiness, strain: score.strain)
        return d
    }
}

@Suite("Readiness widget snapshot")
@MainActor
struct ReadinessSnapshotTests {
    private let day = "2026-10-21"
    private let now = Date(timeIntervalSince1970: 1_792_560_000)

    /// A scored row has a `computed_at`; one without a readiness or the calibrating flag is the unscored placeholder.
    private func score(_ readiness: Int?, calibrating: Bool = false, nights: Int = 30, state: ScoringState? = nil) -> DailyScore {
        DailyScore(day: day, readiness: readiness, baselineDays: nights, calibrating: calibrating,
                   computedAt: readiness != nil || calibrating ? now : nil, scoringState: state)
    }

    private func make(_ today: DailyScore?, prior: [DailyScore] = [], state: ScoringState?) -> ReadinessSnapshot? {
        ReadinessSnapshot.make(day: day, presentation: .decide(TodayScoreFacts(day: day, today: today, scoringState: state,
                                                                               prior: prior)),
                               now: now)
    }

    /// 30 scored days before `day`, the newest (yesterday) at `readiness`; with HRV and resting HR unless `vitals` is false.
    private func history(readiness: Int = 76, vitals: Bool = true) -> [DailyScore] {
        let today = DayFormat.date(from: day)!
        return (1...30).reversed().map { offset in
            DailyScore(day: DayFormat.string(from: DayFormat.shift(today, days: -offset)), readiness: offset == 1 ? readiness : 70,
                       hrvMs: vitals ? 55 : nil, rhr: vitals ? 50 : nil, baselineDays: 30, computedAt: now)
        }
    }

    @Test func itShowsWhatTodayShows() {
        let previous = DailyScore(day: "2026-10-20", readiness: 76)
        #expect(make(score(84), prior: [previous], state: .pending)?.kind == .score)
        let pending = make(nil, prior: [previous], state: .pending)
        #expect(pending?.kind == .pending && pending?.previousReadiness == 76 && pending?.readiness == nil)
        #expect(make(score(nil, calibrating: true, nights: 3), state: .waitingForSleep)?.kind == .waitingForSleep) // the night first
        let calibrating = make(score(nil, calibrating: true, nights: 3), state: .scored)
        #expect(calibrating?.kind == .calibrating && calibrating?.baselineNights == 3)
        #expect(make(nil, prior: [previous], state: nil)?.kind == .waitingForSleep)
        #expect(make(nil, state: nil) == nil)
    }

    /// design.md §7 → Widget: one mapping per gauge.
    @Test func eachRowHasItsWidgetKind() throws {
        // D, today's readiness: the score (the widget has no note).
        let screenshot = DailyScore(day: day, readiness: 80, recovery: 75, strain: 0.9, baselineDays: 0, calibrating: true,
                                    computedAt: now, scoringState: .scored)
        let d = try #require(make(screenshot, prior: history(), state: .scored))
        #expect(d.kind == .score && d.readiness == 80 && d.previousReadiness == 76)
        // D from yesterday (today scored, no readiness): yesterday's readiness, dimmed.
        let noReadiness = score(nil, calibrating: true, nights: 0, state: .scored)
        let dYesterday = try #require(make(noReadiness, prior: history(readiness: 76), state: .scored))
        #expect(dYesterday.kind == .waitingForSleep && dYesterday.previousReadiness == 76 && dYesterday.readiness == nil)
        // B over a long history without HRV, with a readiness: the score on both (Today has the note).
        let b = try #require(make(screenshot, prior: history(vitals: false), state: .scored))
        #expect(b.kind == .score && b.readiness == 80 && b.previousReadiness == 76)
        // ... without one: the baselines, the heart-rate nights counted, and the latest readiness kept for tomorrow
        // (the widget's `asOf` dims it once the day turns).
        let bNights = try #require(make(noReadiness, prior: history(vitals: false), state: .scored))
        #expect(bNights.kind == .calibrating && bNights.baselineNights == 0 && bNights.previousReadiness == 76)
        // C from the unknown day: pending, never the baselines.
        let c = try #require(make(.empty(day: day), prior: history(), state: .pending))
        #expect(c.kind == .pending && c.previousReadiness == 76)
        // E: nothing to show.
        #expect(make(.empty(day: day), state: nil) == nil)
    }

    /// T2 criterion 7: Today and the widget read the same store and decide through the same function.
    @Test func theWidgetAndTodayAgree() throws {
        let screenshot = DailyScore(day: day, readiness: 80, recovery: 75, strain: 0.9, sleepActualMin: 430, baselineDays: 0,
                                    calibrating: true, computedAt: now, scoringState: .scored)
        let placeholder = DailyScore(day: day, state: .calibrating, computedAt: Date(timeIntervalSince1970: -62_135_596_800),
                                     scoringState: .pending)
        var twoHeartRateNights = history(vitals: false)
        for i in twoHeartRateNights.indices.suffix(2) { twoHeartRateNights[i].hrvMs = 55; twoHeartRateNights[i].rhr = 50 }
        // (today, history, GET /v1/me/sync's today, the backfill done, the widget's kind and number)
        let cases: [(DailyScore?, [DailyScore], ScoringState?, Bool, ReadinessSnapshot.Kind?, Int?)] = [
            (score(84), history(), .scored, true, .score, 84),                                    // A
            (score(nil, calibrating: true, nights: 3), Array(history().suffix(3)), .scored, true, .calibrating, 3), // B
            (screenshot, history(vitals: false), .scored, true, .score, 80),                     // B, needs HRV
            (score(nil, calibrating: true, nights: 0), twoHeartRateNights, .scored, true, .calibrating, 2), // B, no readiness
            (placeholder, history(), .pending, true, .pending, 76),                               // C, unscored today
            (nil, history(), .waitingForSleep, true, .waitingForSleep, 76),                       // C, no night yet
            (screenshot, history(), .scored, true, .score, 80),                                   // D, the screenshot
            (score(nil, calibrating: true, nights: 0), history(), .scored, true, .waitingForSleep, 76), // D from yesterday
            (nil, [], nil, false, nil, nil),                                                      // E, importing
            (nil, [], nil, true, nil, nil),                                                       // E, backfill done
        ]
        // Local noon on `day`: the repository's and the view model's "today" is `day` in any time zone.
        let noon = try #require(DayFormat.date(from: day)).addingTimeInterval(12 * 3_600)
        for (index, (today, prior, scoring, backfillDone, kind, number)) in cases.enumerated() {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("readiness-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: file) }
            let env = AppEnvironment.test(clock: TestClock(now: noon))
            if backfillDone, let account = env.auth.accountID {
                var engine = SyncEngineState()
                engine.backfillDone = true
                engine.save(account: account, defaults: env.defaults)
            }
            let state = AppState(env: env)
            state.repository.widgetFile = file
            state.repository.reloadWidget = {}
            state.history = prior
            if let today { state.today = DayDetail(score: today, sleep: nil, workouts: []) }
            if let scoring {
                state.syncStatus = SyncStatus(gate: nil, lastSyncAt: now, lastSyncDevice: nil, latest: [:],
                                              today: TodayState(day: day, state: scoring, scoredAt: nil, modelVersion: "x"),
                                              pendingDays: [], expectedWithinSec: 20, resyncRequestedAt: nil)
            }
            state.repository.publishWidget()
            let sync = SyncService(env: env)
            let vm = TodayViewModel(state: state, sync: sync,
                                    coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                                    apiStatus: APIStatus())
            let written = (try? Data(contentsOf: file)).flatMap { try? ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: $0) }
            // The same facts on both sides, and the same decision.
            let today = vm.facts.scores
            #expect(state.repository.widgetFacts.today == today.today, "case \(index)")
            #expect(state.repository.widgetFacts.prior == today.prior, "case \(index)")
            #expect(state.repository.widgetFacts.scoringState == today.scoringState, "case \(index)")
            let widgetSays = TodayPresentation.decide(state.repository.widgetFacts)
            #expect(widgetSays.row == vm.presentation.row && widgetSays.tiles == vm.presentation.tiles, "case \(index)")
            // What each shows.
            #expect(written?.kind == kind, "case \(index)")
            let shown = written?.kind == .score ? written?.readiness
                : written?.kind == .calibrating ? written?.baselineNights : written?.previousReadiness
            #expect(shown == number, "case \(index)")
            switch vm.hero {
            case .score where !vm.tilesDimmed && vm.readiness != nil:
                #expect(written?.kind == .score && written?.readiness == vm.readiness.map { Int($0) }, "case \(index)")
            case .score where vm.presentation.row == .firstImport:
                // E after the import: nothing scored, no widget, no tiles.
                #expect(written == nil && !vm.showsTiles && backfillDone, "case \(index)")
            case .score:
                #expect(written?.kind == .waitingForSleep && written?.previousReadiness == vm.readiness.map { Int($0) },
                        "case \(index)")
            case .calibrating(let nights):
                #expect(written?.kind == .calibrating && written?.baselineNights == nights, "case \(index)")
            case .pending(let night):
                #expect(written?.kind == (night.waitingForSleep ? .waitingForSleep : .pending), "case \(index)")
                #expect(written?.previousReadiness == night.previousReadiness.map { Int($0) }, "case \(index)")
            case .importing:
                // A signed-in test account with nothing scored is importing: the card, and no widget.
                #expect(vm.presentation.row == .firstImport && written == nil && !backfillDone, "case \(index)")
            }
        }
    }

    @Test func itIsWrittenOnlyWhenWhatItShowsChanged() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("readiness-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let a = try #require(make(score(84), state: nil))
        #expect(ReadinessSnapshot.publish(a, to: file))
        var later = a
        later.updatedAt = now.addingTimeInterval(600)
        #expect(!ReadinessSnapshot.publish(later, to: file)) // the same on the widget: no reload
        later.readiness = 85
        #expect(ReadinessSnapshot.publish(later, to: file))
        // The widget's copy decodes the same JSON (its keys and its ISO 8601 dates).
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        #expect(json?["kind"] as? String == "score" && json?["readiness"] as? Int == 85)
        #expect(json?["updatedAt"] is String)
        #expect(ReadinessSnapshot.publish(nil, to: file)) // signed out: gone
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func theRepositoryPublishesAfterARefreshAndOnTheServersWord() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("readiness-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let (repo, clock, _) = makeRepo()
        #expect(repo.widgetFile == nil) // tests and previews never write the shared file
        repo.widgetFile = file
        let reloads = Counter()
        repo.reloadWidget = { reloads.add() }

        try await repo.refreshDay(clock.now())
        let written = try #require(ReadinessSnapshot.decoder.decode(ReadinessSnapshot.self, from: Data(contentsOf: file)) as ReadinessSnapshot?)
        #expect(written.kind == .score && written.day == DayFormat.string(from: clock.now()))
        #expect(reloads.value == 1)

        try await repo.refreshDay(clock.now(), force: true) // the same score again
        #expect(reloads.value == 1)
        repo.todayStatus = TodayState(day: "1999-01-01", state: .pending, scoredAt: nil, modelVersion: "x") // another day's
        #expect(reloads.value == 1)
    }
}

// MARK: - T0: "Baselines · 0 of 7" beside scored tiles
//
// Item 3. The decisive questions, answered by tests: can the app lose or invent `baseline_days` / `calibrating`
// on its own (c)? Can an unscored today produce the gauge (a)? What wire row does produce exactly the screenshot (b)?

@Suite("T0: calibration on Today")
@MainActor
struct CalibrationSourceTests {
    /// `GET /v1/days` example from API.md, trimmed to the fields that matter here.
    private func wire(baseline: String, readiness: String = "80", computedAt: String = "2026-10-21T16:02:11.123456Z") -> Data {
        Data("""
        {"day":"2026-10-21","readiness":\(readiness),"state":"balanced","recovery":75,"strain":0.9,"sleep_actual_min":430,
         "hrv_ms":58.2,"rhr":48.9,\(baseline)"computed_at":"\(computedAt)","scoring_state":"scored"}
        """.utf8)
    }

    private func decode(_ data: Data) throws -> DailyScore { try APIClient.jsonDecoder.decode(DailyScore.self, from: data) }

    // MARK: (c) the app's own round trip: negative results

    @Test func theWireFieldsSurviveTheReadModelRoundTrip() throws {
        let env = AppEnvironment.test()
        let repo = Repository(env: env)
        for (days, calibrating) in [(0, true), (3, true), (30, false), (0, false)] {
            let key = "2026-10-21"
            let score = DailyScore(day: key, readiness: 80, recovery: 75, baselineDays: days, calibrating: calibrating,
                                   computedAt: env.clock.now(), scoringState: .scored)
            repo.store(detail: DayDetail(score: score, sleep: nil, workouts: []))
            let viaDetail = try #require(repo.day(key)).score
            #expect(viaDetail.baselineDays == days && viaDetail.calibrating == calibrating)
            // The history list reads the same row; the detail wins over the list score, and both agree.
            repo.store(scores: [score])
            let viaList = try #require(repo.history(from: DayFormat.date(from: key)!, to: DayFormat.date(from: key)!).first)
            #expect(viaList.baselineDays == days && viaList.calibrating == calibrating)
            #expect(repo.score(key)?.calibrating == calibrating)
        }
    }

    @Test func theLegacyCacheImportKeepsThemToo() throws {
        // LegacyCacheMigration stores the old JSON through the same encode/decode; it has no field of its own.
        let score = DailyScore(day: "2026-10-21", readiness: 80, baselineDays: 5, calibrating: true)
        let back = try #require(WireCoding.decode(DailyScore.self, WireCoding.encode(score)))
        #expect(back.baselineDays == 5 && back.calibrating)
    }

    // MARK: (a) an unscored today cannot make the gauge: negative results

    @Test func absentFieldsDecodeToNotCalibrating() throws {
        // A cached copy from before the field existed, or a platform that omits it: 0 days, calibrating false.
        let absent = try decode(wire(baseline: ""))
        #expect(absent.baselineDays == 0 && !absent.calibrating)
        var f = TodaySyncFacts(now: Date(timeIntervalSince1970: 1_792_600_000))
        f.today = absent
        f.hasScoredDay = true // the history is scored: not the first import
        #expect(TodayStates.hero(f) == .score) // never "0 of 7" from a missing field
    }

    @Test func anUnscoredDayIsNotCalibratingEither() throws {
        // API.md → GET /v1/days/{day}: all numbers null, state "calibrating", calibrating false, computed_at 0001.
        let unscored = try decode(Data((#"{"day":"2026-10-21","state":"calibrating","baseline_days":0,"calibrating":false,"#
            + #""computed_at":"0001-01-01T00:00:00Z"}"#).utf8))
        #expect(!TodayStates.isScored(unscored))
        var f = TodaySyncFacts(now: Date(timeIntervalSince1970: 1_792_600_000))
        f.today = unscored
        f.hasScoredDay = true
        #expect(TodayStates.hero(f) == .score)
        let empty = DailyScore.empty(day: "2026-10-21") // MockData.detail(for:) / unknown days
        #expect(empty.resolvedState == .calibrating && !empty.calibrating && empty.baselineDays == 0)
        f.today = empty
        #expect(TodayStates.hero(f) == .score)
        // And the tiles of such a row are blank, they cannot show "Recovery 75 %": the screenshot's today was scored.
        #expect(empty.recovery == nil && unscored.recovery == nil)
    }

    // MARK: (b) the row that reproduces the screenshot

    @Test func aScoredRowWithCalibratingTrueAndZeroBaselineDaysIsTheScreenshot() throws {
        let row = try decode(wire(baseline: #""baseline_days":0,"calibrating":true,"#))
        #expect(row.readiness == 80 && row.recovery == 75 && row.calibrating && row.baselineDays == 0)
        var f = TodaySyncFacts(now: Date(timeIntervalSince1970: 1_792_600_000))
        f.today = row
        f.hasScoredDay = true
        // Without a history behind it (a new account), Today's gauge is Baselines 0 of 7 ...
        #expect(TodayStates.hero(f) == .calibrating(nights: 0))
        // ... and the widget, deciding from the same facts (T2), agrees instead of showing the score.
        let widget = ReadinessSnapshot.make(day: row.day, presentation: .decide(f.scores),
                                            now: Date(timeIntervalSince1970: 1_792_600_000))
        #expect(widget?.kind == .calibrating && widget?.baselineNights == 0)
    }

    /// Desired (brief §2 table): a calibrating flag on a scored today with ≥ 7 scored days behind it is not
    /// "0 of 7 nights"; the latest scored day's readiness shows with a "Recalculating" note. T2 decides the exact
    /// state; what must hold is that the gauge does not contradict its own tiles and the widget.
    @Test func todayDoesNotShowBaselinesBesideItsScoredTiles() throws {
        let row = try decode(wire(baseline: #""baseline_days":0,"calibrating":true,"#))
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        var f = TodaySyncFacts(now: now)
        f.today = row
        f.hasScoredDay = true
        // 30 scored days with HRV and resting HR: the baselines the platform says it lacks are there.
        f.prior = (1...30).reversed().map {
            DailyScore(day: DayFormat.string(from: DayFormat.shift(now, days: -$0)), readiness: 78, hrvMs: 55, rhr: 50,
                       baselineDays: 30)
        }
        #expect(TodayStates.hero(f) != .calibrating(nights: 0))
        let p = TodayPresentation.decide(f.scores)
        #expect(p.row == .recalculating && p.gauge == .readiness(80) && p.note == .recalculating)
        #expect(p.tiles.source == row && !p.tiles.isEarlierDay) // the gauge's day, the tiles' day
        #expect(ReadinessSnapshot.make(day: row.day, presentation: p, now: now)?.kind == .score)
    }

    /// `resolvedState` keeps the platform's D4 reading (null state, no readiness → calibrating; design.md §7), so
    /// the unknown day's own state is `standing`, and nothing presents it as calibrating.
    @Test func theUnknownDayHasItsOwnState() {
        let empty = DailyScore.empty(day: "2026-10-21")
        #expect(empty.state == nil && !empty.calibrating)
        #expect(empty.standing == .unscored)
        #expect(!ReadinessCopy.sentence(score: empty).hasPrefix("Learning your baseline"))
    }

    /// The whole path in the app: wire row → repository → AppState.today → TodayViewModel: tiles say 75 %, the
    /// hero says baselines, from one `DailyScore`.
    @Test func gaugeAndTilesComeFromTheSameRow() async throws {
        let env = AppEnvironment.test()
        let state = AppState(env: env)
        let row = try decode(wire(baseline: #""baseline_days":0,"calibrating":true,"#))
        state.history = (1...30).map { DailyScore(day: DayFormat.string(from: DayFormat.shift(env.clock.now(), days: -$0)),
                                                  readiness: 70, baselineDays: 30) }
        state.today = DayDetail(score: DailyScore(day: DayFormat.string(from: env.clock.now()), readiness: row.readiness,
                                                  recovery: row.recovery, strain: row.strain,
                                                  sleepActualMin: row.sleepActualMin, baselineDays: 0, calibrating: true,
                                                  computedAt: env.clock.now(), scoringState: .scored),
                                sleep: nil, workouts: [])
        let sync = SyncService(env: env)
        let vm = TodayViewModel(state: state, sync: sync,
                                coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                                apiStatus: APIStatus())
        // The history has no HRV or resting HR: legitimately calibrating (row B). Not "0 of 7" beside these tiles
        // (lead decision 2, amended): the platform's readiness from the same row, and the note says why.
        #expect(vm.recovery == 75 && vm.tileCaption == nil)                   // tile
        #expect(vm.hero == .score && vm.readiness == 80 && vm.readinessDelta == nil) // gauge
        #expect(vm.gaugeNote == .needsVitals)
        // With HRV and resting HR in the history it's the screenshot: the score, from the same row (row D).
        state.history = (1...30).map { DailyScore(day: DayFormat.string(from: DayFormat.shift(env.clock.now(), days: -$0)),
                                                  readiness: 70, hrvMs: 55, rhr: 50, baselineDays: 30) }
        #expect(vm.hero == .score && vm.readiness == 80 && vm.readinessDelta == nil)
        #expect(vm.recovery == 75 && !vm.tilesDimmed)
        #expect(vm.gaugeNote == .recalculating)
    }
}
