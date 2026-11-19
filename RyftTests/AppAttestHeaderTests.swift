import Foundation
import Security
import Testing
@testable import Ryft

/// AC1: the first run, both hashes, the header where it belongs, the bodies' base64 and the Keychain item.
@Suite("App Attest: first token and header (AC1)")
@MainActor
struct AppAttestHeaderTests {
    static let challenge1 = AppAttestHashVectorTests.challenge1
    static let challenge2 = AppAttestHashVectorTests.challenge2

    @Test func theFirstRunGoesChallengeKeyChallengeTokenThenTheRequest() async throws {
        let rig = AttestRig()
        _ = try await rig.getMe()
        #expect(rig.events.all == ["net challenge", "dc generateKey", "dc attestKey", "net keys",
                                   "net challenge", "dc generateAssertion", "net token", "net GET /v1/me"])
        #expect(rig.keys.stored == StoredAppAttestKey(account: "account-a", keyId: "key-1", attested: true))
    }

    @Test func bothStepsHashTheChallengeAsReceived() async throws {
        let rig = AttestRig()
        rig.server.serveAppAttest(challenges: [Self.challenge1, Self.challenge2])
        _ = try await rig.getMe()
        #expect(rig.service.calls == [
            .generateKey,
            .attestKey("key-1", AppAttestHashVectorTests.commonCryptoSHA256(Self.challenge1)),
            .generateAssertion("key-1", AppAttestHashVectorTests.commonCryptoSHA256(Self.challenge2)),
        ])
        // …and the same challenges went back to the platform untouched.
        #expect(rig.server.requests(AttestServer.keys).first?.field("challenge") == Self.challenge1)
        #expect(rig.server.requests(AttestServer.token).first?.field("challenge") == Self.challenge2)
    }

    @Test func theNextApiRequestsCarryTheToken() async throws {
        let rig = AttestRig()
        _ = try await rig.getMe()
        _ = try await rig.getMe()
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1", "tok-1"])
        #expect(rig.server.count(AttestServer.token) == 1)
    }

    @Test func ingestPostSyncCarriesTheToken() async throws {
        let rig = AttestRig()
        _ = try await rig.postSync()
        let sync = try #require(rig.server.requests(AttestServer.sync).first)
        #expect(sync.host == rig.server.ingestHost)
        #expect(sync.appToken == "tok-1")
        // The API host got the same token on its own routes.
        _ = try await rig.getMe()
        #expect(rig.server.requests(AttestServer.me).first?.host == rig.server.host)
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1"])
    }

    @Test func aBackgroundRunCarriesTheTokenOnItsFirstRequestAndLater() async throws {
        let rig = AttestRig()
        try await APIClient.$runsInBackground.withValue(true) {
            // The sync page of a HealthKit wake-up: the whole run happens inside the background task.
            _ = try await rig.postSync()
            _ = try await rig.getMe()
        }
        #expect(rig.server.appTokens(AttestServer.sync) == ["tok-1"])
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1"])
        #expect(rig.server.count(AttestServer.token) == 1)
    }

    @Test func aFreshInstallGoesWithoutAndTheNextRequestCarriesTheToken() async throws {
        // Never seen the challenge route answer 200: the request doesn't wait, the renewal runs behind it.
        let rig = AttestRig(served: false)
        _ = try await rig.getMe()
        #expect(await rig.renewalEnded())
        _ = try await rig.getMe()
        #expect(rig.server.appTokens(AttestServer.me).count == 2)
        #expect(rig.server.appTokens(AttestServer.me).last == "tok-1")
        #expect(rig.backoff?.servedSeen == true)
    }

    @Test func theThreeAppAttestRoutesNeverCarryAToken() async throws {
        let rig = AttestRig()
        _ = try await rig.getMe()
        // Called straight, with a token in hand: still none.
        _ = try await rig.api.appAttestChallenge()
        _ = try await rig.api.postAppAttestKey(AppAttestKeyPost(keyId: "k", attestation: "a", challenge: "c"))
        _ = try await rig.api.postAppAttestToken(AppAttestTokenPost(keyId: "k", challenge: "c", assertion: "a"))
        for route in AttestServer.appAttestRoutes {
            #expect(rig.server.count(route) >= 2, "\(route)")
            #expect(rig.server.appTokens(route).allSatisfy { $0 == nil }, "\(route)")
        }
        #expect(APIClient.appAttestRoutes == Set(AttestServer.appAttestRoutes))
        for route in AttestServer.appAttestRoutes {
            #expect(APIClient.openBehindInviteGate.contains(route), "\(route) is outside the beta gate")
        }
    }

    @Test func theBodiesUseStandardBase64() async throws {
        let rig = AttestRig()
        let keyID = "pKqW2rZ8yH3nT6v+1mX9cF4sD7gJ0eL5uA2oI8w/3kE="
        rig.service.keyID = keyID
        // 0xfb 0xef 0xbe → "++++", 0xff ×3 → "////", a last byte → "+w==".
        rig.service.attestation = Data([0xfb, 0xef, 0xbe, 0xff, 0xff, 0xff, 0xfb])
        rig.service.assertion = Data([0xff, 0xff, 0xff, 0xfb, 0xef, 0xbe, 0xfb])
        _ = try await rig.getMe()
        let attestation = try #require(rig.server.requests(AttestServer.keys).first)
        let assertion = try #require(rig.server.requests(AttestServer.token).first)
        #expect(attestation.field("attestation") == "++++////+w==")
        #expect(assertion.field("assertion") == "////+++++w==")
        for sent in [attestation.field("attestation"), assertion.field("assertion")] {
            let text = try #require(sent)
            #expect(!text.contains("-") && !text.contains("_"), "url-safe base64 is not what the contract takes")
        }
        #expect(attestation.field("attestation").flatMap { Data(base64Encoded: $0) } == rig.service.attestation)
        // The key ID is passed as `generateKey` returned it, not re-encoded.
        #expect(attestation.field("key_id") == keyID)
        #expect(assertion.field("key_id") == keyID)
        #expect(attestation.header("Content-Type") == "application/json")
    }

    // MARK: the Keychain item

    @Test func theKeyItemIsAfterFirstUnlockThisDeviceOnlyAndNeverSynchronizable() throws {
        let data = Data("{}".utf8)
        let attributes = Keychain.attributes(for: KeychainAppAttestKeys.item, data: data,
                                             accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(attributes[kSecAttrAccount as String] as? String == "ryft.appAttest.key")
        #expect(attributes[kSecClass as String] as? String == kSecClassGenericPassword as String)
        let synchronizable = attributes[kSecAttrSynchronizable as String]
        #expect(synchronizable == nil || (synchronizable as? Bool) == false)
    }

    /// The real item `KeychainAppAttestKeys` writes, read back from the Keychain (the simulator never attests, so
    /// nothing of the app's is in this item).
    @Test func theKeychainStoreWritesThatItemAndReadsItBack() throws {
        let store = KeychainAppAttestKeys()
        store.remove()
        defer { store.remove() }
        let key = StoredAppAttestKey(account: "account-a", keyId: "key-1", attested: true)
        try store.save(key)
        #expect(try store.load() == key)

        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: KeychainAppAttestKeys.item,
                                    kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var found: AnyObject?
        #expect(SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess)
        let attributes = try #require(found as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        let synchronizable = attributes[kSecAttrSynchronizable as String]
        #expect(synchronizable == nil || (synchronizable as? Bool) == false || (synchronizable as? Int) == 0)

        store.remove()
        #expect(try store.load() == nil)
    }
}

