import Foundation
import Testing
@testable import Ryft

// The My Day view model (design.md §7.2): it reads caches only, `load` revalidates through the Repository, and a
// failed or stale read says so. Everything runs on the test graph (`AppEnvironment.test()`, `TestClock`, the
// in-memory platform): no sleeps, no network. The platform starts unseeded; a test seeds what it needs.

@MainActor
private struct Graph {
    let api: MockPlatformAPI
    let clock: TestClock
    let env: AppEnvironment
    let state: AppState
    let store = TrainStore(inMemory: true)
    let vm: MyDayViewModel

    /// `.now` for the clock: the mock day detail is generated around it.
    init(seed: @escaping @Sendable (Date) -> [SportActivity] = { _ in [] },
         flags: [FeatureFlag: Bool] = [.todayMyDay: true], online: Bool = true) {
        clock = TestClock(now: .now)
        api = MockPlatformAPI(activities: MockActivitiesSource(now: { [clock] in clock.now() }, seed: seed))
        env = .test(api: api, clock: clock, flags: flags, online: online)
        state = AppState(env: env)
        vm = MyDayViewModel(state: state, store: store)
    }

    var today: Date { vm.today }
    var key: String { DayFormat.string(from: today) }
}

/// Today's mock tracker run (the one the demo merges), by id.
@MainActor
private func mockRun(on date: Date) -> Workout? {
    MockData.detail(for: date).workouts.first { $0.activity == "running" }
}

private func yoga(on day: Date) -> SportActivity {
    let start = Calendar.current.date(byAdding: .minute, value: 30, to: Calendar.current.startOfDay(for: day)) ?? day
    return SportActivity(id: UUID(uuidString: "00000000-0000-4000-8000-0000000000a3") ?? UUID(), sport: .yoga,
                         origin: .manual, start: start, end: start.addingTimeInterval(1_800), movingSec: 1_800,
                         clientUpdatedAt: start.addingTimeInterval(1_900), strain: 3.4, strainSource: .perceivedEffort,
                         scoringState: "scored")
}

// MARK: - reads

@Suite("My Day view model: reads")
@MainActor
struct MyDayReadTests {
    @Test func readingTheCardAndTheItemsAsksThePlatformForNothing() {
        let g = Graph(seed: { [yoga] in [yoga($0)] })
        _ = g.vm.card
        _ = g.vm.items(for: g.today)
        _ = g.vm.content(for: DayFormat.shift(g.today, days: -1))
        _ = g.vm.week

        #expect(g.api.calls.isEmpty, "calls: \(g.api.calls)")
    }

    @Test func withNothingCachedTheDayIsLoadingNotEmptyOrFailed() {
        let content = Graph().vm.card
        #expect(content.phase == .loading)
        #expect(content.items.isEmpty)
        #expect(content.staleSince == nil)
    }

    @Test func theFlagDecidesWhetherTheFeatureIsOn() {
        #expect(Graph().vm.isEnabled)
        #expect(!Graph(flags: [:]).vm.isEnabled)
        #expect(!Graph(flags: [.todayMyDay: false]).vm.isEnabled)
    }

    @Test func theCardIsAlwaysTodayWhateverTheFullScreenSelected() {
        let g = Graph()
        g.vm.select(DayFormat.shift(g.today, days: -3))
        #expect(g.vm.card.isToday)
        #expect(g.vm.card.day == g.today)
        #expect(!g.vm.content(for: g.vm.date).isToday)
    }

    @Test func theWeekIsSevenDaysEndingTodayWithTheSelectedOneMarked() {
        let g = Graph()
        g.vm.select(DayFormat.shift(g.today, days: -2))
        #expect(g.vm.week.count == 7)
        #expect(g.vm.week.last?.date == g.today)
        #expect(g.vm.week.filter(\.isSelected).map(\.date) == [DayFormat.shift(g.today, days: -2)])
    }
}

// MARK: - load

@Suite("My Day view model: load")
@MainActor
struct MyDayLoadTests {
    @Test func loadRevalidatesTheDayAndItsActivitiesSideBySide() async {
        let g = Graph(seed: { [yoga] in [yoga($0)] })

        await g.vm.load(g.today)

        #expect(g.api.count("day") == 1)
        #expect(g.api.count("activities") == 1)
        let content = g.vm.card
        #expect(content.phase == .ready)
        #expect(content.items.contains { $0.kind == .activity(yoga(on: g.today).id) })
        #expect(content.staleSince == nil)
    }

