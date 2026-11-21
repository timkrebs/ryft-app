// The header of a sheet that commits or closes (Nocturne, docs/work/2026-11-16-nocturne/build-plan.md §2; PR 6 B §1.2, S3,
// D6B-13): a close circle on the left, the title centred between the edges whatever the slots hold, and a trailing slot that
// is empty, a `CircleButton` (a menu), or a compact primary pill for the commit ("Save", "Add", "Done"). It replaces the
// system toolbar's glass "Cancel" / "Save" capsules, which can't be recoloured. The one sheet header (Nocturne gate D4,
// docs/work/2026-11-20-nocturne-gate/design.md §2.4): B's sheets (`SheetFrame`) and every sheet root of `SubpageScaffold`
// (`navigation: .close`) draw it, pinned above their scroll; a page pushed inside a sheet has `PushedHeader`'s row instead.
import SwiftUI

/// The sheet header's numbers.
enum SheetHeaderSpec {
    /// The row: 40 high (a circle button's), taller only when the title wraps at large text sizes.
    static let height: CGFloat = 40
    /// The header starts 26 below the sheet's top edge: 14 under the grabber. The caller's padding.
    static let topInset = SubpageSpec.sheetTopInset
    /// The sides: 20, the screen padding. The caller's padding.
    static let sidePadding = Theme.Metrics.screenPadding
    /// The least room between the title and either slot.
    static let minGap = ScreenHeaderSpec.minGap
    /// Below AX1 the title keeps its place between the slots while it has at least this; with less (a wide pill at XXXL) it
    /// goes on its own line under them, centred.
    static let minTitleWidth: CGFloat = 120
    /// Below AX1, the buttons' row → the title centred under it when the slots squeeze it.
    static let stackedGap: CGFloat = 8
    /// From AX1, the buttons' row → the title under it, from the leading inset: `PushedHeader`'s (C §2.9).
    static let accessibilityStackedGap = SubpageSpec.stackedGap
}

