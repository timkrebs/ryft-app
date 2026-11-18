// Strain's and the Workout detail's measurements (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-3.1, §P5-4, §P5-12
// test 1): the board's gaps and sizes, bottom of one element to the top of the next. `nonisolated` so tests and layout code
// read them anywhere (P2-D9). The parts' own numbers stay with the parts: the zones tile's in `GlowTileSpec` (`.zones`), the
// tiles' in `NeutralTile`, the rows' in `ActivityListRowSpec`, the strip's in `DateStrip`.
import CoreGraphics

enum StrainLayout {
    // MARK: header and strip

    /// The header row (`ScreenHeaderSpec.height`).
    nonisolated static let headerHeight: CGFloat = 40
    /// The header → the week strip (F7, D5-2: the board has none). The strip is the restyled `DateStrip` (build plan §2:
    /// `DayStrip` was not built), so its height is the strip's own, not the spec's 44.
    nonisolated static let stripGap: CGFloat = 12
    /// The strip → the status line or the refresh card (§P5-3.7).
    nonisolated static let statusGap: CGFloat = 12

    // MARK: the hero

    /// The strip (the workout's header) → the numeral.
    nonisolated static let numeralGap: CGFloat = 22
    /// The numeral → the caption ("of 21 · moderate").
    nonisolated static let captionGap: CGFloat = 12
    /// The caption → the split ("Cardio 9.2 · Strength 4.1").
    nonisolated static let splitGap: CGFloat = 4
    /// The caption (or the split) → the ruler.
    nonisolated static let rulerGap: CGFloat = 14
    /// The ruler's box (`RulerScale.Size.regular`).
    nonisolated static let rulerHeight: CGFloat = 36
    /// What the caller puts under the ruler (`RulerScale(followingGap:)`): the zones tile's top is the ruler's top + 56 (the
    /// board's 20 under the ruler's labels, as Sleep's hypnogram, review row 11).
    nonisolated static let rulerFollowingGap: CGFloat = 20
    /// The ruler's top → the zones tile's top.
    nonisolated static var rulerToTile: CGFloat { rulerHeight + rulerFollowingGap }

    // MARK: the zones tile

    /// Inside the tile: the head row ("Heart-rate zones", "82 min · TRIMP 112") → the zone block.
    nonisolated static let zonesHeadGap: CGFloat = 14
    /// The short tile without zone data (§P5-3.7): the head and the sentence.
    nonisolated static let zonesShortHeight: CGFloat = 96
    /// The tile → its footnote ("Zones are in % of heart-rate reserve.").
    nonisolated static let footnoteGap: CGFloat = 8

    // MARK: tiles, sections, rows

    /// The zones tile's footnote → the neutral tiles, and between the two tiles.
    nonisolated static let tilesGap: CGFloat = 12, tileSpacing: CGFloat = 12
    /// The tiles → Train, and Train → Activities (`Theme.Metrics.sectionSpacing`).
    nonisolated static let sectionGap: CGFloat = 24
    /// The tiles → Activities without a Train section (the board's).
    nonisolated static let activitiesGap: CGFloat = 18
    /// "Activities" (or "Train") → the first row.
    nonisolated static let listTitleGap: CGFloat = 10
    /// Between two activity rows (the board's).
    nonisolated static let rowGap: CGFloat = 8
    /// Between the Train section's items (PR 6 B §3.1, `b-23`).
    nonisolated static let trainItemGap: CGFloat = 12
    /// The list → the footer cards (the Health hint).
    nonisolated static let footerGap: CGFloat = 12

    // MARK: Workout detail (§P5-4)

    /// The stat tiles: two columns.
    nonisolated static let statColumns = 2
    /// The header's centre: the sport → the time range under it.
    nonisolated static let headerSubtitleGap: CGFloat = 2
    /// The heart-rate card: radius 22, padding 14 / 16 / 14; the chart 150 high, 8 under the card's head row.
    nonisolated static let chartRadius: CGFloat = 22, chartPadding: CGFloat = 14, chartSidePadding: CGFloat = 16
    nonisolated static let chartHeight: CGFloat = 150, chartHeadGap: CGFloat = 8
    /// From AX1 the chart is taller, so its three value labels (in large text) keep apart.
    nonisolated static let chartHeightLargeText: CGFloat = 200
    /// The line (1.4 pt, round joins), the average's dashed 1 pt rule and the peak's 3 pt dot.
    nonisolated static let chartLine: CGFloat = 1.4, chartAverageLine: CGFloat = 1, chartPeakDot: CGFloat = 3
    /// The y axis's three ticks and its gridlines, `textPrimary` at 8 %.
    nonisolated static let chartYTicks = 3, chartGridOpacity = 0.08
    /// The chart → the source line ("Recorded by Garmin Connect").
    nonisolated static let sourceGap: CGFloat = 14
    /// The last element → the bottom of the page.
    nonisolated static let bottomPadding: CGFloat = 32
}
