import Foundation
import Testing
@testable import Ryft

/// One row of the gate's truth table: `Analytics.destination(flag:config:optIn:demo:)` is open only when all four
/// facts allow it.
struct AnalyticsGateRow: Sendable, CustomTestStringConvertible {
    let flag: Bool
    let config: AnalyticsConfig?
    let optIn: Analytics.OptIn?
    let demo: Bool

    var isOpen: Bool { flag && config != nil && optIn == .optedIn && !demo }

    var testDescription: String {
        "flag \(flag), config \(config == nil ? "null" : "valid"), optIn \(optIn?.rawValue ?? "not asked"), demo \(demo)"
    }

    static let all: [AnalyticsGateRow] = {
        var rows: [AnalyticsGateRow] = []
        for flag in [true, false] {
            for config in [AnalyticsFixture.config, nil] {
                for optIn in [Analytics.OptIn.optedIn, .optedOut, nil] {
                    for demo in [false, true] {
                        rows.append(AnalyticsGateRow(flag: flag, config: config, optIn: optIn, demo: demo))
                    }
                }
            }
        }
        return rows
    }()
}

/// A config that must count as `null`.
private typealias BadDestination = AnalyticsBadDestination

struct AnalyticsBadDestination: Sendable, CustomTestStringConvertible {
    let why: String
    let host: String
    let key: String
    var testDescription: String { why }

    private static let goodHost = "https://eu.i.posthog.com"
    private static let goodKey = AnalyticsFixture.key

    static let all: [AnalyticsBadDestination] = [
        BadDestination(why: "http scheme", host: "http://eu.i.posthog.com", key: goodKey),
        BadDestination(why: "no scheme", host: "eu.i.posthog.com", key: goodKey),
        BadDestination(why: "scheme-relative", host: "//eu.i.posthog.com", key: goodKey),
        BadDestination(why: "a path", host: "https://eu.i.posthog.com/capture", key: goodKey),
        BadDestination(why: "a port", host: "https://eu.i.posthog.com:8443", key: goodKey),
        BadDestination(why: "user info", host: "https://user@eu.i.posthog.com", key: goodKey),
        BadDestination(why: "user and password", host: "https://user:pw@eu.i.posthog.com", key: goodKey),
        BadDestination(why: "a lookalike behind user info", host: "https://eu.i.posthog.com@evil.example.com", key: goodKey),
        BadDestination(why: "a query", host: "https://eu.i.posthog.com?x=1", key: goodKey),
        BadDestination(why: "a fragment", host: "https://eu.i.posthog.com#f", key: goodKey),
        BadDestination(why: "empty host string", host: "", key: goodKey),
        BadDestination(why: "scheme only", host: "https://", key: goodKey),
        BadDestination(why: "not a url", host: "not a url", key: goodKey),
        BadDestination(why: "the US region", host: "https://us.i.posthog.com", key: goodKey),
        BadDestination(why: "another host altogether", host: "https://example.com", key: goodKey),
        BadDestination(why: "empty key", host: goodHost, key: ""),
        BadDestination(why: "the API.md ellipsis placeholder", host: goodHost, key: "phc_…"),
        BadDestination(why: "no phc_ prefix", host: goodHost, key: "testKEY1234567890"), // gitleaks:allow (synthetic)
        BadDestination(why: "another prefix", host: goodHost, key: "pk_testKEY1234567890"), // gitleaks:allow (synthetic)
        BadDestination(why: "uppercase prefix", host: goodHost, key: "PHC_testKEY1234567890"), // gitleaks:allow (synthetic)
        BadDestination(why: "prefix only", host: goodHost, key: "phc_"),
        BadDestination(why: "7 characters after the prefix", host: goodHost, key: "phc_abcdefg"),
        BadDestination(why: "129 characters after the prefix", host: goodHost, key: "phc_" + String(repeating: "a", count: 129)),
        BadDestination(why: "a space in the key", host: goodHost, key: "phc_test KEY123456"),
        BadDestination(why: "a slash in the key", host: goodHost, key: "phc_testKEY12345/6789"),
        BadDestination(why: "a newline in the key", host: goodHost, key: "phc_testKEY1234567\n"), // gitleaks:allow (synthetic)
        BadDestination(why: "a non-ASCII letter in the key", host: goodHost, key: "phc_testKEY123456789é"),
    ]
}

