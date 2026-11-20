import Foundation
import Testing
@testable import Ryft

/// `GET /v1/config` → `analytics` (API.md, D231 and D247). Inline JSON: the shared `remote_config` fixture is PR 1's.
@Suite("Analytics: the config's analytics field")
@MainActor
struct AnalyticsConfigDecodingTests {
    /// API.md's first example: the flag on and a destination. Its key is a placeholder there.
    private static let enabledExample = #"""
    {"flags": {"analytics.enabled": true}, "evaluated_at": "2026-11-20T06:12:00Z", "ttl_sec": 21600,
     "privacy_policy_version": "2026-10-26", "privacy_policy_url": "https://ryftlab.de/privacy",
     "analytics": {"host": "https://eu.i.posthog.com", "project_key": "phc_…"}, "app_attest": "off"}
    """#

    /// API.md's second example: the flag off, `analytics` null.
    private static let disabledExample = #"""
    {"flags": {"analytics.enabled": false}, "evaluated_at": "2026-11-20T06:12:00Z", "ttl_sec": 21600,
     "analytics": null, "app_attest": "warn"}
    """#

    private static let cachedBefore = #"""
    {"flags": {"train.enabled": true}, "evaluated_at": "2026-10-19T06:12:00Z", "ttl_sec": 21600,
     "privacy_policy_version": "2026-10-20", "privacy_policy_url": "https://ryftlab.de/privacy"}
    """#

    private func decode(_ json: String) throws -> RemoteConfig {
        try APIClient.jsonDecoder.decode(RemoteConfig.self, from: Data(json.utf8))
    }

    @Test func analyticsDecodesFromAPIExample() throws {
        let config = try decode(Self.enabledExample)
        #expect(config.flags["analytics.enabled"] == true)
        #expect(config.ttlSec == 21_600)
        #expect(config.privacyPolicyVersion == "2026-10-26" && config.privacyPolicyUrl == "https://ryftlab.de/privacy")
        #expect(config.analytics == AnalyticsConfig(host: "https://eu.i.posthog.com", projectKey: "phc_…"))
    }

    @Test func theExamplesPlaceholderKeyDecodesButIsNotADestination() throws {
        let config = try decode(Self.enabledExample)
        #expect(config.analytics != nil)
        #expect(AnalyticsDestination(config.analytics) == nil)
    }

    @Test func aRealShapedKeyFromTheSameShapeIsADestination() throws {
        let json = Self.enabledExample.replacingOccurrences(of: "phc_…", with: AnalyticsFixture.key)
        let destination = try #require(AnalyticsDestination(decode(json).analytics))
        #expect(destination.host.absoluteString == "https://eu.i.posthog.com" && destination.projectKey == AnalyticsFixture.key)
    }

    @Test func analyticsNullDecodesAsNil() throws {
        let config = try decode(Self.disabledExample)
        #expect(config.flags["analytics.enabled"] == false)
        #expect(config.analytics == nil)
        #expect(config.privacyPolicyVersion == nil)
    }

    @Test func configCachedWithoutAnalyticsDecodes() throws {
        let config = try decode(Self.cachedBefore)
        #expect(config.analytics == nil)
        #expect(config.flags["train.enabled"] == true)
        #expect(config.privacyPolicyVersion == "2026-10-20")
    }

    /// A full config around a given `analytics` value.
    private func config(analytics: String) -> String {
        #"{"flags": {"analytics.enabled": true, "train.enabled": true}, "evaluated_at": "2026-11-20T06:12:00Z", "ttl_sec": 21600,"#
            + #" "privacy_policy_version": "2026-10-26", "analytics": "# + analytics + "}"
    }

    @Test(arguments: [
        #"{"host": "https://eu.i.posthog.com"}"#, // project_key missing
        #"{"project_key": "phc_testKEY1234567890"}"#, // host missing; gitleaks:allow (synthetic)
        #"{"host": 7, "project_key": "phc_testKEY1234567890"}"#, // a field of the wrong type; gitleaks:allow (synthetic)
        #"{"host": "https://eu.i.posthog.com", "project_key": null}"#,
        #""x""#, // not an object
        #"[]"#,
        #"42"#,
        #"{}"#,
    ])
    func aMalformedAnalyticsCountsAsNullAndTheRestOfTheConfigDecodes(_ analytics: String) throws {
        let decoded = try decode(config(analytics: analytics))
        #expect(AnalyticsDestination(decoded.analytics) == nil, "\(analytics)")
        #expect(decoded.flags["analytics.enabled"] == true && decoded.flags["train.enabled"] == true)
        #expect(decoded.privacyPolicyVersion == "2026-10-26" && decoded.ttlSec == 21_600)
    }

    @Test func aMalformedAnalyticsNeverOpensTheGateEvenWithTheFlagOnAndOptedIn() throws {
        let decoded = try decode(config(analytics: #"{"host": "https://eu.i.posthog.com"}"#))
        let rig = AnalyticsRig(flag: true, config: decoded.analytics)
        rig.optIn()
        rig.analytics.track(.healthAccessRequested)
        #expect(rig.sink.calls.isEmpty)
    }

    @Test func aWellFormedAnalyticsStillDecodesInsideTheSameFullConfig() throws {
        let decoded = try decode(config(analytics: #"{"host": "https://eu.i.posthog.com", "project_key": "phc_testKEY1234567890"}"#)) // gitleaks:allow (synthetic)
        #expect(decoded.analytics == AnalyticsFixture.config)
    }

    @Test func theFlagStoreCacheKeepsAnalyticsAcrossALaunch() {
        let store = TrainStore(inMemory: true)
        let defaults = AnalyticsRig.freshDefaults()
        let config = RemoteConfig(flags: ["analytics.enabled": true], evaluatedAt: .now, ttlSec: 21_600,
                                  analytics: AnalyticsFixture.config)
        FlagStore(store: store, defaults: defaults, account: "a").apply(config, fetchedAt: .now)

        let relaunched = FlagStore(store: store, defaults: defaults, account: "a")

        #expect(relaunched.analytics == AnalyticsFixture.config)
    }

    @Test func aConfigCachedWithoutAnalyticsGivesAFlagStoreWithNone() throws {
        let store = TrainStore(inMemory: true)
        let defaults = AnalyticsRig.freshDefaults()
        let old = try decode(Self.cachedBefore)
        FlagStore(store: store, defaults: defaults, account: "a").apply(old, fetchedAt: .now)

        let relaunched = FlagStore(store: store, defaults: defaults, account: "a")

        #expect(relaunched.newestAnalytics == nil && !relaunched.newest(.analyticsEnabled))
    }

    @Test func encodingRoundTripsBothFields() throws {
        let config = RemoteConfig(flags: [:], evaluatedAt: Date(timeIntervalSince1970: 1_792_400_000), ttlSec: 60,
                                  analytics: AnalyticsFixture.config)
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(RemoteConfig.self, from: data)
        #expect(back.analytics == AnalyticsFixture.config)
    }
}
