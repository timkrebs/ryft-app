import SwiftUI

/// "▲ +4 ms · +8 %": arrow, signed change, and the percentage for raw
/// physiology. The colour comes from direction × the metric's polarity: teal when
/// the change is good, Alert when it's bad, secondary ink when the metric has no
/// good direction. Under 2 % it reads "Steady" (spoken "No change"); without a delta
/// nothing renders, so no "—" ever stands in for a value. The arrow and sign carry the
/// meaning, so it never rests on colour alone.
struct DeltaLabel: View {
    let spec: MetricSpec
    let delta: MetricDelta?
    /// After the change, e.g. "vs 7 d".
    var reference: String? = nil
    var font: Font = .ryft(.caption)

    var body: some View {
        if let delta {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Self.text(delta, spec: spec))
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(Self.color(delta, spec: spec))
                if let reference {
                    Text(reference)
                        .font(font)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Self.spoken(delta, spec: spec, reference: reference)))
        }
    }

    static func text(_ d: MetricDelta, spec: MetricSpec) -> String {
        if d.isFlat { return String(localized: "Steady", comment: "A change under 2 %, before \"vs 7 d\".") }
        let up = d.value > 0
        var s = "\(up ? "▲" : "▼") \(up ? "+" : "−")\(spec.deltaMagnitude(abs(d.value)))"
        if spec.deltaShowsPercent, let p = d.percent {
            s += " · \(up ? "+" : "−")\(Int(abs(p).rounded())) %"
        }
        return s
    }

    static func color(_ d: MetricDelta, spec: MetricSpec) -> Color {
        if d.isFlat { return Theme.textSecondary }
        switch spec.polarity {
        case .neutral: return Theme.textSecondary
        case .higherIsBetter: return d.value > 0 ? Theme.accent : Theme.alert
        case .lowerIsBetter: return d.value < 0 ? Theme.accent : Theme.alert
        }
    }

    static func spoken(_ d: MetricDelta, spec: MetricSpec, reference: String?) -> String {
        var s: String
        if d.isFlat {
            s = String(localized: "No change")
        } else {
            let magnitude = spec.deltaMagnitude(abs(d.value))
            s = d.value > 0 ? String(localized: "Up \(magnitude)") : String(localized: "Down \(magnitude)")
            if spec.deltaShowsPercent, let p = d.percent {
                s += ", " + String(localized: "\(Int(abs(p).rounded())) percent")
            }
        }
        if let reference { s += " " + reference }
        return s
    }
}

#Preview("DeltaLabel", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 10) {
            DeltaLabel(spec: .hrv, delta: MetricDelta(current: 56, reference: 52), reference: "vs 7 d")
            DeltaLabel(spec: .hrv, delta: MetricDelta(current: 47, reference: 52), reference: "vs 7 d")
            DeltaLabel(spec: .rhr, delta: MetricDelta(current: 47, reference: 50), reference: "vs 7 d")
            DeltaLabel(spec: .readiness, delta: MetricDelta(current: 84, reference: 78), reference: "vs 7 d")
            DeltaLabel(spec: .strain, delta: MetricDelta(current: 14.2, reference: 11.0), reference: "vs 7 d")
            DeltaLabel(spec: .sleepMin, delta: MetricDelta(current: 468, reference: 443), reference: "vs 7 d")
            DeltaLabel(spec: .hrv, delta: MetricDelta(current: 52.5, reference: 52), reference: "vs 7 d")
        }
    }
}

#Preview("DeltaLabel · up, down, flat, none", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 10) {
            DeltaLabel(spec: .readiness, delta: MetricDelta(current: 84, reference: 78), reference: String(localized: "vs 7 d"))
            DeltaLabel(spec: .readiness, delta: MetricDelta(current: 70, reference: 78), reference: String(localized: "vs 7 d"))
            DeltaLabel(spec: .readiness, delta: MetricDelta(current: 80, reference: 79.6), reference: String(localized: "vs 7 d"))
            // nil: nothing at all, no gap (the border shows it takes no space).
            DeltaLabel(spec: .readiness, delta: nil, reference: String(localized: "vs 7 d"))
                .border(Theme.separator)
            ChartHeader(spec: .readiness, value: 80, delta: nil)
        }
    }
}

#Preview("DeltaLabel · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 10) {
            DeltaLabel(spec: .readiness, delta: MetricDelta(current: 80, reference: 79.6), reference: String(localized: "vs 7 d"))
            ChartHeader(spec: .readiness, value: 80, delta: MetricDelta(current: 80, reference: 79.6))
            ChartHeader(spec: .readiness, value: 80, delta: nil)
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}
