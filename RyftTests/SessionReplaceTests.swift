import Foundation
import Testing
@testable import Ryft

// Replace an exercise during a session, undo, and the sync safety around it (design.md §1-5, plan.md T1).
// Signatures agreed in design.md; the one call that design.md leaves open is `replace(_:with:alsoChangePlan:)`.

extension SessionController {
    /// The only place the tests name the replace entry point.
    func replaceExercise(_ ex: LocalSessionExercise, with new: Exercise, alsoChangePlan: Bool = false) async {
        await replace(ex, with: new, alsoChangePlan: alsoChangePlan)
    }
}

@MainActor
struct SessionReplaceTests {
    // MARK: nothing done: in place (design §1)

    @Test func noDoneSetsMutatesTheRowInPlace() async {
        let rig = ReplaceRig()
        let before = rig.layout
        let setIDs = rig.x.orderedSets.map(\.id)
        #expect(rig.controller.replaceKind(for: rig.x) == .inPlace)

        await rig.controller.replaceExercise(rig.x, with: rig.incline)

        let after = rig.layout
        #expect(after.count == before.count)
        let row = after[1]
        #expect(row.id == before[1].id, "the same row")
        #expect(row.exerciseId == rig.incline.id)
        #expect(row.name == rig.incline.name)
        #expect(rig.x.kind == rig.incline.kind && rig.x.loadType == rig.incline.loadType)
        #expect(row.position == 1)
        #expect(row.supersetGroup == 1, "the superset is kept")
        #expect(rig.lateral.supersetGroup == 1)
        #expect(row.sets.map(\.id) == setIDs, "set ids and count are kept")
        #expect(row.targetSets == 4 && row.targetRepsMin == 5 && row.targetRepsMax == 5)
        #expect(row.restSec == 180)
        #expect(row.notes == "pause on chest")
        // Everything else is untouched.
        #expect(after[0] == before[0] && after[2] == before[2] && after[3] == before[3])
    }

    @Test func inPlaceDropsThePlanLinkAndTheKgTarget() async {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        #expect(rig.x.planExerciseId == nil)
        #expect(rig.x.targetKg == nil)
        // kind .kg: the plan's number belonged to the old lift
        #expect(rig.x.targetValue == nil)
        let wire = rig.session.wire.exercises.first { $0.id == rig.x.id }
        #expect(wire?.exerciseId == rig.incline.id && wire?.planExerciseId == nil)
    }

    @Test func inPlaceKeepsAnRpeTarget() async {
        let rig = ReplaceRig()
        rig.x.targetKindRaw = TargetKind.rpe.rawValue
        rig.x.targetValue = 8
        rig.x.targetKg = nil
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        #expect(rig.x.targetValue == 8)
    }

    @Test func inPlaceClearsTypedValuesAndStampsTheSets() async {
        let rig = ReplaceRig()
        let stamp = rig.clock.now()
        rig.clock.advance(by: .seconds(60))
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        for s in rig.x.orderedSets {
            #expect(s.reps == nil && s.weightKg == nil, "typed, unchecked values were the old lift's")
            #expect(s.completedAt == nil)
            #expect(s.updatedAt >= stamp)
        }
    }

    @Test func inPlaceTakesLastTimeFromTheNewExercisesCache() async {
        let rig = ReplaceRig()
        let last = [SessionSet(setIndex: 0, reps: 10, weightKg: 30, updatedAt: rig.clock.now())]
        rig.library.cached[rig.incline.id] = last
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        #expect(rig.x.lastTime == last)
    }

    @Test func inPlaceWithoutHistoryShowsNoGhostsFromTheOldLift() async {
        let rig = ReplaceRig()
        #expect(rig.x.lastTime.isEmpty == false)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)   // offline, nothing cached
        #expect(rig.x.lastTime.isEmpty)
    }

    @Test func aFreshLastTimeLandsOnlyWhileTheRowIsStillThatExercise() async {
        let rig = ReplaceRig()
        rig.library.fresh[rig.incline.id] = [SessionSet(setIndex: 0, reps: 12, weightKg: 24, updatedAt: rig.clock.now())]
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        #expect(rig.x.lastTime.first?.reps == 12)
    }

