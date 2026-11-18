import SwiftUI

/// Name, email, password (≥ 10 characters). With "Confirm email" on in the
/// Supabase project there's no session yet → Check your inbox; otherwise
/// RootView switches to the tabs. Nocturne (PR 6 A §A-3): the lead, one card with the three fields, the length hint, the
/// banner, the primary, and the terms line with its two links.
struct CreateAccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.appEnvironment) private var env
    @Binding var path: [AuthRoute]
    /// Previews and shots: the busy state, which `AuthService` only enters during a request.
    var showsBusy = false

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var legal: LegalPage?
    @FocusState private var focus: AuthField?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && AuthValidation.isEmail(email) && AuthValidation.isPassword(password)
    }

    private var isBusy: Bool { auth.isWorking || showsBusy }

    var body: some View {
        AuthScreen(title: Text("Create account"), lead: Text("One account for your sleep, recovery and strain.")) {
            GroupedCard {
                AuthTextField(title: "Name", text: $name, field: .name, focus: $focus, contentType: .name,
                              capitalization: .words) { focus = .email }
                AuthTextField(title: "Email", text: $email, field: .email, focus: $focus, contentType: .emailAddress,
                              keyboard: .emailAddress) { focus = .password }
                PasswordField(title: "Password", text: $password, focus: $focus, isNew: true) {
                    if isValid { Task { await submit() } }
                }
            }
            .disabled(isBusy)
            AuthHint(text: Text("At least \(AuthService.minimumPasswordLength) characters."))
            if auth.errorMessage != nil {
                AuthErrorMessage()
                    .padding(.top, AuthScreenSpec.primaryGap)
            }
            PillButton(isBusy ? Text("Creating account…") : Text("Create account"), busy: isBusy) { await submit() }
                .disabled(!isValid)
                .padding(.top, auth.errorMessage == nil ? AuthScreenSpec.primaryGap : AuthScreenSpec.actionGap)
                .accessibilityIdentifier("createAccount.submit")
            // Links must be literal for Markdown; the pages have to exist on ryftapp.de (STATUS.md). They open in-app.
            Text(inlineLinks: "By creating an account you agree to the [Terms](https://ryftapp.de/terms) and the [Privacy Policy](https://ryftapp.de/privacy).")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .onAppear { auth.errorMessage = nil }
        .authFocus($focus, on: .name, clock: env.clock)
        .safariSheet($legal)
    }

    private func submit() async {
        guard isValid, !isBusy else { return }
        focus = nil
        if await auth.signUp(name: name, email: email, password: password) == .confirmEmail {
            path.append(.checkInbox(.confirmSignUp, email: email.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }
}

#Preview("Create account") {
    NavigationStack {
        CreateAccountView(path: .constant([]))
    }
    .environment(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
}

#Preview("Create account · busy") {
    NavigationStack {
        CreateAccountView(path: .constant([]), showsBusy: true)
    }
    .environment(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
}

#Preview("Create account · AX3") {
    NavigationStack {
        CreateAccountView(path: .constant([]))
    }
    .environment(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
