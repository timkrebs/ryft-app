// The Insights tile (docs/work/2026-11-16-nocturne/design.md §P5-5.1 row 3, D5-6, D5-7; build plan F4): the first visible `info`
// insight in the recovery glow (`GlowTile(kind: .idea)`: 120 high at least, radius 28, padding 16 / 18, flat above 420 pt). Row 1:
// the Volt hint dot, 8, "Insight" (13, full ink: the recovery tile sets its labels at 100 %), the dismiss × trailing; 10 below the
// title in 17 Light with a 1.4 line height, growing with Dynamic Type like `.headline`; 8 below the body (13, full ink); last the
// link, when the insight has a route. The tile is never a notice's or a warning's: teal is not the colour of attention.
import SwiftUI

struct InsightTile: View {
    let insight: Insight
    var onDismiss: (() -> Void)?
    var onOpen: (() -> Void)?
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?

    /// The title's 17 Light grows like `.headline` (as the catalog's idea tile).
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = InsightsLayout.tileTitleSize

    var body: some View {
        GlowTile(Theme.recovery, kind: .idea, reduceTransparency: reduceTransparency) {
            InsightRows(insight: insight, wordColor: Theme.textPrimary,
                        titleFont: .ryftNumber(size: titleSize, weight: .light),
                        titleLineSpacing: InsightsLayout.tileTitleLineSpacing(size: titleSize),
                        bodyFont: .ryft(.label), bodyColor: Theme.textPrimary, onDismiss: onDismiss, onOpen: onOpen,
                        identifier: "insights.tile") {
                Circle()
                    .fill(Theme.signal)
                    .frame(width: InsightsLayout.dot, height: InsightsLayout.dot)
            }
        }
    }
}

// MARK: previews (dark only)

private struct InsightTilePreviews: View {
    private static let best = MockData.insights.first { $0.severity == .info }
        ?? Insight(id: "hrv-best-30d", severity: .info, title: "Best HRV in 30 days", body: "", metric: "hrv")
    private static let long = Insight(
        id: "readiness-up", severity: .info, title: "Readiness up three mornings in a row",
        body: "Your readiness has been above its 30-day range since Sunday, after three nights of more than 7 hours asleep. "
            + "Resting heart rate is back at its baseline.", metric: "readiness")

    var body: some View {
        VStack(spacing: InsightsLayout.cardGap) {
            InsightTile(insight: Self.best, onDismiss: {}, onOpen: {})
            InsightTile(insight: Self.long, onDismiss: {}, onOpen: {})
            // No route: no link. Reduce Transparency: flat `surface` and the 2 pt teal border.
            InsightTile(insight: Self.best, onDismiss: {}, reduceTransparency: true)
        }
    }
}

#Preview("InsightTile", traits: .sizeThatFitsLayout) {
    DarkPreview { InsightTilePreviews() }
}

#Preview("InsightTile · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { InsightTilePreviews() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
