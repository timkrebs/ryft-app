// Today's measurements in Nocturne (docs/work/2026-11-16-nocturne/design.md §P4-1; plan.md "Measurements from the Today
// board"): every gap is from the bottom of the element above to the top of the next, so the content is one
// `VStack(spacing: 0)` with these between its rows. Plain values, so the layout tests assert numbers, not pixels.
import CoreGraphics

enum TodayLayout {
    // MARK: rows, top to bottom (§P4-1)

    /// Row 1: `ScreenHeaderSpec.height`.
    static let header: CGFloat = ScreenHeaderSpec.height
    static let headerToGreeting: CGFloat = 18
    /// The greeting's tracking: −0.01 em at 26 pt.
    static let greetingTracking: CGFloat = -0.26
    static let greetingToSubLine: CGFloat = 4
    static let subLineToStatus: CGFloat = 4
    /// The import row (after the first score), when there is one.
    static let statusToImportRow: CGFloat = 12
    /// From the status row (or the import row) to the hero.
    static let statusToGauge: CGFloat = 14
    static let gaugeToLabel: CGFloat = 8
    /// Between "Readiness · High" and "▲ +11 vs 7 d".
    static let labelGap: CGFloat = 10
    static let labelToNote: CGFloat = 8
    /// From the label row (or the note) to the ruler.
    static let labelToRuler: CGFloat = 12
    /// From the ruler to the first attention card (`RawNightCard`, the night hint), and between them.
    static let rulerToCards: CGFloat = 12
    static let cardGap: CGFloat = 12
    /// From the ruler to the tiles, with no attention card between them; with one, `cardGap` below it.
    static let rulerToTiles: CGFloat = 22
    static let tileGap: CGFloat = 12
    static let tilesToStrain: CGFloat = 12
    /// Below the glow block: the cards, 12 apart (`Theme.Metrics.sectionSpacing`, derived).
    static let glowToCards: CGFloat = 24

    // MARK: sizes

    /// L14: the hero gauge's dial, and its frame (dial + 12).
    static let heroDial: CGFloat = 248
    static let heroFrame: CGFloat = 260
    /// The halo's reach from the gauge's centre: 3 pt past the frame's 130.
    static let heroHaloRadius: CGFloat = 133
    static let twoUpHeight: CGFloat = 124
    static let strainHeight: CGFloat = 96
    /// The strain tile's compact ruler: in from the sides (the tile's padding) and up from the bottom.
    static let strainRowInset: CGFloat = 16
    static let strainRulerBottom: CGFloat = 12
    /// The 2-up tile's content height at the board's size (124 − 14 top − 12 bottom padding).
    static let twoUpContentHeight: CGFloat = 98
    /// The strain tile's (96 − 14 − 12): the row on top, the 32 pt compact ruler on the bottom padding.
    static let strainContentHeight: CGFloat = 70

    /// A 2-up tile's width in a content column of `width`: (350 − 12) / 2 = 169; 161.5 at 335, 194 at 400.
    static func twoUpWidth(contentWidth width: CGFloat) -> CGFloat {
        (width - tileGap) / 2
    }

    // MARK: inside the tiles (derived, not measured)

    /// The least space between a 2-up tile's label and its series, and between its two rows.
    static let tileRowGap: CGFloat = 8
    /// Keeps the label clear of the series it shares the row with (the dots are 66 wide, the sparkline 58).
    static let seriesClearance: CGFloat = 74
    /// Between a value and its unit ("82 %", "7:48 h").
    static let unitGap: CGFloat = 3
    /// "12.4" to "of 21 · moderate".
    static let strainCaptionGap: CGFloat = 6
    /// The strain value: 30 pt Light.
    static let strainNumeral: CGFloat = 30

    // MARK: the pending block (§P4-5), in the label row's place

    static let pendingLineGap: CGFloat = 2

    // MARK: data

    /// The readiness ruler's zone starts at the high band (`MetricSpec.scoreBand`: ≥ 67).
    static let highBand: Double = 67
    /// The tiles' series: the last seven days, the shown day last.
    static let weekDays = 7
}