@Suite("Analytics: the gate")
@MainActor
struct AnalyticsGateTests {
    // MARK: nothing before all three hold

    @Test func noEventBeforeOptIn() {
        let rig = AnalyticsRig(flag: true, config: AnalyticsFixture.config)
        for event in AnalyticsEvent.everyCase { rig.analytics.track(event) }
        #expect(rig.sink.calls.isEmpty)
    }

    @Test func noEventAfterDecline() {
        let rig = AnalyticsRig()
        rig.analytics.setOptIn(false)
        for event in AnalyticsEvent.everyCase { rig.analytics.track(event) }
        #expect(rig.sink.starts.isEmpty && rig.sink.captures.isEmpty)
    }

    @Test func noEventWithFlagOff() {
        let rig = AnalyticsRig(flag: false, config: AnalyticsFixture.config)
        rig.optIn()
        for event in AnalyticsEvent.everyCase { rig.analytics.track(event) }
        #expect(rig.sink.calls.isEmpty)
    }

    @Test func noEventWithAnalyticsNull() {
        let rig = AnalyticsRig(flag: true, config: nil)
        rig.optIn()
        for event in AnalyticsEvent.everyCase { rig.analytics.track(event) }
        #expect(rig.sink.calls.isEmpty)
    }

    @Test func noEventInDemoMode() {
        let rig = AnalyticsRig()
        rig.demo.on = true
        rig.optIn()
        for event in AnalyticsEvent.everyCase { rig.analytics.track(event) }
        #expect(rig.sink.calls.isEmpty)
    }

    @Test func noEventWhileSignedOut() {
        let rig = AnalyticsRig()
        rig.signedIn.on = false
        rig.optIn()
        for event in AnalyticsEvent.everyCase { rig.analytics.track(event) }
        #expect(rig.sink.starts.isEmpty && rig.sink.captures.isEmpty)
    }

    @Test func signingInOpensTheGateAndSigningOutClosesItAtOnce() {
        let rig = AnalyticsRig()
        rig.signedIn.on = false
        rig.optIn()
        #expect(rig.sink.calls.isEmpty)

        rig.signedIn.on = true
        rig.analytics.reevaluate()
        rig.analytics.track(.screenViewed(.today))
        #expect(rig.sink.starts.count == 1 && rig.sink.captures.count == 1)

        rig.signedIn.on = false
        rig.analytics.track(.screenViewed(.sleep))
        #expect(rig.sink.stops == 1 && rig.sink.captures.count == 1 && rig.sink.queued.isEmpty)
    }

    @Test func noEventWithAnInvalidConfigEvenWhenTheFlagIsOn() {
        let rig = AnalyticsRig(flag: true, config: AnalyticsConfig(host: "https://eu.i.posthog.com", projectKey: "phc_…"))
        rig.optIn()
        rig.analytics.track(.healthAccessRequested)
        #expect(rig.sink.calls.isEmpty)
    }

