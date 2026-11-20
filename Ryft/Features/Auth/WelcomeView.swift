import SwiftUI

/// First screen without a session: brand, what RYFT does, and the ways in —
/// Continue with Apple (one tap), Create account, Log in. After sign-in RootView switches to the tabs
/// and bootstrap asks for HealthKit access. Nocturne (PR 6 A §A-1, F8, F9): the lock-up, three value lines with the metric
/// legend rings (violet, teal, blue), then the white Apple button, Create account as an outline, "Have an account? Log in"
/// and the privacy line, strongest at the bottom edge under the thumb.
struct WelcomeView: View {
    @State private var legal: LegalPage?
    @Environment(AuthService.self) private var auth
    @Environment(Settings.self) private var settings
    @Environment(\.appEnvironment) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var path: [AuthRoute] = []
    /// What's missing from this build's Supabase values (`SupabaseConfig.problem`); previews pass their own.
    var configProblem: String? = SupabaseConfig.problem

    var body: some View {
        NavigationStack(path: $path) {
            welcome
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .createAccount: CreateAccountView(path: $path)
                    case .logIn: LogInView(path: $path)
                    case .forgotPassword(let email): ForgotPasswordView(path: $path, email: email)
                    case .checkInbox(let reason, let email): CheckInboxView(reason: reason, email: email)
                    }
                }
        }
        .tint(Theme.textPrimary)
        .environment(\.colorScheme, .dark)
    }

    /// Where it fits (the default sizes), the first child lays it out as it always was: the spacers share what's left and
    /// the ways in sit at the bottom. Where it doesn't (the accessibility sizes, or a notice too many), the same content
    /// scrolls at its own height instead of being squeezed, so the privacy line wraps whole and its link stays reachable.
    private var welcome: some View {
        // Looked up once here: both children are built, and each lookup reads the activity store.
        let parked = ParkedActivitiesNotice.parkedToMention(in: env)
        return ViewThatFits(in: .vertical) {
            content(parked: parked)
            ScrollView { content(parked: parked) }
                .scrollIndicators(.hidden)
        }
        // No text field here, but popping back from Log in can arrive with the keyboard still up: a height shortened by it
        // would switch the two children mid-transition.
        .ignoresSafeArea(.keyboard)
        // Here, not on the privacy line: only one of the two children above is shown, and the sheet belongs to the screen.
        .safariSheet($legal)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { auth.errorMessage = nil }
    }

    private func content(parked: ParkedActivitiesNotice.Parked?) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: WelcomeSpec.minSpacer)
            BrandLockup()
            Spacer(minLength: WelcomeSpec.minSpacer)
            VStack(alignment: .leading, spacing: WelcomeSpec.lineSpacing) {
                ValueLine(tint: Theme.metricSleep, title: "Sleep",
                          text: "Stages, need and debt, every night.")
                ValueLine(tint: Theme.recovery, title: "Recovery",
                          text: "HRV and resting heart rate against your own baseline.")
                ValueLine(tint: Theme.metricStrain, title: "Strain",
                          text: "Every workout on one 0–21 scale.")
            }
            .frame(maxWidth: WelcomeSpec.linesMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: WelcomeSpec.minSpacer)
            actions(parked: parked)
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .padding(.bottom, WelcomeSpec.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The build has its Supabase values and AuthService a client.
    private var isConfigured: Bool { configProblem == nil && auth.isConfigured }

    private func actions(parked: ParkedActivitiesNotice.Parked?) -> some View {
        VStack(spacing: WelcomeSpec.actionSpacing) {
            // Banners first, so the reason is read before the ways in.
            if let problem = configProblem {
                InlineMessage(message: problem, systemImage: "key")
            }
            if let notice = auth.signOutNotice {
                InlineMessage(message: notice, systemImage: "person.crop.circle.badge.exclamationmark")
                    .accessibilityIdentifier("welcome.notice")
            }
            // Activities and nights a session expiry kept on this iPhone (design.md §8.4). Not behind
            // `activities.manual`: only an enabled feature parks rows, and signed out the flag reads its default.
            if let parked {
                ParkedActivitiesNotice(parked: parked) { env.activities.purgeParked() }
            }
            VStack(spacing: WelcomeSpec.actionSpacing) {
                AppleSignInButton()
                PillButton(Text("Create account"), style: .secondary) { path.append(.createAccount) }
                    .disabled(auth.isWorking)
                    .accessibilityIdentifier("welcome.createAccount")
                logIn
                    .disabled(auth.isWorking)
            }
            .disabled(!isConfigured)
            AuthErrorMessage()
            Text(inlineLinks: "Your data is stored on the RYFT platform. [Privacy Policy](https://ryftlab.de/privacy)")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            #if DEBUG
            Button {
                settings.apiKeyMode = true
            } label: {
                Text("Developer: use an API key")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .underline()
            }
            #endif
        }
        .frame(maxWidth: WelcomeSpec.actionsMaxWidth)
    }

    /// "Have an account? Log in": one button, 44 high; the question quiet, "Log in" in ink and underlined. At the
    /// accessibility sizes the two stack. Voice Control also takes "Log in".
    private var logIn: some View {
        Button {
            path.append(.logIn)
        } label: {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 0))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: WelcomeSpec.logInGap))
            layout {
                Text("Have an account?")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                Text("Log in")
                    .font(.ryft(.button))
                    .foregroundStyle(InlineLink.ink)
                    .underline(true, pattern: .solid, color: InlineLink.ink.opacity(InlineLink.underlineOpacity))
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityInputLabels([Text("Log in")])
        .accessibilityIdentifier("welcome.logIn")
    }
}

