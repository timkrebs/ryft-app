import Foundation
import SwiftData
import Testing
@testable import Ryft

/// The upload queue (design.md §4.1, §11.1 → Uploader) against the fake platform on the test clock.
@Suite("Activity uploader: idempotency and confirmation")
@MainActor
struct ActivityUploaderIdempotencyTests {
    @Test func twoFlushesOfOneRevisionSendOnePut() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        await h.uploader.flush()
        await h.uploader.flush()
        #expect(h.puts() == 1)
        #expect(h.platform.puts.map(\.id) == [id])
        let row = try #require(h.store.snapshot(id: id))
        #expect(row.confirmedRevision == 1 && !row.needsUpload)
        #expect(h.uploader.state(of: id) == .confirmed)
        #expect(h.uploader.pendingCount == 0)
    }

    @Test func anEditWhileThePutIsOutSendsASecondPut() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        let id = try #require(h.save(notes: "first"))
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        #expect(h.uploader.state(of: id) == .pending(.inFlight))
        _ = h.store.update(id, h.draft(notes: "second"))
        hold.release()
        await flush.value
        await h.uploader.flush()
        #expect(h.platform.puts.map(\.notes) == ["first", "second"])
        let row = try #require(h.store.snapshot(id: id))
        #expect(row.localRevision == 2 && row.confirmedRevision == 2)
    }

    @Test func aRetryAfterATimeoutReusesTheID() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = APIError.transport(URLError(.timedOut))
        await h.uploader.flush()
        #expect(h.puts() == 1 && h.platform.puts.isEmpty)
        #expect(h.uploader.state(of: id) == .pending(.retrying(at: h.clock.now().addingTimeInterval(30))))
        #expect(await eventually { h.clock.pendingSleeps == 1 }) // the retry is waiting on the clock
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { h.store.snapshot(id: id)?.confirmedRevision == 1 })
        #expect(h.puts() == 2)
        #expect(h.platform.puts.map(\.id) == [id]) // the same document, once stored
    }

    @Test func confirmationSetsTheRevisionAndReportsTheDays() async throws {
        let h = UploadHarness()
        var confirmed: [(SportActivity, [String])] = []
        h.uploader.onConfirmed = { confirmed.append(($0, $1)) }
        let id = try #require(h.save())
        await h.uploader.flush()
        #expect(confirmed.count == 1)
        #expect(confirmed.first?.0.id == id && confirmed.first?.0.scoringState == "pending")
        #expect(confirmed.first?.1 == [h.today])
        #expect(h.store.snapshot(id: id)?.lastAttempt == nil)
    }

    @Test func theQueueSendsInCreationOrderThenNights() async throws {
        let h = UploadHarness()
        let later = try #require(h.save(minutesAgo: 60))          // created first, starts later
        let earlier = try #require(h.save(minutesAgo: 300))       // created second, starts earlier
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        await h.uploader.flush()
        #expect(h.platform.puts.map(\.id) == [later, earlier])
        let order = h.api.calls.filter { $0 == "putActivity" || $0 == "putManualSleep" }
        #expect(order == ["putActivity", "putActivity", "putManualSleep"])
    }

    @Test func savedStartsTheQueue() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.uploader.saved(id)
        #expect(await eventually { h.store.snapshot(id: id)?.confirmedRevision == 1 })
        #expect(h.puts() == 1)
    }

    @Test func pendingCountCountsActivitiesAndNights() throws {
        let h = UploadHarness()
        _ = try #require(h.save())
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        #expect(h.uploader.pendingCount == 2)
    }
}

