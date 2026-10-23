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
    private let state: AppState

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator, store: TrainStore, library: TrainLibrary,
         apiStatus: APIStatus? = nil) {
        self.coordinator = coordinator
        self.state = state
        let devices = TrackerSelectionStore(env: state.env)
        self.devices = devices
        onboarding = OnboardingCoordinator(state: state, apiStatus: apiStatus ?? .shared, devices: devices) {
            await coordinator.run(.userInitiated)
        }
        // Nothing syncs before consent, nor behind an enforced invite gate.
        sync.gate = { [onboarding] in onboarding.syncGate }
        // The launch check's sync status reaches the sync (an operator's re-sync request).
        onboarding.statusReceived = { [sync] in sync.receive($0) }
        push = PushRegistrar(env: state.env)
        journal = JournalStore(env: state.env)
        today = TodayViewModel(state: state, sync: sync, coordinator: coordinator, push: push,
                               onboarding: onboarding, devices: devices)
        sleep = SleepViewModel(state: state)
        strain = StrainViewModel(state: state, store: store)
        myDay = MyDayViewModel(state: state, store: store) { [today] in TodayStates.nightGap(today.facts) != nil }
        insights = InsightsViewModel(state: state, journal: journal)
        router = DeepLinkRouter(state: state, sleep: sleep, strain: strain, insights: insights, onboarding: onboarding)
        let env = state.env
        featureFlags = (env.flags as? FlagStore).map { store in
            FeatureFlags(flags: store, clock: env.clock) {
                // Flags are evaluated per user: nothing to ask before sign-in (and nothing recorded).
                guard env.isDemo || env.auth.isSignedIn else { throw APIError.signedOut }
                guard let config = try await env.reads.run(ReadKey(.config), { try await env.api.config() }) else {
                    throw ReadScheduler.NotSent()
                }
                return config
            }
        }
        profile = ProfileViewModel(state: state, sync: sync, coordinator: coordinator, onboarding: onboarding,
                                   devices: devices)
        trainToday = TrainTodayViewModel(library: library, store: store, clock: state.env.clock)
        // Train's reads share the pipeline's budget and per-resource record.
        library.reads = state.env.reads
        bedtime = BedtimePlanner(state: state)
    }

    /// Pull to refresh on any tab: the upload starts, today and the sync status load at once, the
    /// rest after the upload (`AppState.pullToRefresh`). Returns within 3 s; the status line
    /// carries what's still running.
    func pullToRefresh() async {
        await state.pullToRefresh(coordinator: coordinator)
    }
}
