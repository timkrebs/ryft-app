import Foundation
import SwiftData
import Testing
@testable import Ryft

// Read-model writes (docs/work/2026-11-17-persistence-off-main/design.md §7.2). The "before" rows: what readers see
// after a refresh, the order of two answers, and the sign-out wipe, as the Repository does it today. They hold
// through the move of the writes off the main actor.

/// `MockDataSource` with `GET /v1/days/{day}` and `GET /v1/days` answers a test scripts: today's strain in each, and a
/// hold before each answers.
final class HeldDayAnswers: RyftDataSource {
    private let lock = NSLock()
    private var detailStrains: [Double]
    private var listStrain: Double
    let dayHold = RequestHold()
    let daysHold = RequestHold()

    /// `detail`: today's strain in each answer of the day's detail, in turn (the last one repeats); `list`: in the
    /// history's.
    init(detail: [Double], list: Double, held: Bool = false) {
        detailStrains = detail
        listStrain = list
        if !held {
            dayHold.release()
            daysHold.release()
        }
    }

    func day(_ date: Date) async throws -> DayDetail {
        await dayHold.wait()
        let strain = lock.withLock { detailStrains.count > 1 ? detailStrains.removeFirst() : detailStrains.first ?? 0 }
        var detail = MockData.todayDetail
        detail.score = DailyScore(day: DayFormat.string(from: date), readiness: 70, strain: strain)
        return detail
    }

    func days(from: Date, to: Date) async throws -> [DailyScore] {
        await daysHold.wait()
        let strain = lock.withLock { listStrain }
        return DayFormat.days(endingAt: to, count: 5).map { DailyScore(day: $0, readiness: 60, strain: strain) }
    }

    func me() async throws -> User { try await MockDataSource.shared.me() }
    func patchMe(_ p: UserPatch) async throws -> User { try await MockDataSource.shared.patchMe(p) }
    func sleep(range: SleepRangeKind) async throws -> SleepRange { try await MockDataSource.shared.sleep(range: range) }
    func workouts(from: Date, to: Date) async throws -> [Workout] {
        try await MockDataSource.shared.workouts(from: from, to: to)
    }
    func workout(id: UUID) async throws -> WorkoutDetail { try await MockDataSource.shared.workout(id: id) }
    func trends(metric: TrendMetric, range: TrendRange) async throws -> TrendSeries {
        try await MockDataSource.shared.trends(metric: metric, range: range)
    }
    func insights() async throws -> [Insight] { try await MockDataSource.shared.insights() }
    func recompute(from: Date, to: Date) async throws {}
    func deleteMe() async throws -> AccountDeleted { try await MockDataSource.shared.deleteMe() }
}

@Suite("Read-model writes: what readers see")
@MainActor
struct ReadModelReaderTests {
    /// Mid-morning, so nothing below crosses midnight.
    static let morning = Date(timeIntervalSince1970: 1_792_400_000)

    private func repository(_ source: HeldDayAnswers) -> (Repository, AppEnvironment) {
        let env = AppEnvironment.test(api: MockPlatformAPI(screens: source), clock: TestClock(now: Self.morning))
        return (Repository(env: env), env)
    }

    @Test func aRefreshReturnsAfterItsRowIsReadable() async throws {
        let (repo, env) = repository(HeldDayAnswers(detail: [12], list: 4))
        var daysChanged = 0
        repo.onDaysChanged = { daysChanged += 1 }
        let key = DayFormat.string(from: env.clock.now())

        try await repo.refreshDay(env.clock.now())

        // Readable at once, with its fetch time, and the days' readers told once.
        #expect(repo.day(key)?.score.strain == 12)
        #expect(repo.score(key)?.strain == 12)
        #expect(repo.detailFetchedAt(key) == env.clock.now())
        #expect(daysChanged == 1)
    }

    @Test func aHistoryRefreshReturnsAfterItsRowsAreReadable() async throws {
        let (repo, env) = repository(HeldDayAnswers(detail: [12], list: 4))
        var daysChanged = 0
        repo.onDaysChanged = { daysChanged += 1 }
        let now = env.clock.now()

        try await repo.refreshHistory(from: DayFormat.shift(now, days: -4), to: now)

        #expect(repo.history(from: DayFormat.shift(now, days: -4), to: now).map(\.strain) == [4, 4, 4, 4, 4])
        #expect(daysChanged == 1)
    }

