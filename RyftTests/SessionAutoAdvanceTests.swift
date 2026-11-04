import Foundation
import Testing
@testable import Ryft

/// The controller side of "Jump to next exercise": the 0.6 s delay runs on the injected clock,
/// the decision is made from the live state afterwards.
@MainActor
struct SessionAutoAdvanceTests {
    private struct Rig {
        let c: SessionController
        let clock: TestClock
        let a: LocalSessionExercise
        let b: LocalSessionExercise
        var aSets: [LocalSet] { a.orderedSets }
        var bSets: [LocalSet] { b.orderedSets }
    }

    private func rig(aSets: Int = 2, bSets: Int = 2, superset: Bool = false) throws -> Rig {
        let store = TrainStore(inMemory: true)
        let sync = TrainSyncService(store: store, remote: { MockPlatformAPI() }, monitorsNetwork: false)
        sync.gate = { _ in nil }
        let s = SessionFactory.empty(in: store)
        let a = SessionFactory.add(MockTrain.bench, to: s, sets: aSets, in: store)
        let b = SessionFactory.add(MockTrain.squat, to: s, sets: bSets, in: store)
        if superset { a.supersetGroup = 1; b.supersetGroup = 1 }
        let clock = TestClock()
        let c = SessionController(session: s, sync: sync, liveActivity: nil, clock: clock)
        return Rig(c: c, clock: clock, a: a, b: b)
    }

    /// Lets the scheduled task reach its sleep on the test clock.
    private func settle(_ clock: TestClock, sleeping n: Int = 1) async {
        for _ in 0..<200 where clock.pendingSleeps < n { await Task.yield() }
    }

    /// Lets a task that was just released finish its work.
    private func drain() async { for _ in 0..<50 { await Task.yield() } }

    private func check(_ r: Rig, _ set: LocalSet, in ex: LocalSessionExercise) async {
        r.c.toggleCheck(set, in: ex)
        await settle(r.clock)
    }

    private func release(_ r: Rig) async {
        r.clock.advance(by: SessionAdvance.delay)
        await drain()
    }

    // MARK: the happy path and the delay

    @Test func checkingTheLastSetCollapsesAndTargetsTheNextOpenSet() async throws {
        let r = try rig()
        r.c.toggleCheck(r.aSets[0], in: r.a)
        await drain()
        await check(r, r.aSets[1], in: r.a)
        await release(r)
        #expect(r.c.isCollapsed(r.a))
        #expect(r.c.collapsed.contains(r.a.id))
        let adv = try #require(r.c.advance)
        guard case let .advance(collapse, to) = adv.step else { Issue.record("expected advance, got \(adv.step)"); return }
        #expect(collapse == [r.a.id])
        #expect(to == SessionAdvance.SetRef(exerciseID: r.b.id, setID: r.bSets[0].id))
        #expect(!r.c.isCollapsed(r.b))
    }

    @Test func nothingHappensBeforeTheDelayAndItHappensAtIt() async throws {
        let r = try rig(aSets: 1)
        await check(r, r.aSets[0], in: r.a)
        r.clock.advance(by: .milliseconds(599))
        await drain()
        #expect(r.c.advance == nil && !r.c.isCollapsed(r.a))
        r.clock.advance(by: .milliseconds(1))
        await drain()
        #expect(r.c.advance != nil && r.c.isCollapsed(r.a))
    }

    @Test func aMiddleSetNeverCollapsesOrScrolls() async throws {
        let r = try rig(aSets: 3)
        await check(r, r.aSets[0], in: r.a)
        await release(r)
        #expect(r.c.advance == nil || r.c.advance?.step == .stay)
        #expect(!r.c.isCollapsed(r.a))
    }

    // MARK: supersets

    @Test func aSupersetAlternatesAndCollapsesOnlyWhenTheGroupIsDone() async throws {
        let r = try rig(superset: true)
        // A1 -> B1
        await check(r, r.aSets[0], in: r.a)
        await release(r)
        var adv = try #require(r.c.advance)
        #expect(adv.step == .advance(collapse: [], to: .init(exerciseID: r.b.id, setID: r.bSets[0].id)))
        // B1 -> A2
        await check(r, r.bSets[0], in: r.b)
        await release(r)
        adv = try #require(r.c.advance)
        #expect(adv.step == .advance(collapse: [], to: .init(exerciseID: r.a.id, setID: r.aSets[1].id)))
        #expect(!r.c.isCollapsed(r.a) && !r.c.isCollapsed(r.b))
        // A2 -> B2, then B2 finishes the group.
        await check(r, r.aSets[1], in: r.a)
        await release(r)
        #expect(!r.c.isCollapsed(r.a))
        await check(r, r.bSets[1], in: r.b)
        await release(r)
        #expect(r.c.isCollapsed(r.a) && r.c.isCollapsed(r.b))
    }

    // MARK: suppression

