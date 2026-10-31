import Foundation
import os

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
    /// How long scoring has recently taken (`SyncResponse.scoring.expected_within_sec` of the
    /// last upload); `nil` before an upload said.
    var expectedScoringSeconds: Int? { get }
    /// `GET /v1/me/sync`: the days scoring hasn't finished, today's state, any gate.
    func syncStatus() async throws -> SyncStatus
    /// The same, asked for by the person (pull to refresh): it doesn't wait out a `Retry-After`.
    func syncStatus(userInitiated: Bool) async throws -> SyncStatus
    /// Fetches the touched days (and today) regardless of their TTL.
    func refreshDays(_ days: [String]) async throws
    func refreshTrends() async throws
    func refreshInsights() async throws
    /// Nothing new was uploaded: only what's stale is refreshed.
    func refreshStale() async
    /// The pipeline moved on (`SyncMachine`): awaiting scores, refreshing, done, failed, idle (cancelled).
    func report(_ phase: SyncPhase)
    /// The platform accepted a write that touches `days` (an upload's `days_touched`, a `daysChanged`): Today and
    /// the widget show them as being scored until the platform's word (`ScoringWord`). In the background too.
    func awaiting(_ days: [String])
    /// A silent push named `days`: scored, whatever an earlier status read said. Before the refresh.
    func scored(_ days: [String])
    /// A run that sent nothing may ask `GET /v1/me/sync` for days the platform still scores (signed in, configured,
    /// not demo data).
    var readsScoringStatus: Bool { get }
    /// Days this phone's word still holds as pending (`SyncService.scoringLedger`): no status read late enough has
    /// answered them yet.
    var awaitedDays: [String] { get }
    /// Days the last upload's accepted pages touched, also when it failed or was cancelled afterwards; none once the
    /// account is gone.
    var touchedSoFar: [String] { get }
    /// The latest `GET /v1/me/sync` answer and when it arrived, on this phone's clock.
    var lastStatus: (status: SyncStatus, readAt: Date)? { get }
}

extension SyncSteps {
    /// Steps without a user-initiated path (test fakes) ask the ordinary way.
    func syncStatus(userInitiated: Bool) async throws -> SyncStatus { try await syncStatus() }
    /// Fakes that don't record the scoring words.
    func awaiting(_ days: [String]) {}
    func scored(_ days: [String]) {}
    /// Fakes that don't say: a run that sent nothing asks nothing.
    var readsScoringStatus: Bool { false }
    var awaitedDays: [String] { [] }
    var touchedSoFar: [String] { [] }
    var lastStatus: (status: SyncStatus, readAt: Date)? { nil }
}

