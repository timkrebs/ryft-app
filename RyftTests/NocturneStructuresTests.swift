import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// T5.0-B's shared layout pieces, by value and by pixel (docs/work/2026-11-16-nocturne/design.md §P5-11 tests 8, 9, 13, 14, 20,
/// 23; PR 6 B S11): the `.zones` and `.idea` glow kinds and their contrast, `TickRow`'s arrangements, the zone block's rule,
/// `DeltaLabel`'s colours, `TrendLine`'s geometry, the date strip's days and dots, the placeholder outline and the neutral
/// tile. The accessibility tree is in `NocturneStructuresHostedTests`.
@MainActor
@Suite("Nocturne structures: values and pixels")
struct NocturneStructuresTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA
    typealias Kind = GlowTileSpec.Kind

    private var ink: RGBA { Tokens.resolve(Theme.textPrimary) }
    private var screen: RGBA { Tokens.resolve(Theme.background) }
    private var surface: RGBA { Tokens.resolve(Theme.surface) }

    private func with(_ c: RGBA, alpha: Double) -> RGBA { RGBA(r: c.r, g: c.g, b: c.b, a: alpha) }

    // MARK: 13. The zones and idea kinds

    @Test("Spec 13: .zones and .idea draw the hypnogram's ellipse and stops, radius 28, min height 176 / 120; neither changes with its size",
          arguments: [(Kind.zones, CGFloat(176)), (.idea, 120)])
    func zonesAndIdeaShapes(_ kind: Kind, _ minHeight: CGFloat) {
        let shape = GlowTileSpec.shape(for: kind)
        #expect([shape.rx, shape.ry, shape.cy] == [0.90, 0.95, 0.55])
        #expect(shape.stops.map(\.location) == [0, 0.34, 0.68, 1])
        #expect(shape.stops.map(\.opacity) == [0.97, 0.92, 0.55, 0.10])
        #expect(shape.radius == 28 && shape.minHeight == minHeight)
        for size in [CGSize(width: 350, height: minHeight), CGSize(width: 400, height: 600)] {
            #expect(GlowTileSpec.shape(for: kind, size: size) == shape, "\(kind) at \(size)")
        }
        let at = shape.stops.map(\.location).map { shape.overlayOpacity(atRadiusFraction: $0) }
        #expect(zip(at, [0.97, 0.92, 0.55, 0.10]).allSatisfy { abs($0 - $1) < 1e-12 }, "\(at)")
    }

    @Test("Spec 13: the zones tile pads 14 / 16 / 14 / 16, the idea tile 16 / 18 / 16 / 18; the others are unchanged")
    func zonesAndIdeaPadding() {
        #expect(GlowTileSpec.padding(for: .zones) == EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        #expect(GlowTileSpec.padding(for: .idea) == EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        for kind in [Kind.twoUp, .strain, .hypnogram] {
            #expect(GlowTileSpec.padding(for: kind) == EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
        }
        #expect(GlowTileSpec.padding(for: .panel) == EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        #expect(Kind.allCases.count == 6)
    }

    @Test("Spec 9: an idea tile is flat above 420 pt and only then; no other kind is ever flat by size",
          arguments: [(CGFloat(120), false), (420, false), (420.5, true), (440, true), (1_000, true)])
    func ideaFlatAbove420(_ height: CGFloat, _ flat: Bool) {
        #expect(GlowTileSpec.drawsFlat(.idea, size: CGSize(width: 350, height: height)) == flat)
        for kind in Kind.allCases where kind != .idea {
            #expect(!GlowTileSpec.drawsFlat(kind, size: CGSize(width: 350, height: height)), "\(kind)")
        }
    }

    /// The lowest contrast of `foreground` at `alpha` over a `kind` tile of `metric` at `size`, inside `insets`, from the overlay's
    /// formula on a 41 × 41 grid (the way `GlowTileKindTests` measures the board's kinds).
    private func worst(_ kind: Kind, _ metric: Color, _ size: CGSize, insets: EdgeInsets, _ foreground: RGBA,
                       alpha: Double) -> Double {
        let shape = GlowTileSpec.shape(for: kind, size: size)
        let (minX, minY) = (Double(insets.leading), Double(insets.top))
        let (maxX, maxY) = (Double(size.width - insets.trailing), Double(size.height - insets.bottom))
        var lowest = Double.infinity
        for i in 0...40 {
            for j in 0...40 {
                let x = minX + (maxX - minX) * Double(i) / 40, y = minY + (maxY - minY) * Double(j) / 40
                let ground = Tokens.over(with(screen, alpha: shape.overlayOpacity(x: x, y: y, in: size)), Tokens.resolve(metric))
                lowest = min(lowest, Tokens.ratio(with(foreground, alpha: alpha), on: ground))
            }
        }
        return lowest
    }

    struct ContrastCase: Sendable, CustomTestStringConvertible {
        let width: CGFloat, height: CGFloat
        let primary: Double, label: Double
        var testDescription: String { "\(Int(width)) × \(Int(height)): ≥ \(primary) / \(label)" }
    }

    /// Spec 8's floors; the table (§P5-3.3) is 7.77 / 5.46 at 350 × 176 and 7.42 … 7.02 / 5.25 … 5.01 at AX3's heights.
    @Test("Spec 8: the zones tile (strain, padded 14 / 16): textPrimary and the 78 % label over the padded rect", arguments: [
        ContrastCase(width: 350, height: 176, primary: 7.7, label: 5.4),
        ContrastCase(width: 335, height: 176, primary: 7.7, label: 5.4),
        ContrastCase(width: 362, height: 176, primary: 7.7, label: 5.4),
        ContrastCase(width: 400, height: 176, primary: 7.6, label: 5.35),
        ContrastCase(width: 350, height: 240, primary: 7.0, label: 5.0),
        ContrastCase(width: 350, height: 300, primary: 7.0, label: 5.0),
        ContrastCase(width: 350, height: 420, primary: 7.0, label: 5.0),
    ])
    func zonesContrast(_ c: ContrastCase) {
        let size = CGSize(width: c.width, height: c.height), pad = GlowTileSpec.padding(for: .zones)
        let primary = worst(.zones, Theme.metricStrain, size, insets: pad, ink, alpha: 1)
        let label = worst(.zones, Theme.metricStrain, size, insets: pad, ink, alpha: GlowTileSpec.labelOpacity)
        #expect(primary >= c.primary, "textPrimary \(primary)")
        #expect(label >= c.label, "78 % label \(label)")
    }

    @Test("Spec 8: the lit ticks (textPrimary) over the zones glow are far over 3:1 wherever the rows sit")
    func zonesTicks() {
        // The rows' band: under the head row (14 + 16 + 20) to 14 above the bottom, the ticks from the label column on.
        let size = CGSize(width: 350, height: 176)
        let ticks = worst(.zones, Theme.metricStrain, size, insets: EdgeInsets(top: 50, leading: 104, bottom: 14, trailing: 69),
                          ink, alpha: 1)
        #expect(ticks >= 11, "lit ticks \(ticks)")
    }

    @Test("Spec 9: the idea tile (recovery, padded 16 / 18): full ink at 120 / 150 / 260 / 420 high, and ≥ 4.5 at every size to 420",
          arguments: [(CGFloat(120), 6.2), (150, 5.8), (260, 5.1), (420, 4.8)])
    func ideaContrast(_ height: CGFloat, _ floor: Double) {
        let pad = GlowTileSpec.padding(for: .idea)
        let primary = worst(.idea, Theme.recovery, CGSize(width: 350, height: height), insets: pad, ink, alpha: 1)
        #expect(primary >= floor, "350 × \(height): \(primary)")
        for width in [CGFloat(335), 350, 362, 400] {
            for h in stride(from: CGFloat(120), through: GlowTileSpec.ideaFlatAbove, by: 20) {
                let ratio = worst(.idea, Theme.recovery, CGSize(width: width, height: h), insets: pad, ink, alpha: 1)
                #expect(ratio >= 4.5, "\(width) × \(h): \(ratio)")
            }
        }
    }

    @Test("Spec 9: why the idea tile's words are full ink: the board's 78 % label fails at 350 × 200; flat, the ink is over 16")
    func ideaLabelRule() {
        let label = worst(.idea, Theme.recovery, CGSize(width: 350, height: 200), insets: GlowTileSpec.padding(for: .idea), ink,
                          alpha: 0.78)
        #expect(label < 4.5, "the 78 % label at 350 × 200 is \(label): it would fail, so the tile's text is full ink")
        #expect(GlowTileSpec.labelOpacity(metric: Theme.recovery, typeSize: .large) == 1)
        #expect(Tokens.ratio(ink, on: surface) >= 16)
    }

    @Test("Spec 9: the Volt dot at the idea tile's first line is over 6:1 on the glow")
    func ideaVoltDot() {
        // The dot: 6 pt at the content's leading edge (18), centred on the 13 pt label's line (16 + about 8).
        let volt = Tokens.resolve(Theme.signal)
        let ratio = worst(.idea, Theme.recovery, CGSize(width: 350, height: 120),
                          insets: EdgeInsets(top: 21, leading: 18, bottom: 120 - 27, trailing: 350 - 24), volt, alpha: 1)
        #expect(ratio >= 6, "Volt dot \(ratio)")
    }

    /// The rendered tile, worst pixel over its padded rect against `textPrimary`.
    private func renderedWorst(_ kind: Kind, _ metric: Color, _ size: CGSize) throws -> (ratio: Double, shot: ControlRender) {
        let shot = try #require(ControlRender(GlowTile(metric, kind: kind, reduceTransparency: false) { Color.clear }
            .frame(width: size.width, height: size.height), scale: 2))
        let pad = GlowTileSpec.padding(for: kind)
        var lowest = Double.infinity
        for y in stride(from: Double(pad.top), through: Double(size.height - pad.bottom), by: 1) {
            for x in stride(from: Double(pad.leading), through: Double(size.width - pad.trailing), by: 1) {
                var p = shot.at(min(x, Double(size.width) - 0.25), min(y, Double(size.height) - 0.25))
                p.a = 1
                lowest = min(lowest, Tokens.ratio(ink, on: p))
            }
        }
        return (lowest, shot)
    }

    @Test("paddedRectContrast, rendered: the zones tile at 350 × 176 and the idea tile at 350 × 420 keep textPrimary over 4.5")
    func renderedPaddedRect() throws {
        let zones = try renderedWorst(.zones, Theme.metricStrain, CGSize(width: 350, height: 176))
        #expect(zones.ratio >= 7.5, "zones \(zones.ratio)")
        let idea = try renderedWorst(.idea, Theme.recovery, CGSize(width: 350, height: 420))
        #expect(idea.ratio >= 4.7, "idea at 420 \(idea.ratio)")
    }

    @Test("Spec 9: rendered, an idea tile 440 high is flat surface with the 2 pt recovery border; 120 high it glows")
    func ideaRendersFlatAbove420() throws {
        let tall = try #require(ControlRender(GlowTile(Theme.recovery, kind: .idea, minHeight: 440, reduceTransparency: false) {
            Color.clear
        }.frame(width: 350), scale: 2))
        #expect(abs(tall.size.height - 440) < 0.5, "\(tall.size)")
        for (x, y) in [(175.0, 220.0), (30.0, 30.0), (320.0, 410.0)] {
            #expect(Tokens.matches(tall.at(x, y), surface), "flat at \(x), \(y): \(Tokens.describe(tall.at(x, y)))")
        }
        #expect(tall.at(175, 0.5).near(Tokens.resolve(Theme.recovery), 3), "the border: \(Tokens.describe(tall.at(175, 0.5)))")
        let short = try #require(ControlRender(GlowTile(Theme.recovery, kind: .idea, reduceTransparency: false) {
            Color.clear
        }.frame(width: 350), scale: 2))
        #expect(abs(short.size.height - 120) < 0.5)
        #expect(!Tokens.matches(short.at(30, 30), surface), "the 120 pt tile glows: \(Tokens.describe(short.at(30, 30)))")
    }

    // MARK: 14. TickRow's arrangements and the zone block's rule

    private func tickRow(_ label: String = "Z4 · Threshold", minutes: Double? = 40) -> TickRow {
        TickRow(label: Text(verbatim: label), minutes: minutes, scaleMax: 40, value: Text(verbatim: "40m"),
                accessibilityLabel: Text(verbatim: "Zone 4"))
    }

    private func isInk(_ p: RGBA) -> Bool { p.near(ink, 3) }

    @Test("Spec 14: aligned, the label column is exactly the given width: the ticks start at column + 12, one line 12 high",
          arguments: [CGFloat(74), 76, 90])
    func alignedColumn(_ column: CGFloat) throws {
        let view = tickRow().environment(\.tickRowArrangement, .aligned(labelColumn: column)).frame(width: 330)
            .background(Theme.background)
        let shot = try #require(ControlRender(view, scale: 2))
        #expect(abs(shot.size.height - 12) < 0.5, "one line: \(shot.size)")
        let ticks = try #require(shot.bounds(xs: 0...330, ys: 0...12, where: isInk), "ticks")
        #expect(abs(ticks.minX - (column + 12)) <= 0.5, "ticks start at \(ticks.minX), column \(column)")
        #expect(abs(ticks.minX + 177 - (column + 12 + 177)) <= 0.5)
    }

    @Test("Spec 14: stacked, the ticks are under the label line, 177 wide and leading, at the default size and at AX3",
          arguments: [DynamicTypeSize.large, .accessibility3])
    func stackedTicks(_ typeSize: DynamicTypeSize) throws {
        let view = tickRow(minutes: 40).environment(\.tickRowArrangement, .stacked).environment(\.dynamicTypeSize, typeSize)
            .frame(width: 350).background(Theme.background)
        let shot = try #require(ControlRender(view, scale: 2))
        let height = Double(shot.size.height)
        #expect(height >= 12 + 4 + 10, "a text line and 4 pt above the ticks: \(height)")
        let ticks = try #require(shot.bounds(xs: 0...350, ys: (height - 12)...height, where: isInk), "ticks")
        #expect(abs(ticks.minX) <= 0.5 && abs(ticks.width - 177) <= 0.5, "ticks \(ticks)")
        #expect(abs(ticks.maxY - height) <= 0.5)
    }

    @Test("Spec 14: stacked even where one line would fit; aligned even where automatic would stack (a long label)")
    func arrangementOverridesTheRow() throws {
        let stacked = try #require(ControlRender(tickRow("Z1").environment(\.tickRowArrangement, .stacked).frame(width: 350), scale: 2))
        #expect(stacked.size.height > 20, "\(stacked.size)")
        let aligned = try #require(ControlRender(tickRow("Z4 · Threshold · long").environment(\.tickRowArrangement,
                                                                                               .aligned(labelColumn: 120))
                .frame(width: 350), scale: 2))
        #expect(abs(aligned.size.height - 12) < 0.5, "\(aligned.size)")
    }

    @Test("Inside a glow tile a tick row's label takes the tile's label ink (78 %), outside it textSecondary")
    func glowLabelInk() throws {
        func brightestLabel(_ glow: Double?) throws -> Double {
            let view = tickRow("Z4 · Threshold").environment(\.glowLabelOpacity, glow).frame(width: 330).background(Theme.background)
            let shot = try #require(ControlRender(view, scale: 4))
            var best = 0.0
            for y in stride(from: 0.125, to: 12, by: 0.25) {
                for p in shot.row(y, xs: 0...76) { best = max(best, Tokens.luminance(p)) }
            }
            return best
        }
        let glow = try brightestLabel(0.78), plain = try brightestLabel(nil)
        let expectedGlow = Tokens.luminance(Tokens.over(with(ink, alpha: 0.78), screen))
        let expectedPlain = Tokens.luminance(Tokens.over(Tokens.resolve(Theme.textSecondary), screen))
        #expect(abs(glow - expectedGlow) < 0.03, "78 %: \(glow) vs \(expectedGlow)")
        #expect(abs(plain - expectedPlain) < 0.03, "textSecondary: \(plain) vs \(expectedPlain)")
    }

    struct RuleCase: Sendable, CustomTestStringConvertible {
        let widest: CGFloat, available: CGFloat, ax: Bool
        let expected: TickRowArrangement
        var testDescription: String { "widest \(widest) in \(available)\(ax ? " AX" : "") → \(expected)" }
    }

    @Test("Spec 14: the zone block aligns when column + 12 + 177 + 12 + 40 fits, else stacks; from AX1 it stacks", arguments: [
        RuleCase(widest: 76, available: 318, ax: false, expected: .aligned(labelColumn: 76)),
        RuleCase(widest: 75.3, available: 318, ax: false, expected: .aligned(labelColumn: 76)),
        RuleCase(widest: 76, available: 317, ax: false, expected: .aligned(labelColumn: 76)),
        RuleCase(widest: 76, available: 316.9, ax: false, expected: .stacked),
        RuleCase(widest: 76, available: 303, ax: false, expected: .stacked),
        RuleCase(widest: 50, available: 318, ax: false, expected: .aligned(labelColumn: 74)),
        RuleCase(widest: 76, available: 600, ax: true, expected: .stacked),
    ])
    func zoneBlockRule(_ c: RuleCase) {
        #expect(ZoneBlock.arrangement(widestLabel: c.widest, available: c.available, isAccessibilitySize: c.ax) == c.expected)
    }

    @Test("Spec 15: lit ticks for the board's zones on the 40-minute scale")
    func litCountsOn40() {
        let pairs: [(Double, Int)] = [(11, 8), (24, 18), (27, 20), (14, 11), (6, 5), (40, 30), (90, 30)]
        for (minutes, lit) in pairs {
            #expect(TickRow.litCount(minutes: minutes, scaleMax: ZoneBlock.defaultScaleMax) == lit, "\(minutes) min")
        }
    }

    // MARK: 23. DeltaLabel's colours

    @Test("Spec 23: a good change is the metric's colour, a bad one alert, flat or neutral textSecondary; never a red good change")
    func deltaColours() {
        let up = MetricDelta(current: 84, reference: 73), down = MetricDelta(current: 66, reference: 73)
        let flat = MetricDelta(current: 80, reference: 79.6)
        #expect(DeltaLabel.color(up, spec: .readiness) == MetricSpec.readiness.color, "Today's readiness keeps its colour")
        #expect(DeltaLabel.color(up, spec: .hrv) == MetricSpec.hrv.color)
        #expect(DeltaLabel.color(up, spec: .sleepMin) == Theme.metricSleep)
        #expect(DeltaLabel.color(down, spec: .sleepMin) == Theme.alert)
        #expect(DeltaLabel.color(flat, spec: .sleepMin) == Theme.textSecondary)
        #expect(DeltaLabel.color(up, spec: .strain) == Theme.textSecondary)
        // Resting HR: lower is better; drawn in alert until MetricSpec moves it, so its good change is ink.
        #expect(DeltaLabel.color(MetricDelta(current: 47, reference: 50), spec: .rhr) == Theme.textPrimary)
        #expect(DeltaLabel.color(MetricDelta(current: 53, reference: 50), spec: .rhr) == Theme.alert)
        #expect(DeltaLabel.goodColor(.activeKcal) != Theme.warning)
    }

    // MARK: 20. TrendLine

    @Test("Spec 20: the y scale spans the series and the band with a 2 pt inset; the band is a rectangle across the width")
    func trendDomain() throws {
        let size = CGSize(width: 318, height: 48)
        let g = TrendLineGeometry(values: [60, 62, 64], band: 50...70, size: size)
        #expect(g.domain == 50...70)
        let band = try #require(g.bandRect)
        #expect(abs(band.minY - 2) < 1e-9 && abs(band.maxY - 46) < 1e-9 && band.minX == 0 && band.width == 318, "\(band)")
        // 60 is the middle of 50…70: y 24.
        #expect(abs((g.runs.first?.first?.y ?? 0) - 24) < 1e-9)
        // Without a band the series alone: 60 at the bottom inset, 64 at the top.
        let alone = TrendLineGeometry(values: [60, 62, 64], band: nil, size: size)
        #expect(alone.domain == 60...64)
        #expect(alone.runs.first?.map(\.y) == [46, 24, 2])
        #expect(alone.runs.first?.map(\.x) == [0, 159, 318])
    }

    @Test("Spec 20: a nil breaks the path, a lone point is a run of one (the 3 pt dot), a flat series sits at mid height")
    func trendRuns() {
        let size = CGSize(width: 80, height: 48)
        let g = TrendLineGeometry(values: [1, 2, nil, 4, nil, nil, 6, 7, 8], band: nil, size: size)
        #expect(g.runs.map(\.count) == [2, 1, 3])
        #expect(g.runs[1].first?.x == 30, "the lone point at day 3 of 0…8: \(String(describing: g.runs[1].first))")
        let flat = TrendLineGeometry(values: [5, 5, 5], band: nil, size: size)
        #expect(flat.runs.first?.allSatisfy { $0.y == 24 } == true)
        let single = TrendLineGeometry(values: [5], band: nil, size: size)
        #expect(single.runs == [[CGPoint(x: 40, y: 24)]])
        #expect(TrendLineGeometry(values: [nil, nil], band: 1...2, size: size).runs.isEmpty)
        #expect(TrendLine.dotSize == 3 && TrendLine.lineWidth == 1.4 && TrendLine.inset == 2)
    }

    @Test("Spec 20: the spoken ending is above / within (bounds included) / below the band; none without a band or a value")
    func trendEnding() {
        #expect(TrendLine.ending(values: [60, 71], band: 50...70) == .above)
        #expect(TrendLine.ending(values: [60, 70], band: 50...70) == .within)
        #expect(TrendLine.ending(values: [60, 50, nil], band: 50...70) == .within)
        #expect(TrendLine.ending(values: [60, 49.9], band: 50...70) == .below)
        #expect(TrendLine.ending(values: [60], band: nil) == nil)
        #expect(TrendLine.ending(values: [nil], band: 50...70) == nil)
        #expect(TrendLine.spoken(.above) == "ending above its usual range")
    }

    @Test("Spec 20: pending is a flat 1 pt line across the middle at ink 22 %, nothing else")
    func trendPending() throws {
        let view = TrendLine(values: [1, 5, 3], band: 0...6, color: Theme.recovery, isPending: true,
                             accessibilityLabel: Text(verbatim: "HRV")).frame(width: 318).background(Theme.surface)
        let shot = try #require(ControlRender(view, scale: 2))
        let line = Tokens.over(with(ink, alpha: TrendLine.pendingOpacity), surface)
        #expect(shot.at(100, 24.25).near(line, 3), "\(Tokens.describe(shot.at(100, 24.25)))")
        #expect(Tokens.matches(shot.at(100, 10), surface) && Tokens.matches(shot.at(100, 40), surface))
    }

    // MARK: S11. The date strip

    private func days(selected: Int = 0, pending: Int? = nil) -> [DateStrip.Day] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).reversed().map { back in
            DateStrip.Day(date: DayFormat.shift(today, days: -back), strain: back == 6 ? nil : Double(10 + back),
                          isSelected: back == selected, marker: back == pending ? .pending : .scored, isToday: back == 0)
        }
    }

    @Test("S11: week(endingAt:) marks only its last day as today; the spoken value adds Today and the pending words")
    func weekToday() {
        let today = Calendar.current.startOfDay(for: .now)
        let week = DateStrip.week(endingAt: today, selected: DayFormat.shift(today, days: -2)) { _ in nil }
        #expect(week.map(\.isToday) == [false, false, false, false, false, false, true])
        #expect(week.filter(\.isSelected).map(\.date) == [DayFormat.shift(today, days: -2)])
        let day = DateStrip.Day(date: today, strain: 15, isSelected: true, marker: .pending, isToday: true)
        #expect(day.spokenValue.hasPrefix("Strain ") && day.spokenValue.contains("Today") && day.spokenValue.contains("not scored yet"),
                "\(day.spokenValue)")
        #expect(DateStrip.Day(date: today, strain: 30, isSelected: false).arc == 1)
        #expect(DateStrip.Day(date: today, strain: nil, isSelected: false).arc == nil)
        #expect(abs((DateStrip.Day(date: today, strain: 10.5, isSelected: false).arc ?? 0) - 0.5) < 1e-12)
    }

    @Test("S11: the only Volt in the strip is the 4 pt dot under today; a pending day has an outline dot; chips are 80 high")
    func stripDots() throws {
        let view = DateStrip(days: days(selected: 3, pending: 2)) { _ in }.frame(width: 350).background(Theme.background)
        let shot = try #require(ControlRender(view, scale: 4))
        let height = Double(shot.size.height)
        #expect(abs(height - 80) <= 1.5, "the chip is about 64 + 2 × 8: \(shot.size)")
        let volt = Tokens.resolve(Theme.signal)
        let voltBox = try #require(shot.bounds(xs: 0...350, ys: 0...80) { $0.near(volt, 24) }, "the Volt dot")
        #expect(voltBox.minX >= 300 && voltBox.width <= 4.5 && voltBox.height <= 4.5, "under the last chip, 4 pt: \(voltBox)")
        #expect(abs(voltBox.maxY - (height - 8)) <= 0.5, "8 above the chip's bottom: \(voltBox)")
        // The pending day (two back, the fifth chip of 50): its dot's box is lighter than the screen.
        let chip = 50.0 * 4
        let pending = shot.bounds(xs: chip...(chip + 50), ys: 66...73) { Tokens.luminance($0) > Tokens.luminance(self.screen) + 0.005 }
        #expect(pending != nil, "an outline dot under the pending day")
        // The selected chip (three back, the fourth) is on surface, radius 16.
        #expect(Tokens.matches(shot.at(150 + 25, 4), surface), "\(Tokens.describe(shot.at(175, 4)))")
        #expect(Tokens.matches(shot.at(25, 4), screen))
    }

    @Test("S11: the ring's arc is strain blue from 12 o'clock; an unscored day draws only the track")
    func stripRing() throws {
        let shot = try #require(ControlRender(DateStrip(days: days()) { _ in }.frame(width: 350).background(Theme.background), scale: 4))
        let blue = Tokens.resolve(Theme.metricStrain)
        // Ring centre: 8 + the initial's line (about 15) + 6 + 16 from the top; the arc starts at 12 o'clock, 16 above.
        let scored = shot.bounds(xs: (300 + 25 - 3)...(300 + 25 + 3), ys: 20...40) { $0.near(blue, 20) }
        #expect(scored != nil, "the last day's arc passes 12 o'clock")
        let unscored = shot.bounds(xs: 0...50, ys: 18...70) { $0.near(blue, 20) }
        #expect(unscored == nil, "the oldest day has no strain: no arc")
    }

    // MARK: placeholder, neutral tile

    @Test("The placeholder outline is surface inside a 1 pt separator border, at the row's height, also without content")
    func placeholderOutline() throws {
        // In a stack, as on a screen: the outline-only row is a view there too.
        let rows = VStack(spacing: 0) {
            PlaceholderRow(height: 60, radius: 20)
            PlaceholderRow(height: 46) { Text(verbatim: "Loading…") }
        }
        let shot = try #require(ControlRender(rows.frame(width: 350).background(Theme.background), scale: 4))
        #expect(abs(shot.size.height - 106) < 0.5, "60 + 46: \(shot.size)")
        #expect(Tokens.matches(shot.at(175, 30), surface))
        let border = Tokens.over(Tokens.resolve(Theme.separator), surface)
        #expect(shot.at(175, 0.4).near(border, 3), "top edge \(Tokens.describe(shot.at(175, 0.4)))")
        #expect(shot.at(0.4, 30).near(border, 3), "leading edge \(Tokens.describe(shot.at(0.4, 30)))")
        #expect(Tokens.matches(shot.at(175, 1.5), surface), "1 pt, not more")
    }

    @Test("A row's chevron grows with the text size: 12 pt by default, larger at AX3")
    func rowGlyphScales() throws {
        func chevronHeight(_ typeSize: DynamicTypeSize) throws -> CGFloat {
            let row = GroupedRowLabel(Text(verbatim: "Units"), accessory: .chevron)
                .frame(width: 350).background(Theme.surface).environment(\.dynamicTypeSize, typeSize)
            let shot = try #require(ControlRender(row, scale: 4))
            let ink = try #require(shot.bounds(xs: 300...350, ys: 0...Double(shot.size.height)) {
                Tokens.luminance($0) > Tokens.luminance(surface) + 0.03
            }, "the chevron at \(typeSize)")
            return ink.height
        }
        let regular = try chevronHeight(.large), large = try chevronHeight(.accessibility3)
        #expect(regular > 7 && regular < 14, "about 12 pt's chevron: \(regular)")
        #expect(large > regular * 1.6, "AX3 \(large) vs \(regular)")
    }

    @Test("The neutral tile's numbers: 80 high, radius 22, padding 14 / 16 / 12, value 24, unit 3 after")
    func neutralTileNumbers() throws {
        #expect(NeutralTile.height == 80 && NeutralTile.radius == 22 && NeutralTile.valueSize == 24 && NeutralTile.unitGap == 3)
        #expect(NeutralTile.padding == EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
        let shot = try #require(ControlRender(NeutralTile(Text(verbatim: "Steps"), value: Text(verbatim: "8,412"),
                                                          note: Text(verbatim: "Goal 10k")).frame(width: 169), scale: 2))
        #expect(abs(shot.size.height - 80) < 0.5, "\(shot.size)")
        #expect(Tokens.matches(shot.at(84, 40), surface) || Tokens.luminance(shot.at(84, 40)) > Tokens.luminance(surface))
    }
}
