// The pill button (Nocturne, docs/work/2026-11-16-nocturne/design.md §P2-4, brief §2 "Pill-Buttons 52 hoch, primär hell
// mit dunklem Icon-Kreis, sekundär Outline"). No busy state: the caller disables it and changes the title.
import SwiftUI

/// At least 52 pt high (round ends) and the full proposed width. `primary`: a `textPrimary` fill, the title leading in `background`,
/// a 40 pt `background` circle with the icon on the trailing side. `secondary`: a 1 pt outline at 20 %, the title
/// centred, no icon. The title is the accessibility label; it scales and wraps, the pill grows with it.
struct PillButton: View {
    enum Style { case primary, secondary }

    /// 52: `Theme.Metrics.pillHeight`. The icon circle is a circle button's 40.
    static let minHeight = Theme.Metrics.pillHeight, iconCircle = Theme.Metrics.circleButton
    static let outlineOpacity = 0.20, disabledOpacity = 0.35
    /// Primary: the fill when pressed. Secondary: the fill when pressed.
    static let primaryPressedOpacity = 0.85, secondaryPressedFillOpacity = 0.08
    static let iconSize: CGFloat = 14
    /// Primary 20 leading / 6 trailing (the circle's inset), secondary 22 each side; 12 above and below the title.
    static let primaryLeading: CGFloat = 20, primaryTrailing: CGFloat = 6, secondaryHorizontal: CGFloat = 22
    static let titleVertical: CGFloat = 12

    private let title: Text
    private let style: Style
    private let systemImage: String
    private let action: () -> Void

    init(_ title: Text, style: Style = .primary, systemImage: String = "arrow.right", action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            switch style {
            case .primary: primaryLabel
            case .secondary: secondaryLabel
            }
        }
        .buttonStyle(PillButtonStyle(style: style))
    }

    private var primaryLabel: some View {
        HStack(spacing: Theme.Metrics.itemSpacing) {
            styledTitle(Theme.background)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: systemImage)
                .font(.system(size: Self.iconSize, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Self.iconCircle, height: Self.iconCircle)
                .background(Theme.background, in: Circle())
                .accessibilityHidden(true)
        }
        .padding(.leading, Self.primaryLeading)
        .padding(.trailing, Self.primaryTrailing)
    }

    private var secondaryLabel: some View {
        styledTitle(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Self.secondaryHorizontal)
    }

    private func styledTitle(_ color: Color) -> some View {
        title
            .font(.ryft(.button))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Self.titleVertical)
    }
}

private struct PillButtonStyle: ButtonStyle {
    let style: PillButton.Style
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        // A capsule at 52 pt (radius 26 = half the height), but the corners stay 26 when the title wraps: a true
        // capsule's radius grows with the height and cuts the outer corners of the first and last lines at AX3.
        let shape = RoundedRectangle(cornerRadius: PillButton.minHeight / 2, style: .circular)
        configuration.label
            .frame(maxWidth: .infinity, minHeight: PillButton.minHeight)
            .background {
                switch style {
                case .primary:
                    shape.fill(Theme.textPrimary.opacity(configuration.isPressed ? PillButton.primaryPressedOpacity : 1))
                case .secondary:
                    shape.fill(Theme.textPrimary.opacity(configuration.isPressed ? PillButton.secondaryPressedFillOpacity : 0))
                        .overlay {
                            shape.strokeBorder(Theme.textPrimary.opacity(PillButton.outlineOpacity),
                                               lineWidth: Theme.Metrics.hairline)
                        }
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : PillButton.disabledOpacity)
    }
}

#Preview("PillButton", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            PillButton(Text("Continue")) {}
            PillButton(Text("Continue")) {}
                .disabled(true)
            PillButton(Text("Not now"), style: .secondary) {}
            PillButton(Text("Not now"), style: .secondary) {}
                .disabled(true)
        }
    }
}

#Preview("PillButton · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            PillButton(Text("Connect Apple Health to start syncing")) {}
            PillButton(Text("Connect Apple Health to start syncing"), style: .secondary) {}
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
