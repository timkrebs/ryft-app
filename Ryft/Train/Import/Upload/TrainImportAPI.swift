import Foundation

// The import's batch endpoint, as a draft until the platform publishes it (design §7, platform brief): the shapes live
// here, not in `Networking/Models.swift`, so the mirror check keeps matching API.md. C2 (api-contract-keeper) moves the
// reconciled shapes into `Models.swift`, adds `APIClient+TrainImport.swift` with fixtures, and deletes this draft.

/// `POST /v1/train/import`: plans and completed sessions in one idempotent batch (ids come from the app, ADR 0007).
protocol TrainImportAPI {
    /// The platform serves the endpoint. False before the contract is published (C2): nothing is sent, and a job
    /// waits as "saved on this iPhone".
    var publishesTrainImport: Bool { get }
    /// `body` is an encoded `TrainImportRequest` (encoded off the main actor, its size measured before it's sent).
    /// Answers one result per item it read; an item it doesn't name stays pending.
    func importTraining(encoded body: Data) async throws -> TrainImportResponse
}

enum TrainImportError: Error, Equatable, Sendable {
    /// The contract isn't published: the live client sent nothing.
    case notPublished
}

/// The request body (draft): `{ "source": "alpha_progression", "plans": [Plan], "sessions": [Session] }`. Every
/// session is an import (T1), so none carries an `origin`.
struct TrainImportRequest: Encodable, Sendable {
    let source: String
    let plans: [Plan]
    let sessions: [TrainSession]

    init(source: ImportFormatID, plans: [Plan], sessions: [TrainSession]) {
        self.source = source.rawValue
        self.plans = plans
        self.sessions = sessions
    }
}

/// The answer (draft): one result per item, and the days whose scores change (T7).
struct TrainImportResponse: Decodable, Equatable, Sendable {
    var results: [TrainImportItemResult]
    /// `YYYY-MM-DD`, the account's days that get rescored (T7); empty when the platform doesn't say.
    var daysTouched: [String]
    /// `X-Request-ID` of the answer (not in the body): the client sets it, so a `rejected` item can show it.
    var requestID: String?

    init(results: [TrainImportItemResult], daysTouched: [String] = [], requestID: String? = nil) {
        self.results = results
        self.daysTouched = daysTouched
        self.requestID = requestID
    }

    enum CodingKeys: String, CodingKey { case results, daysTouched }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try c.decodeIfPresent([TrainImportItemResult].self, forKey: .results) ?? []
        daysTouched = try c.decodeIfPresent([String].self, forKey: .daysTouched) ?? []
    }
}

struct TrainImportItemResult: Decodable, Equatable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case plan, session, unknown

        init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    enum Status: String, Decodable, Sendable {
        case created, unchanged, updated, rejected
    }

    let kind: Kind
    let id: UUID
    let status: Status
    /// The platform's words for a refusal; shown on the result screen, never logged.
    let reason: String?

    init(kind: Kind, id: UUID, status: Status, reason: String? = nil) {
        self.kind = kind
        self.id = id
        self.status = status
        self.reason = reason
    }
}

/// The live client before C2: throws `notPublished` without a request.
extension APIClient: TrainImportAPI {
    var publishesTrainImport: Bool { false }
    func importTraining(encoded body: Data) async throws -> TrainImportResponse { throw TrainImportError.notPublished }
}
