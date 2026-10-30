import Foundation
import Testing
@testable import Ryft

/// "What's next" has one definition (lead decisions D-a to D-d): the jump, the highlight, the rest bar's "Next:" and
/// "All sets done" agree. Plus the review's timing cases: two checks inside the delay, an uncheck, finishing early.
@MainActor
struct SessionNextUpTests {
    private struct Rig {
        let c: SessionController
        let clock: TestClock
        let ex: [LocalSessionExercise]
    }

    /// One exercise per count, in order (synthetic: bench, squat, bench again).
    private func rig(_ counts: [Int]) -> Rig {
        let store = TrainStore(inMemory: true)
        let sync = TrainSyncService(store: store, remote: { MockPlatformAPI() }, monitorsNetwork: false)
        sync.gate = { _ in nil }
        let s = SessionFactory.empty(in: store)
        let library = [MockTrain.bench, MockTrain.squat, MockTrain.bench]
        let ex = counts.enumerated().map { i, n in SessionFactory.add(library[i % library.count], to: s, sets: n, in: store) }
        let clock = TestClock()
        return Rig(c: SessionController(session: s, sync: sync, liveActivity: nil, clock: clock), clock: clock, ex: ex)
    }

    private func drain() async { for _ in 0..<200 { await Task.yield() } }

    /// Checks a set and lets the 0.6 s run out.
    private func check(_ r: Rig, _ set: LocalSet, in ex: LocalSessionExercise) async {
        r.c.toggleCheck(set, in: ex)
        await drain()
        r.clock.advance(by: SessionAdvance.delay)
        await drain()
    }

    private func target(_ r: Rig) -> SessionAdvance.SetRef? {
        guard case let .advance(_, to)? = r.c.advance?.step else { return nil }
        return to
    }

    private func ref(_ ex: LocalSessionExercise, _ i: Int) -> SessionAdvance.SetRef {
        SessionAdvance.SetRef(exerciseID: ex.id, setID: ex.orderedSets[i].id)
    }

    // MARK: warm-ups (D-a, D-b)

    @Test func anOpenWarmUpIsSkippedAndDoesNotBlockAllDone() async throws {
        let r = rig([3, 1])
        let a = r.ex[0], b = r.ex[1]
        r.c.toggleWarmup(a.orderedSets[0])              // a warm-up the user never checks
        await check(r, a.orderedSets[1], in: a)
        await check(r, a.orderedSets[2], in: a)
        #expect(r.c.isCollapsed(a))
        #expect(target(r) == ref(b, 0))
        #expect(r.c.currentSetID == b.orderedSets[0].id)
        #expect(r.c.nextLabel().hasPrefix(b.name))

        await check(r, b.orderedSets[0], in: b)
        #expect(r.c.isAllDone)
        #expect(r.c.nextUp == nil && r.c.currentSetID == nil)
        guard case .allDone? = r.c.advance?.step else { Issue.record("expected allDone"); return }
        #expect(r.c.isCollapsed(b))
    }

    @Test func warmUpsOfAnExerciseStillOpenAreNextAsBefore() {
        let r = rig([3])
        let a = r.ex[0]
        r.c.toggleWarmup(a.orderedSets[0])
        #expect(r.c.currentSetID == a.orderedSets[0].id)
    }

    @Test func anEmptySessionOrOneWithNoSetsIsNotAllDone() {
        #expect(!rig([]).c.isAllDone)
        let r = rig([1])
        r.c.delete(r.ex[0].orderedSets[0], from: r.ex[0])
        #expect(!r.c.isAllDone)
    }

    @Test func onlyWarmUpsCheckedIsNotAllDone() {
        let r = rig([1])
        let a = r.ex[0]
        r.c.toggleWarmup(a.orderedSets[0])
        r.c.toggleCheck(a.orderedSets[0], in: a)
        #expect(!r.c.isAllDone)                         // no working set at all was checked
    }

    // MARK: order (D-a)

    @Test func aSkippedSetDoesNotPullTheJumpBackAboveLaterOpenSets() async {
        let r = rig([2, 2, 1])
        let a = r.ex[0], b = r.ex[1], c = r.ex[2]
        await check(r, a.orderedSets[0], in: a)         // A2 left open
        await check(r, b.orderedSets[0], in: b)
        await check(r, b.orderedSets[1], in: b)
        #expect(target(r) == ref(c, 0))                 // forward, not back to A2
        #expect(r.c.currentSetID == c.orderedSets[0].id)
        await check(r, c.orderedSets[0], in: c)
        #expect(target(r) == ref(a, 1))                 // then it wraps to the top
        #expect(!r.c.isAllDone)
    }

    @Test func theRestBarNamesWhatTheJumpTargets() async {
        let r = rig([1, 2])
        let a = r.ex[0], b = r.ex[1]
        await check(r, a.orderedSets[0], in: a)
        #expect(r.c.nextLabel() == r.c.nextLabel(after: a))
        #expect(r.c.nextUp?.set.id == b.orderedSets[0].id)
    }

