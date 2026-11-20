// The heart-rate zones as five tick rows that share one tick column (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-3.4,
// review rows 13 and 17): the block measures its labels and picks one arrangement for every row, aligned (one label column, all
// ticks start at the same x) when the widest row fits, else stacked (label and value above, the ticks below). Strain's and the
// workout's zones tiles hold one (`GlowTile(metricStrain, kind: .zones)`); the footnote under the tile is the caller's.
import SwiftUI

struct ZoneBlock: View {
    /// One row: the zone's name ("Z4 · Threshold"), its minutes (`nil`: no data, nothing lit), the value text ("12m", "–") and
    /// what VoiceOver reads for the row ("Zone 4, threshold, 80 to 90 percent of heart-rate reserve, 12 minutes").
    struct Zone {
        let label: Text
        let minutes: Double?
        let value: Text
        let accessibilityLabel: Text
    }

    /// The minutes that light all 30 ticks: 40 (a zone of 40 minutes or more lights them all; its minutes are in the value).
    nonisolated static let defaultScaleMax = 40.0

    private let zones: [Zone]
    private let scaleMax: Double
    private let accessibilityLabel: Text

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var minLabelColumn: CGFloat = TickRow.labelWidth
    @ScaledMetric(relativeTo: .caption) private var valueColumn: CGFloat = TickRow.valueWidth
    /// The widest label's ideal width and the block's width, measured after layout; `nil` until then.
    @State private var widestLabel: CGFloat?
    @State private var available: CGFloat?

    /// - Parameters:
    ///   - zones: top to bottom as the board ("Z5 · Max" first); every row shares `scaleMax`.
    ///   - accessibilityLabel: the block's name for VoiceOver ("Heart-rate zones"); each row is its own element after it.
    init(zones: [Zone], scaleMax: Double = ZoneBlock.defaultScaleMax, accessibilityLabel: Text) {
        self.zones = zones
        self.scaleMax = scaleMax
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TickRow.rowSpacing) {
            ForEach(zones.indices, id: \.self) { i in
                TickRow(label: zones[i].label, minutes: zones[i].minutes, scaleMax: scaleMax, value: zones[i].value,
                        accessibilityLabel: zones[i].accessibilityLabel)
            }
        }
        .environment(\.tickRowArrangement, arrangement)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
        .background(alignment: .topLeading) { labelProbe }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The labels at their ideal width in the rows' font, hidden: the widest is the aligned label column.
    private var labelProbe: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(zones.indices, id: \.self) { i in
                zones[i].label.font(.ryft(.caption)).lineLimit(1).fixedSize()
            }
        }
        .fixedSize()
        .hidden()
        .accessibilityHidden(true)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widestLabel = $0 }
    }

    /// Stacked until the block knows its width and its labels (the first layout pass), then the decision.
    private var arrangement: TickRowArrangement {
        guard let widestLabel, let available else { return .stacked }
        return Self.arrangement(widestLabel: widestLabel, available: available, minLabelColumn: minLabelColumn,
                                valueColumn: valueColumn, isAccessibilitySize: typeSize.isAccessibilitySize)
    }

    /// The rule (§P5-3.4): from AX1 stacked; else the label column is the widest label (rounded up to a whole point) or the
    /// scaled 74, whichever is wider, and the rows are aligned when column + 12 + 177 (the ticks) + 12 + the value column fit in
    /// `available`, else all stacked. At 390 the board's widest label, "Z4 · Threshold", is 76: 76 + 12 + 177 + 12 + 40 = 317 ≤ 318.
    static func arrangement(widestLabel: CGFloat, available: CGFloat, minLabelColumn: CGFloat = TickRow.labelWidth,
                            valueColumn: CGFloat = TickRow.valueWidth,
                            isAccessibilitySize: Bool) -> TickRowArrangement {
        guard !isAccessibilitySize else { return .stacked }
        let column = max(minLabelColumn, widestLabel.rounded(.up))
        let gap = Theme.Metrics.itemSpacing
        let needed = column + gap + TickRow.ticksWidth + gap + valueColumn
        return needed <= available ? .aligned(labelColumn: column) : .stacked
    }
}

// MARK: previews

/// The board's zones (§P5-3.4): names top to bottom, minutes 11 / 24 / 27 / 14 / 6.
@MainActor
private func previewZones(minutes: [Double?] = [6, 14, 27, 24, 11]) -> [ZoneBlock.Zone] {
    let names = ["Z5 · Max", "Z4 · Threshold", "Z3 · Tempo", "Z2 · Aerobic", "Z1 · Easy"]
    return zip(names, minutes).map { name, m in
        ZoneBlock.Zone(label: Text(verbatim: name), minutes: m, value: Text(verbatim: m.map { "\(Int($0))m" } ?? "–"),
                       accessibilityLabel: Text(verbatim: "\(name), \(m.map { "\(Int($0)) minutes" } ?? "no data")"))
    }
}

private struct ZoneBlockPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // In the zones tile at 390: 318 inside, aligned.
            GlowTile(Theme.metricStrain, kind: .zones) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: "Heart-rate zones").ryftGlowLabelStyle()
                        Spacer(minLength: 0)
                        Text(verbatim: "82 min").font(.ryft(.caption))
                    }
                    ZoneBlock(zones: previewZones(), accessibilityLabel: Text(verbatim: "Heart-rate zones"))
                }
            }
            // 303 inside (an SE's tile): stacked.
            ZoneBlock(zones: previewZones(), accessibilityLabel: Text(verbatim: "Heart-rate zones"))
                .frame(width: 303)
                .border(Theme.separator)
            // No data: nothing lit, "–".
            ZoneBlock(zones: previewZones(minutes: [nil, nil, nil, nil, nil]), accessibilityLabel: Text(verbatim: "Heart-rate zones"))
        }
    }
}

#Preview("ZoneBlock", traits: .sizeThatFitsLayout) {
    DarkPreview { ZoneBlockPreview() }
}

#Preview("ZoneBlock · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { ZoneBlockPreview() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
