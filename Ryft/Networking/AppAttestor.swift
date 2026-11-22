// The app token (API.md → Conventions → App Attest, D245; ADR 0023; docs/work/2026-11-19-app-attest/design.md).
// `APIClient.exchange` asks `token(epoch:via:)` for `X-RYFT-App-Token` before each request and, after a
// `403 app_attest_required`, `renewed(after:epoch:via:)` for a new one, once. The three App Attest routes go through
// `exchange` too (bearer, 401, request IDs) but never ask for a token (`APIClient.appAttestRoutes`).
// The server's mode (`GET /v1/config` → `app_attest`, AA2, D247) comes from `FlagStore` (`configure`): under `off`
// nothing is probed; `warn`, `on` and absent behave as before (docs/work/2026-11-20-app-attest-mode/design.md).
// Nothing here logs, records or shows the key ID, the token, a challenge, an attestation or an assertion: log lines
// carry the step, the status, the `code`, the request ID and the DCError code only.
import CryptoKit
import DeviceCheck
import Foundation
import os

/// The one owner of the app token (in memory only), the attested key's ID (the Keychain, with its account) and the
/// backoffs. One renewal at a time: requests that need a token while it runs wait for it, none starts its own.
actor AppAttestor {
    static let live = AppAttestor(
        service: DeviceAppAttestService(), keys: KeychainAppAttestKeys(), clock: SystemClock(), defaults: .standard,
        stamp: { AuthService.shared.accountID.map { AttestStamp(account: $0, epoch: APIStatus.shared.epoch) } })

    static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "appattest")
    /// Intervals `renewal` (one run), `attestKey` and `assertion` (the Secure Enclave's part).
    static let signposter = OSSignposter(subsystem: "dev.timkrebs.ryft", category: "appattest")

    /// A request without a token waits this long for the renewal, once this install has seen the routes served
    /// (design.md §3: under `warn`, every request without a token is logged as `missing`).
    static let firstTokenWait: Duration = .seconds(3)
    /// A request refused with `403 app_attest_required` waits this long for the shared renewal.
    static let refusedWait: Duration = .seconds(20)
    /// A refusal doesn't start a renewal when one started this recently: no loop against a server that refuses them.
    static let refusalSpacing: Duration = .seconds(60)
    /// A renewal starts when this many seconds of the token's lifetime are left (at most half of it).
    static let renewalLead = 300
    /// `404` without a `code`, or `501`, from a route: App Attest isn't served; no renewal before this (the config TTL).
    static let notServedPause: TimeInterval = 6 * 3600
    /// No attestation after the second `app_attest_invalid` of a run, or a `400` (a try costs keys: 10 a day).
    static let attestPause: TimeInterval = 24 * 3600
    /// `429` on `POST /v1/app-attest/keys` without `Retry-After`.
    static let keysRateLimitPause: TimeInterval = 3600
    /// After a failed run, no renewal for 1, 2, 4 … 30 min, or the answer's `Retry-After`. A token resets it.
    static let backoffBase: Duration = .seconds(60)
    static let backoffCap: Duration = .seconds(30 * 60)
    /// The backoffs that outlive the process (`Backoff`).
    static let defaultsKey = "appAttest.backoff"
    /// A cached `off` (the config's `app_attest`, AA2) counts this long after its fetch; then it's absent.
    static let offTrust: TimeInterval = 24 * 3600

    /// `appAttest.backoff`: dates and one flag, nothing that identifies the account or the install.
    struct Backoff: Codable, Equatable, Sendable {
        /// The routes answered `404` without a `code` or `501`: no renewal and no header before this.
        var notServedUntil: Date?
        /// No new key and no attestation before this. The keys budget is the account's: a wipe clears it.
        var attestPausedUntil: Date?
        /// The challenge route has answered `200` on this install: a request without a token waits for one.
        var servedSeen = false
    }

    private let service: AppAttestService
    private nonisolated let keys: AppAttestKeyStore
    private let clock: AppClock
    private let defaults: UserDefaults
    private let stamp: @MainActor @Sendable () -> AttestStamp?
    /// Bumped by `wipe()` on its caller and read here, so what a wipe ended is over before `catchUpWipes` runs.
    private nonisolated let wipes = OSAllocatedUnfairLock(initialState: 0)
    private var handledWipes = 0

    private struct Issued {
        let token: String
        let epoch: Int
        /// On `clock.uptime()`, from when the answer arrived.
        let renewAt: Duration
        let expiresAt: Duration
    }

    private struct Renewal {
        let id: UUID
        let epoch: Int
        let task: Task<Void, Never>
    }

    private var issued: Issued?
    private var renewal: Renewal?
    private var waiters: [UUID: (renewal: UUID, continuation: CheckedContinuation<Void, Never>)] = [:]
    /// When the last renewal started (`refusalSpacing`).
    private var lastStart: Duration?
    /// The in-memory backoff: no renewal before this uptime.
    private var notBefore: Duration?
    private var failures = 0
    /// `isSupported` false or `featureUnsupported`: nothing for the rest of the process.
    private var unsupported = false
    /// A `403 app_attest_required` has lifted the not-served pause in this process (once).
    private var liftedNotServed = false
    private var cachedBackoff: Backoff?

    /// The server's mode from the newest config (`FlagStore` publishes it; nil: absent, today's behaviour), when that
    /// config was fetched, and a count of publications (a refusal's lift of `off` lasts until the next one).
    private struct Configured: Sendable {
        var mode: AppAttestMode?
        var fetchedAt: Date?
        var revision = 0
    }

    /// Written on the caller (the main actor) and read here without a hop: `token()` gains no suspension point.
    private nonisolated let configured = OSAllocatedUnfairLock(initialState: Configured())
    /// The `revision` a `403 app_attest_required` lifted `off` for: the server is checking, whatever the cache says.
    private var offLiftedAt: Int?

    /// `stamp`: the signed-in account and `APIStatus.epoch` (nil: nobody), read on the main actor. Its epoch is the one
    /// `APIClient` gives `token(epoch:via:)`, so a test's stamp reads the epoch of the client's `APIStatus`.
    init(service: AppAttestService, keys: AppAttestKeyStore, clock: AppClock, defaults: UserDefaults,
         stamp: @escaping @MainActor @Sendable () -> AttestStamp?) {
        self.service = service
        self.keys = keys
        self.clock = clock
        self.defaults = defaults
        self.stamp = stamp
    }

    /// The newest config's mode and when it was fetched (`FlagStore`, on every change of the answer it shows or holds;
    /// nil: absent, as before D247 or for an account with no cached config). Ends a refusal's lift of `off`.
    nonisolated func configure(_ mode: AppAttestMode?, fetchedAt: Date?) {
        configured.withLock {
            $0.mode = mode
            $0.fetchedAt = fetchedAt
            $0.revision += 1
        }
    }

    /// The mode last configured (tests).
    nonisolated var configuredMode: AppAttestMode? { configured.withLock { $0.mode } }

    /// Requests waiting for the renewal (tests).
    var waiting: Int { waiters.count }

    /// A renewal is running (tests).
    var isRenewing: Bool { renewal != nil }

    /// Runs still executing, a wiped one included (tests: `isRenewing` turns false at the wipe, before its run ends).
    private(set) var runsInFlight = 0

    // MARK: what APIClient asks

    /// The header for a request that started in `epoch`, or nil: it goes without. Starts a renewal when there's no
    /// valid token, and when under `min(300 s, ttl / 2)` are left (the current token still goes out; none goes out
    /// past its expiry). Once this install has seen the routes served, a request without a token waits up to
    /// `firstTokenWait` for the renewal. Under a configured `off` (AA2) nothing starts and nothing waits: a token
    /// already held still goes out until it expires.
    func token(epoch: Int, via client: APIClient) async -> String? {
        catchUpWipes()
        let now = clock.uptime()
        if let issued, issued.epoch == epoch, now < issued.expiresAt {
            if now >= issued.renewAt, !isOff { startRenewal(epoch: epoch, via: client) }
            return issued.token
        }
        guard !isOff, let id = startRenewal(epoch: epoch, via: client), backoff.servedSeen else { return nil }
        await wait(for: id, upTo: Self.firstTokenWait)
        return usable(epoch)
    }

    /// After a `403 app_attest_required` on a request that started in `epoch` and sent `refused` (nil: none): a valid
    /// token other than the refused one, or the one the renewal in flight brings (waited for up to `refusedWait`), or a
    /// new renewal's. Nil when there's none to be had (a renewal started under `refusalSpacing` ago, a backoff, no App
    /// Attest): the request then throws its `403`. Throws `CancellationError` when the request is cancelled.
    func renewed(after refused: String?, epoch: Int, via client: APIClient) async throws -> String? {
        catchUpWipes()
        try Task.checkCancellation()
        // The platform refuses for App Attest, so its routes are live: a not-served pause (one stray `404` or `501`)
        // ends, once a process, so a refusal can't probe again and again.
        if !liftedNotServed, backoff.notServedUntil != nil {
            liftedNotServed = true
            updateBackoff { $0.notServedUntil = nil }
        }
        // A cached `off` is stale (the server went `warn` → `on`): renewals go on until the next published answer.
        // Set before any suspension, so a request reading `isOff` after this one attests.
        if let revision = offInForce {
            offLiftedAt = revision
            Self.log.notice("App Attest: refused under a cached off; renewing until the next config")
        }
        if let token = usable(epoch), token != refused { return token }
        let id: UUID
        if let renewal, renewal.epoch == epoch {
            id = renewal.id
        } else {
            if let lastStart, clock.uptime() - lastStart < Self.refusalSpacing { return nil }
            guard let started = startRenewal(epoch: epoch, via: client) else { return nil }
            id = started
        }
        await wait(for: id, upTo: Self.refusedWait)
        try Task.checkCancellation()
        guard let token = usable(epoch), token != refused else { return nil }
        return token
    }

    /// Sign-out, deletion, expiry, a switch (`AuthService.wipeSharedLocalData`): the Keychain item now, on the caller
    /// (the main actor, where a run's Keychain writes happen too); then the token, the renewal (cancelled, its waiters
    /// released), the attestation pause and the in-memory backoff. The not-served backoff stays: it's the server's.
    nonisolated func wipe() {
        wipes.withLock { $0 += 1 }
        keys.remove()
        Task { await self.catchUpWipes() }
    }

    /// The header for a route App Attest exempts: the token this process holds for `epoch`, if any. Never starts a
    /// renewal and never waits (sign-out's unregistering, erasure, feedback).
    func heldToken(epoch: Int) -> String? {
        catchUpWipes()
        return usable(epoch)
    }

    /// `clientDataHash` for `attestKey` and `generateAssertion`: SHA-256 of the challenge's UTF-8 bytes, as received.
    static func clientDataHash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }

    // MARK: state

    private func usable(_ epoch: Int) -> String? {
        guard let issued, issued.epoch == epoch, clock.uptime() < issued.expiresAt else { return nil }
        return issued.token
    }

    /// Every way in runs this first: a wipe since the last one ends everything from before it.
    private func catchUpWipes() {
        let current = wipes.withLock { $0 }
        guard current != handledWipes else { return }
        handledWipes = current
        renewal?.task.cancel()
        renewal = nil
        issued = nil
        lastStart = nil
        notBefore = nil
        failures = 0
        updateBackoff { $0.attestPausedUntil = nil }
        let parked = waiters
        waiters = [:]
        parked.values.forEach { $0.continuation.resume() }
    }

    /// The renewal for `epoch`: the one in flight, or a new one (set before any suspension, so there's never a
    /// second). Nil when none may start: a request of an account that's gone, no App Attest, a backoff.
    @discardableResult
    private func startRenewal(epoch: Int, via client: APIClient) -> UUID? {
        if let renewal {
            if renewal.epoch == epoch { return renewal.id }
            // The caller's account has gone (its epoch is older): nothing starts for it.
            if renewal.epoch > epoch { return nil }
            // An earlier account's, which can no longer save or publish anything: it ends, its waiters with it.
            renewal.task.cancel()
            self.renewal = nil
            release(renewal: renewal.id)
        }
        guard mayStart() else { return nil }
        let id = UUID()
        let generation = wipes.withLock { $0 }
        lastStart = clock.uptime()
        let task = Task { await self.run(id, epoch: epoch, generation: generation, via: client) }
        renewal = Renewal(id: id, epoch: epoch, task: task)
        return id
    }

    private func mayStart() -> Bool {
        guard !unsupported else { return false }
        guard service.isSupported else {
            markUnsupported()
            return false
        }
        if Self.inForce(backoff.notServedUntil, now: clock.now(), longest: Self.notServedPause) { return false }
        if let notBefore, clock.uptime() < notBefore { return false }
        return true
    }

    /// A stored pause that hasn't ended. One further out than it can last means the device's clock was set back: over.
    private static func inForce(_ until: Date?, now: Date, longest: TimeInterval) -> Bool {
        guard let until else { return false }
        let left = until.timeIntervalSince(now)
        return left > 0 && left <= longest
    }

    /// The server said `off`: no challenge, no key, no wait.
    private var isOff: Bool { offInForce != nil }

    /// The `revision` of a configured `off` still in force, or nil. An `off` counts for `offTrust` after its fetch (a
    /// fetch dated in the future, or none, doesn't count: the clock was set back), and not once a refusal lifted it.
    private var offInForce: Int? {
        let current = configured.withLock { $0 }
        guard current.mode == .off, let fetchedAt = current.fetchedAt,
              Self.inForce(fetchedAt.addingTimeInterval(Self.offTrust), now: clock.now(), longest: Self.offTrust),
              offLiftedAt != current.revision else { return nil }
        return current.revision
    }

    private func markUnsupported() {
        guard !unsupported else { return }
        unsupported = true
        Self.log.notice("App Attest: not supported on this device; requests go without an app token")
    }

    private var backoff: Backoff {
        if let cachedBackoff { return cachedBackoff }
        let loaded = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Backoff.self, from: $0) } ?? Backoff()
        cachedBackoff = loaded
        return loaded
    }

    private func updateBackoff(_ change: (inout Backoff) -> Void) {
        var next = backoff
        change(&next)
        guard next != backoff else { return }
        cachedBackoff = next
        defaults.set(try? JSONEncoder().encode(next), forKey: Self.defaultsKey)
    }

    private func backOff(retryAfter: Int?) {
        failures += 1
        let wait = retryAfter.map { Duration.seconds(max(1, $0)) }
            ?? min(Self.backoffCap, Self.backoffBase * (1 << min(failures - 1, 10)))
        notBefore = clock.uptime() + wait
    }

    // MARK: waiting

    /// Parks the caller until renewal `id` ends, `limit` passes on the clock, or the caller's task is cancelled.
    private func wait(for id: UUID, upTo limit: Duration) async {
        guard renewal?.id == id else { return }
        let waiter = UUID()
        let clock = self.clock
        let timeout = Task {
            guard (try? await clock.sleep(for: limit)) != nil else { return }
            self.release(waiter: waiter)
        }
        defer { timeout.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                if Task.isCancelled || renewal?.id != id { c.resume() } else { waiters[waiter] = (id, c) }
            }
        } onCancel: {
            Task { await self.release(waiter: waiter) }
        }
    }

    private func release(waiter: UUID) {
        waiters.removeValue(forKey: waiter)?.continuation.resume()
    }

    private func release(renewal id: UUID) {
        for (key, parked) in waiters where parked.renewal == id {
            waiters[key] = nil
            parked.continuation.resume()
        }
    }

    // MARK: one run (design.md §8)

    private enum Phase: String {
        case load, challenge, generateKey, attestKey, keys, assertion, token
    }

    /// How a run ends early. `retry`: the in-memory backoff (`after`: the answer's `Retry-After`).
    private enum Stop: Error {
        case quietly
        case unsupported
        case notServed
        case retry(after: Int?)
        case pauseAttestation(TimeInterval)
    }

    /// The run's key was dropped: it starts again at step 1.
    private struct NewKey: Error {}

    /// One run's account and its "once"s.
    private final class Run {
        let started: AttestStamp
        let generation: Int
        let client: APIClient
        /// Keys dropped and made again in this run: one.
        var newKeys = 0
        /// `app_attest_invalid` answers in this run: the second pauses attestation.
        var invalids = 0
        /// The steps that took a new challenge after `app_attest_challenge_invalid`: once each.
        var newChallenges: Set<String> = []

        init(started: AttestStamp, generation: Int, client: APIClient) {
            self.started = started
            self.generation = generation
            self.client = client
        }
    }

    private func run(_ id: UUID, epoch: Int, generation: Int, via client: APIClient) async {
        runsInFlight += 1
        defer { runsInFlight -= 1 }
        let signpost = Self.signposter.beginInterval("renewal", id: Self.signposter.makeSignpostID())
        await renew(epoch: epoch, generation: generation, via: client)
        Self.signposter.endInterval("renewal", signpost)
        // Ended already by a wipe, or by a newer account's renewal.
        guard renewal?.id == id else { return }
        renewal = nil
        release(renewal: id)
    }

    /// Publishes a token, or ends with the backoff that says when the next run may start.
    private func renew(epoch: Int, generation: Int, via client: APIClient) async {
        // A request whose account has gone (its epoch is older), or nobody signed in: nothing starts.
        guard let started = await stamp(), started.epoch == epoch else { return }
        let run = Run(started: started, generation: generation, client: client)
        do {
            var key = try await loadKey(run)
            while true {
                do {
                    let attested: StoredAppAttestKey
                    if let key, key.attested {
                        attested = key
                    } else {
                        attested = try await attest(key, run)
                    }
                    key = attested
                    let answer = try await token(attested, run)
                    try await publish(answer, run)
                    return
                } catch is NewKey {
                    key = nil
                }
            }
        } catch {
            // A run a wipe (or a newer account's renewal) ended leaves nothing behind: no backoff, in memory or
            // persisted, for the account that comes next.
            guard !Task.isCancelled, wipes.withLock({ $0 }) == generation else { return }
            ended(error)
        }
    }

    private func ended(_ error: Error) {
        switch error as? Stop ?? .retry(after: nil) {
        case .quietly:
            return
        case .unsupported:
            markUnsupported()
        case .notServed:
            let until = clock.now().addingTimeInterval(Self.notServedPause)
            updateBackoff {
                $0.notServedUntil = until
                $0.servedSeen = false
            }
            Self.log.notice("App Attest: not served yet; requests go without an app token for 6 h")
        case .retry(let after):
            backOff(retryAfter: after)
        case .pauseAttestation(let seconds):
            let until = clock.now().addingTimeInterval(min(seconds, Self.attestPause))
            updateBackoff { $0.attestPausedUntil = until }
            backOff(retryAfter: nil)
        }
    }

    /// Before every step: a cancelled run (a wipe, a newer account's renewal) or one from before a wipe sends nothing.
    private func check(_ run: Run) throws {
        guard !Task.isCancelled, wipes.withLock({ $0 }) == run.generation else { throw Stop.quietly }
    }

    /// The account's key. Another account's (a kill mid-wipe, an item that outlived a reinstall) is dropped. A throw is
    /// a Keychain that can't be read yet (before the first unlock): the in-memory backoff.
    private func loadKey(_ run: Run) async throws -> StoredAppAttestKey? {
        let stored: StoredAppAttestKey?
        do {
            stored = try keys.load()
        } catch {
            note(.load, error)
            throw Stop.retry(after: nil)
        }
        guard let stored else { return nil }
        if stored.account == run.started.account { return stored }
        try await write(run) { $0.remove() }
        return nil
    }

    /// A Keychain write for the run's account, in the same main-actor step as the check that the account, its epoch
    /// and the wipe count are still the run's: so it can't land after a wipe's delete, which is main-actor too.
    private func write(_ run: Run, _ change: @escaping @Sendable (AppAttestKeyStore) throws -> Void) async throws {
        let stamp = self.stamp, keys = self.keys, wipes = self.wipes
        let started = run.started, generation = run.generation
        let current = try await MainActor.run(resultType: Bool.self) {
            guard stamp() == started, wipes.withLock({ $0 }) == generation else { return false }
            try change(keys)
            return true
        }
        guard current else { throw Stop.quietly }
    }

    private func challenge(_ run: Run) async throws -> String {
        try check(run)
        do {
            let answer = try await run.client.appAttestChallenge()
            updateBackoff {
                $0.servedSeen = true
                $0.notServedUntil = nil
            }
            return answer.challenge
        } catch {
            throw stop(after: error, .challenge)
        }
    }

    /// Steps 1 and 2: a challenge, then a key (the account's unattested one, or a new one, kept at once so a kill
    /// orphans nothing), Apple's attestation over the challenge, and `POST /v1/app-attest/keys`.
    private func attest(_ existing: StoredAppAttestKey?, _ run: Run) async throws -> StoredAppAttestKey {
        if let until = backoff.attestPausedUntil,
           Self.inForce(until, now: clock.now(), longest: Self.attestPause) {
            throw Stop.retry(after: Int(until.timeIntervalSince(clock.now()).rounded(.up)))
        }
        var challenge = try await self.challenge(run)
        var key: StoredAppAttestKey
        if let existing {
            key = existing
        } else {
            try check(run)
            do {
                key = StoredAppAttestKey(account: run.started.account, keyId: try await service.generateKey(),
                                         attested: false)
            } catch {
                throw deviceStop(error, .generateKey)
            }
            let made = key
            try await write(run) { try $0.save(made) }
        }
        while true {
            try check(run)
            let attestation: Data
            do {
                let signpost = Self.signposter.beginInterval("attestKey", id: Self.signposter.makeSignpostID())
                defer { Self.signposter.endInterval("attestKey", signpost) }
                attestation = try await service.attestKey(key.keyId, clientDataHash: Self.clientDataHash(challenge))
            } catch {
                throw try await failedAttestation(error, run)
            }
            do {
                try check(run)
                _ = try await run.client.postAppAttestKey(AppAttestKeyPost(
                    keyId: key.keyId, attestation: attestation.base64EncodedString(), challenge: challenge))
            } catch {
                if newChallenge(after: error, .keys, run) {
                    challenge = try await self.challenge(run)
                    continue
                }
                throw try await refused(error, .keys, run)
            }
            key.attested = true
            let attested = key
            try await write(run) { try $0.save(attested) }
            Self.log.info("App Attest: key attested")
            return key
        }
    }

    /// Step 3: a challenge, an assertion over it with the attested key, and `POST /v1/app-attest/token`.
    private func token(_ key: StoredAppAttestKey, _ run: Run) async throws -> AppAttestToken {
        var challenge = try await self.challenge(run)
        while true {
            try check(run)
            let assertion: Data
            do {
                let signpost = Self.signposter.beginInterval("assertion", id: Self.signposter.makeSignpostID())
                defer { Self.signposter.endInterval("assertion", signpost) }
                assertion = try await service.generateAssertion(key.keyId,
                                                                clientDataHash: Self.clientDataHash(challenge))
            } catch {
                throw try await failedAssertion(error, run)
            }
            do {
                try check(run)
                return try await run.client.postAppAttestToken(AppAttestTokenPost(
                    keyId: key.keyId, challenge: challenge, assertion: assertion.base64EncodedString()))
            } catch {
                if newChallenge(after: error, .token, run) {
                    challenge = try await self.challenge(run)
                    continue
                }
                throw try await refused(error, .token, run)
            }
        }
    }

    /// The token, for requests of the run's epoch: only while the account, its epoch and the wipe count are still the
    /// run's. Its lifetime counts from when the answer arrived, on the monotonic clock (never `expires_at` against the
    /// device's clock).
    private func publish(_ answer: AppAttestToken, _ run: Run) async throws {
        let arrived = clock.uptime()
        guard answer.ttlSec > 0 else { throw Stop.retry(after: nil) }
        let stamp = self.stamp, wipes = self.wipes, started = run.started, generation = run.generation
        let current = await MainActor.run(resultType: Bool.self) {
            stamp() == started && wipes.withLock({ $0 }) == generation
        }
        // Again here: a wipe between that check and this step.
        guard current, wipes.withLock({ $0 }) == generation else { throw Stop.quietly }
        let lead = min(Self.renewalLead, answer.ttlSec / 2)
        issued = Issued(token: answer.token, epoch: started.epoch, renewAt: arrived + .seconds(answer.ttlSec - lead),
                        expiresAt: arrived + .seconds(answer.ttlSec))
        failures = 0
        notBefore = nil
        Self.log.info("App Attest: token renewed")
    }

    // MARK: what a failure means (design.md §4 and §8)

    /// `422 app_attest_challenge_invalid`: a new challenge, then the same step again, once per step and run.
    private func newChallenge(after error: Error, _ phase: Phase, _ run: Run) -> Bool {
        guard let api = error as? APIError, api.status == 422, api.code == .appAttestChallengeInvalid,
              !run.newChallenges.contains(phase.rawValue) else { return false }
        note(phase, error)
        run.newChallenges.insert(phase.rawValue)
        return true
    }

    /// The answer of `POST keys` or `POST token`.
    private func refused(_ error: Error, _ phase: Phase, _ run: Run) async throws -> Error {
        guard let api = error as? APIError, let status = api.status else { return stop(after: error, phase) }
        switch (status, api.code) {
        case (404, .appAttestKeyUnknown?) where phase == .token:
            note(phase, error)
            return try await dropKey(run)
        case (422, .appAttestInvalid?):
            note(phase, error)
            run.invalids += 1
            let next = try await dropKey(run)
            return run.invalids >= 2 ? Stop.pauseAttestation(Self.attestPause) : next
        case (429, _) where phase == .keys:
            // The keys budget (10 a day): no attestation until then; a token with an attested key still works.
            note(phase, error)
            return Stop.pauseAttestation(api.retryAfter.map(TimeInterval.init) ?? Self.keysRateLimitPause)
        case (400, _):
            // A client bug: sent again unchanged it fails the same way, and a try costs a key.
            note(phase, error)
            return Stop.pauseAttestation(Self.attestPause)
        default:
            return stop(after: error, phase)
        }
    }

    /// `attestKey` failed: `invalidKey` is a key that's gone (a reinstall, a restore): a new one, once.
    /// `serverUnavailable` keeps the key for the next try; anything else drops it.
    private func failedAttestation(_ error: Error, _ run: Run) async throws -> Error {
        switch (error as? DCError)?.code {
        case .invalidKey?:
            note(.attestKey, error)
            return try await dropKey(run)
        case .serverUnavailable?:
            return deviceStop(error, .attestKey)
        default:
            if error.isCancellation { return Stop.quietly }
            try await write(run) { $0.remove() }
            return deviceStop(error, .attestKey)
        }
    }

    /// `generateAssertion` failed: `invalidKey` is a key that's gone: a new one, once.
    private func failedAssertion(_ error: Error, _ run: Run) async throws -> Error {
        guard (error as? DCError)?.code == .invalidKey else { return deviceStop(error, .assertion) }
        note(.assertion, error)
        return try await dropKey(run)
    }

    /// Drops the run's key. The run starts again at step 1 the first time; after that it ends (the backoff).
    private func dropKey(_ run: Run) async throws -> Error {
        try await write(run) { $0.remove() }
        guard run.newKeys == 0 else { return Stop.retry(after: nil) }
        run.newKeys += 1
        return NewKey()
    }

    /// A DeviceCheck failure: `featureUnsupported` ends App Attest for the process; anything else is the backoff.
    private func deviceStop(_ error: Error, _ phase: Phase) -> Error {
        if error.isCancellation { return Stop.quietly }
        note(phase, error)
        return (error as? DCError)?.code == .featureUnsupported ? Stop.unsupported : Stop.retry(after: nil)
    }

    /// A failed request: `404` without a `code` or `501` is "not served"; anything else (a `429`, a `5xx`, no
    /// answer, a final `401`) is the backoff, for `Retry-After` when it came with one.
    private func stop(after error: Error, _ phase: Phase) -> Error {
        if error is Stop || error is NewKey { return error }
        if error.isCancellation { return Stop.quietly }
        note(phase, error)
        guard let api = error as? APIError else { return Stop.retry(after: nil) }
        if (api.status == 404 && api.code == nil) || api.status == 501 { return Stop.notServed }
        return Stop.retry(after: api.retryAfter)
    }

    /// One line per failed step: the step, the status, the `code`, the request ID, the DCError or Keychain code.
    private func note(_ phase: Phase, _ error: Error) {
        let step = phase.rawValue
        if let api = error as? APIError {
            if case .transport(let inner) = api {
                let name = (inner as? URLError)?.code.name ?? "transport"
                Self.log.notice("App Attest \(step, privacy: .public): no answer (\(name, privacy: .public))")
                return
            }
            Self.log.notice("""
            App Attest \(step, privacy: .public): HTTP \(api.status ?? 0, privacy: .public) \
            \(api.code?.rawValue ?? "-", privacy: .public), request \(api.requestID ?? "-", privacy: .public)
            """)
        } else if let device = error as? DCError {
            Self.log.notice("App Attest \(step, privacy: .public): DCError \(device.code.rawValue, privacy: .public)")
        } else if let keychain = error as? Keychain.Failure {
            Self.log.notice("App Attest \(step, privacy: .public): Keychain \(keychain.status, privacy: .public)")
        } else {
            Self.log.notice("App Attest \(step, privacy: .public): \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}