/// Runs syncs as one pipeline with explicit dependencies:
///
///     upload ──▶ awaitScoring(days_touched) ──▶ refreshDays ──┬─▶ refreshTrends
///                                                             └─▶ refreshInsights
///
/// - **Scoring, from the server.** After an upload the pipeline waits the platform's
///   own estimate (`expected_within_sec`), then asks `GET /v1/me/sync` until
///   `pending_days` no longer holds the touched days (doubling waits up to a minute, five
///   minutes at most). The silent push for a scored day ends the wait at once and joins
///   the run instead of queuing another refresh. A gate ends it too. The first ask is never sooner
///   than the platform's status cache allows (`ScoringWord.statusCacheTime`), so no answer from
///   before the write ends a wait. A foreground run that sent nothing refreshes what's stale, asks
///   once whether the platform still scores days (a background upload, another device, a relaunch)
///   and waits for those the same way, except days an earlier wait already gave up on.
/// - **Being scored, one owner.** The pipeline tells `SyncSteps.awaiting` which days a write touched
///   and `SyncSteps.scored` which days a push named; Today and the widget read both (`ScoringWord`).
/// - **One in flight.** A trigger while a sync runs queues a single rerun; more
///   triggers join that rerun (coalesced).
/// - **Priorities.** User-initiated work (pull to refresh, app active, back
///   online) runs above background work (BG refresh, HealthKit delivery, silent push).
/// - **Cancellation.** `cancel()` stops the running pipeline (sign-out, or a
///   background task's time running out); waits are `clock.sleep` and throw
///   `CancellationError`.
/// - **Background.** Going to the background doesn't cancel: `windDown()` lets the
///   page in flight finish (anchor committed) and ends the upload there. While the app
///   is in the background (its lifecycle, not the trigger) a run uploads and skips the
///   scoring wait (the silent push refreshes), requests use the background session
///   (`APIClient.runsInBackground`), and a backlog goes to `BGProcessingTask`.
/// - **HealthKit delivery.** `run(_:afterUpload:)` calls the delivery's completion right
///   after the upload step, not after scoring waits and refreshes.
/// - **Backoff.** Transient upload failures (transport, 5xx after `APIClient`'s own
///   retries) retry with exponential backoff (2 s, 4 s); 4xx don't. Reads after the upload
///   go through `ReadScheduler` (its own retries, per resource) and never fail the run.
actor SyncCoordinator {
    enum Trigger: Equatable, Sendable {
        case userInitiated, appActive, reconnect, healthKit, background
        /// The rest of an upload that stopped early (the first score came first).
        case backlog
        /// `BGProcessingTask`: the backfill, with minutes to spare.
        case processing
        /// A silent push: refresh these days, no upload.
        case silentPush(days: [String])
        /// The platform took a change to these days that didn't come from HealthKit (an activity or a night the
        /// user added, edited or deleted; a training import): no upload, the scoring wait, then the refresh.
        /// Coalesces with a push into one wait for all the days; behind an upload trigger its days ride along.
        case daysChanged(days: [String])

        var priority: TaskPriority {
            switch self {
            case .userInitiated, .appActive, .reconnect: return .userInitiated
            case .healthKit, .background, .silentPush, .daysChanged, .backlog, .processing: return .utility
            }
        }

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

    /// API.md: `expected_within_sec` is 30 until the platform has measured scoring.
    static let defaultExpectedScoring = 30
    static let minimumPollDelay: Duration = .seconds(2)
    static let maximumPollDelay: Duration = .seconds(60)
    /// After this long the days are refreshed anyway (their scores may still be pending).
    static let maximumScoringWait: Duration = .seconds(300)
    static let maxUploadAttempts = 3
    /// A silent push's refresh (the days, then trends and insights) gives up after this: iOS allows
    /// about 30 s. The reads it started finish on their own; their callers stop waiting at once.
    static let silentPushRefreshDeadline: Duration = .seconds(20)
    static let firstBackoff: Duration = .seconds(2)

    private let steps: SyncSteps
    private let clock: AppClock
    /// The silent push's "scored" for a pipeline that waits for it.
    private let scoring = ScoringSignal()
    private var running: Task<Outcome, Never>?
    private var runningID: UUID?
    private var queued: Task<Outcome, Never>?
    private var queuedTrigger: Trigger?
    /// `.daysChanged` days that joined the queued rerun: awaited and refreshed even when an upload trigger won the
    /// merge (`merge` keeps one trigger).
    private var queuedDays: Set<String> = []
    /// HealthKit deliveries waiting for the queued rerun's upload.
    private var queuedAfterUpload: [@Sendable () -> Void] = []
    /// Where the app is, from its lifecycle (RyftApp: the scene phase, and the launch state
    /// for a launch straight into the background), not from what triggered a run: HealthKit
    /// also delivers while the user looks at Today.
    private(set) var inBackground: Bool
    /// A run in the background left a backlog: `BGProcessingTask` takes it (RyftApp
    /// schedules the backfill task).
    private let backlogInBackground: (@MainActor @Sendable () -> Void)?

    init(steps: SyncSteps, clock: AppClock, inBackground: Bool = false,
         backlogInBackground: (@MainActor @Sendable () -> Void)? = nil) {
        self.steps = steps
        self.clock = clock
        self.inBackground = inBackground
        self.backlogInBackground = backlogInBackground
    }

    /// The app became active.
    func enterForeground() {
        inBackground = false
    }

    var isRunning: Bool { running != nil }
    /// A rerun waits behind the running sync.
    var hasQueuedRun: Bool { queued != nil }
    /// What that rerun will run, the triggers merged so far.
    var queuedRunTrigger: Trigger? { queuedTrigger }

    /// Runs (or joins) a sync for `trigger` and returns how it ended. `afterUpload` (a
    /// HealthKit delivery's completion) is called as soon as the upload step is over,
    /// however it ended; a joined rerun calls it after its own upload.
    @discardableResult
    func run(_ trigger: Trigger, afterUpload: (@Sendable () -> Void)? = nil) async -> Outcome {
        if case .silentPush(let days) = trigger {
            // The platform's word that these days are scored, before any refresh: the waiting run's, or its own.
            await steps.scored(days)
            // The push a waiting pipeline was waiting for: it refreshes those days now; nothing to queue.
            if let current = running, await scoring.signal(Set(days)) { return await current.value }
        }
        guard let current = running else { return await start(trigger, afterUpload: afterUpload.map { [$0] } ?? []).value }
        // Busy: one rerun after the current one, shared by every trigger meanwhile.
        if let afterUpload { queuedAfterUpload.append(afterUpload) }
        if case .daysChanged(let days) = trigger { queuedDays.formUnion(days) }
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

    /// Runs `trigger` only when no sync is running or queued (checked and started in one step); nil otherwise. For a
    /// release edge (`ScreenModels.gateChanged`): a sync already on its way reads the gate itself, and a rerun after it
    /// would be an extra pass.
    @discardableResult
    func runIfIdle(_ trigger: Trigger) async -> Outcome? {
        guard running == nil, queued == nil else { return nil }
        return await run(trigger)
    }

    /// `GET /v1/me/sync` now, outside a run (pull to refresh's phase 2): through the read pipeline,
    /// so a scoring poll in flight is joined, with the step's effects (the screens' state, gates,
    /// an operator's re-sync request). A failure is recorded there, not here.
    func refreshStatus() async {
        _ = try? await steps.syncStatus(userInitiated: true)
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
        queuedDays = []
        let waiting = queuedAfterUpload
        queuedAfterUpload = []
        waiting.forEach { $0() }
    }

    private func startQueued() async -> Outcome {
        // Cancelled (dropQueued completed its deliveries): the queue may already hold a
        // replacement, which isn't this task's to take.
        guard !Task.isCancelled else { return Outcome(cancelled: true) }
        let trigger = queuedTrigger ?? .background
        let afterUpload = queuedAfterUpload
        let days = queuedDays.sorted()
        queued = nil
        queuedTrigger = nil
        queuedAfterUpload = []
        queuedDays = []
        return await start(trigger, afterUpload: afterUpload, alsoAwaiting: days).value
    }

    /// `alsoAwaiting`: `.daysChanged` days merged into an upload trigger's run.
    private func start(_ trigger: Trigger, afterUpload: [@Sendable () -> Void],
                       alsoAwaiting extraDays: [String] = []) -> Task<Outcome, Never> {
        let id = UUID()
        // A BG task only ever runs in the background; everything else follows the app.
        let background = inBackground || trigger == .processing
        // The run clears itself before its outcome is returned, so `isRunning` is
        // false as soon as anyone has the outcome.
        let task = Task(priority: trigger.priority) { [weak self, steps, clock, scoring] in
            let outcome = await APIClient.$runsInBackground.withValue(background) {
                // Asked after the upload: a foreground run can end up in the background.
                await Self.pipeline(trigger, steps: steps, clock: clock, scoring: scoring,
                                    inBackground: { [weak self] in
                                        if background { return true }
                                        return await self?.inBackground ?? true
                                    },
                                    afterUpload: afterUpload, alsoAwaiting: extraDays)
            }
            await self?.finished(id, backlog: outcome.backlog && !outcome.cancelled && outcome.error == nil,
                                 trigger: trigger, background: background)
            return outcome
        }
        running = task
        runningID = id
        return task
    }

    private func finished(_ id: UUID, backlog: Bool, trigger: Trigger, background: Bool) {
        guard runningID == id else { return }
        running = nil
        runningID = nil
        guard backlog else { return }
        // In the background the backfill task takes the rest (it loops by itself when it's
        // the one running).
        if background || inBackground {
            if trigger != .processing, let backlogInBackground { Task { @MainActor in backlogInBackground() } }
            return
        }
        // The first score is on screen; the rest of the upload follows.
        if queued != nil {
            // The queued rerun uploads it, even if all that was queued is a push's refresh.
            queuedTrigger = merge(queuedTrigger, .backlog)
        } else {
            // Started (and registered) now, so a cancel() right after finds it.
            _ = start(.backlog, afterUpload: [])
        }
    }

    /// A silent push's days join whatever else is waiting; with a `.daysChanged` they're one wait for all the
    /// days. Any upload trigger wins over both (a `.daysChanged`'s days ride along in `queuedDays`).
    private func merge(_ a: Trigger?, _ b: Trigger) -> Trigger {
        switch (a, b) {
        case (.silentPush(let x)?, .silentPush(let y)): return .silentPush(days: Array(Set(x + y)).sorted())
        case (.silentPush(let x)?, .daysChanged(let y)), (.daysChanged(let x)?, .silentPush(let y)),
             (.daysChanged(let x)?, .daysChanged(let y)):
            return .daysChanged(days: Array(Set(x + y)).sorted())
        case (.silentPush?, _), (.daysChanged?, _): return b
        case (let a?, _): return a.priority >= b.priority ? a : b
        case (nil, _): return b
        }
    }

    // MARK: the pipeline

    /// `body`, or `CancellationError` once `limit` passed on the clock (the body is cancelled then;
    /// its scheduled reads let their callers go at once).
    private static func within(_ limit: Duration, _ clock: AppClock,
                               _ body: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await body()
                return true
            }
            group.addTask {
                try await clock.sleep(for: limit)
                return false
            }
            let finished = try await group.next() ?? false
            group.cancelAll()
            if !finished { throw CancellationError() }
        }
    }

    // Static, so it holds no actor state: every seam comes in as an argument.
    // swiftlint:disable:next function_parameter_count
    private static func pipeline(_ trigger: Trigger, steps: SyncSteps, clock: AppClock, scoring: ScoringSignal,
                                 inBackground: @Sendable () async -> Bool,
                                 afterUpload: [@Sendable () -> Void], alsoAwaiting extraDays: [String]) async -> Outcome {
        var outcome = Outcome()
        // A HealthKit delivery's completion follows the upload step, however it ended.
        var uploadReported = false
        func uploadDone() {
            guard !uploadReported else { return }
            uploadReported = true
            afterUpload.forEach { $0() }
        }
        defer { uploadDone() }
        // An upload that ended early (failed, cancelled) after the platform accepted pages: those days are being
        // scored all the same (`touchedSoFar` is empty once the account is gone).
        var wordOwed = false
        var acceptedBefore = Set<String>() // by upload attempts a transient failure ended
        func sayTouchedSoFar() async {
            guard wordOwed else { return }
            wordOwed = false
            let days = acceptedBefore.union(await steps.touchedSoFar).sorted()
            guard !days.isEmpty else { return }
            await scoring.written(days)
            await steps.awaiting(days)
        }
        do {
            let touched: [String]
            switch trigger {
            case .silentPush(let days):
                uploadDone()
                touched = days
            case .daysChanged(let days):
                uploadDone()
                touched = days
                outcome.touched = days
                try Task.checkCancellation()
                await scoring.written(days)
                await steps.awaiting(days)
                if await inBackground() {
                    // As after an upload in the background: the silent push refreshes once scoring is done.
                    try Task.checkCancellation()
                    await steps.report(.done)
                    return outcome
                }
                await steps.report(.awaitingScores)
                outcome.polls = try await awaitScoring(days, steps, clock, scoring)
            default:
                let uploaded: [String]
                wordOwed = true
                (uploaded, outcome.attempts) = try await uploadWithBackoff(steps, clock, accepted: &acceptedBefore)
                uploadDone()
                // Days a `.daysChanged` brought into this run are awaited and refreshed with the uploaded ones.
                let written = uploaded + Set(extraDays).subtracting(uploaded).sorted()
                outcome.touched = written
                // Only an upload that sent something leaves a backlog to continue (offline,
                // gated or demo uploads send nothing).
                outcome.backlog = uploaded.isEmpty ? false : await steps.hasBacklog
                outcome.waitingForUnlock = await steps.isWaitingForUnlock
                try Task.checkCancellation()
                wordOwed = false
                if !written.isEmpty {
                    await scoring.written(written)
                    await steps.awaiting(written)
                }
                if await inBackground() {
                    // The system's time is short: the silent push refreshes once scoring is done.
                    try Task.checkCancellation()
                    await steps.report(.done)
                    return outcome
                }
                if written.isEmpty {
                    // Nothing sent: the days the platform still scores (uploaded in the background, by another device,
                    // before a relaunch) are waited for like our own; what's stale doesn't wait behind them.
                    let listed = try await stillScoring(steps, clock, scoring)
                    guard !listed.days.isEmpty else {
                        await steps.report(.refreshing)
                        await steps.refreshStale()
                        await steps.report(.done)
                        return outcome
                    }
                    touched = listed.days
                    async let stale: Void = steps.refreshStale()
                    await steps.report(.awaitingScores)
                    outcome.polls = try await awaitScoring(touched, steps, clock, scoring, expected: listed.expected)
                    await stale
                } else {
                    touched = written
                    await steps.report(.awaitingScores)
                    outcome.polls = try await awaitScoring(touched, steps, clock, scoring)
                }
            }
            outcome.touched = touched
            try Task.checkCancellation()
            await steps.report(.refreshing)
            let refresh = Signposts.sync.beginInterval("refresh", id: Signposts.sync.makeSignpostID())
            defer { Signposts.sync.endInterval("refresh", refresh) }
            let refreshing: @Sendable () async throws -> Void = {
                try await steps.refreshDays(touched)
                // Trends and insights depend on the days, not on each other.
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await steps.refreshTrends() }
                    group.addTask { try await steps.refreshInsights() }
                    try await group.waitForAll()
                }
            }
            if case .silentPush = trigger {
                try await within(silentPushRefreshDeadline, clock, refreshing)
            } else {
                try await refreshing()
            }
            await steps.report(.done)
        } catch is CancellationError {
            await sayTouchedSoFar()
            outcome.cancelled = true
            await steps.report(.idle)
        } catch {
            await sayTouchedSoFar()
            outcome.error = error.localizedDescription
            await steps.report(.failed)
        }
        return outcome
    }

    /// The upload, retried on transient failures with exponential backoff. The days an attempt touched before it
    /// failed (`accepted`) are the run's too: the retry starts after the pages the platform accepted.
    private static func uploadWithBackoff(_ steps: SyncSteps, _ clock: AppClock,
                                          accepted: inout Set<String>) async throws -> ([String], Int) {
        var delay = firstBackoff
        for attempt in 1...maxUploadAttempts {
            try Task.checkCancellation()
            do {
                let touched = try await steps.upload()
                return (touched + accepted.subtracting(touched).sorted(), attempt)
            } catch let error where isTransient(error) && attempt < maxUploadAttempts {
                accepted.formUnion(await steps.touchedSoFar)
                try await clock.sleep(for: delay)
                delay *= 2
            }
        }
        throw CancellationError() // unreachable: the last attempt returns or throws
    }

    /// For a foreground run that sent nothing: the days `GET /v1/me/sync` lists as pending plus those this phone's
    /// word still holds (a background upload under the cache time ago), less the days an earlier wait gave up on, and
    /// that answer's `expected_within_sec`. A status read under the cache time ago is used as it is (the platform
    /// would answer from its cache). None for an account that can't read it, when the read failed, or behind a gate the
    /// platform reports (nothing is scored behind it; a local hold isn't one: the platform scores what it has).
    private static func stillScoring(_ steps: SyncSteps, _ clock: AppClock,
                                     _ scoring: ScoringSignal) async throws -> (days: [String], expected: Int?) {
        guard await steps.readsScoringStatus else {
            try Task.checkCancellation()
            return ([], nil)
        }
        let status: SyncStatus?
        if let last = await steps.lastStatus,
           clock.now().timeIntervalSince(last.readAt) < ScoringWord.statusCacheTime {
            status = last.status
        } else {
            let signpost = Signposts.sync.beginInterval("pending-check", id: Signposts.sync.makeSignpostID())
            status = try? await steps.syncStatus()
            Signposts.sync.endInterval("pending-check", signpost, "\(status?.pendingDays.count ?? -1) pending")
        }
        try Task.checkCancellation()
        guard let status, status.gate == nil else { return ([], nil) }
        // After the read: the words it answered are gone.
        let listed = Set(status.pendingDays).union(await steps.awaitedDays)
        let days = listed.subtracting(await scoring.waitedOut).sorted()
        return (days, status.expectedWithinSec)
    }

    /// Until scoring has finished the touched days, by the platform's word: a silent push
    /// for one of them, or `GET /v1/me/sync` no longer listing them as pending. The first
    /// wait is the platform's estimate; after each wait the status is asked while the next
    /// wait runs (doubling up to a minute), and an answer that says "scored" (or names a
    /// gate, behind which nothing is scored) ends that wait at once. Five minutes on the
    /// clock in all; an ask still running then is cancelled. Gives up quietly: the days
    /// are refreshed either way. Returns how often it asked.
    private static func awaitScoring(_ days: [String], _ steps: SyncSteps, _ clock: AppClock,
                                     _ scoring: ScoringSignal, expected override: Int? = nil) async throws -> Int {
        await scoring.begin(Set(days))
        let signpost = Signposts.sync.beginInterval("score-wait", id: Signposts.sync.makeSignpostID(),
                                                    "\(days.count) days")
        var polls = 0
        defer { Signposts.sync.endInterval("score-wait", signpost, "\(polls) polls") }
        var expected = override
        if expected == nil { expected = await steps.expectedScoringSeconds }
        // Never sooner than the platform's status cache allows: an earlier answer may be from before the write.
        let begun = clock.now()
        var delay = max(minimumPollDelay, .seconds(expected ?? defaultExpectedScoring),
                        .seconds(Int(ScoringWord.statusCacheTime)))
        let deadline = begun.addingTimeInterval(maximumScoringWait.timeInterval)
        var cutOff = false
        var asking: Task<Void, Never>?
        defer { asking?.cancel() }
        do {
            while true {
                let left = deadline.timeIntervalSince(clock.now())
                guard left > 0 else {
                    cutOff = true
                    break
                }
                if try await scoring.wait(timeout: min(delay, .seconds(left)), clock: clock) { break }
                guard deadline > clock.now() else {
                    cutOff = true
                    break
                }
                polls += 1
                asking?.cancel()
                let asked = clock.now()
                asking = Task {
                    // A failed ask is one more wait, not the end.
                    guard let status = try? await steps.syncStatus() else { return }
                    let gated = status.gate != nil
                    // Asked inside the cache time after the write: only a gate counts (the timing above keeps it out).
                    guard gated || asked.timeIntervalSince(begun) >= ScoringWord.statusCacheTime else { return }
                    await scoring.answer(pending: Set(status.pendingDays), gated: gated)
                }
                delay = min(delay * 2, maximumPollDelay)
            }
        } catch {
            await scoring.end(cutOff: false)
            throw error
        }
        await scoring.end(cutOff: cutOff)
        return polls
    }

    /// Worth retrying: no answer, or a server error that `APIClient` gave up on. Not 4xx.
    static func isTransient(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .transport: return true
        case .http(let code, _, _, _, _): return code >= 500
        case .notConfigured, .signedOut: return false
        }
    }
}

