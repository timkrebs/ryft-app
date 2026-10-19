import SwiftUI

/// "Value within personal range": a min–max track with the typical band shaded,
/// a baseline tick, today's marker, numeric ends and a status in words.
struct RangeBar: View {
    enum Status {
        case below, inRange, above

        var title: String {
            switch self {
            case .below: return String(localized: "▼ below")
            case .inRange: return String(localized: "in range")
            case .above: return String(localized: "▲ above")
            }
        }
    }

    let spec: MetricSpec
    let value: Double?
    /// The ends of the track: the 30-day min–max.
    let range: ClosedRange<Double>
    /// The shaded typical band (inter-quartile, later ±σ). Status is judged against it.
    var typical: ClosedRange<Double>? = nil
    var baseline: Double? = nil

    private var status: Status? {
        guard let value else { return nil }
        let ref = typical ?? range
        return value < ref.lowerBound ? .below : value > ref.upperBound ? .above : .inRange
    }

    private var statusColor: Color {
        switch (status, spec.polarity) {
        case (.inRange?, _), (nil, _), (_, .neutral): return Theme.textSecondary
        case (.above?, .higherIsBetter), (.below?, .lowerIsBetter): return Theme.accent
        default: return Theme.alert
        }
    }

    private func x(_ v: Double, width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return width / 2 }
        return CGFloat(min(max((v - range.lowerBound) / span, 0), 1)) * width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(spec.title).ryftLabelStyle()
                Spacer(minLength: 4)
                MetricValueText(spec: spec, value: value, font: .ryft(.callout))
                if let status {
                    Text(status.title)
                        .font(.ryft(.caption))
                        .foregroundStyle(statusColor)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.surfaceRaised)
                        .frame(height: 6)
                    if let typical {
                        Rectangle()
                            .fill(spec.color.opacity(0.35))
                            .frame(width: max(2, x(typical.upperBound, width: w) - x(typical.lowerBound, width: w)),
                                   height: 6)
                            .offset(x: x(typical.lowerBound, width: w))
                    }
                    if let baseline {
                        Rectangle()
                            .fill(ChartStyle.reference)
                            .frame(width: 1, height: 12)
                            .offset(x: x(baseline, width: w) - 0.5)
                    }
                    if let value {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.textPrimary)
                            .frame(width: 2, height: 16)
                            .offset(x: x(value, width: w) - 1)
                    }
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                Text(spec.number(range.lowerBound))
                Spacer()
                if let baseline {
                    Text("baseline \(spec.number(baseline))")
                    Spacer()
                }
                Text(spec.number(range.upperBound))
            }
            .font(ChartStyle.axisFont)
            .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spec.title))
        .accessibilityValue(Text(spoken))
    }

    private var spoken: String {
        guard let value else { return String(localized: "No data") }
        let range = String(localized: "range \(spec.number(self.range.lowerBound)) to \(spec.text(self.range.upperBound))")
        return [spec.text(value), status?.title.trimmingCharacters(in: CharacterSet(charactersIn: "▲▼ ")), range]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

extension RangeBar {
    /// Range, inter-quartile band and baseline from a 30-day trend. Nil with fewer
    /// than five values or a flat series.
    init?(spec: MetricSpec, value: Double?, series: TrendSeries?) {
        let values = (series?.points.compactMap(\.value) ?? []).sorted()
        guard values.count >= 5, let lo = series?.min ?? values.first, let hi = series?.max ?? values.last,
              lo < hi else { return nil }
        func quantile(_ q: Double) -> Double {
            let i = q * Double(values.count - 1)
            let a = values[Int(i.rounded(.down))], b = values[Int(i.rounded(.up))]
            return a + (b - a) * (i - i.rounded(.down))
        }
        self.init(spec: spec, value: value, range: lo...hi, typical: quantile(0.25)...quantile(0.75),
                  baseline: series?.baseline)
    }
}

#Preview("RangeBar", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 18) {
            RangeBar(spec: .hrv, value: 58.2, range: 41...66, typical: 48...56, baseline: 53.1)
            RangeBar(spec: .rhr, value: 48.9, range: 46...55, typical: 48...51, baseline: 50.2)
            RangeBar(spec: .respRate, value: 14.6, range: 13.8...15.9, typical: 14.2...15.0)
            RangeBar(spec: .spo2, value: nil, range: 94...98)
        }
    }
}
