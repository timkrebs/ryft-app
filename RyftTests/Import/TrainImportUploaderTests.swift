import Foundation
import SwiftData
import Testing
@testable import Ryft

private typealias H = ImportUploadHarness

/// The import's upload (design §7) against the fake platform on the test clock.
@Suite("Import upload: order, batches and results")
@MainActor
struct TrainImportUploaderBatchTests {
    /// Custom exercises one at a time first, then plans (≤ 5 per request), then sessions oldest first (≤ 50).
    @Test func itSendsInOrderAndInBatches() async throws {
        let h = H()
        let plans = (1...7).map { H.plan($0) }
        let sessions = H.sessions(120)
        let plan = ImportUploadPlan(exercises: [H.custom(1), H.custom(2)], plans: plans, sessions: sessions)
        #expect(await h.run(plan))
        let calls = h.live.calls.filter { $0 == "createExercise" || $0 == "importTraining" }
        #expect(calls == ["createExercise", "createExercise"] + Array(repeating: "importTraining", count: 4))
        #expect(h.requests.map(\.planIDs.count) == [5, 2, 0, 0])
        #expect(h.requests.map(\.sessionIDs.count) == [0, 50, 50, 20])
        #expect(h.requests.flatMap(\.sessionIDs) == sessions.map(\.id))
        #expect(Set(h.requests.map(\.source)) == ["alpha_progression"])
        let status = try #require(h.uploader.status)
        #expect(status.phase == .finished && !status.hasRejected)
        #expect(status.sessions == ImportItemCounts(total: 120, done: 120) && status.plans == ImportItemCounts(total: 7, done: 7))
        #expect(status.exercises.done == 2 && status.progress == 1)
        #expect(status.planIDs == plans.map(\.id))
        // What a result reopened from the resume row shows: sets imported, the plans by name.
        #expect(status.setsDone == 360)
        #expect(status.planSummaries.map(\.name) == plans.map(\.name))
        #expect(status.planSummaries.map(\.state) == Array(repeating: .done, count: 7))
        #expect(status.planSummaries.first?.weeks == 6 && status.planSummaries.first?.daysPerWeek == 1)
        // The custom exercises are in the library cache.
        #expect(h.persistence.exercise(id: H.custom(1).id) != nil)
    }

    /// Bodies are measured: a request never exceeds 1 MiB − 16 KiB, however few sessions that takes.
    @Test func requestsStayUnderTheBodyLimit() async throws {
        let h = H()
        // 50 exercises × 50 sets: about half a MiB each.
        let heavy = H.sessions(5, exercises: 50, sets: 50)
        #expect(await h.run(ImportUploadPlan(sessions: heavy)))
        #expect(h.requests.filter { $0.bytes > TrainImportUploader.maxBodyBytes }.isEmpty)
        #expect(h.requests.count >= 3)
        #expect(h.requests.flatMap(\.sessionIDs) == heavy.map(\.id))
        #expect(h.uploader.status?.phase == .finished)
    }

    /// A `413` halves the sessions per request, for the rest of the job.
    @Test func a413HalvesTheBatch() async throws {
        let h = H()
        let sessions = H.sessions(60)
        h.live.failNext = APIError.http(413, "too large", requestID: "req-413")
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        #expect(h.requests.map(\.sessionIDs.count) == [25, 25, 10])
        #expect(h.jobs().first?.sessionsPerRequest == 25)
        #expect(h.uploader.status?.phase == .finished)
    }

