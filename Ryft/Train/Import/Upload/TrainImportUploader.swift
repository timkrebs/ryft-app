// Uploads a confirmed training import (design §7, ADR 0007):
//
//   Import ──▶ PendingImport (per account) ──▶ custom exercises, one POST /v1/exercises at a time
//            ──▶ POST /v1/train/import: plans (≤ 5) first, then sessions oldest first (≤ 50, ≤ 1 MiB measured)
//            ──▶ POST /v1/plans/{id}/enroll ──▶ done: library refresh, the days rescored
//   per item: created · unchanged · updated ──▶ done · rejected ──▶ listed, Retry · not named 3× ──▶ rejected
//   413 ──▶ half the sessions per request · other 4xx ──▶ that request's items rejected, the rest goes on
//   transport · 408 · 429 · 5xx ──▶ paused, backoff 30 s · 2 min · 10 min · 1 h (Retry-After) · 403 + code ──▶ gated
//   no contract (C2) or train.import off ──▶ "saved on this iPhone"
import Foundation
import Observation
import SwiftData
import UIKit

/// Uploads a confirmed import: one job per account, stored until it's done, sent in order, resumable after a relaunch.
///
/// - **Never another account:** the job is bound to the account the flow started with (or demo), it's read only for
///   that binding, a request goes only through that binding's client, and every answer is dropped unless the
///   generation (an account counter, the binding, the store's wipe epoch) is still the one it started under. Sign-out
///   wipes the job with the store; switching demo off deletes demo's.
/// - **Consent first:** `gate(.data)` (`uploadGate(for: .trainImport, write: .data)`) is asked before the first request
///   and before every one after it; a held job waits, never dropped (ADR 0008). A policy not known right now is asked
///   for once per pass (`ConsentState.revalidate`).
/// - **Idempotent:** every id is derived (ADR 0007), so a request whose answer was lost is sent again and answers
///   `unchanged`; progress is stored after each request, so a relaunch goes on where it stopped.
/// - **Before the contract** (`TrainImportAPI.publishesTrainImport == false`) or with `train.import` off, nothing is
///   sent: the job is "saved on this iPhone".
/// - **Never `LocalSession`, the outbox or Apple Health** (ADR 0007 §4).
@MainActor
@Observable
final class TrainImportUploader {
    /// ≤ 50 sessions and ≤ 5 plans per request (T9); sessions are halved after a `413`.
    static let sessionsPerRequest = 50
    static let plansPerRequest = 5
    /// A request body stays under the platform's 1 MiB with room for headers.
    static let maxBodyBytes = (1 << 20) - (16 << 10)
    /// A job that isn't done is removed after this long (design §7).
    static let retention: TimeInterval = 30 * 86_400
    /// A finished job nobody looked at is removed after this long (ui.md §8.2).
    static let finishedRetention: TimeInterval = 7 * 86_400
    /// Answers that don't name a pending item before it counts as refused.
    static let maxUnanswered = 3
    /// Items refused alone (each a whole-request `400`/`422`) in a pass where nothing was accepted before the pass
    /// stops with the rest pending (`ImportPause.needsAttention`).
    static let maxRefusedAlone = 3
    /// After 1, 2, 3, then any more transient failures in a row: 30 s, 2 min, 10 min, 1 h (the cap).
    static let backoff: [Duration] = [.seconds(30), .seconds(120), .seconds(600), .seconds(3_600)]
    /// Up to this share of the step is added at random, so phones don't retry in step.
    static let jitter = 0.2
    /// `GET /v1/sessions` per request when the account's sessions are read (as `DataExport`).
    static let sessionChunkDays = 180

    /// What stands between the account and the import's requests (`OnboardingCoordinator.uploadGate(for:
    /// .trainImport, write:)`). **Closed until the app connects it** (ScreenModels); tests open it explicitly.
    @ObservationIgnored var gate: @MainActor (UploadWrite) -> UploadGate? = { _ in .gate(.consentRequired) }
    /// Jitter source (tests: `{ $0.lowerBound }`).
    @ObservationIgnored var random: (ClosedRange<Double>) -> Double = { .random(in: $0) }

    /// The current binding's job; nil when there's none (or nothing is signed in).
    private(set) var status: ImportJobStatus?

    /// Whose job a pass sends, and through which client: every answer is checked against it.
    struct Generation: Equatable {
        let count: Int
        let account: String?
        let demo: Bool
        let store: Int
    }

    /// The job in memory: its plan decoded once, its progress as stored.
    private struct Loaded {
        let jobID: UUID
        let account: String
        let plan: ImportUploadPlan
        var progress: ImportJobProgress
    }

    /// What a pass is doing right now.
    private enum Activity { case preparing, uploading }

    @ObservationIgnored private weak var env: AppEnvironment?
    @ObservationIgnored private let library: TrainLibrary?
    @ObservationIgnored private let coordinator: SyncCoordinator?
    @ObservationIgnored private var accountCount = 0
    @ObservationIgnored private var loaded: Loaded?
    @ObservationIgnored private var activity: Activity?
    /// Why the last pass stopped; nil while one runs or after it finished.
    @ObservationIgnored private var pause: ImportPause?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var retryAt: Date?
    @ObservationIgnored private var lostConnection = false
    @ObservationIgnored private var pass: Task<Void, Never>?
    @ObservationIgnored private var passID: UUID?
    @ObservationIgnored private var passAgain = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var reloading: Task<Void, Never>?

    init(env: AppEnvironment, library: TrainLibrary? = nil, coordinator: SyncCoordinator? = nil) {
        self.env = env
        self.library = library
        self.coordinator = coordinator
        env.connectivityMonitor.onChange { [weak self] online in
            guard online, let self else { return }
            if self.lostConnection { self.makeDue() }
            Task { await self.resume() }
        }
    }

    /// Previews: a fixed status, nothing runs.
    static func preview(_ status: ImportJobStatus?, env: AppEnvironment? = nil) -> TrainImportUploader {
        let uploader = TrainImportUploader(env: env ?? .preview())
        uploader.status = status
        return uploader
    }

    /// The binding a flow starts with and passes to `start`: the signed-in account's id, or
    /// `ImportMappingStore.demoAccount` with demo data; nil signed out.
    var currentAccount: String? {
        guard let env else { return nil }
        return env.isDemo ? ImportMappingStore.demoAccount : env.auth.accountID
    }

    var generation: Generation {
        Generation(count: accountCount, account: currentAccount, demo: env?.isDemo ?? false,
                   store: (env?.persistence as? TrainStore)?.epoch ?? 0)
    }

    /// The job exists and isn't finished: a second import never starts (ui.md §8.2).
    var hasUnfinishedJob: Bool { status.map { !$0.isFinished } ?? false }

