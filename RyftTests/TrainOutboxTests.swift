import Foundation
import SwiftData
import Testing
@testable import Ryft

// O1 and O2 (docs/work/2026-11-19-offline-first): a custom exercise goes through Train's outbox, and a refusal is a
// state that keeps its op. In the "Train sync" suite, whose scripted network these share (it runs serialized).
// Synthetic values only.
extension TrainSyncTests {
    private func customExercise(_ name: String = "Landmine press") -> Exercise {
        Exercise(slug: "landmine-press", name: name, kind: .barbell, primaryMuscles: [.frontDelts],
                 equipment: ["barbell", "landmine"], loadType: .weight, isUnilateral: true, isCustom: true)
    }

    /// The suite's service, with no 2 s wait that could fire mid-test and take a scripted reply: each test flushes.
    private func makeOutbox() -> TrainSyncService {
        let outbox = TrainSyncService(store: store, remote: { [api] in api }, debounce: .seconds(3_600),
                                      monitorsNetwork: false)
        outbox.gate = { _ in nil }
        return outbox
    }

    private func library(_ outbox: TrainSyncService) -> TrainLibrary {
        TrainLibrary(store: store, remote: { [api] in api }, outbox: { outbox }, restore: false)
    }

    private var sent: [String] { TrainStubURLProtocol.requests.map { "\($0.method) \($0.path)" } }

