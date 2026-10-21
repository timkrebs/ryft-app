import Foundation
import Testing
@testable import Ryft

@MainActor
private func makeState(api: MockPlatformAPI = MockPlatformAPI(), flags: [FeatureFlag: Bool] = [:],
                       online: Bool = true) -> (AppState, TestClock) {
    let clock = TestClock()
    return (AppState(env: .test(api: api, clock: clock, flags: flags, online: online)), clock)
}

// MARK: - need breakdown

struct SleepNeedBreakdownTests {
    @Test func termsAndSentenceComeFromTheAPI() {
        let b = SleepNeedBreakdown(SleepNeed(base: 460, strain: 37, debt: 41, napCredit: 0, total: 538))
        #expect(b.terms.map(\.kind) == [.base, .strain, .debt])   // a zero credit is left out
        #expect(b.terms.map(\.signed) == ["7h 40m", "+37m", "+41m"])
        #expect(b.sentence.contains(Fmt.duration(minutes: 538)))
        #expect(b.sentence.contains("37m") && b.sentence.contains("41m"))
    }

    @Test func aNapIsACredit() {
        let b = SleepNeedBreakdown(SleepNeed(base: 460, strain: 0, debt: 12, napCredit: 35, total: 437))
        #expect(b.terms.map(\.kind) == [.base, .debt, .nap])
        #expect(b.terms.last?.signed == "−35m")
        #expect(b.total == 437)
    }
}

// MARK: - bedtime strip

struct BedtimeLayoutTests {
    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s) ?? .distantPast }

    @Test func nightsLineUpAcrossMidnight() {
        let cal = Calendar.current
        let wake = cal.date(bySettingHour: 6, minute: 30, second: 0, of: .now) ?? .now
        let bed = wake.addingTimeInterval(-8 * 3600)   // 22:30 the evening before
        let l = BedtimeLayout([SleepBedtime(day: DayFormat.string(from: wake), bed: bed, wake: wake)])
        #expect(l.nights[0].bed == 150 && l.nights[0].wake == 630)   // minutes from 20:00
        #expect(l.domain == BedtimeLayout.defaultDomain)
        #expect(l.meanBed == 150 && l.meanWake == 630)
        #expect(BedtimeLayout.clock(0) == "20" && BedtimeLayout.clock(240) == "00" && BedtimeLayout.clock(600) == "06")
    }

    @Test func aLateNightWidensTheAxis() {
        let cal = Calendar.current
        let wake = cal.date(bySettingHour: 11, minute: 20, second: 0, of: .now) ?? .now
        let l = BedtimeLayout([SleepBedtime(day: DayFormat.string(from: wake), bed: wake.addingTimeInterval(-7 * 3600),
                                            wake: wake)])
        #expect(l.domain.upperBound == 960)   // 12:00
        #expect(l.ticks.first == 0 && l.ticks.last == 960)
    }
}

// MARK: - summaries

struct SleepSummaryTests {
    @Test func nightSummaryHasTilesNapAndNeed() throws {
        let detail = try Fixture.decode(DayDetail.self, "day_detail")
        let s = SleepNightSummary(sleep: try #require(detail.sleep), score: detail.score)
        #expect(s.performance == "87%" && s.restorative == "100%" && s.consistency == "81")
        #expect(s.nap == "Nap · \(Fmt.duration(minutes: 25))")
        #expect(s.needBreakdown?.total == 538)
    }

    @Test func rangeSummaryUsesThePlatformsConsistency() throws {
        let r = try Fixture.decode(SleepRange.self, "sleep_range")
        let s = SleepRangeSummary(range: r)
        #expect(s.averageConsistency == "84" && s.regularity == .steady)
        #expect(s.bedtimes.count == 2)
        #expect(s.nightRows.map(\.day) == ["2026-10-14", "2026-10-12"])   // newest first
        #expect(s.nightRows[0].nap == Fmt.duration(minutes: 30) && s.nightRows[0].consistency == nil)
    }
}

// MARK: - planner

@MainActor
struct SleepPlannerTests {
    @Test func theModeNeedsTheFlag() {
        let (off, _) = makeState(flags: [.sleepPlanner: false])   // on by default (API.md)
        #expect(!SleepViewModel(state: off).modes.contains(.plan))
        let (on, _) = makeState(flags: [.sleepPlanner: true])
        let vm = SleepViewModel(state: on)
        #expect(vm.modes.last == .plan)
        vm.showPlanner()
        #expect(vm.mode == .plan)
    }

    @Test func threeBedtimesAscendingWithTheirSleep() async throws {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api, flags: [.sleepPlanner: true])
        let planner = SleepPlannerViewModel(state: state)
        #expect(planner.wakeText == "07:00")   // nothing cached: the default
        await planner.load()
        let plan = try #require(planner.plan)
        #expect(planner.options.map(\.share) == [100, 85, 70])
        #expect(planner.options.map(\.bedtime) == [plan.bedtime100, plan.bedtime85, plan.bedtime70])
        #expect(planner.options[1].sleepMin == Int((Double(plan.needMin) * 0.85).rounded()))
        #expect(api.planWakes == ["07:00"])
    }

