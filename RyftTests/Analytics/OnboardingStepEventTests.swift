import Foundation
import Testing
@testable import Ryft

/// `onboarding_step` from the first run's own call sites (first-run ui.md §8): one per step and action, through the existing
/// `Analytics` (its gate decides; there is no second one), with closed tokens only.
@MainActor
@Suite("onboarding_step from the first run")
struct OnboardingStepEventTests {
    private let sink = FakeAnalyticsSink()
    private let notifier = MockNotifier()
    private let health = MockHealthStore()

    private func env(optedIn: Bool) -> AppEnvironment {
        let env = AppEnvironment.test(health: health, notifier: notifier,
                                      flags: [.analyticsEnabled: true, .pushEnabled: true, .devicesSetup: true],
                                      analyticsSink: sink)
        (env.flags as? StaticFlags)?.analytics = AnalyticsFixture.config
        if optedIn { env.analytics.setOptIn(true) }
        return env
    }

    private var steps: [[String: String]] {
        sink.captures.filter { $0.name == "onboarding_step" }.map(\.properties)
    }

    /// Every step's answer, as a person taps through the first run.
    private func walk(_ env: AppEnvironment) async {
        let coordinator = OnboardingCoordinator(state: AppState(env: env), apiStatus: APIStatus()) {}
        coordinator.later(.aboutYou)
        coordinator.answerWear(["garmin", "oura"])
        let healthModel = HealthOnboardingViewModel(env: env)
        await healthModel.connect()
        healthModel.reportAnswer(continued: true)
        HealthOnboardingViewModel(env: env).reportAnswer(continued: false)
        let push = PushRegistrar(env: env)
        await NotificationPrimerModel(push: push, analytics: env.analytics).allow()
        NotificationPrimerModel(push: push, analytics: env.analytics).notNow()
        coordinator.finishTrackerSetup(later: false)
        coordinator.finishTrackerSetup(later: true)
    }

    @Test("Analytics not opted in: the whole walk captures nothing")
    func nothingWhileOff() async {
        await walk(env(optedIn: false))
        #expect(sink.captures.isEmpty && sink.starts.isEmpty)
    }

    @Test("Opted in: each answer once, step and action, a permission only on Apple Health's and the primer's Continue")
    func eachAnswer() async {
        await walk(env(optedIn: true))
        #expect(steps == [
            ["step": "about_you", "action": "skipped"],
            ["step": "wear", "action": "continued"],
            ["step": "health", "action": "continued", "permission": "answered"],
            ["step": "health", "action": "skipped"],
            ["step": "notifications", "action": "continued", "permission": "granted"],
            ["step": "notifications", "action": "skipped"],
            ["step": "tracker_setup", "action": "continued"],
            ["step": "tracker_setup", "action": "skipped"],
        ])
    }

    @Test("Never a tracker's name, a year or any value outside the tokens")
    func onlyTokens() async {
        await walk(env(optedIn: true))
        let allowed = Set(OnboardingStepName.allCases.map(\.rawValue) + OnboardingStepAction.allCases.map(\.rawValue)
            + OnboardingPermission.allCases.map(\.rawValue))
        for properties in steps {
            #expect(Set(properties.keys).isSubset(of: ["step", "action", "permission"]), "\(properties)")
            #expect(Set(properties.values).isSubset(of: allowed), "\(properties)")
        }
        #expect(!sink.captures.contains { $0.properties.values.contains { $0.contains("garmin") } })
    }

    @Test("Apple Health's Continue without an answered sheet reports failed; the primer's refused prompt denied")
    func failedAndDenied() async {
        let env = env(optedIn: true)
        HealthOnboardingViewModel(env: env).reportAnswer(continued: true)
        notifier.grants = false
        await NotificationPrimerModel(push: PushRegistrar(env: env), analytics: env.analytics).allow()
        #expect(steps == [
            ["step": "health", "action": "continued", "permission": "failed"],
            ["step": "notifications", "action": "continued", "permission": "denied"],
        ])
    }
}