    @Test(arguments: AnalyticsGateRow.all)
    func theGateIsOpenOnlyWhenEveryFactAllowsIt(_ row: AnalyticsGateRow) {
        let destination = Analytics.destination(flag: row.flag, config: row.config, optIn: row.optIn, demo: row.demo)
        #expect((destination != nil) == row.isOpen)
        if row.isOpen { #expect(destination == AnalyticsDestination(AnalyticsFixture.config)) }
    }

    @Test(arguments: AnalyticsBadDestination.all)
    func anInvalidDestinationCountsAsNull(_ bad: AnalyticsBadDestination) {
        let config = AnalyticsConfig(host: bad.host, projectKey: bad.key)
        #expect(AnalyticsDestination(config) == nil)
        #expect(Analytics.destination(flag: true, config: config, optIn: .optedIn, demo: false) == nil)
    }

    @Test func boundaryKeysAreAccepted() {
        let keys = ["phc_" + String(repeating: "a", count: 8), "phc_" + String(repeating: "Z", count: 128), "phc_a_b-C0d1"]
        for key in keys {
            let destination = AnalyticsDestination(AnalyticsConfig(host: "https://eu.i.posthog.com", projectKey: key))
            #expect(destination?.projectKey == key, "\(key.count) characters")
        }
        #expect(AnalyticsDestination(nil) == nil)
    }

    @Test(arguments: ["https://EU.I.POSTHOG.COM", "https://Eu.I.PostHog.com"])
    func theHostIsNormalisedToTheOneAllowedHost(_ host: String) {
        let destination = AnalyticsDestination(AnalyticsConfig(host: host, projectKey: AnalyticsFixture.key))
        #expect(destination?.host.absoluteString == "https://eu.i.posthog.com", "\(host)")
    }

    // MARK: sending

    @Test func sendsOnlyWhenAllThreeHold() throws {
        let rig = AnalyticsRig()
        let expected = try #require(AnalyticsDestination(AnalyticsFixture.config))
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))
        #expect(rig.sink.starts == [FakeAnalyticsSink.Start(destination: expected, newID: false)])
        #expect(rig.sink.captures == [FakeAnalyticsSink.Capture(name: "screen_viewed", properties: ["screen": "today"])])
        #expect(rig.sink.calls == [.start(.init(destination: expected, newID: false)), .capture("screen_viewed")])
        #expect(expected.host.absoluteString == "https://eu.i.posthog.com" && expected.projectKey == AnalyticsFixture.key)
    }

    @Test func aSavedOptInStartsAtTheFirstGateRunNotBefore() {
        let defaults = AnalyticsRig.freshDefaults()
        defaults.set("in", forKey: Analytics.optInKey)
        let rig = AnalyticsRig(defaults: defaults)
        #expect(rig.analytics.optIn == .optedIn && rig.sink.calls.isEmpty)
        rig.analytics.reevaluate()
        #expect(rig.sink.starts.count == 1)
        rig.analytics.reevaluate()
        #expect(rig.sink.starts.count == 1, "the same destination again does nothing")
    }

    @Test func noEventIsKeptForLater() {
        let rig = AnalyticsRig()
        rig.analytics.track(.healthAccessRequested) // not asked yet
        rig.optIn()
        #expect(rig.sink.captures.isEmpty)
    }

    @Test func callsArriveInOrderAcrossOptOutAndOptIn() throws {
        let rig = AnalyticsRig()
        let destination = try #require(AnalyticsDestination(AnalyticsFixture.config))
        rig.optIn()
        rig.analytics.track(.screenViewed(.sleep))
        rig.analytics.setOptIn(false)
        rig.analytics.track(.screenViewed(.strain)) // dropped
        rig.optIn()
        rig.analytics.track(.featureUsed(.journalSaved))
        #expect(rig.sink.calls == [
            .start(.init(destination: destination, newID: false)), .capture("screen_viewed"),
            .stop, .forgetID,
            .start(.init(destination: destination, newID: true)), .capture("feature_used"),
        ])
    }

    // MARK: stop and drop

    @Test func flagOffStopsAndDropsQueue() {
        let rig = AnalyticsRig()
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))
        rig.analytics.track(.screenViewed(.sleep))
        #expect(rig.sink.queued.count == 2)

        rig.staticFlags.overrides[.analyticsEnabled] = false

        #expect(rig.sink.stops == 1 && rig.sink.queued.isEmpty && rig.analytics.running == nil)
        rig.analytics.track(.screenViewed(.strain))
        #expect(rig.sink.captures.count == 2 && rig.sink.stops == 1)
    }

    @Test func analyticsNullStopsAndDrops() {
        let rig = AnalyticsRig()
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))

        rig.staticFlags.analytics = nil

        #expect(rig.sink.stops == 1 && rig.sink.queued.isEmpty && rig.analytics.running == nil)
        rig.analytics.track(.screenViewed(.sleep))
        #expect(rig.sink.captures.count == 1)
    }

    @Test func anInvalidNewConfigStopsAndDrops() {
        let rig = AnalyticsRig()
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))

        rig.staticFlags.analytics = AnalyticsConfig(host: "https://eu.i.posthog.com", projectKey: "phc_…")

        #expect(rig.sink.stops == 1 && rig.sink.queued.isEmpty && rig.sink.starts.count == 1)
    }

    @Test func optOutStopsAndDrops() {
        let rig = AnalyticsRig()
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))
        rig.analytics.track(.screenViewed(.sleep))

        rig.analytics.setOptIn(false)

        #expect(rig.sink.stops == 1 && rig.sink.queued.isEmpty && rig.analytics.running == nil)
        rig.analytics.track(.screenViewed(.strain))
        #expect(rig.sink.captures.count == 2)
    }

    @Test func trackAsksTheGateAgainSoADemoSwitchStopsAtOnce() {
        let rig = AnalyticsRig(wired: false) // no change hook: only `track`'s own gate run can notice
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))
        rig.demo.on = true

        rig.analytics.track(.screenViewed(.sleep))

        #expect(rig.sink.captures.count == 1 && rig.sink.stops == 1 && rig.sink.queued.isEmpty)
    }

    @Test func trackAsksTheGateAgainSoAFlagFlipStopsAtOnce() {
        let rig = AnalyticsRig(wired: false)
        rig.optIn()
        rig.staticFlags.overrides[.analyticsEnabled] = false

        rig.analytics.track(.screenViewed(.sleep))

        #expect(rig.sink.captures.isEmpty && rig.sink.stops == 1)
    }

    // MARK: the newest answer, not the shown one

    private static func config(flag: Bool, analytics: AnalyticsConfig?, minutes: Double = 0) -> RemoteConfig {
        RemoteConfig(flags: [FeatureFlag.analyticsEnabled.rawValue: flag],
                     evaluatedAt: Date(timeIntervalSince1970: 1_792_400_000 + minutes * 60), ttlSec: 21_600,
                     analytics: analytics)
    }

    /// `store`: nil makes an in-memory one (default arguments run outside the main actor).
    private func storeShowing(_ config: RemoteConfig, account: String? = "a", store: TrainStore? = nil) -> FlagStore {
        let flags = FlagStore(store: store ?? TrainStore(inMemory: true), defaults: AnalyticsRig.freshDefaults(),
                              account: account)
        flags.apply(config, fetchedAt: config.evaluatedAt) // the first answer applies at once
        return flags
    }

    @Test func pendingKillSwitchActsAtOnce() {
        let flags = storeShowing(Self.config(flag: true, analytics: AnalyticsFixture.config))
        let rig = AnalyticsRig(flags: flags)
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))

        flags.apply(Self.config(flag: false, analytics: AnalyticsFixture.config, minutes: 1),
                    fetchedAt: .now) // pending: the screens keep the old answer

        #expect(flags.isOn(.analyticsEnabled), "the screens still show the old answer")
        #expect(flags.pending != nil)
        #expect(rig.sink.stops == 1 && rig.sink.queued.isEmpty && rig.analytics.running == nil)
        rig.analytics.track(.screenViewed(.sleep))
        #expect(rig.sink.captures.count == 1)
    }

    @Test func aPendingNullStopsBeforeAnyApplyPending() {
        let flags = storeShowing(Self.config(flag: true, analytics: AnalyticsFixture.config))
        let rig = AnalyticsRig(flags: flags)
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))

        flags.apply(Self.config(flag: true, analytics: nil, minutes: 1), fetchedAt: .now)

        #expect(rig.sink.stops == 1 && rig.sink.queued.isEmpty && rig.analytics.running == nil)
    }

    @Test func aPendingAnswerThatTurnsItOnStartsAnOptedInUserAtOnce() throws {
        let flags = storeShowing(Self.config(flag: false, analytics: AnalyticsFixture.config))
        let rig = AnalyticsRig(flags: flags)
        rig.optIn()
        #expect(rig.sink.starts.isEmpty)

        flags.apply(Self.config(flag: true, analytics: AnalyticsFixture.config, minutes: 1), fetchedAt: .now)

        #expect(rig.sink.starts.map(\.destination) == [try #require(AnalyticsDestination(AnalyticsFixture.config))])
    }

    @Test func newestDestinationUsed() throws {
        let flags = storeShowing(Self.config(flag: true, analytics: AnalyticsFixture.config))
        let rig = AnalyticsRig(flags: flags)
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))
        rig.analytics.track(.screenViewed(.sleep))
        let first = try #require(AnalyticsDestination(AnalyticsFixture.config))
        let second = try #require(AnalyticsDestination(AnalyticsFixture.otherConfig))

        flags.apply(Self.config(flag: true, analytics: AnalyticsFixture.otherConfig, minutes: 1), fetchedAt: .now)

        // The old project's queue goes first; it never reaches the new one.
        #expect(rig.sink.calls == [
            .start(.init(destination: first, newID: false)), .capture("screen_viewed"), .capture("screen_viewed"),
            .stop,
            .start(.init(destination: second, newID: false)),
        ])
        #expect(rig.sink.queued.isEmpty)
        rig.analytics.track(.screenViewed(.strain))
        #expect(rig.sink.queued.count == 1 && rig.analytics.running == second)
    }

    @Test func applyingThePendingAnswerLaterChangesNothingForTheGate() {
        let flags = storeShowing(Self.config(flag: true, analytics: AnalyticsFixture.config))
        let rig = AnalyticsRig(flags: flags)
        rig.optIn()
        flags.apply(Self.config(flag: true, analytics: AnalyticsFixture.otherConfig, minutes: 1), fetchedAt: .now)
        let calls = rig.sink.calls

        flags.applyPending()
        rig.analytics.reevaluate()

        #expect(rig.sink.calls == calls)
    }

    @Test func accountSwitchClosesTheGate() {
        let store = TrainStore(inMemory: true)
        // B's cached answer has the flag off; A's has it on.
        _ = storeShowing(Self.config(flag: false, analytics: AnalyticsFixture.config), account: "b", store: store)
        let flags = storeShowing(Self.config(flag: true, analytics: AnalyticsFixture.config), account: "a", store: store)
        let rig = AnalyticsRig(flags: flags)
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))

        flags.switchAccount("b")

        #expect(rig.sink.stops == 1 && rig.sink.queued.isEmpty && rig.analytics.running == nil)
    }

    @Test func accountSwitchToAnAccountWithNoCacheClosesTheGate() {
        let flags = storeShowing(Self.config(flag: true, analytics: AnalyticsFixture.config), account: "a")
        let rig = AnalyticsRig(flags: flags)
        rig.optIn()

        flags.switchAccount("c")

        #expect(rig.sink.stops == 1 && rig.analytics.running == nil)
    }

    @Test func demoDataClosesTheGateThroughTheFlagStoreToo() {
        let flags = storeShowing(Self.config(flag: true, analytics: AnalyticsFixture.config))
        let rig = AnalyticsRig(flags: flags)
        rig.optIn()

        flags.setDemo(true) // demo's own flags: none cached, so the flag falls back to off

        #expect(rig.sink.stops == 1 && rig.analytics.running == nil)
    }

    // MARK: the id

    @Test func optOutResetsID() {
        let rig = AnalyticsRig()
        rig.optIn()
        rig.analytics.setOptIn(false)
        rig.optIn()
        #expect(rig.sink.starts.map(\.newID) == [false, true])
        #expect(rig.sink.forgets == 1)
        // Back to normal once the new id is made.
        rig.staticFlags.analytics = AnalyticsFixture.otherConfig
        #expect(rig.sink.starts.map(\.newID) == [false, true, false])
    }

    @Test func optOutForgetsTheIDOnceEvenWhenNothingWasStarted() {
        let rig = AnalyticsRig(flag: false, config: nil)
        rig.optIn() // opted in, but nothing may run: never started in this process
        rig.analytics.setOptIn(false)
        #expect(rig.sink.starts.isEmpty)
        #expect(rig.sink.forgets == 1 && rig.sink.stops == 1)
        #expect(rig.sink.calls == [.stop, .forgetID], "stop first, then the id")
    }

    @Test func signOutResetsIDAndClearsAnswer() {
        let rig = AnalyticsRig()
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))

        rig.analytics.accountLeft()

        #expect(rig.sink.stops == 1 && rig.sink.forgets == 1 && rig.sink.queued.isEmpty && rig.analytics.running == nil)
        #expect(rig.analytics.resetOwed)
        #expect(rig.analytics.optIn == nil)
        #expect(rig.defaults.object(forKey: Analytics.optInKey) == nil)
        rig.analytics.track(.screenViewed(.sleep))
        #expect(rig.sink.captures.count == 1, "not asked again yet: nothing is sent")

        rig.optIn()
        #expect(rig.sink.starts.map(\.newID) == [false, true])
    }

    @Test func signOutForgetsTheIDOnceEvenWhenNothingWasStarted() {
        let rig = AnalyticsRig(flag: false, config: nil)
        rig.analytics.accountLeft()
        #expect(rig.sink.calls == [.stop, .forgetID])
        #expect(rig.analytics.resetOwed)
    }

    @Test func theWipePassOfASignOutCallsAccountLeft() {
        let sink = FakeAnalyticsSink()
        let env = AppEnvironment.test(flags: [.analyticsEnabled: true], analyticsSink: sink)
        (env.flags as? StaticFlags)?.analytics = AnalyticsFixture.config
        env.analytics.setOptIn(true)
        #expect(sink.starts.count == 1)

        AppState(env: env).wiped(AuthService.Wipe(reason: nil, account: "acct"))

        #expect(sink.stops == 1 && sink.forgets == 1)
        #expect(env.analytics.optIn == nil)
        #expect(env.defaults.object(forKey: Analytics.optInKey) == nil)
    }

    @Test func forgetAnswerLeavesWhatAccountLeftWouldInDefaults() {
        let defaults = AnalyticsRig.freshDefaults()
        defaults.set("in", forKey: Analytics.optInKey)
        defaults.set(false, forKey: Analytics.resetOwedKey)

        Analytics.forgetAnswer(defaults: defaults)

        #expect(defaults.object(forKey: Analytics.optInKey) == nil)
        #expect(defaults.bool(forKey: Analytics.resetOwedKey))
    }

    @Test func aWipeWithoutTheOwnerStillAsksAgainAndStartsWithANewID() {
        // `AuthService.wipeSharedLocalData`, or a wipe resumed at launch: no `Analytics` exists to call `accountLeft()`.
        let defaults = AnalyticsRig.freshDefaults()
        defaults.set("in", forKey: Analytics.optInKey)
        Analytics.forgetAnswer(defaults: defaults)

        let next = AnalyticsRig(defaults: defaults)
        #expect(next.analytics.optIn == nil)
        next.analytics.track(.screenViewed(.today))
        #expect(next.sink.calls.isEmpty, "not asked: nothing is sent")
        next.optIn()
        #expect(next.sink.starts.map(\.newID) == [true])
    }

    @Test func resetOwedSurvivesRelaunch() {
        // The flag is off since launch: the sink never starts in this process, but the reset is owed.
        let first = AnalyticsRig(flag: false)
        first.optIn()
        first.analytics.setOptIn(false)
        #expect(first.defaults.bool(forKey: Analytics.resetOwedKey))

        let second = AnalyticsRig(flag: true, defaults: first.defaults)
        second.optIn()
        #expect(second.sink.starts.map(\.newID) == [true])
        #expect(!second.analytics.resetOwed && !second.defaults.bool(forKey: Analytics.resetOwedKey))

        let third = AnalyticsRig(flag: true, defaults: first.defaults)
        third.analytics.reevaluate()
        #expect(third.sink.starts.map(\.newID) == [false], "the reset is owed once")
    }

    // MARK: what is stored, what is printed

    @Test func theKeyIsNeverInADescriptionOrADump() {
        let config = AnalyticsFixture.config
        let destination = AnalyticsDestination(config)
        let remote = RemoteConfig(flags: ["analytics.enabled": true], evaluatedAt: .now, ttlSec: 21_600,
                                  privacyPolicyVersion: "2026-10-26", privacyPolicyUrl: "https://ryftlab.de/privacy",
                                  analytics: config)
        var shown: [String] = []
        func record(_ value: some Any) {
            shown.append("\(value)")
            shown.append(String(describing: value))
            shown.append(String(reflecting: value))
            var dumped = ""
            dump(value, to: &dumped)
            shown.append(dumped)
        }
        record(config)
        record(Optional(config))
        record([config])
        record(destination)
        record(remote)
        record(Optional(remote))
        record(["config": remote])
        #expect(!shown.isEmpty)
        for text in shown {
            #expect(!text.contains(AnalyticsFixture.key), "\(text)")
            #expect(!text.contains("testKEY"), "\(text)")
        }
        // The host is public and useful in a log; the redaction says what is missing.
        #expect("\(config)".contains("<redacted>") && "\(config)".contains("eu.i.posthog.com"))
        #expect("\(String(describing: destination))".contains("<redacted>"))
    }

    @Test func onlyTheOptInAndTheOwedResetAreStoredAndNeverTheKey() {
        let rig = AnalyticsRig()
        rig.optIn()
        rig.analytics.track(.screenViewed(.today))
        rig.analytics.setOptIn(false)
        rig.optIn()
        rig.analytics.accountLeft()
        rig.optIn()

        let stored = rig.defaults.dictionaryRepresentation()
        #expect(Set(stored.keys.filter { $0.hasPrefix("analytics.") }).isSubset(of: ["analytics.optIn", "analytics.resetOwed"]))
        #expect(Analytics.optInKey == "analytics.optIn" && Analytics.resetOwedKey == "analytics.resetOwed")
        #expect(stored[Analytics.optInKey] as? String == "in")
        for (key, value) in stored where key.hasPrefix("analytics.") {
            #expect(!"\(value)".contains("phc_"), "\(key)")
        }
    }

    @Test func theFlagIsNamedAsTheContractSaysAndOffByDefault() {
        #expect(FeatureFlag.analyticsEnabled.rawValue == "analytics.enabled")
        #expect(!FeatureFlag.analyticsEnabled.compiledDefault)
    }
}

