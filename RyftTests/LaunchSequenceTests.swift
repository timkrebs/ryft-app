import Foundation
import SwiftUI
import Testing
@testable import Ryft

/// The launch sequence's phases over time (ADR 0017, launch-design.md §5): the pure value, driven by dates. The play
/// rules are `LaunchPolicyTests`, the clock-driven model is `LaunchSequenceModelTests`.
@Suite("Launch: phases and events")
struct LaunchSequenceTests {
    private let created = Date(timeIntervalSince1970: 1_792_600_000)

    private func at(_ seconds: TimeInterval) -> Date { created.addingTimeInterval(seconds) }
    /// Dates carry about a microsecond of rounding here: boundaries are checked this far either side.
    private let e = 0.001

    private func near(_ date: Date?, _ seconds: TimeInterval) -> Bool {
        date.map { abs($0.timeIntervalSince(at(seconds))) < e } ?? false
    }

    /// Active at `start`, and the overlay's first frame at the same instant: the timeline runs from `start`.
    private func playing(_ variant: LaunchSequence.Variant = .full, at start: TimeInterval = 0.1) -> LaunchSequence {
        var sequence = LaunchSequence(decision: .play(variant), createdAt: created)
        sequence.send(.scene(.active), at: at(start))
        sequence.send(.firstFrame, at: at(start))
        return sequence
    }

    // MARK: phases

    @Test func armedUntilTheFirstActiveThenPlaysHandsOffAndEnds() {
        var sequence = LaunchSequence(decision: .play(.full), createdAt: created)
        // A cold launch passes through `.inactive` while armed.
        sequence.send(.scene(.inactive), at: at(0.05))
        #expect(sequence.phase(at: at(0.05)) == .armed)
        #expect(sequence.covers(at: at(0.05)))
        #expect(sequence.nextChange(after: at(0.05)) == nil)
        sequence.send(.scene(.active), at: at(0.1))
        sequence.send(.firstFrame, at: at(0.1))
        #expect(sequence.phase(at: at(0.1)) == .playing)
        #expect(sequence.phase(at: at(5.3 - e)) == .playing)
        #expect(near(sequence.nextChange(after: at(1)), 5.3))
        // 5.2 s after the start, then the 0.4 s fade.
        #expect(sequence.phase(at: at(5.3 + e)) == .handingOff)
        #expect(!sequence.covers(at: at(5.3 + e)))
        #expect(sequence.ending(at: at(5.3 + e)) == .finished)
        #expect(near(sequence.nextChange(after: at(5.3 + e)), 5.7))
        #expect(sequence.phase(at: at(5.7 - e)) == .handingOff)
        #expect(sequence.phase(at: at(5.7 + e)) == .done)
        #expect(sequence.nextChange(after: at(5.7 + e)) == nil)
    }

    @Test func aTapHandsOffAtOnceWithTheQuickFade() {
        var sequence = playing()
        sequence.send(.tap, at: at(1.1))
        #expect(sequence.phase(at: at(1.1)) == .handingOff)
        #expect(sequence.ending(at: at(1.1)) == .tapped)
        #expect(sequence.phase(at: at(1.35 - e)) == .handingOff)
        #expect(sequence.phase(at: at(1.35 + e)) == .done)
        // Taps reach the root while it hands off, and terminal phases ignore every event.
        sequence.send(.tap, at: at(1.2))
        sequence.send(.scene(.active), at: at(2))
        #expect(sequence.phase(at: at(2)) == .done)
        #expect(sequence.ending(at: at(2)) == .tapped)
    }

    @Test func progressRunsOnThroughTheHandOff() {
        var sequence = playing(at: 0)
        #expect(abs(sequence.progress(at: at(2.6)) - 0.5) < 1e-6)
        sequence.send(.tap, at: at(2.6))
        #expect(sequence.progress(at: at(2.7)) > 0.51)
        #expect(sequence.handOff(at: at(2.6)) < 1e-3)
        #expect(sequence.handOff(at: at(2.85 + e)) == 1)
        #expect(sequence.progress(at: at(9)) == 1)
        #expect(LaunchSequence(decision: .play(.full), createdAt: created).progress(at: at(3)) == 0)
    }

