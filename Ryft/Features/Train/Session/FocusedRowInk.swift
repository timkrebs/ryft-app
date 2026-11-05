import SwiftUI

/// The one colour decision for a Focused row in light, where `textSecondary` on the active row's tint and `surfaceRaised`
/// on the background fall short (design.md §2.8). Picked per row part from existing tokens: changing `textSecondary`
/// would change List and every other screen. Dark keeps the design's tokens. `FocusedRowInkTests` does the maths.
enum FocusedRowInk {
    /// The estimate column. On the active row in light it is the row's own `textPrimary`; grey on the tint is under 4.5:1.
    static func estimate(active: Bool, isDash: Bool, _ scheme: ColorScheme) -> Color {
        if active, scheme == .light { return Theme.textPrimary }
        return isDash ? Theme.textTertiary : Theme.textSecondary
    }

    /// The outline of an upcoming ✓: 4.7:1 on the background in light, and the same grey as its glyph.
    static func upcomingOutline(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Theme.textTertiary : Theme.surfaceRaised
    }

    /// The tint under the active row. `CurrentSetHighlight` draws it.
    static let activeTint = 0.10
}
