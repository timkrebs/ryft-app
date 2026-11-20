import DeviceCheck
import Foundation
import Testing
@testable import Ryft

private let refused = AttestServer.Reply.refusal(403, code: "app_attest_required", requestID: "rid-403")
private let challengeInvalid = AttestServer.Reply.refusal(422, code: "app_attest_challenge_invalid", requestID: "rid-c")
private let invalid = AttestServer.Reply.refusal(422, code: "app_attest_invalid", requestID: "rid-i")

/// A date within a second of `expected`.
private func near(_ date: Date?, _ expected: Date) -> Bool {
    guard let date else { return false }
    return abs(date.timeIntervalSince(expected)) < 1
}

/// AC3: `403 app_attest_required` gets one new token and one more try.
@Suite("App Attest: 403 app_attest_required (AC3)")
@MainActor
struct AppAttestRequiredTests {
    /// A rig that holds `tok-1` and a clock past the 60 s a refusal needs after a renewal started.
    private func holdingToken() async throws -> AttestRig {
        let rig = AttestRig()
        _ = try await rig.getMe()
        rig.clock.advance(by: .seconds(61))
        return rig
    }

    @Test func refusedOnceRenewsOnceAndTheRequestGoesAgainWithTheNewToken() async throws {
        let rig = try await holdingToken()
        rig.server.route(AttestServer.me) { request, _ in request.appToken == "tok-1" ? refused : .ok }
        _ = try await rig.getMe()
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1", "tok-1", "tok-2"])
        #expect(rig.server.count(AttestServer.token) == 2)
        // A renewal: challenge → assertion → token. No new key.
        #expect(rig.service.count("generateKey") == 1 && rig.service.count("attestKey") == 1)
        #expect(rig.service.count("generateAssertion") == 2 && rig.server.count(AttestServer.keys) == 1)
    }

    @Test func aWriteIsSentAgainToo() async throws {
        let rig = try await holdingToken()
        rig.server.route(AttestServer.sync) { request, _ in request.appToken == "tok-1" ? refused : .ok }
        _ = try await rig.postSync()
        #expect(rig.server.appTokens(AttestServer.sync) == ["tok-1", "tok-2"])
    }

    @Test func refusedAgainIsThrownWithItsRequestIDAndNothingLoops() async throws {
        let rig = try await holdingToken()
        rig.server.route(AttestServer.me) { _, _ in refused }
        await #expect {
            try await rig.getMe()
        } throws: { error in
            let api = error as? APIError
            return api?.status == 403 && api?.code == .appAttestRequired && api?.requestID == "rid-403"
        }
        // The warm-up, the refused request and its one resend; one renewal.
        #expect(rig.server.count(AttestServer.me) == 3)
        #expect(rig.server.count(AttestServer.token) == 2)
        let record = rig.status.failures.first
        #expect(record?.status == 403 && record?.code == "app_attest_required" && record?.requestID == "rid-403")

