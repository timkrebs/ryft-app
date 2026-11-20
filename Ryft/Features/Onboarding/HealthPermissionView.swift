import GameplayKit
import Observation
import SwiftUI
import UIKit

// MARK: - Apple Health

/// After sign-in, once per account: what RYFT reads from Apple Health, why, and
/// where it goes — then the system's permission sheet. Declining keeps the app
/// usable (empty states, Profile → Data → Allow access).
struct HealthPermissionView: View {
    @Environment(\.appEnvironment) private var env

    var body: some View {
        HealthPermissionScreen(model: HealthOnboardingViewModel(env: env))
    }
}

/// "Connect Apple Health" as a state machine (`HealthOnboardingMachine`): explain →
/// requesting → granted → firstSync, or denied ("Not now", or the request failed).
/// Both ends mark the intro as done; RootView then shows the tabs and the first sync starts.
@MainActor
@Observable
final class HealthOnboardingViewModel {
    private let env: AppEnvironment
    private(set) var phase: HealthOnboardingPhase = .explain
    @ObservationIgnored private var machine: GKTableMachine<HealthOnboardingPhase>!

    init(env: AppEnvironment) {
        self.env = env
        machine = HealthOnboardingMachine.make { [weak self] to, _ in
            self?.phase = to
            if to == .denied || to == .firstSync { self?.env.settings.healthIntroDone = true }
        }
    }

    var isRequesting: Bool { phase == .requesting }

    /// The system sheet. HealthKit never says what was allowed for reading, only that it was answered.
    func connect() async {
        guard machine.enter(.requesting) else { return }
        do {
            env.analytics.track(.healthAccessRequested)
            try await env.health.requestAuthorization()
            let answered = await env.health.accessStatus() != .notAsked
            machine.enter(answered ? .granted : .denied)
        } catch {
            machine.enter(.denied)
        }
        if phase == .granted { machine.enter(.firstSync) }
    }

    func notNow() { machine.enter(.denied) }
}

private struct HealthPermissionScreen: View {
    @State var model: HealthOnboardingViewModel
    @State private var legal: LegalPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HealthIllustration()
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
                          "Heart rate, HRV, resting heart rate, breathing rate, blood oxygen, VO₂ max, steps, active energy, sleep and workouts. RYFT writes nothing to Apple Health unless you turn on saving strength workouts.")
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
                        Task { await model.connect() }
                    } label: {
                        if model.isRequesting { ProgressView().tint(Theme.onAccent) } else { Text("Continue") }
                    }
                    .buttonStyle(TealButtonStyle())
                    .disabled(model.isRequesting)
                    .accessibilityIdentifier("health.continue")
                    Button("Not now") { model.notNow() }
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
        .environment(Settings.shared)
        .preferredColorScheme(.dark)
}

#Preview("Connect Apple Health · light") {
    HealthPermissionView()
        .environment(Settings.shared)
        .preferredColorScheme(.light)
}
