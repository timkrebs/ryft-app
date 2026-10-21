import Foundation
import Testing
@testable import Ryft

/// For every pair of states: reach `from` along allowed transitions, then
/// entering `to` must succeed exactly when the table has that edge, and a
/// refused transition must leave the machine where it was.
@MainActor
private func walkEveryEdge<S: Hashable & CaseIterable & Sendable>(
    _ table: TransitionTable<S>, make: () -> any StateMachine<S>
) {
    for from in S.allCases {
        guard let path = table.path(to: from) else {
            Issue.record("\(from) is unreachable from \(table.initial)")
            continue
        }
        for to in S.allCases {
            let m = make()
            for step in path { #expect(m.enter(step), "path step \(step)") }
            #expect(m.state == from)
            let allowed = table.allows(from, to)
            #expect(m.canEnter(to) == allowed, "\(from) → \(to)")
            #expect(m.enter(to) == allowed, "\(from) → \(to)")
            #expect(m.state == (allowed ? to : from), "\(from) → \(to)")
        }
    }
}

@Suite("State machines")
@MainActor
struct StateMachineTests {
    @Test func syncPipelineEdges() {
        walkEveryEdge(SyncMachine.table()) { SyncMachine.make() }
        walkEveryEdge(SyncMachine.table()) { TableMachine(SyncMachine.table()) }
    }

    @Test func authSessionEdges() {
        walkEveryEdge(AuthMachine.table()) { AuthMachine.make() }
        walkEveryEdge(AuthMachine.table()) { TableMachine(AuthMachine.table()) }
    }

    @Test func liveSessionEdges() {
        walkEveryEdge(LiveSessionMachine.table()) { LiveSessionMachine.make() }
        walkEveryEdge(LiveSessionMachine.table()) { TableMachine(LiveSessionMachine.table()) }
    }

    @Test func healthOnboardingEdges() {
        walkEveryEdge(HealthOnboardingMachine.table()) { HealthOnboardingMachine.make() }
        walkEveryEdge(HealthOnboardingMachine.table()) { TableMachine(HealthOnboardingMachine.table()) }
    }

    @Test func everyStateIsReachable() {
        #expect(SyncPhase.allCases.allSatisfy { SyncMachine.table().path(to: $0) != nil })
        #expect(AuthPhase.allCases.allSatisfy { AuthMachine.table().path(to: $0) != nil })
        #expect(LiveSessionPhase.allCases.allSatisfy { LiveSessionMachine.table().path(to: $0) != nil })
        #expect(HealthOnboardingPhase.allCases.allSatisfy { HealthOnboardingMachine.table().path(to: $0) != nil })
    }

    @Test func terminalStatesStayTerminal() {
        let m = LiveSessionMachine.make()
        m.enter(.active)
        m.enter(.discarded)
        #expect(LiveSessionPhase.allCases.allSatisfy { !m.canEnter($0) })
        #expect(LiveSessionMachine.table().edges[.completed]?.isEmpty == true)
    }

    @Test func exitThenEnterEffectsFireOnceInOrder() {
        var log: [String] = []
        var table = SyncMachine.table { to, from in log.append("enter \(to.rawValue) from \(from.rawValue)") }
        table.onExit = { from, to in log.append("exit \(from.rawValue) to \(to.rawValue)") }
        for m in [GKTableMachine(table, classes: [
            .idle: SyncMachine.SyncIdle.self, .reading: SyncMachine.SyncReading.self,
            .uploading: SyncMachine.SyncUploading.self, .awaitingScores: SyncMachine.SyncAwaitingScores.self,
            .refreshing: SyncMachine.SyncRefreshing.self, .done: SyncMachine.SyncDone.self,
            .failed: SyncMachine.SyncFailed.self, .offline: SyncMachine.SyncOffline.self,
        ]) as any StateMachine<SyncPhase>, TableMachine(table)] {
            log = []
            m.enter(.done) // refused (idle → done): no effects
            m.enter(.reading)
            m.enter(.uploading)
            #expect(log == ["exit idle to reading", "enter reading from idle",
                            "exit reading to uploading", "enter uploading from reading"])
        }
    }
}
