import Foundation
import Testing
@testable import Ryft

/// Scripted replies for Train; separate from `StubURLProtocol` so suites can run in parallel.
final class TrainStubURLProtocol: URLProtocol {
    enum Reply {
        /// No network.
        case offline
        case status(Int, Data)
        /// 200 with the request body (the platform answering a PUT with the document).
        case echo
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [Reply] = []
    nonisolated(unsafe) private static var seen: [(method: String, path: String, body: Data)] = []

    static func script(_ r: [Reply]) {
        lock.withLock { replies = r }
    }

    static func reset() {
        lock.withLock { replies = []; seen = [] }
    }

    static var requests: [(method: String, path: String, body: Data)] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession moves the body into a stream before it reaches a protocol.
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let reply = Self.lock.withLock { () -> Reply in
            Self.seen.append((request.httpMethod ?? "", request.url?.path ?? "", body))
            return Self.replies.isEmpty ? .offline : Self.replies.removeFirst()
        }
        switch reply {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        case .status(let code, let data):
            respond(code, data)
        case .echo:
            respond(200, body)
        }
    }

    private func respond(_ code: Int, _ data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            guard n > 0 else { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

@MainActor
@Suite("Train sync", .serialized)
struct TrainSyncTests {
    let store = TrainStore(inMemory: true)
    let service: TrainSyncService

    init() {
        TrainStubURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TrainStubURLProtocol.self]
        let api = APIClient(session: URLSession(configuration: config), tokens: FakeTokens(), sleep: { _ in },
                            baseURL: URL(string: "https://api.test"))
        service = TrainSyncService(store: store, remote: { api }, debounce: .milliseconds(30), monitorsNetwork: false)
    }

    private func session(_ title: String) -> LocalSession {
        let s = SessionFactory.empty(in: store)
        s.title = title
        SessionFactory.add(MockTrain.bench, to: s, sets: 2, in: store)
        return s
    }

    private func path(_ id: UUID, _ suffix: String = "") -> String {
        "/v1/sessions/\(id.uuidString.lowercased())\(suffix)"
    }

    private func check(_ set: LocalSet, reps: Int, kg: Double) {
        set.reps = reps
        set.weightKg = kg
        set.completedAt = .now
        set.updatedAt = .now
    }

    @Test func offlineQueueReplaysInOrderOnReconnect() async throws {
        let a = session("A"), b = session("B")
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: 100)
        service.sessionChanged(a)
        check(b.orderedExercises[0].orderedSets[0], reps: 8, kg: 80)
        service.sessionChanged(b)

        // In the gym without signal: nothing gets through, nothing is lost.
        TrainStubURLProtocol.script([.offline])
        await service.flush()
        #expect(!service.isOnline)
        #expect(service.pendingCount == 2)

        // More sets on A while offline: still one PUT for A, at its original place.
        check(a.orderedExercises[0].orderedSets[1], reps: 5, kg: 100)
        service.sessionChanged(a)
        #expect(service.pendingCount == 2)

        TrainStubURLProtocol.script([.offline])
        let done = await service.finish(a)
        #expect(done == nil) // "will sync"
        #expect(a.pendingCompletion)
        #expect(a.status == .completed)
        #expect(service.pendingCount == 3)
        let finishedAt = try #require(a.endedAt)

        // Back online: PUT A, PUT B, then complete A — in the order they were queued.
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo, .echo, .status(200, try Fixture.data("train_session_completed"))])
        await service.flush()
        let sent = TrainStubURLProtocol.requests.map { "\($0.method) \($0.path)" }
        #expect(sent == ["PUT \(path(a.id))", "PUT \(path(b.id))", "POST \(path(a.id, "/complete"))"])
        #expect(service.pendingCount == 0)
        #expect(service.isOnline)
        #expect(!a.pendingCompletion)
        #expect(a.status == .completed)
        #expect(a.strain == 10.6)
        #expect(a.muscularTrimp == 55.3)
        #expect(a.prs.count == 2)

