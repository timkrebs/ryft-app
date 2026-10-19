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
    let trainToday: TrainTodayViewModel
    let coordinator: SyncCoordinator
    let push: PushRegistrar
    let router: DeepLinkRouter
    private let state: AppState

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator, store: TrainStore, library: TrainLibrary) {
        self.coordinator = coordinator
        self.state = state
        push = PushRegistrar(env: state.env)
        today = TodayViewModel(state: state, sync: sync, coordinator: coordinator, push: push)
        sleep = SleepViewModel(state: state)
        strain = StrainViewModel(state: state, store: store)
        insights = InsightsViewModel(state: state)
        router = DeepLinkRouter(state: state, sleep: sleep, strain: strain, insights: insights)
        profile = ProfileViewModel(state: state, sync: sync, coordinator: coordinator)
        trainToday = TrainTodayViewModel(library: library, store: store, clock: state.env.clock)
    }

    /// Pull to refresh on any tab: upload, wait for scoring, reload everything.
    func pullToRefresh() async {
        await coordinator.run(.userInitiated)
        await state.refresh(force: true)
    }
}