    @Test func nextWrapsAndSkipsFinishedExercises() {
        typealias A = SessionAdvance
        func ex(_ done: [Bool], group: Int? = nil) -> A.ExerciseState {
            A.ExerciseState(id: UUID(), supersetGroup: group,
                            sets: done.map { A.SetState(id: UUID(), isWarmup: false, isCompleted: $0) })
        }
        let a = ex([true, false]), b = ex([true, true]), c = ex([false])
        #expect(A.next(after: nil, in: [a, b, c])?.exerciseID == a.id)        // no check yet: from the top
        #expect(A.next(after: b.id, in: [a, b, c])?.exerciseID == c.id)       // below first
        #expect(A.next(after: c.id, in: [a, b, c])?.exerciseID == c.id)       // its own open set
        let s1 = ex([true, false], group: 1), s2 = ex([true, false], group: 1)
        #expect(A.next(after: s2.id, in: [s1, s2, c])?.exerciseID == s1.id)   // the partner wraps inside the group
        #expect(A.next(after: UUID(), in: [b])?.exerciseID == nil)             // a removed exercise: from the top
    }

    // MARK: D-c

    @Test func aForgottenMiddleSetFinishesTheExerciseAndJumps() async {
        let r = rig([3, 1])
        let a = r.ex[0], b = r.ex[1]
        await check(r, a.orderedSets[0], in: a)
        await check(r, a.orderedSets[2], in: a)         // set 2 forgotten: no jump yet
        #expect(r.c.advance == nil && !r.c.isCollapsed(a))
        await check(r, a.orderedSets[1], in: a)
        #expect(r.c.isCollapsed(a))
        #expect(target(r) == ref(b, 0))
    }

    // MARK: D-d

    @Test func withTheSettingOffTheHighlightAndAllDoneStay() async {
        let r = rig([1, 1])
        r.c.jumpToNext = { false }
        let a = r.ex[0], b = r.ex[1]
        await check(r, a.orderedSets[0], in: a)
        #expect(r.c.advance == nil && r.c.collapsed.isEmpty)
        #expect(r.c.currentSetID == b.orderedSets[0].id)
        await check(r, b.orderedSets[0], in: b)
        #expect(r.c.advance == nil && r.c.isAllDone)
    }

    // MARK: timing

    @Test func aCollapseWithoutAScrollWaitsForTheNextJump() async {
        let r = rig([1, 3])
        let a = r.ex[0], b = r.ex[1]
        r.c.toggleCheck(a.orderedSets[0], in: a)        // A done…
        await drain()
        r.c.toggleCheck(b.orderedSets[2], in: b)        // …and B3 inside 0.6 s: out of order, the list stays
        await drain()
        r.clock.advance(by: SessionAdvance.delay)
        await drain()
        #expect(r.c.advance == nil)
        #expect(!r.c.isCollapsed(a))                    // no rows moving under the thumb
        await check(r, b.orderedSets[0], in: b)
        #expect(r.c.advance == nil && !r.c.isCollapsed(a))
        await check(r, b.orderedSets[1], in: b)         // B done: everything collapses together with the jump
        guard case let .allDone(collapse)? = r.c.advance?.step else { Issue.record("expected allDone"); return }
        #expect(Set(collapse) == [a.id, b.id])
        #expect(r.c.isCollapsed(a) && r.c.isCollapsed(b))
    }

    @Test func aCarriedCollapseIsDroppedWhenTheSessionStops() async {
        let r = rig([1, 3])
        let a = r.ex[0], b = r.ex[1]
        r.c.toggleCheck(a.orderedSets[0], in: a)
        await drain()
        r.c.toggleCheck(b.orderedSets[2], in: b)
        await drain()
        r.clock.advance(by: SessionAdvance.delay)
        await drain()
        #expect(r.c.carriedCollapse == [a.id])
        r.c.stop()
        #expect(r.c.carriedCollapse.isEmpty)
    }

    // MARK: stale collapses

    /// X is carried, gets a new set, Z finishes, the setting goes off, X's new set is checked: X never collapses at
    /// the tap.
    @Test func aCardWithANewSetLeavesTheCarriedCollapse() async {
        let r = rig([1, 3, 1])
        let x = r.ex[0], b = r.ex[1], z = r.ex[2]
        r.c.toggleCheck(x.orderedSets[0], in: x)
        await drain()
        r.c.toggleCheck(b.orderedSets[2], in: b)        // out of order: the list stays, X is carried
        await drain()
        r.clock.advance(by: SessionAdvance.delay)
        await drain()
        #expect(r.c.carriedCollapse == [x.id])

        let added = r.c.addSet(to: x)
        #expect(r.c.carriedCollapse.isEmpty)
        await check(r, z.orderedSets[0], in: z)          // a jump: X is open again, so not collapsed with it
        #expect(r.c.advance != nil)
        #expect(!r.c.collapsed.contains(x.id))

        r.c.jumpToNext = { false }
        await check(r, added, in: x)
        #expect(!r.c.isCollapsed(x))

        r.c.jumpToNext = { true }                         // only a normal jump collapses it
        let another = r.c.addSet(to: x)
        await check(r, another, in: x)
        #expect(r.c.isCollapsed(x))
    }

