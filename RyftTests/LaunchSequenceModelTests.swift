import Foundation
import SwiftUI
import Testing
@testable import Ryft

/// `LaunchSequenceModel` on a `TestClock` (ADR 0017, launch-design.md §5.5 and §10): the model keeps the process's one
/// sequence, records events at the clock's time and wakes at each deadline. Time moves only on `advance`, so nothing here
/// sleeps. The clock and the deadlines are compared around boundaries (`margin`), because a deadline is a `Date` and a
/// wake-up that lands a rounding step short of it would only re-arm the wait.
@MainActor
@Suite("Launch: the model on a test clock")
struct LaunchSequenceModelTests {
    private let clock = TestClock()
    /// Either side of a boundary: far above a `Date`'s rounding at this epoch (about 2e-7), far below any fade.
    private let margin = 0.001

    private func model(_ decision: LaunchDecision, signposts: Bool = false) -> LaunchSequenceModel {
        LaunchSequenceModel(decision: decision, clock: clock, signposts: signposts)
    }

    /// Lets the model's deadline task run: it registers its wait, or finishes after a wake-up.
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    private func advance(_ seconds: TimeInterval) async {
        clock.advance(by: .seconds(seconds))
        await settle()
    }

    /// A model that has been sent its first `.active`, and its deadline is waiting.
    private func playing(_ variant: LaunchSequence.Variant = .full) async -> LaunchSequenceModel {
        let model = model(.play(variant))
        model.send(.scene(.active))
        await settle()
        return model
    }

    // MARK: the whole run

    @Test func armedWaitsForTheFirstActiveWithNoTimerAndTheOverlayOnScreen() async {
        let model = model(.play(.full))
        #expect(model.phase == .armed)
        #expect(model.coversRoot && model.isOnScreen)
        #expect(!model.isAnimating, "armed draws the launch screen's colour and nothing that moves")
        #expect(model.ending == nil && !model.movesFocusToRoot)
        await settle()
        #expect(clock.pendingSleeps == 0, "no wait before the scene is active")
        // A cold launch passes through `.inactive`, and a tap before it plays does nothing.
        model.send(.scene(.inactive))
        model.send(.tap)
        #expect(model.phase == .armed && clock.pendingSleeps == 0)
    }

    @Test("Active, 5.2 s of playing, a 0.4 s fade, done: and nothing left waiting")
    func theFullRun() async {
        let model = await playing()
        #expect(model.phase == .playing)
        #expect(model.coversRoot && model.isOnScreen && model.isAnimating)
        #expect(model.ending == nil)
        #expect(clock.pendingSleeps == 1, "one wait, for the end of the timeline")

        await advance(5.2 - margin)
        #expect(model.phase == .playing && model.coversRoot, "the root stays covered until the hand-off starts")
        #expect(clock.pendingSleeps == 1)

        await advance(2 * margin)
        #expect(model.phase == .handingOff)
        #expect(!model.coversRoot, "the root is uncovered the instant the fade starts")
        #expect(model.isOnScreen && model.isAnimating)
        #expect(model.ending == .finished && model.movesFocusToRoot)
        #expect(clock.pendingSleeps == 1, "one wait, for the end of the fade")

        await advance(0.4 - 2 * margin)
        #expect(model.phase == .handingOff)
        await advance(3 * margin)
        #expect(model.phase == .done)
        #expect(!model.isOnScreen && !model.isAnimating && !model.coversRoot)
        #expect(model.ending == .finished)
        #expect(clock.pendingSleeps == 0, "after done nothing waits and nothing animates")
    }

    @Test("Reduced: 1.0 s, then a 0.25 s fade, 1.25 s in all")
    func theReducedRun() async {
        let model = await playing(.reduced)
        #expect(model.phase == .playing && model.isAnimating)
        await advance(1.0 - margin)
        #expect(model.phase == .playing)
        await advance(2 * margin)
        #expect(model.phase == .handingOff && !model.coversRoot)
        await advance(0.25 - 2 * margin)
        #expect(model.phase == .handingOff)
        await advance(3 * margin)
        #expect(model.phase == .done && !model.isOnScreen && !model.isAnimating)
        #expect(clock.pendingSleeps == 0)
    }

