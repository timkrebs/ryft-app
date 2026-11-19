import SwiftUI

/// The live workout's numbers in Nocturne (docs/work/2026-11-16-nocturne/design-pr6-b-train.md §4, D6B-2, D6B-3), so tests
/// assert them. The geometry the Focused tests pinned before stays: the table's columns are `SetTableColumns`, the pill row
/// `RestPill`; the strip and the page's fade read their numbers from here. The spec calls this `SessionLayout`, which is the
/// Focused / List choice already.
enum LiveSessionSpec {
    // MARK: the header (§4.1), shared by both layouts

    /// The page's sides: 16 (358 pt of content), 12 at 320 (D6B-2), in both layouts. The table's own padding is
    /// `SetTableColumns.padding`.
    nonisolated static let sidePadding: CGFloat = 16, compactSidePadding: CGFloat = 12
    /// Above and below the header's row.
    nonisolated static let headerVerticalPadding: CGFloat = 6
    /// The row of buttons: a circle button's 44 pt box, with a 40 pt circle or the compact pill in it (D6B-3, was 48).
    nonisolated static let headerRow: CGFloat = Theme.Metrics.minHitTarget
    /// The header's least height, 56 (was 64). The title over the clock is taller than the buttons, so the header takes their
    /// height and 6 above and below.
    nonisolated static let headerMinHeight: CGFloat = headerRow + 2 * headerVerticalPadding
    /// Between the header's items, from circle edge to circle edge: 8, and 6 at 320.
    nonisolated static let headerGap: CGFloat = 8, compactHeaderGap: CGFloat = 6
    /// The minimise and More circles' glyph.
    nonisolated static let headerIcon: CGFloat = 16
    /// The clock: 30 Light; 26 at 320 in both layouts, where an hour clock stays on one line and may shrink to 80 % beside the
    /// buttons.
    nonisolated static let clock: CGFloat = 30, compactClock: CGFloat = 26, compactClockScale: CGFloat = 0.8
    /// One row of header: Finish stops growing here and keeps its one line (a long press shows it large).
    nonisolated static let finishCap = DynamicTypeSize.xxLarge, compactFinishCap = DynamicTypeSize.large
    /// The session's title beside Finish at 320: it was cut to "Upp…" uncapped.
    nonisolated static let compactTitleCap = DynamicTypeSize.accessibility1

    // MARK: the Focused page (§4.2)

    /// The strip: 8 above, the 56 pt tile, 3, the 3 pt superset bar, 6 below. 84 with the AX3 tile of 64.
    nonisolated static let strip: CGFloat = 76
    /// The strip's tiles: 56, 64 from AX3; radius 14.
    nonisolated static let tile: CGFloat = 56, largeTile: CGFloat = 64, tileRadius: CGFloat = 14
    /// The page's soft top edge under the strip.
    nonisolated static let pageFade: CGFloat = 16

    /// The outline of a thing at rest, ink at 12 %: the chips, the warm-up pill and the idle rest pill. The outlined keys and the
    /// running pill take the secondary pill's 20 % (`OutlinedKey.edge`).
    nonisolated static let restingEdge = 0.12

    // MARK: the set rows (§4.3)

    /// The row's tint, the ✓ and the strip's tile: radius 14. The fields inside a row: 12.
    nonisolated static let rowRadius: CGFloat = 14, fieldRadius: CGFloat = 12
    /// The active row's `#`: a 32 pt raised circle (the number column's width at 320), with a 5 pt Volt dot at its corner.
    nonisolated static let activeNumber: CGFloat = 32, activeDot: CGFloat = 5
    /// The active row's leading bar: 2 pt of Volt, 8 shorter than the row at each end.
    nonisolated static let activeBarWidth: CGFloat = 2, activeBarInset: CGFloat = 8
    /// The bar's leading edge sits this far in from the screen's edge: 10 pt outside the row at 390 (its 16 pt sides), the same
    /// 6 pt from the edge at 320.
    nonisolated static let activeBarFromEdge: CGFloat = 6

    /// How far outside its row the bar starts, for a page with `padding` sides: 10 at 390.
    nonisolated static func activeBarOutset(padding: CGFloat) -> CGFloat {
        max(activeBarWidth, padding - activeBarFromEdge)
    }

    /// The bar's height on a row `rowHeight` high: 40 on the 56 pt row, 48 on the 64 pt one.
    nonisolated static func activeBarHeight(rowHeight: CGFloat) -> CGFloat {
        rowHeight - 2 * activeBarInset
    }
}
