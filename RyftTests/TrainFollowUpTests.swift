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

/// F1 item 3: after a pause, a resume, a switch or a delete the plans are read again, and that read can fail. The overview
/// then still holds what the action changed (`TrainLibrary.patchCatalog`): the page never undoes the action on screen, and
/// nothing is patched for a side that ended meanwhile. Synthetic data only (Alex Doe).
@MainActor
@Suite("F1 item 3: an action's result survives a failed re-read", .serialized)
struct TrainActionPatchTests {
    private let refused = APIError.http(400, "bad request", requestID: "rid-alex-400")

    /// The overview as stored, which the next launch shows.
    private func stored(_ rig: TrainSides) -> PlansOverview? { rig.store.document(PlansOverview.self, key: "train.plans") }

    /// Pause, and the plans can't be read after it: paused on Plans and on the page (Resume, no week), no plan day.
    @Test func aPauseWithTheReadAfterItFailingShowsPaused() async {
        let previous = TrainShotFixtures.setPausedPlan(nil)
        defer { _ = TrainShotFixtures.setPausedPlan(previous) }
        let alex = SideTrainSource(.demo)
        let rig = TrainSides([SideSwitch.alex: alex])
        await rig.library.refresh()
        #expect(rig.library.activeEnrollment?.status == .active && rig.library.today != nil)
        alex.fail(.plans, with: refused)
        let page = PlanDetailViewModel(planID: MockTrain.upperLower.id, library: rig.library)
        let plans = PlansViewModel(library: rig.library)
        #expect(await rig.library.setPaused(true))
        #expect(alex.count(.plans) == 2, "the plans were read again, and that failed")
        #expect(rig.library.pausedPlanID == MockTrain.upperLower.id)
        #expect(page.isCurrent && page.isPaused && page.activeWeek == nil, "the page offers Resume")
        #expect(plans.tile?.state == .paused && plans.tile?.planID == MockTrain.upperLower.id)
        #expect(rig.library.activeEnrollment == nil && stored(rig)?.active == nil, "as GET /v1/plans reports it, stored too")
        #expect(rig.library.today == nil, "no plan day of a paused plan")
    }

    /// Resume with the read failing: active again, where it stopped (the platform's answer), not paused.
    @Test func aResumeWithTheReadAfterItFailingShowsItActive() async {
        let previous = TrainShotFixtures.setPausedPlan(nil)
        defer { _ = TrainShotFixtures.setPausedPlan(previous) }
        let alex = SideTrainSource(.demo)
        let rig = TrainSides([SideSwitch.alex: alex])
        await rig.library.refresh()
        #expect(await rig.library.setPaused(true) && rig.library.isPaused)
        alex.fail(.plans, with: refused)
        let page = PlanDetailViewModel(planID: MockTrain.upperLower.id, library: rig.library)
        #expect(await rig.library.setPaused(false))
        #expect(!rig.library.isPaused && !page.isPaused, "the page offers Pause")
        #expect(rig.library.activeEnrollment?.planId == MockTrain.upperLower.id)
        #expect(rig.library.activeEnrollment?.status == .active && page.activeWeek == MockTrain.enrollment.currentWeek)
        #expect(stored(rig)?.active?.id == MockTrain.enrollment.id)
    }

    /// Switching plans with the read failing: the new plan is the active one, and the old plan's day isn't offered.
    @Test func aSwitchWithTheReadAfterItFailingShowsTheNewPlan() async {
        let alex = SideTrainSource(.demo)
        let rig = TrainSides([SideSwitch.alex: alex])
        await rig.library.refresh()
        #expect(rig.library.today?.enrollment.planId == MockTrain.upperLower.id)
        alex.fail(.plans, with: refused)
        #expect(await rig.library.enroll(in: MockTrain.fullBody))
        #expect(rig.library.activeEnrollment?.planId == MockTrain.fullBody.id && rig.library.activePlanName == "Full Body 3×")
        #expect(stored(rig)?.active?.planId == MockTrain.fullBody.id)
        #expect(rig.library.today == nil, "Upper/Lower's day isn't today's plan day any more")
    }

