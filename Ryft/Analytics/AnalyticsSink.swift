import Foundation

/// What sends: the SDK behind a seam (phase 2's `PostHogSink`), a no-op everywhere else. `Analytics` is its only
/// caller and has already checked the gate; a sink never decides on its own whether to send.
@MainActor
protocol AnalyticsSink: AnyObject {
    /// Sending to `destination` from now on, replacing any other. `newID`: forget the stored anonymous id first.
    func start(_ destination: AnalyticsDestination, newID: Bool)
    func capture(_ name: String, properties: [String: String])
    /// Stop sending and drop everything queued, in memory and on disk. Keeps the id.
    func stop()
    /// Delete the stored anonymous id now (and anything queued), also when nothing was started in this process: an
    /// opt-out or a sign-out. The next `start` makes a new one.
    func forgetID()
    /// False for the no-op: no prompt and no toggle are shown for a sink that can't send (design.md, decision 13).
    var canSend: Bool { get }
}

/// Sends nothing, keeps nothing: previews, tests, the simulator, Debug device builds without `-RyftAnalytics`, and
/// every build until the SDK is added (phase 2).
final class NoopAnalyticsSink: AnalyticsSink {
    /// Nonisolated: it holds nothing, and it's a default argument of `AppEnvironment`'s initialisers.
    nonisolated init() {}

    func start(_ destination: AnalyticsDestination, newID: Bool) {}
    func capture(_ name: String, properties: [String: String]) {}
    func stop() {}
    func forgetID() {}
    var canSend: Bool { false }
}

enum AnalyticsSinks {
    /// The one switch for the live graph. The simulator never sends; a Debug device build only with
    /// `-RyftAnalytics` (phase 2's check), so developers don't fill the dashboards; without the SDK, nothing.
    @MainActor
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AnalyticsSink {
        #if targetEnvironment(simulator)
        return NoopAnalyticsSink()
        #elseif canImport(PostHog)
        #if DEBUG
        guard arguments.contains("-RyftAnalytics") else { return NoopAnalyticsSink() }
        #endif
        return PostHogSink()
        #else
        return NoopAnalyticsSink()
        #endif
    }
}
