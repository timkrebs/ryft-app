import Foundation
import Testing
@testable import Ryft

/// PR 6 review, round R4T: a refresh that outlives its binding sends nothing more and writes nothing, and the Demo data side
/// never joins a read the account started (code review S1). Synthetic data only (Alex Doe, Sam Roe).
@MainActor
@Suite("R4T S1: Train's reads stay on their side", .serialized)
struct TrainRefreshSidesTests {
    /// What the demo answers for the plans and today's plan day: Upper/Lower 4×, enrolled.
    private func demoAnswers() async throws -> (PlansOverview, PlanToday?) {
        let demo = SideTrainSource(.demo)
        return (try await demo.plansNow(), try await demo.todayNow())
    }

    /// The scenario of the review, through the app's read pipeline: the account's refresh waits at the exercises on a slow
    /// network; Demo data goes on (the reset stops that read); the account's refresh goes on, and RyftApp's demo refresh
    /// follows. The account's plans are never asked for again, and the demo's own land as the demo's.
    @Test func aDemoRefreshAfterTheResetGetsTheDemosOwnPlans() async throws {
        let env = AppEnvironment.test()
        let account = SideTrainSource(.empty, holding: [.exercises, .plans])
        let demo = SideTrainSource(.demo)
        let rig = TrainSides([SideSwitch.alex: account, SideSwitch.demo: demo], reads: env.reads)
        let accountRefresh = Task { await rig.library.refresh() }
        #expect(await eventually { account.count(.exercises) == 1 }, "the account's refresh waits at the exercises")

        // Profile's switch: the reads in flight stop (`AppState.reset`), the binding is the demo's, the other side's goes.
        env.reads.reset()
        rig.switchTo(SideSwitch.demo)
        rig.library.demoModeChanged()
        let done = DoneFlag()
        let demoRefresh = Task {
            await rig.library.refresh()
            done.on = true
        }
        // Bounded: a demo refresh that joined the account's flight waits for it until the release below.
        _ = await eventually(timeout: .seconds(1)) { done.on }
        account.release()
        await demoRefresh.value
        await accountRefresh.value

        let (plans, today) = try await demoAnswers()
        #expect(rig.library.catalog == plans && rig.store.document(PlansOverview.self, key: "train.plans") == plans)
        #expect(rig.library.today == today && today != nil)
        #expect(account.count(.plans) == 0 && account.count(.today) == 0, "nothing more asked for the account")
        withExtendedLifetime(env) {}
    }

    /// A refresh whose binding ends while it waits sends none of its other parts with the old binding's client.
    @Test func aRefreshWhoseBindingEndedSendsNothingMore() async {
        let account = SideTrainSource(.demo, holding: [.exercises])
        let rig = TrainSides([SideSwitch.alex: account, SideSwitch.demo: SideTrainSource(.demo)])
        let refresh = Task { await rig.library.refresh() }
        #expect(await eventually { account.count(.exercises) == 1 })
        rig.switchTo(SideSwitch.demo)
        account.release()
        await refresh.value
        #expect(account.count(.plans) == 0 && account.count(.today) == 0, "not sent: the client's binding is over")
        #expect(rig.library.catalog == nil && rig.library.today == nil && rig.library.exercises.isEmpty)
    }

    /// The account's failure ("HTTP 400 · Request ID …") isn't written onto the demo's Plans page once the binding ended,
    /// and the demo's own message stays.
    @Test func aRefreshWhoseBindingEndedLeavesTheNextSidesMessage() async {
        let account = SideTrainSource(.demo, holding: [.plans])
        account.fail(.exercises, with: APIError.http(400, "bad request", requestID: "rid-alex-400"))
        let rig = TrainSides([SideSwitch.alex: account, SideSwitch.demo: SideTrainSource(.demo)])
        let refresh = Task { await rig.library.refresh() }
        #expect(await eventually { account.count(.plans) == 1 }, "the exercises failed; the plans wait")
        rig.switchTo(SideSwitch.demo)
        rig.library.error = "The demo's message"
        rig.library.errorDetails = "HTTP 503 · Request ID rid-demo-503"
        account.release()
        await refresh.value
        #expect(rig.library.error == "The demo's message")
        #expect(rig.library.errorDetails == "HTTP 503 · Request ID rid-demo-503", "\(rig.library.errorDetails ?? "nil")")
    }

    /// The old side's refresh ending doesn't end the loading of the new side's, still running.
    @Test func aRefreshWhoseBindingEndedLeavesTheNextOneLoading() async {
        let account = SideTrainSource(.demo, holding: [.plans])
        let demo = SideTrainSource(.demo, holding: [.plans])
        let rig = TrainSides([SideSwitch.alex: account, SideSwitch.demo: demo])
        let old = Task { await rig.library.refresh() }
        #expect(await eventually { account.count(.plans) == 1 })
        rig.switchTo(SideSwitch.demo)
        let new = Task { await rig.library.refresh() }
        #expect(await eventually { demo.count(.plans) == 1 })
        account.release()
        await old.value
        #expect(rig.library.isLoading, "the demo's refresh still runs")
        demo.release()
        await new.value
        #expect(!rig.library.isLoading)
    }

    /// Without a reset between them (the second guard): the account's plans are in flight when the binding becomes the
    /// demo's, and the demo's refresh reads its own, never joining the account's flight.
    @Test func theDemoNeverJoinsAFlightTheAccountStarted() async throws {
        let env = AppEnvironment.test()
        let account = SideTrainSource(.empty, holding: [.plans])
        let demo = SideTrainSource(.demo)
        let rig = TrainSides([SideSwitch.alex: account, SideSwitch.demo: demo], reads: env.reads)
        let accountRefresh = Task { await rig.library.refresh() }
        #expect(await eventually { account.count(.plans) == 1 }, "the account's plans are in flight")
        rig.switchTo(SideSwitch.demo)
        let done = DoneFlag()
        let demoRefresh = Task {
            await rig.library.refresh()
            done.on = true
        }
        _ = await eventually(timeout: .seconds(1)) { done.on }
        account.release()
        await demoRefresh.value
        await accountRefresh.value

        let (plans, today) = try await demoAnswers()
        #expect(demo.count(.plans) == 1, "the demo asked its own platform")
        #expect(rig.library.catalog == plans && rig.library.today == today)
        withExtendedLifetime(env) {}
    }

