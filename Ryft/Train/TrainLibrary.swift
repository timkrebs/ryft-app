// Exercises, plans and today's prescription, cached for offline browsing in the
// gym. Screens read the cached copy at once; `refresh()` (app active) updates it.
import Foundation
import Observation

@MainActor
@Observable
final class TrainLibrary {
    static let shared = TrainLibrary(outbox: { .shared })

    private(set) var exercises: [Exercise] = []
    private(set) var catalog: PlansOverview?
    private(set) var today: PlanToday?
    /// A refresh is running. Counted: one that ends for a binding that's over doesn't end the next binding's.
    var isLoading: Bool { refreshes > 0 }
    private var refreshes = 0
    /// The Plans page's message and the actions' (save, enrol, pause, delete, a custom exercise): a refresh's first failure
    /// or the last action's, with its status and request ID. Never a page's own read (`loadPlan`).
    var error: String?
    var errorDetails: String?

    let store: TrainStore
    /// The read pipeline (`ScreenModels` sets the app's): Train's reads share its budget, retries
    /// and per-resource record. Without one (tests) each read goes straight to the source.
    @ObservationIgnored var reads: ReadScheduler?
    private let remoteProvider: () -> TrainDataSource
    /// Train's outbox on the same store, where a custom exercise's `POST` is queued (O1) and a plan save waits for it.
    private let outbox: @MainActor () -> TrainSyncService
    /// How long a plan save waits for the custom exercises it names (`savePlan`).
    private let exerciseWait: Duration
    /// The histories read this run, by exercise: a memo (`checkHistories` says whose they are), not state a view observes.
    @ObservationIgnored private var histories: [UUID: ExerciseHistory] = [:]
    /// Whose `histories` are (`checkHistories`).
    @ObservationIgnored private var currentMark: HistoriesMark?
    /// Where this phone remembers the paused plan (`pausedPlanID`): the app's `UserDefaults.standard`. A test's library has
    /// a suite of its own, so tests running side by side never share the key.
    private let defaults: UserDefaults

    /// The longest custom exercise name the platform takes (API.md: `name` 1–80 characters; it counts Unicode scalars
    /// of the trimmed name).
    nonisolated static let maxExerciseName = 80

    init(store: TrainStore? = nil, remote: (() -> TrainDataSource)? = nil, outbox: @escaping @MainActor () -> TrainSyncService,
         exerciseWait: Duration = .seconds(10), restore: Bool = true, defaults: UserDefaults = .standard) {
        self.store = store ?? .shared
        self.defaults = defaults
        self.remoteProvider = remote ?? { TrainSource.current }
        self.outbox = outbox
        self.exerciseWait = exerciseWait
        if restore {
            exercises = self.store.exercises()
            catalog = self.store.document(PlansOverview.self, key: Self.catalogKey)
            today = self.store.document(PlanToday.self, key: Self.todayKey)
        }
    }

    private var remote: TrainDataSource { remoteProvider() }

    var activeEnrollment: Enrollment? { catalog?.active }

    /// The active plan's detail, once loaded (`loadPlan`).
    var activePlan: Plan? {
        guard let id = activeEnrollment?.planId else { return nil }
        return plan(id: id)
    }

    /// The active plan's name, from the overview (no detail needed).
    var activePlanName: String? {
        guard let id = activeEnrollment?.planId else { return nil }
        return catalog?.summary(id: id)?.name ?? store.plan(id: id)?.name
    }

    /// A plan's detail from the offline cache.
    func plan(id: UUID) -> Plan? { store.plan(id: id) }

    func exercise(id: UUID) -> Exercise? {
        exercises.first { $0.id == id } ?? store.exercise(id: id)
    }

    // MARK: refresh

