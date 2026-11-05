import SwiftUI

/// The one colour decision for a Focused row in light, where `textSecondary` on the active row's tint and `surfaceRaised`
/// on the background fall short (design.md §2.8). Picked per row part from existing tokens: changing `textSecondary`
/// would change List and every other screen. Dark keeps the design's tokens. `FocusedRowInkTests` does the maths.
enum FocusedRowInk {
    /// The estimate column. On the active row in light it is the row's own `textPrimary`; grey on the tint is 4.51:1, which
    /// is no margin.
    static func estimate(active: Bool, isDash: Bool, _ scheme: ColorScheme) -> Color {
        if active, scheme == .light { return Theme.textPrimary }
        return isDash ? Theme.textTertiary : Theme.textSecondary
    }

    /// The outline of an upcoming ✓: 4.7:1 on the background in light, and the same grey as its glyph.
    static func upcomingOutline(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Theme.textTertiary : Theme.surfaceRaised
    }

    /// A kg or reps field. On the active row an empty field is grey too: `textTertiary` is 4.40:1 on dark's raised field.
    static func value(_ state: FocusedRowState, hasValue: Bool, hasGhost: Bool) -> Color {
        switch state {
        case .done: hasValue ? Theme.textSecondary : Theme.textTertiary
        case .active: hasValue ? Theme.textPrimary : Theme.textSecondary
        case .upcoming: hasValue ? Theme.textPrimary : hasGhost ? Theme.textSecondary : Theme.textTertiary
        }
    }

    /// The tint under the active row. `CurrentSetHighlight` draws it.
    static let activeTint = 0.10
}
