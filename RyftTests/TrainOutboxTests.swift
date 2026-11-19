import Foundation
import SwiftData
import Testing
@testable import Ryft

/// `aCustomExerciseNeedsAValidName`'s names, and whether the platform takes each.
private let customExerciseNames: [(String, Bool)] = [
    ("", false), ("   ", false), (String(repeating: "a", count: 81), false),
    (String(repeating: "e\u{301}", count: 41), false), (String(repeating: "e\u{301}", count: 40), true),
    (" " + String(repeating: "a", count: 80) + " ", true), ("\u{0}\u{0}", false),
    (String(repeating: "a", count: 80) + "\u{0}", true),
]

// O1 and O2 (docs/work/2026-11-19-offline-first): a custom exercise goes through Train's outbox, and a refusal is a
// state that keeps its op. In the "Train sync" suite, whose scripted network these share (it runs serialized).
// Synthetic values only.
extension TrainSyncTests {
    private func customExercise(_ name: String = "Landmine press") -> Exercise {
        Exercise(slug: "landmine-press", name: name, kind: .barbell, primaryMuscles: [.frontDelts],
                 equipment: ["barbell", "landmine"], loadType: .weight, isUnilateral: true, isCustom: true)
    }

    /// The suite's service, with no 2 s wait that could fire mid-test and take a scripted reply: each test flushes.
    /// `owner`: the binding (by default the app's, as the rest of the suite).
    private func makeOutbox(owner: (@MainActor () -> String?)? = nil, clock: AppClock = SystemClock()) -> TrainSyncService {
        let outbox = TrainSyncService(store: store, remote: { [api] in api }, owner: owner, debounce: .seconds(3_600),
                                      monitorsNetwork: false, clock: clock)
        outbox.gate = { _ in nil }
        return outbox
    }

    /// `remote`: where the library's own requests go (by default the suite's scripted network).
    private func library(_ outbox: TrainSyncService, remote: TrainDataSource? = nil,
                         exerciseWait: Duration = .seconds(10)) -> TrainLibrary {
        TrainLibrary(store: store, remote: { [api] in remote ?? api }, outbox: { outbox }, exerciseWait: exerciseWait,
                     restore: false)
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

    /// The platform's copy of a session as its last `PUT` left it (`body`, which the stub echoed), completed and scored:
    /// what `…/complete` answers with, by the same ids.
    private func completedCopy(_ body: Data, workout: UUID) throws -> Data {
        var copy = try APIClient.jsonDecoder.decode(TrainSession.self, from: body)
        copy.status = .completed
        copy.endedAt = copy.startedAt.addingTimeInterval(3_600)
        copy.workoutId = workout
        copy.strain = 9.4
        copy.muscularTrimp = 38
        copy.volumeKg = 15_000
        copy.bodyweightKg = 82.5
        return try APIClient.jsonEncoder.encode(copy)
    }

    /// What was logged of each set, in order: its id, reps, weight and when it was checked off.
    private struct Logged: Equatable {
        let id: UUID, reps: Int?, kg: Double?, done: Date?
    }

    private func logged(_ s: LocalSession) -> [Logged] {
        s.orderedExercises.flatMap(\.orderedSets).map { Logged(id: $0.id, reps: $0.reps, kg: $0.weightKg, done: $0.completedAt) }
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
    /// answer's request ID. The other session goes. The platform has this one (a `409` says so), so its `complete` goes
    /// too and the refused `PUT` stays (ADR 0022 §5).
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
        TrainStubURLProtocol.script((1...3).map { .headed(409, server, ["X-Request-ID": "req-409-\($0)"]) }
            + [.echo, .status(200, try Fixture.data("train_session_completed"))])
        await outbox.flush()

        #expect(sent == Array(repeating: "PUT \(path(a.id))", count: 3) + ["PUT \(path(b.id))", "POST \(path(a.id, "/complete"))"])
        let attempt = try #require(a.lastAttempt)
        #expect(attempt.status == 409 && attempt.requestID == "req-409-3" && attempt.isRefusal)
        #expect(outbox.state(of: a.id) == .failed(attempt))
        #expect(store.pendingOps().map(\.kind) == [.put])
        #expect(b.uploaded && a.uploaded && !a.pendingCompletion)
    }

    /// O2 (1). Every other refusal of a `PUT` is the same state: a `400`, over 256 KiB (`413`), `422`, and a `4xx` the
    /// contract doesn't list (`405`, `431`: API.md → Errors, "like `400`"). Holds (every `403`, a `404`, `408`, `426`,
    /// `501`, `5xx`) are `holdsKeepTheQueue`.
    @Test(arguments: [400, 405, 413, 422, 431])
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

    /// O2 for the exercise's own op: refused (`422`), it stays, with the attempt on the op. The workout that uses it
    /// isn't sent (the platform would refuse it too) and shows the exercise's attempt (ADR 0022 §7). Retry on the
    /// workout clears both and sends both again, exercise first.
    @Test func aRefusedExerciseGoesAgainWithItsSessionsRetry() async throws {
        let outbox = makeOutbox()
        let s = session("Push")
        let e = customExercise()
        SessionFactory.add(e, to: s, sets: 1, in: store)
        TrainStubURLProtocol.script([refusal(422, "req-ex"), .echo])
        outbox.queueExercise(e)
        outbox.sessionChanged(s)
        await outbox.flush()
        await settled(outbox)
        #expect(sent == ["POST /v1/exercises"])
        let op = try #require(store.pendingOps().first)
        let attempt = try #require(op.lastAttempt)
        #expect(op.kind == .exercise && attempt.requestID == "req-ex" && attempt.request == .create)
        #expect(s.lastAttempt == nil)
        #expect(outbox.state(of: s.id) == .failed(attempt))
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

    // MARK: ADR 0022, holds and deliveries

    /// ADR 0022 §1: no refusal, a hold. Any `403` (a gate this build doesn't know, a proxy), a `404` on `PUT` (a route or
    /// server problem), `408` (transient, API.md → Errors), app-too-old (`426`), `501` (not there yet): the op stays,
    /// nothing is recorded, and the next trigger sends it.
    @Test(arguments: [#"{"error":"forbidden","request_id":"req-403"}"#, #"{"error":"x","code":"region_closed"}"#, "404", "408",
                      "426", "501"])
    func holdsKeepTheQueue(_ answer: String) async throws {
        let outbox = makeOutbox()
        let a = session("A")
        outbox.sessionChanged(a)
        let reply: TrainStubURLProtocol.Reply = if let status = Int(answer) {
            refusal(status, "req-\(status)")
        } else {
            .status(403, Data(answer.utf8))
        }
        TrainStubURLProtocol.script([reply])
        await outbox.flush()
        #expect(a.lastAttempt == nil && !a.uploaded)
        #expect(store.pendingOps().map(\.kind) == [.put])
        #expect(outbox.state(of: a.id) == .pending(.queued))

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo])
        await outbox.flush()
        #expect(sent == ["PUT \(path(a.id))"] && outbox.pendingCount == 0 && a.uploaded)
    }

