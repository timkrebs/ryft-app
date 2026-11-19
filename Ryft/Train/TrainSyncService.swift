// Uploads logged sessions. Local-first: every change is saved to SwiftData
// and queued at once; the queue is replayed in order.
//
//   set change ──▶ outbox `put` (coalesced) ──2 s debounce──▶ PUT /v1/sessions/{id}
//   finish     ──▶ outbox `put` (still in_progress), `complete` ──now──▶ PUT, POST …/complete {ended_at}
//   409        ──▶ merge with the server copy by set id (later updated_at) ──▶ PUT again
//   offline    ──▶ ops stay queued; NWPathMonitor (and app active) replays them
//   gate       ──▶ PUT and complete wait for consent to the policy in force; DELETE goes without it (ADR 0008)
//   binding    ──▶ every op is its account's or demo's, and goes only through that binding's client
//   hold       ──▶ a session's PUT and complete wait while a replace can be undone (`hold`/`release`)
//   exercise   ──▶ outbox `exercise`, ahead of every op ──▶ POST /v1/exercises (by id: a resend updates it); no gate (O1)
//   refusal    ──▶ a 4xx (422, 413, 409 after the merges, 404 …) keeps the op, with the attempt on its session (on the
//                  op for an exercise): that session's ops wait until Retry or an edit; other sessions' go (O2)
//
// Nothing here touches HealthKit; sessions aren't written to Health in v1.
import Foundation
import Observation
import OSLog
import SwiftData

@MainActor
@Observable
final class TrainSyncService {
    static let shared = TrainSyncService()

    private(set) var isOnline = true
    private(set) var pendingCount = 0
    private(set) var isFlushing = false
    /// Moves whenever an op or a refusal changes, so a view that asks `state(of:)` draws again. Not state: that's derived.
    private var outboxRevision = 0
    /// The latest completion the server answered, for the summary sheet.
    private(set) var lastCompletion: TrainSession?
    /// The last replay's `PUT`s and completions waited at this gate (consent, invite, the policy not known); they
    /// stay queued, in order (ADR 0008). Nil when they went, or none waited.
    private(set) var heldAt: UploadGate?
    /// Training logs (sessions, sets, body weight) are health data: every op asks this for its kind before it goes,
    /// and waits, never dropped (`OnboardingCoordinator.uploadGate(for: .train, write:)`, wired by ScreenModels). A
    /// `delete` asks for `.erasure`, which goes without a current consent. **Closed until the app connects it**;
    /// tests open it explicitly. Reads, exercises and plans (TrainLibrary) don't ask it.
    @ObservationIgnored var gate: @MainActor (UploadWrite) -> UploadGate? = { _ in .gate(.consentRequired) }
    /// Asks for the policy in force before a `PUT` waits for `policyUnknown` (`ConsentState.revalidate`).
    @ObservationIgnored var revalidatePolicy: (@MainActor () async throws -> Void)?
    /// `PendingTrainOp.account` for demo data's ops.
    nonisolated static let demoOwner = "demo"
    /// Whose ops the client in use now sends (`remote`): the signed-in account's ID, `demoOwner` with demo data,
    /// nil signed out. Read in the same main-actor step as `remote`, so an op only ever goes through its own
    /// binding's client.
    private let owner: @MainActor () -> String?

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
    /// Sessions whose uploads wait: a replace's undo window is open, so a quick Undo never reaches the server
    /// (ADR 0009, `SessionController.replace`). Their ops stay queued, in order; other sessions' go.
    private var holds: Set<UUID> = []
    private var flushAgain = false
    /// Which account (`accountChanged()`) and which store contents (`TrainStore.wipe()`) a replay works
    /// for: an answer that arrives after either moved is dropped. The wipe moves it at once, in the
    /// sign-out itself, before the app's account-change handler runs.
    struct Generation: Equatable {
        let account: Int
        let store: Int
    }

    private var accountCount = 0
    var generation: Generation { Generation(account: accountCount, store: store.epoch.current) }
    /// Finish waits this long for the replay, then says "will sync" (the replay goes on).
    private let finishWait: Duration
    /// Off in tests: they drive "offline" through the stub URLProtocol instead.
    private let monitorsNetwork: Bool
    private let connectivity: ConnectivityMonitor

