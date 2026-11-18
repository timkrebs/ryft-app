import SwiftUI

/// The colour decision for a Focused row's parts (design.md §2.8), picked per part from existing tokens: changing
/// `textSecondary` would change List and every other screen. The app is dark-only. `FocusedPolishTests` does the maths.
enum FocusedRowInk {
    /// The estimate column: grey on every row, the dash quieter still.
    static func estimate(isDash: Bool) -> Color {
        isDash ? Theme.textTertiary : Theme.textSecondary
    }

    /// The outline of an upcoming ✓: the raised grey, a graphic (3:1).
    static func upcomingOutline() -> Color {
        Theme.surfaceRaised
    }

    /// A kg or reps field. On the active row an empty field is grey too: `textTertiary` is 3.94:1 on the raised field,
    /// under 4.5:1 (a raised fill carries `textPrimary` or `textSecondary` text).
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