/// "Scoring finished these days", for a pipeline waiting on them (`awaitScoring`): from the
/// silent push, or from a `GET /v1/me/sync` answer. A word that comes between two waits
/// is kept, so the next wait returns at once.
actor ScoringSignal {
    /// The days the pipeline waits for; `nil` when none does.
    private var awaited: Set<String>?
    /// Days a wait gave up on at the cut-off while the platform still listed them: a run that sent nothing doesn't
    /// wait for them again, until a write touches them.
    private(set) var waitedOut: Set<String> = []
    private var done = false
    private var waiting: CheckedContinuation<Bool, Never>?
    /// The wait that's open; a parked half that arrives after it closed returns at once.
    private var open: UUID?

    func begin(_ days: Set<String>) {
        awaited = days
        done = false
    }

    /// `cutOff`: the wait ran out of time; the days still awaited are waited out.
    func end(cutOff: Bool) {
        if cutOff, let awaited { waitedOut.formUnion(awaited) }
        awaited = nil
        done = false
    }

    /// A write touched `days`: they're worth a wait again.
    func written(_ days: [String]) {
        waitedOut.subtract(days)
    }

    /// `true` when the days were scored (or are known to be) before `timeout` ended.
    func wait(timeout: Duration, clock: AppClock) async throws -> Bool {
        if done { return true }
        let id = UUID()
        open = id
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await clock.sleep(for: timeout)
                return false
            }
            group.addTask { await self.park(id) }
            let first: Bool
            do {
                first = try await group.next() ?? false
            } catch {
                // Cancelled (sign-out, background): the parked half must end too.
                group.cancelAll()
                close(id)
                throw error
            }
            group.cancelAll()
            close(id)
            return first
        }
    }

    /// A push arrived for `days`: `true` when a pipeline waits for one of them.
    func signal(_ days: Set<String>) -> Bool {
        guard let awaited, !awaited.isDisjoint(with: days) else { return false }
        finish()
        return true
    }

    /// `GET /v1/me/sync` answered: the awaited days still pending, and whether a gate stands.
    func answer(pending: Set<String>, gated: Bool) {
        guard let current = awaited else { return }
        let left = current.intersection(pending)
        awaited = left
        if gated || left.isEmpty { finish() }
    }

    private func finish() {
        done = true
        waiting?.resume(returning: true)
        waiting = nil
    }

    private func park(_ id: UUID) async -> Bool {
        await withCheckedContinuation { c in
            if open == id, !done { waiting = c } else { c.resume(returning: done) }
        }
    }

    private func close(_ id: UUID) {
        guard open == id else { return }
        open = nil
        waiting?.resume(returning: false)
        waiting = nil
    }
}

