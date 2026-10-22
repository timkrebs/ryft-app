import SwiftUI

/// Today's three tiles: label, value, icon. Tappable when `action` is set.
struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    var tint: Color = Theme.accent
    /// A word under the icon, already localized: the recovery band, "calibrating", or the day a
    /// dimmed value is from.
    var caption: String? = nil
    /// Not today's value (ui.md §1.1): the value in tertiary ink, the icon at half strength,
    /// `caption` carries the day, and VoiceOver says it isn't today's score.
    var isDimmed = false
    var accessibilityHint: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 10) {
                Text(title)
                    .ryftLabelStyle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.ryft(.metric))
                    .monospacedDigit()
                    .foregroundStyle(isDimmed ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // A new score rolls its digits instead of jumping (off under Reduce Motion).
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(Theme.Motion.respecting(reduceMotion), value: value)
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
                    .opacity(isDimmed ? 0.5 : 1)
                    .frame(height: 22) // symbols differ in height; keep tiles aligned
                if let caption {
                    // A date or "calibrating" wraps rather than truncates.
                    Text(caption)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // a row of tiles shares one height
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
            // The score landed: the values un-dim with the digit roll (instant under Reduce Motion).
            .animation(Theme.Motion.respecting(reduceMotion), value: isDimmed)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(action == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(spokenValue)
        .accessibilityHint(accessibilityHint.map { Text($0) } ?? Text(""))
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }

    /// "7h 10m, Yesterday, not today's score" while dimmed; "75 %, High" otherwise.
    private var spokenValue: Text {
        if value == Fmt.placeholder { return Text("No data") }
        guard let caption else { return Text(value) }
        if isDimmed { return Text("\(value), \(caption), not today's score") }
        return Text(verbatim: "\(value), \(caption)")
    }
}

#Preview("MetricTile", traits: .sizeThatFitsLayout) {
    SchemePair {
        HStack(spacing: 10) {
            MetricTile(title: "Sleep", value: "7h 48m", systemImage: "moon.fill", action: {})
            MetricTile(title: "Recovery", value: "82%", systemImage: "heart", caption: String(localized: "High"), action: {})
            MetricTile(title: "Strain", value: Fmt.placeholder, systemImage: "bolt.fill", action: {})
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("MetricTile · states", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 10) {
            // Dimmed: an earlier day's values, dated (row C, row D from an earlier day).
            HStack(spacing: 10) {
                MetricTile(title: "Sleep", value: "7h 10m", systemImage: "moon.fill", tint: Theme.metricSleep,
                           caption: String(localized: "Yesterday"), isDimmed: true, action: {})
                MetricTile(title: "Recovery", value: "75%", systemImage: "heart", tint: Theme.band(forScore: 75),
                           caption: String(localized: "Yesterday"), isDimmed: true, action: {})
                MetricTile(title: "Strain", value: "0.9", systemImage: "bolt.fill", tint: Theme.metricStrain,
                           caption: String(localized: "Yesterday"), isDimmed: true, action: {})
            }
            .fixedSize(horizontal: false, vertical: true)
            // Calibrating (row B).
            HStack(spacing: 10) {
                MetricTile(title: "Sleep", value: "7h 11m", systemImage: "moon.fill", tint: Theme.metricSleep,
                           caption: String(localized: "today.tile.calibrating", defaultValue: "calibrating"), action: {})
                MetricTile(title: "Recovery", value: "75%", systemImage: "heart", tint: Theme.band(forScore: 75),
                           caption: String(localized: "today.tile.calibrating", defaultValue: "calibrating"), action: {})
                MetricTile(title: "Strain", value: "0.9", systemImage: "bolt.fill", tint: Theme.metricStrain,
                           caption: String(localized: "today.tile.calibrating", defaultValue: "calibrating"), action: {})
            }
            .fixedSize(horizontal: false, vertical: true)
            // Normal (row A).
            HStack(spacing: 10) {
                MetricTile(title: "Sleep", value: "7h 48m", systemImage: "moon.fill", tint: Theme.metricSleep, action: {})
                MetricTile(title: "Recovery", value: "82%", systemImage: "heart", tint: Theme.band(forScore: 82),
                           caption: String(localized: "High"), action: {})
                MetricTile(title: "Strain", value: "12.4", systemImage: "bolt.fill", tint: Theme.metricStrain, action: {})
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("MetricTile · states · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 10) {
            MetricTile(title: "Sleep", value: "7h 10m", systemImage: "moon.fill", tint: Theme.metricSleep,
                       caption: Fmt.dayTitle(.now.addingTimeInterval(-3 * 86_400)), isDimmed: true, action: {})
            MetricTile(title: "Recovery", value: "75%", systemImage: "heart", tint: Theme.band(forScore: 75),
                       caption: String(localized: "today.tile.calibrating", defaultValue: "calibrating"), action: {})
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}
