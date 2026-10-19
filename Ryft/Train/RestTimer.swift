import Foundation

/// Rest timer between sets. Time is kept as an end date, so it survives the app
/// going to the background (and the Live Activity counts down to the same date).
///
///     idle ──start──▶ running ──time up / −15 s past zero──▶ finished ──dismiss──▶ idle
///                       │  ▲ ±15 s                                │
///                       └──┴── skip ──▶ idle ◀──── start ─────────┘ (restarts)
struct RestTimer: Equatable {
    enum Phase: Equatable {
        case idle
        case running(endsAt: Date, total: TimeInterval)
        case finished
    }

    static let step: TimeInterval = 15
    /// Longest rest the ±15 s buttons can reach.
    static let maxRest: TimeInterval = 15 * 60

    private(set) var phase: Phase = .idle

    init() {}

    /// Restores a timer saved with the session.
    init(endsAt: Date?, total: TimeInterval, now: Date) {
        if let endsAt, endsAt > now, total > 0 {
            phase = .running(endsAt: endsAt, total: total)
        }
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var endsAt: Date? {
        if case .running(let end, _) = phase { return end }
        return nil
    }

    var total: TimeInterval {
        if case .running(_, let total) = phase { return total }
        return 0
    }

    func remaining(at now: Date) -> TimeInterval {
        guard case .running(let end, _) = phase else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    /// 1 → 0 while counting down.
    func fraction(at now: Date) -> Double {
        guard case .running(_, let total) = phase, total > 0 else { return 0 }
        return remaining(at: now) / total
    }

    /// After a set is checked off. A non-positive rest leaves the timer idle.
    mutating func start(seconds: Int, now: Date) {
        guard seconds > 0 else {
            phase = .idle
            return
        }
        let total = min(TimeInterval(seconds), Self.maxRest)
        phase = .running(endsAt: now.addingTimeInterval(total), total: total)
    }

    /// ±15 s. Returns `true` if this ran the timer out (−15 s with less left).
    @discardableResult
    mutating func adjust(by delta: TimeInterval, now: Date) -> Bool {
        guard case .running(let end, let total) = phase else { return false }
        let remaining = min(end.timeIntervalSince(now) + delta, Self.maxRest)
        guard remaining > 0 else {
            phase = .finished
            return true
        }
        // The ring's full length grows with +15 s so the arc never overflows.
        phase = .running(endsAt: now.addingTimeInterval(remaining), total: max(total, remaining))
        return false
    }

    mutating func skip() { phase = .idle }

    mutating func dismiss() {
        if phase == .finished { phase = .idle }
    }

    /// Call on every display tick. Returns `true` exactly once, when time is up.
    @discardableResult
    mutating func tick(now: Date) -> Bool {
        guard case .running(let end, _) = phase, end <= now else { return false }
        phase = .finished
        return true
    }
}
