import Foundation
import Testing
@testable import Ryft

/// Auto-advance in the Focused layout (L1, architecture.md §2, §4): the planner decides, the view hands `advance` to
/// `follow`, which moves the page. Plus the table helpers (`tableRows`, `nextRow`, `position`, `pageAnnouncement`),
/// `nextLabel` and the lock screen's Next against the active row (S1, N1). The rig is `ReplaceRig` with the page on `Row`.
/// Synthetic values only.
@MainActor
struct SessionFocusedAdvanceTests {
    /// The page is pinned, as the screen does on appear: an unpinned one would follow the first open set by itself.
    private func rig(_ layout: SessionLayout = .focused) -> ReplaceRig {
        let r = ReplaceRig(sessionLayout: layout)
        r.controller.pinPage()
        return r
    }

    private func check(_ set: LocalSet, in ex: LocalSessionExercise, _ r: ReplaceRig) async {
        r.controller.toggleCheck(set, in: ex)
        await r.settle { r.clock.pendingSleeps >= 1 }
    }

    private func release(_ r: ReplaceRig) async {
        r.clock.advance(by: SessionAdvance.delay)
        await r.settle()
    }

    /// What `FocusedSessionView` does with a decision.
    private func perform(_ r: ReplaceRig) {
        if let request = r.controller.advance { r.controller.follow(request) }
    }

    private func warmup(_ index: Int, of ex: LocalSessionExercise, _ r: ReplaceRig) -> LocalSet {
        let set = ex.orderedSets[index]
        set.isWarmup = true
        r.store.save()
        return set
    }

    // MARK: the planner to the page

    @Test func theLastSetOfAnExerciseMovesThePageToTheNextOneAtTheirActiveRow() async throws {
        let r = rig()
        r.complete(2, of: r.row)
        await check(r.row.orderedSets[2], in: r.row, r)
        #expect(r.controller.pageExerciseID == r.row.id, "not before the delay")
        await release(r)
        let request = try #require(r.controller.advance)
        #expect(request.step == .advance(collapse: [r.row.id], to: .init(exerciseID: r.x.id, setID: r.x.orderedSets[0].id)))
        perform(r)
        #expect(r.controller.pageExerciseID == r.x.id && r.session.currentExerciseID == r.x.id)
        #expect(r.controller.activeSet(in: r.x)?.id == r.x.orderedSets[0].id)
    }

    @Test func aMiddleSetDoesNotMoveThePage() async {
        let r = rig()
        await check(r.row.orderedSets[0], in: r.row, r)
        await release(r)
        perform(r)
        #expect(r.controller.pageExerciseID == r.row.id)
    }

    @Test func collapseIsIgnoredInFocused() async throws {
        let r = rig()
        r.complete(2, of: r.row)
        await check(r.row.orderedSets[2], in: r.row, r)
        await release(r)
        let shape = r.layout
        let collapsedBefore = r.controller.collapsed
        // A request that names every exercise to collapse: only `to` counts.
        let to = SessionAdvance.SetRef(exerciseID: r.x.id, setID: r.x.orderedSets[0].id)
        r.controller.follow(AdvanceRequest(id: UUID(), step: .advance(collapse: r.controller.exercises.map(\.id), to: to)))
        #expect(r.controller.pageExerciseID == r.x.id)
        #expect(r.layout == shape && r.controller.collapsed == collapsedBefore, "follow collapses nothing and edits nothing")
        #expect(r.controller.userExpanded.isEmpty)
    }

    @Test func followingAnAdvanceWritesNoUpdatedAtAndQueuesNothing() async {
        let r = rig()
        r.complete(2, of: r.row)
        await check(r.row.orderedSets[2], in: r.row, r)
        await release(r)
        let stamp = r.session.updatedAt, ops = r.store.pendingOps().count
        perform(r)
        #expect(r.session.updatedAt == stamp && r.store.pendingOps().count == ops)
    }

    @Test func aSupersetFlipsThePageAfterEverySet() async {
        let r = rig()
        await check(r.x.orderedSets[0], in: r.x, r)
        await release(r)
        perform(r)
        #expect(r.controller.pageExerciseID == r.lateral.id, "A1 to B1")
        await check(r.lateral.orderedSets[0], in: r.lateral, r)
        await release(r)
        perform(r)
        #expect(r.controller.pageExerciseID == r.x.id, "B1 to A2")
        #expect(r.controller.activeSet(in: r.x)?.id == r.x.orderedSets[1].id)
        #expect(r.controller.lastManualScroll == nil, "the planner's moves never stamp the window")
    }

