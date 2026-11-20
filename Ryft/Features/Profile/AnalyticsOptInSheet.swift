import SwiftUI

/// "Share usage analytics?" (analytics ui.md): once, over the tabs, after the onboarding. Two equal
/// buttons; a swipe down is "Don't share". Any answer holds until sign-out; Profile → Privacy changes it.
struct AnalyticsOptInSheet: View {
    /// `true`: share. The sheet's presenter records it (`Analytics.setOptIn`).
    let answer: (Bool) -> Void

    var body: some View {
        OnboardingScreen(symbol: "chart.bar",
                         title: "Share usage analytics?",
                         text: "This is separate from your health-data consent. It stays off unless you say yes.") {
            VStack(alignment: .leading, spacing: 14) {
                ConsentPoint(symbol: "square.grid.2x2",
                             text: "Which screens and features are used, onboarding progress, and errors shown, with their status codes.",
                             symbolColor: Theme.textSecondary)
                ConsentPoint(symbol: "heart.slash",
                             text: "No health data, scores, sleep or workout details, names or free text.",
                             symbolColor: Theme.textSecondary)
                ConsentPoint(symbol: "number",
                             text: "A random ID for this install. Never your account or email.",
                             symbolColor: Theme.textSecondary)
                ConsentPoint(symbol: "hand.raised",
                             text: "Not used for tracking or ads. Sent to PostHog, in the EU.",
                             symbolColor: Theme.textSecondary)
            }
            Text("Change this any time in Profile → Privacy.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                PrimaryButton(title: "Share usage analytics", style: .secondary) { answer(true) }
                    .accessibilityIdentifier("analytics.share")
                PrimaryButton(title: "Don't share", style: .secondary) { answer(false) }
                    .accessibilityIdentifier("analytics.decline")
            }
        }
    }
}

extension View {
    /// The analytics prompt over the tabs, whenever `Analytics.showsPrompt` and nothing else of RootView's is up
    /// (`blocked`: a gate sheet, the workout, the import, the account hint, a new password). Taken away for one of
    /// those, it comes back after; only a swipe or a button is an answer.
    func analyticsOptInPrompt(blocked: Bool) -> some View {
        modifier(AnalyticsOptInPrompt(blocked: blocked))
    }
}

private struct AnalyticsOptInPrompt: ViewModifier {
    let blocked: Bool
    @Environment(\.appEnvironment) private var env
    @State private var presented = false
    /// Dismissed by us (an answer, or something else came up): not a swipe.
    @State private var withdrawn = false

    func body(content: Content) -> some View {
        let analytics = env.analytics
        content
            .sheet(isPresented: $presented, onDismiss: {
                // A swipe down: "Don't share". Not when the prompt went away under it (a sign-out's `accountLeft`):
                // that would answer for whoever signs in next.
                if !withdrawn, analytics.optIn == nil, analytics.showsPrompt { analytics.setOptIn(false) }
                withdrawn = false
            }) {
                AnalyticsOptInSheet { analytics.setOptIn($0) }
                    .presentedRoot()
            }
            .onChange(of: analytics.showsPrompt && !blocked, initial: true) { _, shows in
                if shows {
                    presented = true
                } else if presented {
                    withdrawn = true
                    presented = false
                }
            }
    }
}

#Preview("Analytics prompt · dark") {
    AnalyticsOptInSheet { _ in }
        .preferredColorScheme(.dark)
}

#Preview("Analytics prompt · AX5") {
    AnalyticsOptInSheet { _ in }
        .dynamicTypeSize(.accessibility5)
        .preferredColorScheme(.dark)
}

#Preview("Analytics prompt · AX3") {
    AnalyticsOptInSheet { _ in }
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}
