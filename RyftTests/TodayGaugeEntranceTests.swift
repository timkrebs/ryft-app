import Foundation
import Testing
@testable import Ryft

/// The launch entrance plays once per launch (OrbitGauge PR 3, plan.md decisions 5 and 6): the view model hands out
/// `assemblesGauge` until the gauge reports it has assembled, and nothing brings it back.
@Suite("Today: the gauge assembles once per launch")
@MainActor
struct TodayGaugeEntranceTests {
    private let now = Date(timeIntervalSince1970: 1_792_600_000)

    private func model() -> (TodayViewModel, AppState) {
        let env = AppEnvironment.test(clock: TestClock(now: now))
        let state = AppState(env: env)
        let sync = SyncService.ungated(env: env)
        let model = TodayViewModel(state: state, sync: sync,
                                   coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                                   apiStatus: APIStatus())
        return (model, state)
    }

    @Test func aNewModelAssembles() {
        #expect(model().0.assemblesGauge)
    }

    @Test func assemblingConsumesTheFlag() {
        let (model, _) = model()
        model.gaugeDidAssemble()
        #expect(!model.assemblesGauge)
    }

    @Test func aSecondCallIsHarmless() {
        let (model, _) = model()
        model.gaugeDidAssemble()
        model.gaugeDidAssemble()
        #expect(!model.assemblesGauge)
    }

    @Test func itStaysOffThroughRefreshAndDataChanges() async {
        let (model, state) = model()
        model.gaugeDidAssemble()
        await model.refresh()
        #expect(!model.assemblesGauge)
        state.today = DayDetail(score: DailyScore(day: DayFormat.string(from: now), readiness: 74, recovery: 72, strain: 0.9,
                                                  rhr: 52, baselineDays: 30, calibrating: false, computedAt: now,
                                                  scoringState: .scored), sleep: nil, workouts: [])
        state.selectedTab = .sleep
        state.selectedTab = .today
        #expect(!model.assemblesGauge)
        // The same instance after a data change and another refresh (a foreground return reloads through it).
        await model.refresh()
        #expect(!model.assemblesGauge)
    }

    @Test func aFlagNeverConsumedStaysOnThroughRefresh() async {
        // Foreground return before the first active appearance must not use the entrance up.
        let (model, _) = model()
        await model.refresh()
        #expect(model.assemblesGauge)
    }
}
