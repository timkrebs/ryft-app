import Foundation
import SwiftData

/// The account's import job (design §7, §10): created when Import is tapped, at most one per account (demo is its own),
/// kept until it's done and seen, discarded, 30 days old, or wiped with the account (`TrainStore.wipe`). It holds the
/// confirmed, wire-ready result, never the file. Read and written only by `TrainImportUploader`.
@Model
final class PendingImport {
    @Attribute(.unique) var id: UUID
    /// The account it was confirmed for: the user id, or `ImportMappingStore.demoAccount`. Never uploaded for another.
    var account: String
    /// `ImportFormatID.rawValue`.
    var source: String
    var createdAt: Date
    /// The zone the preview named.
    var timeZoneID: String
    /// False after an offline preview: the uploader checks duplicates and existing ids before its first session batch.
    var duplicatesChecked: Bool
    /// `ImportUploadPlan`, encoded off the main actor once, decoded off it on resume.
    @Attribute(.externalStorage) var payload: Data
    /// `ImportJobProgress`, rewritten after each request.
    var progressData: Data
    /// 50, halved after a `413`.
    var sessionsPerRequest: Int
    /// Nothing was pending any more at this time; nil while something is.
    var finishedAt: Date?
    /// The user saw the finished result.
    var resultSeen: Bool

    init(id: UUID = UUID(), account: String, source: ImportFormatID, createdAt: Date, timeZoneID: String,
         duplicatesChecked: Bool, payload: Data, progressData: Data, sessionsPerRequest: Int) {
        self.id = id
        self.account = account
        self.source = source.rawValue
        self.createdAt = createdAt
        self.timeZoneID = timeZoneID
        self.duplicatesChecked = duplicatesChecked
        self.payload = payload
        self.progressData = progressData
        self.sessionsPerRequest = sessionsPerRequest
        finishedAt = nil
        resultSeen = false
    }
}

/// Where each item of a job is (design §7): what's done, refused, blocked by a refused custom exercise, or skipped as a
/// duplicate by the uploader's own check. Items not named are pending.
struct ImportJobProgress: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        enum Phase: String, Codable, Sendable {
            /// `created`, `unchanged` or `updated` (in `result`).
            case done
            /// Refused (a `rejected` result, a 4xx for its request, or no answer three times): sent again only by Retry.
            case rejected
            /// It uses a custom exercise the platform refused: not sent.
            case blocked
            /// It looks like a session the user logged (found at upload after an offline preview): "Import these too".
            case duplicate
        }

        var phase: Phase
        /// The platform's `status` for a done item.
        var result: String?
        /// The platform's words for a refusal.
        var reason: String?
        var status: Int?
        var requestID: String?
        /// The logged session a duplicate matches, or the custom exercise that blocks.
        var related: UUID?
    }

    /// By the item's id (`uuidString`, so the JSON stays an object).
    var items: [String: Item] = [:]
    /// Answers (2xx) that didn't name a pending item; three make it `rejected`.
    var unanswered: [String: Int] = [:]
    /// Nothing more to do for the enrolment: it went through, was refused, or its plan isn't there.
    var enrolled = false
    /// The plan enrolled in, when it went through.
    var enrolledPlanID: UUID?
    /// The days the platform rescores, for the refresh after the last batch.
    var daysTouched: [String] = []
    var lastFailure: ImportFailure?

    subscript(id: UUID) -> Item? {
        get { items[id.uuidString] }
        set { items[id.uuidString] = newValue }
    }

    func isPending(_ id: UUID) -> Bool { items[id.uuidString] == nil }
}