    @Test("A tap at 1.0 s hands off at once and is done at 1.25 s", arguments: [LaunchSequence.Variant.full, .reduced])
    func aTapAtOneSecond(_ variant: LaunchSequence.Variant) async {
        // Reduced is already handing off at 1.0 s: tap a moment before.
        let tapAt = variant == .full ? 1.0 : 0.5
        let model = await playing(variant)
        await advance(tapAt)
        #expect(model.phase == .playing && model.coversRoot)
        model.send(.tap)
        #expect(model.phase == .handingOff, "the tap acts on the spot, not at the next wake-up")
        #expect(!model.coversRoot && model.isOnScreen && model.isAnimating)
        #expect(model.ending == .tapped && model.movesFocusToRoot)
        await settle()
        #expect(clock.pendingSleeps == 1, "the tap replaced the timeline's wait; it did not add one")

        await advance(0.25 - margin)
        #expect(model.phase == .handingOff)
        await advance(2 * margin)
        #expect(model.phase == .done)
        #expect(!model.isOnScreen && !model.isAnimating)
        #expect(model.ending == .tapped, "the ending outlives the fade")
        #expect(clock.pendingSleeps == 0)
    }

    @Test func tapsDuringTheFadeReachTheRootAndChangeNothing() async {
        let model = await playing()
        await advance(2)
        model.send(.tap)
        let before = model.sequence
        model.send(.tap)
        model.send(.scene(.inactive))
        model.send(.interrupted(.presentation))
        #expect(model.sequence == before)
        #expect(model.phase == .handingOff && model.ending == .tapped)
        await settle()
        #expect(clock.pendingSleeps == 1)
    }

    // MARK: once it is over, it is over

    @Test("A second active after done changes nothing: a re-created scene never replays", arguments: [
        LaunchSequence.Variant.full, .reduced,
    ])
    func noReplay(_ variant: LaunchSequence.Variant) async {
        let model = await playing(variant)
        await advance(10)
        #expect(model.phase == .done)
        let before = model.sequence
        for event: LaunchSequence.Event in [.scene(.active), .scene(.inactive), .scene(.background), .scene(.active), .tap,
                                            .interrupted(.presentation), .interrupted(.purposeLaunch)] {
            model.send(event)
            await settle()
        }
        #expect(model.sequence == before)
        #expect(model.phase == .done && !model.isOnScreen && !model.isAnimating && !model.coversRoot)
        #expect(clock.pendingSleeps == 0, "no event starts a timer again")
    }

    @Test func aSkipDecisionNeverShowsAnythingAndNeverWaits() async {
        let model = model(.skip(.harness))
        #expect(model.phase == .skipped)
        #expect(!model.coversRoot && !model.isOnScreen && !model.isAnimating)
        #expect(model.ending == .skipped(.harness))
        for event: LaunchSequence.Event in [.scene(.active), .scene(.inactive), .scene(.active), .tap,
                                            .interrupted(.presentation)] {
            model.send(event)
        }
        await settle()
        #expect(model.phase == .skipped && !model.isOnScreen)
        #expect(clock.pendingSleeps == 0)
    }

    // MARK: the 5 s window

    @Test("The first active within five seconds plays, after that it is a late background launch", arguments: [
        (4.9, LaunchSequence.Phase.playing, LaunchSequence.Ending?.none), (5.1, .skipped, .skipped(.lateActivation)),
    ])
    func theColdStartWindow(_ delay: TimeInterval, _ phase: LaunchSequence.Phase, _ ending: LaunchSequence.Ending?) async {
        let model = model(.play(.full))
        await advance(delay)
        model.send(.scene(.active))
        await settle()
        #expect(model.phase == phase)
        #expect(model.ending == ending)
        #expect(model.coversRoot == (phase == .playing))
        if phase == .skipped {
            #expect(!model.isOnScreen && clock.pendingSleeps == 0)
            #expect(model.movesFocusToRoot, "the root was hidden while armed: focus goes to it")
        }
    }

    // MARK: interruptions

    @Test func aPurposeLaunchWhileArmedSkipsAndVoiceOverGoesToTheRoot() async {
        let model = model(.play(.full))
        model.send(.interrupted(.purposeLaunch))
        #expect(model.phase == .skipped && !model.isOnScreen && !model.coversRoot)
        #expect(model.ending == .skipped(.purposeLaunch))
        #expect(model.movesFocusToRoot)
        model.send(.scene(.active))
        await settle()
        #expect(model.phase == .skipped, "nothing plays after it")
        #expect(clock.pendingSleeps == 0)
    }

    @Test func aPresentationWhileArmedSkipsAndItsSheetKeepsTheFocus() async {
        let model = model(.play(.full))
        model.send(.interrupted(.presentation))
        #expect(model.phase == .skipped && !model.isOnScreen)
        #expect(model.ending == .skipped(.presentation))
        #expect(!model.movesFocusToRoot)
    }

