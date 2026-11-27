import SwiftUI

/// "Share usage analytics?" (analytics ui.md; decision B, docs/work/2026-11-22-analytics-sdk/plan.md; Nocturne: the gate's D2,
/// docs/work/2026-11-20-nocturne-gate/design.md §2.2): a full-screen onboarding step of its own on the account's first run, after
/// "What do you wear?" and before Apple Health (`OnboardingCoordinator.showsAnalyticsStep`). Never part of the health-data consent.
/// The first run's frame (the lock-up, the title, the lead), one card of four titled `OnboardingPoint`s, the footnote, and two equal
/// outline pills: no primary, nothing pre-selected, no symbol, nothing teal. Pinned below the accessibility sizes, so both answers are
/// always on screen; from AX1 they end the page (a bar of two wrapped pills would cover most of it). No sheet, so no swipe: only a
/// button answers, and "Not now" is an answer (`Analytics.setOptIn(false)`), so the step never comes back. Any answer holds until
/// sign-out; Profile → Privacy changes it.
struct AnalyticsOptInStepView: View {
    @Environment(\.appEnvironment) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var legal: LegalPage?

    /// Where the policy in force is published (`OnboardingCoordinator.policyPage`'s rule), else the bundled address.
    private var policyPage: LegalPage {
        env.consent.policyURL.flatMap(URL.init(string:)).flatMap(LegalPage.init(url:)) ?? .privacy
    }

    var body: some View {
        let inline = typeSize.isAccessibilitySize
        let analytics = env.analytics
        // One page whatever the size, the answers placed by a conditional: a text-size change across AX1 moves them and
        // keeps the page (and its scroll position). Two branches would be two views, and the page would start again.
        page(answersInline: inline, analytics: analytics)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !inline { PinnedActionBar { answers(analytics) } }
            }
            .safariSheet($legal)
    }

    private func page(answersInline: Bool, analytics: Analytics) -> some View {
        OnboardingScreen(title: Text("Share usage analytics?"),
                         lead: Text("This is separate from your health-data consent. It stays off unless you say yes."),
                         showsLockup: true, dismissible: false) {
            GroupedCard {
                OnboardingPoint(symbol: "square.grid.2x2", title: "What is counted",
                                // swiftlint:disable:next line_length
                                text: "Which screens and features are used, including food search, food logging and Sync now, with counts and timings as ranges; onboarding progress; errors shown with their status codes; and when the app is installed, opened or closed, with the app and iOS version and the device type.")
                OnboardingPoint(symbol: "heart.slash", title: "What is not",
                                text: "No health data, scores, sleep or workout details, foods or what you search for, names or free text.")
                OnboardingPoint(symbol: "number", title: "Your ID",
                                text: "A random ID for this install. Never your account or email.")
                OnboardingPoint(symbol: "hand.raised", title: "Where it goes",
                                text: "Not used for tracking or ads. Sent to PostHog, in the EU.")
            }
            Text("Change this any time in Profile → Privacy.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, OnboardingSpec.actionGap)
            // Art. 13: the policy, in the page (never the bar), the consent step's link; the in-app Safari sheet opens it.
            Button { legal = policyPage } label: { Text("Privacy Policy") }
                .ryftLink()
                .accessibilityIdentifier("analytics.policy")
            if answersInline {
                answers(analytics)
                    .padding(.top, OnboardingSpec.primaryGap)
            }
        }
    }

    /// Share, then Not now: the same outline pill, the same size, `PinnedBarSpec.spacing` apart. A consent is not a funnel.
    private func answers(_ analytics: Analytics) -> some View {
        VStack(spacing: PinnedBarSpec.spacing) {
            PillButton(Text("Share usage analytics"), style: .secondary) { analytics.setOptIn(true) }
                .accessibilityIdentifier("analytics.share")
            PillButton(Text("Not now"), style: .secondary) { analytics.setOptIn(false) }
                .accessibilityIdentifier("analytics.decline")
        }
    }
}

/// The step as RootView shows it: full screen, on a graph of its own, so an answer here goes nowhere (the previews and
/// `-RyftScreen analytics-prompt`).
struct AnalyticsStepPreview: View {
    var typeSize: DynamicTypeSize = .large
    @State private var env = AppEnvironment.preview()

    var body: some View {
        AnalyticsOptInStepView()
            .environment(\.appEnvironment, env)
            .dynamicTypeSize(typeSize)
            .preferredColorScheme(.dark)
    }
}

#Preview("Analytics step · dark") { AnalyticsStepPreview() }
#Preview("Analytics step · AX3") { AnalyticsStepPreview(typeSize: .accessibility3) }
#Preview("Analytics step · AX5") { AnalyticsStepPreview(typeSize: .accessibility5) }
