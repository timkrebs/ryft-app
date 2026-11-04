import Foundation
import Testing
@testable import Ryft

/// The rest pill's logic (architecture.md §7, design.md §2.7, §4c): a rest with no set checked, what the pill shows, the
/// sheet's length, "Rest over" going back to idle, and what VoiceOver hears. Synthetic values only.
@MainActor
struct SessionManualRestTests {
    private func rig(_ layout: SessionLayout = .focused) -> ReplaceRig { ReplaceRig(sessionLayout: layout) }

    private func endRest(_ r: ReplaceRig) {
        r.controller.startRest(for: r.row)
        r.controller.adjustRest(by: -RestTimer.maxRest)
    }

    // MARK: a manual rest

    @Test("A manual rest is no edit: no check, no advance, no upload, the same active row")
    func manualRestChangesNothingElse() {
        let r = rig()
        let c = r.controller
        let active = c.activeSet(in: r.row)?.id
        let updated = r.session.updatedAt
        c.startRest(for: r.row)
        #expect(c.rest.isRunning)
        #expect(c.rest.total == TimeInterval(r.row.restSec))
        #expect(r.session.restEndsAt == c.rest.endsAt)
        #expect(c.setsChecked == 0)
        #expect(c.lastCheckedExercise == nil)
        #expect(c.advance == nil)
        #expect(c.activeSet(in: r.row)?.id == active)
        #expect(r.session.updatedAt == updated)
        #expect(r.store.pendingOps().isEmpty)
    }

    @Test("The sheet's length starts the rest and leaves the exercise's alone")
    func sheetLengthLeavesTheExercise() {
        let r = rig()
        let rest = r.row.restSec
        r.controller.startRest(for: r.row, seconds: rest + 30)
        #expect(r.controller.rest.total == TimeInterval(rest + 30))
        #expect(r.row.restSec == rest)
    }

    @Test("A rest after a check goes the same way as before")
    func aRestAfterACheck() {
        let r = rig(.list)
        let set = r.row.orderedSets[0]
        set.reps = 8
        r.controller.toggleCheck(set, in: r.row)
        #expect(r.controller.rest.total == TimeInterval(r.row.restSec))
    }

    // MARK: rest over

    @Test("Focused: Rest over goes back to idle after its moment")
    func restOverSettles() async {
        let r = rig()
        endRest(r)
        #expect(r.controller.rest.phase == .finished)
        await r.settle { r.clock.pendingSleeps >= 1 }
        r.clock.advance(by: SessionController.restOverHold)
        await r.settle { r.controller.rest.phase == .idle }
        #expect(r.controller.rest.phase == .idle)
    }

    @Test("A rest started during Rest over keeps running")
    func aNewRestSurvivesTheHold() async {
        let r = rig()
        endRest(r)
        await r.settle { r.clock.pendingSleeps >= 1 }
        r.controller.startRest(for: r.row)
        r.clock.advance(by: SessionController.restOverHold)
        await r.settle { r.clock.pendingSleeps == 0 }
        #expect(r.controller.rest.isRunning)
    }

    @Test("List keeps its banner until it is dismissed")
    func listKeepsItsBanner() async {
        let r = rig(.list)
        endRest(r)
        await r.settle()
        #expect(r.clock.pendingSleeps == 0)
        #expect(r.controller.rest.phase == .finished)
    }

    // MARK: what the pill shows

    typealias PillCase = (phase: RestTimer.Phase, keypad: Bool, exercises: Bool, allDone: Bool, state: RestPillState)
    /// Nonisolated: `@Test`'s arguments are read off the main actor.
    private nonisolated static let running = RestTimer.Phase.running(endsAt: .distantFuture, total: 75)

    @Test("The pill's state", arguments: [
        (RestTimer.Phase.idle, false, true, false, RestPillState.idle),
        (.idle, true, true, false, .hidden),
        (running, false, true, false, .running),
        (running, true, true, false, .running),
        (.finished, false, true, false, .finished),
        (.finished, true, true, false, .finished),
        (.idle, false, false, false, .hidden),
        (running, false, false, false, .hidden),
        (.idle, false, true, true, .hidden),
        (running, false, true, true, .hidden),
        (.finished, false, true, true, .hidden),
    ] as [PillCase])
    func pillState(_ c: PillCase) {
        #expect(RestPillState.resolve(c.phase, keypadOpen: c.keypad, hasExercises: c.exercises, isAllDone: c.allDone) == c.state)
    }

    // MARK: the sheet's length

    @Test("−15 and +15 step within the sheet's limits")
    func draftLimits() {
        var draft = RestDraft(seconds: 75)
        draft.adjust(by: 15)
        #expect(draft.seconds == 90)
        draft = RestDraft(seconds: 20)
        draft.adjust(by: -15)
        #expect(draft.seconds == 15)
        #expect(!draft.canDecrease)
        draft = RestDraft(seconds: 890)
        draft.adjust(by: 15)
        #expect(draft.seconds == 900)
        #expect(!draft.canIncrease)
    }

    @Test("An exercise that rests 0:00 can't start, and +15 gets it going")
    func draftFromZero() {
        var draft = RestDraft(seconds: 0)
        #expect(!draft.canStart)
        #expect(!draft.canDecrease)
        draft.adjust(by: 15)
        #expect(draft.seconds == 15)
        #expect(draft.canStart)
    }

    // MARK: the strip beside the keypad

    @Test("The strip gives way at 320 pt only, under 220 pt for the page, with the keypad up", arguments: [
        (SetTableColumns.compact, true, 202 + 76, 64, true),
        (.compact, true, 202 + 76, 0, true),
        (.compact, true, 220 + 76, 0, false),
        (.compact, false, 202 + 76, 64, false),
        (.regular, true, 202 + 76, 64, false),
    ] as [(SetTableColumns, Bool, CGFloat, CGFloat, Bool)])
    func stripGivesWay(_ c: (columns: SetTableColumns, keypad: Bool, height: CGFloat, pill: CGFloat, hides: Bool)) {
        #expect(FocusedSessionView.hidesStrip(columns: c.columns, keypadOpen: c.keypad, height: c.height, pillRow: c.pill) == c.hides)
    }

    // MARK: what VoiceOver hears

    @Test("The brief's value, built from its parts")
    func spokenValue() {
        #expect(RestSpeech.value(seconds: 114, next: "next Bench press set 2 of 4")
            == "1 minute 54 seconds left, next Bench press set 2 of 4")
        #expect(RestSpeech.value(seconds: 45, next: nil) == "45 seconds left")
        #expect(RestSpeech.duration(120) == "2 minutes")
        #expect(RestSpeech.duration(0) == "0 seconds")
    }

    @Test("The pill names the row the page shows, in steps of 5 s")
    func pillValue() throws {
        let r = rig()
        let c = r.controller
        c.startRest(for: r.row, seconds: 114)
        let end = try #require(c.rest.endsAt)
        let name = try #require(c.nextUp?.exercise.name)
        #expect(c.restPillValue(at: end.addingTimeInterval(-114))
            == "1 minute 55 seconds left, next \(name) set 1 of \(r.row.sets.count)")
    }
}
