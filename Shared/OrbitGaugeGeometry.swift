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
                       dotRadius: dot, hollowStroke: max(2 * s, 1.25), dotAir: 2.5 * s)
    }

    /// Point on an orbit for an angle, in a rect centred on `centre`.
    static func point(centre: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let r = (degrees - 90) * .pi / 180
        return CGPoint(x: centre.x + radius * CGFloat(cos(r)), y: centre.y + radius * CGFloat(sin(r)))
    }
}
