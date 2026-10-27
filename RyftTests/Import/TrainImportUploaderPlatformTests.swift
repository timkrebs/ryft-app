import Foundation
import SwiftData
import Testing
@testable import Ryft

private typealias H = ImportUploadHarness

/// How the upload meets the platform's answers (API.md → `POST /v1/train/import`, Errors): waits, the flag, per-item
/// codes, the limits of a request, and the one rule for a job that needs attention.
@Suite("Import upload: the platform's answers")
@MainActor
struct TrainImportUploaderPlatformTests {
    // MARK: 429 and the waits

    /// Another import runs: the pass waits `Retry-After` (not the 30 s backoff), then sends the same request again; the
    /// job is paused, never failed, and nothing is shown as a failure.
    @Test func importInProgressWaitsRetryAfterAndResendsTheSameRequest() async throws {
        let h = H()
        let sessions = H.sessions(3)
        h.live.failNext = APIError.http(429, "busy", requestID: "req-429", code: .importInProgress, retryAfter: 10)
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        #expect(h.uploader.status?.phase == .paused(.retrying(at: h.clock.now().addingTimeInterval(10))))
        #expect(h.uploader.status?.lastFailure == nil)
        #expect(h.uploader.status?.sessions == ImportItemCounts(total: 3))
        #expect(await eventually { h.clock.pendingSleeps == 1 })
        h.clock.advance(by: .seconds(9))
        await h.uploader.resume() // not due yet
        #expect(h.live.count("importTraining") == 1)
        h.clock.advance(by: .seconds(1))
        #expect(await eventually { h.uploader.status?.phase == .finished })
        #expect(h.live.count("importTraining") == 2)
        #expect(h.requests.map(\.sessionIDs) == [sessions.map(\.id)])
        #expect(h.uploader.status?.sessions == ImportItemCounts(total: 3, done: 3))
    }

    /// Without a `Retry-After` the wait is 10 s.
    @Test func importInProgressWithoutRetryAfterWaitsTenSeconds() async throws {
        let h = H()
        h.live.failNext = APIError.http(429, "busy", code: .importInProgress)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        #expect(h.uploader.status?.phase == .paused(.retrying(at: h.clock.now().addingTimeInterval(10))))
    }