    /// A refused item is listed with the platform's reason and request ID, never retried on its own; Retry sends only it.
    @Test func aRejectedItemIsKeptAndOnlyRetrySendsItAgain() async throws {
        let h = H()
        let sessions = H.sessions(3)
        h.live.trainImportSource.rejectIDs = [sessions[1].id: "exercise not found"]
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        let status = try #require(h.uploader.status)
        #expect(status.phase == .finished && status.sessions == ImportItemCounts(total: 3, done: 2, rejected: 1))
        #expect(status.setsDone == 6)
        #expect(status.rejected.map(\.id) == [sessions[1].id])
        #expect(status.rejected.first?.reason == "exercise not found" && status.rejected.first?.title == "Pull")
        #expect(status.rejected.first?.date == sessions[1].startedAt)
        await h.uploader.resume()
        await h.uploader.appBecameActive()
        #expect(h.requests.count == 1)
        h.live.trainImportSource.rejectIDs = [:]
        await h.uploader.retryRejected()
        #expect(h.requests.map(\.sessionIDs) == [sessions.map(\.id), [sessions[1].id]])
        #expect(h.uploader.status?.phase == .finished && h.uploader.status?.hasRejected == false)
    }

    /// An answer that doesn't name an item leaves it pending; the third such answer refuses it.
    @Test func anItemNeverAnsweredIsRefusedAfterThreeAnswers() async throws {
        let h = H()
        let sessions = H.sessions(2)
        h.live.trainImportSource.omitIDs = [sessions[0].id]
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        #expect(h.requests.map(\.sessionIDs) == [sessions.map(\.id), [sessions[0].id], [sessions[0].id]])
        #expect(h.uploader.status?.rejected.map(\.id) == [sessions[0].id])
        #expect(h.uploader.status?.sessions.done == 1)
    }

    /// A whole request refused (a 4xx that isn't a gate): its items are refused with the request ID, the rest goes on.
    @Test func aRefusedRequestRefusesItsItemsAndTheRestGoesOn() async throws {
        let h = H()
        let sessions = H.sessions(60)
        h.live.failNext = APIError.http(422, "invalid", requestID: "req-422")
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        let status = try #require(h.uploader.status)
        #expect(status.sessions == ImportItemCounts(total: 60, done: 10, rejected: 50))
        #expect(Set(status.rejected.map(\.requestID)) == ["req-422"])
        #expect(status.lastFailure?.status == 422 && status.lastFailure?.requestID == "req-422")
        #expect(status.phase == .finished)
    }

    /// A custom exercise the platform refuses blocks what uses it; the rest goes.
    @Test func aRefusedCustomExerciseBlocksItsItems() async throws {
        let h = H()
        let custom = H.custom(1)
        let blocked = H.sessions(1, exercise: custom)
        let free = H.sessions(1, from: 5)
        h.live.failNext = APIError.http(422, "name", requestID: "req-ex")
        #expect(await h.run(ImportUploadPlan(exercises: [custom], plans: [H.plan(1, exercise: custom)], sessions: blocked + free)))
        #expect(h.requests.flatMap(\.sessionIDs) == free.map(\.id) && h.requests.flatMap(\.planIDs).isEmpty)
        let status = try #require(h.uploader.status)
        #expect(status.exercises.rejected == 1 && status.plans.blocked == 1 && status.sessions.blocked == 1)
        #expect(Set(status.rejected.filter(\.blocked).map(\.id)) == [blocked[0].id, H.plan(1).id])
        // Retry: the exercise goes, then what it blocked.
        await h.uploader.retryRejected()
        #expect(h.requests.last?.sessionIDs == blocked.map(\.id) && h.requests.last?.planIDs == [H.plan(1).id])
        #expect(h.uploader.status?.hasRejected == false)
    }

    /// "Make this my active plan": one enrolment, after its plan is there.
    @Test func itEnrolsOnceThePlanIsThere() async throws {
        let h = H()
        let plan = H.plan(1)
        #expect(await h.run(ImportUploadPlan(plans: [plan], sessions: H.sessions(2), enrolPlanID: plan.id)))
        #expect(h.live.count("enroll") == 1)
        let order = h.live.calls.filter { $0 == "importTraining" || $0 == "enroll" }
        #expect(order == ["importTraining", "enroll"])
        #expect(h.uploader.status?.enrolledPlanID == plan.id)
        await h.uploader.resume()
        #expect(h.live.count("enroll") == 1)
    }

