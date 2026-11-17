import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// PR 4's shared groundwork (docs/work/2026-11-16-nocturne/design.md §P4-12, T4.0): the pure parts of the new components
/// (sparkline and hypnogram geometry, the clock format), the additive API on the PR 2 components (`DotRow.Mark.noData`,
/// `DeltaLabel(referenceColor:)`, `CircleButton(iconSize:)`) and the board night in `MockData` (§P4-4, test 35).
@MainActor
@Suite struct NocturneSharedComponentTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA

    private var ink: RGBA { Tokens.resolve(Theme.textPrimary) }
    private var screen: RGBA { Tokens.resolve(Theme.background) }

    private func near(_ a: RGBA, _ b: RGBA, _ steps: Double = 2) -> Bool {
        let t = steps / 255 + 1e-9
        return abs(a.r - b.r) <= t && abs(a.g - b.g) <= t && abs(a.b - b.b) <= t
    }

    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }

    // MARK: 32. DotRow.Mark.noData

    @Test("Spec 32: .noData keeps the 6 pt cell, draws a 2 pt dot at 35 % ink, and has no ring (unlike .missed)")
    func noDataMark() throws {
        let row = DotRow([.full, .noData, .missed], accessibilityLabel: Text(verbatim: "summary")).background(Theme.background)
        let shot = try #require(KindShot.render(row, scale: 4))
        #expect(shot.size == CGSize(width: 26, height: 6), "three cells, 6 + 4 + 6 + 4 + 6")
        // The cell's centre (13, 3) is inside the 2 pt dot; 1.5 pt out (at 11.5) is the screen.
        let dot = Tokens.over(RGBA(r: ink.r, g: ink.g, b: ink.b, a: DotRow.noDataOpacity), screen)
        #expect(near(shot.at(13, 3), dot, 3), "the dot: \(Tokens.describe(shot.at(13, 3)))")
        #expect(near(shot.at(11.5, 3), screen), "no ring where .missed has one: \(Tokens.describe(shot.at(11.5, 3)))")
        #expect(near(shot.at(10.4, 3), screen))
        // .missed, beside it: the ring at its edge, the screen in its middle.
        #expect(!near(shot.at(20.4, 3), screen) && near(shot.at(23, 3), screen))
        #expect(DotRow.noDataDot == 2 && DotRow.noDataOpacity == 0.35)
    }

    // MARK: DeltaLabel, CircleButton

    private func pixels(of colour: Color, in shot: KindShot, steps: Double = 6) -> Int {
        let want = Tokens.resolve(colour)
        var count = 0
        for iy in 0..<shot.height {
            for ix in 0..<shot.width where near(shot.px(ix, iy), want, steps) { count += 1 }
        }
        return count
    }

    @Test("DeltaLabel's reference takes the given colour; without it, textTertiary as before")
    func deltaReferenceColour() throws {
        // Volt appears nowhere else in a delta label, so its pixels are the reference's.
        let delta = MetricDelta(current: 56, reference: 52)
        let tinted = DeltaLabel(spec: .hrv, delta: delta, reference: "vs 7 d", referenceColor: Theme.signal)
        let plain = DeltaLabel(spec: .hrv, delta: delta, reference: "vs 7 d")
        #expect(plain.referenceColor == nil)
        let a = try #require(KindShot.render(tinted.padding(4).background(Theme.background), scale: 3))
        let b = try #require(KindShot.render(plain.padding(4).background(Theme.background), scale: 3))
        #expect(pixels(of: Theme.signal, in: a) > 10)
        #expect(pixels(of: Theme.signal, in: b) == 0)
    }

    @Test("CircleButton's symbol is 14 by default and the caller's size when given; the circle and the box do not change")
    func circleButtonIconSize() {
        #expect(CircleButton.iconSize == 14)
        #expect(CircleButton.diameter == 40 && CircleButton.hitSize == 44)
        #expect(ScreenHeaderSpec.buttonOverhang == 2 && ScreenHeaderSpec.height == 40)
    }

    // MARK: Fmt.clock and the spoken duration (spec 5)

    @Test("Spec 5: Fmt.clock is hours and two-digit minutes", arguments: [
        (468 as Int?, "7:48"), (0, "0:00"), (61, "1:01"), (498, "8:18"), (30, "0:30"), (600, "10:00"), (-42, "−0:42"), (nil, "–"),
    ])
    func clock(_ minutes: Int?, _ want: String) {
        #expect(Fmt.clock(minutes: minutes) == want)
    }

    @Test("A duration is spoken one unit at a time", arguments: [
        (468, "7 hours 48 minutes"), (60, "1 hour"), (61, "1 hour 1 minute"), (22, "22 minutes"), (0, "0 minutes"),
        (-42, "42 minutes"),
    ])
    func spokenDuration(_ minutes: Int, _ want: String) {
        #expect(Fmt.spokenDuration(minutes: minutes, locale: Locale(identifier: "en_US")) == want)
    }

    // MARK: Sparkline (spec 21's drawing half)

    @Test("The board's week: one run of seven points, the first at x 0 and the last at 58, max at y 2 and min at y 18")
    func sparklineWeek() throws {
        let layout = Sparkline.layout(values: [58, 51, 60, 55, 62, 57, 66])
        #expect(!layout.isPending && layout.runs.count == 1)
        let run = try #require(layout.runs.first)
        #expect(run.count == 7)
        #expect(near(run[0].x, 0) && near(run[6].x, 58) && near(run[3].x, 29))
        #expect(near(run[6].y, 2), "66, the highest: \(run[6].y)")
        #expect(near(run[1].y, 18), "51, the lowest: \(run[1].y)")
        #expect(near(run[0].y, 2 + 8.0 / 15 * 16), "58")
        #expect(layout.endDot == run[6])
    }

    @Test("A missing day breaks the line; a day alone is its own run; no value on the last day, no Volt dot")
    func sparklineGaps() {
        let gap = Sparkline.layout(values: [58, 51, nil, 55, 62, 57, 66])
        #expect(gap.runs.map(\.count) == [2, 4])
        #expect(gap.runs[1].first.map { near($0.x, 58.0 / 2) } == true, "day 3 at x 29")
        let lone = Sparkline.layout(values: [58, nil, 60, nil, 62, 57, 66])
        #expect(lone.runs.map(\.count) == [1, 1, 3])
        let noToday = Sparkline.layout(values: [58, 51, 60, 55, 62, 57, nil])
        #expect(noToday.endDot == nil && !noToday.isPending)
        #expect(noToday.runs.map(\.count) == [6])
    }

    @Test("Under two values it is the pending look; a flat series sits at mid height")
    func sparklinePendingAndFlat() {
        #expect(Sparkline.layout(values: [nil, nil, nil, nil, nil, nil, 66]).isPending)
        #expect(Sparkline.layout(values: []).isPending)
        #expect(Sparkline.layout(values: [.nan, 60]).isPending, "a non-finite value is no value")
        #expect(!Sparkline.layout(values: [nil, 60, nil, 61]).isPending)
        let flat = Sparkline.layout(values: [60, 60, 60])
        #expect(flat.runs.first?.allSatisfy { near($0.y, 10) } == true)
        #expect(Sparkline.size == CGSize(width: 58, height: 20))
    }

    @Test("The sparkline draws Volt only in its end dot, and none without one")
    func sparklineVolt() throws {
        func voltPixels(_ values: [Double?]) throws -> Int {
            let shot = try #require(KindShot.render(Sparkline(values: values).padding(8).background(Theme.background), scale: 3))
            return pixels(of: Theme.signal, in: shot)
        }
        #expect(try voltPixels([58, 51, 60, 55, 62, 57, 66]) > 20, "a 3 pt dot is about 28 points² at 3x")
        #expect(try voltPixels([58, 51, 60, 55, 62, 57, nil]) == 0)
        #expect(try voltPixels([nil, nil, 66]) == 0, "pending: no dot")
    }

    // MARK: HypnogramPlot (spec 6 and the model half of 29)

    @Test("Spec 6: the grid lines at y 4, 31.33, 58.67, 86 in 90; the deep bar 8 high, radius 4, centred on 86; line 1.4, column 38")
    func hypnogramGeometry() {
        let ys = HypnogramPlot.Level.allCases.map { HypnogramPlot.gridY($0, height: 90) }
        for (got, want) in zip(ys, [4, 31.333, 58.667, 86] as [CGFloat]) { #expect(near(got, want, 0.001), "\(ys)") }
        #expect(HypnogramPlot.deepBarHeight == 8 && HypnogramPlot.deepBarRadius == 4 && HypnogramPlot.lineWidth == 1.4)
        #expect(HypnogramPlot.columnWidth == 38 && HypnogramPlot.plotHeight == 90)
        #expect(HypnogramPlot.lineOpacity == 0.85 && HypnogramPlot.gridOpacity == 0.08)
        #expect(HypnogramPlot.plotHeight(nameLineHeight: 15) == 90, "the default size")
        #expect(HypnogramPlot.plotHeight(nameLineHeight: 32) == 128, "four AX lines")
    }

    @Test("At accessibility sizes the grid moves in so the names reach no farther past the plot than at the default size",
          arguments: [15.0, 20, 32, 44] as [CGFloat])
    func hypnogramNamesKeepClear(_ line: CGFloat) {
        let height = HypnogramPlot.plotHeight(nameLineHeight: line)
        let inset = HypnogramPlot.gridInset(nameLineHeight: line)
        let ys = HypnogramPlot.Level.allCases.map { HypnogramPlot.gridY($0, height: height, inset: inset) }
        // The first name's top and the last name's bottom: at most 3.5 past the plot.
        #expect(ys[0] - line / 2 >= -3.5 - 0.001 && ys[3] + line / 2 <= height + 3.5 + 0.001, "\(ys) in \(height)")
        // Neighbouring names do not overlap.
        for (a, b) in zip(ys, ys.dropFirst()) { #expect(b - a >= line - 0.001, "\(ys) at line \(line)") }
        if line == 15 { #expect(inset == 4) }
    }

    private let night = Date(timeIntervalSince1970: 1_794_869_400)
    private func at(_ minutes: Double) -> Date { night.addingTimeInterval(minutes * 60) }
    private func seg(_ stage: SleepIntervalStage, _ from: Double, _ to: Double) -> SleepInterval {
        SleepInterval(stage: stage, start: at(from), end: at(to))
    }

    @Test("Spec 29: levels per stage (asleep on Light), x of start 0 and of end 1, clamped to the night")
    func hypnogramModel() throws {
        let model = HypnogramPlot.model(segments: [seg(.rem, 50, 100), seg(.light, -20, 20), seg(.deep, 20, 50),
                                                   seg(.asleep, 100, 120), seg(.awake, 120, 130)],
                                        start: at(0), end: at(100))
        #expect(model.runs.count == 1)
        let steps = try #require(model.runs.first)
        #expect(steps.map(\.level) == [.light, .deep, .rem], "sorted, and the night ends at 100")
        #expect(steps.first?.from == 0 && steps.last?.to == 1)
        #expect(near(CGFloat(steps[1].from), 0.2) && near(CGFloat(steps[1].to), 0.5))
        #expect(HypnogramPlot.Level(.asleep) == .light && HypnogramPlot.Level(.awake) == .awake)
        #expect(model.deepSpans.count == 1 && near(CGFloat(model.deepSpans[0].lowerBound), 0.2))
    }

    @Test("Spec 29: a gap of more than a minute breaks the path; under a minute it joins; touching deep steps merge")
    func hypnogramGaps() {
        let broken = HypnogramPlot.model(segments: [seg(.light, 0, 30), seg(.rem, 45, 100)], start: at(0), end: at(100))
        #expect(broken.runs.count == 2)
        let joined = HypnogramPlot.model(segments: [seg(.light, 0, 30), seg(.rem, 30.5, 100)], start: at(0), end: at(100))
        #expect(joined.runs.count == 1)
        #expect(joined.runs.first?[1].from == joined.runs.first?[0].to, "the join has no sliver")
        let deep = HypnogramPlot.model(segments: [seg(.deep, 0, 20), seg(.deep, 20, 30), seg(.light, 30, 100)],
                                       start: at(0), end: at(100))
        #expect(deep.deepSpans.count == 1 && near(CGFloat(deep.deepSpans[0].upperBound), 0.3))
    }

    @Test("Spec 29: no night or no segments is empty; a very short deep span still draws a 3 pt bar inside the plot")
    func hypnogramEdges() {
        #expect(HypnogramPlot.model(segments: [], start: at(0), end: at(100)).isEmpty)
        #expect(HypnogramPlot.model(segments: [seg(.light, 0, 10)], start: at(10), end: at(10)).isEmpty)
        let short = HypnogramPlot.model(segments: [seg(.light, 0, 99.9), seg(.deep, 99.9, 100)], start: at(0), end: at(100))
        let bars = HypnogramPlot.deepBarRects(short, size: CGSize(width: 280, height: 90))
        #expect(bars.count == 1)
        if let bar = bars.first {
            #expect(near(bar.width, 3) && bar.maxX <= 280 + 0.001, "\(bar)")
            #expect(near(bar.midY, 86) && near(bar.height, 8))
        }
    }

    @Test("The step line runs at each step's level and its bounds are the plot's")
    func hypnogramPath() {
        let model = HypnogramPlot.model(segments: [seg(.awake, 0, 10), seg(.deep, 10, 100)], start: at(0), end: at(100))
        let box = HypnogramPlot.stepPath(model, size: CGSize(width: 280, height: 90)).boundingRect
        #expect(near(box.minX, 0) && near(box.maxX, 280) && near(box.minY, 4) && near(box.maxY, 86), "\(box)")
    }

    // MARK: 35. MockData's board night

    @Test("Spec 35: today is the board's night: 468 / 22 / 95 / 105 / 268, 22:50 – 07:00, need 498 (a 40 min nap credit)")
    func boardNight() throws {
        let detail = MockData.todayDetail
        let score = detail.score
        let sleep = try #require(detail.sleep)
        #expect(sleep.totalMin == 468 && sleep.inBedMin == 490 && sleep.efficiency == 95)
        let minutes = Dictionary(sleep.stages.map { ($0.stage, $0.min) }, uniquingKeysWith: { a, _ in a })
        #expect(minutes[.awake] == 22 && minutes[.deep] == 95 && minutes[.rem] == 105 && minutes[.light] == 268, "\(minutes)")
        let start = try #require(sleep.start), end = try #require(sleep.end)
        let cal = Calendar.current
        #expect(cal.component(.hour, from: start) == 22 && cal.component(.minute, from: start) == 50)
        // 490 minutes later: 07:00, except on the morning a DST change moves the clock (the change is at 2–3 am).
        #expect(end.timeIntervalSince(start) == 490 * 60)
        #expect(score.sleepNeedMin == 498 && score.sleepPerformance == 94 && score.sleepActualMin == 468)
        #expect(sleep.need?.total == 498 && sleep.need?.napCredit == 40 && score.sleepNeedNapMin == 40)
        #expect(score.sleepDebtMin == 30 && score.sleepConsistency == 86)
        #expect(score.readiness == 84 && score.recovery == 82 && score.strain == 12.4 && score.hrvMs == 66)
        // Restorative is shown as deep + REM (D4-9): 3:20.
        #expect(Fmt.clock(minutes: (minutes[.deep] ?? 0) + (minutes[.rem] ?? 0)) == "3:20")
    }

    @Test("The board night's timeline runs from sleep onset to the night's end and adds up to the stages")
    func boardNightTimeline() throws {
        let sleep = try #require(MockData.todayDetail.sleep)
        let segments = sleep.segments.sorted { $0.start < $1.start }
        #expect(segments.first?.start == sleep.start && segments.last?.end == sleep.end)
        for (a, b) in zip(segments, segments.dropFirst()) { #expect(a.end == b.start, "no gap at \(a.end)") }
        var minutes: [SleepIntervalStage: Double] = [:]
        for s in segments { minutes[s.stage, default: 0] += s.end.timeIntervalSince(s.start) / 60 }
        #expect(minutes[.deep] == 95 && minutes[.rem] == 105 && minutes[.light] == 268 && minutes[.awake] == 22, "\(minutes)")
    }

    @Test("The last seven days: the HRV week, nights met (≥ 90 % of the need, L24), missed and one without a need, debt ▼ 0:42")
    func boardWeek() throws {
        let week = Array(MockData.history.suffix(7))
        #expect(week.map(\.hrvMs) == [58, 51, 60, 55, 62, 57, 66])
        #expect(week.map(\.readiness) == [72, 66, 75, 70, 79, 76, 84])
        func mark(_ s: DailyScore) -> String {
            guard let need = s.sleepNeedMin, let actual = s.sleepActualMin else { return "noData" }
            return Double(actual) >= 0.9 * Double(need) ? "met" : "missed"
        }
        #expect(week.map(mark) == ["met", "missed", "noData", "met", "missed", "met", "met"])
        #expect(week[2].sleepPerformance == nil && week[2].sleepNeedBaseMin == nil)
        #expect(week.map(\.sleepConsistency) == [78, 64, nil, 52, 71, 80, 86])
        #expect(week[5].sleepDebtMin == 72 && week[6].sleepDebtMin == 30)
        #expect(MockData.detail(for: Calendar.current.date(byAdding: .day, value: -4, to: .now) ?? .now).sleep?.need == nil)
        #expect(MockData.user.name == "Tim")
    }
}
