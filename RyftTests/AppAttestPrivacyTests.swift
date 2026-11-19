import Foundation
import Testing
@testable import Ryft

/// AC10: the key ID, the token, the challenge and the attestation or assertion appear in no `APIStatus` record, no
/// error text (`localizedDescription`, `diagnosticDetails`, the error's own description) and nothing persisted in the
/// backoff. (Log lines can't be read back in a unit test; `AppAttestor.note` is reviewed instead.)
@Suite("App Attest: no secret leaves the attestor (AC10)")
@MainActor
struct AppAttestPrivacyTests {
    enum Secret {
        static let keyID = "pKqW2rZ8yH3nT6v+1mX9cF4sD7gJ0eL5uA2oI8w/3kE="
        static let challengePrefix = "SECRETCHALLENGE-"
        static let tokenPrefix = "SECRETTOKEN-"
        static let attestation = Data("ATTESTATION-SECRET-bytes".utf8)
        static let assertion = Data("ASSERTION-SECRET-bytes".utf8)

        static let challenges = (0..<12).map { "\(challengePrefix)\($0)" }
        /// Every form a value can take in a text.
        static let needles = [keyID, challengePrefix, tokenPrefix, attestation.base64EncodedString(),
                              assertion.base64EncodedString(), "ATTESTATION-SECRET", "ASSERTION-SECRET"]
    }

    enum Scenario: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case success, refusedTwice, keysInvalid, keysRateLimited, tokenKeyUnknown, challengeInvalid, notServed, serverError
        var testDescription: String { rawValue }
    }

    private func rig() -> AttestRig {
        let rig = AttestRig()
        rig.server.serveAppAttest(challenges: Secret.challenges, tokenFor: { _, n in "\(Secret.tokenPrefix)\(n)" })
        rig.service.keyID = Secret.keyID
        rig.service.attestation = Secret.attestation
        rig.service.assertion = Secret.assertion
        return rig
    }

    /// Plays the scenario, returning what the app's own requests threw.
    private func play(_ scenario: Scenario, on rig: AttestRig) async -> [Error] {
        var errors: [Error] = []
        func request() async {
            do { _ = try await rig.getMe() } catch { errors.append(error) }
        }
        switch scenario {
        case .success:
            await request()
            await request()
        case .refusedTwice:
            await request()
            rig.clock.advance(by: .seconds(61))
            rig.server.route(AttestServer.me) { _, _ in .refusal(403, code: "app_attest_required", requestID: "rid-403") }
            await request()
        case .keysInvalid:
            rig.server.reply(AttestServer.keys, .refusal(422, code: "app_attest_invalid", requestID: "rid-422"))
            await request()
        case .keysRateLimited:
            rig.server.reply(AttestServer.keys, .refusal(429, requestID: "rid-429", retryAfter: 120))
            await request()
        case .tokenKeyUnknown:
            rig.server.reply(AttestServer.token, .refusal(404, code: "app_attest_key_unknown", requestID: "rid-404"))
            await request()
        case .challengeInvalid:
            rig.server.reply(AttestServer.token, .refusal(422, code: "app_attest_challenge_invalid", requestID: "rid-422c"))
            await request()
        case .notServed:
            rig.server.reply(AttestServer.challenge, .json(404, #"{"error":"not found"}"#))
            await request()
        case .serverError:
            rig.server.reply(AttestServer.challenge, .refusal(503, requestID: "rid-503"))
            await request()
        }
        _ = await rig.renewalEnded()
        return errors
    }

    /// Everything the app keeps or shows about the requests.
    private func texts(_ rig: AttestRig, errors: [Error]) -> [String] {
        var texts: [String] = []
        for record in rig.status.requests + rig.status.failures {
            texts.append(String(describing: record))
            texts.append(String(reflecting: record))
            texts += [record.method, record.path, record.code ?? "", record.requestID ?? "", record.transport ?? ""]
        }
        for error in errors {
            texts += [error.localizedDescription, error.diagnosticDetails ?? "", String(describing: error),
                      String(reflecting: error)]
        }
        if let stored = rig.defaults.data(forKey: AppAttestor.defaultsKey) {
            texts.append(String(decoding: stored, as: UTF8.self))
        }
        texts.append(rig.status.retryNotice ?? "")
        return texts
    }

    @Test(arguments: Scenario.allCases)
    func noSecretIsInAnyRecordOrErrorText(_ scenario: Scenario) async throws {
        let rig = rig()
        let errors = await play(scenario, on: rig)
        let shown = texts(rig, errors: errors)
        #expect(!shown.isEmpty)
        for text in shown {
            for needle in Secret.needles {
                #expect(!text.contains(needle), "\(scenario): \(needle) is in: \(text)")
            }
        }
        // The scan isn't vacuous: the values were in play (the platform got them).
        if scenario != .notServed && scenario != .serverError {
            let keyPosts = rig.server.requests(AttestServer.keys)
            #expect(keyPosts.first?.field("key_id") == Secret.keyID)
            #expect(keyPosts.first?.field("attestation") == Secret.attestation.base64EncodedString())
            #expect(keyPosts.first?.field("challenge")?.hasPrefix(Secret.challengePrefix) == true)
        }
        if scenario == .success {
            #expect(rig.server.appTokens(AttestServer.me).first??.hasPrefix(Secret.tokenPrefix) == true)
            #expect(rig.server.requests(AttestServer.token).first?.field("assertion") == Secret.assertion.base64EncodedString())
        }
    }

    @Test func theRefusalTheUserSeesNamesTheCodeAndTheRequestIDOnly() async throws {
        let rig = rig()
        let errors = await play(.refusedTwice, on: rig)
        let error = try #require(errors.first as? APIError)
        #expect(error.status == 403 && error.code == .appAttestRequired && error.requestID == "rid-403")
        #expect(error.localizedDescription == String(localized: "RYFT couldn't verify this app on this iPhone. Try again later."))
        #expect(error.diagnosticDetails?.contains("app_attest_required") == true)
        #expect(error.diagnosticDetails?.contains("rid-403") == true)
    }

    @Test func theBackoffRecordHoldsDatesAndOneFlagOnly() async throws {
        let rig = rig()
        rig.server.reply(AttestServer.keys, .refusal(429, requestID: "rid-429", retryAfter: 120))
        _ = await play(.keysRateLimited, on: rig)
        let stored = try #require(rig.defaults.data(forKey: AppAttestor.defaultsKey))
        let object = try #require(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        #expect(Set(object.keys).isSubset(of: ["notServedUntil", "attestPausedUntil", "servedSeen"]))
    }
}
