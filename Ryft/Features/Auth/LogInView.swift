import SwiftUI

/// Email + password. Errors stay calm and never say whether the email has an
/// account ("Email or password is wrong").
struct LogInView: View {
    @EnvironmentObject private var auth: AuthService
    @Binding var path: [AuthRoute]

    @State private var email = ""
    @State private var password = ""

    private var isValid: Bool { AuthValidation.isEmail(email) && !password.isEmpty }

    var body: some View {
        AuthScreen(title: "Log in") {
            AuthTextField(title: "Email", text: $email, contentType: .username, keyboard: .emailAddress)
            PasswordField(title: "Password", text: $password)
            HStack {
                Spacer()
                Button {
                    path.append(.forgotPassword(email: email))
                } label: {
                    Text("Forgot password?")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            AuthErrorMessage()
            PrimaryButton(title: "Log in", busy: auth.isWorking) {
                await auth.logIn(email: email, password: password)
            }
            .disabled(!isValid)
        }
        .onAppear { auth.errorMessage = nil }
    }
}

#Preview("Log in") {
    NavigationStack {
        LogInView(path: .constant([]))
    }
    .environmentObject(AuthService.preview(signedIn: false))
}
