import SwiftUI

/// Today, after the first sync: what RYFT would notify about, before iOS asks.
/// "Not now" hides it for good; Profile → Notifications can still turn push on.
struct PushPrePromptCard: View {
    let enable: () -> Void
    let dismiss: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Your score, when it's ready", systemImage: "bell.badge")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                Text("RYFT can tell you your recovery each morning, when a workout is scored or sets a record, and when your watch stopped syncing. Choose which in Profile → Notifications.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(action: enable) {
                        Text("Turn on")
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
