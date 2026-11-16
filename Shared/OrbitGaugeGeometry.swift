// The drawing of `OrbitGauge` as numbers. Foundation and CoreGraphics only, so a test can check every
// angle without a view.
//
// ANGLES are degrees clockwise from 12 o'clock; a counter-clockwise sweep is negative. The Nocturne boards and
// docs/work/2026-11-16-nocturne/design.md §P3 measure from 3 o'clock: board = code - 90.
//
// GAUGE V3 (Nocturne PR 3, design.md §P3-1). The reference is the Today board at S = 260 pt, S being the gauge's side
// (`OrbitGaugeSize.frame`, the dial + 12). Every length is a fraction of S with an optical floor, so one function
// serves 56 to 260 pt. Radii are centrelines:
//
//   ring     radius at 260  track                            marks
//   outer    118            128 ticks 1.2 x 6, ink 16 %      strain, a 3.5 round arc, 21 -> a whole turn
//   middle    88            a full ring 3.5 wide, ink 7 %    recovery counter-clockwise from -6, sleep clockwise
//                                                            from +6, each over at most 160
//   inner     58            60 ticks 1.3 x 7, ink 13 %       readiness: the first round(r / 100 x 60) ticks in ink,
//                                                            the Volt dot (r 5, a 2.5 cleared ring) at the value
//   dots      on the arc heads: r 7, a 3 pt cleared ring, a halo r 15 at 16 % (from S 110)
//   rail      109.5, 3 wide (the strain band, PR 4)
//
// Below S 150 the tick rings halve (64 / 30); below S 100 they are solid rings, as a hairline tick ring turns into a
// grey band. A tick is whole or absent: one whose centre is closer to a dot of its own ring than that dot's cut (its
// radius plus its ring) is not drawn, so no sliver of a tick shows beside a dot.
//
// THE MIDDLE ORBIT is the mark's middle ring: two dots, two arcs, split at the vertical. Each half starts `innerInset`
// from it and runs at most `innerSpan`:  angle(f) = +-(6 + 160 f). The start dots are 18.4 pt apart at 260 (a dot's
// diameter and 4 pt of air); at 100 % the heads stop 14 deg short of the bottom on each side, 42.6 pt apart.
import CoreGraphics
import Foundation

enum OrbitGaugeGeometry {
    /// The reference side (the Today board), in points.
    static let referenceSide: CGFloat = 260

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
            case .recovery: return -OrbitGaugeGeometry.innerSpan
            case .sleep: return OrbitGaugeGeometry.innerSpan
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

    /// The middle orbit's halves start this far from the vertical (board -96 and -84).
    static let innerInset = 6.0
    /// And run at most this far: a constant, not 180 - 2 x the inset (that would be 168).
    static let innerSpan = 160.0
    /// 360 deg exactly would be an empty path in CoreGraphics' arc; this is a closed ring to the eye.
    static let strainTrackSweep = 359.99

    // MARK: tick rings

    /// The tick rings by side (design.md §P3-1, "Tiers by S"): the width floor would otherwise turn a dense ring grey.
    enum TickTier: Equatable, Sendable {
        /// S >= 150: 128 outer, 60 inner ticks (Today's `.large`, the board, the widget's home tile).
        case fine
        /// 100 <= S < 150: 64 and 30 (`.medium`, the widget's dial from 88 to 137).
        case medium
        /// S < 100: solid rings in the same tints (`.small`, the lock screen and the rectangular widget).
        case solid

        var outerCount: Int {
            switch self {
            case .fine: return OrbitGaugeGeometry.outerTickCount
            case .medium: return OrbitGaugeGeometry.outerTickCount / 2
            case .solid: return 0
            }
        }

        var innerCount: Int {
            switch self {
            case .fine: return OrbitGaugeGeometry.innerTickCount
            case .medium: return OrbitGaugeGeometry.innerTickCount / 2
            case .solid: return 0
            }
        }
    }

    static let fineTierFrom: CGFloat = 150
    static let mediumTierFrom: CGFloat = 100

    static func tier(forSide side: CGFloat) -> TickTier {
        side >= fineTierFrom ? .fine : side >= mediumTierFrom ? .medium : .solid
    }

    /// The board's outer pitch, tick plus gap (1.2 + 4.6).
    static let boardOuterPitch: CGFloat = 5.8
    /// `tickCount(radius: 118, pitch: 5.8)`: 127.83, so 128 (pitch 5.792 at 260). It divides by 4, so ticks sit at 12, 3,
    /// 6 and 9 o'clock. Radius and pitch both scale with S, so the count does not change with size.
    static let outerTickCount = 128
    /// One every 6 deg.
    static let innerTickCount = 60

