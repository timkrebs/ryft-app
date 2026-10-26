// Sends what the user added, edited or deleted on this iPhone to the platform (design.md §4.1): activities
// (`PUT`/`DELETE /v1/activities/{id}`) and manual sleep (`PUT`/`DELETE /v1/sleep/manual/{day}`).
//
//   save / edit ──▶ localRevision += 1 ──▶ flush ──▶ PUT (the whole document as of that revision)
//                                                      2xx ──▶ confirmedRevision = the revision sent
//                                                      edited meanwhile ──▶ one more PUT
//   delete ──▶ never sent: gone at once · else tombstone ──▶ DELETE (2xx or 404 ──▶ gone)
//   transport · 5xx · 408 · 429 · 401 ──▶ that item backs off 30 s · 2 min · 10 min · 1 h (jitter, Retry-After)
//   403 + code, or the gate ──▶ gated (a DELETE passes the consent gate) · 404 on PUT, or no contract yet ──▶ not
//   available yet
//   other 4xx ──▶ failed, kept
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
/// - **Consent first:** no `PUT` goes up while `gate(.data)` names a gate (the rule `SyncService` asks too), as with
///   HealthKit data. A `DELETE` asks `gate(.erasure)`, which only demo binding, an unreadable record and an enforced
///   invite gate hold: erasure goes without a current consent (ADR 0008).
/// - **Never lost:** nothing is deleted before the platform confirmed it, except a delete of a row that was never
///   sent, and the account wipe. A refusal is a state (`failed`), shown with its status and request ID.
/// - **No row holds up the others:** each item backs off on its own; an item that failed `failedAfter` times in a
///   row is passed over until its next attempt is due, and the rest go on.
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
    /// Transient failures in a row before the item shows "failed" (with Retry) and stops holding up the queue.
    /// Attempts go on at the backoff's pace.
    static let failedAfter = 3
    /// "Send first" before a sign-out waits at most this long (design.md §8.4).
    static let sendFirstLimit: Duration = .seconds(10)
    /// `BGAppRefreshTask` waits at most this long for the queue (iOS allows about 30 s in all).
    static let backgroundLimit: Duration = .seconds(20)

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

    /// An item's transient failures in a row, and when it may be tried again.
    struct Backoff: Equatable {
        var failures: Int
        var due: Date
    }

    // MARK: wiring (the app connects these: `connect(repository:coordinator:)`, ScreenModels)

    /// The platform confirmed an activity's `PUT`: its answer (the read model stores it without route or heart-rate
    /// samples) and the days whose scores change.
    @ObservationIgnored var onConfirmed: (@MainActor (SportActivity, _ days: [String]) -> Void)?
    /// The platform confirmed an activity's `DELETE` (or no longer had it): out of the read model; its day rescored.
    @ObservationIgnored var onRemoved: (@MainActor (_ id: UUID, _ days: [String]) -> Void)?
    /// The platform confirmed a night's `PUT` or `DELETE`: that day is rescored.
    @ObservationIgnored var onSleepConfirmed: (@MainActor (_ day: String) -> Void)?
    /// What still stands between the account and a request of that kind
    /// (`OnboardingCoordinator.uploadGate(for: .activities, write:)`): for `PUT`s no consent to the policy in force,
    /// an enforced invite gate, the account or the policy not known yet; for `DELETE`s only the invite gate and a
    /// record that can't be read. While it names one, nothing of that kind is sent. **Closed until the app connects
    /// it** (ScreenModels), so no path can upload without consent; tests open it explicitly.
    @ObservationIgnored var gate: @MainActor (UploadWrite) -> UploadGate? = { _ in .gate(.consentRequired) }
    /// Jitter source (tests: `{ $0.lowerBound }`).
    @ObservationIgnored var random: (ClosedRange<Double>) -> Double = { .random(in: $0) }

    // MARK: state

    /// What's being sent right now.
    private(set) var inFlight: Item?
    /// Per item after transient failures (in memory: a relaunch starts over).
    private(set) var backoffs: [Item: Backoff] = [:]
    /// The platform doesn't take uploads yet (a `404` on `PUT`): nothing is sent until the app is active again.
    private var notAvailable = false
    /// A gate refused the last request (a `403` with a code): tried again on the next trigger. (`gate` is asked
    /// live.)
    private var gated = false
    /// The last transient failure had no answer at all: a reconnect retries at once.
    private var lostConnection = false

    @ObservationIgnored private weak var env: AppEnvironment?
    @ObservationIgnored private let store: ActivityStore
    @ObservationIgnored private var accountCount = 0
    /// The replay in flight. It's the uploader's, not its caller's: only `accountChanged()` and `stopReplay()` (a
    /// background task's expiry) cancel it.
    @ObservationIgnored private var replay: Task<Void, Never>?
    @ObservationIgnored private var replayID: UUID?
    @ObservationIgnored private var flushAgain = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    init(env: AppEnvironment, store: ActivityStore) {
        self.env = env
        self.store = store
        env.connectivityMonitor.onChange { [weak self] online in
            guard online, let self else { return }
            if self.lostConnection { self.makeEverythingDue() }
            Task { await self.flush() }
        }
    }

    var generation: Generation {
        Generation(count: accountCount, account: store.account, demo: env?.isDemo ?? false,
                   store: (env?.persistence as? TrainStore)?.epoch ?? 0)
    }

    /// The earliest automatic attempt waiting after a transient failure; nil when none is.
    var retryAt: Date? { backoffs.values.map(\.due).min() }

    /// Activities and nights the platform hasn't confirmed yet (edits, new rows, deletes) for the account the store
    /// reads as.
    var pendingCount: Int { store.unconfirmed().count + store.unconfirmedSleeps().count }

    // MARK: triggers

    /// A save or an edit (the store bumped the revision): the queue runs, this row without waiting out a backoff.
    func saved(_ id: UUID) {
        backoffs[.activity(id)] = nil
        Task { await flush() }
    }

    /// Delete: a row the platform can't have (never sent, or every attempt refused) goes at once; otherwise it
    /// stays as a tombstone until the `DELETE` is confirmed.
    func deleted(_ id: UUID) {
        guard let row = store.snapshot(id: id) else { return }
        backoffs[.activity(id)] = nil
        guard mayBeOnPlatform(.activity(id), confirmed: row.confirmedRevision, sentAt: row.sentAt) else {
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
        backoffs[.sleep(day)] = nil
        Task { await flush() }
    }

    /// Delete a night, like `deleted(_:)`.
    func sleepDeleted(day: String) {
        guard let night = store.manualSleep(onDay: day) else { return }
        backoffs[.sleep(day)] = nil
        guard mayBeOnPlatform(.sleep(day), confirmed: night.confirmedRevision, sentAt: night.sentAt) else {
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

    /// Retry on a failed row: its refusal and backoff are forgotten and it's sent now.
    func retry(_ id: UUID) async {
        store.recordFailure(id, nil)
        backoffs[.activity(id)] = nil
        await flush(userInitiated: true)
    }

    /// Retry on a failed night.
    func retrySleep(day: String) async {
        store.recordSleepFailure(day: day, nil)
        backoffs[.sleep(day)] = nil
        await flush(userInitiated: true)
    }

    /// Signed out, another account, the Demo data switch, or an account deletion starting: the replay and the retry
    /// stop, answers still in flight are dropped (`generation`), and nothing of the previous account's state shows.
    func accountChanged() {
        accountCount += 1
        replay?.cancel()
        replay = nil
        replayID = nil
        flushAgain = false
        retryTask?.cancel()
        retryTask = nil
        inFlight = nil
        backoffs = [:]
        notAvailable = false
        gated = false
        lostConnection = false
    }

    /// The system's time ran out (a background task's expiry): the replay stops; the request in flight is
    /// cancelled, never counted as a refusal, and the row stays queued.
    func stopReplay() {
        replay?.cancel()
    }

    // MARK: replay

    /// Sends the queue until it's empty or something stops it (offline, the gate, no contract, a transient failure).
    /// Items still backing off are passed over. A replay already running goes round once more for this caller, who
    /// waits for it. `userInitiated` (Retry, Send first) doesn't wait out a backoff.
    func flush(userInitiated: Bool = false) async {
        guard let replay = startReplay(userInitiated: userInitiated) else { return }
        await replay.value
    }

    /// The same, waiting at most `limit` (Send first before a sign-out, the background refresh); the replay goes on
    /// after it unless `stopReplay()` ends it. Returns how many activities and nights are still unconfirmed.
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
        token.begin { [weak self] in self?.stopReplay() }
        return Task {
            await replay.value
            token.end()
        }
    }

    /// `hold` is what `gate(_:)` said: asked once by each caller. An account being deleted holds everything.
    private func isHeld(by hold: UploadGate?) -> Bool { hold != nil || env?.auth.isDeletingAccount == true }

    private func startReplay(userInitiated: Bool) -> Task<Void, Never>? {
        guard let env, store.account != nil else { return nil }
        if userInitiated {
            makeEverythingDue()
            notAvailable = false
        }
        // Before the contract nothing is sent, not even tried (the live stub would throw without a request).
        guard env.api.publishesActivities, !notAvailable else {
            notAvailable = true
            return nil
        }
        guard env.connectivity.isOnline else { return nil }
        // Consent and the invite gate first, as for HealthKit data: nothing starts while both kinds hold. A policy
        // this phone doesn't know right now is asked for before the first `PUT` (`ConsentState.revalidate`), and
        // every item asks the gate for its own kind.
        let data = gate(.data)
        let dataWaits = isHeld(by: data) && (data != .policyUnknown || env.auth.isDeletingAccount)
        if dataWaits, isHeld(by: gate(.erasure)) { return nil }
        if let replay {
            flushAgain = true
            return replay
        }
        let generation = generation, api = env.api, id = UUID()
        let consent = env.consent
        let task = Task { [weak self] in
            guard let self else { return }
            // The policy is asked for at most once per replay (joined with any read in flight, at most once a minute
            // after a failure), when the first `PUT` finds it unknown; a `DELETE` never waits for it.
            var revalidated = false
            var pass = Pass.done
            repeat {
                flushAgain = false
                gated = false
                pass = await drain(generation, api: api, consent: consent, revalidated: &revalidated)
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

    /// One item's request.
    private enum Work {
        case put(LocalActivitySnapshot)
        case delete(LocalActivitySnapshot)
        case night(ManualSleepSnapshot)

        var write: UploadWrite {
            switch self {
            case .put: return .data
            case .delete: return .erasure
            case .night(let night): return night.isTombstone ? .erasure : .data
            }
        }
    }

    /// Sends one item after another. Refused items (until Retry or an edit), items that failed `failedAfter` times in
    /// a row, and items the gate holds (for the rest of the pass) are passed over; any other failure stops the pass.
    private func drain(_ generation: Generation, api: PlatformAPI, consent: ConsentState,
                       revalidated: inout Bool) async -> Pass {
        var passedOver = Set<Item>()
        var dataHeld = false
        while generation == self.generation, !Task.isCancelled {
            if env?.auth.isDeletingAccount == true { return .stopped }
            guard let item = next(excluding: passedOver) else { return dataHeld ? .stopped : .done }
            let work: Work
            switch item {
            case .activity(let id):
                guard let row = store.snapshot(id: id) else { continue }
                work = row.isTombstone ? .delete(row) : .put(row)
            case .sleep(let day):
                guard let night = store.manualSleep(onDay: day) else { continue }
                work = .night(night)
            }
            // Asked before every item, for its kind: consent withdrawn while the queue runs holds the next `PUT`, and
            // every `PUT` after it in this pass (their order stays); a `DELETE` still goes.
            if work.write == .data, dataHeld {
                passedOver.insert(item)
                continue
            }
            var hold = gate(work.write)
            if hold == .policyUnknown, work.write == .data, !revalidated {
                revalidated = true
                try? await consent.revalidate()
                guard generation == self.generation else { return .stopped }
                hold = gate(work.write)
            }
            if hold != nil {
                if work.write == .data { dataHeld = true }
                passedOver.insert(item)
                continue
            }
            let outcome: Outcome
            switch work {
            case .put(let row): outcome = await put(row, generation, api)
            case .delete(let row): outcome = await delete(row, generation, api)
            case .night(let night): outcome = await send(night, generation, api)
            }
            guard generation == self.generation else { return .stopped }
            switch outcome {
            case .sent:
                backoffs[item] = nil
                if backoffs.isEmpty { lostConnection = false }
            case .refused:
                // Recorded on the row, so `next` passes it over; a newer revision saved meanwhile goes up now.
                backoffs[item] = nil
            case .passOver:
                passedOver.insert(item)
            case .stop:
                return .stopped
            }
        }
        return .stopped
    }

    /// The first item to send: activities by creation, then nights by day. Never a refused one (until Retry or an
    /// edit clears its refusal), one passed over in this pass, or one still backing off.
    private func next(excluding passedOver: Set<Item>) -> Item? {
        let now = env?.clock.now() ?? Date()
        func ready(_ item: Item, _ attempt: UploadAttempt?) -> Bool {
            !passedOver.contains(item) && !Self.isRefused(attempt) && (backoffs[item]?.due ?? .distantPast) <= now
        }
        if let row = store.unconfirmed().first(where: { ready(.activity($0.id), $0.lastAttempt) }) {
            return .activity(row.id)
        }
        if let night = store.unconfirmedSleeps().first(where: { ready(.sleep($0.day), $0.lastAttempt) }) {
            return .sleep(night.day)
        }
        return nil
    }

    private enum Outcome { case sent, refused, passOver, stop }

    // MARK: requests

    private func put(_ row: LocalActivitySnapshot, _ generation: Generation, _ api: PlatformAPI) async -> Outcome {
        let item = Item.activity(row.id), sent = row.localRevision
        let signpost = Self.signposter.beginInterval("activity-put", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("activity-put", signpost) }
        // Persisted before the request goes out: a kill or a cut-off now leaves "may be on the platform".
        store.setSent(row.id, env?.clock.now() ?? Date())
        let undoSent = { [store] in store.setSent(row.id, row.sentAt) }
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
            return failed(item, error, request: .put, current: current, nothingStored: undoSent)
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
            return failed(item, error, request: .delete, current: true, nothingStored: {})
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
        if !night.isTombstone { store.setSleepSent(day: night.day, env?.clock.now() ?? Date()) }
        let undoSent = { [store] in if !night.isTombstone { store.setSleepSent(day: night.day, night.sentAt) } }
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
                // Added again while the DELETE was out: that night stays, and goes up on the next round.
                store.removeSleep(day: night.day, onlyIfDeleted: true)
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
            return failed(item, error, request: night.isTombstone ? .delete : .put, current: current,
                          nothingStored: undoSent)
        }
    }

    /// What a failure means for the row and the queue (API.md → Errors, design.md §4.1). `nothingStored` undoes the
    /// request's sent marker: called for answers that say this request left nothing on the platform (no contract,
    /// signed out or not configured before anything went out, a gate, a refusal), never for a cut-off, a timeout or
    /// a server error, and never for an answer with a 2xx status this build couldn't read.
    private func failed(_ item: Item, _ error: Error, request: UploadAttempt.Request, current: Bool,
                        nothingStored: () -> Void) -> Outcome {
        let api = error as? APIError
        // No contract yet: the live stub, or a platform without the route (`404` on a `PUT`). Nothing was stored.
        if error as? ActivitiesError == .notPublished || (request == .put && api?.status == 404) {
            notAvailable = true
            nothingStored()
            return .stop
        }
        switch api {
        case .signedOut?, .notConfigured?:
            // Nobody to send as, so nothing went out (a final 401 signs out, and the wipe moves the generation).
            nothingStored()
            return .stop
        default:
            break
        }
        let kind = FailureKind.of(error)
        let answered = api?.status.map { (200..<300).contains($0) } ?? false
        if !answered, kind == .gate || kind == .signedOut || kind == .other || kind == .appTooOld { nothingStored() }
        let attempt = UploadAttempt(at: env?.clock.now() ?? Date(), request: request, status: api?.status,
                                    code: api?.code?.rawValue, requestID: api?.requestID, kind: kind)
        switch kind {
        case .cancelled:
            // Never a refusal, never counted: it stays queued, and `sentAt` says it may have arrived.
            return .stop
        case .gate:
            gated = true
            record(item, attempt)
            return .stop
        case .transient, .signedOut:
            record(item, attempt)
            let failures = (backoffs[item]?.failures ?? 0) + 1
            backoffs[item] = Backoff(failures: failures, due: due(after: failures, retryAfter: api?.retryAfter))
            lostConnection = api?.status == nil
            scheduleRetry()
            // Probably the platform or the network as a whole: stop. One item failing again and again is passed over.
            return failures >= Self.failedAfter ? .passOver : .stop
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

    /// When an item that failed `failures` times in a row may be tried again, on the environment's clock.
    private func due(after failures: Int, retryAfter: Int?) -> Date {
        let step = Self.backoff[min(failures, Self.backoff.count) - 1].timeInterval
        var wait = step + random(0...(step * Self.jitter))
        if let retryAfter { wait = max(wait, TimeInterval(retryAfter)) }
        return (env?.clock.now() ?? Date()).addingTimeInterval(wait)
    }

    /// Backoffs end now (Retry, Send first, a reconnect after a lost connection); the failure counts stay.
    private func makeEverythingDue() {
        let now = env?.clock.now() ?? Date()
        for item in backoffs.keys { backoffs[item]?.due = now }
        retryTask?.cancel()
        retryTask = nil
    }

    /// One timer, for the earliest backoff still ahead.
    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = nil
        guard let env, let due = backoffs.values.map(\.due).filter({ $0 > env.clock.now() }).min() else { return }
        let generation = generation, clock = env.clock
        retryTask = Task { [weak self] in
            // Until `due` on the clock, however late this task starts.
            let left = due.timeIntervalSince(clock.now())
            if left > 0 { try? await clock.sleep(for: .seconds(left)) }
            guard !Task.isCancelled, let self, generation == self.generation else { return }
            await self.flush()
            // Others may still be backing off (unless a failure meanwhile set a new timer).
            if !Task.isCancelled { self.scheduleRetry() }
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
        return pending(.activity(row.id), write: row.isTombstone ? .erasure : .data, lastAttempt: row.lastAttempt)
    }

    /// A night's state; nil when the account added none for `day`.
    func sleepState(day: String) -> UploadState? {
        store.manualSleep(onDay: day).map(sleepState(for:))
    }

    func sleepState(for night: ManualSleepSnapshot) -> UploadState {
        guard night.needsUpload else { return .confirmed }
        return pending(.sleep(night.day), write: night.isTombstone ? .erasure : .data, lastAttempt: night.lastAttempt)
    }

    private func pending(_ item: Item, write: UploadWrite, lastAttempt: UploadAttempt?) -> UploadState {
        if inFlight == item { return .pending(.inFlight) }
        if let lastAttempt, Self.isRefused(lastAttempt) { return .failed(lastAttempt) }
        let backoff = backoffs[item]
        if let lastAttempt, let backoff, backoff.failures >= Self.failedAfter { return .failed(lastAttempt) }
        guard let env, env.api.publishesActivities, !notAvailable else { return .pending(.notAvailableYet) }
        let online = env.connectivity.isOnline
        let hold = gate(write) // once per row (My Day renders every row)
        if gated || isHeld(by: hold) {
            // Only the policy version is missing, and only being online brings it: say offline. Missing consent or
            // an invite stays "gated" (being online won't help).
            if !gated, !online, hold == .policyUnknown, !env.auth.isDeletingAccount { return .pending(.offline) }
            return .pending(.gated)
        }
        if !online { return .pending(.offline) }
        if let backoff, backoff.due > env.clock.now() { return .pending(.retrying(at: backoff.due)) }
        return .pending(.queued)
    }

    /// The platform refused the request (`400`, `413`, `422`, …): only Retry or an edit sends it again.
    private static func isRefused(_ attempt: UploadAttempt?) -> Bool {
        guard let attempt else { return false }
        return attempt.kind == .other || attempt.kind == .appTooOld
    }

    /// Whether the platform may hold the item: confirmed once, being sent, or sent without an answer that says
    /// nothing was stored (`sentAt`, which edits, Retry and tombstones keep). Only rows never sent, or whose every
    /// request was refused, left nothing there.
    private func mayBeOnPlatform(_ item: Item, confirmed: Int, sentAt: Date?) -> Bool {
        confirmed > 0 || inFlight == item || sentAt != nil
    }

    // MARK: signposts

    /// One interval per request (`activity-put`, `activity-delete`, `sleep-put`, `sleep-delete`): Instruments, or
    /// `log show --signpost`.
    private static let signposter = OSSignposter(subsystem: "dev.timkrebs.ryft", category: "uploads")
}

extension ActivityUploader {
    /// The app's follow-ups (ScreenModels): a confirmed activity into the read model (without route and samples),
    /// a confirmed delete out of it, and the platform's rescoring of the days through the sync pipeline
    /// (`.daysChanged`: the scoring wait, then the refresh). An edit that moved an activity from a day My Day's strip
    /// shows rescores that day too.
    func connect(repository: Repository, coordinator: SyncCoordinator) {
        onConfirmed = { [weak repository] activity, days in
            guard let repository else { return }
            let left = repository.cachedDay(ofActivity: activity.id, startingOn: DayFormat.string(from: activity.start))
            repository.store(activity: activity)
            let all = Set(days + [left].compactMap { $0 }).sorted()
            Task { await coordinator.run(.daysChanged(days: all)) }
        }
        onRemoved = { [weak repository] id, days in
            let left = repository?.cachedDay(ofActivity: id, startingOn: days.first)
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
