import SwiftUI

/// "What do you wear?" (ui.md §2): the first run's step after About you, before Apple Health. Continue saves the
/// choice for this account; Skip saves nothing and doesn't ask again. Profile → Devices & sync changes it later.
struct TrackerPickerView: View {
    let model: OnboardingCoordinator
    /// The first run's step rule (nil in a sheet).
    let progress: FirstRunProgress?
    @State private var picked: [String]
    @Environment(\.appEnvironment) private var env

    /// `picked`: previews start with a choice.
    init(model: OnboardingCoordinator, picked: [String] = [], progress: FirstRunProgress? = nil) {
        self.model = model
        self.progress = progress
        _picked = State(initialValue: picked)
    }

    var body: some View {
        OnboardingScreen(title: Text("What do you wear?"),
                         lead: Text("Pick your watch, tracker or ring. RYFT then shows how to get its data into Apple Health."),
                         showsLockup: model.isFirstRun, progress: progress) {
            TrackerPickerGrid(catalog: env.trackerCatalog, picked: $picked)
            Text("RYFT only uses this to show you setup steps and to check that your data arrives. You can change it any time in Profile → Devices & sync.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, OnboardingSpec.actionGap)
        }
        .pinnedBar {
            PillButton(Text("Continue")) { model.answerWear(picked) }
                .disabled(picked.isEmpty)
                .accessibilityIdentifier("wear.continue")
            LaterButton(title: "Skip") { model.later(.wear) }
                .accessibilityIdentifier("wear.skip")
        }
        .task { await env.catalogStore.refreshIfDue() }
    }
}

/// After Apple Health access (ui.md §3.5): the chosen trackers' setup cards, the first open and the others
/// collapsed. Done and "Show me again later" both lead to the tabs; nothing here is mandatory, and the first
/// sync already runs.
struct TrackerSetupStepView: View {
    let model: OnboardingCoordinator
    /// The open card in a list of several.
    @State private var open: String?
    /// Check sync was tapped: its model, made once on the tap; the result opens below the cards.
    @State private var check: TrackerCheckModel?
    /// Open from the start (previews, and a `-RyftSyncCheck` run's screenshots).
    private let checkOpen: Bool
    /// The first run's step rule: from RootView only (the screen also opens in a sheet, which passes none).
    private let progress: FirstRunProgress?
    @Environment(\.appEnvironment) private var env

    init(model: OnboardingCoordinator, checkOpen: Bool = SyncCheckScenario.requested != nil,
         progress: FirstRunProgress? = nil) {
        self.model = model
        self.checkOpen = checkOpen
        self.progress = progress
    }

    var body: some View {
        let trackers = model.setupTrackers
        OnboardingScreen(title: trackers.count > 1 ? Text("Set up your trackers") : Text("Set up your tracker"),
                         lead: Text("A few minutes now saves a silent week of missing data."),
                         showsLockup: true, progress: progress) {
            VStack(spacing: OnboardingSpec.actionGap) {
                ForEach(trackers) { tracker in
                    if trackers.count == 1 {
                        TrackerSetupCard(tracker: tracker)
                    } else {
                        // `open` nil: the first card; "": none.
                        TrackerSetupCard(tracker: tracker,
                                         expanded: Binding(get: { (open ?? trackers.first?.id) == tracker.id },
                                                           set: { open = $0 ? tracker.id : "" }),
                                         later: {
                                             // Put off: this card closes, the next one still to set up opens.
                                             model.devices.markLater(tracker.id)
                                             open = trackers.first { $0.id != tracker.id && !model.devices.isLater($0.id) }?.id ?? ""
                                         })
                    }
                }
            }
            // The inline Check sync (design.md §8, ui.md §3.5): its button under the cards, the result opening
            // below them, with its own Check again.
            if let check {
                TrackerCheckView(model: check, embedded: true)
                    .padding(.top, OnboardingSpec.actionGap)
            } else {
                PillButton(Text("Check sync"), style: .secondary) { openCheck() }
                    .padding(.top, OnboardingSpec.actionGap)
                    .accessibilityIdentifier("trackerSetup.checkSync")
            }
        }
        .pinnedBar {
            PillButton(Text("Done"), systemImage: PillButton.Icon.confirm) { model.finishTrackerSetup(later: false) }
                .accessibilityIdentifier("trackerSetup.done")
            LaterButton(title: "Show me again later") { model.finishTrackerSetup(later: true) }
                .accessibilityIdentifier("trackerSetup.later")
        }
        .onAppear { if checkOpen { openCheck() } }
    }

    /// The check on the chosen trackers, made once.
    private func openCheck() {
        guard check == nil else { return }
        check = .make(env: env, trackers: model.devices.trackers)
    }
}

/// "What do you wear?" or the setup screen after Apple Health, on the bundled catalog. Dark only (NOCTURNE_STYLE §1).
@MainActor
private func trackerStepPreview(setup: Bool = false, picked: [String] = [], size: DynamicTypeSize = .large,
                                checkOpen: Bool = false) -> some View {
    let state = AppState.preview()
    let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
    model.devices.stage(picked)
    return Group {
        if setup {
            TrackerSetupStepView(model: model, checkOpen: checkOpen)
        } else {
            TrackerPickerView(model: model, picked: picked)
        }
    }
    .previewEnvironment(state)
    .dynamicTypeSize(size)
}

#Preview("Tracker picker · empty") { trackerStepPreview() }
#Preview("Tracker picker · Garmin and Oura") { trackerStepPreview(picked: ["garmin", "oura"]) }
#Preview("Tracker picker · just my iPhone") { trackerStepPreview(picked: ["iphone"]) }
#Preview("Tracker picker · AX3") { trackerStepPreview(picked: ["garmin"], size: .accessibility3) }
#Preview("Tracker picker · AX5") { trackerStepPreview(picked: ["garmin"], size: .accessibility5) }
#Preview("Tracker setup · Garmin") { trackerStepPreview(setup: true, picked: ["garmin"]) }
#Preview("Tracker setup · Garmin and Oura") { trackerStepPreview(setup: true, picked: ["garmin", "oura"]) }
#Preview("Tracker setup · AX3") { trackerStepPreview(setup: true, picked: ["fitbit"], size: .accessibility3) }
#Preview("Tracker setup · check open") { trackerStepPreview(setup: true, picked: ["garmin"], checkOpen: true) }
