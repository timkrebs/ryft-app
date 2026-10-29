import Foundation
import Observation

/// The tab screens' view models, built once with the shared read state so a tab
/// keeps its selection and loaded data when you switch away and back. Detail
/// screens (a workout, an exercise, a plan) make their own per item.
@MainActor
@Observable
final class ScreenModels {
    let today: TodayViewModel
    let sleep: SleepViewModel
    let strain: StrainViewModel
    let insights: InsightsViewModel
    let profile: ProfileViewModel
    /// Bedtime & wake: tonight's bedtime, the reminder and the wake alarm.
    let bedtime: BedtimePlanner
    /// Baseline sleep need, maximum heart rate, birth year: onboarding, Sleep and Profile.
    var bodySettings: BodySettingsEditor { profile.bodySettings }
    let trainToday: TrainTodayViewModel
    let coordinator: SyncCoordinator
    let push: PushRegistrar
    /// The journal (M5), shared by Today, Profile and Insights.
    let journal: JournalStore
    let router: DeepLinkRouter
    /// Remote flags (`GET /v1/config`); nil when the environment's flags are static (tests, previews).
    let featureFlags: FeatureFlags?
    /// Invite, consent and "about you" before the first sync; the gates mid-session.
    let onboarding: OnboardingCoordinator
    /// What the user wears (`devices.setup`): onboarding, Today, Profile → Devices & sync.
    let devices: TrackerSelectionStore
    /// My Day (`today.my_day`): the card on Today and its full screen.
    let myDay: MyDayViewModel
    /// The training import's upload (`train.import`): step 6, the resume row on My Plans and in Profile → Data.
    let trainImport: TrainImportUploader
    /// The training import's flow (`train.import`): one cover for My Plans, Profile → Data and "Open in".
    let importer: ImportCoordinator
    private let state: AppState
    private let sync: SyncService
    /// Republishes the widget when the tracker choice or `devices.setup` changes.
    private let widgetSetupWatch: ObservationWatch
    /// Train's outbox (the app's; nil in tests and previews that don't upload sessions).
    private let trainSync: TrainSyncService?

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator, store: TrainStore, library: TrainLibrary,
         apiStatus: APIStatus? = nil, trainSync: TrainSyncService? = nil) {
        self.coordinator = coordinator
        self.state = state
        self.sync = sync
        self.trainSync = trainSync
        let devices = TrackerSelectionStore(env: state.env)
        self.devices = devices
        // The widget's calibration decides with the same tracker setup as Today's (F3), and is published again when
        // the choice or `devices.setup` changes (neither write goes through the repository).
        state.repository.chosenTrackers = { [devices] in devices.trackers }
        widgetSetupWatch = ObservationWatch(read: { [devices, flags = state.env.flags] in
            _ = flags.isOn(.devicesSetup)
            _ = devices.trackers
        }, changed: { [repository = state.repository] in repository.publishWidget() })
        onboarding = OnboardingCoordinator(state: state, apiStatus: apiStatus ?? .shared, devices: devices) {
            await coordinator.run(.userInitiated)
        }
        // Every upload waits for the same rule, per path and kind of write (ADR 0008): consent to the policy in force,
        // known and fresh, and no enforced invite gate; a DELETE only the invite gate. Until these lines run the two
        // outboxes' gates are closed.
        sync.gate = { [onboarding] in onboarding.uploadGate(for: .healthKit) }
        state.env.uploader.gate = { [onboarding] in onboarding.uploadGate(for: .activities, write: $0) }
        if let trainSync {
            trainSync.gate = { [onboarding] in onboarding.uploadGate(for: .train, write: $0) }
            trainSync.revalidatePolicy = { [consent = state.env.consent] in try await consent.revalidate() }
        }
        trainImport = TrainImportUploader(env: state.env, library: library, coordinator: coordinator)
        trainImport.gate = { [onboarding] in onboarding.uploadGate(for: .trainImport, write: $0) }
        // The launch check's sync status reaches the sync (an operator's re-sync request).
        onboarding.statusReceived = { [sync] in sync.receive($0) }
        push = PushRegistrar(env: state.env)
        journal = JournalStore(env: state.env)
        today = TodayViewModel(state: state, sync: sync, coordinator: coordinator, push: push,
                               onboarding: onboarding, devices: devices)
        sleep = SleepViewModel(state: state)
        strain = StrainViewModel(state: state, store: store)
        myDay = MyDayViewModel(state: state, store: store) { [today] in TodayStates.nightGap(today.facts) != nil }
        // A confirmed activity or night: into the read model, and its days rescored through the sync pipeline.
        state.env.uploader.connect(repository: state.repository, coordinator: coordinator)
        insights = InsightsViewModel(state: state, journal: journal)
        router = DeepLinkRouter(state: state, sleep: sleep, strain: strain, insights: insights, onboarding: onboarding)
        importer = ImportCoordinator(env: state.env, library: library, uploader: trainImport,
                                     showStrain: { [state] in state.selectedTab = .strain },
                                     openRoute: { [state, strain] route in
                                         strain.requestedRoute = route
                                         state.selectedTab = .strain
                                     })
        let env = state.env
        featureFlags = (env.flags as? FlagStore).map { store in
            FeatureFlags(flags: store, clock: env.clock) {
                // Flags are evaluated per user: nothing to ask before sign-in (and nothing recorded).
                guard env.isDemo || env.auth.isSignedIn else { throw APIError.signedOut }
                // The one door for the config: its policy version is recorded for the gates too.
                guard let config = try await env.consent.fetchConfig() else { throw ReadScheduler.NotSent() }
                return config
            }
        }
        profile = ProfileViewModel(state: state, sync: sync, coordinator: coordinator, onboarding: onboarding,
                                   devices: devices)
        state.onForgetAccountState = { [profile] in profile.forgetExport() }
        trainToday = TrainTodayViewModel(library: library, store: store, clock: state.env.clock)
        // Train's reads share the pipeline's budget and per-resource record.
        library.reads = state.env.reads
        bedtime = BedtimePlanner(state: state)
    }

    /// A path's data gate changed (RootView forwards each). When it opens, that path's queue goes: the activity
    /// uploader, Train's outbox, and a sync whose last run was held. A sync that wasn't held isn't rerun: that would be
    /// an extra HealthKit pass at every launch. In the background there's no view: each run asks the gate (and the
    /// policy) at its own start.
    func gateChanged(_ path: UploadPath, to gate: UploadGate?) {
        guard gate == nil else { return }
        switch path {
        case .healthKit:
            // Only a held sync, and only when none is running or queued (`agree()` starts its own): that one reads
            // the gate itself, and a rerun after it would be an extra pass.
            guard sync.pausedFor != nil else { return }
            let coordinator = coordinator
            Task { await coordinator.runIfIdle(.appActive) }
        case .activities:
            let uploader = state.env.uploader
            Task { await uploader.flush() }
        case .train:
            guard let trainSync else { return }
            Task { await trainSync.flush() }
        case .trainImport:
            let uploader = trainImport
            Task { await uploader.resume() }
        }
    }

    /// Pull to refresh on any tab: the upload starts, today and the sync status load at once, the
    /// rest after the upload (`AppState.pullToRefresh`). Returns within 3 s; the status line
    /// carries what's still running.
    func pullToRefresh() async {
        await state.pullToRefresh(coordinator: coordinator)
    }
}