/// `SheetHeader(Text("Add activity")) { PillButton(Text("Save"), size: .compact) { … } }`. The close circle says "Close", or
/// the caller's label ("Cancel" when closing discards what was typed); `onClose` is the caller's (a sheet that discards asks
/// first), or `dismiss` when nil. The title is `callout` (15) `textPrimary`, a header for VoiceOver, which reads it first,
/// then the close circle, then the trailing slot. From AX1 it stacks as `PushedHeader` does (Nocturne gate D4 rule 2): the
/// close circle and the trailing slot on the first 40 pt row, 12 under it the title from the leading inset across the whole
/// width, wrapping, never squeezed between the circles; VoiceOver then reads them as drawn: the close circle, the trailing
/// slot, the title. A compact pill in the slot keeps its one line: cap the slot's type at `.xxLarge` where it would crowd
/// the title, as `PillButton.compact` says. A `CircleButton` in the slot takes `.headerEdgeButton()`, so its circle's edge,
/// not its tap box's, is on the inset.
///
/// The close circle, when the sheet needs it otherwise (each a modifier on the header; the default is unchanged):
/// `.closeHidden()` for a sheet whose commit is its only way out (Reorder: every move is made at once, so a close beside
/// "Done" would say the same twice); `.closeDisabled(saving)` while a save is in flight (dimmed and untappable, as a
/// disabled `CircleButton`); `.closeIdentifier(_:)` where tests and history know it by another name than `sheet.close`.
struct SheetHeader<Trailing: View>: View {
    private let title: Text
    private let closeLabel: Text
    private let onClose: (() -> Void)?
    private let trailing: Trailing
    private var closeIsHidden = false
    private var closeIsDisabled = false
    private var closeID = "sheet.close"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: Text, closeLabel: Text? = nil, onClose: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.closeLabel = closeLabel ?? CircleButton.closeLabel
        self.onClose = onClose
        self.trailing = trailing()
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            stacked
        } else {
            SheetHeaderLayout(minHeight: SheetHeaderSpec.height, minGap: SheetHeaderSpec.minGap) {
                closeSlot
                    .accessibilitySortPriority(1)
                titleText(.center)
                    .accessibilitySortPriority(2)
                // One subview however many (or few) views the slot holds.
                trailingSlot
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// From AX1 (D4 rule 2, as `PushedHeader`): the close circle and the trailing slot on the first 40 pt row, 12 under it
    /// the title from the leading inset across the width. No sort priorities: VoiceOver reads in the order drawn.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: SheetHeaderSpec.accessibilityStackedGap) {
            // A header with neither a close circle nor a trailing view (a stack's root) has no row to draw.
            if !(closeIsHidden && Trailing.self == EmptyView.self) {
                HStack(spacing: 0) {
                    closeSlot
                    Spacer(minLength: SheetHeaderSpec.minGap)
                    trailingSlot
                }
                .frame(minHeight: SheetHeaderSpec.height)
            }
            titleText(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    /// The close circle laid out as its 40 pt circle, or, hidden, the empty leading slot (below AX1 the title stays centred
    /// on the trailing slot's width).
    @ViewBuilder private var closeSlot: some View {
        if closeIsHidden {
            Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
        } else {
            CircleButton(systemImage: "xmark", accessibilityLabel: closeLabel) {
                if let onClose { onClose() } else { dismiss() }
            }
            .headerEdgeButton()
            .disabled(closeIsDisabled)
            .accessibilityIdentifier(closeID)
        }
    }

    private var trailingSlot: some View {
        HStack(spacing: SubpageSpec.trailingSpacing) { trailing }
    }

    private func titleText(_ alignment: TextAlignment) -> some View {
        title
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

extension SheetHeader {
    /// No close circle: the trailing slot is the way out (a sheet must still have one, or the drag down).
    func closeHidden(_ hidden: Bool = true) -> SheetHeader {
        var copy = self
        copy.closeIsHidden = hidden
        return copy
    }

    /// The close circle dimmed and untappable, e.g. while a save is in flight.
    func closeDisabled(_ disabled: Bool) -> SheetHeader {
        var copy = self
        copy.closeIsDisabled = disabled
        return copy
    }

    /// The close circle's accessibility identifier, `sheet.close` unless given.
    func closeIdentifier(_ identifier: String) -> SheetHeader {
        var copy = self
        copy.closeID = identifier
        return copy
    }
}

extension SheetHeader where Trailing == EmptyView {
    /// A sheet with nothing to commit (Start workout, Rest).
    init(_ title: Text, closeLabel: Text? = nil, onClose: (() -> Void)? = nil) {
        self.init(title, closeLabel: closeLabel, onClose: onClose) { EmptyView() }
    }
}

/// Leading at the left edge, trailing at the right, the centre in the middle of the row: it gets the width between the wider
/// of the two slots on both sides, so it stays centred under the grabber when the slots differ (a 40 pt circle against a
/// 70 pt "Save"). Everything is centred vertically; the row is at least `minHeight`. When that leaves the centre less than
/// `minTitleWidth`, the slots keep their row and the centre goes under it, as wide as the row. Three subviews: leading,
/// centre, trailing. The headers use it below AX1 only; from AX1 they stack (`SheetHeader.stacked`, `PushedHeader`).
struct SheetHeaderLayout: Layout {
    let minHeight: CGFloat
    let minGap: CGFloat
    var minTitleWidth: CGFloat = SheetHeaderSpec.minTitleWidth
    var stackedGap: CGFloat = SheetHeaderSpec.stackedGap

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let side = sideWidth(subviews)
        let width = proposal.width ?? 2 * (side + minGap) + subviews[1].sizeThatFits(.unspecified).width
        let row = rowHeight(subviews)
        if isStacked(width, side: side) {
            let centre = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: width, height: row + stackedGap + centre.height)
        }
        let centre = subviews[1].sizeThatFits(ProposedViewSize(width: centreWidth(width, side: side), height: nil))
        return CGSize(width: width, height: max(row, centre.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let side = sideWidth(subviews)
        if isStacked(bounds.width, side: side) {
            let rowMidY = bounds.minY + rowHeight(subviews) / 2
            subviews[0].place(at: CGPoint(x: bounds.minX, y: rowMidY), anchor: .leading, proposal: .unspecified)
            subviews[2].place(at: CGPoint(x: bounds.maxX, y: rowMidY), anchor: .trailing, proposal: .unspecified)
            subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.minY + rowHeight(subviews) + stackedGap), anchor: .top,
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
            return
        }
        let midY = bounds.midY
        subviews[0].place(at: CGPoint(x: bounds.minX, y: midY), anchor: .leading, proposal: .unspecified)
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: midY), anchor: .trailing, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.midX, y: midY), anchor: .center,
                          proposal: ProposedViewSize(width: centreWidth(bounds.width, side: side), height: nil))
    }

    /// The wider slot's width.
    private func sideWidth(_ subviews: Subviews) -> CGFloat {
        max(subviews[0].sizeThatFits(.unspecified).width, subviews[2].sizeThatFits(.unspecified).width)
    }

    /// The slots' row: `minHeight`, or the taller slot.
    private func rowHeight(_ subviews: Subviews) -> CGFloat {
        max(minHeight, subviews[0].sizeThatFits(.unspecified).height, subviews[2].sizeThatFits(.unspecified).height)
    }

    /// The centre's width: the row less the wider slot and the gap on both sides.
    func centreWidth(_ width: CGFloat, side: CGFloat) -> CGFloat {
        max(0, width - 2 * (side + minGap))
    }

    /// The title goes under the slots when they leave it less than `minTitleWidth`.
    func isStacked(_ width: CGFloat, side: CGFloat) -> Bool {
        centreWidth(width, side: side) < minTitleWidth
    }
}

