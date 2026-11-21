// My Day's measurements (Nocturne, docs/work/2026-11-16-nocturne/design-pr6-b-train.md §9, the `b-17`, `b-18` and `b-26`
// drafts): the card on Today and the full screen, bottom of one element to the top of the next. `nonisolated` so tests and
// layout code read them anywhere (P2-D9). The rows' own numbers are `ActivityListRowSpec`'s, the strip's `DateStrip`'s.
import CoreGraphics

enum MyDayLayout {
    // MARK: the card (§9.1)

    /// The header: the title block and the plus circle on a 40 pt row (the circle's 44 pt box reaches 2 past it).
    nonisolated static let headerHeight: CGFloat = 40
    /// The title → the summary under it.
    nonisolated static let headerSubtitleGap: CGFloat = 2
    /// The header → the dashed missing night when it is the first row (the other rows bring their own 12).
    nonisolated static let dashedRowGap: CGFloat = 8
    /// "Show all": a 46 pt row (`GroupedListSpec.rowMinHeight`) under a hairline.
    nonisolated static let showAllHeight: CGFloat = 46
    /// The Add activity pill: 4 under "Show all", 12 under the rows or the empty line.
    nonisolated static let addGapUnderShowAll: CGFloat = 4, addGap: CGFloat = 12
    /// "Nothing logged yet today.": 12 above it under a row (the pill keeps its own 12 below), 4 above it as the card's first line.
    nonisolated static let emptyPadding: CGFloat = 12, emptyTopAlone: CGFloat = 4
    /// The stale caption under the pill (or the rows); its Try again 12 beside the words (under them from AX1).
    nonisolated static let staleGap: CGFloat = 8, staleRetryGap: CGFloat = 12
    /// The header → the outline rows, the failed or the offline message.
    nonisolated static let stateGap: CGFloat = 12
    /// Loading: three outline rows (`ActivityListRowPlaceholder`), 8 apart.
    nonisolated static let placeholderRows = 3, placeholderSpacing: CGFloat = 8

    // MARK: the full screen (§9.2)

    /// The pushed header → the date strip.
    nonisolated static let stripGap: CGFloat = 8
    /// The strip → the summary line ("4 activities · 2h 13m · 6.8 mi", Strain 12.4).
    nonisolated static let summaryGap: CGFloat = 18
    /// The summary line → the first row, and between the rows (tiles).
    nonisolated static let rowsGap: CGFloat = 12, rowSpacing: CGFloat = 8
    /// The rows → "Nothing logged yet today." or "Nothing recorded on this day" (beside the rows' own 8).
    nonisolated static let screenEmptyGap: CGFloat = 4
    /// "Strain" → the day's strain on the summary line.
    nonisolated static let strainLabelGap: CGFloat = 6
    /// The pinned Add activity: a 24 pt fade from the page into `background` above it, 16 between it and the tab bar, 20 at
    /// the sides.
    nonisolated static let pinnedFade: CGFloat = 24, pinnedBottom: CGFloat = 16, pinnedSides: CGFloat = 20
    /// Under the last row (or the stale line): the page ends here, above the pinned pill's fade.
    nonisolated static let bottomPadding: CGFloat = 8
}
