import Foundation
import Testing
import UserNotifications
@testable import Ryft

// PR 6 C's fix round 2 (6c8): demo data's plans are never the account's (review 2, item 1: Tonight's `BedtimePlanner` and
// Sleep → Bedtime keep demo data's last plan in memory only, never in the account's store), and demo data counts as online
// wherever a page asks (item 4). Synthetic data only (Alex Doe).

/// An account beside a switchable Demo data (`settings.demoMode`), each side with its own platform, at 17:42. Demo data
/// plans another night (its bedtimes 45 minutes earlier), so the two plans never look alike.
@MainActor
private func sideGraph(auth: AuthService? = nil) -> (AppState, live: MockPlatformAPI, demo: MockPlatformAPI) {
    let clock = TestClock()
    clock.set(Calendar.current.date(bySettingHour: 17, minute: 42, second: 0, of: clock.now()) ?? clock.now())
    let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
    let live = MockPlatformAPI()
    let demo = MockPlatformAPI()
    live.now = { clock.now() }
    demo.now = { clock.now() }
    demo.planFor = { hhmm in
        let p = MockJournal.sleepPlan(wake: hhmm, now: clock.now())
        let earlier: TimeInterval = -45 * 60
        return SleepPlan(wake: p.wake, needMin: p.needMin + 45, inBedMin: p.inBedMin + 45, efficiency: p.efficiency,
                         bedtime100: p.bedtime100.addingTimeInterval(earlier), bedtime85: p.bedtime85.addingTimeInterval(earlier),
                         bedtime70: p.bedtime70.addingTimeInterval(earlier), basis: p.basis)
    }
    let settings = Settings(defaults: defaults)
    // In the simulator a fresh install starts in demo data: this graph starts on the account.
    settings.demoMode = false
    let env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: live, demoAPI: demo,
                             auth: auth ?? .preview(), persistence: TrainStore(inMemory: true), clock: clock, notifier: MockNotifier(),
                             flags: StaticFlags([.sleepPlanner: true]), connectivity: .preview(online: true),
                             defaults: defaults, demoOverride: nil)
    env.reads.random = { $0.lowerBound }
    env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
    let state = AppState(env: env)
    state.repository.widgetFile = nil
    return (state, live, demo)
}

/// The switch as Profile → Data turns it.
@MainActor
private func switchDemo(_ state: AppState, on: Bool) {
    state.env.settings.demoMode = on
    state.reset()
}

@MainActor
struct PlannerDemoSideTests {
    @Test("Tonight: the account's plan never shows in demo data, demo data's never lands in the account's store",
          .timeLimit(.minutes(1)))
    func bedtimeKeepsTheSidesApart() async throws {
        let (state, _, demo) = sideGraph()
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.update(.default)
        let mine = try #require(planner.plan)
        let kept = state.env.persistence.document(BedtimePlanner.Cached.self, key: BedtimePlanner.cacheKey)
        #expect(kept?.plan == mine, "the account's plan, kept")

        switchDemo(state, on: true)
        await planner.accountChanged()
        #expect(planner.schedule == nil && planner.plan == nil, "demo data sets up Bedtime & wake of its own")
        let hold = RequestHold()
        demo.beforePlan = { _ in await hold.wait() }
        let planning = Task { await planner.update(.default) }
        #expect(await eventually { hold.waiting == 1 })
        #expect(planner.plan == nil && planner.bedtime == nil, "nothing of the account's while demo data plans")
        hold.release()
        await planning.value
        let demos = try #require(planner.plan)
        #expect(demos != mine && planner.asOf == nil, "demo data's own plan")
        #expect(state.env.persistence.document(BedtimePlanner.Cached.self, key: BedtimePlanner.cacheKey) == kept,
                "the account's store, untouched")

