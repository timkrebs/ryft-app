import SwiftUI

// MARK: - account hint

/// `User.account_hint`: this account is new, and this iPhone synced another one
/// recently. Probably the same person signed in another way (Apple vs. email). Nocturne (PR 6 A §A-13): a sheet that must
/// be answered (no swipe down): the title, the text, "Use the other account", "Continue with this one", the support line.
/// At accessibility sizes it opens full height and scrolls.
struct AccountHintSheet: View {
    let hint: AccountHint
    let keep: () -> Void
    let useOther: () async -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

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
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeaderTitle(text: Text("This is a new RYFT account"))
                Text(text)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AccountHintSpec.textGap)
                PillButton(Text("Use the other account")) { await useOther() }
                    .padding(.top, AccountHintSpec.actionsGap)
                    .accessibilityIdentifier("hint.useOther")
                PillButton(Text("Continue with this one"), style: .secondary) { keep() }
                    .padding(.top, AccountHintSpec.buttonGap)
                    .accessibilityIdentifier("hint.keep")
                // Plain text: the address is for reading out, not a link (the domain chore owns its spelling).
                Text("Data in both accounts? Support can merge them: ryftapp.de/support")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AccountHintSpec.captionGap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: AccountHintSpec.maxWidth)
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.top, AccountHintSpec.topInset)
            .padding(.bottom, AccountHintSpec.bottomPadding)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .presentationBackground(Theme.background)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }
}

/// The account hint's numbers (A §A-13).
enum AccountHintSpec {
    /// The title starts 24 below the grabber: the grabber's 12 from the sheet's edge, then 24.
    static let topInset: CGFloat = 36
    /// The title → the text 12, the text → the primary 24, the primary → the outline 12, the outline → the caption 16.
    static let textGap: CGFloat = 12, actionsGap: CGFloat = 24, buttonGap: CGFloat = 12, captionGap: CGFloat = 16
    static let bottomPadding: CGFloat = 24
    static let maxWidth: CGFloat = 480
}

#Preview("Account hint · email") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AccountHintSheet(hint: AccountHint(kind: "other_account_on_device", otherProvider: "email",
                                               otherLastSync: .now.addingTimeInterval(-86_400)),
                             keep: {}, useOther: {})
        }
        .preferredColorScheme(.dark)
}

#Preview("Account hint · Apple · AX3") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AccountHintSheet(hint: AccountHint(kind: "other_account_on_device", otherProvider: "apple",
                                               otherLastSync: .now.addingTimeInterval(-86_400)),
                             keep: {}, useOther: {})
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
