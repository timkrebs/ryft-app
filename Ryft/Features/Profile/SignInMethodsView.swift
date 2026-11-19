import AuthenticationServices
import SwiftUI

// MARK: - sign-in methods

/// Sign-in methods' numbers (Nocturne, PR 6 C §4.9; plain values, so tests assert numbers).
enum SignInMethodsLayout {
    /// The system Sign in with Apple button: 52 high, radius 26 (the page's light pill).
    nonisolated static let appleButtonHeight: CGFloat = 52, appleButtonRadius: CGFloat = 26
    /// While `auth.isWorking`: the button at 35 % (`GroupedListSpec.disabledOpacity`).
    nonisolated static let workingOpacity = 0.35
}

/// Profile → Account → Sign-in methods in Nocturne (PR 6 C §4.9): the account's identities as rows (a ringed glyph, the
/// method, the address), and for an email account the sentence and the system "Continue with Apple" button, so both
/// sign-ins open the same data. With both linked there is nothing to add and no button.
///
/// Before the identities arrive the session's own provider shows as one row; a linking failure shows as a notice under the
/// button. The page has no unlink: the platform offers none (and so no last-method guard to keep).
struct SignInMethodsView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        SubpageScaffold(Text("Sign-in methods")) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                Text("You can sign in to this account with:")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                GroupedCard {
                    ForEach(methods) { method in
                        SignInMethodRow(title: Text(Self.title(method.provider)), email: method.email,
                                        systemImage: method.provider == "apple" ? "apple.logo" : "envelope")
                    }
                }
                if !auth.hasAppleSignIn { addApple }
                if let error = auth.linkError {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle")
                }
            }
        }
        .task { await auth.loadSignInMethods() }
    }

    /// The sentence and Apple's own button (its style and words are Apple's: `.white` on this dark page).
    private var addApple: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
            Text("Add Sign in with Apple to open this account with your Apple ID too. Your data stays in this account.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SignInWithAppleButton(.continue) { request in
                auth.prepareLink(request)
            } onCompletion: { result in
                Task { await auth.completeLink(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: SignInMethodsLayout.appleButtonHeight)
            .clipShape(RoundedRectangle(cornerRadius: SignInMethodsLayout.appleButtonRadius, style: .continuous))
            .disabled(auth.isWorking)
            .opacity(auth.isWorking ? SignInMethodsLayout.workingOpacity : 1)
            .accessibilityIdentifier("signInMethods.addApple")
        }
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

/// One identity: the ringed glyph, the method and the address under it. The address is the one text that may truncate (in
/// the middle, at the default sizes); from AX1 it wraps. VoiceOver reads "Email and password, alex@example.com", whole.
private struct SignInMethodRow: View {
    let title: Text
    let email: String?
    let systemImage: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: GroupedListSpec.rowSpacing) {
            IconDisc(systemImage: systemImage)
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                title
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let email {
                    Text(verbatim: email)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, GroupedListSpec.textPadding)
        .padding(.horizontal, GroupedListSpec.rowInset)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        .groupedRowHairline()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(email.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
    }
}

// MARK: - previews (dark only)

#Preview("Sign-in methods · email") {
    NavigationStack { SignInMethodsView() }
        .environment(AuthService.preview(provider: "email"))
        .preferredColorScheme(.dark)
}

#Preview("Sign-in methods · AX3") {
    NavigationStack { SignInMethodsView() }
        .environment(AuthService.preview(provider: "email"))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
