import SwiftUI

/// The frame of the sheets the live workout opens on an exercise (PR 6 B §4.8, D6B-13): Add exercise and Replace, the custom
/// exercise form, Edit targets and Notes. `SheetHeader` on top (the close circle, the centred title, a compact commit pill),
/// 26 under the sheet's edge and 20 from the sides; an optional pinned part under it (Add exercise's search field), 10 below;
/// then the scrolling body, 20 from the sides. Neither the header nor the pinned part scrolls, so the commit and the search stay
/// in reach. `background` behind it all and the grabber visible; the detents are the caller's.
struct SessionSheetFrame<Trailing: View, Pinned: View, Content: View>: View {
    private let title: Text
    private let closeLabel: Text?
    private let onClose: (() -> Void)?
    private let trailing: Trailing
    private let pinned: Pinned
    private let content: Content

    /// Header → the pinned part, and the pinned part (or the header) → the body.
    static var pinnedGap: CGFloat { 10 }
    static var bodyGap: CGFloat { 12 }
    /// Under the body's last line.
    static var bottomPadding: CGFloat { SubpageSpec.bottomPadding }

    init(_ title: Text, closeLabel: Text? = nil, onClose: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder pinned: () -> Pinned, @ViewBuilder content: () -> Content) {
        self.title = title
        self.closeLabel = closeLabel
        self.onClose = onClose
        self.trailing = trailing()
        self.pinned = pinned()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Self.pinnedGap) {
                SheetHeader(title, closeLabel: closeLabel, onClose: onClose) { trailing }
                pinned
            }
            .padding(.horizontal, SheetHeaderSpec.sidePadding)
            .padding(.top, SheetHeaderSpec.topInset)
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SheetHeaderSpec.sidePadding)
                    .padding(.top, Self.bodyGap)
                    .padding(.bottom, Self.bottomPadding)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
    }
}

extension SessionSheetFrame where Pinned == EmptyView {
    /// A sheet without a pinned part.
    init(_ title: Text, closeLabel: Text? = nil, onClose: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.init(title, closeLabel: closeLabel, onClose: onClose, trailing: trailing, pinned: { EmptyView() }, content: content)
    }
}