    @Test func aCheckOutOfOrderDoesNotAdvance() async throws {
        let r = try rig(aSets: 3)
        await check(r, r.aSets[2], in: r.a)
        await release(r)
        await check(r, r.aSets[0], in: r.a)
        let before = r.c.advance?.id
        await release(r)
        #expect(r.c.advance?.id == before)
        #expect(!r.c.isCollapsed(r.a))
    }

    @Test func aScrollInsideTheDelaySuppresses() async throws {
        let r = try rig(aSets: 1)
        await check(r, r.aSets[0], in: r.a)
        r.c.userScrolled()
        await release(r)
        #expect(r.c.advance == nil && !r.c.isCollapsed(r.a))
    }

    @Test func aScrollWithinThreeSecondsBeforeTheCheckSuppressesButThreeLaterDoesNot() async throws {
        let r = try rig(aSets: 1, bSets: 3)
        r.c.userScrolled()
        r.clock.advance(by: .milliseconds(2300))        // 2.3 s + 0.6 s delay = 2.9 s
        await check(r, r.aSets[0], in: r.a)
        await release(r)
        #expect(r.c.advance == nil)
        // A second exercise: scroll, wait 3.1 s in total before the decision.
        let r2 = try rig(aSets: 1)
        r2.c.userScrolled()
        r2.clock.advance(by: .milliseconds(2500))       // 2.5 s + 0.6 s = 3.1 s
        await check(r2, r2.aSets[0], in: r2.a)
        await release(r2)
        #expect(r2.c.advance != nil)
    }

    @Test func anOpenKeypadSuppresses() async throws {
        let r = try rig(aSets: 1)
        await check(r, r.aSets[0], in: r.a)
        r.c.edit(r.bSets[0], .kg)                        // opened during the delay
        await release(r)
        #expect(r.c.advance == nil && !r.c.isCollapsed(r.a))
    }

    @Test func theSettingOffDoesNothing() async throws {
        let r = try rig(aSets: 1)
        r.c.jumpToNext = { false }
        r.c.toggleCheck(r.aSets[0], in: r.a)
        await drain()
        r.clock.advance(by: .seconds(5))
        await drain()
        #expect(r.c.advance == nil && r.c.collapsed.isEmpty && !r.c.isCollapsed(r.a))
    }

    // MARK: undo and expand

    @Test func anUncheckInsideTheDelayCancelsIt() async throws {
        let r = try rig(aSets: 1)
        await check(r, r.aSets[0], in: r.a)
        r.c.toggleCheck(r.aSets[0], in: r.a)             // uncheck
        await drain()
        #expect(r.clock.pendingSleeps == 0)
        r.clock.advance(by: .seconds(1))
        await drain()
        #expect(r.c.advance == nil && !r.c.isCollapsed(r.a))
    }

    @Test func uncheckingASetOnACollapsedExerciseExpandsIt() async throws {
        let r = try rig(aSets: 1)
        await check(r, r.aSets[0], in: r.a)
        await release(r)
        #expect(r.c.isCollapsed(r.a))
        r.c.toggleCheck(r.aSets[0], in: r.a)
        #expect(!r.c.isCollapsed(r.a))
        #expect(!r.c.collapsed.contains(r.a.id))
    }

    @Test func aCollapsedCardWithAnOpenSetIsNeverShownCollapsed() async throws {
        let r = try rig(aSets: 1)
        await check(r, r.aSets[0], in: r.a)
        await release(r)
        #expect(r.c.isCollapsed(r.a))
        r.c.addSet(to: r.a)                              // a new open set (or an undo) must show the card
        #expect(!r.c.isCollapsed(r.a))
    }

    @Test func aCardTheUserExpandedStaysOpenOnTheNextFinish() async throws {
        let r = try rig(aSets: 1)
        await check(r, r.aSets[0], in: r.a)
        await release(r)
        r.c.expand(r.a)
        #expect(!r.c.isCollapsed(r.a))
        r.c.toggleCheck(r.aSets[0], in: r.a)             // uncheck
        await check(r, r.aSets[0], in: r.a)              // check again
        await release(r)
        #expect(!r.c.isCollapsed(r.a))
    }

    // MARK: all done

    @Test func checkingTheVeryLastSetEndsInAllDone() async throws {
        let r = try rig(aSets: 1, bSets: 1)
        await check(r, r.aSets[0], in: r.a)
        await release(r)
        await check(r, r.bSets[0], in: r.b)
        await release(r)
        #expect(r.c.nextUp == nil)                       // the view derives the finish row from this
        let adv = try #require(r.c.advance)
        guard case let .allDone(collapse) = adv.step else { Issue.record("expected allDone, got \(adv.step)"); return }
        #expect(Set(collapse) == [r.a.id, r.b.id] || collapse == [r.b.id])
        #expect(r.c.isCollapsed(r.b))
    }
}