@Suite("Activity uploader: errors and retries")
@MainActor
struct ActivityUploaderErrorTests {
    @Test func transientFailuresBackOffOnTheClockUpToAnHour() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failure = APIError.http(503, "busy", requestID: "req-503")
        await h.uploader.flush()
        // 30 s, 2 min, 10 min, then 1 h, and 1 h again: the cap.
        for (attempt, wait) in [30, 120, 600, 3_600, 3_600].enumerated() {
            let due = h.clock.now().addingTimeInterval(TimeInterval(wait))
            #expect(await eventually { h.uploader.retryAt == due })
            #expect(h.puts() == attempt + 1)
            #expect(await eventually { h.clock.pendingSleeps == 1 }) // the retry is waiting on the clock
            h.clock.advance(by: .seconds(wait - 1))
            await h.uploader.flush() // not due yet: nothing is sent
            #expect(h.puts() == attempt + 1)
            h.clock.advance(by: .seconds(1))
            #expect(await eventually { h.puts() == attempt + 2 })
        }
        #expect(h.store.snapshot(id: id)?.needsUpload == true) // never lost
    }

    @Test func threeTransientFailuresInARowShowFailedAndAttemptsGoOn() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failure = APIError.http(502, "bad gateway", requestID: "req-502")
        await h.uploader.flush()
        #expect(h.uploader.state(of: id) == .pending(.retrying(at: h.clock.now().addingTimeInterval(30))))
        #expect(await eventually { h.clock.pendingSleeps == 1 }) // the retry is waiting on the clock
        h.clock.advance(by: .seconds(30))
        let second = h.clock.now().addingTimeInterval(120)
        #expect(await eventually { h.uploader.retryAt == second })
        #expect(h.uploader.state(of: id) == .pending(.retrying(at: second))) // two are not yet failed
        #expect(await eventually { h.clock.pendingSleeps == 1 }) // the retry is waiting on the clock
        h.clock.advance(by: .seconds(120))
        let third = h.clock.now().addingTimeInterval(600)
        #expect(await eventually { h.uploader.retryAt == third })
        let attempt = try #require(h.store.snapshot(id: id)?.lastAttempt)
        #expect(attempt.status == 502 && attempt.requestID == "req-502" && attempt.kind == .transient)
        #expect(h.uploader.state(of: id) == .failed(attempt))
        #expect(h.puts() == 3)
        // Still retried at the backoff's pace.
        h.api.failure = nil
        #expect(await eventually { h.clock.pendingSleeps == 1 }) // the retry is waiting on the clock
        h.clock.advance(by: .seconds(600))
        #expect(await eventually { h.uploader.state(of: id) == .confirmed })
    }

    @Test func theJitterAddsUpToAFifthOfTheStep() async throws {
        let h = UploadHarness()
        h.uploader.random = { $0.upperBound }
        _ = try #require(h.save())
        h.api.failNext = APIError.http(500, "oops")
        await h.uploader.flush()
        #expect(h.uploader.retryAt == h.clock.now().addingTimeInterval(36))
    }

    @Test func retryAfterIsHonoured() async throws {
        let h = UploadHarness()
        _ = try #require(h.save())
        h.api.failNext = APIError.http(429, "slow down", retryAfter: 90)
        await h.uploader.flush()
        #expect(h.uploader.retryAt == h.clock.now().addingTimeInterval(90))
        #expect(await eventually { h.clock.pendingSleeps == 1 }) // the retry is waiting on the clock
        h.clock.advance(by: .seconds(90))
        #expect(await eventually { h.puts() == 2 })
    }

    @Test func aShortRetryAfterKeepsTheBackoff() async throws {
        let h = UploadHarness()
        _ = try #require(h.save())
        h.api.failNext = APIError.http(503, "busy", retryAfter: 5)
        await h.uploader.flush()
        #expect(h.uploader.retryAt == h.clock.now().addingTimeInterval(30))
    }

    @Test func aRefusalIsFailedKeptAndNotResent() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = APIError.http(422, "end in the future", requestID: "req-422")
        await h.uploader.flush()
        let attempt = try #require(h.store.snapshot(id: id)?.lastAttempt)
        #expect(attempt.status == 422 && attempt.requestID == "req-422" && attempt.request == .put && attempt.kind == .other)
        #expect(h.uploader.state(of: id) == .failed(attempt))
        #expect(h.uploader.retryAt == nil) // no automatic retry
        await h.uploader.flush()
        #expect(h.puts() == 1)
        #expect(h.store.snapshot(id: id)?.needsUpload == true)
        // Retry sends it again.
        await h.uploader.retry(id)
        #expect(h.puts() == 2 && h.uploader.state(of: id) == .confirmed)
    }

    @Test func aRefusedRowDoesNotHoldUpTheRest() async throws {
        let h = UploadHarness()
        let refused = try #require(h.save(minutesAgo: 120))
        let next = try #require(h.save(minutesAgo: 60))
        h.api.failNext = APIError.http(400, "bad")
        await h.uploader.flush()
        #expect(h.store.snapshot(id: next)?.confirmedRevision == 1)
        #expect(h.store.snapshot(id: refused)?.confirmedRevision == 0)
    }

    @Test func anEditClearsTheRefusal() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = APIError.http(422, "invalid")
        await h.uploader.flush()
        _ = h.store.update(id, h.draft(notes: "fixed"))
        #expect(h.store.snapshot(id: id)?.lastAttempt == nil)
        await h.uploader.flush()
        #expect(h.platform.puts.map(\.notes) == ["fixed"])
        #expect(h.uploader.state(of: id) == .confirmed)
    }

    @Test func aRefusalOfAnOlderRevisionLeavesTheNewerOneQueued() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        // Ends in the future: the platform refuses this revision (422) when it arrives.
        let id = try #require(h.save(minutesAgo: -30))
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        _ = h.store.update(id, h.draft(notes: "fixed"))
        hold.release()
        await flush.value
        // The refusal belonged to revision 1: revision 2 went up in the same replay.
        #expect(h.platform.puts.map(\.notes) == ["fixed"])
        let row = try #require(h.store.snapshot(id: id))
        #expect(row.confirmedRevision == 2 && row.lastAttempt == nil)
    }

    @Test func aGateHoldsTheQueueUntilItsPassed() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = APIError.http(403, "consent required", code: .consentRequired)
        await h.uploader.flush()
        #expect(h.uploader.state(of: id) == .pending(.gated))
        #expect(h.uploader.retryAt == nil)
        await h.uploader.flush() // the gate was passed
        #expect(h.uploader.state(of: id) == .confirmed && h.puts() == 2)
    }

    @Test func a404OnPutIsNotAvailableYetUntilTheAppIsActive() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = APIError.http(404, "not found")
        await h.uploader.flush()
        #expect(h.uploader.state(of: id) == .pending(.notAvailableYet))
        await h.uploader.flush()
        #expect(h.puts() == 1)
        await h.uploader.appBecameActive()
        #expect(h.puts() == 2 && h.uploader.state(of: id) == .confirmed)
    }

    @Test func aCancelledRequestIsNeverARefusalNorAFailure() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = CancellationError()
        await h.uploader.flush()
        // Marked as possibly sent, not counted: no attempt recorded, no backoff, not failed.
        #expect(h.store.snapshot(id: id)?.sentAt != nil && h.store.snapshot(id: id)?.lastAttempt == nil)
        #expect(h.uploader.backoffs.isEmpty && h.uploader.state(of: id) == .pending(.queued))
        await h.uploader.flush()
        #expect(h.uploader.state(of: id) == .confirmed)
        #expect(h.store.snapshot(id: id)?.sentAt == nil) // a full confirmation clears it
    }
}