    /// App active / pull to refresh. Each part (exercises, plans, today's plan day) succeeds or
    /// fails on its own; the cache stays. The message is the first failure's, if any.
    ///
    /// The refresh is its binding's (code review S1): once a sign-out, another account, a wipe or the Demo data switch ends
    /// it, the parts still to come send nothing (`fetch`), and neither the message nor its clearing is written: they're the
    /// next binding's now. `userInitiated`: pull to refresh and Try again, which go through a `Retry-After`'s hold.
    func refresh(userInitiated: Bool = false) async {
        refreshes += 1
        defer { refreshes -= 1 }
        let client = client()
        var failure: Error?
        var cancelled = false
        func note<T>(_ outcome: Fetched<T>, _ write: (T) -> Void) {
            switch outcome {
            case .answer(let value): write(value)
            case .failed(let error): failure = failure ?? error
            case .cancelled: cancelled = true
            case .declined: break
            }
        }
        note(await fetch("exercises", from: client, userInitiated: userInitiated) { try await $0.exercises() }) { list in
            store.cache(exercises: list)
            exercises = store.exercises()
        }
        let plans = await fetch("plans", from: client, userInitiated: userInitiated) { try await $0.plans() }
        note(plans) { c in
            catalog = c
            store.saveDocument(c, key: Self.catalogKey)
        }
        note(await fetch("plans/today", from: client, userInitiated: userInitiated) { try await $0.planToday() }) {
            setToday($0)
        }
        guard client.isCurrent else { return }
        switch plans {
        case .declined(let why): plansDeclined = why
        case .answer, .failed: plansDeclined = nil
        case .cancelled: break
        }
        if let failure {
            self.error = failure.localizedDescription
            self.errorDetails = failure.diagnosticDetails
        } else if !cancelled {
            error = nil
            errorDetails = nil
        }
    }

    /// Why the last refresh got no plans overview without a failure: offline, held back by a `Retry-After`, or for a
    /// binding that ended. Nil when the platform answered or the read failed (`error` says why). Plans tells offline apart
    /// from held back with nothing cached (code review N4).
    private(set) var plansDeclined: Declined?

    /// Why a read wrote nothing of an answer (`fetch`).
    enum Declined: Equatable {
        /// Offline, or signed out: nothing could be sent.
        case offline
        /// Online, but a `Retry-After` still holds automatic reads back (`ReadScheduler.Hold`): nothing was sent, and a
        /// user's Try again goes through. `details`: the failure that set the hold, its status and request ID.
        case heldBack(details: String?)
        /// The answer, or the failure, came for a binding that's over.
        case over
    }

    /// How one read ended (`fetch`).
    private enum Fetched<T> {
        /// The platform answered, for the binding that asked.
        case answer(T)
        /// Nothing was sent (`Declined`), or the answer came for a binding that's over: the copy on this phone is all
        /// there is, and nothing of the answer is written.
        case declined(Declined)
        case failed(Error)
        /// The caller went away (a screen that disappeared, a push) or a reset stopped the read: nothing changes.
        case cancelled

        var error: Error? {
            if case .failed(let error) = self { return error }
            return nil
        }

        /// The iPhone is offline: nothing could be sent, or the request failed for want of a connection. Not when the read
        /// was held back or failed online (Train's pages say "Offline" only then).
        var offline: Bool {
            switch self {
            case .declined(.offline): return true
            case .failed(let error): return SleepLoadFailure.lostConnection(error)
            default: return false
            }
        }

        /// Nothing was sent because a `Retry-After` holds automatic reads back, online.
        var heldBack: Bool {
            if case .declined(.heldBack) = self { return true }
            return false
        }

        /// The status and request ID for Details: the failure's, or the one that set a hold.
        var details: String? {
            switch self {
            case .failed(let error): return error.diagnosticDetails
            case .declined(.heldBack(let details)): return details
            default: return nil
            }
        }
    }

    /// The client in use and its binding, read in one step (`savePlan`'s pattern): an answer is written only while the
    /// binding is still the one that asked.
    @MainActor
    private struct Client {
        let source: TrainDataSource
        let outbox: TrainSyncService
        let binding: TrainSyncService.Binding

        /// No sign-out, other account, wipe or Demo data switch since the read began.
        var isCurrent: Bool { outbox.binding == binding }
    }

    private func client() -> Client {
        let outbox = outbox()
        return Client(source: remote, outbox: outbox, binding: outbox.binding)
    }

    /// Whose requests go now (`TrainSyncService.Binding`): a caller that awaits Train compares it before and after.
    var binding: TrainSyncService.Binding { outbox().binding }

    /// Train's read `id` ("plans", "plan/<id>") for `binding`'s owner: the account's id or the demo's, never shown. Two
    /// owners' reads of one resource are two flights (`fetch`).
    static func readKey(_ id: String, for binding: TrainSyncService.Binding) -> ReadKey {
        ReadKey(.train, id: "\(binding.owner ?? "signed-out")/\(id)")
    }

