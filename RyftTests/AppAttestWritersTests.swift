import Foundation
import Testing
@testable import Ryft

private func delta(_ n: Int) -> HealthDelta {
    let t = Date(timeIntervalSince1970: 1_792_300_000)
    return HealthDelta(samples: (0..<n).map {
        Sample(type: .heartRate, start: t.addingTimeInterval(Double($0) * 60), end: t.addingTimeInterval(Double($0) * 60),
               value: 60, unit: "bpm", source: "Garmin")
    })
}

private let refusal = AttestServer.Reply.refusal(403, code: "app_attest_required", requestID: "rid-aa")

/// A Train outbox whose client is the real `APIClient` with an attestor, against the scripted platform.
@MainActor
final class TrainWriterRig {
    let rig = AttestRig()
    let store = TrainStore(inMemory: true)
    let service: TrainSyncService

    private init() {
        let api: APIClient = rig.api
        // A long debounce: the tests flush by hand, so a sleeping debounce never adds a request of its own.
        service = TrainSyncService(store: store, remote: { api }, debounce: .seconds(3_600), monitorsNetwork: false)
        service.gate = { _ in nil }
    }

    /// With a token in hand and 61 s on the clock, so a refusal may start a renewal (`refusalSpacing`).
    static func make(pastTheRenewalSpacing: Bool = true) async throws -> TrainWriterRig {
        let rig = TrainWriterRig()
        try await rig.rig.getMe()
        if pastTheRenewalSpacing { rig.rig.clock.advance(by: .seconds(61)) }
        return rig
    }

    func session(_ title: String) -> LocalSession {
        let s = SessionFactory.empty(in: store)
        s.title = title
        SessionFactory.add(MockTrain.bench, to: s, sets: 2, in: store)
        s.orderedExercises[0].orderedSets[0].reps = 5
        s.orderedExercises[0].orderedSets[0].weightKg = 100
        s.orderedExercises[0].orderedSets[0].completedAt = .now
        s.orderedExercises[0].orderedSets[0].updatedAt = .now
        return s
    }

    func put(_ id: UUID) -> String { "PUT /v1/sessions/\(id.uuidString.lowercased())" }
    func complete(_ id: UUID) -> String { "POST /v1/sessions/\(id.uuidString.lowercased())/complete" }
    func echo(_ id: UUID) {
        rig.server.route(put(id)) { request, _ in .json(200, String(decoding: request.body, as: UTF8.self)) }
    }
}

/// AC7: a write the platform refuses for App Attest stays queued, whatever the retry did.
@Suite("App Attest: refused writes stay queued (AC7)")
@MainActor
struct AppAttestWriterTests {
    @Test(arguments: [PendingTrainOp.Kind.put, .complete, .delete, .exercise])
    func aTrainOpRefusedWithTheAttestCodeHolds(_ kind: PendingTrainOp.Kind) {
        // Pinned against ADR 0022 §1 (any `403` holds): App Attest's never becomes a refusal, whatever moves there.
        let error = APIError.http(403, "x", requestID: "r", code: .appAttestRequired)
        #expect(TrainSyncService.disposition(of: kind, error, at: .now) == .hold)
    }

    @Test func aTrainPutRefusedAgainAfterTheRetryStaysInTheOutboxAndGoesLater() async throws {
        let t = try await TrainWriterRig.make()
        let a = t.session("A")
        t.rig.server.route(t.put(a.id)) { _, _ in refusal }
        t.service.sessionChanged(a)
        await t.service.flush()

        #expect(t.service.pendingCount == 1)
        #expect(t.store.pendingOps().map(\.kind) == [.put])
        // Sent, a new token fetched, sent again: then kept, not dropped.
        #expect(t.rig.server.appTokens(t.put(a.id)) == ["tok-1", "tok-2"])
        #expect(t.rig.server.count(AttestServer.token) == 2)
        #expect(t.service.lastError == APIError.http(403, "", code: .appAttestRequired).localizedDescription)

        // The platform accepts it later (App Attest served and the token fine): the same op goes.
        t.echo(a.id)
        await t.service.flush()
        #expect(t.service.pendingCount == 0 && t.store.pendingOps().isEmpty)
        #expect(a.uploaded)
    }