    /// The error shape, with its request ID.
    private func refusal(_ status: Int, _ requestID: String) -> TrainStubURLProtocol.Reply {
        .status(status, Data(#"{"error":"refused","request_id":"\#(requestID)"}"#.utf8))
    }

    /// The platform's copy of a custom exercise, as `POST /v1/exercises` answers it.
    private func saved(_ e: Exercise, name: String) throws -> TrainStubURLProtocol.Reply {
        var copy = e
        copy.name = name
        return .status(201, try APIClient.jsonEncoder.encode(copy))
    }

    /// Waits for every replay in flight to end, so nothing started before a `reset()` takes a scripted reply after it.
    private func settled(_ outbox: TrainSyncService) async {
        #expect(await eventually { !outbox.isFlushing })
    }

    /// A finished session whose `PUT` the platform refused with `status`, with `complete` still queued behind it. `b`'s
    /// `PUT` sits between the two and goes.
    private func refusedFinish(_ outbox: TrainSyncService, _ status: Int = 422, _ requestID: String = "req-refused")
        async throws -> (a: LocalSession, b: LocalSession) {
        let a = session("A"), b = session("B")
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: 100)
        outbox.sessionChanged(a)
        check(b.orderedExercises[0].orderedSets[0], reps: 8, kg: 80)
        outbox.sessionChanged(b)
        // Offline: Finish queues `complete` after B's `PUT`.
        _ = await outbox.finish(a)
        await settled(outbox)
        #expect(store.pendingOps().map(\.kind) == [.put, .put, .complete])

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([refusal(status, requestID), .echo])
        await outbox.flush()
        return (a, b)
    }

    // MARK: O1, a custom exercise through the outbox

    /// O1 (1), (2), (4). Alex Doe makes "Landmine press" at a gym with no signal, logs two sets of it and finishes. The
    /// workout's `PUT` was queued before the exercise existed and sends the document as it is when it goes, so the
    /// exercise is queued ahead of it: on reconnect it's exercise, `PUT`, `complete`. Before O1 the exercise was tried
    /// once and never again, the platform refused the `PUT` with `422`, and the workout was lost.
    @Test func anOfflineCustomExerciseGoesFirstOnReconnect() async throws {
        let outbox = makeOutbox()
        let lib = library(outbox)
        let s = session("Push")
        check(s.orderedExercises[0].orderedSets[0], reps: 5, kg: 60)
        outbox.sessionChanged(s)                              // the PUT is queued first
        let e = customExercise()
        let made = await lib.createExercise(e)
        #expect(made == e)                                     // the cached copy, at once
        let listed = lib.exercises.contains { $0.id == e.id }
        #expect(listed)
        let added = SessionFactory.add(e, to: s, sets: 2, in: store)
        check(added.orderedSets[0], reps: 10, kg: 20)
        outbox.sessionChanged(s)
        _ = await outbox.finish(s)
        await settled(outbox)
        #expect(s.pendingCompletion)                           // "will sync"
        #expect(store.pendingOps().map(\.kind) == [.exercise, .put, .complete])

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([try saved(e, name: "Landmine Press"), .echo,
                                     .status(200, try Fixture.data("train_session_completed"))])
        await outbox.flush()

        #expect(sent == ["POST /v1/exercises", "PUT \(path(s.id))", "POST \(path(s.id, "/complete"))"])
        #expect(outbox.pendingCount == 0 && !s.pendingCompletion)
        let posted = try APIClient.jsonDecoder.decode(ExerciseInput.self, from: TrainStubURLProtocol.requests[0].body)
        #expect(posted.id == e.id && posted.name == "Landmine press")
        let put = try APIClient.jsonDecoder.decode(TrainSession.self, from: TrainStubURLProtocol.requests[1].body)
        #expect(put.exercises.map(\.exerciseId).contains(e.id))
        // O1 (4): the platform's answer replaces the cached row.
        let cached = try #require(store.exercise(id: e.id))
        #expect(cached.name == "Landmine Press")
        let rows = try store.context.fetchCount(FetchDescriptor<CachedExercise>())
        #expect(rows == 1)
    }

    /// O1 (3). The answer was lost (the connection dropped after the request went): the op stays and the same `POST`
    /// goes again, by the same id, so the platform updates the one exercise (API.md: same `id` again updates it).
    /// Creating it again queues no second op.
    @Test func aResentExerciseIsTheSameRequest() async throws {
        let outbox = makeOutbox()
        let lib = library(outbox)
        let e = customExercise()
        TrainStubURLProtocol.script([.offline])
        _ = await lib.createExercise(e)
        await settled(outbox)
        #expect(sent == ["POST /v1/exercises"])
        _ = await lib.createExercise(e)
        await settled(outbox)
        #expect(store.pendingOps().map(\.kind) == [.exercise])

        TrainStubURLProtocol.script([try saved(e, name: "Landmine press")])
        await outbox.flush()
        let posts = TrainStubURLProtocol.requests
        #expect(posts.map(\.path) == ["/v1/exercises", "/v1/exercises", "/v1/exercises"])
        let ids = try posts.map { try APIClient.jsonDecoder.decode(ExerciseInput.self, from: $0.body).id }
        #expect(ids == [e.id, e.id, e.id])
        // The same document each time (as JSON: the encoder doesn't sort keys).
        let documents = try posts.map { try JSONSerialization.jsonObject(with: $0.body) as? NSDictionary }
        let same = documents.allSatisfy { $0 != nil && $0 == documents.first }
        #expect(same)
        #expect(store.pendingOps().isEmpty)
        let rows = try store.context.fetchCount(FetchDescriptor<CachedExercise>())
        #expect(rows == 1)
    }

    /// O1 (consent): a custom exercise is no data write (ADR 0008 §1). With consent missing, so that `PUT` and
    /// `DELETE` both wait, it still goes; the workout's `PUT` stays queued, held.
    @Test func theConsentGateDoesNotHoldAnExercise() async throws {
        let outbox = makeOutbox()
        outbox.gate = { _ in .gate(.consentRequired) }
        let s = session("Push")
        outbox.sessionChanged(s)
        let e = customExercise()
        TrainStubURLProtocol.script([try saved(e, name: "Landmine press")])
        outbox.queueExercise(e)
        await settled(outbox)
        #expect(sent == ["POST /v1/exercises"])
        #expect(store.pendingOps().map(\.kind) == [.put])
        #expect(outbox.heldAt == .gate(.consentRequired))
        #expect(outbox.state(of: s.id) == .pending(.gated))
    }

    // MARK: O2, a refusal is a state

    /// O2 (1), (2). The platform refuses A's `PUT` (`422`): A's ops stay, the attempt is on A with its request ID, and
    /// A's `complete` waits (it would answer `404`). B's `PUT`, queued between them, goes. Nothing of A goes again until
    /// Retry or an edit.
    @Test func aRefusedPutKeepsItsOpsAndOtherSessionsGo() async throws {
        let outbox = makeOutbox()
        let (a, b) = try await refusedFinish(outbox, 422, "req-422")

        #expect(sent == ["PUT \(path(a.id))", "PUT \(path(b.id))"])
        #expect(store.pendingOps().map(\.kind) == [.put, .complete])
        #expect(store.pendingOps().map(\.sessionId) == [a.id, a.id])
        let attempt = try #require(a.lastAttempt)
        #expect(attempt.status == 422 && attempt.requestID == "req-422" && attempt.request == .put)
        #expect(attempt.kind == .other && attempt.isRefusal)
        #expect(outbox.state(of: a.id) == .failed(attempt))
        #expect(outbox.state(of: b.id) == .confirmed)
        #expect(b.uploaded && !a.uploaded && a.pendingCompletion)

        // Another trigger (reconnect, app active) sends nothing of A.
        TrainStubURLProtocol.script([.echo, .echo])
        await outbox.flush()
        #expect(TrainStubURLProtocol.requests.count == 2)
        #expect(outbox.pendingCount == 2)
    }

    /// O2 (3). Retry clears the refusal, and the session's ops go again in their order.
    @Test func retrySendsARefusedSessionAgain() async throws {
        let outbox = makeOutbox()
        let (a, _) = try await refusedFinish(outbox)
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo, .status(200, try Fixture.data("train_session_completed"))])