@Suite("Activity uploader: offline, contract, account")
@MainActor
struct ActivityUploaderScopeTests {
    @Test func offlineNothingIsSentAndReconnectSends() async throws {
        let h = UploadHarness(online: false)
        let id = try #require(h.save())
        await h.uploader.flush()
        #expect(h.puts() == 0)
        #expect(h.uploader.state(of: id) == .pending(.offline))
        h.env.connectivityMonitor.update(true)
        #expect(await eventually { h.store.snapshot(id: id)?.confirmedRevision == 1 })
    }

    @Test func aLostConnectionRetriesOnReconnectWithoutWaiting() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = APIError.transport(URLError(.notConnectedToInternet))
        await h.uploader.flush()
        #expect(h.uploader.retryAt != nil)
        h.env.connectivityMonitor.update(false)
        h.env.connectivityMonitor.update(true)
        #expect(await eventually { h.store.snapshot(id: id)?.confirmedRevision == 1 })
    }

    @Test func beforeTheContractNothingIsSent() async throws {
        let h = UploadHarness()
        h.platform.publishesActivities = false
        let id = try #require(h.save())
        await h.uploader.flush()
        await h.uploader.flush(userInitiated: true)
        await h.uploader.appBecameActive()
        #expect(h.puts() == 0 && h.api.calls.isEmpty)
        #expect(h.uploader.state(of: id) == .pending(.notAvailableYet))
        // The live client is the stub until C1.
        #expect(APIClient.shared.publishesActivities == false)
        // The contract arrives: the next active app sends.
        h.platform.publishesActivities = true
        await h.uploader.appBecameActive()
        #expect(h.uploader.state(of: id) == .confirmed)
    }

    @Test func signedOutNothingIsSent() async {
        let h = UploadHarness(signedIn: false)
        h.insertForeign()
        await h.uploader.flush(userInitiated: true)
        #expect(h.api.calls.isEmpty)
        #expect(h.uploader.pendingCount == 0)
    }

    @Test func onlyTheSignedInAccountsRowsAreSent() async throws {
        let h = UploadHarness()
        let foreign = h.insertForeign()
        let own = try #require(h.save())
        await h.uploader.flush()
        #expect(h.platform.puts.map(\.id) == [own])
        let raw = try h.env.persistence.context.fetch(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.id == foreign }))
        #expect(raw.first?.confirmedRevision == 0) // untouched
    }

    @Test func anAnswerAfterAnAccountChangeIsDropped() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        var confirmed = 0
        h.uploader.onConfirmed = { _, _ in confirmed += 1 }
        let id = try #require(h.save())
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        h.uploader.accountChanged()
        hold.release()
        await flush.value
        #expect(h.store.snapshot(id: id)?.confirmedRevision == 0)
        #expect(confirmed == 0)
        #expect(h.uploader.inFlight == nil)
    }

    @Test func aDemoRowNeverGoesThroughTheLiveClient() async throws {
        let clock = TestClock()
        let live = MockPlatformAPI(), demo = MockPlatformAPI()
        live.now = { clock.now() }
        demo.now = { clock.now() }
        let defaults = try #require(UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)"))
        let settings = Settings(defaults: defaults)
        let env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: live, demoAPI: demo,
                                 auth: .preview(), persistence: TrainStore(inMemory: true), clock: clock,
                                 notifier: MockNotifier(), flags: StaticFlags([:]), connectivity: .preview(online: true),
                                 defaults: defaults)
        env.uploader.gate = { _ in nil }
        let end = clock.now().addingTimeInterval(-3_600)
        // The account's own row, saved before demo data goes on.
        settings.demoMode = false
        let liveRow = try #require(env.activities.save(manual: ActivityDraft(sport: .walking, start: end.addingTimeInterval(-1_800),
                                                                              end: end))?.id)
        settings.demoMode = true
        let hold = RequestHold()
        demo.activitySource.beforeWrite = { await hold.wait() }
        let demoRow = try #require(env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-1_800),
                                                                              end: end))?.id)
        #expect(env.activities.account == ActivityStore.demoAccount)
        let flush = Task { await env.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        // Demo data goes off while the demo PUT is out: its answer belongs to another generation.
        settings.demoMode = false
        hold.release()
        await flush.value
        await env.uploader.flush()
        // The live client got the account's row and only it; the demo client only the demo row.
        #expect(live.activitySource.puts.map(\.id) == [liveRow])
        #expect(demo.activitySource.puts.map(\.id) == [demoRow])
        #expect(env.activities.snapshot(id: liveRow)?.confirmedRevision == 1)
        settings.demoMode = true
        #expect(env.activities.snapshot(id: demoRow)?.confirmedRevision == 0) // the dropped answer confirmed nothing
    }

    @Test func aSecondFlushWhileARequestIsOutSendsNoSecondRequest() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        _ = try #require(h.save(minutesAgo: 120))
        _ = try #require(h.save(minutesAgo: 60))
        let first = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        let second = Task { await h.uploader.flush() }
        let third = Task { await h.uploader.flush(userInitiated: true) }
        try? await Task.sleep(for: .milliseconds(50)) // a negative check: nothing more may start meanwhile
        #expect(hold.waiting == 1 && h.puts() == 1)
        hold.release()
        await first.value
        await second.value
        await third.value
        #expect(h.puts() == 2 && h.uploader.pendingCount == 0)
    }
}

