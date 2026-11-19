import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Insights' measurements (docs/work/2026-11-16-nocturne/design.md §P5-12 test 2; §P5-5.1, §P5-5.2): the board's numbers as
/// values, the gaps between the page's blocks, and the hosted card and tile at 390.
@MainActor
@Suite("T5.3: Insights layout")
struct InsightsLayoutTests {
    typealias L = InsightsLayout

    @Test("Spec 2: header 40, header → first block 22, tile → cards 12, cards 12 apart")
    func pageGaps() {
        #expect(L.header == 40 && L.header == ScreenHeaderSpec.height)
        #expect(L.headerToFirstBlock == 22)
        #expect(L.tileToCards == 12 && L.cardGap == 12)
        #expect(L.sectionGap == 24 && L.tileToTrends == 12)
    }

    @Test("Spec 2: the tile is the idea glow kind: min 120, radius 28, padding 16 / 18")
    func tile() {
        let shape = GlowTileSpec.shape(for: .idea)
        #expect(L.tileMinHeight == 120 && shape.minHeight == L.tileMinHeight)
        #expect(L.tileRadius == 28 && shape.radius == L.tileRadius)
        #expect(L.tilePadding == EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        #expect(GlowTileSpec.padding(for: .idea) == L.tilePadding)
        #expect(L.dot == 6 && L.dotGap == 8 && L.rowToTitle == 10 && L.titleToBody == 8)
        #expect(L.tileTitleSize == 17 && L.tileTitleLineHeight == 1.4)
        #expect(L.dismissGlyph == 14 && L.dismissTarget == Theme.Metrics.minHitTarget && L.dismissReach == 15)
    }

    @Test("Spec 2: the title's lines are 1.4 × its size apart, at any size")
    func tileTitleLineHeight() {
        for size: CGFloat in [17, 24, 40] {
            let font = UIFont(name: RyftFonts.postScriptName(for: .light), size: size) ?? .systemFont(ofSize: size, weight: .light)
            let spacing = L.tileTitleLineSpacing(size: size)
            #expect(spacing >= 0)
            #expect(abs(font.lineHeight + spacing - 1.4 * size) < 0.01 || (spacing == 0 && font.lineHeight >= 1.4 * size),
                    "\(size): \(font.lineHeight) + \(spacing)")
        }
    }

    @Test("Spec 2: a trend card is min 132, radius 24, 12 apart, padding 14 / 16; head → value 2, value → chart 6")
    func trendCard() {
        #expect(L.trendCardMinHeight == 132 && L.trendCardRadius == 24 && L.trendCardGap == 12)
        #expect(L.trendCardPadding == EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        #expect(L.headToValue == 2 && L.valueToChart == 6)
        #expect(L.insightCardRadius == 24 && L.insightCardPadding == L.tilePadding)
    }

    @Test("Spec 2: the chart is 318 × 48 at 390 (350 − 32); the band is 6 % behind ink, 12 % behind a metric colour")
    func chartAndBand() {
        #expect(L.chartWidth(contentWidth: 350) == 318)
        #expect(L.chartHeight == 48 && TrendLine.height == L.chartHeight)
        #expect(L.inkBandOpacity == 0.06 && L.metricBandOpacity == 0.12)
        #expect(TrendCardStyle(.readiness).bandOpacity == 0.06 && TrendCardStyle(.rhr).bandOpacity == 0.06)
        #expect(TrendCardStyle(.hrv).bandOpacity == 0.12 && TrendCardStyle(.sleepMin).bandOpacity == 0.12)
    }

    @Test("Spec 2: the gaps between blocks: 22 under the header, 12 between insights, 12 from a lone tile to the trends, else 24")
    func blockGaps() {
        typealias B = InsightsLayout.Block
        #expect(L.gap(above: .tile, below: .header) == 22)
        #expect(L.gap(above: .attention, below: .header) == 22)
        #expect(L.gap(above: .issue, below: .header) == 12)
        #expect(L.gap(above: .attention, below: .issue) == 12)
        #expect(L.gap(above: .tile, below: .attention) == 12)
        #expect(L.gap(above: .more, below: .tile) == 12)
        #expect(L.gap(above: .trends, below: .tile, tileOnly: true) == 12)
        #expect(L.gap(above: .trends, below: .tile, tileOnly: false) == 24)
        #expect(L.gap(above: .behaviors, below: .more) == 24)
        #expect(L.gap(above: .trends, below: .behaviors) == 24)
        #expect(L.gap(above: .trends, below: .empty) == 24)
        #expect(L.gap(above: .moreTrends, below: .trends) == 24)
        #expect(L.gap(above: .trends, below: .issue) == 24)
    }

    @Test("The page's blocks: the board's order, a lone tile, the empty card, not set up")
    func blocks() {
        let scored = InsightsPreview.content()
        #expect(scored.blocks == [.attention, .tile, .trends, .moreTrends])
        #expect(!scored.tileOnly)
        let tile = InsightsPreview.content(insights: InsightsPreview.onlyTile)
        #expect(tile.blocks == [.tile, .trends, .moreTrends] && tile.tileOnly)
        #expect(InsightsPreview.content(insights: []).blocks == [.empty, .trends, .moreTrends])
        #expect(InsightsPreview.content(issue: InsightsPreview.unreachable).blocks.first == .issue)
        // Offline: the status line in the card's place (S4, T5.7).
        #expect(InsightsPreview.content(offline: true).blocks.first == .issue)
        #expect(InsightsPreview.content(hasDataSource: false).blocks.isEmpty)
    }

    // MARK: hosted, at 390

    @Test("Hosted: the card's summary is the inner width (318) and the card at least 132; the × is 44 and its glyph on the padding")
    func hostedCardAndTile() async throws {
        let page = InsightsPage(content: InsightsPreview.content(insights: InsightsPreview.onlyTile), range: .constant(.month))
        try await HostedWindow.run(width: 390, height: 844, page) { w in
            try await w.settle()
            let readiness = try #require(w.nodes().first { $0.identifier == "insights.trend.readiness" })
            #expect(abs(readiness.frame.width - 318) < 0.5, "\(readiness.frame)")
            #expect(readiness.frame.minX == 36)
            #expect(readiness.frame.height + L.trendCardPadding.top + L.trendCardPadding.bottom >= L.trendCardMinHeight - 0.5)
            let dismiss = try #require(w.nodes().first { $0.identifier == "insights.tile.dismiss" })
            #expect(abs(dismiss.frame.width - 44) < 0.01 && abs(dismiss.frame.height - 44) < 0.01, "\(dismiss.frame)")
            // The glyph's trailing edge on the tile's padding: 390 − 20 − 18, the target 15 past it.
            #expect(abs(dismiss.frame.maxX - (390 - 20 - 18 + 15)) < 0.5, "\(dismiss.frame)")
        }
    }
}
