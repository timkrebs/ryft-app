import Foundation
import Testing
@testable import Ryft

/// Serves scripted replies in order and records the requests (body included) it saw. Its own class, so these tests
/// never share a script with the other suites' `StubURLProtocol`.
final class ImportStubProtocol: URLProtocol {
    struct Reply {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data("{}".utf8)
    }

    struct Seen {
        let request: URLRequest
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [Reply] = []
    nonisolated(unsafe) private static var log: [Seen] = []

    static func script(_ r: [Reply]) {
        lock.withLock { replies = r; log = [] }
    }

    static var seen: [Seen] { lock.withLock { log } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let reply = Self.lock.withLock { () -> Reply in
            Self.log.append(Seen(request: request, body: body))
            return Self.replies.isEmpty ? Reply(status: 500) : Self.replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// `POST /v1/train/import` through the real `APIClient` against a stubbed session: what it sends, and what each status
/// of API.md → Errors comes back as. The client waits for nothing itself (the uploader owns every wait).
@Suite("Training import: the live call", .serialized)
struct TrainImportAPIClientTests {
    let tokens = FakeTokens()
    let sleeps = SleepLog()
    let base = URL(string: "https://api.test")!
    let body = Data(#"{"source":"alpha_progression","plans":[],"sessions":[]}"#.utf8)

    private func client(status: APIStatus) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImportStubProtocol.self]
        let sleeps = self.sleeps
        return APIClient(session: URLSession(configuration: config), tokens: tokens, sleep: { sleeps.record($0) },
                         baseURL: base, status: status)
    }

    private static func errorBody(_ message: String, code: String? = nil, requestID: String? = nil) -> Data {
        var json: [String: String] = ["error": message]
        json["code"] = code
        json["request_id"] = requestID
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }

    /// The error a call fails with.
    private func failure(_ replies: [ImportStubProtocol.Reply]) async throws -> APIError {
        ImportStubProtocol.script(replies)
        let status = await APIStatus()
        do {
            _ = try await client(status: status).importTraining(encoded: body)
        } catch let error as APIError {
            return error
        }
        throw TestFailure.succeeded
    }

    private enum TestFailure: Error { case succeeded }

    @Test func itPostsTheEncodedBodyWithTheCommonHeaders() async throws {
        let fixture = try Fixture.data("train_import_response")
        ImportStubProtocol.script([.init(status: 200, headers: ["X-Request-ID": "req-200"], body: fixture)])
        let status = await APIStatus()
        let answer = try await client(status: status).importTraining(encoded: body)
        let seen = try #require(ImportStubProtocol.seen.first)
        #expect(seen.request.httpMethod == "POST")
        #expect(seen.request.url?.path == "/v1/train/import")
        #expect(seen.body == body)
        #expect(seen.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(seen.request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(seen.request.value(forHTTPHeaderField: "X-RYFT-Device-ID") == Settings.shared.deviceId.uuidString.lowercased())
        #expect(ImportStubProtocol.seen.count == 1)
        #expect(answer.results.count == 5 && answer.daysTouched == ["2026-06-08", "2026-06-10"])
    }

    /// The `X-Request-ID` of a `2xx` is kept: a rejected item shows it in Details.
    @Test func theRequestIDOfASuccessIsKept() async throws {
        let fixture = try Fixture.data("train_import_response")
        ImportStubProtocol.script([.init(status: 200, headers: ["X-Request-ID": "01JB7Z3Q8M"], body: fixture)])
        let answer = try await client(status: await APIStatus()).importTraining(encoded: body)
        #expect(answer.requestID == "01JB7Z3Q8M")
    }

    /// The platform writes ids in lower case, Swift sends them in upper case: they are the same `UUID`.
    @Test(arguments: [false, true])
    func resultIDsAreMatchedAsUUIDsNotStrings(_ upper: Bool) async throws {
        let id = try #require(UUID(uuidString: "3D8C5A21-7E4F-5B96-A0D3-C18F2E6B9047"))
        let written = upper ? id.uuidString : id.uuidString.lowercased()
        let json = #"{"results":[{"kind":"session","id":"\#(written)","status":"created"}],"days_touched":[],"#
            + #""scoring":{"queued_days":[],"expected_within_sec":30}}"#
        ImportStubProtocol.script([.init(status: 200, body: Data(json.utf8))])
        let answer = try await client(status: await APIStatus()).importTraining(encoded: body)
        #expect(answer.results.map(\.id) == [id])
        let first = try #require(answer.results.first)
        #expect(Set([id]).contains(first.id))
    }

    /// `429 import_in_progress`: thrown at once with its `Retry-After` and code, never waited out or retried inside the
    /// client (nothing of the request was processed, and the uploader resends it).
    @Test func importInProgressComesBackAtOnce() async throws {
        let error = try await failure([.init(status: 429, headers: ["Retry-After": "10", "X-Request-ID": "req-429"],
                                             body: Self.errorBody("import in progress", code: "import_in_progress")),
                                       .init(status: 200)])
        #expect(error.status == 429 && error.code == .importInProgress && error.retryAfter == 10)
        #expect(error.requestID == "req-429")
        #expect(ImportStubProtocol.seen.count == 1)
        #expect(sleeps.waits.isEmpty)
        #expect(FailureKind.of(error) == .transient)
    }

    @Test func aRateLimitComesBackWithItsRetryAfter() async throws {
        let error = try await failure([.init(status: 429, headers: ["Retry-After": "5"], body: Data("slow down".utf8)),
                                       .init(status: 200)])
        #expect(error.status == 429 && error.code == nil && error.retryAfter == 5)
        #expect(ImportStubProtocol.seen.count == 1 && sleeps.waits.isEmpty)
    }

    /// `503` is not retried inside the client either (the request may run for 50 s): the uploader backs off.
    @Test func unavailableComesBackWithItsRetryAfter() async throws {
        let error = try await failure([.init(status: 503, headers: ["Retry-After": "20", "X-Request-ID": "req-503"],
                                             body: Self.errorBody("request timed out")),
                                       .init(status: 200)])
        #expect(error.status == 503 && error.retryAfter == 20 && error.requestID == "req-503")
        #expect(ImportStubProtocol.seen.count == 1 && sleeps.waits.isEmpty)
        #expect(tokens.rejections == 0)
    }

    @Test func importNotEnabledIsNoGate() async throws {
        let status = await APIStatus()
        ImportStubProtocol.script([.init(status: 403, headers: ["X-Request-ID": "req-403"],
                                         body: Self.errorBody("not enabled", code: "import_not_enabled"))])
        let error = await #expect(throws: APIError.self) {
            _ = try await client(status: status).importTraining(encoded: body)
        }
        #expect(error?.status == 403 && error?.code == .importNotEnabled && error?.requestID == "req-403")
        #expect(error?.gate == nil)
        let thrown = try #require(error)
        #expect(FailureKind.of(thrown) == .other)
        #expect(await status.inviteBlocked == false)
    }

    @Test func consentRequiredIsAGate() async throws {
        let error = try await failure([.init(status: 403, body: Self.errorBody("consent", code: "consent_required"))])
        #expect(error.gate == .consentRequired)
        #expect(FailureKind.of(error) == .gate)
    }

    /// Whole-request errors that are bugs, not waits: thrown once, never retried, never a sign-out.
    @Test(arguments: [400, 413, 422])
    func requestErrorsAreThrownOnce(_ code: Int) async throws {
        let error = try await failure([.init(status: code, headers: ["X-Request-ID": "req-\(code)"],
                                             body: Self.errorBody("nope")), .init(status: 200)])
        #expect(error.status == code && error.requestID == "req-\(code)")
        #expect(ImportStubProtocol.seen.count == 1)
        #expect(tokens.refreshes == 0 && tokens.rejections == 0)
        #expect(FailureKind.of(error) == .other)
    }

    @Test func anUnreadableAnswerKeepsItsRequestID() async throws {
        ImportStubProtocol.script([.init(status: 200, headers: ["X-Request-ID": "req-200"], body: Data("[]".utf8))])
        let error = await #expect(throws: APIError.self) {
            _ = try await client(status: await APIStatus()).importTraining(encoded: body)
        }
        #expect(error?.requestID == "req-200")
    }

    @Test func theLiveClientPublishesTheEndpoint() {
        #expect(APIClient.shared.publishesTrainImport)
    }
}
