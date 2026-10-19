import Foundation
import Testing
@testable import Ryft

/// A signed-in test graph (in-memory store), its read state and the clock.
@MainActor
private func makeState(api: MockPlatformAPI = MockPlatformAPI(), health: MockHealthStore = MockHealthStore(),
                       now: Date = .now, online: Bool = true) -> (AppEnvironment, AppState, TestClock) {
    let clock = TestClock(now: now)
    let env = AppEnvironment.test(api: api, health: health, clock: clock, online: online)
    return (env, AppState(env: env), clock)
}

private func day(_ offset: Int, from date: Date = .now) -> String {
    DayFormat.string(from: DayFormat.shift(date, days: offset))
}

// MARK: - Today

/// Each view model gets its own `APIStatus`: the shared one carries retry notices
/// from other suites running in parallel.
@Suite("Today view model")
@MainActor
struct TodayViewModelTests {
    @Test func loadsTheBriefing() async {
        let (env, state, _) = makeState()
        let vm = TodayViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())
        #expect(vm.readiness == nil)
        #expect(vm.sleepText == Fmt.placeholder)

        await state.refresh()

        #expect(vm.readiness == state.today?.score.readiness.map(Double.init))
        #expect(vm.recoveryText == Fmt.percent(state.today?.score.recovery))
        #expect(vm.recoveryBand != nil)
        #expect(vm.readinessWeek.count == state.readinessWeek?.points.count)
        #expect(vm.status == nil)
        #expect(vm.lastUpdated == env.clock.now())
    }

    @Test func greetingFollowsTheClock() {
        let morning = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        let (env, state, clock) = makeState(now: morning)
        let vm = TodayViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())
        #expect(vm.greeting == String(localized: "Good morning,"))
        clock.set(Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now)!)
        #expect(vm.greeting == String(localized: "Good evening,"))
    }

    @Test func failureWithoutDataShowsTheError() async {
        let api = MockPlatformAPI()
        api.failure = APIError.http(500, "")
        let (env, state, _) = makeState(api: api)
        let vm = TodayViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())

        await state.refresh()

        #expect(vm.status == .error(message: APIError.http(500, "").localizedDescription, details: "HTTP 500"))
    }

    @Test func failureWithDataSaysItsTheLastLoaded() async {
        let api = MockPlatformAPI()
        let (env, state, clock) = makeState(api: api)
        let vm = TodayViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())
        await state.refresh()
        api.failure = APIError.http(503, "")
        clock.advance(by: .seconds(6 * 60)) // today's 5 minutes are over: it asks again

        await state.refresh()

        guard case .error(let message, _) = vm.status else {
            Issue.record("expected an error status, got \(String(describing: vm.status))")
            return
        }
        #expect(message == String(localized: "Couldn't refresh just now — showing your last loaded data."))
        #expect(vm.readiness != nil) // still on screen
    }

    @Test func offlineShowsThePillAndRequestsNothing() async {
        let api = MockPlatformAPI()
        let (env, state, _) = makeState(api: api, online: false)
        let vm = TodayViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())

        await vm.refresh()

        #expect(vm.isOffline)
        #expect(api.calls.isEmpty)
        #expect(vm.status == nil)
    }

    @Test func calibratingSaysHowManyNightsToGo() {
        let (env, state, _) = makeState()
        var detail = MockData.todayDetail
        detail.score = MockData.calibratingScore
        state.today = detail
        let vm = TodayViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())
        #expect(vm.sentence == ReadinessCopy.sentence(score: MockData.calibratingScore))
        #expect(vm.readiness == nil)
    }

    @Test func failedHealthUploadPausesSync() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [
            HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "x")])
        ]])
        let api = MockPlatformAPI()
        api.failNext = APIError.http(500, "")
        let (env, state, _) = makeState(api: api, health: health)
        let sync = SyncService(env: env)
        let vm = TodayViewModel(state: state, sync: sync, apiStatus: APIStatus())

        await sync.syncNow()

        guard case .syncPaused(let message, let details) = vm.status else {
            Issue.record("expected syncPaused, got \(String(describing: vm.status))")
            return
        }
        #expect(message.contains(APIError.http(500, "").localizedDescription))
        #expect(details == "HTTP 500")
    }

    @Test func tilesOpenTheirTabs() {
        let (env, state, _) = makeState()
        let vm = TodayViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())
        vm.open(.strain)
        #expect(state.selectedTab == .strain)
    }
}

