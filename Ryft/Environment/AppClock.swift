import Foundation

/// Time behind a seam, so tests decide when "now" is and when a wait ends.
/// Not called `Clock`: that name would shadow Swift's own `Clock` protocol in this module.
protocol AppClock: AnyObject, Sendable {
    func now() -> Date
    func sleep(for duration: Duration) async throws
}

/// The real clock.
final class SystemClock: AppClock {
    func now() -> Date { Date() }
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

extension Duration {
    var timeInterval: TimeInterval {
        let c = components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1e18
    }
}

/// Tests: time moves only on `advance(by:)`. A `sleep` returns once the clock has
/// passed its deadline, or throws `CancellationError` when its task is cancelled.
final class TestClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var sleepers: [UUID: (deadline: Date, continuation: CheckedContinuation<Void, Error>)] = [:]

    init(now: Date = Date(timeIntervalSince1970: 1_792_400_000)) {   // 2026-10-19
        current = now
    }

    func now() -> Date { lock.withLock { current } }

    /// Waits that haven't ended yet.
    var pendingSleeps: Int { lock.withLock { sleepers.count } }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                let resumeNow: Bool = lock.withLock {
                    if Task.isCancelled { return true }
                    let deadline = current.addingTimeInterval(duration.timeInterval)
                    if deadline <= current { return true }
                    sleepers[id] = (deadline, c)
                    return false
                }
                if resumeNow {
                    if Task.isCancelled { c.resume(throwing: CancellationError()) } else { c.resume() }
                }
            }
        } onCancel: {
            let c = lock.withLock { sleepers.removeValue(forKey: id)?.continuation }
            c?.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and ends every wait that is now due.
    func advance(by duration: Duration) {
        let due: [CheckedContinuation<Void, Error>] = lock.withLock {
            current = current.addingTimeInterval(duration.timeInterval)
            let ready = sleepers.filter { $0.value.deadline <= current }
            for id in ready.keys { sleepers.removeValue(forKey: id) }
            return ready.values.map(\.continuation)
        }
        for c in due { c.resume() }
    }

    func set(_ date: Date) {
        lock.withLock { current = date }
    }
}
