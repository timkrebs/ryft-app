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
    private(set) var isLoading = false
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
    private var histories: [UUID: ExerciseHistory] = [:]

    /// The longest custom exercise name the platform takes, in Unicode scalars (API.md: `name` 1–80 characters, which
    /// it counts as runes).
    static let maxExerciseName = 80

    init(store: TrainStore? = nil, remote: (() -> TrainDataSource)? = nil, outbox: @escaping @MainActor () -> TrainSyncService,
         exerciseWait: Duration = .seconds(10), restore: Bool = true) {
        self.store = store ?? .shared
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
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let src = remote
        var failure: Error?
        do {
            if let list = try await read("exercises", { try await src.exercises() }) {
                store.cache(exercises: list)
                exercises = store.exercises()
            }
        } catch { failure = failure ?? error }
        do {
            if let c = try await read("plans", { try await src.plans() }) {
                catalog = c
                store.saveDocument(c, key: Self.catalogKey)
            }
        } catch { failure = failure ?? error }
        do {
            if let fresh = try await read("plans/today", { try await src.planToday() }) { setToday(fresh) }
        } catch { failure = failure ?? error }
        if let failure, !failure.isCancellation {
            self.error = failure.localizedDescription
            self.errorDetails = failure.diagnosticDetails
        } else if failure == nil {
            error = nil
            errorDetails = nil
        }
    }

    /// Through the read pipeline when there is one (nil: offline or held back, nothing sent).
    private func read<T: Sendable>(_ id: String, _ fetch: @escaping @MainActor () async throws -> T) async throws -> T? {
        guard let reads else { return try await fetch() }
        return try await reads.run(ReadKey(.train, id: id), fetch)
    }

    private func setToday(_ fresh: PlanToday?) {
        today = fresh
        if let fresh { store.saveDocument(fresh, key: Self.todayKey) } else { store.removeDocument(key: Self.todayKey) }
    }

    private func loadToday(from src: TrainDataSource) async throws {
        setToday(try await src.planToday())
    }

    /// The cached plan day was fetched on another day (it has no date of its own).
    func todayIsStale(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard today != nil, let at = store.documentFetchedAt(key: Self.todayKey) else { return false }
        return !calendar.isDate(at, inSameDayAs: now)
    }

    /// Today's plan day again, given at most `limit`: a quick start shouldn't wait on a slow network.
    /// `false` when it couldn't be fetched in time.
    func refreshToday(limit: Duration = .seconds(3)) async -> Bool {
        let src = remote
        let fetch = Task { @MainActor in try await self.loadToday(from: src) }
        let deadline = Task {
            try? await Task.sleep(for: limit)
            fetch.cancel()
        }
        defer { deadline.cancel() }
        return (try? await fetch.value) != nil
    }

    /// Plan detail (days → exercises), cached afterwards.
    func loadPlan(id: UUID) async -> Plan? {
        if let p = store.plan(id: id), !p.days.isEmpty {
            // Cached: show it, refresh quietly.
            Task { if let fresh = try? await remote.plan(id: id) { store.cache(plans: [fresh]) } }
            return p
        }
        do {
            let p = try await remote.plan(id: id)
            store.cache(plans: [p])
            return p
        } catch where error.isCancellation {
            return nil
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
            return nil
        }
    }

    func history(for exerciseID: UUID) async -> ExerciseHistory? {
        if let h = histories[exerciseID] { return h }
        do {
            let h = try await remote.exerciseHistory(id: exerciseID)
            histories[exerciseID] = h
            store.saveDocument(h, key: Self.historyKey(exerciseID))
            return h
        } catch {
            return store.document(ExerciseHistory.self, key: Self.historyKey(exerciseID))
        }
    }

    /// Already-loaded history, for instant paint.
    func cachedHistory(for exerciseID: UUID) -> ExerciseHistory? {
        histories[exerciseID] ?? store.document(ExerciseHistory.self, key: Self.historyKey(exerciseID))
    }

    /// History shows new numbers after a session.
    func invalidateHistories() { histories = [:] }

    // MARK: sessions

    /// Finished sessions of the last `days`, newest first: the server's list
    /// plus anything logged here that hasn't reached it yet (the local copy wins).
    func sessions(days: Int = 90) async -> [SessionSummary] {
        let from = DayFormat.shift(Calendar.current.startOfDay(for: .now), days: -(days - 1))
        let remoteList: [SessionSummary]
        if let fresh = try? await remote.sessions(from: from, to: .now) {
            remoteList = fresh
            store.saveDocument(fresh, key: Self.sessionsKey)
        } else {
            remoteList = store.document([SessionSummary].self, key: Self.sessionsKey) ?? []
        }
        return Self.merged(local: store.completedSessions(from: from).map(\.summary), remote: remoteList)
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

    /// A whole session (the list may carry summaries without exercises).
    func session(id: UUID) async -> TrainSession? {
        if let local = store.session(id: id) { return local.wire }
        return try? await remote.session(id: id)
    }

    /// The most recent finished session, for "Repeat last session".
    func lastSession() async -> TrainSession? {
        var latest = cachedSessions().first
        if latest == nil { latest = await sessions(days: 30).first }
        guard let latest else { return nil }
        return await session(id: latest.id)
    }

    // MARK: a custom exercise (queued)

    /// Cached first, so it can be logged at once, offline too. Train's outbox sends it, ahead of every workout that uses
    /// it, and the answer replaces the cached row (O1); a refusal is kept there, never shown here. Returns the cached
    /// copy at once (the sheet adds it to the workout). Nil, with `error`, for a name the platform would refuse (empty,
    /// or over 80 characters): nothing is cached or queued.
    func createExercise(_ e: Exercise) async -> Exercise? {
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

    /// Not empty, and at most `maxExerciseName` Unicode scalars (as the platform counts).
    static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.unicodeScalars.count <= maxExerciseName
    }

    // MARK: actions (online; the screen shows the error)

    /// A custom exercise the plan names that's still queued goes first, for at most `exerciseWait`: the platform refuses
    /// a plan with an exercise it doesn't have (ADR 0022 §7). Offline, or after the wait, the plan goes as before.
    @discardableResult
    func savePlan(_ p: Plan) async -> Bool {
        let named = Set(p.days.flatMap { $0.exercises.map(\.exercise.id) })
        await outbox().exercisesSent(named, upTo: exerciseWait)
        do {
            let saved = try await remote.savePlan(p)
            store.cache(plans: [saved])
            await reloadCatalog()
            return true
        } catch where error.isCancellation {
            return false
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
            return false
        }
    }

    @discardableResult
    func deletePlan(_ p: Plan) async -> Bool {
        do {
            try await remote.deletePlan(id: p.id)
            store.removePlan(id: p.id)
            await reloadCatalog()
            return true
        } catch where error.isCancellation {
            return false
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Enrol (switching replaces the active plan; the screen confirms first).
    @discardableResult
    func enroll(in p: Plan) async -> Bool {
        let ok = await perform { _ = try await $0.enroll(planID: p.id) }
        if ok { UserDefaults.standard.removeObject(forKey: Self.pausedKey) }
        return ok
    }

    /// The plan paused last. `GET /v1/plans` only reports the active enrolment,
    /// so the app remembers what Resume should continue.
    var pausedPlanID: UUID? {
        if let e = activeEnrollment, e.status == .paused { return e.planId }
        guard activeEnrollment == nil else { return nil }
        return UserDefaults.standard.string(forKey: Self.pausedKey).flatMap(UUID.init(uuidString:))
    }

    var isPaused: Bool { pausedPlanID != nil }

    /// Pause: `DELETE /v1/plans/enrollment`. Resume: enrolling in the same plan
    /// again continues where it stopped.
    @discardableResult
    func setPaused(_ paused: Bool) async -> Bool {
        if paused {
            guard let planID = activeEnrollment?.planId else { return false }
            let ok = await perform { try await $0.pauseEnrollment() }
            if ok { UserDefaults.standard.set(planID.uuidString, forKey: Self.pausedKey) }
            return ok
        }
        guard let planID = pausedPlanID else { return false }
        let ok = await perform { _ = try await $0.enroll(planID: planID) }
        if ok { UserDefaults.standard.removeObject(forKey: Self.pausedKey) }
        return ok
    }

    private func perform(_ action: (TrainDataSource) async throws -> Void) async -> Bool {
        do {
            try await action(remote)
            await reloadCatalog()
            return true
        } catch where error.isCancellation {
            return false
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
            return false
        }
    }

    private func reloadCatalog() async {
        let src = remote
        guard let c = try? await src.plans() else { return }
        catalog = c
        store.saveDocument(c, key: Self.catalogKey)
        try? await loadToday(from: src)
    }

    /// After a session completes, the plan advances.
    func sessionCompleted() async {
        invalidateHistories()
        try? await loadToday(from: remote)
    }

    func wipe() {
        exercises = []
        catalog = nil
        today = nil
        UserDefaults.standard.removeObject(forKey: Self.pausedKey)
        histories = [:]
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