/// The stages against the real app: SyncService uploads, the Repository refreshes.
@MainActor
final class LiveSyncSteps: SyncSteps {
    private let state: AppState
    private let sync: SyncService
    private let apiStatus: APIStatus

    init(state: AppState, sync: SyncService, apiStatus: APIStatus? = nil) {
        self.state = state
        self.sync = sync
        self.apiStatus = apiStatus ?? .shared
        // The widget reads the one ledger, and is republished when it changes.
        let repository = state.repository
        repository.scoringLedger = { [weak sync] in sync?.scoringLedger ?? [:] }
        sync.ledgerChanged = { [weak repository] in repository?.publishWidget() }
    }

    func upload() async throws -> [String] {
        guard !state.isDemo, state.env.auth.isSignedIn, state.env.settings.isConfigured else { return [] }
        return try await sync.upload()
    }

    var hasBacklog: Bool { sync.hasBacklog }
    var isWaitingForUnlock: Bool { sync.waitingForUnlock }
    var isUploading: Bool { sync.isSyncing }
    func stopAfterCurrentPage() async { await sync.stopAfterCurrentPage() }

    var expectedScoringSeconds: Int? { sync.lastScoring?.expectedWithinSec }

    func syncStatus() async throws -> SyncStatus {
        try await syncStatus(userInitiated: false)
    }

