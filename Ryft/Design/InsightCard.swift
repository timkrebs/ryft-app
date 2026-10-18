import SwiftUI

/// An insight from `/v1/insights`, coloured by severity, optionally dismissible.
struct InsightCard: View {
    let insight: Insight
    var onDismiss: (() -> Void)? = nil

    private var color: Color { Theme.color(for: insight.severity) }

    private var severityTitle: String {
        switch insight.severity {
        case .info: return String(localized: "Insight")
        case .notice: return String(localized: "Notice")
        case .warn: return String(localized: "Attention")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Capsule()
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(severityTitle).ryftLabelStyle(color)
                    Spacer()
                    if let onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Dismiss for today"))
                    }
                }
                Text(insight.title)
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.body)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview("InsightCard", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            ForEach(MockData.insights) { InsightCard(insight: $0, onDismiss: {}) }
        }
    }
}