    @Test func backgroundedWhileArmedSkips() async {
        let model = model(.play(.full))
        model.send(.scene(.background))
        #expect(model.phase == .skipped && !model.isOnScreen)
        #expect(model.ending == .skipped(.backgrounded) && !model.movesFocusToRoot)
        model.send(.scene(.active))
        await settle()
        #expect(model.phase == .skipped && clock.pendingSleeps == 0)
    }

    private struct Case: CustomTestStringConvertible, Sendable {
        let event: LaunchSequence.Event
        let ending: LaunchSequence.Ending
        let movesFocus: Bool
        var testDescription: String { "\(event)" }
    }

    @Test("While playing, system UI and a presentation hand off quickly; only a purpose launch moves the focus", arguments: [
        Case(event: .scene(.inactive), ending: .systemUI, movesFocus: false),
        Case(event: .interrupted(.presentation), ending: .interrupted(.presentation), movesFocus: false),
        Case(event: .interrupted(.purposeLaunch), ending: .interrupted(.purposeLaunch), movesFocus: true),
        Case(event: .tap, ending: .tapped, movesFocus: true),
    ])
    private func anInterruptionWhilePlaying(_ test: Case) async {
        let model = await playing()
        await advance(2)
        model.send(test.event)
        #expect(model.phase == .handingOff && !model.coversRoot && model.isOnScreen)
        #expect(model.ending == test.ending)
        #expect(model.movesFocusToRoot == test.movesFocus)
        await advance(0.25 + margin)
        #expect(model.phase == .done && !model.isOnScreen && !model.isAnimating)
        #expect(model.ending == test.ending)
        #expect(clock.pendingSleeps == 0)
    }

    @Test("Backgrounded while playing: done at once, nothing waits, the focus stays with whatever is next",
          arguments: [LaunchSequence.Variant.full, .reduced])
    func backgroundedWhilePlaying(_ variant: LaunchSequence.Variant) async {
        let model = await playing(variant)
        await advance(0.3)
        model.send(.scene(.background))
        #expect(model.phase == .done)
        #expect(!model.coversRoot && !model.isOnScreen && !model.isAnimating)
        #expect(model.ending == .backgrounded && !model.movesFocusToRoot)
        await settle()
        #expect(clock.pendingSleeps == 0)
    }

    @Test func backgroundedDuringTheFadeIsDoneAtOnceAndKeepsItsEnding() async {
        let model = await playing()
        await advance(1)
        model.send(.tap)
        await advance(0.1)
        model.send(.scene(.background))
        #expect(model.phase == .done && !model.isOnScreen)
        #expect(model.ending == .tapped)
        await settle()
        #expect(clock.pendingSleeps == 0)
    }

    // MARK: the clock leads the model

    /// The model measures the wait when its task runs, so a clock that moved on in between ends it at once.
    @Test func aClockThatMovedOnBeforeTheWaitBeganEndsItAtOnce() async {
        let model = model(.play(.full))
        model.send(.scene(.active))
        // Before the deadline task has run, the clock jumps past the end of the timeline (5.2 s), not of the fade (5.6 s).
        clock.advance(by: .seconds(5.4))
        await settle()
        #expect(model.phase == .handingOff)
        await advance(0.3)
        #expect(model.phase == .done)
        #expect(clock.pendingSleeps == 0)
    }

    // MARK: signposts

    @Test func withSignpostsOnTheRunIsTheSame() async {
        let model = model(.play(.full), signposts: true)
        model.send(.scene(.active))
        await settle()
        await advance(5.2 + margin)
        #expect(model.phase == .handingOff)
        await advance(0.4 + margin)
        #expect(model.phase == .done)
        #expect(clock.pendingSleeps == 0)
    }

    // MARK: the environment

    @Test func theEnvironmentDefaultsLeaveTheRootAloneAndTheInterruptionIsANoOp() {
        let values = EnvironmentValues()
        #expect(values.launchCoversRoot == false)
        values.launchInterrupt(.presentation)
    }

    @Test func anInterruptionActionReachesItsClosure() {
        final class Box: @unchecked Sendable { var seen: [LaunchInterruption] = [] }
        let box = Box()
        let action = LaunchInterruptAction { box.seen.append($0) }
        action(.presentation)
        action(.purposeLaunch)
        #expect(box.seen == [.presentation, .purposeLaunch])
    }
}