    @Test func allSetsDoneStaysOnThePage() async throws {
        let r = rig()
        for ex in [r.row, r.x, r.lateral] { r.complete(ex.sets.count, of: ex) }
        r.complete(2, of: r.curl)
        r.controller.jump(to: r.curl.id)
        r.clock.advance(by: .seconds(5))
        await check(r.curl.orderedSets[2], in: r.curl, r)
        await release(r)
        let request = try #require(r.controller.advance)
        guard case .allDone = request.step else { Issue.record("expected allDone, got \(request.step)"); return }
        perform(r)
        #expect(r.controller.pageExerciseID == r.curl.id)
        #expect(r.controller.isAllDone)
        #expect(r.controller.activeSet(in: r.curl) == nil)
    }

    @Test func aRowThatWentBeforeTheViewFollowedIsIgnored() async throws {
        let r = rig()
        r.complete(2, of: r.row)
        await check(r.row.orderedSets[2], in: r.row, r)
        await release(r)
        let request = try #require(r.controller.advance)
        r.controller.remove(r.x)
        r.controller.follow(request)
        #expect(r.controller.pageExerciseID != r.x.id && !r.controller.exercises.contains { $0.id == r.x.id })
        #expect(r.session.currentExerciseID != r.x.id)
    }

    @Test func aCheckWithTheKeypadOpenOnItStillAdvancesBecauseTheCheckClosesIt() async throws {
        let r = rig()
        r.complete(2, of: r.row)
        let last = r.row.orderedSets[2]
        r.controller.edit(last, .reps)
        await check(last, in: r.row, r)
        #expect(r.controller.focus == nil)
        await release(r)
        #expect(r.controller.advance != nil)
    }

    @Test func aKeypadOpenElsewhereHoldsTheAdvance() async {
        let r = rig()
        r.complete(2, of: r.row)
        r.controller.edit(r.curl.orderedSets[0], .kg)
        // The check closes the keypad in Focused, so this reopens it inside the delay.
        await check(r.row.orderedSets[2], in: r.row, r)
        r.controller.edit(r.curl.orderedSets[0], .kg)
        await release(r)
        #expect(r.controller.advance == nil, "the planner stays with a keypad open")
    }

    @Test func theSettingOffKeepsThePageWhereItIs() async {
        let r = rig()
        r.controller.jumpToNext = { false }
        r.complete(2, of: r.row)
        await check(r.row.orderedSets[2], in: r.row, r)
        await release(r)
        #expect(r.controller.advance == nil && r.controller.pageExerciseID == r.row.id)
    }

    // MARK: the 3 s window

    @Test func aSwipeStillHoldsTheAdvanceAtTwoPointSixSecondsAndNotAtThreePointOne() async {
        let r = rig()
        r.complete(2, of: r.row)
        r.controller.jump(to: r.curl.id)
        r.clock.advance(by: .seconds(2))
        await check(r.row.orderedSets[2], in: r.row, r)
        await release(r)
        #expect(r.controller.advance == nil, "the decision falls at 2.6 s")

        let r2 = rig()
        r2.complete(2, of: r2.row)
        r2.controller.jump(to: r2.curl.id)
        r2.clock.advance(by: .milliseconds(2_500))
        await check(r2.row.orderedSets[2], in: r2.row, r2)
        await release(r2)
        #expect(r2.controller.advance != nil, "the decision falls at 3.1 s")
    }

    /// N1: a tap during the 0.6 s delay isn't lost to a superset flip.
    @Test func aTapDuringTheDelayHoldsTheFlip() async {
        let r = rig()
        r.session.currentExerciseID = r.x.id   // written, not jumped to: a jump would stamp the window itself
        r.store.save()
        await check(r.x.orderedSets[0], in: r.x, r)
        r.clock.advance(by: .milliseconds(200))
        r.controller.activate(r.x.orderedSets[3])
        #expect(r.controller.lastManualScroll == r.clock.now())
        await release(r)
        #expect(r.controller.advance == nil, "the page stays where the finger is")
        #expect(r.controller.pageExerciseID == r.x.id)
        #expect(r.controller.activeSet(in: r.x)?.id == r.x.orderedSets[3].id)
    }