    @Test func theReducedVariantHoldsTheLastFrameForOneSecond() {
        let sequence = playing(.reduced, at: 0)
        #expect(sequence.frameProgress(at: at(0)) == 1)
        #expect(sequence.contentOpacity(at: at(0)) < 1e-3)
        #expect(sequence.contentOpacity(at: at(0.25 + e)) == 1)
        #expect(sequence.phase(at: at(1 - e)) == .playing)
        #expect(sequence.phase(at: at(1 + e)) == .handingOff)
        #expect(sequence.phase(at: at(1.25 - e)) == .handingOff)
        #expect(sequence.phase(at: at(1.25 + e)) == .done)
    }

    @Test func systemUIAndPresentationsHandOffTheBackgroundEndsAtOnce() {
        var inactive = playing()
        inactive.send(.scene(.inactive), at: at(2))
        #expect(inactive.ending(at: at(2)) == .systemUI)
        #expect(inactive.phase(at: at(2.25 + e)) == .done)

        var presented = playing()
        presented.send(.interrupted(.presentation), at: at(2))
        #expect(presented.ending(at: at(2)) == .interrupted(.presentation))

        var backgrounded = playing()
        backgrounded.send(.scene(.background), at: at(2))
        #expect(backgrounded.phase(at: at(2)) == .done)
        #expect(backgrounded.ending(at: at(2)) == .backgrounded)
    }

    @Test func armedSkipsOnTheBackgroundAPurposeOrAPresentation() {
        let cases: [(LaunchSequence.Event, LaunchSkip)] = [(.scene(.background), .backgrounded),
                                                           (.interrupted(.purposeLaunch), .purposeLaunch),
                                                           (.interrupted(.presentation), .presentation)]
        for (event, reason) in cases {
            var sequence = LaunchSequence(decision: .play(.full), createdAt: created)
            sequence.send(event, at: at(0.1))
            #expect(sequence.phase(at: at(0.1)) == .skipped, "\(event)")
            #expect(sequence.ending(at: at(0.1)) == .skipped(reason))
            sequence.send(.scene(.active), at: at(0.2))
            #expect(sequence.phase(at: at(0.2)) == .skipped, "nothing plays after \(event)")
        }
    }

    @Test func theFirstActiveMustComeWithinFiveSeconds() {
        #expect(playing(at: 4.9).phase(at: at(5)) == .playing)
        let late = playing(at: 5.1)
        #expect(late.phase(at: at(5.1)) == .skipped)
        #expect(late.ending(at: at(5.1)) == .skipped(.lateActivation))
    }

    @Test func aSkipDecisionNeverCovers() {
        var sequence = LaunchSequence(decision: .skip(.harness), createdAt: created)
        #expect(sequence.phase(at: at(0)) == .skipped)
        #expect(!sequence.covers(at: at(0)))
        sequence.send(.scene(.active), at: at(0.1))
        #expect(sequence.phase(at: at(0.1)) == .skipped)
        #expect(sequence.nextChange(after: at(0.1)) == nil)
        #expect(sequence.ending(at: at(0.1)) == .skipped(.harness))
    }

    // MARK: timing constants

    @Test func theTimingsAreTheDocumentedOnes() {
        let full = LaunchSequence.Timing.full, reduced = LaunchSequence.Timing.reduced
        #expect(full == LaunchSequence.Timing(duration: 5.2, handOff: 0.4, quickHandOff: 0.25, fadeIn: 0))
        #expect(reduced == LaunchSequence.Timing(duration: 1.0, handOff: 0.25, quickHandOff: 0.25, fadeIn: 0.25))
        #expect(LaunchSequence.Timing.coldStartWindow == 5)
        #expect(LaunchSequence(decision: .play(.full), createdAt: created).timing == full)
        #expect(LaunchSequence(decision: .play(.reduced), createdAt: created).timing == reduced)
        #expect(LaunchSequence.Phase.allCases == [.armed, .playing, .handingOff, .done, .skipped])
    }

    // MARK: phases at the timeline's boundaries, both variants

    private struct Moment: CustomTestStringConvertible, Sendable {
        let variant: LaunchSequence.Variant
        let seconds: TimeInterval
        let phase: LaunchSequence.Phase
        var testDescription: String { "\(variant) \(seconds) s after the start: \(phase)" }
    }

