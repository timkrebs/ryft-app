// The Activities screens' numbers in Nocturne (docs/work/2026-11-16-nocturne/design-pr6-b-train.md §10; drafts `b-19`, `b-20`,
// `b-21`): Add activity, Add sleep, the sport picker, the activity detail and its splits. Gaps run from the bottom of one element
// to the top of the next. `nonisolated` so tests and layout code read them anywhere (P2-D9). The parts' own numbers stay with
// the parts (`SheetHeaderSpec`, `GroupedListSpec`, `FormFieldSpec`, `NeutralTile`, `EffortScaleSpec`, `GlowTileSpec`).
import CoreGraphics

enum ActivitiesLayout {
    // MARK: sheets (Add activity, Add sleep)

    /// The sheet header → the first block.
    nonisolated static let headerGap: CGFloat = 10
    /// Between the blocks of Add activity (the sport row, the times, distance, effort, notes, the footnote).
    nonisolated static let blockSpacing: CGFloat = 12
    /// The last block → the sheet's bottom edge.
    nonisolated static let bottomPadding: CGFloat = 32
    /// The sport row: at least 60 high, 16 at the sides, 12 between the disc, the name and the chevron.
    nonisolated static let sportRowMinHeight: CGFloat = 60, sportRowInset: CGFloat = 16, sportRowSpacing: CGFloat = 12
    /// The sport row's `chevron.up.chevron.down`: 13 pt, ink at 35 % (decoration: the row is a button named by the sport).
    nonisolated static let chevronSize: CGFloat = 13, chevronOpacity = 0.35
    /// The Duration row: a list row's 46.
    nonisolated static let durationRowMinHeight: CGFloat = 46
    /// The duration's numerals: 20 Light, growing with the text like `.title3`.
    nonisolated static let durationValueSize: CGFloat = 20
    /// The effort card: its label → the scale.
    nonisolated static let effortLabelGap: CGFloat = 14
    /// The notes card: at least three lines, 12 above and below the text.
    nonisolated static let notesMinLines = 3, notesVerticalPadding: CGFloat = 12
    /// A reason under a field: the glyph, 6, the sentence (`caption`).
    nonisolated static let issueGlyphGap: CGFloat = 6
    /// The Strength suggestion: the sentence → the pill → "Add here anyway".
    nonisolated static let suggestionSpacing: CGFloat = 12

    // MARK: Add sleep

    /// "For a night no tracker recorded." → the times, and the times → "Time asleep".
    nonisolated static let sleepIntroGap: CGFloat = 12, sleepDurationGap: CGFloat = 14
    /// "Time asleep" → its value on the same baseline; the value 24 Light.
    nonisolated static let sleepValueGap: CGFloat = 12, sleepValueSize: CGFloat = 24
    /// The duration's caption → the "added by you" note.
    nonisolated static let sleepNoteGap: CGFloat = 12

    // MARK: the sport picker

    /// The header → the search field → the first group.
    nonisolated static let pickerHeaderGap: CGFloat = 12, pickerSearchGap: CGFloat = 18

    // MARK: the activity detail (§10.3)

    /// The header → the sync line (when there is one) → the numeral.
    nonisolated static let syncGap: CGFloat = 12
    nonisolated static let numeralGap: CGFloat = 20
    /// The numeral → "Duration · h:mm" → the source badge.
    nonisolated static let captionGap: CGFloat = 12, badgeGap: CGFloat = 8
    /// The badge → the tiles; between the blocks under them (the strain block, the rows, notes, the actions).
    nonisolated static let tilesGap: CGFloat = 24, sectionSpacing: CGFloat = 12
    /// The tiles: two columns, 12 apart; one column from AX1.
    nonisolated static let tileColumns = 2, tileSpacing: CGFloat = 12
    /// The strain block: the tile (or the outline card) → its caption ("Heart rate from Garmin Connect").
    nonisolated static let strainCaptionGap: CGFloat = 8
    /// The strain card without a heart-rate strain (`Card`: `surface`, radius 22, padding 16): label → line → reason.
    nonisolated static let strainCardSpacing: CGFloat = 10, strainReasonGap: CGFloat = 6
    /// "Add a note": 52 high, the glyph 12 before the words.
    nonisolated static let addNoteHeight: CGFloat = 52, addNoteSpacing: CGFloat = 12
    /// Between Edit and Delete (and Log this in Train above them).
    nonisolated static let actionSpacing: CGFloat = 12
    /// The last element → the bottom of the page.
    nonisolated static let detailBottomPadding: CGFloat = 32

    // MARK: splits (§10.3 item 4)

    /// A row: at least 40 high. The bar: 6 high, `metricStrain` at 60 %; the fastest split's bar `textPrimary`.
    nonisolated static let splitRowMinHeight: CGFloat = 40, splitBarHeight: CGFloat = 6, splitBarOpacity = 0.6
    /// The card's title → the column header → the rows.
    nonisolated static let splitsTitleGap: CGFloat = 12
}
