import Foundation
import Observation
import Testing
@testable import Ryft

/// Set from `onChange`, which may run on any thread.
private final class Changed: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    var value: Bool { lock.withLock { changed } }
    func set() { lock.withLock { changed = true } }
}

/// What makes the prompt not show although everything else holds.
enum AnalyticsPromptBlocker: CaseIterable, Sendable, CustomTestStringConvertible {
    case sinkCannotSend, demo, flagOff, analyticsNull, invalidDestination, optedIn, optedOut

    var testDescription: String { "\(self)" }
}

/// One row of the toggle's table.
struct AnalyticsToggleRow: Sendable, CustomTestStringConvertible {
    let why: String
    let canSend: Bool
    let flag: Bool
    let config: AnalyticsConfig?
    let demo: Bool
    let answer: Analytics.OptIn?
    let shows: Bool
    var testDescription: String { why }

    private static let valid = AnalyticsFixture.config

    static let all: [AnalyticsToggleRow] = [
        AnalyticsToggleRow(why: "where the prompt could show", canSend: true, flag: true, config: valid, demo: false, answer: nil, shows: true),
        AnalyticsToggleRow(why: "opted out, everything on: can opt in again", canSend: true, flag: true, config: valid, demo: false, answer: .optedOut, shows: true),
        AnalyticsToggleRow(why: "opted in, everything on", canSend: true, flag: true, config: valid, demo: false, answer: .optedIn, shows: true),
        AnalyticsToggleRow(why: "opted in, flag off: can still withdraw", canSend: true, flag: false, config: valid, demo: false, answer: .optedIn, shows: true),
        AnalyticsToggleRow(why: "opted in, analytics null: can still withdraw", canSend: true, flag: true, config: nil, demo: false, answer: .optedIn, shows: true),
        AnalyticsToggleRow(why: "opted in, demo data: can still withdraw", canSend: true, flag: true, config: valid, demo: true, answer: .optedIn, shows: true),
        AnalyticsToggleRow(why: "not asked, flag off", canSend: true, flag: false, config: valid, demo: false, answer: nil, shows: false),
        AnalyticsToggleRow(why: "not asked, analytics null", canSend: true, flag: true, config: nil, demo: false, answer: nil, shows: false),
        AnalyticsToggleRow(why: "not asked, demo data", canSend: true, flag: true, config: valid, demo: true, answer: nil, shows: false),
        AnalyticsToggleRow(why: "opted out, flag off", canSend: true, flag: false, config: valid, demo: false, answer: .optedOut, shows: false),
        AnalyticsToggleRow(why: "opted out, demo data", canSend: true, flag: true, config: valid, demo: true, answer: .optedOut, shows: false),
        AnalyticsToggleRow(why: "a sink that can't send, not asked", canSend: false, flag: true, config: valid, demo: false, answer: nil, shows: false),
        AnalyticsToggleRow(why: "a sink that can't send, even opted in", canSend: false, flag: true, config: valid, demo: false, answer: .optedIn, shows: false),
    ]
}

@Suite("Analytics: the prompt and the toggle")
@MainActor
struct AnalyticsPromptTests {
    private func makeRig(answer: Analytics.OptIn? = nil, flag: Bool = true, config: AnalyticsConfig? = AnalyticsFixture.config,
                     demo: Bool = false, canSend: Bool = true) -> AnalyticsRig {
        let defaults = AnalyticsRig.freshDefaults()
        if let answer { defaults.set(answer.rawValue, forKey: Analytics.optInKey) }
        let rig = AnalyticsRig(flag: flag, config: config, defaults: defaults)
        rig.demo.on = demo
        rig.sink.canSend = canSend
        return rig
    }

    // MARK: the prompt

    @Test func thePromptShowsWhereEveryFactHolds() {
        #expect(makeRig().analytics.showsPrompt)
    }

    @Test(arguments: AnalyticsPromptBlocker.allCases)
    func promptOnlyWhereItMeansSomething(_ blocker: AnalyticsPromptBlocker) {
        let rig: AnalyticsRig
        switch blocker {
        case .sinkCannotSend: rig = makeRig(canSend: false)
        case .demo: rig = makeRig(demo: true)
        case .flagOff: rig = makeRig(flag: false)
        case .analyticsNull: rig = makeRig(config: nil)
        case .invalidDestination: rig = makeRig(config: AnalyticsConfig(host: "https://eu.i.posthog.com", projectKey: "phc_…"))
        case .optedIn: rig = makeRig(answer: .optedIn)
        case .optedOut: rig = makeRig(answer: .optedOut)
        }
        #expect(!rig.analytics.showsPrompt)
    }

    @Test func anAnswerEndsThePromptWhicheverItIs() {
        let yes = makeRig()
        yes.analytics.setOptIn(true)
        let no = makeRig()
        no.analytics.setOptIn(false)
        #expect(!yes.analytics.showsPrompt && !no.analytics.showsPrompt)
    }

    @Test func aDeclineDoesNotComeBackWhenTheFlagCyclesOffAndOn() {
        let rig = makeRig()
        rig.analytics.setOptIn(false)
        rig.staticFlags.overrides[.analyticsEnabled] = false
        rig.staticFlags.overrides[.analyticsEnabled] = true
        #expect(!rig.analytics.showsPrompt && rig.analytics.optIn == .optedOut)
    }

