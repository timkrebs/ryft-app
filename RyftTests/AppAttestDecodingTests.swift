import Foundation
import Testing
@testable import Ryft

/// API.md → Conventions → App Attest (D245, 2026-11-19): the five shapes and the four codes, from the contract's
/// examples (`Fixtures/app_attest_*.json`) through the app's shared snake_case coder.
@Suite("App Attest mirror")
struct AppAttestDecodingTests {
    private static let keyID = "pKqW2rZ8yH3nT6v+1mX9cF4sD7gJ0eL5uA2oI8w/3kE="

    private func object(_ data: Data) throws -> [String: String] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    @Test func challenge() throws {
        let c = try Fixture.decode(AppAttestChallenge.self, "app_attest_challenge")
        #expect(c.challenge == "q3Jx0mZ9cT1vY8kL2pW5nB7dF4hS6aE0uR3iO9yG1tM")
        #expect(c.expiresAt == DateParsing.rfc3339("2026-11-19T10:05:00Z"))
    }

    @Test func keyPostEncodesAsTheExample() throws {
        let wanted = try object(Fixture.data("app_attest_key_post"))
        let post = AppAttestKeyPost(keyId: Self.keyID, attestation: "o2NmbXRvYXBwbGUtYXBwYXR0ZXN0Z2F0dFN0bXSiY3g1Y4JZA…",
                                    challenge: "q3Jx0mZ9cT1vY8kL2pW5nB7dF4hS6aE0uR3iO9yG1tM")
        #expect(try object(APIClient.jsonEncoder.encode(post)) == wanted)
        #expect(Set(wanted.keys) == ["key_id", "attestation", "challenge"])
    }

    @Test func keyEchoesTheKeyID() throws {
        #expect(try Fixture.decode(AppAttestKey.self, "app_attest_key").keyId == Self.keyID)
    }

    @Test func tokenPostEncodesAsTheExample() throws {
        let wanted = try object(Fixture.data("app_attest_token_post"))
        let post = AppAttestTokenPost(keyId: Self.keyID, challenge: "Zt0bH6wQ1cJ8mV3xR5kP9nY2sL7aD4fG0uE6iT1oW3M",
                                      assertion: "omlzaWduYXR1cmVYRzBFAiEA…")
        #expect(try object(APIClient.jsonEncoder.encode(post)) == wanted)
        #expect(Set(wanted.keys) == ["key_id", "challenge", "assertion"])
    }

    @Test func token() throws {
        let t = try Fixture.decode(AppAttestToken.self, "app_attest_token")
        #expect(t.token == "<opaque, at most 512 ASCII characters>")
        #expect(t.expiresAt == DateParsing.rfc3339("2026-11-19T11:06:12Z"))
        #expect(t.ttlSec == 3600)
    }

    @Test func errorCodesAreKnownAndNoneIsAGate() throws {
        func code(_ raw: String) throws -> APIErrorCode? {
            let json = #"{"error":"x","code":"\#(raw)","request_id":"01a1"}"#
            return try APIClient.jsonDecoder.decode(APIErrorBody.self, from: Data(json.utf8)).code
        }
        #expect(try code("app_attest_required") == .appAttestRequired)
        #expect(try code("app_attest_challenge_invalid") == .appAttestChallengeInvalid)
        #expect(try code("app_attest_invalid") == .appAttestInvalid)
        #expect(try code("app_attest_key_unknown") == .appAttestKeyUnknown)
        for c in [APIErrorCode.appAttestRequired, .appAttestChallengeInvalid, .appAttestInvalid, .appAttestKeyUnknown] {
            #expect(!c.isGate, "\(c.rawValue)")
        }
        // A `403 app_attest_required` is no gate: never the invite or consent screen, never `FailureKind.gate`.
        let refused = APIError.http(403, "app attest required", requestID: "r1", code: .appAttestRequired)
        #expect(refused.gate == nil && FailureKind.of(refused) == .other)
    }
}