    // MARK: done sets: split (design §2)

    @Test func aCheckedWarmUpCountsAsDone() {
        let rig = ReplaceRig()
        let first = rig.x.orderedSets[0]
        first.isWarmup = true
        first.completedAt = rig.clock.now()
        #expect(rig.controller.replaceKind(for: rig.x) == .split(done: 1, remaining: 3))
    }

    @Test func replaceKindTable() {
        struct Row { let done: Int; let kind: SessionController.ReplaceKind }
        let rows = [Row(done: 0, kind: .inPlace),
                    Row(done: 1, kind: .split(done: 1, remaining: 3)),
                    Row(done: 2, kind: .split(done: 2, remaining: 2)),
                    Row(done: 3, kind: .split(done: 3, remaining: 1))]
        for r in rows {
            let rig = ReplaceRig()
            rig.complete(r.done, of: rig.x)
            #expect(rig.controller.replaceKind(for: rig.x) == r.kind, "\(r.done) done")
        }
    }

    @Test func withTwoDoneSetsTheOldRowKeepsThemAndItsPlanLink() async {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        let done = rig.x.orderedSets.prefix(2).map(\.id)
        let doneShape = RowShape(rig.x).sets.prefix(2)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)

        #expect(rig.x.exerciseId == MockTrain.bench.id, "the logged lift stays what it was")
        #expect(rig.x.planExerciseId == rig.peBench)
        #expect(rig.x.orderedSets.map(\.id) == done)
        #expect(Array(RowShape(rig.x).sets) == Array(doneShape))
        #expect(rig.x.targetKg == 80 && rig.x.position == 1 && rig.x.supersetGroup == 1)
    }

    @Test func theNewRowFollowsWithTheRemainingSets() async throws {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        let openIDs = Set(rig.x.orderedSets.dropFirst(2).map(\.id))
        await rig.controller.replaceExercise(rig.x, with: rig.incline)

        let list = rig.session.orderedExercises
        #expect(list.count == 5)
        #expect(list.map(\.position) == [0, 1, 2, 3, 4], "positions renumbered")
        let y = list[2]
        #expect(y.id != rig.x.id)
        #expect(y.exerciseId == rig.incline.id && y.name == rig.incline.name)
        #expect(y.sets.count == 2 && y.targetSets == 2)
        #expect(Set(y.sets.map(\.id)).isDisjoint(with: openIDs), "new set ids")
        #expect(y.planExerciseId == nil && y.targetKg == nil)
        #expect(y.supersetGroup == 1, "the bracket carries on")
        #expect(y.restSec == 180 && y.targetRepsMin == 5 && y.targetRepsMax == 5)
        #expect(y.orderedSets.allSatisfy { !$0.isCompleted && $0.reps == nil && $0.weightKg == nil })
        #expect(list[3].id == rig.lateral.id && list[4].id == rig.curl.id)
        #expect(list[0].id == rig.row.id)
    }

    @Test func theOpenSetsOfTheOldRowAreTombstonedAndKeepNoPlace() async {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        let open = rig.x.orderedSets.dropFirst(2).map(\.id)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        #expect(Set(open).isSubset(of: Set(rig.session.deletedSetIDs)))
        #expect(rig.x.sets.count == 2)
        let done = rig.x.orderedSets.map(\.id)
        #expect(rig.session.deletedSetIDs.allSatisfy { !done.contains($0) })
    }

    @Test func aWarmUpOnTheNewRowKeepsItsFlag() async {
        let rig = ReplaceRig()
        rig.complete(1, of: rig.x)
        rig.x.orderedSets[2].isWarmup = true
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        let y = rig.session.orderedExercises[2]
        #expect(y.orderedSets.map(\.isWarmup) == [false, true, false], "3 open sets, the flag stays on the middle one")
    }

    // MARK: the order of the list and the wire

    @Test func theUploadCarriesTheNewExerciseOnceTheUndoWindowHasPassed() async throws {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        #expect(rig.puts.isEmpty, "held for the window")
        await rig.expireUndoWindow()
        #expect(rig.puts.count == 1)
        let doc = try #require(await rig.uploaded())
        #expect(doc.exercises.map(\.exerciseId).contains(rig.incline.id))
    }

    // MARK: undo (design §3)

    @Test func undoInPlaceRestoresTheRowExactly() async {
        let rig = ReplaceRig()
        let before = rig.layout
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        #expect(rig.controller.undo != nil)
        rig.controller.undoReplace()
        #expect(rig.layout == before)
        #expect(rig.controller.undo == nil)
    }

    @Test func undoASplitRestoresRowsSetsAndPositions() async {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        let before = rig.layout
        let open = rig.x.orderedSets.dropFirst(2).map(\.id)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        let y = rig.session.orderedExercises[2]
        let yID = y.id, ySets = y.sets.map(\.id)

        rig.controller.undoReplace()

        #expect(rig.layout == before)
        #expect(rig.session.exercises.contains { $0.id == yID } == false)
        #expect(rig.x.orderedSets.map(\.id).suffix(2) == open, "old ids come back")
        #expect(Set(open).isDisjoint(with: Set(rig.session.deletedSetIDs)), "no longer tombstoned")
        #expect(Set(ySets).isSubset(of: Set(rig.session.deletedSetIDs)))
        #expect(rig.session.deletedExerciseIDs.contains(yID))
    }

    @Test func restoredSetsCarryNewerStampsThanTheReplace() async {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        let replacedAt = rig.clock.now()
        rig.clock.advance(by: .seconds(2))
        rig.controller.undoReplace()
        for s in rig.x.orderedSets { #expect(s.updatedAt > replacedAt, "undo is a new edit, not a rewind") }
    }

    @Test func undoRestoresTheFocus() async {
        let rig = ReplaceRig()
        let set = rig.x.orderedSets[0]
        rig.controller.edit(set, .reps)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        rig.controller.focus = nil
        rig.controller.undoReplace()
        #expect(rig.controller.focus == SetFocus(setID: set.id, field: .reps))
    }

    @Test func undoWithinTheWindowNeverUploadsTheReplacedState() async throws {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        // An earlier edit's PUT is queued too: it waits with the replace (TrainSyncService.hold).
        rig.controller.toggleCheck(rig.row.orderedSets[0], in: rig.row)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        rig.clock.advance(by: .seconds(2))
        await rig.sync.flush()
        #expect(rig.controller.undo != nil)
        #expect(!rig.api.calls.contains("putSession"), "no PUT at all while the undo window is open")
        rig.controller.undoReplace()
        // What goes up now is the restored document: no Y, no new exercise id.
        let doc = try #require(await rig.uploaded())
        #expect(!doc.exercises.contains { $0.exerciseId == rig.incline.id })
        #expect(doc.exercises.count == 4)
        #expect(rig.api.calls.filter { $0 == "putSession" }.count == 1)
    }

    @Test func nothingIsQueuedBeforeTheWindowEnds() async {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        rig.clock.advance(by: .milliseconds(4_900))
        await rig.settle()
        #expect(rig.puts.isEmpty && rig.controller.undo != nil)
    }

    @Test func theWindowEndsAfterFiveSecondsWithOnePutAndNoUndo() async {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        await rig.expireUndoWindow()
        #expect(rig.controller.undo == nil)
        #expect(rig.puts.count == 1)
    }

    @Test func pausingCommitsTheReplace() async {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        rig.controller.pause()
        #expect(rig.puts.count == 1)
        #expect(rig.controller.undo == nil)
    }

    @Test func undoAfterTheWindowChangesNothing() async {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        await rig.expireUndoWindow()
        let after = rig.layout
        rig.controller.undoReplace()
        #expect(rig.layout == after)
    }

    @Test func aSecondReplaceCommitsTheFirst() async {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        let firstID = rig.controller.undo?.id
        await rig.controller.replaceExercise(rig.x, with: rig.other)
        #expect(rig.controller.undo != nil && rig.controller.undo?.id != firstID)
        rig.controller.undoReplace()
        // One level deep: back to the incline, not the original.
        #expect(rig.x.exerciseId == rig.incline.id)
    }

    // MARK: edits cancel the undo (design §3)

    @Test(arguments: ["checkSetOnReplaced", "typeOnReplaced", "addSetToReplaced", "removeReplaced", "toggleSuperset", "moveExercise"])
    func anEditToTheAffectedRowDropsTheUndo(_ edit: String) async throws {
        let rig = ReplaceRig()
        rig.complete(1, of: rig.x)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        let y = rig.session.orderedExercises[1 + 1]
        let c = rig.controller
        switch edit {
        case "checkSetOnReplaced": c.toggleCheck(try #require(y.orderedSets.first), in: y)
        case "typeOnReplaced":
            c.edit(try #require(y.orderedSets.first), .reps)
            c.type("8")
        case "addSetToReplaced": c.addSet(to: y)
        case "removeReplaced": c.remove(y)
        case "toggleSuperset": c.toggleSuperset(y)
        default: c.move(from: IndexSet(integer: 0), to: 2)
        }
        #expect(c.undo == nil, "\(edit)")
    }

    @Test func anEditToTheOldRowOfASplitDropsTheUndoToo() async throws {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        rig.controller.toggleWarmup(try #require(rig.x.orderedSets.first))
        #expect(rig.controller.undo == nil)
    }

    @Test func anEditElsewhereKeepsTheUndo() async throws {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        let set = try #require(rig.curl.orderedSets.first)
        rig.controller.edit(set, .kg)
        rig.controller.type("4")
        rig.controller.skipRest()
        #expect(rig.controller.undo != nil)
    }

    // MARK: the 409 merge never brings a removed exercise back (design §8 step 2)

    @Test func aRemovedExerciseDoesNotComeBackThroughApply() {
        let rig = ReplaceRig()
        let gone = rig.curl
        let server = rig.session.wire                    // still has the curl row
        rig.controller.remove(gone)
        #expect(rig.session.deletedExerciseIDs.contains(gone.id))
        rig.session.apply(server, names: rig.store.exercise(id:), in: rig.store.context)
        #expect(!rig.session.exercises.contains { $0.id == gone.id })
    }

    @Test func aRemovedExerciseDoesNotComeBackThroughMerge() {
        let rig = ReplaceRig()
        let server = rig.session.wire
        let goneID = rig.curl.id
        rig.controller.remove(rig.curl)
        let merged = SessionMerge.merge(local: rig.session.wire, server: server,
                                        deletedSetIDs: Set(rig.session.deletedSetIDs),
                                        deletedExerciseIDs: Set(rig.session.deletedExerciseIDs))
        #expect(!merged.exercises.contains { $0.id == goneID })
        #expect(merged.exercises.count == 3)
    }

    @Test func theRowAnUndoTookOutStaysOutWhenTheServerStillHasIt() async {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        // The server got the replaced state before the undo (a PUT in flight).
        let server = rig.session.wire
        rig.clock.advance(by: .seconds(1))
        rig.controller.undoReplace()
        let restored = rig.layout

        let merged = SessionMerge.merge(local: rig.session.wire, server: server,
                                        deletedSetIDs: Set(rig.session.deletedSetIDs),
                                        deletedExerciseIDs: Set(rig.session.deletedExerciseIDs))
        rig.session.apply(merged, names: rig.store.exercise(id:), in: rig.store.context)
        #expect(rig.layout == restored, "the restored state stays and the inserted row does not return")
    }

    // MARK: also change the plan (design §5)

    @Test func alsoChangeThePlanSavesOnceWithTheNewExerciseInTheSlot() async throws {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true)
        #expect(rig.library.savedPlans.count == 1)
        let saved = try #require(rig.library.savedPlans.first)
        #expect(saved.id == rig.plan.id)
        let old = try #require(rig.plan.days[0].exercises.first { $0.id == rig.peBench })
        let slot = try #require(saved.days[0].exercises.first { $0.position == old.position })
        #expect(slot.id != rig.peBench, "a new plan-exercise id, so the old lift's attempts stay with the old one")
        #expect(slot.exerciseId == rig.incline.id && slot.exercise.id == rig.incline.id)
        #expect(slot.sets == old.sets && slot.repsMin == old.repsMin && slot.repsMax == old.repsMax)
        #expect(slot.restSec == old.restSec && slot.supersetGroup == old.supersetGroup)
        #expect(slot.notes == old.notes && slot.targetKind == old.targetKind)
        #expect(saved.days[0].exercises.count == rig.plan.days[0].exercises.count)
        #expect(saved.days[0].exercises.first { $0.id == rig.peRow } == rig.plan.days[0].exercises[0],
                "the other exercises are untouched")
        #expect(rig.x.planExerciseId == nil, "this session's link to the old plan exercise is cleared")
    }

    @Test func withoutTheToggleThePlanIsNotSaved() async {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline)
        await rig.controller.replaceExercise(rig.x, with: rig.other)
        #expect(rig.library.savedPlans.isEmpty)
    }

    @Test func aBuiltInPlanIsNeverSaved() async {
        let rig = ReplaceRig(builtinPlan: true)
        await rig.controller.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true)
        #expect(rig.library.savedPlans.isEmpty)
        #expect(rig.x.exerciseId == rig.incline.id, "the session still changes")
    }

    @Test func aFailedPlanSaveOnASplitGivesTheOldRowItsLinkBack() async {
        let rig = ReplaceRig()
        rig.complete(2, of: rig.x)
        rig.library.saveSucceeds = false
        await rig.controller.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true)
        #expect(rig.library.savedPlans.count == 1)
        #expect(rig.x.planExerciseId == rig.peBench)
    }

    @Test func aFailedPlanSaveInPlaceLeavesTheReplacementUnlinked() async {
        let rig = ReplaceRig()
        rig.library.saveSucceeds = false
        await rig.controller.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true)
        #expect(rig.library.savedPlans.count == 1)
        #expect(rig.x.planExerciseId == nil, "ADR 0009: a replacement never carries the old plan link")
    }

    @Test func undoRevertsThePlanChangeAndRelinksAfterTheSave() async throws {
        let rig = ReplaceRig()
        await rig.controller.replaceExercise(rig.x, with: rig.incline, alsoChangePlan: true)
        rig.controller.undoReplace()
        await rig.settle { rig.library.savedPlans.count == 2 }
        #expect(rig.library.savedPlans.count == 2)
        #expect(rig.library.savedPlans.last == rig.plan, "the original plan, saved again")
        await rig.settle { rig.x.planExerciseId != nil }
        #expect(rig.x.planExerciseId == rig.peBench)
        #expect(rig.x.exerciseId == MockTrain.bench.id)
    }

    @Test func planReplacingTargetValueTable() {
        struct Case { let kind: TargetKind; let old: Double?; let kg: Double?; let expect: Double? }
        let cases = [Case(kind: .kg, old: 80, kg: 32.5, expect: 32.5),
                     Case(kind: .kg, old: 80, kg: nil, expect: 80),       // no history: the old value stays
                     Case(kind: .rpe, old: 8, kg: 32.5, expect: 8),
                     Case(kind: .pct1rm, old: 75, kg: 32.5, expect: 75),
                     Case(kind: .bodyweight, old: nil, kg: 32.5, expect: nil)]
        for c in cases {
            let rig = ReplaceRig()
            var plan = rig.plan
            plan.days[0].exercises[1].targetKind = c.kind
            plan.days[0].exercises[1].targetValue = c.old
            let out = SessionController.replacing(rig.peBench, with: rig.incline, kg: c.kg, in: plan)
            #expect(out.days[0].exercises[1].targetValue == c.expect, "\(c.kind)")
        }
    }
}
