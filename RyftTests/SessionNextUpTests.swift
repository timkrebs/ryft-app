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

    @Test func aSecondCheckInsideTheDelayKeepsTheFirstCollapse() async {
        let r = rig([1, 2])
        let a = r.ex[0], b = r.ex[1]
        r.c.toggleCheck(a.orderedSets[0], in: a)        // A done…
        await drain()
        r.c.toggleCheck(b.orderedSets[0], in: b)        // …and B1 right after, inside 0.6 s
        await drain()
        r.clock.advance(by: SessionAdvance.delay)
        await drain()
        #expect(r.c.isCollapsed(a))
        #expect(!r.c.isCollapsed(b))
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