    @Test func activateInFocusedStampsTheWindowAndTheListDoesNot() {
        let r = rig()
        r.controller.activate(r.row.orderedSets[1])
        #expect(r.controller.lastManualScroll == r.clock.now())
        let l = rig(.list)
        l.controller.activate(l.row.orderedSets[1])
        #expect(l.controller.lastManualScroll == nil && l.controller.tappedSet == nil)
    }

    @Test func activatingADoneSetDoesNothing() {
        let r = rig()
        r.complete(1, of: r.row)
        r.controller.activate(r.row.orderedSets[0])
        #expect(r.controller.lastManualScroll == nil && r.controller.tappedSet == nil)
    }

    // MARK: tableRows, nextRow, position, pageAnnouncement

    @Test func foldedRowsAreTheWorkingSetsAndOpenRowsPutTheWarmUpsFirst() {
        let r = rig()
        r.controller.addWarmup(to: r.row)                 // highest setIndex, shown first
        let added = r.row.orderedSets.last!
        r.controller.setWarmups(expanded: false, for: r.row)
        #expect(!r.controller.tableRows(of: r.row).contains { $0.id == added.id }, "folded: not in the table")
        r.controller.setWarmups(expanded: true, for: r.row)
        let rows = r.controller.tableRows(of: r.row)
        #expect(rows.first?.id == added.id && rows.count == 4)
        #expect(rows.dropFirst().map(\.id) == r.row.orderedSets.dropLast().map(\.id))
    }

    @Test func nextRowGoesDownTheTableAndNeverUp() {
        let r = rig()
        r.controller.addWarmup(to: r.row)
        let warm = r.row.orderedSets.last!
        let working = r.row.orderedSets.filter { !$0.isWarmup }
        let c = r.controller
        #expect(c.nextRow(after: warm, in: r.row)?.id == working[0].id, "warm-up, then the first working set")
        #expect(c.nextRow(after: working[0], in: r.row)?.id == working[1].id)
        #expect(c.nextRow(after: working[2], in: r.row) == nil, "never upward to the warm-up that has the highest index")
    }

    @Test func nextRowSkipsAFoldedWarmUpAndAReadOnlyRow() {
        let r = rig()
        let plank = r.controller.add(MockTrain.plank)
        plank.orderedSets[1].durationSec = 40
        let c = r.controller
        #expect(c.nextRow(after: plank.orderedSets[0], in: plank)?.id == plank.orderedSets[2].id, "a stored time has no reps to go to")
        _ = warmup(0, of: r.row, r)
        #expect(c.nextRow(after: r.row.orderedSets[1], in: r.row)?.id == r.row.orderedSets[2].id)
        #expect(c.nextRow(after: r.row.orderedSets[0], in: r.row) == nil, "a folded warm-up isn't in the table")
    }

    @Test func nextFieldWalksFromKgToRepsToTheNextRowAndStopsAtTheEnd() {
        let r = rig()
        let c = r.controller
        c.edit(r.row.orderedSets[0], .kg)
        c.nextField()
        #expect(c.focus == SetFocus(setID: r.row.orderedSets[0].id, field: .reps))
        c.nextField()
        #expect(c.focus == SetFocus(setID: r.row.orderedSets[1].id, field: .kg))
    }

    @Test func warmUpsAndWorkingSetsAreNumberedSeparately() {
        let r = rig()
        let w1 = warmup(0, of: r.row, r)
        let w2 = warmup(1, of: r.row, r)
        let c = r.controller
        #expect(c.position(of: w1, in: r.row) == (1, 2, true))
        #expect(c.position(of: w2, in: r.row) == (2, 2, true))
        #expect(c.position(of: r.row.orderedSets[2], in: r.row) == (1, 1, false))
    }

