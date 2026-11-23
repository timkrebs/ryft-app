import Foundation

/// The first run's counted steps, in screen order (docs/work/2026-11-23-first-run/ui.md §1). Welcome, the splash, the
/// account-hint sheet and the system sheets are not steps; Today is where the run ends, not a step.
enum FirstRunStep: String, CaseIterable, Sendable {
    case invite, consent, aboutYou, wear
    /// The usage-analytics prompt (#137); never in a plan until it lands.
    case analytics
    case health, notifications
    /// "Set up your device": one slot, whatever the tracker (lead decision 5).
    case trackerSetup

    init(_ step: OnboardingCoordinator.Step) {
        switch step {
        case .invite: self = .invite
        case .consent: self = .consent
        case .aboutYou: self = .aboutYou
        case .wear: self = .wear
        }
    }
}

/// "Step 3 of 7": where a first-run screen is in its run, for `FirstRunStepRule`. Never for a sheet.
struct FirstRunProgress: Equatable, Sendable {
    let step: Int
    let count: Int
}

/// The steps of one first run, taken once when it starts (ui.md §2.2, lead decision 5):
/// - **A snapshot.** Answering or putting off a step leaves it in the plan, so "Step 2 of 6" never becomes "Step 1 of 5".
/// - **The count never changes.** "Set up your device" holds one slot from the start in every path that can reach it
///   (`devices.setup` on, until it is known that nothing needs setting up), so Apple Watch, Garmin and no device count the
///   same. A step that isn't in the plan (a gate that appears mid-run) has no progress: no rule, rather than a count that
///   moves.
/// - A relaunch mid-run takes a new snapshot of what is still missing, so it counts again from 1, of what remains.
/// Pure: the coordinator hands it plain values.
struct FirstRunPlan: Equatable, Sendable {
    /// What the app knows beyond `OnboardingCoordinator.Facts` when the run starts.
    struct Inputs: Equatable, Sendable {
        /// #137: the usage-analytics step. False until it lands.
        var analyticsStep = false
        /// Apple Health's explanation is still to come (`health.isAvailable && !healthIntroDone`).
        var healthIntro = false
        /// The notification primer will show (`NotificationPrimerFacts.counts`).
        var notificationsPrimer = false
        /// The "set up your device" slot (`reservesDeviceSetup`).
        var trackerSetup = false
    }

    let steps: [FirstRunStep]

    /// The plan for `facts` (the four the coordinator decides, with its invite and `devices.setup` rules) and `inputs`. Demo
    /// data has no first run.
    static func make(_ facts: OnboardingCoordinator.Facts, _ inputs: Inputs) -> FirstRunPlan {
        guard !facts.demo else { return FirstRunPlan(steps: []) }
        var steps = OnboardingCoordinator.missing(facts).map(FirstRunStep.init)
        if inputs.analyticsStep { steps.append(.analytics) }
        if inputs.healthIntro { steps.append(.health) }
        if inputs.notificationsPrimer { steps.append(.notifications) }
        if inputs.trackerSetup { steps.append(.trackerSetup) }
        return FirstRunPlan(steps: steps)
    }

    /// One slot for "set up your device" while it can still come: `devices.setup` is on, the setup screen hasn't been left,
    /// and either "What do you wear?" is still to be answered (the answer isn't known, so the slot is held for every path)
    /// or the answer has a tracker with an app of its own.
    static func reservesDeviceSetup(devicesSetup: Bool, wearAsked: Bool, trackerSetupDone: Bool,
                                    needsSetup: @autoclosure () -> Bool) -> Bool {
        guard devicesSetup, !trackerSetupDone else { return false }
        return !wearAsked || needsSetup()
    }

    /// `step` as "n of m", 1-based; nil when it isn't in the plan, or the plan has fewer than
    /// `FirstRunStepRuleSpec.minimumCount` steps (a run of one has no progress).
    func progress(at step: FirstRunStep) -> FirstRunProgress? {
        guard steps.count >= FirstRunStepRuleSpec.minimumCount, let index = steps.firstIndex(of: step) else { return nil }
        return FirstRunProgress(step: index + 1, count: steps.count)
    }
}
