import Foundation
import SwiftData
import Testing
@testable import Ryft

/// The A2 review's uploader findings: the consent gate, sent markers, re-added nights, a row that keeps failing,
/// bounded background work.
@Suite("Activity uploader: consent gate")
@MainActor
struct ActivityUploaderGateTests {
    /// What `OnboardingCoordinator.syncGate` says, scripted.
    final class Gate { var code: APIErrorCode? }

    @Test func withoutConsentNothingIsSent() async throws {
        let h = UploadHarness()
        let gate = Gate()
        gate.code = .consentRequired
        h.uploader.gate = { gate.code }
        let id = try #require(h.save())
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        await h.uploader.flush()
        await h.uploader.flush(userInitiated: true)
        await h.uploader.appBecameActive()
        #expect(h.api.calls.isEmpty)
        #expect(h.uploader.state(of: id) == .pending(.gated))
        #expect(h.uploader.sleepState(day: night.day) == .pending(.gated))
        // Consent given: the next trigger sends both.
        gate.code = nil
        await h.uploader.flush()
        #expect(h.uploader.state(of: id) == .confirmed && h.uploader.sleepState(day: night.day) == .confirmed)
    }

    @Test func theInviteGateHoldsTheQueueToo() async throws {
        let h = UploadHarness()
        h.uploader.gate = { .inviteRequired }
        _ = try #require(h.save())
        await h.uploader.flush(userInitiated: true)
        #expect(h.puts() == 0)
    }

    @Test func consentWithdrawnMidQueueStopsBeforeTheNextItem() async throws {
        let h = UploadHarness()
        let gate = Gate()
        h.uploader.gate = { gate.code }
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        let first = try #require(h.save(minutesAgo: 120))
        let second = try #require(h.save(minutesAgo: 60))
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        gate.code = .consentRequired // withdrawn while the first PUT is out
        hold.release()
        await flush.value
        #expect(h.puts() == 1)
        #expect(h.uploader.state(of: first) == .confirmed) // its answer still counts
        #expect(h.uploader.state(of: second) == .pending(.gated))
    }

    @Test func theGateIsClosedUntilTheAppConnectsIt() async throws {
        let api = MockPlatformAPI()
        let clock = TestClock()
        let env = AppEnvironment.test(api: api, clock: clock)
        let end = clock.now().addingTimeInterval(-3_600)
        let id = try #require(env.activities.save(manual: ActivityDraft(sport: .yoga, start: end.addingTimeInterval(-900),
                                                                         end: end))?.id)
        await env.uploader.flush(userInitiated: true)
        #expect(api.calls.isEmpty && env.uploader.state(of: id) == .pending(.gated))
    }

    @Test func anAccountBeingDeletedHoldsTheQueue() async throws {
        let h = UploadHarness()
        _ = try #require(h.save())
        // `isDeletingAccount` is the auth service's; a deletion that waits on the platform keeps it set.
        let hold = RequestHold()
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let auth = AuthService(client: MockAuthClient(session: .preview()), settings: Settings(defaults: defaults),
                               defaults: defaults, wipeLocalData: { _ in },
                               deleteRemoteAccount: {
                                   await hold.wait()
                                   return AccountDeleted(status: "deleted", authUserDeleted: true)
                               })
        let env = AppEnvironment.test(api: h.api, clock: h.clock, auth: auth)
        env.uploader.gate = { nil } // only the deletion holds it
        let id = try #require(env.activities.save(manual: h.draft())?.id)
        let deletion = Task { await auth.deleteAccount() }
        #expect(await eventually { auth.isDeletingAccount })
        await env.uploader.flush(userInitiated: true)
        #expect(h.api.count("putActivity") == 0 && env.uploader.state(of: id) == .pending(.gated))
        hold.release()
        #expect(await deletion.value)
    }
}

