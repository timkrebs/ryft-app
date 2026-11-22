#if canImport(PostHog)
import Foundation
import PostHog
import Testing
@testable import Ryft

// A1 to A4 of docs/work/2026-11-22-analytics-sdk/plan.md. Nothing here starts the SDK (`PostHogSDK.with`/`setup`), so
// nothing touches the network: the configuration and the sanitiser are pure, and the files are a temporary directory's.

// MARK: - A1, A2: what the configuration and the sanitiser allow

@Suite("PostHog adapter: configuration and sanitiser")
struct PostHogConfigurationTests {
    private func config() throws -> PostHogConfig {
        PostHogSink.configuration(for: try #require(AnalyticsDestination(AnalyticsFixture.config)))
    }

    // MARK: A1

    @Test func configurationTurnsEverythingOffButLifecycle() throws {
        let config = try config()
        #expect(!config.captureScreenViews)
        #expect(!config.captureElementInteractions)
        #expect(!config.captureSwiftUIElementInteractions)
        #expect(!config.rageClickConfig.enabled)
        #expect(!config.sessionReplay)
        #expect(!config.surveys)
        #expect(!config.preloadFeatureFlags)
        #expect(!config.sendFeatureFlagEvent)
        #expect(!config.setDefaultPersonProperties)
        #expect(!config.capturePushNotificationSubscriptions)
        #expect(!config.capturePushNotificationOpened)
        #expect(!config.errorTrackingConfig.autoCapture)
        #expect(!config.enableSwizzling)
        #expect(!config.debug)
        #expect(!config.optOut, "opting out is Analytics' gate, not the SDK's flag")
    }

    @Test func configurationKeepsTheLifecycleEventsAndTheContractsLimits() throws {
        let config = try config()
        #expect(config.captureApplicationLifecycleEvents)
        #expect(config.personProfiles == .identifiedOnly)
        #expect(config.disableGeoIp)
        #expect(config.flushAt == 10)
        #expect(config.maxQueueSize == 200)
    }

    @Test func configurationSendsToTheDestinationOnly() throws {
        let config = try config()
        #expect(config.host.scheme == "https" && config.host.host() == AnalyticsDestination.allowedHost)
        #expect(config.projectToken == AnalyticsFixture.key)
        let other = PostHogSink.configuration(for: try #require(AnalyticsDestination(AnalyticsFixture.otherConfig)))
        #expect(other.projectToken == AnalyticsFixture.otherKey)
    }

    @Test func theSDKsRequestsGoThroughTheFenceFirst() throws {
        let session = try #require(try config().urlSessionConfiguration)
        let classes = try #require(session.protocolClasses)
        #expect(classes.first.map(ObjectIdentifier.init) == ObjectIdentifier(PostHogFence.self))
        #expect(classes.count > 1, "the system's own protocols stay behind it")
    }

    @Test func defaultRootIsTheSDKsBaseFolderInApplicationSupport() {
        let root = PostHogSink.defaultRoot
        #expect(root.lastPathComponent == (Bundle.main.bundleIdentifier ?? "com.posthog.unknown"))
        #expect(root.deletingLastPathComponent().standardizedFileURL == URL.applicationSupportDirectory.standardizedFileURL)
    }

    // MARK: A2

    /// Events that are neither ours nor the three lifecycle ones leave no trace.
    @Test(arguments: ["$screen", "$rageclick", "$exception", "$identify", "$set", "$feature_flag_called", "$snapshot",
                      "$autocapture", "$pageview", "Application Updated", "application opened", "onboarding_step ", ""])
    func sanitizeDropsUnlistedEvents(_ name: String) {
        #expect(PostHogSink.sanitized(event: name, properties: ["step": "health"]) == nil)
    }

    @Test func aContractEventKeepsOnlyAllowedKeys() throws {
        let properties: [String: Any] = [
            "step": "health", "$process_person_profile": false,
            "$device_id": "synthetic-device", "$locale": "de_DE", "$timezone": "Europe/Berlin", "url": "ryft://x",
        ]
        let kept = try #require(PostHogSink.sanitized(event: "onboarding_step", properties: properties))
        #expect(Set(kept.keys) == ["step", "$process_person_profile"])
        #expect(kept["step"] as? String == "health")
        #expect(kept["$process_person_profile"] as? Bool == false)
    }

    @Test(arguments: ["$device_id", "$device_name", "$device_model", "$device_manufacturer", "$locale", "$timezone",
                      "$network_wifi", "$network_cellular", "$screen_width", "$screen_height", "$set", "$set_once", "url",
                      "referring_application", "$referrer", "$ip", "$feature/x", "$active_feature_flags", "email", "distinct_id"])
    func everyOtherKeyIsRemoved(_ key: String) throws {
        let kept = try #require(PostHogSink.sanitized(event: "screen_viewed", properties: ["screen": "today", key: "x"]))
        #expect(kept[key] == nil)
        #expect(kept["screen"] as? String == "today")
    }

    @Test(arguments: ["$app_version", "$app_build", "$os_name", "$os_version", "$device_type", "$lib", "$lib_version",
                      "$session_id", "$process_person_profile", "$geoip_disable", "step", "screen", "feature", "status", "code"])
    func theSDKsAppOSAndLibraryKeysStay(_ key: String) throws {
        let kept = try #require(PostHogSink.sanitized(event: "feature_used", properties: [key: "x"]))
        #expect(kept[key] != nil)
    }

    @Test func theLifecycleEventsKeepTheirOwnKeys() throws {
        for name in ["Application Installed", "Application Opened", "Application Backgrounded"] {
            let kept = try #require(PostHogSink.sanitized(event: name, properties: [
                "version": "1.0", "build": "7", "previous_version": "0.9", "previous_build": "6", "from_background": true,
                "$network_wifi": true, "$screen_width": 390,
            ]))
            #expect(Set(kept.keys) == ["version", "build", "previous_version", "previous_build", "from_background"], "\(name)")
        }
    }

    @Test func applicationInstalledKeepsOnlyVersionAndBuild() throws {
        let kept = try #require(PostHogSink.sanitized(event: "Application Installed", properties: [
            "version": "1.0", "build": "7", "$device_name": "synthetic phone", "url": "ryft://x", "$device_id": "synthetic",
        ]))
        #expect(Set(kept.keys) == ["version", "build"])
    }

    @Test func theAllowListsAreExactlyTheContract() {
        #expect(PostHogSink.allowedEvents == Set(AnalyticsEvent.everyCase.map(\.name))
            .union(["Application Installed", "Application Opened", "Application Backgrounded"]))
        #expect(!PostHogSink.allowedEvents.contains { $0.hasPrefix("$") })
        #expect(!PostHogSink.allowedProperties.contains("$device_id"))
        #expect(!PostHogSink.allowedProperties.contains("$set"))
    }

    /// What `Analytics` sends passes through untouched: no event of ours is lost to the allow-lists.
    @Test func everyEventOfOursPassesUnchanged() throws {
        for event in AnalyticsEvent.everyCase {
            let kept = try #require(PostHogSink.sanitized(event: event.name, properties: event.properties), "\(event.name)")
            #expect(kept as? [String: String] == event.properties, "\(event.name)")
        }
    }
}

