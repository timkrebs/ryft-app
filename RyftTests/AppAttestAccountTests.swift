import Foundation
import Testing
@testable import Ryft

/// AC8: the key and the token are the account's. A wipe (`AuthService.wipeSharedLocalData` calls
/// `AppAttestor.live.wipe()`; the rig's `switchAccount` does the same on its attestor) ends them, and a renewal that
/// was under way for the old account never publishes anything for the new one.
@Suite("App Attest: wipe and account switch (AC8)")
@MainActor
struct AppAttestAccountTests {
    /// Where account A's renewal is when the account changes.
    enum InFlight: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case assertion       // `generateAssertion` returns after the wipe
        case keysAnswer      // `POST keys`' answer arrives after the wipe
        case tokenAnswer     // `POST token`' answer arrives after the wipe
        var testDescription: String { rawValue }
    }

    /// Tokens name the key they were minted for, so a token of A's is recognisable on B's requests.
    private func rigNamingTokensByKey() -> AttestRig {
        let rig = AttestRig()
        rig.server.serveAppAttest(tokenFor: { request, _ in "tok-of-\(request.field("key_id") ?? "?")" })
        return rig
    }

    @Test(arguments: InFlight.allCases)
    func aRenewalInFlightForTheOldAccountNeverReachesTheNextOne(_ stage: InFlight) async throws {
        let rig = rigNamingTokensByKey()
        let hold = RequestHold()
        switch stage {
        case .assertion: rig.service.holdAssertion(hold)
        case .keysAnswer: rig.server.hold(AttestServer.keys)
        case .tokenAnswer: rig.server.hold(AttestServer.token)
        }
        let requestOfA = Task { try await rig.getMe() }
        switch stage {
        case .assertion: #expect(await rig.until { hold.waiting == 1 })
        case .keysAnswer, .tokenAnswer: #expect(await rig.until { rig.server.heldCount == 1 })
        }
        #expect(await rig.until { await rig.attestor.waiting == 1 })
        let savedBeforeTheWipe = rig.keys.saved.count

        rig.switchAccount(to: AttestRig.b)
        #expect(rig.keys.stored == nil)                              // A's Keychain item is gone at once
        switch stage {
        case .assertion: hold.release()
        case .keysAnswer, .tokenAnswer: rig.server.releaseHeld()
        }

        // B's requests: their own key, their own token.
        _ = try await rig.getMe()
        _ = try await requestOfA.value
        let tokens = rig.server.appTokens(AttestServer.me)
        #expect(tokens.contains("tok-of-key-2"))
        #expect(!tokens.contains("tok-of-key-1"), "a token minted for A's key went out")
        #expect(tokens.allSatisfy { $0 == nil || $0 == "tok-of-key-2" })
        #expect(rig.keys.saved.dropFirst(savedBeforeTheWipe).allSatisfy { $0.account == AttestRig.b })
        #expect(rig.keys.stored == StoredAppAttestKey(account: AttestRig.b, keyId: "key-2", attested: true))
        let tokenPosts = rig.server.requests(AttestServer.token).compactMap { $0.field("key_id") }
        #expect(tokenPosts == (stage == .tokenAnswer ? ["key-1", "key-2"] : ["key-2"]))
    }

    @Test func theNextAccountAttestsItsOwnKey() async throws {
        let rig = rigNamingTokensByKey()
        _ = try await rig.getMe()
        #expect(rig.keys.stored == StoredAppAttestKey(account: AttestRig.a, keyId: "key-1", attested: true))

        rig.switchAccount(to: AttestRig.b)
        #expect(rig.keys.stored == nil && rig.keys.removals >= 1)
        _ = try await rig.getMe()
        #expect(rig.service.count("generateKey") == 2)
        #expect(rig.keys.stored == StoredAppAttestKey(account: AttestRig.b, keyId: "key-2", attested: true))
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-of-key-1", "tok-of-key-2"])
        #expect(rig.server.requests(AttestServer.keys).compactMap { $0.field("key_id") } == ["key-1", "key-2"])
    }

    @Test func aRequestOfTheOldAccountStillInFlightNeverStartsARenewalForTheNewOne() async throws {
        let rig = rigNamingTokensByKey()
        _ = try await rig.getMe()                                    // A has a token
        rig.server.hold(AttestServer.me)
        let late = Task { try await rig.getMe() }                    // A's request, answered after the switch
        #expect(await rig.until { rig.server.heldCount == 1 })
        rig.switchAccount(to: AttestRig.b)
        rig.server.releaseHeld()
        _ = try await late.value
        // It carried A's token before the switch; B's own request then brings B's.
        _ = try await rig.getMe()
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-of-key-1", "tok-of-key-1", "tok-of-key-2"])
    }

    @Test func aKeyOfAnotherAccountIsDroppedWhenRead() async throws {
        // A kill in the middle of a wipe, or an item that outlived a reinstall: B signs in, A's key is in the Keychain.
        let rig = AttestRig(storedKey: StoredAppAttestKey(account: AttestRig.a, keyId: "key-old", attested: true))
        rig.account = AttestRig.b
        _ = try await rig.getMe()
        #expect(!rig.service.calls.contains(.generateAssertion("key-old", AppAttestor.clientDataHash("chal-1"))))
        #expect(!rig.server.requests.contains { $0.field("key_id") == "key-old" })
        #expect(rig.keys.stored == StoredAppAttestKey(account: AttestRig.b, keyId: "key-1", attested: true))
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1"])
    }

    @Test func theWipeEndsTheAttestationPauseAndKeepsTheNotServedBackoff() async throws {
        let rig = AttestRig(served: false)
        let inThreeHours = rig.clock.now().addingTimeInterval(3 * 3_600)
        rig.defaults.set(try JSONEncoder().encode(AppAttestor.Backoff(
            notServedUntil: inThreeHours, attestPausedUntil: inThreeHours)), forKey: AppAttestor.defaultsKey)
        rig.launch()
        rig.attestor.wipe()
        _ = try await rig.getMe()                                    // the attestor's next call applies the wipe
        let kept = rig.backoff
        #expect(kept?.attestPausedUntil == nil)
        #expect(kept?.notServedUntil == inThreeHours)                // the platform's answer, not the account's
        #expect(rig.server.count(AttestServer.challenge) == 0)
    }

    @Test func aWipeRemovesTheKeychainItemOnTheCallersThread() async throws {
        let rig = AttestRig()
        _ = try await rig.getMe()
        rig.attestor.wipe()
        #expect(rig.keys.stored == nil)
        #expect(rig.keys.removals == 1)
    }

    @Test func aStalledRenewalIsEndedByTheWipeAndItsWaitersLetGo() async throws {
        let rig = rigNamingTokensByKey()
        rig.server.hold(AttestServer.challenge)
        let request = Task { try await rig.getMe() }
        #expect(await rig.until { rig.server.heldCount == 1 })
        #expect(await rig.until { await rig.attestor.waiting == 1 })
        rig.attestor.wipe()
        _ = try await request.value                                  // not left waiting for its 3 s on the clock
        #expect(await rig.until { await rig.attestor.waiting == 0 })
        #expect(rig.server.appTokens(AttestServer.me) == [nil])
        rig.server.releaseHeld()
    }
}
