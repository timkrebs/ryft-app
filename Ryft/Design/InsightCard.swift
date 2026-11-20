// An insight from `/v1/insights` in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-5.1, D5-6): a `surface` card, radius 24,
// with a 6 pt severity dot and the severity's word, the dismiss ×, the title, the body and the link to what it is about. No coloured
// stripe and no kind glyph: the colour is on the dot only (amber for a notice, coral for "Attention", a hollow ring for an
// insight), and the dot's shape and the word say it too. The Insights tile (`InsightTile`) is the same rows in the recovery glow.
import SwiftUI

extension Insight {
    /// The severity as a word: "Insight", "Notice", "Attention". VoiceOver starts the card with it.
    var severityWord: String {
        switch severity {
        case .info: return String(localized: "Insight")
        case .notice: return String(localized: "Notice")
        case .warn: return String(localized: "Attention")
        }
    }

    /// The link under the body, for an insight with a route: Insights' Habits, the session (a record), or its trend.
    var linkTitle: String {
        switch kind {
        case .behaviorImpact: return String(localized: "See habits", comment: "An insight about a habit's effect: the link to Insights' Habits section.")
        case .pr: return String(localized: "See the session")
        default: return String(localized: "Show the chart")
        }
    }
}

/// An insight card's rows (§P5-5.1 rows 2–4), shared by the card and the tile: the dot and the word with the dismiss × on
/// one line, 10 below the title, 8 below the body, then the link. VoiceOver reads "Attention: <title>" with the body as its
/// value, then the link, then the dismiss button.
struct InsightRows<Dot: View>: View {
    let insight: Insight
    let wordColor: Color
    let titleFont: Font
    var titleLineSpacing: CGFloat = 0
    let bodyFont: Font
    let bodyColor: Color
    var onDismiss: (() -> Void)?
    var onOpen: (() -> Void)?
    /// "insights.tile", "insights.card.<id>": the dismiss button and the link add ".dismiss" and ".link".
    let identifier: String
    @ViewBuilder let dot: () -> Dot

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: InsightsLayout.dotGap) {
                dot()
                    .accessibilityHidden(true)
                Text(insight.severityWord)
                    .font(.ryft(.label))
                    .foregroundStyle(wordColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                Spacer(minLength: InsightsLayout.dotGap)
                if let onDismiss {
                    InsightDismissButton(identifier: "\(identifier).dismiss", action: onDismiss)
                        .accessibilitySortPriority(1)
                }
            }
            VStack(alignment: .leading, spacing: InsightsLayout.titleToBody) {
                Text(insight.title)
                    .font(titleFont)
                    .lineSpacing(titleLineSpacing)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.body)
                    .font(bodyFont)
                    .foregroundStyle(bodyColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, InsightsLayout.rowToTitle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(insight.severityWord): \(insight.title)"))
            .accessibilityValue(Text(insight.body))
            .accessibilitySortPriority(3)
            if let onOpen {
                Button(action: onOpen) { Text(insight.linkTitle) }
                    .ryftLink()
                    .accessibilityIdentifier("\(identifier).link")
                    .accessibilitySortPriority(2)
                    // The 44 pt target reaches under the text box into the bottom padding (below AX1).
                    .padding(.bottom, -InsightsLayout.linkReach(typeSize))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// The 14 pt × in its 44 pt target, `textPrimary`. Laid out as the glyph: the target reaches 15 past it on every side, so
/// the word's row keeps its height and the glyph's edge is on the padding.
struct InsightDismissButton: View {
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: InsightsLayout.dismissGlyph, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: InsightsLayout.dismissTarget, height: InsightsLayout.dismissTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-InsightsLayout.dismissReach)
        .accessibilityLabel(Text("Dismiss for today"))
        .accessibilityIdentifier(identifier)
    }
}

/// The severity dot: filled `warning` for a notice, `alert` for "Attention", a hollow `textTertiary` ring for an insight.
struct InsightSeverityDot: View {
    let severity: InsightSeverity

    var body: some View {
        Group {
            switch severity {
            case .info:
                Circle().strokeBorder(Theme.textTertiary, lineWidth: InsightsLayout.hollowDotLine)
            case .notice:
                Circle().fill(Theme.warning)
            case .warn:
                Circle().fill(Theme.alert)
            }
        }
        .frame(width: InsightsLayout.dot, height: InsightsLayout.dot)
    }
}

/// A neutral insight card (§P5-5.1 rows 2 and 4): `surface`, radius 24, padding 16 / 18; the word in `textSecondary`, the title
/// `.headline` (17 Medium), the body `.callout` in `textSecondary`, the link `ryftLink()`.
struct InsightCard: View {
    let insight: Insight
    var onDismiss: (() -> Void)?
    /// "Show the chart": the trend behind the card (or the Behaviors section, or the session).
    var onOpen: (() -> Void)?

    var body: some View {
        InsightRows(insight: insight, wordColor: Theme.textSecondary, titleFont: .ryft(.headline), bodyFont: .ryft(.callout),
                    bodyColor: Theme.textSecondary, onDismiss: onDismiss, onOpen: onOpen,
                    identifier: "insights.card.\(insight.id)") {
            InsightSeverityDot(severity: insight.severity)
        }
        .padding(InsightsLayout.insightCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: InsightsLayout.insightCardRadius, style: .continuous))
    }
}

// MARK: previews (dark only)

private struct InsightCardPreviews: View {
    var body: some View {
        VStack(spacing: InsightsLayout.cardGap) {
            ForEach(MockData.insights) { insight in
                InsightCard(insight: insight, onDismiss: {}, onOpen: insight.severity == .notice ? nil : {})
            }
        }
    }
}

#Preview("InsightCard", traits: .sizeThatFitsLayout) {
    DarkPreview { InsightCardPreviews() }
}

#Preview("InsightCard · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { InsightCardPreviews() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
