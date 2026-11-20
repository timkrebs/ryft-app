import SwiftUI

/// After a reset link (`.recovery`, presented by RootView) or from
/// Profile → Change password (`.change`). `updateUser(password:)`. Nocturne (PR 6 A §A-6): a sheet with its own header
/// (the title, "Cancel" as the close circle), one field, the length hint (or "Password saved." once it is), the banner and
/// "Save password" (busy while it works: the pill's spinner, the title stays). Saved closes the sheet after 0.8 s.
struct SetNewPasswordView: View {
    enum Mode { case recovery, change }

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var env
    let mode: Mode
    /// Previews and shots: the busy state, which `AuthService` only enters during a request.
    var showsBusy = false

    @State private var password = ""
    @State private var saved = false
    @FocusState private var focus: AuthField?

    private var isBusy: Bool { auth.isWorking || showsBusy }

    var body: some View {
        AuthScreen(title: mode == .recovery ? Text("Set new password") : Text("Change password"),
                   lead: mode == .recovery ? Text("Choose a new password for your RYFT account.") : nil,
                   navigation: .close(label: Text("Cancel"), .perform(cancel)), isSheet: true) {
            GroupedCard {
                PasswordField(title: "New password", text: $password, focus: $focus, isNew: true) {
                    if canSave { Task { await save() } }
                }
            }
            .disabled(isBusy || saved)
            if saved {
                Label {
                    Text("Password saved.")
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: SetNewPasswordSpec.savedGlyph, weight: .regular))
                }
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, AuthScreenSpec.hintInset)
                .padding(.top, AuthScreenSpec.hintGap)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("newPassword.saved")
            } else {
                AuthHint(text: Text("At least \(AuthService.minimumPasswordLength) characters."))
            }
            if auth.errorMessage != nil {
                AuthErrorMessage()
                    .padding(.top, AuthScreenSpec.primaryGap)
            }
            PillButton(Text("Save password"), systemImage: PillButton.Icon.confirm, busy: isBusy) {
                await save()
            }
            .disabled(!canSave)
            .padding(.top, auth.errorMessage == nil ? AuthScreenSpec.primaryGap : AuthScreenSpec.actionGap)
            .accessibilityIdentifier("newPassword.save")
        }
        .onAppear { auth.errorMessage = nil }
        .authFocus($focus, on: .password, clock: env.clock)
    }

    private var canSave: Bool { AuthValidation.isPassword(password) && !saved }

    private func save() async {
        guard canSave, !isBusy else { return }
        if await auth.updatePassword(password) {
            focus = nil
            saved = true
            AccessibilityNotification.Announcement(String(localized: "Password saved.")).post()
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        }
    }

    private func cancel() {
        auth.needsNewPassword = false
        dismiss()
    }
}

/// Set new password's numbers (A §A-6).
enum SetNewPasswordSpec {
    /// "Password saved.": its checkmark, 17 pt in ink, in place of the hint.
    static let savedGlyph: CGFloat = 17
}

#Preview("Set new password") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SetNewPasswordView(mode: .recovery).presentedRoot()
        }
        .environment(AuthService.preview())
        .preferredColorScheme(.dark)
}

#Preview("Change password · busy · AX3") {
    SetNewPasswordView(mode: .change, showsBusy: true)
        .environment(AuthService.preview())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