    /// One read through the read pipeline when there is one (`ScreenModels` sets the app's): offline, signed out or held
    /// back nothing is sent and it ends at once (`.declined`), and a try uses the fail-fast session, never one that waits
    /// minutes for a network. Without one (tests) it goes straight to the source. An answer or a failure that arrives after
    /// a sign-out, another account, a wipe or the Demo data switch is `.declined`: the caller writes none of it into the
    /// store or memory, which are the next binding's now (security review S-1). A cancelled caller (or a reset of the
    /// pipeline) is `.cancelled`, however the request ended.
    ///
    /// A client whose binding is already over sends nothing (code review S1: a refresh that goes on after the switch), and
    /// a read joins only a flight of its own binding: the key carries the owner, so the Demo data side and the account
    /// never share an answer, whoever started the flight (`ReadKey`, `ReadScheduler.enter`).
    ///
    /// Why nothing was sent is the pipeline's to say, before the read (`ReadScheduler.hold`): offline, or held back online,
    /// with the Details of the failure that set the hold (code review N4).
    private func fetch<T: Sendable>(_ id: String, from client: Client, userInitiated: Bool = false,
                                    _ request: @escaping @MainActor (TrainDataSource) async throws -> T) async -> Fetched<T> {
        guard client.isCurrent else { return .declined(.over) }
        let source = client.source
        do {
            let value: T?
            if let reads {
                // A caller that went away is `.cancelled`, held back or not (as `run` would say).
                try Task.checkCancellation()
                let key = Self.readKey(id, for: client.binding)
                switch reads.hold(key, userInitiated: userInitiated) {
                case .offline?: return .declined(.offline)
                case .heldBack?: return .declined(.heldBack(details: JournalSheetModel.readDetails(reads.states[.train])))
                case nil: break
                }
                value = try await reads.run(key, userInitiated: userInitiated) { try await request(source) }
            } else {
                value = try await request(source)
            }
            guard client.isCurrent else { return .declined(.over) }
            guard let value else { return .declined(.offline) }
            return .answer(value)
        } catch where error.isCancellation || Task.isCancelled {
            return .cancelled
        } catch {
            return client.isCurrent ? .failed(error) : .declined(.over)
        }
    }

    private func setToday(_ fresh: PlanToday?) {
        today = fresh
        if let fresh { store.saveDocument(fresh, key: Self.todayKey) } else { store.removeDocument(key: Self.todayKey) }
    }

    /// Today's plan day from `client`, written only while its binding is still the one in use.
    private func loadToday(from client: Client) async throws {
        let fresh = try await client.source.planToday()
        guard client.isCurrent else { return }
        setToday(fresh)
    }

    /// The cached plan day was fetched on another day (it has no date of its own).
    func todayIsStale(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard today != nil, let at = store.documentFetchedAt(key: Self.todayKey) else { return false }
        return !calendar.isDate(at, inSameDayAs: now)
    }

    /// Today's plan day again, given at most `limit`: a quick start shouldn't wait on a slow network.
    /// `false` when it couldn't be fetched in time.
    func refreshToday(limit: Duration = .seconds(3)) async -> Bool {
        let client = client()
        let fetch = Task { @MainActor in try await self.loadToday(from: client) }
        let deadline = Task {
            try? await Task.sleep(for: limit)
            fetch.cancel()
        }
        defer { deadline.cancel() }
        return (try? await fetch.value) != nil
    }

    /// Plan detail (days → exercises), cached afterwards. A cached one shows at once and is read again quietly, through the
    /// pipeline and for this binding only. One that isn't cached is read: `.offline` when nothing could be sent (or the
    /// answer came for a binding that's over), `.failed` with its sentence and Details, `.cancelled` when the caller went
    /// away.
    ///
    /// A failure is the caller's alone (R4 re-check): the plan page keeps it (`PlanDetailViewModel.loadFailure`), and Start
    /// workout's options go without the plan's days. Neither is written to `error` and `errorDetails`, the Plans page's and
    /// the actions' message: plan X's failure would show on Plans, whose Try again reads the plans and not X, and in plan
    /// Y's actions block.
    func loadPlan(id: UUID, userInitiated: Bool = false) async -> PlanRead {
        let client = client()
        if let p = store.plan(id: id), !p.days.isEmpty {
            // Cached: show it, refresh quietly, for this binding only.
            planRefresh = Task {
                if case .answer(let fresh) = await fetch("plan/\(id.uuidString)", from: client, { try await $0.plan(id: id) }) {
                    store.cache(plans: [fresh])
                }
            }
            return .plan(p)
        }
        switch await fetch("plan/\(id.uuidString)", from: client, userInitiated: userInitiated, { try await $0.plan(id: id) }) {
        case .answer(let p):
            store.cache(plans: [p])
            return .plan(p)
        case .declined(.heldBack(let details)):
            // Online, held back by a `Retry-After`: the failed state, whose Try again goes through (code review N4).
            return .failed(message: RefreshIssue.Reason.busy.message, details: details)
        case .declined:
            return .offline
        case .cancelled:
            return .cancelled
        case .failed(let error):
            return .failed(message: error.localizedDescription, details: error.diagnosticDetails)
        }
    }

