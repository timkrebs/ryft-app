import Foundation
import Testing
@testable import Ryft

/// The controller side of the Focused layout's page (architecture.md §1 to §5, ADR 0013): a page change is no edit, the
/// manual window, the keypad invariant, remove, replace and Undo, the warm-up group's effect on "Next:", and the layout
/// read once. The rig is `ReplaceRig`: `Row` (0) · `Bench` (1, superset 1) · `Lateral` (2, superset 1) · `Curl` (3), the
/// page on `Row` (the first with an open set). Synthetic values only.
@MainActor
struct SessionFocusedPageTests {
    private func rig(_ layout: SessionLayout = .focused) -> ReplaceRig { ReplaceRig(sessionLayout: layout) }

    /// What a page change must leave alone.
    private struct Written: Equatable {
        let updatedAt: Date
        let ops: Int
        let held: Bool

        @MainActor
        init(_ r: ReplaceRig) {
            updatedAt = r.session.updatedAt
            ops = r.store.pendingOps().count
            held = r.sync.isHeld(r.controller.id)
        }
    }

    /// Every way the page changes without an edit.
    enum Move: String, CaseIterable, Sendable {
        case jump, jumpAndBack, follow, pin
    }

    private func perform(_ move: Move, on r: ReplaceRig) {
        let c = r.controller
        switch move {
        case .jump: c.jump(to: r.curl.id)
        case .jumpAndBack:
            c.jump(to: r.curl.id)
            c.jump(to: r.row.id)
        case .follow:
            c.follow(AdvanceRequest(id: UUID(), step: .advance(collapse: [], to: .init(exerciseID: r.curl.id,
                                                                                         setID: r.curl.orderedSets[0].id))))
        case .pin: c.pinPage()
        }
    }

    private func request(to ex: LocalSessionExercise) -> AdvanceRequest {
        AdvanceRequest(id: UUID(), step: .advance(collapse: [], to: .init(exerciseID: ex.id, setID: ex.orderedSets[0].id)))
    }

    /// Checks a set and lets the 0.6 s task reach its sleep on the test clock.
    private func check(_ set: LocalSet, in ex: LocalSessionExercise, _ r: ReplaceRig) async {
        r.controller.toggleCheck(set, in: ex)
        await r.settle { r.clock.pendingSleeps >= 1 }
    }

    private func releaseDelay(_ r: ReplaceRig) async {
        r.clock.advance(by: SessionAdvance.delay)
        await r.settle()
    }

    // MARK: a page change is no edit (L10, ADR 0013 §2)

    @Test(arguments: Move.allCases)
    func aPageChangeWritesNoUpdatedAtAndQueuesNoUpload(_ move: Move) async {
        let r = rig()
        let before = Written(r)
        perform(move, on: r)
        #expect(Written(r) == before, "\(move)")
        await r.sync.flush()
        #expect(!r.api.calls.contains("putSession"), "\(move)")
    }

    @Test func theMovesReallyMoveThePage() {
        let r = rig()
        #expect(r.controller.pageExerciseID == r.row.id)
        r.controller.jump(to: r.curl.id)
        #expect(r.controller.pageExerciseID == r.curl.id && r.session.currentExerciseID == r.curl.id)
        r.session.currentExerciseID = nil
        r.controller.pinPage()
        #expect(r.session.currentExerciseID == r.row.id, "pin stores what resolve chose")
    }

    @Test func theSavedPageIsInTheStoreAtOnce() {
        let r = rig()
        r.controller.jump(to: r.x.id)
        #expect(!r.store.context.hasChanges, "showPage saves, so a kill right after a swipe keeps the page")
    }

    /// Nothing covered this: a swipe while a replace can still be undone.
    @Test(arguments: Move.allCases)
    func aPageChangeDuringTheUndoWindowWritesNothingAndKeepsTheWindow(_ move: Move) async {
        let r = rig()
        r.complete(2, of: r.x)
        await r.controller.replaceExercise(r.x, with: r.incline)
        let undoID = r.controller.undo?.id
        #expect(undoID != nil)
        let before = Written(r)
        #expect(before.held, "the upload is held for the window")

        perform(move, on: r)
        r.clock.advance(by: .seconds(2))
        await r.sync.flush()

        #expect(Written(r) == before, "\(move)")
        #expect(r.controller.undo?.id == undoID, "the window and its toast are the same replace")
        #expect(!r.api.calls.contains("putSession"), "no PUT while the window is open")
        #expect(r.puts.isEmpty)
    }

