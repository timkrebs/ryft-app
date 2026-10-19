import SwiftUI

/// After sign-up (email confirmation on) or a reset request. The link opens
/// the app through `ryft://auth/callback` and completes the session there.
struct CheckInboxView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let reason: InboxReason
    let email: String

    @State private var resent = false

    var body: some View {
        AuthScreen(title: "Check your inbox", subtitle: subtitle) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityHidden(true)
            Text("Open the link on this iPhone. It's valid for an hour.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Open Mail") {
                if let mail = URL(string: "message://") { openURL(mail) }
            }
            PrimaryButton(title: resent ? "Sent again" : "Resend", style: .secondary, busy: auth.isWorking) {
                let ok: Bool
                switch reason {
                case .confirmSignUp: ok = await auth.resendConfirmation(email: email)
                case .resetPassword: ok = await auth.sendPasswordReset(email: email)
                }
                resent = ok
            }
            .disabled(resent)
            // Back to the form, where the address can be corrected.
            Button("Use another email") { dismiss() }
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
            AuthErrorMessage()
        }
        .onAppear { auth.errorMessage = nil }
    }

    private var subtitle: LocalizedStringKey {
        switch reason {
        case .confirmSignUp: return "We sent a confirmation link to \(email)."
        case .resetPassword: return "If \(email) has a RYFT account, we sent it a link to set a new password."
        }
    }
}

#Preview("Check your inbox · dark") {
    NavigationStack {
        CheckInboxView(reason: .confirmSignUp, email: "tim@example.com")
    }
    .environmentObject(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
}

#Preview("Check your inbox · light") {
    NavigationStack {
        CheckInboxView(reason: .resetPassword, email: "tim@example.com")
    }
    .environmentObject(AuthService.preview(signedIn: false))
    .preferredColorScheme(.light)
}
