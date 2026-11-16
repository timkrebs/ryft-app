// One heart-rate zone as a row of ticks (Nocturne, docs/work/2026-11-16-nocturne/design.md §P2-4): label, 30 ticks lit
// in proportion to the minutes, value. Five rows make the zones block; the caller stacks them with
// `VStack(spacing: TickRow.rowSpacing)` and groups them with `.accessibilityElement(children: .contain)`.
import SwiftUI

/// `label` (74 pt, `textSecondary`) · 30 ticks of 3 × 12 (177 pt) · `value` (40 pt, trailing), 12 pt apart. The first
/// `litCount` ticks are `textPrimary`, the rest 12 %. A label wider than 74 pt widens its own column (this row's ticks then
/// start further right; never truncated, never over the ticks). When the row no longer fits, and always from AX1, the label
/// and value go on a line above the ticks. A block of rows that must keep one tick column decides stacking for all of
/// them. One accessibility element with the caller's label ("Zone 3, 24 minutes").
struct TickRow: View {
    nonisolated static let tickCount = 30, tick = CGSize(width: 3, height: 12), tickGap: CGFloat = 3, rowSpacing: CGFloat = 9
    static let labelWidth: CGFloat = 74, valueWidth: CGFloat = 40, unlitOpacity = 0.12
    static let tickRadius: CGFloat = 1.5
    /// The ticks' width: 30·3 + 29·3 = 177.
    static let ticksWidth = CGFloat(tickCount) * tick.width + CGFloat(tickCount - 1) * tickGap
    /// Stacked layout: the gap between the label line and the ticks.
    static let stackedSpacing: CGFloat = 4

    private let label: Text
    private let minutes: Double?
    private let scaleMax: Double
    private let value: Text
    private let accessibilityLabel: Text

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var scaledLabelWidth: CGFloat = TickRow.labelWidth
    @ScaledMetric(relativeTo: .caption) private var scaledValueWidth: CGFloat = TickRow.valueWidth
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = TickRow.tick.height

    /// - Parameters:
    ///   - minutes: time in the zone; `nil` lights nothing, and `value` then says "–" or "no data".
    ///   - scaleMax: the minutes that light all 30 ticks; the same for every row of a block.
    init(label: Text, minutes: Double?, scaleMax: Double, value: Text, accessibilityLabel: Text) {
        self.label = label
        self.minutes = minutes
        self.scaleMax = scaleMax
        self.value = value
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    row
                    stacked
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The one-line layout. The label column is at least the scaled 74 pt and grows to the label's ideal width; its
    /// layout priority makes the HStack size it before the flexible value column, so a mid-length label pushes the
    /// ticks right instead of running into them. A label too long for the row makes `ViewThatFits` stack. A short
    /// label keeps the column at exactly 74: the ticks start at 74 + 12.
    private var row: some View {
        HStack(spacing: Theme.Metrics.itemSpacing) {
            styledLabel
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: scaledLabelWidth, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
                .layoutPriority(1)
            ticks
            styledValue
                .lineLimit(1)
                .frame(minWidth: scaledValueWidth, maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight,
                       alignment: .trailing)
        }
        .frame(height: rowHeight)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: Self.stackedSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Metrics.itemSpacing) {
                styledLabel
                Spacer(minLength: 0)
                styledValue
            }
            ticks
        }
    }

    private var styledLabel: some View {
        label.font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
    }

    private var styledValue: some View {
        value.font(.ryft(.caption)).foregroundStyle(Theme.textPrimary)
    }

    private var ticks: some View {
        let lit = Self.litCount(minutes: minutes, scaleMax: scaleMax)
        return ZStack {
            TickBars(indices: lit..<Self.tickCount, tick: Self.tick, gap: Self.tickGap, radius: Self.tickRadius)
                .fill(Theme.textPrimary.opacity(Self.unlitOpacity))
            TickBars(indices: 0..<lit, tick: Self.tick, gap: Self.tickGap, radius: Self.tickRadius)
                .fill(Theme.textPrimary)
        }
        .frame(width: Self.ticksWidth, height: Self.tick.height)
    }

    // MARK: layout (pure)

    /// `clamp(round(minutes·30 / scaleMax), 0…30)`; `nil`, negative, NaN or `scaleMax ≤ 0` lights none.
    nonisolated static func litCount(minutes: Double?, scaleMax: Double) -> Int {
        guard let minutes, !minutes.isNaN, scaleMax > 0 else { return 0 }
        let raw = (minutes * Double(tickCount) / scaleMax).rounded()
        guard !raw.isNaN else { return 0 }
        return Int(min(max(raw, 0), Double(tickCount)))
    }
}

/// Rounded ticks at the given indices, left to right.
private struct TickBars: Shape {
    let indices: Range<Int>
    let tick: CGSize
    let gap: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in indices {
            let x = rect.minX + CGFloat(i) * (tick.width + gap)
            path.addRoundedRect(in: CGRect(x: x, y: rect.minY, width: tick.width, height: tick.height),
                                cornerSize: CGSize(width: radius, height: radius))
        }
        return path
    }
}

#Preview("TickRow", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: TickRow.rowSpacing) {
            TickRow(label: Text("Zone 1"), minutes: 12, scaleMax: 60, value: Text(verbatim: "12m"),
                    accessibilityLabel: Text("Zone 1, 12 minutes"))
            TickRow(label: Text("Zone 2"), minutes: 31, scaleMax: 60, value: Text(verbatim: "31m"),
                    accessibilityLabel: Text("Zone 2, 31 minutes"))
            TickRow(label: Text("Zone 3"), minutes: 24, scaleMax: 60, value: Text(verbatim: "24m"),
                    accessibilityLabel: Text("Zone 3, 24 minutes"))
            TickRow(label: Text("Zone 4"), minutes: 7, scaleMax: 60, value: Text(verbatim: "7m"),
                    accessibilityLabel: Text("Zone 4, 7 minutes"))
            TickRow(label: Text("Zone 5"), minutes: 1, scaleMax: 60, value: Text(verbatim: "1m"),
                    accessibilityLabel: Text("Zone 5, 1 minute"))
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("TickRow · no data", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: TickRow.rowSpacing) {
            TickRow(label: Text("Zone 1"), minutes: nil, scaleMax: 60, value: Text(verbatim: "–"),
                    accessibilityLabel: Text("Zone 1, no data"))
            TickRow(label: Text("Zone 2"), minutes: nil, scaleMax: 60, value: Text(verbatim: "–"),
                    accessibilityLabel: Text("Zone 2, no data"))
        }
    }
}

#Preview("TickRow · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: TickRow.rowSpacing) {
            TickRow(label: Text("Zone 2"), minutes: 31, scaleMax: 60, value: Text(verbatim: "31m"),
                    accessibilityLabel: Text("Zone 2, 31 minutes"))
            TickRow(label: Text("Zone 3"), minutes: 24, scaleMax: 60, value: Text(verbatim: "24m"),
                    accessibilityLabel: Text("Zone 3, 24 minutes"))
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
