import Foundation
import SwiftUI
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

    // MARK: when the flag is consumed (`TodayGaugeEntrance.decide`, applied by Today's gauges)

    private typealias Entrance = TodayGaugeEntrance
    private typealias Outcome = TodayGaugeEntrance.Outcome

    /// One row per decision: flag, scene phase now, event, played unseen before → the outcome.
    private struct Row {
        let name: String
        let flag: Bool
        let phase: ScenePhase
        let event: Entrance.Event
        let playedUnseen: Bool
        let expected: Outcome
    }

    private static let rows: [Row] = [
        // Flag still set.
        Row(name: "appears while active: consume", flag: true, phase: .active, event: .appeared, playedUnseen: false,
            expected: Outcome(consume: true)),
        Row(name: "appears while inactive (cold launch): wait", flag: true, phase: .inactive, event: .appeared,
            playedUnseen: false, expected: Outcome()),
        Row(name: "appears in the background: played unseen", flag: true, phase: .background, event: .appeared,
            playedUnseen: false, expected: Outcome(playedUnseen: true)),
        Row(name: "inactive to active, seen: consume", flag: true, phase: .active, event: .phaseChanged,
            playedUnseen: false, expected: Outcome(consume: true)),
        Row(name: "to inactive, seen: wait", flag: true, phase: .inactive, event: .phaseChanged, playedUnseen: false,
            expected: Outcome()),
        Row(name: "background to inactive, played unseen: rebuild", flag: true, phase: .inactive, event: .phaseChanged,
            playedUnseen: true, expected: Outcome(rebuild: true)),
        Row(name: "background to active, played unseen: rebuild, not consume", flag: true, phase: .active,
            event: .phaseChanged, playedUnseen: true, expected: Outcome(rebuild: true)),
        Row(name: "inactive to background, never active: played unseen", flag: true, phase: .background,
            event: .phaseChanged, playedUnseen: false, expected: Outcome(playedUnseen: true)),
        Row(name: "to background again, played unseen: stays unseen", flag: true, phase: .background,
            event: .phaseChanged, playedUnseen: true, expected: Outcome(playedUnseen: true)),
        Row(name: "a rebuilt gauge appears while active: consume", flag: true, phase: .active, event: .appeared,
            playedUnseen: false, expected: Outcome(consume: true)),
    ] + {
        // Flag consumed: nothing, in every phase and event, whatever was remembered.
        var rows: [Row] = []
        for phase in [ScenePhase.active, .inactive, .background] {
            for event in [Entrance.Event.appeared, .phaseChanged] {
                for unseen in [false, true] {
                    rows.append(Row(name: "consumed, \(phase), \(event), unseen \(unseen): nothing", flag: false,
                                    phase: phase, event: event, playedUnseen: unseen, expected: Outcome()))
                }
            }
        }
        return rows
    }()

    @Test func everyDecisionRow() {
        for row in Self.rows {
            let outcome = Entrance.decide(flag: row.flag, phase: row.phase, event: row.event, playedUnseen: row.playedUnseen)
            #expect(outcome == row.expected, "\(row.name)")
        }
    }

    /// Plays a sequence through `decide` the way Today's gauge modifier applies it (a rebuild is followed by the new
    /// instance's `.appeared` in the phase now). Returns how often it consumed and rebuilt.
    private func play(_ steps: [(Entrance.Event, ScenePhase)]) -> (flag: Bool, consumed: Int, rebuilds: Int) {
        var flag = true, unseen = false, consumed = 0, rebuilds = 0
        var queue = steps
        while !queue.isEmpty {
            let (event, phase) = queue.removeFirst()
            let outcome = Entrance.decide(flag: flag, phase: phase, event: event, playedUnseen: unseen)
            unseen = outcome.playedUnseen
            if outcome.consume { flag = false; consumed += 1 }
            if outcome.rebuild {
                rebuilds += 1
                queue.insert((.appeared, phase), at: 0)
            }
        }
        return (flag, consumed, rebuilds)
    }

    @Test func aColdLaunchConsumesWhenTheSceneTurnsActive() {
        let run = play([(.appeared, .inactive), (.phaseChanged, .active)])
        #expect(run == (false, 1, 0))
    }

    @Test func aBackgroundLaunchOpenedLaterRebuildsOnceAndConsumes() {
        let run = play([(.appeared, .background), (.phaseChanged, .inactive), (.phaseChanged, .active)])
        #expect(run == (false, 1, 1))
        let straight = play([(.appeared, .background), (.phaseChanged, .active)])
        #expect(straight == (false, 1, 1))
    }

    @Test func theRebuildFiresAtMostOncePerUnseenPlay() {
        // Repeated phase changes while still inactive after the rebuild: no second rebuild, no loop.
        let run = play([(.appeared, .background), (.phaseChanged, .inactive), (.phaseChanged, .inactive),
                        (.phaseChanged, .inactive), (.phaseChanged, .active), (.phaseChanged, .inactive),
                        (.phaseChanged, .active)])
        #expect(run == (false, 1, 1))
    }

    @Test func aLaunchInterruptedBeforeActiveReplaysOnTheNextOpen() {
        // Drawn while inactive, then straight to the background: the entrance played unseen.
        let run = play([(.appeared, .inactive), (.phaseChanged, .background), (.phaseChanged, .inactive),
                        (.phaseChanged, .active)])
        #expect(run == (false, 1, 1))
    }

    @Test func foregroundReturnsAfterConsumingDoNothing() {
        let run = play([(.appeared, .active), (.phaseChanged, .inactive), (.phaseChanged, .background),
                        (.phaseChanged, .inactive), (.phaseChanged, .active), (.appeared, .active),
                        (.appeared, .background), (.phaseChanged, .active)])
        #expect(run == (false, 1, 0))
    }

    @Test func theBackgroundNeverConsumes() {
        let run = play([(.appeared, .background), (.phaseChanged, .background), (.appeared, .background)])
        #expect(run == (true, 0, 0))
    }
}