    @Test func aFreshDayIsNotAskedAgainUntilForced() async {
        let g = Graph()
        await g.vm.load(g.today)
        await g.vm.load(g.today)
        #expect(g.api.count("day") == 1)
        #expect(g.api.count("activities") == 1)

        await g.vm.load(g.today, force: true)
        #expect(g.api.count("day") == 2)
        #expect(g.api.count("activities") == 2)
    }

    @Test func aPastDayLoadsItsOwnDayAndItsOwnActivities() async {
        let g = Graph()
        let yesterday = DayFormat.shift(g.today, days: -1)
        await g.vm.load(yesterday)
        #expect(g.api.count("day") == 1)
        #expect(g.api.count("activities") == 1)
        #expect(g.vm.content(for: yesterday).phase == .ready)
        #expect(g.vm.card.phase == .loading, "today wasn't asked")
    }

    @Test func aMergedRunShowsOnceWithTwoBadgesAfterTheLoad() async throws {
        let run = try #require(mockRun(on: .now))
        let g = Graph(seed: { date in
            [SportActivity(id: UUID(uuidString: "00000000-0000-4000-8000-0000000a0001") ?? UUID(), sport: .running,
                           origin: .recorded, start: run.start, end: run.end, movingSec: run.duration - 240,
                           distanceM: 8_420, clientUpdatedAt: date, strain: 10.1, strainSource: .heartRate,
                           hrSource: run.source, mergedWith: run.id, scoringState: "scored")]
        })
        await g.vm.load(g.today)
        let items = g.vm.card.items
        #expect(!items.contains { $0.kind == .workout(run.id) }, "the tracker's row is hidden")
        let row = try #require(items.first { $0.isMerged })
        #expect(row.sources.count == 2)
        #expect(g.vm.workout(run.id, on: g.today)?.id == run.id, "the workout is still cached for its detail")
    }

    @Test func offlineLoadSendsNothingAndKeepsWhatIsCached() async {
        let g = Graph()
        await g.vm.load(g.today)
        let cached = g.vm.card.items.map(\.id)
        g.env.connectivityMonitor.update(false)

        await g.vm.load(g.today, force: true)

        #expect(g.vm.card.items.map(\.id) == cached)
        #expect(g.vm.card.phase == .ready)
    }
}

// MARK: - failed and stale

@Suite("My Day view model: failed and stale")
@MainActor
struct MyDayFailureTests {
    private let offline = APIError.transport(URLError(.notConnectedToInternet))

    @Test func aFailedLoadWithNothingCachedIsFailedNotLoading() async {
        let g = Graph()
        g.api.failure = offline

        await g.vm.load(g.today)

        #expect(g.vm.card.phase == .failed)
        #expect(g.vm.failed.contains(g.key))
        #expect(g.vm.card.items.isEmpty)
        #expect(g.vm.card.staleSince == nil)
    }

    @Test func failedIsPerDay() async {
        let g = Graph()
        g.api.failure = offline
        await g.vm.load(g.today)
        #expect(g.vm.content(for: DayFormat.shift(g.today, days: -1)).phase == .loading)
    }

    @Test func tryAgainClearsTheFailureWhenTheLoadWorks() async {
        let g = Graph()
        g.api.failure = offline
        await g.vm.load(g.today)
        g.api.failure = nil

        await g.vm.load(g.today, force: true)

        #expect(g.vm.card.phase == .ready)
        #expect(!g.vm.failed.contains(g.key))
    }

    @Test func aCancelledLoadIsNotAFailure() async {
        let g = Graph()
        g.api.faults["day"] = .init(.cancel)
        await g.vm.load(g.today)
        #expect(!g.vm.failed.contains(g.key))
        #expect(g.vm.card.phase != .failed)
    }

    @Test func aFailureAfterALoadKeepsTheListAndSaysSinceWhen() async throws {
        let g = Graph(seed: { [yoga] in [yoga($0)] })
        await g.vm.load(g.today)
        let loaded = g.clock.now()
        let rows = g.vm.card.items.map(\.id)
        g.clock.advance(by: .seconds(30))
        g.api.failure = offline

        await g.vm.load(g.today, force: true)

        let content = g.vm.card
        #expect(content.phase == .ready, "never replaced by an error")
        #expect(content.items.map(\.id) == rows)
        #expect(content.staleSince == loaded)
        #expect(!content.offersRetry, "30 s: too early to offer Try again")
    }