        // Off again, offline: the account's own plan, as it was kept.
        state.env.connectivityMonitor.update(false)
        switchDemo(state, on: false)
        await planner.accountChanged()
        #expect(planner.plan == mine && planner.asOf == kept?.fetchedAt)
    }

    @Test("Sleep → Bedtime: the switch forgets the other side's plan, and demo data's never lands in the account's store",
          .timeLimit(.minutes(1)))
    func sleepTabKeepsTheSidesApart() async throws {
        let (state, _, _) = sideGraph()
        let sync = SyncService(env: state.env)
        // The app's models: the Sleep tab's planner forgets with the other account-state forgetters.
        let screens = ScreenModels(state: state, sync: sync,
                                   coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                clock: state.env.clock),
                                   store: TrainPreview.store, library: TrainPreview.library)
        let planner = screens.sleep.planner
        await planner.load()
        let mine = try #require(planner.plan)
        let kept = state.env.persistence.document(SleepPlannerViewModel.Cached.self, key: SleepPlannerViewModel.cacheKey)
        #expect(kept?.plan == mine)

        switchDemo(state, on: true)
        #expect(planner.plan == nil && planner.asOf == nil, "the account's plan went with the switch")
        await planner.load()
        let demos = try #require(planner.plan)
        #expect(demos != mine && planner.asOf == nil, "demo data's own plan")
        #expect(state.env.persistence.document(SleepPlannerViewModel.Cached.self, key: SleepPlannerViewModel.cacheKey) == kept,
                "the account's store, untouched")

        state.env.connectivityMonitor.update(false)
        switchDemo(state, on: false)
        #expect(planner.plan == mine && planner.asOf == kept?.fetchedAt, "the account's own, as kept")
        await planner.load()
        #expect(planner.plan == mine, "offline: still the account's")
    }
}

// MARK: - round 3 (6c8): Bedtime & wake follows the side, and so does everything held across the switch

/// The app's models on `state` (the account-state forgetters as `ScreenModels` connects them).
@MainActor
private func appScreens(_ state: AppState) -> ScreenModels {
    let sync = SyncService(env: state.env)
    return ScreenModels(state: state, sync: sync,
                        coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock),
                        store: TrainPreview.store, library: TrainPreview.library)
}

/// Tonight's planner as the app connects it (it forgets with the reset, `ScreenModels`), with alarms the test reads.
@MainActor
private func appPlanner(_ state: AppState, alarms: WakeAlarms? = nil) -> BedtimePlanner {
    let planner = BedtimePlanner(state: state, alarms: alarms ?? MockWakeAlarms())
    state.forgetsAccountState { [weak planner] in planner?.forget() }
    return planner
}

/// The switch, and RyftApp's refresh after it.
@MainActor
private func turnDemo(_ state: AppState, _ planner: BedtimePlanner, on: Bool) async {
    switchDemo(state, on: on)
    await planner.refresh()
}

/// What Bedtime & wake keeps for `account` on this iPhone: its schedule and planned nights, as stored.
@MainActor
private func kept(_ state: AppState, account: String?) -> (schedule: Data?, nights: Data?) {
    (state.env.defaults.data(forKey: SleepSchedule.key(account)),
     state.env.defaults.data(forKey: "sleep.planned.\(account ?? "signed-out")"))
}

@MainActor
private func windDowns(_ notifier: MockNotifier) -> [UNNotificationRequest] {
    notifier.requests.filter { $0.identifier.hasPrefix(BedtimePlanner.reminderPrefix) }
}