    @Test func noEnrolmentWhenItsPlanWasRefused() async throws {
        let h = H()
        let plan = H.plan(1)
        h.live.trainImportSource.rejectIDs = [plan.id: "invalid plan"]
        #expect(await h.run(ImportUploadPlan(plans: [plan], enrolPlanID: plan.id)))
        #expect(h.live.count("enroll") == 0)
        #expect(h.uploader.status?.phase == .finished && h.uploader.status?.enrolledPlanID == nil)
        #expect(h.uploader.status?.planSummaries.map(\.state) == [.rejected])
    }

    /// A session whose plan was refused goes without its plan links.
    @Test func aRefusedPlansSessionsGoWithoutLinks() async throws {
        let h = H()
        let plan = H.plan(1)
        var linked = H.sessions(1)
        linked[0].planDayId = plan.days.first?.id
        linked[0].exercises[0].planExerciseId = plan.days.first?.exercises.first?.id
        h.live.trainImportSource.rejectIDs = [plan.id: "invalid plan"]
        // Plans and sessions travel together when there's room: refuse the first request's plan only.
        #expect(await h.run(ImportUploadPlan(plans: [plan, H.plan(2), H.plan(3), H.plan(4), H.plan(5), H.plan(6)], sessions: linked)))
        let stored = try #require(h.live.trainImportSource.sessions.first)
        #expect(stored.planDayId == nil && stored.exercises.first?.planExerciseId == nil)
    }

    /// Imports never touch the live-session path (ADR 0007 §4).
    @Test func noLocalSessionAndNoOutboxOp() async throws {
        let h = H()
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(3))))
        let logged = try h.persistence.context.fetchCount(FetchDescriptor<LocalSession>())
        #expect(logged == 0)
        #expect(h.persistence.pendingOps().isEmpty)
        #expect(h.live.count("putSession") == 0 && h.live.count("completeSession") == 0)
    }
}

@Suite("Import upload: pauses, retries and resume")
@MainActor
struct TrainImportUploaderResumeTests {
    /// Transient failures back off on the clock (30 s, then 2 min), and the job goes on where it stopped.
    @Test func aTransientFailureBacksOffOnTheClock() async throws {
        let h = H()
        let sessions = H.sessions(3)
        h.live.failNext = APIError.http(503, "busy", requestID: "req-503")
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        let due = h.clock.now().addingTimeInterval(30)
        #expect(h.uploader.status?.phase == .paused(.retrying(at: due)))
        #expect(h.uploader.status?.lastFailure?.requestID == "req-503")
        #expect(h.requests.isEmpty)
        #expect(await eventually { h.clock.pendingSleeps == 1 })
        h.clock.advance(by: .seconds(29))
        await h.uploader.resume() // not due yet
        #expect(h.requests.isEmpty)
        h.clock.advance(by: .seconds(1))
        #expect(await eventually { h.uploader.status?.phase == .finished })
        #expect(h.requests.map(\.sessionIDs) == [sessions.map(\.id)])
    }

    @Test func retryAfterIsHonoured() async throws {
        let h = H()
        h.live.failNext = APIError.http(429, "slow down", requestID: "req-429", retryAfter: 90)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        #expect(h.uploader.status?.phase == .paused(.retrying(at: h.clock.now().addingTimeInterval(90))))
    }

