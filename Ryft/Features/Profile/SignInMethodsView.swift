import AuthenticationServices
import SwiftUI

// MARK: - sign-in methods

/// Profile → Account → Sign-in methods: the account's identities, and "Add Sign in
/// with Apple" for an email account, so both sign-ins open the same data.
struct SignInMethodsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("You can sign in to this account with:")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                VStack(spacing: 0) {
                    ForEach(methods) { method in
                        HStack(spacing: 12) {
                            Image(systemName: method.provider == "apple" ? "apple.logo" : "envelope")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.title(method.provider))
                                    .font(.ryft(.body))
                                    .foregroundStyle(Theme.textPrimary)
                                if let email = method.email {
                                    Text(email)
                                        .font(.ryft(.caption))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Spacer()
                        }
                        .frame(minHeight: 52)
                        .accessibilityElement(children: .combine)
                        if method != methods.last { Divider().overlay(Theme.separator) }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
                if !auth.hasAppleSignIn {
                    Text("Add Sign in with Apple to open this account with your Apple ID too. Your data stays in this account.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SignInWithAppleButton(.continue) { request in
                        auth.prepareLink(request)
                    } onCompletion: { result in
                        Task { await auth.completeLink(result) }
                    }
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .id(scheme) // the style is read once; a new scheme needs a new button
                    .frame(height: 50)
                    .clipShape(Capsule())
                    .disabled(auth.isWorking)
                    .accessibilityIdentifier("signInMethods.addApple")
                }
                if let error = auth.linkError {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle")
                }
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Sign-in methods"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await auth.loadSignInMethods() }
    }

    /// Loaded identities; before they arrive, the session's provider.
    private var methods: [SignInMethod] {
        if !auth.signInMethods.isEmpty { return auth.signInMethods }
        return auth.provider.map { [SignInMethod(provider: $0, email: auth.user?.email, addedAt: nil)] } ?? []
    }

    static func title(_ provider: String) -> String {
        switch provider {
        case "apple": return String(localized: "Apple ID")
        case "email": return String(localized: "Email and password")
        default: return provider.capitalized
        }
    }
}

#Preview("Sign-in methods · dark") {
    NavigationStack { SignInMethodsView() }
        .environment(AuthService.preview(provider: "email"))
        .preferredColorScheme(.dark)
}

#Preview("Sign-in methods · light") {
    NavigationStack { SignInMethodsView() }
        .environment(AuthService.preview(provider: "email"))
        .preferredColorScheme(.light)
}