    @Test func theWindowStillEndsOnItsClockAfterPagesChanged() async {
        let r = rig()
        r.complete(2, of: r.x)
        await r.controller.replaceExercise(r.x, with: r.incline)
        r.controller.jump(to: r.curl.id)
        r.clock.advance(by: .milliseconds(2_000))
        r.controller.jump(to: r.row.id)
        r.clock.advance(by: .milliseconds(2_800))
        await r.settle()
        #expect(r.controller.undo != nil, "4.8 s after the replace: swipes didn't restart or end the window")
        await r.expireUndoWindow()
        #expect(r.controller.undo == nil)
        #expect(r.puts.count == 1, "the replace's one upload")
    }

    @Test func undoAfterSwipingAroundRestoresTheRowExactly() async {
        let r = rig()
        r.complete(2, of: r.x)
        let before = r.layout
        await r.controller.replaceExercise(r.x, with: r.incline)
        r.controller.jump(to: r.curl.id)
        r.controller.jump(to: r.lateral.id)
        r.controller.undoReplace()
        #expect(r.layout == before)
        #expect(r.controller.pageExerciseID == r.x.id)
    }

    // MARK: the manual window (architecture.md §2)

    @Test func jumpStampsTheManualWindowOnTheInjectedClock() {
        let r = rig()
        #expect(r.controller.lastManualScroll == nil)
        r.controller.jump(to: r.curl.id)
        #expect(r.controller.lastManualScroll == r.clock.now())
        r.clock.advance(by: .seconds(1))
        r.controller.jump(to: r.x.id)
        #expect(r.controller.lastManualScroll == r.clock.now(), "each jump restarts the window")
    }

    @Test func followDoesNotStampTheWindow() {
        let r = rig()
        r.controller.follow(request(to: r.curl))
        #expect(r.controller.pageExerciseID == r.curl.id)
        #expect(r.controller.lastManualScroll == nil)
    }

    @Test func anEchoJumpDoesNotStampTheWindow() throws {
        let r = rig()
        let current = try #require(r.controller.pageExerciseID)
        r.controller.jump(to: current)
        #expect(r.controller.lastManualScroll == nil, "the pager's binding echoing the page the planner moved to")
        r.controller.follow(request(to: r.curl))
        r.controller.jump(to: r.curl.id)
        #expect(r.controller.lastManualScroll == nil)
    }

    @Test func aJumpToARowThatIsGoneChangesNothing() {
        let r = rig()
        r.controller.jump(to: UUID())
        #expect(r.controller.pageExerciseID == r.row.id)
        #expect(r.controller.lastManualScroll == nil && r.session.currentExerciseID == nil)
    }

    @Test func twoPlannerFlipsInsideThreeSecondsBothHappen() {
        let r = rig()
        r.controller.follow(request(to: r.x))
        #expect(r.controller.pageExerciseID == r.x.id)
        r.clock.advance(by: .seconds(1))
        r.controller.follow(request(to: r.lateral))
        #expect(r.controller.pageExerciseID == r.lateral.id, "a superset flips after every set")
        r.controller.follow(request(to: r.x))
        #expect(r.controller.pageExerciseID == r.x.id)
    }

    @Test func aPlannerStepThatMovesNothingIsIgnored() {
        let r = rig()
        r.controller.follow(AdvanceRequest(id: UUID(), step: .allDone(collapse: [r.row.id])))
        r.controller.follow(AdvanceRequest(id: UUID(), step: .stay))
        r.controller.follow(request(to: r.curl))
        #expect(r.controller.pageExerciseID == r.curl.id)
        r.controller.follow(AdvanceRequest(id: UUID(), step: .allDone(collapse: [])))
        #expect(r.controller.pageExerciseID == r.curl.id, "all done leaves the page (L1)")
    }

    @Test func aPlannerStepToARowThatWentIsIgnored() {
        let r = rig()
        let gone = AdvanceRequest(id: UUID(), step: .advance(collapse: [], to: .init(exerciseID: UUID(), setID: UUID())))
        r.controller.follow(gone)
        #expect(r.controller.pageExerciseID == r.row.id && r.session.currentExerciseID == nil)
    }