    /// Conflict rounds per upload before the session is refused (O2).
    static let maxConflictRounds = 3

    /// What a `409` after the last merge round means (Details shows the request ID with it).
    static var conflictMessage: String {
        String(localized: "This workout changed on another device. Open it again to sync.")
    }

    /// The sessions started while the binding was demo's (`sessionStarting`), by id: what ending the demo discards
    /// (ADR 0019). Ids only, never a title, a time or a health value; pruned against the store. Kept in `defaults`;
    /// this copy is what's read, and it's observable (Profile's VoiceOver hint follows it with no fetch per render).
    private(set) var demoSessionIDs: [UUID] = []
    private let defaults: UserDefaults
    nonisolated static let demoSessionsKey = "train.demoSessions"
    /// Set once the first launch with the list has seeded it (`seedDemoSessions`), whatever it found.
    nonisolated static let demoSessionsSeededKey = "train.demoSessionsSeeded"
    /// Reads the store's sessions for the demo's list; tests make it throw.
    @ObservationIgnored var fetchSessions: @MainActor (TrainStore, FetchDescriptor<LocalSession>) throws -> [LocalSession]
        = { try $0.context.fetch($1) }

    /// `owner` goes with `remote`: by default both follow the live environment's account and Demo data switch.
    init(store: TrainStore? = nil, remote: (() -> TrainDataSource)? = nil, owner: (@MainActor () -> String?)? = nil,
         debounce: Duration = .seconds(2), finishWait: Duration = .seconds(10), monitorsNetwork: Bool = true,
         connectivity: ConnectivityMonitor? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        demoSessionIDs = (defaults.stringArray(forKey: Self.demoSessionsKey) ?? []).compactMap(UUID.init(uuidString:))
        self.connectivity = connectivity ?? .shared
        self.finishWait = finishWait
        self.store = store ?? .shared
        self.remoteProvider = remote ?? { TrainSource.current }
        self.owner = owner ?? {
            let env = AppEnvironment.live
            return env.isDemo ? Self.demoOwner : env.auth.accountID
        }
        self.debounce = debounce
        self.monitorsNetwork = monitorsNetwork
        pendingCount = self.store.pendingOps().count
        // By binding from the next step on: the default owner reads `AppEnvironment.live`, which `shared` mustn't
        // touch while it's being built (the live graph's sign-in wipe calls back into `shared`).
        Task { [weak self] in self?.refreshCount() }
        if monitorsNetwork { startMonitoring() }
    }

    private var remote: TrainDataSource { remoteProvider() }

    // MARK: changes

    /// The session's `PUT`s and completion wait (queued ones from earlier edits too) until `release`.
    func hold(_ sessionID: UUID) { holds.insert(sessionID) }

    /// The undo window is over (committed, undone or dropped). The caller queues the upload it wants, if any.
    func release(_ sessionID: UUID) { holds.remove(sessionID) }

    func isHeld(_ sessionID: UUID) -> Bool { holds.contains(sessionID) }

    /// After every set change: persist now, upload after a quiet 2 s. An edit clears a refusal (O2).
    func sessionChanged(_ s: LocalSession) {
        s.updatedAt = .now
        enqueuePut(for: s)
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
        enqueuePut(for: s)
        let owner = owner()
        if queues(s.id, for: owner) {
            store.enqueue(.complete, sessionID: s.id, bodyweightKg: bodyweightKg, account: owner)
        }
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
        stopReplay()
        holds = []
        lastCompletion = nil
        outboxRevision += 1
        // As in `init`: a launch wipe calls this while `AppEnvironment.live` is being built, and the default owner reads it.
        Task { [weak self] in self?.refreshCount() }
    }

    /// The replay and the 2 s wait stop, and the generation moves: an answer in flight is dropped before it touches a
    /// row. The ops stay queued and go at the next trigger.
    private func stopReplay() {
        accountCount += 1
        debounceTask?.cancel()
        debounceTask = nil
        replay?.cancel()
        replay = nil
        replayID = nil
        isFlushing = false
        flushAgain = false
        inFlightSeq = nil
    }

    // MARK: the demo's sessions (ADR 0019)

