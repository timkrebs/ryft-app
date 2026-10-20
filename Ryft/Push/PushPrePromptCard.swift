import SwiftUI

/// Today, after the first sync: one sentence before iOS asks. "Not now" is
/// remembered per user; the question returns once, after 14 days.
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
                HStack(spacing: 12) {
                    Button(action: enable) {
                        Text("Allow")
                    }
                    .buttonStyle(TealButtonStyle(prominent: true))
                    Button(action: dismiss) {
                        Text("Not now")
                    }
                    .buttonStyle(TealButtonStyle(prominent: false))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("Push pre-prompt · dark", traits: .sizeThatFitsLayout) {
    PushPrePromptCard(enable: {}, dismiss: {})
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("Push pre-prompt · light", traits: .sizeThatFitsLayout) {
    PushPrePromptCard(enable: {}, dismiss: {})
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.light)
}
