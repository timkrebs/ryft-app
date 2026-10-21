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
    /// The op being sent right now; a change meanwhile queues a fresh `put`.
    private var inFlightSeq: Int?
    private var flushAgain = false
    /// Off in tests: they drive "offline" through the stub URLProtocol instead.
    private let monitorsNetwork: Bool
    private let connectivity: ConnectivityMonitor

    /// Conflict rounds per upload before the op is set aside.
    static let maxConflictRounds = 3

    init(store: TrainStore? = nil, remote: (() -> TrainDataSource)? = nil,
         debounce: Duration = .seconds(2), monitorsNetwork: Bool = true, connectivity: ConnectivityMonitor? = nil) {
        self.connectivity = connectivity ?? .shared
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
        await flush()
        guard !s.pendingCompletion else { return nil }
        return s.wire
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

    /// Sends queued ops in order until the queue is empty or the network fails.
    func flush() async {
        guard !monitorsNetwork || connectivity.isOnline else { return }
        guard !isFlushing else {
            flushAgain = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }
        repeat {
            flushAgain = false
            await drain()
        } while flushAgain
    }

    private func drain() async {
        while let op = store.pendingOps().first {
            inFlightSeq = op.seq
            defer { inFlightSeq = nil }
            do {
                try await perform(op)
                store.dequeue(op)
                lastError = nil
                isOnline = true
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
        case .http(let code, _, _, _): return code == 401 || code == 408 || code == 429 || code >= 500
        }
    }

    private func perform(_ op: PendingTrainOp) async throws {
        switch op.kind {
        case .put:
            guard let s = store.session(id: op.sessionId) else { return } // discarded meanwhile
            try await put(s)
        case .complete:
            guard let s = store.session(id: op.sessionId) else { return }
            // `ended_at` from here: the queue may replay this long after the workout.
            let done = try await remote.completeSession(id: s.id, SessionComplete(bodyweightKg: op.bodyweightKg,
                                                                                endedAt: s.endedAt))
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

    private func put(_ s: LocalSession) async throws {
        var doc = s.wire
        for _ in 0..<Self.maxConflictRounds {
            switch try await remote.putSession(doc) {
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