/// Welcome's numbers (A §A-1).
enum WelcomeSpec {
    /// The spacers between the lock-up, the value lines and the ways in share what's left; never under 32.
    static let minSpacer: CGFloat = 32
    /// Between two value lines; their column is at most 360 wide (it centres on a wide window).
    static let lineSpacing: CGFloat = 22, linesMaxWidth: CGFloat = 360
    /// The mark → the name, and the name → its sentence.
    static let markGap: CGFloat = 16, sentenceGap: CGFloat = 2
    /// The mark sits on the name's line, 1 pt lower than its centre.
    static let markDrop: CGFloat = 1
    /// Between the banners, the ways in and the privacy line; the ways in at most 480 wide.
    static let actionSpacing: CGFloat = 12, actionsMaxWidth: CGFloat = 480
    /// "Have an account?" → "Log in".
    static let logInGap: CGFloat = 6
    static let bottomPadding: CGFloat = 12
}

/// One value line: the metric's legend ring (`LegendMark`, its colour names the metric; no value), the name in 17 Medium
/// and one sentence in `textSecondary`. One VoiceOver element, the mark hidden.
private struct ValueLine: View {
    let tint: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .valueLineName, spacing: WelcomeSpec.markGap) {
            LegendMark(tint)
                .alignmentGuide(.valueLineName) { $0[VerticalAlignment.center] - WelcomeSpec.markDrop }
            VStack(alignment: .leading, spacing: WelcomeSpec.sentenceGap) {
                Text(title)
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .alignmentGuide(.valueLineName) { $0[VerticalAlignment.center] }
                Text(text)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension VerticalAlignment {
    /// A value line's name: the mark centres on it, not on the name and the sentence together.
    enum ValueLineName: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }

    static let valueLineName = VerticalAlignment(ValueLineName.self)
}

// Dark only (NOCTURNE_STYLE §1). The words in the file-waiting preview are RootView's (`importSignInNote`).
#Preview("Welcome") {
    WelcomeView()
        .environment(AuthService.preview(signedIn: false))
        .environment(Settings.shared)
}

/// Scrolls: the privacy line wraps whole under the ways in.
#Preview("Welcome · AX3") {
    WelcomeView()
        .environment(AuthService.preview(signedIn: false))
        .environment(Settings.shared)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Welcome · signed-out notice") {
    let auth = AuthService.preview(signedIn: false)
    auth.signOutNotice = AuthService.SignOutReason.sessionExpired.notice
    return WelcomeView()
        .environment(auth)
        .environment(Settings.shared)
}

#Preview("Welcome · parked activities") {
    let auth = AuthService.preview(signedIn: false)
    auth.signOutNotice = AuthService.SignOutReason.sessionExpired.notice
    return WelcomeView()
        .environment(auth)
        .environment(Settings.shared)
        .environment(\.appEnvironment, AppEnvironment.previewWithParkedRows())
}

/// A sign-in held over an owed wipe: the message under the ways in, derived from the hold, so `onAppear` doesn't clear it.
#Preview("Welcome · sign-in held") {
    WelcomeView()
        .environment(AuthService.previewHeld())
        .environment(Settings.shared)
}

/// The most it shows: an expiry's notice and its parked rows, then another account's sign-in held over them, at AX3.
/// The scrolling child.
#Preview("Welcome · sign-in held · parked · AX3") {
    let auth = AuthService.previewHeld()
    auth.signOutNotice = AuthService.SignOutReason.sessionExpired.notice
    return WelcomeView()
        .environment(auth)
        .environment(Settings.shared)
        .environment(\.appEnvironment, AppEnvironment.previewWithParkedRows())
        .dynamicTypeSize(.accessibility3)
}

#Preview("Welcome · file waiting") {
    WelcomeView()
        .safeAreaInset(edge: .top) {
            InlineMessage(message: "Your file is ready. Sign in to continue.", systemImage: "doc.text", announces: false)
                .padding(.horizontal, Theme.Metrics.screenPadding)
        }
        .environment(AuthService.preview(signedIn: false))
        .environment(Settings.shared)
}

#Preview("Welcome · not configured") {
    WelcomeView(configProblem: "Sign-in isn't set up in this build.")
        .environment(AuthService.preview(signedIn: false))
        .environment(Settings.shared)
}
