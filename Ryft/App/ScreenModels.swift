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

    init(state: AppState, sync: SyncService, store: TrainStore, library: TrainLibrary) {
        today = TodayViewModel(state: state, sync: sync)
        sleep = SleepViewModel(state: state)
        strain = StrainViewModel(state: state, store: store)
        insights = InsightsViewModel(state: state)
        profile = ProfileViewModel(state: state, sync: sync)
        trainToday = TrainTodayViewModel(library: library, store: store, clock: state.env.clock)
    }
}
