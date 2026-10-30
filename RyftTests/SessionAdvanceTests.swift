import Foundation
import Testing
@testable import Ryft

/// The planner behind "Jump to next exercise" (rules in design.md section 7).
struct SessionAdvanceTests {
    private typealias A = SessionAdvance

    private static let t0 = Date(timeIntervalSince1970: 1_792_400_000)

    /// `done` marks the completed sets by index; `warmups` the warm-up indices.
    private func ex(_ id: UUID = UUID(), group: Int? = nil, sets n: Int, done: Set<Int> = [],
                    warmups: Set<Int> = []) -> (state: A.ExerciseState, ids: [UUID]) {
        let ids = (0..<n).map { _ in UUID() }
        let sets = (0..<n).map { A.SetState(id: ids[$0], isWarmup: warmups.contains($0), isCompleted: done.contains($0)) }
        return (A.ExerciseState(id: id, supersetGroup: group, sets: sets), ids)
    }

    private func input(_ exercises: [A.ExerciseState], checked: A.SetRef, next: A.SetRef?,
                       keypadOpen: Bool = false, lastManualScroll: Date? = nil, userExpanded: Set<UUID> = [],
                       enabled: Bool = true, now: Date = SessionAdvanceTests.t0) -> A.Input {
        A.Input(exercises: exercises, checked: checked, next: next, keypadOpen: keypadOpen,
                lastManualScroll: lastManualScroll, userExpanded: userExpanded, enabled: enabled, now: now)
    }

    @Test func theDelayAndWindowAreTheAgreedOnes() {
        #expect(A.delay == .milliseconds(600))
        #expect(A.manualScrollWindow == 3)
    }

