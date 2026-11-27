import SwiftUI

/// The Google Identity light button treatment with a native, localized label.
/// See docs/GOOGLE_SIGN_IN_BRANDING.md for the upstream artwork and font.
struct GoogleSignInButton: View {
    let title: LocalizedStringKey
    let action: @MainActor () async -> Void

    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var scaledHeight = AppleSignInButtonSpec.height

    private let labelColor = Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255)
    private let borderColor = Color(red: 116 / 255, green: 119 / 255, blue: 117 / 255)

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 12) {
                Image("GoogleSignInLogo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.custom("GoogleSans-Medium", size: 14, relativeTo: .callout))
                    .foregroundStyle(labelColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: AppleSignInButton.height(scaled: scaledHeight))
            .background(.white, in: Capsule())
            .overlay { Capsule().strokeBorder(borderColor, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : PillButton.disabledOpacity)
    }
}