    /// Deleting one of the user's plans with the read failing: it's gone from the list (and the stored copy), and the
    /// active plan stays.
    @Test func aDeleteWithTheReadAfterItFailingDropsThePlan() async {
        let alex = SideTrainSource(.demo)
        let rig = TrainSides([SideSwitch.alex: alex])
        await rig.library.refresh()
        let mine = MockTrain.homeDumbbells
        let plans = PlansViewModel(library: rig.library)
        #expect(plans.mine.contains { $0.id == mine.id })
        alex.fail(.plans, with: refused)
        #expect(await rig.library.deletePlan(mine))
        #expect(!plans.mine.contains { $0.id == mine.id } && !plans.mineRows.contains { $0.id == mine.id })
        #expect(stored(rig)?.mine.contains { $0.id == mine.id } == false)
        #expect(rig.library.activeEnrollment?.planId == MockTrain.upperLower.id && rig.library.today != nil)
    }

    /// Deleting the plan the user is on, with the read failing: its enrolment goes with it (`DELETE` removes it), active or
    /// paused, so Plans has no tile and nothing to resume.
    @Test(arguments: [false, true])
    func deletingTheCurrentPlanEndsItsEnrolment(paused: Bool) async throws {
        let previous = TrainShotFixtures.setPausedPlan(nil)
        defer { _ = TrainShotFixtures.setPausedPlan(previous) }
        let alex = SideTrainSource(.demo)
        let mine = MockTrain.homeDumbbells
        try await alex.enrollNow(mine.id)
        let rig = TrainSides([SideSwitch.alex: alex])
        await rig.library.refresh()
        #expect(rig.library.activeEnrollment?.planId == mine.id && rig.library.today != nil)
        if paused { #expect(await rig.library.setPaused(true) && rig.library.pausedPlanID == mine.id) }
        alex.fail(.plans, with: refused)
        let plans = PlansViewModel(library: rig.library)
        #expect(await rig.library.deletePlan(mine))
        #expect(rig.library.activeEnrollment == nil && rig.library.pausedPlanID == nil && plans.tile == nil)
        #expect(rig.library.today == nil && stored(rig)?.active == nil)
        #expect(UserDefaults.standard.string(forKey: "train.pausedPlanID") == nil)
    }

    /// Alex's pause is answered after the Demo data switch, with the demo enrolled in the same plan: the demo's overview and
    /// plan day aren't patched, and the demo's plan isn't paused.
    @Test func aBindingChangeBeforeThePatchWritesNothing() async throws {
        let previous = TrainShotFixtures.setPausedPlan(nil)
        defer { _ = TrainShotFixtures.setPausedPlan(previous) }
        let alex = SideTrainSource(.demo, holding: [.pause])
        let demo = SideTrainSource(.demo)
        let rig = TrainSides([SideSwitch.alex: alex, SideSwitch.demo: demo])
        await rig.library.refresh()
        let pause = Task { await rig.library.setPaused(true) }
        #expect(await eventually { alex.count(.pause) == 1 }, "Alex's pause is on its way")
        rig.switchTo(SideSwitch.demo)
        rig.library.demoModeChanged()
        await rig.library.refresh()
        let demos = try #require(rig.library.catalog)
        let demosDay = try #require(rig.library.today)
        #expect(demos.active?.status == .active && demos.active?.planId == MockTrain.upperLower.id)
        alex.release()
        #expect(await pause.value == false)
        #expect(rig.library.catalog == demos && stored(rig) == demos, "the demo's overview as the demo read it")
        #expect(rig.library.today == demosDay && !rig.library.isPaused)
        #expect(alex.count(.plans) == 1, "nor were Alex's plans read again")
    }
}
