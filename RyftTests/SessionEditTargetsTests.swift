import Foundation
import Testing
@testable import Ryft

// Edit targets for the running session only (design.md §6) and the progression-fallback scenario (design.md §4).

@MainActor
struct SessionEditTargetsTests {
    // The rig's Bench: 4 sets, the first two typed in (5 x 80), the last two empty.

    @Test func targetsReadTheRow() {
        let rig = ReplaceRig()
        let t = rig.controller.targets(of: rig.x)
        #expect(t == SessionTargets(sets: 4, repsMin: 5, repsMax: 5, kg: 80, restSec: 180))
    }

    @Test func onlyEmptyUncheckedSetsCanGo() {
        let rig = ReplaceRig()
        #expect(rig.controller.minSets(for: rig.x) == 2)
        rig.x.orderedSets[2].reps = 3                   // a value: no longer removable
        #expect(rig.controller.minSets(for: rig.x) == 3)
        rig.complete(4, of: rig.x)
        #expect(rig.controller.minSets(for: rig.x) == 4)
    }

    @Test func fewerSetsRemoveFromTheEndAndKeepFilledOnes() {
        let rig = ReplaceRig()
        let ids = rig.x.orderedSets.map(\.id)
        var t = rig.controller.targets(of: rig.x)
        t.sets = 2
        rig.controller.setTargets(t, for: rig.x)
        #expect(rig.x.orderedSets.map(\.id) == Array(ids.prefix(2)))
        #expect(Set(ids.suffix(2)).isSubset(of: Set(rig.session.deletedSetIDs)))
        #expect(rig.x.targetSets == 2)
        #expect(rig.x.orderedSets.map(\.setIndex) == [0, 1])
    }

    @Test func neverDeletesCheckedSetsOrSetsWithValues() {
        // Checked set at the end, a typed value in the middle: asking for 1 set removes only what is empty.
        let rig = ReplaceRig()
        let sets = rig.x.orderedSets
        sets[3].completedAt = rig.clock.now()       // checked, empty values
        sets[2].weightKg = 70                       // value only
        var t = rig.controller.targets(of: rig.x)
        t.sets = 1
        rig.controller.setTargets(t, for: rig.x)
        #expect(rig.x.sets.count == 4, "all four hold something")
        #expect(rig.session.deletedSetIDs.isEmpty)
        #expect(rig.x.orderedSets.map(\.id) == sets.map(\.id))
    }

    @Test func removalStopsAtTheFirstSetThatHoldsSomething() {
        let rig = ReplaceRig()
        let sets = rig.x.orderedSets
        sets[2].reps = 4                            // set 3 has a value; set 4 is empty
        var t = rig.controller.targets(of: rig.x)
        t.sets = 1
        rig.controller.setTargets(t, for: rig.x)
        #expect(rig.x.orderedSets.map(\.id) == sets.dropLast().map(\.id))
        #expect(rig.session.deletedSetIDs == [sets[3].id])
    }

    @Test func moreSetsAppendEmptyOnes() {
        let rig = ReplaceRig()
        var t = rig.controller.targets(of: rig.x)
        t.sets = 6
        rig.controller.setTargets(t, for: rig.x)
        #expect(rig.x.sets.count == 6 && rig.x.targetSets == 6)
        #expect(rig.x.orderedSets.map(\.setIndex) == Array(0..<6))
        #expect(rig.x.orderedSets.suffix(2).allSatisfy { $0.reps == nil && $0.weightKg == nil && !$0.isCompleted })
    }

    @Test func repsKgAndRestAreWrittenToTheSessionOnly() async {
        let rig = ReplaceRig()
        let setValues = rig.x.orderedSets.map(\.reps)
        rig.controller.setTargets(SessionTargets(sets: 4, repsMin: 6, repsMax: 10, kg: 82.5, restSec: 120), for: rig.x)
        #expect(rig.x.targetRepsMin == 6 && rig.x.targetRepsMax == 10)
        #expect(rig.x.targetKg == 82.5 && rig.x.restSec == 120)
        #expect(rig.x.orderedSets.map(\.reps) == setValues, "typed values are not touched")
        #expect(rig.x.planExerciseId == rig.peBench, "the plan link stays")
        #expect(rig.library.savedPlans.isEmpty, "session only")
        #expect(rig.controller.undo == nil, "no undo for targets: the sheet has Cancel")
    }

    @Test func targetsUploadLikeAnyEdit() {
        let rig = ReplaceRig()
        var t = rig.controller.targets(of: rig.x)
        t.sets = 3
        rig.controller.setTargets(t, for: rig.x)
        #expect(rig.puts.count == 1, "removing a set is a change the server must hear about")
    }

    // MARK: decision 9: the progression fallback counts a replacement twice (design.md §4)

    /// What the app can observe: the document it sends. Bench is planned today and linked in the session; an
    /// exercise planned today is also the replacement for another row, so two rows of Bench go up, one without a
    /// `plan_exercise_id`. That is the trigger the platform's fallback (`plan_exercise_id IS NULL AND plan_day_id =
    /// day AND exercise_id = pe.exercise_id`) would count a second time.
    ///
    /// The count itself is not observable here: `MockTrain` (planToday, completeSession) has no `PlanExerciseAttempts`
    /// and no progression; its targets come from the best past weight per exercise only. The request therefore
    /// rests on design.md §4's reading of the platform code.
    @Test func replacingWithAnExerciseThatIsPlannedTodayPutsTwoRowsOfItOnTheWire() async throws {
        let rig = ReplaceRig()
        // The session also has the planned Bench (linked) from the plan; the Row is replaced with Bench.
        let planned = SessionFactory.add(MockTrain.bench, to: rig.session, sets: 3, in: rig.store)
        planned.planExerciseId = rig.peBench
        rig.x.planExerciseId = nil                       // x is a different planned lift here: unlink for clarity
        await rig.controller.replaceExercise(rig.row, with: MockTrain.bench)
        await rig.expireUndoWindow()

        let doc = rig.session.wire
        let benchRows = doc.exercises.filter { $0.exerciseId == MockTrain.bench.id }
        #expect(benchRows.count >= 2)
        #expect(benchRows.filter { $0.planExerciseId == rig.peBench }.count == 1, "one linked row")
        #expect(benchRows.contains { $0.planExerciseId == nil }, "and one the fallback would also match")
        // The planned day on the session is what the fallback joins on.
        #expect(doc.planDayId == rig.session.planDayId && doc.planDayId != nil)
    }
}