    /// Uploads go now: the platform takes imports and `train.import` is on. False: step 5 offers "Keep on this
    /// iPhone" (V5).
    var uploadsAvailable: Bool {
        guard let env, let account = currentAccount else { return false }
        return client(for: account, env: env).publishesTrainImport && env.flags.isOn(.trainImport)
    }

    /// A pass is sending now.
    var isRunning: Bool { pass != nil }

    // MARK: the flow

    /// What the account already has (design §6): its plans with the import's derived ids (and their current copy),
    /// the derived sessions already there, and the sessions logged in RYFT on the import's days, on the platform and
    /// finished on this iPhone but not uploaded. Offline, for another binding, or on an error: `.unchecked`.
    func checkExisting(_ query: ImportExistingQuery) async -> ImportExisting {
        guard let env, currentAccount == query.account, env.connectivity.isOnline else { return .unchecked }
        let generation = generation
        let api = client(for: query.account, env: env)
        let signpost = ImportLog.signposter.beginInterval("check-existing", id: ImportLog.signposter.makeSignpostID())
        defer { ImportLog.signposter.endInterval("check-existing", signpost) }
        do {
            let mine = Set(try await api.plans().mine.map(\.id))
            var plans: [UUID: Plan?] = [:]
            for id in query.planIDs where mine.contains(id) {
                plans[id] = .some(try? await api.plan(id: id))
            }
            var existingSessions = Set<UUID>()
            var logged: [LoggedSession] = []
            if let range = query.range {
                let derived = Set(query.sessionIDs)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = query.zone
                func dayKey(_ date: Date) -> String? {
                    let parts = calendar.dateComponents([.year, .month, .day], from: date)
                    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
                    return LocalDate(year: year, month: month, day: day)?.key
                }
                var from = range.lowerBound
                while from <= range.upperBound {
                    let to = min(from.addingTimeInterval(TimeInterval(Self.sessionChunkDays * 86_400) - 1), range.upperBound)
                    for summary in try await api.sessions(from: from, to: to) {
                        if derived.contains(summary.id) {
                            existingSessions.insert(summary.id)
                            continue
                        }
                        guard summary.status == .completed, let key = dayKey(summary.startedAt),
                              query.days.contains(key) else { continue }
                        let detail = try await api.session(id: summary.id)
                        logged.append(LoggedSession(id: detail.id, startedAt: detail.startedAt,
                                                    exerciseIDs: Self.performedExercises(detail)))
                    }
                    from = to.addingTimeInterval(1)
                }
                // Finished on this iPhone and not uploaded yet: the account's own (demo's sessions aren't in this store).
                if query.account != ImportMappingStore.demoAccount, let store = env.persistence as? TrainStore {
                    for local in store.completedSessions(from: range.lowerBound, to: range.upperBound)
                    where !local.uploaded && !derived.contains(local.id) {
                        guard let key = dayKey(local.startedAt), query.days.contains(key) else { continue }
                        logged.append(LoggedSession(id: local.id, startedAt: local.startedAt,
                                                    exerciseIDs: Self.performedExercises(local.wire)))
                    }
                }
            }
            guard generation == self.generation else { return .unchecked }
            ImportLog.logger.info("""
            Import check: \(plans.count, privacy: .public) plans and \(existingSessions.count, privacy: .public) \
            sessions exist, \(logged.count, privacy: .public) logged on those days
            """)
            return ImportExisting(checked: true, plans: plans, sessionIDs: existingSessions, logged: logged)
        } catch {
            ImportLog.logger.info("Import check failed: \(FailureKind.of(error).rawValue, privacy: .public)")
            return .unchecked
        }
    }

    /// Import tapped: the job is stored for `account` (the flow's, `currentAccount` when it started) and the upload
    /// starts; this returns once the job is stored. Returns false, and stores nothing, when that account isn't the
    /// current binding any more or its job is still unfinished (a finished one is replaced). Without uploads
    /// (`uploadsAvailable` false) the job is kept as "saved on this iPhone".
    @discardableResult
    func start(_ plan: ImportUploadPlan, account: String, source: ImportFormatID, zone: TimeZone,
               duplicatesChecked: Bool) async -> Bool {
        guard let env, currentAccount == account, !(job(for: account).map(isUnfinished) ?? false) else { return false }
        let generation = generation
        let signpost = ImportLog.signposter.beginInterval("encode-job", id: ImportLog.signposter.makeSignpostID())
        let encoded = await Self.encodeJob(plan)
        ImportLog.signposter.endInterval("encode-job", signpost)
        guard let encoded, generation == self.generation, currentAccount == account,
              !(job(for: account).map(isUnfinished) ?? false) else { return false }
        cancelPass()
        for old in jobs(account: account) { env.persistence.context.delete(old) }
        let row = PendingImport(account: account, source: source, createdAt: env.clock.now(), timeZoneID: zone.identifier,
                                duplicatesChecked: duplicatesChecked, payload: encoded.payload,
                                progressData: encoded.progress, sessionsPerRequest: Self.sessionsPerRequest)
        env.persistence.context.insert(row)
        env.persistence.save()
        loaded = Loaded(jobID: row.id, account: account, plan: plan, progress: ImportJobProgress())
        resetRetry()
        pause = nil
        ImportLog.logger.info("""
        Import job stored: \(plan.exercises.count, privacy: .public) exercises, \(plan.plans.count, privacy: .public) \
        plans, \(plan.sessions.count, privacy: .public) sessions, \(encoded.payload.count, privacy: .public) bytes
        """)
        refreshStatus()
        _ = startPass(userInitiated: true)
        return true
    }

    // MARK: triggers

    /// Continue: app active, reconnect, sign-in, the gate opening. Waits for the pass (a running one goes round once
    /// more); a pass still backing off isn't started early.
    func resume() async {
        await reload()
        guard let pass = startPass(userInitiated: false) else { return }
        await pass.value
    }

    /// "Retry N" and "Try again": the rejected and blocked items go back to pending and are sent now, without
    /// waiting out a backoff; the rest isn't resubmitted.
    func retryRejected() async {
        await reload()
        guard var current = loaded else { return }
        current.progress.items = current.progress.items.filter { $0.value.phase != .rejected && $0.value.phase != .blocked }
        current.progress.unanswered = [:]
        loaded = current
        await store(current.progress, finished: nil)
        guard let pass = startPass(userInitiated: true) else { return }
        await pass.value
    }

    /// "Import these too": the sessions the uploader's own duplicate check skipped are sent.
    func importDuplicatesFound() async {
        await reload()
        guard var current = loaded else { return }
        current.progress.items = current.progress.items.filter { $0.value.phase != .duplicate }
        loaded = current
        await store(current.progress, finished: nil)
        guard let pass = startPass(userInitiated: true) else { return }
        await pass.value
    }