    @Test func thePageAnnouncementNamesTheActiveRow() {
        let r = rig()
        let c = r.controller
        let plain = c.pageAnnouncement(of: r.x)
        #expect(plain?.contains(r.x.name) == true && plain?.contains("set 1 of 4") == true, "\(plain ?? "nil")")
        _ = warmup(0, of: r.row, r)
        #expect(c.pageAnnouncement(of: r.row)?.contains("set 1 of 2") == true, "folded: the warm-up isn't counted")
        c.setWarmups(expanded: true, for: r.row)
        #expect(c.pageAnnouncement(of: r.row)?.contains("warm-up 1 of 1") == true)
        c.activate(r.x.orderedSets[2])
        #expect(c.pageAnnouncement(of: r.x)?.contains("set 3 of 4") == true, "a tap moves it")
    }

    @Test func thePageAnnouncementIsNilWithNoOpenRow() {
        let r = rig()
        r.complete(3, of: r.row)
        #expect(r.controller.pageAnnouncement(of: r.row) == nil)
    }

    // MARK: nextLabel

    @Test func nextNumbersWorkingSetsFromOneAndNamesAnOpenWarmUp() {
        let r = rig()
        let c = r.controller
        _ = warmup(0, of: r.row, r)
        #expect(c.nextLabel().contains("\(r.row.name) · set 1 of 2"), "\(c.nextLabel())")
        c.setWarmups(expanded: true, for: r.row)
        #expect(c.nextLabel().contains("warm-up 1 of 1"), "\(c.nextLabel())")
    }

    @Test func nextNamesTheTappedRow() {
        let r = rig()
        r.controller.activate(r.row.orderedSets[2])
        #expect(r.controller.nextLabel().contains("set 3 of 3"), "\(r.controller.nextLabel())")
    }

    @Test func nextNamesAStoredTimeRowByItsValueInFocusedOnly() {
        let r = rig()
        let plank = r.controller.add(MockTrain.plank)
        plank.orderedSets[0].durationSec = 45
        r.complete(3, of: r.row)
        for ex in [r.x, r.lateral, r.curl] { r.complete(ex.sets.count, of: ex) }
        r.controller.jump(to: plank.id)
        #expect(r.controller.nextLabel().contains("0:45"), "\(r.controller.nextLabel())")

        let l = rig(.list)
        let lplank = l.controller.add(MockTrain.plank)
        lplank.orderedSets[0].durationSec = 45
        for ex in [l.row, l.x, l.lateral, l.curl] { l.complete(ex.sets.count, of: ex) }
        #expect(!l.controller.nextLabel().contains("0:45"), "List never showed it")
    }

    @Test func listsNextLabelCountsEverySetAndOffersTheWarmUpFirst() {
        let r = rig(.list)
        _ = warmup(0, of: r.row, r)
        #expect(r.controller.nextLabel().contains("set 1 of 3"), "\(r.controller.nextLabel())")
        #expect(r.controller.nextUp?.set.id == r.row.orderedSets[0].id)
    }

    // MARK: S1, the lock screen's Next against lastActivityNext

    @Test func activateKeepsTheLockScreenWhereTheRowIs() {
        let r = rig()
        let c = r.controller
        let before = c.lastActivityNext
        c.activate(r.row.orderedSets[2])
        #expect(c.nextLabel() != before)
        #expect(c.lastActivityNext == c.nextLabel())
    }

    @Test func aPageChangeKeepsTheLockScreenWhereThePageIs() {
        let r = rig()
        let c = r.controller
        let before = c.lastActivityNext
        c.jump(to: r.curl.id)
        #expect(c.nextLabel() != before, "no check yet: Next follows the page")
        #expect(c.lastActivityNext == c.nextLabel())
    }

    @Test func theKeypadMovingBetweenRowsKeepsTheLockScreenWhereTheKeypadIs() {
        let r = rig()
        let c = r.controller
        c.edit(r.row.orderedSets[1], .kg)
        #expect(c.lastActivityNext == c.nextLabel() && c.nextLabel().contains("set 2 of 3"))
        c.edit(r.row.orderedSets[2], .reps)
        #expect(c.lastActivityNext == c.nextLabel() && c.nextLabel().contains("set 3 of 3"))
    }

    @Test func nextFieldOffTheEndKeepsTheLockScreenInStep() {
        let r = rig()
        let c = r.controller
        c.edit(r.row.orderedSets[2], .reps)
        c.nextField()
        #expect(c.focus == nil && c.nextLabel().contains("set 1 of 3"))
        #expect(c.lastActivityNext == c.nextLabel())
    }
}