        // Another request straight after: refused, no second renewal this soon, so no resend either.
        await #expect(throws: APIError.self) { try await rig.getMe() }
        #expect(rig.server.count(AttestServer.me) == 4)
        #expect(rig.server.count(AttestServer.token) == 2)
        #expect(rig.server.count(AttestServer.challenge) == 3)
    }

    @Test func aRefusalSoonAfterARenewalStartedStartsNoneOfItsOwn() async throws {
        let rig = AttestRig()
        _ = try await rig.getMe()                                   // the run started at uptime 0
        rig.server.route(AttestServer.me) { _, _ in refused }
        await #expect {
            try await rig.getMe()
        } throws: { ($0 as? APIError)?.requestID == "rid-403" }
        #expect(rig.server.count(AttestServer.me) == 2)             // sent once, not again
        #expect(rig.server.count(AttestServer.token) == 1)
    }

    @Test func fiveConcurrentRefusalsWaitForOneRenewal() async throws {
        let rig = try await holdingToken()
        rig.server.route(AttestServer.me) { request, _ in request.appToken == "tok-1" ? refused : .ok }
        rig.server.hold(AttestServer.challenge)                     // the renewal's challenge stays out
        let requests = (0..<5).map { _ in Task { try await rig.getMe() } }
        #expect(await rig.until { await rig.attestor.waiting == 5 })
        #expect(rig.server.heldCount == 1)
        #expect(rig.server.count(AttestServer.challenge) == 3)      // two for the first run, one held
        rig.server.releaseHeld()
        for request in requests { _ = try await request.value }

        #expect(rig.server.count(AttestServer.token) == 2)
        #expect(rig.server.count(AttestServer.challenge) == 3)
        #expect(rig.service.count("generateAssertion") == 2)
        let tokens = rig.server.appTokens(AttestServer.me)
        #expect(tokens.filter { $0 == "tok-1" }.count == 1 + 5)     // the warm-up and the five refused
        #expect(tokens.filter { $0 == "tok-2" }.count == 5)         // each resent once
        #expect(tokens.count == 11)
    }

    @Test(arguments: ["consent_required", "invite_required", ""])
    func anotherForbiddenIsNotAnAttestRefusal(_ code: String) async throws {
        let rig = try await holdingToken()
        rig.server.route(AttestServer.me) { _, _ in .refusal(403, code: code.isEmpty ? nil : code, requestID: "rid-x") }
        await #expect(throws: APIError.self) { try await rig.getMe() }
        #expect(rig.server.count(AttestServer.me) == 2)             // the warm-up and the one refused
        #expect(rig.server.count(AttestServer.token) == 1)
    }

    @Test func theAppAttestRoutesDontHandleTheirOwnRefusalsSoNothingRecurses() async throws {
        let rig = AttestRig()
        rig.server.reply(AttestServer.challenge, refused)
        _ = try await rig.getMe()                                   // goes without: the run ended
        #expect(await rig.renewalEnded())
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 1)
        #expect(rig.service.calls.isEmpty)
        #expect(rig.server.appTokens(AttestServer.me) == [nil, nil])
    }
}

/// AC4: a key the platform doesn't know is replaced once.
@Suite("App Attest: key unknown (AC4)")
@MainActor
struct AppAttestKeyUnknownTests {
    struct Refusal: Sendable, CustomTestStringConvertible {
        let status: Int
        let code: String
        var testDescription: String { "\(status) \(code)" }
    }

    private let attested = StoredAppAttestKey(account: "account-a", keyId: "key-old", attested: true)

    @Test(arguments: [Refusal(status: 404, code: "app_attest_key_unknown"),
                      Refusal(status: 422, code: "app_attest_invalid")])
    func theKeyIsDroppedANewOneAttestedThenATokenOnce(_ refusal: Refusal) async throws {
        let rig = AttestRig(storedKey: attested)
        rig.server.route(AttestServer.token) { _, n in
            n == 0 ? .refusal(refusal.status, code: refusal.code, requestID: "rid-k") : .token("tok-new")
        }
        _ = try await rig.getMe()
        #expect(rig.events.all == [
            "net challenge", "dc generateAssertion", "net token",              // the old key: refused
            "net challenge", "dc generateKey", "dc attestKey", "net keys",     // a new one, attested
            "net challenge", "dc generateAssertion", "net token",              // its token
            "net GET /v1/me",
        ])
        #expect(rig.service.calls == [
            .generateAssertion("key-old", AppAttestor.clientDataHash("chal-1")),
            .generateKey,
            .attestKey("key-1", AppAttestor.clientDataHash("chal-2")),
            .generateAssertion("key-1", AppAttestor.clientDataHash("chal-3")),
        ])
        #expect(rig.keys.stored == StoredAppAttestKey(account: "account-a", keyId: "key-1", attested: true))
        #expect(rig.keys.removals >= 1)
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-new"])
    }

    @Test func refusedAgainItStopsAndTheNextRequestsDoNotTryAgain() async throws {
        let rig = AttestRig(storedKey: attested)
        rig.server.reply(AttestServer.token, .refusal(404, code: "app_attest_key_unknown", requestID: "rid-k"))
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.token) == 2)          // the old key's, and the new key's
        #expect(rig.service.count("generateKey") == 1)              // one new key, not more
        #expect(rig.server.appTokens(AttestServer.me) == [nil])

        let requests = rig.server.appAttestRequests
        _ = try await rig.getMe()
        #expect(rig.server.appAttestRequests == requests)           // backing off
        #expect(rig.service.count("generateKey") == 1)
    }
}

