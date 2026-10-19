import SwiftUI

/// Name, email, password (≥ 10 characters). With "Confirm email" on in the
/// Supabase project there's no session yet → Check your inbox; otherwise
/// RootView switches to the tabs.
struct CreateAccountView: View {
    @EnvironmentObject private var auth: AuthService
    @Binding var path: [AuthRoute]

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && AuthValidation.isEmail(email) && AuthValidation.isPassword(password)
    }

    var body: some View {
        AuthScreen(title: "Create account", subtitle: "One account for your sleep, recovery and strain.") {
            AuthTextField(title: "Name", text: $name, contentType: .name, capitalization: .words)
            AuthTextField(title: "Email", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
            PasswordField(title: "Password", text: $password, isNew: true,
                          hint: "At least \(AuthService.minimumPasswordLength) characters.")
            AuthErrorMessage()
            PrimaryButton(title: "Create account", busy: auth.isWorking) { await submit() }
                .disabled(!isValid)
                .padding(.top, 4)
            // Links must be literal for Markdown; the pages have to exist on ryftapp.de (STATUS.md).
            Text("By creating an account you agree to the [Terms](https://ryftapp.de/terms) and the [Privacy Policy](https://ryftapp.de/privacy).")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .tint(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { auth.errorMessage = nil }
    }

    private func submit() async {
        guard isValid else { return }
        if await auth.signUp(name: name, email: email, password: password) == .confirmEmail {
            path.append(.checkInbox(.confirmSignUp, email: email.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }
}

#Preview("Create account") {
    NavigationStack {
        CreateAccountView(path: .constant([]))
    }
    .environmentObject(AuthService.preview(signedIn: false))
}

#Preview("Create account · light system") {
    NavigationStack {
        CreateAccountView(path: .constant([]))
    }
    .environmentObject(AuthService.preview(signedIn: false))
    .preferredColorScheme(.light)
}