    @Test func wakeChangesAreDebounced() async throws {
        let api = MockPlatformAPI()
        let (state, clock) = makeState(api: api)
        let planner = SleepPlannerViewModel(state: state)
        let cal = Calendar.current
        for minute in [5, 10, 15] {
            planner.setWake(cal.date(bySettingHour: 6, minute: minute, second: 0, of: .now) ?? .now)
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: SleepPlannerViewModel.debounce)
        await planner.settle()
        #expect(api.planWakes == ["06:15"])   // one request, the last value
    }

    @Test func offlineKeepsTheLastPlanWithItsTime() async throws {
        let api = MockPlatformAPI()
        let (online, _) = makeState(api: api)
        await SleepPlannerViewModel(state: online).load()
        // Same store, now offline: the cached plan, stamped.
        let offlineEnv = AppEnvironment.test(api: api, flags: [:], online: false)
        let cached = try #require(online.env.persistence.document(SleepPlannerViewModel.Cached.self,
                                                                  key: SleepPlannerViewModel.cacheKey))
        offlineEnv.persistence.saveDocument(cached, key: SleepPlannerViewModel.cacheKey, at: cached.fetchedAt)
        let planner = SleepPlannerViewModel(state: AppState(env: offlineEnv))
        await planner.load()
        #expect(planner.plan == cached.plan && planner.asOf == cached.fetchedAt)
        #expect(api.planWakes.count == 1)
    }

    @Test func theDefaultWakeIsTheLatestFromTheWeek() async {
        let (state, _) = makeState()
        _ = await state.sleepRange(.week)
        let latest = MockData.sleepRange(.week).bedtimes.max { $0.wake < $1.wake }?.wake
        #expect(SleepPlannerViewModel(state: state).wakeText == latest.map { SleepPlannerViewModel.hhmm($0) })
    }
}

// MARK: - baseline source

@MainActor
struct SleepBaselineTests {
    private func editor(_ state: AppState) -> BodySettingsEditor { BodySettingsEditor(state: state) }

    @Test func sourceLinesSayWhereTheValueComesFrom() {
        let (state, _) = makeState()
        let e = editor(state)
        var user = MockData.user
        user.sleepBaseSource = .default
        user.sleepBaseLearnedAt = nil
        state.user = user
        #expect(e.sleepBaseSourceText == String(localized: "Default") && !e.canUseLearnedBase)
        state.user = MockData.user   // learned
        #expect(e.sleepBaseSourceText?.hasPrefix(String(localized: "Learned")) == true && !e.canUseLearnedBase)
        var manual = MockData.user
        manual.sleepBaseSource = .manual
        manual.sleepBaseLearnedMin = 455
        state.user = manual
        #expect(e.sleepBaseSourceText == String(localized: "Set by you · learned \(Fmt.duration(minutes: 455))"))
        #expect(e.canUseLearnedBase && e.usesLearnedTitle == String(localized: "Use the learned value"))
        manual.sleepBaseLearnedMin = nil
        state.user = manual
        #expect(e.usesLearnedTitle == String(localized: "Use the default"))
    }

