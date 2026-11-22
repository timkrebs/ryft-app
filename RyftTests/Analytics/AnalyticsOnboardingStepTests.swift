import Foundation
import Testing
@testable import Ryft

// A5 to A8 of docs/work/2026-11-22-analytics-sdk/plan.md (decision B): the usage analytics question is its own onboarding
// step, after invite, consent, about you and wear, before Apple Health. The tests drive `OnboardingCoordinator` and
// `Analytics` the way RootView does: `showsAnalyticsStep` picks the screen, `analyticsStep` (nil while the question
// shows, `.health` after) feeds `track(.onboardingStep(…))`.

/// What keeps the question from showing although the first run has reached it.
enum AnalyticsStepBlocker:CaseIterable, Sendable, CustomTestStringConvertible {
    case flagOff, analyticsNull, invalidDestination, demo, noopSink, sinkCannotSend

    var testDescription: String { "\(self)" }
}

/// A coordinator on a test graph whose sink is a `FakeAnalyticsSink` that can send.
@MainActor
private final class StepRig {
    let sink = FakeAnalyticsSink()
    let api = MockPlatformAPI()
    let env: AppEnvironment
    let state: AppState
    let model: OnboardingCoordinator

    /// `walk`: the account still has to redeem an invite, agree to the policy, say its age and answer "What do you wear?".
    init(flag: Bool = true, config: AnalyticsConfig? = AnalyticsFixture.config, noop: Bool = false, demo: Bool = false,
         walk: Bool = false) {
        if walk {
            api.betaAccess = false
            api.inviteGateOn = true
            api.accountConsent = nil
        }
        let flags: [FeatureFlag: Bool] = [.analyticsEnabled: flag, .devicesSetup: walk]
        let analyticsSink: AnalyticsSink = noop ? NoopAnalyticsSink() : sink
        if demo {
            let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
            env = AppEnvironment(
                settings: Settings(defaults: defaults), health: MockHealthStore(), liveAPI: api, demoAPI: api,
                auth: .preview(), persistence: TrainStore(inMemory: true), clock: TestClock(),
                notifier: MockNotifier(), flags: StaticFlags(flags), connectivity: .preview(online: true),
                defaults: defaults, demoOverride: true, analyticsSink: analyticsSink)
        } else {
            env = AppEnvironment.test(api: api, flags: flags, analyticsSink: analyticsSink)
        }
        (env.flags as? StaticFlags)?.analytics = config
        state = AppState(env: env)
        model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
    }

    var analytics: Analytics { env.analytics }

    /// RootView's `onChange(of: analyticsStep)`: what it tracks for the screen on show.
    func rootViewTracks(_ step: OnboardingCoordinator.Step) {
        analytics.track(.onboardingStep(OnboardingStepName(step)))
    }

    /// Past every gate, "about you" and "What do you wear?", to where the question would show.
    func finishTheStepsBeforeTheQuestion() async {
        await model.check()
        model.finishAboutYou()
        model.later(.wear)
    }

    var nothingSent: Bool { sink.starts.isEmpty && sink.captures.isEmpty }
}

@Suite("Analytics: the onboarding step (decision B)")
@MainActor
struct AnalyticsOnboardingStepTests {
    // MARK: A5

    @Test func noEventBeforeTheYes() async {
        let rig = StepRig(walk: true)
        #expect(!rig.model.showsAnalyticsStep, "the first check hasn't answered")
        await rig.model.check()
        #expect(rig.model.phase == .ready && rig.model.isFirstRun)

        // invite
        #expect(rig.model.flowStep == .invite && !rig.model.showsAnalyticsStep)
        rig.rootViewTracks(.invite)
        rig.model.inviteCode = "RYFT7K3MQX9P"
        #expect(await rig.model.redeemInvite())
        // consent
        #expect(rig.model.flowStep == .consent && !rig.model.showsAnalyticsStep)
        rig.rootViewTracks(.consent)
        #expect(await rig.model.agree())
        // about you
        #expect(rig.model.flowStep == .aboutYou && !rig.model.showsAnalyticsStep)
        rig.rootViewTracks(.aboutYou)
        rig.model.finishAboutYou()
        // wear
        #expect(rig.model.flowStep == .wear && !rig.model.showsAnalyticsStep)
        rig.rootViewTracks(.wear)
        rig.model.later(.wear)

        // the question
        #expect(rig.model.flowStep == nil && rig.model.showsAnalyticsStep)
        #expect(rig.analytics.optIn == nil)
        #expect(rig.nothingSent, "nothing started, nothing captured through four steps and the question")

        // Something tracked while the question is on screen is dropped, never kept for the yes.
        rig.analytics.track(.onboardingStep(.health))
        #expect(rig.nothingSent)

        rig.analytics.setOptIn(true)
        #expect(rig.sink.starts.count == 1)
        #expect(rig.sink.captures.isEmpty, "what came before the yes isn't sent after it")
        #expect(!rig.model.showsAnalyticsStep, "answered")

        // RootView's analyticsStep is now `.health`: the change fires through the open gate.
        rig.analytics.track(.onboardingStep(.health))
        #expect(rig.sink.captures == [FakeAnalyticsSink.Capture(name: "onboarding_step", properties: ["step": "health"])])
        #expect(rig.sink.calls.count == 2)
        if case .start = rig.sink.calls[0] {} else { Issue.record("the start comes first: \(rig.sink.calls)") }
    }

