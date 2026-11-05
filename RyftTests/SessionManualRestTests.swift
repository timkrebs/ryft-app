import Foundation
import SwiftUI
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
        #expect(SessionController.restOverHold == .seconds(1), "design.md §2.7: the pill says it for 1 s")
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
        // The woken task runs on the next turns; `pendingSleeps` is already 0, so wait them out.
        await r.settle()
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
        #expect(FocusedSessionView.hidesStrip(columns: c.columns, keypadOpen: c.keypad, height: c.height, pillRow: c.pill, typeSize: .large) == c.hides)
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

// MARK: - T3 acceptance: the decision tables and the seams (test-engineer)

extension SessionManualRestTests {
    /// The pill's other 13 rows of its 24: phase × keypad × exercises × all done, written out.
    @Test("The pill's state, the rest of the table", arguments: [
        (RestTimer.Phase.idle, false, false, true, RestPillState.hidden),
        (.idle, true, false, false, .hidden),
        (.idle, true, true, true, .hidden),
        (running, true, false, false, .hidden),
        (running, false, false, true, .hidden),
        (running, true, true, true, .hidden),
        (.finished, false, false, false, .hidden),
        (.finished, true, false, false, .hidden),
        (.finished, true, true, true, .hidden),
        (.idle, false, false, false, .hidden),
        (running, true, false, true, .hidden),
        (.finished, false, false, true, .hidden),
        (.idle, true, false, true, .hidden),
    ] as [PillCase])
    func pillStateRest(_ c: PillCase) {
        #expect(RestPillState.resolve(c.phase, keypadOpen: c.keypad, hasExercises: c.exercises, isAllDone: c.allDone) == c.state)
    }

    // MARK: the pill's state on a controller

    @Test("Rest over holds over the keypad for its moment, then the idle pill gives way to the keypad")
    func restOverOverTheKeypad() async throws {
        let r = rig()
        let c = r.controller
        let set = try #require(r.row.orderedSets.first)
        #expect(c.restPillState == .idle)
        c.startRest(for: r.row)
        c.edit(set, .kg)
        #expect(c.restPillState == .running, "a running rest shows over the keypad")
        c.adjustRest(by: -RestTimer.maxRest)
        #expect(c.restPillState == .finished, "and so does its end")
        await r.settle { r.clock.pendingSleeps >= 1 }
        r.clock.advance(by: SessionController.restOverHold - .milliseconds(1))
        await r.settle()
        #expect(c.restPillState == .finished, "still its moment")
        r.clock.advance(by: .milliseconds(1))
        await r.settle { c.rest.phase == .idle }
        #expect(c.restPillState == .hidden, "idle under the keypad: no pill")
        c.focus = nil
        #expect(c.restPillState == .idle, "the keypad closes: the idle pill is back")
    }

    @Test("No exercises or all sets done: hidden, and a set unchecked brings the pill back",
          arguments: [FocusedPreview.Scenario.empty, .allDone])
    func hiddenStates(_ scenario: FocusedPreview.Scenario) {
        let c = FocusedPreview.controller(scenario)
        defer { c.stop() }
        #expect(c.restPillState == .hidden)
        if scenario == .allDone, let ex = c.exercises.last, let set = ex.orderedSets.last {
            c.toggleCheck(set, in: ex)
            #expect(c.restPillState == .idle, "unchecking the last set: the workout is open again, and nothing rests")
            c.toggleCheck(set, in: ex)
            #expect(c.restPillState == .hidden, "checking it again: all done, and the last set starts no rest")
        }
    }

