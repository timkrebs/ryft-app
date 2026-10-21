// Drains HealthKit into the backend. `SyncEngine` (an actor) does the work off the
// main actor: it reads a page, maps and encodes it, uploads it, and persists its
// anchor only after the page was accepted, reading the next page while this one
// uploads. `SyncService` is its observable face for the screens and the
// coordinator. Safe to call from foreground, background delivery and a
// BGAppRefreshTask alike; concurrent calls coalesce. Needs a signed-in caller: the
// SDK restores the session from the Keychain without UI, so background runs work too.
import Foundation
import GameplayKit
import Observation
import UIKit

@MainActor
@Observable
final class SyncService {
    /// Migration shim: the live graph's instance (`docs/ARCHITECTURE.md`).
    static let shared = SyncService(env: .live)

    /// Where the pipeline is (`SyncMachine`); `SyncCoordinator` drives the phases after the upload.
    private(set) var phase: SyncPhase = .idle
    @ObservationIgnored private var machine: GKTableMachine<SyncPhase>!
    /// Reading or uploading HealthKit data.
    var isSyncing: Bool { phase == .reading || phase == .uploading }
    private(set) var progress = ""
    private(set) var lastError: String?
    /// Status and request ID of `lastError`, for the inline message's Details.
    private(set) var lastErrorDetails: String?
    private(set) var lastUploaded = 0
    /// Days the last sync queued for rescoring (`days_touched`).
    private(set) var lastDaysTouched: [String] = []
    /// The engine's persisted state (phase, per-stream progress, last error).
    private(set) var engineState: SyncEngineState
    /// The last run stopped early on purpose (the first score came first, or the app went
    /// to the background); another follows.
    private(set) var hasBacklog = false
    /// HealthKit was locked (the phone is locked): the sync resumes after the unlock.
    private(set) var waitingForUnlock = false
    /// What the last upload's responses said about scoring: the days queued, how long it
    /// has recently taken (`SyncResponse.scoring`).
    private(set) var lastScoring: SyncScoring?
    /// Uploads wait behind this gate (no consent to the current policy, no beta access)
    /// until it's passed. Not an error: something the user does (`OnboardingCoordinator`).
    private(set) var pausedFor: APIErrorCode?
    /// Asked before every upload: the gate the account is behind, if any (RyftApp wires
    /// `OnboardingCoordinator.syncGate`). Nothing syncs before consent.
    @ObservationIgnored var gate: (@MainActor () -> APIErrorCode?)?
    /// Scoring usually finishes within a few seconds of an upload or recompute.
    static let rescoreDelay: Duration = .seconds(3)

    private let env: AppEnvironment
    private let engine: SyncEngine
    private var health: HealthStore { env.health }
    private var settings: Settings { env.settings }
    private var auth: AuthService { env.auth }
    private var inFlight: Task<[String], Error>?

    init(env: AppEnvironment) {
        self.env = env
        // Always the account's platform: demo mode never syncs.
        engine = SyncEngine(health: env.health, api: env.liveAPI, defaults: env.defaults)
        engineState = SyncEngineState.load(account: env.auth.accountID, defaults: env.defaults)
        machine = SyncMachine.make { [weak self] to, _ in self?.phase = to }
    }

    /// Moves the pipeline on (refused transitions are ignored: the table guards them).
    func advance(to next: SyncPhase) {
        machine.enter(next)
    }

    /// Another account: its own engine state. The previous account's upload is cancelled,
    /// and what it still reports is ignored (it can't restore wiped state either:
    /// `SyncEngineState.wipe`).
    func accountChanged() {
        inFlight?.cancel()
        engineState = SyncEngineState.load(account: auth.accountID, defaults: env.defaults)
        hasBacklog = false
        pausedFor = nil
        waitingForUnlock = false
    }

    /// The app went to the background: the page being uploaded finishes (its anchor
    /// committed), then the upload stops with a backlog.
    func stopAfterCurrentPage() async {
        await engine.requestStop()
    }