/// AC9: the 422 matrix, `400`, and `429`.
@Suite("App Attest: 422, 400 and 429 (AC9)")
@MainActor
struct AppAttestRefusedStepsTests {
    @Test func challengeInvalidOnKeysTakesANewChallengeAndTheSameStepOnce() async throws {
        let rig = AttestRig()
        rig.server.route(AttestServer.keys) { request, n in n == 0 ? challengeInvalid : .keyCreated(request) }
        _ = try await rig.getMe()
        #expect(rig.events.all == [
            "net challenge", "dc generateKey", "dc attestKey", "net keys",
            "net challenge", "dc attestKey", "net keys",                       // a new challenge, the same step
            "net challenge", "dc generateAssertion", "net token", "net GET /v1/me",
        ])
        #expect(rig.service.count("generateKey") == 1)
        #expect(rig.service.calls[1] == .attestKey("key-1", AppAttestor.clientDataHash("chal-1")))
        #expect(rig.service.calls[2] == .attestKey("key-1", AppAttestor.clientDataHash("chal-2")))
        #expect(rig.server.requests(AttestServer.keys).map { $0.field("challenge") } == ["chal-1", "chal-2"])
        #expect(rig.keys.stored?.attested == true)
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1"])
    }

    @Test func challengeInvalidOnTokenTakesANewChallengeAndTheSameStepOnce() async throws {
        let rig = AttestRig()
        rig.server.route(AttestServer.token) { _, n in n == 0 ? challengeInvalid : .token("tok-after") }
        _ = try await rig.getMe()
        #expect(rig.events.all == [
            "net challenge", "dc generateKey", "dc attestKey", "net keys",
            "net challenge", "dc generateAssertion", "net token",
            "net challenge", "dc generateAssertion", "net token", "net GET /v1/me",
        ])
        #expect(rig.service.count("generateKey") == 1 && rig.server.count(AttestServer.keys) == 1)
        #expect(rig.server.requests(AttestServer.token).map { $0.field("challenge") } == ["chal-2", "chal-3"])
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-after"])
    }

    @Test(arguments: [AttestServer.keys, AttestServer.token])
    func challengeInvalidAgainEndsTheRunAndNothingLoops(_ route: String) async throws {
        let rig = AttestRig()
        rig.server.reply(route, challengeInvalid)
        _ = try await rig.getMe()
        #expect(rig.server.count(route) == 2)
        #expect(rig.server.appTokens(AttestServer.me) == [nil])
        let requests = rig.server.appAttestRequests
        _ = try await rig.getMe()
        #expect(rig.server.appAttestRequests == requests)
        #expect(rig.service.count("generateKey") == 1)
    }

    @Test func invalidOnKeysDropsTheKeyAndAttestsANewOneOnce() async throws {
        let rig = AttestRig()
        rig.server.route(AttestServer.keys) { request, n in n == 0 ? invalid : .keyCreated(request) }
        _ = try await rig.getMe()
        #expect(rig.events.all == [
            "net challenge", "dc generateKey", "dc attestKey", "net keys",
            "net challenge", "dc generateKey", "dc attestKey", "net keys",     // a new key
            "net challenge", "dc generateAssertion", "net token", "net GET /v1/me",
        ])
        #expect(rig.server.requests(AttestServer.keys).map { $0.field("key_id") } == ["key-1", "key-2"])
        #expect(rig.keys.stored == StoredAppAttestKey(account: "account-a", keyId: "key-2", attested: true))
        #expect(rig.backoff?.attestPausedUntil == nil)
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1"])
    }

    @Test func invalidTwiceStopsAttestationForADayAndAcrossLaunches() async throws {
        let rig = AttestRig()
        rig.server.reply(AttestServer.keys, invalid)
        _ = try await rig.getMe()
        #expect(rig.service.count("generateKey") == 2 && rig.server.count(AttestServer.keys) == 2)
        #expect(rig.server.appTokens(AttestServer.me) == [nil])
        #expect(rig.keys.stored == nil)
        #expect(near(rig.backoff?.attestPausedUntil, rig.clock.now().addingTimeInterval(24 * 3_600)))

        // The next launch: nothing is asked of Apple or the platform inside the day.
        let before = rig.server.appAttestRequests
        rig.launch()
        _ = try await rig.getMe()
        #expect(rig.server.appAttestRequests == before && rig.service.count("generateKey") == 2)
        rig.clock.advance(by: .seconds(24 * 3_600 - 60))
        rig.launch()
        _ = try await rig.getMe()
        #expect(rig.server.appAttestRequests == before)

        // After the day it tries again.
        rig.clock.advance(by: .seconds(61))
        rig.launch()
        _ = try await rig.getMe()
        #expect(rig.server.appAttestRequests > before)
    }

    @Test func aPausedAttestationStillRenewsATokenForAnAttestedKey() async throws {
        let rig = AttestRig(storedKey: StoredAppAttestKey(account: "account-a", keyId: "key-old", attested: true))
        rig.defaults.set(try JSONEncoder().encode(AppAttestor.Backoff(
            attestPausedUntil: rig.clock.now().addingTimeInterval(3_600), servedSeen: true)), forKey: AppAttestor.defaultsKey)
        rig.launch()
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.keys) == 0 && rig.service.count("generateKey") == 0)
        #expect(rig.server.appTokens(AttestServer.me) == ["tok-1"])
    }

    @Test func badRequestOnKeysStopsAttestationForADay() async throws {
        let rig = AttestRig()
        rig.server.reply(AttestServer.keys, .refusal(400, requestID: "rid-400"))
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.keys) == 1)
        #expect(near(rig.backoff?.attestPausedUntil, rig.clock.now().addingTimeInterval(24 * 3_600)))
        #expect(rig.server.appTokens(AttestServer.me) == [nil])
    }

    @Test func rateLimitedKeysCarryOnWithoutATokenUntilRetryAfter() async throws {
        let rig = AttestRig()
        rig.server.route(AttestServer.keys) { request, n in
            n == 0 ? .refusal(429, requestID: "rid-429", retryAfter: 120) : .keyCreated(request)
        }
        _ = try await rig.getMe()
        #expect(rig.server.appTokens(AttestServer.me) == [nil])     // the request carried on
        #expect(near(rig.backoff?.attestPausedUntil, rig.clock.now().addingTimeInterval(120)))
        #expect(rig.service.count("generateKey") == 1)

        // Past the in-process backoff but inside Retry-After: no challenge, no key.
        rig.clock.advance(by: .seconds(61))
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.challenge) == 1 && rig.server.count(AttestServer.keys) == 1)
        #expect(rig.server.appTokens(AttestServer.me) == [nil, nil])

        // Retry-After over: the same key is attested and a token follows.
        rig.clock.advance(by: .seconds(60))
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.keys) == 2)
        #expect(rig.service.count("generateKey") == 1)
        #expect(rig.server.appTokens(AttestServer.me) == [nil, nil, "tok-1"])
    }

    @Test func rateLimitedKeysWithoutRetryAfterWaitAnHourAcrossLaunches() async throws {
        let rig = AttestRig()
        rig.server.route(AttestServer.keys) { request, n in n == 0 ? .refusal(429, requestID: "rid-429") : .keyCreated(request) }
        _ = try await rig.getMe()
        #expect(near(rig.backoff?.attestPausedUntil, rig.clock.now().addingTimeInterval(3_600)))
        rig.clock.advance(by: .seconds(3_599))
        rig.launch()
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.keys) == 1)
        rig.clock.advance(by: .seconds(2))
        rig.launch()
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.keys) == 2)
        #expect(rig.server.appTokens(AttestServer.me).last == "tok-1")
    }

    @Test func rateLimitedTokenWaitsRetryAfterAndKeepsTheKey() async throws {
        let rig = AttestRig()
        rig.server.route(AttestServer.token) { _, n in
            n == 0 ? .refusal(429, requestID: "rid-429", retryAfter: 90) : .token("tok-later")
        }
        _ = try await rig.getMe()
        #expect(rig.server.appTokens(AttestServer.me) == [nil])
        #expect(rig.backoff?.attestPausedUntil == nil)              // attesting isn't paused: only this step waits
        rig.clock.advance(by: .seconds(61))
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.token) == 1)
        rig.clock.advance(by: .seconds(30))
        _ = try await rig.getMe()
        #expect(rig.server.count(AttestServer.token) == 2)
        #expect(rig.server.count(AttestServer.keys) == 1 && rig.service.count("generateKey") == 1)
        #expect(rig.server.appTokens(AttestServer.me) == [nil, nil, "tok-later"])
    }
}
