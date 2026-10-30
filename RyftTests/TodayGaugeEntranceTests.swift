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

    // MARK: what assembles (`TodayGaugeEntrance.hasSomethingToShow`, `entrance`)

    @Test func onlyAGaugeWithSomethingToShowAssembles() {
        let some = OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)
        let one = OrbitGaugeValues(strain: 4.2)
        let cases: [(String, OrbitGaugeMode, Bool)] = [
            ("scored", .scored(some), true),
            ("scored, one score only", .scored(one), true),
            ("scored, learning", .scored(some, learning: OrbitGaugeCalibration(nights: 3)), true),
            ("no data yet / first import (empty)", .scored(.empty), false),
            ("scored, nothing scored", .scored(OrbitGaugeValues()), false),
            ("calibrating, 0 nights", .calibrating(OrbitGaugeCalibration(nights: 0)), true),
            ("calibrating, 3 nights", .calibrating(OrbitGaugeCalibration(nights: 3)), true),
            ("pending over a scored day", .pending(previous: some), true),
            ("pending without a previous day", .pending(previous: nil), false),
            ("pending over an empty day", .pending(previous: OrbitGaugeValues()), false),
        ]
        for (name, mode, shows) in cases {
            #expect(TodayGaugeEntrance.hasSomethingToShow(mode) == shows, "\(name)")
            #expect(TodayGaugeEntrance.entrance(flag: true, mode: mode) == (shows ? .assemble : .none), "\(name)")
            #expect(TodayGaugeEntrance.entrance(flag: false, mode: mode) == .none, "consumed: \(name)")
        }
    }

    // MARK: when the flag is consumed (`TodayGaugeEntrance.decide`, applied by Today's gauges)

    private typealias Entrance = TodayGaugeEntrance
    private typealias Outcome = TodayGaugeEntrance.Outcome

    /// One row per decision: flag, something to show, scene phase now, event, played unseen before → the outcome.
    private struct Row {
        let name: String
        var flag = true
        var showable = true
        let phase: ScenePhase
        let event: Entrance.Event
        var playedUnseen = false
        let expected: Outcome
    }

    private static let rows: [Row] = [
        // Flag still set, a gauge with something to show.
        Row(name: "appears while active: consume", phase: .active, event: .appeared, expected: Outcome(consume: true)),
        Row(name: "appears while inactive (cold launch): wait", phase: .inactive, event: .appeared, expected: Outcome()),
        Row(name: "appears in the background: played unseen", phase: .background, event: .appeared,
            expected: Outcome(playedUnseen: true)),
        Row(name: "appears while inactive, played unseen: stays unseen (no consume later without a rebuild)",
            phase: .inactive, event: .appeared, playedUnseen: true, expected: Outcome(playedUnseen: true)),
        Row(name: "appears while active, played unseen: rebuild, not consume", phase: .active, event: .appeared,
            playedUnseen: true, expected: Outcome(rebuild: true)),
        Row(name: "inactive to active, seen: consume", phase: .active, event: .phaseChanged,
            expected: Outcome(consume: true)),
        Row(name: "to inactive, seen: wait", phase: .inactive, event: .phaseChanged, expected: Outcome()),
        Row(name: "background to inactive, played unseen: rebuild", phase: .inactive, event: .phaseChanged,
            playedUnseen: true, expected: Outcome(rebuild: true)),
        Row(name: "background to active, played unseen: rebuild, not consume", phase: .active, event: .phaseChanged,
            playedUnseen: true, expected: Outcome(rebuild: true)),
        Row(name: "inactive to background, never active: played unseen", phase: .background, event: .phaseChanged,
            expected: Outcome(playedUnseen: true)),
        Row(name: "to background again, played unseen: stays unseen", phase: .background, event: .phaseChanged,
            playedUnseen: true, expected: Outcome(playedUnseen: true)),
    ] + {
        var rows: [Row] = []
        for phase in [ScenePhase.active, .inactive, .background] {
            for event in [Entrance.Event.appeared, .phaseChanged] {
                for unseen in [false, true] {
                    // Flag consumed: nothing, in every phase and event, whatever was remembered.
                    rows.append(Row(name: "consumed, \(phase), \(event), unseen \(unseen): nothing", flag: false,
                                    phase: phase, event: event, playedUnseen: unseen, expected: Outcome()))
                    // Nothing to show: never consumed, never played unseen, never rebuilt.
                    rows.append(Row(name: "nothing to show, \(phase), \(event), unseen \(unseen): nothing",
                                    showable: false, phase: phase, event: event, playedUnseen: unseen,
                                    expected: Outcome()))
                }
            }
        }
        return rows
    }()

    @Test func everyDecisionRow() {
        for row in Self.rows {
            let outcome = Entrance.decide(flag: row.flag, showable: row.showable, phase: row.phase, event: row.event,
                                          playedUnseen: row.playedUnseen)
            #expect(outcome == row.expected, "\(row.name)")
        }
    }

    // MARK: sequences, as Today's gauge modifier applies them

    private enum Step {
        /// The gauge appears in this phase: built the first time, the same instance again after that (a tab switch
        /// back, or an `onAppear` that SwiftUI sends again on a foreground return).
        case appear(ScenePhase)
        /// The scene changes to this phase.
        case phase(ScenePhase)
        /// The data changes: whether the mode has something to show. A change makes a new gauge instance, which
        /// appears in the current phase.
        case data(showable: Bool)
    }

    private struct Run: Equatable {
        /// The flag at the end (`assemblesGauge`).
        var flag = true
        var consumed = 0
        var rebuilds = 0
        /// The instance that consumed the flag latched `.assemble`: the entrance the user saw was a real one.
        var consumedOnAnAssemblingGauge = false
        /// Instances built while they latch `.assemble`.
        var assemblingInstances = 0
    }

    /// Plays the steps through `entrance` and `decide` the way `GaugeEntranceConsumer` does: a new instance (first
    /// appearance, a rebuild, data that becomes showable or empty) latches its entrance and appears in the current
    /// phase.
    private func play(showable start: Bool = true, _ steps: [Step]) -> Run {
        var run = Run()
        var showable = start, unseen = false, phase = ScenePhase.inactive
        var latched = OrbitGauge.Entrance.none
        var built = false
        func apply(_ event: Entrance.Event) {
            let outcome = Entrance.decide(flag: run.flag, showable: showable, phase: phase, event: event,
                                          playedUnseen: unseen)
            unseen = outcome.playedUnseen
            if outcome.rebuild {
                run.rebuilds += 1
                appear()
            }
            if outcome.consume {
                run.flag = false
                run.consumed += 1
                run.consumedOnAnAssemblingGauge = latched == .assemble
            }
        }
        func appear() {
            built = true
            let mode: OrbitGaugeMode = showable ? .scored(OrbitGaugeValues(readiness: 71, strain: 9.6)) : .scored(.empty)
            latched = Entrance.entrance(flag: run.flag, mode: mode)
            if latched == .assemble { run.assemblingInstances += 1 }
            apply(.appeared)
        }
        for step in steps {
            switch step {
            case .appear(let p):
                phase = p
                if built { apply(.appeared) } else { appear() }
            case .phase(let p):
                phase = p
                apply(.phaseChanged)
            case .data(let now):
                guard now != showable else { continue }
                showable = now
                appear()
            }
        }
        return run
    }

    @Test func aColdLaunchConsumesWhenTheSceneTurnsActive() {
        let run = play([.appear(.inactive), .phase(.active)])
        #expect(run == Run(flag: false, consumed: 1, consumedOnAnAssemblingGauge: true, assemblingInstances: 1))
    }

    @Test func aBackgroundLaunchOpenedLaterRebuildsOnceAndConsumes() {
        let run = play([.appear(.background), .phase(.inactive), .phase(.active)])
        #expect(run == Run(flag: false, consumed: 1, rebuilds: 1, consumedOnAnAssemblingGauge: true,
                           assemblingInstances: 2))
        let straight = play([.appear(.background), .phase(.active)])
        #expect(straight == Run(flag: false, consumed: 1, rebuilds: 1, consumedOnAnAssemblingGauge: true,
                                assemblingInstances: 2))
    }

    @Test func anAppearanceBeforeThePhaseChangeStillRebuilds() {
        // SwiftUI may send the unseen gauge onAppear before onChange on a foreground return.
        let inactiveFirst = play([.appear(.background), .appear(.inactive), .phase(.inactive), .phase(.active)])
        #expect(inactiveFirst == Run(flag: false, consumed: 1, rebuilds: 1, consumedOnAnAssemblingGauge: true,
                                     assemblingInstances: 2))
        let activeFirst = play([.appear(.background), .appear(.active), .phase(.active)])
        #expect(activeFirst == Run(flag: false, consumed: 1, rebuilds: 1, consumedOnAnAssemblingGauge: true,
                                   assemblingInstances: 2))
    }

    @Test func theRebuildFiresAtMostOncePerUnseenPlay() {
        // Repeated phase changes while still inactive after the rebuild: no second rebuild, no loop.
        let run = play([.appear(.background), .phase(.inactive), .phase(.inactive), .phase(.inactive),
                        .phase(.active), .phase(.inactive), .phase(.active)])
        #expect(run.rebuilds == 1)
        #expect(run.consumed == 1)
    }

    @Test func aLaunchInterruptedBeforeActiveReplaysOnTheNextOpen() {
        // Drawn while inactive, then straight to the background: the entrance played unseen.
        let run = play([.appear(.inactive), .phase(.background), .phase(.inactive), .phase(.active)])
        #expect(run == Run(flag: false, consumed: 1, rebuilds: 1, consumedOnAnAssemblingGauge: true,
                           assemblingInstances: 2))
    }

    @Test func foregroundReturnsAfterConsumingDoNothing() {
        let run = play([.appear(.active), .phase(.inactive), .phase(.background), .phase(.inactive), .phase(.active),
                        .appear(.active), .appear(.background), .phase(.active)])
        #expect(run == Run(flag: false, consumed: 1, consumedOnAnAssemblingGauge: true, assemblingInstances: 1))
    }

    @Test func theBackgroundNeverConsumes() {
        let run = play([.appear(.background), .phase(.background), .appear(.background)])
        #expect(run.flag)
        #expect(run.consumed == 0)
    }

    // MARK: sequences with data arriving (a first launch, demo mode)

    @Test func anEmptyGaugeNeitherAssemblesNorConsumes() {
        let run = play(showable: false, [.appear(.inactive), .phase(.active), .phase(.inactive), .phase(.background),
                                         .phase(.inactive), .phase(.active), .appear(.active)])
        #expect(run == Run(flag: true, consumed: 0, rebuilds: 0, assemblingInstances: 0))
    }

    @Test func dataArrivingWhileActivePlaysOnceOnTheDataAndConsumes() {
        // The first launch the ui-validator recorded: the empty gauge first, the data about 0.5 s later.
        let run = play(showable: false, [.appear(.inactive), .phase(.active), .data(showable: true)])
        #expect(run == Run(flag: false, consumed: 1, consumedOnAnAssemblingGauge: true, assemblingInstances: 1))
        // Still inactive when the data arrives: consumed when the scene turns active.
        let early = play(showable: false, [.appear(.inactive), .data(showable: true), .phase(.active)])
        #expect(early == Run(flag: false, consumed: 1, consumedOnAnAssemblingGauge: true, assemblingInstances: 1))
    }

    @Test func dataFromTheFirstFrameIsAsBefore() {
        let run = play(showable: true, [.appear(.inactive), .phase(.active), .data(showable: true)])
        #expect(run == Run(flag: false, consumed: 1, consumedOnAnAssemblingGauge: true, assemblingInstances: 1))
    }

    @Test func dataArrivingInTheBackgroundFollowsThePlayedUnseenRules() {
        let run = play(showable: false, [.appear(.background), .data(showable: true), .phase(.inactive),
                                         .phase(.active)])
        #expect(run == Run(flag: false, consumed: 1, rebuilds: 1, consumedOnAnAssemblingGauge: true,
                           assemblingInstances: 2))
    }

    @Test func showableThenEmptyThenShowableAfterConsumingNeverReplays() {
        let run = play(showable: true, [.appear(.active), .data(showable: false), .data(showable: true),
                                        .phase(.background), .phase(.active), .data(showable: false),
                                        .data(showable: true)])
        #expect(run == Run(flag: false, consumed: 1, consumedOnAnAssemblingGauge: true, assemblingInstances: 1))
    }

    @Test func dataGoingEmptyBeforeItWasSeenKeepsTheFlagForTheNextData() {
        // Showable in the background, then empty (a refresh) before anyone looked: the next data plays it.
        let run = play(showable: true, [.appear(.background), .data(showable: false), .phase(.active),
                                        .data(showable: true)])
        #expect(run == Run(flag: false, consumed: 1, rebuilds: 0, consumedOnAnAssemblingGauge: true,
                           assemblingInstances: 2))
    }
}
