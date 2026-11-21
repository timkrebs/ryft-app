import SwiftUI

/// The colour decision for a set row's parts (Nocturne PR 6 B §4.3, which replaces design.md §2.5 and §2.8's inks; the
/// geometry is the same), picked per part from existing tokens. Ink and grey carry every state; Volt is only the active row's
/// two small marks, the dot and the bar (D6B-1). The ✓ of the active row is the page's one filled ink square (F16). List's
/// rows take the same three looks (§4.7). The app is dark-only. `FocusedPolishTests` does the maths.
enum FocusedRowInk {
    /// The estimate column: grey on every row, the dash quieter still.
    static func estimate(isDash: Bool) -> Color {
        isDash ? Theme.textTertiary : Theme.textSecondary
    }

    /// The outline of an upcoming ✓: the raised grey, a graphic beside a glyph that carries the meaning.
    static func upcomingOutline() -> Color {
        Theme.surfaceRaised
    }

    /// A kg or reps value. On a raised field (the active row's, List's upcoming ones, and the field the keypad types into on a
    /// done row) an empty field is grey too: `textTertiary` is 3.94:1 on the raised fill, under 4.5:1 (a raised fill carries
    /// `textPrimary` or `textSecondary` text).
    static func value(_ state: FocusedRowState, hasValue: Bool, hasGhost: Bool, onRaisedField: Bool = false) -> Color {
        switch state {
        case .done: hasValue || onRaisedField ? Theme.textSecondary : Theme.textTertiary
        case .active: hasValue ? Theme.textPrimary : Theme.textSecondary
        case .upcoming: hasValue ? Theme.textPrimary : hasGhost || onRaisedField ? Theme.textSecondary : Theme.textTertiary
        }
    }

    /// The `#` column: the active row's number in ink on its raised circle, every other number and the warm-up "W" grey (the
    /// letter is the cue: D6B-9, no amber).
    static func number(_ state: FocusedRowState) -> Color {
        state == .active ? Theme.textPrimary : Theme.textSecondary
    }

    /// The ✓'s fill: ink on the active row, nothing on the others.
    static func checkFill(_ state: FocusedRowState) -> Color {
        state == .active ? Theme.textPrimary : .clear
    }

    /// The ✓ glyph: the screen's colour on the ink fill (17.35:1), grey on a done row, quieter on an upcoming one.
    static func checkGlyph(_ state: FocusedRowState) -> Color {
        switch state {
        case .active: Theme.background
        case .done: Theme.textSecondary
        case .upcoming: Theme.textTertiary
        }
    }

    /// The active row's two marks, the dot on its `#` and the bar at its edge: Volt, the "now" (L27), never a fill or text.
    static let mark = Theme.signal

    /// The tint under the active row: ink at 5 %.
    static let activeTint = 0.05
    /// The tint's colour at `activeTint`, or clear on another row.
    static func activeRowFill(_ isActive: Bool) -> Color {
        Theme.textPrimary.opacity(isActive ? activeTint : 0)
    }

    /// The ring around the field the keypad types into: ink, the strip's "current" ring.
    static let focusRing = Theme.textPrimary
}
