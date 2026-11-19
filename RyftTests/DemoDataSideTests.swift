import Foundation
import Testing
@testable import Ryft

// PR 6 C's fix round 2 (6c8): demo data's plans are never the account's (review 2, item 1: Tonight's `BedtimePlanner` and
// Sleep → Bedtime keep demo data's last plan in memory only, never in the account's store), and demo data counts as online
// wherever a page asks (item 4). Synthetic data only (Alex Doe).

/// An account beside a switchable Demo data (`settings.demoMode`), each side with its own platform, at 17:42. Demo data
/// plans another night (its bedtimes 45 minutes earlier), so the two plans never look alike.
@MainActor
private func sideGraph() -> (AppState, live: MockPlatformAPI, demo: MockPlatformAPI) {
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
                             auth: .preview(), persistence: TrainStore(inMemory: true), clock: clock, notifier: MockNotifier(),
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

        let hold = RequestHold()
        demo.beforePlan = { _ in await hold.wait() }
        switchDemo(state, on: true)
        // As RyftApp does when the switch turns.
        let switching = Task { await planner.accountChanged() }
        #expect(await eventually { hold.waiting == 1 })
        #expect(planner.plan == nil && planner.bedtime == nil, "nothing of the account's while demo data plans")
        hold.release()
        await switching.value
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
