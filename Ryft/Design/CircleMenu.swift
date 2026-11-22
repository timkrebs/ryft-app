// The icon-only circle that opens a menu (Nocturne gate D3, docs/work/2026-11-20-nocturne-gate/design.md §2.3): the live
// workout's More, the activity detail's More, My Day's Add. A `CircleButton` is a `Button`, so a menu can't be one; this is
// the same circle from the same numbers (`CircleButtonLook`).
import SwiftUI

/// A `Menu` drawn as a `CircleButton`: the 40 pt outlined circle with a 14 pt symbol (`iconSize`, or the caller's) in a 44 × 44
/// box that is all tappable, the icon at 35 % when disabled. Pressed shows the system's menu highlight, not the button's 8 %
/// fill. The caller's label is required (there is no text) and so is its identifier, set on this view. The icon does not scale
/// with Dynamic Type; at accessibility sizes a long press shows the Large Content Viewer with the icon and the label. At a
/// header's edge the caller adds `.headerEdgeButton()`, as for a `CircleButton`.
struct CircleMenu<Items: View>: View {
    private let systemImage: String
    private let iconSize: CGFloat
    private let accessibilityLabel: Text
    private let items: Items

    /// - Parameter iconSize: the symbol's point size, 14 by default (the live workout's header draws 16, as its Minimise).
    init(systemImage: String, iconSize: CGFloat = CircleButton.iconSize, accessibilityLabel: Text,
         @ViewBuilder items: () -> Items) {
        self.systemImage = systemImage
        self.iconSize = iconSize
        self.accessibilityLabel = accessibilityLabel
        self.items = items()
    }

    var body: some View {
        Menu {
            items
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
                .modifier(CircleButtonLook())
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityShowsLargeContentViewer {
            Label { accessibilityLabel } icon: { Image(systemName: systemImage) }
        }
    }
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

/// Idle and disabled, each beside the `CircleButton` it matches.
private struct CircleMenuPreviewBoard: View {
    var body: some View {
        HStack(spacing: 8) {
            CircleMenu(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "More")) {
                Button {} label: { Label { Text(verbatim: "Edit") } icon: { Image(systemName: "pencil") } }
                Button(role: .destructive) {} label: { Label { Text(verbatim: "Delete") } icon: { Image(systemName: "trash") } }
            }
            CircleButton(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "More")) {}
            CircleMenu(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "More")) {
                Button {} label: { Text(verbatim: "Edit") }
            }
            .disabled(true)
            CircleButton(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "More")) {}
                .disabled(true)
            CircleMenu(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add")) {
                Button {} label: { Label { Text(verbatim: "Add activity") } icon: { Image(systemName: "square.and.pencil") } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("CircleMenu", traits: .sizeThatFitsLayout) {
    DarkPreview { CircleMenuPreviewBoard() }
}

#Preview("CircleMenu · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { CircleMenuPreviewBoard() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