    @Test func swipeCountsAsDecline() {
        // The sheet's dismissal calls `setOptIn(false)` while nothing was answered: that is a decline, and final.
        let rig = makeRig()
        rig.analytics.setOptIn(false)
        #expect(rig.analytics.optIn == .optedOut)
        #expect(rig.defaults.string(forKey: Analytics.optInKey) == "out")
        #expect(rig.sink.starts.isEmpty && rig.sink.captures.isEmpty)
        for event in AnalyticsEvent.everyCase { rig.analytics.track(event) }
        #expect(rig.sink.captures.isEmpty)
    }

    @Test func thePromptAppearsWhenTheFlagTurnsOnLater() {
        let rig = makeRig(flag: false)
        #expect(!rig.analytics.showsPrompt)
        rig.staticFlags.overrides[.analyticsEnabled] = true
        #expect(rig.analytics.showsPrompt)
    }

    @Test func theViewRendersAgainWhenOnlyAPendingAnswerChangedWhatItReads() {
        let store = TrainStore(inMemory: true)
        let flags = FlagStore(store: store, defaults: AnalyticsRig.freshDefaults(), account: "a")
        let off = RemoteConfig(flags: ["analytics.enabled": false], evaluatedAt: Date(timeIntervalSince1970: 1_792_400_000),
                               ttlSec: 21_600, analytics: AnalyticsFixture.config)
        flags.apply(off, fetchedAt: off.evaluatedAt)
        let rig = AnalyticsRig(flags: flags)
        rig.analytics.reevaluate()
        #expect(!rig.analytics.showsPrompt)

        let changed = Changed()
        let analytics = rig.analytics
        withObservationTracking({ _ = analytics.showsPrompt }, onChange: { changed.set() })
        flags.apply(RemoteConfig(flags: ["analytics.enabled": true], evaluatedAt: off.evaluatedAt.addingTimeInterval(60),
                                 ttlSec: 21_600, analytics: AnalyticsFixture.config), fetchedAt: .now)

        #expect(changed.value, "the screens' own flags didn't change, but the prompt's inputs did")
        #expect(rig.analytics.showsPrompt)
    }

    // MARK: the toggle

    @Test(arguments: AnalyticsToggleRow.all)
    func theToggleShowsWhereItMeansSomething(_ row: AnalyticsToggleRow) {
        let rig = makeRig(answer: row.answer, flag: row.flag, config: row.config, demo: row.demo, canSend: row.canSend)
        #expect(rig.analytics.showsToggle == row.shows)
    }

    @Test func toggleStaysWhileOptedInWithFlagOff() {
        let rig = makeRig()
        rig.optIn()
        rig.staticFlags.overrides[.analyticsEnabled] = false
        #expect(rig.analytics.showsToggle && !rig.analytics.showsPrompt)
        rig.analytics.setOptIn(false)
        #expect(!rig.analytics.showsToggle, "withdrawn with the flag off: nothing left to offer")
    }

    // MARK: the no-op

    @Test func noopCanNotSendAndDoesNothing() {
        let sink = NoopAnalyticsSink()
        #expect(!sink.canSend)
        if let destination = AnalyticsDestination(AnalyticsFixture.config) { sink.start(destination, newID: true) }
        sink.capture("screen_viewed", properties: ["screen": "today"])
        sink.stop()
        sink.forgetID()
        #expect(!sink.canSend)
    }

    @Test func testGraphWithNoSinkOfItsOwnShowsNeitherPromptNorToggle() {
        let env = AppEnvironment.test(flags: [.analyticsEnabled: true])
        (env.flags as? StaticFlags)?.analytics = AnalyticsFixture.config
        #expect(!env.analytics.showsPrompt && !env.analytics.showsToggle)
    }

    @Test func previewGraphShowsNeitherPromptNorToggle() {
        let env = AppEnvironment.preview(flags: [.analyticsEnabled: true])
        (env.flags as? StaticFlags)?.analytics = AnalyticsFixture.config
        #expect(!env.analytics.showsPrompt && !env.analytics.showsToggle)
    }

    @Test func aTestGraphGivenAFakeSinkSendsToIt() {
        let sink = FakeAnalyticsSink()
        let env = AppEnvironment.test(flags: [.analyticsEnabled: true], analyticsSink: sink)
        (env.flags as? StaticFlags)?.analytics = AnalyticsFixture.config
        #expect(env.analytics.showsPrompt)
        env.analytics.setOptIn(true)
        env.analytics.track(.healthAccessRequested)
        #expect(sink.starts.count == 1 && sink.captures.map(\.name) == ["health_access_requested"])
    }

    @Test func theTestGraphReadsTheAnswerFromItsOwnDefaults() {
        let env = AppEnvironment.test()
        #expect(env.analytics.optIn == nil)
        env.analytics.setOptIn(true)
        #expect(env.defaults.string(forKey: Analytics.optInKey) == "in")
    }

    @Test func liveSinkIsNoopInSimulator() {
        #if targetEnvironment(simulator)
        #expect(AnalyticsSinks.live() is NoopAnalyticsSink)
        #expect(AnalyticsSinks.live(arguments: ["-RyftAnalytics"]) is NoopAnalyticsSink, "even with the device switch")
        #endif
    }

    @Test func withoutTheSDKTheLiveSinkIsNoopAndCannotSend() {
        #if !canImport(PostHog)
        #expect(AnalyticsSinks.live() is NoopAnalyticsSink)
        #expect(!AnalyticsSinks.live(arguments: ["-RyftAnalytics"]).canSend)
        #endif
    }
}
