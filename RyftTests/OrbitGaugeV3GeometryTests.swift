import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Gauge v3 (Nocturne PR 3) as numbers: docs/work/2026-11-16-nocturne/design.md §P3-8, cases 1 to 12. Pure; the board's
/// values are readiness 84, recovery 82 %, sleep 94 %, strain 12.4 of 21 at S = 260. Angles in the board's convention
/// are the code's less 90 (the board measures from 3 o'clock).
@MainActor
@Suite("OrbitGauge v3: geometry")
struct OrbitGaugeV3GeometryTests {
    typealias G = OrbitGaugeGeometry

    private static let board = G.metrics(forSide: 260)

    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-9) -> Bool { abs(a - b) <= tolerance }
    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    /// A code angle in the board's convention.
    private func board(_ code: Double) -> Double { code - 90 }

    // MARK: 1. radii and widths

    @Test func radiiAndWidthsAt260() {
        let m = Self.board
        #expect(m.side == 260)
        #expect(near(m.outerRadius, 118) && near(m.innerRadius, 88) && near(m.centreRadius, 58))
        #expect(near(m.outerRadius / m.side, 0.4538, 0.0001))
        #expect(near(m.innerRadius / m.side, 0.3385, 0.0001))
        #expect(near(m.centreRadius / m.side, 0.2231, 0.0001))
        #expect(near(m.arcStroke, 3.5))
        #expect(near(m.outerTick.width, 1.2) && near(m.outerTick.height, 6))
        #expect(near(m.innerTick.width, 1.3) && near(m.innerTick.height, 7))
        #expect(near(m.dotRadius, 7) && near(m.dotAir, 3) && near(m.haloRadius, 15) && m.showsHalo)
        #expect(near(m.voltRadius, 5) && near(m.voltAir, 2.5))
        #expect(near(m.bandRadius, 109.5) && near(m.bandStroke, 3))
        #expect(near(m.hollowStroke, 1.5))
        // The rail is thinner than the arcs at the board's size.
        #expect(m.bandStroke < m.arcStroke)
    }

    // MARK: 2. pitch

    @Test func tickPitch() {
        let m = Self.board
        #expect(m.outerTickCount == 128)
        let pitch = 2 * .pi * m.outerRadius / CGFloat(m.outerTickCount)
        #expect(near(pitch, 5.792, 0.005))
        #expect(near(pitch - m.outerTick.width, 4.592, 0.005))
        #expect(G.tickCount(radius: 118, pitch: G.boardOuterPitch) == 128)
        #expect(m.innerTickCount == 60)
        #expect(near(2 * .pi * m.centreRadius / CGFloat(m.innerTickCount), 6.074, 0.005))
    }

    // MARK: 3. tick counts by S

    @Test(arguments: [
        (260, 128, 60), (172, 128, 60), (150, 128, 60),
        (149.9, 64, 30), (124, 64, 30), (100, 64, 30),
        (99.9, 0, 0), (84, 0, 0), (56, 0, 0),
    ] as [(CGFloat, Int, Int)])
    func tickCountsBySide(_ side: CGFloat, _ outer: Int, _ inner: Int) {
        let m = G.metrics(forSide: side)
        #expect(m.outerTickCount == outer && m.innerTickCount == inner, "S \(side)")
        #expect((m.tier == .solid) == (outer == 0), "S \(side)")
    }

    @Test func tickFloors() {
        let medium = G.metrics(forSide: 124)
        #expect(medium.outerTick.width >= 0.75 && medium.outerTick.height >= 3)
        #expect(medium.innerTick.width >= 0.75 && medium.innerTick.height >= 3)
        #expect(near(G.metrics(forSide: 172).outerTick.width, 0.795, 0.002))
        for side in stride(from: CGFloat(56), through: 260, by: 4) {
            let m = G.metrics(forSide: side)
            #expect(m.outerTick.width >= G.minTickWidth && m.innerTick.height >= G.minTickLength, "S \(side)")
            #expect(m.arcStroke >= G.minStroke, "S \(side)")
        }
    }

    // MARK: 4. arc end angles

    @Test(arguments: [
        (G.Orbit.strain, 12.4 / 21, 122.571), (.strain, 0, -90), (.strain, 1, 269.99), (.strain, 25.0 / 21, 269.99),
        (.recovery, 0.82, -227.2), (.recovery, 0, -96), (.recovery, 1, -256), (.recovery, 0.5, -176),
        (.sleep, 0.94, 66.4), (.sleep, 0, -84), (.sleep, 1, 76), (.sleep, 0.5, -4),
    ] as [(G.Orbit, Double, Double)])
    func arcEndAnglesInTheBoardsConvention(_ orbit: G.Orbit, _ fraction: Double, _ expected: Double) {
        #expect(near(board(orbit.headDegrees(for: fraction)), expected, 0.01), "\(orbit) \(fraction)")
    }

    @Test func theBoardValuesLandWhereTheBoardDrawsThem() throws {
        let v = OrbitGaugeValues.previewBoard
        let strain = try #require(v.strainFraction), recovery = try #require(v.recoveryFraction)
        let sleep = try #require(v.sleepFraction)
        #expect(near(board(G.Orbit.strain.headDegrees(for: strain)), 122.6, 0.5))
        #expect(near(board(G.Orbit.recovery.headDegrees(for: recovery)), -227, 0.5))
        #expect(near(board(G.Orbit.sleep.headDegrees(for: sleep)), 66, 0.5))
    }

    // MARK: 5. the middle orbit's split

    @Test func theMiddleSplitAgainstToday() {
        #expect(G.innerInset == 6 && G.innerSpan == 160)
        #expect(G.Orbit.recovery.startDegrees == -6 && G.Orbit.sleep.startDegrees == 6)
        #expect(G.Orbit.recovery.headDegrees(for: 1) == -166 && G.Orbit.sleep.headDegrees(for: 1) == 166)
        func apart(_ m: G.Metrics, _ a: Double, _ b: Double) -> CGFloat {
            let p = G.point(centre: .zero, radius: m.innerRadius, degrees: a)
            let q = G.point(centre: .zero, radius: m.innerRadius, degrees: b)
            return hypot(p.x - q.x, p.y - q.y)
        }
        #expect(near(apart(Self.board, -6, 6), 18.4, 0.05))
        #expect(near(apart(Self.board, -166, 166), 42.6, 0.05))
        for side in stride(from: CGFloat(56), through: 260, by: 1) {
            let m = G.metrics(forSide: side)
            #expect(apart(m, -6, 6) >= 2 * m.dotRadius, "start dots touch at S \(side)")
        }
    }

    // MARK: 6. readiness

    @Test(arguments: [
        (Optional(84), 50, 25), (0, 0, 0), (100, 60, 30), (1, 1, 0), (120, 60, 30), (-5, 0, 0), (nil, 0, 0),
    ] as [(Int?, Int, Int)])
    func litTicksForAReadiness(_ readiness: Int?, _ fine: Int, _ medium: Int) {
        #expect(G.litTicks(readiness: readiness, count: 60) == fine, "\(String(describing: readiness)) of 60")
        #expect(G.litTicks(readiness: readiness, count: 30) == medium, "\(String(describing: readiness)) of 30")
    }

    @Test func theVoltDotSitsAtTheValue() throws {
        let at84 = try #require(G.voltDegrees(readiness: 84))
        #expect(near(at84, 302.4, 1e-9))
        #expect(near(board(at84), 212.4, 1e-9) && near(board(at84) - 360, -147.6, 1e-9))
        // 0 and 100 are both the top; past 100 it clamps there.
        let top = G.point(centre: .zero, radius: 58, degrees: 0)
        for r in [0, 100, 120, -5] {
            let p = G.point(centre: .zero, radius: 58, degrees: try #require(G.voltDegrees(readiness: r)))
            #expect(hypot(p.x - top.x, p.y - top.y) < 1e-9, "readiness \(r)")
        }
        // No readiness, no dot: Volt marks a value.
        #expect(G.voltDegrees(readiness: nil) == nil)
        let scene = OrbitGaugeScene(mode: .scored(OrbitGaugeValues(recovery: 0.8, sleep: 0.9, strain: 12)), size: .custom(dial: 248))
        #expect(!scene.showsVolt && scene.readiness == nil)
        #expect(OrbitGaugeScene(mode: .scored(.previewBoard), size: .custom(dial: 248)).showsVolt)
    }

    // MARK: 7. omitted ticks

    @Test func theTicksBesideTheDotsAreLeftOut() {
        let m = Self.board
        #expect(near(G.clearDegrees(cut: m.dotCut, radius: m.outerRadius), 4.857, 0.01))
        #expect(near(G.clearDegrees(cut: m.voltCut, radius: m.centreRadius), 7.41, 0.01))
        let strain = G.Orbit.strain.headDegrees(for: 12.4 / 21)
        let outer = G.drawnTicks(count: 128, ringRadius: m.outerRadius, fraction: 1, lit: false,
                                 dot: (strain, m.outerRadius), cut: m.dotCut)
        #expect(Set(0..<128).subtracting(outer) == [74, 75, 76, 77])
        let volt = 302.4
        let unlit = G.drawnTicks(count: 60, ringRadius: m.centreRadius, fraction: 1, lit: false,
                                 dot: (volt, m.centreRadius), cut: m.voltCut)
        #expect(Set(0..<60).subtracting(unlit) == [50, 51])
        let lit = G.drawnTicks(count: 60, ringRadius: m.centreRadius, fraction: 0.84, lit: true,
                               dot: (volt, m.centreRadius), cut: m.voltCut)
        #expect(lit == Array(0..<50), "the first 50 are lit and none is left out")
        #expect(lit.contains(49))
    }

    /// No tick is partly cut: every drawn tick is a whole rectangle (the tick rings are never under a cut), and at the
    /// board's values none of them reaches into a dot's cleared ring.
    @Test func noTickIsPartlyCut() {
        let m = Self.board
        let rect = CGRect(x: 0, y: 0, width: 260, height: 260)
        let centre = CGPoint(x: 130, y: 130)
        func check(_ shape: OrbitTicks, _ label: String) {
            let dot = (degrees: shape.dotStart + shape.dotSweep, radius: shape.dotRadius)
            let drawn = G.drawnTicks(count: shape.count, ringRadius: shape.radius, fraction: shape.fraction, lit: shape.lit,
                                     dot: dot, cut: shape.cut)
            var moves = 0
            shape.path(in: rect).forEach { if case .move = $0 { moves += 1 } }
            #expect(moves == drawn.count, "\(label): one whole rectangle per drawn tick")
            let d = G.point(centre: centre, radius: dot.radius, degrees: dot.degrees)
            for i in drawn {
                // The dot's centre in the tick's own frame (tick centred at the origin, its length along y).
                let a = G.tickDegrees(i, count: shape.count) * .pi / 180
                let t = G.point(centre: centre, radius: shape.radius, degrees: G.tickDegrees(i, count: shape.count))
                let (dx, dy) = (d.x - t.x, d.y - t.y)
                let local = CGPoint(x: dx * CGFloat(cos(a)) + dy * CGFloat(sin(a)), y: -dx * CGFloat(sin(a)) + dy * CGFloat(cos(a)))
                let ox = max(abs(local.x) - shape.tick.width / 2, 0), oy = max(abs(local.y) - shape.tick.height / 2, 0)
                #expect(hypot(ox, oy) >= shape.cut, "\(label): tick \(i) reaches into the cut")
            }
        }
        let strain = OrbitGaugeScene.Dot(radius: m.outerRadius, start: 0, sweep: G.Orbit.strain.sweep(for: 12.4 / 21))
        check(OrbitTicks(count: 128, radius: m.outerRadius, tick: m.outerTick, fraction: 1, lit: false, dot: strain,
                         cut: m.dotCut), "outer")
        let volt = OrbitGaugeScene.Dot(radius: m.centreRadius, start: 0, sweep: 302.4)
        check(OrbitTicks(count: 60, radius: m.centreRadius, tick: m.innerTick, fraction: 1, lit: false, dot: volt,
                         cut: m.voltCut), "inner unlit")
        check(OrbitTicks(count: 60, radius: m.centreRadius, tick: m.innerTick, fraction: 0.84, lit: true, dot: volt,
                         cut: m.voltCut), "inner lit")
    }

    // MARK: 8. the strain rail

    @Test func theStrainRailFromS102() throws {
        let band: ClosedRange<Double> = 8...13
        #expect(G.drawsBandRail(band, dial: 90))
        #expect(OrbitGaugeSize.custom(dial: 90).frame == 102)
        #expect(!G.drawsBandRail(band, dial: 89.9))
        #expect(!G.drawsBandRail(nil, dial: 248))
        #expect(G.drawsBandRail(band, dial: 248))
        // Unchanged from PR 4: the band's upper end on the strain scale.
        #expect(near(try #require(G.strainSplitDegrees(band: band)), 13.0 / 21 * 359.99, 1e-9))
    }

    // MARK: 9. the centre

    @Test func theCentreRule() {
        typealias Look = OrbitGauge.CentreLook
        #expect(OrbitGauge.centreLook("84", side: 260, style: .dots, typeSize: .large) == Look.dots)
        #expect(OrbitGauge.centreLook("84", side: 172, style: .dots, typeSize: .large) == Look.light)
        #expect(OrbitGauge.centreLook("100", side: 260, style: .dots, typeSize: .large) == Look.light)
        #expect(OrbitGauge.centreLook("84", side: 260, style: .dots, typeSize: .accessibility1) == Look.light)
        #expect(OrbitGauge.centreLook("84", side: 260, style: .light, typeSize: .large) == Look.light)
        // A missing readiness is the unlit grid where "00" fits.
        #expect(OrbitGauge.centreLook(nil, side: 260, style: .dots, typeSize: .large) == Look.dots)
        // "84" (74 pt) fits from S 205.2 up.
        #expect(near(Self.board.centreSlotWidth, 93.74, 0.01))
        #expect(near(G.metrics(forSide: 172).centreSlotWidth, 62.01, 0.01))
        #expect(OrbitGauge.centreLook("84", side: 206, style: .dots, typeSize: .large) == Look.dots)
        #expect(OrbitGauge.centreLook("84", side: 205, style: .dots, typeSize: .large) == Look.light)
        #expect(near(OrbitGauge.lightNumeralSize(side: 260), 52, 1e-9))
    }

    // MARK: 10. sizes

    @Test func sizesUnchanged() {
        #expect(OrbitGauge.Size.small.frame == 84)
        #expect(OrbitGauge.Size.medium.frame == 124)
        #expect(OrbitGauge.Size.large.frame == 172)
        #expect(OrbitGauge.Size.previewBoard.frame == 260)
        #expect(OrbitGaugeGeometry.minDialForNumber == 56)
    }

    // MARK: 11. calibrating

    @Test func calibratingDrawsSevenSegmentsAndNoTickRing() {
        for size in [OrbitGaugeSize.custom(dial: 248), .large, .medium, .small] {
            let scene = OrbitGaugeScene(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: size)
            #expect(!scene.drawsOuterTicks, "\(size)")
            #expect(scene.calibration?.counted == 3)
            let m = scene.metrics
            let cap = Double(m.outerStroke / 2 / m.outerRadius) * 180 / .pi
            let s = G.segments(required: 7, dial: size.dial)
            #expect(s.count == 7)
            #expect(near(s[0].start - cap, 9, 1e-9) && near(s[6].start + s[6].sweep + cap, 351, 1e-9))
            for i in 0..<6 { #expect(near((s[i + 1].start - cap) - (s[i].start + s[i].sweep + cap), 5, 1e-9)) }
        }
        #expect(OrbitGaugeScene(mode: .scored(.previewBoard), size: .large).drawsOuterTicks)
        #expect(!OrbitGaugeScene(mode: .scored(.previewBoard), size: .small).drawsOuterTicks)
    }

    // MARK: 12. palette and timings

    private func hex(_ colour: Color) -> String {
        let ui = UIColor(colour).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    @Test func thePaletteAndTheEntranceTimings() {
        let p = OrbitGaugePalette.assets
        #expect(hex(p.ink) == "F2F1EC" && hex(p.ink) == hex(Theme.textPrimary))
        #expect(hex(p.signal) == hex(Theme.signal) && hex(p.signal) == "D8FF4F")
        #expect(hex(p.recovery) == "63D2B4")
        #expect(hex(p.sleep) == "9B8AF0")
        #expect(hex(p.strain) == "5E8BEA")
        #expect(hex(p.strainPastBand) == "E36B5B")
        #expect(OrbitEntranceFrame.tracksEnd == 0.25)
        #expect(OrbitEntranceFrame.flightStart == 0.15 && OrbitEntranceFrame.flightEnd == 0.60)
        #expect(OrbitEntranceFrame.dotStagger == 0.03 && OrbitEntranceFrame.turnDegrees == 40)
        #expect(OrbitEntranceFrame.glideStart == 0.60 && OrbitEntranceFrame.glideDuration == 0.25)
        #expect(OrbitEntranceFrame.end == 0.85 && OrbitEntranceFrame.fadeDuration == 0.25)
    }
}
