// The three App Attest routes (API.md → Conventions → App Attest, D245): `AppAttestor` calls them through
// `exchange`, so they get the bearer, the 401 refresh-once and request IDs, but never ask for an app token.
import Foundation

extension APIClient {
    /// The routes that mint the app token: no `X-RYFT-App-Token` and no `403 app_attest_required` handling on them
    /// (`exchange`), so the attestor's own requests can't recurse. Open behind the invite gate too.
    static let appAttestRoutes: Set<String> = [
        "POST /v1/app-attest/challenge", "POST /v1/app-attest/keys", "POST /v1/app-attest/token",
    ]

    /// `POST /v1/app-attest/challenge` (no body). Each is one attempt (`singleAttempt`): the fail-fast session, no
    /// `503` or `429` loop; the attestor's backoff decides when to try again.
    func appAttestChallenge() async throws -> AppAttestChallenge {
        try await APIClient.$singleAttempt.withValue(true) {
            try Self.decode(AppAttestChallenge.self,
                            from: try await exchange("POST", path: "/v1/app-attest/challenge", encodedBody: nil))
        }
    }

    /// `POST /v1/app-attest/keys`: `201 AppAttestKey`.
    func postAppAttestKey(_ post: AppAttestKeyPost) async throws -> AppAttestKey {
        try await APIClient.$singleAttempt.withValue(true) {
            try Self.decode(AppAttestKey.self, from: try await exchange("POST", path: "/v1/app-attest/keys", body: post))
        }
    }

    /// `POST /v1/app-attest/token`: `200 AppAttestToken`.
    func postAppAttestToken(_ post: AppAttestTokenPost) async throws -> AppAttestToken {
        try await APIClient.$singleAttempt.withValue(true) {
            try Self.decode(AppAttestToken.self,
                            from: try await exchange("POST", path: "/v1/app-attest/token", body: post))
        }
    }
}