// MARK: - the flag store's side of the seam

@Suite("Analytics: the flag store's newest answer")
@MainActor
struct AnalyticsFlagSeamTests {
    enum Action: CaseIterable, Sendable, CustomTestStringConvertible {
        case firstAnswer, pendingAnswer, switchAccount, setDemo, reset
        #if DEBUG
        case setOverride, clearOverrides
        #endif

        var testDescription: String { "\(self)" }
    }

    @MainActor
    final class Counter {
        var fired = 0
    }

    private static func config(flag: Bool, analytics: AnalyticsConfig?, minutes: Double = 0) -> RemoteConfig {
        RemoteConfig(flags: [FeatureFlag.analyticsEnabled.rawValue: flag],
                     evaluatedAt: Date(timeIntervalSince1970: 1_792_400_000 + minutes * 60), ttlSec: 21_600,
                     analytics: analytics)
    }

    private let defaults = AnalyticsRig.freshDefaults()

    private func flagStore(shows config: RemoteConfig? = nil) -> FlagStore {
        let flags = FlagStore(store: TrainStore(inMemory: true), defaults: defaults, account: "a")
        if let config { flags.apply(config, fetchedAt: config.evaluatedAt) }
        return flags
    }

    @Test func nothingAnsweredYetNewestIsTheCompiledDefault() {
        let flags = flagStore()
        #expect(!flags.newest(.analyticsEnabled) && flags.newestAnalytics == nil)
    }

