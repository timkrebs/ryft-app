import Foundation
import SwiftUI
import Testing
@testable import Ryft

/// The launch's timeline as numbers (docs/work/2026-11-16-nocturne/design.md §P3-4, tests 18-30; plan.md criterion 3):
/// `LaunchFrame` is a pure function of t, so every moment is sampled here with no view. Angles are degrees, 0 = 3 o'clock,
/// clockwise, as the boards and `RyftMarkGeometry` have them.
@Suite("Launch: the frame at every moment")
struct LaunchFrameTests {
    typealias Frame = LaunchFrame
    private typealias G = RyftMarkGeometry

    // MARK: the palette

    static func rgb(_ hex: UInt32) -> Frame.RGB {
        Frame.RGB(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    /// The metric colours of the Nocturne catalog (`#5E8BEA` strain, `#9B8AF0` sleep, `#63D2B4` recovery) and its ink.
    static let palette = Frame.Palette(strain: rgb(0x5E8BEA), sleep: rgb(0x9B8AF0), recovery: rgb(0x63D2B4), ink: rgb(0xF2F1EC))

    static func frame(_ t: Double, side: Double = 184) -> Frame { Frame(t: t, palette: palette, side: side) }

    private func close(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool { abs(a - b) <= tolerance }

    private func closeArc(_ arc: Frame.Arc, _ expected: (Double, Double), _ tolerance: Double) -> Bool {
        close(arc.start, expected.0, tolerance) && close(arc.end, expected.1, tolerance)
    }

    // MARK: constants (case 18)

    @Test func theConstants() {
        #expect(Frame.duration == 5.2)
        #expect(Frame.trackInk == 0.10 && Frame.taglineInk == 0.55 && Frame.wordmarkStartTracking == 0.9)
        #expect(Wordmark.tracking == 0.32)
        typealias K = Frame.Key
        let keys = [K.groupIn, K.tracksIn, K.drawEnd, K.holdEnd, K.tracksOutFrom, K.tracksOutTo, K.morphEnd, K.wordmarkFrom,
                    K.wordmarkTo, K.colourTo, K.taglineFrom, K.taglineTo]
        #expect(keys == [0.04, 0.06, 0.26, 0.50, 0.52, 0.74, 0.76, 0.74, 0.86, 0.86, 0.80, 0.88])
        #expect(Frame.Reading.strain == 12.4 && Frame.Reading.recovery == 0.82 && Frame.Reading.sleep == 0.94)
        #expect(Frame.Reading.readiness == 84)
        #expect(Frame.Arc.minimumSweep == 0.05)
    }

    @Test func theControlPointsAreTheDesignsCurves() {
        #expect(Frame.Easing.e1 == Frame.Easing(0.45, 0, 0.15, 1))
        #expect(Frame.Easing.e2 == Frame.Easing(0.2, 0, 0, 1))
        #expect(Frame.Easing.e3 == Frame.Easing(0.25, 0.1, 0.25, 1))
        #expect(Frame.Easing.easeOut == Frame.Easing(0, 0, 0.58, 1))
    }

    // MARK: easing (case 19)

    private struct EasingPoint: CustomTestStringConvertible, Sendable {
        let name: String
        let curve: Frame.Easing
        let x: Double
        let y: Double
        var testDescription: String { "\(name)(\(x))" }
    }

    /// The designer's three values at 0.5 (±0.0005), and an independent bisection of the same curves at 0.1, 0.25, 0.75, 0.9.
    private static let easingPoints: [EasingPoint] = {
        let e1 = Frame.Easing.e1, e2 = Frame.Easing.e2, e3 = Frame.Easing.e3, out = Frame.Easing.easeOut
        return [
            EasingPoint(name: "E1", curve: e1, x: 0.5, y: 0.7912), EasingPoint(name: "E2", curve: e2, x: 0.5, y: 0.8778),
            EasingPoint(name: "E3", curve: e3, x: 0.5, y: 0.8024),
            EasingPoint(name: "E1", curve: e1, x: 0.1, y: 0.0206), EasingPoint(name: "E1", curve: e1, x: 0.25, y: 0.2068),
            EasingPoint(name: "E1", curve: e1, x: 0.75, y: 0.9635), EasingPoint(name: "E1", curve: e1, x: 0.9, y: 0.9950),
            EasingPoint(name: "E2", curve: e2, x: 0.1, y: 0.1563), EasingPoint(name: "E2", curve: e2, x: 0.25, y: 0.6072),
            EasingPoint(name: "E2", curve: e2, x: 0.75, y: 0.9755), EasingPoint(name: "E3", curve: e3, x: 0.1, y: 0.0948),
            EasingPoint(name: "E3", curve: e3, x: 0.25, y: 0.4085), EasingPoint(name: "E3", curve: e3, x: 0.75, y: 0.9605),
            EasingPoint(name: "easeOut", curve: out, x: 0.25, y: 0.3781), EasingPoint(name: "easeOut", curve: out, x: 0.5, y: 0.6846),
            EasingPoint(name: "easeOut", curve: out, x: 0.75, y: 0.9065),
        ]
    }()

    @Test("The curves at known points", arguments: easingPoints)
    private func easingValues(_ point: EasingPoint) {
        #expect(close(point.curve(point.x), point.y, 0.0005))
    }

    @Test("Each curve runs 0 to 1, never decreases and never overshoots", arguments: [
        Frame.Easing.e1, .e2, .e3, .easeOut,
    ])
    private func easingShape(_ curve: Frame.Easing) {
        #expect(curve(0) == 0 && curve(1) == 1)
        #expect(curve(-3) == 0 && curve(7) == 1, "clamped outside 0...1")
        var last = 0.0
        for step in 0...1_000 {
            let y = curve(Double(step) / 1_000)
            #expect(y >= last - 1e-12 && y >= 0 && y <= 1 + 1e-12, "step \(step)")
            last = y
        }
    }

    @Test func progressIsAClampedShareOfASegment() {
        #expect(Frame.progress(0.5, 0.5, 0.76) == 0 && Frame.progress(0.76, 0.5, 0.76) == 1)
        #expect(abs(Frame.progress(0.63, 0.5, 0.76) - 0.5) < 1e-12)
        #expect(Frame.progress(0, 0.5, 0.76) == 0 && Frame.progress(1, 0.5, 0.76) == 1)
    }

    @Test func aColourMixIsExactAtBothEndsAndPerComponentBetween() {
        let a = Frame.RGB(r: 0.2, g: 0.4, b: 0.6), b = Frame.RGB(r: 0.8, g: 0.2, b: 1)
        #expect(a.mixed(with: b, by: 0) == a && a.mixed(with: b, by: 1) == b)
        #expect(a.mixed(with: b, by: -1) == a && a.mixed(with: b, by: 2) == b)
        let half = a.mixed(with: b, by: 0.5)
        #expect(close(half.r, 0.5, 1e-12) && close(half.g, 0.3, 1e-12) && close(half.b, 0.8, 1e-12))
    }

    @Test func anArcShorterThanFiftyThousandthsOfADegreeDrawsNothing() {
        #expect(Frame.Arc(start: 10, end: 10).isEmpty)
        #expect(Frame.Arc(start: 10, end: 10.049).isEmpty)
        #expect(!Frame.Arc(start: 10, end: 10.05).isEmpty)
        #expect(Frame.Arc(start: 10, end: 9).isEmpty, "reversed")
    }

    // MARK: the sample table (design.md §P3-4; cases 20-24)

    private struct Sample: CustomTestStringConvertible, Sendable {
        let t: Double
        let strain: [Double]      // arc start, arc end, dot
        let sleep: [Double]
        let recovery: [Double]
        let inner: Double
        let group: Double
        let tracks: Double
        let wordmark: Double
        let tracking: Double
        let tagline: Double
        let mix: Double
        var testDescription: String { "t = \(t)" }
    }

    private static let settled = (strain: [79.02, 410.98, 425.0], sleep: [-51.78, 155.78, -76.0], recovery: [204.22, 259.78, 180.0])

    /// design.md §P3-4's table. Angles to ±0.01 (two decimals), opacities and tracking to ±0.005.
    private static let samples: [Sample] = [
        Sample(t: 0, strain: [-90, -90, -75.98], sleep: [-84, -84, -59.78], recovery: [264, 264, -120.22], inner: 0,
               group: 0, tracks: 0, wordmark: 0, tracking: 0.90, tagline: 0, mix: 0),
        Sample(t: 0.13, strain: [-90, 67.10, 81.12], sleep: [-84, 15.84, 40.06], recovery: [179.35, 264, -204.87], inner: 239.27,
               group: 1, tracks: 1, wordmark: 0, tracking: 0.90, tagline: 0, mix: 0),
        Sample(t: 0.26, strain: [-90, 108.55, 122.57], sleep: [-84, 42.18, 66.40], recovery: [157.02, 264, -227.20], inner: 302.40,
               group: 1, tracks: 1, wordmark: 0, tracking: 0.90, tagline: 0, mix: 0),
        Sample(t: 0.50, strain: [-90, 108.55, 122.57], sleep: [-84, 42.18, 66.40], recovery: [157.02, 264, -227.20], inner: 302.40,
               group: 1, tracks: 1, wordmark: 0, tracking: 0.90, tagline: 0, mix: 0),
        Sample(t: 0.63, strain: [43.74, 347.85, 361.87], sleep: [-58.51, 132.07, -46.27], recovery: [194.36, 260.66, 94.99],
               inner: 347.98, group: 1, tracks: 0.21, wordmark: 0, tracking: 0.90, tagline: 0, mix: 0),
        Sample(t: 0.76, strain: settled.strain, sleep: settled.sleep, recovery: settled.recovery, inner: 360, group: 1, tracks: 0,
               wordmark: 0.41, tracking: 0.66, tagline: 0, mix: 0),
        Sample(t: 0.86, strain: settled.strain, sleep: settled.sleep, recovery: settled.recovery, inner: 360, group: 1, tracks: 0,
               wordmark: 1, tracking: 0.32, tagline: 0.96, mix: 1),
        Sample(t: 1, strain: settled.strain, sleep: settled.sleep, recovery: settled.recovery, inner: 360, group: 1, tracks: 0,
               wordmark: 1, tracking: 0.32, tagline: 1, mix: 1),
    ]

    @Test("The sample table", arguments: samples)
    private func theSampleTable(_ sample: Sample) {
        let f = Self.frame(sample.t)
        let name = "t = \(sample.t)"
        if sample.strain[0] == sample.strain[1] {
            #expect(f.strain.arc.isEmpty && f.sleep.arc.isEmpty && f.recovery.arc.isEmpty, "\(name): nothing drawn yet")
        }
        #expect(closeArc(f.strain.arc, (sample.strain[0], sample.strain[1]), 0.01), "\(name) strain arc \(f.strain.arc)")
        #expect(close(f.strain.dot, sample.strain[2], 0.01), "\(name) strain dot \(f.strain.dot)")
        #expect(closeArc(f.sleep.arc, (sample.sleep[0], sample.sleep[1]), 0.01), "\(name) sleep arc \(f.sleep.arc)")
        #expect(close(f.sleep.dot, sample.sleep[2], 0.01), "\(name) sleep dot \(f.sleep.dot)")
        #expect(closeArc(f.recovery.arc, (sample.recovery[0], sample.recovery[1]), 0.01), "\(name) recovery arc \(f.recovery.arc)")
        #expect(close(f.recovery.dot, sample.recovery[2], 0.01), "\(name) recovery dot \(f.recovery.dot)")
        #expect(close(f.innerSweep, sample.inner, 0.01), "\(name) inner \(f.innerSweep)")
        #expect(close(f.groupOpacity, sample.group, 0.005), "\(name) group \(f.groupOpacity)")
        #expect(close(f.trackOpacity, sample.tracks, 0.005), "\(name) tracks \(f.trackOpacity)")
        #expect(close(f.wordmarkOpacity, sample.wordmark, 0.005), "\(name) wordmark \(f.wordmarkOpacity)")
        #expect(close(f.wordmarkTracking, sample.tracking, 0.005), "\(name) tracking \(f.wordmarkTracking)")
        #expect(close(f.taglineOpacity, sample.tagline, 0.005), "\(name) tagline \(f.taglineOpacity)")
        // Colour: the metric colour until 0.76, `textPrimary` from 0.86, per component in between.
        let p = Self.palette
        for (orbit, metric) in [(f.strain, p.strain), (f.sleep, p.sleep), (f.recovery, p.recovery)] {
            #expect(orbit.colour == metric.mixed(with: p.ink, by: sample.mix), "\(name) colour")
        }
        #expect(f.ink == p.ink)
        #expect(f.t == sample.t && f.side == 184)
    }

    /// Within one frame (1/312 of t) of every keyframe: the table's values hold for a frame either side of a boundary
    /// where the design says the value stops moving.
    @Test func theHoldIsFlatForItsWholeLength() {
        let hold = Self.frame(0.26)
        for step in 0...23 {
            let f = Self.frame(0.26 + Double(step) * 0.01)
            #expect(f.strain == hold.strain && f.sleep == hold.sleep && f.recovery == hold.recovery, "t = \(f.t)")
            #expect(f.innerSweep == hold.innerSweep && f.groupOpacity == 1 && f.trackOpacity == 1, "t = \(f.t)")
        }
        let start = Self.frame(0.5), end = Self.frame(0.5 - 1.0 / 312)
        #expect(start.strain == hold.strain && start.sleep == hold.sleep && start.recovery == hold.recovery, "t = 0.5")
        #expect(start.strain == end.strain && start.recovery == end.recovery, "no drift on the last frame of the hold")
    }

    @Test func theTracksAreInAtSixPercentOutFromFiftyTwoToSeventyFour() {
        #expect(Self.frame(0.06).trackOpacity == 1 && Self.frame(0.52).trackOpacity == 1)
        #expect(Self.frame(0.5).trackOpacity == 1)
        #expect(Self.frame(0.74).trackOpacity == 0 && Self.frame(1).trackOpacity == 0)
        #expect(Self.frame(0.03).trackOpacity > 0 && Self.frame(0.03).trackOpacity < 1)
        #expect(Self.frame(0.04).groupOpacity == 1 && Self.frame(0.02).groupOpacity > 0)
    }

    @Test func theTaglineIsInFullFromEightyEightPercent() {
        #expect(Self.frame(0.80).taglineOpacity == 0 && Self.frame(0.79).taglineOpacity == 0)
        #expect(Self.frame(0.88).taglineOpacity == 1 && Self.frame(0.9).taglineOpacity == 1)
        #expect(close(Self.frame(0.84).taglineOpacity, Frame.Easing.e3(0.5), 1e-9))
    }

    // MARK: the board (case 21)

    @Test func theHoldIsTheBoardWithinHalfADegree() {
        let f = Self.frame(0.26)
        // Dots: strain 122.6, sleep 66, recovery -227.
        #expect(close(f.strain.dot, 122.6, 0.5) && close(f.sleep.dot, 66, 0.5) && close(f.recovery.dot, -227, 0.5))
        // Arc ends: strain 108.61, sleep 41.78, recovery -202.78 (stored + 360).
        #expect(close(f.strain.arc.end, 108.61, 0.5), "\(f.strain.arc)")
        #expect(close(f.sleep.arc.end, 41.78, 0.5), "\(f.sleep.arc)")
        #expect(close(f.recovery.arc.start - 360, -202.78, 0.5), "\(f.recovery.arc)")
        // Lengths as shares of the circle: 55.17 %, 34.94 %, 29.66 % to 0.2 %.
        let strain = (f.strain.arc.end - f.strain.arc.start) / 360
        let sleep = (f.sleep.arc.end - f.sleep.arc.start) / 360
        let recovery = (f.recovery.arc.end - f.recovery.arc.start) / 360
        #expect(close(strain, 0.5517, 0.002) && close(sleep, 0.3494, 0.002) && close(recovery, 0.2966, 0.002),
                "\(strain) \(sleep) \(recovery)")
        #expect(close(f.innerSweep, 302.4, 0.01), "84 % of the closed ring")
    }

    @Test func theHoldIsTheGaugesOwnReading() {
        // 12.4 of 21, 94 %, 82 %: the gauge's mapping, then the mark's clear air less (strain) or more (recovery).
        let g = OrbitGaugeGeometry.Orbit.self
        let metrics = G.metrics(forSide: 184)
        let outerGap = G.halfGap(ringRadius: G.outer.radius, metrics: metrics)
        let middleGap = G.halfGap(ringRadius: G.middle.radius, metrics: metrics)
        let f = Self.frame(0.26)
        // One mapping for the gauge and the launch (review PR 3 row 14): the head on the gauge's 359.99 track, 122.5655,
        // not a second 360 x fraction (122.5714).
        #expect(close(f.strain.dot, g.strain.headDegrees(for: 12.4 / 21) - 90, 1e-9))
        #expect(close(f.strain.dot, 122.5655, 1e-4), "\(f.strain.dot)")
        #expect(close(f.sleep.dot, g.sleep.headDegrees(for: 0.94) - 90, 1e-9))
        #expect(close(f.recovery.dot, g.recovery.headDegrees(for: 0.82) - 90, 1e-9))
        #expect(close(f.strain.arc.end, f.strain.dot - outerGap, 1e-9))
        #expect(close(f.sleep.arc.end, f.sleep.dot - middleGap, 1e-9))
        #expect(close(f.recovery.arc.start - 360, f.recovery.dot + middleGap, 1e-9))
    }

    // MARK: t = 1 is the static mark (cases 25, 31 in numbers)

    @Test("t = 1 equals the static mark's arcs and dots, to 1e-6", arguments: [184.0, 160, 100, 44, 24])
    private func theLastFrameIsTheStaticMark(_ side: Double) throws {
        let f = Self.frame(1, side: side)
        let metrics = G.metrics(forSide: side)
        let outer = try #require(G.arcs(of: G.outer, metrics: metrics).first)
        let middle = G.arcs(of: G.middle, metrics: metrics)
        try #require(middle.count == 2)
        #expect(close(f.strain.arc.start, outer.start, 1e-6) && close(f.strain.arc.end, outer.end, 1e-6), "side \(side) strain")
        #expect(close(f.sleep.arc.start, middle[0].start, 1e-6) && close(f.sleep.arc.end, middle[0].end, 1e-6), "side \(side) sleep")
        #expect(close(f.recovery.arc.start, middle[1].start, 1e-6) && close(f.recovery.arc.end, middle[1].end, 1e-6),
                "side \(side) recovery")
        #expect(close(f.strain.dot, G.outer.dots[0] + 360, 1e-6))
        #expect(close(f.sleep.dot, G.middle.dots[0], 1e-6) && close(f.recovery.dot, G.middle.dots[1], 1e-6))
        #expect(f.innerSweep == 360)
        #expect(f.side == side)
    }

    @Test func theLastFrameInNumbers() {
        let f = Self.frame(1)
        #expect(closeArc(f.strain.arc, (79.0203, 410.9797), 1e-4))
        #expect(closeArc(f.sleep.arc, (-51.7828, 155.7828), 1e-4))
        #expect(closeArc(f.recovery.arc, (204.2172, 259.7827), 1e-4))
        #expect(f.strain.dot == 425 && f.strain.dot - 360 == 65, "the strain dot is the mark's 65 + a whole turn")
        #expect(f.sleep.dot == -76 && f.recovery.dot == 180)
        #expect(f.groupOpacity == 1 && f.trackOpacity == 0 && f.wordmarkOpacity == 1 && f.taglineOpacity == 1)
        #expect(f.wordmarkTracking == 0.32)
        let p = Self.palette
        #expect(f.strain.colour == p.ink && f.sleep.colour == p.ink && f.recovery.colour == p.ink && f.ink == p.ink)
        #expect(G.metrics(forSide: 184).showsInnerRing, "the inner ring is part of the mark at 184 pt")
    }

    // MARK: the dot rule: a dot is its arc's head plus the ring's clear air (case 26)

    @Test("Phase A: each dot rides its arc's head, a clear air away", arguments: Array(stride(from: 0.0, through: 0.5, by: 0.01)))
    private func theDotsRideTheArcsInPhaseA(_ t: Double) {
        let f = Self.frame(t)
        let metrics = G.metrics(forSide: 184)
        let outerGap = G.halfGap(ringRadius: G.outer.radius, metrics: metrics)
        let middleGap = G.halfGap(ringRadius: G.middle.radius, metrics: metrics)
        #expect(close(outerGap, 14.0203, 1e-3) && close(middleGap, 24.2172, 1e-3))
        #expect(close(f.strain.dot - f.strain.arc.end, outerGap, 0.001), "t = \(t) strain")
        #expect(close(f.sleep.dot - f.sleep.arc.end, middleGap, 0.001), "t = \(t) sleep")
        #expect(close((f.recovery.arc.start - 360) - f.recovery.dot, middleGap, 0.001), "t = \(t) recovery")
    }

    @Test("Phase B: the strain dot keeps riding its arc, the other two travel on their own",
          arguments: Array(stride(from: 0.5, through: 1.0, by: 0.01)))
    private func theStrainDotRidesThroughPhaseB(_ t: Double) {
        let f = Self.frame(t)
        let outerGap = G.halfGap(ringRadius: G.outer.radius, metrics: G.metrics(forSide: 184))
        #expect(close(f.strain.dot - f.strain.arc.end, outerGap, 0.001), "t = \(t)")
    }

    @Test func theOtherDotsLeaveTheirArcsInPhaseB() {
        let metrics = G.metrics(forSide: 184)
        let middleGap = G.halfGap(ringRadius: G.middle.radius, metrics: metrics)
        let mid = Self.frame(0.63)
        #expect(!close(mid.sleep.dot - mid.sleep.arc.end, middleGap, 1), "the sleep dot travels back across its arc")
        #expect(!close((mid.recovery.arc.start - 360) - mid.recovery.dot, middleGap, 1))
    }

    @Test("The dot's clear air follows the mark's optical size", arguments: [184.0, 100, 44])
    private func theFirstFrameDotsFollowTheSide(_ side: Double) {
        let f = Self.frame(0, side: side)
        let metrics = G.metrics(forSide: side)
        let outerGap = G.halfGap(ringRadius: G.outer.radius, metrics: metrics)
        let middleGap = G.halfGap(ringRadius: G.middle.radius, metrics: metrics)
        #expect(close(f.strain.dot, -90 + outerGap, 1e-9))
        #expect(close(f.sleep.dot, -84 + middleGap, 1e-9))
        #expect(close(f.recovery.dot, -96 - middleGap, 1e-9))
    }

    // MARK: direction and the lap (case 27)

    @Test func theDotsTravelByTheDesignsAmounts() {
        let a0 = Self.frame(0), a1 = Self.frame(0.26), b0 = Self.frame(0.5), b1 = Self.frame(0.76)
        // Phase A.
        #expect(close(a1.strain.dot - a0.strain.dot, 198.55, 0.01))
        #expect(close(a1.sleep.dot - a0.sleep.dot, 126.18, 0.01))
        #expect(close(a1.recovery.dot - a0.recovery.dot, -106.98, 0.01), "counter-clockwise")
        // Phase B: strain +302.43 clockwise, sleep -142.40 counter-clockwise, recovery +407.20: a lap and 47.2 deg more.
        #expect(close(b1.strain.dot - b0.strain.dot, 302.43, 0.01))
        #expect(close(b1.sleep.dot - b0.sleep.dot, -142.40, 0.01))
        #expect(close(b1.recovery.dot - b0.recovery.dot, 407.20, 0.01))
    }

    /// Half way through the move the recovery dot has gone 322 deg clockwise. A dot interpolated the short way would have
    /// gone the other way (-38 deg) or stayed within +-180.
    @Test func theRecoveryDotGoesClockwiseAroundAWholeLap() {
        let start = Self.frame(0.5).recovery.dot
        let mid = Self.frame(0.63).recovery.dot
        #expect(close(mid - start, 322.19, 0.01), "travelled \(mid - start) deg")
        #expect(mid - start > 180, "more than half a lap: no shortest-way interpolation")
        // Clockwise all the way: increasing, across the point a lap on from the start.
        var last = start
        var crossed = false
        for step in 0...260 {
            let value = Self.frame(0.5 + Double(step) * 0.001).recovery.dot
            #expect(value >= last - 1e-12, "step \(step): turned back")
            if last < start + 360, value >= start + 360 { crossed = true }
            last = value
        }
        #expect(crossed, "it passes its own starting point on the way round")
        #expect(close(last - start, 407.2, 0.01))
        #expect(close(last, 180, 1e-9))
    }

    @Test func theSleepDotTravelsBackThroughItsArc() {
        let start = Self.frame(0.5).sleep.dot, mid = Self.frame(0.63)
        #expect(mid.sleep.dot < start, "counter-clockwise")
        #expect(mid.sleep.dot > mid.sleep.arc.start && mid.sleep.dot < mid.sleep.arc.end, "its dot is among the arc's angles")
    }

    // MARK: monotonic progress (case 28)

    private static let steps = (0...312).map { Double($0) / 312 }

    @Test func theFadesAndSweepsOnlyGoOneWay() {
        let frames = Self.steps.map { Self.frame($0) }
        func mix(_ f: Frame) -> Double {
            // The strain colour's red channel as a share of the way from the metric to the ink.
            (f.strain.colour.r - Self.palette.strain.r) / (Self.palette.ink.r - Self.palette.strain.r)
        }
        for (a, b) in zip(frames, frames.dropFirst()) {
            let at = "t = \(a.t) -> \(b.t)"
            #expect(b.groupOpacity >= a.groupOpacity, "group, \(at)")
            #expect(b.innerSweep >= a.innerSweep, "inner ring, \(at)")
            #expect(b.wordmarkOpacity >= a.wordmarkOpacity, "wordmark, \(at)")
            #expect(b.taglineOpacity >= a.taglineOpacity, "tagline, \(at)")
            #expect(mix(b) >= mix(a) - 1e-12, "colour mix, \(at)")
            #expect(b.wordmarkTracking <= a.wordmarkTracking, "tracking, \(at)")
        }
        #expect(frames.allSatisfy { $0.wordmarkTracking >= 0.32 && $0.wordmarkTracking <= 0.9 })
    }

    @Test func theTracksRiseHoldAndFallOnce() {
        let opacities = Self.steps.map { Self.frame($0).trackOpacity }
        let peak = opacities.firstIndex(of: 1)
        #expect(peak != nil)
        let first = peak ?? 0
        let last = opacities.lastIndex(of: 1) ?? 0
        for index in 1..<opacities.count {
            if index <= first { #expect(opacities[index] >= opacities[index - 1], "rising, step \(index)") }
            if index > last { #expect(opacities[index] <= opacities[index - 1], "falling, step \(index)") }
            if index > first, index <= last { #expect(opacities[index] == 1, "held, step \(index)") }
        }
        #expect(opacities.first == 0 && opacities.last == 0 && opacities.max() == 1)
        #expect(Self.steps[last] >= 0.52 - 1.0 / 312 && Self.steps[first] <= 0.06 + 1.0 / 312)
    }

    private struct Direction: CustomTestStringConvertible, Sendable {
        let name: String
        let path: KeyPath<Frame, Double> & Sendable
        /// +1: never decreases, -1: never increases, 0: does not move.
        let sign: Double
        var testDescription: String { name }
    }

    private static let phaseA: [Direction] = [
        Direction(name: "strain arc start", path: \.strain.arc.start, sign: 0),
        Direction(name: "strain arc end", path: \.strain.arc.end, sign: 1),
        Direction(name: "strain dot", path: \.strain.dot, sign: 1),
        Direction(name: "sleep arc start", path: \.sleep.arc.start, sign: 0),
        Direction(name: "sleep arc end", path: \.sleep.arc.end, sign: 1),
        Direction(name: "sleep dot", path: \.sleep.dot, sign: 1),
        Direction(name: "recovery arc start", path: \.recovery.arc.start, sign: -1),
        Direction(name: "recovery arc end", path: \.recovery.arc.end, sign: 0),
        Direction(name: "recovery dot", path: \.recovery.dot, sign: -1),
        Direction(name: "inner sweep", path: \.innerSweep, sign: 1),
    ]

    private static let phaseB: [Direction] = [
        Direction(name: "strain arc start", path: \.strain.arc.start, sign: 1),
        Direction(name: "strain arc end", path: \.strain.arc.end, sign: 1),
        Direction(name: "strain dot", path: \.strain.dot, sign: 1),
        Direction(name: "sleep arc start", path: \.sleep.arc.start, sign: 1),
        Direction(name: "sleep arc end", path: \.sleep.arc.end, sign: 1),
        Direction(name: "sleep dot", path: \.sleep.dot, sign: -1),
        Direction(name: "recovery arc start", path: \.recovery.arc.start, sign: 1),
        Direction(name: "recovery arc end", path: \.recovery.arc.end, sign: -1),
        Direction(name: "recovery dot", path: \.recovery.dot, sign: 1),
        Direction(name: "inner sweep", path: \.innerSweep, sign: 1),
    ]

    private func walk(_ direction: Direction, from: Double, to: Double) {
        let frames = stride(from: from, through: to, by: 1.0 / 312).map { Self.frame($0) }
        for (a, b) in zip(frames, frames.dropFirst()) {
            let delta = b[keyPath: direction.path] - a[keyPath: direction.path]
            if direction.sign == 0 {
                #expect(delta == 0, "\(direction.name) holds, t = \(a.t)")
            } else {
                #expect(delta * direction.sign >= -1e-9, "\(direction.name) turned back at t = \(a.t)")
            }
        }
        let total = (frames.last?[keyPath: direction.path] ?? 0) - (frames.first?[keyPath: direction.path] ?? 0)
        if direction.sign != 0 { #expect(total * direction.sign > 1, "\(direction.name) moved \(total) deg") }
    }

    @Test("Phase A: every angle moves its way and never reverses", arguments: phaseA)
    private func phaseAMonotonic(_ direction: Direction) { walk(direction, from: 0, to: 0.26) }

    @Test("Phase B: every angle moves its way and never reverses", arguments: phaseB)
    private func phaseBMonotonic(_ direction: Direction) { walk(direction, from: 0.5, to: 0.76) }

    @Test func afterTheMorphNothingMovesButTheTextAndTheColour() {
        let settled = Self.frame(0.76)
        for t in stride(from: 0.76, through: 1, by: 0.01) {
            let f = Self.frame(t)
            #expect(f.strain.arc == settled.strain.arc && f.strain.dot == settled.strain.dot, "t = \(t)")
            #expect(f.sleep.arc == settled.sleep.arc && f.sleep.dot == settled.sleep.dot, "t = \(t)")
            #expect(f.recovery.arc == settled.recovery.arc && f.recovery.dot == settled.recovery.dot, "t = \(t)")
            #expect(f.innerSweep == 360 && f.trackOpacity == 0, "t = \(t)")
        }
    }

    // MARK: colour (case 29)

    @Test func theColoursMixInGammaEncodedSRGBPerComponent() {
        // At 0.81 the mix is E1(0.5) = 0.7912: strain (211, 220, 236), sleep (224, 220, 237), recovery (212, 235, 224).
        let f = Self.frame(0.81)
        func bytes(_ c: Frame.RGB) -> [Double] { [c.r, c.g, c.b].map { ($0 * 255).rounded() } }
        func within(_ actual: Frame.RGB, _ expected: [Double]) -> Bool {
            zip([actual.r, actual.g, actual.b].map { $0 * 255 }, expected).allSatisfy { abs($0 - $1) <= 1 }
        }
        #expect(within(f.strain.colour, [211, 220, 236]), "strain \(bytes(f.strain.colour))")
        #expect(within(f.sleep.colour, [224, 220, 237]), "sleep \(bytes(f.sleep.colour))")
        #expect(within(f.recovery.colour, [212, 235, 224]), "recovery \(bytes(f.recovery.colour))")
    }

    @Test func theColourStaysMetricUntilSeventySixAndIsTheInkFromEightySix() {
        let p = Self.palette
        for t in stride(from: 0.0, through: 0.76, by: 0.02) {
            #expect(Self.frame(t).strain.colour == p.strain && Self.frame(t).sleep.colour == p.sleep
                        && Self.frame(t).recovery.colour == p.recovery, "t = \(t)")
        }
        for t in stride(from: 0.86, through: 1, by: 0.02) {
            let f = Self.frame(t)
            #expect(f.strain.colour == p.ink && f.sleep.colour == p.ink && f.recovery.colour == p.ink, "t = \(t)")
        }
    }

    /// The mix only gets lighter, so a metric's contrast on the background never drops below its own (design.md §P3-4).
    @Test func theMixNeverFallsBelowTheMetricsLuminance() {
        func luminance(_ c: Frame.RGB) -> Double {
            func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
        }
        let p = Self.palette
        for t in stride(from: 0.76, through: 0.86, by: 0.005) {
            let f = Self.frame(t)
            #expect(luminance(f.strain.colour) >= luminance(p.strain) - 1e-9, "strain, t = \(t)")
            #expect(luminance(f.sleep.colour) >= luminance(p.sleep) - 1e-9, "sleep, t = \(t)")
            #expect(luminance(f.recovery.colour) >= luminance(p.recovery) - 1e-9, "recovery, t = \(t)")
        }
    }

    @MainActor
    @Test func theResolvedPaletteIsTheCatalogsColours() {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let resolved = Frame.Palette.resolved(in: environment)
        let expected = Self.palette
        for (name, actual, hex) in [("strain", resolved.strain, expected.strain), ("sleep", resolved.sleep, expected.sleep),
                                    ("recovery", resolved.recovery, expected.recovery), ("ink", resolved.ink, expected.ink)] {
            #expect(close(actual.r, hex.r, 1.0 / 255) && close(actual.g, hex.g, 1.0 / 255) && close(actual.b, hex.b, 1.0 / 255),
                    "\(name): \(actual) against \(hex)")
        }
    }

    // MARK: clamping (case 30)

    @Test("t outside 0...1 clamps", arguments: [-0.5, -1e-9, -100, -Double.infinity])
    private func belowZeroIsZero(_ t: Double) {
        #expect(Self.frame(t) == Self.frame(0))
        #expect(Self.frame(t).t == 0)
    }

    @Test("t above 1 clamps", arguments: [1 + 1e-9, 1.5, 100, Double.infinity])
    private func aboveOneIsOne(_ t: Double) {
        #expect(Self.frame(t) == Self.frame(1))
        #expect(Self.frame(t).t == 1)
    }

    @Test func notANumberIsZero() {
        #expect(Self.frame(.nan) == Self.frame(0))
        #expect(Self.frame(.nan).t == 0)
    }
}
