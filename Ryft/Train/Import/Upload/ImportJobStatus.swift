import Foundation

/// Where the account's import job is (ui.md §8.2, the resume row): what step 6, My Plans and Profile → Data show.
/// `TrainImportUploader.status` publishes it; nil when this account (or demo) has no job.
struct ImportJobStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Custom exercises are being created (I1, "Creating 3 custom exercises…").
        case preparing
        /// Batches are going up (I2).
        case uploading
        /// Nothing is being sent right now; the job is kept and continues on its own (I5, I6, I8, I9).
        case paused(ImportPause)
        /// Nothing is pending: every item is done or rejected (I3, or I4 when `hasRejected`).
        case finished
    }

    var phase: Phase
    /// When Import was tapped; the job is removed 30 days later if it isn't done.
    let createdAt: Date
    let source: ImportFormatID
    /// The zone the times were read in (the preview named it).
    let timeZoneID: String
    var exercises: ImportItemCounts
    var plans: ImportItemCounts
    var sessions: ImportItemCounts
    /// Sets in the sessions that are done ("Sets imported: 28").
    var setsDone: Int
    /// Every plan of the job, in its order, with its state ("Plan: Upper/Lower · 6 weeks").
    var planSummaries: [ImportPlanSummary]
    /// What the preview left out (ui.md §8.2's "Already in RYFT", "Sets skipped").
    var skipped: ImportSkipCounts
    /// Refused by the platform, or blocked by a refused custom exercise: listed with their reasons ("Not imported (3)").
    var rejected: [ImportItemSummary]
    /// Sessions the uploader's own duplicate check skipped (the preview was offline): "Import these too".
    var duplicatesFound: [ImportItemSummary]
    /// The last failed request, for Details: status, code and request ID.
    var lastFailure: ImportFailure?
    /// The plans sent (for "Open plan"), and the one enrolled in once that's done.
    var planIDs: [UUID]
    var enrolledPlanID: UUID?
    /// The user saw the finished result (I3); the resume row then disappears.
    var resultSeen: Bool

    var isFinished: Bool { phase == .finished }
    var hasRejected: Bool { !rejected.isEmpty }
    /// Done items over all items (exercises, plans and sessions), 0…1, for the progress bar.
    var progress: Double {
        let total = exercises.total + plans.total + sessions.total
        guard total > 0 else { return isFinished ? 1 : 0 }
        return Double(exercises.done + plans.done + sessions.done) / Double(total)
    }
}

/// Why nothing is being sent.
enum ImportPause: Equatable, Sendable {
    /// No network: continues when it's back (I6).
    case offline
    /// A transient failure (network, `408`, `429`, `5xx`): tried again at `at` (a `Retry-After` countdown), or on the
    /// next trigger when nil (I5). `lastFailure` has the details.
    case retrying(at: Date?)
    /// Consent, the invite gate, or the policy in force not known yet (`uploadGate(for: .trainImport)`): held, never
    /// dropped, until the gate opens (I8).
    case gated(UploadGate)
    /// Uploads aren't available yet (the platform hasn't published the endpoint, or `train.import` is off): the job is
    /// saved on this iPhone and uploads once they are (V5, I9).
    case notAvailable
    /// Signed out, or the job belongs to the account while demo data shows: it waits for its account.
    case waitingForAccount
}

/// A plan of the job, for the result screen and the resume row.
struct ImportPlanSummary: Equatable, Sendable, Identifiable {
    enum State: Equatable, Sendable { case pending, done, rejected, blocked }

    let id: UUID
    let name: String
    /// nil: it repeats.
    let weeks: Int?
    let daysPerWeek: Int
    let state: State
}

/// One kind of item's progress.
struct ImportItemCounts: Equatable, Sendable {
    var total = 0
    /// `created`, `unchanged` or `updated`.
    var done = 0
    var rejected = 0
    /// Not sent: it uses a custom exercise the platform refused.
    var blocked = 0

    var pending: Int { max(0, total - done - rejected - blocked) }
}

/// A rejected, blocked or skipped item, as the result screen lists it: its title and date come from the job (the
/// platform stores them anyway), the reason from the platform's answer.
struct ImportItemSummary: Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case exercise, plan, session }

    let id: UUID
    let kind: Kind
    /// The exercise's or plan's name, or the session's title.
    let title: String
    /// A session's start; nil for exercises and plans.
    let date: Date?
    /// The platform's words, or nil (blocked, skipped, or no reason given).
    let reason: String?
    /// Refused by the platform with this request ID; nil when blocked or skipped.
    let requestID: String?
    /// Not sent because the custom exercise it uses was refused.
    let blocked: Bool
}

/// A failed request, for Details: statuses, codes, request IDs and the time only, never a body.
struct ImportFailure: Codable, Equatable, Sendable {
    let at: Date
    /// HTTP status; nil without a response.
    let status: Int?
    let code: String?
    /// `X-Request-ID`, exactly as received.
    let requestID: String?
    let kind: FailureKind

    /// `requestID` round-trips as `request_id` through the snake_case coders too.
    private enum CodingKeys: String, CodingKey {
        case at, status, code, requestID = "requestId", kind
    }

    /// "HTTP 503 · Request ID 01a1…" for an inline message's Details, or nil without a status.
    var details: String? {
        guard let status else { return nil }
        let head = code.map { "HTTP \(status) · \($0)" } ?? "HTTP \(status)"
        guard let requestID else { return head }
        return String(localized: "\(head) · Request ID \(requestID)")
    }
}
