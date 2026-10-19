import Foundation

/// The stages of one sync, each a seam so the coordinator can be tested on the
/// `TestClock` with fakes. `LiveSyncSteps` runs them against HealthKit, the
/// platform and the Repository.
@MainActor
protocol SyncSteps: AnyObject {
    /// Reads new HealthKit records page by page and uploads them; returns `days_touched`.
    func upload() async throws -> [String]
    /// Whether every touched day was rescored at or after `since` (`computed_at`).
    func isScored(_ days: [String], since: Date) async throws -> Bool
    /// Fetches the touched days (and today) regardless of their TTL.
    func refreshDays(_ days: [String]) async throws
    func refreshTrends() async throws
    func refreshInsights() async throws
    /// Nothing new was uploaded: only what's stale is refreshed.
    func refreshStale() async
}

/// Runs syncs as one pipeline with explicit dependencies:
///
///     upload ──▶ awaitScoring(days_touched, ≤ 3 polls) ──▶ refreshDays ──┬─▶ refreshTrends
///                                                                        └─▶ refreshInsights
///
/// - **One in flight.** A trigger while a sync runs queues a single rerun; more
///   triggers join that rerun (coalesced).
/// - **Priorities.** User-initiated work (pull to refresh, app active, back
///   online) runs above background work (BG refresh, HealthKit delivery, silent push).
/// - **Cancellation.** `cancel()` stops the running pipeline (sign-out, app
///   backgrounded); waits are `clock.sleep` and throw `CancellationError`.
/// - **Backoff.** Transient failures (transport, 5xx after `APIClient`'s own
///   retries) retry with exponential backoff (2 s, 4 s); 4xx don't.
actor SyncCoordinator {
    enum Trigger: Equatable, Sendable {
        case userInitiated, appActive, reconnect, healthKit, background
        /// A silent push: refresh these days, no upload.
        case silentPush(days: [String])

        var priority: TaskPriority {
            switch self {
            case .userInitiated, .appActive, .reconnect: return .userInitiated
            case .healthKit, .background, .silentPush: return .utility
            }
        }
    }

    struct Outcome: Equatable, Sendable {
        var touched: [String] = []
        var polls = 0
        var attempts = 0
        var cancelled = false
        var error: String?
    }

    /// Polls for scoring after an upload; waits double each time (3 s, 6 s, 12 s).
    static let maxPolls = 3
    static let firstPollDelay: Duration = .seconds(3)
    static let maxUploadAttempts = 3
    static let firstBackoff: Duration = .seconds(2)

    private let steps: SyncSteps
    private let clock: AppClock
    private var running: Task<Outcome, Never>?
    private var queued: Task<Outcome, Never>?
    private var queuedTrigger: Trigger?

    init(steps: SyncSteps, clock: AppClock) {
        self.steps = steps
        self.clock = clock
    }

    var isRunning: Bool { running != nil }

    /// Runs (or joins) a sync for `trigger` and returns how it ended.
    @discardableResult
    func run(_ trigger: Trigger) async -> Outcome {
        guard let current = running else { return await start(trigger).value }
        // Busy: one rerun after the current one, shared by every trigger meanwhile.
        if let queued {
            queuedTrigger = merge(queuedTrigger, trigger)
            return await queued.value
        }
        queuedTrigger = trigger
        let next = Task(priority: trigger.priority) { [weak self] () -> Outcome in
            _ = await current.value
            guard let self else { return Outcome(cancelled: true) }
            return await self.startQueued()
        }
        queued = next
        return await next.value
    }

    /// Stops the running pipeline and drops a queued rerun.
    func cancel() {
        running?.cancel()
        queued?.cancel()
        queued = nil
        queuedTrigger = nil
    }

    private func startQueued() async -> Outcome {
        let trigger = queuedTrigger ?? .background
        queued = nil
        queuedTrigger = nil
        guard !Task.isCancelled else { return Outcome(cancelled: true) }
        return await start(trigger).value
    }

    private func start(_ trigger: Trigger) -> Task<Outcome, Never> {
        let task = Task(priority: trigger.priority) { [steps, clock] in
            await Self.pipeline(trigger, steps: steps, clock: clock)
        }
        running = task
        Task { [weak self] in
            _ = await task.value
            await self?.finished(task)
        }
        return task
    }

    private func finished(_ task: Task<Outcome, Never>) {
        if running == task { running = nil }
    }

    /// A silent push's days join whatever else is waiting; any upload trigger wins over a push.
    private func merge(_ a: Trigger?, _ b: Trigger) -> Trigger {
        switch (a, b) {
        case (.silentPush(let x)?, .silentPush(let y)): return .silentPush(days: Array(Set(x + y)).sorted())
        case (.silentPush?, _): return b
        case (let a?, _): return a.priority >= b.priority ? a : b
        case (nil, _): return b
        }
    }

    // MARK: the pipeline

    private static func pipeline(_ trigger: Trigger, steps: SyncSteps, clock: AppClock) async -> Outcome {
        var outcome = Outcome()
        do {
            let touched: [String]
            if case .silentPush(let days) = trigger {
                touched = days
            } else {
                let started = clock.now()
                (touched, outcome.attempts) = try await uploadWithBackoff(steps, clock)
                outcome.touched = touched
                guard !touched.isEmpty else {
                    try Task.checkCancellation()
                    await steps.refreshStale()
                    return outcome
                }
                outcome.polls = try await awaitScoring(touched, since: started, steps, clock)
            }
            outcome.touched = touched
            try Task.checkCancellation()
            try await steps.refreshDays(touched)
            // Trends and insights depend on the days, not on each other.
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await steps.refreshTrends() }
                group.addTask { try await steps.refreshInsights() }
                try await group.waitForAll()
            }
        } catch is CancellationError {
            outcome.cancelled = true
        } catch {
            outcome.error = error.localizedDescription
        }
        return outcome
    }

    /// The upload, retried on transient failures with exponential backoff.
    private static func uploadWithBackoff(_ steps: SyncSteps, _ clock: AppClock) async throws -> ([String], Int) {
        var delay = firstBackoff
        for attempt in 1...maxUploadAttempts {
            try Task.checkCancellation()
            do {
                return (try await steps.upload(), attempt)
            } catch let error where isTransient(error) && attempt < maxUploadAttempts {
                try await clock.sleep(for: delay)
                delay *= 2
            }
        }
        throw CancellationError() // unreachable: the last attempt returns or throws
    }

    /// Waits until scoring caught up with the upload, at most `maxPolls` times.
    /// Gives up quietly: the days are refreshed either way.
    private static func awaitScoring(_ days: [String], since: Date, _ steps: SyncSteps, _ clock: AppClock) async throws -> Int {
        var delay = firstPollDelay
        for poll in 1...maxPolls {
            try await clock.sleep(for: delay)
            if (try? await steps.isScored(days, since: since)) == true { return poll }
            delay *= 2
        }
        return maxPolls
    }

    /// Worth retrying: no answer, or a server error that `APIClient` gave up on. Not 4xx.
    static func isTransient(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .transport: return true
        case .http(let code, _, _): return code >= 500
        case .notConfigured, .signedOut: return false
        }
    }
}