@MainActor
struct BedtimeDemoSideTests {
    @Test("A: demo data edits Bedtime & wake, turns its alarm off and turns it off: the account's schedule, nights, reminders and alarms stay",
          .timeLimit(.minutes(1)))
    func demoNeverTouchesTheAccounts() async throws {
        let (state, _, _) = sideGraph()
        let account = state.env.auth.accountID
        let notifier = try #require(state.env.notifier as? MockNotifier)
        let alarms = MockWakeAlarms()
        let planner = appPlanner(state, alarms: alarms)
        var mine = SleepSchedule.default
        mine.reminderOn = true
        mine.alarmOn = true
        await planner.update(mine)
        let before = kept(state, account: account)
        #expect(before.schedule != nil && before.nights != nil, "the account's schedule and tonight, kept")
        #expect(alarms.scheduled == mine.wake && !windDowns(notifier).isEmpty, "its alarm and wind-down, set")
        let set = (alarms.schedulings, alarms.cancellations)
        let requests = notifier.requests

        await turnDemo(state, planner, on: true)
        #expect(planner.schedule == nil && planner.plan == nil, "demo data has none of the account's")
        var demos = SleepSchedule.default
        demos.goal = .perform
        demos.reminderOn = true
        demos.alarmOn = true
        demos.setWeekdays("05:45")
        await planner.update(demos)
        #expect(planner.schedule == demos && planner.plan != nil, "demo data's own, planned")
        demos.alarmOn = false
        await planner.update(demos)
        await planner.editor.turnOff()
        #expect(planner.schedule == nil, "turned off, on demo data's side")
        let during = kept(state, account: account)
        #expect(during.schedule == before.schedule && during.nights == before.nights, "the account's schedule and nights, untouched")
        #expect(SleepSchedule.load(account: account, defaults: state.env.defaults) == mine)
        #expect(alarms.schedulings == set.0 && alarms.cancellations == set.1 && alarms.scheduled == mine.wake,
                "no alarm set or taken away: the account's rings on")
        #expect(notifier.requests.count == requests.count && zip(notifier.requests, requests).allSatisfy { $0 === $1 },
                "no reminder added or removed: the account's wind-down stays")

        await turnDemo(state, planner, on: false)
        #expect(planner.schedule == mine && planner.plan != nil, "the account's own again")
        #expect(kept(state, account: account).schedule == before.schedule)
        #expect(alarms.scheduled == mine.wake && !windDowns(notifier).isEmpty, "its alarm and wind-down, set again")
    }

    @Test("A: signed out with demo data shown: the account's reminders and alarms go, as they do on the account",
          .timeLimit(.minutes(1)))
    func aSignOutInDemoTakesTheAccountsAway() async throws {
        // An auth service of its own: the preview's shares its defaults with every other preview graph.
        let auth = AuthService(client: MockAuthClient(session: .preview()),
                               defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard,
                               wipeLocalData: { _ in true },
                               deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
        let (state, _, _) = sideGraph(auth: auth)
        let notifier = try #require(state.env.notifier as? MockNotifier)
        let alarms = MockWakeAlarms()
        let planner = appPlanner(state, alarms: alarms)
        var mine = SleepSchedule.default
        mine.reminderOn = true
        mine.alarmOn = true
        await planner.update(mine)
        await turnDemo(state, planner, on: true)
        #expect(alarms.scheduled == mine.wake && !windDowns(notifier).isEmpty, "the account's, ringing on")

        await auth.signOut()
        #expect(auth.accountID == nil)
        // As RyftApp does at an account change.
        await planner.accountChanged()
        #expect(alarms.scheduled == nil && windDowns(notifier).isEmpty, "nothing of the account's once it signed out")
    }

    @Test("1: Tonight forgets with the reset itself: the switch shows the side's schedule and plan at once, and the widget's bedtime goes")
    func tonightForgetsWithTheReset() async throws {
        let (state, _, _) = sideGraph()
        let account = state.env.auth.accountID, now = state.env.clock.now()
        // The account's Bedtime & wake and tonight's plan, kept on this iPhone at launch.
        SleepSchedule.default.save(account: account, defaults: state.env.defaults)
        let wake = SleepSchedule.default.nextWake(after: now)
        let plan = MockJournal.sleepPlan(wake: SleepPlannerViewModel.hhmm(wake), now: now)
        state.env.persistence.saveDocument(BedtimePlanner.Cached(plan: plan, fetchedAt: now), key: BedtimePlanner.cacheKey, at: now)
        let screens = appScreens(state)
        let tonight = screens.bedtime
        let mine = try #require(tonight.plan)
        #expect(tonight.schedule == .default)
        state.repository.tonightBedtime = tonight.bedtime

        // The reset alone (RyftApp's refresh comes after it): nothing of the account's is left to show.
        switchDemo(state, on: true)
        #expect(tonight.schedule == nil && tonight.plan == nil && tonight.bedtime == nil, "demo data's: none set up")
        #expect(state.repository.tonightBedtime == nil, "the widget's bedtime went with it")

        switchDemo(state, on: false)
        #expect(tonight.schedule == .default && tonight.plan == mine, "the account's own, as kept")
        withExtendedLifetime(screens) {}
    }

    @Test("2: Tonight's plan held across the switch, both ways: the account's never shows in demo data, demo data's never lands in the account's",
          .timeLimit(.minutes(1)))
    func heldTonightAnswersStayOnTheirSide() async throws {
        let (state, live, demo) = sideGraph()
        let account = state.env.auth.accountID
        let planner = appPlanner(state)
        await planner.update(.default)
        let mine = try #require(planner.plan)
        let night = DayFormat.string(from: mine.wake)

        // The account's answer held; demo data on before it lands.
        let accountHold = RequestHold()
        live.beforePlan = { _ in await accountHold.wait() }
        let asking = Task { await planner.refresh() }
        #expect(await eventually { accountHold.waiting == 1 })
        switchDemo(state, on: true)
        accountHold.release()
        await asking.value
        await planner.refresh()
        #expect(planner.schedule == nil && planner.plan == nil && planner.bedtime == nil, "nothing of the account's in demo data")
        #expect(planner.planned(nightEnding: night) == nil && state.repository.tonightBedtime == nil)
        live.beforePlan = nil

        // Demo data's own, then its answer held; demo data off before it lands.
        await planner.update(.default)
        let demos = try #require(planner.plan)
        #expect(demos != mine)
        let before = kept(state, account: account)
        let cached = state.env.persistence.document(BedtimePlanner.Cached.self, key: BedtimePlanner.cacheKey)
        let demoHold = RequestHold()
        demo.beforePlan = { _ in await demoHold.wait() }
        let demoAsking = Task { await planner.refresh() }
        #expect(await eventually { demoHold.waiting == 1 })
        switchDemo(state, on: false)
        demoHold.release()
        await demoAsking.value
        let after = kept(state, account: account)
        #expect(after.schedule == before.schedule && after.nights == before.nights, "the account's schedule and nights, as they were")
        #expect(state.env.persistence.document(BedtimePlanner.Cached.self, key: BedtimePlanner.cacheKey) == cached,
                "the account's plan on disk, as it was")
        #expect(planner.plan == mine && planner.planned(nightEnding: night)?.bed == planner.bedtime, "the account's own shows")
    }

    @Test("2: Sleep → Bedtime's plan held across the switch, both ways: the account's never shows in demo data, demo data's never lands in the account's",
          .timeLimit(.minutes(1)))
    func heldSleepTabAnswersStayOnTheirSide() async throws {
        let (state, live, demo) = sideGraph()
        let screens = appScreens(state)
        let planner = screens.sleep.planner
        await planner.load()
        let mine = try #require(planner.plan)
        let cached = state.env.persistence.document(SleepPlannerViewModel.Cached.self, key: SleepPlannerViewModel.cacheKey)
        #expect(cached?.plan == mine)

        let accountHold = RequestHold()
        live.beforePlan = { _ in await accountHold.wait() }
        let asking = Task { await planner.load() }
        #expect(await eventually { accountHold.waiting == 1 })
        switchDemo(state, on: true)
        accountHold.release()
        await asking.value
        #expect(planner.plan == nil && planner.asOf == nil && planner.failure == nil, "the account's answer, dropped")
        live.beforePlan = nil

        await planner.load()
        let demos = try #require(planner.plan)
        #expect(demos != mine)
        let demoHold = RequestHold()
        demo.beforePlan = { _ in await demoHold.wait() }
        let demoAsking = Task { await planner.load() }
        #expect(await eventually { demoHold.waiting == 1 })
        switchDemo(state, on: false)
        demoHold.release()
        await demoAsking.value
        #expect(state.env.persistence.document(SleepPlannerViewModel.Cached.self, key: SleepPlannerViewModel.cacheKey) == cached,
                "the account's plan on disk, as it was")
        #expect(planner.plan == mine, "the account's own shows")
        withExtendedLifetime(screens) {}
    }

    @Test("3: launched in demo data with the account's journal, plans and schedule on this iPhone: none of it shows")
    func aLaunchInDemoShowsNothingOfTheAccounts() async throws {
        let (state, _, _) = sideGraph()
        let account = state.env.auth.accountID, now = state.env.clock.now(), disk = state.env.persistence
        let yesterday = DayFormat.string(from: DayFormat.shift(now, days: -1))
        disk.saveDocument(MockJournal.behaviors, key: JournalStore.behaviorsKey, at: now)
        disk.saveDocument(MockJournal.journal(day: yesterday), key: JournalStore.dayKey(yesterday), at: now)
        SleepSchedule.default.save(account: account, defaults: state.env.defaults)
        let wake = SleepSchedule.default.nextWake(after: now)
        let tonight = MockJournal.sleepPlan(wake: SleepPlannerViewModel.hhmm(wake), now: now)
        disk.saveDocument(BedtimePlanner.Cached(plan: tonight, fetchedAt: now), key: BedtimePlanner.cacheKey, at: now)
        let sleepTab = SleepPlannerViewModel(state: state)
        let plan = MockJournal.sleepPlan(wake: sleepTab.wakeText, now: now)
        disk.saveDocument(SleepPlannerViewModel.Cached(plan: plan, wake: sleepTab.wakeText, fetchedAt: now),
                          key: SleepPlannerViewModel.cacheKey, at: now)
        // On the account they show (offline-first), so the launch below has them to leave out.
        #expect(!JournalStore(env: state.env).behaviors.isEmpty)
        #expect(BedtimePlanner(state: state, alarms: MockWakeAlarms()).plan != nil)
        #expect(SleepPlannerViewModel(state: state).plan == plan)

        state.env.settings.demoMode = true
        let journal = JournalStore(env: state.env)
        #expect(journal.behaviors.isEmpty && journal.availability == .unknown && journal.cachedDay(yesterday) == nil,
                "the journal: none of the account's habits or days")
        let bedtime = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        #expect(bedtime.schedule == nil && bedtime.plan == nil && bedtime.bedtime == nil, "Tonight: none of its schedule or plan")
        let sleep = SleepPlannerViewModel(state: state)
        #expect(sleep.plan == nil && sleep.asOf == nil, "Sleep → Bedtime: none of its plan")
    }

    @Test("4: Sleep → Bedtime's wake time is its side's: the switch drops the one followed and the one picked, and a plan for another wake time isn't shown")
    func sleepTabWakeStaysWithItsSide() async throws {
        let (state, _, _) = sideGraph()
        let screens = appScreens(state)
        let planner = screens.sleep.planner
        let start = planner.wakeText
        var early = SleepSchedule.default
        early.setWeekdays("05:45")
        early.setWeekend("05:45")
        planner.follow(early)
        #expect(planner.wakeText == "05:45" && start != "05:45")
        await planner.load()
        #expect(planner.plan != nil, "the account's plan for 05:45")
        planner.setWake(planner.wake.addingTimeInterval(15 * 60))
        #expect(planner.pickerMoved)

        switchDemo(state, on: true)
        #expect(planner.wakeText == start && !planner.pickerMoved && planner.plan == nil, "demo data's own wake time")
        planner.follow(early)
        #expect(planner.wakeText == "05:45", "demo data's Bedtime & wake is followed again, not the account's picker")

        state.env.connectivityMonitor.update(false)
        switchDemo(state, on: false)
        #expect(planner.wakeText == start && planner.plan == nil, "the account's 05:45 plan isn't the \(start) one")
        withExtendedLifetime(screens) {}
    }
}

@MainActor
struct DemoOfflineIsOnlineTests {
    @Test("Demo data offline is online wherever a page asks: Journal (and its sheet), Tonight and Sleep → Bedtime")
    func demoDataHasNoNetworkToLose() async throws {
        let state = AppState.preview(online: false)
        #expect(state.isDemo && !state.env.connectivity.isOnline)
        let api = try #require(state.env.api as? MockPlatformAPI)

        let journal = JournalStore(env: state.env)
        #expect(journal.isOnline && JournalSheetModel(store: journal).isOnline, "no Offline pill on the sheet")
        await journal.load()
        try await journal.setEnabled(MockJournal.magnesium, true)
        #expect(journal.behavior(MockJournal.magnesium)?.enabled == true, "saved, not refused as offline")

        let bedtime = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        #expect(bedtime.isOnline)
        let plans = api.count("sleepPlan")
        let sleepTab = SleepPlannerViewModel(state: state)
        await sleepTab.load()
        #expect(api.count("sleepPlan") == plans + 1 && sleepTab.plan != nil && sleepTab.asOf == nil, "asked, not offline")
    }
}