    @Test func withNothingPendingNewestIsWhatIsShown() {
        let flags = flagStore(shows: Self.config(flag: true, analytics: AnalyticsFixture.config))
        #expect(flags.newest(.analyticsEnabled) == flags.isOn(.analyticsEnabled))
        #expect(flags.newest(.analyticsEnabled))
        #expect(flags.newestAnalytics == AnalyticsFixture.config)
    }

    @Test func aPendingAnswerCountsForNewestButNotForWhatIsShown() {
        let flags = flagStore(shows: Self.config(flag: true, analytics: AnalyticsFixture.config))
        flags.apply(Self.config(flag: false, analytics: AnalyticsFixture.otherConfig, minutes: 1), fetchedAt: .now)
        #expect(flags.isOn(.analyticsEnabled))
        #expect(!flags.newest(.analyticsEnabled))
        #expect(flags.newestAnalytics == AnalyticsFixture.otherConfig)
    }

    @Test func aPendingNullWinsOverTheShownConfig() {
        let flags = flagStore(shows: Self.config(flag: true, analytics: AnalyticsFixture.config))
        flags.apply(Self.config(flag: true, analytics: nil, minutes: 1), fetchedAt: .now)
        #expect(flags.newestAnalytics == nil)
        #expect(flags.analytics == AnalyticsFixture.config, "the shown config keeps its own")
    }

