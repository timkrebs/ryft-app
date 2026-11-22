import SwiftUI

/// "Share usage analytics?" (analytics ui.md; Nocturne: the gate's D2, docs/work/2026-11-20-nocturne-gate/design.md §2.2): once,
/// over the tabs, after the onboarding. The Consent step's sibling: an `OnboardingScreen` sheet (the title, the lead), one card of
/// four titled `OnboardingPoint`s, the footnote, and two equal outline pills, no primary, no symbol, nothing teal. Pinned below the
/// accessibility sizes, so both answers are always on screen; from AX1 they end the page (a bar of two wrapped pills would cover
/// most of it). A swipe down is "Don't share". Any answer holds until sign-out; Profile → Privacy changes it.
struct AnalyticsOptInSheet: View {
    /// `true`: share. The sheet's presenter records it (`Analytics.setOptIn`).
    let answer: (Bool) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            page(answersInline: true)
        } else {
            page(answersInline: false)
                .pinnedBar { answers }
        }
    }

    private func page(answersInline: Bool) -> some View {
        OnboardingScreen(title: Text("Share usage analytics?"),
                         lead: Text("This is separate from your health-data consent. It stays off unless you say yes."),
                         showsLockup: false) {
            GroupedCard {
                OnboardingPoint(symbol: "square.grid.2x2", title: "What is counted",
                                text: "Which screens and features are used, onboarding progress, and errors shown, with their status codes.")
                OnboardingPoint(symbol: "heart.slash", title: "What is not",
                                text: "No health data, scores, sleep or workout details, names or free text.")
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
            if answersInline {
                answers
                    .padding(.top, OnboardingSpec.primaryGap)
            }
        }
    }

    /// Share, then Don't share: the same outline pill, the same size, `PinnedBarSpec.spacing` apart. A consent is not a funnel.
    private var answers: some View {
        VStack(spacing: PinnedBarSpec.spacing) {
            PillButton(Text("Share usage analytics"), style: .secondary) { answer(true) }
                .accessibilityIdentifier("analytics.share")
            PillButton(Text("Don't share"), style: .secondary) { answer(false) }
                .accessibilityIdentifier("analytics.decline")
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

/// The prompt as it is shown: a sheet over the tabs.
private struct AnalyticsPromptPreview: View {
    var typeSize: DynamicTypeSize = .large

    var body: some View {
        Theme.background
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                AnalyticsOptInSheet { _ in }
                    .dynamicTypeSize(typeSize)
                    .presentedRoot()
            }
            .preferredColorScheme(.dark)
    }
}

#Preview("Analytics prompt") { AnalyticsPromptPreview() }
#Preview("Analytics prompt · AX3") { AnalyticsPromptPreview(typeSize: .accessibility3) }
#Preview("Analytics prompt · AX5") { AnalyticsPromptPreview(typeSize: .accessibility5) }
