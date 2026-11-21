import AuthenticationServices
import SwiftUI

/// The Apple button's numbers (PR 6 A §A-1, D6A-3).
enum AppleSignInButtonSpec {
    /// 52 at the default size, growing with the text up to 64 (Apple's range for the button).
    static let height: CGFloat = 52, maxHeight: CGFloat = 64
    /// Apple allows the corner radius; the label, the logo and the fill stay Apple's.
    static let cornerRadius: CGFloat = 26
    /// The veil while the Apple sheet is up: `background` at 60 % (opaque under Reduce Transparency).
    static let veilOpacity = 0.6
}

/// The native Sign in with Apple button, wired to `AuthService`: the white style, the one Apple allows on a dark ground
/// (the black one vanishes on `background`, the outline one is for white grounds), 52 high and growing with the text to
/// 64, corners of 26. While a sign-in runs it is veiled with a small spinner and takes no taps.
struct AppleSignInButton: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = AppleSignInButtonSpec.height

    /// The button's height at a text size's scaled 52: never under 52, never over 64.
    static func height(scaled: CGFloat) -> CGFloat {
        min(max(scaled, AppleSignInButtonSpec.height), AppleSignInButtonSpec.maxHeight)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppleSignInButtonSpec.cornerRadius, style: .continuous)
        SignInWithAppleButton(.continue) { request in
            auth.prepare(request)
        } onCompletion: { result in
            Task { await auth.complete(result) }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: Self.height(scaled: scaledHeight))
        .clipShape(shape)
        .overlay {
            if auth.isWorking {
                shape
                    .fill(Theme.background.opacity(reduceTransparency ? 1 : AppleSignInButtonSpec.veilOpacity))
                    .overlay { ProgressView().tint(Theme.textPrimary) }
            }
        }
        .disabled(auth.isWorking)
        .accessibilityIdentifier("welcome.apple")
    }
}

#Preview("Apple button", traits: .sizeThatFitsLayout) {
    DarkPreview {
        AppleSignInButton()
    }
    .environment(AuthService.preview(signedIn: false))
}

#Preview("Apple button · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        AppleSignInButton()
    }
    .environment(AuthService.preview(signedIn: false))
    .dynamicTypeSize(.accessibility3)
}