    @Test func applyingThePendingAnswerKeepsNewestWhereItWas() {
        let flags = flagStore(shows: Self.config(flag: true, analytics: AnalyticsFixture.config))
        flags.apply(Self.config(flag: false, analytics: nil, minutes: 1), fetchedAt: .now)
        flags.applyPending()
        #expect(!flags.newest(.analyticsEnabled) && flags.newestAnalytics == nil)
        #expect(!flags.isOn(.analyticsEnabled))
    }

    @Test func theCachedAnswerComesBackWithItsAnalyticsOnRelaunch() {
        let store = TrainStore(inMemory: true)
        let config = Self.config(flag: true, analytics: AnalyticsFixture.config)
        FlagStore(store: store, defaults: defaults, account: "a").apply(config, fetchedAt: config.evaluatedAt)
        let relaunched = FlagStore(store: store, defaults: defaults, account: "a")
        #expect(relaunched.newestAnalytics == AnalyticsFixture.config && relaunched.newest(.analyticsEnabled))
    }

    @Test(arguments: Action.allCases)
    func onNewestFiresWhenTheNewestAnswerMayHaveChanged(_ action: Action) {
        let shown = Self.config(flag: true, analytics: AnalyticsFixture.config)
        let flags = flagStore(shows: action == .firstAnswer ? nil : shown)
        let counter = Counter()
        flags.onNewest = { counter.fired += 1 }

        switch action {
        case .firstAnswer: flags.apply(shown, fetchedAt: .now)
        case .pendingAnswer: flags.apply(Self.config(flag: false, analytics: nil, minutes: 1), fetchedAt: .now)
        case .switchAccount: flags.switchAccount("b")
        case .setDemo: flags.setDemo(true)
        case .reset: flags.reset()
        #if DEBUG
        case .setOverride: flags.setOverride(.analyticsEnabled, false)
        case .clearOverrides: flags.clearOverrides()
        #endif
        }

        #expect(counter.fired >= 1)
    }

