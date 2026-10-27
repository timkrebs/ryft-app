import Foundation

// The import's batch endpoint seam. The wire shapes (`TrainImportRequest`, `TrainImportResponse`, `ImportResult`, ...)
// are mirrored in `Networking/Models.swift` (C2); the live call (`APIClient+TrainImport.swift`) is still to come, and
// until then the live client throws `notPublished`.

/// `POST /v1/train/import`: plans and completed sessions in one idempotent batch (ids come from the app, ADR 0007).
protocol TrainImportAPI {
    /// The platform serves the endpoint. False before the live call exists: nothing is sent, and a job
    /// waits as "saved on this iPhone".
    var publishesTrainImport: Bool { get }
    /// `body` is an encoded `TrainImportRequest` (encoded off the main actor, its size measured before it's sent).
    /// Answers one result per item it read; an item it doesn't name stays pending.
    func importTraining(encoded body: Data) async throws -> TrainImportResponse
}

enum TrainImportError: Error, Equatable, Sendable {
    /// The live call isn't wired: the live client sent nothing.
    case notPublished
}

/// The live client before the call is wired: throws `notPublished` without a request.
extension APIClient: TrainImportAPI {
    var publishesTrainImport: Bool { false }
    func importTraining(encoded body: Data) async throws -> TrainImportResponse { throw TrainImportError.notPublished }
}