    /// The quiet read of a cached plan that `loadPlan` started last (tests await it).
    @ObservationIgnored private(set) var planRefresh: Task<Void, Never>?

    /// How `loadPlan` ended.
    enum PlanRead: Equatable {
        case plan(Plan)
        /// Not cached, and nothing was sent (offline): nothing to show until it's read. Held back online is `failed`.
        case offline
        /// Not cached, and the read failed: why, and its status and request ID for Details. The plan page keeps them
        /// (code review N1); `error`, the Plans page's, never gets them.
        case failed(message: String, details: String?)
        /// The caller went away: nothing changes.
        case cancelled

        var plan: Plan? {
            if case .plan(let p) = self { return p }
            return nil
        }
    }

    /// The exercise's history: the one read this run, else the platform's, else the copy on this phone.
    func history(for exerciseID: UUID) async -> ExerciseHistory? {
        (await historyRead(for: exerciseID))?.value ?? cachedHistory(for: exerciseID)
    }

    /// Already-loaded history, for instant paint.
    func cachedHistory(for exerciseID: UUID) -> ExerciseHistory? {
        checkHistories()
        return histories[exerciseID] ?? store.document(ExerciseHistory.self, key: Self.historyKey(exerciseID))
    }

    /// History shows new numbers after a session.
    func invalidateHistories() { histories = [:] }

    /// Whose the histories in memory are and which completion they're from before (`checkHistories`).
    private struct HistoriesMark: Equatable {
        let binding: TrainSyncService.Binding
        let completed: UUID?
    }

    private func historiesMark() -> HistoriesMark {
        let outbox = outbox()
        return HistoriesMark(binding: outbox.binding, completed: outbox.lastCompletion?.id)
    }

    /// The histories in memory count as fresh (`historyRead`) only for the binding that read them and only until the
    /// platform answers a session's completion: after a sign-out, another account or the Demo data switch they're another
    /// binding's (security review N-1), and after a completion their e1RM and records are from before that workout (B
    /// review N3). Either way they go, and the next read asks the platform.
    private func checkHistories() {
        let mark = historiesMark()
        guard mark != currentMark else { return }
        currentMark = mark
        histories = [:]
    }

    // MARK: sessions

    /// History's window: the last 90 days, the one window the session list is read and cached for (its "last 90 days").
    nonisolated static let sessionsWindowDays = 90

    /// Finished sessions of the last 90 days, newest first: the server's list
    /// plus anything logged here that hasn't reached it yet (the local copy wins).
    func sessions() async -> [SessionSummary] {
        (await sessionsRead())?.value ?? cachedSessions(now: .now)
    }

    /// Sessions already known for instant paint.
    func cachedSessions() -> [SessionSummary] {
        Self.merged(local: store.completedSessions().map(\.summary),
                    remote: store.document([SessionSummary].self, key: Self.sessionsKey) ?? [])
    }

    /// The demo's discard (ADR 0019, `TrainCoordinator.discardDemoWorkouts`): these sessions leave what Train shows
    /// offline, the cached list (history, "Last: …") and every exercise history (its sessions and records), in the store
    /// and in memory. Only these ids; the rest of each document, and when it was fetched, stay.
    func forgetSessions(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        if let list = store.document([SessionSummary].self, key: Self.sessionsKey) {
            let kept = list.filter { !ids.contains($0.id) }
            if kept.count != list.count { resave(kept, key: Self.sessionsKey) }
        }
        for key in store.documentKeys(prefix: Self.historyPrefix) {
            guard var history = store.document(ExerciseHistory.self, key: key) else { continue }
            let before = (history.sessions.count, history.prs.count, history.e1rm.count)
            // A chart point has only its day: a day one of them was on goes (another workout that day comes back with
            // the next fetch), so the chart and "current" never show their numbers.
            let days = Set(history.sessions.filter { ids.contains($0.sessionId) }.map(\.date))
            history.sessions.removeAll { ids.contains($0.sessionId) }
            history.prs.removeAll { $0.sessionId.map(ids.contains) == true }
            history.e1rm.removeAll { days.contains($0.day) }
            if (history.sessions.count, history.prs.count, history.e1rm.count) != before { resave(history, key: key) }
        }
        // The in-memory copies are read again, from the documents just filtered or the platform.
        invalidateHistories()
    }

