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
//   exercise   ──▶ outbox `exercise`, ahead of every op ──▶ POST /v1/exercises (by id: a resend updates it); no gate;
//                  a session that uses it waits while it's queued or refused (O1, ADR 0022 §7)
//   refusal    ──▶ any 4xx but 401, 403, 408, 426, 429 (409 after the merges; 404 only on complete), or a body this
//                  build can't encode: the op stays, with the attempt on its session (on the op for an exercise); that
//                  session's ops wait until Retry or an edit; other sessions' go. Every 403, a 404 on PUT/POST, 426,
//                  408, 429 and 5xx hold (an answered hold of an exercise passes it over); a 2xx the app can't read is
//                  delivered (O2, ADR 0022 §1)
//   completed  ──▶ the answer is applied, but only what the platform owns while the session's PUT is refused or queued
//                  (its copy is older: ADR 0022 §5)
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
    /// Moves whenever an op or a refusal changes (`refreshCount`, the one place), so a view that asks `state(of:)` draws
    /// again. Not state: that's derived.
    private var outboxRevision = 0
    /// Edits per session (`enqueuePut`), in memory: a refusal of a `PUT` sent before the latest edit answered an older
    /// document, so it isn't kept (ADR 0022 §4).
    private var putEdits: [UUID: Int] = [:]
    /// When a refusal happened (`UploadAttempt.at`).
    private let clock: AppClock
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

    /// Whose requests go now: the generation and the binding (`owner`). A caller that waits between reading its client
    /// and sending (a plan save waiting for its exercises) compares this before and after, so nothing read for one
    /// account or for demo goes as another's.
    struct Binding: Equatable {
        let generation: Generation
        let owner: String?
    }

    var binding: Binding { Binding(generation: generation, owner: owner()) }

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
         connectivity: ConnectivityMonitor? = nil, defaults: UserDefaults = .standard, clock: AppClock = SystemClock()) {
        self.defaults = defaults
        self.clock = clock
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
    /// `bodyweightKg` goes on the session too, as the platform's completion stores it: Retry queues a `complete` with
    /// it when the first one is in flight or gone (`requeueUpload`).
    @discardableResult
    func finish(_ s: LocalSession, bodyweightKg: Double? = nil) async -> TrainSession? {
        let now = Date.now
        s.status = .completed
        s.endedAt = now
        s.updatedAt = now
        s.volumeKg = s.liveVolumeKg
        if let bodyweightKg { s.bodyweightKg = bodyweightKg }
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
        putEdits = [:]
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
    /// and its `POST /v1/exercises` queued ahead of every op; then the queue goes. A session that uses it doesn't go
    /// while the op is queued or refused (the platform would refuse its `PUT`). The op sends the cached row as it is
    /// when it goes, and the answer replaces the row; a resend updates the same id (API.md). It's no data write (ADR 0008
    /// §1), so no gate holds it, but it's bound to its account like every op. One op per exercise and binding: creating
    /// it again clears a refusal (ADR 0022 §7). Returns the replay to wait for (nil offline).
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

    /// For a plan save (ADR 0022 §7): waits until none of `ids` has an `exercise` op of this binding's that can still
    /// go (it went, was refused, or is gone), at most `limit` on the clock. At once when none is queued, offline, or
    /// when nothing may start; the plan then goes as it always did. Whichever ends the wait first (the ops, the replay's
    /// end, the cap, or the caller's cancellation), the waiter and its cap go with it.
    func exercisesSent(_ ids: Set<UUID>, upTo limit: Duration) async {
        let owner = owner()
        guard !ids.isEmpty, Self.awaitsExercise(ids, owner: owner, in: store.pendingOps()),
              let replay = startReplay() else { return }
        let wakeup = Wakeup()
        exerciseWaiters.append(ExerciseWaiter(ids: ids, owner: owner, wakeup: wakeup))
        let clock = clock
        let replayEnded = Task {
            await replay.value
            wakeup.fire()
        }
        let cap = Task {
            try? await clock.sleep(for: limit)
            wakeup.fire()
        }
        await withTaskCancellationHandler {
            await wakeup.wait()
        } onCancel: {
            wakeup.fire()
        }
        cap.cancel()
        replayEnded.cancel()
        exerciseWaiters.removeAll { $0.wakeup === wakeup }
    }

    /// A plan save waiting for exercise ops (`exercisesSent`): woken by `refreshCount` once they can't go any more.
    private struct ExerciseWaiter {
        let ids: Set<UUID>
        let owner: String?
        let wakeup: Wakeup
    }

    private var exerciseWaiters: [ExerciseWaiter] = []

    /// Plan saves waiting for their exercises right now (tests: none is left behind).
    var exerciseWaiterCount: Int { exerciseWaiters.count }

    private static func awaitsExercise(_ ids: Set<UUID>, owner: String?, in queue: [PendingTrainOp]) -> Bool {
        queue.contains {
            $0.kind == .exercise && ids.contains($0.sessionId) && belongs($0, to: owner) && $0.lastAttempt?.isRefusal != true
        }
    }

    // MARK: refusals (ADR 0022)

    /// Retry, from "Couldn't sync". The session's refusal goes, and so does that of every custom exercise it uses (a
    /// `PUT` is refused while the platform lacks one). A custom exercise it uses that has no op for this binding (one
    /// demo's binding left, or a build before O1 tried once) is queued again, ahead. Then the session's `PUT` and, when
    /// it's still to be completed, its `complete` with the body weight given at Finish go to the end of the queue,
    /// behind the exercises: what a `404` on `complete` or a refused `PUT` left (and a session an earlier build dropped).
    func retry(sessionID: UUID) async {
        guard let s = store.session(id: sessionID) else { return }
        let owner = owner()
        s.lastAttemptData = nil
        let used = Set(s.exercises.map(\.exerciseId))
        var queued = Set<UUID>()
        for op in store.pendingOps() where op.kind == .exercise && used.contains(op.sessionId) {
            op.lastAttemptData = nil
            if Self.belongs(op, to: owner) { queued.insert(op.sessionId) }
        }
        if queues(s.id, for: owner) {
            for id in used.subtracting(queued).sorted(by: { $0.uuidString < $1.uuidString })
                where store.exercise(id: id)?.isCustom == true {
                store.enqueueAhead(.exercise, subject: id, account: owner)
            }
            requeueUpload(of: s, as: owner)
        }
        store.save()
        refreshCount()
        await flush()
    }

    /// Where session `id` is on its way to the platform, for Train's summary and history: derived from the outbox and
    /// the session each time it's asked, never stored (ADR 0022 §3). `failed`: the platform refused it, or a custom
    /// exercise it uses (Retry, Details with the request ID). `confirmed`: nothing of it waits, or the store doesn't have
    /// it (a session only the platform has). A session finished here whose ops a build before O2 dropped has none left:
    /// it reads `queued`, as "Will sync" did, until O1b queues them again. One fetch of the queue per call.
    func state(of id: UUID) -> UploadState {
        _ = outboxRevision // drawn again when an op or a refusal changes (`refreshCount`)
        guard let s = store.session(id: id) else { return .confirmed }
        if let attempt = s.lastAttempt, attempt.isRefusal { return .failed(attempt) }
        let queue = store.pendingOps()
        let blocker = blockingExercise(for: s, owner: owner(), in: queue)
        if let attempt = blocker?.lastAttempt, attempt.isRefusal { return .failed(attempt) }
        let ops = queue.filter { $0.sessionId == id && $0.kind != nil } + (blocker.map { [$0] } ?? [])
        guard !ops.isEmpty || s.pendingCompletion else { return .confirmed }
        if let inFlightSeq, ops.contains(where: { $0.seq == inFlightSeq }) { return .pending(.inFlight) }
        if !isOnline { return .pending(.offline) }
        // Only the policy version is missing, and asking for it is the replay's first step: not a gate the user passes.
        if let hold = gate(.data), hold != .policyUnknown { return .pending(.gated) }
        return .pending(.queued)
    }

    /// The session's `PUT` and, while it's to be completed, its `complete` (with the body weight its last one had, else
    /// the one Finish stored on the session), at the end of the queue for `owner`. The ones queued for it before go,
    /// except one in flight.
    private func requeueUpload(of s: LocalSession, as owner: String?) {
        let mine = store.pendingOps().filter {
            $0.sessionId == s.id && ($0.kind == .put || $0.kind == .complete) && Self.belongs($0, to: owner)
                && $0.seq != inFlightSeq
        }
        let bodyweight = mine.last { $0.kind == .complete }?.bodyweightKg ?? s.bodyweightKg
        for op in mine { store.context.delete(op) }
        store.save()
        store.enqueue(.put, sessionID: s.id, account: owner)
        if s.pendingCompletion { store.enqueue(.complete, sessionID: s.id, bodyweightKg: bodyweight, account: owner) }
    }

    private func enqueuePut(for s: LocalSession) {
        let id = s.id
        // An edit. A refusal answered an earlier document (O2), so this one goes; and a `PUT` in flight now answers a
        // stale one (`drain`). Saved with the op below.
        let cleared = s.lastAttemptData != nil
        s.lastAttemptData = nil
        putEdits[id, default: 0] += 1
        // One queued PUT per session and binding is enough: it sends the document as it is then.
        let owner = owner()
        guard queues(id, for: owner) else {
            store.save()
            if cleared { refreshCount() }
            return
        }
        let last = store.pendingOps().last { $0.sessionId == id }
        if let last, last.kind == .put, last.seq != inFlightSeq, Self.belongs(last, to: owner) {
            store.save()
            if cleared { refreshCount() }
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
    /// this client), the ops the gate holds, a kind this build doesn't know, refused ones (ADR 0022), and a session's
    /// ops while a custom exercise it uses is still queued or refused. Once one of a session's ops waits, its later ones
    /// do too, and once a `PUT` or completion waits at the gate, every later one does (their order stays); a `delete` or
    /// a custom exercise may still go.
    private func drain(_ generation: Generation, revalidated: inout Bool) async {
        var passedOver = Set<Int>()
        // Sessions with an op passed over in this pass: their later ops wait too (a `complete` never overtakes its
        // `PUT`). A refused op doesn't add its session: `isRefused` decides for each of its ops (ADR 0022 §5).
        var waiting = Set<UUID>()
        var held: UploadGate?
        defer { if generation == self.generation { heldAt = held } }
        while generation == self.generation {
            let queue = store.pendingOps()
            guard let op = queue.first(where: { !passedOver.contains($0.seq) }) else { break }
            // A kind a later build queued: kept, never sent and never read as another kind (ADR 0022 §8).
            guard let kind = op.kind else {
                passedOver.insert(op.seq)
                continue
            }
            let writesSession = kind == .put || kind == .complete
            if writesSession, waiting.contains(op.sessionId) {
                passedOver.insert(op.seq)
                continue
            }
            // Refused: kept, and passed over until Retry or an edit.
            if isRefused(op) {
                passedOver.insert(op.seq)
                continue
            }
            if let write = Self.write(of: kind), let hold = await holdsBack(op, write, held: held, revalidated: &revalidated) {
                if case .gate(let closed) = hold { held = closed }
                if hold != .askedAgain {
                    passedOver.insert(op.seq)
                    if writesSession { waiting.insert(op.sessionId) }
                }
                continue
            }
            // The binding is checked and the client read in the same step: an op goes only through its own. One for a
            // session on the demo's list goes only through the demo's, whatever it's bound to (an op queued before ops
            // had an owner, review R15).
            let owner = owner()
            guard Self.belongs(op, to: owner), queues(op.sessionId, for: owner) else {
                passedOver.insert(op.seq)
                if writesSession { waiting.insert(op.sessionId) }
                continue
            }
            // A custom exercise the session uses is still queued, or was refused: its `PUT` would be refused too (`422`).
            if writesSession, let s = store.session(id: op.sessionId),
               blockingExercise(for: s, owner: owner, in: queue) != nil {
                passedOver.insert(op.seq)
                waiting.insert(op.sessionId)
                continue
            }
            let client = remote
            // What a `PUT` sends is the session as it is when it goes: an edit while it's out makes a refusal stale.
            let sentEdit = kind == .put ? putEdits[op.sessionId] : nil
            inFlightSeq = op.seq
            defer { inFlightSeq = nil }
            let signpost = Self.signposter.beginInterval("train-op", id: Self.signposter.makeSignpostID(),
                                                         "\(op.kindRaw, privacy: .public)")
            defer { Self.signposter.endInterval("train-op", signpost) }
            do {
                try await perform(op, kind, generation, client, as: owner)
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
            } catch is PutQueuedAhead {
                // `complete` found no such session there: its `PUT` was queued ahead of it and goes first, now.
                isOnline = true
                refreshCount()
                continue
            } catch {
                switch Self.disposition(of: kind, error, at: clock.now()) {
                case .delivered:
                    delivered(op, kind, as: owner)
                    isOnline = true
                case .hold:
                    // A custom exercise the platform answered without taking (a `5xx`, a `403`, a `404`): passed over
                    // for this pass, so other sessions' ops still go. The sessions that use it wait for it
                    // (`blockingExercise`), and the next trigger sends it again. Not after a `429`: nothing more goes
                    // before the platform says so.
                    if kind == .exercise, let status = (error as? APIError)?.status, status != 429 {
                        isOnline = true
                        passedOver.insert(op.seq)
                        refreshCount()
                        continue
                    }
                    // Offline, signed out, a gate or any `403`, the platform busy or not there: keep the queue as is.
                    if case .transport? = error as? APIError { isOnline = false }
                    refreshCount()
                    return
                case .refused(let attempt):
                    isOnline = true
                    if kind == .put, putEdits[op.sessionId] != sentEdit {
                        // Edited while the request was out: the refusal was for the older document. The same op goes
                        // again now, with the newer one, still ahead of the session's later ops (ADR 0022 §4).
                        refreshCount()
                        continue
                    }
                    refuse(op, kind, attempt)
                    passedOver.insert(op.seq)
                }
            }
            refreshCount()
        }
    }

    /// Why a data write or erasure waits this pass, if it does: its undo window, the gate, or a gate an earlier op of
    /// this pass waited at. `askedAgain`: the policy in force was asked for (once per replay); look at the queue again.
    private enum HoldBack: Equatable {
        case undoWindow, gate(UploadGate), heldBefore, askedAgain
    }

    private func holdsBack(_ op: PendingTrainOp, _ write: UploadWrite, held: UploadGate?,
                           revalidated: inout Bool) async -> HoldBack? {
        // Its undo window is open: this session's ops wait; the ones after them (other sessions') may go.
        if write == .data, holds.contains(op.sessionId) { return .undoWindow }
        if write == .data, held != nil { return .heldBefore }
        // Asked before every op: consent withdrawn mid-queue holds the next `PUT`, which stays queued.
        let hold = gate(write)
        if hold == .policyUnknown, write == .data, !revalidated {
            revalidated = true
            try? await revalidatePolicy?()
            return .askedAgain // the account, the binding and the policy may have moved meanwhile
        }
        guard let hold else { return nil }
        return write == .data ? .gate(hold) : .heldBefore
    }

    /// `nil`: no gate asks for it (a custom exercise, ADR 0008 §1).
    private static func write(of kind: PendingTrainOp.Kind) -> UploadWrite? {
        switch kind {
        case .put, .complete: return .data
        case .delete: return .erasure
        case .exercise: return nil
        }
    }

    /// A custom exercise is queued that no refusal holds: the replay starts for it even while the gate holds the rest.
    private var hasUngatedOp: Bool {
        store.pendingOps().contains { $0.kind == .exercise && $0.lastAttempt?.isRefusal != true }
    }

    /// Refused and not cleared since: an exercise's op by its own attempt, a session's `PUT` and completion by the
    /// session's. A refused `PUT` of a session the platform already has doesn't hold its completion: the platform's copy
    /// is completed and scored, and a later `PUT` replaces the session whole (ADR 0022 §5). A `delete` is never kept
    /// refused (`refuse`).
    private func isRefused(_ op: PendingTrainOp) -> Bool {
        switch op.kind {
        case .exercise?:
            return op.lastAttempt?.isRefusal == true
        case .put?:
            return store.session(id: op.sessionId)?.lastAttempt?.isRefusal == true
        case .complete?:
            guard let s = store.session(id: op.sessionId), let attempt = s.lastAttempt, attempt.isRefusal else {
                return false
            }
            return !(attempt.request == .put && s.uploaded)
        case .delete?, nil:
            return false
        }
    }

    /// A completion's answer is the platform's copy as its last `PUT` left it. It's older than this one while a `PUT` of
    /// the session is refused (the attempt's request) or queued, in any binding: then the answer brings only what the
    /// platform owns (ADR 0022 §5).
    private func keepsLocalDocument(_ s: LocalSession) -> Bool {
        s.lastAttempt?.request == .put
            || store.pendingOps().contains { $0.sessionId == s.id && $0.kind == .put }
    }

    /// The first of `owner`'s queued `exercise` ops, refused or not, for a custom exercise `s` uses (ADR 0022 §7).
    private func blockingExercise(for s: LocalSession, owner: String?, in queue: [PendingTrainOp]) -> PendingTrainOp? {
        let exercises = queue.filter { $0.kind == .exercise && Self.belongs($0, to: owner) }
        guard !exercises.isEmpty else { return nil }
        let used = Set(s.exercises.map(\.exerciseId))
        return exercises.first { used.contains($0.sessionId) }
    }

    /// What a failed op's error means (ADR 0022 §1). `delivered`: a `2xx` this build couldn't read, so the platform
    /// took it. `refused`: `UploadAttempt.isRefusal`, the one definition (an `EncodingError` included). Everything else
    /// holds: the op stays, and the queue goes at the next trigger (offline, a sign-out, no server configured, a gate or
    /// any `403`, `404` on a `PUT` or `POST`, `426`, the platform busy).
    enum Disposition: Equatable {
        case delivered, hold, refused(UploadAttempt)
    }

    static func disposition(of kind: PendingTrainOp.Kind, _ error: Error, at date: Date) -> Disposition {
        let api = error as? APIError
        if api?.wasDelivered == true { return .delivered }
        // No server to send to: nothing went out, and nothing about the document is wrong.
        if case .notConfigured? = api { return .hold }
        let request: UploadAttempt.Request = switch kind {
        case .put: .put
        case .complete: .complete
        case .delete: .delete
        case .exercise: .create
        }
        let attempt = UploadAttempt(at: date, request: request, status: api?.status, code: api?.code?.rawValue,
                                    requestID: api?.requestID, kind: FailureKind.of(error))
        return attempt.isRefusal ? .refused(attempt) : .hold
    }

    /// A `2xx` whose body this build couldn't read: the platform took the request, so the op goes (ADR 0022 §1).
    private func delivered(_ op: PendingTrainOp, _ kind: PendingTrainOp.Kind, as owner: String?) {
        TrainStore.log.notice("Train \(op.kindRaw, privacy: .public) delivered; its answer couldn't be read")
        if let s = store.session(id: op.sessionId) {
            switch kind {
            case .put:
                s.uploaded = true
                s.uploadedTo = owner
            case .complete:
                s.pendingCompletion = false
            case .delete, .exercise:
                break
            }
        }
        store.dequeue(op)
    }

    /// The platform refused `op` (API.md → Errors: sent again unchanged, it fails the same way). It stays queued, never
    /// dropped: the attempt goes on its session, or on the op for a custom exercise, which has none. A `DELETE` is the
    /// exception (ADR 0022 §6): its session is gone, so nothing could show it or send it again. Status and request ID are
    /// logged, never the message: the platform's can quote a value.
    private func refuse(_ op: PendingTrainOp, _ kind: PendingTrainOp.Kind, _ attempt: UploadAttempt) {
        let status = attempt.status ?? 0, requestID = attempt.requestID ?? "-"
        TrainStore.log.error("Train \(op.kindRaw, privacy: .public) refused: \(status, privacy: .public) \(requestID, privacy: .public)")
        switch kind {
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
    }

    /// `complete` answered `404` for a session the platform never got: its `PUT` is queued ahead, and goes first.
    private struct PutQueuedAhead: Error {}

    /// Whether `op` goes through the client whose binding is `owner` (an account's ID, `demoOwner`, nil signed out).
    /// An op queued before ops had an owner is the signed-in account's: demo's client never sends it.
    static func belongs(_ op: PendingTrainOp, to owner: String?) -> Bool {
        guard let account = op.account else { return owner != demoOwner }
        return account == owner
    }

    /// `owner`: the binding `remote` belongs to.
    private func perform(_ op: PendingTrainOp, _ kind: PendingTrainOp.Kind, _ generation: Generation,
                         _ remote: TrainDataSource, as owner: String?) async throws {
        switch kind {
        case .put:
            guard let s = store.session(id: op.sessionId) else { return } // discarded meanwhile
            try await put(s, generation, remote, as: owner)
        case .complete:
            guard let s = store.session(id: op.sessionId) else { return }
            let done: TrainSession
            do {
                // `ended_at` from here: the queue may replay this long after the workout.
                done = try await remote.completeSession(id: s.id, SessionComplete(bodyweightKg: op.bodyweightKg,
                                                                                endedAt: s.endedAt))
            } catch let error as APIError where error.status == 409 || error.status == 404 {
                guard generation == self.generation else { throw CancellationError() }
                guard let s = store.session(id: op.sessionId) else { return }
                if error.status == 409 {
                    // Discarded on the platform (API.md: "treat it as discarded"): nothing to complete, and no
                    // refusal either (ADR 0022 §6). The op goes.
                    s.pendingCompletion = false
                    store.save()
                    return
                }
                // No such session there because its `PUT` never arrived (an earlier build dropped it): that goes
                // first. Once the platform has the session, a `404` is a refusal.
                guard !s.uploaded else { throw error }
                store.enqueueAhead(.put, subject: s.id, account: op.account)
                throw PutQueuedAhead()
            }
            // Another account meanwhile: the session may be wiped, and the answer isn't theirs.
            guard generation == self.generation else { throw CancellationError() }
            // Discarded meanwhile (its ops went with it): nothing to write, and its rows mustn't be read.
            guard store.session(id: op.sessionId) != nil else { return }
            s.pendingCompletion = false
            if keepsLocalDocument(s) {
                // The platform completed its own copy, older than this one: what's logged here (a refused `PUT`'s
                // sets, an edit queued behind) stays, and that `PUT` sends it later (ADR 0022 §5).
                s.applyPlatformFields(done)
            } else {
                s.apply(done, names: store.exercise(id:), in: store.context)
            }
            s.prs = done.prs
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
    /// Every change to an op or a refusal comes through here, once: the count, `state(of:)`'s readers (the revision),
    /// and a plan save waiting for its exercises. A kind this build doesn't know isn't counted.
    private func refreshCount() {
        let owner = owner(), queue = store.pendingOps()
        pendingCount = queue.filter { $0.kind != nil && Self.belongs($0, to: owner) && queues($0.sessionId, for: owner) }
            .count
        outboxRevision += 1
        exerciseWaiters.removeAll { waiter in
            guard !Self.awaitsExercise(waiter.ids, owner: waiter.owner, in: queue) else { return false }
            waiter.wakeup.fire()
            return true
        }
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

extension TrainSyncService {
    /// For previews and tests that don't send: demo data's binding, the mock platform, an open gate, no network monitor.
    static func preview(store: TrainStore) -> TrainSyncService {
        let sync = TrainSyncService(store: store, remote: { MockTrainSource.shared }, owner: { TrainSyncService.demoOwner },
                                    monitorsNetwork: false)
        sync.gate = { _ in nil }
        return sync
    }
}

/// Wakes one waiting task, once: from any thread, and also when it fires before the wait has begun (a cancellation).
private final class Wakeup: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let now = lock.withLock { () -> Bool in
                if fired { return true }
                self.continuation = continuation
                return false
            }
            if now { continuation.resume() }
        }
    }

    func fire() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            fired = true
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
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
