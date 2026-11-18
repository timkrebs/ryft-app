import SwiftUI
import Testing
@testable import Ryft

/// Strain's board measurements (docs/work/2026-11-16-nocturne/design.md §P5-12 test 1), from `StrainLayout` and the parts it
/// is built from.
@MainActor
@Suite("Strain layout (§P5-12 test 1)")
struct StrainLayoutTests {
    @Test func headerStripAndHero() {
        #expect(StrainLayout.headerHeight == 40)
        #expect(StrainLayout.headerHeight == ScreenHeaderSpec.height)
        #expect(StrainLayout.stripGap == 12)
        #expect(StrainLayout.numeralGap == 22)
        #expect(StrainLayout.captionGap == 12)
        #expect(StrainLayout.splitGap == 4)
        #expect(StrainLayout.rulerGap == 14)
        #expect(StrainLayout.rulerHeight == RulerScale.Size.regular.height)
        #expect(StrainLayout.rulerToTile == 56, "the zones tile's top is the ruler's top + 56")
    }

    @Test func theZonesTile() {
        #expect(GlowTileSpec.zonesMinHeight == 176)
        #expect(GlowTileSpec.shape(for: .zones).radius == 28)
        #expect(GlowTileSpec.padding(for: .zones) == EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        #expect(StrainLayout.zonesHeadGap == 14)
        #expect(StrainLayout.footnoteGap == 8)
    }

    @Test func theTiles() {
        #expect(StrainLayout.tilesGap == 12)
        #expect(NeutralTile.height == 80)
        #expect(StrainLayout.tileSpacing == 12)
        #expect(NeutralTile.radius == 22)
        #expect(NeutralTile.padding == EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
    }

    @Test func sectionsAndRows() {
        #expect(StrainLayout.sectionGap == 24)
        #expect(StrainLayout.sectionGap == Theme.Metrics.sectionSpacing)
        #expect(StrainLayout.activitiesGap == 18)
        #expect(StrainLayout.listTitleGap == 10)
        #expect(StrainLayout.rowGap == 8)
        #expect(ActivityListRowSpec.minHeight == 60)
        #expect(ActivityListRowSpec.radius == 20)
        #expect(ActivityListRowSpec.sidePadding == 16)
        #expect(ActivityListRowSpec.spacing == 12)
        #expect(ActivityListRowSpec.disc == 36)
        #expect(ActivityListRowSpec.disc == IconDisc.Size.regular.diameter)
    }

    @Test func theWorkoutsChart() {
        #expect(StrainLayout.chartHeight == 150)
        #expect(StrainLayout.chartHeightLargeText > StrainLayout.chartHeight)
        #expect(StrainLayout.chartLine == 1.4)
        #expect(StrainLayout.chartRadius == 22)
        #expect(StrainLayout.sourceGap == 14)
        #expect(StrainLayout.statColumns == 2)
    }
}
