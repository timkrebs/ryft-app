// What the UI needs to know about requests in flight: the "RYFT is catching
// up" notice while APIClient waits out a 503, the gates the platform reported
// (invite, consent), and the recent failures with their request IDs (Profile →
// Developer, Debug builds).
import Foundation
import Observation
import os

@MainActor
@Observable
final class APIStatus {
    static let shared = APIStatus()

    /// "RYFT is catching up, retrying in 12 s" while a 503 retry is pending.
    private(set) var retryNotice: String?
    /// Newest first, at most `maxFailures`.
    private(set) var failures: [RequestFailure] = []
    /// Gates the platform reported for this account and not yet passed: a `403` with a
    /// code, or `X-RYFT-Gate` on a request it served anyway (warn mode).
    private(set) var gates: Set<APIErrorCode> = []
    /// A `403 invite_required` (not just a warning): every call but onboarding's stops
    /// until the code is redeemed (APIClient).
    private(set) var inviteBlocked = false

    static let maxFailures = 20
    nonisolated static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "api")

    struct RequestFailure: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let method: String
        let path: String
        let status: Int
        /// The error body's `code` as sent (`consent_required`), if any.
        var code: String? = nil
        let requestID: String?
    }

    func waiting(seconds: Int) {
        retryNotice = String(localized: "RYFT is catching up, retrying in \(seconds) s")
    }

    func finishedWaiting() {
        retryNotice = nil
    }

    func record(_ failure: RequestFailure) {
        failures.insert(failure, at: 0)
        if failures.count > Self.maxFailures { failures.removeLast(failures.count - Self.maxFailures) }
    }

    // MARK: gates

    /// A refusal's code (`enforced`) or a warn-mode header.
    func observe(_ codes: Set<APIErrorCode>, enforced: Bool) {
        gates.formUnion(codes)
        if enforced, codes.contains(.inviteRequired) { inviteBlocked = true }
    }

    /// The gate was passed (code redeemed, consent given) or the server no longer reports it.
    func resolved(_ code: APIErrorCode) {
        gates.remove(code)
        if code == .inviteRequired { inviteBlocked = false }
    }

    /// Another account: its gates are its own.
    func resetGates() {
        gates = []
        inviteBlocked = false
    }
}