@Suite("Activity uploader: deletes and nights")
@MainActor
struct ActivityUploaderDeleteTests {
    @Test func aRowNeverUploadedIsDeletedLocally() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.uploader.deleted(id)
        #expect(h.store.snapshot(id: id) == nil)
        await h.uploader.flush()
        #expect(h.api.calls.isEmpty)
    }

    @Test func aRowTheContractNeverTookIsDeletedLocally() async throws {
        let h = UploadHarness()
        h.platform.publishesActivities = false
        let id = try #require(h.save())
        await h.uploader.flush()
        h.uploader.deleted(id)
        #expect(h.store.snapshot(id: id) == nil && h.api.calls.isEmpty)
    }

    @Test func aRefusedRowIsDeletedLocally() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = APIError.http(422, "invalid")
        await h.uploader.flush()
        h.uploader.deleted(id)
        #expect(h.store.snapshot(id: id) == nil)
        #expect(h.deletes() == 0)
    }

    @Test func aRowWhoseFirstPutTimedOutIsDeletedOnThePlatform() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = APIError.transport(URLError(.timedOut)) // it may have arrived
        await h.uploader.flush()
        h.uploader.deleted(id)
        #expect(h.store.snapshot(id: id)?.isTombstone == true)
        await h.uploader.flush(userInitiated: true)
        #expect(h.deletes() == 1)
        #expect(h.store.snapshot(id: id) == nil) // a 404 there means gone
    }

    @Test func anUploadedRowIsDeletedThenRemoved() async throws {
        let h = UploadHarness()
        var removed: [(UUID, [String])] = []
        h.uploader.onRemoved = { removed.append(($0, $1)) }
        let id = try #require(h.save())
        await h.uploader.flush()
        h.uploader.deleted(id)
        let tombstone = try #require(h.store.snapshot(id: id))
        #expect(tombstone.isTombstone && h.uploader.state(of: id) != .confirmed)
        await h.uploader.flush()
        #expect(h.platform.deletes == [id])
        #expect(h.store.snapshot(id: id) == nil)
        #expect(removed.map(\.0) == [id] && removed.first?.1 == [h.today])
    }

    @Test func aDeleteThatFailsKeepsTheTombstone() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        await h.uploader.flush()
        h.uploader.deleted(id)
        h.api.failNext = APIError.http(503, "busy")
        await h.uploader.flush()
        #expect(h.store.snapshot(id: id)?.isTombstone == true)
        #expect(h.store.snapshot(id: id)?.lastAttempt?.request == .delete)
    }

    @Test func aDeleteWhileThePutIsOutFollowsIt() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        var confirmed = 0
        h.uploader.onConfirmed = { _, _ in confirmed += 1 }
        let id = try #require(h.save())
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        h.uploader.deleted(id) // the PUT may land: keep a tombstone
        #expect(h.store.snapshot(id: id)?.isTombstone == true)
        hold.release()
        await flush.value
        await h.uploader.flush()
        #expect(h.platform.deletes == [id] && h.store.snapshot(id: id) == nil)
        #expect(confirmed == 0) // nothing to show for a deleted row
    }

    @Test func aNightIsPutConfirmedAndKept() async throws {
        let h = UploadHarness()
        var days: [String] = []
        h.uploader.onSleepConfirmed = { days.append($0) }
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        #expect(h.uploader.sleepState(day: night.day) == .pending(.queued))
        await h.uploader.flush()
        #expect(h.platform.sleepPuts[night.day] == ManualSleepPut(bed: night.bed, wake: night.wake))
        #expect(h.store.manualSleep(onDay: night.day)?.confirmedRevision == 1)
        #expect(h.uploader.sleepState(day: night.day) == .confirmed)
        #expect(days == [night.day])
        // An edit is one more PUT of the same day.
        h.store.saveSleep(day: night.day, bed: night.bed.addingTimeInterval(1_800), wake: night.wake)
        await h.uploader.flush()
        #expect(h.api.count("putManualSleep") == 2 && h.store.manualSleep(onDay: night.day)?.confirmedRevision == 2)
    }

    @Test func aNightIsDeletedOnThePlatformOrLocally() async throws {
        let h = UploadHarness()
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        h.uploader.sleepDeleted(day: night.day) // never sent
        #expect(h.store.manualSleep(onDay: night.day) == nil && h.api.calls.isEmpty)
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        await h.uploader.flush()
        h.uploader.sleepDeleted(day: night.day)
        #expect(h.store.manualSleep(onDay: night.day)?.isTombstone == true)
        await h.uploader.flush()
        #expect(h.platform.sleepDeletes == [night.day] && h.store.manualSleep(onDay: night.day) == nil)
    }

    @Test func aRefusedNightIsFailedUntilRetried() async throws {
        let h = UploadHarness()
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        h.api.failNext = APIError.http(422, "too long", requestID: "req-sleep")
        await h.uploader.flush()
        let attempt = try #require(h.store.manualSleep(onDay: night.day)?.lastAttempt)
        #expect(attempt.requestID == "req-sleep" && h.uploader.sleepState(day: night.day) == .failed(attempt))
        await h.uploader.retrySleep(day: night.day)
        #expect(h.uploader.sleepState(day: night.day) == .confirmed)
    }
}