    #if DEBUG
    @Test func aDebugOverrideWinsOverAPendingAnswerBothWays() {
        let flags = flagStore(shows: Self.config(flag: true, analytics: AnalyticsFixture.config))
        flags.apply(Self.config(flag: false, analytics: AnalyticsFixture.config, minutes: 1), fetchedAt: .now)
        flags.setOverride(.analyticsEnabled, true)
        #expect(flags.newest(.analyticsEnabled))
        flags.setOverride(.analyticsEnabled, false)
        #expect(!flags.newest(.analyticsEnabled))
    }

    @Test func aDebugOverrideOnReachesTheGate() throws {
        let flags = flagStore(shows: Self.config(flag: false, analytics: AnalyticsFixture.config))
        let rig = AnalyticsRig(flags: flags)
        rig.optIn()
        #expect(rig.sink.starts.isEmpty)
        flags.setOverride(.analyticsEnabled, true)
        #expect(rig.sink.starts.map(\.destination) == [try #require(AnalyticsDestination(AnalyticsFixture.config))])
        flags.setOverride(.analyticsEnabled, false) // the override is the kill switch's mirror image
        #expect(rig.sink.stops == 1)
    }
    #endif

    @Test func staticFlagsNewestIsIsOnAndTheirChangesFireOnNewest() {
        let flags = StaticFlags([.analyticsEnabled: true], analytics: AnalyticsFixture.config)
        let counter = Counter()
        flags.onNewest = { counter.fired += 1 }
        #expect(flags.newest(.analyticsEnabled) == flags.isOn(.analyticsEnabled))
        #expect(flags.newestAnalytics == AnalyticsFixture.config)
        flags.overrides[.analyticsEnabled] = false
        #expect(counter.fired == 1 && !flags.newest(.analyticsEnabled))
        flags.analytics = nil
        #expect(counter.fired == 2 && flags.newestAnalytics == nil)
    }
}
