import Foundation
import Testing
@testable import Ryft

/// PR 6's R4 re-checks, follow-up F1 item 1: a plan's failed read is its page's alone. The library's `error` is the Plans
/// page's and the actions': plan X's failure there would show on Plans (whose Try again reads the plans, not X) and in plan
/// Y's actions block. Synthetic data only (Alex Doe).
@MainActor
@Suite("F1 item 1: a plan's failure stays on its page", .serialized)
struct PlanFailureStaysOnItsPageTests {
    private let refused = APIError.http(400, "bad request", requestID: "rid-alex-400")
    private let details = "HTTP 400 · Request ID rid-alex-400"

    /// Plans loaded; plan X (not cached) fails on its page: the page has the failure and its Details, Plans has no message.
    @Test func aFailedPlanLeavesPlansWithoutAMessage() async {
        let alex = SideTrainSource(.demo)
        let rig = TrainSides([SideSwitch.alex: alex])
        let plans = PlansViewModel(library: rig.library)
        await plans.loadIfNeeded()
        #expect(plans.hasCatalog && plans.error == nil)
        alex.fail(.plan, with: refused)
        let x = PlanDetailViewModel(planID: MockTrain.fullBody.id, library: rig.library)
        await x.load()
        #expect(alex.count(.plan) == 1 && x.failure != nil && x.failureDetails == details, "the page's own")
        #expect(plans.error == nil && plans.errorDetails == nil, "Plans: \(plans.errorDetails ?? "nil")")
        #expect(rig.library.error == nil && rig.library.errorDetails == nil)
    }

    /// Plan Y is open (cached); plan X fails: Y's actions block shows nothing of X's.
    @Test func anotherPlansPageDoesNotShowTheFailure() async {
        let alex = SideTrainSource(.demo)
        let rig = TrainSides([SideSwitch.alex: alex])
        rig.store.cache(plans: [MockTrain.upperLower])
        let y = PlanDetailViewModel(planID: MockTrain.upperLower.id, library: rig.library)
        await y.load()
        await rig.library.planRefresh?.value
        #expect(y.plan?.id == MockTrain.upperLower.id && y.error == nil)
        alex.fail(.plan, with: refused)
        let x = PlanDetailViewModel(planID: MockTrain.fullBody.id, library: rig.library)
        await x.load()
        #expect(x.failureDetails == details)
        #expect(y.error == nil && y.errorDetails == nil, "Y's actions block: \(y.errorDetails ?? "nil")")
        #expect(y.failure == nil, "Y has its plan")
    }

    /// Start workout reads the active plan for "A day from …"; that read fails: no days offered, and Plans stays clean.
    @Test func startWorkoutsFailedPlanReadLeavesPlansClean() async {
        let alex = SideTrainSource(.demo)
        let rig = TrainSides([SideSwitch.alex: alex])
        let plans = PlansViewModel(library: rig.library)
        await plans.loadIfNeeded()
        #expect(rig.library.activeEnrollment?.planId == MockTrain.upperLower.id)
        alex.fail(.plan, with: refused)
        let start = TrainTodayViewModel(library: rig.library, store: rig.store, clock: TestClock(now: .now))
        await start.loadStartOptions()
        #expect(alex.count(.plan) == 1, "the active plan was asked for")
        #expect(start.activePlan == nil && start.planDays.isEmpty)
        #expect(plans.error == nil && plans.errorDetails == nil, "Plans: \(plans.errorDetails ?? "nil")")
    }
}
