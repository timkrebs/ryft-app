// The launch sequence's visual timeline (Nocturne PR 3, design.md §P3-4; brief §5) as a pure function of t, the
// share of the 5.2 s that has passed: what each part of the mark looks like at that moment. Foundation and
// `RyftMarkGeometry` only, no SwiftUI, so every moment can be sampled in a unit test; `LaunchStage` draws a frame and
// `LaunchSequence` (App/) says which t is now.
//
// Angles are degrees, 0 = 3 o'clock, clockwise (the mark's and the boards' convention; the gauge's code angles are
// these + 90). An arc is (start, end) with end > start, drawn clockwise; the recovery arc, which grows
// counter-clockwise from -96, is stored as (head + clear air + 360, 264), the form `RyftMarkGeometry.arcs` returns.
// A dot is its arc's head plus the ring's clear air in the direction of travel (L5), as on the board and in the mark.
//
// There is no second set of numbers: the hold frame comes from the gauge's mapping of the board's reading, less the
// mark's clear air; the end of phase B is `RyftMarkGeometry.arcs(of:metrics:)` and the mark's dots, so t = 1 is the
// static mark exactly.
import Foundation

struct LaunchFrame: Equatable {
    /// Degrees, drawn clockwise from `start` to `end`.
    struct Arc: Equatable {
        var start: Double
        var end: Double

        /// Shorter than this draws nothing (no lone round cap at the start).
        static let minimumSweep = 0.05
        var isEmpty: Bool { end - start < Self.minimumSweep }
    }

    /// Gamma-encoded sRGB, 0...1, not premultiplied: the space CSS keyframes mix in, so the board's mid-frames match.
    struct RGB: Equatable {
        var r, g, b: Double

        /// `self` moved `amount` (0...1) of the way to `other`, per component; exactly `other` at 1.
        func mixed(with other: RGB, by amount: Double) -> RGB {
            RGB(r: LaunchFrame.lerp(r, other.r, amount), g: LaunchFrame.lerp(g, other.g, amount),
                b: LaunchFrame.lerp(b, other.b, amount))
        }
    }

    /// The metric colours and the ink, resolved from the asset catalog by the view (`LaunchStage`).
    struct Palette: Equatable {
        var strain, sleep, recovery, ink: RGB
    }

    /// One orbit's arc, its dot and their colour.
    struct Orbit: Equatable {
        var arc: Arc
        var dot: Double
        var colour: RGB
    }

    /// A cubic-bézier timing curve as CSS applies it (`cubic-bezier(x1, y1, x2, y2)`), solved by bisection.
    struct Easing: Equatable, Sendable {
        let x1, y1, x2, y2: Double

        init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            self.x1 = x1
            self.y1 = y1
            self.x2 = x2
            self.y2 = y2
        }

        /// Geometry, the group, the tracks and the colour.
        static let e1 = Easing(0.45, 0, 0.15, 1)
        /// The wordmark.
        static let e2 = Easing(0.2, 0, 0, 1)
        /// The tagline: CSS `ease`.
        static let e3 = Easing(0.25, 0.1, 0.25, 1)
        /// CSS `ease-out`, SwiftUI's `.easeOut` (`Theme.Motion`): the fades of the hand-off and of the reduced variant.
        static let easeOut = Easing(0, 0, 0.58, 1)