    @Test func theSecondFailureWaitsTwoMinutes() async throws {
        let h = H()
        h.live.failure = APIError.http(500, "oops")
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        #expect(await eventually { h.clock.pendingSleeps == 1 })
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { h.live.count("importTraining") == 2 })
        #expect(await eventually { h.uploader.status?.phase == .paused(.retrying(at: h.clock.now().addingTimeInterval(120))) })
    }

    /// The app ended mid-import: a new uploader on the same store finds the job and sends only what's left.
    @Test func aRelaunchContinuesWhereItStopped() async throws {
        let h = H()
        let sessions = H.sessions(70)
        let live = h.live
        // The first request goes through; the platform is down from the second on.
        h.live.trainImportSource.beforeImport = { live.failure = APIError.http(503, "down") }
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        #expect(h.requests.map(\.sessionIDs.count) == [50])
        #expect(h.uploader.status?.sessions.done == 50)
        h.live.trainImportSource.beforeImport = nil
        h.live.failure = nil
        let again = h.relaunch()
        await again.resume()
        #expect(again.status?.phase == .finished)
        #expect(h.requests.map(\.sessionIDs) == [Array(sessions.prefix(50).map(\.id)), Array(sessions.suffix(20).map(\.id))])
        #expect(again.status?.sessions == ImportItemCounts(total: 70, done: 70))
    }

    @Test func offlineItWaitsAndTheConnectionStartsIt() async throws {
        let h = H(online: false)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(2))))
        #expect(h.uploader.status?.phase == .paused(.offline))
        #expect(h.live.calls.isEmpty)
        h.connectivity.update(true)
        #expect(await eventually { h.uploader.status?.phase == .finished })
    }

    /// Before the contract (C2), or with `train.import` off: nothing is sent, the job is saved on this iPhone.
    @Test(arguments: [false, true])
    func withoutUploadsTheJobIsSavedOnThisIPhone(_ flagOff: Bool) async throws {
        let h = H(flag: !flagOff)
        if !flagOff { h.live.trainImportSource.publishesTrainImport = false }
        #expect(!h.uploader.uploadsAvailable)
        #expect(await h.run(ImportUploadPlan(exercises: [H.custom(1)], sessions: H.sessions(2))))
        #expect(h.uploader.status?.phase == .paused(.notAvailable))
        #expect(h.live.calls.isEmpty)
        #expect(h.jobs().count == 1)
        // Switched on: the next activation sends it.
        h.flags.overrides[.trainImport] = true
        h.live.trainImportSource.publishesTrainImport = true
        #expect(h.uploader.uploadsAvailable)
        await h.uploader.appBecameActive()
        #expect(h.uploader.status?.phase == .finished)
    }

    /// The live client before C2 throws `notPublished` and sends nothing.
    @Test func theLiveClientIsNotPublishedYet() async {
        #expect(!APIClient.shared.publishesTrainImport)
        await #expect(throws: TrainImportError.notPublished) {
            _ = try await APIClient.shared.importTraining(encoded: Data())
        }
    }

    /// The gate is asked before the first request and before every later one; a held job waits and goes when it opens.
    @Test func theGateHoldsAndReleases() async throws {
        let h = H()
        h.gate = .gate(.consentRequired)
        let sessions = H.sessions(60)
        #expect(await h.run(ImportUploadPlan(exercises: [H.custom(1)], sessions: sessions)))
        #expect(h.live.calls.isEmpty)
        #expect(h.uploader.status?.phase == .paused(.gated(.gate(.consentRequired))))
        #expect(h.jobs().count == 1)
        h.gate = nil
        await h.uploader.resume()
        #expect(h.uploader.status?.phase == .finished)
        #expect(h.requests.flatMap(\.sessionIDs) == sessions.map(\.id))
    }

    /// Consent withdrawn between two batches: the rest waits.
    @Test func theGateClosingMidJobHoldsTheRest() async throws {
        let h = H()
        let sessions = H.sessions(60)
        h.live.trainImportSource.beforeImport = { @MainActor [weak h] in h?.gate = .gate(.consentRequired) }
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        #expect(h.requests.map(\.sessionIDs.count) == [50])
        #expect(h.uploader.status?.phase == .paused(.gated(.gate(.consentRequired))))
        #expect(h.uploader.status?.sessions.done == 50)
    }

    /// A `403` with a code from the platform holds the job like the gate.
    @Test func aPlatformGateHoldsTheJob() async throws {
        let h = H()
        h.live.failNext = APIError.http(403, "consent", requestID: "req-403", code: .consentRequired)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(2))))
        #expect(h.uploader.status?.phase == .paused(.gated(.gate(.consentRequired))))
        #expect(h.uploader.status?.sessions.pending == 2)
    }

    /// The request in flight finishes inside a background task, which ends with the pass.
    @Test func theRequestInFlightFinishesInTheBackground() async throws {
        let h = H()
        let hold = RequestHold()
        h.live.trainImportSource.beforeImport = { await hold.wait() }
        #expect(await h.start(ImportUploadPlan(sessions: H.sessions(2))))
        #expect(await eventually { hold.waiting == 1 })
        let app = FakeBackgroundApp()
        let finishing = try #require(h.uploader.finishInBackground(app: app))
        #expect(app.begun == 1 && app.ended.isEmpty)
        hold.release()
        await finishing.value
        #expect(app.ended.count == 1)
        #expect(h.uploader.status?.phase == .finished)
    }
}

