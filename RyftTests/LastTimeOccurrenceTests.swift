import Foundation
import Testing
@testable import Ryft

/// "Last time" per occurrence (beta feedback 2, §4): the platform concatenates every occurrence of an exercise in the
/// last session; each plan row of that exercise gets its own run. Synthetic sets only.
@Suite("Last time per occurrence")
struct LastTimeOccurrenceTests {
    /// A run of working sets from `start`, reps 10, 9, 8 …, at `kg`.
    static func run(_ kg: Double, count: Int, from start: Int = 0) -> [SessionSet] {
        (0..<count).map { i in SessionSet(setIndex: start + i, reps: 10 - i, weightKg: kg) }
    }

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

    /// More rows than the last session had occurrences: the later rows get the last run.
    @Test func moreRowsThanRuns() {
        let first = Self.run(40, count: 3)
        let second = Self.run(30, count: 2)
        let sets = first + second
        #expect(LastTimeOccurrence.sets(sets, occurrence: 1, of: 3) == second)
        #expect(LastTimeOccurrence.sets(sets, occurrence: 2, of: 3) == second)
        // One run for two rows: both get it.
        #expect(LastTimeOccurrence.sets(first, occurrence: 1, of: 2) == first)
        #expect(LastTimeOccurrence.sets([], occurrence: 1, of: 2) == [])
    }

    /// A warm-up inside a run doesn't start a new one; the next occurrence's warm-up does.
    @Test func warmUpsInsideARun() {
        let first = [SessionSet(setIndex: 0, reps: 8, weightKg: 20, isWarmup: true)] + Self.run(40, count: 3, from: 1)
        let second = [SessionSet(setIndex: 0, reps: 8, weightKg: 15, isWarmup: true),
                      SessionSet(setIndex: 1, reps: 6, weightKg: 20, isWarmup: true)] + Self.run(30, count: 3, from: 2)
        let sets = first + second
        #expect(LastTimeOccurrence.runs(sets) == [first, second])
        #expect(LastTimeOccurrence.sets(sets, occurrence: 1, of: 2) == second)
        // Warm-ups the platform already left out: the working sets still restart.
        let working = Self.run(40, count: 3, from: 1) + Self.run(30, count: 3, from: 2)
        #expect(LastTimeOccurrence.runs(working).map(\.count) == [3, 3])
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
