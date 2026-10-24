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

/// The last failed request for a row (`LocalActivity.lastAttemptData`): what Details shows. Statuses, codes,
/// request IDs and times only, never a body.
struct UploadAttempt: Codable, Equatable, Sendable {
    enum Request: String, Codable, Sendable { case put, delete }

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
