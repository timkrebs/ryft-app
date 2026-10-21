// Exercises, plans and today's prescription, cached for offline browsing in the
// gym. Screens read the cached copy at once; `refresh()` (app active) updates it.
import Foundation
import Observation

@MainActor
@Observable
final class TrainLibrary {
    static let shared = TrainLibrary()

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
    private var histories: [UUID: ExerciseHistory] = [:]

    init(store: TrainStore? = nil, remote: (() -> TrainDataSource)? = nil, restore: Bool = true) {
        self.store = store ?? .shared
        self.remoteProvider = remote ?? { TrainSource.current }
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
        if let failure, !(failure is CancellationError) {
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

    static func merged(local: [SessionSummary], remote: [SessionSummary]) -> [SessionSummary] {
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

    // MARK: actions (online; the screen shows the error)

    func createExercise(_ e: Exercise) async -> Exercise? {
        // Saved locally first so it can be logged right away, even offline.
        store.cache(exercises: [e])
        exercises = store.exercises()
        do {
            let saved = try await remote.createExercise(e)
            store.cache(exercises: [saved])
            exercises = store.exercises()
            return saved
        } catch {
            self.error = error.localizedDescription
            return e
        }
    }

    @discardableResult
    func savePlan(_ p: Plan) async -> Bool {
        do {
            let saved = try await remote.savePlan(p)
            store.cache(plans: [saved])
            await reloadCatalog()
            return true
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
    private static func historyKey(_ id: UUID) -> String { "train.history.\(id.uuidString)" }
    private static let pausedKey = "train.pausedPlanID"
    private static let catalogKey = "train.plans"
    private static let todayKey = "train.today"
}

// MARK: - previews

extension TrainLibrary {
    /// Filled from `MockTrain`, in an in-memory store.
    static func preview(store: TrainStore, enrolled: Bool = true) -> TrainLibrary {
        let lib = TrainLibrary(store: store, remote: { MockTrainSource.shared }, restore: false)
        store.cache(exercises: MockTrain.exercises)
        store.cache(plans: MockTrain.plans)
        lib.exercises = store.exercises()
        lib.catalog = MockTrain.catalog(enrolled: enrolled)
        lib.today = enrolled ? MockTrain.planToday : nil
        return lib
    }
}
