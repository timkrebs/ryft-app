#if canImport(PostHog)
/// Phase 1's placeholder, so the build stays green once the posthog-ios package is added in Xcode and before phase 2
/// writes the adapter here (design.md, decision 16). It sends nothing and can't send, so no prompt or switch shows.
final class PostHogSink: AnalyticsSink {
    func start(_ destination: AnalyticsDestination, newID: Bool) {}
    func capture(_ name: String, properties: [String: String]) {}
    func stop() {}
    func forgetID() {}
    var canSend: Bool { false }
}
#endif