        await outbox.retry(sessionID: a.id)

        #expect(sent == ["PUT \(path(a.id))", "POST \(path(a.id, "/complete"))"])
        #expect(a.lastAttempt == nil && !a.pendingCompletion)
        #expect(outbox.pendingCount == 0)
        #expect(outbox.state(of: a.id) == .confirmed)
    }

    /// O2 (3). An edit queues a fresh `PUT`, and the refusal goes at once: what was refused was an earlier document.
    @Test func anEditClearsARefusal() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        outbox.sessionChanged(a)
        TrainStubURLProtocol.script([refusal(422, "req-422")])
        await outbox.flush()
        let refused = try #require(a.lastAttempt)
        #expect(outbox.state(of: a.id) == .failed(refused))

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo])
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: 100)
        outbox.sessionChanged(a)
        #expect(a.lastAttempt == nil)
        #expect(outbox.state(of: a.id) == .pending(.queued))
        await outbox.flush()
        #expect(outbox.pendingCount == 0 && a.uploaded)
        #expect(sent == ["PUT \(path(a.id))"])
        let put = try APIClient.jsonDecoder.decode(TrainSession.self, from: TrainStubURLProtocol.requests[0].body)
        #expect(put.exercises[0].sets.compactMap(\.reps) == [5])
    }

    /// O2: the refusal answered a document that an edit replaced while the request was out. The same op goes again at
    /// once with the newer one, ahead of the session's later ops; nothing is recorded.
    @Test func aRefusalOfADocumentEditedMeanwhileIsNotKept() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        TrainStubURLProtocol.script([.holdThen(422, Data(#"{"error":"refused","request_id":"req-old"}"#.utf8)), .echo, .echo])
        outbox.sessionChanged(a)
        let replay = Task { await outbox.flush() }
        #expect(await eventually { TrainStubURLProtocol.requests.count == 1 })     // the PUT, held
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: 100)
        outbox.sessionChanged(a)                               // a fresh PUT behind it
        TrainStubURLProtocol.release()
        await replay.value

        #expect(outbox.pendingCount == 0 && a.uploaded)
        #expect(a.lastAttempt == nil)
        // The refused one, the same op again with the edit, then the fresh one.
        #expect(sent == Array(repeating: "PUT \(path(a.id))", count: 3))
        let second = try APIClient.jsonDecoder.decode(TrainSession.self, from: TrainStubURLProtocol.requests[1].body)
        #expect(second.exercises[0].sets.compactMap(\.reps) == [5])
    }

    /// O2 (1). Still newer on the platform after every merge round (`409` three times): the same state, with the last
    /// answer's request ID. The session's `complete` waits; the other session goes.
    @Test func aConflictAfterEveryMergeRoundIsARefusal() async throws {
        let outbox = makeOutbox()
        let a = session("A"), b = session("B")
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: 100)
        outbox.sessionChanged(a)
        outbox.sessionChanged(b)
        _ = await outbox.finish(a)
        await settled(outbox)
        #expect(store.pendingOps().map(\.kind) == [.put, .put, .complete])

        TrainStubURLProtocol.reset()
        let server = try APIClient.jsonEncoder.encode(a.wire)
        TrainStubURLProtocol.script((1...3).map { .headed(409, server, ["X-Request-ID": "req-409-\($0)"]) } + [.echo])
        await outbox.flush()

        #expect(sent == Array(repeating: "PUT \(path(a.id))", count: 3) + ["PUT \(path(b.id))"])
        let attempt = try #require(a.lastAttempt)
        #expect(attempt.status == 409 && attempt.requestID == "req-409-3" && attempt.isRefusal)
        #expect(outbox.state(of: a.id) == .failed(attempt))
        #expect(store.pendingOps().map(\.kind) == [.put, .complete])
        #expect(b.uploaded)
    }

    /// O2 (1). Every other refusal of a `PUT` is the same state: over 256 KiB (`413`), and a `400` and a `403` without a
    /// gate code. A `401`, a `403` with one, a `429` and a `5xx` stay retryable as before (`isRetryable`).
    @Test(arguments: [413, 400, 403])
    func anyRefusalOfAPutIsKept(_ status: Int) async throws {
        let outbox = makeOutbox()
        let (a, b) = try await refusedFinish(outbox, status, "req-\(status)")
        #expect(sent == ["PUT \(path(a.id))", "PUT \(path(b.id))"])
        let attempt = try #require(a.lastAttempt)
        #expect(attempt.status == status && attempt.requestID == "req-\(status)")
        #expect(outbox.state(of: a.id) == .failed(attempt))
        #expect(store.pendingOps().map(\.kind) == [.put, .complete])
    }

    /// O2 (1). `complete` answered `404` (the platform has no such session): its op stays, with the attempt.
    @Test func aCompleteAnswered404IsKept() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: 100)
        TrainStubURLProtocol.script([.echo, refusal(404, "req-404")])
        _ = await outbox.finish(a)
        await settled(outbox)

        #expect(sent == ["PUT \(path(a.id))", "POST \(path(a.id, "/complete"))"])
        let attempt = try #require(a.lastAttempt)
        #expect(attempt.status == 404 && attempt.request == .complete && attempt.requestID == "req-404")
        #expect(store.pendingOps().map(\.kind) == [.complete])
        #expect(a.pendingCompletion)
        #expect(outbox.state(of: a.id) == .failed(attempt))
    }

    /// A transient failure is still no refusal: a `500` keeps the queue as it is, records nothing, and the next trigger
    /// sends it.
    @Test func aServerErrorStaysRetryable() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        outbox.sessionChanged(a)
        TrainStubURLProtocol.script([refusal(500, "req-500")])
        await outbox.flush()
        #expect(a.lastAttempt == nil)
        #expect(outbox.pendingCount == 1)

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo])
        await outbox.flush()
        #expect(sent == ["PUT \(path(a.id))"] && outbox.pendingCount == 0)
    }

    /// O2: the state is derived from the store, not kept by the outbox. Another service on the same store (a
    /// relaunch) finds the refusal, and sends nothing of the session.
    @Test func aRefusalOutlivesTheService() async throws {
        let outbox = makeOutbox()
        let (a, _) = try await refusedFinish(outbox)
        let attempt = try #require(a.lastAttempt)
        let relaunched = TrainSyncService(store: store, remote: { [api] in api }, debounce: .milliseconds(30),
                                          monitorsNetwork: false)
        relaunched.gate = { _ in nil }
        #expect(relaunched.state(of: a.id) == .failed(attempt))
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo, .echo])
        await relaunched.flush()
        #expect(TrainStubURLProtocol.requests.isEmpty)
    }

    /// O2 for the exercise's own op: refused (`422`), it stays, with the attempt on the op; the workout that uses it is
    /// then refused by the platform. Retry on the workout sends both again, exercise first.
    @Test func aRefusedExerciseGoesAgainWithItsSessionsRetry() async throws {
        let outbox = makeOutbox()
        let s = session("Push")
        let e = customExercise()
        SessionFactory.add(e, to: s, sets: 1, in: store)
        TrainStubURLProtocol.script([refusal(422, "req-ex"), refusal(422, "req-put")])
        outbox.queueExercise(e)
        outbox.sessionChanged(s)
        await outbox.flush()
        await settled(outbox)
        #expect(sent == ["POST /v1/exercises", "PUT \(path(s.id))"])
        let op = try #require(store.pendingOps().first)
        #expect(op.kind == .exercise && op.lastAttempt?.requestID == "req-ex" && op.lastAttempt?.request == .create)
        #expect(s.lastAttempt?.requestID == "req-put")
        #expect(store.pendingOps().map(\.kind) == [.exercise, .put])

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([try saved(e, name: "Landmine press"), .echo])
        await outbox.retry(sessionID: s.id)
        #expect(sent == ["POST /v1/exercises", "PUT \(path(s.id))"])
        #expect(store.pendingOps().isEmpty && s.lastAttempt == nil)
    }

    /// The state while nothing is refused: offline, then queued; `confirmed` once nothing waits.
    @Test func theStateFollowsTheQueue() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        #expect(outbox.state(of: a.id) == .confirmed)
        outbox.sessionChanged(a)
        #expect(outbox.state(of: a.id) == .pending(.queued))
        TrainStubURLProtocol.script([.offline])
        await outbox.flush()
        #expect(outbox.state(of: a.id) == .pending(.offline))
        TrainStubURLProtocol.script([.echo])
        await outbox.flush()
        #expect(outbox.state(of: a.id) == .confirmed)
        #expect(outbox.state(of: UUID()) == .confirmed)       // only the platform has it
    }
}
