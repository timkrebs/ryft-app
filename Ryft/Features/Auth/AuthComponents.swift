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
