import AuthenticationServices
import SwiftUI

/// Where the Welcome flow can go. "Set new password" isn't here: it opens as a
/// sheet from a reset link or Profile.
enum AuthRoute: Hashable {
    case createAccount
    case logIn
    case forgotPassword(email: String)
    case checkInbox(InboxReason, email: String)
}

enum InboxReason: Hashable {
    case confirmSignUp
    case resetPassword
}

enum AuthValidation {
    static func isEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = t.firstIndex(of: "@"), at != t.startIndex else { return false }
        let domain = t[t.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !t.contains(" ")
    }

    static func isPassword(_ s: String) -> Bool { s.count >= AuthService.minimumPasswordLength }
}

/// Frame for the auth screens: Graphite (always dark, like Welcome), title,
/// subtitle, scrolling form.
struct AuthScreen<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.ryft(.title))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 6)
                content()
            }
            .padding(.horizontal, Theme.Metrics.screenPadding + 4)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Labelled text field in the RYFT field style.
struct AuthTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
            TextField("", text: $text)
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .authFieldBackground()
                .accessibilityLabel(Text(title))
        }
    }
}

/// Password field with show/hide. `isNew` asks the system for a strong-password suggestion.
struct PasswordField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var isNew = false
    var hint: LocalizedStringKey? = nil

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Group {
                    if revealed {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
                .textContentType(isNew ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(Text(title))
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(revealed ? Text("Hide password") : Text("Show password"))
            }
            .authFieldBackground()
            if let hint {
                Text(hint)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Inline error from AuthService, if any.
struct AuthErrorMessage: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        if let message = auth.errorMessage {
            InlineMessage(message: message, systemImage: "exclamationmark.circle")
        }
    }
}

extension View {
    fileprivate func authFieldBackground() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - account hint

/// `User.account_hint`: this account is new, and this iPhone synced another one
/// recently. Probably the same person signed in another way (Apple vs. email).
struct AccountHintSheet: View {
    let hint: AccountHint
    let keep: () -> Void
    let useOther: () async -> Void

    private var text: String {
        let last = Fmt.date(hint.otherLastSync)
        switch hint.otherProvider {
        case "email":
            return String(localized: "This iPhone synced another RYFT account until \(last), one you logged in to with email. If that was you, log out and log in with email. You can then add Sign in with Apple to it in Profile.")
        case "apple":
            return String(localized: "This iPhone synced another RYFT account until \(last), one you opened with Sign in with Apple. If that was you, log out and continue with Apple.")
        default:
            return String(localized: "This iPhone synced another RYFT account until \(last). If that was you, log out and sign in the way you did then.")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "person.2")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 28)
                    .accessibilityHidden(true)
                Text("This is a new RYFT account")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Use the other account") { await useOther() }
                    .accessibilityIdentifier("hint.useOther")
                PrimaryButton(title: "Continue with this one", style: .secondary) { keep() }
                    .accessibilityIdentifier("hint.keep")
                Text("Data in both accounts? Support can merge them: ryftapp.de/support")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding + 4)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}

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

#Preview("Account hint · dark") {
    AccountHintSheet(hint: AccountHint(kind: "other_account_on_device", otherProvider: "email",
                                       otherLastSync: .now.addingTimeInterval(-86_400)),
                     keep: {}, useOther: {})
        .preferredColorScheme(.dark)
}

#Preview("Account hint · light") {
    AccountHintSheet(hint: AccountHint(kind: "other_account_on_device", otherProvider: "apple",
                                       otherLastSync: .now.addingTimeInterval(-86_400)),
                     keep: {}, useOther: {})
        .preferredColorScheme(.light)
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
