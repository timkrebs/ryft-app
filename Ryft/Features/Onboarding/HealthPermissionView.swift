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
    /// The first run's step rule under the lock-up (nil after the first run).
    var progress: FirstRunProgress?

    var body: some View {
        HealthPermissionScreen(model: HealthOnboardingViewModel(env: env), showsBusy: showsBusy, progress: progress)
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

/// What the system sheet is about to ask, in words to match against it (first-run ui.md §3, G2): the lock-up row and the step
/// rule, the 72 pt outline mark (its pulse drawn once), the title and the lead; "On the next screen" (Tap Turn On All, then
/// Allow: a partial grant is invisible, HealthKit never reports a refused read, so this is the one place to prevent it); "The
/// ten kinds of data" in the Health app's own groups and names; the footnote and the policy link. Continue (busy while the
/// system sheet is up: the pill's spinner, the title stays) and Not now pinned under the page (from AX1 they end it).
private struct HealthPermissionScreen: View {
    @State var model: HealthOnboardingViewModel
    let showsBusy: Bool
    let progress: FirstRunProgress?
    @State private var legal: LegalPage?

    private var isBusy: Bool { model.isRequesting || showsBusy }

    var body: some View {
        OnboardingScreen(title: Text("Connect Apple Health"),
                         lead: Text("RYFT turns what your watch writes to Apple Health into recovery, strain and sleep scores."),
                         showsLockup: true, progress: progress) {
            HealthIllustration()
        } content: {
            GroupedCard(Text("On the next screen")) {
                OnboardingPoint(symbol: "switch.2", title: "Tap Turn On All",
                                text: "It is at the top of the list and switches on all ten kinds of data below.")
                OnboardingPoint(symbol: "checkmark.circle", title: "Then tap Allow",
                                text: "That is all RYFT needs. You can change any of them later in the Health app.")
            }
            // As the Health app groups and spells them, so each can be found on the sheet.
            GroupedCard(Text("The ten kinds of data")) {
                OnboardingPoint(symbol: "figure.walk", title: "Activity", text: "Active Energy, Steps, Workouts")
                OnboardingPoint(symbol: "heart", title: "Heart",
                                text: "Heart Rate, Heart Rate Variability, Resting Heart Rate, Cardio Fitness (VO₂ max)")
                OnboardingPoint(symbol: "lungs", title: "Respiratory", text: "Respiratory Rate, Blood Oxygen")
                OnboardingPoint(symbol: "bed.double", title: "Sleep", text: "Sleep")
            }
            .padding(.top, GroupedListSpec.groupSpacing)
            Text("RYFT writes nothing to Apple Health unless you turn on saving strength workouts. Your data goes to your RYFT account, where the scores are calculated. Never sold, never used for advertising.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, OnboardingSpec.actionGap)
            Button { legal = .privacy } label: { Text("Privacy Policy") }
                .ryftLink()
                .padding(.top, HealthPermissionSpec.linkGap)
                .accessibilityIdentifier("health.privacy")
        } actions: {
            PillButton(Text("Continue"), busy: isBusy) {
                await model.connect()
                model.reportAnswer(continued: true)
            }
            .accessibilityIdentifier("health.continue")
            LaterButton(title: "Not now") {
                model.notNow()
                model.reportAnswer(continued: false)
            }
            .disabled(isBusy)
            .accessibilityIdentifier("health.notNow")
        }
        .safariSheet($legal)
    }
}

extension HealthOnboardingViewModel {
    /// `onboarding_step` for Apple Health (first-run ui.md §8), after the answer was taken: Continue with `answered` (the sheet
    /// was answered: what was allowed, HealthKit never says) or `failed`; Not now as `skipped`. Apart from `connect()` and
    /// `notNow()`, which own the request and `healthIntroDone`.
    func reportAnswer(continued: Bool) {
        let event: AnalyticsEvent = continued
            ? .onboardingStep(.health, .continued, phase == .firstSync ? .answered : .failed)
            : .onboardingStep(.health, .skipped)
        env.analytics.track(event)
    }
}

/// Connect Apple Health's numbers (A §A-10); the frame is the onboarding steps' (`OnboardingScreen`, `OnboardingSpec`).
enum HealthPermissionSpec {
    /// The footnote → the policy link 4.
    static let linkGap: CGFloat = 4
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

// Dark only (NOCTURNE_STYLE §1, ADR 0016: one-value colour assets, so a light preview would be the same pixels).
#Preview("Connect Apple Health · step 5 of 7") {
    HealthPermissionView(progress: FirstRunProgress(step: 5, count: 7))
        .environment(Settings.shared)
        .preferredColorScheme(.dark)
}

#Preview("Connect Apple Health · no step (after the first run)") {
    HealthPermissionView()
        .environment(Settings.shared)
        .preferredColorScheme(.dark)
}

#Preview("Connect Apple Health · busy") {
    HealthPermissionView(showsBusy: true, progress: FirstRunProgress(step: 5, count: 7))
        .environment(Settings.shared)
        .preferredColorScheme(.dark)
}

#Preview("Connect Apple Health · AX3") {
    HealthPermissionView(progress: FirstRunProgress(step: 5, count: 7))
        .environment(Settings.shared)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Connect Apple Health · AX5") {
    HealthPermissionView(progress: FirstRunProgress(step: 5, count: 7))
        .environment(Settings.shared)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