    /// The whole number of ticks nearest to a pitch on a ring.
    static func tickCount(radius: CGFloat, pitch: CGFloat) -> Int {
        guard radius > 0, pitch > 0 else { return 0 }
        return Int((2 * .pi * radius / pitch).rounded())
    }

    /// The centre of tick `i` of `count`, degrees clockwise from the top: tick 0 at the top.
    static func tickDegrees(_ i: Int, count: Int) -> Double {
        count > 0 ? Double(i) * 360 / Double(count) : 0
    }

    /// The angle a dot clears of ticks on a ring of `radius`: a tick whose centre is closer than `cut` to the dot's
    /// centre is not drawn. 2 asin(cut / 2r): the strain dot (cut 10 at r 118) 4.857 deg, Volt (7.5 at r 58) 7.41.
    static func clearDegrees(cut: CGFloat, radius: CGFloat) -> Double {
        guard radius > 0 else { return 0 }
        return 2 * asin(min(1, Double(cut / (2 * radius)))) * 180 / .pi
    }

    /// The readiness ticks lit for a fraction of the inner ring: round(f x n), half up, clamped to 0...n.
    static func litTicks(fraction: Double, count: Int) -> Int {
        guard fraction.isFinite, count > 0 else { return 0 }
        return min(max(Int((fraction * Double(count)).rounded()), 0), count)
    }

    /// The same for a readiness: 84 -> 50 of 60 (25 of 30); 0 -> 0; 1 -> 1; 100 and over -> all; nil -> none.
    static func litTicks(readiness: Int?, count: Int) -> Int {
        readinessFraction(readiness).map { litTicks(fraction: $0, count: count) } ?? 0
    }

    /// Readiness as 0...1 of the inner ring, clamped; nil without one. The numeral shows the integer given.
    static func readinessFraction(_ readiness: Int?) -> Double? {
        readiness.map { min(max(Double($0) / 100, 0), 1) }
    }

    /// Where the Volt dot sits, degrees clockwise from the top: at the value, not at a tick (84 -> 302.4, board 212.4).
    /// 100 is 360, back at the top. nil without a readiness: Volt marks a value.
    static func voltDegrees(readiness: Int?) -> Double? {
        readinessFraction(readiness).map { $0 * 360 }
    }

    /// Which ticks of a ring of `count` are drawn: the first round(f x n) when `lit` (the readiness), else those whose
    /// centre is before `fraction` of the turn (1 = all; the entrance draws the ring in clockwise), less every tick whose
    /// centre is closer than `cut` to the dot at `dot` (degrees and radius; the dot of that ring, nil for none).
    static func drawnTicks(count: Int, ringRadius: CGFloat, fraction: Double, lit: Bool,
                           dot: (degrees: Double, radius: CGFloat)?, cut: CGFloat) -> [Int] {
        guard count > 0, fraction.isFinite else { return [] }
        let limit: Int
        if lit {
            limit = litTicks(fraction: fraction, count: count)
        } else {
            limit = fraction >= 1 ? count : min(max(Int((fraction * Double(count)).rounded(.up)), 0), count)
        }
        guard limit > 0 else { return [] }
        guard let dot, cut > 0 else { return Array(0..<limit) }
        let d = point(centre: .zero, radius: dot.radius, degrees: dot.degrees)
        return (0..<limit).filter { i in
            let t = point(centre: .zero, radius: ringRadius, degrees: tickDegrees(i, count: count))
            return hypot(t.x - d.x, t.y - d.y) >= cut
        }
    }

    // MARK: metrics

    /// Radii, widths, ticks, dots and halos, in points for one side.
    struct Metrics: Equatable {
        /// S: the gauge's frame.
        var side: CGFloat
        /// Strain (118 at 260), recovery and sleep (88), readiness (58): centrelines.
        var outerRadius: CGFloat
        var innerRadius: CGFloat
        var centreRadius: CGFloat
        /// arcW: every arc, the middle ring and the solid rings (3.5 at 260).
        var arcStroke: CGFloat
        /// A tick: width across the ring x length along the radius, centred on its ring.
        var outerTick: CGSize
        var innerTick: CGSize
        var tier: TickTier
        var dotRadius: CGFloat
        /// The cleared ring around an orbit dot (the cut is `dotRadius + dotAir`).
        var dotAir: CGFloat
        var haloRadius: CGFloat
        var showsHalo: Bool
        var voltRadius: CGFloat
        /// The cleared ring around the Volt dot.
        var voltAir: CGFloat
        /// Outline of a hollow dot.
        var hollowStroke: CGFloat
        /// The strain band's rail inside the outer ticks (centreline radius and width).
        var bandRadius: CGFloat
        var bandStroke: CGFloat