    @Test func aLaterAnswerForTheSameDayWins() async throws {
        let (repo, env) = repository(HeldDayAnswers(detail: [4, 12], list: 1))
        let key = DayFormat.string(from: env.clock.now())
        try await repo.refreshDay(env.clock.now())
        #expect(repo.day(key)?.score.strain == 4)
        try await repo.refreshDay(env.clock.now(), force: true)
        #expect(repo.day(key)?.score.strain == 12)
        #expect(repo.score(key)?.strain == 12)
    }

    /// No order between the two exists (design.md §5.5): `AppState.refresh` runs them in one task group. Whichever lands
    /// last, today's score is the detail's.
    @Test(arguments: [true, false])
    func theDetailWinsWhicheverOfHistoryAndDayLandsFirst(historyFirst: Bool) async throws {
        let source = HeldDayAnswers(detail: [12], list: 4, held: true)
        let (repo, env) = repository(source)
        let now = env.clock.now()
        let key = DayFormat.string(from: now)
        let history = Task { try await repo.refreshHistory(from: DayFormat.shift(now, days: -4), to: now) }
        let day = Task { try await repo.refreshDay(now) }
        #expect(await eventually { source.dayHold.waiting == 1 && source.daysHold.waiting == 1 })
        if historyFirst {
            source.daysHold.release()
            try await history.value
            #expect(repo.score(key)?.strain == 4)
            source.dayHold.release()
            _ = try await day.value
        } else {
            source.dayHold.release()
            _ = try await day.value
            source.daysHold.release()
            try await history.value
        }
        #expect(repo.score(key)?.strain == 12)
        #expect(repo.day(key)?.score.strain == 12)
        // The list's other days are there either way.
        #expect(repo.history(from: DayFormat.shift(now, days: -4), to: now).map(\.strain) == [4, 4, 4, 4, 12])
    }

    @Test func trendsAreStaleAfterTheRefreshTrendsStage() async throws {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, clock: TestClock(now: Self.morning))
        let state = AppState(env: env)
        let steps = LiveSyncSteps(state: state, sync: SyncService.ungated(env: env))
        try await state.repository.refreshTrend(.hrv, .month)
        #expect(api.count("trends") == 1)
        try await state.repository.refreshTrend(.hrv, .month)
        #expect(api.count("trends") == 1) // fresh

        try await steps.refreshTrends() // the readiness week, newer than now

        #expect(api.count("trends") == 2)
        // The stage ended with every cached series stale: the next look asks again.
        try await state.repository.refreshTrend(.hrv, .month)
        #expect(api.count("trends") == 3)
    }
}

/// A real `AuthService` whose wipe works on the test store, as the app wires it: the store's wipe, then the account
/// hooks (`AppState.bindAccountHooks`).
@MainActor
final class WipeHarness {
    nonisolated static let a = UUID(uuidString: "0000000A-0000-4000-8000-0000000000E1") ?? UUID()
    nonisolated static let b = UUID(uuidString: "0000000B-0000-4000-8000-0000000000E2") ?? UUID()

    let clock = TestClock(now: ReadModelReaderTests.morning)
    let persistence: TrainStore
    let client = MockAuthClient(session: .preview(id: WipeHarness.a))
    let auth: AuthService
    let env: AppEnvironment
    let state: AppState

    init(persistence given: TrainStore? = nil) {
        let persistence = given ?? TrainStore(inMemory: true)
        self.persistence = persistence
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let settings = Settings(defaults: defaults)
        settings.demoMode = false
        let clock = clock
        auth = AuthService(client: client, settings: settings, defaults: defaults,
                           wipeLocalData: { wipe in persistence.wipe(parkingActivitiesOf: wipe.parking, at: clock.now()) },
                           deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                           postAppleAuthorization: { _ in })
        let api = MockPlatformAPI()
        api.now = { clock.now() }
        env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: api, demoAPI: MockPlatformAPI(),
                             auth: auth, persistence: persistence, clock: clock, notifier: MockNotifier(),
                             flags: StaticFlags([:]), connectivity: .preview(online: true), defaults: defaults,
                             demoOverride: false)
        env.reads.random = { $0.lowerBound }
        env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
        state = AppState(env: env)
        state.bindAccountHooks(auth, apiStatus: APIStatus())
    }

    var repository: Repository { state.repository }
    var today: String { DayFormat.string(from: clock.now()) }

    func signIn(_ id: UUID) async {
        client.signInSession = .preview(id: id)
        _ = await auth.logIn(email: "tim@example.com", password: "0123456789")
    }

    /// Rows of every read-model table, read through a fresh context (what the file holds, not a memo).
    func rowCount() throws -> Int {
        let c = ModelContext(persistence.container)
        return try c.fetchCount(FetchDescriptor<CachedDay>()) + c.fetchCount(FetchDescriptor<CachedTrend>())
            + c.fetchCount(FetchDescriptor<CachedInsight>()) + c.fetchCount(FetchDescriptor<CachedUser>())
            + c.fetchCount(FetchDescriptor<CachedSleepRange>()) + c.fetchCount(FetchDescriptor<CachedWorkout>())
            + c.fetchCount(FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key.starts(with: "activities.") }))
    }
}