    @Test func theYesStartsWithoutANewIDOnAFirstInstall() async throws {
        let rig = StepRig()
        await rig.finishTheStepsBeforeTheQuestion()
        rig.analytics.setOptIn(true)
        let start = try #require(rig.sink.starts.first)
        #expect(!start.newID)
        #expect(start.destination == AnalyticsDestination(AnalyticsFixture.config))
    }

    // MARK: A6

    @Test func notNowSendsNothing() async {
        let rig = StepRig()
        await rig.finishTheStepsBeforeTheQuestion()
        #expect(rig.model.showsAnalyticsStep)

        rig.analytics.setOptIn(false) // the button "Not now"

        #expect(rig.analytics.optIn == .optedOut)
        #expect(rig.env.defaults.string(forKey: Analytics.optInKey) == "out")
        #expect(rig.sink.starts.isEmpty)
        #expect(!rig.model.showsAnalyticsStep)

        // RootView's later screens: Apple Health, tracker setup, then the tabs.
        rig.analytics.track(.onboardingStep(.health))
        rig.analytics.track(.healthAccessRequested)
        rig.env.settings.healthIntroDone = true
        rig.analytics.track(.onboardingStep(.trackerSetup))
        rig.model.reachedTabs() // tracks `done`
        rig.analytics.track(.firstSyncCompleted)

        #expect(rig.sink.starts.isEmpty && rig.sink.captures.isEmpty && rig.sink.queued.isEmpty)
        #expect(!rig.model.showsAnalyticsStep)
    }

    @Test func notNowDoesNotComeBack() async {
        let rig = StepRig()
        await rig.finishTheStepsBeforeTheQuestion()
        rig.analytics.setOptIn(false)

        await rig.model.check(force: true)
        let flags = rig.env.flags as? StaticFlags
        flags?.overrides[.analyticsEnabled] = false
        flags?.overrides[.analyticsEnabled] = true
        flags?.analytics = AnalyticsFixture.otherConfig
        #expect(!rig.model.showsAnalyticsStep && !rig.analytics.showsPrompt)

        // A fresh coordinator on the same phone (an app start): still answered.
        let next = OnboardingCoordinator(state: rig.state, apiStatus: APIStatus()) {}
        await next.check()
        next.finishAboutYou()
        next.later(.wear)
        #expect(!next.showsAnalyticsStep)
        #expect(rig.sink.starts.isEmpty && rig.sink.captures.isEmpty)
    }

    // MARK: A7

    @Test func stepOrder() async {
        let rig = StepRig(walk: true)
        #expect(!rig.model.showsAnalyticsStep, "before the first check")
        await rig.model.check()

        var seen: [String] = []
        // Whatever step the first run is on, the question isn't; it comes when `flowStep` is nil.
        while let step = rig.model.flowStep {
            seen.append(step.rawValue)
            #expect(!rig.model.showsAnalyticsStep, "\(step) comes before the question")
            switch step {
            case .invite:
                rig.model.inviteCode = "RYFT7K3MQX9P"
                _ = await rig.model.redeemInvite()
            case .consent: _ = await rig.model.agree()
            case .aboutYou: rig.model.finishAboutYou()
            case .wear: rig.model.later(.wear)
            }
        }
        #expect(seen == ["invite", "consent", "aboutYou", "wear"])
        #expect(rig.model.showsAnalyticsStep, "then the question")
        // "Before Apple Health" is RootView's case order, not a condition of the step (a UI order, tested there).
    }