    /// `GET /v1/me/sync`, kept for the screens (Today's pending and scored states). A gate
    /// goes to onboarding; an operator's re-sync request to the next upload. Scheduled
    /// (`ReadKey(.syncStatus)`): a pull's ask joins a poll in flight, and the other way round.
    /// The effects run inside the flight, so they happen even if this caller stops waiting.
    func syncStatus(userInitiated: Bool) async throws -> SyncStatus {
        let env = state.env, state = state, apiStatus = apiStatus, sync = sync
        let status = try await env.reads.run(ReadKey(.syncStatus), userInitiated: userInitiated,
                                             storeAsked: { (status: SyncStatus, asked: Date) in
            state.syncStatus = status
            if let gate = status.gate { apiStatus.observe([gate], enforced: false) }
            // When the flight was asked for, not when this caller joined it: the ledger's "requested after".
            sync.receive(status, requestedAt: asked)
        }) { try await env.api.syncStatus() }
        guard let status else { throw ReadScheduler.NotSent() }
        return status
    }

    func refreshDays(_ days: [String]) async throws {
        try await state.refreshDays(days)
    }

    /// After scores landed: newer than now, or nothing. A failed read is recorded per resource, never thrown.
    func refreshTrends() async throws {
        let since = state.env.clock.now()
        do {
            try await state.repository.refreshTrend(.readiness, .week, mode: .changed(since: since))
        } catch is CancellationError {
            throw CancellationError()
        } catch {}
        // Other series refetch when Insights shows them.
        state.repository.markTrendsStale()
    }

    func refreshInsights() async throws {
        let since = state.env.clock.now()
        do {
            try await state.repository.refreshInsights(mode: .changed(since: since))
        } catch is CancellationError {
            throw CancellationError()
        } catch {}
    }

    func refreshStale() async {
        await state.refresh()
    }

    func report(_ phase: SyncPhase) {
        sync.advance(to: phase)
    }

    /// Signed out meanwhile (a sign-out races the pipeline's cancel): nobody's word.
    func awaiting(_ days: [String]) {
        guard state.env.auth.isSignedIn else { return }
        sync.awaiting(days)
    }

    func scored(_ days: [String]) {
        sync.scored(days)
    }

    var readsScoringStatus: Bool {
        !state.isDemo && state.env.auth.isSignedIn && state.env.settings.isConfigured
    }

    var awaitedDays: [String] {
        sync.scoringLedger.filter { $0.value.kind == .pending }.keys.sorted()
    }

    var touchedSoFar: [String] { sync.lastDaysTouched }

    var lastStatus: (status: SyncStatus, readAt: Date)? {
        guard let status = state.syncStatus, let read = sync.statusReadAt else { return nil }
        return (status, read)
    }
}
