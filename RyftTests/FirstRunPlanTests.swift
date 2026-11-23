import Foundation
import Testing
@testable import Ryft

/// The first run's step count (docs/work/2026-11-23-first-run/ui.md §1, §2.2 and lead decision 5): a pure plan, taken once.
@Suite("First run: the plan and its count")
struct FirstRunPlanTests {
    typealias Facts = OnboardingCoordinator.Facts
    typealias Inputs = FirstRunPlan.Inputs

    /// A new account: the platform knows it, no consent, no birth year, the policy in force known.
    private static func newAccount(invite: Bool = true, devices: Bool = true) -> Facts {
        Facts(userKnown: true, betaAccess: false, policyVersion: "v2", serverGate: invite ? .inviteRequired : nil,
              devicesSetup: devices)
    }

    /// Apple Health still to explain, iOS not asked about notifications; the device slot as the coordinator decides it.
    private static func inputs(devices: Bool = true, wearAsked: Bool = false, needsSetup: Bool = false) -> Inputs {
        Inputs(healthIntro: true, notificationsPrimer: true,
               trackerSetup: FirstRunPlan.reservesDeviceSetup(devicesSetup: devices, wearAsked: wearAsked,
                                                              trackerSetupDone: false, needsSetup: needsSetup))
    }

    // MARK: the paths of §1's table, with lead decision 5's one device slot

    @Test("Every path with devices.setup counts the same: Apple Watch, Garmin and no device are 7 with the invite gate")
    func everyDevicePathCountsTheSame() {
        let plan = FirstRunPlan.make(Self.newAccount(), Self.inputs())
        #expect(plan.steps == [.invite, .consent, .aboutYou, .wear, .health, .notifications, .trackerSetup])
        // Whatever "What do you wear?" brings, the plan was taken before it: one slot, the same 7.
        #expect(plan.progress(at: .notifications) == FirstRunProgress(step: 6, count: 7))
        #expect(plan.progress(at: .trackerSetup) == FirstRunProgress(step: 7, count: 7))
    }

    @Test("The invite gate off: one fewer")
    func inviteOff() {
        let plan = FirstRunPlan.make(Self.newAccount(invite: false), Self.inputs())
        #expect(plan.steps == [.consent, .aboutYou, .wear, .health, .notifications, .trackerSetup])
        #expect(plan.progress(at: .consent) == FirstRunProgress(step: 1, count: 6))
        #expect(plan.progress(at: .invite) == nil)
    }

    @Test("devices.setup off: no wear and no device slot", arguments: [true, false])
    func devicesSetupOff(_ invite: Bool) {
        let plan = FirstRunPlan.make(Self.newAccount(invite: invite, devices: false), Self.inputs(devices: false))
        let expected: [FirstRunStep] = [.consent, .aboutYou, .health, .notifications]
        #expect(plan.steps == (invite ? [.invite] + expected : expected))
        #expect(plan.progress(at: .wear) == nil && plan.progress(at: .trackerSetup) == nil)
    }

    @Test("iOS already asked about notifications: no primer step")
    func notificationsAlreadyDecided() {
        var inputs = Self.inputs()
        inputs.notificationsPrimer = false
        let plan = FirstRunPlan.make(Self.newAccount(), inputs)
        #expect(!plan.steps.contains(.notifications) && plan.steps.count == 6)
    }

    @Test("A second phone of an account with consent and a birth year: Apple Health and notifications (and wear while on)")
    func secondDevice() {
        let known = Facts(userKnown: true, betaAccess: true, consentVersion: "v2", policyVersion: "v2", birthYear: 1990,
                          devicesSetup: true)
        #expect(FirstRunPlan.make(known, Self.inputs()).steps == [.wear, .health, .notifications, .trackerSetup])
        var off = known
        off.devicesSetup = false
        #expect(FirstRunPlan.make(off, Self.inputs(devices: false)).steps == [.health, .notifications])
    }

    @Test("Demo data has no first run")
    func demoHasNoPlan() {
        var demo = Self.newAccount()
        demo.demo = true
        let plan = FirstRunPlan.make(demo, Self.inputs())
        #expect(plan.steps.isEmpty && plan.progress(at: .health) == nil)
    }

    @Test("One step is no progress; a step outside the plan has none")
    func oneStepAndOutside() {
        let one = FirstRunPlan(steps: [.health])
        #expect(one.progress(at: .health) == nil)
        let two = FirstRunPlan(steps: [.health, .notifications])
        #expect(two.progress(at: .health) == FirstRunProgress(step: 1, count: 2))
        #expect(two.progress(at: .consent) == nil)
    }

    // MARK: the device slot