@Suite("Activity uploader: sent markers and re-added nights")
@MainActor
struct ActivityUploaderMarkerTests {
    @Test func aPutCutOffBeforeItsAnswerCountsAsSent() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        let id = try #require(h.save(notes: "Morning loop"))
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        // Persisted before the request goes out (a kill now leaves it there).
        #expect(h.store.snapshot(id: id)?.sentAt != nil)
        h.uploader.stopReplay()
        hold.release()
        await flush.value
        // Deleting it now asks the platform (the PUT may have arrived) instead of deleting locally.
        h.uploader.deleted(id)
        let tombstone = try #require(h.store.snapshot(id: id))
        #expect(tombstone.isTombstone)
        #expect(tombstone.notes.isEmpty) // a DELETE needs only the id (privacy review N3)
        await h.uploader.flush()
        #expect(h.deletes() == 1 && h.store.snapshot(id: id) == nil)
    }

    @Test func aNightCutOffBeforeItsAnswerCountsAsSent() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        h.uploader.accountChanged() // as a kill or a switch drops the answer
        hold.release()
        await flush.value
        h.uploader.sleepDeleted(day: night.day)
        #expect(h.store.manualSleep(onDay: night.day)?.isTombstone == true)
    }

    @Test func aNightAddedAgainWhileItsDeleteIsOutStays() async throws {
        let h = UploadHarness()
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        await h.uploader.flush()
        h.uploader.sleepDeleted(day: night.day)
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        let later = night.bed.addingTimeInterval(1_800)
        h.store.saveSleep(day: night.day, bed: later, wake: night.wake) // added again
        hold.release()
        await flush.value
        await h.uploader.flush()
        let kept = try #require(h.store.manualSleep(onDay: night.day))
        #expect(!kept.isTombstone && kept.bed == later)
        #expect(h.platform.sleepDeletes == [night.day])
        #expect(h.platform.manualSleep(day: night.day) == ManualSleepPut(bed: later, wake: night.wake))
        #expect(!kept.needsUpload)
    }

    @Test(arguments: [
        ErrorCase(APIError.http(404, "not found"), "404 on a PUT: the route isn't there"),
        ErrorCase(APIError.signedOut, "no session: nothing went out"),
        ErrorCase(APIError.notConfigured, "no server: nothing went out"),
        ErrorCase(APIError.http(403, "consent", code: .consentRequired), "a gate refused it"),
        ErrorCase(APIError.http(422, "invalid"), "refused"),
    ])
    func anAnswerThatStoredNothingClearsTheMarker(_ c: ErrorCase) async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = c.error
        await h.uploader.flush()
        #expect(h.store.snapshot(id: id)?.sentAt == nil)
        h.uploader.deleted(id)
        #expect(h.store.snapshot(id: id) == nil) // deleted here, no DELETE
        await h.uploader.flush()
        #expect(h.deletes() == 0)
    }

    @Test(arguments: [
        ErrorCase(APIError.http(503, "busy"), "a server error"),
        ErrorCase(APIError.transport(URLError(.timedOut)), "a timeout"),
        ErrorCase(APIError.http(200, "unreadable"), "a 2xx this build couldn't read"),
    ])
    func anAnswerThatMayHaveStoredItKeepsTheMarker(_ c: ErrorCase) async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        h.api.failNext = c.error
        await h.uploader.flush()
        #expect(h.store.snapshot(id: id)?.sentAt != nil)
        h.uploader.deleted(id)
        #expect(h.store.snapshot(id: id)?.isTombstone == true)
    }

    /// The A2 re-review: an edit, Retry or a night's edit after a cut-off kept "may be on the platform".
    @Test func anEditAfterACutOffKeepsTheMarker() async throws {
        let h = UploadHarness()
        let cut = await Self.cutOffPut(h)
        let id = try #require(cut)
        _ = h.store.update(id, h.draft(notes: "edited offline"))
        h.uploader.deleted(id)
        #expect(h.store.snapshot(id: id)?.isTombstone == true)
        await h.uploader.flush()
        #expect(h.deletes() == 1)
    }

    @Test func aRetryOfflineAfterACutOffKeepsTheMarker() async throws {
        let h = UploadHarness()
        let cut = await Self.cutOffPut(h)
        let id = try #require(cut)
        h.env.connectivityMonitor.update(false)
        await h.uploader.retry(id)
        h.uploader.deleted(id)
        #expect(h.store.snapshot(id: id)?.isTombstone == true)
        h.env.connectivityMonitor.update(true)
        #expect(await eventually { h.deletes() == 1 })
    }

    @Test func aRefusalOfALaterRevisionKeepsTheEarlierMarker() async throws {
        let h = UploadHarness()
        let cut = await Self.cutOffPut(h)
        let id = try #require(cut)
        _ = h.store.update(id, h.draft(notes: "second"))
        h.api.failNext = APIError.http(422, "invalid") // revision 2 refused; revision 1 may still be there
        await h.uploader.flush()
        #expect(h.store.snapshot(id: id)?.sentAt != nil)
        h.uploader.deleted(id)
        #expect(h.store.snapshot(id: id)?.isTombstone == true)
    }

    @Test func aNightsEditAfterACutOffKeepsTheMarker() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        h.uploader.stopReplay()
        hold.release()
        await flush.value
        h.store.saveSleep(day: night.day, bed: night.bed.addingTimeInterval(600), wake: night.wake)
        h.uploader.sleepDeleted(day: night.day)
        #expect(h.store.manualSleep(onDay: night.day)?.isTombstone == true)
        h.platform.beforeWrite = nil
        await h.uploader.flush()
        #expect(h.api.count("deleteManualSleep") == 1)
    }

    /// A PUT that went out and was cut off by the background task's expiry (no answer).
    private static func cutOffPut(_ h: UploadHarness) async -> UUID? {
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        let id = h.save()
        let flush = Task { await h.uploader.flush() }
        #expect(await eventually { hold.waiting == 1 })
        h.uploader.stopReplay()
        hold.release()
        await flush.value
        h.platform.beforeWrite = nil
        #expect(id.flatMap { h.store.snapshot(id: $0)?.sentAt } != nil)
        return id
    }
}