    private static let moments: [Moment] = [
        Moment(variant: .full, seconds: 0, phase: .playing),
        Moment(variant: .full, seconds: 2.6, phase: .playing),
        Moment(variant: .full, seconds: 5.2 - 0.001, phase: .playing),
        Moment(variant: .full, seconds: 5.2 + 0.001, phase: .handingOff),
        Moment(variant: .full, seconds: 5.4, phase: .handingOff),
        Moment(variant: .full, seconds: 5.6 - 0.001, phase: .handingOff),
        Moment(variant: .full, seconds: 5.6 + 0.001, phase: .done),
        Moment(variant: .full, seconds: 3_600, phase: .done),
        Moment(variant: .reduced, seconds: 0, phase: .playing),
        Moment(variant: .reduced, seconds: 0.5, phase: .playing),
        Moment(variant: .reduced, seconds: 1.0 - 0.001, phase: .playing),
        Moment(variant: .reduced, seconds: 1.0 + 0.001, phase: .handingOff),
        Moment(variant: .reduced, seconds: 1.25 - 0.001, phase: .handingOff),
        Moment(variant: .reduced, seconds: 1.25 + 0.001, phase: .done),
        Moment(variant: .reduced, seconds: 3_600, phase: .done),
    ]

    @Test("Phase at the timeline's boundaries", arguments: moments)
    private func phaseAtTheBoundaries(_ moment: Moment) {
        let sequence = playing(moment.variant, at: 0)
        #expect(sequence.phase(at: at(moment.seconds)) == moment.phase)
        #expect(sequence.covers(at: at(moment.seconds)) == (moment.phase == .playing))
    }

    /// The boundary itself belongs to the later phase: the fade starts at the deadline, the overlay is gone at its end.
    @Test("The boundary instant belongs to the later phase", arguments: [LaunchSequence.Variant.full, .reduced])
    private func theBoundaryInstants(_ variant: LaunchSequence.Variant) throws {
        let sequence = playing(variant, at: 0)
        let handOff = try #require(sequence.handOffStart), done = try #require(sequence.doneAt)
        #expect(abs(handOff.timeIntervalSince(at(0)) - sequence.timing.duration) < 1e-6)
        #expect(abs(done.timeIntervalSince(handOff) - sequence.timing.handOff) < 1e-6)
        #expect(sequence.phase(at: at(0)) == .playing)
        #expect(sequence.phase(at: handOff) == .handingOff)
        #expect(!sequence.covers(at: handOff))
        #expect(sequence.phase(at: done) == .done)
        #expect(sequence.phase(at: handOff.addingTimeInterval(-1e-6)) == .playing)
        #expect(sequence.phase(at: done.addingTimeInterval(-1e-6)) == .handingOff)
    }

    @Test func beforeTheStartThereIsNothingToSeeOrHandOff() {
        for variant in [LaunchSequence.Variant.full, .reduced] {
            let sequence = LaunchSequence(decision: .play(variant), createdAt: created)
            #expect(sequence.phase(at: at(2)) == .armed)
            #expect(sequence.progress(at: at(2)) == 0)
            #expect(sequence.handOff(at: at(2)) == 0)
            #expect(sequence.contentOpacity(at: at(2)) == 0)
            #expect(sequence.handOffStart == nil && sequence.doneAt == nil)
            #expect(sequence.ending(at: at(2)) == nil)
            #expect(sequence.covers(at: at(2)))
        }
    }

    @Test func theFirstActiveAtExactlyFiveSecondsStillPlays() {
        #expect(playing(at: 5.0).phase(at: at(5.0)) == .playing)
        #expect(playing(at: 5.0 + 0.001).phase(at: at(5.001)) == .skipped)
    }

    @Test func aSecondActiveWhilePlayingDoesNotRestartTheClock() {
        var sequence = playing(at: 0.1)
        sequence.send(.scene(.active), at: at(3))
        #expect(sequence.startedAt == at(0.1))
        #expect(near(sequence.handOffStart, 5.3))
    }

    // MARK: the first frame (review PR 3 row 18)

    /// The scene is active about 0.15 s before the overlay draws (Debug). Counted from `.active`, the first frame was t 0.03
    /// at 77 % group opacity: a pop, where the launch screen should fade into the mark. The timeline starts at the first frame.
    @Test func theTimelineStartsAtTheFirstFrameNotAtActive() {
        var sequence = LaunchSequence(decision: .play(.full), createdAt: created)
        sequence.send(.scene(.active), at: at(0.1))
        // Waiting for it: covered, playing (the overlay is up), and every frame is t = 0.
        #expect(sequence.phase(at: at(0.2)) == .playing && sequence.covers(at: at(0.2)))
        #expect(sequence.progress(at: at(0.2)) == 0 && sequence.frameProgress(at: at(0.25)) == 0)
        sequence.send(.firstFrame, at: at(0.25))
        #expect(sequence.activatedAt == at(0.1) && sequence.firstFrameAt == at(0.25) && sequence.startedAt == at(0.25))
        #expect(sequence.progress(at: at(0.25)) == 0)
        let first = LaunchFrame(t: sequence.frameProgress(at: at(0.25)), palette: LaunchFrameTests.palette)
        #expect(first.groupOpacity == 0, "the mark fades in from nothing")
        #expect(abs(sequence.progress(at: at(0.25 + 2.6)) - 0.5) < 1e-6)
        // The natural end follows: 5.2 s after the first frame, then the 0.4 s fade.
        #expect(near(sequence.handOffStart, 5.45) && near(sequence.doneAt, 5.85))
        #expect(sequence.phase(at: at(5.45 - e)) == .playing && sequence.phase(at: at(5.45 + e)) == .handingOff)
        #expect(sequence.phase(at: at(5.85 + e)) == .done)
    }

