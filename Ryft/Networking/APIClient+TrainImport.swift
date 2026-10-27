// `POST /v1/train/import` (API.md → Train → "import plans and history from another training app").
import Foundation

extension APIClient: TrainImportAPI {
    /// The endpoint is live; whether the import is offered is the `train.import` flag's decision.
    var publishesTrainImport: Bool { true }

    /// One request, no waiting inside the client: a `429` (`import_in_progress` or the rate limit) and a `503` come back
    /// as errors with their `Retry-After`, because `TrainImportUploader` owns the wait (it shows "paused", survives a
    /// relaunch and resends the same request). `413`, `422` and `400` are thrown as they are for the uploader to split.
    /// The body is up to 1 MiB and the server takes up to 50 s, which the default session's 60 s allows.
    func importTraining(encoded body: Data) async throws -> TrainImportResponse {
        let answer = try await exchange("POST", path: "/v1/train/import", encodedBody: body, unavailableRetries: 0,
                                        retriesRateLimit: false)
        var response = try Self.decode(TrainImportResponse.self, from: answer)
        // On every `2xx`: a rejected item shows it in Details, and support finds the request by it.
        response.requestID = answer.requestID
        return response
    }
}
