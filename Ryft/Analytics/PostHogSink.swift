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
        config.personProfiles = .never
        config.disableGeoIp = true
        config.flushAt = 10
        config.maxQueueSize = 200

        // Ephemeral: no cookies, cache or credentials on disk. The fence goes first, so it sees every request.
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [PostHogFence.self] + (session.protocolClasses ?? [])
        config.urlSessionConfiguration = session

        config.setBeforeSend(PostHogSink.sanitize)
        assert(AnalyticsSDKSettings(config) == .required, "PostHogConfig drifted from AnalyticsSDKSettings.required")
        return config
    }

    // MARK: sanitising

    /// The `beforeSend` hook, the last check before the SDK queues an event (on the capture caller's thread). The
    /// allow-list is `AnalyticsCatalog`'s, nothing of its own: see `sanitized(event:properties:)`.
    nonisolated static func sanitize(_ event: PostHogEvent) -> PostHogEvent? {
        guard let properties = sanitized(event: event.event, properties: event.properties) else { return nil }
        event.properties = properties
        return event
    }

    /// `sanitize` on plain values (`PostHogEvent` has no public initialiser). nil drops the event.
    /// - A key `AnalyticsCatalog.isDeniedKey` names (a food, a query, a health or body value, a person) drops the whole
    ///   event, on any event: something smuggled it past `Analytics.deliver`, so nothing of that event is trusted.
    /// - The lifecycle events (`AnalyticsCatalog.sdkEventNames`) keep only `sdkPropertyKeys`.
    /// - Our events keep `sdkPropertyKeys` and their own keys, and their own part has to pass `AnalyticsCatalog.check`
    ///   again (a non-string value fails it). Any other key, which the SDK added (the device's id, name and model,
    ///   locale, time zone, network, screen size, `$set`, the opened URL), is dropped.
    /// - Every other event is dropped: `$screen`, `$rageclick`, `$exception`, `$identify`, `$set`,
    ///   `$feature_flag_called`, `$snapshot`, `Application Updated` and whatever a later SDK adds.
    nonisolated static func sanitized(event: String, properties: [String: Any]) -> [String: Any]? {
        if properties.keys.contains(where: AnalyticsCatalog.isDeniedKey) { return nil }
        let sdk = properties.filter { AnalyticsCatalog.sdkPropertyKeys.contains($0.key) }
        if AnalyticsCatalog.sdkEventNames.contains(event) { return sdk }
        guard let listed = AnalyticsCatalog.events[event] else { return nil }
        var ours: [String: String] = [:]
        for (key, value) in properties where listed[key] != nil {
            guard let value = value as? String else { return nil }
            ours[key] = value
        }
        guard AnalyticsCatalog.check(name: event, properties: ours) == nil else { return nil }
        return sdk.merging(ours) { _, own in own }
    }
}

extension AnalyticsSDKSettings {
    /// What a `PostHogConfig` would do, as the SDK-free value `configuration(for:)` asserts against `.required`.
    /// `identifies` isn't a config setting: RYFT never calls `identify` or `alias` (no call site; the sink has no API
    /// for it), so it is `false` by construction.
    init(_ config: PostHogConfig) {
        let profiles: PersonProfiles
        switch config.personProfiles {
        case .never: profiles = .never
        case .always: profiles = .always
        case .identifiedOnly: profiles = .identifiedOnly
        @unknown default: profiles = .always
        }
        self.init(
            sessionReplay: config.sessionReplay,
            captureScreenViews: config.captureScreenViews,
            captureElementInteractions: config.captureElementInteractions,
            captureSwiftUIElementInteractions: config.captureSwiftUIElementInteractions,
            rageClicks: config.rageClickConfig.enabled,
            surveys: config.surveys,
            preloadFeatureFlags: config.preloadFeatureFlags,
            sendFeatureFlagEvent: config.sendFeatureFlagEvent,
            setDefaultPersonProperties: config.setDefaultPersonProperties,
            capturePushNotificationSubscriptions: config.capturePushNotificationSubscriptions,
            capturePushNotificationOpened: config.capturePushNotificationOpened,
            crashAutocapture: config.errorTrackingConfig.autoCapture,
            swizzling: config.enableSwizzling,
            debug: config.debug,
            captureApplicationLifecycleEvents: config.captureApplicationLifecycleEvents,
            personProfiles: profiles,
            identifies: false,
            disableGeoIp: config.disableGeoIp
        )
    }
}
#endif