    @Test func aSwipeBeforeTheDelayEndsKeepsTheAutoAdvanceFromMovingThePage() async {
        let r = rig()
        r.complete(2, of: r.row)
        r.controller.jump(to: r.curl.id)   // the user peeks at another page
        await check(r.row.orderedSets[2], in: r.row, r)
        await releaseDelay(r)
        #expect(r.controller.advance == nil, "inside the 3 s window the planner stays")
    }

    @Test func withoutASwipeTheSameCheckAdvances() async throws {
        let r = rig()
        r.complete(2, of: r.row)
        await check(r.row.orderedSets[2], in: r.row, r)
        await releaseDelay(r)
        let advance = try #require(r.controller.advance)
        #expect(advance.step == .advance(collapse: [r.row.id], to: .init(exerciseID: r.x.id, setID: r.x.orderedSets[0].id)))
    }

    @Test func theAutoAdvanceWorksAgainWhenTheWindowHasPassed() async {
        let r = rig()
        r.complete(2, of: r.row)
        r.controller.jump(to: r.curl.id)
        r.clock.advance(by: .seconds(3))
        await check(r.row.orderedSets[2], in: r.row, r)
        await releaseDelay(r)
        #expect(r.controller.advance != nil)
    }

    @Test func aPlannerFollowDoesNotKeepTheNextAutoAdvanceFromHappening() async {
        let r = rig()
        r.complete(2, of: r.row)
        r.controller.follow(request(to: r.x))
        await check(r.row.orderedSets[2], in: r.row, r)
        await releaseDelay(r)
        #expect(r.controller.advance != nil, "follow isn't the user's hand")
    }

    // MARK: persistence and the fallback (ADR 0013 §1, §4)

    @Test func theSamePageComesBackAfterTheControllerIsRebuilt() {
        let r = rig()
        r.controller.jump(to: r.curl.id)
        let rebuilt = SessionController(session: r.session, sync: r.sync, liveActivity: nil, clock: r.clock,
                                        library: r.library, layout: .focused)
        defer { rebuilt.stop() }
        #expect(rebuilt.pageExerciseID == r.curl.id)
    }

    @Test func aRebuildWithoutAPageStoresNothingUntilTheScreenPinsIt() {
        let r = rig()
        let rebuilt = SessionController(session: r.session, sync: r.sync, liveActivity: nil, clock: r.clock,
                                        library: r.library, layout: .focused)
        defer { rebuilt.stop() }
        #expect(r.session.currentExerciseID == nil && rebuilt.pageExerciseID == r.row.id)
    }

    @Test func aPinnedPageDoesNotMoveByItselfAsSetsGetChecked() {
        let r = rig()
        r.controller.pinPage()
        r.complete(3, of: r.row)
        #expect(r.controller.pageExerciseID == r.row.id, "the first exercise with an open set is now Bench, but the page is Row")
    }

    @Test func anUnpinnedPageFollowsTheFirstOpenSet() {
        let r = rig()
        r.complete(3, of: r.row)
        #expect(r.controller.pageExerciseID == r.x.id, "the fallback, which is why the screen pins it")
    }

    @Test func whenTheStoredExerciseIsGoneTheFirstOpenOneShows() {
        let r = rig()
        r.controller.jump(to: r.curl.id)
        // A List controller's remove leaves the id behind (it never writes the page).
        let list = SessionController(session: r.session, sync: r.sync, liveActivity: nil, clock: r.clock, library: r.library,
                                     layout: .list)
        defer { list.stop() }
        list.remove(r.curl)
        #expect(r.session.currentExerciseID == r.curl.id, "the stale id is still there")
        #expect(r.controller.pageExerciseID == r.row.id)
        r.controller.pinPage()
        #expect(r.session.currentExerciseID == r.row.id)
    }

    @Test func whenTheStoredExerciseIsGoneAndEverythingIsDoneTheLastOneShows() {
        let r = rig()
        for ex in [r.row, r.x, r.lateral, r.curl] { r.complete(ex.sets.count, of: ex) }
        r.session.currentExerciseID = UUID()
        #expect(r.controller.pageExerciseID == r.curl.id)
    }

    // MARK: remove (architecture.md §5)