/// An error and what it stands for, for parameterised tests.
struct ErrorCase: CustomTestStringConvertible, @unchecked Sendable {
    let error: Error
    let testDescription: String

    init(_ error: Error, _ description: String) {
        self.error = error
        testDescription = description
    }
}

@Suite("Activity uploader: one failing row doesn't hold up the rest")
@MainActor
struct ActivityUploaderQueueTests {
    @Test func aRowBackingOffIsPassedOverByTheNextTrigger() async throws {
        let h = UploadHarness()
        let failing = try #require(h.save(minutesAgo: 120))
        let other = try #require(h.save(minutesAgo: 60))
        h.platform.failingPuts = [failing: APIError.http(503, "busy")]
        await h.uploader.flush()
        // The first failure stops the pass (most likely the platform as a whole)…
        #expect(h.store.snapshot(id: other)?.confirmedRevision == 0)
        // …but the next trigger sends the other row while the failing one waits for its backoff.
        await h.uploader.flush()
        #expect(h.store.snapshot(id: other)?.confirmedRevision == 1)
        #expect(h.uploader.state(of: failing) == .pending(.retrying(at: h.clock.now().addingTimeInterval(30))))
    }

    @Test func afterThreeFailuresInARowTheRestGoOnInTheSamePass() async throws {
        let h = UploadHarness()
        let failing = try #require(h.save(minutesAgo: 120))
        h.platform.failingPuts = [failing: APIError.http(503, "busy")]
        await h.uploader.flush()
        #expect(await eventually { h.clock.pendingSleeps == 1 })
        h.clock.advance(by: .seconds(30))
        let second = h.clock.now().addingTimeInterval(120)
        #expect(await eventually { h.uploader.retryAt == second })
        // A row saved without a trigger of its own: only the retry's pass can send it.
        let waiting = try #require(h.save(minutesAgo: 60))
        #expect(await eventually { h.clock.pendingSleeps == 1 })
        h.clock.advance(by: .seconds(120))
        #expect(await eventually { h.store.snapshot(id: waiting)?.confirmedRevision == 1 })
        #expect(h.uploader.backoffs[.activity(failing)]?.failures == 3)
        guard case .failed = h.uploader.state(of: failing) else {
            Issue.record("three failures in a row show failed")
            return
        }
    }