    @Test func onlyTheFirstFrameCounts() {
        var sequence = playing(at: 0.1)
        sequence.send(.firstFrame, at: at(0.5))
        #expect(sequence.startedAt == at(0.1) && near(sequence.handOffStart, 5.3))
    }

    @Test("Without a first frame the timeline starts a second after active: the overlay never holds the root")
    func withoutAFirstFrameTheTimelineStartsAfterTheWindow() {
        #expect(LaunchSequence.Timing.firstFrameWindow == 1)
        var sequence = LaunchSequence(decision: .play(.full), createdAt: created)
        sequence.send(.scene(.active), at: at(0.1))
        #expect(near(sequence.startedAt, 1.1))
        #expect(near(sequence.handOffStart, 6.3) && near(sequence.doneAt, 6.7))
        #expect(sequence.progress(at: at(1.1)) == 0 && abs(sequence.progress(at: at(1.1 + 2.6)) - 0.5) < 1e-6)
        // A first frame after the window starts nothing.
        sequence.send(.firstFrame, at: at(1.1 + e))
        #expect(sequence.firstFrameAt == nil && near(sequence.handOffStart, 6.3))
        // One just inside it still starts it.
        var onTime = LaunchSequence(decision: .play(.full), createdAt: created)
        onTime.send(.scene(.active), at: at(0.1))
        onTime.send(.firstFrame, at: at(1.1 - e))
        #expect(onTime.firstFrameAt == at(1.1 - e) && near(onTime.handOffStart, 6.3 - e))
    }

    @Test func aFirstFrameAfterATapStartsNothing() {
        var sequence = LaunchSequence(decision: .play(.full), createdAt: created)
        sequence.send(.scene(.active), at: at(0.1))
        sequence.send(.tap, at: at(0.15))
        sequence.send(.firstFrame, at: at(0.2))
        #expect(sequence.firstFrameAt == nil)
        #expect(sequence.ending(at: at(0.2)) == .tapped && near(sequence.doneAt, 0.4))
        #expect(sequence.frameProgress(at: at(0.3)) == 0, "the fade shows the launch screen's t = 0, nothing moves")
    }

    @Test func theReducedFadeInStartsAtTheFirstFrame() {
        var sequence = LaunchSequence(decision: .play(.reduced), createdAt: created)
        sequence.send(.scene(.active), at: at(0.1))
        #expect(sequence.contentOpacity(at: at(0.3)) == 0, "nothing before the first frame")
        sequence.send(.firstFrame, at: at(0.3))
        #expect(sequence.contentOpacity(at: at(0.3)) == 0)
        #expect(sequence.contentOpacity(at: at(0.55 + e)) == 1)
        #expect(near(sequence.handOffStart, 1.3) && near(sequence.doneAt, 1.55))
    }

    /// The 5 s window still runs from init to the first `.active`: a first frame that comes after it plays on.
    @Test func theColdStartWindowEndsAtActiveNotAtTheFirstFrame() {
        var sequence = LaunchSequence(decision: .play(.full), createdAt: created)
        sequence.send(.scene(.active), at: at(4.9))
        sequence.send(.firstFrame, at: at(5.5))
        #expect(sequence.phase(at: at(5.5)) == .playing && sequence.startedAt == at(5.5))
        #expect(near(sequence.handOffStart, 10.7))
    }

    // MARK: the hand-off