    @Test func removingTheCurrentPageGoesToTheNextExercise() {
        let r = rig()
        r.controller.jump(to: r.x.id)
        r.controller.remove(r.x)
        #expect(r.controller.pageExerciseID == r.lateral.id && r.session.currentExerciseID == r.lateral.id)
    }

    @Test func removingTheLastPageGoesToThePreviousOne() {
        let r = rig()
        r.controller.jump(to: r.curl.id)
        r.controller.remove(r.curl)
        #expect(r.controller.pageExerciseID == r.lateral.id && r.session.currentExerciseID == r.lateral.id)
    }

    @Test func removingEveryExerciseEndsWithNoPageAndNoKeypad() throws {
        let r = rig()
        let c = r.controller
        c.remove(r.row)
        #expect(c.pageExerciseID == r.x.id)
        c.remove(r.x)
        #expect(c.pageExerciseID == r.lateral.id)
        c.remove(r.lateral)
        #expect(c.pageExerciseID == r.curl.id)
        c.edit(try #require(r.curl.orderedSets.first), .reps)
        #expect(c.focus != nil)
        c.remove(r.curl)
        #expect(c.pageExerciseID == nil && r.session.currentExerciseID == nil)
        #expect(c.focus == nil, "the keypad closes with its page")
        #expect(c.exercises.isEmpty && c.pageExercise == nil)
    }

    @Test func removingThePageClosesTheKeypadOnIt() throws {
        let r = rig()
        r.controller.edit(try #require(r.row.orderedSets.first), .kg)
        r.controller.remove(r.row)
        #expect(r.controller.focus == nil)
        #expect(r.controller.pageExerciseID == r.x.id)
    }

    @Test func removingAnotherExerciseKeepsThePageAndTheKeypad() throws {
        let r = rig()
        let set = try #require(r.row.orderedSets.first)
        r.controller.edit(set, .kg)
        r.controller.remove(r.curl)
        #expect(r.controller.pageExerciseID == r.row.id)
        #expect(r.controller.focus == SetFocus(setID: set.id, field: .kg))
    }

    // MARK: the keypad closes on a page change (architecture.md §5)

    @Test func theKeypadClosesWhenThePageChanges() throws {
        let r = rig()
        let set = try #require(r.row.orderedSets.first)
        r.controller.edit(set, .reps)
        r.controller.jump(to: r.x.id)
        #expect(r.controller.focus == nil)
        r.controller.jump(to: r.row.id)
        #expect(r.controller.focus == nil, "swiping back doesn't bring it back")
    }

    @Test func thePlannersFollowClosesItToo() throws {
        let r = rig()
        r.controller.edit(try #require(r.row.orderedSets.first), .reps)
        r.controller.follow(request(to: r.x))
        #expect(r.controller.focus == nil)
    }

    @Test func anEchoJumpLeavesTheKeypadOpen() throws {
        let r = rig()
        let set = try #require(r.row.orderedSets.first)
        r.controller.edit(set, .reps)
        r.controller.jump(to: r.row.id)
        #expect(r.controller.focus == SetFocus(setID: set.id, field: .reps))
    }

    @Test func aPageChangeForgetsTheTappedRow() throws {
        let r = rig()
        r.controller.tappedSet = try #require(r.row.orderedSets.last).id
        r.controller.jump(to: r.x.id)
        #expect(r.controller.tappedSet == nil)
    }

    // MARK: split, replace in place and Undo (architecture.md §5)

    @Test func aSplitOnThePageMovesThePageToTheRowThatContinues() async {
        let r = rig()
        r.controller.jump(to: r.x.id)
        r.complete(2, of: r.x)
        await r.controller.replaceExercise(r.x, with: r.incline)
        let y = r.session.orderedExercises[2]
        #expect(y.id != r.x.id && y.exerciseId == r.incline.id)
        #expect(r.controller.pageExerciseID == y.id && r.session.currentExerciseID == y.id)
    }

    @Test func aSplitOnAnotherPageLeavesThePage() async {
        let r = rig()
        r.controller.jump(to: r.curl.id)
        r.complete(2, of: r.x)
        await r.controller.replaceExercise(r.x, with: r.incline)
        #expect(r.controller.pageExerciseID == r.curl.id)
    }

    @Test func aReplaceInPlaceKeepsThePageOnTheSameRow() async {
        let r = rig()
        r.controller.jump(to: r.x.id)
        await r.controller.replaceExercise(r.x, with: r.incline)
        #expect(r.x.exerciseId == r.incline.id)
        #expect(r.controller.pageExerciseID == r.x.id)
        #expect(r.layout.count == 4)
    }

    @Test func aSplitWritesNoUpdatedAtForThePageMove() async {
        let r = rig()
        r.controller.jump(to: r.x.id)
        r.complete(2, of: r.x)
        // The replace is an edit and stamps, but only held; the page move itself adds no upload.
        await r.controller.replaceExercise(r.x, with: r.incline)
        #expect(r.puts.isEmpty)
    }

    @Test func undoOfASplitLandsOnTheRowThatCameBack() async {
        let r = rig()
        r.controller.jump(to: r.x.id)
        r.complete(2, of: r.x)
        await r.controller.replaceExercise(r.x, with: r.incline)
        let yID = r.session.orderedExercises[2].id
        #expect(r.controller.pageExerciseID == yID)
        r.controller.undoReplace()
        #expect(r.controller.pageExerciseID == r.x.id && r.session.currentExerciseID == r.x.id)
        #expect(!r.session.exercises.contains { $0.id == yID })
    }

    @Test func undoFromAnotherPageLandsOnTheRestoredRow() async {
        let r = rig()
        r.controller.jump(to: r.x.id)
        r.complete(2, of: r.x)
        await r.controller.replaceExercise(r.x, with: r.incline)
        r.controller.jump(to: r.curl.id)
        r.controller.undoReplace()
        #expect(r.controller.pageExerciseID == r.x.id, "the toast is screen-wide; Undo shows what it restored")
    }

    @Test func undoOfAReplaceInPlaceFromAnotherPageLandsOnTheRow() async {
        let r = rig()
        r.controller.jump(to: r.x.id)
        await r.controller.replaceExercise(r.x, with: r.incline)
        r.controller.jump(to: r.curl.id)
        r.controller.undoReplace()
        #expect(r.controller.pageExerciseID == r.x.id)
        #expect(r.x.exerciseId == MockTrain.bench.id)
    }

    @Test func undoPutsTheKeypadBackOnTheRestoredRow() async throws {
        let r = rig()
        let set = try #require(r.x.orderedSets.first)
        r.controller.jump(to: r.x.id)
        r.controller.edit(set, .reps)
        r.controller.beginReplace()
        #expect(r.controller.focus == nil)
        await r.controller.replaceExercise(r.x, with: r.incline)
        r.controller.jump(to: r.curl.id)
        r.controller.undoReplace()
        #expect(r.controller.pageExerciseID == r.x.id)
        #expect(r.controller.focus == SetFocus(setID: set.id, field: .reps))
    }

    @Test func aKeypadOpenOnAnotherPageClosesWhenUndoLands() async throws {
        let r = rig()
        await r.controller.replaceExercise(r.x, with: r.incline)
        r.controller.jump(to: r.curl.id)
        r.controller.edit(try #require(r.curl.orderedSets.first), .kg)
        r.controller.undoReplace()
        #expect(r.controller.pageExerciseID == r.x.id)
        #expect(r.controller.focus == nil, "the invariant: an open keypad's set is on the page")
    }

    @Test func theKeypadOnTheReplacedPageStaysClosedAfterAReplaceInPlace() async throws {
        let r = rig()
        r.controller.jump(to: r.x.id)
        r.controller.edit(try #require(r.x.orderedSets.first), .kg)
        r.controller.beginReplace()
        await r.controller.replaceExercise(r.x, with: r.incline)
        #expect(r.controller.focus == nil && r.controller.pageExerciseID == r.x.id)
    }

    // MARK: the session has ended (ADR 0013 §5)

    enum Ending: String, CaseIterable, Sendable {
        case finishing, finished, discarded
    }

    /// The cover's last `onChange` arrives after the session ended. The page is unpinned here, so a pin that got through
    /// would store what `resolve` chose: on Discard, on a deleted row.
    @Test(arguments: Ending.allCases)
    func afterTheSessionEndsPinPageWritesNothing(_ ending: Ending) async {
        let r = rig()
        let c = r.controller
        switch ending {
        case .finishing:
            let finish = Task { await c.finish() }
            await r.settle { c.isFinishing }
            #expect(c.isFinishing)
            c.pinPage()
            #expect(r.session.currentExerciseID == nil, "\(ending)")
            _ = await finish.value
        case .finished:
            _ = await c.finish()
            c.pinPage()
            #expect(r.session.currentExerciseID == nil, "\(ending)")
        case .discarded:
            c.discard()
            c.pinPage()
            #expect(r.session.currentExerciseID == nil, "\(ending)")
        }
        #expect(!c.isUnderway)
    }

    @Test func theSummaryClosingLeavesThePageOnTheCompletedRow() async {
        let r = rig()
        let coordinator = TrainCoordinator(sync: r.sync, library: TrainLibrary.preview(store: r.store), liveActivities: false)
        coordinator.live = r.controller
        r.controller.jump(to: r.curl.id)
        _ = await r.controller.finish()
        coordinator.summaryDone()
        r.controller.pinPage() // what the cover's last change does
        #expect(coordinator.live == nil && coordinator.summary == nil)
        #expect(r.session.currentExerciseID == r.curl.id, "unread on the completed row, and it goes with the row")
    }

    @Test func finishLeavesThePageForTheSummary() async {
        let r = rig()
        r.controller.jump(to: r.curl.id)
        _ = await r.controller.finish()
        #expect(r.session.currentExerciseID == r.curl.id, "no flip behind the Finish spinner")
    }

    // MARK: List never writes the page

    enum ListMove: String, CaseIterable, Sendable {
        case jump, pin, follow, removeCurrent, splitReplace
    }

    @Test(arguments: ListMove.allCases)
    func theListLayoutNeverWritesThePage(_ move: ListMove) async {
        let r = rig(.list)
        let c = r.controller
        #expect(c.layout == .list)
        switch move {
        case .jump: c.jump(to: r.curl.id)
        case .pin: c.pinPage()
        case .follow: c.follow(request(to: r.curl))
        case .removeCurrent:
            if let ex = c.pageExercise { c.remove(ex) }
        case .splitReplace:
            r.complete(2, of: r.row)
            await c.replaceExercise(r.row, with: r.incline)
        }
        #expect(r.session.currentExerciseID == nil, "\(move)")
    }

    @Test func theListLayoutLeavesAnEarlierFocusedPageAlone() {
        let r = rig(.list)
        r.session.currentExerciseID = r.x.id
        r.controller.jump(to: r.curl.id)
        r.controller.remove(r.x)
        #expect(r.session.currentExerciseID == r.x.id)
    }

    // MARK: folded warm-ups (architecture.md §4)

    /// Row's first set is a warm-up, the group folded.
    private func withWarmup(_ r: ReplaceRig) {
        r.row.orderedSets[0].isWarmup = true
        r.store.save()
    }

    @Test func foldedWarmUpsLeaveThePlannersInputInFocused() {
        let r = rig()
        withWarmup(r)
        let states = r.controller.advanceStates
        #expect(states[0].sets.count == 2 && states[0].sets.allSatisfy { !$0.isWarmup })
        #expect(states[1].sets.count == 4, "other exercises are untouched")
        #expect(r.controller.isFolded(r.row))
    }

    @Test func anOpenGroupPutsThemBack() {
        let r = rig()
        withWarmup(r)
        r.controller.setWarmups(expanded: true, for: r.row)
        let states = r.controller.advanceStates
        #expect(states[0].sets.count == 3 && states[0].sets[0].isWarmup)
        #expect(!r.controller.isFolded(r.row))
        r.controller.setWarmups(expanded: false, for: r.row)
        #expect(r.controller.advanceStates[0].sets.count == 2)
    }

    @Test func nextNamesTheWorkingSetWhileFoldedAndTheWarmUpWhenOpen() {
        let r = rig()
        withWarmup(r)
        #expect(r.controller.nextUp?.set.id == r.row.orderedSets[1].id)
        r.controller.setWarmups(expanded: true, for: r.row)
        #expect(r.controller.nextUp?.set.id == r.row.orderedSets[0].id)
    }

    @Test func foldingChangesNoSetAndQueuesNothing() {
        let r = rig()
        withWarmup(r)
        let shape = RowShape(r.row)
        let before = Written(r)
        r.controller.setWarmups(expanded: true, for: r.row)
        r.controller.setWarmups(expanded: false, for: r.row)
        #expect(RowShape(r.row) == shape)
        #expect(Written(r) == before)
    }

    @Test func theGroupFoldsItselfWhenItsLastWarmUpIsChecked() {
        let r = rig()
        withWarmup(r)
        r.controller.setWarmups(expanded: true, for: r.row)
        r.controller.toggleCheck(r.row.orderedSets[0], in: r.row)
        #expect(r.controller.expandedWarmups.isEmpty)
        #expect(r.controller.isFolded(r.row))
    }

    @Test func inListNothingIsFoldedAndThePlannersInputIsTheStates() {
        let r = rig(.list)
        withWarmup(r)
        #expect(!r.controller.isFolded(r.row))
        #expect(r.controller.advanceStates == SessionController.states(of: r.controller.exercises))
        #expect(r.controller.advanceStates[0].sets[0].isWarmup, "the warm-up stays in the input")
        r.controller.setWarmups(expanded: true, for: r.row)
        r.controller.setWarmups(expanded: false, for: r.row)
        #expect(r.controller.advanceStates == SessionController.states(of: r.controller.exercises))
    }

    @Test func inListNextStillOffersTheWarmUpFirst() {
        let r = rig(.list)
        withWarmup(r)
        #expect(r.controller.nextUp?.set.id == r.row.orderedSets[0].id)
    }

    @Test func aWarmUpMarkedInFocusedStaysOnScreenInItsOpenGroup() {
        let r = rig()
        r.controller.toggleWarmup(r.row.orderedSets[0])
        #expect(r.controller.expandedWarmups.contains(r.row.id))
        #expect(r.controller.advanceStates[0].sets[0].isWarmup)
    }

    // MARK: a keypad on a folding warm-up

    /// Row's first two sets are warm-ups, the group open. Its third is a working set.
    private func withOpenWarmups(_ r: ReplaceRig) -> [LocalSet] {
        let sets = r.row.orderedSets
        sets[0].isWarmup = true
        sets[1].isWarmup = true
        r.store.save()
        r.controller.setWarmups(expanded: true, for: r.row)
        return sets
    }

    @Test func foldingClosesAKeypadOnAWarmUp() {
        let r = rig()
        let sets = withOpenWarmups(r)
        r.controller.edit(sets[0], .kg)
        r.controller.setWarmups(expanded: false, for: r.row)
        #expect(r.controller.focus == nil)
    }

    @Test func foldingLeavesAKeypadOnAWorkingSet() {
        let r = rig()
        let sets = withOpenWarmups(r)
        r.controller.edit(sets[2], .kg)
        r.controller.setWarmups(expanded: false, for: r.row)
        #expect(r.controller.focus?.setID == sets[2].id)
    }

    @Test func foldingAnotherExerciseLeavesAKeypadOnAWarmUp() {
        let r = rig()
        let sets = withOpenWarmups(r)
        r.x.orderedSets[0].isWarmup = true
        r.store.save()
        r.controller.setWarmups(expanded: true, for: r.x)
        r.controller.edit(sets[0], .kg)
        r.controller.setWarmups(expanded: false, for: r.x)
        #expect(r.controller.focus?.setID == sets[0].id)
    }

    @Test func openingTheGroupLeavesTheKeypad() {
        let r = rig()
        let sets = withOpenWarmups(r)
        r.controller.edit(sets[0], .kg)
        r.controller.setWarmups(expanded: true, for: r.row)
        #expect(r.controller.focus?.setID == sets[0].id)
    }

    /// The set being checked is another one, so `toggleCheck`'s own close doesn't cover this.
    @Test func checkingTheLastWarmUpClosesAKeypadOnAnEarlierOne() {
        let r = rig()
        let sets = withOpenWarmups(r)
        r.complete(1, of: r.row)
        r.controller.edit(sets[0], .kg)
        r.controller.toggleCheck(sets[1], in: r.row)
        #expect(!r.controller.expandedWarmups.contains(r.row.id), "the group folded itself")
        #expect(r.controller.focus == nil)
    }

    @Test func checkingAWarmUpThatDoesNotFoldTheGroupLeavesTheKeypad() {
        let r = rig()
        let sets = withOpenWarmups(r)
        r.controller.edit(sets[0], .kg)
        r.controller.toggleCheck(sets[1], in: r.row)
        #expect(r.controller.expandedWarmups.contains(r.row.id))
        #expect(r.controller.focus?.setID == sets[0].id)
    }

    @Test func theListLayoutKeepsAKeypadOnAWarmUpWhenTheLastOneIsChecked() {
        let r = rig(.list)
        let sets = r.row.orderedSets
        sets[0].isWarmup = true
        sets[1].isWarmup = true
        r.complete(1, of: r.row)
        r.controller.edit(sets[0], .kg)
        r.controller.toggleCheck(sets[1], in: r.row)
        #expect(r.controller.focus?.setID == sets[0].id)
    }

    // MARK: stored time and distance (L20)

    enum Stored: String, CaseIterable, Sendable {
        case time, distance
    }

    /// `set` has no reps, only what an import or another client stored.
    private func store(_ stored: Stored, on set: LocalSet, _ r: ReplaceRig) {
        set.reps = nil
        switch stored {
        case .time: set.durationSec = 45
        case .distance: set.distanceM = 500
        }
        r.store.save()
    }

    @Test(arguments: Stored.allCases)
    func nextPassesOverAStoredRow(_ stored: Stored) {
        let r = rig()
        let sets = r.row.orderedSets
        store(stored, on: sets[1], r)
        r.controller.edit(sets[0], .reps)
        r.controller.nextField()
        #expect(r.controller.focus == SetFocus(setID: sets[2].id, field: .kg), "\(stored)")
    }

    @Test func nextFromAStoredRowsWeightHasNoRepsToGoTo() {
        let r = rig()
        let sets = r.row.orderedSets
        store(.time, on: sets[1], r)
        r.controller.edit(sets[1], .kg)
        r.controller.nextField()
        #expect(r.controller.focus == SetFocus(setID: sets[2].id, field: .kg))
    }

    @Test func nextClosesTheKeypadWhenOnlyStoredRowsFollow() {
        let r = rig()
        let sets = r.row.orderedSets
        store(.time, on: sets[1], r)
        store(.distance, on: sets[2], r)
        r.controller.edit(sets[0], .reps)
        r.controller.nextField()
        #expect(r.controller.focus == nil)
    }

    @Test func aRowWithRepsAndATimeStaysEditable() {
        let r = rig()
        let sets = r.row.orderedSets
        sets[1].reps = 8
        sets[1].durationSec = 45
        r.store.save()
        r.controller.edit(sets[0], .reps)
        r.controller.nextField()
        #expect(r.controller.focus == SetFocus(setID: sets[1].id, field: .kg))
        r.controller.nextField()
        #expect(r.controller.focus == SetFocus(setID: sets[1].id, field: .reps))
    }

    @Test func theListLayoutKeepsStoredRowsInNext() {
        let r = rig(.list)
        let sets = r.row.orderedSets
        store(.time, on: sets[1], r)
        r.controller.edit(sets[0], .reps)
        r.controller.nextField()
        #expect(r.controller.focus == SetFocus(setID: sets[1].id, field: .kg))
        r.controller.nextField()
        #expect(r.controller.focus == SetFocus(setID: sets[1].id, field: .reps))
    }

    // MARK: the layout is read once (plan.md L5)

    private final class LayoutBox {
        var layout: SessionLayout
        private(set) var reads = 0
        init(_ layout: SessionLayout) { self.layout = layout }
        @MainActor func read() -> SessionLayout { reads += 1; return layout }
    }

    @Test func theCoordinatorReadsItWhenTheControllerIsBuiltAndNotWhenItIsResumed() {
        let r = rig()
        let coordinator = TrainCoordinator(sync: r.sync, library: TrainLibrary.preview(store: r.store), liveActivities: false)
        let box = LayoutBox(.focused)
        coordinator.sessionLayout = { box.read() }
        coordinator.resume()
        defer { coordinator.live?.stop() }
        #expect(coordinator.live?.layout == .focused)
        box.layout = .list
        coordinator.resume()
        #expect(coordinator.live?.layout == .focused, "the running controller stays as it was built")
        #expect(box.reads == 1)
        coordinator.close()
        coordinator.resume()
        #expect(coordinator.live?.layout == .list, "reopening picks the new value up")
        #expect(box.reads == 2)
    }
}