    private func resave<T: Encodable>(_ value: T, key: String) {
        store.saveDocument(value, key: key, at: store.documentFetchedAt(key: key) ?? .now)
    }

    /// Pure (My Day's assembler calls it off the main actor).
    nonisolated static func merged(local: [SessionSummary], remote: [SessionSummary]) -> [SessionSummary] {
        let localIDs = Set(local.map(\.id))
        return (local + remote.filter { !localIDs.contains($0.id) && $0.status == .completed })
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// A whole session (the list may carry summaries without exercises): the one logged here, else the platform's.
    func session(id: UUID) async -> TrainSession? {
        (await sessionRead(id: id))?.value
    }

    /// `session(id:)`, saying whether the platform answered and why not (the session detail's failure and its Details).
    /// Nil when the caller was cancelled.
    func sessionRead(id: UUID, userInitiated: Bool = false) async -> TrainRead<TrainSession?>? {
        if let local = store.session(id: id) { return TrainRead(value: local.wire, fresh: true, fetchedAt: nil) }
        let fetched = await fetch("session/\(id.uuidString)", from: client(), userInitiated: userInitiated) {
            try await $0.session(id: id)
        }
        switch fetched {
        case .cancelled: return nil
        case .answer(let s): return TrainRead(value: s, fresh: true, fetchedAt: nil)
        case .declined, .failed:
            return TrainRead(value: nil, fresh: false, fetchedAt: nil, failure: fetched.details, offline: fetched.offline,
                             heldBack: fetched.heldBack)
        }
    }

    /// The most recent finished session, for "Repeat last session".
    func lastSession() async -> TrainSession? {
        var latest = cachedSessions().first
        if latest == nil { latest = await sessions().first }
        guard let latest else { return nil }
        return await session(id: latest.id)
    }

    // MARK: a custom exercise (queued)

    /// Cached first, so it can be logged at once, offline too. Train's outbox sends it, ahead of every workout that uses
    /// it, and the answer replaces the cached row (O1); a refusal is kept there, never shown here. Returns the cached
    /// copy at once (the sheet adds it to the workout). Nil, with `error`, for a name the platform would refuse (empty,
    /// or over 80 characters): nothing is cached or queued. A NUL in the names is dropped first (API.md → Text: the
    /// platform answers `422` to it).
    func createExercise(_ exercise: Exercise) async -> Exercise? {
        var e = exercise
        e.name = Self.withoutNUL(e.name)
        e.nameEn = Self.withoutNUL(e.nameEn)
        e.nameDe = Self.withoutNUL(e.nameDe)
        guard Self.isValidName(e.name) else {
            error = String(localized: "Give the exercise a name of up to 80 characters.")
            errorDetails = nil
            return nil
        }
        let outbox = outbox()
        assert(outbox.store === store, "the library and its outbox share one store")
        store.cache(exercises: [e])
        exercises = store.exercises()
        // The outbox caches it too: the row its `POST` sends.
        let replay = outbox.queueExercise(e)
        if let replay {
            // The platform's copy once the replay ends, however it ended.
            Task { [weak self] in
                await replay.value
                guard let self else { return }
                exercises = store.exercises()
            }
        }
        return e
    }

    /// Without NUL, trimmed, not empty and at most `maxExerciseName` Unicode scalars, as the platform counts.
    nonisolated static func isValidName(_ name: String) -> Bool {
        let trimmed = withoutNUL(name).trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.unicodeScalars.count <= maxExerciseName
    }

    /// `text` without U+0000, which the platform can't store (API.md → Text): what the app sends of typed text.
    nonisolated static func withoutNUL(_ text: String) -> String {
        guard text.unicodeScalars.contains("\u{0}") else { return text }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { $0 != "\u{0}" })
        return String(scalars)
    }

