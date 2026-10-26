// Sends what the user added, edited or deleted on this iPhone to the platform (design.md §4.1): activities
// (`PUT`/`DELETE /v1/activities/{id}`) and manual sleep (`PUT`/`DELETE /v1/sleep/manual/{day}`).
//
//   save / edit ──▶ localRevision += 1 ──▶ flush ──▶ PUT (the whole document as of that revision)
//                                                      2xx ──▶ confirmedRevision = the revision sent
//                                                      edited meanwhile ──▶ one more PUT
//   delete ──▶ never sent: gone at once · else tombstone ──▶ DELETE (2xx or 404 ──▶ gone)
//   transport · 5xx · 408 · 429 · 401 ──▶ backoff 30 s · 2 min · 10 min · 1 h (jitter, Retry-After)
//   403 + code ──▶ gated · 404 on PUT, or no contract yet ──▶ not available yet · other 4xx ──▶ failed, kept
import Foundation
import Observation
import UIKit
import os

/// The upload queue for own activities and nights. The queue is the rows themselves: a row needs uploading while
/// `localRevision > confirmedRevision` or while it's a tombstone (`ActivityStore.unconfirmed()`), so state lives in
/// one place and survives relaunches. The uploader adds what only it knows: in flight, offline, retrying, gated,
/// not available yet.
///
/// - **One request at a time:** activities in the order they were created, then nights by day.
/// - **Idempotent:** a `PUT` is keyed by the app's id (a night by its day), so a retry after a timeout never makes a
///   second one; an edit made while a `PUT` was out is sent with one more.
/// - **Never lost:** nothing is deleted before the platform confirmed it, except a delete of a row that was never
///   sent, and the account wipe. A refusal is a state (`failed`), shown with its status and request ID.
/// - **Never another account's row:** it reads only through `ActivityStore` (every fetch filtered by the signed-in
///   account), and every answer is dropped unless the generation (an account counter, the account, the Demo data
///   switch and the store's wipe epoch) is still the one the request started under. So a demo row never goes
///   through the live client, and an answer for A never confirms anything for B.
/// - **Before the contract** (`ActivitiesAPI.publishesActivities == false`) nothing is sent: rows wait as "not
///   available yet".
@MainActor
@Observable
final class ActivityUploader {
    /// After 1, 2, 3, then any more transient failures in a row: 30 s, 2 min, 10 min, 1 h (the cap).
    static let backoff: [Duration] = [.seconds(30), .seconds(120), .seconds(600), .seconds(3_600)]
    /// Up to this share of the step is added at random, so phones don't retry in step.
    static let jitter = 0.2
    /// Transient failures in a row before the row shows "failed" (with Retry). Attempts go on at the backoff's pace.
    static let failedAfter = 3
    /// "Send first" before a sign-out waits at most this long (design.md §8.4).
    static let sendFirstLimit: Duration = .seconds(10)

    /// One thing to send.
    enum Item: Hashable, Sendable {
        case activity(UUID)
        /// A night, by its wake day (`yyyy-MM-dd`).
        case sleep(String)
    }

    /// Whose rows a replay sends, and through which client: every answer is checked against it. (The same idea as
    /// `AccountBinding` in #47, plus the counter and the store's epoch.)
    struct Generation: Equatable {
        let count: Int
        let account: String?
        let demo: Bool
        let store: Int
    }

    // MARK: follow-ups (the app connects them: `connect(repository:coordinator:)`)

    /// The platform confirmed an activity's `PUT`: its answer (the read model stores it without route or heart-rate
    /// samples) and the days whose scores change.
    @ObservationIgnored var onConfirmed: (@MainActor (SportActivity, _ days: [String]) -> Void)?
    /// The platform confirmed an activity's `DELETE` (or no longer had it): out of the read model; its day rescored.
    @ObservationIgnored var onRemoved: (@MainActor (_ id: UUID, _ days: [String]) -> Void)?
    /// The platform confirmed a night's `PUT` or `DELETE`: that day is rescored.
    @ObservationIgnored var onSleepConfirmed: (@MainActor (_ day: String) -> Void)?
    /// Jitter source (tests: `{ $0.lowerBound }`).
    @ObservationIgnored var random: (ClosedRange<Double>) -> Double = { .random(in: $0) }

    // MARK: state

    /// What's being sent right now.
    private(set) var inFlight: Item?
    /// When the next automatic attempt is due after a transient failure; nil when none is waiting.
    private(set) var retryAt: Date?
    /// Transient failures in a row, per item (in memory: a relaunch starts over).
    private var transientFailures: [Item: Int] = [:]
    /// The platform doesn't take uploads yet (a `404` on `PUT`): nothing is sent until the app is active again.
    private var notAvailable = false
    /// A gate (invite, consent) refused the last request: tried again on the next trigger.
    private var gated = false
    /// The last transient failure had no answer at all: a reconnect retries at once.
    private var lostConnection = false