// MARK: - Strain

@Suite("Strain view model")
@MainActor
struct StrainViewModelTests {
    @Test func startsOnTodayWithAWeekStrip() {
        let (_, state, _) = makeState()
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        #expect(vm.isToday)
        #expect(vm.title == String(localized: "Today"))
        #expect(vm.week.count == 7)
        #expect(vm.week.last?.isSelected == true)
        #expect(vm.week.filter(\.isSelected).count == 1)
    }

    @Test func pastDayLoadsItsDetail() async {
        let api = MockPlatformAPI()
        let (_, state, _) = makeState(api: api)
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        vm.select(DayFormat.shift(.now, days: -1))

        await vm.load()

        #expect(!vm.isToday)
        #expect(vm.title == String(localized: "Yesterday"))
        #expect(vm.detail?.score.day == day(-1))
        #expect(api.count("day") == 1)
        #expect(vm.week[5].isSelected)
    }

    @Test func deltaAgainstTheSevenDaysBefore() {
        let (_, state, _) = makeState()
        state.history = (1...7).map { DailyScore(day: day(-$0), strain: 10) } + [DailyScore(day: day(0), strain: 13)]
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        #expect(vm.strain == 13)
        #expect(vm.strainDelta == MetricDelta(current: 13, reference: 10))
        #expect(vm.week.map(\.strain) == [10, 10, 10, 10, 10, 10, 13])
    }

    @Test func failureWithoutCacheShowsTheError() async {
        let api = MockPlatformAPI()
        api.failure = APIError.transport(URLError(.notConnectedToInternet))
        let (_, state, _) = makeState(api: api)
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))

        await vm.load()

        #expect(vm.error != nil)
        #expect(vm.activities.isEmpty)
    }

    @Test func offlineKeepsTheCachedDay() async throws {
        let api = MockPlatformAPI()
        let (_, state, _) = makeState(api: api)
        _ = try await state.dayDetail(for: .now) // cached once
        api.failure = APIError.transport(URLError(.notConnectedToInternet))
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))

        await vm.load()

        #expect(vm.error == nil)
        #expect(vm.detail != nil)
    }
}

// MARK: - Sleep

@Suite("Sleep view model")
@MainActor
struct SleepViewModelTests {
    @Test func stepsBackButNotIntoTheFuture() async {
        let (_, state, _) = makeState()
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        #expect(vm.subtitle == String(localized: "Last night"))
        #expect(!vm.canStepForward)

        await vm.step(by: -1)
        #expect(vm.subtitle == String(localized: "Yesterday"))
        #expect(vm.canStepForward)
        #expect(vm.sleep != nil)

        await vm.step(by: 1)
        await vm.step(by: 1) // refused: tomorrow
        #expect(vm.isToday)
    }

    @Test func weekModeLoadsTheRange() async {
        let (_, state, _) = makeState()
        let vm = SleepViewModel(state: state)
        vm.mode = .week
        await vm.load()
        #expect(vm.range?.range == SleepRangeKind.week.rawValue)
        #expect(vm.subtitle == String(localized: "Last 7 nights"))
        #expect(!vm.canStepBack)
    }

    @Test func failureWithoutCacheShowsTheError() async {
        let api = MockPlatformAPI()
        api.failure = APIError.http(500, "")
        let (_, state, _) = makeState(api: api)
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        await vm.load()
        #expect(vm.error != nil)
    }

