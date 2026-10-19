import SwiftUI

/// Today's three tiles: label, value, icon. Tappable when `action` is set.
struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    var tint: Color = Theme.accent
    /// A word under the icon, e.g. the recovery band (already localized).
    var caption: String? = nil
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
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // A new score rolls its digits instead of jumping (off under Reduce Motion).
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(Theme.Motion.respecting(reduceMotion), value: value)
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(height: 22) // symbols differ in height; keep tiles aligned
                if let caption {
                    Text(caption)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // a row of tiles shares one height
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(action == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(value == Fmt.placeholder ? Text("No data") : caption.map { Text(verbatim: "\(value), \($0)") } ?? Text(value))
        .accessibilityHint(accessibilityHint.map { Text($0) } ?? Text(""))
        .accessibilityAddTraits(action == nil ? [] : .isButton)
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