    @ObservationIgnored private weak var env: AppEnvironment?
    @ObservationIgnored private let store: ActivityStore
    @ObservationIgnored private var accountCount = 0
    /// The replay in flight. It's the uploader's, not its caller's: only `accountChanged()` and a background task's
    /// expiry cancel it.
    @ObservationIgnored private var replay: Task<Void, Never>?
    @ObservationIgnored private var replayID: UUID?
    @ObservationIgnored private var flushAgain = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    init(env: AppEnvironment, store: ActivityStore) {
        self.env = env
        self.store = store
        env.connectivityMonitor.onChange { [weak self] online in
            guard online, let self else { return }
            if self.lostConnection { self.retryAt = nil }
            Task { await self.flush() }
        }
    }

    var generation: Generation {
        Generation(count: accountCount, account: store.account, demo: env?.isDemo ?? false,
                   store: (env?.persistence as? TrainStore)?.epoch ?? 0)
    }

    /// Activities and nights the platform hasn't confirmed yet (edits, new rows, deletes) for the account the store
    /// reads as.
    var pendingCount: Int { store.unconfirmed().count + store.unconfirmedSleeps().count }

    // MARK: triggers

    /// A save or an edit (the store bumped the revision): the queue runs.
    func saved(_ id: UUID) {
        transientFailures[.activity(id)] = nil
        Task { await flush() }
    }

    /// Delete: a row the platform can't have (never sent, or every attempt refused) goes at once; otherwise it
    /// stays as a tombstone until the `DELETE` is confirmed.
    func deleted(_ id: UUID) {
        guard let row = store.snapshot(id: id) else { return }
        transientFailures[.activity(id)] = nil
        guard mayBeOnPlatform(.activity(id), confirmed: row.confirmedRevision, lastAttempt: row.lastAttempt) else {
            store.remove(id)
            return
        }
        // A delete is a new request: the refusal of an edit no longer applies.
        store.recordFailure(id, nil)
        store.tombstone(id)
        Task { await flush() }
    }

    /// Add sleep or its edit (`ActivityStore.saveSleep`): the queue runs.
    func sleepSaved(day: String) {
        transientFailures[.sleep(day)] = nil
        Task { await flush() }
    }

    /// Delete a night, like `deleted(_:)`.
    func sleepDeleted(day: String) {
        guard let night = store.manualSleep(onDay: day) else { return }
        transientFailures[.sleep(day)] = nil
        guard mayBeOnPlatform(.sleep(day), confirmed: night.confirmedRevision, lastAttempt: night.lastAttempt) else {
            store.removeSleep(day: day)
            return
        }
        store.recordSleepFailure(day: day, nil)
        store.tombstoneSleep(day: day)
        Task { await flush() }
    }

    /// The app became active: "not available yet" is asked again, and the queue runs.
    func appBecameActive() async {
        notAvailable = false
        await flush()
    }

    /// Retry on a failed row: its refusal is forgotten and it's sent now, whatever the backoff says.
    func retry(_ id: UUID) async {
        store.recordFailure(id, nil)
        transientFailures[.activity(id)] = nil
        await flush(userInitiated: true)
    }

    /// Retry on a failed night.
    func retrySleep(day: String) async {
        store.recordSleepFailure(day: day, nil)
        transientFailures[.sleep(day)] = nil
        await flush(userInitiated: true)
    }

    /// Signed out, another account, or the Demo data switch: the replay and the retry stop, answers still in flight
    /// are dropped (`generation`), and nothing of the previous account's state shows.
    func accountChanged() {
        accountCount += 1
        replay?.cancel()
        replay = nil
        replayID = nil
        flushAgain = false
        retryTask?.cancel()
        retryTask = nil
        inFlight = nil
        retryAt = nil
        transientFailures = [:]
        notAvailable = false
        gated = false
        lostConnection = false
    }

    // MARK: replay

    /// Sends the queue until it's empty or something stops it (offline, a backoff, a gate, no contract). A replay
    /// already running goes round once more for this caller, who waits for it. `userInitiated` (Retry, Send first)
    /// doesn't wait out a backoff.
    func flush(userInitiated: Bool = false) async {
        guard let replay = startReplay(userInitiated: userInitiated) else { return }
        await replay.value
    }

