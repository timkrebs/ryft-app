import Foundation
import SwiftData

/// "Export my data": the account's import job while some of it isn't on the platform yet (privacy review S2), like
/// the activities this iPhone hasn't sent. What's done is in the platform's own lists (`/v1/sessions`), so only the
/// rest is here: each item as it would be sent, and why it isn't there yet.
struct PendingImportExport: Encodable, Equatable, Sendable {
    /// `alpha_progression`.
    let source: String
    let createdAt: Date
    /// The zone the times were read in.
    let timeZone: String
    let items: [Item]

    struct Item: Encodable, Equatable, Sendable {
        /// `exercise`, `plan`, `session`.
        let kind: String
        /// `pending` (not sent yet), `refused` (the platform didn't accept it), `blocked` (it uses an exercise the
        /// platform refused), `skipped_duplicate` (it looks like a session already logged: sent only on request).
        let state: String
        let item: Wire
    }

    /// The item as the request carries it.
    enum Wire: Encodable, Equatable, Sendable {
        case exercise(Exercise)
        case plan(Plan)
        case session(TrainSession)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .exercise(value): try container.encode(value)
            case let .plan(value): try container.encode(value)
            case let .session(value): try container.encode(value)
            }
        }
    }

    /// The job of `account` (an account id, or `ImportMappingStore.demoAccount`), read now and decoded off the main
    /// actor; nil without a job, or when everything in it is done.
    @MainActor
    static func make(persistence: Persistence, account: String?) async -> PendingImportExport? {
        guard let account else { return nil }
        let descriptor = FetchDescriptor<PendingImport>(predicate: #Predicate { $0.account == account },
                                                        sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        guard let row = (try? persistence.context.fetch(descriptor))?.first else { return nil }
        return await build(source: row.source, createdAt: row.createdAt, timeZone: row.timeZoneID, payload: row.payload,
                           progress: row.progressData)
    }

    @concurrent
    private static func build(source: String, createdAt: Date, timeZone: String, payload: Data,
                              progress: Data) async -> PendingImportExport? {
        MainThread.assertOff("Exporting an import job")
        guard let plan = try? APIClient.jsonDecoder.decode(ImportUploadPlan.self, from: payload) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = (try? decoder.decode(ImportJobProgress.self, from: progress)) ?? ImportJobProgress()
        func phase(_ id: UUID) -> String? {
            switch state[id]?.phase {
            case nil: "pending"
            case .rejected?: "refused"
            case .blocked?: "blocked"
            case .duplicate?: "skipped_duplicate"
            case .done?: nil
            }
        }
        var items: [Item] = []
        for exercise in plan.exercises {
            if let phase = phase(exercise.id) { items.append(Item(kind: "exercise", state: phase, item: .exercise(exercise))) }
        }
        for item in plan.plans {
            if let phase = phase(item.id) { items.append(Item(kind: "plan", state: phase, item: .plan(item))) }
        }
        for session in plan.sessions {
            if let phase = phase(session.id) { items.append(Item(kind: "session", state: phase, item: .session(session))) }
        }
        guard !items.isEmpty else { return nil }
        return PendingImportExport(source: source, createdAt: createdAt, timeZone: timeZone, items: items)
    }
}