        var outerStroke: CGFloat { arcStroke }
        var innerStroke: CGFloat { arcStroke }
        var centreStroke: CGFloat { arcStroke }

        func radius(of orbit: Orbit) -> CGFloat {
            orbit == .strain ? outerRadius : innerRadius
        }

        func stroke(of orbit: Orbit) -> CGFloat { arcStroke }

        var outerTickCount: Int { tier.outerCount }
        var innerTickCount: Int { tier.innerCount }

        /// What an orbit dot cuts out of everything under it: itself and its ring.
        var dotCut: CGFloat { dotRadius + dotAir }
        var voltCut: CGFloat { voltRadius + voltAir }

        /// Inside the readiness ring: its radius less half a tick (half the solid ring below S 100), twice.
        var centreInnerDiameter: CGFloat {
            2 * centreRadius - (tier == .solid ? arcStroke : innerTick.height)
        }

        /// The numeral's frame: 0.86 of that (93.7 pt at 260, 62 at 172).
        var centreSlotWidth: CGFloat { centreInnerDiameter * 0.86 }
    }

    static let minStroke: CGFloat = 1.5
    /// Ticks never thinner or shorter than this.
    static let minTickWidth: CGFloat = 0.75, minTickLength: CGFloat = 3
    /// Halos are drawn from this side up.
    static let minSideForHalo: CGFloat = 110

    /// Below this dial the readiness ring is too small for a number: the gauge is the mark only (VoiceOver and the
    /// text beside it still say the value). The same in the app and the widget.
    static let minDialForNumber: CGFloat = 56

    /// The widget's number size: one that fills the centre slot, two digits at full size (about 1.35 em in the
    /// rounded face), "100" at about 0.7 of it, never under the 0.6 minimum scale. The app's numeral is the dot grid
    /// or Light at 0.2 x S.
    static func numberPointSize(forDial dial: CGFloat) -> CGFloat {
        metrics(forDial: dial).centreSlotWidth / 1.4
    }

    /// The metrics of a dial: S is its frame (`OrbitGaugeSize.frame`, the dial + 12).
    static func metrics(forDial dial: CGFloat) -> Metrics {
        metrics(forSide: OrbitGaugeSize.custom(dial: dial).frame)
    }

    /// design.md §P3-1: fraction x S with the floors of its second table.
    static func metrics(forSide side: CGFloat) -> Metrics {
        let s = max(side, 0)
        let k = s / referenceSide
        let arc = max(3.5 * k, minStroke)
        return Metrics(
            side: s,
            outerRadius: 118 * k, innerRadius: 88 * k, centreRadius: 58 * k,
            arcStroke: arc,
            outerTick: CGSize(width: max(1.2 * k, minTickWidth), height: max(6 * k, minTickLength)),
            innerTick: CGSize(width: max(1.3 * k, minTickWidth), height: max(7 * k, minTickLength)),
            tier: tier(forSide: s),
            // Dots stay at least 1.15 x the stroke in radius so they read as dots, not as thick arc ends.
            dotRadius: max(7 * k, arc * 1.15), dotAir: max(3 * k, 1),
            haloRadius: 15 * k, showsHalo: s >= minSideForHalo,
            voltRadius: max(5 * k, 2), voltAir: max(2.5 * k, 1),
            hollowStroke: max(1.5 * k, 1.25),
            bandRadius: 109.5 * k, bandStroke: max(3 * k, minStroke))
    }

    // MARK: strain band (PR 4)

    /// Below this dial the band's rail is not drawn (S 102): it would crowd the outer ring. The arc's shift past the band
    /// still is (design.md §11 of the orbit gauge).
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
        guard let strain, strain.isFinite, let rail = bandRail(for: band), let upper = clampedBand(band)?.upperBound
        else { return nil }
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
    /// orbit's hollow dot sits; no tick ring. Both numbers are VISIBLE distances, measured between the tips of the round
    /// caps: the first segment's tip is `seamClearDegrees` after the top and the last one's that far before it, and
    /// neighbours are `segmentGapDegrees` apart. The centrelines are therefore shortened by one cap (the stroke's
    /// half-width as an angle) at each end.
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
        let cap = m.outerRadius > 0 ? Double(m.outerStroke / 2 / m.outerRadius) * 180 / .pi : 0
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
