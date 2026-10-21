import Foundation
import Testing
import UserNotifications
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
        #expect(state.refreshIssue == nil) // not Today's card: the sheet's
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
        #expect(state.refreshIssue == nil)
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

// MARK: - Bedtime & wake

@MainActor
struct BedtimeAndWakeTests {
    /// Berlin, with a DST change on Sunday 25 October 2026 (03:00 → 02:00).
    private var berlin: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func plan(wake: Date, needMin: Int = 520, bedShift: TimeInterval = 0) -> SleepPlan {
        let inBed = Int((Double(needMin) / 0.9).rounded())
        func bed(_ share: Double) -> Date { wake.addingTimeInterval(-share * Double(inBed) * 60 + bedShift) }
        return SleepPlan(wake: wake, needMin: needMin, inBedMin: inBed, efficiency: 90,
                         bedtime100: bed(1), bedtime85: bed(0.85), bedtime70: bed(0.7),
                         basis: SleepPlanBasis(base: 460, strainTopup: 30, debtTopup: 30, napCredit: 0, efficiency: 90))
    }

    /// The next `weekday` (1 Sunday … 7 Saturday) at `hour:minute`, local, after the test clock's start.
    private func next(weekday: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.nextDate(after: TestClock().now(), matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                                  matchingPolicy: .nextTime)!
    }

    private func reminders(_ state: AppState) -> [UNNotificationRequest] {
        (state.env.notifier as? MockNotifier)?.requests.filter { $0.identifier.hasPrefix(BedtimePlanner.reminderPrefix) } ?? []
    }

    @Test func theNextWakeIsTheWeekdaysTimeAsTheAPIResolvesIt() {
        var s = SleepSchedule.default    // weekdays 06:30, weekend 08:00
        s.wake[0] = "06:15"              // Monday earlier
        let cal = berlin
        // Friday evening: the night ends Saturday at the weekend time.
        #expect(s.nextWake(after: at(2026, 10, 23, 20, calendar: cal), calendar: cal) == at(2026, 10, 24, 8, calendar: cal))
        // Friday 07:30, after Friday's wake: Saturday's, though 08:00 still comes today.
        #expect(s.nextWake(after: at(2026, 10, 23, 7, 30, calendar: cal), calendar: cal) == at(2026, 10, 24, 8, calendar: cal))
        // Sunday evening: Monday's.
        #expect(s.nextWake(after: at(2026, 10, 25, 22, calendar: cal), calendar: cal) == at(2026, 10, 26, 6, 15, calendar: cal))
        // After midnight and up to the wake time, the night in progress ends this morning.
        #expect(s.nextWake(after: at(2026, 10, 26, 1, 30, calendar: cal), calendar: cal) == at(2026, 10, 26, 6, 15, calendar: cal))
        #expect(s.nextWake(after: at(2026, 10, 26, 5, 0, calendar: cal), calendar: cal) == at(2026, 10, 26, 6, 15, calendar: cal))
        // The night the clocks go back still wakes at 08:00 local.
        let sunday = s.nextWake(after: at(2026, 10, 24, 22, calendar: cal), calendar: cal)
        #expect(cal.component(.hour, from: sunday) == 8 && cal.component(.day, from: sunday) == 25)
    }

    @Test func aPlanForTodaysTimeMovesToTomorrowsWakeAndNothingElseIsTaken() throws {
        let cal = berlin
        let saturday = at(2026, 10, 24, 8, calendar: cal)
        let friday = at(2026, 10, 23, 8, calendar: cal)       // what `wake=08:00` resolves to on Friday 07:30
        let p = plan(wake: friday)
        let aligned = try #require(BedtimePlanner.align(p, to: saturday, calendar: cal))
        #expect(aligned.wake == saturday && aligned.needMin == p.needMin && aligned.basis == p.basis)
        #expect(aligned.bedtime100 == saturday.addingTimeInterval(-Double(p.inBedMin) * 60))
        #expect(aligned.bedtime70 == p.bedtime70.addingTimeInterval(saturday.timeIntervalSince(friday)))
        // Across the clock change the wall-clock wake still matches (25 hours apart).
        let sunday = at(2026, 10, 25, 8, calendar: cal)
        #expect(BedtimePlanner.align(plan(wake: saturday), to: sunday, calendar: cal)?.wake == sunday)
        #expect(BedtimePlanner.align(p, to: friday, calendar: cal) == p)
        // Another time zone's 08:00: not tonight's plan.
        #expect(BedtimePlanner.align(plan(wake: friday.addingTimeInterval(3 * 3_600)), to: saturday, calendar: cal) == nil)
    }

