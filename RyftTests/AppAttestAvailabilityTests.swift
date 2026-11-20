import DeviceCheck
import Foundation
import Testing
@testable import Ryft

/// AC5: the platform doesn't serve App Attest (yet): no key, no header, and few probes.
@Suite("App Attest: not served yet (AC5)")
@MainActor
struct AppAttestNotServedTests {
    struct Answer: Sendable, CustomTestStringConvertible {
        let status: Int
        let servedBefore: Bool
        var testDescription: String { "\(status), seen served before: \(servedBefore)" }
    }

    @Test(arguments: [Answer(status: 404, servedBefore: false), Answer(status: 501, servedBefore: false),
                      Answer(status: 404, servedBefore: true)])
    func noKeyNoHeaderAndNoSecondProbeUntilSixHours(_ answer: Answer) async throws {
        let rig = AttestRig(served: answer.servedBefore, scripted: false)
        rig.server.reply(AttestServer.challenge, .json(answer.status, #"{"error":"not found"}"#))

        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.service.calls.isEmpty && rig.keys.stored == nil && rig.keys.saved.isEmpty)
        #expect(rig.server.count(AttestServer.keys) == 0 && rig.server.count(AttestServer.token) == 0)
        #expect(rig.backoff?.servedSeen == false)

        // The next launch, a few hours on, on the same defaults: no probe either.
        rig.launch()
        _ = try await rig.getMe()
        rig.clock.advance(by: .seconds(6 * 3_600 - 60))
        rig.launch()
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.server.appTokens(AttestServer.me) == [nil, nil, nil, nil])

        // Six hours after the answer: one probe again (and still nothing else).
        rig.clock.advance(by: .seconds(61))
        rig.launch()
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == 2)
        #expect(rig.service.calls.isEmpty)
        #expect(rig.server.appTokens(AttestServer.me).allSatisfy { $0 == nil })
    }

    @Test func twoAttestorsOnOneDefaultsSuiteProbeOnce() async throws {
        let rig = AttestRig(served: false, scripted: false)
        rig.server.reply(AttestServer.challenge, .json(404, #"{"error":"not found"}"#))
        let first: AppAttestor = rig.attestor
        let second = rig.launch()
        #expect(first !== second)
        _ = try await rig.getMe(rig.client(for: first))
        #expect(await rig.renewalEnded(first))
        _ = try await rig.getMe(rig.client(for: second))
        #expect(await rig.renewalEnded(second))
        #expect(rig.server.count(AttestServer.challenge) == 1)
    }

    @Test(arguments: [500, 503])
    func aServerErrorIsNotAnAnswerToNotServed(_ status: Int) async throws {
        let rig = AttestRig()
        rig.server.reply(AttestServer.challenge, .refusal(status, requestID: "rid-5xx"))
        _ = try await rig.getMe()
        #expect(rig.backoff?.notServedUntil == nil)
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.service.calls.isEmpty)
        // Only the in-process backoff holds: the next launch asks again.
        rig.launch()
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 2)
    }

    @Test func aServedAnswerEndsTheBackoff() async throws {
        let rig = AttestRig(served: false)
        rig.defaults.set(try JSONEncoder().encode(AppAttestor.Backoff(
            notServedUntil: rig.clock.now().addingTimeInterval(3_600))), forKey: AppAttestor.defaultsKey)
        rig.launch()
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 0)       // inside the six hours
        rig.clock.advance(by: .seconds(3_601))
        rig.launch()
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.backoff?.servedSeen == true && rig.backoff?.notServedUntil == nil)
        _ = try await rig.getMe()
        #expect(rig.server.appTokens(AttestServer.me).last == "tok-1")
    }

    /// Review C3: a `403 app_attest_required` shows the routes are live, so it lifts the not-served pause, once a process:
    /// here the probe it allows is answered `404` again, and the next refusal (past the 60 s spacing) probes no more.
    @Test func aRefusalLiftsTheNotServedPauseOnce() async throws {
        let rig = AttestRig(served: false, scripted: false)
        rig.defaults.set(try JSONEncoder().encode(AppAttestor.Backoff(
            notServedUntil: rig.clock.now().addingTimeInterval(3 * 3_600))), forKey: AppAttestor.defaultsKey)
        rig.launch()
        rig.server.reply(AttestServer.challenge, .json(404, #"{"error":"not found"}"#))
        rig.server.reply(AttestServer.me, .refusal(403, code: "app_attest_required", requestID: "rid-403"))

        await #expect { try await rig.getMe() } throws: { ($0 as? APIError)?.code == .appAttestRequired }
        #expect(rig.server.count(AttestServer.challenge) == 1)       // the pause was lifted for this refusal
        #expect(rig.backoff?.notServedUntil != nil)                  // and set again by the 404

        rig.clock.advance(by: .seconds(61))
        await #expect { try await rig.getMe() } throws: { ($0 as? APIError)?.code == .appAttestRequired }
        #expect(rig.server.count(AttestServer.challenge) == 1)       // not lifted twice
        #expect(rig.server.appTokens(AttestServer.me).allSatisfy { $0 == nil })
    }

    @Test func aDeviceClockSetBackDoesNotExtendTheBackoff() async throws {
        let rig = AttestRig(served: false)
        // A stored end further out than six hours can only come from a clock that was set back: over.
        rig.defaults.set(try JSONEncoder().encode(AppAttestor.Backoff(
            notServedUntil: rig.clock.now().addingTimeInterval(30 * 86_400))), forKey: AppAttestor.defaultsKey)
        rig.launch()
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) > 0)       // a whole run: asked again
    }
}

