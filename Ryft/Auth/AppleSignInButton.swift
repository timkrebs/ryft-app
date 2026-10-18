import AuthenticationServices
import SwiftUI

/// The native Sign in with Apple button, wired to `AuthService`. White on
/// dark backgrounds, black on light ones (Apple's guidelines).
struct AppleSignInButton: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            auth.prepare(request)
        } onCompletion: { result in
            Task { await auth.complete(result) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(Capsule())
        .overlay {
            if auth.isWorking {
                Capsule()
                    .fill(.background.opacity(0.6))
                    .overlay { ProgressView().tint(Theme.textPrimary) }
            }
        }
        .disabled(auth.isWorking)
    }
}

#Preview("Apple button", traits: .sizeThatFitsLayout) {
    SchemePair {
        AppleSignInButton()
    }
    .environmentObject(AuthService.preview(signedIn: false))
}
