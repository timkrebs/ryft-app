import SwiftUI

/// Heart-rate-zone minutes as one stacked horizontal bar, minute labels over
/// segments wide enough to carry them, and a Z1–Z5 legend with the HRR ranges.
struct ZoneBar: View {
    /// Minutes in zones 1–5 (`DayStrain.zone_min`); nil or empty shows a placeholder.
    let minutes: [Double]?

    static let ranges = ["50–60 %", "60–70 %", "70–80 %", "80–90 %", "≥ 90 %"]

    private var values: [Double] {
        guard let minutes, minutes.count == 5 else { return [] }
        return minutes
    }

    private static let gap: CGFloat = 2
    private static let minLabelWidth: CGFloat = 26

    var body: some View {
        let values = values
        let total = values.reduce(0, +)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let shown = values.indices.filter { values[$0] > 0 }
                let available = geo.size.width - Self.gap * CGFloat(max(0, shown.count - 1))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Self.gap) {
                        ForEach(shown, id: \.self) { i in
                            let w = max(2, available * values[i] / max(total, 1))
                            Text(w >= Self.minLabelWidth ? "\(Int(values[i].rounded()))" : " ")
                                .font(ChartStyle.axisFont)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: w)
                        }
                    }
                    HStack(spacing: Self.gap) {
                        if total <= 0 {
                            Rectangle().fill(Theme.surfaceRaised)
                        } else {
                            ForEach(shown, id: \.self) { i in
                                Rectangle()
                                    .fill(Theme.zones[i])
                                    .frame(width: max(2, available * values[i] / total))
                            }
                        }
                    }
                    .frame(height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
            }
            .frame(height: 26)

            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1.5).fill(Theme.zones[i]).frame(width: 8, height: 8)
                            Text("Z\(i + 1)")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(values.isEmpty ? Fmt.placeholder : "\(Int(values[i].rounded())) min")
                            .font(.ryft(.callout))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text(Self.ranges[i])
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Zones in % of heart-rate reserve")
                .font(ChartStyle.axisFont)
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart-rate zones"))
        .accessibilityValue(Text(values.isEmpty ? String(localized: "No data")
            : values.enumerated().map { "Zone \($0.offset + 1): \(Int($0.element.rounded())) min" }.joined(separator: ", ")))
    }
}

#Preview("ZoneBar", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 24) {
            ZoneBar(minutes: MockData.todayDetail.strain?.zoneMin.map(Double.init))
            ZoneBar(minutes: [3, 41, 18, 2, 0])
            ZoneBar(minutes: nil)
        }
    }
}
