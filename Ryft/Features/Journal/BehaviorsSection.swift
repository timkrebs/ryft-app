import SwiftUI

/// How the impact section words its numbers (API.md → `GET /v1/behaviors/impact`).
enum ImpactFormat {
    /// Points, signed: one decimal only when |delta| < 10 ("−14", "+4.6").
    static func points(_ delta: Double) -> String {
        let magnitude = abs(delta)
        let digits = magnitude < 10 ? 1 : 0
        let text = magnitude.formatted(.number.precision(.fractionLength(digits)))
        if text == 0.0.formatted(.number.precision(.fractionLength(digits))) { return text }
        return (delta < 0 ? "−" : "+") + text
    }

    /// "Alcohol · −14 recovery".
    static func headline(_ impact: BehaviorImpact) -> String {
        guard let r = impact.recovery else { return impact.name }
        return String(localized: "\(impact.name) · \(points(r.delta)) recovery")
    }

    /// "n = 12/31": days with / without it.
    static func n(_ effect: BehaviorEffect) -> String { "n = \(effect.nYes)/\(effect.nNo)" }

    /// "3 more days with it to unlock", "2 more days without it", or both.
    static func locked(_ needed: ImpactNeeded) -> String {
        switch (needed.yes, needed.no) {
        case (let y, 0) where y > 0: return String(localized: "\(y) more days with it to unlock")
        case (0, let n) where n > 0: return String(localized: "\(n) more days without it to unlock")
        case (let y, let n): return String(localized: "\(y) more days with it and \(n) without to unlock")
        }
    }

    /// "Last 90 days · computed 06:45".
    static func footer(_ impacts: BehaviorImpacts) -> String {
        String(localized: "Last \(impacts.windowDays) days · computed \(Fmt.time(impacts.computedAt))")
    }
}

/// The 90 % interval as a thin bar on an axis centred on 0, with the delta as a dot.
struct ImpactIntervalBar: View {
    let effect: BehaviorEffect
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let span = max(abs(effect.ciLo), abs(effect.ciHi), abs(effect.delta), 1) * 1.15
            let w = geo.size.width
            let x: (Double) -> CGFloat = { w / 2 + CGFloat($0 / span) * (w / 2) }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.separator).frame(height: 2).frame(maxHeight: .infinity)
                Rectangle().fill(Theme.textTertiary).frame(width: 1, height: 12).position(x: w / 2, y: 6)
                Capsule().fill(color.opacity(0.35))
                    .frame(width: max(2, x(effect.ciHi) - x(effect.ciLo)), height: 4)
                    .position(x: (x(effect.ciLo) + x(effect.ciHi)) / 2, y: 6)
                Circle().fill(color).frame(width: 7, height: 7).position(x: x(effect.delta), y: 6)
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

/// Insights → Behaviors: unlocked effects first, then the ones still locked, in
/// the platform's order (never re-sorted here).
struct BehaviorsSection: View {
    let impacts: BehaviorImpacts
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Behaviors").ryftLabelStyle()
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(impacts.impacts) { impact in
                        if impact.status == .unlocked {
                            unlocked(impact)
                        } else {
                            locked(impact)
                        }
                        if impact.id != impacts.impacts.last?.id { Divider().overlay(Theme.separator) }
                    }
                    if impacts.impacts.isEmpty {
                        Text("Log a few days in the journal to see how your habits change the morning after.")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(ImpactFormat.footer(impacts))
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    /// Significant: coloured by direction × polarity (CHART_STYLE → Readouts), so a
    /// drop in recovery is never teal. Otherwise muted.
    static func color(_ effect: BehaviorEffect, spec: MetricSpec) -> Color {
        guard effect.significant else { return Theme.textTertiary }
        switch spec.polarity {
        case .higherIsBetter: return effect.delta >= 0 ? Theme.accent : Theme.alert
        case .lowerIsBetter: return effect.delta <= 0 ? Theme.accent : Theme.alert
        case .neutral: return Theme.textSecondary
        }
    }

    private func color(_ effect: BehaviorEffect, spec: MetricSpec) -> Color { Self.color(effect, spec: spec) }

    @ViewBuilder
    private func unlocked(_ impact: BehaviorImpact) -> some View {
        let isOpen = expanded.contains(impact.id)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Theme.Motion.quick) {
                    if isOpen { expanded.remove(impact.id) } else { expanded.insert(impact.id) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(impact.name)
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let r = impact.recovery {
                        Text(String(localized: "\(ImpactFormat.points(r.delta)) recovery"))
                            .font(.ryft(.headline).monospacedDigit())
                            .foregroundStyle(r.significant ? color(r, spec: .recovery) : Theme.textSecondary)
                    }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            if let r = impact.recovery {
                effectRow(r, spec: .recovery, unit: nil)
            }
            if isOpen {
                if let hrv = impact.hrvPct {
                    effectRow(hrv, spec: .hrv, unit: String(localized: "% HRV"))
                } else {
                    Text("HRV needs 5 nights with and 5 without it.")
                        .font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                }
                if let sleep = impact.sleepPerformance {
                    effectRow(sleep, spec: .sleepPerformance, unit: String(localized: "sleep performance"))
                } else {
                    Text("Sleep performance needs 5 nights with and 5 without it.")
                        .font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(ImpactFormat.headline(impact)))
    }

    /// `unit` nil: the headline already says the number (recovery).
    private func effectRow(_ effect: BehaviorEffect, spec: MetricSpec, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let unit {
                    Text(verbatim: "\(ImpactFormat.points(effect.delta)) \(unit)")
                        .font(.ryft(.caption).monospacedDigit())
                        .foregroundStyle(color(effect, spec: spec))
                } else {
                    Text("90 % interval")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text(ImpactFormat.n(effect))
                    .font(.ryft(.caption).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
            ImpactIntervalBar(effect: effect, color: color(effect, spec: spec))
        }
    }

    private func locked(_ impact: BehaviorImpact) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "lock")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            Text(impact.name)
                .font(.ryft(.body))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(ImpactFormat.locked(impact.needed))
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Behaviors", traits: .sizeThatFitsLayout) {
    SchemePair {
        BehaviorsSection(impacts: MockJournal.impacts)
    }
}