    @Test func fridayMorningPlansSaturdaysNight() async throws {
        let api = MockPlatformAPI()
        let (state, clock) = makeState(api: api)
        clock.set(next(weekday: 6, 7, 30))                  // Friday 07:30
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var s = SleepSchedule.default
        s.reminderOn = true
        await planner.update(s)
        let saturday = next(weekday: 7, 8)
        let p = try #require(planner.plan)
        #expect(api.planWakes == ["08:00"] && p.wake == saturday)
        #expect(planner.bedtime == saturday.addingTimeInterval(-Double(p.inBedMin) * 60))
        #expect(planner.planned(nightEnding: DayFormat.string(from: saturday))?.bed == planner.bedtime)
        // Tonight's reminder is there, and it's Saturday's.
        #expect(reminders(state).contains { $0.identifier == "bedtime." + DayFormat.string(from: saturday) })
    }

    @Test func theGoalPicksItsBedtime() {
        let p = plan(wake: .now)
        #expect(SleepSchedule.Goal.peak.bedtime(in: p) == p.bedtime100)
        #expect(SleepSchedule.Goal.perform.bedtime(in: p) == p.bedtime85)
        #expect(SleepSchedule.Goal.getBy.bedtime(in: p) == p.bedtime70)
    }

    @Test func remindersWindDownBeforeEachNightLocalTimeAcrossTheClockChange() async throws {
        let (state, clock) = makeState()
        let cal = berlin
        clock.set(at(2026, 10, 24, 12, calendar: cal)) // Saturday noon, before the DST night
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var s = SleepSchedule.default
        s.reminderOn = true
        s.windDownMin = 30
        let wake = at(2026, 10, 25, 8, calendar: cal)  // Sunday, after the clocks went back
        let p = plan(wake: wake)
        await planner.scheduleReminders(schedule: s, plan: p, calendar: cal)

        let notifier = try #require(state.env.notifier as? MockNotifier)
        let ids = notifier.requests.map(\.identifier)
        #expect(ids.count == BedtimePlanner.nightsAhead && ids.allSatisfy { $0.hasPrefix(BedtimePlanner.reminderPrefix) })
        let tonight = try #require(notifier.requests.first { $0.identifier == "bedtime." + DayFormat.string(from: wake) })
        // Wall-clock components in the planning calendar's zone (`nextTriggerDate` would read them
        // in the device's zone).
        let fire = try #require((tonight.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        let expected = cal.dateComponents([.year, .month, .day, .hour, .minute], from: p.bedtime100.addingTimeInterval(-30 * 60))
        #expect(fire.day == expected.day && fire.hour == expected.hour && fire.minute == expected.minute)
        #expect(tonight.content.categoryIdentifier == PushCategories.bedtime)
        #expect(tonight.content.body.contains(Fmt.time(p.bedtime100)))
        // Monday's (estimated from tonight's time in bed) wakes at the weekday time.
        let monday = try #require(notifier.requests.first { $0.identifier == "bedtime.2026-10-26" })
        let mondayFire = try #require((monday.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        let mondayBed = at(2026, 10, 26, 6, 30, calendar: cal).addingTimeInterval(-Double(p.inBedMin) * 60 - 30 * 60)
        #expect(mondayFire.hour == cal.component(.hour, from: mondayBed) && mondayFire.minute == cal.component(.minute, from: mondayBed))

        // Off: none left.
        s.reminderOn = false
        await planner.scheduleReminders(schedule: s, plan: p, calendar: cal)
        #expect(notifier.requests.isEmpty)
    }

