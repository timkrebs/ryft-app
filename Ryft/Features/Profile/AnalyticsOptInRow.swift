import SwiftUI

/// Profile → Privacy → "Share usage analytics" (analytics ui.md). Only where it means something
/// (`Analytics.showsToggle`): where the prompt could show, and always while opted in, so it can be withdrawn.
struct AnalyticsOptInRow: View {
    @Environment(\.appEnvironment) private var env

    var body: some View {
        let analytics = env.analytics
        if analytics.showsToggle {
            AnalyticsOptInToggle(isOn: Binding(get: { analytics.optIn == .optedIn },
                                               set: { analytics.setOptIn($0) }))
        }
    }
}

/// The switch itself, a grouped toggle row like Demo data's: off stops sending at once and resets the random ID.
struct AnalyticsOptInToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        GroupedRow.toggle(Text("Share usage analytics"),
                          detail: Text("Screens used and errors shown. No health data. Turning it off stops sending now and resets your random ID."),
                          identifier: ProfileRow.analytics.identifier, isOn: $isOn)
            .accessibilityHint(Text("Uses a random ID, never your account. Turning it off resets it."))
    }
}

#if DEBUG
/// `-RyftScreen analytics-row`: the switch in Profile's Privacy card, working, for a capture (phase 1 shows it to
/// nobody: the no-op sink can't send).
struct AnalyticsOptInRowCapture: View {
    @State private var isOn = false

    var body: some View {
        ScrollView {
            PrivacyCardPreview { AnalyticsOptInToggle(isOn: $isOn) }
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.vertical, 16)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
#endif

/// Profile's Privacy group around the row (Nocturne: consent, Withdraw, then this row), for the previews.
private struct PrivacyCardPreview<Row: View>: View {
    @ViewBuilder var row: () -> Row

    var body: some View {
        GroupedCard(ProfileGroup.privacy.title) {
            GroupedRow.value(Text("Health-data consent"), value: Text(verbatim: "Agreed"))
            GroupedRow.destructive(Text("Withdraw consent")) {}
            row()
        }
    }
}

#Preview("Profile · Privacy · analytics off · dark") {
    DarkPreview {
        PrivacyCardPreview { AnalyticsOptInToggle(isOn: .constant(false)) }
    }
}

#Preview("Profile · Privacy · analytics on · dark") {
    DarkPreview {
        PrivacyCardPreview { AnalyticsOptInToggle(isOn: .constant(true)) }
    }
}

#Preview("Profile · Privacy · flag off · dark") {
    // The preview graph's sink can't send and the flag is off: the row isn't there.
    DarkPreview {
        PrivacyCardPreview { AnalyticsOptInRow() }
    }
    .environment(\.appEnvironment, .preview())
}
