import Foundation
import Testing
@testable import Ryft

/// The live path to Today's calibration note (design.md §7 rev. 2 §5): `TodayViewModel.facts` hands `devices.setup`
/// and the chosen trackers to `decide`, which the demo scenarios and §6's tables set directly. A smoke test of that
/// wiring only; the decision and `resolve` tables are §6's.
@Suite("Today: the calibration note's wiring")
@MainActor
struct TodayCalibrationWiringTests {
    private let now = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0,
                                            of: Date(timeIntervalSince1970: 1_792_600_000))!
    private func dayKey(_ offset: Int) -> String { DayFormat.string(from: DayFormat.shift(now, days: offset)) }

    /// API.md's example 3 (`no_hrv`, H 0, R 24, readiness 74) over 30 scored days without HRV; `reason` swaps it.
    private func model(devicesSetup: Bool, trackers: [String], reason: CalibratingReason? = .noHrv) -> TodayViewModel {
        let env = AppEnvironment.test(clock: TestClock(now: now), flags: [.devicesSetup: devicesSetup])
        let state = AppState(env: env)
        state.history = (1...30).reversed().map { offset in
            DailyScore(day: dayKey(-offset), readiness: 70, recovery: 60, strain: 8, rhr: 52, baselineDays: 0,
                       calibrating: true, computedAt: DayFormat.shift(now, days: -offset), scoringState: .scored)
        }
        let today = DailyScore(day: dayKey(0), readiness: 74, state: .calibrating, recovery: 72, strain: 0.9, rhr: 52,
                               baselineDays: 0, calibrating: true, computedAt: now, scoringState: .scored,
                               baselineHrvDays: 0, baselineRhrDays: 24, calibratingReason: reason)
        state.today = DayDetail(score: today, sleep: nil, workouts: [])
        let sync = SyncService(env: env)
        return TodayViewModel(state: state, sync: sync,
                              coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                              devices: TrackerSelectionStore(env: env, launch: trackers), apiStatus: APIStatus())
    }

    @Test func theFlagAndTheChoiceReachTheNote() {
        let on = model(devicesSetup: true, trackers: ["garmin"])
        #expect(on.facts.devicesSetup && on.facts.trackers.map(\.id) == ["garmin"])
        guard case .blocked(let blocker)? = on.gaugeNote else { Issue.record("expected the blocked note"); return }
        #expect(blocker.source == .notShared(app: "Garmin Connect"))
        #expect(on.gaugeNote?.link == .setup(trackerID: "garmin", app: "Garmin Connect"))
        #expect(on.readiness == 74 && on.sentence == String(localized: "Readiness from the signals that reached RYFT."))
        // Flag off: the choice isn't read, nothing is named and nothing links.
        let off = model(devicesSetup: false, trackers: ["garmin"])
        #expect(!off.facts.devicesSetup && off.facts.trackers.isEmpty)
        #expect(off.gaugeNote == .blocked(CalibrationBlocker(signals: [.hrv], source: .unknown, link: nil)))
        // Only a row whose note names the tracker reads the choice (and the catalog): not short history, not legacy.
        for reason in [CalibratingReason.shortHistory, nil] {
            let other = model(devicesSetup: true, trackers: ["garmin"], reason: reason)
            #expect(other.facts.devicesSetup && other.facts.trackers.isEmpty, "\(String(describing: reason))")
        }
    }
}