    @Test func aBedtimeThatMovesLessThanTenMinutesKeepsItsReminders() async throws {
        let api = MockPlatformAPI()
        let (state, clock) = makeState(api: api)
        clock.set(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: clock.now())!)
        let shift = ShiftBox()
        let now = clock.now()
        api.planFor = { _ in
            let wake = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: now)!)!
            let inBed = 578
            let bed = wake.addingTimeInterval(-Double(inBed) * 60 + shift.value)
            return SleepPlan(wake: wake, needMin: 520, inBedMin: inBed, efficiency: 90, bedtime100: bed,
                             bedtime85: bed.addingTimeInterval(3_600), bedtime70: bed.addingTimeInterval(7_200),
                             basis: SleepPlanBasis(base: 460, strainTopup: 30, debtTopup: 30, napCredit: 0, efficiency: 90))
        }
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var s = SleepSchedule.default
        s.reminderOn = true
        await planner.update(s)
        let notifier = try #require(state.env.notifier as? MockNotifier)
        let first = try #require(notifier.requests.first { $0.identifier.hasPrefix("bedtime.") })
        #expect(planner.scheduledBedtime == planner.bedtime)
        #expect(state.repository.tonightBedtime == planner.bedtime)

        shift.value = 5 * 60   // 5 minutes later: the reminders stay, the card and the widget move
        await planner.refresh()
        #expect(planner.scheduledBedtime != planner.bedtime)
        #expect(state.repository.tonightBedtime == planner.bedtime)
        #expect(notifier.requests.first { $0.identifier == first.identifier }?.content.body == first.content.body)

        shift.value = 12 * 60  // 12: moved
        await planner.refresh()
        #expect(planner.scheduledBedtime == planner.bedtime)
        #expect(notifier.requests.first { $0.identifier == first.identifier }?.content.body != first.content.body)
        #expect(api.planWakes.allSatisfy { $0 == "06:30" })
    }

    @Test func turningTheReminderOffCancelsItWithoutTheNetwork() async throws {
        let (state, clock) = makeState()
        clock.set(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: clock.now())!)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var s = SleepSchedule.default
        s.reminderOn = true
        await planner.update(s)
        #expect(!reminders(state).isEmpty)
        (state.env.connectivity as? ConnectivityMonitor)?.update(false)
        s.reminderOn = false
        await planner.update(s)
        #expect(reminders(state).isEmpty)
        // Offline the cached plan still plans tonight, as of when it was fetched.
        #expect(planner.plan != nil && planner.asOf != nil && planner.error == nil)
    }

    @Test func aFlagTurnedOffLeavesNothingScheduled() async throws {
        let (state, clock) = makeState()
        clock.set(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: clock.now())!)
        let alarms = MockWakeAlarms()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        var s = SleepSchedule.default
        s.reminderOn = true
        s.alarmOn = true
        await planner.update(s)
        #expect(!reminders(state).isEmpty && alarms.scheduled == s.wake && state.repository.tonightBedtime != nil)
        (state.env.flags as? StaticFlags)?.overrides[.sleepPlanner] = false
        await planner.refresh()
        #expect(reminders(state).isEmpty && alarms.scheduled == nil && state.repository.tonightBedtime == nil)
        #expect(planner.schedule == s)   // kept for when it comes back
    }

    @Test func anotherAccountTakesThePreviousOnesRemindersAndAlarmsAway() async throws {
        let (state, clock) = makeState()
        clock.set(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: clock.now())!)
        let alarms = MockWakeAlarms()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        var s = SleepSchedule.default
        s.reminderOn = true
        s.alarmOn = true
        await planner.update(s)
        #expect(!reminders(state).isEmpty && alarms.scheduled != nil)

        // The next account on this phone hasn't set anything up.
        SleepSchedule.remove(account: state.env.auth.accountID, defaults: state.env.defaults)
        await planner.accountChanged()
        #expect(planner.schedule == nil && planner.plan == nil)
        #expect(reminders(state).isEmpty && alarms.scheduled == nil && state.repository.tonightBedtime == nil)

        // One that has: its alarm comes back.
        var theirs = SleepSchedule.default
        theirs.alarmOn = true
        theirs.setWeekdays("05:45")
        theirs.save(account: state.env.auth.accountID, defaults: state.env.defaults)
        await planner.accountChanged()
        #expect(alarms.scheduled == theirs.wake && reminders(state).isEmpty)
    }

    @Test func signingOutWipesEverySchedule() {
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)")!
        SleepSchedule.default.save(account: "a", defaults: defaults)
        SleepSchedule.default.save(account: "b", defaults: defaults)
        defaults.set(Data(), forKey: "sleep.planned.a")
        defaults.set(true, forKey: "sleep.other")
        BedtimePlanner.wipe(defaults: defaults)
        #expect(SleepSchedule.load(account: "a", defaults: defaults) == nil)
        #expect(SleepSchedule.load(account: "b", defaults: defaults) == nil)
        #expect(defaults.data(forKey: "sleep.planned.a") == nil && defaults.bool(forKey: "sleep.other"))
    }

    @Test func concurrentRefreshesEndWithTheLastChange() async throws {
        let api = MockPlatformAPI()
        let (state, clock) = makeState(api: api)
        clock.set(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: clock.now())!)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var s = SleepSchedule.default
        s.reminderOn = true
        await planner.update(s)
        var changed = s
        changed.goal = .perform
        let perform = changed
        async let a: Void = planner.refresh()
        async let b: Void = planner.refresh()
        async let c: Void = planner.update(perform)
        async let d: Void = planner.refresh()
        _ = await (a, b, c, d)
        let p = try #require(planner.plan)
        #expect(planner.bedtime == p.bedtime85 && planner.scheduledBedtime == p.bedtime85)
        let tonight = try #require(reminders(state).first { $0.identifier == "bedtime." + DayFormat.string(from: p.wake) })
        #expect(tonight.content.body.contains(Fmt.time(p.bedtime85)))
    }

    @Test func plannedAndActualAreKeptPerNightAndFrozenOnceBedtimePassed() async throws {
        let api = MockPlatformAPI()
        let (state, clock) = makeState(api: api)
        clock.set(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: clock.now())!)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.update(.default)
        let p = try #require(planner.plan)
        let day = DayFormat.string(from: p.wake)
        let planned = try #require(planner.planned(nightEnding: day))
        #expect(planned.bed == p.bedtime100 && planned.wake == p.wake)

        // After bedtime (today's strain starts again at midnight) the night keeps what it planned.
        clock.set(p.bedtime100.addingTimeInterval(60))
        let later = plan(wake: p.wake, needMin: 460)
        api.planFor = { _ in later }
        await planner.refresh()
        #expect(planner.plan?.needMin == 460)
        #expect(planner.planned(nightEnding: day) == planned)
        // And a new planner (the next launch) reads it back.
        #expect(BedtimePlanner(state: state, alarms: MockWakeAlarms()).planned(nightEnding: day) == planned)
    }

    @Test func theAlarmFollowsTheScheduleAndAsksFirst() async {
        let (state, _) = makeState()
        let alarms = MockWakeAlarms()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        alarms.allows = false
        #expect(!(await planner.allowAlarm()))
        alarms.allows = true
        #expect(await planner.allowAlarm())
        var s = SleepSchedule.default
        s.alarmOn = true
        await planner.update(s)
        #expect(alarms.scheduled == s.wake)
        s.wake[6] = "09:30"
        await planner.update(s)
        #expect(alarms.scheduled?[6] == "09:30")
        s.alarmOn = false
        await planner.update(s)
        #expect(alarms.scheduled == nil && alarms.cancellations >= 1)
    }

    @Test func theAlarmIsSetAgainAtLaunchOrTurnedOffWhenIOSNoLongerAllowsIt() async {
        let (state, _) = makeState()
        var s = SleepSchedule.default
        s.alarmOn = true
        s.save(account: state.env.auth.accountID, defaults: state.env.defaults)
        // A restore: the schedule says on, AlarmKit has nothing. The first look sets it, once.
        let alarms = MockWakeAlarms()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        await planner.refresh()
        await planner.refresh()
        #expect(alarms.scheduled == s.wake && alarms.schedulings == 1)

        // Not allowed any more (Settings, or a new iOS asking again): off, and the card says why.
        let refused = MockWakeAlarms()
        refused.allowed = false
        let next = BedtimePlanner(state: state, alarms: refused)
        await next.refresh()
        #expect(refused.scheduled == nil && refused.schedulings == 0)
        #expect(next.schedule?.alarmOn == false && next.alarmProblem != nil)
        #expect(SleepSchedule.load(account: state.env.auth.accountID, defaults: state.env.defaults)?.alarmOn == false)
    }

    @Test func equalWakeTimesShareOneAlarm() {
        let groups = SystemWakeAlarms.groups(SleepSchedule.default.wake)
        #expect(groups.map(\.time) == ["06:30", "08:00"])
        #expect(groups.map(\.days) == [[0, 1, 2, 3, 4], [5, 6]])
    }

    @Test func remindersAskForNotificationsWhenTurnedOn() async throws {
        let (state, _) = makeState()
        let notifier = try #require(state.env.notifier as? MockNotifier)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        notifier.grants = false
        #expect(!(await planner.allowReminders()) && notifier.authorizationPrompts == 1)
        notifier.status = .authorized
        #expect(await planner.allowReminders())
        #expect(notifier.authorizationPrompts == 1) // already answered: no second prompt
        // Provisional ones arrive silently: asked for the real thing.
        notifier.status = .provisional
        notifier.grants = true
        #expect(await planner.allowReminders())
        #expect(notifier.authorizationPrompts == 2)
    }

    @Test func nothingIsPlannedWithoutTheFlagOrASchedule() async {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api, flags: [.sleepPlanner: false])
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.refresh()          // no schedule
        await planner.update(.default)  // a schedule, but the flag is off
        #expect(api.count("sleepPlan") == 0 && planner.plan == nil && !planner.isEnabled)
    }

    @Test func turningItOffForgetsTheSchedule() async {
        let (state, clock) = makeState()
        clock.set(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: clock.now())!)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var s = SleepSchedule.default
        s.reminderOn = true
        await planner.update(s)
        await planner.update(nil)
        #expect(planner.schedule == nil && planner.plan == nil && planner.summary == String(localized: "Off"))
        #expect(reminders(state).isEmpty && state.repository.tonightBedtime == nil)
        #expect(SleepSchedule.load(account: state.env.auth.accountID, defaults: state.env.defaults) == nil)
    }

    @Test func theScheduleIsTheAccountsOwn() async {
        let (state, _) = makeState()
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var s = SleepSchedule.default
        s.goal = .perform
        await planner.update(s)
        #expect(BedtimePlanner(state: state, alarms: MockWakeAlarms()).schedule?.goal == .perform)
        #expect(SleepSchedule.load(account: "someone-else", defaults: state.env.defaults) == nil)
    }

    @Test func sameTimeOnWeekdaysTakesTheShownTimes() throws {
        var s = SleepSchedule.default
        s.sameOnWeekdays = false
        s.wake = ["06:00", "06:10", "06:20", "06:30", "06:40", "09:00", "10:00"]
        s.setSameOnWeekdays(true)
        #expect(s.wake == ["06:00", "06:00", "06:00", "06:00", "06:00", "09:00", "09:00"])
        // A stored schedule with the wrong number of days is no schedule.
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)")!
        var broken = SleepSchedule.default
        broken.wake = ["06:30"]
        broken.save(account: "a", defaults: defaults)
        #expect(SleepSchedule.load(account: "a", defaults: defaults) == nil)
    }

    @Test func theWidgetShowsTonightsBedtimeOnlyAheadOfIt() {
        let now = Date.now
        let ahead = ReadinessSnapshot.make(day: "2026-10-21", today: nil, previous: DailyScore(day: "2026-10-20", readiness: 70),
                                           state: nil, now: now, bedtime: now.addingTimeInterval(3_600))
        #expect(ahead?.bedtime != nil)
        let passed = ReadinessSnapshot.make(day: "2026-10-21", today: nil, previous: DailyScore(day: "2026-10-20", readiness: 70),
                                            state: nil, now: now, bedtime: now.addingTimeInterval(-60))
        #expect(passed?.bedtime == nil)
    }
}

/// A value the scripted plan reads from any thread.
final class ShiftBox: @unchecked Sendable {
    private let lock = NSLock()
    private var shift: TimeInterval = 0
    var value: TimeInterval {
        get { lock.withLock { shift } }
        set { lock.withLock { shift = newValue } }
    }
}
