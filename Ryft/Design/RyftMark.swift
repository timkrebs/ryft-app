// The RYFT "orbit" mark (2026-10-28, supersedes the mark on design/brand-board.png):
// three concentric rings on a common centre, round-capped, each broken where a dot
// sits on it. Outer ring: one dot, lower right. Middle ring: two dots, upper
// centre-right and left. Inner ring: closed, empty. Pure vector, filled with the
// current foreground style, so it scales to any size and takes any colour.
//
// GEOMETRY. All numbers live in `RyftMarkGeometry`, in a 100 x 100 box with the
// centre at 50/50, and are scaled by side/100. The numbers are stroke-centreline
// radii, so the outer ring's outer edge is 44 + 1.58 = 45.58 from the centre: the
// mark covers 91.16 % of the box, the rest is padding. The web port copies the
// constants as they are; design/ryft-mark.svg is generated from them
// (scripts/mark-svg.swift).
//
// CLEAR AIR. A ring ends in a round cap, i.e. a disc of radius stroke/2 centred on
// the arc's end point E. The air between ring and dot is the distance from that disc
// to the dot's edge, measured along the line E -> dot centre D:
//
//     |E D| = dotR + stroke/2 + airFactor * stroke        (airFactor = 1.0)
//
// E and D both lie on the ring (radius R), so |E D| is the chord of the angle
// between them:
//
//     |E D| = 2 R sin(halfGap / 2)   =>   halfGap = 2 asin(|E D| / (2 R))
//
// Each arc therefore starts at (dot angle + halfGap) and ends at
// (next dot angle - halfGap). With the measured values:
//     outer  (R 44.0): |E D| = 10.74, halfGap = 14.02 deg
//     middle (R 25.6): |E D| = 10.74, halfGap = 24.22 deg
// (The tangent tip of the cap is up to 0.1 stroke farther from the dot than the
// nearest point of the cap, so the nearest-point rule is the one the eye reads.)
//
// OPTICAL SIZE. At 24 pt the nominal stroke is 0.76 pt, a hairline. The rule, a
// pure function of the rendered side (`RyftMarkGeometry.metrics(forSide:)`), with
// k = max(1, 1.25 pt / nominal stroke pt):
//   - stroke = 3.16 x k (box units), i.e. max(3.16 % of side, 1.25 pt). k = 1 from
//     39.6 pt up, so 44 pt and 1024 pt match the measured numbers exactly.
//   - dot radius = 6.0 x sqrt(k) and clear air = airFactor x 3.16 x sqrt(k): both
//     grow by the square root of the stroke factor. The stroke must thicken to stay
//     visible, but dots and gaps scaled by the full k would eat the short arcs (the
//     old rule left 354 deg "drawn" through two dots at 18 pt). The dot is a little
//     heavier relative to the stroke than at nominal size, which suits a small mark.
//     In `halfGap` the air is recovered from the metrics as airFactor x sqrt(3.16 x
//     effective stroke), which is the same thing.
//   - the inner ring is dropped below 22 pt: its hole would be under 1 pt wide.
//     The 18 pt mark is two rings and three dots.
//   - `arcs` drops any arc whose sweep would be <= 0 (defensive: with the rule above
//     the shortest arc, middle ring between the dots at 180 and 284 deg, is 26 deg
//     at 18 pt).
// Below 18 pt the mark is not supported (nothing in the app asks for it).
//
//   side   stroke  dot r   halfGap  halfGap  middle short-arc
//   (pt)   (pt)    (box)   outer    middle   sweep (180 -> 284 deg)
//   18     1.25    8.89    22.34    38.90    26.2 deg
//   20     1.25    8.44    20.96    36.44    31.1 deg
//   24     1.25    7.70    18.79    32.59    38.8 deg
//   34     1.25    6.47    15.30    26.46    51.1 deg
//   44     1.39    6.00    14.02    24.22    55.6 deg   (nominal)
// (box dot r x side / 100 = points; sweep = 104 - 2 x middle halfGap. The visible
// arc is longer than its sweep by one stroke, the two round caps.)
//
// This file only depends on SwiftUI so scripts/render-icon.swift and
// scripts/mark-svg.swift can compile it for macOS and draw from the exact same
// geometry.
import SwiftUI

/// The mark's measured geometry in a 100 x 100 box (centre 50/50). Angles in
/// degrees, 0 = 3 o'clock, clockwise (y points down).
enum RyftMarkGeometry {
    static let box = 100.0
    static let centre = 50.0

    /// Stroke width of every ring (round caps).
    static let stroke = 3.16
    /// Radius of every dot; dots are centred on their ring and break it.
    static let dotRadius = 6.0
    /// Clear air between a cap and a dot's edge, in multiples of the nominal stroke
    /// (scaled by sqrt(k) at small sizes, see OPTICAL SIZE).
    static let airFactor = 1.0

    struct Ring {
        /// Radius of the stroke centreline.
        let radius: Double
        /// Dot angles, ascending.
        let dots: [Double]
    }