    /// `Settings.healthIntroDone` is per install and turns true by itself when iOS already asked (`accessStatus() ==
    /// .asked`): another account's first run on this phone. That account still sees the question.
    @Test func aSecondAccountOnAPhoneWhereHealthWasAskedIsStillAsked() async {
        let rig = StepRig()
        rig.env.settings.healthIntroDone = true
        await rig.finishTheStepsBeforeTheQuestion()
        #expect(rig.model.isFirstRun && rig.model.flowStep == nil)
        #expect(rig.model.showsAnalyticsStep)

        rig.analytics.setOptIn(true)
        #expect(!rig.model.showsAnalyticsStep, "answered")
        #expect(rig.sink.starts.count == 1)
    }

    @Test func theControlShowsTheQuestionWhereNothingBlocksIt() async {
        let rig = StepRig()
        await rig.finishTheStepsBeforeTheQuestion()
        #expect(rig.model.showsAnalyticsStep)
    }

    @Test(arguments: AnalyticsStepBlocker.allCases)
    func neverWithTheFlagOffAnalyticsNullDemoOrASinkThatCantSend(_ blocker: AnalyticsStepBlocker) async {
        let rig: StepRig
        switch blocker {
        case .flagOff: rig = StepRig(flag: false)
        case .analyticsNull: rig = StepRig(config: nil)
        case .invalidDestination:
            rig = StepRig(config: AnalyticsConfig(host: "https://example.org", projectKey: AnalyticsFixture.key))
        case .demo: rig = StepRig(demo: true)
        case .noopSink: rig = StepRig(noop: true)
        case .sinkCannotSend:
            rig = StepRig()
            rig.sink.canSend = false
        }
        await rig.finishTheStepsBeforeTheQuestion()
        #expect(rig.model.phase == .ready && rig.model.flowStep == nil)
        #expect(!rig.model.showsAnalyticsStep, "\(blocker)")
        #expect(rig.nothingSent)
    }

    @Test func theQuestionAppearsWhenTheConfigArrivesAfterTheOtherSteps() async {
        let rig = StepRig(flag: false, config: nil)
        await rig.finishTheStepsBeforeTheQuestion()
        #expect(!rig.model.showsAnalyticsStep)

        let flags = rig.env.flags as? StaticFlags
        flags?.overrides[.analyticsEnabled] = true
        #expect(!rig.model.showsAnalyticsStep, "no destination yet")
        flags?.analytics = AnalyticsFixture.config
        #expect(rig.model.showsAnalyticsStep, "still before Apple Health")
        #expect(rig.nothingSent)
    }

    // MARK: A8

    @Test func accountsPastOnboardingAreNotPrompted() async {
        let rig = StepRig()
        rig.model.reachedTabs() // this account reached the tabs on this phone (first run done)
        await rig.model.check()
        #expect(!rig.model.isFirstRun && rig.model.phase == .ready)

        #expect(!rig.model.showsAnalyticsStep, "no step")
        #expect(rig.analytics.optIn == nil, "nothing answered for them")
        #expect(rig.analytics.showsToggle, "Profile → Privacy still offers the switch")
        #expect(rig.nothingSent)
    }

    @Test func firstRunDoneIsKeptAcrossAnAppStart() async {
        let rig = StepRig()
        await rig.finishTheStepsBeforeTheQuestion()
        rig.model.reachedTabs()

        let next = OnboardingCoordinator(state: rig.state, apiStatus: APIStatus()) {}
        await next.check()
        #expect(!next.isFirstRun && !next.showsAnalyticsStep)
        #expect(rig.analytics.showsToggle)
    }

    @Test func aSignOutThatForgetsTheAnswerDoesNotBringTheQuestionBackToThoseWhoArePastTheirFirstRun() async {
        let rig = StepRig()
        await rig.finishTheStepsBeforeTheQuestion()
        rig.analytics.setOptIn(true)
        rig.model.reachedTabs()
        rig.analytics.accountLeft() // phase 1: the answer goes with the sign-out

        #expect(rig.analytics.optIn == nil)
        #expect(!rig.model.showsAnalyticsStep)
        #expect(rig.analytics.showsToggle, "the way in is Profile → Privacy")
    }

    @Test func theProfileToggleStillOptsInAfterTheFirstRun() async {
        let rig = StepRig()
        rig.model.reachedTabs()
        await rig.model.check()
        rig.analytics.setOptIn(true)
        #expect(rig.sink.starts.count == 1)
        rig.analytics.track(.screenViewed(.today))
        #expect(rig.sink.captures.map(\.name) == ["screen_viewed"])
        #expect(!rig.model.showsAnalyticsStep)
    }
}