@Suite("Read-model writes: the sign-out wipe")
@MainActor
struct ReadModelWipeTests {
    /// Every kind, through the refreshes the app runs.
    private func load(_ h: WipeHarness) async throws {
        let now = h.clock.now()
        try await h.repository.refreshDay(now)
        try await h.repository.refreshHistory(from: DayFormat.shift(now, days: -6), to: now)
        try await h.repository.refreshTrend(.readiness, .week)
        try await h.repository.refreshInsights()
        try await h.repository.refreshUser()
        try await h.repository.refreshSleepRange(.week)
        try await h.repository.refreshWorkout(MockData.todayDetail.workouts[0].id)
    }

    @Test func aSignOutEmptiesEveryReadModelAndItsReaders() async throws {
        let h = WipeHarness()
        try await load(h)
        #expect(try h.rowCount() > 0)
        #expect(h.repository.day(h.today) != nil && h.repository.user() != nil && !h.repository.insights().isEmpty)

        await h.auth.signOut()

        #expect(try h.rowCount() == 0)
        #expect(h.repository.day(h.today) == nil && h.repository.score(h.today) == nil)
        #expect(h.repository.user() == nil && h.repository.insights().isEmpty)
        #expect(h.repository.trend(.readiness, .week) == nil && h.repository.sleepRange(.week) == nil)
        #expect(h.repository.history(from: DayFormat.shift(h.clock.now(), days: -6), to: h.clock.now()).isEmpty)
    }

    @Test func anotherAccountSeesNothingOfTheFirst() async throws {
        let h = WipeHarness()
        try await load(h)
        await h.auth.signOut()
        await h.signIn(WipeHarness.b)
        #expect(h.auth.accountID != nil)
        #expect(try h.rowCount() == 0)
        #expect(h.repository.day(h.today) == nil && h.repository.user() == nil)
    }

    @Test func anAnswerThatLandsAfterTheSignOutIsDropped() async throws {
        let h = WipeHarness()
        let source = HeldDayAnswers(detail: [12], list: 4, held: true)
        let api = MockPlatformAPI(screens: source)
        let env = AppEnvironment(settings: h.env.settings, health: MockHealthStore(), liveAPI: api, demoAPI: api,
                                 auth: h.auth, persistence: h.persistence, clock: h.clock, notifier: MockNotifier(),
                                 flags: StaticFlags([:]), connectivity: .preview(online: true), defaults: h.env.defaults,
                                 demoOverride: false)
        env.reads.random = { $0.lowerBound }
        let repo = Repository(env: env)
        let day = Task { try await repo.refreshDay(h.clock.now()) }
        #expect(await eventually { source.dayHold.waiting == 1 })
        await h.auth.signOut()
        source.dayHold.release()
        _ = try? await day.value
        #expect(try h.rowCount() == 0)
        #expect(repo.day(h.today) == nil)
    }
}

/// Records the days a `.daysChanged` run was started for (`accepted`), and nothing else.
@MainActor
final class AcceptedDaysSteps: SyncSteps {
    private(set) var accepted: [[String]] = []
    func accepted(_ days: [String]) { accepted.append(days) }
    func upload() async throws -> [String] { [] }
    var hasBacklog: Bool { false }
    var isWaitingForUnlock: Bool { false }
    var isUploading: Bool { false }
    func stopAfterCurrentPage() async {}
    var expectedScoringSeconds: Int? { 3 }
    func syncStatus() async throws -> SyncStatus { throw CancellationError() }
    func refreshDays(_ days: [String]) async throws {}
    func refreshTrends() async throws {}
    func refreshInsights() async throws {}
    func refreshStale() async {}
    func report(_ phase: SyncPhase) {}
}

@Suite("Read-model writes: the writers outside a refresh")
@MainActor
struct ReadModelOtherWritersTests {
    private static func activity(_ id: UUID, on day: Date) -> SportActivity {
        SportActivity(id: id, sport: .running, origin: .manual, start: day, end: day.addingTimeInterval(600),
                      movingSec: 600, clientUpdatedAt: day)
    }