/// The stages against the real app: SyncService uploads, the Repository refreshes.
@MainActor
final class LiveSyncSteps: SyncSteps {
    private let state: AppState
    private let sync: SyncService

    init(state: AppState, sync: SyncService) {
        self.state = state
        self.sync = sync
    }

    func upload() async throws -> [String] {
        guard !state.isDemo, state.env.auth.isSignedIn, state.env.settings.isConfigured else { return [] }
        return try await sync.upload()
    }

    func isScored(_ days: [String], since: Date) async throws -> Bool {
        guard let first = days.min().flatMap(DayFormat.date(from:)),
              let last = days.max().flatMap(DayFormat.date(from:)) else { return true }
        let scores = try await state.env.api.days(from: first, to: last)
        state.repository.store(scores: scores)
        let scored = Dictionary(scores.map { ($0.day, $0.computedAt) }, uniquingKeysWith: { a, _ in a })
        return days.allSatisfy { day in (scored[day] ?? nil).map { $0 >= since } ?? false }
    }

    func refreshDays(_ days: [String]) async throws {
        try await state.refreshDays(days)
    }

    func refreshTrends() async throws {
        try await state.repository.refreshTrend(.readiness, .week, force: true)
        // Other series refetch when Insights shows them.
        state.repository.markTrendsStale()
    }

    func refreshInsights() async throws {
        try await state.repository.refreshInsights(force: true)
    }

    func refreshStale() async {
        await state.refresh()
    }
}
