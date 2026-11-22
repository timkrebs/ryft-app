#if canImport(PostHog)
import Foundation
import os

/// The SDK's only way out. posthog-ios 3.98.2 builds every request from one `URLSession` made from
/// `config.urlSessionConfiguration` (`PostHogApi`), and this protocol is first in its `protocolClasses`, so a request
/// leaves only while the fence is open and goes to `AnalyticsDestination.allowedHost` over HTTPS. Everything else
/// fails at once: the remote config `setup` always fetches from `eu-assets.i.posthog.com` (no public switch), a redirect
/// to another host, and whatever `close()`'s flush sends after `stop()` closed the fence.
final class PostHogFence: URLProtocol {
    /// Static, because URLSession makes its own instances; locked, because URLSession asks from its own queues.
    private static let state = OSAllocatedUnfairLock(initialState: false)

    /// Opened by `PostHogSink.start` just before setup; closed first thing in `stop()`.
    nonisolated static func open(_ on: Bool) {
        state.withLock { $0 = on }
    }

    nonisolated static var isOpen: Bool { state.withLock { $0 } }

    /// True unless the fence is open and the request is `https://eu.i.posthog.com/…` exactly.
    nonisolated static func blocks(_ request: URLRequest) -> Bool {
        guard isOpen, let url = request.url, url.scheme?.lowercased() == "https",
              url.host()?.lowercased() == AnalyticsDestination.allowedHost
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