    /// The same, waiting at most `limit` (Send first before a sign-out); the replay goes on after it. Returns how
    /// many activities and nights are still unconfirmed.
    @discardableResult
    func flush(upTo limit: Duration, userInitiated: Bool = true) async -> Int {
        if let replay = startReplay(userInitiated: userInitiated), let clock = env?.clock {
            let (done, finish) = AsyncStream<Void>.makeStream()
            Task {
                await replay.value
                finish.finish()
            }
            // Iterating the stream stops on cancellation (`Task.value` wouldn't), so the limit can end the wait.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in done {} }
                group.addTask { try? await clock.sleep(for: limit) }
                await group.next()
                group.cancelAll()
            }
        }
        return pendingCount
    }

    /// The app went to the background: the request in flight finishes inside a background task, which ends when
    /// the replay does. If the system's time runs out first, the replay is cancelled (the row stays queued; a
    /// cancelled request is never a refusal). Nil when nothing is running.
    @discardableResult
    func finishInBackground(app: BackgroundTaskRunning) -> Task<Void, Never>? {
        guard let replay else { return nil }
        let token = UploadBackgroundTask(app: app)
        token.begin { [weak self] in self?.replay?.cancel() }
        return Task {
            await replay.value
            token.end()
        }
    }

    private func startReplay(userInitiated: Bool) -> Task<Void, Never>? {
        guard let env, store.account != nil else { return nil }
        if userInitiated {
            retryTask?.cancel()
            retryTask = nil
            retryAt = nil
            notAvailable = false
        }
        // Before the contract nothing is sent, not even tried (the live stub would throw without a request).
        guard env.api.publishesActivities, !notAvailable else {
            notAvailable = true
            return nil
        }
        guard env.connectivity.isOnline else { return nil }
        if let retryAt, retryAt > env.clock.now() { return nil }
        if let replay {
            flushAgain = true
            return replay
        }
        let generation = generation, api = env.api, id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            var pass = Pass.done
            repeat {
                flushAgain = false
                gated = false
                pass = await drain(generation, api: api)
            } while pass == .done && flushAgain && generation == self.generation
            // Same main-actor step as the last check: nobody can join a replay that's over.
            guard replayID == id else { return }
            replay = nil
            replayID = nil
            flushAgain = false
        }
        replay = task
        replayID = id
        return task
    }

    private enum Pass { case done, stopped }

    /// Sends one item after another; refused ones are skipped (failed), anything else that fails stops the pass.
    private func drain(_ generation: Generation, api: PlatformAPI) async -> Pass {
        while generation == self.generation, !Task.isCancelled {
            guard let item = next() else { return .done }
            let outcome: Outcome
            switch item {
            case .activity(let id):
                guard let row = store.snapshot(id: id) else { continue }
                outcome = row.isTombstone ? await delete(row, generation, api) : await put(row, generation, api)
            case .sleep(let day):
                guard let night = store.manualSleep(onDay: day) else { continue }
                outcome = await send(night, generation, api)
            }
            guard generation == self.generation else { return .stopped }
            switch outcome {
            case .sent:
                transientFailures[item] = nil
                retryAt = nil
                lostConnection = false
            case .refused:
                transientFailures[item] = nil
            case .stop:
                return .stopped
            }
        }
        return .stopped
    }

    /// The first row to send: activities by creation, then nights by day; never a refused one (until Retry or an
    /// edit clears its refusal).
    private func next() -> Item? {
        if let row = store.unconfirmed().first(where: { !Self.isRefused($0.lastAttempt) }) { return .activity(row.id) }
        if let night = store.unconfirmedSleeps().first(where: { !Self.isRefused($0.lastAttempt) }) { return .sleep(night.day) }
        return nil
    }

    private enum Outcome { case sent, refused, stop }

    // MARK: requests

    private func put(_ row: LocalActivitySnapshot, _ generation: Generation, _ api: PlatformAPI) async -> Outcome {
        let item = Item.activity(row.id), sent = row.localRevision
        let signpost = Self.signposter.beginInterval("activity-put", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("activity-put", signpost) }
        inFlight = item
        defer { if generation == self.generation { inFlight = nil } }
        do {
            let answer = try await api.putActivity(row.activity)
            guard generation == self.generation else { return .stop }
            store.confirm(row.id, revision: sent)
            // Deleted while the PUT was out: the DELETE follows on the next round; nothing to show meanwhile.
            if store.snapshot(id: row.id)?.isTombstone == false {
                let days = Set([answer.start, row.start].map(DayFormat.string(from:)))
                onConfirmed?(answer, days.sorted())
            }
            return .sent
        } catch {
            guard generation == self.generation else { return .stop }
            let current = store.snapshot(id: row.id)?.localRevision == sent
            return failed(item, error, request: .put, current: current)
        }
    }

    private func delete(_ row: LocalActivitySnapshot, _ generation: Generation, _ api: PlatformAPI) async -> Outcome {
        let item = Item.activity(row.id)
        let signpost = Self.signposter.beginInterval("activity-delete", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("activity-delete", signpost) }
        inFlight = item
        defer { if generation == self.generation { inFlight = nil } }
        do {
            try await api.deleteActivity(id: row.id)
        } catch let error as APIError where error.status == 404 {
            // Gone already.
        } catch {
            guard generation == self.generation else { return .stop }
            return failed(item, error, request: .delete, current: true)
        }
        guard generation == self.generation else { return .stop }
        store.remove(row.id)
        onRemoved?(row.id, [DayFormat.string(from: row.start)])
        return .sent
    }

    private func send(_ night: ManualSleepSnapshot, _ generation: Generation, _ api: PlatformAPI) async -> Outcome {
        let item = Item.sleep(night.day), sent = night.localRevision
        let name: StaticString = night.isTombstone ? "sleep-delete" : "sleep-put"
        let signpost = Self.signposter.beginInterval(name, id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval(name, signpost) }
        inFlight = item
        defer { if generation == self.generation { inFlight = nil } }
        do {
            if night.isTombstone {
                do {
                    try await api.deleteManualSleep(day: night.day)
                } catch let error as APIError where error.status == 404 {
                    // Gone already.
                }
                guard generation == self.generation else { return .stop }
                store.removeSleep(day: night.day)
            } else {
                try await api.putManualSleep(day: night.day, ManualSleepPut(bed: night.bed, wake: night.wake))
                guard generation == self.generation else { return .stop }
                store.confirmSleep(day: night.day, revision: sent)
            }
            onSleepConfirmed?(night.day)
            return .sent
        } catch {
            guard generation == self.generation else { return .stop }
            let current = store.manualSleep(onDay: night.day)?.localRevision == sent
            return failed(item, error, request: night.isTombstone ? .delete : .put, current: current)
        }
    }

    /// What a failure means for the row and the queue (API.md → Errors, design.md §4.1).
    private func failed(_ item: Item, _ error: Error, request: UploadAttempt.Request, current: Bool) -> Outcome {
        let api = error as? APIError
        // No contract yet: the live stub, or a platform without the route (`404` on a `PUT`).
        if error as? ActivitiesError == .notPublished || (request == .put && api?.status == 404) {
            notAvailable = true
            return .stop
        }
        switch api {
        case .signedOut?, .notConfigured?:
            // Nobody to send as (a final 401 signs out, and the wipe moves the generation).
            return .stop
        default:
            break
        }
        let kind = FailureKind.of(error)
        let attempt = UploadAttempt(at: env?.clock.now() ?? Date(), request: request, status: api?.status,
                                    code: api?.code?.rawValue, requestID: api?.requestID, kind: kind)
        switch kind {
        case .cancelled:
            // Never a refusal: it stays queued for the next replay.
            return .stop
        case .gate:
            gated = true
            record(item, attempt)
            return .stop
        case .transient, .signedOut:
            record(item, attempt)
            let failures = (transientFailures[item] ?? 0) + 1
            transientFailures[item] = failures
            lostConnection = api?.status == nil
            scheduleRetry(after: failures, retryAfter: api?.retryAfter)
            return .stop
        case .other, .appTooOld:
            // The platform refused this revision: failed, kept, until Retry or an edit. A newer revision saved while
            // the request was out is still to be sent, so the refusal isn't recorded on it.
            if current { record(item, attempt) }
            return .refused
        }
    }

    private func record(_ item: Item, _ attempt: UploadAttempt) {
        switch item {
        case .activity(let id): store.recordFailure(id, attempt)
        case .sleep(let day): store.recordSleepFailure(day: day, attempt)
        }
    }

    /// The next automatic attempt, on the environment's clock.
    private func scheduleRetry(after failures: Int, retryAfter: Int?) {
        guard let env else { return }
        let step = Self.backoff[min(failures, Self.backoff.count) - 1].timeInterval
        var wait = step + random(0...(step * Self.jitter))
        if let retryAfter { wait = max(wait, TimeInterval(retryAfter)) }
        let due = env.clock.now().addingTimeInterval(wait)
        retryAt = due
        retryTask?.cancel()
        let generation = generation, clock = env.clock
        retryTask = Task { [weak self] in
            // Until `due` on the clock, however late this task starts.
            let left = due.timeIntervalSince(clock.now())
            if left > 0 { try? await clock.sleep(for: .seconds(left)) }
            guard !Task.isCancelled, let self, generation == self.generation, self.retryAt == due else { return }
            await self.flush()
        }
    }

    // MARK: states

    /// What My Day and the detail show for an activity.
    func state(of id: UUID) -> UploadState {
        guard let row = store.snapshot(id: id) else { return .confirmed }
        return state(for: row)
    }

    /// The same for a snapshot already read (no fetch). A recording in progress has nothing to send yet: My Day
    /// shows the recording instead.
    func state(for row: LocalActivitySnapshot) -> UploadState {
        guard row.needsUpload else { return .confirmed }
        return pending(.activity(row.id), lastAttempt: row.lastAttempt)
    }

    /// A night's state; nil when the account added none for `day`.
    func sleepState(day: String) -> UploadState? {
        store.manualSleep(onDay: day).map(sleepState(for:))
    }

    func sleepState(for night: ManualSleepSnapshot) -> UploadState {
        guard night.needsUpload else { return .confirmed }
        return pending(.sleep(night.day), lastAttempt: night.lastAttempt)
    }

    private func pending(_ item: Item, lastAttempt: UploadAttempt?) -> UploadState {
        if inFlight == item { return .pending(.inFlight) }
        if let lastAttempt, Self.isRefused(lastAttempt) { return .failed(lastAttempt) }
        if let lastAttempt, (transientFailures[item] ?? 0) >= Self.failedAfter { return .failed(lastAttempt) }
        guard let env, env.api.publishesActivities, !notAvailable else { return .pending(.notAvailableYet) }
        if gated { return .pending(.gated) }
        if !env.connectivity.isOnline { return .pending(.offline) }
        if let retryAt, retryAt > env.clock.now() { return .pending(.retrying(at: retryAt)) }
        return .pending(.queued)
    }

    /// The platform refused the request (`400`, `413`, `422`, …): only Retry or an edit sends it again.
    private static func isRefused(_ attempt: UploadAttempt?) -> Bool {
        guard let attempt else { return false }
        return attempt.kind == .other || attempt.kind == .appTooOld
    }

    /// Whether the platform may hold the item: confirmed once, being sent, or a request whose fate is unknown (no
    /// answer, a server error, a cancellation). Refused requests and ones never sent left nothing there.
    private func mayBeOnPlatform(_ item: Item, confirmed: Int, lastAttempt: UploadAttempt?) -> Bool {
        if confirmed > 0 || inFlight == item { return true }
        guard let lastAttempt else { return false }
        return lastAttempt.kind == .transient || lastAttempt.kind == .cancelled || lastAttempt.kind == .signedOut
    }

    // MARK: signposts

    /// One interval per request (`activity-put`, `activity-delete`, `sleep-put`, `sleep-delete`): Instruments, or
    /// `log show --signpost`.
    private static let signposter = OSSignposter(subsystem: "dev.timkrebs.ryft", category: "uploads")
}

