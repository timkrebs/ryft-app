import Foundation
import SwiftUI
import Testing
@testable import Ryft

/// The launch sequence's phases over time and the play rules' order (ADR 0017, launch-design.md §5 and §6.2, L9). The
/// essential rows only; the full tables are T3.4's.
@Suite("Launch: phases and play rules")
struct LaunchSequenceTests {
    private let created = Date(timeIntervalSince1970: 1_792_600_000)

    private func at(_ seconds: TimeInterval) -> Date { created.addingTimeInterval(seconds) }
    /// Dates carry about a microsecond of rounding here: boundaries are checked this far either side.
    private let e = 0.001

    private func near(_ date: Date?, _ seconds: TimeInterval) -> Bool {
        date.map { abs($0.timeIntervalSince(at(seconds))) < e } ?? false
    }

    private func playing(_ variant: LaunchSequence.Variant = .full, at start: TimeInterval = 0.1) -> LaunchSequence {
        var sequence = LaunchSequence(decision: .play(variant), createdAt: created)
        sequence.send(.scene(.active), at: at(start))
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

    // MARK: the play rules, from the top

    @Test func thePlayRulesInOrder() {
        typealias C = LaunchContext
        let recent: TimeInterval = 60
        let rows: [(String, C, LaunchDecision)] = [
            ("1 forced skip beats everything", C(hasLaunchArguments: true, override: .skip, reduceMotion: true), .skip(.harness)),
            ("2 a background launch, even with play", C(launchedInBackground: true, hasLaunchArguments: true, override: .play),
             .skip(.backgroundLaunch)),
            ("3 any launch argument", C(hasLaunchArguments: true), .skip(.harness)),
            ("3 play overrides the arguments", C(hasLaunchArguments: true, override: .play), .play(.full)),
            ("4 an open workout, even with play", C(hasLaunchArguments: true, override: .play, workoutActive: true),
             .skip(.workoutActive)),
            ("4 before recency and the reduced variant", C(reduceMotion: true, workoutActive: true,
                                                           secondsSinceLastBackground: recent), .skip(.workoutActive)),
            ("L9 back within 10 minutes", C(secondsSinceLastBackground: recent), .skip(.recentlyUsed)),
            ("L9 before the reduced variant", C(voiceOver: true, secondsSinceLastBackground: 599), .skip(.recentlyUsed)),
            ("L9 10 minutes is long enough", C(secondsSinceLastBackground: 600), .play(.full)),
            ("L9 a clock set back doesn't count", C(secondsSinceLastBackground: -5), .play(.full)),
            ("L9 play overrides recency", C(hasLaunchArguments: true, override: .play, secondsSinceLastBackground: recent),
             .play(.full)),
            ("5 Reduce Motion", C(reduceMotion: true), .play(.reduced)),
            ("5 Low Power Mode", C(lowPower: true), .play(.reduced)),
            ("5 VoiceOver", C(voiceOver: true), .play(.reduced)),
            ("6 otherwise", C(), .play(.full)),
        ]
        for (name, context, expected) in rows {
            #expect(LaunchPolicy.decide(context) == expected, "\(name)")
        }
    }

    @MainActor
    @Test func theRecencyRuleReadsWhatTheBackgroundWrote() throws {
        let defaults = try #require(UserDefaults(suiteName: "LaunchSequenceTests.recency"))
        defaults.removePersistentDomain(forName: "LaunchSequenceTests.recency")
        #expect(LaunchContext.current(launchedInBackground: false, workoutActive: false, defaults: defaults)
            .secondsSinceLastBackground == nil)
        LaunchContext.recordBackground(at: at(0), in: defaults)
        let context = LaunchContext.current(launchedInBackground: false, workoutActive: false, now: at(90),
                                            defaults: defaults)
        #expect(abs((context.secondsSinceLastBackground ?? 0) - 90) < e)
        defaults.removePersistentDomain(forName: "LaunchSequenceTests.recency")
    }
}
