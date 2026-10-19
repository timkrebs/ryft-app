import SwiftUI
import UIKit

/// After sign-in, once per account: what RYFT reads from Apple Health, why, and
/// where it goes — then the system's permission sheet. Declining keeps the app
/// usable (empty states, Profile → Data → Allow access).
struct HealthPermissionView: View {
    @EnvironmentObject private var settings: Settings
    @State private var asking = false
    @State private var legal: LegalPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                    .padding(.top, 32)
                Text("Connect Apple Health")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("RYFT turns what your watch writes to Apple Health into recovery, strain and sleep scores.")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    point("waveform.path.ecg", "What RYFT reads",
                          "Heart rate, HRV, resting heart rate, breathing rate, blood oxygen, VO₂ max, steps, active energy, sleep and workouts. RYFT never writes to Apple Health.")
                    point("server.rack", "Where it goes",
                          "To your RYFT account, where the scores are calculated. Never used for advertising, never sold.")
                    point("hand.raised", "You decide",
                          "Choose the data types on the next screen. You can change them later in the Health app, and delete your account and data in Profile.")
                }
                Button {
                    legal = .privacy
                } label: {
                    Text("Privacy Policy")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 12)
                VStack(spacing: 10) {
                    Button {
                        Task {
                            asking = true
                            try? await HealthKitManager.shared.requestAuthorization()
                            asking = false
                            settings.healthIntroDone = true
                        }
                    } label: {
                        if asking { ProgressView().tint(Theme.onAccent) } else { Text("Continue") }
                    }
                    .buttonStyle(TealButtonStyle())
                    .disabled(asking)
                    .accessibilityIdentifier("health.continue")
                    Button("Not now") { settings.healthIntroDone = true }
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("health.notNow")
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding + 4)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .safariSheet($legal)
    }

    private func point(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ryft(.headline)).foregroundStyle(Theme.textPrimary)
                Text(text).font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Empty state when there's no Health data: Health access may be off, or the
/// watch isn't writing to Apple Health. HealthKit never tells an app which.
struct HealthAccessHint: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("No Health data yet", systemImage: "heart.text.square")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                Text("RYFT needs Apple Health access, and your watch app writing to Apple Health (Garmin Connect → More → Settings → Apple Health). Check RYFT's access in Health → your profile → Apps → RYFT.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    HealthLinks.open(with: openURL)
                } label: {
                    Text("Open Health")
                }
                .buttonStyle(TealButtonStyle(prominent: false))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

enum HealthLinks {
    /// The Health app (its Apps list holds RYFT's permissions); Settings if Health is missing.
    @MainActor
    static func open(with openURL: OpenURLAction) {
        if let health = URL(string: "x-apple-health://"), UIApplication.shared.canOpenURL(health) {
            openURL(health)
        } else if let settings = URL(string: UIApplication.openSettingsURLString) {
            openURL(settings)
        }
    }
}

#Preview("Connect Apple Health · dark") {
    HealthPermissionView()
        .environmentObject(Settings.shared)
        .preferredColorScheme(.dark)
}

#Preview("Connect Apple Health · light") {
    HealthPermissionView()
        .environmentObject(Settings.shared)
        .preferredColorScheme(.light)
}

#Preview("Health hint", traits: .sizeThatFitsLayout) {
    SchemePair { HealthAccessHint() }
}