extension View {
    /// A `CircleButton` at a header's edge, laid out as its 40 pt circle: its 44 pt box reaches 2 past the inset (and past the
    /// row's top and bottom), as in `ScreenHeader`.
    func headerEdgeButton() -> some View {
        padding(-ScreenHeaderSpec.buttonOverhang)
    }
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

private struct SheetHeaderPreviewBoard: View {
    var body: some View {
        VStack(spacing: 24) {
            SheetHeader(Text(verbatim: "Start workout"))
            SheetHeader(Text(verbatim: "Add activity"), closeLabel: Text(verbatim: "Cancel")) {
                PillButton(Text(verbatim: "Save"), size: .compact) {}
            }
            SheetHeader(Text(verbatim: "Edit plan")) {
                PillButton(Text(verbatim: "Save"), size: .compact) {}
                    .disabled(true)
            }
            SheetHeader(Text(verbatim: "Rest")) {
                CircleButton(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "More")) {}
                    .headerEdgeButton()
            }
            SheetHeader(Text(verbatim: "Mon, Nov 16")) {
                PillButton(Text(verbatim: "Save"), size: .compact, busy: true) {}
            }
            // Saving: the close circle off while the save runs.
            SheetHeader(Text(verbatim: "New plan"), closeLabel: Text(verbatim: "Cancel")) {
                PillButton(Text(verbatim: "Save"), size: .compact, busy: true) {}
            }
            .closeDisabled(true)
            // The commit is the only way out.
            SheetHeader(Text(verbatim: "Reorder")) {
                PillButton(Text(verbatim: "Done"), size: .compact) {}
            }
            .closeHidden()
        }
    }
}

#Preview("SheetHeader", traits: .sizeThatFitsLayout) {
    DarkPreview { SheetHeaderPreviewBoard() }
}

#Preview("SheetHeader · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { SheetHeaderPreviewBoard() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