    /// The uploader's follow-up (`ActivityUploader.connect`): an activity the platform confirmed on today, cached two
    /// days ago before its start was edited, moves to today's list, and both days are rescored.
    @Test func aConfirmedActivityMovedFromAnotherDayRescoresBoth() async throws {
        let clock = TestClock(now: ReadModelReaderTests.morning)
        let env = AppEnvironment.test(clock: clock)
        let state = AppState(env: env)
        let steps = AcceptedDaysSteps()
        let coordinator = SyncCoordinator(steps: steps, clock: clock)
        env.uploader.connect(repository: state.repository, coordinator: coordinator)
        let now = clock.now()
        let today = DayFormat.string(from: now)
        let twoDaysAgo = DayFormat.string(from: DayFormat.shift(now, days: -2))
        let id = UUID(), other = UUID()
        state.repository.store(activities: [Self.activity(id, on: DayFormat.shift(now, days: -2)),
                                            Self.activity(other, on: DayFormat.shift(now, days: -2))], day: twoDaysAgo)

        env.uploader.onConfirmed?(Self.activity(id, on: now), [today])

        #expect(await eventually { !steps.accepted.isEmpty })
        #expect(steps.accepted == [[twoDaysAgo, today]])
        #expect(state.repository.activities(day: today).map(\.id) == [id])
        #expect(state.repository.activities(day: twoDaysAgo).map(\.id) == [other])
        await coordinator.cancel()
    }

    @Test func aConfirmedDeleteRescoresTheDayItWasCachedUnder() async throws {
        let clock = TestClock(now: ReadModelReaderTests.morning)
        let env = AppEnvironment.test(clock: clock)
        let state = AppState(env: env)
        let steps = AcceptedDaysSteps()
        let coordinator = SyncCoordinator(steps: steps, clock: clock)
        env.uploader.connect(repository: state.repository, coordinator: coordinator)
        let now = clock.now()
        let yesterday = DayFormat.string(from: DayFormat.shift(now, days: -1))
        let id = UUID()
        state.repository.store(activities: [Self.activity(id, on: DayFormat.shift(now, days: -1))], day: yesterday)

        env.uploader.onRemoved?(id, [DayFormat.string(from: now)])

        #expect(await eventually { !steps.accepted.isEmpty })
        #expect(steps.accepted == [[yesterday, DayFormat.string(from: now)]])
        #expect(state.repository.activities(day: yesterday).isEmpty)
        await coordinator.cancel()
    }

    /// Nightly compaction: what goes, and its count.
    @Test func compactionRemovesWhatItRemovedBefore() async throws {
        let clock = TestClock(now: ReadModelReaderTests.morning)
        let env = AppEnvironment.test(clock: clock)
        let repo = Repository(env: env)
        let start = clock.now()
        func key(_ days: Int) -> String { DayFormat.string(from: DayFormat.shift(start, days: days)) }
        repo.store(scores: [DailyScore(day: key(-400)), DailyScore(day: key(-366)), DailyScore(day: key(-10))])
        let workout = MockData.workoutDetail(MockData.todayDetail.workouts[0])
        repo.store(workout: workout)
        repo.store(trend: MockData.trend(.hrv, range: .week), metric: .hrv, range: .week)
        repo.store(activities: [Self.activity(UUID(), on: DayFormat.shift(start, days: -400))], day: key(-400))
        repo.store(activities: [Self.activity(UUID(), on: DayFormat.shift(start, days: -30))], day: key(-30))
        env.persistence.saveDocument(["old"], key: "train.history.old", at: start)
        clock.advance(by: .seconds(31 * 86_400))
        repo.store(trend: MockData.trend(.hrv, range: .month), metric: .hrv, range: .month)
        env.persistence.saveDocument(["new"], key: "train.history.new", at: clock.now())

        // Queued behind the writes above: the queue keeps submit order.
        let removed = await repo.compact()

        // Two days beyond a year, the workout and the week's series unopened for 30 and 7 days, one Train document,
        // one day's activities.
        #expect(removed == 6)
        let all = repo.history(from: DayFormat.shift(clock.now(), days: -500), to: clock.now())
        #expect(all.map(\.day) == [key(-10)])
        #expect(repo.workout(workout.workout.id) == nil)
        #expect(repo.trend(.hrv, .week) == nil && repo.trend(.hrv, .month) != nil)
        #expect(env.persistence.document([String].self, key: "train.history.old") == nil)
        #expect(env.persistence.document([String].self, key: "train.history.new") == ["new"])
        #expect(repo.activitiesFetchedAt(day: key(-400)) == nil && repo.activitiesFetchedAt(day: key(-30)) != nil)
    }
}
