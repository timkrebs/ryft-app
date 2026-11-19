// Offline copies of the exercise library and plans, plus the upload outbox.
import Foundation
import SwiftData

/// One library exercise, as the API sent it.
@Model
final class CachedExercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var isCustom: Bool
    var payload: Data
    var updatedAt: Date

    init(_ e: Exercise) {
        id = e.id
        name = e.name
        kindRaw = e.kind.rawValue
        isCustom = e.isCustom
        payload = (try? APIClient.jsonEncoder.encode(e)) ?? Data()
        updatedAt = .now
    }

    var exercise: Exercise? { try? APIClient.jsonDecoder.decode(Exercise.self, from: payload) }
}

/// One plan (with days when its detail was loaded).
@Model
final class CachedPlan {
    @Attribute(.unique) var id: UUID
    var name: String
    var isBuiltin: Bool
    var hasDays: Bool
    var payload: Data
    var updatedAt: Date

    init(_ p: Plan) {
        id = p.id
        name = p.name
        isBuiltin = p.isBuiltin
        hasDays = !p.days.isEmpty
        payload = (try? APIClient.jsonEncoder.encode(p)) ?? Data()
        updatedAt = .now
    }

    func update(_ p: Plan) {
        // A summary (no days) never replaces a cached detail.
        guard !p.days.isEmpty || !hasDays else { return }
        name = p.name
        isBuiltin = p.isBuiltin
        hasDays = !p.days.isEmpty
        payload = (try? APIClient.jsonEncoder.encode(p)) ?? payload
        updatedAt = .now
    }

    var plan: Plan? { try? APIClient.jsonDecoder.decode(Plan.self, from: payload) }
}

/// A queued request, replayed in `seq` order when the network is back.
@Model
final class PendingTrainOp {
    /// `exercise`: a custom exercise's `POST /v1/exercises` (O1), queued ahead of every other op.
    enum Kind: String { case put, complete, delete, exercise }

    var seq: Int
    var kindRaw: String
    /// The op's subject: the session's id, or for `exercise` the custom exercise's (`CachedExercise.id`). The name is
    /// from before exercises were queued; kept, so the store needs no migration.
    var sessionId: UUID
    var bodyweightKg: Double?
    var createdAt: Date
    /// Whose op it is: the account's ID, or `TrainSyncService.demoOwner` for demo data. It goes only through that
    /// binding's client (ADR 0008). Nil for ops queued before this build: the signed-in account's.
    var account: String?
    /// `UploadAttempt`: the platform refused an `exercise` op, which has no session to hold it. The op stays, passed
    /// over, until Retry on a session that uses the exercise, or the exercise is created again. Added in O2: optional,
    /// so the store migrates lightweight (`TrainOutboxSchemaUpgradeTests`).
    var lastAttemptData: Data?

    init(seq: Int, kind: Kind, sessionId: UUID, bodyweightKg: Double? = nil, account: String? = nil) {
        self.seq = seq
        self.kindRaw = kind.rawValue
        self.sessionId = sessionId
        self.bodyweightKg = bodyweightKg
        self.createdAt = .now
        self.account = account
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .put }

    var lastAttempt: UploadAttempt? {
        get { WireCoding.decode(UploadAttempt.self, lastAttemptData) }
        set { lastAttemptData = newValue.flatMap { WireCoding.encode($0) } }
    }
}