    @Test("The last set of the workout starts no rest and ends a running one: the pill goes")
    func lastSetEndsTheRest() throws {
        let r = rig()
        let c = r.controller
        for ex in c.exercises { r.complete(ex.orderedSets.count, of: ex) }
        let last = try #require(c.exercises.last?.orderedSets.last)
        last.completedAt = nil
        #expect(!c.isAllDone)
        c.startRest(for: r.row)
        #expect(c.restPillState == .running)
        c.toggleCheck(last, in: try #require(c.exercises.last))
        #expect(c.isAllDone)
        #expect(c.rest.phase == .idle, "nothing follows the last set")
        #expect(c.restPillState == .hidden)
        #expect(r.session.restEndsAt == nil)
    }

    enum LastOpenSet: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case deleted = "deleted", warmedUp = "made a warm-up", exerciseRemoved = "its exercise removed"
        var testDescription: String { rawValue }
    }

    /// Every set checked but `Curl`'s last, with a rest running on `Row`.
    private func restOnTheLastOpenSet(_ r: ReplaceRig) throws -> LocalSet {
        for ex in r.controller.exercises { r.complete(ex.orderedSets.count, of: ex) }
        let last = try #require(r.curl.orderedSets.last)
        last.completedAt = nil
        r.controller.startRest(for: r.row)
        #expect(r.controller.rest.isRunning)
        #expect(!r.controller.isAllDone)
        return last
    }

    private func take(_ last: LocalSet, _ path: LastOpenSet, _ r: ReplaceRig) {
        switch path {
        case .deleted: r.controller.delete(last, from: r.curl)
        case .warmedUp: r.controller.toggleWarmup(last)
        case .exerciseRemoved: r.controller.remove(r.curl)
        }
    }

    @Test("Focused: an edit that leaves nothing open ends the rest, or it would run on with no pill", arguments: LastOpenSet.allCases)
    func editEndsTheRest(_ path: LastOpenSet) throws {
        let r = rig()
        let c = r.controller
        take(try restOnTheLastOpenSet(r), path, r)
        #expect(c.isAllDone)
        #expect(c.rest.phase == .idle, "no pill, so no rest")
        #expect(c.restPillState == .hidden)
        #expect(r.session.restEndsAt == nil)
        #expect(r.session.restTotal == 0)
        #expect(c.restsEnded == 0, "ended, not run out: no Rest over and no haptic")
    }

    @Test("List: the same edits leave the rest alone, its bar stays", arguments: LastOpenSet.allCases)
    func listKeepsTheRest(_ path: LastOpenSet) throws {
        let r = rig(.list)
        take(try restOnTheLastOpenSet(r), path, r)
        #expect(r.controller.isAllDone)
        #expect(r.controller.rest.isRunning)
        #expect(r.session.restEndsAt != nil)
    }

    @Test("Focused: removing the last exercise ends the rest")
    func noExercisesEndTheRest() {
        let r = rig()
        let c = r.controller
        c.startRest(for: r.row)
        for ex in c.exercises { c.remove(ex) }
        #expect(c.exercises.isEmpty)
        #expect(c.rest.phase == .idle)
        #expect(r.session.restEndsAt == nil)
    }

