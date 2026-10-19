// Exercises, plans and today's prescription, cached for offline browsing in the
// gym. Screens read the cached copy at once; `refresh()` (app active) updates it.
import Foundation

@MainActor
final class TrainLibrary: ObservableObject {
    static let shared = TrainLibrary()

    @Published private(set) var exercises: [Exercise] = []
    @Published private(set) var catalog: PlanCatalog?
    @Published private(set) var today: PlanToday?
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published var errorDetails: String?

    let store: TrainStore
    private let remoteProvider: () -> TrainDataSource
    private let cache: ResponseCache
    private var histories: [UUID: ExerciseHistory] = [:]

    init(store: TrainStore? = nil, remote: (() -> TrainDataSource)? = nil, cache: ResponseCache = .shared,
         restore: Bool = true) {
        self.store = store ?? .shared
        self.remoteProvider = remote ?? { TrainSource.current }
        self.cache = cache
        if restore {
            exercises = self.store.exercises()
            catalog = cache.load(PlanCatalog.self, key: Self.catalogKey)
            today = cache.load(PlanToday.self, key: Self.todayKey)
        }
    }

    private var remote: TrainDataSource { remoteProvider() }

    var activeEnrollment: Enrollment? { catalog?.active }

    var activePlan: Plan? {
        guard let id = activeEnrollment?.planId else { return nil }
        return plan(id: id)
    }

    func plan(id: UUID) -> Plan? {
        store.plan(id: id) ?? (catalog.map { $0.builtin + $0.mine } ?? []).first { $0.id == id }
    }

    func exercise(id: UUID) -> Exercise? {
        exercises.first { $0.id == id } ?? store.exercise(id: id)
    }

    // MARK: refresh

    /// App active / pull to refresh. Each part fails on its own; the cache stays.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let src = remote
        do {
            let list = try await src.exercises()
            store.cache(exercises: list)
            exercises = store.exercises()
            let c = try await src.plans()
            store.cache(plans: c.builtin + c.mine)
            catalog = c
            cache.save(c, as: Self.catalogKey)
            try await loadToday(from: src)
            error = nil
            errorDetails = nil
        } catch {
            self.error = error.localizedDescription
            self.errorDetails = error.diagnosticDetails
        }
    }

    private func loadToday(from src: TrainDataSource) async throws {
        today = try await src.planToday()
        if let today { cache.save(today, as: Self.todayKey) } else { cache.remove(Self.todayKey) }
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
            cache.save(h, as: "train.history.\(exerciseID.uuidString)")
            return h
        } catch {
            return cache.load(ExerciseHistory.self, key: "train.history.\(exerciseID.uuidString)")
        }
    }

    /// Already-loaded history, for instant paint.
    func cachedHistory(for exerciseID: UUID) -> ExerciseHistory? {
        histories[exerciseID] ?? cache.load(ExerciseHistory.self, key: "train.history.\(exerciseID.uuidString)")
    }

    /// History shows new numbers after a session.
    func invalidateHistories() { histories = [:] }

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
        await perform { _ = try await $0.enroll(planID: p.id) }
    }

    @discardableResult
    func setPaused(_ paused: Bool) async -> Bool {
        await perform { _ = try await $0.setEnrollment(paused: paused) }
    }

    @discardableResult
    func leavePlan() async -> Bool {
        await perform { try await $0.leaveEnrollment() }
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
        store.cache(plans: c.builtin + c.mine)
        catalog = c
        cache.save(c, as: Self.catalogKey)
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
        histories = [:]
    }

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