    /// Another import that keeps running doesn't count as failures: the wait stays 10 s, it never backs off.
    @Test func importInProgressNeverBacksOff() async throws {
        let h = H()
        h.live.trainImportSource.importInProgressAnswers = 3
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(2))))
        for answered in 1...3 {
            #expect(await eventually { h.live.count("importTraining") == answered && h.clock.pendingSleeps == 1 })
            #expect(h.uploader.status?.phase == .paused(.retrying(at: h.clock.now().addingTimeInterval(10))))
            h.clock.advance(by: .seconds(10))
        }
        #expect(await eventually { h.uploader.status?.phase == .finished })
        #expect(h.live.count("importTraining") == 4)
    }

    /// A rate limit waits what the platform says, exactly (not the longer backoff step).
    @Test func aRateLimitHonoursRetryAfter() async throws {
        let h = H()
        h.live.failNext = APIError.http(429, "slow down", requestID: "req-429", retryAfter: 5)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        #expect(h.uploader.status?.phase == .paused(.retrying(at: h.clock.now().addingTimeInterval(5))))
        #expect(h.uploader.status?.lastFailure?.status == 429)
    }

    /// A rate limit without `Retry-After` backs off like a `5xx`.
    @Test func aRateLimitWithoutRetryAfterBacksOff() async throws {
        let h = H()
        h.live.failNext = APIError.http(429, "slow down")
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        #expect(h.uploader.status?.phase == .paused(.retrying(at: h.clock.now().addingTimeInterval(30))))
    }

    /// `503` with `Retry-After` is transient: it waits the longer of the backoff and the header.
    @Test func unavailableWaitsRetryAfter() async throws {
        let h = H()
        h.live.failNext = APIError.http(503, "request timed out", requestID: "req-503", retryAfter: 45)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        #expect(h.uploader.status?.phase == .paused(.retrying(at: h.clock.now().addingTimeInterval(45))))
        #expect(h.uploader.status?.lastFailure?.requestID == "req-503")
        #expect(h.uploader.status?.sessions.rejected == 0)
    }

    // MARK: 403

    /// The flag is off for the account: not retried, not a gate, no consent or invite screen; the job is kept as "saved
    /// on this iPhone" and nothing more is sent until the app is opened again: then one probe, and if the platform still
    /// says no, it stops again (no hammering by reconnects or resumes in between).
    @Test func importNotEnabledStopsCleanly() async throws {
        let h = H()
        h.live.trainImportSource.notEnabled = true
        #expect(h.uploader.uploadsAvailable)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(3))))
        let status = try #require(h.uploader.status)
        #expect(status.phase == .paused(.notAvailable))
        #expect(status.lastFailure?.status == 403 && status.lastFailure?.code == "import_not_enabled")
        #expect(status.sessions == ImportItemCounts(total: 3) && !status.hasRejected)
        #expect(!h.uploader.uploadsAvailable)
        #expect(h.jobs().count == 1)
        await h.uploader.resume()
        await h.uploader.resume()
        #expect(h.live.count("importTraining") == 1)
        #expect(h.uploader.status?.phase == .paused(.notAvailable))
        // Opening the app asks once; still not enabled: latched again.
        await h.uploader.appBecameActive()
        #expect(h.live.count("importTraining") == 2)
        #expect(h.uploader.status?.phase == .paused(.notAvailable) && !h.uploader.uploadsAvailable)
        await h.uploader.resume()
        #expect(h.live.count("importTraining") == 2)
    }

    /// The platform enables imports for the account while the app runs: the next activation finds it and the job goes.
    @Test func importEnabledLaterIsFoundOnTheNextActivation() async throws {
        let h = H()
        h.live.trainImportSource.notEnabled = true
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(2))))
        #expect(h.uploader.status?.phase == .paused(.notAvailable))
        h.live.trainImportSource.notEnabled = false
        await h.uploader.resume()
        #expect(h.uploader.status?.phase == .paused(.notAvailable)) // not before the app is opened
        await h.uploader.appBecameActive()
        #expect(h.uploader.status?.phase == .finished)
        #expect(h.uploader.uploadsAvailable)
    }

    /// Consent is asked for: the job holds behind the consent gate (the user answers it), and goes again, unchanged,
    /// once the gate lets it.
    @Test func consentRequiredHoldsThenResends() async throws {
        let h = H()
        let sessions = H.sessions(2)
        h.live.failNext = APIError.http(403, "consent", requestID: "req-403", code: .consentRequired)
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        #expect(h.uploader.status?.phase == .paused(.gated(.gate(.consentRequired))))
        #expect(h.uploader.status?.sessions.rejected == 0)
        h.gate = nil
        await h.uploader.resume() // the gate opening
        #expect(h.uploader.status?.phase == .finished)
        #expect(h.live.count("importTraining") == 2)
        #expect(h.requests.map(\.sessionIDs) == [sessions.map(\.id)])
    }

    /// A request that can't be right (`400`): the item is refused with the request ID in its Details, and the state says so.
    @Test func aBadRequestIsRefusedWithItsRequestID() async throws {
        let h = H()
        h.live.failNext = APIError.http(400, "unknown field", requestID: "req-400")
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        let status = try #require(h.uploader.status)
        #expect(status.sessions == ImportItemCounts(total: 1, rejected: 1))
        #expect(status.rejected.first?.requestID == "req-400")
        #expect(status.lastFailure?.status == 400 && status.lastFailure?.requestID == "req-400")
        #expect(status.phase == .finished)
    }

    // MARK: per-item results

    /// A rejected item keeps the platform's code and words, and the request's `X-Request-ID` for the Details.
    @Test func aRejectedItemShowsTheRequestID() async throws {
        let h = H()
        let sessions = H.sessions(3)
        let bad = sessions[1].id
        h.live.trainImportSource.rejectIDs = [bad: "exercise 4f6a is neither built-in nor yours"]
        h.live.trainImportSource.rejectCodes = [bad: "unknown_exercise"]
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        let status = try #require(h.uploader.status)
        #expect(status.sessions == ImportItemCounts(total: 3, done: 2, rejected: 1))
        let item = try #require(status.rejected.first)
        #expect(item.id == bad && item.code == "unknown_exercise")
        #expect(item.reason == "exercise 4f6a is neither built-in nor yours")
        #expect(item.requestID == "mock-req-1")
        #expect(status.leftAsIs == 0)
    }

    /// Any code, even one this build doesn't know, is a refusal like the rest.
    @Test(arguments: ["invalid", "unknown_exercise", "id_taken", "something_new"])
    func everyOtherCodeIsAnOrdinaryRefusal(_ code: String) async throws {
        let h = H()
        let sessions = H.sessions(2)
        h.live.trainImportSource.rejectIDs = [sessions[0].id: "field x"]
        h.live.trainImportSource.rejectCodes = [sessions[0].id: code]
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        #expect(h.uploader.status?.rejected.map(\.code) == [code])
        #expect(h.uploader.status?.sessions == ImportItemCounts(total: 2, done: 1, rejected: 1))
        #expect(h.requests.count == 1) // never resent on its own
    }

    /// Changed in the app since the import wrote it: left as it is, "already there", not a failure and not a rejection.
    @Test func newerOnServerIsLeftAsIsNotAFailure() async throws {
        let h = H()
        let sessions = H.sessions(3)
        let plan = H.plan(1)
        h.live.trainImportSource.rejectIDs = [sessions[0].id: "changed in the app", plan.id: "changed in the app"]
        h.live.trainImportSource.rejectCodes = [sessions[0].id: "newer_on_server", plan.id: "newer_on_server"]
        #expect(await h.run(ImportUploadPlan(plans: [plan], sessions: sessions)))
        let status = try #require(h.uploader.status)
        #expect(status.phase == .finished && !status.hasRejected)
        #expect(status.sessions == ImportItemCounts(total: 3, done: 3) && status.plans == ImportItemCounts(total: 1, done: 1))
        #expect(status.leftAsIs == 2)
        #expect(status.leftAsIsSessions == 1 && status.sessionsImported == 2 && status.plansImported == 0)
        // Sets of the two sessions that were imported now; not the one left as it is.
        #expect(status.setsDone == 6)
        #expect(h.requests.count == 1) // the plan and the sessions in one request; nothing resent
    }

    /// T5: a session whose plan reference the platform doesn't know is sent again, once, without the references.
    @Test func unknownPlanReferenceIsResentWithoutLinks() async throws {
        let h = H()
        let plan = H.plan(1)
        var sessions = H.sessions(2)
        for index in sessions.indices {
            sessions[index].planDayId = plan.days.first?.id
            sessions[index].exercises[0].planExerciseId = plan.days.first?.exercises.first?.id
        }
        let bad = sessions[0].id
        h.live.trainImportSource.rejectIDs = [bad: "plan_day_id is unknown"]
        h.live.trainImportSource.rejectCodes = [bad: "unknown_plan_reference"]
        // The plan stays out of the request (a kept copy), so the references point nowhere for the platform.
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        let status = try #require(h.uploader.status)
        #expect(status.phase == .finished && !status.hasRejected)
        #expect(status.sessions == ImportItemCounts(total: 2, done: 2))
        #expect(h.requests.map(\.sessionIDs) == [sessions.map(\.id), [bad]])
        let stored = try #require(h.live.trainImportSource.session(id: bad))
        #expect(stored.planDayId == nil && stored.exercises.compactMap(\.planExerciseId).isEmpty)
        // The other one keeps its links.
        #expect(h.live.trainImportSource.session(id: sessions[1].id)?.planDayId == plan.days.first?.id)
        #expect(TrainImportUploader.withoutPlanLinks(sessions[0]).planDayId == nil)
    }

    /// The same answer after the resend refuses it: no loop.
    @Test func unknownPlanReferenceIsResentOnlyOnce() async throws {
        let h = H()
        var session = H.sessions(1)[0]
        session.planDayId = ImportBuildFixture.id(40_001)
        h.live.trainImportSource.rejectIDs = [session.id: "plan_day_id is unknown"]
        h.live.trainImportSource.rejectCodes = [session.id: "unknown_plan_reference"]
        // The platform says it again for the resend, which has no links: the answer is final then.
        h.live.trainImportSource.refusesUnlinkedSessions = true
        #expect(await h.run(ImportUploadPlan(sessions: [session])))
        #expect(h.requests.count == 2)
        #expect(h.uploader.status?.sessions == ImportItemCounts(total: 1, rejected: 1))
        #expect(h.uploader.status?.rejected.first?.code == "unknown_plan_reference")
    }

    // MARK: the limits of a request

    /// ≤ 50 sessions, ≤ 5 plans, ≤ 2,500 sets and a measured body under 1 MiB, however big the sessions are.
    @Test func everyRequestStaysWithinTheLimits() async throws {
        let h = H()
        let sessions = H.sessions(70, exercises: 2, sets: 50) // 100 sets each: 25 per request
        let plans = (1...7).map { H.plan($0) }
        #expect(await h.run(ImportUploadPlan(plans: plans, sessions: sessions)))
        #expect(h.uploader.status?.phase == .finished)
        let sets = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.exercises.reduce(0) { $0 + $1.sets.count }) })
        let requests = h.requests
        #expect(requests.allSatisfy { $0.planIDs.count <= 5 && $0.sessionIDs.count <= 50 })
        #expect(requests.allSatisfy { $0.sessionIDs.reduce(0) { $0 + (sets[$1] ?? 0) } <= 2_500 })
        #expect(requests.allSatisfy { $0.bytes <= TrainImportUploader.maxBodyBytes && $0.bytes <= 1 << 20 })
        // Plans first (5, then 2 with the first sessions), 25 sessions of 100 sets at most per request.
        #expect(requests.map(\.planIDs.count) == [5, 2, 0, 0])
        #expect(requests.map(\.sessionIDs.count) == [0, 25, 25, 20])
        #expect(requests.flatMap(\.sessionIDs) == sessions.map(\.id))
        #expect(h.live.count("importTraining") == 4)
    }

    // MARK: needs attention

    /// A job that needs attention (every request of the pass refused) is continued only by the user's Try again. None
    /// of the automatic triggers touches it, and it stays so after a relaunch.
    @Test func onlyTryAgainContinuesAJobThatNeedsAttention() async throws {
        let h = H()
        let sessions = H.sessions(50)
        h.live.failure = APIError.http(422, "exercise unknown", requestID: "req-422")
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        #expect(h.uploader.status?.phase == .paused(.needsAttention))
        let sent = h.live.count("importTraining")
        // The platform would take everything now: any trigger that sent again would show.
        h.live.failure = nil
        func untouched(_ trigger: String) {
            #expect(h.live.count("importTraining") == sent, Comment(rawValue: trigger))
            #expect(h.uploader.status?.phase == .paused(.needsAttention), Comment(rawValue: trigger))
            #expect(h.uploader.status?.sessions == ImportItemCounts(total: 50, rejected: 3), Comment(rawValue: trigger))
        }
        await h.uploader.resume()
        untouched("resume")
        await h.uploader.appBecameActive()
        untouched("app active")
        h.connectivity.update(false)
        h.connectivity.update(true)
        for _ in 0..<50 { await Task.yield() }
        await h.uploader.resume()
        untouched("reconnect")
        h.gate = .gate(.consentRequired)
        h.gate = nil
        await h.uploader.resume() // what `gateChanged` does when the gate opens
        untouched("gate opens")
        await h.uploader.resume() // what the app does after a sign-in
        untouched("sign-in")
        // A relaunch keeps it.
        let again = h.relaunch()
        await again.resume()
        #expect(again.status?.phase == .paused(.needsAttention))
        #expect(h.live.count("importTraining") == sent)
        await again.appBecameActive()
        #expect(h.live.count("importTraining") == sent)
        // Try again: the rest goes.
        await again.tryAgain()
        #expect(again.status?.sessions == ImportItemCounts(total: 50, done: 47, rejected: 3))
        #expect(again.status?.phase == .finished)
        #expect(h.live.count("importTraining") > sent)
    }

    /// Try again lands while the pass is still writing "needs attention": it isn't lost (the flag cleared, nothing sent,
    /// the pause set), and neither the app nor a relaunch comes back needing attention.
    @Test func tryAgainDuringTheAttentionWriteIsNotLost() async throws {
        let h = H()
        h.live.failure = APIError.http(422, "exercise unknown", requestID: "req-422")
        var again: Task<Void, Never>?
        let uploader = h.uploader
        uploader.attentionStoreHook = {
            h.live.failure = nil // the platform would take everything now
            uploader.attentionStoreHook = nil
            again = Task { await uploader.tryAgain() }
            for _ in 0..<100 { await Task.yield() }
        }
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(50))))
        await again?.value
        #expect(again != nil)
        #expect(await eventually { h.uploader.status?.phase == .finished })
        #expect(h.uploader.status?.sessions == ImportItemCounts(total: 50, done: 47, rejected: 3))
        let relaunched = h.relaunch()
        await relaunched.resume()
        #expect(relaunched.status?.phase == .finished)
    }

    /// Try again also leaves the backoff of a transient pause at once (a user tap, not a trigger).
    @Test func tryAgainDoesNotWaitOutABackoff() async throws {
        let h = H()
        h.live.failNext = APIError.http(503, "busy", requestID: "req-503")
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(2))))
        #expect(h.uploader.status?.phase == .paused(.retrying(at: h.clock.now().addingTimeInterval(30))))
        await h.uploader.tryAgain()
        #expect(h.uploader.status?.phase == .finished)
    }
}
