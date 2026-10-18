import SwiftUI

/// First screen without a session: brand, what RYFT does, Sign in with Apple.
/// Always on Graphite (dark), like the brand board. After sign-in RootView
/// switches to the tabs and bootstrap asks for HealthKit access.
struct OnboardingView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            BrandLockup()
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 22) {
                ValueLine(systemImage: "moon.fill", tint: Theme.stageREM, title: "Sleep",
                          text: "Stages, need and debt, every night.")
                ValueLine(systemImage: "heart.fill", tint: Theme.accent, title: "Recovery",
                          text: "HRV and resting heart rate against your own baseline.")
                ValueLine(systemImage: "bolt.fill", tint: Theme.warning, title: "Strain",
                          text: "Every workout on one 0–21 scale.")
            }
            .frame(maxWidth: 360, alignment: .leading)
            Spacer(minLength: 40)
            signIn
        }
        .padding(.horizontal, Theme.Metrics.screenPadding + 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var signIn: some View {
        VStack(spacing: 14) {
            if let problem = SupabaseConfig.problem {
                InlineMessage(message: problem, systemImage: "key")
            }
            AppleSignInButton()
                .disabled(!auth.isConfigured)
            if let error = auth.errorMessage {
                InlineMessage(message: error, systemImage: "exclamationmark.circle")
            }
            Text("Your data is stored in your own RYFT platform.")
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

private struct ValueLine: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .environmentObject(AuthService.preview(signedIn: false))
        .environmentObject(Settings.shared)
}