    // MARK: actions (online; the screen shows the error)

    /// A custom exercise the plan names that's still queued goes first, for at most `exerciseWait`: the platform refuses
    /// a plan with an exercise it doesn't have (ADR 0022 §7). Offline, or after the wait, the plan goes as before. The
    /// client and the binding are read before the wait: a sign-out, another account or the Demo data switch meanwhile
    /// (or a cancelled caller) drops the save, and its answer is cached only for the binding that sent it.
    @discardableResult
    func savePlan(_ p: Plan) async -> Bool {
        let named = Set(p.days.flatMap { $0.exercises.map(\.exercise.id) })
        let outbox = outbox(), src = remote, binding = outbox.binding
        await outbox.exercisesSent(named, upTo: exerciseWait)
        guard outbox.binding == binding, !Task.isCancelled else { return false }
        do {
            let saved = try await src.savePlan(p)
            guard outbox.binding == binding else { return false }
            store.cache(plans: [saved])
            await reloadCatalog(from: client())
            return true
        } catch where error.isCancellation || outbox.binding != binding {
            return false
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
            return false
        }
    }

    /// `true` when it's gone (the screen closes). A sign-out, another account or the Demo data switch before the answer
    /// writes nothing: neither the store, nor the message (security review N-A).
    ///
    /// `DELETE /v1/plans/{id}` removes the plan and any enrolment in it: its summary goes from the plans overview, and so
    /// does the enrolment, active or the paused one only this phone remembers (`pausedPlanID`), so Plans offers no Resume
    /// of a plan that's gone.
    @discardableResult
    func deletePlan(_ p: Plan) async -> Bool {
        await perform({ try await $0.deletePlan(id: p.id) }, then: { _ in
            store.removePlan(id: p.id)
            if activeEnrollment?.planId == p.id { enrollmentEnded() }
            if defaults.string(forKey: Self.pausedKey) == p.id.uuidString {
                defaults.removeObject(forKey: Self.pausedKey)
            }
            patchCatalog { $0.mine.removeAll { $0.id == p.id } }
        })
    }

    /// Enrol (switching replaces the active plan; the screen confirms first).
    @discardableResult
    func enroll(in p: Plan) async -> Bool {
        await perform({ try await $0.enroll(planID: p.id) }, then: enrolled)
    }

    /// The plan paused last. `GET /v1/plans` only reports the active enrolment,
    /// so the app remembers what Resume should continue.
    var pausedPlanID: UUID? {
        if let e = activeEnrollment, e.status == .paused { return e.planId }
        guard activeEnrollment == nil else { return nil }
        return defaults.string(forKey: Self.pausedKey).flatMap(UUID.init(uuidString:))
    }

    var isPaused: Bool { pausedPlanID != nil }

    /// Pause: `DELETE /v1/plans/enrollment`. Resume: enrolling in the same plan
    /// again continues where it stopped.
    @discardableResult
    func setPaused(_ paused: Bool) async -> Bool {
        if paused {
            guard let planID = activeEnrollment?.planId else { return false }
            return await perform({ try await $0.pauseEnrollment() }, then: { _ in
                defaults.set(planID.uuidString, forKey: Self.pausedKey)
                enrollmentEnded()
            })
        }
        guard let planID = pausedPlanID else { return false }
        return await perform({ try await $0.enroll(planID: planID) }, then: enrolled)
    }

    /// An action of the binding in use when it starts (security review N-A): its client is read first, and only while that
    /// binding still holds is anything written (`then` with the platform's answer when it worked, before the plans are read
    /// again; the message and its Details when it failed). An answer or a failure after a sign-out, another account, a wipe
    /// or the Demo data switch is dropped and the action says `false`: on the next side's pages there's no paused plan, no
    /// message and no request ID of the side that ended.
    ///
    /// `then` also puts in the plans overview what the action changed, as `GET /v1/plans` now reports it (`patchCatalog`):
    /// if the read after it fails, the old overview would undo the action on screen (R4 re-check: the stale active enrolment
    /// offered Pause again, a deleted plan stayed in the list). The read still follows for what this phone can't tell (the
    /// week and day after a switch, today's plan day), and a failure of it says nothing: the action itself worked, and the
    /// next refresh (app active, pull to refresh) reads the plans again.
    private func perform<Answer>(_ action: (TrainDataSource) async throws -> Answer,
                                 then written: (Answer) -> Void) async -> Bool {
        let client = client()
        do {
            let answer = try await action(client.source)
            guard client.isCurrent else { return false }
            written(answer)
            await reloadCatalog(from: client)
            return true
        } catch where error.isCancellation || !client.isCurrent {
            return false
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
            return false
        }
    }