/// AC2: renewal under 300 s left, on the app's own monotonic clock.
@Suite("App Attest: refresh (AC2)")
@MainActor
struct AppAttestRefreshTests {
    @Test func underThreeHundredSecondsLeftOneRenewalAndNoNewKey() async throws {
        let rig = AttestRig()
        _ = try await rig.getMe()                                   // tok-1, ttl 3600
        rig.clock.advance(by: .seconds(3_299))                      // 301 s left
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.token) == 1)

        rig.clock.advance(by: .seconds(2))                          // 299 s left
        _ = try await rig.getMe()                                   // still sends the current token
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.token) == 2)
        #expect(rig.service.count("generateKey") == 1 && rig.service.count("generateAssertion") == 2)
        #expect(rig.service.count("attestKey") == 1 && rig.server.count(AttestServer.keys) == 1)
        _ = try await rig.getMe()
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1", "tok-1", "tok-1", "tok-2"])
    }

    @Test func changingTheDeviceDateChangesNothing() async throws {
        let rig = AttestRig()
        _ = try await rig.getMe()
        rig.clock.set(rig.clock.now().addingTimeInterval(7_200))    // the user sets the date forward
        _ = try await rig.getMe()
        rig.clock.set(rig.clock.now().addingTimeInterval(-86_400))  // …and back
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.token) == 1)
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1", "tok-1", "tok-1"])
    }

    @Test func neverTwoRenewalsAtOnce() async throws {
        let rig = AttestRig()
        _ = try await rig.getMe()
        rig.clock.advance(by: .seconds(3_400))
        rig.server.hold(AttestServer.challenge)
        // Four requests while the renewal is under way: all go with the token still valid, none starts another run.
        for _ in 0..<4 { _ = try await rig.getMe() }
        #expect(await rig.until { rig.server.heldCount == 1 })
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1", "tok-1", "tok-1", "tok-1", "tok-1"])
        rig.server.releaseHeld()
        #expect(await rig.renewalEnded())
        #expect(rig.server.count(AttestServer.token) == 2)
        #expect(rig.server.count(AttestServer.challenge) == 3)      // two for the first run, one for the renewal
    }

    @Test func aTokenPastItsExpiryIsNeverSent() async throws {
        let rig = AttestRig()
        _ = try await rig.getMe()
        rig.clock.advance(by: .seconds(3_601))
        rig.server.hold(AttestServer.challenge)
        let request = Task { try await rig.getMe() }
        // The request waits for the renewal; it gives up after 3 s on the clock and goes without.
        // (its timeout is registered on the clock, too: advancing before that would move the deadline with it)
        #expect(await rig.until { await rig.attestor.waiting == 1 && rig.clock.pendingSleeps == 1 })
        rig.clock.advance(by: .seconds(3))
        _ = try await request.value
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1", nil])
        rig.server.releaseHeld()
        #expect(await rig.renewalEnded())
    }
}

extension Data {
    /// Bytes from a lowercase hex string.
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            guard let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) else { break }
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}