@Suite("Activity uploader: background and Send first")
@MainActor
struct ActivityUploaderLifecycleTests {
    @Test func theRequestInFlightFinishesInABackgroundTask() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        let id = try #require(h.save())
        let app = FakeBackgroundApp()
        #expect(h.uploader.finishInBackground(app: app) == nil) // nothing running
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        let finishing = try #require(h.uploader.finishInBackground(app: app))
        #expect(app.begun == 1 && app.ended.isEmpty)
        hold.release()
        await finishing.value
        await flush.value
        #expect(app.ended.count == 1)
        #expect(h.store.snapshot(id: id)?.confirmedRevision == 1)
    }

    @Test func theSystemsTimeRunningOutCancelsAndKeepsTheRow() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        let id = try #require(h.save())
        let app = FakeBackgroundApp()
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        let finishing = try #require(h.uploader.finishInBackground(app: app))
        app.expiry?()
        hold.release()
        await finishing.value
        await flush.value
        #expect(app.ended.count == 1) // once, though both the expiry and the replay ended it
        let row = try #require(h.store.snapshot(id: id))
        // Queued, not refused, not counted; and marked as possibly sent: a delete now goes to the platform.
        #expect(row.confirmedRevision == 0 && row.sentAt != nil && row.lastAttempt == nil)
        #expect(h.uploader.state(of: id) == .pending(.queued) && h.uploader.backoffs.isEmpty)
        h.platform.beforeWrite = nil
        await h.uploader.flush()
        #expect(h.store.snapshot(id: id)?.confirmedRevision == 1)
    }

    @Test func sendFirstWaitsTenSecondsAtMost() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        _ = try #require(h.save())
        let send = Task { await h.uploader.flush(upTo: ActivityUploader.sendFirstLimit) }
        #expect(await eventually { hold.waiting == 1 && h.clock.pendingSleeps == 1 })
        h.clock.advance(by: .seconds(9))
        #expect(h.clock.pendingSleeps == 1)
        h.clock.advance(by: .seconds(1))
        #expect(await send.value == 1) // still unconfirmed; the upload goes on
        hold.release()
        #expect(await eventually { h.uploader.pendingCount == 0 })
    }

    @Test func sendFirstReturnsAtOnceWhenEverythingArrived() async throws {
        let h = UploadHarness()
        _ = try #require(h.save())
        #expect(await h.uploader.flush(upTo: ActivityUploader.sendFirstLimit) == 0)
    }
}