@Suite("Import upload: accounts and demo")
@MainActor
struct TrainImportUploaderAccountTests {
    /// Demo's job goes through the demo platform only, and never once demo is off.
    @Test func demoNeverGoesThroughTheLiveClient() async throws {
        let h = H(demo: true)
        #expect(h.account == ImportMappingStore.demoAccount)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(2))))
        #expect(h.demoAPI.trainImportSource.requests.count == 1)
        #expect(h.live.calls.isEmpty)
        // A second demo job, then demo off: the account sees none of it and nothing reaches the live platform.
        h.uploader.markResultSeen()
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(2, from: 10))))
        h.settings.demoMode = false
        h.uploader.accountChanged()
        TrainImportUploader.forgetDemo(in: h.persistence)
        await h.uploader.resume()
        #expect(h.uploader.status == nil && h.jobs().isEmpty)
        #expect(h.live.calls.isEmpty)
    }

    /// The account's job while demo data shows: it waits, and the demo platform never sees it.
    @Test func theAccountsJobWaitsWhileDemoShows() async throws {
        let h = H()
        h.gate = .gate(.consentRequired)
        let sessions = H.sessions(2)
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        h.gate = nil
        h.settings.demoMode = true
        h.uploader.accountChanged()
        await h.uploader.resume()
        #expect(h.uploader.status == nil)
        #expect(h.demoAPI.calls.isEmpty && h.live.calls.isEmpty)
        h.settings.demoMode = false
        h.uploader.accountChanged()
        await h.uploader.resume()
        #expect(h.uploader.status?.phase == .finished)
        #expect(h.requests.flatMap(\.sessionIDs) == sessions.map(\.id))
    }

    /// An answer that arrives after the account changed is dropped, and the next account's store has no job.
    @Test func anotherAccountNeverGetsTheJobOrItsAnswers() async throws {
        let h = H()
        let hold = RequestHold()
        h.live.trainImportSource.beforeImport = { await hold.wait() }
        #expect(await h.start(ImportUploadPlan(sessions: H.sessions(2))))
        #expect(await eventually { hold.waiting == 1 })
        // B signs in: the wipe runs inside it, the app's account-change handler a runloop later.
        await h.signIn(H.b)
        #expect(h.jobs().isEmpty)
        hold.release()
        // A's request completes; its answer finds another generation and writes nothing.
        #expect(await eventually { h.requests.count == 1 && !h.uploader.isRunning })
        h.uploader.accountChanged()
        await h.uploader.resume()
        #expect(h.jobs().isEmpty)
        #expect(h.uploader.status == nil)
        #expect(h.requests.count == 1)
    }

    /// Demo data switched on while the account's request is out (no wipe, the job stays): the answer is dropped,
    /// unrecorded, and the account's job sends that batch again once demo is off (it answers `unchanged`).
    @Test func anAnswerAfterTheDemoSwitchIsDropped() async throws {
        let h = H()
        let hold = RequestHold()
        h.live.trainImportSource.beforeImport = { await hold.wait() }
        let sessions = H.sessions(2)
        #expect(await h.start(ImportUploadPlan(sessions: sessions)))
        #expect(await eventually { hold.waiting == 1 })
        h.settings.demoMode = true
        hold.release()
        #expect(await eventually { h.requests.count == 1 && !h.uploader.isRunning })
        #expect(h.jobs().count == 1)
        h.settings.demoMode = false
        h.uploader.accountChanged()
        await h.uploader.resume()
        #expect(h.requests.map(\.sessionIDs) == [sessions.map(\.id), sessions.map(\.id)])
        #expect(h.uploader.status?.phase == .finished)
    }

    /// The account changes while a request is out: the pass stops and the request is cancelled, never a refusal.
    @Test func anAccountChangeCancelsTheRequestInFlight() async throws {
        let h = H()
        let hold = RequestHold()
        h.live.trainImportSource.beforeImport = { await hold.wait() }
        #expect(await h.start(ImportUploadPlan(sessions: H.sessions(2))))
        #expect(await eventually { hold.waiting == 1 })
        h.uploader.accountChanged()
        #expect(!h.uploader.isRunning)
        hold.release()
        await h.uploader.resume()
        // The same account: its job is still all pending, and it goes now.
        #expect(h.uploader.status?.phase == .finished)
        #expect(h.requests.count == 1)
    }

    /// A job stored for one account is never sent for another, even if the wipe missed it.
    @Test func aJobOfAnotherAccountIsNeverSent() async throws {
        let h = H()
        let plan = ImportUploadPlan(sessions: H.sessions(1))
        let payload = try APIClient.jsonEncoder.encode(plan)
        let progress = try JSONEncoder().encode(ImportJobProgress())
        h.persistence.context.insert(PendingImport(account: H.b.uuidString, source: .alphaProgression, createdAt: h.clock.now(),
                                                   timeZoneID: "Europe/Berlin", duplicatesChecked: true, payload: payload,
                                                   progressData: progress, sessionsPerRequest: 50))
        h.persistence.save()
        await h.uploader.resume()
        #expect(h.uploader.status == nil && h.live.calls.isEmpty)
        // And a flow started as B can't store a job while A is signed in.
        #expect(!(await h.start(plan, account: H.b.uuidString)))
    }

    /// Sign-out wipes the job with the store.
    @Test func signOutWipesTheJob() async throws {
        let h = H(online: false)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        #expect(h.jobs().count == 1)
        await h.auth.signOut()
        h.uploader.accountChanged()
        #expect(h.jobs().isEmpty)
        #expect(h.uploader.status == nil && h.uploader.currentAccount == nil)
    }

    @Test func aSecondImportWaitsForTheFirst() async throws {
        let h = H(online: false)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        #expect(h.uploader.hasUnfinishedJob)
        #expect(!(await h.start(ImportUploadPlan(sessions: H.sessions(1, from: 3)))))
        #expect(h.jobs().count == 1)
        h.connectivity.update(true)
        #expect(await eventually { h.uploader.status?.phase == .finished })
        // Finished: a new import replaces it.
        #expect(await h.start(ImportUploadPlan(sessions: H.sessions(1, from: 3))))
        #expect(h.jobs().count == 1)
    }
}