        // The PUT for A carried both sets checked off offline, still `in_progress`:
        // the platform takes `completed` only from `…/complete`.
        let putA = try APIClient.jsonDecoder.decode(TrainSession.self, from: TrainStubURLProtocol.requests[0].body)
        #expect(putA.exercises[0].sets.compactMap(\.reps) == [5, 5])
        #expect(putA.status == .inProgress)
        #expect(putA.deviceId == Settings.shared.deviceId)
        // …and complete sends the workout's own end time, not the replay time.
        let complete = try APIClient.jsonDecoder.decode(SessionComplete.self, from: TrainStubURLProtocol.requests[2].body)
        let sentEnd = try #require(complete.endedAt)
        #expect(abs(sentEnd.timeIntervalSince(finishedAt)) < 1)
    }

    @Test func changesAreDebouncedIntoOnePut() async throws {
        let a = session("A")
        TrainStubURLProtocol.script([.echo, .echo])
        for (i, set) in a.orderedExercises[0].orderedSets.enumerated() {
            check(set, reps: 5 + i, kg: 100)
            service.sessionChanged(a)
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(TrainStubURLProtocol.requests.count == 1)
        #expect(service.pendingCount == 0)
        #expect(a.uploaded)
    }

    @Test func conflictMergesBySetIDAndPutsAgain() async throws {
        let a = session("A")
        let ex = a.orderedExercises[0]
        let t1 = Date(timeIntervalSinceNow: -600), t2 = Date(timeIntervalSinceNow: -300), t3 = Date(timeIntervalSinceNow: -60)
        let mine = ex.orderedSets[0], localOnly = ex.orderedSets[1]
        check(mine, reps: 5, kg: 100)
        mine.updatedAt = t2
        check(localOnly, reps: 8, kg: 90)
        localOnly.updatedAt = t2
        let deletedHere = UUID()
        a.deletedSetIDs = [deletedHere]

        // The server's copy: an older version of `mine`, a set from another device, and one deleted here.
        var server = a.wire
        server.exercises[0].sets = [
            SessionSet(id: mine.id, setIndex: 0, reps: 3, weightKg: 100, completedAt: t1, updatedAt: t1),
            SessionSet(id: UUID(), setIndex: 2, reps: 6, weightKg: 95, completedAt: t3, updatedAt: t3),
            SessionSet(id: deletedHere, setIndex: 3, reps: 1, weightKg: 20, completedAt: t1, updatedAt: t1),
        ]
        let fromOtherDevice = server.exercises[0].sets[1].id
        TrainStubURLProtocol.script([.status(409, try APIClient.jsonEncoder.encode(server)), .echo])

        service.sessionChanged(a)
        await service.flush()

        let puts = TrainStubURLProtocol.requests
        #expect(puts.map(\.method) == ["PUT", "PUT"])
        let second = try APIClient.jsonDecoder.decode(TrainSession.self, from: puts[1].body)
        let sets = second.exercises[0].sets
        #expect(Set(sets.map(\.id)) == [mine.id, localOnly.id, fromOtherDevice])
        #expect(sets.first { $0.id == mine.id }?.reps == 5) // later updated_at wins
        #expect(!sets.contains { $0.id == deletedHere })
        // The local copy has the other device's set too.
        #expect(ex.sets.contains { $0.id == fromOtherDevice })
        #expect(service.pendingCount == 0)
    }

    @Test func refusedOpIsSetAsideAndTheQueueMovesOn() async throws {
        let a = session("A"), b = session("B")
        service.sessionChanged(a)
        service.sessionChanged(b)
        TrainStubURLProtocol.script([.status(422, Data(#"{"error":"reps out of range"}"#.utf8)), .echo])
        await service.flush()
        #expect(TrainStubURLProtocol.requests.count == 2)
        #expect(service.pendingCount == 0)
        #expect(service.lastError == nil) // the later success clears it
    }

    @Test func discardBeforeUploadSendsNothing() async {
        let a = session("A")
        service.sessionChanged(a)
        service.discard(a)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(TrainStubURLProtocol.requests.isEmpty)
        #expect(store.session(id: a.id) == nil)
        #expect(service.pendingCount == 0)
    }
}

@Suite("Session merge")
struct SessionMergeTests {
    let t1 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var t2: Date { t1.addingTimeInterval(60) }

    private func doc(_ sets: [SessionSet], exerciseID: UUID = UUID(uuidString: "4d5e6f7a-8b9c-4d0e-9f1a-2b3c4d5e6f01")!) -> TrainSession {
        TrainSession(id: UUID(uuidString: "3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e01")!, title: "Upper A", startedAt: t1,
                     status: .inProgress,
                     exercises: [SessionExercise(id: exerciseID, exerciseId: MockTrain.bench.id, position: 0, sets: sets)])
    }

    @Test func newerServerSetWins() {
        let id = UUID()
        let merged = SessionMerge.merge(local: doc([SessionSet(id: id, setIndex: 0, reps: 5, updatedAt: t1)]),
                                        server: doc([SessionSet(id: id, setIndex: 0, reps: 6, updatedAt: t2)]))
        #expect(merged.exercises[0].sets.map(\.reps) == [6])
    }

    @Test func tieKeepsTheLocalSet() {
        let id = UUID()
        let merged = SessionMerge.merge(local: doc([SessionSet(id: id, setIndex: 0, reps: 5, updatedAt: t1)]),
                                        server: doc([SessionSet(id: id, setIndex: 0, reps: 6, updatedAt: t1)]))
        #expect(merged.exercises[0].sets.map(\.reps) == [5])
    }

    @Test func serverOnlyExerciseIsKeptInPosition() {
        var server = doc([])
        server.exercises.append(SessionExercise(exerciseId: MockTrain.row.id, position: 1,
                                                     sets: [SessionSet(setIndex: 0, reps: 8, updatedAt: t1)]))
        let merged = SessionMerge.merge(local: doc([SessionSet(setIndex: 0, reps: 5, updatedAt: t1)]), server: server)
        #expect(merged.exercises.map(\.exerciseId) == [MockTrain.bench.id, MockTrain.row.id])
    }

    @Test func setsComeBackInOrder() {
        let merged = SessionMerge.merge(local: doc([SessionSet(setIndex: 2, updatedAt: t1), SessionSet(setIndex: 0, updatedAt: t1)]),
                                        server: doc([SessionSet(setIndex: 1, updatedAt: t1)]))
        #expect(merged.exercises[0].sets.map(\.setIndex) == [0, 1, 2])
    }

    @Test func scoresComeFromTheServer() {
        var server = doc([])
        server.strain = 9.4
        server.muscularTrimp = 70
        let merged = SessionMerge.merge(local: doc([]), server: server)
        #expect(merged.strain == 9.4 && merged.muscularTrimp == 70)
    }
}