    @Test func aSetBaselineShowsAtOnceSavesAsManualAndOffersTheRescore() async {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api)
        state.user = MockData.user
        let e = editor(state)
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }

        let save = Task { await e.setSleepBase(470) }
        #expect(await eventually { e.saving })
        #expect(e.sleepBase == 470 && e.sleepBaseSource == .manual) // optimistic, while the PATCH is out
        await gate.open()
        #expect(await save.value)

        #expect(api.mePatches.last?.sleepBaseMin == 470 && api.mePatches.last?.sleepBaseManual == nil)
        #expect(state.user?.sleepBaseSource == .manual && e.sleepBase == 470)
        #expect(e.savedChange && e.error == nil)
        #expect(api.count("recompute") == 0) // past days only when asked
    }

    @Test func aRefusalShowsInTheSheetAndTheValueGoesBack() async {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api)
        state.user = MockData.user
        let e = editor(state)
        api.failNext = APIError.http(422, "sleep_base_min out of range", requestID: "rid-422")

        #expect(!(await e.setSleepBase(500)))

        #expect(e.error == String(localized: "RYFT takes a baseline between 4 and 12 hours."))
        #expect(e.errorDetails?.contains("rid-422") == true)
        #expect(e.sleepBase == MockData.user.sleepBaseMin && !e.savedChange)
        #expect(state.error == nil) // not Today's message: the sheet's
    }

    @Test func valuesStayInTheRangeThePlatformTakes() async {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api)
        state.user = MockData.user
        await editor(state).setSleepBase(1_000)
        #expect(api.mePatches.last?.sleepBaseMin == 720)
        await editor(state).setSleepBase(60)
        #expect(api.mePatches.last?.sleepBaseMin == 240)
    }

    @Test func useTheLearnedValueSendsManualFalse() async {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api)
        var manual = MockData.user
        manual.sleepBaseSource = .manual
        state.user = manual
        #expect(await editor(state).useLearnedSleepBase())
        #expect(api.mePatches.last?.sleepBaseManual == false && api.mePatches.last?.sleepBaseMin == nil)
        #expect(state.user?.sleepBaseSource == .learned)
        #expect(api.count("recompute") == 0)   // no rescore until asked
    }

    @Test func rescoringWaitsForScoringOnTheClock() async {
        let api = MockPlatformAPI()
        let (state, clock) = makeState(api: api)
        state.user = MockData.user
        let e = editor(state)
        await e.setSleepBase(470)
        let run = Task { await e.rescore() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(e.rescoring && e.rescoreStatus == String(localized: "Rescoring — scores update in a few seconds."))
        #expect(api.count("recompute") == 1)
        clock.advance(by: SyncService.rescoreDelay)
        await run.value
        #expect(!e.rescoring && !e.savedChange)
        #expect(e.rescoreStatus == String(localized: "The last 90 days are rescored with your settings."))
    }

    @Test func anotherFailureSaysWhatWentWrongInTheForm() async {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api)
        state.user = MockData.user
        let e = editor(state)
        api.failNext = APIError.http(500, "", requestID: "rid-500")
        #expect(!(await e.setSleepBase(500)))
        #expect(e.error == APIError.http(500, "").localizedDescription)
        #expect(e.errorDetails?.contains("rid-500") == true)
        #expect(state.error == nil)
    }

    @Test func aRefusedGoingBackSaysSoInWords() async {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api)
        var manual = MockData.user
        manual.sleepBaseSource = .manual
        state.user = manual
        let e = editor(state)
        api.failNext = APIError.http(422, "sleep_base_manual: conflicting fields")
        #expect(!(await e.useLearnedSleepBase()))
        #expect(e.error == String(localized: "RYFT couldn't take that change. Try again later.")) // not the server's English
    }

    @Test func aBirthYearFailureStaysBesideThePicker() async {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api)
        state.user = MockData.user
        let e = editor(state)
        api.failNext = APIError.http(503, "")
        #expect(!(await e.setBirthYear(1990)))
        #expect(e.birthYearError == APIError.http(503, "").localizedDescription && e.error == nil)
        #expect(await e.setBirthYear(1990))
        #expect(e.birthYearError == nil)
    }

    @Test func nothingSavesWhileARescoreRuns() async {
        let api = MockPlatformAPI()
        let (state, clock) = makeState(api: api)
        state.user = MockData.user
        let e = editor(state)
        let run = Task { await e.rescore() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(e.isBusy)
        #expect(!(await e.setSleepBase(470))) // it would be reported as rescored
        #expect(api.count("patchMe") == 0)
        clock.advance(by: SyncService.rescoreDelay)
        await run.value
        #expect(await e.setSleepBase(470))
    }

    @Test func aFailedRescoreKeepsTheRequestID() async {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api)
        let e = editor(state)
        api.failure = APIError.http(500, "", requestID: "rid-rescore")
        await e.rescore()
        #expect(e.rescoreStatus == APIError.http(500, "").localizedDescription)
        #expect(e.rescoreDetails?.contains("rid-rescore") == true)
    }

    @Test func theMockPlatformKeepsEachChange() async throws {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api)
        state.user = MockData.user
        let e = editor(state)
        await e.setMaxHR(184)
        await e.setSleepBase(470)
        #expect(state.user?.maxHr == 184 && state.user?.sleepBaseMin == 470) // the first isn't undone by the second
        let me = try await api.me()
        #expect(me.maxHr == 184 && me.sleepBaseMin == 470)
    }

    @Test func theNeedBreakdownAddsUp() {
        let need = SleepNeed(base: 460, strain: 37, debt: 41, napCredit: 25, total: 513)
        let b = SleepNeedBreakdown(need)
        #expect(b.terms.map(\.kind) == [.base, .strain, .debt, .nap])
        #expect(b.minutes(.base) + b.minutes(.strain) + b.minutes(.debt) - b.minutes(.nap) == b.total)
        #expect(SleepNeedBreakdown(SleepNeed(base: 460, strain: 0, debt: 0, napCredit: 0, total: 460)).terms.count == 1)
    }
}

/// Holds an async step open until the test lets it go.
actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

// MARK: - insights

@MainActor
struct InsightOpenTests {
    @Test func aCardOpensItsChart() {
        let (state, _) = makeState()
        let vm = InsightsViewModel(state: state)
        let card = Insight(id: "nap-credit", severity: .info, title: "", body: "", metric: "nap_min")
        #expect(vm.route(for: card) == .insights(.napMin))
        let pr = Insight(id: "pr", severity: .info, title: "", body: "", metric: "volume_kg")
        #expect(vm.route(for: pr) == .trainHistory)
        // behavior-impact only once the journal is live.
        let impact = Insight(id: "behavior-impact", severity: .notice, title: "", body: "", metric: "recovery")
        #expect(vm.route(for: impact) == nil)
        let unknown = Insight(id: "new-rule", severity: .info, title: "", body: "", metric: "something_else")
        #expect(!vm.canOpen(unknown))
    }
}