    @Test("The natural end fades for 0.4 s, eased out", arguments: [0.0, 0.1, 0.2, 0.3, 0.4])
    private func theNaturalEndsFade(_ elapsed: Double) throws {
        let sequence = playing(at: 0)
        let handOff = try #require(sequence.handOffStart)
        let expected = LaunchFrame.Easing.easeOut(elapsed / 0.4)
        #expect(abs(sequence.handOff(at: handOff.addingTimeInterval(elapsed)) - expected) < 1e-5)
        #expect(sequence.handOff(at: handOff.addingTimeInterval(-0.5)) == 0, "no fade before the hand-off")
    }

    @Test("A tap fades for 0.25 s, eased out, from the tap", arguments: [LaunchSequence.Variant.full, .reduced])
    private func aTapsFade(_ variant: LaunchSequence.Variant) {
        var sequence = playing(variant, at: 0)
        sequence.send(.tap, at: at(0.6))
        for elapsed in [0.0, 0.0625, 0.125, 0.1875, 0.25] {
            let expected = LaunchFrame.Easing.easeOut(elapsed / 0.25)
            #expect(abs(sequence.handOff(at: at(0.6 + elapsed)) - expected) < 1e-5, "\(variant) +\(elapsed)")
        }
        #expect(sequence.handOff(at: at(0.59)) == 0)
        #expect(sequence.handOff(at: at(60)) == 1)
    }

    @Test func theFadeNeverGoesBackwardsNorLeavesZeroToOne() {
        for variant in [LaunchSequence.Variant.full, .reduced] {
            var sequence = playing(variant, at: 0)
            sequence.send(.tap, at: at(0.4))
            var last = 0.0
            for step in 0...200 {
                let value = sequence.handOff(at: at(0.4 + Double(step) * 0.002))
                #expect(value >= last && value >= 0 && value <= 1, "\(variant) step \(step)")
                last = value
            }
            #expect(last == 1)
        }
    }

    /// Progress is the timeline's, not the fade's: a tap never freezes a frame, and the natural end clamps at 1.
    @Test func theFrameKeepsMovingThroughTheHandOffAndClampsAtTheEnd() {
        var sequence = playing(at: 0)
        #expect(sequence.frameProgress(at: at(1.3)) == sequence.progress(at: at(1.3)))
        sequence.send(.tap, at: at(1.3))
        #expect(abs(sequence.frameProgress(at: at(1.4)) - 1.4 / 5.2) < 1e-6)
        #expect(sequence.frameProgress(at: at(100)) == 1)
        #expect(sequence.frameProgress(at: at(-1)) == 0)
    }

    // MARK: the reduced variant (Reduce Motion, VoiceOver, Low Power Mode)

    @Test func theReducedVariantShowsTheLastFrameThroughout() {
        var sequence = playing(.reduced, at: 0)
        for seconds in [-1.0, 0, 0.1, 0.25, 0.9, 1.0, 1.1, 1.25, 10] {
            #expect(sequence.frameProgress(at: at(seconds)) == 1, "\(seconds) s")
        }
        // Armed too: the frame is the last one before it is ever shown.
        #expect(LaunchSequence(decision: .play(.reduced), createdAt: created).frameProgress(at: at(0)) == 1)
        sequence.send(.tap, at: at(0.5))
        #expect(sequence.frameProgress(at: at(0.6)) == 1, "a tap freezes nothing: there is nothing moving")
    }

    @Test func theReducedFrameCarriesTheMarkTheWordmarkAndTheTagline() {
        let palette = LaunchFrameTests.palette
        let sequence = playing(.reduced, at: 0)
        let frame = LaunchFrame(t: sequence.frameProgress(at: at(0.3)), palette: palette)
        #expect(frame == LaunchFrame(t: 1, palette: palette))
        // L11: the tagline is part of the reduced frame.
        #expect(frame.wordmarkOpacity == 1 && frame.taglineOpacity == 1 && frame.groupOpacity == 1)
        #expect(frame.trackOpacity == 0)
    }

    @Test func theReducedVariantTotalsAtMostAQuarterPastASecond() {
        let reduced = LaunchSequence.Timing.reduced
        #expect(reduced.duration == 1.0 && reduced.handOff == 0.25)
        #expect(reduced.duration + reduced.handOff <= 1.25 + 1e-9)
        #expect(reduced.quickHandOff <= reduced.handOff)
        let sequence = playing(.reduced, at: 0)
        #expect(sequence.doneAt?.timeIntervalSince(at(0)) ?? .infinity <= 1.25 + 1e-6)
    }

