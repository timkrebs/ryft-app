import Foundation
import Testing
@testable import Ryft

@Suite("Chart style")
struct ChartStyleTests {
    @Test func niceScaleRoundsOutToFewTicks() {
        let s = ChartStyle.niceScale([47.4, 50.8, 57.6])
        #expect(s.domain == 45...60)
        #expect(s.ticks == [45, 50, 55, 60])
    }

    @Test func niceScaleNeverGoesNegativeForPositiveData() {
        let s = ChartStyle.niceScale([0.4, 3.1, 2.2])
        #expect(s.domain.lowerBound == 0)
        #expect(s.ticks.count <= 5 && s.ticks.count >= 2)
    }

    @Test func flatSeriesStillGetsARange() {
        let s = ChartStyle.niceScale([50, 50])
        #expect(s.domain.lowerBound < 50 && s.domain.upperBound > 50)
    }

    @Test func scoresKeepTheirScaleWithThresholdTicks() {
        #expect(ChartStyle.scale(for: [70, 84], spec: .readiness).ticks == [0, 33, 67, 100])
        #expect(ChartStyle.scale(for: [4, 12], spec: .strain).ticks == [0, 10, 14, 18, 21])
        #expect(ChartStyle.scale(for: [80], spec: .sleepPerformance).ticks == [0, 25, 50, 75, 100])
    }

    @Test func minutesTickOnWholeHours() {
        let s = ChartStyle.scale(for: [402, 468, 510], spec: .sleepMin)
        #expect(s.ticks.allSatisfy { $0.truncatingRemainder(dividingBy: 60) == 0 })
    }

    @Test func windowTicks() throws {
        let end = try #require(DayFormat.date(from: "2026-10-19"))
        #expect(ChartWindow.week.ticks(endingAt: end).count == 7)
        let month = ChartWindow.month.ticks(endingAt: end)
        #expect(month.map(DayFormat.string) == ["2026-09-21", "2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19"])
        let quarter = ChartWindow.quarter.ticks(endingAt: end)
        #expect(quarter.map(DayFormat.string) == ["2026-08-01", "2026-09-01", "2026-10-01"])
        #expect(ChartWindow(days: 30) == .month && ChartWindow(days: 7) == .week && ChartWindow(days: 90) == .quarter)
    }

    @Test func deltaAgainstTheSevenDaysBefore() throws {
        let points = (12...19).map { TrendPoint(day: "2026-10-\($0)", value: $0 == 19 ? 60 : 50) }
        let d = try #require(MetricDelta.vsSevenDayMean(points))
        #expect(d.value == 10)
        #expect(d.percent == 20)
        #expect(DeltaLabel.text(d, spec: .hrv) == "▲ +10 ms · +20 %")
        #expect(DeltaLabel.color(d, spec: .hrv) == Theme.accent)
        #expect(DeltaLabel.color(d, spec: .rhr) == Theme.alert)
    }

    @Test func smallChangesReadAsFlat() {
        let d = MetricDelta(current: 50.5, reference: 50)
        #expect(d.isFlat)
        #expect(DeltaLabel.text(d, spec: .hrv) == "—")
    }

    @Test func scoresChangeInPointsWithoutPercent() {
        #expect(DeltaLabel.text(MetricDelta(current: 84, reference: 78), spec: .readiness) == "▲ +6")
        #expect(DeltaLabel.text(MetricDelta(current: 41, reference: 63), spec: .recovery) == "▼ −22")
    }

    @Test func rangeBarDerivesItsBandFromTheTrend() throws {
        let points = (1...9).map { TrendPoint(day: "2026-10-0\($0)", value: Double(40 + $0)) }
        let series = TrendSeries(metric: "hrv", range: "30d", points: points, avg: 45, min: 41, max: 49, baseline: 45)
        let bar = try #require(RangeBar(spec: .hrv, value: 52, series: series))
        #expect(bar.range == 41...49)
        #expect(bar.typical == 43...47)
        #expect(RangeBar(spec: .hrv, value: 52, series: nil) == nil)
    }
}