    @Test("Focused: an edit that leaves a set open keeps the rest")
    func openSetKeepsTheRest() throws {
        let r = rig()
        let c = r.controller
        _ = try restOnTheLastOpenSet(r)
        c.delete(try #require(r.curl.orderedSets.first), from: r.curl)
        #expect(!c.isAllDone)
        #expect(c.rest.isRunning, "Curl's last set is still open")
        #expect(c.restPillState == .running)
    }

    @Test("The preview scenarios the shots use: running 1:54, and Rest over that holds")
    func scenarios() {
        let running = FocusedPreview.controller(.restRunning)
        defer { running.stop() }
        #expect(running.restPillState == .running)
        #expect(running.rest.total == 114)
        let over = FocusedPreview.controller(.restOver)
        defer { over.stop() }
        #expect(over.restPillState == .finished)
        #expect(over.restsEnded == 1)
    }

    // MARK: a manual rest and a rest after a check: what they share

    @Test("A rest from a check and a manual one reach the same places", arguments: [SessionLayout.list, .focused])
    func sameWayToTheSameSeams(_ layout: SessionLayout) {
        let viaCheck = rig(layout), manual = rig(layout)
        let set = viaCheck.row.orderedSets[0]
        set.reps = 8
        viaCheck.controller.toggleCheck(set, in: viaCheck.row)
        manual.controller.startRest(for: manual.row)

        for r in [viaCheck, manual] {
            let c = r.controller
            #expect(c.rest.isRunning)
            #expect(c.rest.total == TimeInterval(r.row.restSec))
            #expect(c.phase == .resting, "the workout's machine rests")
            #expect(r.session.restEndsAt == c.rest.endsAt, "persisted for a relaunch")
            #expect(r.session.restTotal == c.rest.total)
            #expect(c.lastActivityNext == c.nextLabel(), "the Live Activity is told what the screen says is next")
            #expect(c.restsEnded == 0)
        }
        #expect(viaCheck.controller.setsChecked == 1)
        #expect(manual.controller.setsChecked == 0)
    }

    @Test("A manual rest survives a relaunch: the rebuilt controller shows the pill running")
    func manualRestSurvivesARebuild() {
        let r = rig()
        r.controller.startRest(for: r.row, seconds: 300)
        let rebuilt = SessionController(session: r.session, sync: r.sync, liveActivity: nil, clock: r.clock, library: r.library,
                                        layout: .focused)
        defer { rebuilt.stop() }
        #expect(rebuilt.rest.isRunning)
        #expect(rebuilt.rest.total == 300)
        #expect(rebuilt.restPillState == .running)
    }

    @Test("A manual rest of 0:00 starts nothing; a long one is cut at 15:00; a second one replaces the first")
    func manualRestEdges() {
        let r = rig()
        let c = r.controller
        r.row.restSec = 0
        c.startRest(for: r.row)
        #expect(c.rest.phase == .idle)
        #expect(r.session.restEndsAt == nil)
        c.startRest(for: r.row, seconds: 5000)
        #expect(c.rest.total == RestTimer.maxRest)
        c.startRest(for: r.row, seconds: 75)
        #expect(c.rest.total == 75, "restarted, not added")
        #expect(r.session.restTotal == 75)
    }

    @Test("In a superset round a check hands over without a rest and ends a running one, as before")
    func supersetCheckStillSkips() throws {
        let r = rig()
        let c = r.controller
        #expect(r.x.supersetGroup != nil && r.x.supersetGroup == r.lateral.supersetGroup)
        c.startRest(for: r.row)
        let set = try #require(r.x.orderedSets.first { !$0.isCompleted })
        c.toggleCheck(set, in: r.x)
        #expect(c.rest.phase == .idle, "the partner follows straight away")
        #expect(c.phase == .active)
    }

    // MARK: skip, run out, restsEnded

    @Test("Skip ends a rest quietly; running out counts once and clears what was persisted")
    func skipAndRunOut() {
        let r = rig()
        let c = r.controller
        c.startRest(for: r.row)
        #expect(c.phase == .resting)
        c.skipRest()
        #expect(c.rest.phase == .idle)
        #expect(c.phase == .active)
        #expect(c.restsEnded == 0, "no haptic, no flash for a skip")
        #expect(r.session.restEndsAt == nil && r.session.restTotal == 0)

        c.startRest(for: r.row, seconds: 10)
        c.adjustRest(by: -RestTimer.step)
        #expect(c.rest.phase == .finished)
        #expect(c.restsEnded == 1)
        #expect(c.phase == .active)
        #expect(r.session.restEndsAt == nil && r.session.restTotal == 0)
        #expect(c.lastActivityNext == c.nextLabel())
    }

    @Test("A −15 that doesn't run out shortens the rest and keeps it running")
    func minusFifteenShortens() {
        let r = rig()
        let c = r.controller
        c.startRest(for: r.row, seconds: 60)
        c.adjustRest(by: -RestTimer.step)
        #expect(c.rest.isRunning)
        #expect(c.restsEnded == 0)
        #expect(c.rest.remaining(at: .now) < 46 && c.rest.remaining(at: .now) > 44)
    }

    // MARK: the hold

    @Test("A second Rest over restarts its moment; the first one's end doesn't cut it short")
    func holdRestarts() async {
        let r = rig()
        endRest(r)
        await r.settle { r.clock.pendingSleeps >= 1 }
        r.clock.advance(by: .milliseconds(600))
        endRest(r)
        await r.settle { r.clock.pendingSleeps >= 1 }
        r.clock.advance(by: .milliseconds(600))
        await r.settle()
        #expect(r.controller.rest.phase == .finished, "1.2 s after the first, 0.6 s after the second")
        r.clock.advance(by: .milliseconds(400))
        await r.settle { r.controller.rest.phase == .idle }
        #expect(r.controller.rest.phase == .idle)
    }

    @Test("Leaving the workout cancels the pending moment")
    func stopCancelsTheHold() async {
        let r = rig()
        endRest(r)
        await r.settle { r.clock.pendingSleeps >= 1 }
        r.controller.stop()
        await r.settle { r.clock.pendingSleeps == 0 }
        r.clock.advance(by: SessionController.restOverHold * 5)
        await r.settle()
        #expect(r.controller.rest.phase == .finished, "nothing woke the controller after stop")
    }

    @Test("A Skip during Rest over, then the moment passing, changes nothing")
    func skipDuringTheHold() async {
        let r = rig()
        endRest(r)
        await r.settle { r.clock.pendingSleeps >= 1 }
        r.controller.skipRest()
        r.clock.advance(by: SessionController.restOverHold)
        await r.settle()
        #expect(r.controller.rest.phase == .idle)
        #expect(r.controller.restsEnded == 1)
    }

    // MARK: the sheet's length

    typealias DraftCase = (start: Int, delta: Int, end: Int)

    @Test("−15 and +15 clamp to 0:15 and 15:00", arguments: [
        (75, 15, 90), (75, -15, 60), (15, -15, 15), (20, -15, 15), (30, -15, 15), (10, 15, 25), (890, 15, 900),
        (895, 15, 900), (900, 15, 900), (900, -15, 885), (0, 15, 15),
    ] as [DraftCase])
    func draftSteps(_ c: DraftCase) {
        var draft = RestDraft(seconds: c.start)
        draft.adjust(by: c.delta)
        #expect(draft.seconds == c.end)
    }

    @Test("The keys are off exactly at the ends, and Start from 0:15", arguments: [
        (0, false, true, false), (15, false, true, true), (16, true, true, true), (899, true, true, true),
        (900, true, false, true),
    ] as [(Int, Bool, Bool, Bool)])
    func draftKeys(_ c: (seconds: Int, down: Bool, up: Bool, start: Bool)) {
        let draft = RestDraft(seconds: c.seconds)
        #expect(draft.canDecrease == c.down)
        #expect(draft.canIncrease == c.up)
        #expect(draft.canStart == c.start)
        #expect(RestDraft.range == 15...900)
        #expect(RestDraft.step == 15)
    }

    @Test("The exercise's rest changes only through setRest: an edit, clamped to 0 to 15:00")
    func setRestIsTheOnlyWay() {
        let r = rig()
        let c = r.controller
        let rest = r.row.restSec
        c.startRest(for: r.row, seconds: 200)
        c.skipRest()
        #expect(r.row.restSec == rest)
        #expect(r.store.pendingOps().isEmpty, "a manual rest is no edit")
        c.setRest(180, for: r.row)
        #expect(r.row.restSec == 180)
        #expect(!r.store.pendingOps().isEmpty, "saving the length is one")
        c.setRest(5000, for: r.row)
        #expect(r.row.restSec == 900)
        c.setRest(-5, for: r.row)
        #expect(r.row.restSec == 0)
    }

    // MARK: sizes, the strip

    @Test("The pill is 48 pt, 56 from AX3; its row adds 8 above and below", arguments: DynamicTypeSize.allCases)
    func pillHeights(_ size: DynamicTypeSize) {
        let expected: CGFloat = size >= .accessibility3 ? 56 : 48
        #expect(RestPill.height(size) == expected)
        #expect(RestPill.rowHeight(size) == expected + 16)
    }

    @Test("The strip's edge: a page of 220 pt is enough, 219 is not; the pill row counts while it shows", arguments: [
        (SetTableColumns.compact, true, 360 as CGFloat, 64 as CGFloat, false),
        (.compact, true, 359, 64, true),
        (.compact, true, 296, 0, false),
        (.compact, true, 295, 0, true),
        (.compact, false, 100, 64, false),
        (.regular, true, 100, 64, false),
    ] as [(SetTableColumns, Bool, CGFloat, CGFloat, Bool)])
    func stripEdge(_ c: (columns: SetTableColumns, keypad: Bool, height: CGFloat, pill: CGFloat, hides: Bool)) {
        #expect(FocusedSessionView.hidesStrip(columns: c.columns, keypadOpen: c.keypad, height: c.height, pillRow: c.pill, typeSize: .large) == c.hides)
    }

    // MARK: what VoiceOver hears

    @Test("The spoken time: one unit at a time", arguments: [
        (0, "0 seconds"), (1, "1 second"), (45, "45 seconds"), (60, "1 minute"), (61, "1 minute 1 second"),
        (114, "1 minute 54 seconds"), (120, "2 minutes"), (900, "15 minutes"),
    ] as [(Int, String)])
    func spokenDuration(_ c: (Int, String)) {
        #expect(RestSpeech.duration(c.0) == c.1)
    }

    @Test("The idle pill says when it starts")
    func spokenIdle() {
        #expect(RestSpeech.idle(seconds: 75) == "Not running. Starts at 1 minute 15 seconds")
        let r = rig()
        let page = r.controller.pageExercise
        page?.restSec = 150
        #expect(r.controller.restPillValue(at: .now) == "Not running. Starts at 2 minutes 30 seconds", "the page's exercise: \(page?.name ?? "none")")
    }

    typealias StepCase = (remaining: Double, spoken: String)

    @Test("A running pill counts down in 5 s steps, rounded up", arguments: [
        (114, "1 minute 55 seconds left"), (115, "1 minute 55 seconds left"), (110.5, "1 minute 55 seconds left"),
        (110, "1 minute 50 seconds left"), (60, "1 minute left"), (0.2, "5 seconds left"), (0, "0 seconds left"),
    ] as [StepCase])
    func fiveSecondSteps(_ c: StepCase) throws {
        let r = rig()
        r.controller.startRest(for: r.row, seconds: 300)
        let end = try #require(r.controller.rest.endsAt)
        #expect(r.controller.restPillValue(at: end.addingTimeInterval(-c.remaining)).hasPrefix(c.spoken))
    }

    @Test("Rest over is what the pill says while it holds")
    func spokenFinished() {
        let r = rig()
        endRest(r)
        #expect(r.controller.restPillValue(at: .now) == "Rest over")
    }

    /// Review risk: the pill must name the row the page shows. A folded group isn't on screen; an open one is.
    @Test("The next set the pill names is the row on the page: a warm-up only while the group is open",
          arguments: [(FocusedPreview.Scenario.warmups, "set 1 of 4"), (.warmupsOpen, "warm-up 1 of 2")])
    func spokenWarmup(_ c: (scenario: FocusedPreview.Scenario, next: String)) throws {
        let controller = FocusedPreview.controller(c.scenario)
        defer { controller.stop() }
        let ex = try #require(controller.pageExercise)
        controller.startRest(for: ex, seconds: 114)
        let end = try #require(controller.rest.endsAt)
        #expect(controller.restPillValue(at: end.addingTimeInterval(-114)) == "1 minute 55 seconds left, next \(ex.name) \(c.next)")
    }

    @Test("Nothing next: only the time")
    func spokenWithoutNext() {
        #expect(RestSpeech.value(seconds: 60, next: nil) == "1 minute left")
        #expect(RestSpeech.value(seconds: 0, next: nil) == "0 seconds left")
    }
}