@Suite("Import upload: the job's life")
@MainActor
struct TrainImportUploaderJobTests {
    @Test func anUnfinishedJobGoesAfterThirtyDays() async throws {
        let h = H(online: false)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        h.clock.advance(by: .seconds(30 * 86_400 - 1))
        await h.uploader.appBecameActive()
        #expect(h.jobs().count == 1)
        h.clock.advance(by: .seconds(1))
        await h.uploader.appBecameActive()
        #expect(h.jobs().isEmpty && h.uploader.status == nil)
    }

    @Test func aFinishedJobGoesOnceSeenOrAfterSevenDays() async throws {
        let h = H()
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(1))))
        #expect(h.uploader.status?.resultSeen == false)
        await h.uploader.appBecameActive()
        #expect(h.jobs().count == 1) // not seen yet
        h.uploader.markResultSeen()
        #expect(h.uploader.status?.resultSeen == true && h.jobs().count == 1) // the result screen keeps showing it
        await h.uploader.appBecameActive()
        #expect(h.jobs().isEmpty)

        let other = H()
        #expect(await other.run(ImportUploadPlan(sessions: H.sessions(1))))
        other.clock.advance(by: .seconds(7 * 86_400))
        await other.uploader.appBecameActive()
        #expect(other.jobs().isEmpty)
    }

    @Test func discardRemovesItAndSendsNothingMore() async throws {
        let h = H(online: false)
        #expect(await h.run(ImportUploadPlan(sessions: H.sessions(2))))
        h.uploader.discard()
        #expect(h.jobs().isEmpty && h.uploader.status == nil)
        h.connectivity.update(true)
        await h.uploader.resume()
        #expect(h.live.calls.isEmpty)
    }

    /// After an offline preview the uploader checks first: a session that looks like one the user logged is skipped
    /// and listed ("Import these too"); one already on the account isn't sent again.
    @Test func anOfflinePreviewIsCheckedBeforeTheFirstSession() async throws {
        let h = H()
        let sessions = H.sessions(3)
        // The user logged the second one's workout in RYFT that day.
        let logged = TrainSession(id: ImportBuildFixture.id(900), title: "Back", startedAt: sessions[1].startedAt.addingTimeInterval(1_800),
                                  status: .inProgress, exercises: sessions[1].exercises.map { exercise in
                                      SessionExercise(id: UUID(), exerciseId: exercise.exerciseId, position: 0, sets: exercise.sets.map {
                                          SessionSet(id: UUID(), setIndex: $0.setIndex, reps: 5, weightKg: 90, completedAt: $0.completedAt)
                                      })
                                  })
        _ = try await h.live.putSession(logged)
        _ = try await h.live.completeSession(id: logged.id, SessionComplete())
        // The third was imported before.
        _ = try await h.live.importTraining(encoded: APIClient.jsonEncoder.encode(
            TrainImportRequest(source: .alphaProgression, plans: [], sessions: [sessions[2]])))
        let before = h.requests.count
        #expect(await h.run(ImportUploadPlan(sessions: sessions), duplicatesChecked: false))
        #expect(h.requests.dropFirst(before).flatMap(\.sessionIDs) == [sessions[0].id])
        let status = try #require(h.uploader.status)
        #expect(status.duplicatesFound.map(\.id) == [sessions[1].id])
        #expect(status.phase == .finished && status.sessions == ImportItemCounts(total: 2, done: 2))
        #expect(h.jobs().first?.duplicatesChecked == true)
        await h.uploader.importDuplicatesFound()
        #expect(h.requests.last?.sessionIDs == [sessions[1].id])
        #expect(h.uploader.status?.duplicatesFound.isEmpty == true && h.uploader.status?.sessions.done == 3)
    }

    /// What the account already has, read as the preview reads it.
    @Test func checkExistingReadsPlansSessionsAndLoggedWorkouts() async throws {
        let h = H()
        let bundle = try ImportBuildFixture.bundle()
        let decisions = ImportBuildFixture.decisions(account: h.account)
        let query = ImportBuilder.query(for: bundle, decisions: decisions)
        let first = await h.uploader.checkExisting(query)
        #expect(first.checked && first.plans.isEmpty && first.sessionIDs.isEmpty && first.logged.isEmpty)
        // Import it, then ask again: everything exists.
        let build = try ImportBuilder.buildNow(bundle, decisions: decisions, existing: first, now: ImportBuildFixture.now)
        #expect(await h.run(build.uploadPlan(including: build.defaultIncluded)))
        let again = await h.uploader.checkExisting(query)
        #expect(again.checked && Set(again.plans.keys) == Set(query.planIDs) && again.sessionIDs == Set(query.sessionIDs))
        #expect(again.logged.isEmpty)
        let rebuilt = try ImportBuilder.buildNow(bundle, decisions: decisions, existing: again, now: ImportBuildFixture.now)
        #expect(rebuilt.uploadPlan(including: rebuilt.defaultIncluded).sessions.isEmpty)
        #expect(rebuilt.plans.first?.state == .alreadyInRYFT)
        // Offline, or for another account: unchecked.
        h.connectivity.update(false)
        #expect(await h.uploader.checkExisting(query) == .unchecked)
        h.connectivity.update(true)
        let foreign = ImportBuilder.query(for: bundle, decisions: ImportBuildFixture.decisions(account: "someone-else"))
        #expect(await h.uploader.checkExisting(foreign) == .unchecked)
    }
}
