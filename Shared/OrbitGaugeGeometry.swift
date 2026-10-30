// The drawing of `OrbitGauge` as numbers. Foundation and CoreGraphics only, so a test can check every
// angle without a view.
//
// ANGLES are degrees clockwise from 12 o'clock; a counter-clockwise sweep is negative.
//
// THE REFERENCE DRAWING is the `.large` dial, 160 pt across (the same 160 as `MetricGauge`'s dial). Radii are
// stroke centrelines. Everything scales by dial / 160, with an optical floor for strokes and dots (the same
// idea as RyftMarkGeometry.metrics(forSide:)) so the drawing at 44 pt keeps three visible rings and three dots.
//
//   ring     radius  stroke   why
//   outer    77      5.5      the day: Strain, 21 -> 360 deg. Its outer edge is 80 = the dial's radius.
//   inner    54      5.5      the night: Recovery counter-clockwise, Sleep clockwise.
//   centre   32      4.5      Readiness; inside it the number, 59 pt wide at .large.
//   dot r    9                 about 3.3 x the stroke (the icon: 3.8): the dot is "you are here".
//
// THE INNER ORBIT is the icon's middle ring: two dots, two arcs. Recovery and Sleep both start at the top,
// so their two start dots (and, at 100 %, their two end dots at the bottom) would sit on one spot. Each half
// therefore starts `innerInset` degrees from the vertical and ends `innerInset` before the other half:
//     angle(f) = innerInset + f * (180 - 2 * innerInset)
// With innerInset = 12.5 deg, f = 0.5 is exactly 90 deg (3 and 9 o'clock); 0 and 1 are 12.5 and 167.5 deg, leaving
// 25 deg between the two dots at the bottom: 23.4 pt on the 54 pt orbit, a dot's diameter (18) plus 5.4 pt of air.
import CoreGraphics
import Foundation

enum OrbitGaugeGeometry {
    /// The reference dial, in points.
    static let referenceDial: CGFloat = 160

    enum Orbit: CaseIterable, Hashable {
        case recovery, sleep, strain

        /// Where the orbit starts, degrees clockwise from the top.
        var startDegrees: Double {
            switch self {
            case .recovery: return -OrbitGaugeGeometry.innerInset
            case .sleep: return OrbitGaugeGeometry.innerInset
            case .strain: return 0
            }
        }

        /// Signed sweep of the whole track.
        var trackSweep: Double {
            switch self {
            case .recovery: return -(180 - 2 * OrbitGaugeGeometry.innerInset)
            case .sleep: return 180 - 2 * OrbitGaugeGeometry.innerInset
            case .strain: return OrbitGaugeGeometry.strainTrackSweep
            }
        }

        /// Signed sweep for a fraction of the track (0 = the start dot, 1 = the whole track).
        func sweep(for fraction: Double) -> Double {
            trackSweep * min(max(fraction, 0), 1)
        }

        /// Where the dot sits for a fraction, degrees clockwise from the top.
        func headDegrees(for fraction: Double) -> Double {
            startDegrees + sweep(for: fraction)
        }
    }

    static let innerInset = 12.5
    /// 360 deg exactly would be an empty path in CoreGraphics' arc; this is a closed ring to the eye.
    static let strainTrackSweep = 359.99

    /// Radii, strokes and the dot, in points for one dial.
    struct Metrics: Equatable {
        var outerRadius: CGFloat
        var innerRadius: CGFloat
        var centreRadius: CGFloat
        var outerStroke: CGFloat
        var innerStroke: CGFloat
        var centreStroke: CGFloat
        var dotRadius: CGFloat
        /// Outline of a hollow dot.
        var hollowStroke: CGFloat
        /// Clear air cut out of a track around a dot, as the mark cuts its rings.
        var dotAir: CGFloat
        /// The strain band's rail inside the outer orbit (centreline radius and stroke).
        var bandRadius: CGFloat
        var bandStroke: CGFloat

        func radius(of orbit: Orbit) -> CGFloat {
            orbit == .strain ? outerRadius : innerRadius
        }

        func stroke(of orbit: Orbit) -> CGFloat {
            orbit == .strain ? outerStroke : innerStroke
        }

        /// Inside the centre ring: where the number lives.
        var centreInnerDiameter: CGFloat { 2 * centreRadius - centreStroke }

        /// The number's width inside the centre ring: the inset scales with the dial, so a small dial keeps room.
        var centreSlotWidth: CGFloat { centreInnerDiameter * 0.86 }
    }

    static let minStroke: CGFloat = 1.5

    /// Below this dial the centre ring is too small for a number: the gauge is the mark only (VoiceOver and the text
    /// beside it still say the value). The same in the app and the widget.
    static let minDialForNumber: CGFloat = 56

    /// A number size that fills the centre slot: two digits at full size (about 1.35 em in the rounded face), "100"
    /// at about 0.7 of it, never under the 0.6 minimum scale. The widget's number; the app keeps its 0.19 x dial.
    static func numberPointSize(forDial dial: CGFloat) -> CGFloat {
        metrics(forDial: dial).centreSlotWidth / 1.4
    }

