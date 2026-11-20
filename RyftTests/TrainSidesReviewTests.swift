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