/// AC6: this iPhone can't attest: nothing is sent.
@Suite("App Attest: unsupported (AC6)")
@MainActor
struct AppAttestUnsupportedTests {
    @Test func noAttestRequestAndNoHeaderOnAnyRoute() async throws {
        let rig = AttestRig(supported: false)
        _ = try await rig.getMe()
        _ = try await rig.postSync()
        _ = try await rig.getMe()
        #expect(rig.server.appAttestRequests == 0)
        #expect(rig.service.calls.isEmpty)
        #expect(rig.server.requests.allSatisfy { $0.appToken == nil })
        #expect(rig.server.requests.count == 3)
        // Nothing kept: no Keychain item, no backoff.
        #expect(rig.keys.saved.isEmpty && rig.keys.stored == nil)
        #expect(rig.backoff == AppAttestor.Backoff(servedSeen: true))   // as it was set up
    }

    @Test func aLaterLaunchOnTheSameDeviceDoesNotAskEither() async throws {
        let rig = AttestRig(supported: false)
        for _ in 0..<3 {
            rig.launch()
            _ = try await rig.getMe()
        }
        #expect(rig.server.appAttestRequests == 0 && rig.service.calls.isEmpty)
    }

    @Test func featureUnsupportedFromAppleEndsAppAttestForTheProcess() async throws {
        let rig = AttestRig()
        rig.service.failNext("generateKey", with: DCError(.featureUnsupported))
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.service.count("generateKey") == 1 && rig.server.count(AttestServer.keys) == 0)
        #expect(rig.server.appTokens(AttestServer.me) == [nil])
        // For the rest of the process, whatever the clock says.
        rig.clock.advance(by: .seconds(3_600))
        _ = try await rig.getMe()
        #expect(rig.server.appAttestRequests == 1 && rig.service.count("generateKey") == 1)
        #expect(rig.server.appTokens(AttestServer.me) == [nil, nil])
    }
}

/// AA2 (D247): the server's App Attest mode, from `GET /v1/config`, decides whether this install probes. The clock
/// never moves unless a test moves it, so a request that waited for a renewal would hang: the time limit turns that
/// into a failure.
@Suite("App Attest: the mode from the config (AA2)", .timeLimit(.minutes(1)))
@MainActor
struct AppAttestModeTests {
    private static let refused = AttestServer.Reply.refusal(403, code: "app_attest_required", requestID: "rid-403")

