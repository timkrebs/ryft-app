// Uploads logged sessions. Local-first: every change is saved to SwiftData
// and queued at once; the queue is replayed in order.
//
//   set change ──▶ outbox `put` (coalesced) ──2 s debounce──▶ PUT /v1/sessions/{id}
//   finish     ──▶ outbox `put` (still in_progress), `complete` ──now──▶ PUT, POST …/complete {ended_at}
//   409        ──▶ merge with the server copy by set id (later updated_at) ──▶ PUT again
//   offline    ──▶ ops stay queued; NWPathMonitor (and app active) replays them
//
// Nothing here touches HealthKit; sessions aren't written to Health in v1.
import Foundation
import Observation

@MainActor
@Observable
final class TrainSyncService {
    static let shared = TrainSyncService()

    private(set) var isOnline = true
    private(set) var pendingCount = 0
    private(set) var isFlushing = false
    private(set) var lastError: String?
    /// The latest completion the server answered, for the summary sheet.
    private(set) var lastCompletion: TrainSession?

    let store: TrainStore
    private let remoteProvider: () -> TrainDataSource
    private let debounce: Duration
    private var debounceTask: Task<Void, Never>?
    /// The replay in flight. It belongs to this service, not to whoever asked: a new set or Finish
    /// cancels the 2 s wait, never a request in flight.
    private var replay: Task<Void, Never>?
    /// The running replay's identity: only it clears `replay` when it ends (not one an account
    /// change or a wipe left behind).
    private var replayID: UUID?
    /// The op being sent right now; a change meanwhile queues a fresh `put`.
    private var inFlightSeq: Int?
    private var flushAgain = false
    /// Which account (`accountChanged()`) and which store contents (`TrainStore.wipe()`) a replay works
    /// for: an answer that arrives after either moved is dropped. The wipe moves it at once, in the
    /// sign-out itself, before the app's account-change handler runs.
    struct Generation: Equatable {
        let account: Int
        let store: Int
    }

    private var accountCount = 0
    var generation: Generation { Generation(account: accountCount, store: store.epoch) }
    /// Finish waits this long for the replay, then says "will sync" (the replay goes on).
    private let finishWait: Duration
    /// Off in tests: they drive "offline" through the stub URLProtocol instead.
    private let monitorsNetwork: Bool
    private let connectivity: ConnectivityMonitor

    /// Conflict rounds per upload before the op is set aside.
    static let maxConflictRounds = 3

    init(store: TrainStore? = nil, remote: (() -> TrainDataSource)? = nil,
         debounce: Duration = .seconds(2), finishWait: Duration = .seconds(10), monitorsNetwork: Bool = true,
         connectivity: ConnectivityMonitor? = nil) {
        self.connectivity = connectivity ?? .shared
        self.finishWait = finishWait
        self.store = store ?? .shared
        self.remoteProvider = remote ?? { TrainSource.current }
        self.debounce = debounce
        self.monitorsNetwork = monitorsNetwork
        pendingCount = self.store.pendingOps().count
        if monitorsNetwork { startMonitoring() }
    }

    private var remote: TrainDataSource { remoteProvider() }

    // MARK: changes

    /// After every set change: persist now, upload after a quiet 2 s.
    func sessionChanged(_ s: LocalSession) {
        s.updatedAt = .now
        enqueuePut(for: s.id)
        scheduleFlush()
    }

    /// Finish: upload the last state and complete. Returns the server's answer,
    /// or `nil` when offline (the session is marked `pendingCompletion`).
    @discardableResult
    func finish(_ s: LocalSession, bodyweightKg: Double? = nil) async -> TrainSession? {
        let now = Date.now
        s.status = .completed
        s.endedAt = now
        s.updatedAt = now
        s.volumeKg = s.liveVolumeKg
        s.pendingCompletion = true
        s.restEndsAt = nil
        enqueuePut(for: s.id)
        store.enqueue(.complete, sessionID: s.id, bodyweightKg: bodyweightKg)
        refreshCount()
        debounceTask?.cancel()
        let generation = generation
        guard let replay = startReplay() else { return nil }      // offline: "will sync"
        // At most `finishWait` (a request can wait minutes for a network): then "will sync", and the
        // replay goes on; its answer still lands on the session.
        _ = await wait(for: replay, upTo: finishWait)
        // Another account meanwhile: this session isn't theirs (and may be wiped).
        guard generation == self.generation, !s.pendingCompletion else { return nil }
        return s.wire
    }

    /// Signed out or another account: the replay and the 2 s wait stop, and nothing of the previous
    /// account's shows (summary, error). An answer still in flight for it is dropped (`generation`).
    func accountChanged() {
        accountCount += 1
        debounceTask?.cancel()
        debounceTask = nil
        replay?.cancel()
        replay = nil
        replayID = nil
        isFlushing = false
        flushAgain = false
        inFlightSeq = nil
        lastCompletion = nil
        lastError = nil
        refreshCount()
    }

    /// Discard (after confirmation): gone locally; a `DELETE` if the server has a copy.
    func discard(_ s: LocalSession) {
        let id = s.id, uploaded = s.uploaded
        store.dropOps(for: id)
        store.delete(s)
        if uploaded { store.enqueue(.delete, sessionID: id) }
        refreshCount()
        Task { await flush() }
    }

    private func enqueuePut(for id: UUID) {
        // One queued PUT per session is enough: it sends the document as it is then.
        let last = store.pendingOps().last { $0.sessionId == id }
        if let last, last.kind == .put, last.seq != inFlightSeq {
            store.save()
            return
        }
        store.enqueue(.put, sessionID: id)
        refreshCount()
    }

