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

    @Test func theWeekdaysWakeTimeAsksForTonight() {
        var s = SleepSchedule.default    // weekdays 06:30, weekend 08:00
        s.wake[0] = "06:15"              // Monday earlier
        let cal = berlin
        // Friday evening: the night ends Saturday at the weekend time.
        #expect(s.nextWake(after: at(2026, 10, 23, 20, calendar: cal), calendar: cal) == at(2026, 10, 24, 8, calendar: cal))
        // Sunday evening: Monday's.
        #expect(s.nextWake(after: at(2026, 10, 25, 22, calendar: cal), calendar: cal) == at(2026, 10, 26, 6, 15, calendar: cal))
        // After midnight the night in progress ends this morning.
        #expect(s.nextWake(after: at(2026, 10, 26, 1, 30, calendar: cal), calendar: cal) == at(2026, 10, 26, 6, 15, calendar: cal))
        // The night the clocks go back still wakes at 08:00 local.
        let sunday = s.nextWake(after: at(2026, 10, 24, 22, calendar: cal), calendar: cal)
        #expect(cal.component(.hour, from: sunday) == 8 && cal.component(.day, from: sunday) == 25)
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
        await planner.scheduleReminders(schedule: s, plan: p, wake: wake, calendar: cal)

        let notifier = try #require(state.env.notifier as? MockNotifier)
        let ids = notifier.requests.map(\.identifier)
        #expect(ids.count == BedtimePlanner.nightsAhead && ids.allSatisfy { $0.hasPrefix(BedtimePlanner.reminderPrefix) })
        let tonight = try #require(notifier.requests.first { $0.identifier == "bedtime." + DayFormat.string(from: wake) })
        let fire = try #require((tonight.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
        #expect(fire == p.bedtime100.addingTimeInterval(-30 * 60))
        #expect(tonight.content.categoryIdentifier == PushCategories.bedtime)
        #expect(tonight.content.body.contains(Fmt.time(p.bedtime100)))
        // Monday's (estimated from tonight's time in bed) wakes at the weekday time.
        let monday = try #require(notifier.requests.first { $0.identifier == "bedtime.2026-10-26" })
        let mondayFire = try #require((monday.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        let mondayBed = at(2026, 10, 26, 6, 30, calendar: cal).addingTimeInterval(-Double(p.inBedMin) * 60 - 30 * 60)
        #expect(mondayFire.hour == cal.component(.hour, from: mondayBed) && mondayFire.minute == cal.component(.minute, from: mondayBed))

        // Off: none left.
        s.reminderOn = false
        await planner.scheduleReminders(schedule: s, plan: p, wake: wake, calendar: cal)
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

        shift.value = 5 * 60   // 5 minutes later: the reminders stay
        await planner.refresh()
        #expect(planner.scheduledBedtime != planner.bedtime)
        #expect(notifier.requests.first { $0.identifier == first.identifier }?.content.body == first.content.body)

        shift.value = 12 * 60  // 12: moved
        await planner.refresh()
        #expect(planner.scheduledBedtime == planner.bedtime)
        #expect(notifier.requests.first { $0.identifier == first.identifier }?.content.body != first.content.body)
        #expect(api.planWakes.allSatisfy { $0 == "06:30" })
    }

    @Test func plannedAndActualAreKeptPerNight() async throws {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.update(.default)
        let p = try #require(planner.plan)
        let planned = try #require(planner.planned(nightEnding: DayFormat.string(from: p.wake)))
        #expect(planned.bed == p.bedtime100 && planned.wake == p.wake)
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

    @Test func remindersAskForNotificationsWhenTurnedOn() async throws {
        let (state, _) = makeState()
        let notifier = try #require(state.env.notifier as? MockNotifier)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        notifier.grants = false
        #expect(!(await planner.allowReminders()) && notifier.authorizationPrompts == 1)
        notifier.status = .authorized
        #expect(await planner.allowReminders())
        #expect(notifier.authorizationPrompts == 1) // already answered: no second prompt
    }

    @Test func nothingIsPlannedWithoutTheFlagOrASchedule() async {
        let api = MockPlatformAPI()
        let (state, _) = makeState(api: api, flags: [.sleepPlanner: false])
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.refresh()          // no schedule
        await planner.update(.default)  // a schedule, but the flag is off
        #expect(api.count("sleepPlan") == 0 && planner.plan == nil && !planner.isEnabled)
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
