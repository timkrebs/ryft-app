import Foundation

/// The stages of one sync, each a seam so the coordinator can be tested on the
/// `TestClock` with fakes. `LiveSyncSteps` runs them against HealthKit, the
/// platform and the Repository.
@MainActor
protocol SyncSteps: AnyObject {
    /// Reads new HealthKit records page by page and uploads them; returns `days_touched`.
    func upload() async throws -> [String]
    /// The last upload stopped early on purpose (the first score's window went first,
    /// or the app went to the background); another run follows.
    var hasBacklog: Bool { get }
    /// The last upload found HealthKit locked (protected data): it resumes after the unlock.
    var isWaitingForUnlock: Bool { get }
    /// Reading or uploading right now.
    var isUploading: Bool { get }
    /// Ends the upload after the page in flight (the app went to the background).
    func stopAfterCurrentPage() async
    /// Whether every touched day was rescored at or after `since` (`computed_at`).
    func isScored(_ days: [String], since: Date) async throws -> Bool
    /// Fetches the touched days (and today) regardless of their TTL.
    func refreshDays(_ days: [String]) async throws
    func refreshTrends() async throws
    func refreshInsights() async throws
    /// Nothing new was uploaded: only what's stale is refreshed.
    func refreshStale() async
    /// The pipeline moved on (`SyncMachine`): awaiting scores, refreshing, done, failed, idle (cancelled).
    func report(_ phase: SyncPhase)
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
/// - **Cancellation.** `cancel()` stops the running pipeline (sign-out, or a
///   background task's time running out); waits are `clock.sleep` and throw
///   `CancellationError`.
/// - **Background.** Going to the background doesn't cancel: `windDown()` lets the
///   page in flight finish (anchor committed) and ends the upload there. While in the
///   background a run uploads and skips the scoring wait (the silent push refreshes),
///   requests use the background session (`APIClient.runsInBackground`), and a
///   backlog is left to `BGProcessingTask` instead of running on.
/// - **HealthKit delivery.** `run(_:afterUpload:)` calls the delivery's completion right
///   after the upload step, not after scoring waits and refreshes.
/// - **Backoff.** Transient failures (transport, 5xx after `APIClient`'s own
///   retries) retry with exponential backoff (2 s, 4 s); 4xx don't.
actor SyncCoordinator {
    enum Trigger: Equatable, Sendable {
        case userInitiated, appActive, reconnect, healthKit, background
        /// The rest of an upload that stopped early (the first score came first).
        case backlog
        /// `BGProcessingTask`: the backfill, with minutes to spare.
        case processing
        /// A silent push: refresh these days, no upload.
        case silentPush(days: [String])

        var priority: TaskPriority {
            switch self {
            case .userInitiated, .appActive, .reconnect: return .userInitiated
            case .healthKit, .background, .silentPush, .backlog, .processing: return .utility
            }
        }

        /// Woken by the system, not by the user: background networking.
        var isBackground: Bool {
            switch self {
            case .healthKit, .background, .silentPush, .processing: return true
            case .userInitiated, .appActive, .reconnect, .backlog: return false
            }
        }

        /// The user is looking: the app is in the foreground again.
        var isForeground: Bool { self == .userInitiated || self == .appActive || self == .reconnect }
    }

    struct Outcome: Equatable, Sendable {
        var touched: [String] = []
        var polls = 0
        var attempts = 0
        var cancelled = false
        var error: String?
        /// The upload left a backlog; a `.backlog` run follows.
        var backlog = false
        /// HealthKit was locked; nothing is lost, the rest follows the unlock.
        var waitingForUnlock = false
    }

    /// Polls for scoring after an upload; waits double each time (3 s, 6 s, 12 s).
    static let maxPolls = 3
    static let firstPollDelay: Duration = .seconds(3)
    static let maxUploadAttempts = 3
    static let firstBackoff: Duration = .seconds(2)

    private let steps: SyncSteps
    private let clock: AppClock
    private var running: Task<Outcome, Never>?
    private var runningID: UUID?
    private var queued: Task<Outcome, Never>?
    private var queuedTrigger: Trigger?
    /// HealthKit deliveries waiting for the queued rerun's upload.
    private var queuedAfterUpload: [@Sendable () -> Void] = []
    /// The app is in the background (`windDown()`), until a foreground trigger.
    private(set) var inBackground = false

    init(steps: SyncSteps, clock: AppClock) {
        self.steps = steps
        self.clock = clock
    }

    var isRunning: Bool { running != nil }
    /// A rerun waits behind the running sync.
    var hasQueuedRun: Bool { queued != nil }

    /// Runs (or joins) a sync for `trigger` and returns how it ended. `afterUpload` (a
    /// HealthKit delivery's completion) is called as soon as the upload step is over,
    /// however it ended; a joined rerun calls it after its own upload.
    @discardableResult
    func run(_ trigger: Trigger, afterUpload: (@Sendable () -> Void)? = nil) async -> Outcome {
        if trigger.isForeground { inBackground = false }
        guard let current = running else { return await start(trigger, afterUpload: afterUpload.map { [$0] } ?? []).value }
        // Busy: one rerun after the current one, shared by every trigger meanwhile.
        if let afterUpload { queuedAfterUpload.append(afterUpload) }
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

    /// Stops the running pipeline and drops a queued rerun (its deliveries are completed).
    func cancel() {
        running?.cancel()
        dropQueued()
    }

    /// The app went to the background: the page being uploaded finishes and the upload
    /// stops there (a backlog stays); a scoring wait or refresh is abandoned. Returns when
    /// the run has ended, so the caller can end its background task.
    func windDown() async {
        inBackground = true
        dropQueued()
        guard let running else { return }
        if await steps.isUploading {
            await steps.stopAfterCurrentPage()
        } else {
            running.cancel()
        }
        _ = await running.value
    }

    private func dropQueued() {
        queued?.cancel()
        queued = nil
        queuedTrigger = nil
        let waiting = queuedAfterUpload
        queuedAfterUpload = []
        waiting.forEach { $0() }
    }

    private func startQueued() async -> Outcome {
        let trigger = queuedTrigger ?? .background
        let afterUpload = queuedAfterUpload
        queued = nil
        queuedTrigger = nil
        queuedAfterUpload = []
        guard !Task.isCancelled else {
            afterUpload.forEach { $0() }
            return Outcome(cancelled: true)
        }
        return await start(trigger, afterUpload: afterUpload).value
    }

    private func start(_ trigger: Trigger, afterUpload: [@Sendable () -> Void]) -> Task<Outcome, Never> {
        let id = UUID()
        let background = trigger.isBackground || inBackground
        // The run clears itself before its outcome is returned, so `isRunning` is
        // false as soon as anyone has the outcome.
        let task = Task(priority: trigger.priority) { [weak self, steps, clock] in
            let outcome = await APIClient.$runsInBackground.withValue(background) {
                // Asked after the upload: a foreground run can end up in the background.
                await Self.pipeline(trigger, steps: steps, clock: clock,
                                    inBackground: { [weak self] in
                                        if background { return true }
                                        return await self?.inBackground ?? true
                                    },
                                    afterUpload: afterUpload)
            }
            // Only a foreground run continues by itself; in the background the backfill task loops.
            await self?.finished(id, continuing: outcome.backlog && !outcome.cancelled && outcome.error == nil
                                 && !background)
            return outcome
        }
        running = task
        runningID = id
        return task
    }

    private func finished(_ id: UUID, continuing: Bool) {
        guard runningID == id else { return }
        running = nil
        runningID = nil
        // The first score is on screen; the rest of the upload follows (unless a queued
        // rerun is about to upload anyway). In the background `BGProcessingTask` takes it.
        if continuing, queued == nil, !inBackground {
            Task(priority: Trigger.backlog.priority) { [weak self] in await self?.run(.backlog) }
        }
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

    private static func pipeline(_ trigger: Trigger, steps: SyncSteps, clock: AppClock,
                                 inBackground: @Sendable () async -> Bool,
                                 afterUpload: [@Sendable () -> Void]) async -> Outcome {
        var outcome = Outcome()
        // A HealthKit delivery's completion follows the upload step, however it ended.
        var uploadReported = false
        func uploadDone() {
            guard !uploadReported else { return }
            uploadReported = true
            afterUpload.forEach { $0() }
        }
        defer { uploadDone() }
        do {
            let touched: [String]
            if case .silentPush(let days) = trigger {
                uploadDone()
                touched = days
            } else {
                let started = clock.now()
                (touched, outcome.attempts) = try await uploadWithBackoff(steps, clock)
                uploadDone()
                outcome.touched = touched
                outcome.backlog = await steps.hasBacklog
                outcome.waitingForUnlock = await steps.isWaitingForUnlock
                if await inBackground() {
                    // The system's time is short: the silent push refreshes once scoring is done.
                    try Task.checkCancellation()
                    await steps.report(.done)
                    return outcome
                }
                guard !touched.isEmpty else {
                    try Task.checkCancellation()
                    await steps.report(.refreshing)
                    await steps.refreshStale()
                    await steps.report(.done)
                    return outcome
                }
                await steps.report(.awaitingScores)
                outcome.polls = try await awaitScoring(touched, since: started, steps, clock)
            }
            outcome.touched = touched
            try Task.checkCancellation()
            await steps.report(.refreshing)
            try await steps.refreshDays(touched)
            // Trends and insights depend on the days, not on each other.
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await steps.refreshTrends() }
                group.addTask { try await steps.refreshInsights() }
                try await group.waitForAll()
            }
            await steps.report(.done)
        } catch is CancellationError {
            outcome.cancelled = true
            await steps.report(.idle)
        } catch {
            outcome.error = error.localizedDescription
            await steps.report(.failed)
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
        case .http(let code, _, _, _): return code >= 500
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

    var hasBacklog: Bool { sync.hasBacklog }
    var isWaitingForUnlock: Bool { sync.waitingForUnlock }
    var isUploading: Bool { sync.isSyncing }
    func stopAfterCurrentPage() async { await sync.stopAfterCurrentPage() }

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

    func report(_ phase: SyncPhase) {
        sync.advance(to: phase)
    }
}