    /// The plans overview with `change`, in memory and stored: what an action changed, before the read after it.
    private func patchCatalog(_ change: (inout PlansOverview) -> Void) {
        guard var overview = catalog else { return }
        change(&overview)
        catalog = overview
        store.saveDocument(overview, key: Self.catalogKey)
    }

    /// Paused, or its plan deleted: `GET /v1/plans` reports only an active enrolment (none now), and `GET /v1/plans/today`
    /// answers `204` without one.
    private func enrollmentEnded() {
        patchCatalog { $0.active = nil }
        setToday(nil)
    }

    /// Enrolled, switched or resumed: the platform's answer is the active enrolment (a resumed one where it stopped). A plan
    /// day of another enrolment goes; this one's comes with the read after it.
    private func enrolled(_ enrollment: Enrollment) {
        defaults.removeObject(forKey: Self.pausedKey)
        patchCatalog { $0.active = enrollment }
        if let today, today.enrollment.id != enrollment.id { setToday(nil) }
    }

    /// After an action: the plans and today's plan day again from `client`, written only while its binding holds.
    private func reloadCatalog(from client: Client) async {
        guard let c = try? await client.source.plans(), client.isCurrent else { return }
        catalog = c
        store.saveDocument(c, key: Self.catalogKey)
        try? await loadToday(from: client)
    }

    /// After a session completes, the plan advances.
    func sessionCompleted() async {
        invalidateHistories()
        try? await loadToday(from: client())
    }

    func wipe() {
        exercises = []
        catalog = nil
        today = nil
        // The account's last failure and its request ID aren't the next one's (security review N-A).
        error = nil
        errorDetails = nil
        plansDeclined = nil
        defaults.removeObject(forKey: Self.pausedKey)
        histories = [:]
        currentMark = nil
    }

    /// The Demo data switch (RyftApp, security review N-1). Train's cache is one store for both sides (ADR 0019: a demo
    /// store of its own is the follow-up), so what was read for the side that ended goes rather than show as the new side's
    /// own: today's plan day and the plans overview (the active plan), in memory and stored, and the stored session list
    /// and exercise histories (the histories in memory go by themselves, `checkHistories`). Each is read again for this
    /// side: the overview and the plan day by the caller's `refresh()`, the rest when its screen opens. Left for the
    /// follow-up: the exercise library, the plans' details, the paused plan's id (only this phone knows it, API_REQUESTS
    /// Train #2) and the workouts themselves (ending the demo discards its own, ADR 0019).
    func demoModeChanged() {
        histories = [:]
        currentMark = nil
        catalog = nil
        today = nil
        // Nor are the side's failure and its request ID (security review N-A).
        error = nil
        errorDetails = nil
        plansDeclined = nil
        for key in [Self.catalogKey, Self.todayKey, Self.sessionsKey] + store.documentKeys(prefix: Self.historyPrefix) {
            store.removeDocument(key: key)
        }
    }

    private static let sessionsKey = "train.sessions"
    private static let historyPrefix = "train.history."
    private static func historyKey(_ id: UUID) -> String { historyPrefix + id.uuidString }
    private static let pausedKey = "train.pausedPlanID"
    private static let catalogKey = "train.plans"
    private static let todayKey = "train.today"
}

// MARK: - previews

extension TrainLibrary {
    /// Filled from `MockTrain`, in an in-memory store. `outbox`: the caller's service on `store`, so no queue has two
    /// replayers.
    static func preview(store: TrainStore, outbox: TrainSyncService, enrolled: Bool = true) -> TrainLibrary {
        let lib = TrainLibrary(store: store, remote: { MockTrainSource.shared }, outbox: { outbox }, restore: false)
        store.cache(exercises: MockTrain.exercises)
        store.cache(plans: MockTrain.plans)
        lib.exercises = store.exercises()
        lib.catalog = MockTrain.catalog(enrolled: enrolled)
        lib.today = enrolled ? MockTrain.planToday : nil
        return lib
    }
}

// MARK: - reads that say whether they reached the platform

