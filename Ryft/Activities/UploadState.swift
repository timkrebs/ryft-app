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
    /// My Day: Retry. The platform refused it (`UploadAttempt.isRefusal`), or three holds in a row while online.
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
    /// The request can't succeed as it is (ADR 0022 §1, the one definition every outbox uses): sent again unchanged it
    /// fails the same way, so only Retry or a newer edit sends it again. API.md → Errors: `400`, `409` (Train's `PUT`
    /// only after its merge rounds), `413`, `422`, and "any other `4xx` (`405`, `431` …) is like `400`"; a `404` on a
    /// `complete` (the platform has no such session); and a request this build couldn't make (an `EncodingError`: no
    /// answer and no transport failure).
    ///
    /// Holds, never refusals (what the contract says to wait out or send again): a transient failure (no answer,
    /// `408`, `429`, a `5xx`), a cancellation, a sign-out (`401` after the refresh), every `403` (a gate, or one this
    /// build doesn't know), a `404` on a `PUT` or `POST` (a route problem: the app is newer than the server), `426`
    /// (reserved for app-too-old, API_REQUESTS §3: a newer build sends the same document), and a `501`. A `2xx` the app
    /// couldn't read was delivered: no attempt is kept for it.
    var isRefusal: Bool {
        guard kind == .other else { return false }
        guard let status else { return true }
        switch status {
        case 401, 403, 408, 426, 429: return false
        case 404: return request == .complete
        case 400..<500: return true
        default: return false
        }
    }
}

extension APIError {
    /// A `2xx` whose body this build couldn't read (`APIClient.decode`): the platform took the request, so it was
    /// delivered (ADR 0022 §1).
    var wasDelivered: Bool { status.map { (200..<300).contains($0) } ?? false }
}
