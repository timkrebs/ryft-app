import SwiftUI

/// Email + password. Errors stay calm and never say whether the email has an
/// account ("Email or password is wrong"). Nocturne (PR 6 A §A-2): the subpage header, one card with the two fields,
/// "Forgot password?" under it, the banner, the primary; while it works the pill says "Logging in…" and the rows hold still.
struct LogInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.appEnvironment) private var env
    @Binding var path: [AuthRoute]
    /// Previews and shots: the busy state, which `AuthService` only enters during a request.
    var showsBusy = false

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: AuthField?

    private var isValid: Bool { AuthValidation.isEmail(email) && !password.isEmpty }
    private var isBusy: Bool { auth.isWorking || showsBusy }

    var body: some View {
        AuthScreen(title: Text("Log in")) {
            GroupedCard {
                AuthTextField(title: "Email", text: $email, field: .email, focus: $focus, contentType: .username,
                              keyboard: .emailAddress) { focus = .password }
                PasswordField(title: "Password", text: $password, focus: $focus) {
                    if isValid { Task { await logIn() } }
                }
            }
            .disabled(isBusy)
            Button {
                path.append(.forgotPassword(email: email))
            } label: {
                Text("Forgot password?")
            }
            .ryftLink()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
            if auth.errorMessage != nil {
                AuthErrorMessage()
                    .padding(.bottom, AuthScreenSpec.actionGap)
            }
            PillButton(isBusy ? Text("Logging in…") : Text("Log in"), busy: isBusy) { await logIn() }
                .disabled(!isValid)
                .accessibilityHint(isValid ? Text(verbatim: "") : Text("Fill in your email and password first."))
                .accessibilityIdentifier("logIn.submit")
        }
        .onAppear { auth.errorMessage = nil }
        .authFocus($focus, on: .email, clock: env.clock)
    }

    private func logIn() async {
        guard isValid, !isBusy else { return }
        focus = nil
        await auth.logIn(email: email, password: password)
    }
}

#Preview("Log in") {
    NavigationStack {
        LogInView(path: .constant([]))
    }
    .environment(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
}

#Preview("Log in · busy") {
    NavigationStack {
        LogInView(path: .constant([]), showsBusy: true)
    }
    .environment(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
}

#Preview("Log in · error") {
    let auth = AuthService.preview(signedIn: false)
    return NavigationStack {
        LogInView(path: .constant([]))
            .task {
                // After the screen's own clearing on appear.
                try? await Task.sleep(for: .milliseconds(100))
                auth.errorMessage = String(localized: "Email or password is wrong.")
            }
    }
    .environment(auth)
    .preferredColorScheme(.dark)
}

/// A held sign-in shows here too: Log in is where it was tried.
#Preview("Log in · sign-in held") {
    NavigationStack {
        LogInView(path: .constant([]))
    }
    .environment(AuthService.previewHeld())
    .preferredColorScheme(.dark)
}

#Preview("Log in · AX3") {
    NavigationStack {
        LogInView(path: .constant([]))
    }
    .environment(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