    private func setDemoSessionIDs(_ ids: [UUID]) {
        guard ids != demoSessionIDs else { return }
        demoSessionIDs = ids
        if ids.isEmpty {
            defaults.removeObject(forKey: Self.demoSessionsKey)
        } else {
            defaults.set(ids.map(\.uuidString), forKey: Self.demoSessionsKey)
        }
    }

    /// `TrainCoordinator`'s starts, before the new session's row is made: one started while the binding is demo's goes
    /// on the list, whatever happens to its ops later. A kill before the row is saved leaves an id the store doesn't
    /// have, which nothing counts and the next discard prunes; the other order could leave a demo session unlisted.
    func sessionStarting(_ id: UUID) {
        guard owner() == Self.demoOwner, !demoSessionIDs.contains(id) else { return }
        setDemoSessionIDs(demoSessionIDs + [id])
    }

    /// Whether any session is on the list (the launch sweep asks before it fetches anything; Profile's hint).
    var hasDemoSessions: Bool { !demoSessionIDs.isEmpty }

    /// Whether an op for session `id` is queued for, and sent by, `owner` (review R15). A session on the demo's list is
    /// the demo's whatever the switch says now: its ops are only ever bound to "demo", and with Demo data off none is
    /// queued or sent (one left open by a sweep that couldn't read the store waits for the next discard, never for an
    /// account). Other sessions follow the binding (an account's that went on during the demo: STATUS → Open, F1).
    private func queues(_ id: UUID, for owner: String?) -> Bool {
        owner == Self.demoOwner || !demoSessionIDs.contains(id)
    }

    /// The first launch of a build with the list, once (`demoSessionsSeededKey`). Workouts logged in the demo before it
    /// aren't on the list. With nobody signed in (`signedIn` also counts an account `auth.lastUserID` still names) the
    /// store holds no account's Train rows: sign-out and expiry wipe Train, and a failed wipe keeps the account's id. So
    /// every stored session is the demo's, Demo data on or not, and goes on the list; with Demo data off the same
    /// launch's sweep discards them without asking (ADR 0019's leftovers). Signed in, the account's are there too and
    /// can't be told apart: nothing is added (STATUS, Known issues). Done once whatever it found.
    ///
    /// That holds only while the defaults can be read: before the first unlock `auth.lastUserID` reads nil, and the
    /// Keychain session may be unreadable too, so "nobody signed in" could be an account whose rows are stored. Without
    /// protected data, or with memory in place of the store's file (what's in the file is out of reach), or a store that
    /// can't be read, nothing is seeded and the flag isn't set: a later launch decides (review R13).
    func seedDemoSessions(signedIn: Bool, protectedDataAvailable: Bool) {
        guard protectedDataAvailable, !store.lostItsFile, !defaults.bool(forKey: Self.demoSessionsSeededKey) else {
            return
        }
        if !signedIn {
            guard let stored = try? fetchSessions(store, FetchDescriptor<LocalSession>()) else { return }
            let ids = demoSessionIDs
            setDemoSessionIDs(ids + stored.map(\.id).filter { !ids.contains($0) })
        }
        defaults.set(true, forKey: Self.demoSessionsSeededKey)
    }

