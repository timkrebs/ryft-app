// The icon-only circle button (Nocturne, docs/work/2026-11-16-nocturne/design.md §P2-4, brief §2 "Kreis-Buttons 40 mit
// 1-pt-Rand @ 16 %"): previous/next, the calendar, the plus. A 40 pt circle in a 44 pt tap box (P2-D3).
import SwiftUI

/// A 40 pt outlined circle with a 14 pt symbol (`iconSize`, or the caller's), inside a 44 × 44 layout box that is all
/// tappable. The caller's label is required: there is no text. Pressed fills the circle at 8 %; disabled dims the icon to
/// 35 %. The icon does not scale with Dynamic Type; at accessibility sizes a long press shows the Large Content Viewer
/// with the icon and the label.
struct CircleButton: View {
    /// 40 and 44: `Theme.Metrics.circleButton` and `minHitTarget`.
    static let diameter = Theme.Metrics.circleButton, hitSize = Theme.Metrics.minHitTarget, iconSize: CGFloat = 14
    static let borderOpacity = 0.16, disabledIconOpacity = 0.35
    static let pressedFillOpacity = 0.08

    private let systemImage: String
    private let iconSize: CGFloat
    private let accessibilityLabel: Text
    private let action: () -> Void

    /// - Parameter iconSize: the symbol's point size, 14 by default; Today's calendar is 16 (design.md §P4-1, D4-8). The
    ///   weight stays `.regular`, so the stroke is the component's (≈ 1.3 pt).
    init(systemImage: String, iconSize: CGFloat = CircleButton.iconSize, accessibilityLabel: Text,
         action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.iconSize = iconSize
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
        }
        .buttonStyle(CircleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityShowsLargeContentViewer {
            Label { accessibilityLabel } icon: { Image(systemName: systemImage) }
        }
    }
}

private struct CircleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.textPrimary.opacity(isEnabled ? 1 : CircleButton.disabledIconOpacity))
            .frame(width: CircleButton.diameter, height: CircleButton.diameter)
            .background {
                Circle().fill(Theme.textPrimary.opacity(configuration.isPressed ? CircleButton.pressedFillOpacity : 0))
            }
            .overlay {
                Circle().strokeBorder(Theme.textPrimary.opacity(CircleButton.borderOpacity), lineWidth: Theme.Metrics.hairline)
            }
            .frame(width: CircleButton.hitSize, height: CircleButton.hitSize)
            .contentShape(Rectangle())
    }
}

#Preview("CircleButton", traits: .sizeThatFitsLayout) {
    DarkPreview {
        HStack(spacing: 8) {
            CircleButton(systemImage: "chevron.left", accessibilityLabel: Text("Previous night")) {}
            CircleButton(systemImage: "chevron.right", accessibilityLabel: Text("Next night")) {}
                .disabled(true)
            CircleButton(systemImage: "calendar", accessibilityLabel: Text("Choose a day")) {}
            CircleButton(systemImage: "calendar", iconSize: 16, accessibilityLabel: Text(verbatim: "Calendar")) {}
            CircleButton(systemImage: "plus", accessibilityLabel: Text("Add an activity")) {}
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("CircleButton · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        HStack(spacing: 8) {
            CircleButton(systemImage: "chevron.left", accessibilityLabel: Text("Previous night")) {}
            CircleButton(systemImage: "chevron.right", accessibilityLabel: Text("Next night")) {}
                .disabled(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