    /// The mode as the newest config says it, fetched `ago` seconds before the rig's now.
    private func configure(_ rig: AttestRig, _ mode: AppAttestMode?, ago: TimeInterval = 0) {
        rig.attestor.configure(mode, fetchedAt: rig.clock.now().addingTimeInterval(-ago))
    }

    private func notServed(_ rig: AttestRig, status: Int = 501) {
        rig.server.reply(AttestServer.challenge, .json(status, #"{"error":"not found"}"#))
    }

    private func config(_ mode: String?, at now: Date) -> RemoteConfig {
        RemoteConfig(flags: [:], evaluatedAt: now, ttlSec: 21_600, appAttest: mode)
    }

    /// A config document in the store, as `FlagStore.apply` leaves it.
    private func cache(_ store: TrainStore, account: String?, mode: String?, fetchedAt: Date) {
        store.saveDocument(FlagStore.Cached(config: config(mode, at: fetchedAt), fetchedAt: fetchedAt),
                           key: FlagStore.cacheKey(account), at: fetchedAt)
    }

    private func flagStore(_ store: TrainStore, account: String? = AttestRig.a, feeding rig: AttestRig) -> FlagStore {
        FlagStore(store: store, defaults: UserDefaults(suiteName: "ryft.test.flags.\(UUID().uuidString)") ?? .standard,
                  account: account, appAttest: rig.attestor)
    }

    // MARK: what each mode does (AC4-AC7)

    @Test func offSendsNoChallengeAndNeverWaits() async throws {
        let rig = AttestRig()                     // served: without `off`, a request without a token waits up to 3 s
        configure(rig, .off)
        _ = try await rig.getMe()
        _ = try await rig.getMe()
        _ = try await rig.postSync()
        #expect(rig.server.appAttestRequests == 0)
        #expect(rig.service.calls.isEmpty && rig.keys.saved.isEmpty && rig.keys.stored == nil)
        #expect(rig.events.all == ["net GET /v1/me", "net GET /v1/me", "net POST /v1/sync"])
        #expect(rig.server.requests.count == 3 && rig.server.requests.allSatisfy { $0.appToken == nil })
        #expect(await rig.attestor.waiting == 0)
        #expect(await !rig.attestor.isRenewing)
        #expect(rig.clock.pendingSleeps == 0 && rig.clock.uptime() == .zero)
    }

    @Test func offKeepsAHeldTokenAndDoesNotRenew() async throws {
        let rig = AttestRig()
        _ = try await rig.getMe()                                   // absent: tok-1
        #expect(await rig.renewalEnded())
        let challenges = rig.server.count(AttestServer.challenge)
        configure(rig, .off)

        rig.clock.advance(by: .seconds(3_301))                      // inside the renewal window
        _ = try await rig.getMe()
        #expect(await !rig.attestor.isRenewing)
        rig.clock.advance(by: .seconds(300))                        // 3 601 s: tok-1 has expired
        _ = try await rig.getMe()

        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1", "tok-1", nil])
        #expect(rig.server.count(AttestServer.token) == 1)
        #expect(rig.server.count(AttestServer.challenge) == challenges)
        #expect(rig.server.count(AttestServer.keys) == 1)
        #expect(await rig.attestor.waiting == 0)
    }

    @Test(arguments: [nil, "strict"] as [String?])
    func absentProbesAsToday(_ raw: String?) async throws {
        let rig = AttestRig(served: false, scripted: false)
        notServed(rig)
        // The answer as `FlagStore` reads it: no key, or one this build doesn't know.
        configure(rig, config(raw, at: rig.clock.now()).appAttestMode)
        #expect(rig.attestor.configuredMode == nil)

        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.backoff?.notServedUntil != nil)
        #expect(rig.service.calls.isEmpty && rig.server.count(AttestServer.keys) == 0)
        #expect(rig.server.appTokens(AttestServer.me) == [nil])
    }

    @Test(arguments: [AppAttestMode.warn, .on])
    func warnAndOnAttest(_ mode: AppAttestMode) async throws {
        let rig = AttestRig()
        configure(rig, mode)
        _ = try await rig.getMe()
        #expect(rig.events.all == ["net challenge", "dc generateKey", "dc attestKey", "net keys",
                                   "net challenge", "dc generateAssertion", "net token", "net GET /v1/me"])
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1"])
    }

    @Test(arguments: [AppAttestMode.warn, .on], [501, 404])
    func aNotServedAnswerUnderWarnOrOnStaysAuthoritative(_ mode: AppAttestMode, _ status: Int) async throws {
        let rig = AttestRig(served: false, scripted: false)
        configure(rig, mode)
        notServed(rig, status: status)

        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.backoff?.notServedUntil != nil && rig.backoff?.servedSeen == false)
        #expect(rig.service.calls.isEmpty && rig.keys.stored == nil)

        rig.clock.advance(by: .seconds(6 * 3_600 - 60))
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == 1)       // still inside the pause

        rig.clock.advance(by: .seconds(61))
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == 2)       // the pause ended: one more probe
        #expect(rig.server.appTokens(AttestServer.me).allSatisfy { $0 == nil })
    }

    @Test(arguments: [AppAttestMode.warn, .on])
    func warnDoesNotLiftANotServedPause(_ mode: AppAttestMode) async throws {
        let rig = AttestRig(served: false)
        rig.defaults.set(try JSONEncoder().encode(AppAttestor.Backoff(
            notServedUntil: rig.clock.now().addingTimeInterval(3 * 3_600))), forKey: AppAttestor.defaultsKey)
        rig.launch()
        configure(rig, mode)
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.appAttestRequests == 0)
        #expect(rig.server.appTokens(AttestServer.me) == [nil])
    }

    // MARK: a cached `off` that is wrong (AC8)

    @Test func aRefusalUnderCachedOffRenewsAndRetriesOnce() async throws {
        let rig = AttestRig()
        configure(rig, .off)
        rig.server.reply(AttestServer.me, Self.refused, .ok)
        _ = try await rig.getMe()
        #expect(rig.server.appTokens(AttestServer.me) == [nil, "tok-1"])
        #expect(rig.server.count(AttestServer.token) == 1)
        #expect(rig.server.count(AttestServer.keys) == 1 && rig.server.count(AttestServer.challenge) == 2)
        #expect(rig.server.count(AttestServer.me) == 2)
    }

    @Test func aRefusalThatKeepsComingIsThrownAfterOneRetry() async throws {
        let rig = AttestRig()
        configure(rig, .off)
        rig.server.reply(AttestServer.me, Self.refused)
        await #expect { try await rig.getMe() } throws: { ($0 as? APIError)?.code == .appAttestRequired }
        #expect(rig.server.count(AttestServer.me) == 2)
        #expect(rig.server.count(AttestServer.token) == 1)
    }

    @Test func theRefusalLiftsOffUntilTheNextAnswer() async throws {
        let rig = AttestRig()
        configure(rig, .off)
        rig.server.reply(AttestServer.me, Self.refused, .ok)
        _ = try await rig.getMe()                                   // tok-1, by the refusal
        #expect(await rig.renewalEnded())

        rig.clock.advance(by: .seconds(3_301))                      // the lift keeps renewals going
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.token) == 2)
        #expect(rig.server.appTokens(AttestServer.me) == [nil, "tok-1", "tok-1", "tok-2"])

        // The next answer says `off` again: that counts, and past expiry nothing is asked for.
        configure(rig, .off)
        let challenges = rig.server.count(AttestServer.challenge)
        rig.clock.advance(by: .seconds(3_601))
        _ = try await rig.getMe()
        let tokens = rig.server.appTokens(AttestServer.me)
        #expect(tokens.count == 5 && tokens[4] == nil)
        #expect(rig.server.count(AttestServer.challenge) == challenges && rig.server.count(AttestServer.token) == 2)
    }

    // MARK: how long an `off` counts

    struct Fetch: Sendable, CustomTestStringConvertible {
        /// Seconds before now the config was fetched (negative: in the future); nil: no date.
        let ago: TimeInterval?
        let probes: Bool
        var testDescription: String { ago.map { "fetched \($0) s ago" } ?? "no fetch date" }
    }

    @Test(arguments: [Fetch(ago: 86_401, probes: true), Fetch(ago: 86_400, probes: true),
                      Fetch(ago: -25 * 3_600, probes: true), Fetch(ago: nil, probes: true),
                      Fetch(ago: 86_399, probes: false), Fetch(ago: 0, probes: false)])
    func aStaleOffCountsAsAbsent(_ fetch: Fetch) async throws {
        let rig = AttestRig(served: false, scripted: false)
        notServed(rig)
        rig.attestor.configure(.off, fetchedAt: fetch.ago.map { rig.clock.now().addingTimeInterval(-$0) })
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == (fetch.probes ? 1 : 0))
    }

    @Test func anOffAgesOutWithTheClock() async throws {
        let rig = AttestRig(served: false, scripted: false)
        notServed(rig)
        configure(rig, .off)
        _ = try await rig.getMe()
        rig.clock.advance(by: .seconds(24 * 3_600 - 1))
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 0)
        rig.clock.advance(by: .seconds(2))                          // 24 h and 1 s after the fetch
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == 1)
    }

    // MARK: `FlagStore` feeds the attestor (AC9)

    @Test func flagStorePublishesTheNewestMode() async throws {
        let rig = AttestRig()
        let now = rig.clock.now()
        let store = TrainStore(inMemory: true)
        cache(store, account: AttestRig.a, mode: "off", fetchedAt: now)
        let flags = flagStore(store, feeding: rig)
        #expect(rig.attestor.configuredMode == .off)                // at init, from the cache

        flags.apply(config("warn", at: now), fetchedAt: now)        // a screen shows the cached answer: held back…
        #expect(flags.pending != nil)
        #expect(rig.attestor.configuredMode == .warn)               // …but the mode counts at once
        flags.applyPending()
        #expect(rig.attestor.configuredMode == .warn)

        flags.apply(config("on", at: now), fetchedAt: now)
        #expect(rig.attestor.configuredMode == .on)
    }

    @Test func aFirstAnswerWithNothingShownIsPublishedToo() async throws {
        let rig = AttestRig()
        let now = rig.clock.now()
        let flags = flagStore(TrainStore(inMemory: true), feeding: rig)
        #expect(rig.attestor.configuredMode == nil)
        flags.apply(config("on", at: now), fetchedAt: now)
        #expect(flags.pending == nil)
        #expect(rig.attestor.configuredMode == .on)
    }

    @Test func aPendingAnswerWithoutTheFieldMakesTheModeAbsent() async throws {
        let rig = AttestRig()
        let now = rig.clock.now()
        let store = TrainStore(inMemory: true)
        cache(store, account: AttestRig.a, mode: "off", fetchedAt: now)
        let flags = flagStore(store, feeding: rig)
        flags.apply(config(nil, at: now), fetchedAt: now)           // the newest answer says nothing: absent
        #expect(rig.attestor.configuredMode == nil)
        flags.apply(config("strict", at: now), fetchedAt: now)      // …and so does one this build doesn't know
        #expect(rig.attestor.configuredMode == nil)
    }

    /// A switch publishes the new side's cached mode, or absent when it has none (never the previous side's).
    @Test func anAccountSwitchSignOutAndDemoPublishTheNewSidesModeOrAbsent() async throws {
        let rig = AttestRig()
        let now = rig.clock.now()
        let store = TrainStore(inMemory: true)
        cache(store, account: AttestRig.a, mode: "warn", fetchedAt: now)
        cache(store, account: "account-b2", mode: "off", fetchedAt: now)
        let flags = flagStore(store, feeding: rig)
        #expect(rig.attestor.configuredMode == .warn)

        flags.switchAccount("account-b2")                           // a side with a cached `off`
        #expect(rig.attestor.configuredMode == .off)
        flags.switchAccount(AttestRig.b)                            // a side with no cached config
        #expect(rig.attestor.configuredMode == nil)
        flags.switchAccount(AttestRig.a)                            // back: A's own cache
        #expect(rig.attestor.configuredMode == .warn)
        flags.reset()                                               // forgets the account's flags
        #expect(rig.attestor.configuredMode == nil)
        cache(store, account: AttestRig.a, mode: "off", fetchedAt: now)
        flags.switchAccount(AttestRig.b)
        flags.switchAccount(AttestRig.a)
        flags.switchAccount(nil)                                    // sign-out
        #expect(rig.attestor.configuredMode == nil)
        flags.switchAccount(AttestRig.a)
        #expect(rig.attestor.configuredMode == .off)
        flags.setDemo(true)                                         // demo data has its own flags
        #expect(rig.attestor.configuredMode == nil)
        flags.setDemo(false)
        #expect(rig.attestor.configuredMode == .off)
    }

    @Test func aSwitchDoesNotCarryThePreviousAccountsPendingAnswer() async throws {
        let rig = AttestRig()
        let now = rig.clock.now()
        let store = TrainStore(inMemory: true)
        cache(store, account: AttestRig.a, mode: "off", fetchedAt: now)
        cache(store, account: AttestRig.b, mode: "warn", fetchedAt: now)
        let flags = flagStore(store, feeding: rig)
        flags.apply(config("on", at: now), fetchedAt: now)          // pending for A
        #expect(rig.attestor.configuredMode == .on)
        flags.switchAccount(AttestRig.b)
        #expect(flags.pending == nil && rig.attestor.configuredMode == .warn)
    }

    @Test func anAnswerAskedForBeforeASwitchChangesNothing() async throws {
        let rig = AttestRig()
        let now = rig.clock.now()
        let store = TrainStore(inMemory: true)
        cache(store, account: AttestRig.a, mode: "off", fetchedAt: now)
        let flags = flagStore(store, feeding: rig)
        let asked = flags.generation
        flags.switchAccount(AttestRig.b)
        #expect(rig.attestor.configuredMode == nil)
        flags.apply(config("on", at: now), fetchedAt: now, generation: asked)   // A's answer, arriving as B
        #expect(rig.attestor.configuredMode == nil)
        flags.switchAccount(AttestRig.a)
        #expect(rig.attestor.configuredMode == .off)                // A's cache was not overwritten either
    }

    @Test func resetForgetsTheMode() async throws {
        let rig = AttestRig()
        let now = rig.clock.now()
        let store = TrainStore(inMemory: true)
        cache(store, account: AttestRig.a, mode: "warn", fetchedAt: now)
        let flags = flagStore(store, feeding: rig)
        #expect(rig.attestor.configuredMode == .warn)
        flags.reset()
        #expect(rig.attestor.configuredMode == nil)
    }

    @Test func theCachedModeReachesTheFirstRequestOfALaunch() async throws {
        let rig = AttestRig()
        let store = TrainStore(inMemory: true)
        cache(store, account: AttestRig.a, mode: "off", fetchedAt: rig.clock.now())
        _ = flagStore(store, feeding: rig)                          // a cold launch: the store loads before any request
        _ = try await rig.getMe()
        #expect(rig.server.appAttestRequests == 0 && rig.server.appTokens(AttestServer.me) == [nil])
    }

    @Test func aCachedOffFetchedOverADayAgoProbesAgain() async throws {
        let rig = AttestRig(served: false, scripted: false)
        notServed(rig)
        let store = TrainStore(inMemory: true)
        cache(store, account: AttestRig.a, mode: "off", fetchedAt: rig.clock.now().addingTimeInterval(-(24 * 3_600 + 1)))
        _ = flagStore(store, feeding: rig)
        #expect(rig.attestor.configuredMode == .off)                // the mode is published; its age decides
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.challenge) == 1)
    }
}
