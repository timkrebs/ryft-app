import Foundation

// The import's batch endpoint seam. The wire shapes (`TrainImportRequest`, `TrainImportResponse`, `ImportResult`, ...)
// are mirrored in `Networking/Models.swift` (C2); the live call is `APIClient+TrainImport.swift`.

/// `POST /v1/train/import`: plans and completed sessions in one idempotent batch (ids come from the app, ADR 0007).
protocol TrainImportAPI {
    /// The platform serves the endpoint. False for a platform that doesn't (a test double, a UI test's
    /// `-importUploadsUnavailable`): nothing is sent, and a job waits as "saved on this iPhone".
    var publishesTrainImport: Bool { get }
    /// `body` is an encoded `TrainImportRequest` (encoded off the main actor, its size measured before it's sent).
    /// Answers one result per item it read; an item it doesn't name stays pending. The answer carries the response's
    /// `X-Request-ID`.
    func importTraining(encoded body: Data) async throws -> TrainImportResponse
}