    @Test func nightSummaryComparesWithTheNeed() throws {
        let sleep = try #require(MockData.todayDetail.sleep)
        let score = DailyScore(day: day(0), sleepNeedMin: 500, sleepActualMin: 450, sleepDebtMin: 60)
        let summary = SleepNightSummary(sleep: sleep, score: score)
        #expect(summary.actualOfNeed == String(localized: "90% of need"))
        #expect(summary.debtIsHigh)
        #expect(SleepNightSummary(sleep: sleep, score: DailyScore(day: day(0), sleepDebtMin: 0)).debt
            == String(localized: "None"))
    }

    @Test func rangeSummaryBuildsBarsAndRegularity() {
        let summary = SleepRangeSummary(range: MockData.sleepRange(.week))
        #expect(!summary.bars.isEmpty)
        #expect(summary.window == .week)
        #expect(summary.tallestNight > 0)
        #expect(summary.regularity != .unknown)
    }
}

// MARK: - Insights

@Suite("Insights view model")
@MainActor
struct InsightsViewModelTests {
    @Test func loadsEveryMetricAndBandsOnlyPersonalRanges() async {
        let (_, state, _) = makeState()
        let vm = InsightsViewModel(state: state)
        vm.range = .week

        await vm.load()

        #expect(vm.series.count == TrendMetric.allCases.count)
        #expect(vm.monthly[.hrv]?.range == TrendRange.month.rawValue)
        #expect(vm.band(for: .hrv) != nil)
        #expect(vm.band(for: .strain) == nil)
    }

    @Test func emptyMessageDependsOnWhy() async {
        let (_, state, _) = makeState()
        let vm = InsightsViewModel(state: state)
        #expect(vm.emptyMessage == String(localized: "Nothing stands out today. Insights appear when your data shifts."))
        state.insights = MockData.insights
        #expect(vm.emptyMessage == nil)
        for i in MockData.insights { vm.dismiss(i) }
        #expect(vm.emptyMessage == String(localized: "All caught up for today."))
    }

    @Test func noDataSourceLoadsNothing() async {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, auth: .preview(signedIn: false))
        let state = AppState(env: env)
        let vm = InsightsViewModel(state: state)
        await vm.load()
        #expect(api.calls.isEmpty)
    }
}

// MARK: - Profile

@Suite("Profile view model")
@MainActor
struct ProfileViewModelTests {
    @Test func accountFallsBackFromNameToEmail() {
        let (env, state, _) = makeState()
        let vm = ProfileViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())
        state.user = User(id: UUID(), name: "", email: "a@b.c", provider: "email", tz: TimeZone.current.identifier,
                          maxHr: 185, sleepBaseMin: 450)
        #expect(vm.accountTitle == "a@b.c")
        #expect(vm.accountSubtitle == nil)
        #expect(vm.canChangePassword)
        #expect(vm.providerBadge?.systemImage == "envelope.fill")
        #expect(vm.timezoneDetail == nil)

        vm.applyUser()
        #expect(vm.maxHR == 185 && vm.sleepBase == 450)
    }

    @Test func recomputeWaitsForScoringOnTheClock() async {
        let api = MockPlatformAPI()
        let (env, state, clock) = makeState(api: api)
        let vm = ProfileViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())
        let run = Task { await vm.applyAndRecompute() }

        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(vm.recomputing)
        #expect(vm.recomputeStatus == String(localized: "Recomputing — scores update in a few seconds."))
        #expect(api.count("recompute") == 1 && api.count("patchMe") == 1)
        clock.advance(by: SyncService.rescoreDelay)
        await run.value

        #expect(!vm.recomputing)
        #expect(vm.recomputeStatus == String(localized: "Scores recomputed with your new settings."))
    }

    @Test func failedRecomputeSaysWhy() async {
        let api = MockPlatformAPI()
        let (env, state, _) = makeState(api: api)
        let vm = ProfileViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())
        api.failure = APIError.http(429, "")
        await vm.applyAndRecompute()
        #expect(vm.recomputeStatus == APIError.http(429, "").localizedDescription)
    }

    @Test func healthStatusComesFromTheStore() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let (env, state, _) = makeState(health: health)
        let vm = ProfileViewModel(state: state, sync: SyncService(env: env), apiStatus: APIStatus())
        await vm.refreshHealthStatus()
        #expect(vm.canAskForHealth && vm.healthNeedsAttention)
        await vm.requestHealthAccess()
        #expect(health.authorizationRequests == 1)
        #expect(vm.healthStatusText == String(localized: "Requested"))
    }
}

