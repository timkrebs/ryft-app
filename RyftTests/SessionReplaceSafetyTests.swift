import Foundation
import Testing
@testable import Ryft

// The replace's safety after review (plan.md T1 review fixes 1-4): plan tasks after Finish, two quick plan changes,
// the upload hold during the undo window, and an account change with the window open. Synthetic data only.

/// A `SessionLibrary` whose plan saves wait until the test lets them go, in the order they were asked for.
@MainActor
private final class GatedSessionLibrary: SessionLibrary {
    var plan: Plan?
    var saveSucceeds = true
    private(set) var savedPlans: [Plan] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    init(plan: Plan) { self.plan = plan }

    var waitingSaves: Int { waiting.count }

    func cachedLastTime(for exerciseID: UUID) -> [SessionSet] { [] }
    func lastTime(for exerciseID: UUID) async -> [SessionSet] { [] }
    func editablePlan(containing planExerciseID: UUID) -> Plan? {
        guard let plan, plan.days.contains(where: { $0.exercises.contains { $0.id == planExerciseID } }) else { return nil }
        return plan
    }
    func savePlan(_ plan: Plan) async -> Bool {
        if !opened { await withCheckedContinuation { waiting.append($0) } }
        savedPlans.append(plan)
        if saveSucceeds { self.plan = plan }
        return saveSucceeds
    }

    /// Every waiting save goes, and the ones after it don't wait.
    func open() {
        opened = true
        let all = waiting
        waiting = []
        for c in all { c.resume() }
    }
}

@MainActor
struct SessionReplaceSafetyTests {
    /// A second controller on the rig's session, with saves that wait.
    private func gated(_ rig: ReplaceRig) -> (SessionController, GatedSessionLibrary) {
        let library = GatedSessionLibrary(plan: rig.plan)
        let c = SessionController(session: rig.session, sync: rig.sync, liveActivity: nil, clock: rig.clock,
                                  library: library)
        return (c, library)
    }

    private func slot(_ position: Int, in plan: Plan?) -> PlanExercise? {
        plan?.days[0].exercises.first { $0.position == position }
    }

    // MARK: 1 · a plan task after Finish saves the plan only

    @Test func aPlanRevertAfterFinishSavesThePlanAndNothingElse() async throws {
        let rig = ReplaceRig()
        let (c, library) = gated(rig)
        defer { c.stop() }
        let replacing = Task { await c.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true) }
        await rig.settle { library.waitingSaves == 1 }
        c.undoReplace()
        _ = await c.finish()
        #expect(rig.store.pendingOps().isEmpty, "Finish uploaded the workout")
        let stamp = rig.session.updatedAt
        let calls = rig.api.calls.count

        library.open()
        await replacing.value
        await rig.settle { library.savedPlans.count == 2 }
        await rig.settle()

