import Foundation
import SwiftUI
import Testing
import UserNotifications
@testable import Ryft

/// The first run's notification primer (docs/work/2026-11-23-first-run/ui.md §4): when it shows, what it asks, and that it
/// is the registrar's ask, not a new one.
@MainActor
@Suite("Notification primer")
struct NotificationPrimerTests {
    private let notifier = MockNotifier()

    private func registrar(push: Bool = true) -> (PushRegistrar, AppEnvironment) {
        let env = AppEnvironment.test(notifier: notifier, flags: [.pushEnabled: push])
        return (PushRegistrar(env: env), env)
    }

    // MARK: when

    @Test("Shown only while iOS can ask: notDetermined and provisional; authorized, denied and ephemeral skip it",
          arguments: [(UNAuthorizationStatus.notDetermined, true), (.provisional, true), (.authorized, false),
                      (.denied, false), (.ephemeral, false)])
    func onlyWhileIOSCanAsk(_ status: UNAuthorizationStatus, _ shows: Bool) {
        #expect(NotificationPrimerFacts.shows(firstRun: true, demo: false, status: status, answered: false,
                                              healthIntroAnswered: true) == shows)
        #expect(NotificationPrimerFacts.counts(demo: false, status: status, answered: false) == shows)
    }

    @Test("Never after the first run, in demo mode, once answered, or before Apple Health's step")
    func neverOutsideItsPlace() {
        let ok = (firstRun: true, demo: false, answered: false, health: true)
        #expect(NotificationPrimerFacts.shows(firstRun: ok.firstRun, demo: ok.demo, status: .notDetermined,
                                              answered: ok.answered, healthIntroAnswered: ok.health))
        #expect(!NotificationPrimerFacts.shows(firstRun: false, demo: false, status: .notDetermined, answered: false,
                                               healthIntroAnswered: true))
        #expect(!NotificationPrimerFacts.shows(firstRun: true, demo: true, status: .notDetermined, answered: false,
                                               healthIntroAnswered: true))
        #expect(!NotificationPrimerFacts.shows(firstRun: true, demo: false, status: .notDetermined, answered: true,
                                               healthIntroAnswered: true))
        #expect(!NotificationPrimerFacts.shows(firstRun: true, demo: false, status: .notDetermined, answered: false,
                                               healthIntroAnswered: false))
    }

    @Test("An account whose iPhone already answered iOS has no primer step in its plan (the real wiring)",
          arguments: [UNAuthorizationStatus.authorized, .denied])
    func alreadyDeterminedIsNotAStep(_ status: UNAuthorizationStatus) async {
        notifier.status = status
        let screens = Self.screens(notifier: notifier)
        await screens.onboarding.check()
        #expect(screens.onboarding.plan?.steps.contains(.notifications) == false)
        #expect(screens.push.status == status, "the registrar read the same answer the plan did")
        #expect(!NotificationPrimerFacts.shows(firstRun: screens.onboarding.isFirstRun, demo: false, status: screens.push.status,
                                               answered: screens.push.isPrimerAnswered, healthIntroAnswered: true))
    }

    @Test("Not asked yet: the primer is a counted step, after Apple Health")
    func notAskedIsAStep() async throws {
        notifier.status = .notDetermined
        let screens = Self.screens(notifier: notifier)
        await screens.onboarding.check()
        let steps = try #require(screens.onboarding.plan?.steps)
        #expect(steps.contains(.notifications))
        if let health = steps.firstIndex(of: .health), let primer = steps.firstIndex(of: .notifications) {
            #expect(health < primer)
        }
        #expect(notifier.authorizationPrompts == 0, "planning asks iOS nothing")
    }

    // MARK: what it asks

    @Test("Not now: no prompt, the card's dismissal (back once after 14 days), and the primer answered")
    func notNowNeverPrompts() throws {
        let (push, env) = registrar()
        let model = NotificationPrimerModel(push: push, analytics: env.analytics)
        model.notNow()
        #expect(notifier.authorizationPrompts == 0)
        #expect(push.isPrimerAnswered && push.status == .notDetermined)
        push.syncSucceeded()
        #expect(!push.showsPrePrompt, "Today's card waits its 14 days")
        let clock = try #require(env.clock as? TestClock)
        clock.advance(by: .seconds(PushRegistrar.askAgainAfter))
        #expect(push.showsPrePrompt, "the second chance")
    }

    @Test("Continue: exactly one prompt, through the registrar's ask; APNs only when allowed")
    func continueAsksOnce() async {
        let (push, env) = registrar()
        let model = NotificationPrimerModel(push: push, analytics: env.analytics)
        let outcome = await model.allow()
        #expect(outcome == .granted && notifier.authorizationPrompts == 1)
        #expect(push.isPrimerAnswered && push.isAllowed && notifier.registeredForRemote)
    }

    @Test("Declined at the prompt: no APNs, nothing nags (no card on Today)")
    func declined() async {
        notifier.grants = false
        let (push, env) = registrar()
        #expect(await NotificationPrimerModel(push: push, analytics: env.analytics).allow() == .denied)
        push.syncSucceeded()
        #expect(!notifier.registeredForRemote && !push.showsPrePrompt)
    }

    @Test("push.enabled off: the permission is still asked (the local kinds need it), APNs isn't registered")
    func pushOffAsksWithoutAPNs() async {
        let (push, env) = registrar(push: false)
        #expect(await NotificationPrimerModel(push: push, analytics: env.analytics).allow() == .granted)
        #expect(notifier.authorizationPrompts == 1 && !notifier.registeredForRemote)
    }

    // MARK: the example

    @Test("The example arrives for this account: the morning score with push on; else the journal when live; else not syncing")
    func exampleFollowsWhatArrives() {
        #expect(NotificationPrimerExample.choose(pushEnabled: true, journalLive: true) == .morningScore)
        #expect(NotificationPrimerExample.choose(pushEnabled: true, journalLive: false) == .morningScore)
        #expect(NotificationPrimerExample.choose(pushEnabled: false, journalLive: true) == .journal)
        #expect(NotificationPrimerExample.choose(pushEnabled: false, journalLive: false) == .syncStale)
    }

    @Test("No health value, no count: no digit in any title or message", arguments: NotificationPrimerExample.allCases)
    func noDigitOnTheLockScreen(_ example: NotificationPrimerExample) {
        #expect(example.title.rangeOfCharacter(from: .decimalDigits) == nil, "\(example.title)")
        #expect(example.message.rangeOfCharacter(from: .decimalDigits) == nil, "\(example.message)")
        #expect(example.accessibilityLabel.hasPrefix("Example notification from RYFT."))
    }

    // MARK: hosted

    @Test("Hosted: Not now and Continue on the screen, VoiceOver's order and hint, one prompt for Continue only",
          arguments: [false, true])
    func hosted(_ continues: Bool) async throws {
        let (push, env) = registrar()
        let view = NotificationPrimerStep(model: NotificationPrimerModel(push: push, analytics: env.analytics), example: .morningScore,
                                          progress: FirstRunProgress(step: 6, count: 7))
            .environment(\.appEnvironment, env)
        try await HostedWindow.run(width: 390, height: 844, view) { w in
            try await w.wait("the primer") { w.nodes().contains { $0.identifier == "notifications.notNow" } }
            try await w.settle()
            let labels = w.nodes().map(\.label)
            let title = try #require(labels.firstIndex(of: "Hear from RYFT when it matters"))
            let step = try #require(labels.firstIndex(of: "Step 6 of 7"))
            let example = try #require(labels.firstIndex { $0.hasPrefix("Example notification from RYFT.") })
            #expect(title < step && step < example, "title, step, then the example: \(labels)")
            let allow = try #require(w.nodes().first { $0.identifier == "notifications.continue" })
            #expect(allow.hint == "iOS asks next")
            if continues {
                allow.activate()
                try await w.wait("answered") { push.isPrimerAnswered }
                #expect(notifier.authorizationPrompts == 1)
            } else {
                try #require(w.nodes().first { $0.identifier == "notifications.notNow" }).activate()
                try await w.wait("answered") { push.isPrimerAnswered }
                #expect(notifier.authorizationPrompts == 0)
            }
        }
    }

    // MARK: support

    /// The app's own graph of models on a test environment (signed in, not demo): `ScreenModels` wires the plan's inputs.
    static func screens(notifier: MockNotifier) -> ScreenModels {
        let state = AppState(env: .test(notifier: notifier))
        let sync = SyncService(env: state.env)
        return ScreenModels(state: state, sync: sync,
                            coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock),
                            store: TrainPreview.store, library: TrainPreview.library, apiStatus: APIStatus())
    }
}
