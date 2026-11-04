import Foundation
import Testing
@testable import Ryft

/// The Focused layout's active row (L6, architecture.md §3), ✓ on it (L17, L23) and the fixes of the T2 review (S2, N2,
/// N3, N4, S4). The rig is `ReplaceRig`: `Row` (0, 3 sets, no target) · `Bench` (1, superset 1, 4 sets, a target and last
/// time: every row prefilled) · `Lateral` (2, superset 1) · `Curl` (3). Synthetic values only.
@MainActor
struct SessionActiveSetTests {
    private func rig(_ layout: SessionLayout = .focused) -> ReplaceRig { ReplaceRig(sessionLayout: layout) }

    private func active(_ ex: LocalSessionExercise, _ r: ReplaceRig) -> UUID? { r.controller.activeSet(in: ex)?.id }

    /// A warm-up is a set flagged by the user: `setIndex` order stays.
    private func warmup(_ index: Int, of ex: LocalSessionExercise, _ r: ReplaceRig) -> LocalSet {
        let set = ex.orderedSets[index]
        set.isWarmup = true
        r.store.save()
        return set
    }

    /// Exactly one active row, and it is one of the rows on screen, open; none when the table has no open row.
    private func assertOneActive(_ ex: LocalSessionExercise, _ r: ReplaceRig, _ note: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
        let c = r.controller
        let open = c.tableRows(of: ex).filter { !$0.isCompleted }
        let rows = c.tableRows(of: ex).filter { c.activeSet(in: ex)?.id == $0.id }
        if open.isEmpty {
            #expect(c.activeSet(in: ex) == nil, "no open row, no active one. \(note)", sourceLocation: sourceLocation)
        } else {
            #expect(rows.count == 1 && rows[0].isCompleted == false, "one active row among \(open.count) open. \(note)",
                    sourceLocation: sourceLocation)
        }
    }

    // MARK: L6, in order

    @Test func theFirstOpenWorkingSetIsActiveAndFollowsEachCheck() {
        let r = rig()
        let sets = r.row.orderedSets
        #expect(active(r.row, r) == sets[0].id)
        r.controller.toggleCheck(sets[0], in: r.row)
        #expect(active(r.row, r) == sets[1].id)
        r.controller.toggleCheck(sets[1], in: r.row)
        #expect(active(r.row, r) == sets[2].id)
        r.controller.toggleCheck(sets[2], in: r.row)
        #expect(active(r.row, r) == nil, "every set done: no active row")
        assertOneActive(r.row, r)
    }

    @Test func aTappedOpenSetIsActiveAndNoSetChanges() {
        let r = rig()
        let shape = RowShape(r.row)
        r.controller.activate(r.row.orderedSets[2])
        #expect(active(r.row, r) == r.row.orderedSets[2].id)
        #expect(RowShape(r.row) == shape, "tapping an upcoming row edits nothing")
        assertOneActive(r.row, r)
    }

    @Test func aTappedDoneSetIsNotActive() {
        let r = rig()
        r.complete(1, of: r.row)
        r.controller.activate(r.row.orderedSets[0])
        #expect(r.controller.tappedSet == nil && active(r.row, r) == r.row.orderedSets[1].id)
    }

    @Test func anOpenWarmUpIsActiveOnlyWhileTheGroupIsOpen() {
        let r = rig()
        let w = warmup(0, of: r.row, r)
        #expect(active(r.row, r) == r.row.orderedSets[1].id, "folded: the first working set")
        r.controller.setWarmups(expanded: true, for: r.row)
        #expect(active(r.row, r) == w.id, "open: the first open warm-up")
        assertOneActive(r.row, r)
    }

    @Test func aTappedWorkingSetBeatsAnOpenWarmUp() {
        let r = rig()
        _ = warmup(0, of: r.row, r)
        r.controller.setWarmups(expanded: true, for: r.row)
        r.controller.activate(r.row.orderedSets[2])
        #expect(active(r.row, r) == r.row.orderedSets[2].id)
    }

    @Test func foldingTheGroupMovesTheActiveRowAndChangesNoSet() {
        let r = rig()
        let w = warmup(0, of: r.row, r)
        r.controller.setWarmups(expanded: true, for: r.row)
        r.controller.activate(w)
        let shape = RowShape(r.row)
        r.controller.setWarmups(expanded: false, for: r.row)
        #expect(r.controller.tappedSet == nil, "a tapped warm-up isn't active once hidden")
        #expect(active(r.row, r) == r.row.orderedSets[1].id)
        #expect(RowShape(r.row) == shape)
        assertOneActive(r.row, r)
    }

    @Test func aWarmUpAddedFromTheMenuIsActiveInItsOpenGroup() {
        let r = rig()
        r.controller.addWarmup(to: r.row)
        let added = r.row.orderedSets.last
        #expect(added?.isWarmup == true && active(r.row, r) == added?.id)
        #expect(r.controller.tableRows(of: r.row).first?.id == added?.id, "the group sits above the table, not at its setIndex")
    }

    // MARK: check, uncheck, delete

    @Test func aCheckClearsTheTap() {
        let r = rig()
        r.controller.activate(r.row.orderedSets[2])
        r.controller.toggleCheck(r.row.orderedSets[2], in: r.row)
        #expect(r.controller.tappedSet == nil)
        #expect(active(r.row, r) == r.row.orderedSets[0].id, "the first open row again")
    }

    @Test func unCheckingASetMakesItActive() {
        let r = rig()
        r.complete(2, of: r.row)
        #expect(active(r.row, r) == r.row.orderedSets[2].id)
        r.controller.toggleCheck(r.row.orderedSets[0], in: r.row)
        #expect(active(r.row, r) == r.row.orderedSets[0].id, "whatever its position")
        assertOneActive(r.row, r)
    }

    /// S2: a keypad on another row would type into a row that isn't active.
    @Test func unCheckingASetClosesTheKeypadOnAnotherRow() throws {
        let r = rig()
        r.complete(1, of: r.row)
        let other = r.row.orderedSets[2]
        r.controller.edit(other, .kg)
        r.controller.toggleCheck(r.row.orderedSets[0], in: r.row)
        #expect(r.controller.focus == nil, "digits would go to a row that isn't active")
        #expect(r.controller.tappedSet == r.row.orderedSets[0].id)
    }

    @Test func unCheckingTheSetUnderTheKeypadKeepsTheKeypad() {
        let r = rig()
        r.complete(1, of: r.row)
        let set = r.row.orderedSets[0]
        r.controller.edit(set, .kg)
        r.controller.toggleCheck(set, in: r.row)
        #expect(r.controller.focus == SetFocus(setID: set.id, field: .kg))
    }

    @Test func deletingTheActiveRowMakesTheNextOneActive() {
        let r = rig()
        r.controller.delete(r.row.orderedSets[0], from: r.row)
        #expect(active(r.row, r) == r.row.orderedSets[0].id && r.row.sets.count == 2)
        assertOneActive(r.row, r)
    }

    @Test func deletingTheTappedRowFallsBackToTheFirstOpenOne() {
        let r = rig()
        let tapped = r.row.orderedSets[2]
        r.controller.activate(tapped)
        r.controller.delete(tapped, from: r.row)
        #expect(active(r.row, r) == r.row.orderedSets[0].id)
        assertOneActive(r.row, r)
    }

    @Test func aServerCopyThatCompletesTheActiveRowMovesOn() {
        let r = rig()
        r.row.orderedSets[0].completedAt = .now
        r.store.save()
        #expect(active(r.row, r) == r.row.orderedSets[1].id)
    }

    // MARK: reorder, replace, undo, rebuild

    @Test func reorderingChangesNoExercisesActiveRow() {
        let r = rig()
        r.controller.activate(r.row.orderedSets[2])
        let before = [r.row, r.x, r.lateral, r.curl].map { active($0, r) }
        r.controller.move(from: IndexSet(integer: 0), to: 4)
        #expect([r.row, r.x, r.lateral, r.curl].map { active($0, r) } == before)
        for ex in r.controller.exercises { assertOneActive(ex, r) }
    }

    /// N2: the new exercise starts on its first open set, not on the old one's tap.
    @Test func aReplaceInPlaceForgetsTheTap() async {
        let r = rig()
        r.controller.jump(to: r.x.id)
        r.controller.activate(r.x.orderedSets[2])
        await r.controller.replaceExercise(r.x, with: r.incline)
        #expect(r.controller.tappedSet == nil)
        #expect(active(r.x, r) == r.x.orderedSets[0].id)
        assertOneActive(r.x, r)
    }

    @Test func aSplitLeavesOneActiveRowOnEachSide() async {
        let r = rig()
        r.controller.jump(to: r.x.id)
        r.complete(2, of: r.x)
        await r.controller.replaceExercise(r.x, with: r.incline)
        let y = r.session.orderedExercises[2]
        #expect(active(r.x, r) == r.x.orderedSets.first { !$0.isCompleted }?.id, "x keeps its open rows: none after the split")
        #expect(r.x.sets.allSatisfy(\.isCompleted) && active(r.x, r) == nil)
        #expect(active(y, r) == y.orderedSets[0].id)
        assertOneActive(y, r)
    }

    @Test func undoOfASplitGivesTheRestoredRowOneActiveRow() async {
        let r = rig()
        r.controller.jump(to: r.x.id)
        r.complete(2, of: r.x)
        await r.controller.replaceExercise(r.x, with: r.incline)
        r.controller.undoReplace()
        #expect(active(r.x, r) == r.x.orderedSets[2].id, "the first open set that came back")
        assertOneActive(r.x, r)
        #expect(r.controller.exercises.count == 4)
    }

    @Test func aSupersetPartnersActiveRowIsItsOwn() {
        let r = rig()
        r.controller.toggleCheck(r.x.orderedSets[0], in: r.x)
        #expect(active(r.lateral, r) == r.lateral.orderedSets[0].id, "checking Bench doesn't touch its partner")
        #expect(active(r.x, r) == r.x.orderedSets[1].id)
        assertOneActive(r.lateral, r)
    }

    @Test func aRebuiltControllerStartsOnTheFirstOpenRowWithTheGroupFolded() {
        let r = rig()
        _ = warmup(0, of: r.row, r)
        r.controller.setWarmups(expanded: true, for: r.row)
        r.controller.activate(r.row.orderedSets[2])
        let rebuilt = SessionController(session: r.session, sync: r.sync, liveActivity: nil, clock: r.clock,
                                        library: r.library, layout: .focused)
        defer { rebuilt.stop() }
        #expect(rebuilt.tappedSet == nil && rebuilt.expandedWarmups.isEmpty)
        #expect(rebuilt.activeSet(in: r.row)?.id == r.row.orderedSets[1].id)
    }

    // MARK: S4, the auto-fold event

    @Test func theGroupFoldsItselfWhenItsLastWarmUpIsCheckedAndSaysSo() {
        let r = rig()
        _ = warmup(0, of: r.row, r)
        let second = warmup(1, of: r.row, r)
        r.controller.setWarmups(expanded: true, for: r.row)
        r.controller.toggleCheck(r.row.orderedSets[0], in: r.row)
        #expect(r.controller.autoFold == nil, "one warm-up is left")
        #expect(r.controller.expandedWarmups.contains(r.row.id))
        r.controller.toggleCheck(second, in: r.row)
        #expect(r.controller.autoFold?.exerciseID == r.row.id)
        #expect(r.controller.isFolded(r.row))
        #expect(active(r.row, r) == r.row.orderedSets[2].id, "the active row left the table with the group: the first working set")
    }

    @Test func eachAutoFoldIsANewEvent() {
        let r = rig()
        let w = warmup(0, of: r.row, r)
        r.controller.setWarmups(expanded: true, for: r.row)
        r.controller.toggleCheck(w, in: r.row)
        let first = r.controller.autoFold
        #expect(first != nil)
        r.controller.setWarmups(expanded: true, for: r.row)
        r.controller.toggleCheck(w, in: r.row)   // uncheck
        r.controller.toggleCheck(w, in: r.row)   // check again: last warm-up
        #expect(r.controller.autoFold != nil && r.controller.autoFold != first, "a new id per fold")
    }

    @Test func foldingFromThePillIsNoAutoFold() {
        let r = rig()
        _ = warmup(0, of: r.row, r)
        r.controller.setWarmups(expanded: true, for: r.row)
        r.controller.setWarmups(expanded: false, for: r.row)
        #expect(r.controller.autoFold == nil, "the pill stays under the user's finger")
    }

    // MARK: N3

    @Test func nextOffTheEndOfTheTableMakesTheFirstOpenRowActiveAgain() {
        let r = rig()
        let last = r.row.orderedSets[2]
        r.controller.edit(last, .reps)
        #expect(active(r.row, r) == last.id, "the active row follows the keypad")
        r.controller.nextField()
        #expect(r.controller.focus == nil && r.controller.tappedSet == nil)
        #expect(active(r.row, r) == r.row.orderedSets[0].id)
    }

    // MARK: N4

    @Test func removingTheLastCheckedExerciseForgetsIt() {
        let r = rig()
        r.controller.toggleCheck(r.x.orderedSets[0], in: r.x)
        #expect(r.controller.lastCheckedExercise == r.x.id)
        r.controller.jump(to: r.curl.id)
        r.controller.remove(r.x)
        #expect(r.controller.lastCheckedExercise == nil)
        #expect(r.controller.nextUp?.exercise.id == r.curl.id, "Next falls back to the page, not to the top")
    }

    @Test func removingAnotherExerciseKeepsTheLastChecked() {
        let r = rig()
        r.controller.toggleCheck(r.x.orderedSets[0], in: r.x)
        r.controller.remove(r.curl)
        #expect(r.controller.lastCheckedExercise == r.x.id)
    }

    @Test func undoOfASplitForgetsTheRowItRemoves() async {
        let r = rig()
        r.complete(2, of: r.x)
        await r.controller.replaceExercise(r.x, with: r.incline)
        let y = r.session.orderedExercises[2]
        r.controller.lastCheckedExercise = y.id   // as if its first set had been the last check
        r.controller.undoReplace()
        #expect(r.controller.lastCheckedExercise == nil)
    }

    // MARK: L17, ✓ on the active row

    /// L24: the reason for L17 holds on any open row, not only the active one.
    @Test func anEmptyUpcomingRowOpensTheKeypadTooAndLogsNothing() {
        let r = rig()
        let set = r.row.orderedSets[1]
        #expect(r.controller.activeSet(in: r.row)?.id != set.id)
        r.controller.checkRow(set, in: r.row)
        #expect(!set.isCompleted)
        #expect(r.controller.focus == SetFocus(setID: set.id, field: .kg))
    }

    @Test func anEmptyRowWithoutAGhostOpensTheKeypadOnKgAndLogsNothing() throws {
        let r = rig()
        let set = r.row.orderedSets[0]
        let before = r.controller.setsChecked
        r.controller.checkRow(set, in: r.row)
        #expect(!set.isCompleted && r.controller.setsChecked == before)
        #expect(r.controller.focus == SetFocus(setID: set.id, field: .kg))
        #expect(r.controller.emptyCheck?.setID == set.id)
        #expect(r.controller.tappedSet == set.id)
    }

    @Test func anEmptyBodyweightRowOpensRepsNotKg() throws {
        let r = rig()
        let dip = r.controller.add(r.other)
        r.store.save()
        #expect(dip.loadType == .bodyweight)
        let set = dip.orderedSets[0]
        r.controller.checkRow(set, in: dip)
        #expect(r.controller.focus == SetFocus(setID: set.id, field: .reps), "its added load is optional")
        #expect(!set.isCompleted)
    }

    @Test func aRowWithAnyValueOrGhostLogsInOneTap() {
        let r = rig()
        // Reps typed.
        r.row.orderedSets[0].reps = 8
        r.controller.checkRow(r.row.orderedSets[0], in: r.row)
        #expect(r.row.orderedSets[0].isCompleted && r.controller.emptyCheck == nil)
        // Load typed.
        r.row.orderedSets[1].weightKg = 60
        r.controller.checkRow(r.row.orderedSets[1], in: r.row)
        #expect(r.row.orderedSets[1].isCompleted)
        // A plan session's ghost: Bench has a target.
        r.controller.checkRow(r.x.orderedSets[3], in: r.x)
        #expect(r.x.orderedSets[3].isCompleted && r.x.orderedSets[3].reps == 5 && r.x.orderedSets[3].weightKg == 80)
        #expect(r.controller.emptyCheck == nil)
    }

    @Test func aRowAfterALoggedOneTakesTheSetAboveAsItsGhost() {
        let r = rig()
        r.row.orderedSets[0].reps = 8
        r.row.orderedSets[0].weightKg = 60
        r.controller.checkRow(r.row.orderedSets[0], in: r.row)
        r.controller.checkRow(r.row.orderedSets[1], in: r.row)
        #expect(r.row.orderedSets[1].isCompleted && r.row.orderedSets[1].reps == 8)
    }

    @Test func bodyweightWithARepsGhostLogs() {
        let r = rig()
        let dip = r.controller.add(r.other)
        dip.targetRepsMin = 8
        dip.orderedSets[0].reps = nil
        r.controller.checkRow(dip.orderedSets[0], in: dip)
        #expect(dip.orderedSets[0].isCompleted && dip.orderedSets[0].reps == 8)
    }

    @Test func timeAndDistanceRowsKeepTodaysBehaviourAndLogWhenEmpty() {
        let r = rig()
        let plank = r.controller.add(MockTrain.plank)
        let erg = r.controller.add(MockTrain.erg)
        #expect(plank.loadType == .time && erg.loadType == .distance)
        r.controller.checkRow(plank.orderedSets[0], in: plank)
        r.controller.checkRow(erg.orderedSets[0], in: erg)
        #expect(plank.orderedSets[0].isCompleted && erg.orderedSets[0].isCompleted, "L20: ✓ on an empty one logs")
        #expect(r.controller.emptyCheck == nil)
    }

    @Test func aStoredTimeIsALoggedValue() {
        let r = rig()
        let plank = r.controller.add(MockTrain.plank)
        plank.orderedSets[0].durationSec = 45
        r.controller.checkRow(plank.orderedSets[0], in: plank)
        #expect(plank.orderedSets[0].isCompleted && r.controller.emptyCheck == nil)
    }

    @Test func checkRowOnADoneRowUnchecksIt() {
        let r = rig()
        r.complete(1, of: r.row)
        r.controller.checkRow(r.row.orderedSets[0], in: r.row)
        #expect(!r.row.orderedSets[0].isCompleted && r.controller.emptyCheck == nil)
    }

    @Test func toggleCheckIsUnchangedAndLogsAnEmptyRow() {
        let r = rig()
        let set = r.row.orderedSets[0]
        r.controller.toggleCheck(set, in: r.row)
        #expect(set.isCompleted && set.reps == nil && set.weightKg == nil, "toggleCheck never asks")
        #expect(r.controller.emptyCheck == nil)
    }

    @Test func eachEmptyCheckIsANewEvent() {
        let r = rig()
        let set = r.row.orderedSets[0]
        r.controller.checkRow(set, in: r.row)
        let first = r.controller.emptyCheck
        r.controller.checkRow(set, in: r.row)
        #expect(r.controller.emptyCheck != nil && r.controller.emptyCheck != first, "the view announces every time")
    }

    @Test func theKeypadStillWorksAfterAnEmptyCheck() {
        let r = rig()
        let set = r.row.orderedSets[0]
        r.controller.checkRow(set, in: r.row)
        r.controller.type("6")
        r.controller.type("0")
        #expect(set.weightKg == 60)
        r.controller.checkRow(set, in: r.row)
        #expect(set.isCompleted, "with a load typed the same tap logs")
    }

    // MARK: flag off: the same actions in List touch nothing of Focused

    @Test func listLeavesTheFocusedStateAlone() async {
        let r = rig(.list)
        let c = r.controller
        let initial = c.lastActivityNext
        _ = warmup(0, of: r.row, r)
        c.activate(r.row.orderedSets[2])
        c.checkRow(r.row.orderedSets[1], in: r.row)       // an empty row: List logs it
        #expect(r.row.orderedSets[1].isCompleted, "List's ✓ is toggleCheck")
        c.toggleCheck(r.row.orderedSets[0], in: r.row)       // the warm-up, last of its kind
        c.toggleCheck(r.row.orderedSets[0], in: r.row)       // and back
        c.edit(r.row.orderedSets[2], .reps)
        c.nextField()
        c.nextField()
        c.toggleWarmup(r.row.orderedSets[2])
        c.addWarmup(to: r.curl)
        await c.replaceExercise(r.x, with: r.incline)
        c.undoReplace()
        c.remove(r.curl)
        #expect(c.expandedWarmups.isEmpty, "List has no groups")
        #expect(c.tappedSet == nil && c.emptyCheck == nil && c.autoFold == nil)
        #expect(c.lastActivityNext != nil && initial != nil)
    }

    @Test func listsLockScreenNextIgnoresTapsPagesAndTheKeypad() {
        let r = rig(.list)
        let c = r.controller
        let initial = c.lastActivityNext
        c.activate(r.row.orderedSets[2])
        c.jump(to: r.curl.id)
        c.edit(r.row.orderedSets[2], .kg)
        c.nextField()
        c.nextField()
        #expect(c.lastActivityNext == initial && initial == c.nextLabel(), "List's Next never followed the page or the keypad")
    }

    @Test func listNumbersEverySetAndKeepsTheSetIndexOrder() {
        let r = rig(.list)
        let w = warmup(0, of: r.row, r)
        let c = r.controller
        #expect(c.position(of: w, in: r.row) == (1, 3, false))
        #expect(c.position(of: r.row.orderedSets[2], in: r.row) == (3, 3, false))
        #expect(c.tableRows(of: r.row).map(\.id) == r.row.orderedSets.map(\.id), "List never folds")
        #expect(c.nextRow(after: r.row.orderedSets[0], in: r.row)?.id == r.row.orderedSets[1].id)
    }
}
