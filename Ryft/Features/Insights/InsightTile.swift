// The Insights tile (docs/work/2026-11-16-nocturne/design.md §P5-5.1 row 3, D5-6, D5-7; build plan F4): the first visible `info`
// insight in its metric's glow (`GlowTile(kind: .idea)`: 120 high at least, radius 28, padding 16 / 18, flat above 420 pt). Row 1:
// the Volt hint dot, 8, "Insight" (13, full ink), the dismiss × trailing; 10 below the title in 17 Light with a 1.4 line height,
// growing with Dynamic Type like `.headline`; 8 below the body (13, full ink); last the link, when the insight has a route. The
// tile is never a notice's or a warning's: a legend colour is not the colour of attention.
//
// The glow's colour (the Nocturne gate's D1, docs/work/2026-11-20-nocturne-gate/design.md §2.1): the insight's metric's legend
// colour, as the trend cards draw it (recovery teal, sleep violet, strain blue); an insight whose metric has none (resting HR,
// steps, energy, no known metric) is the flat neutral tile: `surface`, the same radius, padding and height, a 1.5 pt ring in
// `textPrimary` at 16 %. Teal is recovery only (L27).
import SwiftUI

struct InsightTile: View {
    let insight: Insight
    var onDismiss: (() -> Void)?
    var onOpen: (() -> Void)?
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?

    /// The title's 17 Light grows like `.headline` (as the catalog's idea tile).
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = InsightsLayout.tileTitleSize

    /// The glow's legend colour for `insight`'s metric (`TrendCardStyle`'s legend: readiness, recovery and HRV teal; the sleep
    /// metrics violet; strain and training blue); nil: the flat neutral tile (resting HR, steps, energy, or no known metric).
    static func tint(for insight: Insight) -> Color? {
        guard let metric = insight.trendMetric else { return nil }
        switch metric {
        case .readiness, .recovery, .hrv: return Theme.recovery
        case .sleep, .sleepMin, .sleepQuality, .sleepConsistency, .napMin: return Theme.metricSleep
        case .strain, .strengthMin, .volumeKg: return Theme.metricStrain
        case .rhr, .steps, .activeKcal: return nil
        }
    }

    var body: some View {
        if let tint = Self.tint(for: insight) {
            GlowTile(tint, kind: .idea, reduceTransparency: reduceTransparency) { rows }
        } else {
            NeutralInsightTile { rows }
        }
    }

    private var rows: some View {
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

/// The insight tile for a metric without a legend colour: the idea tile's frame (`GlowTileSpec` `.idea`: radius 28, padding
/// 16 / 18, at least 120 high) drawn flat in `surface` with a 1.5 pt ring in `textPrimary` at 16 % (`controlOutline`, the
/// `IconDisc` ring's ink) in place of the glow's colour. It looks the same whatever Reduce Transparency says.
private struct NeutralInsightTile<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GlowTileSpec.shape(for: .idea).radius, style: .continuous)
        content
            .foregroundStyle(Theme.textPrimary)
            .padding(GlowTileSpec.padding(for: .idea))
            .frame(maxWidth: .infinity, minHeight: GlowTileSpec.ideaMinHeight, alignment: .topLeading)
            .background {
                shape.fill(Theme.surface)
                    .overlay {
                        shape.strokeBorder(Theme.textPrimary.opacity(IconDisc.ringOpacity), lineWidth: Theme.Metrics.controlOutline)
                    }
            }
            .clipShape(shape)
            .accessibilityElement(children: .contain)
    }
}

// MARK: previews (dark only)

private struct InsightTilePreviews: View {
    private static let best = MockData.insights.first { $0.severity == .info }
        ?? Insight(id: "hrv-best-30d", severity: .info, title: "Best HRV in 30 days", body: "", metric: "hrv")
    private static let long = Insight(
        id: "readiness-up", severity: .info, title: "Readiness up three mornings in a row",
        body: "Your readiness has been above its usual range since Sunday, after three nights of more than 7 hours asleep. "
            + "Resting heart rate is back at its baseline.", metric: "readiness")
    private static let naps = Insight(id: "naps-paying-off", severity: .info, title: "Naps are paying off",
                                      body: "On days with a nap, your sleep performance was 6 points higher.", metric: "nap_min")
    private static let record = Insight(id: "pr", severity: .info, title: "New personal record",
                                        body: "Back squat: 100 kg for 5, your best set yet.", metric: "volume_kg")
    private static let steps = Insight(id: "steps-up", severity: .info, title: "More steps this week",
                                       body: "You averaged 9,400 steps a day, 1,200 more than last week.", metric: "steps")

    var body: some View {
        VStack(spacing: InsightsLayout.cardGap) {
            InsightTile(insight: Self.best, onDismiss: {}, onOpen: {})
            InsightTile(insight: Self.long, onDismiss: {}, onOpen: {})
            // Sleep violet, strain blue, and the flat neutral tile for a metric without a legend colour.
            InsightTile(insight: Self.naps, onDismiss: {}, onOpen: {})
            InsightTile(insight: Self.record, onDismiss: {}, onOpen: {})
            InsightTile(insight: Self.steps, onDismiss: {}, onOpen: {})
            // No route: no link. Reduce Transparency: flat `surface` and the 2 pt border in the metric's colour.
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