    /// ADR 0022 §1 for a custom exercise: a `403`, a `404` on `POST /v1/exercises`, `426`, `501` hold its op too.
    @Test(arguments: [403, 404, 426, 501])
    func anExerciseHeldIsNoRefusal(_ status: Int) async throws {
        let outbox = makeOutbox()
        let e = customExercise()
        TrainStubURLProtocol.script([refusal(status, "req-\(status)")])
        outbox.queueExercise(e)
        await settled(outbox)
        let op = try #require(store.pendingOps().first)
        #expect(op.kind == .exercise && op.lastAttempt == nil)

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([try saved(e, name: "Landmine press")])
        await outbox.flush()
        #expect(sent == ["POST /v1/exercises"] && store.pendingOps().isEmpty)
    }

    /// ADR 0022 §1: a `2xx` this build can't read was delivered. `complete`'s op goes and the session is completed;
    /// nothing is refused, and there's no summary answer to show.
    @Test func anUnreadableAnswerToCompleteIsDelivered() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: 100)
        TrainStubURLProtocol.script([.echo, .status(200, Data(#"{"id":"#.utf8))])
        _ = await outbox.finish(a)
        await settled(outbox)
        #expect(sent == ["PUT \(path(a.id))", "POST \(path(a.id, "/complete"))"])
        #expect(store.pendingOps().isEmpty && !a.pendingCompletion && a.lastAttempt == nil)
        #expect(outbox.lastCompletion == nil)
        #expect(outbox.state(of: a.id) == .confirmed)
    }

    /// The same for a custom exercise: its op goes, and the cached row stays as it was made.
    @Test func anUnreadableAnswerToAnExerciseIsDelivered() async throws {
        let outbox = makeOutbox()
        let e = customExercise()
        TrainStubURLProtocol.script([.status(201, Data("[]".utf8))])
        outbox.queueExercise(e)
        await settled(outbox)
        #expect(sent == ["POST /v1/exercises"])
        #expect(store.pendingOps().isEmpty)
        #expect(store.exercise(id: e.id)?.name == "Landmine press")
    }

    /// ADR 0022 §6: `complete` answered `409`, so the platform discarded the session ("treat it as discarded"). Its op
    /// goes and the session is no longer to be completed; no refusal, nothing sent again.
    @Test func aCompleteAnswered409IsDiscarded() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        TrainStubURLProtocol.script([.echo, refusal(409, "req-409")])
        _ = await outbox.finish(a)
        await settled(outbox)
        #expect(sent == ["PUT \(path(a.id))", "POST \(path(a.id, "/complete"))"])
        #expect(store.pendingOps().isEmpty && !a.pendingCompletion && a.lastAttempt == nil)
        #expect(outbox.state(of: a.id) == .confirmed)
    }

    /// ADR 0022 §1: `complete` answered `404` for a session whose `PUT` never arrived (an earlier build dropped it). The
    /// `PUT` is queued ahead and goes, then `complete` again, with the body weight given at Finish.
    @Test func aCompleteBeforeItsPutQueuesThePut() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: 100)
        _ = await outbox.finish(a, bodyweightKg: 82.5)        // offline
        await settled(outbox)
        let put = try #require(store.pendingOps().first)
        store.dequeue(put)                                     // what an earlier build left: `complete` alone
        #expect(store.pendingOps().map(\.kind) == [.complete] && !a.uploaded)

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([refusal(404, "req-404"), .echo, .status(200, try Fixture.data("train_session_completed"))])
        await outbox.flush()
        #expect(sent == ["POST \(path(a.id, "/complete"))", "PUT \(path(a.id))", "POST \(path(a.id, "/complete"))"])
        #expect(store.pendingOps().isEmpty && !a.pendingCompletion && a.uploaded && a.lastAttempt == nil)
        let complete = try APIClient.jsonDecoder.decode(SessionComplete.self, from: TrainStubURLProtocol.requests[2].body)
        #expect(complete.bodyweightKg == 82.5)
    }

    /// ADR 0022 §5. Alex Doe logs 50 sets of bench at 60 kg and they go up. Then set 1 was 6 × 65 kg, set 2 wasn't done
    /// after all, and set 51 is one too many: that `PUT` is refused (`422`). Finish still completes the workout: the
    /// platform has it, with its own 50 sets, and scores it. The answer is that copy (by the same ids), so it brings
    /// only the status, the workout, the scores and the body weight: every set logged here stays as it is, the refused
    /// `PUT` stays for Retry or an edit, and Retry sends the sets as logged.
    @Test func aRefusedPutOfAnUploadedSessionDoesNotHoldItsComplete() async throws {
        let outbox = makeOutbox()
        let a = SessionFactory.empty(in: store)
        a.title = "Bench day"
        let bench = SessionFactory.add(MockTrain.bench, to: a, sets: 50, in: store)
        for set in bench.orderedSets { check(set, reps: 5, kg: 60) }
        outbox.sessionChanged(a)
        TrainStubURLProtocol.script([.echo])
        await outbox.flush()
        #expect(a.uploaded && store.pendingOps().isEmpty)
        let workout = UUID()
        let answer = try completedCopy(TrainStubURLProtocol.requests[0].body, workout: workout)

        check(bench.orderedSets[0], reps: 6, kg: 65)
        bench.orderedSets[1].completedAt = nil
        check(SessionFactory.appendSet(index: 50, to: bench, in: store), reps: 5, kg: 60)
        outbox.sessionChanged(a)
        let before = logged(a)
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([refusal(422, "req-51"), .status(200, answer)])
        let done = await outbox.finish(a, bodyweightKg: 82.5)
        await settled(outbox)

        #expect(done != nil)
        #expect(sent == ["PUT \(path(a.id))", "POST \(path(a.id, "/complete"))"])
        let put = try APIClient.jsonDecoder.decode(TrainSession.self, from: TrainStubURLProtocol.requests[0].body)
        #expect(put.exercises[0].sets.count == 51)
        // What the platform owns came with the answer ...
        #expect(a.status == .completed && !a.pendingCompletion)
        #expect(a.workoutId == workout && a.strain == 9.4 && a.muscularTrimp == 38 && a.bodyweightKg == 82.5)
        // ... and what was logged here stayed: reps, weights, the times they were checked off, set 51.
        #expect(logged(a) == before)
        #expect(bench.orderedSets[0].weightKg == 65 && bench.sets.count == 51)
        #expect(store.pendingOps().map(\.kind) == [.put])
        let attempt = try #require(a.lastAttempt)
        #expect(attempt.status == 422 && attempt.request == .put && attempt.requestID == "req-51")
        #expect(outbox.state(of: a.id) == .failed(attempt))

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo])
        await outbox.retry(sessionID: a.id)
        #expect(sent == ["PUT \(path(a.id))"])
        let again = try APIClient.jsonDecoder.decode(TrainSession.self, from: TrainStubURLProtocol.requests[0].body)
        let sets = again.exercises[0].sets
        #expect(again.status == .completed && sets.count == 51)
        #expect(sets.first { $0.setIndex == 0 }?.weightKg == 65 && sets.first { $0.setIndex == 0 }?.reps == 6)
        let second = try #require(sets.first { $0.setIndex == 1 })
        #expect(second.completedAt == nil)
    }

    /// ADR 0022 §5, the other way the platform's copy is older: an edit while `complete` is out queues a `PUT` behind
    /// it. The answer brings only what the platform owns; the edit stays, and the queued `PUT` sends it (here it finds
    /// no network, so the edit is still what's here afterwards).
    @Test func anEditWhileCompleteIsOutIsKept() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        for set in a.orderedExercises[0].orderedSets { check(set, reps: 5, kg: 60) }
        outbox.sessionChanged(a)
        TrainStubURLProtocol.script([.echo])
        await outbox.flush()
        #expect(a.uploaded)
        let workout = UUID()
        let answer = try completedCopy(TrainStubURLProtocol.requests[0].body, workout: workout)

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo, .holdThen(200, answer), .offline])
        let finishing = Task { await outbox.finish(a) }
        #expect(await eventually { TrainStubURLProtocol.requests.count == 2 })   // `complete`, held
        check(a.orderedExercises[0].orderedSets[0], reps: 6, kg: 65)
        outbox.sessionChanged(a)                               // a `PUT` behind it
        let before = logged(a)
        TrainStubURLProtocol.release()
        _ = await finishing.value
        await settled(outbox)

        #expect(sent == ["PUT \(path(a.id))", "POST \(path(a.id, "/complete"))", "PUT \(path(a.id))"])
        #expect(a.status == .completed && !a.pendingCompletion && a.workoutId == workout && a.strain == 9.4)
        #expect(logged(a) == before)
        #expect(store.pendingOps().map(\.kind) == [.put])
        let put = try APIClient.jsonDecoder.decode(TrainSession.self, from: TrainStubURLProtocol.requests[2].body)
        let first = try #require(put.exercises[0].sets.first { $0.setIndex == 0 })
        #expect(first.weightKg == 65 && first.reps == 6)
        #expect(put.status == .completed)
    }

    /// ADR 0022 §1: the attempt's time is the injected clock's.
    @Test func aRefusalIsDatedByTheClock() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_795_000_000))
        let outbox = makeOutbox(clock: clock)
        let a = session("A")
        outbox.sessionChanged(a)
        TrainStubURLProtocol.script([refusal(422, "req-422")])
        await outbox.flush()
        #expect(a.lastAttempt?.at == clock.now())
    }

    // MARK: ADR 0022 §7, sessions wait for their exercises

    /// A session's `PUT` doesn't go while a custom exercise it uses is still queued (here behind it: an order no build
    /// writes, the strictest case). The exercise goes; the `PUT` goes at the next trigger. Meanwhile the session reads
    /// as waiting.
    @Test func aSessionWaitsForAQueuedExercise() async throws {
        let outbox = makeOutbox(owner: { "acct-alex" })
        let s = session("Push")
        let e = customExercise()
        SessionFactory.add(e, to: s, sets: 1, in: store)
        outbox.sessionChanged(s)
        store.cache(exercises: [e])
        store.enqueue(.exercise, sessionID: e.id, account: "acct-alex")
        #expect(store.pendingOps().map(\.kind) == [.put, .exercise])
        #expect(outbox.state(of: s.id) == .pending(.queued))

        TrainStubURLProtocol.script([try saved(e, name: "Landmine press"), .echo])
        await outbox.flush()
        #expect(sent == ["POST /v1/exercises"])
        #expect(store.pendingOps().map(\.kind) == [.put])
        await outbox.flush()
        #expect(sent == ["POST /v1/exercises", "PUT \(path(s.id))"] && store.pendingOps().isEmpty)
    }

    /// ADR 0022 §7, Retry. The session uses a custom exercise that has no op (demo's binding took it, or a build before
    /// O1 tried once): Retry queues its `POST` again, ahead, then the session's `PUT` and `complete`, which keeps the
    /// body weight given at Finish.
    @Test func retryQueuesAMissingExerciseAndKeepsTheBodyWeight() async throws {
        let outbox = makeOutbox()
        let s = session("Push")
        let e = customExercise()
        store.cache(exercises: [e])
        SessionFactory.add(e, to: s, sets: 1, in: store)
        _ = await outbox.finish(s, bodyweightKg: 82.5)        // offline
        await settled(outbox)
        s.bodyweightKg = nil                                   // finished by a build before N6: only the op has it
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([refusal(422, "req-422")])
        await outbox.flush()
        #expect(s.lastAttempt?.status == 422)
        #expect(store.pendingOps().map(\.kind) == [.put, .complete])

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([try saved(e, name: "Landmine press"), .echo,
                                     .status(200, try Fixture.data("train_session_completed"))])
        await outbox.retry(sessionID: s.id)
        #expect(sent == ["POST /v1/exercises", "PUT \(path(s.id))", "POST \(path(s.id, "/complete"))"])
        #expect(store.pendingOps().isEmpty && !s.pendingCompletion && s.lastAttempt == nil)
        let complete = try APIClient.jsonDecoder.decode(SessionComplete.self, from: TrainStubURLProtocol.requests[2].body)
        #expect(complete.bodyweightKg == 82.5)
    }

    /// ADR 0022 §7: a plan that names a custom exercise still queued waits for its `POST` (the platform refuses a plan
    /// with an exercise it doesn't have).
    @Test func aPlanSaveWaitsForItsExercise() async throws {
        let outbox = makeOutbox()
        let lib = library(outbox)
        let e = customExercise()
        TrainStubURLProtocol.script([.offline])
        _ = await lib.createExercise(e)
        await settled(outbox)
        let plan = planNaming(e)
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([try saved(e, name: "Landmine press"), .status(200, try APIClient.jsonEncoder.encode(plan))])

        let ok = await lib.savePlan(plan)
        #expect(ok)
        #expect(Array(sent.prefix(2)) == ["POST /v1/exercises", "PUT /v1/plans/\(plan.id.uuidString.lowercased())"])
        #expect(!store.pendingOps().contains { $0.kind == .exercise })
    }

    /// The other order: the `POST` doesn't answer within the wait, so the plan goes as before, while the exercise's op
    /// is still queued.
    @Test func aPlanSaveWaitsNoLongerThanItsCap() async throws {
        let outbox = makeOutbox()
        let platform = MockPlatformAPI()
        let lib = library(outbox, remote: platform, exerciseWait: .milliseconds(200))
        let e = customExercise()
        TrainStubURLProtocol.script([.holdThen(201, try APIClient.jsonEncoder.encode(e))])
        _ = await lib.createExercise(e)
        #expect(await eventually { TrainStubURLProtocol.requests.count == 1 })   // the POST, held

        let ok = await lib.savePlan(planNaming(e))
        #expect(ok && platform.count("savePlan") == 1)
        #expect(store.pendingOps().contains { $0.kind == .exercise })
        TrainStubURLProtocol.release()
        await settled(outbox)
        #expect(store.pendingOps().isEmpty)
    }

    private func planNaming(_ e: Exercise) -> Plan {
        let day = PlanDay(dayIndex: 0, name: "Push", exercises: [
            PlanExercise(exercise: e, position: 0, sets: 3, repsMin: 8, repsMax: 12, targetKind: .kg, targetValue: 20,
                         restSec: 90),
        ])
        return Plan(name: "Alex's push", goal: .general, weeks: nil, daysPerWeek: 1, description: "",
                    progression: nil, isBuiltin: false, days: [day])
    }

    // MARK: TrainLibrary.createExercise, the name

    /// A name the platform refuses (empty, or over 80 characters as it counts them: Unicode scalars of the trimmed
    /// name) is never cached or queued; the library says why. 80 scalars is fine, however few characters they make, and
    /// so is a space around them. A NUL doesn't count: it's dropped first (N3), so NULs alone are no name.
    @Test(arguments: customExerciseNames)
    func aCustomExerciseNeedsAValidName(_ name: String, _ valid: Bool) async throws {
        let outbox = makeOutbox()
        let lib = library(outbox)
        var e = customExercise()
        e.name = name
        #expect(TrainLibrary.isValidName(name) == valid)    // what the sheet's Save asks
        let made = await lib.createExercise(e)
        await settled(outbox)
        #expect((made != nil) == valid)
        #expect((lib.error == nil) == valid)
        #expect(store.pendingOps().count == (valid ? 1 : 0))
        #expect((store.exercise(id: e.id) != nil) == valid)
    }

    // MARK: guards

    /// A wipe (sign-out) while the exercise's `POST` is out: its answer writes no row into the wiped store.
    @Test func aWipeMidExerciseWritesNothing() async throws {
        let outbox = makeOutbox()
        let lib = library(outbox)
        let e = customExercise()
        TrainStubURLProtocol.script([.holdThen(201, try APIClient.jsonEncoder.encode(e))])
        _ = await lib.createExercise(e)
        #expect(await eventually { TrainStubURLProtocol.requests.count == 1 })
        store.wipe()
        TrainStubURLProtocol.release()
        await settled(outbox)
        #expect(try store.context.fetchCount(FetchDescriptor<CachedExercise>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<PendingTrainOp>()) == 0)
    }

    /// Discarded while its `PUT` is out: the answer writes nothing, and the session stays gone.
    @Test func aDiscardMidPutWritesNothing() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        outbox.sessionChanged(a)
        TrainStubURLProtocol.script([.hold])
        let replay = Task { await outbox.flush() }
        #expect(await eventually { TrainStubURLProtocol.requests.count == 1 })
        outbox.discard(a)
        TrainStubURLProtocol.release()
        await replay.value
        await settled(outbox)
        #expect(try store.context.fetchCount(FetchDescriptor<LocalSession>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<LocalSet>()) == 0)
        #expect(store.pendingOps().isEmpty && sent == ["PUT \(path(a.id))"])
    }

    /// The same while the platform answers the `PUT` with its newer copy (`409`, an exercise this one doesn't have):
    /// nothing of it is merged into the discarded session, and no merge round follows.
    @Test func aDiscardMidPutConflictWritesNothing() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        outbox.sessionChanged(a)
        var server = a.wire
        server.exercises.append(SessionExercise(exerciseId: MockTrain.squat.id, position: 1,
                                                sets: [SessionSet(setIndex: 0, reps: 5, weightKg: 100)]))
        TrainStubURLProtocol.script([.holdThen(409, try APIClient.jsonEncoder.encode(server))])
        let replay = Task { await outbox.flush() }
        #expect(await eventually { TrainStubURLProtocol.requests.count == 1 })
        outbox.discard(a)
        TrainStubURLProtocol.release()
        await replay.value
        await settled(outbox)
        #expect(try store.context.fetchCount(FetchDescriptor<LocalSession>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<LocalSessionExercise>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<LocalSet>()) == 0)
        #expect(store.pendingOps().isEmpty && sent == ["PUT \(path(a.id))"])
    }

    /// Discarded while its `complete` is out: the answer (this session's own copy, by its ids) writes nothing and the
    /// `DELETE` goes. What fails if the discard check goes: applying the answer reads the deleted session's rows, which are
    /// detached, and SwiftData traps ("backing data was detached"), so the run crashes here rather than failing a check.
    /// The row counts, in this context and a fresh one, and the summary catch a write that gets past without reading them.
    @Test func aDiscardMidCompleteWritesNothing() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        let id = a.id
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: 100)
        _ = await outbox.finish(a)                             // offline
        await settled(outbox)
        let answer = try completedCopy(try APIClient.jsonEncoder.encode(a.wire), workout: UUID())
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo, .holdThen(200, answer), .status(204, Data())])
        let replay = Task { await outbox.flush() }
        #expect(await eventually { TrainStubURLProtocol.requests.count == 2 })
        outbox.discard(a)
        TrainStubURLProtocol.release()
        await replay.value
        await settled(outbox)
        #expect(outbox.lastCompletion == nil)
        #expect(store.session(id: id) == nil)
        #expect(try store.context.fetchCount(FetchDescriptor<LocalSession>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<LocalSessionExercise>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<LocalSet>()) == 0)
        let fresh = ModelContext(store.context.container)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalSession>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalSessionExercise>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalSet>()) == 0)
        #expect(store.pendingOps().isEmpty)
        #expect(sent == ["PUT \(path(a.id))", "POST \(path(a.id, "/complete"))", "DELETE \(path(a.id))"])
    }

    /// ADR 0022 §6: a refused `DELETE` is dropped (its session is gone here; nothing could show it or send it again).
    @Test func aRefusedDeleteIsDropped() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        outbox.sessionChanged(a)
        TrainStubURLProtocol.script([.echo])
        await outbox.flush()
        #expect(a.uploaded)
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([refusal(422, "req-del")])
        outbox.discard(a)
        await settled(outbox)
        await outbox.flush()
        #expect(sent == ["DELETE \(path(a.id))"])
        #expect(store.pendingOps().isEmpty && outbox.pendingCount == 0)
    }

    /// One op per exercise and binding: made again under the same binding, it's the same op; under another, that
    /// binding gets its own (an op only goes through its own client, ADR 0008 §4).
    @Test func oneExerciseOpPerBinding() async throws {
        let binding = Binding()
        let outbox = makeOutbox(owner: { binding.owner })
        let e = customExercise()
        outbox.queueExercise(e)                                // offline
        await settled(outbox)
        outbox.queueExercise(e)
        await settled(outbox)
        #expect(store.pendingOps().map(\.account) == ["acct-alex"])
        binding.owner = "acct-sam"
        outbox.queueExercise(e)
        await settled(outbox)
        outbox.queueExercise(e)
        await settled(outbox)
        #expect(Set(store.pendingOps().compactMap(\.account)) == ["acct-alex", "acct-sam"])
        #expect(store.pendingOps().count == 2)
    }

    private final class Binding {
        var owner = "acct-alex"
    }

    /// ADR 0022 §8: a kind a later build queued is kept, never sent, never read as another kind, and not counted.
    /// The ops behind it go.
    @Test func anUnknownKindIsKeptAndPassedOver() async throws {
        let outbox = makeOutbox(owner: { "acct-alex" })
        let a = session("A")
        store.enqueue(.put, sessionID: UUID(), account: "acct-alex")
        let future = try #require(store.pendingOps().first)
        future.kindRaw = "split_session"
        store.save()
        outbox.sessionChanged(a)
        TrainStubURLProtocol.script([.echo, .echo])
        await outbox.flush()
        #expect(sent == ["PUT \(path(a.id))"])
        #expect(store.pendingOps().map(\.kindRaw) == ["split_session"])
        #expect(outbox.pendingCount == 0)
    }

    // MARK: fix round 3

    /// N3, API.md → Text: a NUL in a typed name never goes out (the platform answers `422` to a body with one). The
    /// library drops it before it checks the name, caches it and queues the `POST`.
    @Test func aNULInACustomExerciseNameIsDropped() async throws {
        let outbox = makeOutbox()
        let lib = library(outbox)
        let e = customExercise("Land\u{0}mine press")
        var platformCopy = e
        platformCopy.name = "Landmine press"
        platformCopy.nameEn = "Landmine press"
        platformCopy.nameDe = "Landmine press"
        TrainStubURLProtocol.script([.status(201, try APIClient.jsonEncoder.encode(platformCopy))])
        let made = await lib.createExercise(e)
        #expect(made?.name == "Landmine press" && made?.nameEn == "Landmine press" && made?.nameDe == "Landmine press")
        await settled(outbox)
        #expect(sent == ["POST /v1/exercises"])
        let body = TrainStubURLProtocol.requests[0].body
        let posted = try APIClient.jsonDecoder.decode(ExerciseInput.self, from: body)
        #expect(posted.name == "Landmine press" && posted.nameDe == nil)
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(!text.contains("\\u0000"))
        #expect(TrainLibrary.withoutNUL("\u{0}a\u{0}b\u{0}") == "ab" && TrainLibrary.withoutNUL("ab") == "ab")
    }

    /// N4: the platform answers a custom exercise's `POST` without taking it (`503` after the client's retries). Its
    /// op stays and the session that uses it waits, but an unrelated session's `PUT` and a discard's `DELETE` behind it
    /// still go. No network is different: then nothing goes until the next trigger.
    @Test func aHeldExerciseDoesNotHoldUnrelatedOps() async throws {
        let outbox = makeOutbox()
        let c = session("C")
        outbox.sessionChanged(c)
        TrainStubURLProtocol.script([.echo])
        await outbox.flush()
        #expect(c.uploaded)
        TrainStubURLProtocol.reset()
        let e = customExercise()
        outbox.queueExercise(e)                                // offline
        await settled(outbox)
        let s = session("S")
        SessionFactory.add(e, to: s, sets: 1, in: store)
        outbox.sessionChanged(s)
        let b = session("B")
        outbox.sessionChanged(b)
        outbox.discard(c)                                      // its replay finds no network either
        #expect(await eventually { TrainStubURLProtocol.requests.count == 2 })
        await settled(outbox)
        #expect(store.pendingOps().map(\.kind) == [.exercise, .put, .put, .delete])

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script(Array(repeating: refusal(503, "req-503"), count: APIClient.maxUnavailableRetries + 1)
            + [.echo, .status(204, Data())])
        await outbox.flush()
        let posts = Array(repeating: "POST /v1/exercises", count: APIClient.maxUnavailableRetries + 1)
        #expect(sent == posts + ["PUT \(path(b.id))", "DELETE \(path(c.id))"])
        #expect(store.pendingOps().map(\.kind) == [.exercise, .put])
        #expect(store.pendingOps().map(\.sessionId) == [e.id, s.id])
        let op = try #require(store.pendingOps().first)
        #expect(op.lastAttempt == nil && b.uploaded && !s.uploaded)

        let d = session("D")
        outbox.sessionChanged(d)
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.offline, .echo, .echo])
        await outbox.flush()
        #expect(sent == ["POST /v1/exercises"])
        #expect(store.pendingOps().map(\.sessionId) == [e.id, s.id, d.id])
    }

    /// S3: a `405` (a `4xx` the contract doesn't list: "like `400`") on the exercise's `POST` is a refusal, kept on the
    /// op, as `422` is.
    @Test func anExerciseAnswered405IsRefused() async throws {
        let outbox = makeOutbox()
        let e = customExercise()
        TrainStubURLProtocol.script([refusal(405, "req-405")])
        outbox.queueExercise(e)
        await settled(outbox)
        let op = try #require(store.pendingOps().first)
        let attempt = try #require(op.lastAttempt)
        #expect(op.kind == .exercise && attempt.status == 405 && attempt.requestID == "req-405" && attempt.isRefusal)
        TrainStubURLProtocol.reset()
        await outbox.flush()
        #expect(TrainStubURLProtocol.requests.isEmpty)
    }

    /// S3: a session this build can't encode (a weight that isn't finite: JSON has no infinity) never leaves: an
    /// `EncodingError` before any request is a refusal, kept with Retry, and it doesn't hold the queue. B's `PUT` goes;
    /// nothing of A goes again. (Not NaN: SQLite stores it as NULL, so the saved set has no weight and goes.)
    @Test func aSessionThatCantBeEncodedIsRefusedAndOthersGo() async throws {
        let outbox = makeOutbox()
        let a = session("A"), b = session("B")
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: .infinity)
        outbox.sessionChanged(a)
        outbox.sessionChanged(b)
        TrainStubURLProtocol.script([.echo, .echo])
        await outbox.flush()

        #expect(sent == ["PUT \(path(b.id))"])
        let attempt = try #require(a.lastAttempt)
        #expect(attempt.status == nil && attempt.request == .put && attempt.kind == .other && attempt.isRefusal)
        #expect(outbox.state(of: a.id) == .failed(attempt))
        #expect(store.pendingOps().map(\.sessionId) == [a.id] && b.uploaded)
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo])
        await outbox.flush()
        #expect(TrainStubURLProtocol.requests.isEmpty)
    }

    /// N6: Finish stores the body weight on the session. A `complete` that's in flight or gone when Retry queues the
    /// upload again leaves no op to take it from: the session's goes, on the `PUT` and on the new `complete`.
    @Test func retryTakesTheBodyWeightFromTheSessionWhenTheCompleteIsGone() async throws {
        let outbox = makeOutbox()
        let a = session("A")
        check(a.orderedExercises[0].orderedSets[0], reps: 5, kg: 100)
        _ = await outbox.finish(a, bodyweightKg: 82.5)        // offline
        await settled(outbox)
        #expect(a.bodyweightKg == 82.5)
        let complete = try #require(store.pendingOps().first { $0.kind == .complete })
        store.dequeue(complete)
        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([refusal(422, "req-422")])
        await outbox.flush()
        #expect(a.lastAttempt?.status == 422 && store.pendingOps().map(\.kind) == [.put])

        TrainStubURLProtocol.reset()
        TrainStubURLProtocol.script([.echo, .status(200, try Fixture.data("train_session_completed"))])
        await outbox.retry(sessionID: a.id)
        #expect(sent == ["PUT \(path(a.id))", "POST \(path(a.id, "/complete"))"])
        let put = try APIClient.jsonDecoder.decode(TrainSession.self, from: TrainStubURLProtocol.requests[0].body)
        #expect(put.bodyweightKg == 82.5)
        let body = try APIClient.jsonDecoder.decode(SessionComplete.self, from: TrainStubURLProtocol.requests[1].body)
        #expect(body.bodyweightKg == 82.5)
        #expect(store.pendingOps().isEmpty && !a.pendingCompletion)
    }

    /// N1: every plan save that waits for the same `POST` ends its wait at the cap, and leaves nothing behind: no waiter
    /// and no cap on the clock.
    @Test func heldPlanSavesLeaveNoWaiterBehind() async throws {
        let clock = TestClock()
        let outbox = makeOutbox(clock: clock)
        let platform = MockPlatformAPI()
        let lib = library(outbox, remote: platform)
        let e = customExercise()
        TrainStubURLProtocol.script([.holdThen(201, try APIClient.jsonEncoder.encode(e))])
        _ = await lib.createExercise(e)
        #expect(await eventually { TrainStubURLProtocol.requests.count == 1 })   // the POST, held
        let saves = (0..<3).map { _ in Task { await lib.savePlan(planNaming(e)) } }
        #expect(await eventually { outbox.exerciseWaiterCount == 3 && clock.pendingSleeps == 3 })

        clock.advance(by: .seconds(10))
        for save in saves {
            let ok = await save.value
            #expect(ok)
        }
        #expect(platform.count("savePlan") == 3)
        #expect(outbox.exerciseWaiterCount == 0 && clock.pendingSleeps == 0)
        #expect(store.pendingOps().contains { $0.kind == .exercise })   // the POST is still out
        TrainStubURLProtocol.release()
        await settled(outbox)
        #expect(store.pendingOps().isEmpty)
    }

    /// N1: the exercise went before the cap: the save goes at once, and its cap is gone from the clock.
    @Test func aPlanSaveWokenEarlyCancelsItsCap() async throws {
        let clock = TestClock()
        let outbox = makeOutbox(clock: clock)
        let platform = MockPlatformAPI()
        let lib = library(outbox, remote: platform)
        let e = customExercise()
        TrainStubURLProtocol.script([.holdThen(201, try APIClient.jsonEncoder.encode(e))])
        _ = await lib.createExercise(e)
        #expect(await eventually { TrainStubURLProtocol.requests.count == 1 })
        let save = Task { await lib.savePlan(planNaming(e)) }
        #expect(await eventually { outbox.exerciseWaiterCount == 1 && clock.pendingSleeps == 1 })

        TrainStubURLProtocol.release()
        let ok = await save.value
        #expect(ok && platform.count("savePlan") == 1)
        #expect(outbox.exerciseWaiterCount == 0 && clock.pendingSleeps == 0)
        await settled(outbox)
    }

    /// N1: a plan save cancelled while it waits ends then (the `POST` is still out), takes its waiter and its cap with
    /// it, and sends nothing.
    @Test func aCancelledPlanSaveStopsWaiting() async throws {
        let clock = TestClock()
        let outbox = makeOutbox(clock: clock)
        let platform = MockPlatformAPI()
        let lib = library(outbox, remote: platform)
        let e = customExercise()
        TrainStubURLProtocol.script([.holdThen(201, try APIClient.jsonEncoder.encode(e))])
        _ = await lib.createExercise(e)
        #expect(await eventually { TrainStubURLProtocol.requests.count == 1 })
        let save = Task { await lib.savePlan(planNaming(e)) }
        #expect(await eventually { outbox.exerciseWaiterCount == 1 && clock.pendingSleeps == 1 })

        save.cancel()
        let ok = await save.value
        #expect(!ok && platform.count("savePlan") == 0)
        #expect(store.pendingOps().contains { $0.kind == .exercise })   // it didn't wait for the POST
        #expect(outbox.exerciseWaiterCount == 0 && clock.pendingSleeps == 0)
        clock.advance(by: .seconds(10))
        TrainStubURLProtocol.release()
        await settled(outbox)
    }

    /// N2: another account (or sign-out, or the Demo data switch) while a plan save waits for its exercise. The save is
    /// dropped: nothing goes, and nothing is cached for whoever is signed in now.
    @Test func aPlanSaveAcrossAnAccountChangeSendsNothing() async throws {
        let clock = TestClock()
        let outbox = makeOutbox(clock: clock)
        let platform = MockPlatformAPI()
        let lib = library(outbox, remote: platform)
        let e = customExercise()
        TrainStubURLProtocol.script([.holdThen(201, try APIClient.jsonEncoder.encode(e))])
        _ = await lib.createExercise(e)
        #expect(await eventually { TrainStubURLProtocol.requests.count == 1 })
        let plan = planNaming(e)
        let save = Task { await lib.savePlan(plan) }
        #expect(await eventually { outbox.exerciseWaiterCount == 1 })

        outbox.accountChanged()
        TrainStubURLProtocol.release()
        let ok = await save.value
        #expect(!ok && lib.error == nil)
        #expect(platform.count("savePlan") == 0)
        #expect(store.plan(id: plan.id) == nil)
        #expect(outbox.exerciseWaiterCount == 0 && clock.pendingSleeps == 0)
        await settled(outbox)
    }
}