    @Test func twoFailingRowsBackOffEachOnItsOwnClock() async throws {
        let h = UploadHarness()
        let a = try #require(h.save(minutesAgo: 120))
        h.platform.failingPuts = [a: APIError.http(503, "busy")]
        await h.uploader.flush()
        h.clock.advance(by: .seconds(10))
        let b = try #require(h.save(minutesAgo: 60))
        h.platform.failingPuts = [a: APIError.http(503, "busy"), b: APIError.http(503, "busy")]
        await h.uploader.flush()
        #expect(h.uploader.backoffs[.activity(a)]?.due == h.clock.now().addingTimeInterval(20))
        #expect(h.uploader.backoffs[.activity(b)]?.due == h.clock.now().addingTimeInterval(30))
        #expect(h.uploader.retryAt == h.clock.now().addingTimeInterval(20)) // the earliest
    }
}

@Suite("Activity uploader: bounded background work")
@MainActor
struct ActivityUploaderBackgroundTests {
    @Test func theBackgroundRefreshWaitsTwentySecondsAtMostAndTheExpiryStopsTheReplay() async throws {
        let h = UploadHarness()
        let hold = RequestHold()
        h.platform.beforeWrite = { await hold.wait() }
        let id = try #require(h.save())
        let refresh = Task { await h.uploader.flush(upTo: ActivityUploader.backgroundLimit, userInitiated: false) }
        #expect(await eventually { hold.waiting == 1 && h.clock.pendingSleeps == 1 })
        h.clock.advance(by: .seconds(20))
        #expect(await refresh.value == 1)
        h.uploader.stopReplay() // the task's expiry
        hold.release()
        #expect(await eventually { h.uploader.inFlight == nil })
        let row = try #require(h.store.snapshot(id: id))
        #expect(row.confirmedRevision == 0 && h.uploader.state(of: id) == .pending(.queued))
        #expect(ActivityUploader.backgroundLimit == .seconds(20))
    }

    @Test func theBackgroundRefreshRespectsABackoff() async throws {
        let h = UploadHarness()
        _ = try #require(h.save())
        h.api.failNext = APIError.http(503, "busy")
        await h.uploader.flush()
        #expect(await h.uploader.flush(upTo: ActivityUploader.backgroundLimit, userInitiated: false) == 1)
        #expect(h.puts() == 1)
    }
}

@Suite("Activities: where a confirmed activity was cached")
@MainActor
struct CachedActivityDayTests {
    private static func activity(_ id: UUID, on day: Date) -> SportActivity {
        SportActivity(id: id, sport: .running, origin: .manual, start: day, end: day.addingTimeInterval(600),
                      movingSec: 600, clientUpdatedAt: day)
    }

    @Test func theNewDaysListFirstThenOnlyTheStrip() {
        let env = AppEnvironment.test()
        let repository = AppState(env: env).repository
        let now = env.clock.now()
        let id = UUID()
        let today = DayFormat.string(from: now)
        let twoDaysAgo = DayFormat.shift(now, days: -2)
        let monthAgo = DayFormat.shift(now, days: -30)
        // On the new day's list already: that day.
        repository.store(activities: [Self.activity(id, on: now)], day: today)
        #expect(repository.cachedDay(ofActivity: id, startingOn: today) == today)
        // Moved from two days ago (in the strip): found there.
        let moved = UUID()
        repository.store(activities: [Self.activity(moved, on: twoDaysAgo)], day: DayFormat.string(from: twoDaysAgo))
        #expect(repository.cachedDay(ofActivity: moved, startingOn: today) == DayFormat.string(from: twoDaysAgo))
        // Cached a month ago: outside the strip, not searched.
        let old = UUID()
        repository.store(activities: [Self.activity(old, on: monthAgo)], day: DayFormat.string(from: monthAgo))
        #expect(repository.cachedDay(ofActivity: old, startingOn: today) == nil)
        #expect(repository.cachedDay(ofActivity: UUID(), startingOn: nil) == nil)
    }
}
