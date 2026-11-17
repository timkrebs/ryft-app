// A week as a line (Nocturne, docs/work/2026-11-16-nocturne/design.md §P4-1, "Sparkline"): the HRV series in Today's
// recovery tile, oldest first, in straight segments of 80 % ink. A missing day breaks the line (no interpolation); the last
// day's Volt dot, the series' "today" mark (L17), sits in a cleared ring as the gauge's dots do. Under two values it is
// the pending look: a flat, faint line and no dot.
import SwiftUI

/// A fixed 58 × 20 graphic; `values` oldest first, the last the tile's day, `nil` a day without one. Hidden from
/// VoiceOver: the tile it sits in says the series ("HRV 66 milliseconds, lowest 51 and highest 66 over the last 7 days").
struct Sparkline: View {
    nonisolated static let size = CGSize(width: 58, height: 20)
    /// The series' min and max sit this far inside the top and the bottom.
    nonisolated static let inset: CGFloat = 2
    nonisolated static let lineWidth: CGFloat = 1.3, lineOpacity = 0.8
    /// A value with a missing day on both sides draws a dot of the line's ink, this radius (derived: twice the stroke).
    nonisolated static let loneDotRadius: CGFloat = 1.3
    /// The last value's Volt dot, and the ring cleared around it through the line.
    nonisolated static let endDotRadius: CGFloat = 3, endDotClearance: CGFloat = 1.5
    /// The pending look: a flat line across at mid height.
    nonisolated static let pendingLineWidth: CGFloat = 1, pendingOpacity = 0.22
    /// The canvas reaches this far past the box on every side, so the end dot and its ring are never clipped.
    nonisolated static let overhang: CGFloat = 4.5

    /// The drawing in the box's points.
    struct Layout: Equatable, Sendable {
        /// Consecutive values, each run drawn as one polyline; a run of one point is a lone dot.
        var runs: [[CGPoint]]
        /// The last value's point, where the Volt dot goes; `nil` when the last day has none.
        var endDot: CGPoint?
        /// Fewer than two values: the flat pending line, no runs, no dot.
        var isPending: Bool
    }

    private let values: [Double?]

    init(values: [Double?]) {
        self.values = values
    }

    var body: some View {
        let o = Self.overhang
        Canvas { context, size in
            let box = CGSize(width: size.width - 2 * o, height: size.height - 2 * o)
            context.translateBy(x: o, y: o)
            draw(Self.layout(values: values, size: box), in: &context, box: box)
        }
        .frame(width: Self.size.width + 2 * o, height: Self.size.height + 2 * o)
        .padding(-o)
        .accessibilityHidden(true)
    }

    private func draw(_ layout: Layout, in context: inout GraphicsContext, box: CGSize) {
        if layout.isPending {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: box.height / 2))
            line.addLine(to: CGPoint(x: box.width, y: box.height / 2))
            context.stroke(line, with: .color(Theme.textPrimary.opacity(Self.pendingOpacity)), lineWidth: Self.pendingLineWidth)
            return
        }
        let ink = GraphicsContext.Shading.color(Theme.textPrimary.opacity(Self.lineOpacity))
        var lines = Path()
        for run in layout.runs where run.count > 1 { lines.addLines(run) }
        context.stroke(lines, with: ink, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round))
        for run in layout.runs where run.count == 1 && run[0] != layout.endDot {
            context.fill(Self.circle(run[0], Self.loneDotRadius), with: ink)
        }
        guard let end = layout.endDot else { return }
        // The ring is cut out of the line itself, so the tile shows through it.
        context.blendMode = .destinationOut
        context.fill(Self.circle(end, Self.endDotRadius + Self.endDotClearance), with: .color(.black))
        context.blendMode = .normal
        context.fill(Self.circle(end, Self.endDotRadius), with: .color(Theme.signal))
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    // MARK: layout (pure)

    /// Fewer than two values (of any count of days): nothing to draw a line between.
    nonisolated static func isPending(_ values: [Double?]) -> Bool {
        values.compactMap { $0 }.filter(\.isFinite).count < 2
    }

    /// Value `i` of `n` at x = i / (n − 1) × width (the first at 0, the last at the box's trailing edge); y from the
    /// series' max at `inset` to its min at height − `inset`, mid height when they are equal. A missing or non-finite
    /// value breaks the run.
    nonisolated static func layout(values: [Double?], size: CGSize = Sparkline.size) -> Layout {
        guard !isPending(values) else { return Layout(runs: [], endDot: nil, isPending: true) }
        let present = values.compactMap { $0 }.filter(\.isFinite)
        let lo = present.min() ?? 0, hi = present.max() ?? 0
        let n = values.count
        func point(_ i: Int, _ v: Double) -> CGPoint {
            let x = n > 1 ? CGFloat(i) / CGFloat(n - 1) * size.width : size.width
            let y = hi > lo ? inset + CGFloat((hi - v) / (hi - lo)) * (size.height - 2 * inset) : size.height / 2
            return CGPoint(x: x, y: y)
        }
        var runs: [[CGPoint]] = [], run: [CGPoint] = []
        for (i, value) in values.enumerated() {
            if let value, value.isFinite {
                run.append(point(i, value))
            } else if !run.isEmpty {
                runs.append(run)
                run = []
            }
        }
        if !run.isEmpty { runs.append(run) }
        let end = values.last.flatMap { $0 }.flatMap { $0.isFinite ? point(n - 1, $0) : nil }
        return Layout(runs: runs, endDot: end, isPending: false)
    }
}

#Preview("Sparkline", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 16) {
            // The board's week (lowest 51, highest 66, today last), a gap, a lone day, no value today, pending.
            Sparkline(values: [58, 51, 60, 55, 62, 57, 66])
            Sparkline(values: [58, 51, nil, 55, 62, 57, 66])
            Sparkline(values: [58, nil, 60, nil, 62, 57, 66])
            Sparkline(values: [58, 51, 60, 55, 62, 57, nil])
            Sparkline(values: [60, 60, 60, 60, 60, 60, 60])
            Sparkline(values: [nil, nil, nil, nil, nil, nil, 66])
            GlowTile(Theme.recovery, kind: .twoUp) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "Recovery").ryftGlowLabelStyle()
                    Spacer(minLength: 8)
                    Sparkline(values: [58, 51, 60, 55, 62, 57, 66])
                }
            }
            .frame(width: 169)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Sparkline · AX3", traits: .sizeThatFitsLayout) {
    // A graphic: it keeps its size; the label beside it grows.
    DarkPreview {
        GlowTile(Theme.recovery, kind: .twoUp) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Recovery").ryftGlowLabelStyle()
                Sparkline(values: [58, 51, 60, 55, 62, 57, 66])
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