        #expect(library.savedPlans.count == 2, "the plan still goes back")
        #expect(library.savedPlans.last == rig.plan)
        #expect(rig.store.pendingOps().filter { $0.sessionId == rig.session.id }.isEmpty, "no PUT queued after Finish")
        #expect(rig.api.calls.count == calls, "nothing sent after Finish")
        #expect(rig.session.updatedAt == stamp, "the finished session isn't written again")
        #expect(rig.x.planExerciseId == nil, "no relink on the finished session")
    }

    @Test func aForwardPlanSaveAfterFinishSavesThePlanAndNothingElse() async {
        let rig = ReplaceRig()
        let (c, library) = gated(rig)
        defer { c.stop() }
        let replacing = Task { await c.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true) }
        await rig.settle { library.waitingSaves == 1 }
        _ = await c.finish()
        let stamp = rig.session.updatedAt

        library.open()
        await replacing.value
        await rig.settle()

        #expect(library.savedPlans.count == 1)
        #expect(slot(1, in: library.plan)?.exerciseId == rig.incline.id)
        #expect(rig.store.pendingOps().isEmpty)
        #expect(rig.session.updatedAt == stamp)
        #expect(c.notice == nil && c.undo == nil)
    }

    // MARK: 2 · two quick plan changes

    @Test func twoQuickPlanChangesBothStay() async throws {
        let rig = ReplaceRig()
        let (c, library) = gated(rig)
        defer { c.stop() }
        let a = Task { await c.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true) }
        await rig.settle { library.waitingSaves == 1 }
        let b = Task { await c.replaceExercise(rig.row, with: rig.other, alsoChangePlan: true) }
        await rig.settle { c.undo?.newName == rig.other.name }
        #expect(library.waitingSaves == 1, "the second save waits for the first")

        library.open()
        await a.value
        await b.value

        #expect(library.savedPlans.count == 2)
        #expect(slot(1, in: library.plan)?.exerciseId == rig.incline.id, "A stays")
        #expect(slot(0, in: library.plan)?.exerciseId == rig.other.id, "B too")
    }

    @Test func undoingTheSecondPlanChangeKeepsTheFirst() async throws {
        let rig = ReplaceRig()
        let (c, library) = gated(rig)
        defer { c.stop() }
        let a = Task { await c.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true) }
        await rig.settle { library.waitingSaves == 1 }
        let b = Task { await c.replaceExercise(rig.row, with: rig.other, alsoChangePlan: true) }
        await rig.settle { c.undo?.newName == rig.other.name }

        library.open()
        await a.value
        await b.value
        c.undoReplace()
        await rig.settle { library.savedPlans.count == 3 }

        #expect(library.savedPlans.count == 3)
        #expect(slot(1, in: library.plan)?.exerciseId == rig.incline.id, "A stays")
        #expect(slot(0, in: library.plan) == rig.plan.days[0].exercises[0], "B's slot is back as it was")
        await rig.settle { rig.row.planExerciseId != nil }
        #expect(rig.row.planExerciseId == rig.peRow)
    }

    @Test func undoingTheSecondBeforeItsTurnSavesItNever() async throws {
        let rig = ReplaceRig()
        let (c, library) = gated(rig)
        defer { c.stop() }
        let a = Task { await c.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true) }
        await rig.settle { library.waitingSaves == 1 }
        let b = Task { await c.replaceExercise(rig.row, with: rig.other, alsoChangePlan: true) }
        await rig.settle { c.undo?.newName == rig.other.name }
        c.undoReplace()

        library.open()
        await a.value
        await b.value
        await rig.settle { rig.row.planExerciseId != nil }

        #expect(library.savedPlans.count == 1, "only A's save")
        #expect(slot(1, in: library.plan)?.exerciseId == rig.incline.id)
        #expect(slot(0, in: library.plan) == rig.plan.days[0].exercises[0])
        #expect(rig.row.planExerciseId == rig.peRow)
    }

    // MARK: 3 · no upload while the undo window is open

    @Test func aPutQueuedBeforeTheReplaceWaitsForTheWindow() async throws {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        // A set checked: its PUT is queued, waiting for the debounce.
        rig.controller.toggleCheck(rig.row.orderedSets[0], in: rig.row)
        #expect(rig.puts.count == 1)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        let y = try #require(rig.session.exercises.first { $0.exerciseId == rig.incline.id }?.id)

        // The debounce, a reconnect or the app coming back all flush.
        await rig.sync.flush()
        #expect(rig.controller.undo != nil)
        #expect(!rig.api.calls.contains("putSession"), "nothing goes while Undo can still take the replace back")
        #expect(rig.puts.count == 1, "the PUT stays queued")

        rig.controller.undoReplace()
        await rig.sync.flush()
        #expect(rig.api.calls.filter { $0 == "putSession" }.count == 1)
        let doc = try await rig.api.session(id: rig.session.id)
        #expect(!doc.exercises.contains { $0.id == y || $0.exerciseId == rig.incline.id })
        #expect(doc.exercises.count == 4)
        #expect(doc.exercises.first { $0.id == rig.row.id }?.sets.first?.completedAt != nil, "the checked set went")
    }

    @Test func theHeldPutGoesOnceTheWindowEnds() async throws {
        let rig = ReplaceRig()
        rig.controller.toggleCheck(rig.row.orderedSets[0], in: rig.row)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        await rig.sync.flush()
        #expect(!rig.api.calls.contains("putSession"))

        await rig.expireUndoWindow()
        #expect(!rig.sync.isHeld(rig.session.id))
        await rig.sync.flush()
        let doc = try await rig.api.session(id: rig.session.id)
        #expect(doc.exercises.first { $0.id == rig.x.id }?.exerciseId == rig.incline.id)
    }

    @Test func anotherSessionsUploadIsNotHeld() async {
        let rig = ReplaceRig()
        rig.controller.toggleCheck(rig.row.orderedSets[0], in: rig.row)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        let other = UUID()
        rig.store.enqueue(.delete, sessionID: other, account: "test")
        await rig.sync.flush()
        #expect(rig.api.calls.contains("deleteSession"))
        #expect(!rig.api.calls.contains("putSession"))
    }

    // MARK: 4 · an account change with the window open

    @Test func signingOutWithAnOpenUndoQueuesAndWritesNothing() async {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        let coordinator = TrainCoordinator(sync: rig.sync, library: TrainLibrary.preview(store: rig.store),
                                           liveActivities: false)
        coordinator.live = rig.controller

        // The sign-out wipes the store and moves the sync service first (AuthService.wipeSharedLocalData) ...
        rig.store.wipe()
        rig.sync.accountChanged()
        // ... the toast's onDisappear may run before the app's handler ...
        rig.controller.commitUndo()
        // ... which stops the controller.
        coordinator.accountChanged()
        rig.clock.advance(by: .seconds(10))
        await rig.settle()

        #expect(rig.controller.undo == nil)
        #expect(rig.store.pendingOps().isEmpty)
        #expect(!rig.sync.isHeld(rig.controller.id))
    }

    @Test func stopDropsTheUndoWithoutAWrite() async {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        let stamp = rig.session.updatedAt
        rig.controller.stop()
        #expect(rig.controller.undo == nil)
        // The toast's onDisappear and the window's end find nothing to commit.
        rig.controller.commitUndo()
        rig.clock.advance(by: .seconds(10))
        await rig.settle()
        #expect(rig.puts.isEmpty)
        #expect(rig.session.updatedAt == stamp)
    }

    // MARK: nits

    @Test func aFailedPlanSaveAfterItsUndoShowsNoNotice() async {
        let rig = ReplaceRig()
        let (c, library) = gated(rig)
        defer { c.stop() }
        library.saveSucceeds = false
        let replacing = Task { await c.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true) }
        await rig.settle { library.waitingSaves == 1 }
        c.undoReplace()
        // The same exercise on another row, so the session has it again while the failed save comes back.
        let curlName = rig.curl.name
        await c.replaceExercise(rig.curl, with: rig.incline)
        library.open()
        await replacing.value
        await rig.settle()
        #expect(c.notice == nil, "that replace was taken back: nothing to say about its plan")
        #expect(c.undo?.newName == rig.incline.name, "the open undo is the curl's, its message unchanged")
        #expect(c.undo?.message == SessionController.message(replacedWith: rig.incline.name, kind: .inPlace,
                                                             oldName: curlName, planDay: nil))
    }

    @Test func restStepsOverTheWholeRangeTheAPIAllows() {
        var t = SessionTargets(sets: 3, restSec: 900)
        t.stepRest(1)
        #expect(t.restSec == 900)
        t.stepRest(-1)
        #expect(t.restSec == 885)
        t.restSec = 15
        t.stepRest(-1)
        #expect(t.restSec == 0)
        t.stepRest(-1)
        #expect(t.restSec == 0)
    }

    @Test func switchControlGetsTheLongWindowToo() {
        #expect(SessionController.undoWindow(voiceOver: false, switchControl: false) == .seconds(5))
        #expect(SessionController.undoWindow(voiceOver: true, switchControl: false) == .seconds(10))
        #expect(SessionController.undoWindow(voiceOver: false, switchControl: true) == .seconds(10))
    }
}
