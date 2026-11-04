import Foundation
import Testing
@testable import Ryft

/// "Last time" per occurrence (beta feedback 2, §4): the platform concatenates every occurrence of an exercise in the
/// last session; each plan row of that exercise gets its own run, but only when runs and rows match one to one.
/// Synthetic sets only; like the platform's list, completed working sets only (no warm-ups).
@Suite("Last time per occurrence")
struct LastTimeOccurrenceTests {
    /// Working sets at `indexes`, reps 10, 9, 8 …, at `kg`.
    static func run(_ kg: Double, _ indexes: [Int]) -> [SessionSet] {
        indexes.enumerated().map { i, index in SessionSet(setIndex: index, reps: 10 - i, weightKg: kg) }
    }

    static func run(_ kg: Double, count: Int) -> [SessionSet] { run(kg, Array(0..<count)) }

    static func row(_ exercise: Exercise, _ position: Int, sets: Int = 3) -> PlanExercise {
        PlanExercise(exercise: exercise, position: position, sets: sets, repsMin: 8, repsMax: 12, targetKind: .rpe,
                     targetValue: 8, restSec: 90)
    }

    // MARK: Splitting

    @Test func oneOccurrenceKeepsTheList() {
        let sets = Self.run(40, count: 3) + Self.run(30, count: 3)
        #expect(LastTimeOccurrence.sets(sets, occurrence: 0, of: 1) == sets)
        let only = Self.row(MockTrain.facePull, 0)
        let day = [Self.row(MockTrain.bench, 1), only]
        #expect(LastTimeOccurrence.sets(sets, for: only, in: day) == sets)
    }

    @Test func twoOccurrencesOfThreeAndThree() {
        let first = Self.run(40, count: 3)
        let second = Self.run(30, count: 3)
        let sets = first + second
        #expect(LastTimeOccurrence.runs(sets) == [first, second])
        #expect(LastTimeOccurrence.sets(sets, occurrence: 0, of: 2) == first)
        #expect(LastTimeOccurrence.sets(sets, occurrence: 1, of: 2) == second)
    }

    /// Rows are taken by position, not by their order in the day's array.
    @Test func rowsByPosition() {
        let first = Self.run(40, count: 3)
        let second = Self.run(30, count: 3)
        let early = Self.row(MockTrain.facePull, 1)
        let late = Self.row(MockTrain.facePull, 4)
        let day = [late, Self.row(MockTrain.bench, 0), early]
        #expect(LastTimeOccurrence.sets(first + second, for: early, in: day) == first)
        #expect(LastTimeOccurrence.sets(first + second, for: late, in: day) == second)
    }

    /// Gaps from left-out sets: the working sets still restart, so the split holds.
    @Test func completedOnlyGapsStillSplit() {
        let first = Self.run(40, [1, 2, 4]) // warm-up 0 and an unfinished set 3 left out
        let second = Self.run(30, [2, 3, 4]) // two warm-ups left out
        #expect(LastTimeOccurrence.runs(first + second) == [first, second])
        #expect(LastTimeOccurrence.sets(first + second, occurrence: 1, of: 2) == second)
    }

    /// A gap that lets the second occurrence start above where the first ended merges the runs: both rows get the
    /// joint list, never a wrong half.
    @Test func mergedRunsKeepTheJointList() {
        let sets = Self.run(40, [0, 1]) + Self.run(30, [2, 3, 4])
        #expect(LastTimeOccurrence.runs(sets).count == 1)
        #expect(LastTimeOccurrence.sets(sets, occurrence: 0, of: 2) == sets)
        #expect(LastTimeOccurrence.sets(sets, occurrence: 1, of: 2) == sets)
    }

    /// Three rows, two runs (one occurrence merged or missing): every row keeps the joint list.
    @Test func moreRowsThanRunsKeepTheJointList() {
        let sets = Self.run(40, count: 3) + Self.run(30, count: 2)
        for k in 0..<3 { #expect(LastTimeOccurrence.sets(sets, occurrence: k, of: 3) == sets) }
        #expect(LastTimeOccurrence.sets([], occurrence: 1, of: 2) == [])
    }

    /// Two sets with one index (a 409 merge keeps both) split a run: more runs than rows, so the joint list.
    @Test func duplicateIndexKeepsTheJointList() {
        let sets = Self.run(40, [0, 1, 1, 2]) + Self.run(30, count: 3)
        #expect(LastTimeOccurrence.runs(sets).count == 3)
        #expect(LastTimeOccurrence.sets(sets, occurrence: 0, of: 2) == sets)
        #expect(LastTimeOccurrence.sets(sets, occurrence: 1, of: 2) == sets)
    }

    // MARK: Through the session

    /// Two rows of one exercise in a plan day: each card's last time and ghosts are its own occurrence.
    @MainActor
    @Test func sessionFromPlanSplitsPerRow() {
        let store = TrainStore(inMemory: true)
        let first = Self.row(MockTrain.facePull, 0)
        let second = Self.row(MockTrain.facePull, 1)
        let day = PlanDay(dayIndex: 0, name: "Pull", exercises: [first, second])
        let last = Self.run(25, count: 3) + Self.run(15, count: 3)
        let targets = [first, second].map {
            PlanTarget(planExerciseId: $0.id, exerciseId: $0.exerciseId, sets: 3, repsMin: 8, repsMax: 12,
                       targetKind: .rpe, targetKg: nil, restSec: 90, lastTime: last)
        }
        let today = PlanToday(enrollment: MockTrain.enrollment, day: day, targets: targets)
        let session = SessionFactory.fromPlan(day: day, today: today, library: MockTrain.exercises, in: store)
        let cards = session.orderedExercises
        #expect(cards.count == 2)
        #expect(cards[0].lastTime.compactMap(\.weightKg) == [25, 25, 25])
        #expect(cards[1].lastTime.compactMap(\.weightKg) == [15, 15, 15])
        #expect(cards[1].ghost(forSetAt: 0).kg == 15)
        #expect(cards[1].ghost(forSetAt: 2).reps == 8)
    }
}
