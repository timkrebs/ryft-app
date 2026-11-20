import Observation
import SwiftUI

/// After sign-up (email confirmation on) or a reset request. The link opens
/// the app through `ryft://auth/callback` and completes the session there. Nocturne (PR 6 A §A-5, D6A-12): a waiting state,
/// so the mark is an outline (a 72 pt circle with the envelope), then Open Mail, Resend and "Use another email".
struct CheckInboxView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let reason: InboxReason
    let email: String

    /// Resend's state; tests hand in one that is already sending.
    @State var resend = InboxResendModel()

    var body: some View {
        AuthScreen(title: Text("Check your inbox"), lead: lead) {
            EnvelopeMark()
                .frame(maxWidth: .infinity)
                .padding(.top, CheckInboxSpec.markGap - AuthScreenSpec.formGap)
                .padding(.bottom, CheckInboxSpec.markGap)
            Text("Open the link on this iPhone. It's valid for an hour.")
                .font(.ryft(.body))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PillButton(Text("Open Mail"), systemImage: PillButton.Icon.linkOut) {
                if let mail = URL(string: "message://") { openURL(mail) }
            }
            .padding(.top, 24)
            PillButton(resendTitle, style: .secondary, busy: resend.phase == .sending) {
                await resend.resend { await send() }
            }
            .disabled(resend.phase == .sent)
            .padding(.top, 12)
            .accessibilityIdentifier("checkInbox.resend")
            // Back to the form, where the address can be corrected.
            Button { dismiss() } label: { Text("Use another email") }
                .ryftLink()
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            if auth.errorMessage != nil {
                AuthErrorMessage()
                    .padding(.top, AuthScreenSpec.actionGap)
            }
        }
        .onAppear { auth.errorMessage = nil }
    }

    private var lead: Text {
        switch reason {
        case .confirmSignUp: return Text("We sent a confirmation link to \(email).")
        case .resetPassword: return Text("If \(email) has a RYFT account, we sent it a link to set a new password.")
        }
    }

    private var resendTitle: Text {
        switch resend.phase {
        // Busy keeps the title: the pill's spinner and VoiceOver's "In progress" say it is sending.
        case .idle, .sending: return Text("Resend")
        case .sent: return Text("Sent again")
        }
    }

    private func send() async -> Bool {
        switch reason {
        case .confirmSignUp: return await auth.resendConfirmation(email: email)
        case .resetPassword: return await auth.sendPasswordReset(email: email)
        }
    }
}

/// Check your inbox's numbers (A §A-5).
enum CheckInboxSpec {
    /// The outline: 72 pt, a 1 pt ink stroke at 16 % (the circle button's border), the envelope 26 Light in ink.
    static let markSide: CGFloat = 72
    static let glyphSize: CGFloat = 26
    /// Above and below the outline.
    static let markGap: CGFloat = 32
}

/// "Resend": idle → sending → sent ("Sent again", disabled until the screen is left), or back to idle when it failed (the
/// banner says why). Sent is announced: the pill's title changes where VoiceOver may not be.
@MainActor
@Observable
final class InboxResendModel {
    enum Phase: Equatable { case idle, sending, sent }

    private(set) var phase: Phase = .idle
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    init(announce: @escaping @MainActor (String) -> Void = InboxResendModel.post) {
        self.announce = announce
    }

    /// Sends once more through `send` (true: sent). A tap while sending or after it was sent does nothing.
    func resend(_ send: () async -> Bool) async {
        guard phase == .idle else { return }
        phase = .sending
        if await send() {
            phase = .sent
            announce(String(localized: "Sent again"))
        } else {
            phase = .idle
        }
    }

    static func post(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

/// The outline that stands for the waiting link: decoration, hidden from VoiceOver.
private struct EnvelopeMark: View {
    var body: some View {
        Image(systemName: "envelope")
            .font(.system(size: CheckInboxSpec.glyphSize, weight: .light))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: CheckInboxSpec.markSide, height: CheckInboxSpec.markSide)
            .overlay {
                Circle().strokeBorder(Theme.textPrimary.opacity(CircleButton.borderOpacity), lineWidth: Theme.Metrics.hairline)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Check your inbox") {
    NavigationStack {
        CheckInboxView(reason: .confirmSignUp, email: "alex@example.com")
    }
    .environment(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
}

#Preview("Check your inbox · reset · AX3") {
    NavigationStack {
        CheckInboxView(reason: .resetPassword, email: "alex@example.com")
    }
    .environment(AuthService.preview(signedIn: false))
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