    static let outer = Ring(radius: 44.0, dots: [65])
    static let middle = Ring(radius: 25.6, dots: [-76, 180])
    /// Closed ring, no dots, no centre dot.
    static let innerRadius = 7.6

    // Optical size (see the header).
    static let minStrokePt = 1.25
    static let innerRingMinSide = 22.0

    /// Stroke, dot radius and inner-ring visibility for a given rendered side, in
    /// box units (multiply by side/100 for points).
    struct Metrics: Equatable {
        let stroke: Double
        let dotRadius: Double
        let showsInnerRing: Bool
    }

    static func metrics(forSide side: Double) -> Metrics {
        guard side > 0 else { return Metrics(stroke: stroke, dotRadius: dotRadius, showsInnerRing: false) }
        let nominalPt = stroke * side / box
        let k = max(1, minStrokePt / nominalPt)
        return Metrics(stroke: stroke * k, dotRadius: dotRadius * k.squareRoot(),
                       showsInnerRing: side >= innerRingMinSide)
    }

    /// Half the angular gap (degrees) a dot cuts out of its ring, on each side.
    /// The air is airFactor x nominal stroke x sqrt(k) = airFactor x sqrt(stroke x
    /// effective stroke), see OPTICAL SIZE.
    static func halfGap(ringRadius r: Double, metrics m: Metrics) -> Double {
        let air = airFactor * (stroke * m.stroke).squareRoot()
        let chord = m.dotRadius + m.stroke / 2 + air
        return 2 * asin(min(1, chord / (2 * r))) * 180 / .pi
    }

    /// The visible arcs (start, end in degrees, ascending; the last arc's end can
    /// exceed 360) of a ring, one between each pair of neighbouring dots.
    static func arcs(of ring: Ring, metrics m: Metrics) -> [(start: Double, end: Double)] {
        let gap = halfGap(ringRadius: ring.radius, metrics: m)
        let dots = ring.dots.sorted()
        return dots.enumerated().compactMap { i, a in
            let next = i == dots.count - 1 ? dots[0] + 360 : dots[i + 1]
            let start = a + gap, end = next - gap
            // Guard: if the gaps of two neighbouring dots meet or overlap there is
            // no arc between them; drawing one would sweep the long way round.
            return end > start ? (start: start, end: end) : nil
        }
    }

    /// Point on a ring in box units.
    static func point(radius: Double, degrees: Double) -> (x: Double, y: Double) {
        let r = degrees * .pi / 180
        return (centre + radius * cos(r), centre + radius * sin(r))
    }
}

struct RyftMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let g = RyftMarkGeometry.self
        let m = g.metrics(forSide: Double(side))
        let u = side / g.box
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let style = StrokeStyle(lineWidth: m.stroke * u, lineCap: .round)

        var p = Path()
        for ring in [g.outer, g.middle] {
            for a in g.arcs(of: ring, metrics: m) {
                var arc = Path()
                // SwiftUI's `clockwise` is mirrored in y-down space: false = visually clockwise.
                arc.addArc(center: c, radius: ring.radius * u,
                           startAngle: .degrees(a.start), endAngle: .degrees(a.end),
                           clockwise: false)
                p.addPath(arc.strokedPath(style))
            }
            for d in ring.dots {
                let r = d * .pi / 180
                let pt = CGPoint(x: c.x + ring.radius * u * cos(r), y: c.y + ring.radius * u * sin(r))
                let dr = m.dotRadius * u
                p.addEllipse(in: CGRect(x: pt.x - dr, y: pt.y - dr, width: dr * 2, height: dr * 2))
            }
        }
        if m.showsInnerRing {
            let ir = g.innerRadius * u
            var inner = Path()
            inner.addEllipse(in: CGRect(x: c.x - ir, y: c.y - ir, width: ir * 2, height: ir * 2))
            p.addPath(inner.strokedPath(StrokeStyle(lineWidth: m.stroke * u)))
        }
        return p
    }
}

/// The mark as a view. Colour comes from `.foregroundStyle`, size from `.frame`.
/// The frame is the 100-box: the outer ring's edge sits at 91 % of it.
struct RyftMark: View {
    var body: some View {
        RyftMarkShape()
            .fill(.foreground)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

#if os(iOS)
#Preview("Mark", traits: .sizeThatFitsLayout) {
    HStack(alignment: .center, spacing: 24) {
        RyftMark().frame(width: 120)
        RyftMark().frame(width: 44)
        RyftMark().frame(width: 24)
        RyftMark().frame(width: 18)
    }
    .foregroundStyle(Theme.textPrimary)
    .padding(32)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}

#Preview("Mark · light", traits: .sizeThatFitsLayout) {
    HStack(alignment: .center, spacing: 24) {
        RyftMark().frame(width: 120)
        RyftMark().frame(width: 44).foregroundStyle(Theme.accent)
        RyftMark().frame(width: 24)
        RyftMark().frame(width: 18)
    }
    .foregroundStyle(Theme.textPrimary)
    .padding(32)
    .background(Theme.background)
    .preferredColorScheme(.light)
}
#endif
