import SwiftUI

/// About you's "Use my birth year from Apple Health" in each of its states (health-groups.md §7), for previews and tests.
/// Demo data is off here, as it must be for the button to show; the fake HealthStore answers, and the platform is the
/// in-process mock. Nothing reaches a server, and no date exists anywhere: the mock knows only a year. Synthetic data.
@MainActor
enum MockBirthYearPrefill {
    enum Scenario: CaseIterable {
        /// The record has no `about`: the button and its primer.
        case notAsked
        /// Asked before: the button alone.
        case askedBefore
        /// The system sheet is still up: the button busy, the wheel off.
        case asking
        /// 1990, on the wheel with "From Apple Health" under it.
        case filled
        /// Asked before, and Apple Health shares no year: the note, Allow in Health and the route.
        case nothing
        /// 1900: the note, the wheel untouched.
        case outOfRange

        /// The button is tapped once on appear (`AboutYouView.fillsFromHealthOnAppear`).
        var taps: Bool { ![.notAsked, .askedBefore].contains(self) }
    }

    /// The year Apple Health holds in `filled`.
    static let year = 1990
    /// A year before `OnboardingCoordinator.earliestBirthYear`.
    static let outOfRangeYear = 1900

    /// The fake HealthStore as `scenario` needs it.
    static func health(_ scenario: Scenario) -> MockHealthStore {
        let health = MockHealthStore()
        switch scenario {
        case .notAsked: break
        case .askedBefore, .nothing: health.asked = [.about]
        case .asking: health.beforeAuthorizationReturns = { try? await Task.sleep(for: .seconds(3_600)) }
        case .filled: health.birthYearValue = year
        case .outOfRange: health.birthYearValue = outOfRangeYear
        }
        return health
    }

    /// A signed-in account's graph (Demo data off) over `health`.
    static func state(health: MockHealthStore) -> AppState {
        let api = MockPlatformAPI(activities: .demoSource())
        // A suite of its own each time, as `.test` makes: nothing a preview or a test writes reaches the next one.
        let defaults = UserDefaults(suiteName: "ryft.preview.prefill.\(UUID().uuidString)") ?? .standard
        let env = AppEnvironment(
            settings: Settings(defaults: defaults), health: health, liveAPI: api, demoAPI: api, auth: .preview(),
            persistence: TrainStore(inMemory: true), clock: SystemClock(), notifier: MockNotifier(), flags: StaticFlags([:]),
            connectivity: .preview(online: true), defaults: defaults, demoOverride: false)
        return AppState(env: env)
    }
}

/// About you with the prefill in `scenario`, as the previews show it.
struct AboutYouPrefillPreview: View {
    let scenario: MockBirthYearPrefill.Scenario
    @State private var state: AppState
    @State private var model: OnboardingCoordinator

    init(_ scenario: MockBirthYearPrefill.Scenario) {
        self.scenario = scenario
        let state = MockBirthYearPrefill.state(health: MockBirthYearPrefill.health(scenario))
        _state = State(initialValue: state)
        _model = State(initialValue: OnboardingCoordinator(state: state, apiStatus: APIStatus()) {})
    }

    var body: some View {
        AboutYouView(model: model, fillsFromHealthOnAppear: scenario.taps)
            .previewEnvironment(state)
    }
}