// MARK: - A3, A4: the fence and the files

/// Everything that reads or writes `PostHogFence`'s one process-wide switch, or calls `stop()` (which closes it), runs
/// here, one test at a time, and leaves it closed. Never a request to the real host: with the fence open only a
/// request the fence blocks is made.
@Suite("PostHog adapter: the fence and the files", .serialized)
@MainActor
struct PostHogFenceTests {
    init() { PostHogFence.open(false) }

    private func request(_ url: String) throws -> URLRequest {
        URLRequest(url: try #require(URL(string: url)))
    }

    // MARK: A3

    @Test func theFenceStartsClosed() {
        #expect(!PostHogFence.isOpen)
        #expect(PostHogFence.blocks(URLRequest(url: URL(filePath: "/"))))
    }

    /// Only the event batch may leave, and only while open.
    @Test(arguments: ["https://eu.i.posthog.com/batch", "https://eu.i.posthog.com/batch/", "https://EU.i.posthog.com/batch/"])
    func fenceAllowsTheBatchOnTheAllowedHostOnlyWhenOpen(_ url: String) throws {
        let batch = try request(url)
        #expect(PostHogFence.blocks(batch), "closed: \(url)")
        PostHogFence.open(true)
        defer { PostHogFence.open(false) }
        #expect(PostHogFence.isOpen)
        #expect(!PostHogFence.blocks(batch), "open: \(url)")
        PostHogFence.open(false)
        #expect(PostHogFence.blocks(batch), "closed again: \(url)")
    }

    @Test func everythingIsBlockedWhenClosed() throws {
        for url in ["https://eu.i.posthog.com/batch", "https://eu.i.posthog.com/batch/", "https://eu.i.posthog.com/flags",
                    "https://eu-assets.i.posthog.com/array/phc_x/config", "https://api.ryftlab.de/v1/me"] {
            #expect(PostHogFence.blocks(try request(url)), "\(url)")
        }
    }

    @Test func theAllowedPathsAreTheBatchOnly() {
        #expect(PostHogFence.allowedPaths == ["/batch", "/batch/"])
    }

    @Test(arguments: [
        "https://eu-assets.i.posthog.com/array/phc_x/config",
        "https://us.i.posthog.com/batch/",
        "https://us-assets.i.posthog.com/array/phc_x/config",
        "https://api.ryftlab.de/v1/me",
        "http://eu.i.posthog.com/batch",
        "http://eu.i.posthog.com/batch/",
        "https://eu.i.posthog.com.example.org/batch/",
        "https://example.org/eu.i.posthog.com/batch/",
        "https://eu.i.posthog.com@example.org/batch/",
        "https://user@eu.i.posthog.com/batch",
        "ftp://eu.i.posthog.com/batch/",
        // The allowed host, but not the batch (path, query, port).
        "https://eu.i.posthog.com/flags",
        "https://eu.i.posthog.com/flags/?v=2",
        "https://eu.i.posthog.com/api/push_subscriptions/",
        "https://eu.i.posthog.com/i/v1/logs",
        "https://eu.i.posthog.com/i/v0/e/",
        "https://eu.i.posthog.com/s/",
        "https://eu.i.posthog.com/",
        "https://eu.i.posthog.com",
        "https://eu.i.posthog.com/batch/extra",
        "https://eu.i.posthog.com/batch?x=1",
        "https://eu.i.posthog.com/batch/?x=1",
        "https://eu.i.posthog.com:8443/batch",
        "https://eu.i.posthog.com:443/batch",
    ])
    func fenceBlocksOtherHostsSchemesAndPathsEvenWhenOpen(_ url: String) throws {
        let request = try request(url)
        PostHogFence.open(true)
        defer { PostHogFence.open(false) }
        #expect(PostHogFence.blocks(request), "\(url)")
        #expect(PostHogFence.canInit(with: request), "a blocked request is claimed by the fence: \(url)")
    }

    @Test func theFenceLetsAnAllowedRequestPassToTheSystem() throws {
        PostHogFence.open(true)
        defer { PostHogFence.open(false) }
        // Not claimed, so the system's HTTP loader takes it. Nothing is sent here: only `canInit` is asked.
        #expect(!PostHogFence.canInit(with: try request("https://eu.i.posthog.com/batch/")))
    }

    @Test func aBlockedRequestFailsAtOnceAndNeverLeaves() async throws {
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [PostHogFence.self]
        let urlSession = URLSession(configuration: session)
        defer { urlSession.invalidateAndCancel() }
        // Open, but another host: blocked.
        PostHogFence.open(true)
        defer { PostHogFence.open(false) }
        do {
            _ = try await urlSession.data(for: try request("https://eu-assets.i.posthog.com/array/phc_x/config"))
            Issue.record("the assets host was reached")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        }
        // Closed, the allowed host too.
        PostHogFence.open(false)
        do {
            _ = try await urlSession.data(for: try request("https://eu.i.posthog.com/batch/"))
            Issue.record("the allowed host was reached with the fence closed")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        }
    }

    // MARK: A4

    /// A fake `Application Support/<bundle id>/` with two projects, in the file and folder names of posthog-ios 3.98.2.
    private struct Fake {
        let root: URL
        let projects: [URL]

        static let queueNames = PostHogSink.queueFiles
        static let kept = ["posthog.anonymousId", "posthog.deviceId"]

        init() throws {
            let files = FileManager.default
            let root = files.temporaryDirectory.appending(path: "ryft-posthog-test-\(UUID().uuidString)", directoryHint: .isDirectory)
            self.root = root
            projects = [AnalyticsFixture.key, AnalyticsFixture.otherKey].map {
                root.appending(path: $0, directoryHint: .isDirectory)
            }
            for project in projects {
                try files.createDirectory(at: project, withIntermediateDirectories: true)
                for name in Self.queueNames {
                    try Self.write(project.appending(path: name))
                }
                for name in Self.kept {
                    try Data("synthetic id".utf8).write(to: project.appending(path: name))
                }
            }
            // The queues of a pre-3.x layout sit in the root itself.
            try Self.write(root.appending(path: "posthog.queue.plist"))
            try Self.write(root.appending(path: "posthog.queueFolder"))
            try Data("not ours".utf8).write(to: root.appending(path: "unrelated.txt"))
        }

        /// A folder with a file in it, as a queue folder is; a plain file for the rest (a name with an extension).
        private static func write(_ url: URL) throws {
            if url.pathExtension.isEmpty || url.lastPathComponent.hasSuffix("Folder") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data("{}".utf8).write(to: url.appending(path: "event.json"))
            } else {
                try Data("synthetic".utf8).write(to: url)
            }
        }

        func exists(_ name: String, in folder: URL) -> Bool {
            FileManager.default.fileExists(atPath: folder.appending(path: name).path)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func stopDeletesQueuesEvenWithoutSetup() throws {
        let fake = try Fake()
        defer { fake.remove() }
        PostHogFence.open(true)
        defer { PostHogFence.open(false) }
        let sink = PostHogSink(root: fake.root)

        sink.stop()

        for project in fake.projects {
            for name in Fake.queueNames { #expect(!fake.exists(name, in: project), "\(name) in a project folder") }
            for name in Fake.kept { #expect(fake.exists(name, in: project), "the anonymous id stays: \(name)") }
        }
        for name in Fake.queueNames { #expect(!fake.exists(name, in: fake.root), "\(name) in the root") }
        #expect(fake.exists("unrelated.txt", in: fake.root), "only the SDK's own names go")
        #expect(!PostHogFence.isOpen, "stop closes the fence first")
    }

    @Test func stopWithNothingOnDiskDoesNothing() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "ryft-posthog-none-\(UUID().uuidString)")
        let sink = PostHogSink(root: missing)
        sink.stop()
        sink.stop()
        #expect(!FileManager.default.fileExists(atPath: missing.path), "stop creates nothing")
        #expect(!PostHogFence.isOpen)
    }

    @Test func deleteQueuesLeavesTheIdsAndTheFenceAlone() throws {
        let fake = try Fake()
        defer { fake.remove() }
        PostHogFence.open(true)
        defer { PostHogFence.open(false) }
        PostHogSink(root: fake.root).deleteQueues()
        for project in fake.projects {
            for name in Fake.kept { #expect(fake.exists(name, in: project)) }
            for name in Fake.queueNames { #expect(!fake.exists(name, in: project)) }
        }
        #expect(PostHogFence.isOpen, "only stop() closes it")
    }

    @Test func forgetIDDeletesEverything() throws {
        let fake = try Fake()
        defer { fake.remove() }
        PostHogFence.open(true)
        defer { PostHogFence.open(false) }

        PostHogSink(root: fake.root).forgetID()

        #expect(!FileManager.default.fileExists(atPath: fake.root.path), "the ids, the flags and the queues of every project")
        #expect(!PostHogFence.isOpen)
    }

    /// `start(_, newID: true)` forgets through `forgetFiles()` before it sets the SDK up; tests never set it up.
    @Test func startWithNewIDForgetsFirst() throws {
        let fake = try Fake()
        defer { fake.remove() }
        let sink = PostHogSink(root: fake.root)

        sink.forgetFiles()
        #expect(!FileManager.default.fileExists(atPath: fake.root.path))
        sink.forgetFiles() // nothing there: no error
    }

    @Test func aStoppedSinkCapturesNothingAndWritesNothing() throws {
        let fake = try Fake()
        defer { fake.remove() }
        let sink = PostHogSink(root: fake.root)
        sink.stop()
        let before = try FileManager.default.subpathsOfDirectory(atPath: fake.root.path).sorted()

        sink.capture("screen_viewed", properties: ["screen": "today"])

        #expect(try FileManager.default.subpathsOfDirectory(atPath: fake.root.path).sorted() == before)
        #expect(sink.canSend)
    }
}
#endif
