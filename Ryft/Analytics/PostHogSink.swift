#if canImport(PostHog)
import Foundation
import PostHog

/// The live sink: one posthog-ios instance (3.98.2, pinned exactly; a bump re-reads every fact cited here), never
/// `PostHogSDK.shared`, and never `identify`, `alias`, `group` or `register`, so events carry the SDK's anonymous id
/// and nothing that names a person. `Analytics` has checked the gate before every call.
///
/// The SDK runs no code until `setup`, so creating this sink does nothing either.
@MainActor
final class PostHogSink: AnalyticsSink {
    /// The SDK's own base folder, `Application Support/<bundle id>/`: one child per project key, holding the id and
    /// the queues. The app keeps nothing else there.
    nonisolated static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "com.posthog.unknown",
                                                  directoryHint: .isDirectory)
    }

    private let root: URL
    /// nil while stopped.
    private var sdk: PostHogSDK?

    /// `start` and `stop` do their file work (the SDK's setup, our deletions) on the main actor, as `Analytics` calls
    /// them: a few small files, once per opt-in, opt-out or config change, never per event.
    init(root: URL = PostHogSink.defaultRoot) {
        self.root = root
    }

    var canSend: Bool { true }

    func start(_ destination: AnalyticsDestination, newID: Bool) {
        if sdk != nil { stop() }
        if newID { forgetFiles() }
        PostHogFence.open(true)
        sdk = PostHogSDK.with(Self.configuration(for: destination))
    }

    func capture(_ name: String, properties: [String: String]) {
        sdk?.capture(name, properties: properties)
    }

    /// The fence closes first, so nothing of the SDK's leaves from here; then the queues go from disk, also for a
    /// project not set up in this process. Only then `close()`: in 3.98.2 it flushes one batch first and leaves the
    /// rest for the next setup, so on its own it would send after an opt-out. Its flush finds no files (missing ones
    /// are skipped) and is fenced anyway. The queues go once more after it, for a capture already handed to the SDK's
    /// own queue that wrote its file after the first deletion. A batch already on the wire can't be recalled; it was
    /// captured while opted in.
    func stop() {
        PostHogFence.open(false)
        deleteQueues()
        sdk?.close()
        deleteQueues()
        sdk = nil
    }

    /// The SDK's `reset()` keeps `$device_id` ("persists across identify() and reset()" in 3.98.2), so the id is
    /// forgotten by deleting the SDK's files: every project's ids, flags and queues.
    func forgetID() {
        stop()
        forgetFiles()
    }

    // MARK: files

    /// What the SDK queues to send, per project folder (and in `root` itself, where pre-3.x SDKs kept them):
    /// 3.98.2's `StorageKey` raw values for the event, replay and log queues, and the opt-out state. The ids stay.
    nonisolated static let queueFiles = [
        "posthog.queueFolder.uuid", "posthog.queueFolder", "posthog.queue.plist",
        "posthog.replayFolder.uuid", "posthog.replayFolder", "posthog.replayBufferFolder",
        "posthog.logsFolder", "posthog.optOut",
    ]

    func deleteQueues() {
        let files = FileManager.default
        let projects = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let isFolder = { (url: URL) in (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        for folder in [root] + projects.filter(isFolder) {
            for name in Self.queueFiles {
                try? files.removeItem(at: folder.appending(path: name))
            }
        }
    }

    /// Everything the SDK keeps: the next setup makes a new anonymous id and a new `$device_id`.
    func forgetFiles() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: configuration

    /// Only what the contract allows: our events, and the SDK's lifecycle ones. 3.98.2's defaults that would collect
    /// more are turned off: screen views, rage clicks, push-token registration and push opens (which send the APNs
    /// token to PostHog), surveys, feature flags and their events, default person properties, swizzling. Autocapture,
    /// session replay and crash autocapture are off by default and stated anyway. Remote config is always fetched at
    /// setup, from `eu-assets.i.posthog.com`; the fence refuses it.
    nonisolated static func configuration(for destination: AnalyticsDestination) -> PostHogConfig {
        let config = PostHogConfig(projectToken: destination.projectKey, host: destination.host.absoluteString)
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.captureSwiftUIElementInteractions = false
        config.rageClickConfig.enabled = false
        config.sessionReplay = false
        config.surveys = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.setDefaultPersonProperties = false
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        config.errorTrackingConfig.autoCapture = false
        config.enableSwizzling = false
        config.debug = false

        config.captureApplicationLifecycleEvents = true
        config.personProfiles = .identifiedOnly
        config.disableGeoIp = true
        config.flushAt = 10
        config.maxQueueSize = 200

        // Ephemeral: no cookies, cache or credentials on disk. The fence goes first, so it sees every request.
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [PostHogFence.self] + (session.protocolClasses ?? [])
        config.urlSessionConfiguration = session

        config.setBeforeSend(PostHogSink.sanitize)
        return config
    }

    // MARK: sanitising

    /// `AnalyticsEvent`'s names, and the lifecycle events that say the app was installed, opened or backgrounded.
    /// Everything else is dropped: `$screen`, `$rageclick`, `$exception`, `$identify`, `$set`, `$feature_flag_called`,
    /// `$snapshot`, `Application Updated` and whatever a later SDK adds.
    nonisolated static let allowedEvents: Set<String> = [
        "onboarding_step", "health_access_requested", "first_sync_completed", "screen_viewed", "feature_used",
        "error_shown",
        "Application Installed", "Application Opened", "Application Backgrounded",
    ]

    /// Our own keys; the SDK's app, OS, library and session keys; and the lifecycle events' own. Gone are the device's
    /// id, name and model, locale, time zone, network, screen size, person properties (`$set`), and the opened URL.
    nonisolated static let allowedProperties: Set<String> = [
        "step", "screen", "feature", "status", "code",
        "$app_version", "$app_build", "$os_name", "$os_version", "$device_type", "$lib", "$lib_version",
        "$session_id", "$process_person_profile", "$geoip_disable",
        "version", "build", "previous_version", "previous_build", "from_background",
    ]

    /// The `beforeSend` hook: an unlisted event is dropped, a listed one keeps only listed keys. The SDK runs it before
    /// an event is queued, on the capture caller's thread.
    nonisolated static func sanitize(_ event: PostHogEvent) -> PostHogEvent? {
        guard let properties = sanitized(event: event.event, properties: event.properties) else { return nil }
        event.properties = properties
        return event
    }

    /// `sanitize` on plain values: `PostHogEvent` has no public initialiser.
    nonisolated static func sanitized(event: String, properties: [String: Any]) -> [String: Any]? {
        guard allowedEvents.contains(event) else { return nil }
        return properties.filter { allowedProperties.contains($0.key) }
    }
}
#endif
