#if canImport(PostHog)
import Foundation
import os

/// The SDK's only way out. posthog-ios 3.98.2 builds every request from one `URLSession` made from
/// `config.urlSessionConfiguration` (`PostHogApi`), and this protocol is first in its `protocolClasses`, so a request
/// leaves only while the fence is open, and only as `POST https://eu.i.posthog.com/batch` (`AnalyticsDestination
/// .allowedHost`; 3.98.2 builds that path in `PostHogApi.batch`). Everything else fails at once: the remote config
/// `setup` always fetches from `eu-assets.i.posthog.com` (no public switch); `/flags` (it carries `$device_id`) and
/// `/api/push_subscriptions/` (the APNs token) on the allowed host, should a later change ever reach them; the logs and
/// replay endpoints; and whatever `close()`'s flush sends after `stop()` closed the fence. Whether a redirect is asked
/// again is the system's (the SDK's session has no delegate); PostHog's ingestion doesn't redirect.
final class PostHogFence: URLProtocol {
    /// Static, because URLSession makes its own instances; locked, because URLSession asks from its own queues.
    private static let state = OSAllocatedUnfairLock(initialState: false)

    /// Opened by `PostHogSink.start` just before setup; closed first thing in `stop()`.
    nonisolated static func open(_ on: Bool) {
        state.withLock { $0 = on }
    }

    nonisolated static var isOpen: Bool { state.withLock { $0 } }

    /// The only paths that may leave: the event batch.
    nonisolated static let allowedPaths: Set<String> = ["/batch", "/batch/"]

    /// True unless the fence is open and the request is `https://eu.i.posthog.com/batch` exactly (no port, user or
    /// query).
    nonisolated static func blocks(_ request: URLRequest) -> Bool {
        guard isOpen, let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.host?.lowercased() == AnalyticsDestination.allowedHost,
              parts.port == nil, parts.user == nil, parts.password == nil, parts.query == nil,
              allowedPaths.contains(parts.path)
        else { return true }
        return false
    }

    /// Claiming a request is what blocks it; an allowed one goes on to the system's HTTP loader.
    override nonisolated class func canInit(with request: URLRequest) -> Bool { blocks(request) }
    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override nonisolated func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override nonisolated func stopLoading() {}
}
#endif