    @Test func theLastOpenSetCollapsesAndAdvancesToTheNextExercise() {
        let a = ex(sets: 2, done: [0, 1]), b = ex(sets: 2)
        let checked = A.SetRef(exerciseID: a.state.id, setID: a.ids[1])
        let next = A.SetRef(exerciseID: b.state.id, setID: b.ids[0])
        #expect(A.step(input([a.state, b.state], checked: checked, next: next))
                == .advance(collapse: [a.state.id], to: next))
    }

    @Test func aMiddleSetOfAPlainExerciseStays() {
        let a = ex(sets: 3, done: [0]), b = ex(sets: 2)
        let checked = A.SetRef(exerciseID: a.state.id, setID: a.ids[0])
        let next = A.SetRef(exerciseID: a.state.id, setID: a.ids[1])
        #expect(A.step(input([a.state, b.state], checked: checked, next: next)) == .stay)
    }

    @Test func anOpenWarmUpDoesNotKeepAnExerciseOpen() throws {
        // `next` as the controller builds it (SessionAdvance.next), not by hand: the open warm-up is skipped.
        let a = ex(sets: 3, done: [1, 2], warmups: [0]), b = ex(sets: 1)
        let checked = A.SetRef(exerciseID: a.state.id, setID: a.ids[2])
        let next = try #require(A.next(after: a.state.id, in: [a.state, b.state]))
        #expect(next == A.SetRef(exerciseID: b.state.id, setID: b.ids[0]))
        #expect(A.step(input([a.state, b.state], checked: checked, next: next))
                == .advance(collapse: [a.state.id], to: next))
    }

    // MARK: supersets

    @Test func aSupersetAlternatesWithoutCollapsingUntilTheGroupIsDone() {
        let id1 = UUID(), id2 = UUID()
        // A1 checked: partner B1.
        let a = ex(id1, group: 1, sets: 2, done: [0])
        var b = ex(id2, group: 1, sets: 2)
        var next = A.SetRef(exerciseID: id2, setID: b.ids[0])
        #expect(A.step(input([a.state, b.state], checked: .init(exerciseID: id1, setID: a.ids[0]), next: next))
                == .advance(collapse: [], to: next))
        // B1 checked: back to A2 (no collapse).
        b = ex(id2, group: 1, sets: 2, done: [0])
        next = A.SetRef(exerciseID: id1, setID: a.ids[1])
        #expect(A.step(input([a.state, b.state], checked: .init(exerciseID: id2, setID: b.ids[0]), next: next))
                == .advance(collapse: [], to: next))
    }

    @Test func aFinishedSupersetCollapsesBothMembersTogether() {
        let id1 = UUID(), id2 = UUID()
        let a = ex(id1, group: 1, sets: 2, done: [0, 1]), b = ex(id2, group: 1, sets: 2, done: [0, 1])
        let c = ex(sets: 1)
        let next = A.SetRef(exerciseID: c.state.id, setID: c.ids[0])
        let step = A.step(input([a.state, b.state, c.state], checked: .init(exerciseID: id2, setID: b.ids[1]), next: next))
        guard case let .advance(collapse, to) = step else { Issue.record("expected advance, got \(step)"); return }
        #expect(Set(collapse) == [id1, id2] && collapse.count == 2)
        #expect(to == next)
    }

    @Test func aSupersetMemberFinishingFirstDoesNotCollapseWhileThePartnerHasOpenSets() {
        let id1 = UUID(), id2 = UUID()
        let a = ex(id1, group: 1, sets: 1, done: [0]), b = ex(id2, group: 1, sets: 2, done: [0])
        let next = A.SetRef(exerciseID: id2, setID: b.ids[1])
        #expect(A.step(input([a.state, b.state], checked: .init(exerciseID: id1, setID: a.ids[0]), next: next))
                == .advance(collapse: [], to: next))
    }

    // MARK: stays

    @Test func aCheckOutOfOrderDoesNotAdvance() {
        // Set 3 was done first; now set 1 is checked and set 2 is still open.
        let a = ex(sets: 3, done: [0, 2]), b = ex(sets: 1)
        let next = A.SetRef(exerciseID: a.state.id, setID: a.ids[1])
        #expect(A.step(input([a.state, b.state], checked: .init(exerciseID: a.state.id, setID: a.ids[0]), next: next))
                == .stay)
    }

    @Test func aForgottenSetThatFinishesTheExerciseAdvances() {
        // Sets 2 and 3 done earlier, set 1 last: no open working set is left, so the exercise is done (lead D-c).
        let a = ex(sets: 3, done: [0, 1, 2]), b = ex(sets: 1)
        let next = A.SetRef(exerciseID: b.state.id, setID: b.ids[0])
        #expect(A.step(input([a.state, b.state], checked: .init(exerciseID: a.state.id, setID: a.ids[0]), next: next))
                == .advance(collapse: [a.state.id], to: next))
    }

    @Test(arguments: [(2.9, false), (3.1, true), (0.0, false), (60.0, true)])
    func aManualScrollSuppressesForThreeSeconds(secondsSinceScroll: Double, advances: Bool) {
        let a = ex(sets: 1, done: [0]), b = ex(sets: 1)
        let next = A.SetRef(exerciseID: b.state.id, setID: b.ids[0])
        let now = Self.t0
        let step = A.step(input([a.state, b.state], checked: .init(exerciseID: a.state.id, setID: a.ids[0]), next: next,
                                lastManualScroll: now.addingTimeInterval(-secondsSinceScroll), now: now))
        #expect((step != .stay) == advances)
    }

    @Test func noManualScrollAtAllAdvances() {
        let a = ex(sets: 1, done: [0]), b = ex(sets: 1)
        let next = A.SetRef(exerciseID: b.state.id, setID: b.ids[0])
        #expect(A.step(input([a.state, b.state], checked: .init(exerciseID: a.state.id, setID: a.ids[0]), next: next))
                == .advance(collapse: [a.state.id], to: next))
    }

    @Test func anOpenKeypadStays() {
        let a = ex(sets: 1, done: [0]), b = ex(sets: 1)
        let next = A.SetRef(exerciseID: b.state.id, setID: b.ids[0])
        #expect(A.step(input([a.state, b.state], checked: .init(exerciseID: a.state.id, setID: a.ids[0]), next: next,
                             keypadOpen: true)) == .stay)
    }

    @Test func theSettingOffStays() {
        let a = ex(sets: 1, done: [0]), b = ex(sets: 1)
        let next = A.SetRef(exerciseID: b.state.id, setID: b.ids[0])
        #expect(A.step(input([a.state, b.state], checked: .init(exerciseID: a.state.id, setID: a.ids[0]), next: next,
                             enabled: false)) == .stay)
    }

    @Test func aCardTheUserExpandedIsNotCollapsedAgainButTheListStillAdvances() {
        let a = ex(sets: 1, done: [0]), b = ex(sets: 1)
        let next = A.SetRef(exerciseID: b.state.id, setID: b.ids[0])
        #expect(A.step(input([a.state, b.state], checked: .init(exerciseID: a.state.id, setID: a.ids[0]), next: next,
                             userExpanded: [a.state.id])) == .advance(collapse: [], to: next))
    }

    // MARK: all done

    @Test func noNextSetMeansAllDone() {
        let a = ex(sets: 2, done: [0, 1]), b = ex(sets: 1, done: [0])
        #expect(A.step(input([a.state, b.state], checked: .init(exerciseID: b.state.id, setID: b.ids[0]), next: nil))
                == .allDone(collapse: [b.state.id]))
    }

    @Test func allDoneStaysWhenTheKeypadIsOpen() {
        let a = ex(sets: 1, done: [0])
        #expect(A.step(input([a.state], checked: .init(exerciseID: a.state.id, setID: a.ids[0]), next: nil,
                             keypadOpen: true)) == .stay)
    }
}