@Suite("Activity uploader: unknown values (code nit 7)")
@MainActor
struct ActivityUploaderUnknownValueTests {
    private static func platformCopy(sport: String, origin: String, end: Date) throws -> SportActivity {
        let json = """
        {"id": "6f1c2a9e-3b7d-4c8e-9a1f-2d4e6b8c0a12", "sport": "\(sport)", "origin": "\(origin)",
         "start": "\(end.addingTimeInterval(-3_600).ISO8601Format())", "end": "\(end.ISO8601Format())",
         "moving_sec": 3600, "notes": "Windy", "client_updated_at": "\(end.ISO8601Format())", "scoring_state": "scored"}
        """
        return try APIClient.jsonDecoder.decode(SportActivity.self, from: Data(json.utf8))
    }

    @Test func anUnknownSportGoesBackAsItCameOnAnEdit() async throws {
        let h = UploadHarness()
        let copy = try Self.platformCopy(sport: "kitesurfing", origin: "manual", end: h.clock.now().addingTimeInterval(-3_600))
        #expect(copy.sport == .other && copy.unknownSport == "kitesurfing" && copy.isEditable)
        let adopted = try #require(h.store.adopt(copy))
        #expect(adopted.confirmedRevision == 1 && !adopted.needsUpload && adopted.unknownSport == "kitesurfing")
        // The edit form shows Other; keeping it keeps the platform's sport.
        let draft = ActivityDraft(sport: .other, start: copy.start, end: copy.end, notes: "Gusty")
        _ = h.store.update(copy.id, draft)
        await h.uploader.flush()
        let body = try APIClient.jsonEncoder.encode(SportActivityPut(try #require(h.store.snapshot(id: copy.id)).activity))
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["sport"] as? String == "kitesurfing")
        #expect(h.platform.puts.first?.unknownSport == "kitesurfing" && h.platform.puts.first?.notes == "Gusty")
    }

    @Test func choosingASportReplacesTheUnknownOne() throws {
        let h = UploadHarness()
        var copy = try Self.platformCopy(sport: "kitesurfing", origin: "manual", end: h.clock.now().addingTimeInterval(-3_600))
        copy.sport = .swimming
        #expect(copy.unknownSport == nil)
        _ = try #require(h.store.adopt(try Self.platformCopy(sport: "kitesurfing", origin: "manual",
                                                              end: h.clock.now().addingTimeInterval(-3_600))))
        let edited = h.store.update(copy.id, ActivityDraft(sport: .swimming, start: copy.start, end: copy.end))
        #expect(edited?.sport == .swimming && edited?.unknownSport == nil)
    }

    @Test func anUnknownOriginIsReadOnly() throws {
        let h = UploadHarness()
        let copy = try Self.platformCopy(sport: "running", origin: "imported", end: h.clock.now().addingTimeInterval(-3_600))
        #expect(!copy.isEditable && copy.unknownOrigin == "imported")
        #expect(h.store.adopt(copy) == nil)
        let input = MyDayInput(day: DayFormat.string(from: copy.start), server: .dayDetail(nil, activities: [copy]))
        let item = try #require(MyDayAssembler.items(input, catalog: .bundled, now: h.clock.now()).first)
        #expect(!item.editable)
        // The cache keeps what the platform said.
        let cached = try APIClient.jsonDecoder.decode(SportActivity.self, from: APIClient.jsonEncoder.encode(copy))
        #expect(cached.unknownOrigin == "imported" && cached == copy)
    }

    @Test func adoptKeepsAnotherAccountsRowAndAnExistingOne() throws {
        let h = UploadHarness()
        let foreign = h.insertForeign()
        let copy = try Self.platformCopy(sport: "running", origin: "manual", end: h.clock.now().addingTimeInterval(-3_600))
        let stolen = SportActivity(id: foreign, sport: .running, origin: .manual, start: copy.start, end: copy.end,
                                   movingSec: 3_600, clientUpdatedAt: copy.clientUpdatedAt)
        #expect(h.store.adopt(stolen) == nil)
        let own = try #require(h.save())
        let existing = try #require(h.store.snapshot(id: own))
        let again = SportActivity(id: own, sport: .walking, origin: .manual, start: existing.start,
                                  end: existing.end ?? existing.start, movingSec: 60, clientUpdatedAt: h.clock.now())
        #expect(h.store.adopt(again) == existing) // the row on this iPhone wins
    }
}
