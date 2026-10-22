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

    /// A scored row (it has a `computed_at`) without a readiness.
    private static let scoredAt = Date(timeIntervalSince1970: 1_792_300_000)

    @Test func nightsToGoFromBaselineDays() {
        let s = DailyScore(day: "2026-10-18", state: .calibrating, baselineDays: 5, calibrating: true, computedAt: Self.scoredAt)
        #expect(s.nightsToGo == 2)
        #expect(ReadinessCopy.sentence(score: s) == "Learning your baseline — 2 nights to go.")
        // Never zero nights to go.
        #expect(DailyScore(day: "2026-10-18", baselineDays: 9, calibrating: true).nightsToGo == 1)
    }

    /// D4: `calibrating` also when the baseline is complete but there's no readiness.
    @Test func calibratingWithoutReadiness() {
        let s = DailyScore(day: "2026-10-18", readiness: nil, state: .calibrating, baselineDays: 30, calibrating: false,
                           computedAt: Self.scoredAt)
        #expect(ReadinessCopy.sentence(score: s) == "No readiness yet today. It appears once last night has synced.")
        // A cached payload without `state` reads the same way.
        #expect(DailyScore(day: "2026-10-18", baselineDays: 30).resolvedState == .calibrating)
    }

    @Test func noScoreHasNeutralSentence() {
        #expect(ReadinessCopy.sentence(score: nil) == ReadinessCopy.sentence(for: ReadinessState?.none))
    }

    /// An unscored row (API.md's placeholder, `DailyScore.empty`) has no readiness yet: never "Learning your
    /// baseline", even when it says `state: calibrating` or carries the flag.
    @Test func anUnscoredRowIsNoReadinessYet() {
        let noReadiness = "No readiness yet today. It appears once last night has synced."
        #expect(ReadinessCopy.sentence(score: .empty(day: "2026-10-18")) == noReadiness)
        let placeholder = DailyScore(day: "2026-10-18", state: .calibrating, baselineDays: 0, calibrating: false,
                                     computedAt: Date(timeIntervalSince1970: -62_135_596_800))
        #expect(ReadinessCopy.sentence(score: placeholder) == noReadiness)
        let claims = DailyScore(day: "2026-10-18", state: .calibrating, baselineDays: 2, calibrating: true)
        #expect(ReadinessCopy.sentence(score: claims) == noReadiness)
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
