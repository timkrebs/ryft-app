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
    /// Previews and tests: the busy state, which the model only enters while the system sheet is up.
    var showsBusy = false

    var body: some View {
        HealthPermissionScreen(model: HealthOnboardingViewModel(env: env), showsBusy: showsBusy)
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
            try await env.health.requestAuthorization(.core)
            let answered = await env.health.accessStatus(.core) != .notAsked
            machine.enter(answered ? .granted : .denied)
        } catch {
            machine.enter(.denied)
        }
        if phase == .granted { machine.enter(.firstSync) }
    }

    func notNow() { machine.enter(.denied) }
}

/// Nocturne (PR 6 A §A-10): the lock-up row, the 72 pt outline mark (its pulse drawn once), the title, the lead, the three
/// points as a card and the policy link; Continue (busy while the system sheet is up: the pill's spinner, the title stays) and
/// Not now pinned under the page.
private struct HealthPermissionScreen: View {
    @State var model: HealthOnboardingViewModel
    let showsBusy: Bool
    @State private var legal: LegalPage?

    private var isBusy: Bool { model.isRequesting || showsBusy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Decoration: VoiceOver starts at the title, the first heading.
                WordmarkLockup()
                    .frame(height: OnboardingSpec.headerHeight)
                    .accessibilityHidden(true)
                HealthIllustration()
                    .padding(.top, OnboardingSpec.titleGap)
                ScreenHeaderTitle(text: Text("Connect Apple Health"))
                    .padding(.top, HealthPermissionSpec.titleGap)
                Text("RYFT turns what your watch writes to Apple Health into recovery, strain and sleep scores.")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, OnboardingSpec.leadGap)
                GroupedCard {
                    OnboardingPoint(symbol: "waveform.path.ecg", title: "What RYFT reads",
                                    text: "Heart rate, HRV, resting heart rate, breathing rate, blood oxygen, VO₂ max, steps, active energy, sleep and workouts. RYFT writes nothing to Apple Health unless you turn on saving strength workouts.")
                    OnboardingPoint(symbol: "server.rack", title: "Where it goes",
                                    text: "To your RYFT account, where the scores are calculated. Never used for advertising, never sold.")
                    OnboardingPoint(symbol: "hand.raised", title: "You decide",
                                    text: "Choose the data types on the next screen. You can change them later in the Health app, and delete your account and data in Profile.")
                }
                .padding(.top, HealthPermissionSpec.pointsGap)
                Button { legal = .privacy } label: { Text("Privacy Policy") }
                    .ryftLink()
                    .padding(.top, HealthPermissionSpec.linkGap)
                    .accessibilityIdentifier("health.privacy")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: OnboardingSpec.maxWidth)
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, OnboardingSpec.bottomPadding)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .pinnedBar {
            PillButton(Text("Continue"), busy: isBusy) {
                await model.connect()
            }
            .accessibilityIdentifier("health.continue")
            LaterButton(title: "Not now") { model.notNow() }
                .disabled(isBusy)
                .accessibilityIdentifier("health.notNow")
        }
        .safariSheet($legal)
    }
}

/// Connect Apple Health's numbers (A §A-10); the frame is the onboarding steps' (`OnboardingSpec`).
enum HealthPermissionSpec {
    /// The mark → the title 20; the lead → the points 20; the card → the policy link 4.
    static let titleGap: CGFloat = 20, pointsGap: CGFloat = 20, linkGap: CGFloat = 4
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

// Dark only (NOCTURNE_STYLE §1).
#Preview("Connect Apple Health") {
    HealthPermissionView()
        .environment(Settings.shared)
        .preferredColorScheme(.dark)
}

#Preview("Connect Apple Health · busy") {
    HealthPermissionView(showsBusy: true)
        .environment(Settings.shared)
        .preferredColorScheme(.dark)
}

#Preview("Connect Apple Health · AX3") {
    HealthPermissionView()
        .environment(Settings.shared)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