    private func scheduleFlush() {
        debounceTask?.cancel()
        let wait = debounce
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    // MARK: replay

    /// Sends queued ops in order until the queue is empty or the network fails. A replay already
    /// running goes round once more for this caller, who waits for it.
    func flush() async {
        guard let replay = startReplay() else { return }
        await replay.value
    }

    /// The same, waiting at most `limit` (app active: the library needn't wait for a slow upload).
    func flush(upTo limit: Duration) async {
        guard let replay = startReplay() else { return }
        _ = await wait(for: replay, upTo: limit)
    }

    /// Starts the replay, or has the running one go round once more; nil offline.
    private func startReplay() -> Task<Void, Never>? {
        guard !monitorsNetwork || connectivity.isOnline else { return nil }
        if let replay {
            flushAgain = true
            return replay
        }
        let generation = generation, id = UUID()
        // Its own task: cancelling the caller (the debounce, Finish's view) can't cancel a PUT; only
        // `accountChanged()` does.
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                flushAgain = false
                await drain(generation)
            } while flushAgain && isOnline && generation == self.generation
            // Same main-actor step as the last check: nobody can join a replay that's over.
            guard replayID == id else { return }
            flushAgain = false
            replay = nil
            replayID = nil
            isFlushing = false
        }
        replay = task
        replayID = id
        isFlushing = true
        return task
    }

    /// Whether `task` ended within `limit`; it goes on either way.
    private func wait(for task: Task<Void, Never>, upTo limit: Duration) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(continuation)
            Task {
                await task.value
                once.resume(true)
            }
            Task {
                try? await Task.sleep(for: limit)
                once.resume(false)
            }
        }
    }

    private func drain(_ generation: Generation) async {
        while generation == self.generation, let op = store.pendingOps().first {
            inFlightSeq = op.seq
            defer { inFlightSeq = nil }
            do {
                try await perform(op, generation)
                // Another account meanwhile: its queue and sessions aren't this replay's.
                guard generation == self.generation else { return }
                store.dequeue(op)
                lastError = nil
                isOnline = true
            } catch is CancellationError {
                // A cancelled request is never a refusal: the op stays queued for the next replay.
                if generation == self.generation { refreshCount() }
                return
            } catch where generation != self.generation {
                return
            } catch let error as APIError where Self.isRetryable(error) {
                // Offline, signed out or the platform is busy: keep the queue as is.
                if case .transport = error { isOnline = false }
                lastError = error.localizedDescription
                refreshCount()
                return
            } catch {
                // The platform refused this op (4xx): set it aside, keep the local copy.
                TrainStore.log.error("Train \(op.kindRaw, privacy: .public) dropped: \(error.localizedDescription, privacy: .public)")
                lastError = error.localizedDescription
                store.dequeue(op)
            }
            refreshCount()
        }
    }

    static func isRetryable(_ error: APIError) -> Bool {
        switch error {
        case .transport, .notConfigured, .signedOut: return true
        // A gate (invite, consent) is passed later: keep the op for then.
        case .http(let code, _, _, let gate, _): return code == 401 || code == 408 || code == 429 || code >= 500
            || (code == 403 && gate != nil)
        }
    }

    private func perform(_ op: PendingTrainOp, _ generation: Generation) async throws {
        switch op.kind {
        case .put:
            guard let s = store.session(id: op.sessionId) else { return } // discarded meanwhile
            try await put(s, generation)
        case .complete:
            guard let s = store.session(id: op.sessionId) else { return }
            // `ended_at` from here: the queue may replay this long after the workout.
            let done = try await remote.completeSession(id: s.id, SessionComplete(bodyweightKg: op.bodyweightKg,
                                                                                endedAt: s.endedAt))
            // Another account meanwhile: the session may be wiped, and the answer isn't theirs.
            guard generation == self.generation else { throw CancellationError() }
            s.pendingCompletion = false
            s.apply(done, names: store.exercise(id:), in: store.context)
            s.prs = done.prs
            s.pendingCompletion = false
            store.save()
            lastCompletion = done
        case .delete:
            do {
                try await remote.deleteSession(id: op.sessionId)
            } catch let e as APIError where e.status == 404 {
                return // already gone
            }
        }
    }

    private func put(_ s: LocalSession, _ generation: Generation) async throws {
        var doc = s.wire
        for _ in 0..<Self.maxConflictRounds {
            let result = try await remote.putSession(doc)
            guard generation == self.generation else { throw CancellationError() }
            switch result {
            case .saved:
                s.uploaded = true
                store.save()
                return
            case .conflict(let server):
                s.uploaded = true
                let merged = SessionMerge.merge(local: s.wire, server: server, deletedSetIDs: Set(s.deletedSetIDs))
                s.apply(merged, names: store.exercise(id:), in: store.context)
                store.save()
                doc = s.wire
            }
        }
        throw APIError.http(409, String(localized: "This workout changed on another device. Open it again to sync."))
    }

    private func refreshCount() {
        pendingCount = store.pendingOps().count
    }

    // MARK: network

    private func startMonitoring() {
        isOnline = connectivity.isOnline
        connectivity.onChange { [weak self] online in
            guard let self else { return }
            self.isOnline = online
            if online { Task { await self.flush() } }
        }
    }
}

/// Resumes a continuation once, whichever of its racers comes first.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        let pending = lock.withLock { () -> CheckedContinuation<T, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
