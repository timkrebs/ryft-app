// Insights' measurements in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-5.1, §P5-5.2; the lead's board measurements):
// every gap is from the bottom of one element to the top of the next, so the page is one `VStack(spacing: 0)` with these
// between its rows. Plain values, so the layout tests assert numbers, not pixels.
import CoreGraphics
import SwiftUI
import UIKit

enum InsightsLayout {
    // MARK: the page, top to bottom (§P5-5.1)

    /// Row 1: the header with the range control (`ScreenHeaderSpec.height`).
    nonisolated static let header: CGFloat = 40
    /// The header to the first block (an attention card, the tile, the empty card, the trend cards).
    nonisolated static let headerToFirstBlock: CGFloat = 22
    /// The header to the offline card, and the offline card to the block under it.
    nonisolated static let headerToIssue: CGFloat = 12, issueToBlock: CGFloat = 12
    /// Between two insight cards, and from the attention cards to the tile, and from the tile to the other insights.
    nonisolated static let cardGap: CGFloat = 12
    /// The tile, or the cards above it, to the cards under it: the board's 12.
    nonisolated static let tileToCards: CGFloat = 12
    /// To the Behaviors section, to the trend cards, to "More trends" and to the footer: a section's 24.
    nonisolated static let sectionGap: CGFloat = 24
    /// The trend cards straight under the tile, with no other insight and no Behaviors section (the board's 12).
    nonisolated static let tileToTrends: CGFloat = 12
    /// "More trends" to its first card.
    nonisolated static let labelToCards: CGFloat = 10

    // MARK: the insight tile (§P5-5.1 row 3; `GlowTile(kind: .idea)` carries the radius, the padding and the minimum height)

    nonisolated static let tileMinHeight: CGFloat = 120
    nonisolated static let tileRadius: CGFloat = 28
    static let tilePadding = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    /// The Volt hint dot (and an insight card's severity dot), and the gap to the word beside it.
    nonisolated static let dot: CGFloat = 6, dotGap: CGFloat = 8
    /// The word's row to the title, the title to the body.
    nonisolated static let rowToTitle: CGFloat = 10, titleToBody: CGFloat = 8
    /// The insight's title in the tile: 17 Light (it grows with Dynamic Type like `.headline`), line height 1.4.
    nonisolated static let tileTitleSize: CGFloat = 17, tileTitleLineHeight: CGFloat = 1.4

    // MARK: an insight card (rows 2 and 4)

    nonisolated static let insightCardRadius: CGFloat = 24
    static let insightCardPadding = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    /// A hollow (info) dot's ring.
    nonisolated static let hollowDotLine: CGFloat = 1

    // MARK: the dismiss × and the link (tile and cards)

    /// The × is a 14 pt glyph in a 44 pt target; the target reaches past the glyph, so the word's row keeps its height.
    nonisolated static let dismissGlyph: CGFloat = 14, dismissTarget: CGFloat = 44
    nonisolated static var dismissReach: CGFloat { (dismissTarget - dismissGlyph) / 2 }
    /// The link (`ryftLink()`, 44 high) reaches this far under the text box at the default sizes, so its words sit at the
    /// tile's bottom padding, not 12 above it. From AX1 its text is as tall as its target: no reach.
    nonisolated static let linkReach: CGFloat = 12

    static func linkReach(_ typeSize: DynamicTypeSize) -> CGFloat {
        typeSize.isAccessibilitySize ? 0 : linkReach
    }

    // MARK: a trend card (§P5-5.2)

    nonisolated static let trendCardMinHeight: CGFloat = 132, trendCardRadius: CGFloat = 24, trendCardGap: CGFloat = 12
    static let trendCardPadding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    /// The head row (name, note, chevron) to the value row, the value row to the chart.
    nonisolated static let headToValue: CGFloat = 2, valueToChart: CGFloat = 6
    /// The value to its unit, the value to the delta.
    nonisolated static let unitGap: CGFloat = 3, deltaGap: CGFloat = 8
    /// The chart: the card's inner width at 390 (350 − 2 × 16), 48 high (`TrendLine.height`).
    nonisolated static let chartHeight: CGFloat = 48
    /// The chevron: 12 pt.
    nonisolated static let chevron: CGFloat = 12
    /// The note to the chevron, and the name to the note.
    nonisolated static let chevronGap: CGFloat = 6, noteGap: CGFloat = 8
    /// The usual range behind the line: `textPrimary` at 6 % (readiness, resting HR), a metric colour at 12 %.
    nonisolated static let inkBandOpacity = 0.06, metricBandOpacity = 0.12
    /// Expanded: the summary to the detailed chart (`TrendChart`, 150 high), the chart to Avg · Min · Max.
    nonisolated static let summaryToDetail: CGFloat = 14, detailChartHeight: CGFloat = 150, chartToStats: CGFloat = 12
    nonisolated static let statsGap: CGFloat = 16

    /// The chart's width in a content column `width` wide: 318 at 390 (350 − 32).
    static func chartWidth(contentWidth width: CGFloat) -> CGFloat {
        width - trendCardPadding.leading - trendCardPadding.trailing
    }

    // MARK: derived

    /// The space between two lines of the tile's title so a line is 1.4 × its size: the font's own line height comes off.
    static func tileTitleLineSpacing(size: CGFloat) -> CGFloat {
        let name = RyftFonts.postScriptName(for: .light)
        let font = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .light)
        return max(0, tileTitleLineHeight * size - font.lineHeight)
    }

    /// The page's blocks, in order, for the gaps between them.
    enum Block: Hashable, Sendable {
        case header, issue, attention, tile, empty, more, behaviors, trends, moreTrends, footer
    }

    /// The gap above `next` when `previous` is above it. `tileOnly`: the tile is the page's only insight block and Behaviors
    /// is not there, so the board's 12 holds between the tile and the trend cards.
    static func gap(above next: Block, below previous: Block, tileOnly: Bool = false) -> CGFloat {
        switch (previous, next) {
        case (.header, .issue): return headerToIssue
        case (.header, _): return headerToFirstBlock
        case (.issue, .trends), (.issue, .behaviors), (.issue, .footer): return sectionGap
        case (.issue, _): return issueToBlock
        case (_, .attention), (_, .more): return cardGap
        case (.attention, .tile), (.attention, .empty): return tileToCards
        case (.tile, .trends): return tileOnly ? tileToTrends : sectionGap
        default: return sectionGap
        }
    }
}
