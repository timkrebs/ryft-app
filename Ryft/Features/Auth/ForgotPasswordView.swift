import SwiftUI

/// Sends a reset link to `ryft://auth/callback`; opening it shows Set new password.
struct ForgotPasswordView: View {
    @Environment(AuthService.self) private var auth
    @Binding var path: [AuthRoute]
    @State var email: String

    var body: some View {
        AuthScreen(title: "Reset password",
                   subtitle: "Enter your account's email. We'll send you a link to set a new password.") {
            AuthTextField(title: "Email", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
            AuthErrorMessage()
            PrimaryButton(title: "Send reset link", busy: auth.isWorking) {
                if await auth.sendPasswordReset(email: email) {
                    path.append(.checkInbox(.resetPassword, email: email.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            .disabled(!AuthValidation.isEmail(email))
        }
        .onAppear { auth.errorMessage = nil }
    }
}

#Preview("Reset password") {
    NavigationStack {
        ForgotPasswordView(path: .constant([]), email: "tim@example.com")
    }
    .environment(AuthService.preview(signedIn: false))
}
