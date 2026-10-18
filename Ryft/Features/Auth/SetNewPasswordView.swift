import SwiftUI

/// After a reset link (`.recovery`, presented by RootView) or from
/// Profile → Change password (`.change`). `updateUser(password:)`.
struct SetNewPasswordView: View {
    enum Mode { case recovery, change }

    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var password = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            AuthScreen(title: mode == .recovery ? "Set new password" : "Change password",
                       subtitle: mode == .recovery ? "Choose a new password for your RYFT account." : nil) {
                PasswordField(title: "New password", text: $password, isNew: true,
                              hint: "At least \(AuthService.minimumPasswordLength) characters.")
                AuthErrorMessage()
                if saved {
                    Label("Password saved.", systemImage: "checkmark.circle.fill")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                }
                PrimaryButton(title: "Save password", busy: auth.isWorking) {
                    if await auth.updatePassword(password) {
                        saved = true
                        try? await Task.sleep(for: .seconds(0.8))
                        dismiss()
                    }
                }
                .disabled(!AuthValidation.isPassword(password) || saved)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        auth.needsNewPassword = false
                        dismiss()
                    }
                }
            }
        }
        .onAppear { auth.errorMessage = nil }
    }
}

#Preview("Set new password") {
    SetNewPasswordView(mode: .recovery)
        .environmentObject(AuthService.preview())
}
