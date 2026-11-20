// The placeholder outline (Nocturne, docs/work/2026-11-16-nocturne/build-plan.md §2; design.md §P4-5 and §P5-3.7; PR 6 B §1.5
// S12, C §2.7): what a row, a tile or a card is while its data loads, the honest state instead of a spinner. Sleep's PR 4
// outlines (its tiles and the hypnogram's slot) were the first; they draw with `PlaceholderOutline` now.
import SwiftUI

/// `surface` inside a 1 pt `separator` border, in `shape`: the look of a placeholder. Decoration, hidden from VoiceOver.
struct PlaceholderOutline<S: InsettableShape>: View {
    private let shape: S

    init(_ shape: S) {
        self.shape = shape
    }

    var body: some View {
        ZStack {
            shape.fill(Theme.surface)
            shape.strokeBorder(Theme.separator, lineWidth: PlaceholderRowSpec.lineWidth)
        }
        .accessibilityHidden(true)
    }
}

/// The placeholder's numbers (a separate, non-generic type: `PlaceholderRow` is generic).
enum PlaceholderRowSpec {
    /// The outline: 1 pt (`Theme.Metrics.hairline`) in `separator`.
    static let lineWidth = Theme.Metrics.hairline
    /// The default corner: the neutral tile's and the grouped card's 22. An activity row passes 20.
    static let radius = Theme.Metrics.neutralTileRadius
    /// The content's inset at the sides (a row's 16).
    static let inset: CGFloat = 16
}

/// A row in its loading state: the outline at the row's own height (a minimum: it grows with its content at large sizes), and
/// the caller's content inside it, leading and centred ("–" values, a "Loading…" caption). Without content it is only the
/// outline and VoiceOver skips it; the screen says it is loading once (Strain's "Loading this day").
struct PlaceholderRow<Content: View>: View {
    private let height: CGFloat
    private let radius: CGFloat
    private let content: Content

    init(height: CGFloat, radius: CGFloat = PlaceholderRowSpec.radius, @ViewBuilder content: () -> Content) {
        self.height = height
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        // In a container: an `EmptyView` with modifiers is no view at all in a stack, and the outline-only row would vanish.
        ZStack(alignment: .leading) { content }
            .padding(.horizontal, PlaceholderRowSpec.inset)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .background { PlaceholderOutline(RoundedRectangle(cornerRadius: radius, style: .continuous)) }
    }
}

extension PlaceholderRow where Content == EmptyView {
    /// The outline alone.
    init(height: CGFloat, radius: CGFloat = PlaceholderRowSpec.radius) {
        self.init(height: height, radius: radius) { EmptyView() }
    }
}

extension View {
    /// A view of the caller's (a tile, a card) drawn in its placeholder state: the outline behind it, with `radius` corners.
    func placeholderOutline(radius: CGFloat = PlaceholderRowSpec.radius) -> some View {
        background { PlaceholderOutline(RoundedRectangle(cornerRadius: radius, style: .continuous)) }
    }
}
