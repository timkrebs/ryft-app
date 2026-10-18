import SwiftUI

/// Rounded Slate surface used for every grouped block.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Metrics.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
    }
}

/// Card title row: "Trends" … "7 days ›".
struct CardHeader: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey? = nil
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let trailing {
                HStack(spacing: 4) {
                    Text(trailing)
                    if showsChevron { Image(systemName: "chevron.right").imageScale(.small) }
                }
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// A label/value row inside a card ("Bedtime  23:05").
struct StatRow: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String? = nil
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.ryft(.body))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                if let detail {
                    Text(detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Subtle press feedback for tappable cards and tiles.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview("Card", traits: .sizeThatFitsLayout) {
    SchemePair {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Trends", trailing: "7 days", showsChevron: true)
                StatRow(title: "Bedtime", value: "22:50")
                StatRow(title: "Sleep debt", value: "25m", detail: "Need 8h 06m", valueColor: Theme.warning)
            }
        }
    }
}
