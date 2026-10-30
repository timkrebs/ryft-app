import Foundation
import Testing
@testable import Ryft

/// PR 2 of the orbit gauge, without a view: the seven segments as numbers, the count, the mode helpers and the
/// VoiceOver sentences. Synthetic values only (71 / 71 % / 88 % / 9.6, and 3 of 7).
@Suite struct OrbitGaugeCalibratingTests {
    typealias G = OrbitGaugeGeometry

    private static let dials: [CGFloat] = [44, 72, 112, 160]

    /// A centreline's cap as an angle on the outer orbit, as `segments` computes it.
    private func capDegrees(dial: CGFloat) -> Double {
        let m = G.metrics(forDial: dial)
        return Double(m.outerStroke / 2 / m.outerRadius) * 180 / .pi
    }

    // MARK: geometry

    @Test(arguments: [44, 72, 112, 160] as [CGFloat])
    func sevenRequiredGivesSevenEqualSegments(dial: CGFloat) {
        let segments = G.segments(required: 7, dial: dial)
        #expect(segments.count == 7)
        let sweeps = Set(segments.map { ($0.sweep * 1e6).rounded() })
        #expect(sweeps.count == 1, "all segments are equal")
    }

    @Test func tipsStartNineDegreesAfterTheTopAndEndNineBeforeIt() {
        for dial in Self.dials {
            let cap = capDegrees(dial: dial)
            let segments = G.segments(required: 7, dial: dial)
            let firstTip = segments[0].start - cap
            let lastTip = segments[6].start + segments[6].sweep + cap
            #expect(abs(firstTip - G.seamClearDegrees) < 1e-9, "dial \(dial)")
            #expect(abs(lastTip - (360 - G.seamClearDegrees)) < 1e-9, "dial \(dial)")
        }
    }

    @Test func neighbouringTipsAreFiveDegreesApart() {
        for dial in Self.dials {
            let cap = capDegrees(dial: dial)
            let s = G.segments(required: 7, dial: dial)
            for i in 0..<6 {
                let gap = (s[i + 1].start - cap) - (s[i].start + s[i].sweep + cap)
                #expect(abs(gap - 5) < 1e-9, "dial \(dial), gap \(i)")
            }
        }
    }

    @Test func eachSegmentIsAboutFortyFourPointFiveSevenDegreesVisible() {
        let cap = capDegrees(dial: 160)
        let visible = G.segments(required: 7, dial: 160)[0].sweep + 2 * cap
        #expect(abs(visible - 44.57) < 0.01)
        // design.md: centrelines 40.5 deg, the first starting at 11.05 deg and then every 49.57 deg.
        #expect(abs(G.segments(required: 7, dial: 160)[0].sweep - 40.5) < 0.05)
        #expect(abs(G.segments(required: 7, dial: 160)[0].start - 11.05) < 0.01)
        #expect(abs(G.segments(required: 7, dial: 160)[1].start - 60.62) < 0.01)
    }

    @Test func segmentsRunClockwiseInOrderAndNeverWrapPastTheTop() {
        let s = G.segments(required: 7, dial: 160)
        #expect(s.map(\.start) == s.map(\.start).sorted())
        #expect(s.allSatisfy { $0.start > 0 && $0.sweep > 0 && $0.start + $0.sweep < 360 })
    }

    @Test func nothingOverlapsTheTopDot() {
        // The hollow Strain dot sits at the top of the outer orbit, with its air cut out of the track around it.
        for dial in Self.dials {
            let m = G.metrics(forDial: dial)
            let top = G.point(centre: .zero, radius: m.outerRadius, degrees: 0)
            let clear = Double(m.dotRadius + m.dotAir)
            let cap = capDegrees(dial: dial)
            let s = G.segments(required: 7, dial: dial)
            for tipDegrees in [s[0].start - cap, s[6].start + s[6].sweep + cap] {
                let tip = G.point(centre: .zero, radius: m.outerRadius, degrees: tipDegrees)
                let distance = Double(hypot(tip.x - top.x, tip.y - top.y))
                #expect(distance >= clear - 0.01, "dial \(dial): tip \(distance) pt from the dot, needs \(clear)")
            }
        }
    }

    @Test(arguments: [1, 2, 3, 5, 7, 10, 12, 14, 24])
    func otherRequirementsKeepTheSameSeamAndGaps(required: Int) {
        let dial: CGFloat = 160
        let cap = capDegrees(dial: dial)
        let s = G.segments(required: required, dial: dial)
        #expect(s.count == required)
        #expect(abs((s[0].start - cap) - 9) < 1e-9)
        #expect(abs((s[required - 1].start + s[required - 1].sweep + cap) - 351) < 1e-9)
        for i in 0..<(required - 1) {
            #expect(abs((s[i + 1].start - cap) - (s[i].start + s[i].sweep + cap) - 5) < 1e-9)
        }
        #expect(s.allSatisfy { $0.sweep > 0 })
    }

    @Test(arguments: [0, -3, Int.min])
    func requiredBelowOneIsOneSegment(required: Int) {
        #expect(G.segments(required: required, dial: 160).count == 1)
    }

    @Test func aHugeRequirementStaysFiniteAndKeepsTheSweepFloor() {
        // Past the point where a segment can be wider than its caps the sweep floors at 0.5 deg; the drawing stays
        // valid (it overlaps, which nothing in the app asks for: required is 7).
        let s = G.segments(required: 200, dial: 160)
        #expect(s.count == 200)
        #expect(s.allSatisfy { $0.sweep >= 0.5 && $0.start.isFinite })
    }

