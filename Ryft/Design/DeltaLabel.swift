import SwiftUI

/// "▲ +4 ms · +8 %": arrow, signed change, and the percentage for raw
/// physiology. The colour comes from direction × the metric's polarity (design.md §P5-5.2): the metric's own colour when
/// the change is good (the legend: recovery teal, sleep violet), `alert` when it's bad, secondary ink when the metric has no
/// good direction. Under 2 %, or when its size rounds to nothing as written ("+0"), it reads "Steady" (spoken "No change");
/// without a delta nothing renders, so no "—" ever stands in for a value. The arrow and sign carry the
/// meaning, so it never rests on colour alone. No-break spaces hold the arrow to the number and a number to its unit, so a
/// long line wraps only after "·" (AX3); VoiceOver hears "vs 7 d" as "versus 7 days".
struct DeltaLabel: View {
    let spec: MetricSpec
    let delta: MetricDelta?
    /// After the change, e.g. "vs 7 d".
    var reference: String? = nil
    var font: Font = .ryft(.caption)
    /// The reference's ink; `nil` is `textTertiary`. Today's label row passes the change's own colour
    /// (`DeltaLabel.color(_:spec:)`), so "▲ +11 vs 7 d" is one colour (design.md §P4-1, row 7).
    var referenceColor: Color?

    /// The change stays whole ("▲ +11"); the reference wraps beside it when the line is too long
    /// (German at large text sizes), never cut off. A caller that needs one line limits it.
    var body: some View {
        if let delta {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Self.text(delta, spec: spec))
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(Self.color(delta, spec: spec))
                    .fixedSize()
                if let reference {
                    Text(reference)
                        .font(font)
                        .foregroundStyle(referenceColor ?? Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Self.spoken(delta, spec: spec, reference: reference)))
        }
    }

    /// U+00A0: between the arrow and the number, and between a number and its unit.
    nonisolated static let noBreakSpace = "\u{00A0}"

    /// The reference every 7-day change carries.
    static var sevenDayReference: String { String(localized: "vs 7 d") }

    /// Flat: under 2 % (`MetricDelta.isFlat`), or a size that rounds to nothing as written ("+0", "+0m").
    static func isFlat(_ d: MetricDelta, spec: MetricSpec) -> Bool {
        d.isFlat || spec.deltaMagnitude(abs(d.value)) == spec.deltaMagnitude(0)
    }

    static func text(_ d: MetricDelta, spec: MetricSpec) -> String {
        if isFlat(d, spec: spec) { return String(localized: "Steady", comment: "A change under 2 %, before \"vs 7 d\".") }
        let up = d.value > 0
        let size = spec.deltaMagnitude(abs(d.value)).replacingOccurrences(of: " ", with: noBreakSpace)
        var s = (up ? "▲" : "▼") + noBreakSpace + (up ? "+" : "−") + size
        if spec.deltaShowsPercent, let p = d.percent {
            s += " · \(up ? "+" : "−")\(Int(abs(p).rounded()))\(noBreakSpace)%"
        }
        return s
    }

    static func color(_ d: MetricDelta, spec: MetricSpec) -> Color {
        if isFlat(d, spec: spec) { return Theme.textSecondary }
        switch spec.polarity {
        case .neutral: return Theme.textSecondary
        case .higherIsBetter: return d.value > 0 ? goodColor(spec) : Theme.alert
        case .lowerIsBetter: return d.value < 0 ? goodColor(spec) : Theme.alert
        }
    }

    /// A good change's ink: the metric's colour (readiness, recovery and HRV teal, sleep violet: unchanged for Today's
    /// readiness). A metric drawn in a warning hue (resting HR and heart rate `alert`, active energy `warning`, until
    /// `MetricSpec` moves them to ink) takes `textPrimary` instead, so a good change is never red or amber.
    static func goodColor(_ spec: MetricSpec) -> Color {
        spec.color == Theme.alert || spec.color == Theme.warning ? Theme.textPrimary : spec.color
    }

    static func spoken(_ d: MetricDelta, spec: MetricSpec, reference: String?) -> String {
        var s: String
        if isFlat(d, spec: spec) {
            s = String(localized: "No change")
        } else {
            let magnitude = spec.deltaMagnitude(abs(d.value))
            s = d.value > 0 ? String(localized: "Up \(magnitude)") : String(localized: "Down \(magnitude)")
            if spec.deltaShowsPercent, let p = d.percent {
                s += ", " + String(localized: "\(Int(abs(p).rounded())) percent")
            }
        }
        if let reference { s += " " + spokenReference(reference) }
        return s
    }

    /// "vs 7 d" as VoiceOver says it: "versus 7 days". Another reference is read as written.
    static func spokenReference(_ reference: String) -> String {
        guard reference == sevenDayReference else { return reference }
        return String(localized: "versus 7 days", comment: "VoiceOver: \"vs 7 d\" after a change, e.g. \"Up 11 versus 7 days\".")
    }
}

#Preview("DeltaLabel", traits: .sizeThatFitsLayout) {
    DarkPreview {
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

#Preview("DeltaLabel · reference in the change's colour", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 10) {
            let up = MetricDelta(current: 84, reference: 73), down = MetricDelta(current: 66, reference: 73)
            DeltaLabel(spec: .readiness, delta: up, reference: String(localized: "vs 7 d"), font: .ryft(.label),
                       referenceColor: DeltaLabel.color(up, spec: .readiness))
            DeltaLabel(spec: .readiness, delta: down, reference: String(localized: "vs 7 d"), font: .ryft(.label),
                       referenceColor: DeltaLabel.color(down, spec: .readiness))
        }
    }
}

#Preview("DeltaLabel · up, down, flat, none", traits: .sizeThatFitsLayout) {
    DarkPreview {
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

#Preview("DeltaLabel · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 10) {
            DeltaLabel(spec: .readiness, delta: MetricDelta(current: 80, reference: 79.6), reference: String(localized: "vs 7 d"))
            ChartHeader(spec: .readiness, value: 80, delta: MetricDelta(current: 80, reference: 79.6))
            ChartHeader(spec: .readiness, value: 80, delta: nil)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