    @Test func tryAgainJoinsTheStaleCaptionAfterTwoMinutes() async {
        let g = Graph()
        await g.vm.load(g.today)
        g.clock.advance(by: .seconds(MyDayContent.retryAfter + 1))
        g.api.failure = offline

        await g.vm.load(g.today, force: true)

        #expect(g.vm.card.staleSince != nil)
        #expect(g.vm.card.offersRetry)
    }

    @Test func aLoadThatWorksAgainClearsTheStaleCaption() async {
        let g = Graph()
        await g.vm.load(g.today)
        g.clock.advance(by: .seconds(600))
        g.api.failure = offline
        await g.vm.load(g.today, force: true)
        #expect(g.vm.card.staleSince != nil)
        g.api.failure = nil

        await g.vm.load(g.today, force: true)

        #expect(g.vm.card.staleSince == nil)
        #expect(!g.vm.card.offersRetry)
    }

    @Test func offlineWithACacheIsStaleSinceTheFetch() async {
        let g = Graph()
        await g.vm.load(g.today)
        let loaded = g.clock.now()
        g.clock.advance(by: .seconds(600))
        g.env.connectivityMonitor.update(false)

        #expect(g.vm.card.staleSince == loaded)
        #expect(g.vm.card.phase == .ready)
    }

    @Test func aFailedActivitiesReadAloneIsStaleToo() async {
        let g = Graph()
        await g.vm.load(g.today)
        g.clock.advance(by: .seconds(600))
        g.api.faults["activities"] = .init(.timeout)

        await g.vm.load(g.today, force: true)

        #expect(g.vm.card.phase == .ready)
        #expect(g.vm.card.staleSince != nil)
    }
}

// MARK: - the card's own rules

@Suite("My Day view model: the card's rows")
struct MyDayContentTests {
    private func item(_ n: Int, hour: Int, sleep: Bool = false) -> MyDayItem {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: DayFormat.date(from: "2026-10-22") ?? .now) ?? .now
        let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n)) ?? UUID()
        return MyDayItem(id: sleep ? "sleep.2026-10-22" : "activity.\(id)", kind: sleep ? .sleep(day: "2026-10-22") : .activity(id),
                         symbol: "figure.run", title: "Run", start: start, end: start.addingTimeInterval(1_800),
                         duration: 1_800, distanceM: nil, strain: .pending, sources: [.ryftManual], upload: nil, editable: true)
    }

    private func content(_ items: [MyDayItem]) -> MyDayContent {
        MyDayContent(day: DayFormat.date(from: "2026-10-22") ?? .now, isToday: true, phase: .ready, items: items)
    }

    @Test func upToFiveRowsAreAllShown() {
        let c = content((1...5).map { item($0, hour: $0 + 6) })
        #expect(c.cardRows.count == 5)
        #expect(!c.showsAll)
    }

    @Test func overFiveTheNightStaysAndTheLatestOthersFollow() {
        let c = content([item(0, hour: 6, sleep: true)] + (1...7).map { item($0, hour: $0 + 6) })
        #expect(c.cardRows.count == 5)
        #expect(c.cardRows.first?.kind.isSleep == true)
        #expect(c.cardRows.dropFirst().map(\.id) == c.items.suffix(4).map(\.id))
        #expect(c.showsAll)
    }

    @Test func aDayWithOnlyTheNightHasNoActivities() {
        let c = content([item(0, hour: 6, sleep: true)])
        #expect(c.hasNoActivities)
        #expect(!c.isEmpty)
        #expect(c.summary == nil)
    }

    @Test func aDayWithNothingButTheMissingNightIsEmpty() {
        #expect(content([]).isEmpty)
    }
}

// MARK: - Strain's list behind the flag

@Suite("My Day: Strain's activity list behind today.my_day")
@MainActor
struct MyDayStrainFlagTests {
    private let mergedID = UUID(uuidString: "00000000-0000-4000-8000-0000000a0001") ?? UUID()

    /// A platform that holds RYFT's merged run for today, and a Strain view model on it.
    private func strain(flag: Bool) throws -> (StrainViewModel, MockPlatformAPI, Workout) {
        let run = try #require(mockRun(on: .now))
        let id = mergedID
        let g = Graph(seed: { date in
            [SportActivity(id: id, sport: .running, origin: .recorded, start: run.start, end: run.end,
                           movingSec: run.duration - 240, distanceM: 8_420, clientUpdatedAt: date, strain: 10.1,
                           strainSource: .heartRate, hrSource: run.source, mergedWith: run.id, scoringState: "scored")]
        }, flags: flag ? [.todayMyDay: true] : [:])
        return (StrainViewModel(state: g.state, store: g.store), g.api, run)
    }