    @Test("The device slot: held until wear is answered, then only for a tracker with its own app; never with the flag off or after setup")
    func deviceSlot() {
        #expect(FirstRunPlan.reservesDeviceSetup(devicesSetup: true, wearAsked: false, trackerSetupDone: false, needsSetup: false))
        #expect(FirstRunPlan.reservesDeviceSetup(devicesSetup: true, wearAsked: true, trackerSetupDone: false, needsSetup: true))
        #expect(!FirstRunPlan.reservesDeviceSetup(devicesSetup: true, wearAsked: true, trackerSetupDone: false, needsSetup: false))
        #expect(!FirstRunPlan.reservesDeviceSetup(devicesSetup: true, wearAsked: false, trackerSetupDone: true, needsSetup: true))
        #expect(!FirstRunPlan.reservesDeviceSetup(devicesSetup: false, wearAsked: false, trackerSetupDone: false, needsSetup: true))
    }

    @Test("A relaunch after wear counts what remains: the Apple Watch without a slot, Garmin with one")
    func relaunchAfterWear() {
        var facts = Self.newAccount(invite: false)
        facts.consentVersion = "v2"
        facts.aboutYouDone = true
        facts.wearAsked = true
        let watch = FirstRunPlan.make(facts, Self.inputs(wearAsked: true, needsSetup: false))
        let garmin = FirstRunPlan.make(facts, Self.inputs(wearAsked: true, needsSetup: true))
        #expect(watch.steps == [.health, .notifications])
        #expect(garmin.steps == [.health, .notifications, .trackerSetup])
    }
}

/// The coordinator takes the plan once and keeps it: answers and deferrals never change the count.
@MainActor
@Suite("First run: the coordinator's snapshot")
struct FirstRunSnapshotTests {
    private func coordinator(devices: Bool = true) -> (OnboardingCoordinator, AppState) {
        let state = AppState(env: .test(flags: [.devicesSetup: devices]))
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        model.planInputs = { FirstRunPlan.Inputs(healthIntro: true, notificationsPrimer: true) }
        return (model, state)
    }

    @Test("The count never grows or shrinks: about you, wear (Garmin), Apple Health, notifications, set up, each of 5")
    func countNeverChanges() async {
        let (model, _) = coordinator()
        await model.check()
        #expect(model.plan?.steps == [.aboutYou, .wear, .health, .notifications, .trackerSetup])
        #expect(model.progress(for: .aboutYou) == FirstRunProgress(step: 1, count: 5))
        model.finishAboutYou()
        #expect(model.progress(for: .aboutYou) == FirstRunProgress(step: 1, count: 5), "an answered step keeps its index")
        #expect(model.progress(for: .wear) == FirstRunProgress(step: 2, count: 5))
        model.answerWear(["garmin", "oura"])
        await model.check(force: true)
        #expect(model.progress(for: .health) == FirstRunProgress(step: 3, count: 5))
        #expect(model.progress(for: .notifications) == FirstRunProgress(step: 4, count: 5))
        // Two trackers to set up: one slot.
        #expect(model.setupTrackers.count == 2 && model.progress(for: .trackerSetup) == FirstRunProgress(step: 5, count: 5))
    }

    @Test("The Apple Watch path keeps the slot it was given: the count stays 5")
    func appleWatchKeepsTheCount() async {
        let (model, _) = coordinator()
        await model.check()
        model.finishAboutYou()
        model.answerWear(["apple_watch"])
        await model.check(force: true)
        #expect(!model.showsTrackerSetup)
        #expect(model.progress(for: .notifications) == FirstRunProgress(step: 4, count: 5))
    }

    @Test("A deferred step stays counted")
    func deferralKeepsTheCount() async {
        let (model, _) = coordinator()
        await model.check()
        model.later(.aboutYou)
        model.later(.wear)
        #expect(model.progress(for: .health) == FirstRunProgress(step: 3, count: 5))
    }

    @Test("After the first run, nothing counts (a sheet or a later screen draws no rule)")
    func afterTheFirstRun() async {
        let (model, _) = coordinator()
        await model.check()
        model.reachedTabs()
        #expect(model.progress(for: .health) == nil && model.progress(for: .consent) == nil)
    }

    @Test("Another account takes its own plan")
    func anotherAccount() async {
        let (model, _) = coordinator()
        await model.check()
        #expect(model.plan != nil)
        model.switchAccount("someone-else")
        #expect(model.plan == nil && model.progress(for: .health) == nil)
    }

    @Test("Demo data: no plan, no progress")
    func demo() async {
        let model = OnboardingCoordinator(state: AppState.preview(), apiStatus: APIStatus()) {}
        model.planInputs = { FirstRunPlan.Inputs(healthIntro: true, notificationsPrimer: true) }
        await model.check()
        #expect(model.plan == nil && model.progress(for: .health) == nil)
    }
}