/// One read of Train's history: what to show, and whether the platform answered (`fresh`) or the copy on this phone is all
/// there is. A failed read with nothing cached is an error, not "no workouts" (the API sends empty arrays for none). A read
/// whose caller was cancelled has none (the readers return nil): nothing on screen changes for it.
struct TrainRead<Value> {
    let value: Value
    /// The platform answered this time.
    let fresh: Bool
    /// When the copy shown was fetched; nil when nothing was ever saved (only sessions logged on this phone).
    let fetchedAt: Date?
    /// The failure's status and request ID for Details ("HTTP 503 · Request ID …", `diagnosticDetails`), or those of the
    /// failure whose `Retry-After` held this read back; nil when the read didn't fail, wasn't sent offline or failed
    /// without an answer.
    var failure: String?
    /// The iPhone is offline: nothing was sent, or the request failed for want of a connection. A copy shown after a read
    /// held back or failed online isn't "Offline" (code review N4).
    var offline = false
    /// Nothing was sent because a `Retry-After` holds automatic reads back, online: with nothing cached, the failed state
    /// says RYFT is busy (not "when you're online"), and its Try again goes through.
    var heldBack = false
}

extension TrainLibrary {
    /// The first day of History's window (`sessionsWindowDays`), as `sessionsRead` asks for it.
    nonisolated static func sessionsWindowStart(now: Date) -> Date {
        DayFormat.shift(Calendar.current.startOfDay(for: now), days: -(sessionsWindowDays - 1))
    }

    /// `sessions()`, saying whether the platform answered (History's offline and failed states). The one writer of the
    /// cached list, always for History's 90 days. Nil when the caller was cancelled.
    func sessionsRead(now: Date = .now, userInitiated: Bool = false) async -> TrainRead<[SessionSummary]>? {
        let from = Self.sessionsWindowStart(now: now)
        let fetched = await fetch("sessions/\(DayFormat.string(from: from))", from: client(), userInitiated: userInitiated) {
            try await $0.sessions(from: from, to: now)
        }
        let remoteList: [SessionSummary]
        switch fetched {
        case .cancelled:
            return nil
        case .answer(let list):
            remoteList = list
            store.saveDocument(list, key: Self.sessionsKey)
        case .declined, .failed:
            remoteList = (store.document([SessionSummary].self, key: Self.sessionsKey) ?? []).filter { $0.startedAt >= from }
        }
        var fresh = false
        if case .answer = fetched { fresh = true }
        return TrainRead(value: Self.merged(local: store.completedSessions(from: from).map(\.summary), remote: remoteList),
                         fresh: fresh, fetchedAt: store.documentFetchedAt(key: Self.sessionsKey),
                         failure: fetched.details, offline: fetched.offline, heldBack: fetched.heldBack)
    }

    /// `cachedSessions()` within History's window, so its first paint shows what the read will (nothing that vanishes).
    func cachedSessions(now: Date) -> [SessionSummary] {
        let from = Self.sessionsWindowStart(now: now)
        return cachedSessions().filter { $0.startedAt >= from }
    }

    /// `history(for:)`, saying whether the platform answered (the exercise page's offline and failed states). A history
    /// read earlier in this run for the binding in use, and since the platform's last completion, counts as fresh
    /// (`checkHistories`). Nil when the caller was cancelled.
    func historyRead(for exerciseID: UUID, userInitiated: Bool = false) async -> TrainRead<ExerciseHistory?>? {
        let key = Self.historyKey(exerciseID)
        checkHistories()
        if let h = histories[exerciseID] { return TrainRead(value: h, fresh: true, fetchedAt: store.documentFetchedAt(key: key)) }
        let asked = historiesMark()
        let fetched = await fetch("history/\(exerciseID.uuidString)", from: client(), userInitiated: userInitiated) {
            try await $0.exerciseHistory(id: exerciseID)
        }
        switch fetched {
        case .cancelled:
            return nil
        case .answer(let h):
            store.saveDocument(h, key: key)
            // Kept in memory only if no completion was answered meanwhile: it may be from before that workout.
            checkHistories()
            if currentMark == asked { histories[exerciseID] = h }
            return TrainRead(value: h, fresh: true, fetchedAt: store.documentFetchedAt(key: key))
        case .declined, .failed:
            return TrainRead(value: store.document(ExerciseHistory.self, key: key), fresh: false,
                             fetchedAt: store.documentFetchedAt(key: key), failure: fetched.details, offline: fetched.offline,
                             heldBack: fetched.heldBack)
        }
    }
}