    /// The sessions on the list that the store has, in progress or finished: the list is never trusted on its own.
    /// Nothing is fetched while it's empty. Throws when the store can't be read (the discard then changes nothing).
    func fetchDemoSessions() throws -> [LocalSession] {
        let ids = demoSessionIDs
        guard !ids.isEmpty else { return [] }
        return try fetchSessions(store, FetchDescriptor<LocalSession>(predicate: #Predicate { ids.contains($0.id) }))
    }

    /// The demo ends (`TrainCoordinator.discardDemoWorkouts`, which fetched `sessions` and closed what showed them, and
    /// then takes the ids out of Train's library caches): they go, with their ops, and nothing is sent, not even a
    /// `DELETE` (their only other copy was on the demo's in-memory platform, which `AppState.reset` starts over). The
    /// replay stops first, so a demo answer in flight never touches a deleted row. Then the list keeps only the ids a
    /// fresh context on the store still finds: the file decides, not the main context, so a delete the store refused is
    /// tried again at the next launch. A store in memory in place of its file only drops what it deleted: those rows were
    /// made in this process, and what it doesn't find may still be in the file.
    func discardDemoSessions(_ sessions: [LocalSession]) {
        let ids = demoSessionIDs
        guard !ids.isEmpty else { return }
        stopReplay()
        let listed = Set(ids)
        let gone = Set(sessions.map(\.id)).intersection(listed)
        // One by one, so ops only inserted are found too (a batch delete skips them).
        for op in store.pendingOps() where gone.contains(op.sessionId) { store.context.delete(op) }
        for session in sessions where gone.contains(session.id) {
            // Read now: reading either list on a deleted row is a fatal error unless it was resolved before the delete.
            _ = (session.deletedSetIDs, session.deletedExerciseIDs)
            // Cascades to its exercises and sets.
            store.context.delete(session)
        }
        holds.subtract(gone)
        if let id = lastCompletion?.id, listed.contains(id) { lastCompletion = nil }
        store.save()
        if store.lostItsFile {
            setDemoSessionIDs(ids.filter { !gone.contains($0) })
        } else {
            let fresh = ModelContext(store.container)
            let kept = (try? fresh.fetch(FetchDescriptor<LocalSession>(predicate: #Predicate { ids.contains($0.id) })))
                .map { Set($0.map(\.id)) } ?? listed
            setDemoSessionIDs(ids.filter { kept.contains($0) })
        }
        refreshCount()
    }

    /// Discard (after confirmation): gone locally; a `DELETE` if the server has a copy.
    func discard(_ s: LocalSession) {
        // The copy is where its uploads went (`uploadedTo`), whatever the Demo data switch says now: the delete is
        // bound there, so A's session deleted while demo data shows goes to A's platform once demo is off.
        let id = s.id, uploaded = s.uploaded, copy = s.uploadedTo
        store.dropOps(for: id)
        store.delete(s)
        // Its own `put` and `complete` went with `dropOps`: sent after the delete, they'd bring the session back.
        if uploaded { store.enqueue(.delete, sessionID: id, account: copy) }
        refreshCount()
        Task { await flush() }
    }

    /// Demo data on or off (RyftApp): the count follows the binding in use. Off, demo's ops go: they could only ever
    /// reach the in-memory platform, which is gone with it.
    func demoModeChanged(_ on: Bool) {
        if !on { store.dropOps(account: Self.demoOwner) }
        refreshCount()
    }

    // MARK: custom exercises (O1)

    /// A custom exercise made here (`TrainLibrary.createExercise`): cached, so it can be logged at once, offline too,
    /// and its `POST /v1/exercises` queued ahead of every op; then the queue goes. A session's `PUT` that uses it is
    /// refused (`422`) until the platform has it. The op sends the cached row as it is when it goes, and the answer
    /// replaces the row; a resend updates the same id (API.md). It's no data write (ADR 0008 §1), so no gate holds it,
    /// but it's bound to its account like every op. One op per exercise and binding: creating it again clears a
    /// refusal. Returns the replay to wait for (nil offline).
    @discardableResult
    func queueExercise(_ exercise: Exercise) -> Task<Void, Never>? {
        let owner = owner(), id = exercise.id
        store.cache(exercises: [exercise])
        let queued = store.pendingOps().first { $0.kind == .exercise && $0.sessionId == id && Self.belongs($0, to: owner) }
        if let queued {
            queued.lastAttemptData = nil
            store.save()
        } else {
            store.enqueueAhead(.exercise, subject: id, account: owner)
        }
        refreshCount()
        return startReplay()
    }

    // MARK: refusals (O2)

    /// Retry, from "Couldn't sync": the session's refusal goes, and so does that of every custom exercise it uses (a
    /// `PUT` is refused while the platform lacks one), and its ops go again, in their order.
    func retry(sessionID: UUID) async {
        guard let s = store.session(id: sessionID) else { return }
        s.lastAttemptData = nil
        let used = Set(s.exercises.map(\.exerciseId))
        for op in store.pendingOps() where op.kind == .exercise && used.contains(op.sessionId) {
            op.lastAttemptData = nil
        }
        store.save()
        outboxRevision += 1
        await flush()
    }

    /// Where session `id` is on its way to the platform, for Train's summary and history: derived from the outbox and
    /// the session each time it's asked, never stored. `failed`: the platform refused it (Retry, Details with the
    /// request ID). `confirmed`: nothing of it waits, or the store doesn't have it (a session only the platform has).
    /// A session finished here whose ops a build before O2 dropped has none left: it reads `queued`, as "Will sync" did.
    func state(of id: UUID) -> UploadState {
        _ = outboxRevision // drawn again when an op or a refusal changes
        guard let s = store.session(id: id) else { return .confirmed }
        if let attempt = s.lastAttempt, attempt.isRefusal { return .failed(attempt) }
        let ops = store.pendingOps().filter { $0.sessionId == id }
        guard !ops.isEmpty || s.pendingCompletion else { return .confirmed }
        if let inFlightSeq, ops.contains(where: { $0.seq == inFlightSeq }) { return .pending(.inFlight) }
        if !isOnline { return .pending(.offline) }
        // Only the policy version is missing, and asking for it is the replay's first step: not a gate the user passes.
        if let hold = gate(.data), hold != .policyUnknown { return .pending(.gated) }
        return .pending(.queued)
    }

    private func enqueuePut(for s: LocalSession) {
        // A fresh document: what was refused was an earlier one (O2), so this one goes. Saved with the op below.
        if s.lastAttemptData != nil {
            s.lastAttemptData = nil
            outboxRevision += 1
        }
        let id = s.id
        // One queued PUT per session and binding is enough: it sends the document as it is then.
        let owner = owner()
        guard queues(id, for: owner) else {
            store.save()
            return
        }
        let last = store.pendingOps().last { $0.sessionId == id }
        if let last, last.kind == .put, last.seq != inFlightSeq, Self.belongs(last, to: owner) {
            store.save()
            return
        }
        store.enqueue(.put, sessionID: id, account: owner)
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

    /// Starts the replay, or has the running one go round once more; nil offline, or while the gate holds every op.
    private func startReplay() -> Task<Void, Never>? {
        guard !monitorsNetwork || connectivity.isOnline else { return nil }
        // Consent first: while both kinds wait, nothing starts and the ops stay queued, unless a custom exercise is
        // queued (no data write, ADR 0008 §1). A policy not known right now is asked for before the first `PUT`; a
        // `delete` goes without a current consent.
        let data = gate(.data)
        if let data, data != .policyUnknown, gate(.erasure) != nil, !hasUngatedOp {
            heldAt = data
            return nil
        }
        if let replay {
            flushAgain = true
            return replay
        }
        let generation = generation, id = UUID()
        // Its own task: cancelling the caller (the debounce, Finish's view) can't cancel a PUT; only
        // `accountChanged()` does.
        let task = Task { [weak self] in
            guard let self else { return }
            // At most once per replay, when the first `PUT` finds the policy unknown.
            var revalidated = false
            repeat {
                flushAgain = false
                await drain(generation, revalidated: &revalidated)
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

    /// Sends the queued ops in order. Passed over for this pass, and kept: another binding's ops (never sent through
    /// this client), the ops the gate holds, and refused ones with their session's (O2). Once a `PUT` or completion
    /// waits at the gate, every later one does too (their order stays); a `delete` or a custom exercise may still go.
    private func drain(_ generation: Generation, revalidated: inout Bool) async {
        var passedOver = Set<Int>()
        var held: UploadGate?
        defer { if generation == self.generation { heldAt = held } }
        while generation == self.generation, let op = store.pendingOps().first(where: { !passedOver.contains($0.seq) }) {
            // Refused: kept, and passed over until Retry or an edit; so are the session's ops after it.
            if isRefused(op) {
                passedOver.insert(op.seq)
                continue
            }
            // A custom exercise is no data write (ADR 0008 §1): neither the gate nor an undo window holds it.
            if let write = Self.write(of: op) {
                // Its undo window is open: this session's ops wait; the ones after them (other sessions') may go.
                if write == .data, holds.contains(op.sessionId) {
                    passedOver.insert(op.seq)
                    continue
                }
                if write == .data, held != nil {
                    passedOver.insert(op.seq)
                    continue
                }
                // Asked before every op: consent withdrawn mid-queue holds the next `PUT`, which stays queued.
                let hold = gate(write)
                if hold == .policyUnknown, write == .data, !revalidated {
                    revalidated = true
                    try? await revalidatePolicy?()
                    continue // asked again: the account, the binding and the policy may have moved meanwhile
                }
                if let hold {
                    if write == .data { held = hold }
                    passedOver.insert(op.seq)
                    continue
                }
            }
            // The binding is checked and the client read in the same step: an op goes only through its own. One for a
            // session on the demo's list goes only through the demo's, whatever it's bound to (an op queued before ops
            // had an owner, review R15).
            let owner = owner()
            guard Self.belongs(op, to: owner), queues(op.sessionId, for: owner) else {
                passedOver.insert(op.seq)
                continue
            }
            let client = remote
            // What a `PUT` sends is the session as it is when it goes: an edit while it's out makes a refusal stale.
            let sentRevision = op.kind == .put ? store.session(id: op.sessionId)?.updatedAt : nil
            inFlightSeq = op.seq
            defer { inFlightSeq = nil }
            let signpost = Self.signposter.beginInterval("train-op", id: Self.signposter.makeSignpostID(),
                                                         "\(op.kindRaw, privacy: .public)")
            defer { Self.signposter.endInterval("train-op", signpost) }
            do {
                try await perform(op, generation, client, as: owner)
                // Another account meanwhile: its queue and sessions aren't this replay's.
                guard generation == self.generation else { return }
                store.dequeue(op)
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
                refreshCount()
                return
            } catch {
                let attempt = Self.attempt(for: op, error)
                // Not the platform's refusal (a transient failure this service doesn't know as one): kept for the next
                // replay, unchanged.
                guard attempt.isRefusal else {
                    refreshCount()
                    return
                }
                isOnline = true
                if op.kind == .put, store.session(id: op.sessionId)?.updatedAt != sentRevision {
                    // Edited while the request was out: the refusal was for the older document. The same op goes again
                    // now, with the newer one, still ahead of the session's later ops.
                    continue
                }
                refuse(op, attempt)
                passedOver.insert(op.seq)
            }
            refreshCount()
        }
    }

    /// `nil`: no gate asks for it (a custom exercise).
    private static func write(of op: PendingTrainOp) -> UploadWrite? {
        switch op.kind {
        case .put, .complete: return .data
        case .delete: return .erasure
        case .exercise: return nil
        }
    }

    /// A custom exercise is queued that no refusal holds: the replay starts for it even while the gate holds the rest.
    private var hasUngatedOp: Bool {
        store.pendingOps().contains { $0.kind == .exercise && $0.lastAttempt?.isRefusal != true }
    }

    /// Refused and not cleared since (O2): an exercise's op by its own attempt, a session's `PUT` and completion by the
    /// session's. A `delete` is never kept refused (`refuse`).
    private func isRefused(_ op: PendingTrainOp) -> Bool {
        switch op.kind {
        case .exercise: return op.lastAttempt?.isRefusal == true
        case .put, .complete: return store.session(id: op.sessionId)?.lastAttempt?.isRefusal == true
        case .delete: return false
        }
    }

    /// What Details shows of the failure: status, code, request ID and time, never a body.
    private static func attempt(for op: PendingTrainOp, _ error: Error) -> UploadAttempt {
        let api = error as? APIError
        let request: UploadAttempt.Request = switch op.kind {
        case .put: .put
        case .complete: .complete
        case .delete: .delete
        case .exercise: .create
        }
        return UploadAttempt(at: .now, request: request, status: api?.status, code: api?.code?.rawValue,
                             requestID: api?.requestID, kind: FailureKind.of(error))
    }

    /// The platform refused `op` (API.md → Errors: sent again unchanged, it fails the same way). It stays queued, never
    /// dropped: the attempt goes on its session, or on the op for a custom exercise, which has none. A `DELETE` is the
    /// exception, as before O2: its session is gone, so nothing could show it or send it again (a `404` is success).
    /// Status and request ID are logged, never the message: the platform's can quote a value.
    private func refuse(_ op: PendingTrainOp, _ attempt: UploadAttempt) {
        let status = attempt.status ?? 0, requestID = attempt.requestID ?? "-"
        TrainStore.log.error("Train \(op.kindRaw, privacy: .public) refused: \(status, privacy: .public) \(requestID, privacy: .public)")
        switch op.kind {
        case .delete:
            store.dequeue(op)
        case .exercise:
            op.lastAttempt = attempt
            store.save()
        case .put, .complete:
            // Read again: a discard while the request was out took the session, and its ops with it.
            guard let s = store.session(id: op.sessionId) else { return }
            s.lastAttempt = attempt
            store.save()
        }
        outboxRevision += 1
    }

    /// Whether `op` goes through the client whose binding is `owner` (an account's ID, `demoOwner`, nil signed out).
    /// An op queued before ops had an owner is the signed-in account's: demo's client never sends it.
    static func belongs(_ op: PendingTrainOp, to owner: String?) -> Bool {
        guard let account = op.account else { return owner != demoOwner }
        return account == owner
    }

    static func isRetryable(_ error: APIError) -> Bool {
        switch error {
        case .transport, .notConfigured, .signedOut: return true
        // A gate (invite, consent) is passed later: keep the op for then.
        case .http(let code, _, _, let gate, _): return code == 401 || code == 408 || code == 429 || code >= 500
            || (code == 403 && gate != nil)
        }
    }

    /// `owner`: the binding `remote` belongs to.
    private func perform(_ op: PendingTrainOp, _ generation: Generation, _ remote: TrainDataSource,
                         as owner: String?) async throws {
        switch op.kind {
        case .put:
            guard let s = store.session(id: op.sessionId) else { return } // discarded meanwhile
            try await put(s, generation, remote, as: owner)
        case .complete:
            guard let s = store.session(id: op.sessionId) else { return }
            // `ended_at` from here: the queue may replay this long after the workout.
            let done = try await remote.completeSession(id: s.id, SessionComplete(bodyweightKg: op.bodyweightKg,
                                                                                endedAt: s.endedAt))
            // Another account meanwhile: the session may be wiped, and the answer isn't theirs.
            guard generation == self.generation else { throw CancellationError() }
            // Discarded meanwhile (its ops went with it): nothing to write, and its rows mustn't be read.
            guard store.session(id: op.sessionId) != nil else { return }
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
        case .exercise:
            // Not cached any more (nothing removes a custom exercise but a wipe, which takes the op too): nothing to send.
            guard let exercise = store.exercise(id: op.sessionId) else { return }
            let saved = try await remote.createExercise(exercise)
            guard generation == self.generation else { throw CancellationError() }
            // The answer replaces the cached row (the library reads it again when the replay ends).
            store.cache(exercises: [saved])
        }
    }

    private func put(_ s: LocalSession, _ generation: Generation, _ remote: TrainDataSource,
                     as owner: String?) async throws {
        var doc = s.wire
        var conflictID: String?
        for _ in 0..<Self.maxConflictRounds {
            let result = try await remote.putSession(doc)
            guard generation == self.generation else { throw CancellationError() }
            // Discarded meanwhile (its ops went with it): nothing to write, and its rows mustn't be read.
            guard store.session(id: s.id) != nil else { return }
            switch result {
            case .saved:
                s.uploaded = true
                s.uploadedTo = owner
                store.save()
                return
            case .conflict(let server, let requestID):
                conflictID = requestID
                s.uploaded = true
                s.uploadedTo = owner
                let merged = SessionMerge.merge(local: s.wire, server: server, deletedSetIDs: Set(s.deletedSetIDs),
                                                deletedExerciseIDs: Set(s.deletedExerciseIDs))
                s.apply(merged, names: store.exercise(id:), in: store.context)
                store.save()
                // Replaced meanwhile and still undoable: the next round would send that. The op waits, queued.
                guard !holds.contains(s.id) else { throw CancellationError() }
                doc = s.wire
            }
        }
        // Still newer there after every round: refused, with the last answer's request ID (O2).
        throw APIError.http(409, Self.conflictMessage, requestID: conflictID)
    }

    /// The ops the client in use can send: another binding's (demo's after demo data is switched off, the
    /// account's while it's on) don't show as waiting here.
    private func refreshCount() {
        let owner = owner()
        pendingCount = store.pendingOps().filter { Self.belongs($0, to: owner) && queues($0.sessionId, for: owner) }.count
    }

    /// One interval per op (`train-op`, its kind as the message): Instruments, or `log show --signpost`.
    private static let signposter = OSSignposter(subsystem: "dev.timkrebs.ryft", category: "uploads")

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
