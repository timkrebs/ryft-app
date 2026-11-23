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

    @Test("Shown only while iOS hasn't been asked: notDetermined; provisional, authorized, denied and ephemeral skip it (§4.3)",
          arguments: [(UNAuthorizationStatus.notDetermined, true), (.provisional, false), (.authorized, false),
                      (.denied, false), (.ephemeral, false)])
    func onlyWhileIOSCanAsk(_ status: UNAuthorizationStatus, _ shows: Bool) {
        #expect(NotificationPrimerFacts.shows(firstRun: true, demo: false, status: status, answered: false,
                                              healthIntroAnswered: true, example: .morningScore) == shows)
        #expect(NotificationPrimerFacts.counts(demo: false, status: status, answered: false, example: .morningScore) == shows)
    }

    @Test("Never after the first run, in demo mode, once answered, before Apple Health's step, or with nothing that can arrive")
    func neverOutsideItsPlace() {
        let ok = (firstRun: true, demo: false, answered: false, health: true)
        let example: NotificationPrimerExample? = .journal
        #expect(NotificationPrimerFacts.shows(firstRun: ok.firstRun, demo: ok.demo, status: .notDetermined,
                                              answered: ok.answered, healthIntroAnswered: ok.health, example: example))
        #expect(!NotificationPrimerFacts.shows(firstRun: false, demo: false, status: .notDetermined, answered: false,
                                               healthIntroAnswered: true, example: example))
        #expect(!NotificationPrimerFacts.shows(firstRun: true, demo: true, status: .notDetermined, answered: false,
                                               healthIntroAnswered: true, example: example))
        #expect(!NotificationPrimerFacts.shows(firstRun: true, demo: false, status: .notDetermined, answered: true,
                                               healthIntroAnswered: true, example: example))
        #expect(!NotificationPrimerFacts.shows(firstRun: true, demo: false, status: .notDetermined, answered: false,
                                               healthIntroAnswered: false, example: example))
        #expect(!NotificationPrimerFacts.shows(firstRun: true, demo: false, status: .notDetermined, answered: false,
                                               healthIntroAnswered: true, example: nil), "nothing can arrive")
        #expect(!NotificationPrimerFacts.counts(demo: false, status: .notDetermined, answered: false, example: nil))
    }

    @Test("An account whose iPhone already answered iOS, or allowed quiet delivery, has no primer step in its plan (the real wiring)",
          arguments: [UNAuthorizationStatus.authorized, .denied, .provisional])
    func alreadyDeterminedIsNotAStep(_ status: UNAuthorizationStatus) async {
        notifier.status = status
        let screens = Self.screens(notifier: notifier, flags: [.pushEnabled: true, .notificationsReminders: true])
        await screens.onboarding.check()
        #expect(screens.onboarding.plan?.steps.contains(.notifications) == false)
        #expect(screens.push.status == status, "the registrar read the same answer the plan did")
        #expect(!NotificationPrimerFacts.shows(firstRun: screens.onboarding.isFirstRun, demo: false, status: screens.push.status,
                                               answered: screens.push.isPrimerAnswered, healthIntroAnswered: true,
                                               example: .morningScore))
    }

    @Test("Not asked yet: the primer counts only while a notification can arrive; with neither flag the plan has one step fewer",
          arguments: [(push: false, reminders: false, counted: false), (push: true, reminders: false, counted: true),
                      (push: false, reminders: true, counted: true), (push: true, reminders: true, counted: true)])
    func countedOnlyWhenSomethingArrives(_ flags: (push: Bool, reminders: Bool, counted: Bool)) async throws {
        notifier.status = .notDetermined
        let screens = Self.screens(notifier: notifier, flags: [.pushEnabled: flags.push, .notificationsReminders: flags.reminders])
        await screens.onboarding.check()
        let steps = try #require(screens.onboarding.plan?.steps)
        #expect(steps.contains(.notifications) == flags.counted, "\(flags): \(steps)")
        let others = steps.filter { $0 != .notifications }
        #expect(steps.count == others.count + (flags.counted ? 1 : 0))
        #expect(notifier.authorizationPrompts == 0, "planning asks iOS nothing")
    }

    @Test("Not asked yet: the primer is a counted step, after Apple Health")
    func notAskedIsAStep() async throws {
        notifier.status = .notDetermined
        let screens = Self.screens(notifier: notifier, flags: [.pushEnabled: true])
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

    /// Review C1: the example is one that can arrive. The morning score is a push (`push.enabled`); the journal reminder and
    /// "not syncing" are local kinds behind `notifications.reminders` (`ReminderScheduler`); with neither, nothing.
    @Test("Every flag combination: the morning score with push on; else the journal (reminders on, journal live); else not syncing (reminders on); else none",
          arguments: [true, false], [true, false])
    func exampleFollowsWhatArrives(_ push: Bool, _ reminders: Bool) {
        for journal in [true, false] {
            let expected: NotificationPrimerExample? = push ? .morningScore : !reminders ? nil : journal ? .journal : .syncStale
            #expect(NotificationPrimerExample.choose(pushEnabled: push, remindersOn: reminders, journalLive: journal) == expected,
                    "push \(push), reminders \(reminders), journal \(journal)")
            let flags = StaticFlags([.pushEnabled: push, .notificationsReminders: reminders])
            #expect(NotificationPrimerExample.current(flags: flags, journalLive: journal) == expected, "read through the flags")
        }
    }

    @Test("notifications.reminders not known yet counts as off, as the scheduler adds nothing then")
    func remindersNotKnownIsOff() {
        let flags = UnknownReminders()
        #expect(NotificationPrimerExample.current(flags: flags, journalLive: true) == nil)
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

    // MARK: the invite gate (review S1)

    /// Continue behind a closed invite gate: iOS asks (the permission is the person's), but nothing registers with APNs and
    /// nothing is sent; `ScreenModels`' invite-gate watch registers once the gate opens, once.
    @Test("Continue behind the invite gate: no APNs registration, no POST; the gate opens: one registration")
    func continueBehindTheInviteGate() async throws {
        let api = MockPlatformAPI()
        let status = APIStatus()
        let screens = Self.screens(notifier: notifier, flags: [.pushEnabled: true], api: api, status: status)
        status.observe([.inviteRequired], enforced: true)
        let model = NotificationPrimerModel(push: screens.push, analytics: AppEnvironment.test().analytics)
        #expect(await model.allow() == .granted && notifier.authorizationPrompts == 1)
        #expect(notifier.remoteRegistrations == 0 && !notifier.registeredForRemote, "behind the gate: no APNs")
        // A token APNs hands over anyway (an earlier session's registration) isn't sent behind the gate.
        await screens.push.didRegister(deviceToken: Data([0x0A, 0x0B]))
        #expect(api.count("registerPush") == 0, "no POST behind the gate")

        status.resolved(.inviteRequired)
        #expect(await eventually(timeout: .seconds(10)) { notifier.remoteRegistrations == 1 }, "the gate opened: registered")
        try await Task.sleep(for: .milliseconds(200))
        #expect(notifier.remoteRegistrations == 1, "once")
    }

    // MARK: support

    /// The app's own graph of models on a test environment (signed in, not demo): `ScreenModels` wires the plan's inputs.
    static func screens(notifier: MockNotifier, flags: [FeatureFlag: Bool] = [:], api: MockPlatformAPI? = nil,
                        status: APIStatus? = nil) -> ScreenModels {
        let state = AppState(env: .test(api: api ?? MockPlatformAPI(), notifier: notifier, flags: flags))
        let sync = SyncService(env: state.env)
        return ScreenModels(state: state, sync: sync,
                            coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock),
                            store: TrainPreview.store, library: TrainPreview.library, apiStatus: status ?? APIStatus())
    }
}

/// `notifications.reminders` with no answer yet (no config for the account): `known` is nil.
@MainActor
private final class UnknownReminders: FeatureFlagProvider {
    private let base = StaticFlags([:])
    func isOn(_ flag: FeatureFlag) -> Bool { base.isOn(flag) }
    func source(of flag: FeatureFlag) -> FlagSource { base.source(of: flag) }
    func newest(_ flag: FeatureFlag) -> Bool { base.newest(flag) }
    var newestAnalytics: AnalyticsConfig? { nil }
    func known(_ flag: FeatureFlag) -> Bool? { flag == .notificationsReminders ? nil : base.known(flag) }
    var onNewest: (@MainActor () -> Void)?
}
