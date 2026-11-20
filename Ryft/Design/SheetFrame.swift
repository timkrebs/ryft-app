import SwiftUI

/// The numbers of `SheetFrame` (a separate, non-generic type: the frame is generic).
enum SheetFrameSpec {
    /// The header → the pinned part under it.
    static let pinnedGap: CGFloat = 10
    /// The header (or the pinned part) → the body's first line.
    static let bodyGap: CGFloat = 12
    /// The body's insets: 12 on top, the header's 20 at the sides, a sub-page's bottom padding under the last line.
    static let bodyInsets = EdgeInsets(top: bodyGap, leading: SheetHeaderSpec.sidePadding, bottom: SubpageSpec.bottomPadding,
                                       trailing: SheetHeaderSpec.sidePadding)
    /// VoiceOver's order: the header and the pinned part first (one group, its own order inside), then a bar a caller pins
    /// outside the frame at `outsidePinnedPriority` (Replace's plan toggle; the sheet's root a `.contain` group), then the body.
    static let headerPriority: Double = 2, outsidePinnedPriority: Double = 1

    /// §12: a sheet opens at `.large` from XL; below it, `compact` (half height first, the drag up to full).
    static func detents(for typeSize: DynamicTypeSize,
                        compact: Set<PresentationDetent> = [.medium, .large]) -> Set<PresentationDetent> {
        typeSize >= .xLarge ? [.large] : compact
    }
}

extension View {
    /// §12's detents (`SheetFrameSpec.detents(for:compact:)`) at the sheet content's own text size, for a sheet whose view
    /// doesn't read it (the plate calculator): `.large` from XL, `compact` below it.
    func sheetDetents(compact: Set<PresentationDetent> = [.medium, .large]) -> some View {
        modifier(SheetDetents(compact: compact))
    }
}

private struct SheetDetents: ViewModifier {
    let compact: Set<PresentationDetent>
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.presentationDetents(SheetFrameSpec.detents(for: typeSize, compact: compact))
    }
}

/// A sheet's frame (PR 6 B §4.8, D6B-13): `SheetHeader` on top (the close circle, the centred title, the trailing slot), 26 under
/// the sheet's edge and 20 from the sides; an optional pinned part under it, 10 below (Add exercise's search field); then the
/// scrolling body. Neither the header nor the pinned part scrolls, so the commit and the search stay in reach. `background`
/// behind it all. The detents are the caller's (`SheetFrameSpec.detents(for:)` for §12's rule). VoiceOver meets the header and
/// the pinned part before the body (`SheetFrameSpec.headerPriority`).
///
/// `SheetFrame(Text("Notes"), closeLabel: Text("Cancel")) { PillButton(Text("Save"), size: .compact) { … } } content: { … }`.
/// Settings, each a modifier on the frame: the close circle's (`closeHidden()`, `closeDisabled(_:)`, `closeIdentifier(_:)`, as
/// `SheetHeader`'s), `bodyInsets(_:)` for a body that pads itself (`EdgeInsets()`), and `grabber(_:)`: visible by default,
/// `.automatic` leaves it to the detents (shown only when there are two or more).
struct SheetFrame<Trailing: View, Pinned: View, Content: View>: View {
    private var header: SheetHeader<Trailing>
    private let pinned: Pinned
    private let content: Content
    private var insets = SheetFrameSpec.bodyInsets
    private var grabberVisibility: Visibility = .visible

    init(_ title: Text, closeLabel: Text? = nil, onClose: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder pinned: () -> Pinned, @ViewBuilder content: () -> Content) {
        header = SheetHeader(title, closeLabel: closeLabel, onClose: onClose, trailing: trailing)
        self.pinned = pinned()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: SheetFrameSpec.pinnedGap) {
                header
                pinned
            }
            .padding(.horizontal, SheetHeaderSpec.sidePadding)
            .padding(.top, SheetHeaderSpec.topInset)
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(SheetFrameSpec.headerPriority)
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(insets)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationBackground(Theme.background)
        .presentationDragIndicator(grabberVisibility)
    }

    /// No close circle: the trailing slot is the way out.
    func closeHidden(_ hidden: Bool = true) -> SheetFrame {
        var copy = self
        copy.header = header.closeHidden(hidden)
        return copy
    }

    /// The close circle dimmed and untappable, e.g. while a save is in flight.
    func closeDisabled(_ disabled: Bool) -> SheetFrame {
        var copy = self
        copy.header = header.closeDisabled(disabled)
        return copy
    }

    /// The close circle's accessibility identifier, `sheet.close` unless given.
    func closeIdentifier(_ identifier: String) -> SheetFrame {
        var copy = self
        copy.header = header.closeIdentifier(identifier)
        return copy
    }

    /// The body's insets inside the scroll view; `EdgeInsets()` for a body that pads itself.
    func bodyInsets(_ insets: EdgeInsets) -> SheetFrame {
        var copy = self
        copy.insets = insets
        return copy
    }

    /// The grabber: visible by default; `.automatic` shows it only with two or more detents.
    func grabber(_ visibility: Visibility) -> SheetFrame {
        var copy = self
        copy.grabberVisibility = visibility
        return copy
    }
}

extension SheetFrame where Pinned == EmptyView {
    /// A sheet without a pinned part.
    init(_ title: Text, closeLabel: Text? = nil, onClose: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.init(title, closeLabel: closeLabel, onClose: onClose, trailing: trailing, pinned: { EmptyView() }, content: content)
    }
}

extension SheetFrame where Trailing == EmptyView, Pinned == EmptyView {
    /// A sheet with nothing to commit and nothing pinned (Rest).
    init(_ title: Text, closeLabel: Text? = nil, onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, closeLabel: closeLabel, onClose: onClose, trailing: { EmptyView() }, pinned: { EmptyView() },
                  content: content)
    }
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

#Preview("SheetFrame") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetFrame(Text(verbatim: "Add exercise")) {
                EmptyView()
            } pinned: {
                SearchField(text: .constant(""), prompt: Text(verbatim: "Search exercises"))
            } content: {
                GroupedCard(Text(verbatim: "All exercises")) {
                    GroupedRow.action(Text(verbatim: "Bench press"), detail: Text(verbatim: "Barbell · Chest"),
                                      systemImage: "plus") {}
                    GroupedRow.action(Text(verbatim: "Back squat"), detail: Text(verbatim: "Barbell · Quads, glutes"),
                                      systemImage: "plus") {}
                }
            }
            .presentedRoot()
        }
        .previewEnvironment()
}

#Preview("SheetFrame · commit, close hidden") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SheetFrame(Text(verbatim: "Reorder")) {
                PillButton(Text(verbatim: "Done"), size: .compact) {}
            } content: {
                Text(verbatim: "Rows").foregroundStyle(Theme.textSecondary)
            }
            .closeHidden()
            .presentationDetents([.medium])
            .presentedRoot()
        }
        .previewEnvironment()
}
