// What the UI needs to know about requests in flight: the "RYFT is catching
// up" notice while APIClient waits out a 503, and the recent failures with
// their request IDs (Profile → Developer, Debug builds).
import Foundation
import os

@MainActor
final class APIStatus: ObservableObject {
    static let shared = APIStatus()

    /// "RYFT is catching up, retrying in 12 s" while a 503 retry is pending.
    @Published private(set) var retryNotice: String?
    /// Newest first, at most `maxFailures`.
    @Published private(set) var failures: [RequestFailure] = []

    static let maxFailures = 20
    nonisolated static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "api")

    struct RequestFailure: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let method: String
        let path: String
        let status: Int
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
}