    /// What's left of the backfill, estimated (`BGProcessingTask` wants power above 10 MB);
    /// `nil` when nothing is left, signed out or in demo mode.
    var backlogBytes: Int? {
        guard auth.isSignedIn, !env.isDemo, hasBacklog || !engineState.backfillDone else { return nil }
        if engineState.backlogBytes > 0 { return engineState.backlogBytes }
        // Not measured yet (the first-score window just went up, or an older state): the
        // streams not yet backfilled, estimated.
        let remaining = health.streams.map(\.anchorID).filter { engineState.streams[$0]?.backfilled != true }
        return SyncEngineState.backlogEstimate(engineState.streams, remaining: remaining)
    }

    /// Uploads and keeps any error for the screens (Profile → Re-sync, tests).
    func syncNow() async {
        _ = try? await upload()
    }

    /// Uploads what HealthKit has that the platform hasn't and returns the days
    /// queued for rescoring. Concurrent calls share one upload. `SyncCoordinator`
    /// waits for scoring and refreshes afterwards.
    func upload() async throws -> [String] {
        // The coordinator's cancel (sign-out, background time over) reaches the upload.
        if let t = inFlight { return try await withTaskCancellationHandler { try await t.value } onCancel: { t.cancel() } }
        let t = Task { try await run() }
        inFlight = t
        defer { inFlight = nil }
        return try await withTaskCancellationHandler { try await t.value } onCancel: { t.cancel() }
    }

    private func run() async throws -> [String] {
        // Only this run's outcome counts: an early return (offline, gated) leaves no backlog.
        hasBacklog = false
        guard auth.isSignedIn, let account = auth.accountID else {
            lastError = APIError.signedOut.localizedDescription
            throw APIError.signedOut
        }
        guard settings.isConfigured else {
            lastError = APIError.notConfigured.localizedDescription
            throw APIError.notConfigured
        }
        // Offline: nothing to send; the anchors stay and the next reconnect resumes.
        guard env.connectivity.isOnline else {
            advance(to: .offline)
            return []
        }
        // Behind a gate nothing goes out; the anchors stay, so the pages follow once it's passed.
        if let gate = gate?() {
            pausedFor = gate
            return []
        }
        pausedFor = nil
        health.migrateLegacyAnchors()
        // The operator asked for one (`resync_requested_at`): this upload re-reads everything.
        if engineState.fullResyncRequested { resetForFullResync() }
        advance(to: .reading)
        lastError = nil
        lastErrorDetails = nil
        lastUploaded = 0
        hasBacklog = false
        waitingForUnlock = false
        defer { progress = "" }
        let context = SyncEngine.Context(account: account, deviceID: settings.deviceId,
                                         deviceName: UIDevice.current.name, appVersion: AppInfo.version,
                                         osVersion: AppInfo.osVersion, now: env.clock.now())
        do {
            let result = try await engine.run(context, gate: { [weak self] in await self?.gate?() }) { [weak self] event in
                await self?.apply(event, for: account)
            }
            lastDaysTouched = result.touched
            hasBacklog = result.backlog
            lastScoring = result.scoring
            if result.waitingForUnlock {
                // Locked phone: not a failure. Unlock (or the next app start) resumes it.
                waitingForUnlock = true
                advance(to: .idle)
                return result.touched
            }
            if let gate = result.pausedFor {
                // The platform refused at a gate (consent withdrawn, policy updated, access
                // revoked): pause, keep the uncommitted page's anchor, and let the gate prompt.
                pausedFor = gate
                advance(to: .idle)
                return result.touched
            }
            settings.lastSync = env.clock.now()
            return result.touched
        } catch is CancellationError {
            // Stopped from outside (sign-out, background time over): nothing to show.
            lastDaysTouched = await engine.touchedSoFar
            advance(to: .idle)
            throw CancellationError()
        } catch {
            lastError = error.localizedDescription
            lastErrorDetails = error.diagnosticDetails
            lastDaysTouched = await engine.touchedSoFar
            advance(to: .failed)
            throw error
        }
    }

    private func apply(_ event: SyncEngine.Event, for account: String) {
        // A run of the previous account: its news isn't this account's.
        guard auth.accountID == account else { return }
        switch event {
        case .reading(let stream):
            // A page read ahead while another uploads: the upload is what's happening.
            if phase != .uploading { advance(to: .reading) }
            progress = "Reading \(stream.anchorID)…"
        case .uploading(_, let records):
            advance(to: .uploading)
            progress = "Uploading \(records) records…"
        case .accepted(_, let response):
            lastUploaded += response.samples + response.sleep + response.workouts
        case .state(let state):
            engineState = state
        }
    }

