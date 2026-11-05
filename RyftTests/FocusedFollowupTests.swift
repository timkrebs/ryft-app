import Testing
@testable import Ryft

/// What ✓ logs on a bodyweight row, and the keypad when its exercise goes. Synthetic values only.
@MainActor
@Suite("Focused follow-ups")
struct FocusedFollowupTests {
    private func rig(_ layout: SessionLayout) -> ReplaceRig {
        let r = ReplaceRig(sessionLayout: layout)
        r.controller.settings.setColumn = nil
        return r
    }

    /// A new page with last time's sets: 8 reps at `kg`.
    private func added(_ exercise: Exercise, to r: ReplaceRig, kg: Double?) -> LocalSessionExercise {
        let ex = SessionFactory.add(exercise, to: r.session, sets: 3, in: r.store)
        ex.lastTime = [SessionSet(setIndex: 0, reps: 8, weightKg: kg)]
        r.controller.showPage(ex.id)
        return ex
    }

    // MARK: ✓ on a bodyweight row

    @Test("Focused: ✓ logs the added load the row shows")
    func focusedLogsTheAddedLoad() {
        let r = rig(.focused)
        let ex = added(MockTrain.pullUp, to: r, kg: 10)
        let set = ex.orderedSets[0]
        #expect(r.controller.ghost(for: set, in: ex).kg == 10)
        r.controller.toggleCheck(set, in: ex)
        #expect(set.isCompleted)
        #expect(set.weightKg == 10)
        #expect(set.reps == 8)
    }

    @Test("List: ✓ logs no added load, as before")
    func listLogsNone() {
        let r = rig(.list)
        let ex = added(MockTrain.pullUp, to: r, kg: 10)
        let set = ex.orderedSets[0]
        r.controller.toggleCheck(set, in: ex)
        #expect(set.isCompleted)
        #expect(set.weightKg == nil)
        #expect(set.reps == 8)
    }

    @Test("Focused: with no added load to show, ✓ logs none")
    func noLoadToLog() {
        let r = rig(.focused)
        let ex = added(MockTrain.pullUp, to: r, kg: nil)
        let set = ex.orderedSets[0]
        r.controller.toggleCheck(set, in: ex)
        #expect(set.isCompleted)
        #expect(set.weightKg == nil)
    }

    @Test("Focused: a typed load isn't replaced by the ghost")
    func aTypedLoadStays() {
        let r = rig(.focused)
        let ex = added(MockTrain.pullUp, to: r, kg: 10)
        let set = ex.orderedSets[0]
        set.weightKg = 5
        r.controller.toggleCheck(set, in: ex)
        #expect(set.weightKg == 5)
    }

    @Test("Time and distance fill no kg in either layout", arguments: [SessionLayout.focused, .list])
    func timeAndDistanceStay(_ layout: SessionLayout) {
        for exercise in [MockTrain.plank, MockTrain.erg] {
            let r = rig(layout)
            let ex = added(exercise, to: r, kg: 10)
            let set = ex.orderedSets[0]
            r.controller.toggleCheck(set, in: ex)
            #expect(set.isCompleted)
            #expect(set.weightKg == nil)
        }
    }

    // MARK: the keypad when its exercise goes

    @Test("List: removing the exercise under the keypad closes the keypad")
    func listRemoveClosesTheKeypad() {
        let r = rig(.list)
        r.controller.edit(r.x.orderedSets[0], .kg)
        r.controller.remove(r.x)
        #expect(r.controller.focus == nil)
    }

    @Test("List: removing another exercise leaves the keypad open")
    func listRemoveElsewhereKeepsIt() {
        let r = rig(.list)
        let focus = SetFocus(setID: r.x.orderedSets[0].id, field: .kg)
        r.controller.edit(r.x.orderedSets[0], .kg)
        r.controller.remove(r.curl)
        #expect(r.controller.focus == focus)
    }

    /// `leavePage` has nowhere to go and no page to clear: `showPage(nil)` matches the stored nil and returns.
    @Test("Focused: removing a lone exercise with no stored page closes the keypad")
    func focusedLoneExercise() {
        let r = rig(.focused)
        for ex in [r.x, r.lateral, r.curl] { r.controller.remove(ex) }
        r.session.currentExerciseID = nil
        r.controller.edit(r.row.orderedSets[0], .kg)
        r.controller.remove(r.row)
        #expect(r.controller.exercises.isEmpty)
        #expect(r.controller.focus == nil)
    }

    @Test("Focused: removing the page's exercise closes the keypad, as it did")
    func focusedPage() {
        let r = rig(.focused)
        r.controller.showPage(r.x.id)
        r.controller.edit(r.x.orderedSets[0], .kg)
        r.controller.remove(r.x)
        #expect(r.controller.focus == nil)
    }
}