extension ActivityUploader {
    /// The app's follow-ups (ScreenModels): a confirmed activity into the read model (without route and samples),
    /// a confirmed delete out of it, and the platform's rescoring of the days through the sync pipeline
    /// (`.daysChanged`: the scoring wait, then the refresh). An edit that moved an activity to another day rescores
    /// the day it left too.
    func connect(repository: Repository, coordinator: SyncCoordinator) {
        onConfirmed = { [weak repository] activity, days in
            guard let repository else { return }
            let left = repository.cachedDay(ofActivity: activity.id)
            repository.store(activity: activity)
            let all = Set(days + [left].compactMap { $0 }).sorted()
            Task { await coordinator.run(.daysChanged(days: all)) }
        }
        onRemoved = { [weak repository] id, days in
            let left = repository?.cachedDay(ofActivity: id)
            repository?.forget(activity: id)
            let all = Set(days + [left].compactMap { $0 }).sorted()
            Task { await coordinator.run(.daysChanged(days: all)) }
        }
        onSleepConfirmed = { day in
            Task { await coordinator.run(.daysChanged(days: [day])) }
        }
    }
}

/// One background task for the request in flight, ended exactly once (by the replay or by the expiry).
@MainActor
private final class UploadBackgroundTask {
    private let app: BackgroundTaskRunning
    private var id = UIBackgroundTaskIdentifier.invalid

    init(app: BackgroundTaskRunning) { self.app = app }

    func begin(onExpiry: @escaping @MainActor () -> Void) {
        id = app.beginBackgroundTask(withName: "Finish the activity upload") { [weak self] in
            onExpiry()
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        app.endBackgroundTask(id)
        id = .invalid
    }
}