    static func metrics(forDial dial: CGFloat) -> Metrics {
        let s = max(dial, 0) / referenceDial
        let outer = max(5.5 * s, minStroke)
        let centre = max(4.5 * s, minStroke)
        // Dots stay at least 1.15 x the stroke in radius so they read as dots, not as thick arc ends.
        let dot = max(9 * s, outer * 1.15)
        return Metrics(outerRadius: 77 * s, innerRadius: 54 * s, centreRadius: 32 * s,
                       outerStroke: outer, innerStroke: outer, centreStroke: centre,
                       dotRadius: dot, hollowStroke: max(2 * s, 1.25), dotAir: 2.5 * s,
                       bandRadius: 69.5 * s, bandStroke: max(3 * s, minStroke))
    }

    // MARK: strain band (PR 4)

    /// Below this dial the band's rail is not drawn: at `.small` (72 pt) it would be a 1.5 pt line 1.4 pt from the outer
    /// ring. The arc's shift past the band still is (design.md §11).
    static let minDialForBandRail: CGFloat = 90

    /// How much of its colour the rail keeps: `metricStrain` at this opacity.
    static let bandRailOpacity = 0.5

    /// The band clamped to the strain scale, nil when nothing of it is left (an empty or one-point range, or one wholly
    /// outside 0...21). `ClosedRange` cannot be inverted, so "inverted" input never reaches here.
    static func clampedBand(_ band: ClosedRange<Double>?) -> ClosedRange<Double>? {
        guard let band, band.lowerBound.isFinite, band.upperBound.isFinite else { return nil }
        let lo = max(band.lowerBound, 0), hi = min(band.upperBound, OrbitGaugeValues.strainScale)
        return lo < hi ? lo...hi : nil
    }

    /// The rail as an arc of the outer orbit: degrees clockwise from the top, positions as `Orbit.strain` maps strain,
    /// so the rail's ends sit where an arc of those strains would end.
    struct BandRail: Equatable {
        var start: Double
        var sweep: Double
        var end: Double { start + sweep }
    }

    static func bandRail(for band: ClosedRange<Double>?) -> BandRail? {
        guard let band = clampedBand(band) else { return nil }
        let scale = OrbitGaugeValues.strainScale
        let start = Orbit.strain.headDegrees(for: band.lowerBound / scale)
        return BandRail(start: start, sweep: Orbit.strain.headDegrees(for: band.upperBound / scale) - start)
    }

    /// Where the strain arc turns toward alert (degrees clockwise from the top): the band's upper end, only when strain
    /// is above it. nil: below the band, inside it (the end included), missing strain, or no usable band.
    static func strainPastBandDegrees(strain: Double?, band: ClosedRange<Double>?) -> Double? {
        guard let strain, strain.isFinite, let rail = bandRail(for: band) else { return nil }
        let upper = clampedBand(band)!.upperBound
        return min(strain, OrbitGaugeValues.strainScale) > upper ? rail.end : nil
    }

    /// The radial line where the strain arc may turn toward alert: the band's upper end, whether or not strain is past
    /// it (the drawing is one structure and the line does not move with strain). nil: no usable band.
    static func strainSplitDegrees(band: ClosedRange<Double>?) -> Double? { bandRail(for: band)?.end }

    /// The arc and dot's colour decision, for tests and the drawing alike.
    enum StrainTone: Equatable { case plain, pastBand }

    static func strainTone(_ values: OrbitGaugeValues) -> StrainTone {
        strainPastBandDegrees(strain: values.strain, band: values.strainBand) == nil ? .plain : .pastBand
    }

    /// The rail is drawn: a usable band, and a dial that has room for it.
    static func drawsBandRail(_ band: ClosedRange<Double>?, dial: CGFloat) -> Bool {
        dial >= minDialForBandRail && bandRail(for: band) != nil
    }

    // MARK: calibrating segments

    /// The calibrating gauge's outer orbit: `required` round-capped segments with the seam at the top, where the outer
    /// orbit's hollow dot sits. Both numbers are VISIBLE distances, measured between the tips of the round caps:
    /// the first segment's tip is `seamClearDegrees` after the top and the last one's that far before it (the dot's
    /// half-width plus its air: 9 + 2.5 pt on r 77 = 8.6 deg), and neighbours are `segmentGapDegrees` apart.
    /// The centrelines are therefore shortened by one cap (the stroke's half-width as an angle) at each end.
    static let seamClearDegrees = 9.0
    static let segmentGapDegrees = 5.0

    /// One segment's centreline: starts at `start` (degrees clockwise from the top) and sweeps `sweep` degrees.
    struct Segment: Equatable {
        var start: Double
        var sweep: Double
    }

    /// The segments, clockwise from the seam. `required` below 1 is treated as 1.
    static func segments(required: Int, dial: CGFloat) -> [Segment] {
        let n = max(required, 1)
        let m = metrics(forDial: dial)
        let cap = Double(m.outerStroke / 2 / m.outerRadius) * 180 / .pi
        let visible = (360 - 2 * seamClearDegrees - Double(n - 1) * segmentGapDegrees) / Double(n)
        let sweep = max(visible - 2 * cap, 0.5)
        return (0..<n).map { i in
            Segment(start: seamClearDegrees + cap + Double(i) * (visible + segmentGapDegrees), sweep: sweep)
        }
    }

    /// Point on an orbit for an angle, in a rect centred on `centre`.
    static func point(centre: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let r = (degrees - 90) * .pi / 180
        return CGPoint(x: centre.x + radius * CGFloat(cos(r)), y: centre.y + radius * CGFloat(sin(r)))
    }
}
