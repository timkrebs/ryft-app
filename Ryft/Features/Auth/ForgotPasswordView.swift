import SwiftUI

/// Sends a reset link to `ryft://auth/callback`; opening it shows Set new password. Nocturne (PR 6 A §A-4): the lead, a
/// one-row card with the email (Log in's, focused), the banner, "Send reset link" (busy while it works: the pill's
/// spinner, the title stays).
struct ForgotPasswordView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.appEnvironment) private var env
    @Binding var path: [AuthRoute]
    @State var email: String
    /// Previews and shots: the busy state, which `AuthService` only enters during a request.
    var showsBusy = false

    @FocusState private var focus: AuthField?

    private var isValid: Bool { AuthValidation.isEmail(email) }
    private var isBusy: Bool { auth.isWorking || showsBusy }

    var body: some View {
        AuthScreen(title: Text("Reset password"),
                   lead: Text("Enter your account's email. We'll send you a link to set a new password.")) {
            GroupedCard {
                AuthTextField(title: "Email", text: $email, field: .email, focus: $focus, contentType: .emailAddress,
                              keyboard: .emailAddress, submitLabel: .send) {
                    if isValid { Task { await send() } }
                }
            }
            .disabled(isBusy)
            if auth.errorMessage != nil {
                AuthErrorMessage()
                    .padding(.top, AuthScreenSpec.actionGap)
            }
            PillButton(Text("Send reset link"), systemImage: PillButton.Icon.send, busy: isBusy) {
                await send()
            }
            .disabled(!isValid)
            .padding(.top, auth.errorMessage == nil ? AuthScreenSpec.primaryGap : AuthScreenSpec.actionGap)
            .accessibilityIdentifier("resetPassword.submit")
        }
        .onAppear { auth.errorMessage = nil }
        .authFocus($focus, on: .email, clock: env.clock)
    }

    private func send() async {
        guard isValid, !isBusy else { return }
        focus = nil
        if await auth.sendPasswordReset(email: email) {
            path.append(.checkInbox(.resetPassword, email: email.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }
}

#Preview("Reset password") {
    NavigationStack {
        ForgotPasswordView(path: .constant([]), email: "alex@example.com")
    }
    .environment(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
}

#Preview("Reset password · busy · AX3") {
    NavigationStack {
        ForgotPasswordView(path: .constant([]), email: "alex@example.com", showsBusy: true)
    }
    .environment(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