    /// The key carries the binding's owner: the demo's and an account's reads of one resource are two flights.
    @Test func trainsReadKeysCarryTheOwner() {
        let rig = TrainSides([:])
        let alex = rig.library.binding
        rig.switchTo(SideSwitch.demo)
        let demo = rig.library.binding
        #expect(TrainLibrary.readKey("plans", for: alex) == ReadKey(.train, id: "alex-doe/plans"))
        #expect(TrainLibrary.readKey("plans", for: demo) == ReadKey(.train, id: "demo/plans"))
    }
}

/// The app's models on `state` with `rig`'s library and store: the account-state forgetters as `ScreenModels` connects them.
@MainActor
func sidesScreens(_ state: AppState, _ rig: TrainSides) -> ScreenModels {
    let sync = SyncService(env: state.env)
    return ScreenModels(state: state, sync: sync,
                        coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock),
                        store: rig.store, library: rig.library)
}

/// Security review S-A: Start workout's last session and plan live as long as the app; another account, a sign-out or the
/// Demo data switch never shows the previous side's, and a late answer for it is dropped. Synthetic data only.
@MainActor
@Suite("R4T S-A: Start workout's options stay on their side", .serialized)
struct TrainStartOptionsSidesTests {
    /// Loaded for Alex, then the reset every switch runs (`AppState.reset`, the forgetters `ScreenModels` registers): no
    /// "Repeat last session", no "A day from …".
    @Test func theSwitchForgetsTheLastSessionAndThePlan() async {
        let state = AppState(env: .test())
        let rig = TrainSides([SideSwitch.alex: SideTrainSource(.demo)])
        let screens = sidesScreens(state, rig)
        await rig.library.refresh()
        let model = screens.trainToday
        await model.loadStartOptions()
        #expect(model.lastSession != nil && model.activePlan?.id == MockTrain.upperLower.id)
        state.reset()
        #expect(model.lastSession == nil, "no Repeat last session of the side that ended")
        #expect(model.activePlan == nil && model.planDays.isEmpty, "no A day from its plan")
        withExtendedLifetime(screens) {}
    }

    /// Sam signs in after Alex on this iPhone, with no plan of his own: no "A day from" Alex's plan, even with the sheet's
    /// model never told (the plan shown follows the enrolment in use).
    @Test func anotherAccountWithoutAPlanGetsNoDayFromThePreviousOnes() async {
        let rig = TrainSides([SideSwitch.alex: SideTrainSource(.demo), SideSwitch.sam: SideTrainSource(.empty)])
        let model = TrainTodayViewModel(library: rig.library, store: rig.store, clock: TestClock(now: .now))
        await rig.library.refresh()
        await model.loadStartOptions()
        #expect(model.activePlan?.id == MockTrain.upperLower.id, "Alex's")
        // Alex signs out (the wipe), Sam signs in.
        _ = rig.store.wipe()
        rig.library.wipe()
        rig.switchTo(SideSwitch.sam)
        await rig.library.refresh()
        #expect(rig.library.activeEnrollment == nil)
        await model.loadStartOptions()
        #expect(model.activePlan == nil && model.planDays.isEmpty, "no A day from Alex's plan")
    }

    /// Alex's last session is on its way when Demo data goes on; the demo's sheet loads its own; Alex's late answer
    /// doesn't replace it.
    @Test func aLateLastSessionAfterTheSwitchIsDropped() async throws {
        let alex = SideTrainSource(.demo, holding: [.session])
        let rig = TrainSides([SideSwitch.alex: alex, SideSwitch.demo: SideTrainSource(.demo)])
        let model = TrainTodayViewModel(library: rig.library, store: rig.store, clock: TestClock(now: .now))
        let late = Task { await model.loadStartOptions() }
        #expect(await eventually { alex.count(.session) == 1 }, "Alex's last session is on its way")
        rig.switchTo(SideSwitch.demo)
        rig.library.demoModeChanged()
        model.forget()
        await model.loadStartOptions()
        let demos = try #require(model.lastSession, "the demo's own")
        alex.release()
        await late.value
        #expect(model.lastSession == demos, "Alex's late answer doesn't replace the demo's")
    }

    /// The sweep: Strain's failed day (its sentence and request ID) and a deep link's Train page go with the switch, and
    /// the next side's uncached day shows its outlines until it loads, not "no strain".
    @Test func strainForgetsItsFailedDayWithTheSwitch() async {
        let api = MockPlatformAPI()
        api.failure = APIError.http(400, "bad request", requestID: "rid-alex-400")
        let state = AppState(env: .test(api: api, clock: TestClock(now: .now)))
        let rig = TrainSides([SideSwitch.alex: SideTrainSource(.demo)])
        let screens = sidesScreens(state, rig)
        let strain = screens.strain
        await strain.load()
        #expect(strain.board.failure?.details == "HTTP 400 · Request ID rid-alex-400")
        strain.requestedRoute = .history
        state.reset()
        #expect(strain.board.failure == nil, "the side that ended's failure")
        #expect(strain.board.look == .loading, "the next side's day isn't loaded yet")
        #expect(strain.requestedRoute == nil)
        withExtendedLifetime(screens) {}
    }
}

