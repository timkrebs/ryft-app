import Foundation
@testable import Ryft

/// One side's platform for the PR 6 R4T tests (the account's, another account's or demo data's): `MockTrainSource`'s
/// answers from `start`. The calls in `holding` wait at a gate until `release()`; a call with a `failures` entry throws it
/// once past the gate. Counts the calls that reached it, by kind.
final class SideTrainSource: TrainDataSource, @unchecked Sendable {
    enum Call: Hashable, CaseIterable {
        case exercises, plans, today, plan, sessions, session, history, enroll, pause, delete
    }

    private let base: MockTrainSource
    private let lock = NSLock()
    private var held: Set<Call>
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var counts: [Call: Int] = [:]
    private var thrown: [Call: Error] = [:]

    init(_ start: MockTrainSource.Start = .demo, holding: Set<Call> = []) {
        base = MockTrainSource(start: start)
        held = holding
    }

    /// Thrown by `call` once past its gate; nil: it answers.
    func fail(_ call: Call, with error: Error?) { lock.withLock { thrown[call] = error } }
    func count(_ call: Call) -> Int { lock.withLock { counts[call, default: 0] } }
    var calls: Int { lock.withLock { counts.values.reduce(0, +) } }

    /// Holds `call` again from now on (calls already past the gate go on).
    func hold(_ call: Call) { lock.withLock { _ = held.insert(call) } }

    /// Opens every gate: the calls waiting go on, and later ones don't wait.
    func release() {
        let parked = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            held = []
            defer { waiting = [] }
            return waiting
        }
        for continuation in parked { continuation.resume() }
    }

    /// What this side answers for `GET /v1/plans` and `/v1/plans/today` now, read past the gate and the counts.
    func plansNow() async throws -> PlansOverview { try await base.plans() }
    func todayNow() async throws -> PlanToday? { try await base.planToday() }
    /// Enrols this side in `plan` before a test starts (not counted).
    func enrollNow(_ plan: UUID) async throws { _ = try await base.enroll(planID: plan) }

    private func pass(_ call: Call) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let open = lock.withLock { () -> Bool in
                counts[call, default: 0] += 1
                let waits = held.contains(call)
                if waits { waiting.append(continuation) }
                return !waits
            }
            if open { continuation.resume() }
        }
        if let error = lock.withLock({ thrown[call] }) { throw error }
    }

    func exercises() async throws -> [Exercise] {
        try await pass(.exercises)
        return try await base.exercises()
    }
    func createExercise(_ e: Exercise) async throws -> Exercise { try await base.createExercise(e) }
    func exerciseHistory(id: UUID) async throws -> ExerciseHistory {
        try await pass(.history)
        return try await base.exerciseHistory(id: id)
    }
    func plans() async throws -> PlansOverview {
        try await pass(.plans)
        return try await base.plans()
    }
    func plan(id: UUID) async throws -> Plan {
        try await pass(.plan)
        return try await base.plan(id: id)
    }
    func savePlan(_ p: Plan) async throws -> Plan { try await base.savePlan(p) }
    func deletePlan(id: UUID) async throws {
        try await pass(.delete)
        try await base.deletePlan(id: id)
    }
    func enroll(planID: UUID) async throws -> Enrollment {
        try await pass(.enroll)
        return try await base.enroll(planID: planID)
    }
    func pauseEnrollment() async throws {
        try await pass(.pause)
        try await base.pauseEnrollment()
    }
    func planToday() async throws -> PlanToday? {
        try await pass(.today)
        return try await base.planToday()
    }
    func sessions(from: Date, to: Date) async throws -> [SessionSummary] {
        try await pass(.sessions)
        return try await base.sessions(from: from, to: to)
    }
    func session(id: UUID) async throws -> TrainSession {
        try await pass(.session)
        return try await base.session(id: id)
    }
    func putSession(_ s: TrainSession) async throws -> SessionPutResult { try await base.putSession(s) }
    func completeSession(id: UUID, _ body: SessionComplete) async throws -> TrainSession {
        try await base.completeSession(id: id, body)
    }
    func deleteSession(id: UUID) async throws { try await base.deleteSession(id: id) }
}

/// Whose binding is in use (`TrainSyncService.Binding.owner`) and which side's platform answers it, switched together as
/// the Demo data switch or a sign-in switches `TrainSource.current` and the outbox's owner. Behind a lock: the library's
/// `remote` is a plain closure.
final class SideSwitch: @unchecked Sendable {
    static let alex = "alex-doe", sam = "sam-roe", demo = TrainSyncService.demoOwner

    private let lock = NSLock()
    private var current: String
    private let sources: [String: SideTrainSource]

    init(_ sources: [String: SideTrainSource], start: String = SideSwitch.alex) {
        self.sources = sources
        current = start
    }

    var owner: String {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    var source: TrainDataSource { lock.withLock { sources[current] } ?? MockTrainSource(start: .empty) }
}

/// A library and its outbox on one in-memory store, answered by the side `sides` has switched to; `reads`: the app's read
/// pipeline (`env.reads`), or none. The paused plan's id is kept in `defaults`, the rig's own suite.
@MainActor
struct TrainSides {
    let sides: SideSwitch
    let store = TrainStore(inMemory: true)
    let defaults = UserDefaults.isolated()
    let outbox: TrainSyncService
    let library: TrainLibrary

    init(_ sources: [String: SideTrainSource], start: String = SideSwitch.alex, reads: ReadScheduler? = nil) {
        let sides = SideSwitch(sources, start: start)
        self.sides = sides
        let outbox = TrainSyncService(store: store, remote: { sides.source }, owner: { sides.owner }, monitorsNetwork: false)
        outbox.gate = { _ in nil }
        self.outbox = outbox
        library = TrainLibrary(store: store, remote: { sides.source }, outbox: { outbox }, restore: false, defaults: defaults)
        library.reads = reads
    }

    /// Profile's Demo data switch, or another account signed in: the binding is `owner`'s from now on.
    func switchTo(_ owner: String) { sides.owner = owner }
}

@MainActor
final class DoneFlag {
    var on = false
}
