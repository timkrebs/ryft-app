import SwiftUI

// MARK: - account hint

/// `User.account_hint`: this account is new, and this iPhone synced another one
/// recently. Probably the same person signed in another way (Apple vs. email).
struct AccountHintSheet: View {
    let hint: AccountHint
    let keep: () -> Void
    let useOther: () async -> Void

    private var text: String {
        let last = Fmt.date(hint.otherLastSync)
        switch hint.otherProvider {
        case "email":
            return String(localized: "This iPhone synced another RYFT account until \(last), one you logged in to with email. If that was you, log out and log in with email. You can then add Sign in with Apple to it in Profile.")
        case "apple":
            return String(localized: "This iPhone synced another RYFT account until \(last), one you opened with Sign in with Apple. If that was you, log out and continue with Apple.")
        default:
            return String(localized: "This iPhone synced another RYFT account until \(last). If that was you, log out and sign in the way you did then.")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "person.2")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 28)
                    .accessibilityHidden(true)
                Text("This is a new RYFT account")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Use the other account") { await useOther() }
                    .accessibilityIdentifier("hint.useOther")
                PrimaryButton(title: "Continue with this one", style: .secondary) { keep() }
                    .accessibilityIdentifier("hint.keep")
                Text("Data in both accounts? Support can merge them: ryftapp.de/support")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding + 4)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}

#Preview("Account hint · dark") {
    AccountHintSheet(hint: AccountHint(kind: "other_account_on_device", otherProvider: "email",
                                       otherLastSync: .now.addingTimeInterval(-86_400)),
                     keep: {}, useOther: {})
        .preferredColorScheme(.dark)
}

#Preview("Account hint · light") {
    AccountHintSheet(hint: AccountHint(kind: "other_account_on_device", otherProvider: "apple",
                                       otherLastSync: .now.addingTimeInterval(-86_400)),
                     keep: {}, useOther: {})
        .preferredColorScheme(.light)
}