        /// y at x (both 0...1; clamped outside).
        func callAsFunction(_ x: Double) -> Double {
            guard x > 0 else { return 0 }
            guard x < 1 else { return 1 }
            var lo = 0.0, hi = 1.0
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                if Self.bezier(mid, x1, x2) < x { lo = mid } else { hi = mid }
            }
            return Self.bezier((lo + hi) / 2, y1, y2)
        }

        private static func bezier(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
        }
    }

    /// Where each segment starts and ends, as shares of `duration` (design.md §P3-4).
    enum Key {
        static let groupIn = 0.04
        static let tracksIn = 0.06
        /// Phase A, the draw-in, ends; the hold starts.
        static let drawEnd = 0.26
        /// The hold ends; phase B, the move into the mark, starts.
        static let holdEnd = 0.50
        static let tracksOutFrom = 0.52
        static let tracksOutTo = 0.74
        /// Phase B ends: the geometry is the mark's.
        static let morphEnd = 0.76
        static let wordmarkFrom = 0.74
        static let wordmarkTo = 0.86
        static let colourTo = 0.86
        static let taglineFrom = 0.80
        static let taglineTo = 0.88
    }

    /// The board's reading, which the hold shows: a brand moment, never the user's data.
    enum Reading {
        static let strain = 12.4
        static let recovery = 0.82
        static let sleep = 0.94
        static let readiness = 84
    }

    static let duration = 5.2
    /// The tracks are `ink` at this opacity, times `trackOpacity`.
    static let trackInk = 0.10
    /// The wordmark's tracking (em) before it settles at `Wordmark.tracking` (0.32).
    static let wordmarkStartTracking = 0.9
    /// The tagline is `ink` at this opacity (5.67:1 on `background`), times `taglineOpacity`.
    static let taglineInk = 0.55

    /// 0...1 of `duration`; NaN is 0.
    var t: Double
    /// The side of the mark's 100 box this frame was built for (its clear air and stroke follow it).
    var side: Double
    /// The mark (tracks, arcs, dots and the inner ring); 0...1.
    var groupOpacity: Double
    /// 0...1, times `trackInk`.
    var trackOpacity: Double
    var strain, sleep, recovery: Orbit
    /// The inner ring, degrees clockwise from -90 (12 o'clock); 360 is the closed ring.
    var innerSweep: Double
    /// The inner ring, the wordmark and the tagline: `ink` throughout.
    var ink: RGB
    var wordmarkOpacity: Double
    /// In em.
    var wordmarkTracking: Double
    var taglineOpacity: Double

    init(t rawT: Double, palette: Palette, side: Double = 184) {
        let t = rawT.isNaN ? 0 : min(max(rawT, 0), 1)
        let g = RyftMarkGeometry.self
        let metrics = g.metrics(forSide: side)
        let outerGap = g.halfGap(ringRadius: g.outer.radius, metrics: metrics)
        let middleGap = g.halfGap(ringRadius: g.middle.radius, metrics: metrics)
        let e1 = Easing.e1
        let phaseA = e1(Self.progress(t, 0, Key.drawEnd))
        let phaseB = e1(Self.progress(t, Key.holdEnd, Key.morphEnd))
        let mix = e1(Self.progress(t, Key.morphEnd, Key.colourTo))

        // The gauge's starts and its heads for the reading, in board angles (code - 90): the gauge's own mapping, so the
        // hold shows the strain head where the gauge draws it (its track is 359.99, as CoreGraphics draws no arc of
        // exactly 360: 122.5655, not 360 x 12.4 / 21's 122.5714).
        let gauge = OrbitGaugeGeometry.Orbit.self
        let strainStart = gauge.strain.startDegrees - 90
        let strainHead = gauge.strain.headDegrees(for: Reading.strain / OrbitGaugeValues.strainScale) - 90
        let sleepStart = gauge.sleep.startDegrees - 90
        let sleepHead = gauge.sleep.headDegrees(for: Reading.sleep) - 90
        let recoveryStart = gauge.recovery.startDegrees - 90 + 360
        let recoveryHead = gauge.recovery.headDegrees(for: Reading.recovery) - 90

        // The mark: the end of phase B.
        let outerArc = g.arcs(of: g.outer, metrics: metrics).first.map { Arc(start: $0.start, end: $0.end) }
            ?? Arc(start: strainStart, end: strainStart)
        let middleArcs = g.arcs(of: g.middle, metrics: metrics).map { Arc(start: $0.start, end: $0.end) }
        let sleepArc = middleArcs.first ?? Arc(start: sleepStart, end: sleepStart)
        let recoveryArc = middleArcs.dropFirst().first ?? Arc(start: recoveryStart, end: recoveryStart)
        let strainDot = (g.outer.dots.first ?? 65) + 360
        let sleepDot = g.middle.dots.first ?? -76
        let recoveryDot = g.middle.dots.dropFirst().first ?? 180

        // Phase A, then phase B, of one value.
        func run(_ from: Double, _ hold: Double, _ to: Double) -> Double {
            t < Key.holdEnd ? Self.lerp(from, hold, phaseA) : Self.lerp(hold, to, phaseB)
        }

        let strainHoldEnd = strainHead - outerGap
        strain = Orbit(arc: Arc(start: run(strainStart, strainStart, outerArc.start),
                                end: run(strainStart, strainHoldEnd, outerArc.end)),
                       dot: run(strainStart + outerGap, strainHead, strainDot),
                       colour: palette.strain.mixed(with: palette.ink, by: mix))
        sleep = Orbit(arc: Arc(start: run(sleepStart, sleepStart, sleepArc.start),
                               end: run(sleepStart, sleepHead - middleGap, sleepArc.end)),
                      dot: run(sleepStart + middleGap, sleepHead, sleepDot),
                      colour: palette.sleep.mixed(with: palette.ink, by: mix))
        recovery = Orbit(arc: Arc(start: run(recoveryStart, recoveryHead + middleGap + 360, recoveryArc.start),
                                  end: run(recoveryStart, recoveryStart, recoveryArc.end)),
                         dot: run(recoveryStart - 360 - middleGap, recoveryHead, recoveryDot),
                         colour: palette.recovery.mixed(with: palette.ink, by: mix))
        let readiness = OrbitGaugeGeometry.voltDegrees(readiness: Reading.readiness) ?? 0
        innerSweep = run(0, readiness, 360)

        self.t = t
        self.side = side
        ink = palette.ink
        groupOpacity = e1(Self.progress(t, 0, Key.groupIn))
        trackOpacity = t < Key.tracksOutFrom
            ? e1(Self.progress(t, 0, Key.tracksIn))
            : 1 - e1(Self.progress(t, Key.tracksOutFrom, Key.tracksOutTo))
        let wordmark = Easing.e2(Self.progress(t, Key.wordmarkFrom, Key.wordmarkTo))
        wordmarkOpacity = wordmark
        wordmarkTracking = Self.lerp(Self.wordmarkStartTracking, Double(Wordmark.tracking), wordmark)
        taglineOpacity = Easing.e3(Self.progress(t, Key.taglineFrom, Key.taglineTo))
    }

    /// How far `t` is through the segment from `a` to `b`, clamped to 0...1.
    static func progress(_ t: Double, _ a: Double, _ b: Double) -> Double {
        min(max((t - a) / (b - a), 0), 1)
    }

    /// Exact at both ends, so the last frame carries the mark's own numbers, not a rounding of them.
    fileprivate static func lerp(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        if amount <= 0 { return from }
        if amount >= 1 { return to }
        return from + (to - from) * amount
    }
}
