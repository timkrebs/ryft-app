// The root's control styles for presented content (T5.7, PR 5 review S1).
import SwiftUI

extension View {
    /// The window root's tint and toggle style again, for content the app presents: every `.sheet`, `.fullScreenCover` and
    /// `.popover` content closure in `Ryft/` ends its view with it (one line at the presenter).
    ///
    /// `RyftApp` sets `.tint(Theme.textPrimary)` (teal is recovery only, design.md §P5-1) and `.toggleStyle(.ryft)`
    /// (§P5-1.4) once, on the window's root. On iOS 27.2 the toggle style doesn't reach what that root presents: the
    /// integrated app showed stock switches in the import cover, and Report a problem, pushed in the error card's Details
    /// sheet, did too. Previews and hosted tests that set the style on the presented view itself never show it. The tint
    /// does cross today; it goes along so that a presented root never depends on that (what nothing tints falls back to the
    /// app's global accent, the `AccentColor` asset, also the ink). A screen that wants another tint or toggle style still
    /// sets its own inside. `PresentedRootTests` pins what crosses a sheet, renders presented roots through their real
    /// presenters, and fails for a presentation in `Ryft/` that goes without it.
    func presentedRoot() -> some View {
        tint(Theme.textPrimary)
            .toggleStyle(.ryft)
    }
}