    /// A split collapses the old row (a pending check sees it finished); Undo brings its open sets back. Finishing
    /// it later with the setting off doesn't collapse it.
    @Test func anUndoneSplitDoesNotLeaveTheOldRowCollapsed() async {
        let r = rig([4, 1])
        let x = r.ex[0]
        await check(r, x.orderedSets[0], in: x)
        r.c.toggleCheck(x.orderedSets[1], in: x)        // pending while the split happens
        await drain()
        await r.c.replace(x, with: MockTrain.inclineDB)
        r.clock.advance(by: SessionAdvance.delay)
        await drain()
        #expect(r.c.collapsed.contains(x.id))           // finished at fire time: the old row collapses

        r.c.undoReplace()
        #expect(x.orderedSets.filter { !$0.isCompleted }.count == 2)
        #expect(!r.c.collapsed.contains(x.id))

        r.c.jumpToNext = { false }
        await check(r, x.orderedSets[2], in: x)
        await check(r, x.orderedSets[3], in: x)
        #expect(!r.c.isCollapsed(x))
    }

    // MARK: no rest after the last set

    @Test func theLastWorkingSetStartsNoRest() async {
        let r = rig([2])
        let a = r.ex[0]
        r.c.toggleWarmup(a.orderedSets[0])              // an open warm-up doesn't count
        r.c.toggleCheck(a.orderedSets[1], in: a)
        #expect(!r.c.rest.isRunning)
        #expect(r.c.session.restEndsAt == nil)
    }

    @Test func theLastWorkingSetStopsARunningRest() async {
        let r = rig([2])
        let a = r.ex[0]
        r.c.toggleCheck(a.orderedSets[0], in: a)
        #expect(r.c.rest.isRunning)
        r.c.toggleCheck(a.orderedSets[1], in: a)
        #expect(!r.c.rest.isRunning)
        #expect(r.c.session.restEndsAt == nil)
    }

    // MARK: superset rest

    @Test func anOpenWarmUpOfThePartnerDoesNotSkipTheRest() {
        let r = rig([1, 2, 1])                          // the third keeps the session going: a rest is due
        let a = r.ex[0], b = r.ex[1]
        a.supersetGroup = 1
        b.supersetGroup = 1
        r.c.toggleWarmup(b.orderedSets[0])              // B: an open warm-up…
        r.c.toggleCheck(b.orderedSets[1], in: b)        // …and its working set done
        r.c.skipRest()
        r.c.toggleCheck(a.orderedSets[0], in: a)        // A's last set: the round is over
        #expect(r.c.rest.isRunning)
    }

    @Test func anOpenWorkingSetOfThePartnerStillSkipsTheRest() {
        let r = rig([1, 1])
        let a = r.ex[0], b = r.ex[1]
        a.supersetGroup = 1
        b.supersetGroup = 1
        r.c.toggleCheck(a.orderedSets[0], in: a)        // B1 follows straight away
        #expect(!r.c.rest.isRunning)
    }

    @Test func anUncheckCancelsOnlyItsOwnExercise() async {
        let r = rig([1, 2])
        let a = r.ex[0], b = r.ex[1]
        r.c.toggleCheck(a.orderedSets[0], in: a)
        await drain()
        r.c.toggleCheck(b.orderedSets[0], in: b)
        await drain()
        r.c.toggleCheck(b.orderedSets[0], in: b)        // B1 unchecked again
        await drain()
        #expect(r.clock.pendingSleeps == 1)             // A's decision is still due
        r.clock.advance(by: SessionAdvance.delay)
        await drain()
        #expect(r.c.isCollapsed(a))
        #expect(target(r) == ref(b, 0))
    }

    @Test func finishingInsideTheDelayPublishesNothing() async {
        let r = rig([1])
        let a = r.ex[0]
        r.c.toggleCheck(a.orderedSets[0], in: a)
        await drain()
        _ = await r.c.finish()
        #expect(r.clock.pendingSleeps == 0)
        r.clock.advance(by: .seconds(1))
        await drain()
        #expect(r.c.advance == nil && r.c.collapsed.isEmpty)
    }

    @Test func discardingInsideTheDelayPublishesNothing() async {
        let r = rig([1, 1])
        let a = r.ex[0]
        r.c.toggleCheck(a.orderedSets[0], in: a)
        await drain()
        r.c.discard()
        r.clock.advance(by: .seconds(1))
        await drain()
        #expect(r.c.advance == nil)
    }

    // MARK: rest bar text

    @Test func theRestBarsNextLineHasItsOwnKey() {
        #expect(RestBar.nextLine("Bench press · set 1 of 4") == "Next: Bench press · set 1 of 4")
    }
}