    @Test func theReducedFrameFadesInOverAQuarterSecondThenHolds() {
        let sequence = playing(.reduced, at: 0)
        var last = -1.0
        for step in 0...125 {
            let value = sequence.contentOpacity(at: at(Double(step) * 0.002))
            #expect(value >= last && value >= 0 && value <= 1, "step \(step)")
            last = value
        }
        #expect(sequence.contentOpacity(at: at(0)) == 0)
        #expect(abs(sequence.contentOpacity(at: at(0.125)) - LaunchFrame.Easing.easeOut(0.5)) < 1e-6)
        #expect(sequence.contentOpacity(at: at(0.25)) == 1)
        #expect(sequence.contentOpacity(at: at(0.9)) == 1, "held")
    }

    @Test func theFullVariantHasNoFadeInOfItsOwn() {
        let sequence = playing(.full, at: 0)
        for seconds in [0.0, 0.01, 2, 5] { #expect(sequence.contentOpacity(at: at(seconds)) == 1) }
    }

    // MARK: events: what ends it, how, and what each ending does for VoiceOver

    private struct Interruption: CustomTestStringConvertible, Sendable {
        let event: LaunchSequence.Event
        let ending: LaunchSequence.Ending
        var testDescription: String { "\(event) -> \(ending)" }
    }

    private static let interruptions: [Interruption] = [
        Interruption(event: .tap, ending: .tapped),
        Interruption(event: .scene(.inactive), ending: .systemUI),
        Interruption(event: .interrupted(.purposeLaunch), ending: .interrupted(.purposeLaunch)),
        Interruption(event: .interrupted(.presentation), ending: .interrupted(.presentation)),
    ]

    @Test("While playing, an event hands off with its ending, quickly", arguments: interruptions,
          [LaunchSequence.Variant.full, .reduced])
    private func anEventWhilePlayingHandsOffQuickly(_ interruption: Interruption, _ variant: LaunchSequence.Variant) throws {
        var sequence = playing(variant, at: 0)
        #expect(sequence.ending(at: at(0.5)) == nil, "still playing: no ending yet")
        sequence.send(interruption.event, at: at(0.5))
        #expect(sequence.phase(at: at(0.5)) == .handingOff)
        #expect(!sequence.covers(at: at(0.5)))
        #expect(sequence.ending(at: at(0.5)) == interruption.ending)
        #expect(near(sequence.handOffStart, 0.5) && near(sequence.doneAt, 0.75))
        #expect(sequence.phase(at: at(0.75 - e)) == .handingOff)
        #expect(sequence.phase(at: at(0.75 + e)) == .done)
        #expect(sequence.ending(at: at(0.75 + e)) == interruption.ending, "the ending outlives the fade")
        #expect(near(sequence.nextChange(after: at(0.5)), 0.75))
        #expect(sequence.nextChange(after: at(0.75 + e)) == nil)
    }

    @Test("Before it plays, the same events skip it or do nothing", arguments: [
        (LaunchSequence.Event.tap, LaunchSkip?.none),
        (.scene(.inactive), nil),
        (.firstFrame, nil),
        (.scene(.background), .backgrounded),
        (.interrupted(.purposeLaunch), .purposeLaunch),
        (.interrupted(.presentation), .presentation),
    ])
    private func anEventWhileArmed(_ event: LaunchSequence.Event, _ skip: LaunchSkip?) {
        var sequence = LaunchSequence(decision: .play(.full), createdAt: created)
        sequence.send(event, at: at(0.1))
        if let skip {
            #expect(sequence.phase(at: at(0.1)) == .skipped)
            #expect(sequence.ending(at: at(0.1)) == .skipped(skip))
            #expect(!sequence.covers(at: at(0.1)))
            #expect(sequence.nextChange(after: at(0.1)) == nil)
        } else {
            #expect(sequence.phase(at: at(0.1)) == .armed)
            #expect(sequence.covers(at: at(0.1)))
            #expect(sequence.ending(at: at(0.1)) == nil)
        }
    }

    @Test("Backgrounded while playing: over at once, whichever the variant", arguments: [LaunchSequence.Variant.full, .reduced])
    private func backgroundedWhilePlayingIsOverAtOnce(_ variant: LaunchSequence.Variant) {
        var sequence = playing(variant, at: 0)
        sequence.send(.scene(.background), at: at(0.4))
        #expect(sequence.phase(at: at(0.4)) == .done)
        #expect(sequence.ending(at: at(0.4)) == .backgrounded)
        #expect(sequence.handOff(at: at(0.4)) == 1)
        #expect(!sequence.covers(at: at(0.4)))
        #expect(sequence.nextChange(after: at(0.4)) == nil)
        // The moments before it still show what was playing.
        #expect(sequence.phase(at: at(0.4 - e)) == .playing)
    }

    @Test func backgroundedDuringTheFadeKeepsWhatStartedIt() {
        var tapped = playing(at: 0)
        tapped.send(.tap, at: at(1))
        tapped.send(.scene(.background), at: at(1.1))
        #expect(tapped.phase(at: at(1.1)) == .done)
        #expect(tapped.ending(at: at(1.1)) == .tapped)
        #expect(tapped.handOff(at: at(1.1)) == 1)

        var finished = playing(at: 0)
        let start = finished.handOffStart ?? at(0)
        finished.send(.scene(.background), at: start.addingTimeInterval(0.1))
        #expect(finished.phase(at: start.addingTimeInterval(0.1)) == .done)
        #expect(finished.ending(at: start.addingTimeInterval(0.1)) == .finished)
    }

    @Test("While it fades, taps reach the root and nothing else changes it", arguments: [
        LaunchSequence.Event.tap, .scene(.inactive), .scene(.active), .interrupted(.presentation), .interrupted(.purposeLaunch),
        .firstFrame,
    ])
    private func eventsDuringTheFadeChangeNothing(_ event: LaunchSequence.Event) {
        var sequence = playing(at: 0)
        sequence.send(.tap, at: at(1))
        let before = sequence
        sequence.send(event, at: at(1.1))
        #expect(sequence == before)
        #expect(sequence.ending(at: at(1.1)) == .tapped)
    }

    @Test("Done and skipped ignore every event", arguments: [
        LaunchSequence.Event.tap, .scene(.inactive), .scene(.active), .scene(.background), .interrupted(.presentation),
        .interrupted(.purposeLaunch), .firstFrame,
    ])
    private func terminalPhasesIgnoreEverything(_ event: LaunchSequence.Event) {
        var done = playing(at: 0)
        done.send(.tap, at: at(1))
        let doneBefore = done
        done.send(event, at: at(30))
        #expect(done == doneBefore)
        #expect(done.phase(at: at(30)) == .done)

        var skipped = LaunchSequence(decision: .skip(.harness), createdAt: created)
        let skippedBefore = skipped
        skipped.send(event, at: at(0.1))
        #expect(skipped == skippedBefore)
        #expect(skipped.phase(at: at(0.1)) == .skipped)

        var armedThenSkipped = LaunchSequence(decision: .play(.full), createdAt: created)
        armedThenSkipped.send(.scene(.background), at: at(0.1))
        let before = armedThenSkipped
        armedThenSkipped.send(event, at: at(0.2))
        #expect(armedThenSkipped == before)
    }

    @Test("Every decided skip is skipped from the first instant, with its own reason", arguments: [
        LaunchSkip.backgroundLaunch, .harness, .workoutActive, .recentlyUsed, .lateActivation, .backgrounded, .purposeLaunch,
        .presentation,
    ])
    private func aSkipDecisionKeepsItsReason(_ reason: LaunchSkip) {
        let sequence = LaunchSequence(decision: .skip(reason), createdAt: created)
        for seconds in [0.0, 1, 10] {
            #expect(sequence.phase(at: at(seconds)) == .skipped)
            #expect(!sequence.covers(at: at(seconds)))
            #expect(sequence.ending(at: at(seconds)) == .skipped(reason))
            #expect(sequence.nextChange(after: at(seconds)) == nil)
            #expect(sequence.progress(at: at(seconds)) == 0 && sequence.handOff(at: at(seconds)) == 0)
        }
        #expect(sequence.variant == nil)
    }

    @Test func aSkippedSequenceNeverCoversNorHasAFrameToShow() {
        var sequence = LaunchSequence(decision: .skip(.recentlyUsed), createdAt: created)
        sequence.send(.scene(.active), at: at(0.1))
        #expect(sequence.startedAt == nil && sequence.handOffStart == nil && sequence.doneAt == nil)
    }

    // MARK: endings: names and VoiceOver focus

    private struct Focus: CustomTestStringConvertible, Sendable {
        let ending: LaunchSequence.Ending
        let name: String
        let movesFocus: Bool
        var testDescription: String { name }
    }

    /// `movesFocusToRoot`: VoiceOver moves to the root once it is uncovered, unless what ended the sequence owns the focus
    /// (a sheet, system UI, the background). launch-design.md §7.4, §8.
    private static let focus: [Focus] = [
        Focus(ending: .finished, name: "finished", movesFocus: true),
        Focus(ending: .tapped, name: "tapped", movesFocus: true),
        Focus(ending: .interrupted(.purposeLaunch), name: "interrupted-purposeLaunch", movesFocus: true),
        Focus(ending: .skipped(.purposeLaunch), name: "skipped-purposeLaunch", movesFocus: true),
        Focus(ending: .skipped(.lateActivation), name: "skipped-lateActivation", movesFocus: true),
        Focus(ending: .systemUI, name: "system-ui", movesFocus: false),
        Focus(ending: .backgrounded, name: "backgrounded", movesFocus: false),
        Focus(ending: .interrupted(.presentation), name: "interrupted-presentation", movesFocus: false),
        Focus(ending: .skipped(.presentation), name: "skipped-presentation", movesFocus: false),
        Focus(ending: .skipped(.backgrounded), name: "skipped-backgrounded", movesFocus: false),
        Focus(ending: .skipped(.harness), name: "skipped-harness", movesFocus: false),
        Focus(ending: .skipped(.backgroundLaunch), name: "skipped-backgroundLaunch", movesFocus: false),
        Focus(ending: .skipped(.workoutActive), name: "skipped-workoutActive", movesFocus: false),
        Focus(ending: .skipped(.recentlyUsed), name: "skipped-recentlyUsed", movesFocus: false),
    ]

    @Test("Which endings move VoiceOver to the root, and their signpost names", arguments: focus)
    private func theEndingsFocusAndName(_ focus: Focus) {
        #expect(focus.ending.movesFocusToRoot == focus.movesFocus)
        #expect(focus.ending.signpostName == focus.name)
    }

    // MARK: nextChange

    @Test("nextChange walks the phases in order and ends", arguments: [LaunchSequence.Variant.full, .reduced])
    private func nextChangeWalksToTheEnd(_ variant: LaunchSequence.Variant) throws {
        let sequence = playing(variant, at: 0)
        var date = at(0), chain: [Date] = []
        while let next = sequence.nextChange(after: date) {
            #expect(next > date, "strictly later")
            chain.append(next)
            date = next
            #expect(chain.count <= 2, "no endless chain")
        }
        let timing = sequence.timing
        #expect(chain.count == 2)
        #expect(near(chain.first, timing.duration) && near(chain.last, timing.duration + timing.handOff))
        #expect(sequence.phase(at: date) == .done)
    }

    @Test("nextChange never moves backwards as time passes, and is nil exactly when only an event can change the phase")
    func nextChangeIsMonotonicAndNilWhenTerminal() throws {
        let sequences: [(String, LaunchSequence)] = {
            var tapped = playing(at: 0)
            tapped.send(.tap, at: at(2))
            var background = playing(.reduced, at: 0)
            background.send(.scene(.background), at: at(0.3))
            return [("full", playing(at: 0)), ("reduced", playing(.reduced, at: 0)), ("tapped", tapped),
                    ("backgrounded", background), ("armed", LaunchSequence(decision: .play(.full), createdAt: created)),
                    ("skipped", LaunchSequence(decision: .skip(.harness), createdAt: created))]
        }()
        for (name, sequence) in sequences {
            var last: Date?
            for step in -20...300 {
                let date = at(Double(step) * 0.025)
                let next = sequence.nextChange(after: date)
                switch sequence.phase(at: date) {
                case .armed, .done, .skipped: #expect(next == nil, "\(name) at \(step): terminal or armed")
                case .playing, .handingOff:
                    let value = try #require(next, "\(name) at \(step)")
                    #expect(value > date, "\(name) at \(step)")
                    if let last { #expect(value >= last, "\(name) at \(step): never earlier than before") }
                    last = value
                }
            }
        }
    }

    @Test func nothingIsLeftToWaitForAfterDone() {
        var sequence = playing(at: 0)
        sequence.send(.tap, at: at(0.2))
        for seconds in [0.46, 1, 10, 1_000] { #expect(sequence.nextChange(after: at(seconds)) == nil) }
    }

    // MARK: names

    @Test func theVariantsAndTheInterruptionsMap() {
        #expect(LaunchSequence(decision: .play(.full), createdAt: created).variant == .full)
        #expect(LaunchSequence(decision: .play(.reduced), createdAt: created).variant == .reduced)
        #expect(LaunchInterruption.purposeLaunch.skip == .purposeLaunch)
        #expect(LaunchInterruption.presentation.skip == .presentation)
    }
}
