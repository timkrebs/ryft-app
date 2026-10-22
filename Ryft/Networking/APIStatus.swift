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
    /// Every request's outcome, served or not, newest first, at most `maxFailures` (Sync details).
    private(set) var requests: [RequestFailure] = []
    /// Gates the platform reported for this account and not yet passed: a `403` with a
    /// code, or `X-RYFT-Gate` on a request it served anyway (warn mode).
    private(set) var gates: Set<APIErrorCode> = []
    /// A `403 invite_required` (not just a warning): every call but onboarding's stops
    /// until the code is redeemed (APIClient).
    private(set) var inviteBlocked = false
    /// Requests cancelled since launch (a pull let go, a screen closed). Not failures: they take
    /// none of the `maxFailures` slots and show as one count in Copy diagnostics.
    private(set) var cancelledCount = 0

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
        /// How long the round trip took (nil: not measured).
        var durationMs: Int? = nil
        /// No response: the `URLError` code's name ("timedOut"), or "cancelled". `status` is 0 then.
        var transport: String? = nil
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
        served(failure)
    }

    func cancelled() {
        cancelledCount += 1
    }

    /// A request the platform answered (failures go through `record` too).
    func served(_ request: RequestFailure) {
        requests.insert(request, at: 0)
        if requests.count > Self.maxFailures { requests.removeLast(requests.count - Self.maxFailures) }
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

// MARK: - request budget

/// Admits scheduled reads (`ReadScheduler`) so a refresh never bursts against the platform's
/// limits (API.md → Conventions: per user 60 then 10/s, per IP 20/s at the edge): at most
/// `maxInFlight` at once, and at most `maxStarts` starts in any `window` (a sliding log, so
/// "no burst over 5" holds exactly; a token bucket of 5 would allow 10 in the first second).
/// Waiters go high priority first (today, `GET /v1/me/sync`), then first come, first served.
/// Waits run on the `AppClock`, so tests drive them with `TestClock`.
actor RequestBudget {
    enum Priority: Int, Comparable, Sendable {
        case high, normal
        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    private struct Ticket: Equatable {
        let id: UUID
        let priority: Priority
        let order: Int
    }

    private let clock: AppClock
    let maxInFlight: Int
    let maxStarts: Int
    let window: Duration
    private(set) var inFlight = 0
    /// Start times inside the window, oldest first.
    private var starts: [Date] = []
    /// Waiting, in admission order.
    private var queue: [Ticket] = []
    private var parked: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var nextOrder = 0
    /// After a `429` from either limiter (per user, or the edge's per IP): no new start before this,
    /// for any resource, pull and Try again included.
    private(set) var notBefore: Date?

    /// The longest a `429`'s `Retry-After` holds every start back.
    static let maxHoldBack: Duration = .seconds(30)

    init(clock: AppClock, maxInFlight: Int = 3, maxStarts: Int = 5, window: Duration = .seconds(1)) {
        self.clock = clock
        self.maxInFlight = maxInFlight
        self.maxStarts = maxStarts
        self.window = window
    }

    /// Requests waiting for a slot (tests).
    var waiting: Int { queue.count }

    /// The rate-limit hold has `seconds` left, longer than the read may wait (`maxHold`).
    struct HeldBack: Error, Equatable {
        let seconds: Int
    }

    /// Returns once this read may start; throws `CancellationError` if its task is cancelled while
    /// waiting (it leaves the queue), or `HeldBack` when the rate-limit hold has longer left than
    /// `maxHold` (the read fails at once instead of waiting under "Updating…"). Every successful
    /// `acquire` needs one `release`.
    func acquire(_ priority: Priority, maxHold: Duration? = nil) async throws {
        let ticket = Ticket(id: UUID(), priority: priority, order: nextOrder)
        nextOrder += 1
        let at = queue.firstIndex { $0.priority > priority } ?? queue.endIndex
        queue.insert(ticket, at: at)
        defer {
            queue.removeAll { $0 == ticket }
            wakeAll()
        }
        while true {
            try Task.checkCancellation()
            // Re-checked after every suspension: another acquire or release ran meanwhile.
            guard queue.first == ticket, inFlight < maxInFlight else {
                try await park(ticket.id)
                continue
            }
            let now = clock.now()
            if let notBefore, now < notBefore {
                let wait = notBefore.timeIntervalSince(now)
                if let maxHold, wait > maxHold.timeInterval { throw HeldBack(seconds: Int(wait.rounded(.up))) }
                try await clock.sleep(for: .milliseconds(max(1, Int((wait * 1000).rounded(.up)))))
                continue
            }
            starts.removeAll { now.timeIntervalSince($0) >= window.timeInterval }
            if starts.count < maxStarts {
                inFlight += 1
                starts.append(now)
                return
            }
            // The window is full: wait until its oldest relevant start is a window old.
            let oldest = starts[starts.count - maxStarts]
            let wait = oldest.addingTimeInterval(window.timeInterval).timeIntervalSince(now)
            try await clock.sleep(for: .milliseconds(max(1, Int((wait * 1000).rounded(.up)))))
        }
    }

    /// A try ended: its slot goes back. After a `429` (`holdBack` seconds) every new start is held
    /// back first, in the same step, so no read parked behind this one slips through.
    func release(holdBack seconds: Int? = nil) {
        if let seconds { holdBack(seconds: seconds) }
        inFlight = max(0, inFlight - 1)
        wakeAll()
    }

    /// The platform said `429`: hold every new start back for its `Retry-After` (a `429` without
    /// one counts as 1 s), at most `maxHoldBack`. A later, longer hold extends it.
    func holdBack(seconds: Int) {
        let hold = min(Duration.seconds(max(1, seconds)), Self.maxHoldBack)
        let until = clock.now().addingTimeInterval(hold.timeInterval)
        if notBefore.map({ until > $0 }) ?? true { notBefore = until }
    }

    private func park(_ id: UUID) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { c.resume(throwing: CancellationError()) } else { parked[id] = c }
            }
        } onCancel: {
            Task { await self.unpark(id) }
        }
    }

    private func unpark(_ id: UUID) {
        parked.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    /// Something changed (a slot, the head of the queue): every parked waiter checks again.
    private func wakeAll() {
        let waiting = parked
        parked = [:]
        waiting.values.forEach { $0.resume() }
    }
}

// MARK: - redaction

/// A request path as Sync details, Copy diagnostics and the log may show it: no query or fragment
/// (`?wake=06:30`, date ranges), and UUID segments (install, session, plan, exercise) as `{id}`.
/// Day segments (`/v1/days/2026-10-21`) and names stay: they say which day failed, nothing more.
func redactedPath(_ path: String) -> String {
    let bare = path.prefix { $0 != "?" && $0 != "#" }
    return bare.split(separator: "/", omittingEmptySubsequences: false)
        .map { UUID(uuidString: String($0)) == nil ? String($0) : "{id}" }
        .joined(separator: "/")
}