    @Test func withTheFlagOffStrainListsExactlyTheOldMergeAndAsksForNoActivities() async throws {
        let (vm, api, run) = try strain(flag: false)

        await vm.load()

        #expect(!vm.showsMyDayList)
        #expect(api.count("activities") == 0, "no activities read")
        let detail = try #require(vm.detail)
        // What `main` shows: the day's workouts by start, then logged sessions no workout points at.
        let linked = Set(detail.workouts.flatMap { w in
            (detail.strain?.sessions ?? []).filter { $0.id == w.sessionId || $0.workoutId == w.id }.map(\.id)
        })
        let expected = detail.workouts.sorted { $0.start < $1.start }.map(\.id)
            + (detail.strain?.sessions ?? []).filter { $0.status == .completed && !linked.contains($0.id) }.map(\.id)
        #expect(Set(vm.activities.map(\.id)) == Set(expected))
        #expect(vm.activities.map(\.id).contains(run.id), "the tracker's run keeps its own row: nothing merged")
        #expect(!vm.activities.map(\.id).contains(mergedID), "no RYFT activity")
        #expect(vm.activities.map(\.start) == vm.activities.map(\.start).sorted())
    }

    @Test func withTheFlagOnTheSameDayListsRYFTActivitiesAndHidesTheMergedWorkout() async throws {
        let (vm, api, run) = try strain(flag: true)

        await vm.load()

        #expect(vm.showsMyDayList)
        #expect(api.count("activities") == 1)
        let ids = vm.dayItems.map(\.id)
        #expect(ids.contains("activity.\(mergedID.uuidString)"))
        #expect(!ids.contains("workout.\(run.id.uuidString)"))
        #expect(!vm.dayItems.contains { $0.kind.isSleep }, "Strain's list has no night")
    }
}

// MARK: - review fixes

@Suite("My Day view model: flag, pull to refresh, touched days, names")
@MainActor
struct MyDayReviewFixTests {
    @Test func withTheFlagOffLoadAsksForNoActivities() async {
        let g = Graph(flags: [:])
        await g.vm.load(g.today)
        #expect(g.api.count("activities") == 0)
        #expect(g.api.count("day") == 1)
    }

    @Test func pullToRefreshOnTodayLeavesTodaysReadToTheAppsPullAndAsksForTheActivities() async {
        let g = Graph()
        await g.vm.load(g.today)
        var pulled = 0

        await g.vm.refresh(g.today) { pulled += 1 }

        #expect(pulled == 1)
        #expect(g.api.count("day") == 1, "today's detail isn't asked a second time")
        // The activities are asked beside the pull, not waited for.
        for _ in 0..<200 where g.api.count("activities") < 2 { await Task.yield() }
        #expect(g.api.count("activities") == 2)
    }

    @Test func pullToRefreshOnAPastDayAsksForItsReadsAgainAndNotTheAppsPull() async {
        let g = Graph()
        let yesterday = DayFormat.shift(g.today, days: -1)
        await g.vm.load(yesterday)

        await g.vm.refresh(yesterday) { Issue.record("a past day doesn't run the app's pull") }

        #expect(g.api.count("day") == 2)
        #expect(g.api.count("activities") == 2)
    }

    @Test func touchedDaysRefreshTheirActivitiesOnlyInsideTheWeek() async throws {
        let g = Graph()
        let inside = DayFormat.string(from: DayFormat.shift(g.today, days: -2))
        let outside = DayFormat.string(from: DayFormat.shift(g.today, days: -30))

        try await g.state.refreshDays([inside, outside])

        #expect(g.api.count("activities") == 1)
    }

    @Test func touchedDaysRefreshNoActivitiesWithTheFlagOff() async throws {
        let g = Graph(flags: [:])
        try await g.state.refreshDays([DayFormat.string(from: g.today)])
        #expect(g.api.count("activities") == 0)
    }

    @Test func trackersAreNamedOnlyOnceTheCatalogIsParsedOffTheMainActor() async {
        let g = Graph()
        #expect(!g.vm.namesTrackers, "the first frame names nothing by the catalog")
        await g.vm.load(g.today)
        #expect(g.vm.namesTrackers, "MockData's today has workouts to name")
    }
}
