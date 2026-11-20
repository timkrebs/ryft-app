// The small ring that stands for a metric in a legend (Nocturne, docs/work/2026-11-16-nocturne/build-plan.md §2; PR 6 A
// Welcome's three rows, C's Insights legend and About): a quiet track, an arc in the metric's colour from 12 o'clock and a
// dot at its end, as the gauges draw a value. Decoration: the row's text says what it is.
import SwiftUI

/// The legend mark's numbers, at its 28 pt default size; the strokes and the dot scale with it.
enum LegendMarkSpec {
    /// The mark's side at the default text size; it grows with `.headline` up to `maxSide`.
    static let side: CGFloat = 28
    static let maxSide: CGFloat = 44
    /// The track: 1.5 pt, ink at 16 %.
    static let trackWidth: CGFloat = 1.5
    static let trackOpacity = 0.16
    /// The arc: 2.5 pt, round caps, 62 % of the turn from 12 o'clock, clockwise.
    static let arcWidth: CGFloat = 2.5
    static let fraction = 0.62
    /// The dot at the arc's end: 3.5 radius in the arc's colour, ringed 1.5 in `background` so it reads over the track.
    static let dotRadius: CGFloat = 3.5
    static let dotRing: CGFloat = 1.5

    /// The ring's radius in a mark of `side`: the outer edge of the arc or the dot's ring touches the frame.
    static func radius(side: CGFloat) -> CGFloat {
        let scale = side / Self.side
        return side / 2 - max(arcWidth / 2, dotRadius + dotRing) * scale
    }

    /// The arc's end on a ring of `radius` around `centre`: `fraction` of a clockwise turn from 12 o'clock.
    static func endPoint(centre: CGPoint, radius: CGFloat, fraction: Double = fraction) -> CGPoint {
        let angle = 2 * Double.pi * fraction - Double.pi / 2
        return CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
    }
}

/// `LegendMark(Theme.recovery)`: the ring for one metric, 28 pt, hidden from VoiceOver. `fraction` changes how far the arc
/// reaches (a legend that shows a share); the default is the drafts' 62 %.
struct LegendMark: View {
    private let tint: Color
    private let fraction: Double

    @ScaledMetric(relativeTo: .headline) private var scaledSide: CGFloat = LegendMarkSpec.side

    init(_ tint: Color, fraction: Double = LegendMarkSpec.fraction) {
        self.tint = tint
        self.fraction = min(1, max(0, fraction))
    }

    var body: some View {
        let side = min(scaledSide, LegendMarkSpec.maxSide)
        let scale = side / LegendMarkSpec.side
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = LegendMarkSpec.radius(side: min(size.width, size.height))
            var track = Path()
            track.addArc(center: centre, radius: radius, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            context.stroke(track, with: .color(Theme.textPrimary.opacity(LegendMarkSpec.trackOpacity)),
                           lineWidth: LegendMarkSpec.trackWidth * scale)
            guard fraction > 0 else { return }
            var arc = Path()
            arc.addArc(center: centre, radius: radius, startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
            context.stroke(arc, with: .color(tint),
                           style: StrokeStyle(lineWidth: LegendMarkSpec.arcWidth * scale, lineCap: .round))
            let end = LegendMarkSpec.endPoint(centre: centre, radius: radius, fraction: fraction)
            let outer = (LegendMarkSpec.dotRadius + LegendMarkSpec.dotRing) * scale
            let inner = LegendMarkSpec.dotRadius * scale
            context.fill(Path(ellipseIn: CGRect(x: end.x - outer, y: end.y - outer, width: 2 * outer, height: 2 * outer)),
                         with: .color(Theme.background))
            context.fill(Path(ellipseIn: CGRect(x: end.x - inner, y: end.y - inner, width: 2 * inner, height: 2 * inner)),
                         with: .color(tint))
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

private struct LegendMarkPreviewBoard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            row(Theme.recovery, "Recovery", "How ready your body is today.")
            row(Theme.metricStrain, "Strain", "How much you asked of it.")
            row(Theme.metricSleep, "Sleep", "How well you paid it back.")
            HStack(spacing: 16) {
                LegendMark(Theme.recovery, fraction: 0.25)
                LegendMark(Theme.metricStrain, fraction: 0.9)
                LegendMark(Theme.textSecondary, fraction: 0)
            }
        }
    }

    private func row(_ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            LegendMark(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.ryft(.headline)).foregroundStyle(Theme.textPrimary)
                Text(verbatim: detail).font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

#Preview("LegendMark", traits: .sizeThatFitsLayout) {
    DarkPreview { LegendMarkPreviewBoard() }
}

#Preview("LegendMark · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { LegendMarkPreviewBoard() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