    @Test func aTrainPutRefusedWhereNoRenewalMayStartStaysToo() async throws {
        let t = try await TrainWriterRig.make(pastTheRenewalSpacing: false)
        let a = t.session("A")
        t.rig.server.route(t.put(a.id)) { _, _ in refusal }
        t.service.sessionChanged(a)
        await t.service.flush()
        #expect(t.service.pendingCount == 1)
        #expect(t.rig.server.count(t.put(a.id)) == 1)               // no resend: a renewal started a moment ago
    }

    @Test func aCompleteRefusedAgainAfterTheRetryStaysQueuedAndTheSessionPending() async throws {
        let t = try await TrainWriterRig.make()
        let a = t.session("A")
        t.echo(a.id)
        t.rig.server.route(t.complete(a.id)) { _, _ in refusal }
        let done = await t.service.finish(a)

        #expect(done == nil)                                        // "will sync"
        #expect(a.pendingCompletion && a.status == .completed)
        #expect(t.service.pendingCount == 1)
        #expect(t.store.pendingOps().map(\.kind) == [.complete])
        #expect(t.rig.server.appTokens(t.complete(a.id)) == ["tok-1", "tok-2"])

        t.rig.server.route(t.complete(a.id)) { _, _ in .json(200, String(decoding: (try? Fixture.data("train_session_completed")) ?? Data(), as: UTF8.self)) }
        await t.service.flush()
        #expect(t.service.pendingCount == 0 && !a.pendingCompletion)
    }

    @Test func aSyncPageRefusedForAttestationCommitsNoAnchorAndIsNoGate() async throws {
        let health = MockHealthStore(streams: [.quantity(.heartRate)],
                                     pages: [.quantity(.heartRate): [delta(2), delta(2)]])
        health.commit(HealthPage(delta: HealthDelta(), anchor: nil, more: false), for: .sleep) // not a first sync
        let api = MockPlatformAPI()
        api.failNext = APIError.http(403, "refused", requestID: "rid-sync", code: .appAttestRequired)
        let sync = SyncService.ungated(env: .test(api: api, health: health))

        await sync.syncNow()

        #expect(api.count("sync") == 1)
        #expect(health.committed == [.sleep])                       // the seeded anchor only: the page's isn't kept
        #expect(sync.pausedFor == nil)                              // not the invite or consent screen
        #expect(sync.lastError == APIError.http(403, "", code: .appAttestRequired).localizedDescription)
        #expect(sync.lastErrorDetails?.contains("rid-sync") == true)
    }

    @Test func anActivityRefusedForAttestationIsTransientAndKept() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = APIError.http(403, "refused", requestID: "req-aa", code: .appAttestRequired)
        await h.uploader.flush()

        let row = try #require(h.store.snapshot(id: id))
        let attempt = try #require(row.lastAttempt)
        #expect(attempt.kind == .transient && attempt.status == 403)
        #expect(attempt.code == "app_attest_required" && attempt.requestID == "req-aa" && attempt.request == .put)
        #expect(row.sentAt == nil && row.needsUpload)               // the platform stored nothing
        #expect(h.uploader.state(of: id) == .pending(.retrying(at: h.clock.now().addingTimeInterval(30))))

        // Tried again at the backoff's pace, like an outage.
        #expect(await eventually { h.clock.pendingSleeps == 1 })
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { h.puts() == 2 })
        #expect(await eventually { h.uploader.state(of: id) == .confirmed })
    }

    @Test func anImportRefusedForAttestationIsHeldNotGatedAndResumes() async throws {
        let h = ImportUploadHarness()
        h.live.failure = APIError.http(403, "refused", requestID: "req-aa", code: .appAttestRequired)
        let sessions = ImportUploadHarness.sessions(120)
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))

        let status = try #require(h.uploader.status)
        #expect(status.phase == .paused(.held))                     // nothing for the user to answer
        #expect(status.sessions.pending == 120 && status.rejected.isEmpty)
        #expect(status.lastFailure?.requestID == "req-aa")
        #expect(h.live.count("importTraining") == 1)
        #expect(h.jobs().count == 1)

        h.live.failure = nil
        await h.uploader.resume()
        #expect(h.uploader.status?.phase == .finished)
    }
}