    // MARK: count

    @Test func countedClampsToTheRequirementAndZero() {
        #expect(OrbitGaugeCalibration(nights: 3).counted == 3)
        #expect(OrbitGaugeCalibration(nights: 0).counted == 0)
        #expect(OrbitGaugeCalibration(nights: 7).counted == 7)
        #expect(OrbitGaugeCalibration(nights: 9).counted == 7)
        #expect(OrbitGaugeCalibration(nights: -2).counted == 0)
        #expect(OrbitGaugeCalibration(nights: 5, required: 4).counted == 4)
        #expect(OrbitGaugeCalibration.defaultRequired == 7)
    }

    // MARK: mode helpers

    @Test func drawnValuesAndPendingPerMode() {
        let day = OrbitGaugeValues.previewScored
        let cal = OrbitGaugeCalibration(nights: 3)
        #expect(OrbitGaugeMode.scored(day).drawnValues == day)
        #expect(OrbitGaugeMode.scored(day, learning: cal).drawnValues == day)
        #expect(OrbitGaugeMode.pending(previous: day).drawnValues == day)
        #expect(OrbitGaugeMode.pending(previous: nil).drawnValues == nil)
        #expect(OrbitGaugeMode.calibrating(cal).drawnValues == nil)
        #expect(OrbitGaugeMode.assembling.drawnValues == nil)

        #expect(OrbitGaugeMode.pending(previous: day).isPending)
        #expect(OrbitGaugeMode.pending(previous: nil).isPending)
        #expect(!OrbitGaugeMode.scored(day).isPending)
        #expect(!OrbitGaugeMode.scored(day, learning: cal).isPending)
        #expect(!OrbitGaugeMode.calibrating(cal).isPending)
        #expect(!OrbitGaugeMode.assembling.isPending)
    }

    @Test func scoredValuesIsOnlyForScored() {
        let day = OrbitGaugeValues.previewScored
        #expect(OrbitGaugeMode.scored(day).scoredValues == day)
        #expect(OrbitGaugeMode.pending(previous: day).scoredValues == nil)
    }

    @Test func calibratingValueIsNilForEveryOtherMode() {
        let cal = OrbitGaugeCalibration(nights: 3, signal: .hrv)
        #expect(OrbitGaugeMode.calibrating(cal).calibratingValue == cal)
        #expect(OrbitGaugeMode.scored(.previewScored).calibratingValue == nil)
        #expect(OrbitGaugeMode.scored(.previewScored, learning: cal).calibratingValue == nil)
        #expect(OrbitGaugeMode.pending(previous: .previewScored).calibratingValue == nil)
        #expect(OrbitGaugeMode.pending(previous: nil).calibratingValue == nil)
        #expect(OrbitGaugeMode.assembling.calibratingValue == nil)
    }

    // MARK: VoiceOver (English; the simulator's region decides the decimal separator)

    private func normalised(_ s: String) -> String { s.replacingOccurrences(of: "9,6", with: "9.6") }

    @Test func calibratingSpeaksTheCountForEachSignal() {
        func say(_ signal: OrbitGaugeCalibration.Signal, nights: Int = 3) -> String {
            OrbitGauge.spokenValue(OrbitGaugeCalibration(nights: nights, signal: signal))
        }
        #expect(say(.anyNight) == "3 of 7 nights. Readiness appears once the baselines are complete.")
        #expect(say(.heartRateNights)
                == "3 of 7 nights with heart-rate data. Readiness appears once the baselines are complete.")
        #expect(say(.hrv) == "3 of 7 nights with HRV.")
        #expect(say(.restingHR) == "3 of 7 nights with resting heart rate.")
    }

    @Test func calibratingSpeaksTheClampedCount() {
        #expect(OrbitGauge.spokenValue(OrbitGaugeCalibration(nights: 9, signal: .hrv)) == "7 of 7 nights with HRV.")
        #expect(OrbitGauge.spokenValue(OrbitGaugeCalibration(nights: -1, signal: .hrv)) == "0 of 7 nights with HRV.")
    }

    /// No closing full stop: the gauge appends its note with ". " (design.md writes the sentence with one).
    @Test func pendingWithADayBeforeSaysWhatWasLastScored() {
        let spoken = normalised(OrbitGauge.spokenPending(.previewScored))
        #expect(spoken == "Not scored yet. Last scored: 71. Recovery 71 percent, Sleep 88 percent, Strain 9.6 of 21")
    }

    @Test func pendingLeavesOutTheBandWordForTheDayBefore() {
        #expect(!OrbitGauge.spokenPending(.previewScored).contains("High"))
    }

    @Test func pendingWithoutADayBeforeOnlySaysNotScoredYet() {
        #expect(OrbitGauge.spokenPending(nil) == "Not scored yet")
        // A previous day with nothing in it is no previous day.
        #expect(OrbitGauge.spokenPending(OrbitGaugeValues()) == "Not scored yet")
    }

    @Test func scoredSpeechIsUnchanged() {
        let spoken = normalised(OrbitGauge.spokenValue(.previewScored))
        #expect(spoken == "71, High. Recovery 71 percent, Sleep 88 percent, Strain 9.6 of 21")
        #expect(OrbitGauge.spokenValue(OrbitGaugeValues()) == "No data")
    }
}