// MARK: - Train

@Suite("Train view models")
@MainActor
struct TrainViewModelTests {
    private func library(_ api: MockPlatformAPI = MockPlatformAPI()) -> TrainLibrary {
        TrainLibrary(store: TrainStore(inMemory: true), remote: { api }, restore: false)
    }

    @Test func historyGroupsByWeekNewestFirst() async {
        let vm = TrainHistoryViewModel(library: library())
        #expect(!vm.loaded)
        await vm.load()
        #expect(vm.loaded)
        let weeks = vm.weeks
        #expect(!weeks.isEmpty)
        #expect(zip(weeks, weeks.dropFirst()).allSatisfy { $0.start > $1.start })
        #expect(weeks.flatMap(\.sessions).count == vm.sessions.count)
    }

    @Test func exerciseDetailKeepsTheLast90Days() async {
        let clock = TestClock(now: .now)
        let vm = ExerciseDetailViewModel(exerciseID: MockTrain.bench.id, library: library(), clock: clock)
        #expect(vm.emptyChartText == String(localized: "Loading…"))
        await vm.load()
        #expect(vm.loaded)
        let from = DayFormat.string(from: DayFormat.shift(clock.now(), days: -89))
        #expect(vm.points.allSatisfy { $0.day >= from })
        #expect(vm.hasTrend == (vm.points.count >= 2))
        #expect(vm.recentRows.count <= 10)
        // Moving the clock 200 days on empties the window.
        clock.advance(by: .seconds(200 * 86_400))
        #expect(vm.points.isEmpty && vm.change == nil)
    }

    @Test func planDetailFiltersByWeek() async {
        let lib = library()
        let vm = PlanDetailViewModel(planID: MockTrain.weightlifting.id, library: lib)
        await vm.load()
        #expect(vm.plan?.id == MockTrain.weightlifting.id)
        if vm.weeks.count > 1 {
            vm.week = vm.weeks[1]
            #expect(vm.shownDays.allSatisfy { $0.week == nil || $0.week == vm.weeks[1] })
        }
        #expect(vm.shownDays == vm.shownDays.sorted { $0.dayIndex < $1.dayIndex })
    }

    @Test func planBuilderValidatesOnSaveAndEditsDays() async throws {
        let vm = PlanBuilderViewModel(plan: .blank(), library: library())
        #expect(vm.isNew && !vm.hasChanges)
        #expect(vm.shownIssues.isEmpty) // not before the first Save

        #expect(await vm.save() == false)
        #expect(!vm.shownIssues.isEmpty)

        vm.addDay()
        #expect(vm.plan.days.map(\.name).last == String(localized: "Day B"))
        let dayID = try #require(vm.plan.days.first?.id)
        vm.add(MockTrain.bench, toDay: dayID)
        vm.add(MockTrain.squat, toDay: dayID)
        vm.link(dayID: dayID, 0, true)
        #expect(vm.isLinked(dayID: dayID, 0))
        vm.move(dayID: dayID, 0, by: 1)
        #expect(vm.plan.days[0].exercises.map(\.position) == [0, 1])
        vm.remove(dayID: dayID, 0)
        #expect(vm.plan.days[0].exercises.count == 1)
        #expect(vm.plan.days[0].exercises[0].supersetGroup == nil) // a superset of one isn't one
        vm.removeDay(vm.plan.days[1].id)
        #expect(vm.plan.days.count == 1)
    }

    @Test func customExerciseSlug() {
        var draft = CustomExerciseDraft(name: "  Landmine Press (1-arm) ")
        #expect(draft.slug == "landmine-press-1-arm")
        #expect(draft.exercise.name == "Landmine Press (1-arm)")
        draft.loadType = .bodyweight
        #expect(draft.exercise.bodyweightFactor == 1)
        #expect(!CustomExerciseDraft(name: "   ").canSave)
    }
}
