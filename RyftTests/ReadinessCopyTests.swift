import Foundation
import Testing
@testable import Ryft

@Suite("Readiness copy")
struct ReadinessCopyTests {
    @Test(arguments: [
        (ReadinessState.balanced, "Your health is in balance."),
        (.strained, "Take it a little easier today."),
        (.depleted, "Your body is asking for rest."),
    ])
    func stateSentences(state: ReadinessState, expected: String) {
        #expect(ReadinessCopy.sentence(for: state) == expected)
    }

    @Test func calibratingCountsNights() {
        #expect(ReadinessCopy.sentence(for: .calibrating, nightsToGo: 4) == "Learning your baseline — 4 nights to go.")
        #expect(ReadinessCopy.sentence(for: .calibrating, nightsToGo: 1) == "Learning your baseline — 1 night to go.")
    }

    @Test func nightsToGoFromBaselineDays() {
        let s = DailyScore(day: "2026-10-18", calibrating: true, details: ["baseline_days": .number(5)])
        #expect(s.nightsToGo == 2)
        #expect(ReadinessCopy.sentence(score: s) == "Learning your baseline — 2 nights to go.")
        // Without details it still asks for at least one night, never zero.
        #expect(DailyScore(day: "2026-10-18", calibrating: true, details: ["baseline_days": .number(9)]).nightsToGo == 1)
    }

    @Test func noScoreHasNeutralSentence() {
        #expect(ReadinessCopy.sentence(score: nil) == ReadinessCopy.sentence(for: ReadinessState?.none))
    }

    @Test(arguments: [(90, ReadinessState.balanced), (67, .balanced), (66, .strained), (34, .strained), (33, .depleted)])
    func derivedStateWhenServerOmitsIt(readiness: Int, expected: ReadinessState) {
        #expect(DailyScore(day: "2026-10-18", readiness: readiness).resolvedState == expected)
    }

    @Test func serverStateWins() {
        #expect(DailyScore(day: "2026-10-18", readiness: 90, state: .strained).resolvedState == .strained)
    }

    @Test(arguments: [(6, "Good morning,"), (11, "Good morning,"), (12, "Good afternoon,"), (17, "Good afternoon,"),
                      (18, "Good evening,"), (2, "Good evening,")])
    func greeting(hour: Int, expected: String) {
        let d = Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: .now)!
        #expect(ReadinessCopy.greeting(at: d) == expected)
    }
}
