import Foundation
import SwiftData
import OSLog

/// The app's SwiftData container: Train's sessions being logged, its offline
/// library and upload outbox, and (`ReadModels.swift`) every platform read model
/// the Repository caches. On disk in the app, in memory for tests, previews and
/// demo data. Everything runs on the main context; documents are small.
@MainActor
final class TrainStore {
    static let shared = TrainStore()

    static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "train")
    static let schema = Schema([LocalSession.self, LocalSessionExercise.self, LocalSet.self,
                                CachedExercise.self, CachedPlan.self, PendingTrainOp.self] + readModels)

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) {
        let config = ModelConfiguration("Train", schema: Self.schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: Self.schema, configurations: config)
        } catch {
            // A store that can't be opened must not keep the app from launching.
            Self.log.error("Train store unavailable, using memory: \(error.localizedDescription, privacy: .public)")
            let memory = ModelConfiguration("TrainFallback", schema: Self.schema, isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(for: Self.schema, configurations: memory)
            } catch {
                fatalError("SwiftData can't create an in-memory store: \(error)")
            }
        }
        context.autosaveEnabled = true
    }

    func save() {
        do {
            try context.save()
        } catch {
            Self.log.error("Train save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: sessions

    func session(id: UUID) -> LocalSession? {
        var d = FetchDescriptor<LocalSession>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// The workout being logged, if any (the newest one if several survived).
    func activeSession() -> LocalSession? {
        let raw = SessionStatus.inProgress.rawValue
        var d = FetchDescriptor<LocalSession>(predicate: #Predicate { $0.statusRaw == raw },
                                              sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// Finished sessions, newest first.
    func completedSessions(from: Date = .distantPast, to: Date = .distantFuture) -> [LocalSession] {
        let raw = SessionStatus.completed.rawValue
        let d = FetchDescriptor<LocalSession>(
            predicate: #Predicate { $0.statusRaw == raw && $0.startedAt >= from && $0.startedAt <= to },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    func insert(_ s: LocalSession) {
        context.insert(s)
        save()
    }

    func delete(_ s: LocalSession) {
        context.delete(s)
        save()
    }

    // MARK: library

    func exercises() -> [Exercise] {
        let d = FetchDescriptor<CachedExercise>(sortBy: [SortDescriptor(\.name)])
        return ((try? context.fetch(d)) ?? []).compactMap(\.exercise).filter { !$0.archived }
    }

    func exercise(id: UUID) -> Exercise? {
        var d = FetchDescriptor<CachedExercise>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.exercise
    }

    func cache(exercises: [Exercise]) {
        let existing = Dictionary(((try? context.fetch(FetchDescriptor<CachedExercise>())) ?? []).map { ($0.id, $0) },
                                  uniquingKeysWith: { a, _ in a })
        for e in exercises {
            if let row = existing[e.id] {
                row.name = e.name
                row.kindRaw = e.kind.rawValue
                row.isCustom = e.isCustom
                row.payload = (try? APIClient.jsonEncoder.encode(e)) ?? row.payload
                row.updatedAt = .now
            } else {
                context.insert(CachedExercise(e))
            }
        }
        save()
    }

    func plans() -> [Plan] {
        let d = FetchDescriptor<CachedPlan>(sortBy: [SortDescriptor(\.name)])
        return ((try? context.fetch(d)) ?? []).compactMap(\.plan)
    }

    func plan(id: UUID) -> Plan? {
        var d = FetchDescriptor<CachedPlan>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.plan
    }

    func cache(plans: [Plan]) {
        let existing = Dictionary(((try? context.fetch(FetchDescriptor<CachedPlan>())) ?? []).map { ($0.id, $0) },
                                  uniquingKeysWith: { a, _ in a })
        for p in plans {
            if let row = existing[p.id] { row.update(p) } else { context.insert(CachedPlan(p)) }
        }
        save()
    }

    func removePlan(id: UUID) {
        try? context.delete(model: CachedPlan.self, where: #Predicate { $0.id == id })
        save()
    }

    // MARK: outbox

    func pendingOps() -> [PendingTrainOp] {
        (try? context.fetch(FetchDescriptor<PendingTrainOp>(sortBy: [SortDescriptor(\.seq)]))) ?? []
    }

    func enqueue(_ kind: PendingTrainOp.Kind, sessionID: UUID, bodyweightKg: Double? = nil) {
        let next = (pendingOps().last?.seq ?? 0) + 1
        context.insert(PendingTrainOp(seq: next, kind: kind, sessionId: sessionID, bodyweightKg: bodyweightKg))
        save()
    }

    func dequeue(_ op: PendingTrainOp) {
        context.delete(op)
        save()
    }

    func dropOps(for sessionID: UUID) {
        try? context.delete(model: PendingTrainOp.self, where: #Predicate { $0.sessionId == sessionID })
        save()
    }

    // MARK: account

    /// Log out / account switch: everything Train goes.
    func wipe() {
        // Batch deletes skip cascade rules, so children go explicitly.
        try? context.delete(model: LocalSet.self)
        try? context.delete(model: LocalSessionExercise.self)
        try? context.delete(model: LocalSession.self)
        try? context.delete(model: CachedExercise.self)
        try? context.delete(model: CachedPlan.self)
        try? context.delete(model: PendingTrainOp.self)
        try? context.delete(model: CachedDay.self)
        try? context.delete(model: CachedTrend.self)
        try? context.delete(model: CachedInsight.self)
        try? context.delete(model: CachedUser.self)
        try? context.delete(model: CachedSleepRange.self)
        try? context.delete(model: CachedWorkout.self)
        try? context.delete(model: CachedDocument.self)
        save()
    }
}
