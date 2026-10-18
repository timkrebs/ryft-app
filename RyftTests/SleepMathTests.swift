import Foundation
import Testing
@testable import Ryft

@Suite("Sleep stage maths")
struct SleepMathTests {
    @Test func boardNightSumsTo100() {
        let shares = SleepMath.shares([.deep: 112, .light: 261, .rem: 95, .awake: 10])
        #expect(shares.map(\.stage) == [.deep, .light, .rem, .awake])
        #expect(shares.map { Int($0.pct ?? -1) } == [23, 55, 20, 2])
        #expect(shares.compactMap(\.pct).reduce(0, +) == 100)
    }

    @Test(arguments: [
        [SleepStageKind.deep: 1, .light: 1, .rem: 1],
        [.deep: 7, .light: 333, .rem: 1, .awake: 59],
        [.light: 420],
    ])
    func alwaysSumsTo100(minutes: [SleepStageKind: Int]) {
        #expect(SleepMath.shares(minutes).compactMap(\.pct).reduce(0, +) == 100)
    }

    @Test func emptyNightIsAllZero() {
        let shares = SleepMath.shares([:])
        #expect(shares.count == 4)
        #expect(shares.allSatisfy { $0.min == 0 && $0.pct == 0 })
    }

    @Test func negativeMinutesAreIgnored() {
        let shares = SleepMath.shares([.deep: -5, .light: 100])
        #expect(shares.first { $0.stage == .deep }?.min == 0)
        #expect(shares.first { $0.stage == .light }?.pct == 100)
    }

    @Test func percentNormalisesFractions() {
        #expect(SleepMath.percent(0.82) == 82)
        #expect(SleepMath.percent(82) == 82)
    }

    @Test func serverPercentagesWin() {
        let detail = SleepDetail(totalMin: 100, stages: [StageShare(stage: .deep, min: 50, pct: 0.4),
                                                        StageShare(stage: .light, min: 50)])
        let stages = detail.displayStages
        #expect(stages.first { $0.stage == .deep }?.pct == 40)
        #expect(stages.first { $0.stage == .light }?.pct == 50)
        #expect(stages.count == 4)
    }

    @Test func efficiencyDerivedWhenMissing() {
        let d = SleepDetail(totalMin: 450, inBedMin: 500)
        #expect(d.efficiencyPercent == 90)
    }

    @Test(arguments: [(90, "Excellent"), (82, "Good"), (60, "Fair"), (20, "Poor")])
    func qualityLabels(quality: Int, expected: String) {
        #expect(SleepMath.qualityLabel(quality) == expected)
    }

    @Test func bedtimeDeviationAcrossMidnight() throws {
        let cal = Calendar.current
        let base = cal.startOfDay(for: .now)
        let times = [(23, 30), (0, 30), (23, 30), (0, 30)].map {
            cal.date(bySettingHour: $0.0, minute: $0.1, second: 0, of: base)!
        }
        let dev = try #require(SleepMath.bedtimeDeviation(times))
        #expect(abs(dev - 30) < 0.001) // ±30 min, not ±11.5 h
        #expect(SleepMath.bedtimeDeviation(Array(times.prefix(2))) == nil)
    }
}
