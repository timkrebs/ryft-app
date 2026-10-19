import Foundation
import GameplayKit

/// A finite state machine over an enum, behind a protocol so the engine can be
/// swapped. `GKTableMachine` runs on GameplayKit's `GKStateMachine` (WHOOP uses
/// GameKit's for the same job); `TableMachine` is the plain-Swift equivalent.
/// Both enforce the same transition table and fire the same entry/exit effects.
@MainActor
protocol StateMachine<State>: AnyObject {
    associatedtype State: Hashable & CaseIterable & Sendable
    var state: State { get }
    func canEnter(_ next: State) -> Bool
    /// Moves to `next` when the table allows it; otherwise stays and returns `false`.
    @discardableResult func enter(_ next: State) -> Bool
}

/// Which states may follow which, and what happens on the way.
struct TransitionTable<State: Hashable & CaseIterable & Sendable> {
    let initial: State
    let edges: [State: Set<State>]
    /// Called after leaving `from` (`willExit`).
    var onExit: (@MainActor (_ from: State, _ to: State) -> Void)? = nil
    /// Called after entering `to` (`didEnter`).
    var onEnter: (@MainActor (_ to: State, _ from: State) -> Void)? = nil

    func allows(_ from: State, _ to: State) -> Bool { edges[from]?.contains(to) ?? false }

    /// Every allowed (from, to) pair, for tests that walk each edge.
    var allEdges: [(State, State)] {
        State.allCases.flatMap { from in State.allCases.filter { allows(from, $0) }.map { (from, $0) } }
    }

    /// The shortest path of allowed transitions from `initial` to `target` (excluding `initial`).
    func path(to target: State) -> [State]? {
        if target == initial { return [] }
        var queue: [(State, [State])] = [(initial, [])]
        var seen: Set<State> = [initial]
        while !queue.isEmpty {
            let (s, p) = queue.removeFirst()
            for next in edges[s] ?? [] where !seen.contains(next) {
                if next == target { return p + [next] }
                seen.insert(next)
                queue.append((next, p + [next]))
            }
        }
        return nil
    }
}

// MARK: - GameplayKit engine

/// One `GKState` per enum case. GameplayKit identifies states by class, so each
/// case gets a subclass; `GKTableMachine` makes them from the table.
class TableGKState<State: Hashable & CaseIterable & Sendable>: GKState {
    let value: State
    unowned let owner: GKTableMachine<State>

    required init(value: State, owner: GKTableMachine<State>) {
        self.value = value
        self.owner = owner
        super.init()
    }

    // GameplayKit calls these on the thread that called `enter`: the main actor.
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        MainActor.assumeIsolated {
            guard let next = owner.value(for: stateClass) else { return false }
            return owner.table.allows(value, next)
        }
    }

    override func didEnter(from previousState: GKState?) {
        guard let from = (previousState as? TableGKState<State>)?.value else { return }
        let to = value
        MainActor.assumeIsolated { owner.table.onEnter?(to, from) }
    }

    override func willExit(to nextState: GKState) {
        guard let to = (nextState as? TableGKState<State>)?.value else { return }
        let from = value
        MainActor.assumeIsolated { owner.table.onExit?(from, to) }
    }
}

@MainActor
final class GKTableMachine<State: Hashable & CaseIterable & Sendable>: StateMachine {
    let table: TransitionTable<State>
    private var gk: GKStateMachine!
    private var classes: [State: AnyClass] = [:]
    private var values: [ObjectIdentifier: State] = [:]

    /// `classes` maps each case to its `TableGKState` subclass (one per case, see the machines).
    init(_ table: TransitionTable<State>, classes: [State: TableGKState<State>.Type]) {
        self.table = table
        var states: [GKState] = []
        for value in State.allCases {
            guard let cls = classes[value] else { preconditionFailure("No GKState class for \(value)") }
            self.classes[value] = cls
            values[ObjectIdentifier(cls)] = value
            states.append(cls.init(value: value, owner: self))
        }
        gk = GKStateMachine(states: states)
        gk.enter(classes[table.initial]!)
    }

    func value(for stateClass: AnyClass) -> State? { values[ObjectIdentifier(stateClass)] }

    var state: State { (gk.currentState as? TableGKState<State>)?.value ?? table.initial }

    func canEnter(_ next: State) -> Bool {
        guard let cls = classes[next] else { return false }
        return gk.canEnterState(cls)
    }

    @discardableResult
    func enter(_ next: State) -> Bool {
        guard let cls = classes[next] else { return false }
        return gk.enter(cls)
    }
}

// MARK: - plain Swift engine

@MainActor
final class TableMachine<State: Hashable & CaseIterable & Sendable>: StateMachine {
    let table: TransitionTable<State>
    private(set) var state: State

    init(_ table: TransitionTable<State>) {
        self.table = table
        state = table.initial
    }

    func canEnter(_ next: State) -> Bool { table.allows(state, next) }

    @discardableResult
    func enter(_ next: State) -> Bool {
        guard canEnter(next) else { return false }
        let from = state
        table.onExit?(from, next)
        state = next
        table.onEnter?(next, from)
        return true
    }
}
