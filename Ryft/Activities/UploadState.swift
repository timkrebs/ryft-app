import Foundation

/// Where an own activity (or manual sleep) is on its way to the platform (design.md §4.1). My Day shows it on
/// each row. The rows themselves are the queue: `ActivityStore` knows saved vs confirmed; the uploader (A2)
/// adds what only it knows (offline, in flight, retrying, gated).
enum UploadState: Equatable, Sendable {
    enum Pending: Equatable, Sendable {
        case queued, offline, retrying(at: Date), inFlight, notAvailableYet, gated
    }

    /// My Day: a cloud with an arrow.
    case pending(Pending)
    /// My Day: Retry. The platform refused it, or three transient failures in a row while online.
    case failed(UploadAttempt)
    /// The server's copy decides from here: a hollow dot while strain is pending, then the strain.
    case confirmed
}

/// The last failed request for a row (`LocalActivity.lastAttemptData`, and Train's `LocalSession.lastAttemptData` and
/// `PendingTrainOp.lastAttemptData`): what Details shows. Statuses, codes, request IDs and times only, never a body.
struct UploadAttempt: Codable, Equatable, Sendable {
    /// `complete`: `POST /v1/sessions/{id}/complete`; `create`: `POST /v1/exercises` (Train, O2).
    enum Request: String, Codable, Sendable { case put, delete, complete, create }

    let at: Date
    let request: Request
    /// HTTP status; nil without a response.
    let status: Int?
    /// The error body's `code`, as sent.
    let code: String?
    /// `X-Request-ID`, exactly as received.
    let requestID: String?
    let kind: FailureKind

    /// `requestID` must round-trip as `request_id` through `WireCoding` (snake_case both ways).
    private enum CodingKeys: String, CodingKey {
        case at, request, status, code, requestID = "requestId", kind
    }
}

extension UploadAttempt {
    /// The platform refused the request (`400`, `404`, `409`, `413`, `422`, …): sent again unchanged it fails the same way
    /// (API.md → Errors), so only Retry or an edit sends it again. Never a transient failure, a gate or a sign-out.
    var isRefusal: Bool { kind == .other || kind == .appTooOld }
}
