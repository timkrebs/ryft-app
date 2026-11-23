import SwiftUI

/// Today, after the first sync: one sentence before iOS asks. "Not now" is
/// remembered per user; the question returns once, after 14 days.
///
/// Nocturne (gate G1, design.md §1.2): "Allow" is the primary pill (full width, the forward arrow); "Not now" is the
/// onboarding steps' quiet action under it (`LaterButton`): a deferral, not a refusal, so it is not a second pill.
struct PushPrePromptCard: View {
    let enable: () -> Void
    let dismiss: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Get your recovery each morning", systemImage: "bell.badge")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                PushAskButtons(identifier: "push", enable: enable, dismiss: dismiss)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The push question's two answers on Today's card: "Allow" as the primary
/// pill, "Not now" as the quiet text action 4 under it (`OnboardingSpec.quietGap`). Identifiers `<identifier>.allow` and
/// `<identifier>.notNow`.
struct PushAskButtons: View {
    let identifier: String
    let enable: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: OnboardingSpec.quietGap) {
            PillButton(Text("Allow"), action: enable)
                .accessibilityIdentifier("\(identifier).allow")
            LaterButton(title: "Not now", action: dismiss)
                .accessibilityIdentifier("\(identifier).notNow")
        }
    }
}

#Preview("Push pre-prompt · dark", traits: .sizeThatFitsLayout) {
    DarkPreview {
        PushPrePromptCard(enable: {}, dismiss: {})
    }
}

#Preview("Push pre-prompt · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        PushPrePromptCard(enable: {}, dismiss: {})
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
