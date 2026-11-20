import Foundation
@testable import Ryft

/// A sink that records what `Analytics` asks of it, in order, and pretends to hold a queue the way the SDK will:
/// `capture` queues, `stop()` empties it (design.md decision 8). `canSend` is true unless a test says otherwise.
@MainActor
final class FakeAnalyticsSink: AnalyticsSink {
    struct Start: Equatable {
        let destination: AnalyticsDestination
        let newID: Bool
    }

    struct Capture: Equatable {
        let name: String
        let properties: [String: String]
    }

    /// Every call, in the order it arrived (sync ordering: a stop before the start of a newer destination).
    enum Call: Equatable {
        case start(Start)
        case capture(String)
        case stop
        case forgetID
    }

    private(set) var starts: [Start] = []
    private(set) var captures: [Capture] = []
    private(set) var stops = 0
    /// `forgetID()` calls: the stored anonymous id deleted now, started or not.
    private(set) var forgets = 0
    private(set) var calls: [Call] = []
    /// What the SDK would still hold: captured since the last `stop()`.
    private(set) var queued: [Capture] = []
    var canSend = true

    func start(_ destination: AnalyticsDestination, newID: Bool) {
        let start = Start(destination: destination, newID: newID)
        starts.append(start)
        calls.append(.start(start))
    }

    func capture(_ name: String, properties: [String: String]) {
        let capture = Capture(name: name, properties: properties)
        captures.append(capture)
        queued.append(capture)
        calls.append(.capture(name))
    }

    func stop() {
        stops += 1
        queued.removeAll()
        calls.append(.stop)
    }

    /// Deletes the id and drops the queue too, also when nothing was ever started.
    func forgetID() {
        forgets += 1
        queued.removeAll()
        calls.append(.forgetID)
    }
}
