import SwiftUI

/// First screen without a session: brand, what RYFT does, and the ways in —
/// Continue with Apple (one tap), Create account, Log in. Always on Graphite
/// (dark), like the brand board. After sign-in RootView switches to the tabs
/// and bootstrap asks for HealthKit access.
struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var settings: Settings
    @State private var path: [AuthRoute] = []

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

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            BrandLockup()
            Spacer(minLength: 32)
            VStack(alignment: .leading, spacing: 22) {
                ValueLine(systemImage: "moon", title: "Sleep",
                          text: "Stages, need and debt, every night.")
                ValueLine(systemImage: "heart", title: "Recovery",
                          text: "HRV and resting heart rate against your own baseline.")
                ValueLine(systemImage: "bolt", title: "Strain",
                          text: "Every workout on one 0–21 scale.")
            }
            .frame(maxWidth: 360, alignment: .leading)
            Spacer(minLength: 32)
            actions
        }
        .padding(.horizontal, Theme.Metrics.screenPadding + 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { auth.errorMessage = nil }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let problem = SupabaseConfig.problem {
                InlineMessage(message: problem, systemImage: "key")
            }
            if let notice = auth.signOutNotice {
                InlineMessage(message: notice, systemImage: "person.crop.circle.badge.exclamationmark")
                    .accessibilityIdentifier("welcome.notice")
            }
            VStack(spacing: 12) {
                AppleSignInButton()
                PrimaryButton(title: "Create account", style: .secondary) { path.append(.createAccount) }
                Button {
                    path.append(.logIn)
                } label: {
                    Text("Log in")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .disabled(!auth.isConfigured)
            AuthErrorMessage()
            Text("Your data is stored on the RYFT platform.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
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
        .frame(maxWidth: 400)
    }
}

/// The board's value line: a teal glyph in an outlined circle, a tracked
/// uppercase label and one short sentence.
private struct ValueLine: View {
    let systemImage: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 46, height: 46)
                .overlay(Circle().stroke(Theme.accent.opacity(0.55), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .ryftLabelStyle(Theme.textPrimary)
                    .tracking(3)
                Text(text)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// Welcome is always dark (Graphite), so the light previews match the dark ones by design.
#Preview("Welcome") {
    WelcomeView()
        .environmentObject(AuthService.preview(signedIn: false))
        .environmentObject(Settings.shared)
}

#Preview("Welcome · light system") {
    WelcomeView()
        .environmentObject(AuthService.preview(signedIn: false))
        .environmentObject(Settings.shared)
        .preferredColorScheme(.light)
}