    /// Forget anchors and re-upload the backfill window. Use after changing
    /// `backfillDays` or if the backend database was recreated. The engine counts it as a
    /// backfill again (the platform answers the overlap as duplicates).
    func fullResync() async {
        resetForFullResync()
        await syncNow()
    }

    /// `GET /v1/me/sync` → `resync_requested_at`: the operator found data missing. Newer
    /// than this account's last full re-sync: the next upload is one.
    func fullResyncRequested(at requested: Date) {
        guard let account = auth.accountID, requested > (engineState.lastFullResyncAt ?? .distantPast),
              !engineState.fullResyncRequested else { return }
        engineState.fullResyncRequested = true
        engineState.save(account: account, defaults: env.defaults)
    }

    private func resetForFullResync() {
        health.resetAnchors()
        guard let account = auth.accountID else { return }
        var state = SyncEngineState.load(account: account, defaults: env.defaults)
        // The whole window in one go: no first-score window that would leave a backlog.
        state.recentDone = true
        state.backfillDone = false
        state.streams = [:]
        state.fullResyncRequested = false
        state.lastFullResyncAt = env.clock.now()
        state.save(account: account, defaults: env.defaults)
        engineState = state
    }
}

// MARK: - engine

/// What the engine knows about an account's sync, persisted per account (UserDefaults,
/// like the anchors) so the screens and a relaunch see the same truth.
struct SyncEngineState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case idle
        /// The first sync's last `SyncEngine.recentDays` days, for a first score within a minute.
        case recent
        /// The backfill window, the first time through.
        case backfill
        /// Anchored: only what's new.
        case incremental
    }

    struct StreamProgress: Codable, Equatable, Sendable {
        /// Records sent and their encoded size.
        var records = 0
        var bytes = 0
        /// The oldest and newest record sent (anchored reads come in insertion order, not by date).
        var oldest: Date?
        var newest: Date?
        /// Drained once in the backfill.
        var backfilled = false
        var lastAccepted = 0
        var lastIgnored: IgnoredCounts?
    }

    var phase: Phase = .idle
    /// The stream being read (`HealthStream.anchorID`).
    var stream: String?
    var recentDone = false
    var backfillDone = false
    /// Per `HealthStream.anchorID`.
    var streams: [String: StreamProgress] = [:]
    var bytesUploaded = 0
    /// What's left of the backfill, estimated; 0 once it's done.
    var backlogBytes = 0
    /// HealthKit deletions kept for the platform (`PendingDeletions`), counted.
    var pendingDeletions = 0
    /// The last full re-sync (Profile, or the operator's request).
    var lastFullResyncAt: Date?
    /// `resync_requested_at` asked for one; the next upload does it.
    var fullResyncRequested = false
    var lastError: String?
    var lastRequestID: String?
    var updatedAt: Date?

    init() {}

    // A state saved by an older build decodes with the new fields at their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = (try? c.decodeIfPresent(Phase.self, forKey: .phase)) ?? .idle
        stream = try c.decodeIfPresent(String.self, forKey: .stream)
        recentDone = try c.decodeIfPresent(Bool.self, forKey: .recentDone) ?? false
        backfillDone = try c.decodeIfPresent(Bool.self, forKey: .backfillDone) ?? false
        streams = try c.decodeIfPresent([String: StreamProgress].self, forKey: .streams) ?? [:]
        bytesUploaded = try c.decodeIfPresent(Int.self, forKey: .bytesUploaded) ?? 0
        backlogBytes = try c.decodeIfPresent(Int.self, forKey: .backlogBytes) ?? 0
        pendingDeletions = try c.decodeIfPresent(Int.self, forKey: .pendingDeletions) ?? 0
        lastFullResyncAt = try c.decodeIfPresent(Date.self, forKey: .lastFullResyncAt)
        fullResyncRequested = try c.decodeIfPresent(Bool.self, forKey: .fullResyncRequested) ?? false
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        lastRequestID = try c.decodeIfPresent(String.self, forKey: .lastRequestID)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// Before a stream's backfill measured it, a 90-day stream is assumed this big (an
    /// Apple Watch's heart rate alone is ~25 MB of JSON): enough to wait for power.
    static let unmeasuredStreamBytes = 10_000_000

    /// The backfill still to go: each stream not yet drained, at the average size of the
    /// drained ones (or `unmeasuredStreamBytes` before any is).
    static func backlogEstimate(_ streams: [String: StreamProgress], remaining: [String]) -> Int {
        let done = streams.values.filter(\.backfilled)
        let average = done.isEmpty ? unmeasuredStreamBytes : done.map(\.bytes).reduce(0, +) / done.count
        return remaining.reduce(0) { total, id in total + max(0, average - (streams[id]?.bytes ?? 0)) }
    }

    static let keyPrefix = "sync.engine."

    /// How many wipes happened (kept beside the state, outside its prefix); a run saves
    /// only while it's the count it started with.
    static func wipes(_ defaults: UserDefaults) -> Int { defaults.integer(forKey: wipesKey) }
    private static let wipesKey = "syncEngineWipes"

    static func load(account: String?, defaults: UserDefaults) -> SyncEngineState {
        guard let account, let data = defaults.data(forKey: keyPrefix + account),
              let state = try? JSONDecoder().decode(SyncEngineState.self, from: data) else { return SyncEngineState() }
        return state
    }

    func save(account: String, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.keyPrefix + account) }
    }

    /// Log out, account deletion: every account's state goes with the anchors. A run still
    /// going (of the account that ended) can't save over it afterwards (`wipes`).
    static func wipe(defaults: UserDefaults) {
        defaults.set(wipes(defaults) + 1, forKey: wipesKey)
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(keyPrefix) || key.hasPrefix(PendingDeletions.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

/// HealthKit UUIDs deleted in Apple Health (`deletedObjects` of the anchored reads), per
/// account and stream. The platform can't take them yet (samples go up without their
/// UUID; `docs/API_REQUESTS.md`), so they're kept, bounded, until it can.
enum PendingDeletions {
    static let keyPrefix = "sync.deleted."
    /// Per stream; the oldest go first beyond it.
    static let limitPerStream = 2_000

    static func load(account: String, defaults: UserDefaults) -> [String: [String]] {
        (defaults.dictionary(forKey: keyPrefix + account) as? [String: [String]]) ?? [:]
    }

    /// Adds `ids` to the stream's list; returns the total kept for the account.
    @discardableResult
    static func add(_ ids: [UUID], stream: HealthStream, account: String, defaults: UserDefaults) -> Int {
        var all = load(account: account, defaults: defaults)
        let list = (all[stream.anchorID] ?? []) + ids.map { $0.uuidString.lowercased() }
        all[stream.anchorID] = Array(list.suffix(limitPerStream))
        defaults.set(all, forKey: keyPrefix + account)
        return all.values.reduce(0) { $0 + $1.count }
    }
}

/// Reads HealthKit, maps, encodes and uploads, off the main actor:
///
/// - **Order.** `HealthStore.streams`: the night and overnight vitals before the
///   high-volume day streams, so scoring has the night first.
/// - **First score first.** On an account's first sync (no anchors), the last
///   `recentDays` days of every stream go up first (date-bounded, anchors never
///   committed; the platform counts the later re-send as duplicates). The run then stops
///   with a backlog, so the coordinator refreshes, and the anchored backfill follows.
/// - **Pipelined.** While a page uploads, the next one is read (one page ahead, never
///   more). Its anchor is committed only after its own upload.
/// - **Pages by bytes.** A page holds as many records as fit `targetPageBytes` at the
///   bytes per record the last page of that stream measured; a `413` halves it for the
///   rest of the run.
actor SyncEngine {
    struct Context: Sendable {
        let account: String
        let deviceID: UUID
        let deviceName: String?
        let appVersion: String
        let osVersion: String
        let now: Date
    }

    enum Event: Sendable {
        case reading(HealthStream)
        case uploading(HealthStream, records: Int)
        case accepted(HealthStream, SyncResponse)
        case state(SyncEngineState)
    }

    struct Result: Sendable {
        var touched: [String] = []
        var uploaded = 0
        /// Stopped after the first score's window; the backfill follows.
        var backlog = false
        /// Refused at a gate; the page's anchor isn't committed.
        var pausedFor: APIErrorCode?
        /// HealthKit was locked (protected data); nothing is lost, the rest follows the unlock.
        var waitingForUnlock = false
        /// The responses' `scoring`, merged: every day queued, the longest expected wait.
        var scoring: SyncScoring?
    }

    /// The first score's window.
    static let recentDays = 3
    /// Uncompressed body per page (the platform takes 32 MiB; small pages fail cheaply).
    static let targetPageBytes = 2_000_000
    /// Smallest page a 413 can shrink to; below that the error is real.
    static let minimumPageSize = 250

    private let health: HealthStore
    private let api: PlatformAPI
    private let defaults: UserDefaults
    private var state = SyncEngineState()
    private var account = ""
    private var touched = Set<String>()
    private var scoring: SyncScoring?
    /// Measured on the last page of each stream.
    private var bytesPerRecord: [HealthStream: Double] = [:]
    /// The most records per page this run; a 413 lowers it.
    private var maxRecords = 0
    private var gate: @Sendable () async -> APIErrorCode? = { nil }
    /// `requestStop()`: end after the page being uploaded.
    private var stopRequested = false
    private var stoppedEarly = false
    /// `SyncEngineState.wipes` when the run started: a wipe since then (sign-out) means
    /// this run's state isn't anyone's to keep.
    private var wipesAtStart = 0

    /// Ends the run after the page being uploaded (its anchor committed); the run then
    /// reports a backlog. For the app going to the background.
    func requestStop() {
        stopRequested = true
    }

    init(health: HealthStore, api: PlatformAPI, defaults: UserDefaults) {
        self.health = health
        self.api = api
        self.defaults = defaults
    }

    /// Days queued for rescoring by the pages accepted so far (after a failure, too).
    var touchedSoFar: [String] { touched.sorted() }

    /// `gate` is asked before every page: a gate that appears mid-run (consent withdrawn)
    /// stops the next page before it goes up, uncommitted.
    func run(_ context: Context, gate: @escaping @Sendable () async -> APIErrorCode?,
             report: @escaping @Sendable (Event) async -> Void) async throws -> Result {
        self.gate = gate
        account = context.account
        wipesAtStart = SyncEngineState.wipes(defaults)
        state = SyncEngineState.load(account: account, defaults: defaults)
        touched = []
        scoring = nil
        maxRecords = health.pageSize
        stopRequested = false
        stoppedEarly = false
        var result = Result()
        defer { persist() }
        do {
            state.lastError = nil
            state.lastRequestID = nil
            // An account that synced before has nothing to gain from the window.
            if !state.recentDone, health.hasAnchors { state.recentDone = true }
            if !state.recentDone {
                let since = Calendar.current.date(byAdding: .day, value: -Self.recentDays, to: context.now) ?? context.now
                try await set(.recent, report)
                try await drain(.recent(since: since), context, report)
                if stoppedEarly { return await stopped(result, context, report) }
                state.recentDone = true
                // Something to score: let the coordinator refresh before the long backfill.
                if !touched.isEmpty {
                    state.phase = .backfill
                    await finished(context, report)
                    result.backlog = true
                    return finish(result)
                }
            }
            try await set(state.backfillDone ? .incremental : .backfill, report)
            try await drain(.anchored, context, report)
            if stoppedEarly { return await stopped(result, context, report) }
            state.backfillDone = true
            state.backlogBytes = 0
            state.phase = .idle
            await finished(context, report)
            return finish(result)
        } catch let error where ProtectedData.isLocked(error) {
            result.waitingForUnlock = true
            state.phase = .idle
            await finished(context, report)
            return finish(result)
        } catch let error where error.gate != nil {
            result.pausedFor = error.gate
            state.phase = .idle
            await finished(context, report)
            return finish(result)
        } catch is CancellationError {
            // Stopped from outside (sign-out, background time over): not an error to show.
            state.phase = .idle
            await finished(context, report)
            throw CancellationError()
        } catch {
            state.lastError = error.localizedDescription
            state.lastRequestID = (error as? APIError)?.requestID
            state.phase = .idle
            await finished(context, report)
            throw error
        }
    }

    /// Stopped on request after a page: the rest is a backlog.
    private func stopped(_ result: Result, _ context: Context, _ report: @Sendable (Event) async -> Void) async -> Result {
        var r = result
        r.backlog = true
        if !state.backfillDone {
            let remaining = health.streams.map(\.anchorID).filter { state.streams[$0]?.backfilled != true }
            state.backlogBytes = SyncEngineState.backlogEstimate(state.streams, remaining: remaining)
        }
        state.phase = .idle
        await finished(context, report)
        return finish(r)
    }

    /// The run's last word: no stream in progress, and when it ended.
    private func finished(_ context: Context, _ report: @Sendable (Event) async -> Void) async {
        state.stream = nil
        state.updatedAt = context.now
        await report(.state(state))
    }

    /// Saves the state, unless the account's state was wiped since the run began.
    private func persist() {
        guard SyncEngineState.wipes(defaults) == wipesAtStart else { return }
        state.save(account: account, defaults: defaults)
    }

    private func finish(_ result: Result) -> Result {
        var r = result
        r.touched = touched.sorted()
        r.scoring = scoring
        return r
    }

    private func set(_ phase: SyncEngineState.Phase, _ report: @Sendable (Event) async -> Void) async throws {
        try Task.checkCancellation()
        state.phase = phase
        await report(.state(state))
    }

    // MARK: draining

    enum Mode {
        /// Date-bounded, anchors kept in memory only.
        case recent(since: Date)
        /// From the committed anchor (the backfill window on the first query).
        case anchored
    }

    /// Where the next read starts: a stream, and the uncommitted anchor of the page before.
    private struct Cursor {
        let index: Int
        let after: Data?
    }

    /// Every stream, page by page, reading one page ahead while the current one uploads.
    private func drain(_ mode: Mode, _ context: Context, _ report: @escaping @Sendable (Event) async -> Void) async throws {
        let streams = health.streams
        guard !streams.isEmpty else { return }
        var cursor = Cursor(index: 0, after: nil)
        await report(.reading(streams[0]))
        guard var page = try await Self.read(health, mode, streams[0], after: nil, limit: limit(for: streams[0])) else {
            return
        }
        while true {
            try Task.checkCancellation()
            let stream = streams[cursor.index]
            state.stream = stream.anchorID
            let next: Cursor? = page.more ? Cursor(index: cursor.index, after: page.anchor)
                : cursor.index + 1 < streams.count ? Cursor(index: cursor.index + 1, after: nil) : nil
            let nextStream = next.map { streams[$0.index] }
            let nextLimit = nextStream.map(limit(for:)) ?? 0
            if let nextStream { await report(.reading(nextStream)) }
            // One page ahead, never more: it reads (and maps) while this one uploads.
            async let ahead = Self.read(health, mode, nextStream, after: next?.after, limit: nextLimit)
            guard try await upload(page.delta, stream: stream, context: context, report: report) else {
                // 413: drop what was read ahead and read this page again, smaller.
                _ = try? await ahead
                page = try await Self.read(health, mode, stream, after: cursor.after, limit: limit(for: stream)) ?? page
                continue
            }
            if case .anchored = mode {
                // The deletions before the anchor: once the anchor moves, HealthKit won't
                // report them again.
                if !page.deleted.isEmpty {
                    state.pendingDeletions = PendingDeletions.add(page.deleted, stream: stream, account: account,
                                                                  defaults: defaults)
                }
                health.commit(page, for: stream)
                if !page.more, !state.backfillDone { state.streams[stream.anchorID, default: .init()].backfilled = true }
                // Checkpointed with its anchor: a run the system ends keeps its progress.
                persist()
            }
            // The app went to the background: this page is in, the rest waits.
            if stopRequested, page.more || next != nil {
                stoppedEarly = true
                _ = try? await ahead
                return
            }
            let read = try await ahead
            guard let next, let read else { return }
            cursor = next
            page = read
        }
    }

    /// A page of `stream` (`nil`: nothing to read). Nonisolated: when read ahead it runs on
    /// the global executor beside the upload, mapping included.
    private static func read(_ health: HealthStore, _ mode: Mode, _ stream: HealthStream?, after: Data?,
                             limit: Int) async throws -> HealthPage? {
        guard let stream else { return nil }
        switch mode {
        case .recent(let since): return try await health.recentPage(stream, since: since, after: after, limit: limit)
        case .anchored: return try await health.nextPage(stream, after: after, limit: limit)
        }
    }

    /// Records per page for `stream`: what fits `targetPageBytes` at its measured size.
    private func limit(for stream: HealthStream) -> Int {
        let perRecord = bytesPerRecord[stream] ?? Self.estimatedBytesPerRecord(stream)
        let fitting = Int(Double(Self.targetPageBytes) / max(perRecord, 1))
        return max(Self.minimumPageSize, min(maxRecords, fitting))
    }

    /// Before a page measured it: a sample is ~200 bytes of JSON, a workout ~400.
    static func estimatedBytesPerRecord(_ stream: HealthStream) -> Double {
        switch stream {
        case .quantity: return 210
        case .sleep: return 190
        case .workouts: return 420
        }
    }

    // MARK: uploading

    /// `false` when the body was too large (413): pages shrink for the rest of the run
    /// and the caller reads the page again. 503/429 are retried inside APIClient.
    private func upload(_ delta: HealthDelta, stream: HealthStream, context: Context,
                        report: @Sendable (Event) async -> Void) async throws -> Bool {
        guard !delta.isEmpty else { return true }
        // Consent withdrawn or a gate reported meanwhile: this page stays (its anchor too).
        if let gate = await gate() { throw APIError.http(403, "", code: gate) }
        await report(.uploading(stream, records: delta.count))
        let request = SyncRequest(deviceId: context.deviceID, deviceName: context.deviceName,
                                  appVersion: context.appVersion, osVersion: context.osVersion,
                                  samples: delta.samples, sleep: delta.sleep, workouts: delta.workouts)
        let body = try await Self.encode(request)
        bytesPerRecord[stream] = Double(body.count) / Double(delta.count)
        let response: SyncResponse
        do {
            response = try await api.sync(encoded: body)
        } catch let error as APIError where error.status == 413 && maxRecords > Self.minimumPageSize {
            maxRecords = max(Self.minimumPageSize, min(maxRecords, delta.count) / 2)
            return false
        }
        touched.formUnion(response.daysTouched)
        scoring = SyncScoring(queuedDays: Set(scoring?.queuedDays ?? []).union(response.scoring.queuedDays).sorted(),
                              expectedWithinSec: max(scoring?.expectedWithinSec ?? 0, response.scoring.expectedWithinSec))
        record(delta, bytes: body.count, response: response, stream: stream)
        await report(.accepted(stream, response))
        await report(.state(state))
        return true
    }

    private func record(_ delta: HealthDelta, bytes: Int, response: SyncResponse, stream: HealthStream) {
        var p = state.streams[stream.anchorID, default: .init()]
        p.records += delta.count
        p.bytes += bytes
        let starts = delta.samples.map(\.start) + delta.sleep.map(\.start) + delta.workouts.map(\.start)
        let ends = delta.samples.map(\.end) + delta.sleep.map(\.end) + delta.workouts.map(\.end)
        if let lo = starts.min() { p.oldest = min(p.oldest ?? lo, lo) }
        if let hi = ends.max() { p.newest = max(p.newest ?? hi, hi) }
        switch stream {
        case .quantity:
            p.lastAccepted = response.accepted.samples
            p.lastIgnored = response.ignored.samples
        case .sleep:
            p.lastAccepted = response.accepted.sleep
            p.lastIgnored = response.ignored.sleep
        case .workouts:
            p.lastAccepted = response.accepted.workouts
            p.lastIgnored = response.ignored.workouts
        }
        state.streams[stream.anchorID] = p
        state.bytesUploaded += bytes
    }

    /// JSON for a page: several MB for a full one, so never on the main actor.
    @concurrent
    private static func encode(_ request: SyncRequest) async throws -> Data {
        MainThread.assertOff("Encoding a sync page")
        return try APIClient.jsonEncoder.encode(request)
    }
}
