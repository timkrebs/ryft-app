import Foundation
@testable import Ryft

/// Demo mode as a switch the test flips (`Analytics` asks `isDemo` on every gate run).
@MainActor
final class DemoSwitch {
    var on = false
}

/// Signed in or not, as a switch the test flips.
@MainActor
final class SignedInSwitch {
    var on = true
}

/// Synthetic keys: they pass `AnalyticsDestination`'s check and are nobody's. Not main-actor, so parameterized
/// arguments can use them.
enum AnalyticsFixture {
    static let key = "phc_testKEY1234567890" // gitleaks:allow (synthetic)
    static let config = AnalyticsConfig(host: "https://eu.i.posthog.com", projectKey: key)
    static let otherKey = "phc_otherKEY0987654321" // gitleaks:allow (synthetic)
    /// Same host (the only one a destination accepts), another project: "the newest host and key" differ by the key.
    static let otherConfig = AnalyticsConfig(host: "https://eu.i.posthog.com", projectKey: otherKey)
}

/// One `Analytics` with a fake sink, flags of the test's choosing and defaults of its own (never shared, never
/// `.standard`). `wired` connects `flags.onNewest` to `reevaluate()` the way `ScreenModels` does.
@MainActor
final class AnalyticsRig {
    static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ryft.test.analytics.\(UUID().uuidString)") ?? .standard
    }

    let sink: FakeAnalyticsSink
    let flags: FeatureFlagProvider
    let defaults: UserDefaults
    let demo = DemoSwitch()
    /// Whether anybody is signed in (`on`, the default). Off, the gate is closed.
    let signedIn = SignedInSwitch()
    let analytics: Analytics

    /// `sink` and `defaults`: nil makes a fresh one (default arguments run outside the main actor).
    init(flags: FeatureFlagProvider, sink: FakeAnalyticsSink? = nil, defaults: UserDefaults? = nil, wired: Bool = true) {
        let sink = sink ?? FakeAnalyticsSink()
        let defaults = defaults ?? Self.freshDefaults()
        self.flags = flags
        self.sink = sink
        self.defaults = defaults
        let demo = demo
        let signedIn = signedIn
        analytics = Analytics(sink: sink, flags: flags, defaults: defaults, isDemo: { demo.on },
                              isSignedIn: { signedIn.on })
        if wired { flags.onNewest = { [weak analytics] in analytics?.reevaluate() } }
    }

    /// Static flags: `analytics.enabled` = `flag`, `analytics` = `config`.
    convenience init(flag: Bool = true, config: AnalyticsConfig? = AnalyticsFixture.config,
                     sink: FakeAnalyticsSink? = nil, defaults: UserDefaults? = nil, wired: Bool = true) {
        self.init(flags: StaticFlags([.analyticsEnabled: flag], analytics: config), sink: sink, defaults: defaults,
                  wired: wired)
    }

    /// The static flags of the convenience initialiser; a test using it never has a `FlagStore`.
    var staticFlags: StaticFlags {
        guard let flags = flags as? StaticFlags else { preconditionFailure("this rig runs on a FlagStore") }
        return flags
    }

    /// The prompt's "Share usage data", then the first gate run.
    func optIn() {
        analytics.setOptIn(true)
    }
}