    /// The user saw the finished result (I3): the resume row goes; the job is removed at the next app start or import.
    func markResultSeen() {
        guard let current = loaded, !Self.hasWork(current), let row = job(id: current.jobID), !row.resultSeen else { return }
        row.resultSeen = true
        env?.persistence.save()
        refreshStatus()
    }

    /// Discard: removed; nothing more is sent.
    func discard() {
        cancelPass()
        if let current = loaded, let row = job(id: current.jobID) {
            env?.persistence.context.delete(row)
            env?.persistence.save()
            ImportLog.logger.info("Import job discarded")
        }
        loaded = nil
        resetRetry()
        pause = nil
        refreshStatus()
    }

    /// Signed out, another account, the Demo data switch, or an account deletion starting: the pass and the retry
    /// stop, answers in flight are dropped (`generation`), and the status follows the new binding.
    func accountChanged() {
        accountCount += 1
        cancelPass()
        reloading?.cancel()
        reloading = nil
        loaded = nil
        resetRetry()
        pause = nil
        status = nil
        Task { [weak self] in await self?.reload() }
    }

    /// Demo data switched off: demo's job goes (it could only ever reach the in-memory platform).
    static func forgetDemo(in persistence: Persistence) {
        let demo = ImportMappingStore.demoAccount
        let rows = (try? persistence.context.fetch(FetchDescriptor<PendingImport>(predicate: #Predicate { $0.account == demo }))) ?? []
        guard !rows.isEmpty else { return }
        for row in rows { persistence.context.delete(row) }
        persistence.save()
    }

    /// The app became active: old jobs go (unfinished after 30 days, finished once seen or after 7 days), "not
    /// available yet" is asked again, and the current one continues.
    func appBecameActive() async {
        purge()
        pause = pause == .notAvailable ? nil : pause
        await resume()
    }

    /// The app went to the background: the request in flight finishes inside a background task, which ends when the
    /// pass does; if the system's time runs out first, the pass is cancelled (the items stay pending). Nil when
    /// nothing runs.
    @discardableResult
    func finishInBackground(app: BackgroundTaskRunning) -> Task<Void, Never>? {
        guard let pass else { return nil }
        let token = ImportBackgroundTask(app: app)
        token.begin { [weak self] in self?.cancelPass() }
        return Task {
            await pass.value
            token.end()
        }
    }

    // MARK: the job

    private func client(for account: String, env: AppEnvironment) -> PlatformAPI {
        account == ImportMappingStore.demoAccount ? env.demoAPI : env.liveAPI
    }

    private func jobs(account: String) -> [PendingImport] {
        guard let env else { return [] }
        let descriptor = FetchDescriptor<PendingImport>(predicate: #Predicate { $0.account == account },
                                                        sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? env.persistence.context.fetch(descriptor)) ?? []
    }

    private func job(for account: String) -> PendingImport? { jobs(account: account).first }

    private func job(id: UUID) -> PendingImport? {
        guard let env else { return nil }
        var descriptor = FetchDescriptor<PendingImport>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? env.persistence.context.fetch(descriptor))?.first
    }

    /// Something of it is still to send (as `status` says), whether or not its end was stored yet.
    private func isUnfinished(_ row: PendingImport) -> Bool {
        if let loaded, loaded.jobID == row.id { return Self.hasWork(loaded) }
        return row.finishedAt == nil
    }

    /// The current binding's job into memory (its plan decoded off the main actor), or none.
    private func reload() async {
        if let reloading {
            await reloading.value
            return
        }
        guard let account = currentAccount, let row = job(for: account) else {
            loaded = nil
            refreshStatus()
            return
        }
        if loaded?.jobID == row.id {
            refreshStatus()
            return
        }
        let generation = generation, id = row.id, payload = row.payload, progress = row.progressData
        let task = Task { [weak self] in
            let signpost = ImportLog.signposter.beginInterval("decode-job", id: ImportLog.signposter.makeSignpostID())
            let decoded = await Self.decodeJob(payload, progress)
            ImportLog.signposter.endInterval("decode-job", signpost)
            guard let self, generation == self.generation, let row = self.job(id: id) else { return }
            guard let decoded else {
                // Written by this app, so this can't happen short of a damaged store: nothing could ever be sent.
                ImportLog.logger.error("Import job unreadable; removed")
                self.env?.persistence.context.delete(row)
                self.env?.persistence.save()
                self.refreshStatus()
                return
            }
            self.loaded = Loaded(jobID: id, account: row.account, plan: decoded.plan, progress: decoded.progress)
            self.refreshStatus()
        }
        reloading = task
        await task.value
        reloading = nil
    }

    private func purge() {
        guard let env else { return }
        let now = env.clock.now()
        let rows = (try? env.persistence.context.fetch(FetchDescriptor<PendingImport>())) ?? []
        var removed = 0
        for row in rows {
            let expired: Bool = if let finished = row.finishedAt {
                row.resultSeen || now.timeIntervalSince(finished) >= Self.finishedRetention
            } else {
                now.timeIntervalSince(row.createdAt) >= Self.retention
            }
            guard expired else { continue }
            if loaded?.jobID == row.id {
                cancelPass()
                loaded = nil
            }
            env.persistence.context.delete(row)
            removed += 1
        }
        guard removed > 0 else { return }
        env.persistence.save()
        ImportLog.logger.info("Import jobs removed: \(removed, privacy: .public)")
        refreshStatus()
    }

    /// Writes the progress (encoded off the main actor), and the finish time when it changes. Rewritten after each
    /// request: about 60 bytes per finished item, so about 600 KB at the limit of 10,000 sessions, 200 times over a
    /// whole upload; acceptable for a one-off import.
    private func store(_ progress: ImportJobProgress, finished: Date?) async {
        guard let current = loaded else { return }
        let generation = generation
        let data = await Self.encodeProgress(progress)
        guard generation == self.generation, let data, let row = job(id: current.jobID) else { return }
        row.progressData = data
        row.finishedAt = finished
        if finished == nil { row.resultSeen = false }
        env?.persistence.save()
        refreshStatus()
    }

    // MARK: the pass

    private func startPass(userInitiated: Bool) -> Task<Void, Never>? {
        guard env != nil, let current = loaded, current.account == currentAccount else { return nil }
        if userInitiated { makeDue() }
        if let pass {
            passAgain = true
            return pass
        }
        guard Self.hasWork(current) else {
            // Everything was answered, but the end wasn't stored (the app was ended in between).
            if job(id: current.jobID)?.finishedAt == nil {
                let generation = generation
                Task { [weak self] in await self?.finishIfDone(generation) }
            }
            refreshStatus()
            return nil
        }
        let generation = generation, id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            var revalidated = false
            repeat {
                passAgain = false
                await run(generation, revalidated: &revalidated)
            } while passAgain && pause == nil && generation == self.generation
            guard passID == id else { return }
            pass = nil
            passID = nil
            passAgain = false
            activity = nil
            refreshStatus()
        }
        pass = task
        passID = id
        refreshStatus()
        return task
    }

    private func cancelPass() {
        pass?.cancel()
        pass = nil
        passID = nil
        passAgain = false
        activity = nil
    }

    /// Something is still to send: a pending item, or the enrolment.
    private static func hasWork(_ job: Loaded) -> Bool {
        let plan = job.plan
        if plan.exercises.contains(where: { job.progress.isPending($0.id) }) { return true }
        if plan.plans.contains(where: { job.progress.isPending($0.id) }) { return true }
        if plan.sessions.contains(where: { job.progress.isPending($0.id) }) { return true }
        return plan.enrolPlanID != nil && !job.progress.enrolled
    }

    /// One pass: what can go now goes, in order, until it's done or something stops it.
    private func run(_ generation: Generation, revalidated: inout Bool) async {
        guard let env, let current = loaded, let account = generation.account, current.account == account else { return }
        let api = client(for: account, env: env)
        guard env.flags.isOn(.trainImport), api.publishesTrainImport else {
            stop(.notAvailable)
            return
        }
        guard env.connectivity.isOnline else {
            stop(.offline)
            return
        }
        if let retryAt, retryAt > env.clock.now() {
            stop(.retrying(at: retryAt))
            return
        }
        pause = nil
        // The duplicates an offline preview couldn't check, before the first session goes.
        if let row = job(id: current.jobID), !row.duplicatesChecked,
           current.plan.sessions.contains(where: { current.progress.isPending($0.id) }) {
            guard await isOpen(generation, revalidated: &revalidated) else { return }
            guard await checkAtUpload(generation) else { return }
        }
        // Custom exercises, one at a time.
        while let exercise = nextExercise() {
            activity = .preparing
            refreshStatus()
            guard await isOpen(generation, revalidated: &revalidated) else { return }
            guard await create(exercise, api: api, generation: generation) else { return }
        }
        // Plans, then sessions, in batches. A request refused as a whole (`400`, `422`) is split in halves until the
        // item it refuses is alone; after an accepted request the limit grows again.
        var plansLimit = Self.plansPerRequest
        var sessionsWithPlans = true
        var itemLimit: Int?
        // Whether the platform took anything in this pass, and how many items it refused alone meanwhile. With nothing
        // taken and `maxRefusedAlone` refused alone, the refusal is the requests' shape, not single items: the pass
        // stops and the rest stays pending (never refused), at about eight requests.
        var acceptedInPass = false
        var refusedAlone = 0
        while let batch = nextBatch(plansLimit: plansLimit, sessionsWithPlans: sessionsWithPlans, itemLimit: itemLimit) {
            activity = .uploading
            refreshStatus()
            guard await isOpen(generation, revalidated: &revalidated) else { return }
            switch await send(batch, api: api, generation: generation) {
            case .accepted:
                acceptedInPass = true
                itemLimit = itemLimit.flatMap { $0 * 2 >= Self.plansPerRequest + Self.sessionsPerRequest ? nil : $0 * 2 }
            case .refusedAlone:
                refusedAlone += 1
                if !acceptedInPass, refusedAlone >= Self.maxRefusedAlone {
                    ImportLog.logger.info("Import: every request refused, \(refusedAlone, privacy: .public) alone; the rest waits")
                    stop(.needsAttention)
                    return
                }
            case .sent, .fewerSessions: continue
            case let .fewerPlans(count): plansLimit = max(1, count / 2)
            case .plansAlone: sessionsWithPlans = false
            case let .fewerItems(count): itemLimit = max(1, count / 2)
            case .stop: return
            }
        }
        // The enrolment, once its plan is there.
        guard await enrol(api: api, generation: generation, revalidated: &revalidated) else { return }
        await finishIfDone(generation)
    }

    /// The gate for the next request: open, or the pass stops with it (after asking for the policy once).
    private func isOpen(_ generation: Generation, revalidated: inout Bool) async -> Bool {
        guard generation == self.generation, !Task.isCancelled else { return false }
        guard env?.auth.isDeletingAccount != true else {
            stop(.waitingForAccount)
            return false
        }
        var hold = gate(.data)
        if hold == .policyUnknown, !revalidated, let consent = env?.consent {
            revalidated = true
            try? await consent.revalidate()
            guard generation == self.generation else { return false }
            hold = gate(.data)
        }
        if let hold {
            stop(.gated(hold))
            return false
        }
        return true
    }

    private func stop(_ reason: ImportPause) {
        pause = reason
        activity = nil
        refreshStatus()
    }

    // MARK: duplicates at upload (design §6)

    /// After an offline preview: what already exists is marked done (RYFT's copy of a plan is kept), and sessions that
    /// look like one the user logged are skipped (`duplicate`, "Import these too"). False when it couldn't be read.
    private func checkAtUpload(_ generation: Generation) async -> Bool {
        guard let current = loaded, let row = job(id: current.jobID) else { return false }
        let jobID = current.jobID
        let zone = TimeZone(identifier: row.timeZoneID) ?? .current
        let pending = current.plan.sessions.filter { current.progress.isPending($0.id) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func dayKey(_ date: Date) -> String? {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
            return LocalDate(year: year, month: month, day: day)?.key
        }
        let starts = pending.map(\.startedAt)
        let pad = ImportBuilder.existingPadding
        let range = starts.min().flatMap { first in starts.max().map { first.addingTimeInterval(-pad)...$0.addingTimeInterval(pad) } }
        let query = ImportExistingQuery(account: current.account, planIDs: current.plan.plans.map(\.id),
                                        sessionIDs: current.plan.sessions.map(\.id),
                                        days: Set(pending.compactMap { dayKey($0.startedAt) }), range: range, zone: zone)
        let existing = await checkExisting(query)
        guard isCurrent(generation, job: jobID), var updated = loaded else { return false }
        guard existing.checked else {
            transientFailure(nil)
            return false
        }
        var missing = Set(updated.progress.missingLinks)
        for plan in updated.plan.plans where updated.progress.isPending(plan.id) {
            guard let entry = existing.plans[plan.id] else { continue }
            // RYFT's copy may have been edited: it's kept (the preview couldn't offer "Replace"), and sessions keep only
            // the links into days and rows that copy still has (as the preview's `linkablePlan` does).
            updated.progress[plan.id] = ImportJobProgress.Item(phase: .done, result: TrainImportItemResult.Status.unchanged.rawValue)
            let kept = Set((entry?.days ?? []).flatMap { [$0.id] + $0.exercises.map(\.id) })
            for day in plan.days {
                for id in [day.id] + day.exercises.map(\.id) where !kept.contains(id) { missing.insert(id.uuidString) }
            }
        }
        updated.progress.missingLinks = missing.sorted()
        for id in existing.sessionIDs where updated.progress.isPending(id) {
            updated.progress[id] = ImportJobProgress.Item(phase: .done, result: TrainImportItemResult.Status.unchanged.rawValue)
        }
        let candidates = pending.filter { updated.progress.isPending($0.id) }.compactMap { session -> DuplicateDetector.Candidate? in
            guard let key = dayKey(session.startedAt) else { return nil }
            return DuplicateDetector.Candidate(id: session.id, day: key, exerciseIDs: Self.performedExercises(session))
        }
        let found = DuplicateDetector.duplicates(of: candidates, against: existing.logged, zone: zone)
        for (id, match) in found {
            updated.progress[id] = ImportJobProgress.Item(phase: .duplicate, related: match)
        }
        loaded = updated
        row.duplicatesChecked = true
        await store(updated.progress, finished: nil)
        ImportLog.logger.info("Import duplicates found at upload: \(found.count, privacy: .public)")
        return generation == self.generation
    }

    // MARK: custom exercises

    private func nextExercise() -> Exercise? {
        guard let current = loaded else { return nil }
        return current.plan.exercises.first { current.progress.isPending($0.id) }
    }

    /// `POST /v1/exercises` (the same id again updates it). False stops the pass.
    private func create(_ exercise: Exercise, api: PlatformAPI, generation: Generation) async -> Bool {
        guard let jobID = loaded?.jobID else { return false }
        let signpost = ImportLog.signposter.beginInterval("upload-exercise", id: ImportLog.signposter.makeSignpostID())
        defer { ImportLog.signposter.endInterval("upload-exercise", signpost) }
        do {
            let saved = try await api.createExercise(exercise)
            guard isCurrent(generation, job: jobID), var current = loaded else { return false }
            current.progress[exercise.id] = ImportJobProgress.Item(phase: .done, result: TrainImportItemResult.Status.created.rawValue)
            loaded = current
            // Demo's exercises live on the demo platform only: never in the account's library cache.
            if current.account != ImportMappingStore.demoAccount { (env?.persistence as? TrainStore)?.cache(exercises: [saved]) }
            resetRetry()
            await store(current.progress, finished: nil)
            return isCurrent(generation, job: jobID)
        } catch {
            guard isCurrent(generation, job: jobID) else { return false }
            return await failed([exercise.id], error, job: jobID)
        }
    }

    /// The pass's binding and job are still the ones an answer was asked for: a late answer for a discarded or
    /// replaced job never marks the next one's items.
    private func isCurrent(_ generation: Generation, job jobID: UUID) -> Bool {
        generation == self.generation && loaded?.jobID == jobID
    }

    // MARK: batches

    private struct Batch {
        let plans: [Plan]
        let sessions: [TrainSession]
        /// Items not sent because a custom exercise they use was refused.
        let blocked: [UUID: UUID]
        var ids: [UUID] { plans.map(\.id) + sessions.map(\.id) }
    }

    private enum SendOutcome {
        /// The platform answered (each item done, refused, or still pending).
        case accepted
        /// Items were refused here (too large alone, or one item the platform refused as a whole).
        case sent
        /// A `400` or `422` for a request of this many items: half as many per request until it's down to the one.
        case fewerItems(Int)
        /// A `400` or `422` for a request of one item: that item is refused.
        case refusedAlone
        /// A `413`: half the sessions per request from now on (stored with the job).
        case fewerSessions
        /// A `413` for this many plans (and at most one session): half as many per request in this pass.
        case fewerPlans(Int)
        /// A `413` for plans and one session: plans go on their own in this pass.
        case plansAlone
        case stop
    }

    /// The next request: pending plans first (≤ `plansLimit`); sessions, oldest first, only once no plan is left for a
    /// later request (and, without `sessionsWithPlans`, only once none is left at all). Items that use a refused custom
    /// exercise are marked blocked instead; a session whose plan was refused or blocked goes without its plan links.
    /// Nil when nothing is left.
    ///
    /// Cost: a scan of the job's items per request, on the main actor; at the limits (10,000 sessions, 200 requests)
    /// about two million dictionary lookups over the whole upload, a few hundred milliseconds in all.
    private func nextBatch(plansLimit: Int, sessionsWithPlans: Bool, itemLimit: Int?) -> Batch? {
        guard var current = loaded, let row = job(id: current.jobID) else { return nil }
        let refused = Set(current.plan.exercises.map(\.id).filter { id in
            guard let item = current.progress[id] else { return false }
            return item.phase == .rejected || item.phase == .blocked
        })
        var blocked: [UUID: UUID] = [:]
        func blocker(_ ids: [UUID]) -> UUID? { ids.first { refused.contains($0) } }
        var plans: [Plan] = []
        var laterPlans = false
        for plan in current.plan.plans where current.progress.isPending(plan.id) {
            if let by = blocker(plan.days.flatMap(\.exercises).map(\.exerciseId)) {
                blocked[plan.id] = by
                continue
            }
            if plans.count < min(plansLimit, itemLimit ?? .max) { plans.append(plan) } else { laterPlans = true }
        }
        var sessions: [TrainSession] = []
        if !laterPlans, sessionsWithPlans || plans.isEmpty {
            // Plan days of plans that won't be there: their links go.
            let failedPlans = Set(current.plan.plans.map(\.id).filter { id in
                guard let item = current.progress[id] else { return blocked[id] != nil }
                return item.phase == .rejected || item.phase == .blocked
            })
            let failedDays = Set(current.plan.plans.filter { failedPlans.contains($0.id) }.flatMap(\.days).map(\.id))
            // And links into RYFT's copy of a plan where that copy no longer has the day or row.
            let missing = Set(current.progress.missingLinks.compactMap(UUID.init(uuidString:)))
            let limit = min(max(1, row.sessionsPerRequest), (itemLimit ?? .max) - plans.count)
            for session in current.plan.sessions where current.progress.isPending(session.id) {
                if let by = blocker(session.exercises.map(\.exerciseId)) {
                    blocked[session.id] = by
                    continue
                }
                guard sessions.count < limit else { break }
                sessions.append(Self.unlinked(session, days: failedDays.union(missing), rows: missing))
            }
        }
        if !blocked.isEmpty {
            for (id, by) in blocked { current.progress[id] = ImportJobProgress.Item(phase: .blocked, related: by) }
            loaded = current
            ImportLog.logger.info("Import items blocked by a refused exercise: \(blocked.count, privacy: .public)")
        }
        guard !plans.isEmpty || !sessions.isEmpty else {
            if !blocked.isEmpty { refreshStatus() }
            return nil
        }
        return Batch(plans: plans, sessions: sessions, blocked: blocked)
    }

    /// The session without `plan_day_id` and every `plan_exercise_id` when its day is in `days`, and without the
    /// `plan_exercise_id`s in `rows` otherwise.
    static func unlinked(_ session: TrainSession, days: Set<UUID>, rows: Set<UUID>) -> TrainSession {
        guard let day = session.planDayId else { return session }
        let dropDay = days.contains(day)
        guard dropDay || session.exercises.contains(where: { $0.planExerciseId.map(rows.contains) == true }) else { return session }
        var copy = session
        if dropDay { copy.planDayId = nil }
        copy.exercises = copy.exercises.map { exercise in
            var copy = exercise
            if dropDay || copy.planExerciseId.map(rows.contains) == true { copy.planExerciseId = nil }
            return copy
        }
        return copy
    }

    /// Encodes (off the main actor, measured), sends and records one request.
    private func send(_ batch: Batch, api: PlatformAPI, generation: Generation) async -> SendOutcome {
        guard let current = loaded, let row = job(id: current.jobID) else { return .stop }
        let jobID = current.jobID
        if !batch.blocked.isEmpty { await store(current.progress, finished: nil) }
        let source = ImportFormatID(rawValue: row.source)
        // Measured: fewer sessions until the body fits; one item alone that doesn't fit is refused.
        var plans = batch.plans, sessions = batch.sessions
        var body: Data?
        while true {
            let signpost = ImportLog.signposter.beginInterval("encode-batch", id: ImportLog.signposter.makeSignpostID())
            let encoded = await Self.encodeRequest(TrainImportRequest(source: source, plans: plans, sessions: sessions))
            ImportLog.signposter.endInterval("encode-batch", signpost)
            guard isCurrent(generation, job: jobID) else { return .stop }
            guard let encoded else { return .stop }
            if encoded.count <= Self.maxBodyBytes {
                body = encoded
                break
            }
            if sessions.count > 1 {
                sessions = Array(sessions.prefix(sessions.count / 2))
            } else if plans.count > 1 {
                plans = Array(plans.prefix(plans.count / 2))
                sessions = []
            } else if !sessions.isEmpty, !plans.isEmpty {
                sessions = []
            } else {
                await refuse(plans.map(\.id) + sessions.map(\.id), reason: nil, error: nil, job: jobID)
                return isCurrent(generation, job: jobID) ? .sent : .stop
            }
        }
        guard let body else { return .stop }
        let ids = plans.map(\.id) + sessions.map(\.id)
        let signpost = ImportLog.signposter.beginInterval("upload-batch", id: ImportLog.signposter.makeSignpostID())
        defer { ImportLog.signposter.endInterval("upload-batch", signpost) }
        do {
            let answer = try await api.importTraining(encoded: body)
            guard isCurrent(generation, job: jobID) else { return .stop }
            await record(answer, ids: ids, bytes: body.count, plans: plans.count, sessions: sessions.count, job: jobID)
            resetRetry()
            return isCurrent(generation, job: jobID) ? .accepted : .stop
        } catch {
            guard isCurrent(generation, job: jobID) else { return .stop }
            let status = (error as? APIError)?.status
            // One refused item mustn't keep the rest out: split until it's alone (Retry sends only what's refused).
            if status == 400 || status == 422 {
                if ids.count > 1 {
                    ImportLog.logger.info("Import: \(status ?? 0, privacy: .public) for \(ids.count, privacy: .public) items, split")
                    return .fewerItems(ids.count)
                }
                if ids.count == 1 {
                    await refuse(ids, reason: nil, error: error, job: jobID)
                    return isCurrent(generation, job: jobID) ? .refusedAlone : .stop
                }
            }
            if status == 413 {
                if sessions.count > 1 {
                    row.sessionsPerRequest = max(1, sessions.count / 2)
                    env?.persistence.save()
                    ImportLog.logger.info("Import: 413, \(row.sessionsPerRequest, privacy: .public) sessions per request")
                    return .fewerSessions
                }
                if !sessions.isEmpty, !plans.isEmpty { return .plansAlone }
                if plans.count > 1 { return .fewerPlans(plans.count) }
                // One item alone is too large for the platform.
                await refuse(ids, reason: nil, error: error, job: jobID)
                return isCurrent(generation, job: jobID) ? .sent : .stop
            }
            return await failed(ids, error, job: jobID) ? .sent : .stop
        }
    }

    /// Per item: done, refused, or (not named) one answer closer to refused.
    private func record(_ answer: TrainImportResponse, ids: [UUID], bytes: Int, plans: Int, sessions: Int, job jobID: UUID) async {
        guard var current = loaded, current.jobID == jobID else { return }
        let sent = Set(ids)
        var counts: [String: Int] = [:]
        for result in answer.results where sent.contains(result.id) && current.progress.isPending(result.id) {
            switch result.status {
            case .created, .unchanged, .updated:
                current.progress[result.id] = ImportJobProgress.Item(phase: .done, result: result.status.rawValue)
            case .rejected:
                current.progress[result.id] = ImportJobProgress.Item(phase: .rejected, reason: result.reason,
                                                                  requestID: answer.requestID)
            }
            counts[result.status.rawValue, default: 0] += 1
            current.progress.unanswered[result.id.uuidString] = nil
        }
        var unanswered = 0
        for id in ids where current.progress.isPending(id) {
            unanswered += 1
            let times = (current.progress.unanswered[id.uuidString] ?? 0) + 1
            if times >= Self.maxUnanswered {
                current.progress.unanswered[id.uuidString] = nil
                current.progress[id] = ImportJobProgress.Item(phase: .rejected, requestID: answer.requestID)
            } else {
                current.progress.unanswered[id.uuidString] = times
            }
        }
        current.progress.daysTouched = Array(Set(current.progress.daysTouched + answer.daysTouched)).sorted()
        loaded = current
        let summary = counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        ImportLog.logger.info("""
        Import batch: \(plans, privacy: .public) plans, \(sessions, privacy: .public) sessions, \
        \(bytes, privacy: .public) bytes: \(summary, privacy: .public), \(unanswered, privacy: .public) not named, \
        request \(answer.requestID ?? "-", privacy: .public)
        """)
        await store(current.progress, finished: nil)
    }

    /// Items the platform refused (or that can't be sent): kept with the request's status and ID until Retry.
    private func refuse(_ ids: [UUID], reason: String?, error: Error?, job jobID: UUID) async {
        guard var current = loaded, current.jobID == jobID else { return }
        let api = error as? APIError
        for id in ids where current.progress.isPending(id) {
            current.progress[id] = ImportJobProgress.Item(phase: .rejected, reason: reason, status: api?.status,
                                                       requestID: api?.requestID)
        }
        if let error { current.progress.lastFailure = failure(error) }
        loaded = current
        ImportLog.logger.info("""
        Import items refused: \(ids.count, privacy: .public), status \(api?.status ?? 0, privacy: .public), \
        request \(api?.requestID ?? "-", privacy: .public)
        """)
        await store(current.progress, finished: nil)
    }

    /// What a failed request means (API.md → Errors). True: the pass goes on (the items were refused).
    private func failed(_ ids: [UUID], _ error: Error, job jobID: UUID) async -> Bool {
        if error as? TrainImportError == .notPublished || (error as? APIError)?.status == 404 {
            stop(.notAvailable)
            return false
        }
        let api = error as? APIError
        // Every `403` holds, without a code this build knows too: health data waits, never dropped (ADR 0008). Only
        // the gates the user can answer (consent, the invite) are `gated`; any other is `held`.
        if api?.status == 403 {
            record(failure(error))
            stop(api?.code.map { ImportPause.gated(.gate($0)) } ?? .held)
            return false
        }
        switch FailureKind.of(error) {
        case .cancelled:
            // Never a refusal: the items stay pending for the next pass.
            return false
        case .gate:
            record(failure(error))
            stop(api?.code.map { ImportPause.gated(.gate($0)) } ?? .held)
            return false
        case .signedOut:
            record(failure(error))
            stop(.waitingForAccount)
            return false
        case .transient:
            transientFailure(error)
            return false
        case .other, .appTooOld:
            if case .notConfigured? = api {
                stop(.waitingForAccount)
                return false
            }
            await refuse(ids, reason: nil, error: error, job: jobID)
            return true
        }
    }

    private func record(_ failure: ImportFailure) {
        guard var current = loaded else { return }
        current.progress.lastFailure = failure
        loaded = current
    }

    private func failure(_ error: Error) -> ImportFailure {
        let api = error as? APIError
        return ImportFailure(at: env?.clock.now() ?? Date(), status: api?.status, code: api?.code?.rawValue,
                             requestID: api?.requestID, kind: FailureKind.of(error))
    }

    // MARK: enrolment and the end

    /// "Make this my active plan": once its plan is done (or was kept as RYFT's copy). False stops the pass.
    private func enrol(api: PlatformAPI, generation: Generation, revalidated: inout Bool) async -> Bool {
        guard var current = loaded, let planID = current.plan.enrolPlanID, !current.progress.enrolled else { return true }
        // Nothing else may still be pending: the plan goes in the first requests, and the enrolment last.
        guard !current.plan.plans.contains(where: { current.progress.isPending($0.id) }) else { return true }
        if current.plan.plans.contains(where: { $0.id == planID }), current.progress[planID]?.phase != .done {
            // Its plan was refused or blocked: there's nothing to enrol in.
            current.progress.enrolled = true
            loaded = current
            await store(current.progress, finished: nil)
            return true
        }
        guard await isOpen(generation, revalidated: &revalidated) else { return false }
        let jobID = current.jobID
        do {
            _ = try await api.enroll(planID: planID)
            guard isCurrent(generation, job: jobID), var updated = loaded else { return false }
            updated.progress.enrolled = true
            updated.progress.enrolledPlanID = planID
            loaded = updated
            ImportLog.logger.info("Import: enrolled in the imported plan")
            await store(updated.progress, finished: nil)
            return isCurrent(generation, job: jobID)
        } catch {
            guard isCurrent(generation, job: jobID) else { return false }
            switch FailureKind.of(error) {
            case .other where (error as? APIError)?.status == 403:
                return await failed([], error, job: jobID)
            case .other, .appTooOld:
                // Refused: the plan is there; enrolling is the user's to do in Plans.
                guard var updated = loaded else { return false }
                updated.progress.enrolled = true
                updated.progress.lastFailure = failure(error)
                loaded = updated
                await store(updated.progress, finished: nil)
                return true
            case .cancelled, .gate, .signedOut, .transient:
                return await failed([], error, job: jobID)
            }
        }
    }

    /// Nothing pending: the job is finished, the library and history are read again, and the days are rescored.
    private func finishIfDone(_ generation: Generation) async {
        guard let current = loaded, !Self.hasWork(current), let row = job(id: current.jobID), row.finishedAt == nil else {
            return
        }
        await store(current.progress, finished: env?.clock.now() ?? Date())
        guard generation == self.generation else { return }
        let done = current.progress.items.values.filter { $0.phase == .done }.count
        let rejected = current.progress.items.values.filter { $0.phase == .rejected || $0.phase == .blocked }.count
        ImportLog.logger.info("Import finished: \(done, privacy: .public) done, \(rejected, privacy: .public) refused")
        library?.invalidateHistories()
        let days = current.progress.daysTouched
        if let library { Task { await library.refresh() } }
        if !days.isEmpty, let coordinator { Task { await coordinator.run(.daysChanged(days: days)) } }
    }

    // MARK: retries

    private func transientFailure(_ error: Error?) {
        let api = error as? APIError
        failures += 1
        let step = Self.backoff[min(failures, Self.backoff.count) - 1].timeInterval
        var wait = step + random(0...(step * Self.jitter))
        // `Retry-After` is honoured up to the backoff's ceiling (1 h): a larger one waits for a later trigger.
        if let retryAfter = api?.retryAfter {
            wait = max(wait, min(TimeInterval(retryAfter), Self.backoff[Self.backoff.count - 1].timeInterval))
        }
        let due = (env?.clock.now() ?? Date()).addingTimeInterval(wait)
        retryAt = due
        lostConnection = error.map { _ in api?.status == nil } ?? false
        if let error { record(failure(error)) }
        ImportLog.logger.info("""
        Import paused: \(error.map { FailureKind.of($0).rawValue } ?? "check", privacy: .public), status \
        \(api?.status ?? 0, privacy: .public), request \(api?.requestID ?? "-", privacy: .public)
        """)
        if let env, error != nil, api?.status == nil, !env.connectivity.isOnline {
            stop(.offline)
        } else {
            stop(.retrying(at: due))
        }
        scheduleRetry(at: due)
    }

    private func resetRetry() {
        failures = 0
        retryAt = nil
        lostConnection = false
        retryTask?.cancel()
        retryTask = nil
    }

    /// Backoff ends now (Retry, a reconnect after a lost connection); the failure count stays.
    private func makeDue() {
        retryAt = nil
        retryTask?.cancel()
        retryTask = nil
        if case .retrying? = pause { pause = nil }
    }

    /// One timer, until `due` on the environment's clock however late it starts.
    private func scheduleRetry(at due: Date) {
        retryTask?.cancel()
        guard let env else { return }
        let generation = generation, clock = env.clock
        retryTask = Task { [weak self] in
            let left = due.timeIntervalSince(clock.now())
            if left > 0 { try? await clock.sleep(for: .seconds(left)) }
            guard !Task.isCancelled, let self, generation == self.generation else { return }
            self.retryAt = nil
            self.pause = nil
            await self.resume()
        }
    }

    // MARK: status

    /// Cost: one pass over the job's items on the main actor, after each request and state change; at the limits
    /// (10,000 sessions) a few milliseconds each time. `hasWork` is the same scan.
    private func refreshStatus() {
        guard let env, let current = loaded, current.account == currentAccount, let row = job(id: current.jobID) else {
            status = nil
            return
        }
        let plan = current.plan, progress = current.progress
        func counts(_ ids: [UUID]) -> ImportItemCounts {
            var counts = ImportItemCounts()
            for id in ids {
                switch progress[id]?.phase {
                case .done?: counts.done += 1
                case .rejected?: counts.rejected += 1
                case .blocked?: counts.blocked += 1
                case .duplicate?: continue
                case nil: break
                }
                counts.total += 1
            }
            return counts
        }
        var rejected: [ImportItemSummary] = []
        var duplicates: [ImportItemSummary] = []
        func summarise(_ id: UUID, _ kind: ImportItemSummary.Kind, _ title: String, _ date: Date?) {
            guard let item = progress[id] else { return }
            switch item.phase {
            case .rejected, .blocked:
                rejected.append(ImportItemSummary(id: id, kind: kind, title: title, date: date, reason: item.reason,
                                                  requestID: item.requestID, blocked: item.phase == .blocked))
            case .duplicate:
                duplicates.append(ImportItemSummary(id: id, kind: kind, title: title, date: date, reason: nil,
                                                    requestID: nil, blocked: false))
            case .done:
                break
            }
        }
        for exercise in plan.exercises { summarise(exercise.id, .exercise, exercise.name, nil) }
        for item in plan.plans { summarise(item.id, .plan, item.name, nil) }
        for session in plan.sessions { summarise(session.id, .session, session.title, session.startedAt) }
        let phase: ImportJobStatus.Phase
        if !Self.hasWork(current) {
            phase = .finished
        } else if pass != nil, let activity {
            phase = activity == .preparing ? .preparing : .uploading
        } else if let pause {
            phase = .paused(pause)
        } else if pass != nil {
            phase = .uploading
        } else {
            phase = .paused(livePause(env: env, account: current.account))
        }
        let sentPlans = plan.plans.map(\.id).filter { progress[$0]?.phase == .done }
        let setsDone = plan.sessions.filter { progress[$0.id]?.phase == .done }
            .reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
        let planSummaries = plan.plans.map { item in
            let state: ImportPlanSummary.State = switch progress[item.id]?.phase {
            case .done?: .done
            case .rejected?: .rejected
            case .blocked?: .blocked
            case .duplicate?, nil: .pending
            }
            return ImportPlanSummary(id: item.id, name: item.name, weeks: item.weeks, daysPerWeek: item.daysPerWeek, state: state)
        }
        status = ImportJobStatus(
            phase: phase, createdAt: row.createdAt, source: ImportFormatID(rawValue: row.source), timeZoneID: row.timeZoneID,
            exercises: counts(plan.exercises.map(\.id)), plans: counts(plan.plans.map(\.id)),
            sessions: counts(plan.sessions.map(\.id)), setsDone: setsDone, planSummaries: planSummaries,
            skipped: plan.skipped, rejected: rejected,
            duplicatesFound: duplicates, lastFailure: progress.lastFailure, planIDs: sentPlans,
            enrolledPlanID: progress.enrolledPlanID,
            resultSeen: row.resultSeen)
    }

    /// Why nothing runs, when no pass has said so yet (a job loaded at launch).
    private func livePause(env: AppEnvironment, account: String) -> ImportPause {
        if !env.flags.isOn(.trainImport) || !client(for: account, env: env).publishesTrainImport { return .notAvailable }
        if !env.connectivity.isOnline { return .offline }
        if let hold = gate(.data) { return .gated(hold) }
        return .retrying(at: retryAt)
    }

    // MARK: off the main actor

    /// Distinct exercises with at least one completed set.
    nonisolated static func performedExercises(_ session: TrainSession) -> Set<UUID> {
        Set(session.exercises.filter { $0.sets.contains { $0.completedAt != nil } }.map(\.exerciseId))
    }

    @concurrent
    private static func encodeJob(_ plan: ImportUploadPlan) async -> (payload: Data, progress: Data)? {
        MainThread.assertOff("Encoding an import job")
        guard let payload = try? APIClient.jsonEncoder.encode(plan),
              let progress = try? progressEncoder.encode(ImportJobProgress()) else { return nil }
        return (payload, progress)
    }

    @concurrent
    private static func decodeJob(_ payload: Data, _ progress: Data) async -> (plan: ImportUploadPlan, progress: ImportJobProgress)? {
        MainThread.assertOff("Decoding an import job")
        guard let plan = try? APIClient.jsonDecoder.decode(ImportUploadPlan.self, from: payload),
              let state = try? progressDecoder.decode(ImportJobProgress.self, from: progress) else { return nil }
        return (plan, state)
    }

    @concurrent
    private static func encodeProgress(_ progress: ImportJobProgress) async -> Data? {
        try? progressEncoder.encode(progress)
    }

    @concurrent
    private static func encodeRequest(_ request: TrainImportRequest) async -> Data? {
        MainThread.assertOff("Encoding an import request")
        return try? APIClient.jsonEncoder.encode(request)
    }

    /// Plain keys (the snake_case coders would rewrite the ids used as keys) and ISO 8601 dates.
    nonisolated private static var progressEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated private static var progressDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// One background task for the request in flight, ended exactly once (by the pass or by the expiry).
@MainActor
private final class ImportBackgroundTask {
    private let app: BackgroundTaskRunning
    private var id = UIBackgroundTaskIdentifier.invalid

    init(app: BackgroundTaskRunning) { self.app = app }

    func begin(onExpiry: @escaping @MainActor () -> Void) {
        id = app.beginBackgroundTask(withName: "Finish the training import") { [weak self] in
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
