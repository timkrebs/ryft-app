import Foundation
import Testing
import UIKit
import UserNotifications
@testable import Ryft

/// Records every stage with the clock's time; each stage can be slowed down on
/// the clock or made to fail.
@MainActor
private final class FakeSteps: SyncSteps {
    let clock: TestClock
    var touched: [String] = ["2026-10-19"]
    /// Upload failures, one per attempt, before it succeeds.
    var uploadFailures: [Error] = []
    /// Per ask of `GET /v1/me/sync`: whether scoring has finished the touched days.
    var scored: [Bool] = [true]
    var uploadDuration: Duration = .zero
    /// Backlog after each upload, in order (then none).
    var backlogs: [Bool] = []
    private(set) var hasBacklog = false
    /// The next upload finds HealthKit locked.
    var locked = false
    private(set) var isWaitingForUnlock = false
    private(set) var isUploading = false
    private(set) var stopRequests = 0
    /// `APIClient.runsInBackground` during each upload.
    private(set) var backgroundUploads: [Bool] = []
    private(set) var events: [String] = []
    private var stopRequested = false

    init(clock: TestClock) { self.clock = clock }

    func upload() async throws -> [String] {
        events.append("upload")
        backgroundUploads.append(APIClient.runsInBackground)
        isUploading = true
        stopRequested = false
        defer { isUploading = false }
        if uploadDuration > .zero { try await clock.sleep(for: uploadDuration) }
        if !uploadFailures.isEmpty { throw uploadFailures.removeFirst() }
        isWaitingForUnlock = locked
        // Stopped after the page in flight: what's left is a backlog.
        hasBacklog = stopRequested || (backlogs.isEmpty ? false : backlogs.removeFirst())
        return touched
    }

    func stopAfterCurrentPage() async {
        stopRequests += 1
        stopRequested = true
    }

    /// What the uploads said scoring takes; the first wait.
    var expectedScoringSeconds: Int? = 3
    /// `GET /v1/me/sync` → `gate`.
    var gate: APIErrorCode?

    /// How long each ask of `GET /v1/me/sync` takes, on the clock.
    var askDuration: Duration = .zero

    /// The days `GET /v1/me/sync` lists while they're pending, when not the touched ones (uploaded elsewhere).
    var listed: [String]?

    /// Every ask fails (offline, a timeout).
    var statusFails = false
    /// `GET /v1/me/sync`'s `expected_within_sec`.
    var statusExpected = 3

    /// `scored` per ask: the touched (or listed) days are pending until one says `true`.
    func syncStatus() async throws -> SyncStatus {
        events.append("poll")
        if statusFails { throw APIError.transport(URLError(.notConnectedToInternet)) }
        if askDuration > .zero { try await clock.sleep(for: askDuration) }
        let done = scored.isEmpty ? false : scored.removeFirst()
        return SyncStatus(gate: gate, lastSyncAt: nil, lastSyncDevice: nil, latest: [:],
                          today: TodayState(day: "2026-10-19", state: done ? .scored : .pending, scoredAt: nil,
                                            modelVersion: "2026.10.1"),
                          pendingDays: done ? [] : listed ?? touched, expectedWithinSec: statusExpected,
                          resyncRequestedAt: nil)
    }

    /// When the touched days were refreshed, on the clock.
    private(set) var refreshedAt: Date?
    func refreshDays(_ days: [String]) async throws {
        events.append("days:\(days.joined(separator: ","))")
        refreshedAt = clock.now()
    }
    func refreshTrends() async throws { events.append("trends") }
    func refreshInsights() async throws { events.append("insights") }
    func refreshStale() async { events.append("stale") }
    private(set) var phases: [SyncPhase] = []
    func report(_ phase: SyncPhase) {
        phases.append(phase)
        if recordsWords { events.append("phase:\(phase)") }
    }

    /// The scoring words (and the phases) go into `events` too, in order with the stages.
    var recordsWords = false
    private(set) var awaited: [[String]] = []
    func awaiting(_ days: [String]) {
        awaited.append(days)
        if recordsWords { events.append("awaiting:\(days.joined(separator: ","))") }
    }
    func scored(_ days: [String]) {
        if recordsWords { events.append("scored:\(days.joined(separator: ","))") }
    }
    var readsScoringStatus = true
    /// The phone's unanswered pending words.
    var awaitedDays: [String] = []
    /// What the last upload's accepted pages touched (also when it failed afterwards).
    var touchedSoFar: [String] = []
    /// The latest status read and when it arrived.
    var lastStatus: (status: SyncStatus, readAt: Date)?

    func count(_ name: String) -> Int { events.filter { $0 == name }.count }
}

@Suite("Sync coordinator")
@MainActor
struct SyncCoordinatorTests {
    @Test func stagesRunInDependencyOrder() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock)

        let run = Task { await c.run(.userInitiated) }
        #expect(await eventually { clock.pendingSleeps == 1 }) // waiting for scoring
        #expect(steps.events == ["upload"])
        clock.advance(by: .seconds(10))
        let outcome = await run.value

        #expect(outcome.touched == ["2026-10-19"] && outcome.polls == 1 && outcome.error == nil)
        #expect(Array(steps.events.prefix(3)) == ["upload", "poll", "days:2026-10-19"])
        #expect(Set(steps.events.suffix(2)) == ["trends", "insights"]) // in parallel, after the days
    }

    @Test func nothingUploadedOnlyRefreshesWhatsStale() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        // The platform scores nothing (the one ask): what's stale is refreshed, no wait.
        let outcome = await SyncCoordinator(steps: steps, clock: clock).run(.appActive)
        #expect(steps.events == ["upload", "poll", "stale"])
        #expect(outcome.polls == 0 && steps.awaited.isEmpty)
        // An account that can't read the status (demo data, signed out) doesn't ask.
        let quiet = FakeSteps(clock: clock)
        quiet.touched = []
        quiet.readsScoringStatus = false
        _ = await SyncCoordinator(steps: quiet, clock: clock).run(.appActive)
        #expect(quiet.events == ["upload", "stale"])
    }

    // MARK: D3b: one owner for "this day is being scored"

    @Test func aForegroundRunThatSentNothingWaitsForDaysThePlatformStillScores() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        steps.listed = ["2026-10-19"] // uploaded in the background, or by another device
        steps.scored = [false, true]
        steps.recordsWords = true
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        // What's stale is refreshed at once, not behind the wait.
        #expect(await eventually { clock.pendingSleeps == 1 && steps.events.contains("stale") })
        #expect(Array(steps.events.prefix(2)) == ["upload", "poll"])
        #expect(Set(steps.events.dropFirst(2)) == ["phase:awaitingScores", "stale"])
        // The status's 3 s, no sooner than the status cache allows.
        clock.advance(by: .seconds(9))
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(steps.count("poll") == 1)
        clock.advance(by: .seconds(1))
        let outcome = await run.value
        #expect(outcome.polls == 1 && outcome.touched == ["2026-10-19"])
        #expect(Array(steps.events.dropFirst(4).prefix(3)) == ["poll", "phase:refreshing", "days:2026-10-19"])
        #expect(steps.count("stale") == 1)
        // Nothing was written: no word of the phone's (the status is the platform's own).
        #expect(steps.awaited.isEmpty)
    }

    @Test func aBackgroundRunThatSentNothingAsksNothing() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        steps.listed = ["2026-10-19"]
        let outcome = await SyncCoordinator(steps: steps, clock: clock, inBackground: true).run(.healthKit)
        #expect(steps.events == ["upload"])
        #expect(outcome.polls == 0 && steps.phases == [.done])
    }

    @Test func aGatedRunThatSentNothingDoesNotWait() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        steps.listed = ["2026-10-19"]
        steps.scored = [false]
        steps.gate = .consentRequired // nothing is scored behind it
        let outcome = await SyncCoordinator(steps: steps, clock: clock).run(.appActive)
        #expect(steps.events == ["upload", "poll", "stale"])
        #expect(outcome.polls == 0 && !steps.phases.contains(.awaitingScores))
        // A failed ask refreshes what's stale too.
        let offline = FakeSteps(clock: clock)
        offline.touched = []
        offline.statusFails = true
        _ = await SyncCoordinator(steps: offline, clock: clock).run(.appActive)
        #expect(offline.events == ["upload", "poll", "stale"])
    }

    @Test func aSilentPushMarksItsDaysScoredBeforeTheRefresh() async {
        let clock = TestClock()
        // Its own refresh.
        let steps = FakeSteps(clock: clock)
        steps.recordsWords = true
        _ = await SyncCoordinator(steps: steps, clock: clock).run(.silentPush(days: ["2026-10-18"]))
        #expect(Array(steps.events.prefix(3)) == ["scored:2026-10-18", "phase:refreshing", "days:2026-10-18"])
        // Ending a wait: the word comes before the waiting run refreshes.
        let waiting = FakeSteps(clock: clock)
        waiting.recordsWords = true
        let c = SyncCoordinator(steps: waiting, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        _ = await c.run(.silentPush(days: ["2026-10-19"]))
        _ = await run.value
        let scored = waiting.events.firstIndex(of: "scored:2026-10-19") ?? .max
        let refreshed = waiting.events.firstIndex(of: "days:2026-10-19") ?? -1
        #expect(scored < refreshed, "\(waiting.events)")
        // Queued behind an upload: said at once, before the rerun.
        let busy = FakeSteps(clock: clock)
        busy.recordsWords = true
        busy.touched = []
        busy.uploadDuration = .seconds(10)
        let b = SyncCoordinator(steps: busy, clock: clock)
        let upload = Task { await b.run(.userInitiated) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let push = Task { await b.run(.silentPush(days: ["2026-10-17"])) }
        #expect(await eventually { busy.events.contains("scored:2026-10-17") })
        #expect(!busy.events.contains("days:2026-10-17"))
        clock.advance(by: .seconds(10))
        _ = await upload.value
        _ = await push.value
        #expect(busy.events.contains("days:2026-10-17"))
    }

    @Test func theAwaitedDaysAreKnownDuringTheWaitAndClearedAfter() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.recordsWords = true
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.userInitiated) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        // Said right after the upload, before the wait starts.
        #expect(steps.events == ["upload", "awaiting:2026-10-19", "phase:awaitingScores"])
        clock.advance(by: .seconds(10))
        _ = await run.value
        // In the background too (no wait there: the foreground return reads it), and for a `daysChanged`.
        let background = FakeSteps(clock: clock)
        _ = await SyncCoordinator(steps: background, clock: clock, inBackground: true).run(.healthKit)
        #expect(background.awaited == [["2026-10-19"]])
        let changed = FakeSteps(clock: clock)
        _ = await SyncCoordinator(steps: changed, clock: clock, inBackground: true).run(.daysChanged(days: ["2026-10-12"]))
        #expect(changed.awaited == [["2026-10-12"]])
        // A `daysChanged` that rode along with an upload is said with the uploaded days.
        let merged = FakeSteps(clock: clock)
        merged.uploadDuration = .seconds(5)
        let m = SyncCoordinator(steps: merged, clock: clock, inBackground: true)
        let first = Task { await m.run(.healthKit) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let days = Task { await m.run(.daysChanged(days: ["2026-10-12"])) }
        #expect(await queued(m, .daysChanged(days: ["2026-10-12"])))
        let rerun = Task { await m.run(.userInitiated) } // an upload trigger wins the merge; the day rides along
        #expect(await queued(m, .userInitiated))
        clock.advance(by: .seconds(5))
        _ = await first.value
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(5))
        _ = await rerun.value
        _ = await days.value
        #expect(merged.awaited == [["2026-10-19"], ["2026-10-19", "2026-10-12"]])
    }

    @Test func aRunThatSentNothingWaitsForThePhonesWordsEvenWhenTheStatusListsNone() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        steps.recordsWords = true
        // A background upload under 10 s ago: the platform's cached answer lists nothing yet, the phone's word does.
        steps.scored = [true, true]
        steps.awaitedDays = ["2026-10-19"]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        let outcome = await run.value
        #expect(outcome.polls == 1 && outcome.touched == ["2026-10-19"])
        #expect(steps.events.contains("days:2026-10-19") && steps.phases.contains(.awaitingScores))
        #expect(steps.awaited.isEmpty) // the word was the background run's
    }

    @Test func aDayAWaitGaveUpOnIsNotWaitedForAgainUntilAWriteTouchesIt() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        steps.listed = ["2026-10-19"]
        steps.scored = [] // pending for good
        let c = SyncCoordinator(steps: steps, clock: clock)
        let first = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: SyncCoordinator.maximumScoringWait)
        #expect(await first.value.polls == 0)
        #expect(steps.events.contains("days:2026-10-19"))
        // The next opening asks, sees the same day, and doesn't hold the pipeline for it again.
        let again = await c.run(.appActive)
        #expect(again.polls == 0 && again.touched.isEmpty)
        #expect(Array(steps.events.suffix(3)) == ["upload", "poll", "stale"])
        // A write touches it: waited for again, and so is the platform's listing of it after that.
        steps.touched = ["2026-10-19"]
        steps.scored = [true]
        let written = Task { await c.run(.userInitiated) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        #expect(await written.value.polls == 1)
        steps.touched = []
        steps.scored = [false, true]
        let listed = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        #expect(await listed.value.polls == 1)
    }

    @Test func aStatusReadUnderTheCacheTimeAgoIsUsedAsItIsWithItsOwnEstimate() async {
        let clock = TestClock()
        let pending = SyncStatus(gate: nil, lastSyncAt: nil, lastSyncDevice: nil, latest: [:],
                                 today: TodayState(day: "2026-10-19", state: .pending, scoredAt: nil, modelVersion: "x"),
                                 pendingDays: ["2026-10-19"], expectedWithinSec: 25, resyncRequestedAt: nil)
        let fresh = FakeSteps(clock: clock)
        fresh.touched = []
        fresh.expectedScoringSeconds = 50 // an older upload's estimate: not this status's
        fresh.lastStatus = (pending, clock.now().addingTimeInterval(-9))
        let c = SyncCoordinator(steps: fresh, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 && fresh.events.contains("stale") })
        #expect(fresh.count("poll") == 0) // the platform would answer from its cache
        clock.advance(by: .seconds(24))
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(fresh.count("poll") == 0)
        clock.advance(by: .seconds(1))
        #expect(await run.value.polls == 1)
        // 10 s old: asked again, and its estimate is the wait's.
        let stale = FakeSteps(clock: clock)
        stale.touched = []
        stale.listed = ["2026-10-19"]
        stale.scored = [false, true]
        stale.statusExpected = 25
        stale.expectedScoringSeconds = 50
        stale.lastStatus = (pending, clock.now().addingTimeInterval(-ScoringWord.statusCacheTime))
        let s = SyncCoordinator(steps: stale, clock: clock)
        let asked = Task { await s.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(stale.count("poll") == 1)
        clock.advance(by: .seconds(25))
        #expect(await asked.value.polls == 1)
    }

    @Test func anUploadThatEndsEarlySaysTheDaysItsAcceptedPagesTouched() async {
        let clock = TestClock()
        // Failed after the platform accepted a page.
        let failed = FakeSteps(clock: clock)
        failed.uploadFailures = [APIError.http(422, "bad")]
        failed.touchedSoFar = ["2026-10-18"]
        let outcome = await SyncCoordinator(steps: failed, clock: clock).run(.userInitiated)
        #expect(outcome.error != nil && failed.awaited == [["2026-10-18"]])
        // Cancelled (sign-out, background time over) mid-upload.
        let cancelled = FakeSteps(clock: clock)
        cancelled.uploadDuration = .seconds(10)
        cancelled.touchedSoFar = ["2026-10-18"]
        let c = SyncCoordinator(steps: cancelled, clock: clock)
        let run = Task { await c.run(.userInitiated) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        await c.cancel()
        #expect(await run.value.cancelled)
        #expect(cancelled.awaited == [["2026-10-18"]])
        // A transient failure retried: the first attempt's days are the run's too.
        let retried = FakeSteps(clock: clock)
        retried.uploadFailures = [APIError.transport(URLError(.timedOut))]
        retried.touchedSoFar = ["2026-10-17"]
        let r = SyncCoordinator(steps: retried, clock: clock)
        let retry = Task { await r.run(.userInitiated) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: SyncCoordinator.firstBackoff)
        #expect(await eventually { clock.pendingSleeps == 1 && retried.count("upload") == 2 })
        clock.advance(by: .seconds(10))
        #expect(await retry.value.touched == ["2026-10-19", "2026-10-17"])
        #expect(retried.awaited == [["2026-10-19", "2026-10-17"]])
        // Nothing accepted: nothing said.
        let refused = FakeSteps(clock: clock)
        refused.uploadFailures = [APIError.http(422, "bad")]
        _ = await SyncCoordinator(steps: refused, clock: clock).run(.userInitiated)
        #expect(refused.awaited.isEmpty)
    }

    /// Until the queued rerun's trigger is `trigger`.
    private func queued(_ c: SyncCoordinator, _ trigger: SyncCoordinator.Trigger) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            if await c.queuedRunTrigger == trigger { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await c.queuedRunTrigger == trigger
    }

    @Test func asksTheServerWithDoublingWaitsForFiveMinutesAtMost() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = []
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }

        // The platform's estimate (3 s), but no sooner than its status cache allows (10 s), doubling, a minute at
        // most, five minutes in all; no ask at the deadline itself (the days are refreshed now anyway).
        let waits = [10, 20, 40, 60, 60, 60, 50]
        for wait in waits {
            #expect(await eventually { clock.pendingSleeps == 1 })
            clock.advance(by: .seconds(wait))
        }
        let outcome = await run.value
        #expect(outcome.polls == waits.count - 1)
        #expect(steps.count("poll") == waits.count - 1)
        #expect(steps.events.contains("days:2026-10-19")) // refreshed anyway
    }

    @Test func scoredOnTheSecondPollStopsPolling() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = [false, true]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(20))
        #expect(await run.value.polls == 2)
    }

    @Test func concurrentTriggersCoalesceIntoOneRerun() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        steps.uploadDuration = .seconds(10)
        let c = SyncCoordinator(steps: steps, clock: clock)

        let first = Task { await c.run(.background) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        // Three more while the first is uploading: one queued rerun, shared.
        let others = (0..<3).map { _ in Task { await c.run(.healthKit) } }
        #expect(await eventually { steps.count("upload") == 1 })
        clock.advance(by: .seconds(10))
        _ = await first.value
        #expect(await eventually { clock.pendingSleeps == 1 }) // the rerun is uploading
        clock.advance(by: .seconds(10))
        for t in others { _ = await t.value }

        #expect(steps.count("upload") == 2)
        #expect(await !c.isRunning)
    }

    @Test func cancellingStopsThePipeline() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.userInitiated) }
        #expect(await eventually { clock.pendingSleeps == 1 }) // waiting for scoring
        await c.cancel()
        let outcome = await run.value
        #expect(outcome.cancelled)
        #expect(!steps.events.contains { $0.hasPrefix("days:") })
    }

    @Test func transientUploadFailuresBackOffExponentially() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        steps.uploadFailures = [APIError.http(503, ""), APIError.transport(URLError(.timedOut))]
        let start = clock.now()
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.userInitiated) }

        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(2))
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(4))
        let outcome = await run.value

        #expect(outcome.attempts == 3 && outcome.error == nil)
        #expect(clock.now().timeIntervalSince(start) == 6)
        #expect(steps.count("upload") == 3)
    }

    @Test func clientErrorsAreNotRetried() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.uploadFailures = [APIError.http(422, "bad")]
        let outcome = await SyncCoordinator(steps: steps, clock: clock).run(.userInitiated)
        #expect(outcome.attempts == 0 && outcome.error != nil)
        #expect(steps.count("upload") == 1)
        #expect(!SyncCoordinator.isTransient(APIError.http(401, "")))
        #expect(SyncCoordinator.isTransient(APIError.http(502, "")))
    }

    @Test func silentPushRefreshesItsDaysWithoutUploading() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let outcome = await SyncCoordinator(steps: steps, clock: clock).run(.silentPush(days: ["2026-10-18"]))
        #expect(steps.events.first == "days:2026-10-18")
        #expect(!steps.events.contains("upload") && !steps.events.contains("poll"))
        #expect(outcome.touched == ["2026-10-18"])
    }

    @Test func prioritiesFollowTheTrigger() {
        #expect(SyncCoordinator.Trigger.userInitiated.priority == .userInitiated)
        #expect(SyncCoordinator.Trigger.reconnect.priority == .userInitiated)
        #expect(SyncCoordinator.Trigger.background.priority == .utility)
        #expect(SyncCoordinator.Trigger.silentPush(days: []).priority == .utility)
    }
}

@Suite("Scheduled work")
@MainActor
struct ScheduledWorkTests {
    @Test func compactionRunsAtThreeAtNight() {
        let cal = Calendar.current
        let evening = cal.date(bySettingHour: 22, minute: 0, second: 0, of: .now)!
        let next = BackgroundWork.nextCompaction(after: evening)
        #expect(cal.component(.hour, from: next) == 3 && next > evening)
        let early = cal.date(bySettingHour: 1, minute: 0, second: 0, of: .now)!
        #expect(cal.isDate(BackgroundWork.nextCompaction(after: early), inSameDayAs: early))
    }

    @Test func dailyReminderUsesACalendarTrigger() async throws {
        let notifier = MockNotifier()
        let scheduler = ReminderScheduler(notifier: notifier)
        try await scheduler.scheduleDaily(id: "bedtime", hour: 22, minute: 30, title: "Bedtime", body: "Wind down",
                                          category: "BEDTIME")
        try await scheduler.scheduleDaily(id: "bedtime", hour: 23, minute: 0, title: "Bedtime", body: "Wind down")
        #expect(notifier.requests.count == 1)
        let trigger = try #require(notifier.requests.first?.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats && trigger.dateComponents.hour == 23 && trigger.dateComponents.minute == 0)
        scheduler.cancel(id: "bedtime")
        #expect(notifier.requests.isEmpty)
    }

    @Test func compactionDropsOldDaysAndUnusedDetails() throws {
        let clock = TestClock(now: .now)
        let env = AppEnvironment.test(clock: clock)
        let repo = Repository(env: env)
        let now = clock.now()
        repo.store(scores: [DailyScore(day: DayFormat.string(from: DayFormat.shift(now, days: -400))),
                            DailyScore(day: DayFormat.string(from: now))])
        repo.store(workout: MockData.workoutDetail(MockData.todayDetail.workouts[0]))
        clock.advance(by: .seconds(31 * 86_400))
        let removed = repo.compact()
        #expect(removed >= 2)
        #expect(repo.history(from: DayFormat.shift(clock.now(), days: -500), to: clock.now()).count == 1)
        #expect(repo.workout(MockData.todayDetail.workouts[0].id) == nil)
    }
}

@Suite("Sync coordinator: backlog")
@MainActor
struct SyncCoordinatorBacklogTests {
    @Test func aBacklogRunsOnAfterTheFirstScoreIsOnScreen() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.backlogs = [true]
        steps.scored = [true, true]
        let c = SyncCoordinator(steps: steps, clock: clock)

        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 }) // waiting for the first score
        clock.advance(by: .seconds(10))
        let first = await run.value
        #expect(first.backlog)
        #expect(steps.events.contains("days:2026-10-19")) // the first score refreshed…

        #expect(await eventually { steps.count("upload") == 2 }) // …then the backlog uploads
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        #expect(await eventually { !steps.hasBacklog && steps.events.filter { $0.hasPrefix("days:") }.count == 2 })
        #expect(SyncCoordinator.Trigger.backlog.priority == .utility)
    }

    @Test func aCancelledRunDoesNotContinue() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.backlogs = [true]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        await c.cancel()
        #expect(await run.value.cancelled)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(steps.count("upload") == 1)
    }
}

@Suite("Sync coordinator: background and HealthKit delivery")
@MainActor
struct SyncCoordinatorBackgroundTests {
    /// Counts completions from any thread.
    final class Completions: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var calls: Int { lock.withLock { n } }
        func done() { lock.withLock { n += 1 } }
    }

    @Test func aDeliveryCompletesRightAfterTheUploadNotAfterScoring() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let completions = Completions()
        // A foreground run waits for scoring; the delivery doesn't.
        let run = Task { await c.run(.userInitiated, afterUpload: { completions.done() }) }
        #expect(await eventually { clock.pendingSleeps == 1 }) // waiting for the score…
        #expect(completions.calls == 1) // …the delivery already completed
        clock.advance(by: .seconds(10))
        _ = await run.value
        #expect(completions.calls == 1)
    }

    @Test func aDeliveryThatJoinsARunCompletesAfterItsOwnUpload() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        steps.uploadDuration = .seconds(5)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let completions = Completions()
        let first = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let joined = Task { await c.run(.healthKit, afterUpload: { completions.done() }) }
        var queued = false
        for _ in 0..<10_000 where !queued {
            queued = await c.hasQueuedRun
            if !queued { try? await Task.sleep(for: .milliseconds(1)) }
        }
        #expect(queued)
        clock.advance(by: .seconds(5)) // the first upload ends: not this delivery's
        _ = await first.value
        #expect(await eventually { clock.pendingSleeps == 1 && steps.count("upload") == 2 })
        #expect(completions.calls == 0)
        clock.advance(by: .seconds(5))
        _ = await joined.value
        #expect(completions.calls == 1)
    }

    @Test func aDeliveryCompletesEvenWhenItsRunIsCancelledOrFails() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.uploadFailures = [APIError.http(422, "")]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let completions = Completions()
        _ = await c.run(.healthKit, afterUpload: { completions.done() })
        #expect(completions.calls == 1)

        steps.uploadDuration = .seconds(5)
        let busy = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let queued = Task { await c.run(.healthKit, afterUpload: { completions.done() }) }
        var joined = false
        for _ in 0..<10_000 where !joined {
            joined = await c.hasQueuedRun
            if !joined { try? await Task.sleep(for: .milliseconds(1)) }
        }
        #expect(joined)
        await c.cancel() // sign-out: the queued delivery is completed, not left hanging
        #expect(await eventually { completions.calls == 2 })
        _ = await busy.value
        _ = await queued.value
    }

    @Test func backgroundRunsUseTheBackgroundSessionAndSkipTheScoringWait() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock, inBackground: true) // launched for a delivery

        let outcome = await c.run(.healthKit)

        #expect(steps.backgroundUploads == [true])
        #expect(outcome.polls == 0 && !steps.events.contains("poll")) // the silent push refreshes
        await c.enterForeground()
        let foreground = Task { await c.run(.userInitiated) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        _ = await foreground.value
        #expect(steps.backgroundUploads == [true, false] && steps.count("poll") == 1)
    }

    @Test func goingToTheBackgroundFinishesThePageInFlightAndLeavesABacklog() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.uploadDuration = .seconds(5)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 && steps.isUploading })

        let wound = Task { await c.windDown() }
        #expect(await eventually { steps.stopRequests == 1 })
        clock.advance(by: .seconds(5)) // the page finishes
        await wound.value
        let outcome = await run.value

        #expect(!outcome.cancelled && outcome.backlog) // not cancelled: stopped with a backlog
        #expect(await c.inBackground)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(steps.count("upload") == 1) // no backlog run in the background: BG processing takes it
    }

    @Test func goingToTheBackgroundDuringTheScoringWaitEndsIt() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 }) // waiting for scoring
        await c.windDown()
        #expect(await run.value.cancelled)
        #expect(steps.stopRequests == 0)
        await c.enterForeground() // the user is back
        let again = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(await !c.inBackground)
        await c.cancel()
        _ = await again.value
    }

    @Test func aLockedPhoneIsWaitingNotFailing() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.locked = true
        steps.touched = []
        let outcome = await SyncCoordinator(steps: steps, clock: clock).run(.healthKit)
        #expect(outcome.waitingForUnlock && outcome.error == nil)
    }
}

/// A `BGProcessingTask` stand-in.
@MainActor
private final class FakeBGTask: BackgroundTaskHandle {
    var expirationHandler: (() -> Void)?
    private(set) var completed: Bool?
    func setTaskCompleted(success: Bool) { completed = success }
}

/// `UIApplication`'s background time, recorded.
@MainActor
private final class FakeApp: BackgroundTaskRunning {
    private(set) var begun = 0
    private(set) var ended: [UIBackgroundTaskIdentifier] = []
    private(set) var expiration: (@MainActor @Sendable () -> Void)?
    func beginBackgroundTask(withName taskName: String?,
                             expirationHandler handler: (@MainActor @Sendable () -> Void)?) -> UIBackgroundTaskIdentifier {
        begun += 1
        expiration = handler
        return UIBackgroundTaskIdentifier(rawValue: begun)
    }
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) { ended.append(identifier) }
}

@Suite("Background work")
@MainActor
struct BackgroundWorkTests {
    @Test func theBackfillWaitsForPowerAboveTenMegabytes() {
        let small = BackgroundWork.backfillRequest(backlogBytes: 2_000_000)
        #expect(small.requiresNetworkConnectivity && !small.requiresExternalPower)
        #expect(BackgroundWork.backfillRequest(backlogBytes: 40_000_000).requiresExternalPower)
        #expect(small.identifier == BackgroundWork.backfillTaskID)
    }

    @Test func theBackfillTaskRunsUntilTheBacklogIsGone() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.backlogs = [true, false] // the first score's window, then the backfill
        let c = SyncCoordinator(steps: steps, clock: clock)
        let task = FakeBGTask()
        var scheduled: [Int] = []

        await BackgroundWork.runBackfill(task, coordinator: c, backlogBytes: { nil }) { scheduled.append($0) }

        #expect(steps.count("upload") == 2 && steps.backgroundUploads == [true, true])
        #expect(task.completed == true && scheduled.isEmpty)
    }

    @Test func anExpiredBackfillIsCancelledAtOnceAndScheduledAgain() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.uploadDuration = .seconds(5)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let task = FakeBGTask()
        var scheduled: [Int] = []
        let run = Task {
            await BackgroundWork.runBackfill(task, coordinator: c, backlogBytes: { 30_000_000 }) { scheduled.append($0) }
        }
        #expect(await eventually { steps.isUploading && task.expirationHandler != nil })
        task.expirationHandler?() // the system's time is up: no waiting for the page
        await run.value

        #expect(steps.count("upload") == 1) // not another page after the expiry
        #expect(scheduled == [30_000_000] && task.completed == false)
    }

    @Test func leavingTheAppFinishesThePageInABackgroundTask() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.uploadDuration = .seconds(5)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let app = FakeApp()
        var scheduled: [Int] = []
        let run = Task { await c.run(.appActive) }
        // Uploading and asleep on the clock: an advance before the sleep starts is lost.
        #expect(await eventually { steps.isUploading && clock.pendingSleeps == 1 })

        let finishing = BackgroundWork.finishInBackground(coordinator: c, app: app, backlogBytes: { 12_000_000 }) {
            scheduled.append($0)
        }
        #expect(app.begun == 1)
        #expect(await eventually { steps.stopRequests == 1 })
        clock.advance(by: .seconds(5))
        await finishing.value

        #expect(!(await run.value).cancelled) // finished, not cancelled
        #expect(app.ended.count == 1 && scheduled == [12_000_000])
    }

    @Test func runningOutOfBackgroundTimeCancels() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.uploadDuration = .seconds(5)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let app = FakeApp()
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { steps.isUploading })
        let finishing = BackgroundWork.finishInBackground(coordinator: c, app: app, backlogBytes: { nil }) { _ in }

        app.expiration?() // iOS: time's up
        #expect(await run.value.cancelled)
        await finishing.value
        #expect(app.ended.count == 1) // ended once, not twice
    }
}

/// The review on #10.
@Suite("Sync coordinator: backlog edge cases")
@MainActor
struct SyncCoordinatorBacklogEdgeTests {
    @Test func theContinuationIsRegisteredAtOnceSoACancelFindsIt() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.backlogs = [true]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        #expect(await run.value.backlog)
        #expect(await c.isRunning) // the backlog run, already registered
        await c.cancel()
        var stopped = false
        for _ in 0..<5_000 where !stopped {
            stopped = await !c.isRunning
            if !stopped { try? await Task.sleep(for: .milliseconds(1)) }
        }
        #expect(stopped)
    }

    @Test func aQueuedPushDoesNotSwallowTheBacklog() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.backlogs = [true]
        steps.scored = [true, true]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let push = Task { await c.run(.silentPush(days: ["2026-10-20"])) } // queued behind it
        var queued = false
        for _ in 0..<10_000 where !queued {
            queued = await c.hasQueuedRun
            if !queued { try? await Task.sleep(for: .milliseconds(1)) }
        }
        clock.advance(by: .seconds(10))
        _ = await run.value
        #expect(await eventually { steps.count("upload") == 2 }) // the queued rerun uploads the rest
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        _ = await push.value
    }

    @Test func anUploadThatSentNothingLeavesNoBacklog() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = [] // offline, gated or demo
        steps.backlogs = [true] // a flag left from before
        let outcome = await SyncCoordinator(steps: steps, clock: clock).run(.appActive)
        #expect(!outcome.backlog)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(steps.count("upload") == 1) // no loop
    }
}

/// The review on #11.
@Suite("Sync coordinator: lifecycle")
@MainActor
struct SyncCoordinatorLifecycleTests {
    @Test func aDeliveryWhileTheUserLooksStillRefreshesToday() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock) // foreground
        let run = Task { await c.run(.healthKit) }
        #expect(await eventually { clock.pendingSleeps == 1 }) // waits for the score like any foreground run
        clock.advance(by: .seconds(10))
        _ = await run.value
        #expect(steps.backgroundUploads == [false] && steps.events.contains("days:2026-10-19"))
    }

    @Test func comingBackOnlineInTheBackgroundStaysInTheBackground() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock)
        await c.windDown()
        _ = await c.run(.reconnect)
        #expect(await c.inBackground)
        #expect(steps.backgroundUploads == [true] && !steps.events.contains("poll"))
    }

    @Test func aBacklogLeftInTheBackgroundGoesToTheBackfillTask() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.backlogs = [true, true]
        let scheduled = Counter()
        let c = SyncCoordinator(steps: steps, clock: clock, inBackground: true) { scheduled.add() }

        _ = await c.run(.healthKit)
        #expect(await eventually { scheduled.value == 1 })
        _ = await c.run(.processing) // the backfill task loops by itself
        try? await Task.sleep(for: .milliseconds(50))
        #expect(scheduled.value == 1 && steps.count("upload") == 2)
    }

    @Test func aCancelledRerunLeavesItsReplacementAlone() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        steps.uploadDuration = .seconds(5)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let first = Task { await c.run(.appActive) }
        #expect(await eventually { steps.isUploading && clock.pendingSleeps == 1 })
        let a = SyncCoordinatorBackgroundTests.Completions()
        let queuedA = Task { await c.run(.healthKit, afterUpload: { a.done() }) }
        #expect(await waitForQueue(c))
        let wound = Task { await c.windDown() } // cancels A (completing it), waits for the page
        #expect(await eventually { a.calls == 1 && steps.stopRequests == 1 })
        let b = SyncCoordinatorBackgroundTests.Completions()
        let queuedB = Task { await c.run(.healthKit, afterUpload: { b.done() }) } // a replacement
        #expect(await waitForQueue(c))

        clock.advance(by: .seconds(5)) // the page in flight ends
        await wound.value
        _ = await first.value
        _ = await queuedA.value
        #expect(await eventually { steps.count("upload") == 2 && steps.isUploading && clock.pendingSleeps == 1 }) // B uploads
        #expect(b.calls == 0) // not completed by A on the way out
        clock.advance(by: .seconds(5))
        _ = await queuedB.value
        #expect(b.calls == 1)
    }

    private func waitForQueue(_ c: SyncCoordinator) async -> Bool {
        for _ in 0..<10_000 {
            if await c.hasQueuedRun { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

/// Counts from any thread.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func add() { lock.withLock { n += 1 } }
}

@Suite("Sync coordinator: scoring from the server")
@MainActor
struct SyncCoordinatorScoringTests {
    @Test func theFirstWaitIsThePlatformsEstimate() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.expectedScoringSeconds = 20
        let c = SyncCoordinator(steps: steps, clock: clock)
        let start = clock.now()
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(19))
        #expect(steps.count("poll") == 0)
        clock.advance(by: .seconds(1))
        _ = await run.value
        #expect(steps.count("poll") == 1 && clock.now().timeIntervalSince(start) == 20)
    }

    @Test func theSilentPushEndsTheWaitAndJoinsTheRun() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })

        let pushed = await c.run(.silentPush(days: ["2026-10-19"])) // scoring finished that day

        let outcome = await run.value
        #expect(pushed == outcome) // the push joined the run that refreshed
        #expect(outcome.polls == 0 && steps.count("poll") == 0) // no need to ask
        #expect(steps.events.filter { $0.hasPrefix("days:") } == ["days:2026-10-19"]) // refreshed once
    }

    @Test func aPushForAnotherDayDoesNotEndTheWait() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let other = Task { await c.run(.silentPush(days: ["2026-09-01"])) } // queued instead
        var queued = false
        for _ in 0..<10_000 where !queued {
            queued = await c.hasQueuedRun
            if !queued { try? await Task.sleep(for: .milliseconds(1)) }
        }
        #expect(queued && clock.pendingSleeps == 1) // still waiting
        clock.advance(by: .seconds(10))
        _ = await run.value
        _ = await other.value
        #expect(steps.events.contains("days:2026-09-01"))
    }

    @Test func daysLeaveTheWaitAsTheyAreScored() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = ["2026-10-18", "2026-10-19"]
        steps.scored = [false, true]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(20))
        #expect(await run.value.polls == 2)
    }

    @Test func aGateEndsTheWait() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = []
        steps.gate = .consentRequired // nothing is scored behind it
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        let outcome = await run.value
        #expect(outcome.polls == 1 && steps.events.contains("days:2026-10-19"))
    }

    @Test func aCancelledWaitEndsCleanly() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        await c.cancel()
        #expect(await run.value.cancelled)
        #expect(clock.pendingSleeps == 0)
        // A push after that finds nothing waiting: it refreshes on its own.
        let pushed = await c.run(.silentPush(days: ["2026-10-19"]))
        #expect(!pushed.cancelled && steps.events.last != nil)
    }
}

/// The review on #12.
@Suite("Sync coordinator: the scoring deadline")
@MainActor
struct SyncCoordinatorDeadlineTests {
    @Test func fiveMinutesMeansFiveMinutesWithSlowAsksToo() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = []
        steps.askDuration = .seconds(10) // every ask is slow
        let c = SyncCoordinator(steps: steps, clock: clock)
        let start = clock.now()
        let deadline = start.addingTimeInterval(300)
        let run = Task { await c.run(.appActive) }
        // Time moves up to the deadline and no further: the refresh must come without more of it,
        // asks included. (Ticking on until the refresh shows would count the ticks that ran
        // while the pipeline was busy cancelling an ask, not waiting.)
        while clock.now() < deadline, !steps.events.contains("days:2026-10-19") {
            guard await eventually({ clock.pendingSleeps > 0 || steps.events.contains("days:2026-10-19") }) else { break }
            if !steps.events.contains("days:2026-10-19") { clock.advance(by: .seconds(1)) }
        }
        #expect(await eventually { steps.events.contains("days:2026-10-19") })
        _ = await run.value
        #expect(steps.refreshedAt.map { $0 <= deadline } == true)
    }
}

// MARK: - read pipeline (T1): scheduler, budget, retries, pull phases, refresh policy

@MainActor
private func readGraph(api: MockPlatformAPI = MockPlatformAPI(), online: Bool = true, auth: AuthService? = nil,
                       now: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!)
    -> (AppEnvironment, AppState, TestClock) {
    let clock = TestClock(now: now)
    let env = AppEnvironment.test(api: api, clock: clock, auth: auth, online: online)
    return (env, AppState(env: env), clock)
}

/// A signed-in account whose session a test can end and start again (`MockAuthClient`).
@MainActor
private func testAuth(_ client: MockAuthClient) -> AuthService {
    AuthService(client: client, defaults: UserDefaults(suiteName: "ryft.test.auth.\(UUID().uuidString)") ?? .standard,
                wipeLocalData: { _ in }, deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                postAppleAuthorization: { _ in })
}

/// Counts calls of a scripted fetch (closures on the main actor).
@MainActor
private final class Calls {
    var count = 0
    /// Nothing counted yet.
    var isEmpty: Bool { count == .zero }
}

@Suite("Read scheduler")
@MainActor
struct ReadSchedulerTests {
    /// Criterion 3: transient failures retry at most twice, with backoff on the clock (full jitter: here its top).
    @Test func transientFailuresRetryTwiceWithBackoffOnTheClock() async throws {
        let api = MockPlatformAPI()
        api.faults["day"] = .init(.unavailable, times: 2)
        let (env, state, clock) = readGraph(api: api)
        env.reads.random = { $0.upperBound }
        let refresh = Task { try await state.repository.refreshDay(clock.now(), mode: .latest) }

        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(api.count("day") == 1)
        clock.advance(by: .milliseconds(999))
        #expect(api.count("day") == 1)                         // retry 1 waits up to 1 s
        clock.advance(by: .milliseconds(1))
        #expect(await eventually { api.count("day") == 2 && clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(2))                         // retry 2 waits up to 2 s
        let detail = try await refresh.value

        #expect(detail != nil && api.count("day") == 3)
        #expect(env.reads.states[.today]?.consecutiveFailures == 0)
        #expect(env.reads.states[.today]?.fetchedAt == clock.now())
    }

    /// Criterion 2: after its retries a read records its last error, exactly as received, and counts once.
    @Test func aReadGivesUpAfterTwoRetriesAndRecordsTheLastError() async {
        let api = MockPlatformAPI()
        api.faults["me"] = .init(.unavailable)
        let (env, state, _) = readGraph(api: api)

        await #expect(throws: APIError.self) { try await state.repository.refreshUser(mode: .latest) }

        #expect(api.count("me") == 3)
        let s = env.reads.states[.me]
        #expect(s?.consecutiveFailures == 1 && s?.fetchedAt == nil)
        #expect(s?.lastError?.kind == .transient && s?.lastError?.status == 503)
        #expect(s?.lastError?.requestID == "fault-me" && s?.lastError?.attempts == 3)

        api.faults["me"] = nil
        try? await state.repository.refreshUser(mode: .latest)
        #expect(env.reads.states[.me]?.consecutiveFailures == 0)  // a success resets the count
    }

    @Test func notTransientIsNotRetried() async {
        let api = MockPlatformAPI()
        api.faults["insights"] = .init(.notFound)
        let (env, state, _) = readGraph(api: api)
        try? await state.repository.refreshInsights(mode: .latest)
        #expect(api.count("insights") == 1)
        #expect(env.reads.states[.insights]?.lastError?.kind == .other)
        #expect(env.reads.states[.insights]?.consecutiveFailures == 1)
    }

    /// `Retry-After` up to the cap (5 s) is waited out, at least.
    @Test func retryAfterWithinTheCapIsWaitedOut() async throws {
        let api = MockPlatformAPI()
        api.faults["me"] = .init(.status(429, retryAfter: 3), times: 1)
        let (env, state, clock) = readGraph(api: api)
        let refresh = Task { try await state.repository.refreshUser(mode: .latest) }

        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(2))
        #expect(api.count("me") == 1)
        clock.advance(by: .seconds(1))
        try await refresh.value

        #expect(api.count("me") == 2 && env.reads.states[.me]?.consecutiveFailures == 0)
    }

    /// Beyond the cap: no retry now, counted, and automatic reads send nothing until then. A pull
    /// ignores the resource's hold, not the shared one after a `429`: longer than it may wait (5 s),
    /// so it fails at once with that 429 instead of waiting under "Updating…" (review 11).
    @Test func retryAfterBeyondTheCapHoldsAutomaticReadsBack() async {
        let api = MockPlatformAPI()
        api.faults["me"] = .init(.status(429, retryAfter: 30), times: 1)
        let (env, state, clock) = readGraph(api: api)

        try? await state.repository.refreshUser(mode: .latest)
        #expect(api.count("me") == 1)
        #expect(env.reads.states[.me]?.consecutiveFailures == 1)
        #expect(env.reads.states[.me]?.retryNotBefore == clock.now().addingTimeInterval(30))

        try? await state.repository.refreshUser(mode: .latest)
        #expect(api.count("me") == 1)                           // held back, nothing counted
        #expect(env.reads.states[.me]?.consecutiveFailures == 1)

        await #expect(throws: APIError.self) { try await state.repository.refreshUser(mode: .latest, userInitiated: true) }
        #expect(api.count("me") == 1 && clock.pendingSleeps == 0)   // nothing sent, nothing waited
        #expect(env.reads.states[.me]?.consecutiveFailures == 2)
        #expect(env.reads.states[.me]?.lastError?.status == 429)

        clock.advance(by: RequestBudget.maxHoldBack)
        try? await state.repository.refreshUser(mode: .latest, userInitiated: true)
        #expect(api.count("me") == 2)                           // the hold is over: it goes out
        #expect(env.reads.states[.me]?.retryNotBefore == nil)
    }

    /// Criterion 4: a cancellation is never a failure, from the fault or from `cancelAll`.
    @Test func cancellationIsNeverRecorded() async {
        let api = MockPlatformAPI()
        api.faults["trends"] = .init(.cancel)
        let (env, state, clock) = readGraph(api: api)
        await #expect(throws: CancellationError.self) {
            try await state.repository.refreshTrend(.readiness, .week, mode: .latest)
        }
        #expect(api.count("trends") == 1 && env.reads.states[.trends] == nil)

        let held = Task {
            try await env.reads.run(ReadKey(.insights)) { try await clock.sleep(for: .seconds(5)); return 1 }
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        env.reads.cancelAll()
        await #expect(throws: CancellationError.self) { try await held.value }
        #expect(env.reads.states[.insights] == nil && env.reads.inFlight.isEmpty)
    }

    /// Criterion 6: a second read of a key in flight joins it; the first caller's cancellation cancels nothing.
    @Test func aSecondReadOfAKeyInFlightJoinsIt() async throws {
        let (env, _, clock) = readGraph()
        let calls = Calls()
        let key = ReadKey(.trends, id: "readiness-7d")
        let fetch: @MainActor () async throws -> Int = {
            calls.count += 1
            try await clock.sleep(for: .seconds(1))
            return calls.count
        }
        let first = Task { try await env.reads.run(key, fetch) }
        let second = Task { try await env.reads.run(key, fetch) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(env.reads.inFlight == [key])
        first.cancel()                                          // .refreshable going away
        clock.advance(by: .seconds(1))

        #expect(try await second.value == 1)
        #expect(calls.count == 1 && env.reads.inFlight.isEmpty)
        #expect(env.reads.states[.trends]?.fetchedAt == clock.now())
    }

    /// `.changed(since:)` doesn't join a read that started before the change: one follow-up, shared.
    @Test func aChangeAfterAReadStartedGetsOneSharedFollowUp() async throws {
        let (env, _, clock) = readGraph()
        let calls = Calls()
        let key = ReadKey(.today, id: "2026-10-21")
        let fetch: @MainActor () async throws -> Int = {
            calls.count += 1
            let n = calls.count
            try await clock.sleep(for: .seconds(1))
            return n
        }
        let first = Task { try await env.reads.run(key, mode: .latest, fetch) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .milliseconds(10))                    // scores landed after it started
        let since = clock.now()
        // `run` registers its caller before its first suspension: once a task has counted, it has asked.
        let asked = Calls()
        let a = Task { asked.count += 1; return try await env.reads.run(key, mode: .changed(since: since), fetch) }
        let b = Task { asked.count += 1; return try await env.reads.run(key, mode: .changed(since: since), fetch) }
        let late = Task { asked.count += 1; return try await env.reads.run(key, mode: .latest, fetch) }
        #expect(await eventually { asked.count == 3 })
        clock.advance(by: .seconds(1))

        let (one, joined) = (try await first.value, try await late.value)
        #expect(one == 1 && joined == 1)
        #expect(await eventually { clock.pendingSleeps == 1 })  // the follow-up
        clock.advance(by: .seconds(1))
        let (followA, followB) = (try await a.value, try await b.value)
        #expect(followA == 2 && followB == 2)
        #expect(calls.count == 2)
    }

    /// Offline (not demo): nothing is sent, nothing is recorded.
    @Test func offlineSendsAndRecordsNothing() async throws {
        let api = MockPlatformAPI()
        let (env, state, _) = readGraph(api: api, online: false)
        #expect(try await env.reads.run(ReadKey(.me)) { 1 } == nil)
        await state.refresh(force: true)
        try await state.refreshDays([])
        #expect(api.calls.isEmpty && env.reads.states.isEmpty)
    }

    /// One retry layer: every scheduled try is a single attempt for `APIClient`.
    @Test func scheduledReadsAreSingleAttempts() async throws {
        let (env, _, _) = readGraph()
        var seen: Bool?
        _ = try await env.reads.run(ReadKey(.insights)) { () -> Int in
            seen = APIClient.singleAttempt
            return 0
        }
        #expect(seen == true && !APIClient.singleAttempt)
    }

    /// In the background a read retries once.
    @Test func theBackgroundPolicyRetriesOnce() async {
        let api = MockPlatformAPI()
        api.faults["me"] = .init(.unavailable)
        let (_, state, _) = readGraph(api: api)
        await APIClient.$runsInBackground.withValue(true) {
            try? await state.repository.refreshUser(mode: .latest)
        }
        #expect(api.count("me") == 2)
    }

    /// The live account's record survives a relaunch (Copy diagnostics after a force-quit), request ID intact.
    @Test func theRecordPersistsForTheLiveAccount() async {
        let api = MockPlatformAPI()
        api.faults["me"] = .init(.unavailable)
        let (env, state, _) = readGraph(api: api)
        try? await state.repository.refreshUser(mode: .latest)
        #expect(ReadScheduler(env: env).states[.me] == nil)    // not yet: one save per `persistDelay`
        await env.reads.savePending()

        let relaunched = ReadScheduler(env: env)
        #expect(relaunched.states[.me] == env.reads.states[.me])
        #expect(relaunched.states[.me]?.lastError?.requestID == "fault-me")
        #expect(relaunched.states[.me]?.consecutiveFailures == 1)
    }

    /// Account change: reads in flight stop and what was known goes; the other account's record
    /// isn't loaded, and its own comes back when it signs in again.
    @Test func resetForgetsTheRecord() async {
        let api = MockPlatformAPI()
        api.faults["me"] = .init(.unavailable)
        let client = MockAuthClient(session: .preview(), signInSession: .preview(id: Self.otherUser))
        let (env, state, _) = readGraph(api: api, auth: testAuth(client))
        try? await state.repository.refreshUser(mode: .latest)
        let first = env.auth.accountID

        await env.auth.signOut()
        state.accountChanged(from: first)
        #expect(env.reads.states.isEmpty && state.refreshIssue == nil)
        await env.auth.signInWithApple(idToken: "token", nonce: "nonce", fullName: nil)
        state.accountChanged(from: nil)
        #expect(env.auth.accountID != first)
        #expect(env.reads.states.isEmpty)                       // not the first account's
        #expect(ReadScheduler(env: env).states.isEmpty)         // nor after a relaunch
    }

    static let otherUser = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    /// Copy diagnostics: one line per resource with times, statuses and IDs, no health values.
    @Test func diagnosticsListEveryResource() async {
        let api = MockPlatformAPI()
        api.faults["me"] = .init(.status(503, retryAfter: nil))
        let (_, state, _) = readGraph(api: api)
        await state.refresh()
        let sync = SyncService.ungated(env: state.env)
        let model = SyncDetailsModel(state: state, sync: sync,
                                     coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                  clock: state.env.clock),
                                     apiStatus: APIStatus())
        let text = model.diagnostics
        for resource in ReadResource.allCases { #expect(text.contains("\n\(resource.rawValue) | ")) }
        #expect(text.contains("me | - | 503 - fault-me "))
        #expect(model.resources.map(\.resource) == [.today, .history, .me, .syncStatus, .trends, .insights,
                                                    .journal, .config, .train])
        let me = model.resources.first { $0.resource == .me }
        #expect(me?.statusText(now: state.env.clock.now()).contains("503") == true)
        if let readiness = state.today?.score.readiness { #expect(!text.contains("readiness \(readiness)")) }
    }
}

@Suite("Request budget")
@MainActor
struct RequestBudgetTests {
    /// Criterion 5: never more than 3 in flight.
    @Test func atMostThreeInFlight() async throws {
        let clock = TestClock()
        let budget = RequestBudget(clock: clock)
        let admitted = Calls()
        for _ in 0..<4 {
            Task {
                guard (try? await budget.acquire(.normal)) != nil else { return }
                admitted.count += 1
            }
        }
        #expect(await eventually { admitted.count == 3 })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(admitted.count == 3)
        await budget.release()
        #expect(await eventually { admitted.count == 4 })
    }

    /// Criterion 5: never a burst over 5: 7 starts at once → 5, the rest a second later.
    @Test func atMostFiveStartsInAnySecond() async throws {
        let clock = TestClock()
        let budget = RequestBudget(clock: clock, maxInFlight: 10)
        let admitted = Calls()
        for _ in 0..<7 {
            Task {
                guard (try? await budget.acquire(.normal)) != nil else { return }
                admitted.count += 1
                await budget.release()
            }
        }
        #expect(await eventually { admitted.count == 5 && clock.pendingSleeps == 1 })
        clock.advance(by: .milliseconds(999))
        #expect(admitted.count == 5)
        clock.advance(by: .milliseconds(1))
        #expect(await eventually { admitted.count == 7 })
    }

    @Test func todayAndTheSyncStatusGoFirst() async throws {
        let clock = TestClock()
        let budget = RequestBudget(clock: clock, maxInFlight: 1)
        try await budget.acquire(.normal)
        var order: [String] = []
        let normal = Task { try await budget.acquire(.normal); order.append("normal"); await budget.release() }
        #expect(await queued(budget, 1))
        let high = Task { try await budget.acquire(.high); order.append("high"); await budget.release() }
        #expect(await queued(budget, 2))                         // the high one queued after the normal one
        await budget.release()
        try await normal.value
        try await high.value
        #expect(order == ["high", "normal"])
    }

    @Test func aCancelledWaiterLeavesTheQueue() async throws {
        let clock = TestClock()
        let budget = RequestBudget(clock: clock, maxInFlight: 1)
        try await budget.acquire(.normal)
        let waiter = Task { try await budget.acquire(.normal) }
        #expect(await queued(budget, 1))
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(await budget.waiting == 0)
        await budget.release()
        try await budget.acquire(.normal)                        // the slot went to nobody else
        #expect(await budget.inFlight == 1)
    }

    /// Waits until `count` requests are queued. A fixed real sleep raced the scheduler when the whole
    /// plan ran in parallel: the waiter hadn't reached `acquire` yet.
    private func queued(_ budget: RequestBudget, _ count: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            if await budget.waiting == count { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await budget.waiting == count
    }
}

/// A sync whose upload takes `uploadDuration` on the clock; the rest is the live pipeline.
@MainActor
private final class SlowUploadSteps: SyncSteps {
    let live: LiveSyncSteps
    let state: AppState
    let clock: TestClock
    var uploadDuration: Duration
    var statusDuration: Duration = .zero

    init(state: AppState, clock: TestClock, uploadDuration: Duration) {
        live = LiveSyncSteps(state: state, sync: SyncService.ungated(env: state.env), apiStatus: APIStatus())
        self.state = state
        self.clock = clock
        self.uploadDuration = uploadDuration
    }

    func upload() async throws -> [String] {
        try await clock.sleep(for: uploadDuration)
        return []
    }
    var hasBacklog: Bool { false }
    var isWaitingForUnlock: Bool { false }
    var isUploading: Bool { false }
    func stopAfterCurrentPage() async {}
    var expectedScoringSeconds: Int? { nil }
    func syncStatus() async throws -> SyncStatus {
        guard statusDuration > .zero else { return try await live.syncStatus() }
        // A slow status read is a read *in flight* (what Today's "Updating…" watches), not a sleep before it.
        let clock = clock, wait = statusDuration, state = state
        let status = try await state.env.reads.run(ReadKey(.syncStatus), userInitiated: true) {
            try await clock.sleep(for: wait)
            return try await state.env.api.syncStatus()
        }
        guard let status else { throw ReadScheduler.NotSent() }
        return status
    }
    func refreshDays(_ days: [String]) async throws { try await live.refreshDays(days) }
    func refreshTrends() async throws { try await live.refreshTrends() }
    func refreshInsights() async throws { try await live.refreshInsights() }
    func refreshStale() async {}
    func report(_ phase: SyncPhase) {}
}

@Suite("Pull to refresh")
@MainActor
struct PullToRefreshTests {
    /// Criterion 5: the upload starts, today and the sync status at once; the rest after 2 s if the upload
    /// takes longer.
    @Test func todayAndTheStatusFirstTheRestAfterTwoSeconds() async {
        let api = MockPlatformAPI()
        let (_, state, clock) = readGraph(api: api)
        let c = SyncCoordinator(steps: SlowUploadSteps(state: state, clock: clock, uploadDuration: .seconds(10)),
                                clock: clock)

        await state.pullToRefresh(coordinator: c)               // returned once phase 2 settled

        #expect(api.count("day") == 1 && api.count("syncStatus") == 1)
        #expect(api.count("days") + api.count("me") + api.count("trends") + api.count("insights") == 0)
        #expect(await eventually { clock.pendingSleeps == 3 })  // the upload, the 2 s head start, the upload wait's cap
        clock.advance(by: .seconds(2))
        await state.pullPhases?.value
        #expect(api.count("days") == 1 && api.count("me") == 1 && api.count("trends") == 1 && api.count("insights") == 1)
        clock.advance(by: .seconds(8))
    }

    /// The rest starts as soon as the upload ends, if that's before 2 s.
    @Test func theRestStartsWhenTheUploadEnds() async {
        let api = MockPlatformAPI()
        let (_, state, clock) = readGraph(api: api)
        let c = SyncCoordinator(steps: SlowUploadSteps(state: state, clock: clock, uploadDuration: .milliseconds(500)),
                                clock: clock)
        await state.pullToRefresh(coordinator: c)
        #expect(await eventually { clock.pendingSleeps == 3 })
        clock.advance(by: .milliseconds(500))
        await state.pullPhases?.value                           // without the 2 s passing
        #expect(api.count("days") == 1 && api.count("insights") == 1)
    }

    /// The spinner lasts until phase 2 settled or 3 s, whichever is first; the line carries the rest.
    @Test func thePullReturnsAfterThreeSecondsAtMost() async {
        let api = MockPlatformAPI()
        let (_, state, clock) = readGraph(api: api)
        let steps = SlowUploadSteps(state: state, clock: clock, uploadDuration: .seconds(1))
        steps.statusDuration = .seconds(10)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let returned = Calls()
        Task { await state.pullToRefresh(coordinator: c); returned.count += 1 }

        #expect(await eventually { clock.pendingSleeps == 5 })  // upload, its wait's cap, head start, spinner, status
        clock.advance(by: .milliseconds(2_999))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(returned.isEmpty)
        clock.advance(by: .milliseconds(1))
        #expect(await eventually { returned.count == 1 })
        #expect(state.isLoading)                                // the status is still loading: "Updating…"
        clock.advance(by: .seconds(10))
    }

    /// `.refreshable` cancelling its task cancels neither phase.
    @Test func aCancelledPullStillLoads() async {
        let api = MockPlatformAPI()
        let (_, state, clock) = readGraph(api: api)
        let c = SyncCoordinator(steps: SlowUploadSteps(state: state, clock: clock, uploadDuration: .zero), clock: clock)
        let pull = Task { await state.pullToRefresh(coordinator: c) }
        pull.cancel()
        await pull.value
        await state.pullPhases?.value
        #expect(api.count("day") == 1 && api.count("days") == 1 && api.count("insights") == 1)
        #expect(state.refreshIssue == nil)
    }

    /// Offline the pull sends nothing and returns at once (the line says offline).
    @Test func offlineThePullSendsNothing() async {
        let api = MockPlatformAPI()
        let (_, state, clock) = readGraph(api: api, online: false)
        let c = SyncCoordinator(steps: SlowUploadSteps(state: state, clock: clock, uploadDuration: .zero), clock: clock)
        await state.pullToRefresh(coordinator: c)
        #expect(api.calls.isEmpty && state.pullPhases == nil)
    }

    /// After a push, a failed read is recorded per resource and the sync doesn't fail.
    @Test func aFailedReadAfterScoringDoesNotFailTheSync() async {
        let api = MockPlatformAPI()
        api.faults["days"] = .init(.timeout)
        api.faults["insights"] = .init(.unavailable)
        let (env, state, clock) = readGraph(api: api)
        let c = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: SyncService.ungated(env: env)), clock: clock)
        let outcome = await c.run(.silentPush(days: [DayFormat.string(from: clock.now())]))
        #expect(outcome.error == nil && !outcome.cancelled)
        #expect(env.reads.states[.history]?.consecutiveFailures == 1)
        #expect(env.reads.states[.insights]?.consecutiveFailures == 1)
        #expect(env.reads.states[.today]?.consecutiveFailures == 0)
    }
}

@Suite("Refresh policy")
struct RefreshPolicyTests {
    let now = Date(timeIntervalSince1970: 1_792_400_000)

    private func failing(_ n: Int, fetched hoursAgo: Double?, kind: FailureKind = .transient, status: Int? = 503)
        -> ResourceState {
        ResourceState(fetchedAt: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) },
                      lastError: ResourceError(kind: kind, status: status, code: nil, requestID: "rid", transport: nil,
                                               attempts: 3, at: now),
                      consecutiveFailures: n)
    }

    private func ok(_ hoursAgo: Double) -> ResourceState { ResourceState(fetchedAt: now.addingTimeInterval(-hoursAgo * 3600)) }

    /// Criterion 7 as a table: (states, online) → card resource, stale line.
    @Test func whenTheCardAndTheStaleLineShow() {
        typealias Row = (String, [ReadResource: ResourceState], Bool, ReadResource?, Bool)
        let rows: [Row] = [
            ("all fine", [.today: ok(0.1), .history: ok(1)], true, nil, false),
            ("3 failures under 2 h", [.today: failing(3, fetched: 1), .history: ok(1)], true, nil, false),
            ("1 failure past 2 h: stale line only", [.today: failing(1, fetched: 3), .history: ok(1)], true, nil, true),
            ("3 failures past 2 h", [.today: failing(3, fetched: 3), .history: ok(1)], true, .today, true),
            ("offline is never an error", [.today: failing(3, fetched: 3), .history: ok(1)], false, nil, false),
            ("history 3 failures under 24 h", [.today: ok(0.1), .history: failing(3, fetched: 20)], true, nil, false),
            ("history past 24 h", [.today: ok(0.1), .history: failing(3, fetched: 25)], true, .history, true),
            ("nothing cached: one pass", [.today: failing(1, fetched: nil), .history: failing(1, fetched: nil)],
             true, .today, false),
            ("other resources never", [.today: ok(0.1), .history: ok(1), .me: failing(9, fetched: 99)], true, nil, false),
            // Migrated from nothing: the store's history counts (AppState.resourceStates), so one failed
            // pass of today isn't "nothing cached"; three are, while today was never loaded.
            ("cache from before the record: one pass", [.today: failing(1, fetched: nil), .history: ok(2)],
             true, nil, false),
            ("cache from before the record: three passes", [.today: failing(3, fetched: nil), .history: ok(2)],
             true, .today, false),
            ("gates never", [.today: failing(3, fetched: 3, kind: .gate, status: 403), .history: ok(1)], true, nil, true),
            ("signed out at once", [.today: ok(0.1), .me: failing(1, fetched: 1, kind: .signedOut, status: 401)],
             true, .me, false),
        ]
        for (name, states, online, card, stale) in rows {
            let issue = RefreshPolicy.issue(for: states, now: now, online: online)
            #expect(issue?.resource == card, "\(name): \(String(describing: issue))")
            let since = RefreshPolicy.staleSince(for: states, now: now, online: online)
            #expect((since != nil) == stale, "\(name): staleSince \(String(describing: since))")
            if stale { #expect(since == states[.today]?.fetchedAt, "\(name)") }
        }
    }

    @Test func reasonsFollowTheClasses() {
        func reason(_ kind: FailureKind, _ status: Int?) -> RefreshIssue.Reason {
            RefreshIssue.reason(for: ResourceError(kind: kind, status: status, code: nil, requestID: nil, transport: nil,
                                                   attempts: 1, at: now))
        }
        #expect(reason(.transient, 503) == .busy && reason(.transient, 429) == .busy)
        #expect(reason(.transient, nil) == .unreachable)
        #expect(reason(.other, 404) == .unexpected)
        #expect(reason(.signedOut, 401) == .signedOut)
    }

    /// The status line: stale only when idle, after "Updating…"; "Try again" only without the card.
    @Test func theStaleLineShowsOnlyWhenIdle() {
        let since = now.addingTimeInterval(-3 * 3600)
        var f = TodaySyncFacts(now: now)
        f.syncs = false
        #expect(TodayStates.line(f, staleSince: since) == .stale(since: since))
        // The card is on screen (last on Today): the line points to it instead.
        #expect(TodayStates.line(f, staleSince: since, card: .today) == .issue(.today))
        #expect(TodayStates.line(f, card: .history) == .issue(.history))
        // A signed-out card: the line says so, whichever read found out.
        #expect(TodayStates.line(f, card: .me, signedOut: true) == .issue(.me, signedOut: true))
        #expect(SyncLine.issue(.me, signedOut: true).text(now: now) == String(localized: "You're signed out · Details"))
        f.isLoading = true
        #expect(TodayStates.line(f, staleSince: since) == .updating)
        f.isLoading = false
        f.online = false
        #expect(TodayStates.line(f, staleSince: since) == .offline)
    }

    @Test func theDataTimeIsNeverRelative() {
        let cal = Calendar.current
        let today = cal.date(bySettingHour: 14, minute: 5, second: 0, of: now)!
        let later = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
        #expect(SyncLine.dataTime(today, now: later) == Fmt.time(today))
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        #expect(SyncLine.dataTime(yesterday, now: later) == String(localized: "Yesterday \(Fmt.time(yesterday))"))
    }
}

@Suite("Read scheduler: waiters, stores, accounts")
@MainActor
struct ReadSchedulerWaiterTests {
    /// A fetch that answers `value` after `seconds` on the test clock, counting its calls.
    private func slowFetch(_ clock: TestClock, _ calls: Calls, seconds: Int = 1,
                           value: Int = 7) -> @MainActor () async throws -> Int {
        {
            calls.count += 1
            try await clock.sleep(for: .seconds(seconds))
            return value
        }
    }

    /// Code review blocker 3: a joiner cancelled mid-flight is released at once; the flight goes on.
    @Test func aCancelledJoinerStopsWaitingAtOnce() async throws {
        let (env, _, clock) = readGraph()
        let calls = Calls(), asked = Calls()
        let key = ReadKey(.trends, id: "readiness-7d")
        let owner = Task { try await env.reads.run(key, slowFetch(clock, calls)) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let joiner = Task { asked.count += 1; return try await env.reads.run(key, slowFetch(clock, calls)) }
        #expect(await eventually { asked.count == 1 })

        joiner.cancel()
        await #expect(throws: CancellationError.self) { try await joiner.value }   // the clock hasn't moved
        #expect(env.reads.inFlight == [key])

        clock.advance(by: .seconds(1))
        #expect(try await owner.value == 7)
        #expect(calls.count == 1)
    }

    /// The shape of onboarding's check (and the silent push's cut-off): a deadline that cancels the
    /// wait returns on time although the read is still in flight.
    @Test func aDeadlineIsMetWhileTheReadGoesOn() async {
        let (env, _, clock) = readGraph()
        let calls = Calls()
        let key = ReadKey(.me)
        let fetch = slowFetch(clock, calls, seconds: 60)
        let check = Task {
            await withTaskGroup(of: Int?.self) { group in
                group.addTask { try? await env.reads.run(key, fetch) }
                group.addTask {
                    try? await clock.sleep(for: .seconds(10))
                    return nil
                }
                let first = await group.next().flatMap { $0 }
                group.cancelAll()
                return first
            }
        }
        #expect(await eventually { clock.pendingSleeps == 2 })
        clock.advance(by: .seconds(10))
        #expect(await check.value == nil)                       // on time, not after 60 s
        #expect(env.reads.inFlight == [key])
        clock.advance(by: .seconds(50))
        #expect(await eventually { env.reads.inFlight.isEmpty })
    }

    /// The answer is stored inside the flight: its owner was cancelled, it still lands.
    @Test func theStoreRunsWhenTheOwnerIsCancelled() async {
        let (env, _, clock) = readGraph()
        let calls = Calls(), stored = Calls()
        let key = ReadKey(.trends, id: "readiness-7d")
        let owner = Task {
            try await env.reads.run(key, store: { (_: Int) in stored.count += 1 }, slowFetch(clock, calls))
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        owner.cancel()
        await #expect(throws: CancellationError.self) { try await owner.value }
        #expect(stored.isEmpty)

        clock.advance(by: .seconds(1))
        #expect(await eventually { stored.count == 1 })
        #expect(env.reads.states[.trends]?.fetchedAt == clock.now())
    }

    /// Onboarding's check starts `.me` without a store; `refreshUser` joins it: the user is stored.
    @Test func aJoinersStoreRunsOnAFlightStartedWithoutOne() async throws {
        let api = MockPlatformAPI()
        let (env, state, clock) = readGraph(api: api)
        #expect(state.user == nil)
        let check = Task {
            try await env.reads.run(ReadKey(.me)) { () async throws -> User in
                try await clock.sleep(for: .seconds(1))
                return try await api.me()
            }
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let asked = Calls()
        let refresh = Task { asked.count += 1; try await state.repository.refreshUser(mode: .latest) }
        #expect(await eventually { asked.count == 1 })

        clock.advance(by: .seconds(1))
        _ = try await check.value
        try await refresh.value
        #expect(state.user != nil)
        #expect(api.count("me") == 1)
    }

    /// Security should-fix 1: signed out (not demo), nothing is sent and nothing is recorded.
    @Test func signedOutSendsAndRecordsNothing() async throws {
        let api = MockPlatformAPI()
        let (env, state, _) = readGraph(api: api, auth: .preview(signedIn: false))
        try await state.repository.refreshInsights(mode: .latest)
        #expect(try await env.reads.run(ReadKey(.me)) { try await api.me() } == nil)
        #expect(api.calls.isEmpty && env.reads.states.isEmpty)
    }

    /// Session expiry, then a silent push while signed out, then signing in again: no "You're signed out".
    @Test func aSignInAfterAnExpiredSessionStartsClean() async {
        let api = MockPlatformAPI()
        let client = MockAuthClient(session: .preview())
        let (env, state, clock) = readGraph(api: api, auth: testAuth(client))
        api.faults["insights"] = .init(.status(401, retryAfter: nil))
        try? await state.repository.refreshInsights(mode: .latest)
        #expect(env.reads.states[.insights]?.lastError?.kind == .signedOut)
        await env.reads.savePending()
        let account = env.auth.accountID

        await env.auth.signOut(reason: .sessionExpired)
        state.accountChanged(from: account)
        let sent = api.calls.count
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: SyncService.ungated(env: env)), clock: clock)
        _ = await coordinator.run(.silentPush(days: [DayFormat.string(from: clock.now())]))
        #expect(api.calls.count == sent)                        // nothing went out signed out
        #expect(env.reads.states.isEmpty)

        await env.auth.signInWithApple(idToken: "token", nonce: "nonce", fullName: nil)
        state.accountChanged(from: nil)
        #expect(env.auth.accountID == account)
        #expect(env.reads.states[.insights]?.lastError == nil)
        #expect(state.refreshIssue == nil)
    }

    /// Should-fix 6: a cache from before the read record (the first launch of this build) isn't
    /// "never loaded": history's age comes from the store, and one failed pass of today shows no card.
    @Test func aCacheFromBeforeTheRecordCounts() async {
        let api = MockPlatformAPI()
        let (env, state, clock) = readGraph(api: api)
        let yesterday = DayFormat.string(from: DayFormat.shift(clock.now(), days: -1))
        state.repository.store(scores: [DailyScore(day: yesterday)])
        #expect(env.reads.states[.history] == nil)
        #expect(state.resourceStates[.history]?.fetchedAt == clock.now())

        api.faults["day"] = .init(.status(404, retryAfter: nil))
        _ = try? await state.repository.refreshDay(clock.now(), mode: .latest)
        #expect(env.reads.states[.today]?.consecutiveFailures == 1)
        #expect(state.refreshIssue == nil)
    }

    /// Should-fix 5: a reset (sign-out, another account) stops the pull's phase 3.
    @Test func aResetStopsThePullsRest() async {
        let api = MockPlatformAPI()
        let (_, state, clock) = readGraph(api: api)
        let c = SyncCoordinator(steps: SlowUploadSteps(state: state, clock: clock, uploadDuration: .seconds(10)),
                                clock: clock)
        await state.pullToRefresh(coordinator: c)
        state.reset()
        clock.advance(by: .seconds(2))
        await state.pullPhases?.value
        #expect(api.count("days") + api.count("me") + api.count("trends") + api.count("insights") == 0)
        clock.advance(by: .seconds(8))
    }
}

@Suite("Request budget: rate-limit hold-back")
@MainActor
struct RequestBudgetHoldBackTests {
    /// Security nit 4: after a `429`, no start before its `Retry-After`, whatever its priority.
    @Test func a429HoldsEveryStartBack() async {
        let clock = TestClock()
        let budget = RequestBudget(clock: clock)
        await budget.holdBack(seconds: 3)
        let admitted = Calls()
        Task {
            guard (try? await budget.acquire(.high)) != nil else { return }
            admitted.count += 1
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .milliseconds(2_999))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(admitted.isEmpty)
        clock.advance(by: .milliseconds(1))
        #expect(await eventually { admitted.count == 1 })
    }

    /// At most `maxHoldBack`; a shorter one never shortens a longer hold.
    @Test func theHoldBackIsCappedAndOnlyExtends() async {
        let clock = TestClock()
        let budget = RequestBudget(clock: clock)
        await budget.holdBack(seconds: 600)
        #expect(await budget.notBefore == clock.now().addingTimeInterval(RequestBudget.maxHoldBack.timeInterval))
        await budget.holdBack(seconds: 2)
        #expect(await budget.notBefore == clock.now().addingTimeInterval(RequestBudget.maxHoldBack.timeInterval))
    }

    /// A `429` on one resource holds the next read of another back, a pull's included.
    @Test func a429OnOneResourceHoldsTheOthers() async {
        let api = MockPlatformAPI()
        api.faults["me"] = .init(.status(429, retryAfter: 4), times: 1)
        let (_, state, clock) = readGraph(api: api)
        let me = Task { try? await state.repository.refreshUser(mode: .latest) }
        #expect(await eventually { api.count("me") == 1 && clock.pendingSleeps == 1 })   // me's retry waits 4 s
        let today = Task { _ = try? await state.repository.refreshDay(clock.now(), mode: .latest, userInitiated: true) }
        #expect(await eventually { clock.pendingSleeps == 2 })
        #expect(api.count("day") == 0)
        clock.advance(by: .seconds(4))
        await today.value
        await me.value
        #expect(api.count("day") == 1 && api.count("me") == 2)
    }
}

@Suite("Details sheet")
@MainActor
struct RefreshDetailsSheetTests {
    /// ui-validator 11c: the time follows the screen's locale (German: 24-hour), not a fixed one.
    @Test func theTimeFollowsTheScreensLocale() {
        let at = Calendar.current.date(bySettingHour: 14, minute: 7, second: 12, of: .now)!
        #expect(RefreshDetailsSheet.time(at, locale: Locale(identifier: "de_DE")) == "14:07:12")
        #expect(RefreshDetailsSheet.time(at, locale: Locale(identifier: "en_US")).contains("PM"))
    }

    private let failedAt = Date(timeIntervalSince1970: 1_792_400_000)

    private func issue(_ resource: ReadResource = .today, kind: FailureKind = .transient, status: Int? = 503,
                       code: String? = nil, requestID: String? = "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c",
                       transport: String? = nil, failures: Int = 3, dataFrom: Date? = nil) -> RefreshIssue {
        let error = ResourceError(kind: kind, status: status, code: code, requestID: requestID, transport: transport,
                                  attempts: 3, at: failedAt)
        return RefreshIssue(reason: RefreshIssue.reason(for: error), resource: resource, dataFrom: dataFrom,
                            failures: failures, error: error)
    }

    /// Criterion 9: one plain sentence and symbol per class (ui.md §3.3), and they differ.
    @Test(arguments: [
        (RefreshIssue.Reason.busy, "RYFT is busy right now. Your data is safe; try again in a moment.",
         "clock.arrow.circlepath"),
        (.unreachable, "RYFT can't be reached right now. Your connection looks fine, so this isn't on your side.",
         "wifi.exclamationmark"),
        (.unexpected, "Part of your data couldn't be loaded. The details help us find out why.",
         "exclamationmark.circle"),
        (.signedOut, "You're signed out, so new data can't load.", "person.crop.circle.badge.exclamationmark"),
        (.appTooOld, "This version of RYFT is too old to load new data. Update it to continue.", "arrow.down.app"),
    ])
    func theReasonSaysWhatHappenedPerClass(reason: RefreshIssue.Reason, english: String, symbol: String) {
        #expect(reason.message == String(localized: String.LocalizationValue(english)))
        #expect(reason.systemImage == symbol)
    }

    /// Criterion 9: the sheet's rows come from the issue: resource, status, code, request ID.
    @Test func theRowsComeFromTheIssue() {
        let sheet = issue(.history, status: 503, code: "consent_required")
        #expect(sheet.resourceName == ReadResource.history.displayName)
        #expect(sheet.statusText == "503")
        #expect(sheet.error.code == "consent_required")
        #expect(sheet.error.requestID == "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c") // exactly as received
        #expect(issue(.today).resourceName == ReadResource.today.displayName)
        // A resource without a display name still says what failed.
        #expect(issue(.day).resourceName == ReadResource.day.rawValue)
        // No response: no status (the sheet shows "—" and "No response").
        #expect(issue(status: nil, transport: "timedOut").statusText == nil)
    }

    /// Copy details: every row, the ID unshortened, "—" for what's missing, no health values.
    @Test func copyDetailsListsEveryRow() {
        let dataFrom = failedAt.addingTimeInterval(-3 * 3600)
        let text = issue(code: "consent_required", dataFrom: dataFrom).copyText
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.contains(String(localized: "What failed") + ": " + (ReadResource.today.displayName ?? "")))
        #expect(lines.contains(String(localized: "HTTP status") + ": 503"))
        #expect(lines.contains(String(localized: "Code") + ": consent_required"))
        #expect(lines.contains(String(localized: "Request ID") + ": 01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c"))
        #expect(lines.contains(String(localized: "Time") + ": " + failedAt.ISO8601Format()))
        #expect(lines.contains(String(localized: "Showing data from") + ": " + dataFrom.ISO8601Format()))
        #expect(lines.contains(String(localized: "Failed in a row") + ": 3"))

        let bare = issue(status: nil, requestID: nil, transport: "timedOut").copyText
        #expect(bare.contains(String(localized: "Request ID") + ": " + String(localized: "Not available")))
        #expect(bare.contains(String(localized: "HTTP status") + ": — (timedOut)"))
        #expect(bare.contains(String(localized: "Code") + ": —"))
        #expect(bare.contains(String(localized: "Showing data from") + ": —"))
    }

    /// The line's wording per resource ("Couldn't load today · Details") and the age in the card.
    @Test func theLinePointsToTheCardByName() {
        #expect(SyncLine.issue(.today).text(now: failedAt) == String(localized: "Couldn't load today · Details"))
        #expect(SyncLine.issue(.history).text(now: failedAt) == String(localized: "Couldn't load your history · Details"))
        #expect(SyncLine.issue(.me).text(now: failedAt) == String(localized: "Couldn't load your data · Details"))
    }

    /// The line's "Hold": 600 ms per step. The hold itself is `SyncStatusLineView` state (`Task.sleep` and
    /// `Date.now`, not `AppClock`), so only its constant is unit-testable; the UI test covers the progression.
    @Test func eachLineStepIsHeldSixHundredMilliseconds() {
        #expect(SyncStatusLineView.minimumShown == 0.6)
    }
}

/// Set from an observation callback (any thread).
private final class Tripped: @unchecked Sendable {
    private let lock = NSLock()
    private var tripped = false
    var value: Bool { lock.withLock { tripped } }
    func trip() { lock.withLock { tripped = true } }
}

/// A silent push whose refresh never ends on its own (the days take 60 s on the clock).
@MainActor
private final class HangingRefreshSteps: SyncSteps {
    let clock: TestClock
    private(set) var reported: [SyncPhase] = []

    init(clock: TestClock) {
        self.clock = clock
    }

    func upload() async throws -> [String] { [] }
    var hasBacklog: Bool { false }
    var isWaitingForUnlock: Bool { false }
    var isUploading: Bool { false }
    func stopAfterCurrentPage() async {}
    var expectedScoringSeconds: Int? { nil }
    func syncStatus() async throws -> SyncStatus { throw ReadScheduler.NotSent() }
    func refreshDays(_ days: [String]) async throws { try await clock.sleep(for: .seconds(60)) }
    func refreshTrends() async throws {}
    func refreshInsights() async throws {}
    func refreshStale() async {}
    func report(_ phase: SyncPhase) { reported.append(phase) }
}

@Suite("Refresh: final review (observation, limits, background)")
@MainActor
struct RefreshFinalReviewTests {
    /// Perf 1: Today observes `isLoading` and `refreshInputs`. A config read (like a journal's or
    /// Train's) changes neither; a read of today does.
    @Test func onlyTodaysReadsInvalidateWhatTodayObserves() async throws {
        let api = MockPlatformAPI()
        let (env, state, clock) = readGraph(api: api)
        await state.refresh(force: true)
        let tripped = Tripped()
        withObservationTracking {
            _ = state.isLoading
            _ = state.refreshInputs
        } onChange: { tripped.trip() }
        _ = try await env.reads.run(ReadKey(.config)) { try await api.config() }
        #expect(!tripped.value)

        _ = try await state.repository.refreshDay(clock.now(), mode: .latest)
        #expect(tripped.value)
    }

    /// Perf 2: Today's card and line read the stored inputs (no SwiftData in `body`), and they match
    /// what the full record says.
    @Test func theStoredInputsMatchTheRecord() async {
        let api = MockPlatformAPI()
        api.faults["day"] = .init(.status(503, retryAfter: nil))
        let (_, state, clock) = readGraph(api: api)
        for _ in 0..<3 { _ = try? await state.repository.refreshDay(clock.now(), mode: .latest) }
        #expect(state.refreshInputs == RefreshPolicy.inputs(state.resourceStates))
        #expect(state.refreshIssue?.resource == .today)          // nothing cached: the card
    }

    /// Perf 4: in the background a timed-out request isn't tried again; a 503 still is.
    @Test func theBackgroundDoesntRetryATimeout() {
        let top: (ClosedRange<Double>) -> Double = { $0.upperBound }
        let timeout = APIError.transport(URLError(.timedOut))
        #expect(RetryPolicy.background.delay(before: 1, after: timeout, random: top) == nil)
        #expect(RetryPolicy.background.delay(before: 1, after: URLError(.timedOut), random: top) == nil)
        #expect(RetryPolicy.foreground.delay(before: 1, after: timeout, random: top) != nil)
        #expect(RetryPolicy.background.delay(before: 1, after: APIError.http(503, ""), random: top) != nil)
    }

    /// Perf 4: a silent push's refresh gives up after 20 s (iOS allows ~30 s), as a cancellation.
    @Test(.timeLimit(.minutes(1))) func aSilentPushRefreshGivesUpAfterTwentySeconds() async {
        let clock = TestClock()
        let steps = HangingRefreshSteps(clock: clock)
        let coordinator = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await coordinator.run(.silentPush(days: ["2026-10-21"])) }
        #expect(await eventually { clock.pendingSleeps == 2 })  // the days, the deadline
        clock.advance(by: .seconds(19))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(steps.reported.last == .refreshing)
        clock.advance(by: .seconds(1))
        let outcome = await run.value
        #expect(outcome.cancelled && outcome.error == nil)
        #expect(steps.reported.last == .idle)                   // not "sync paused"
    }

    /// Security low: the 429's hold is set with the slot's release, so the read parked behind it waits.
    @Test func aHoldSetWithTheReleaseHoldsTheParkedRead() async throws {
        let clock = TestClock()
        let budget = RequestBudget(clock: clock, maxInFlight: 1)
        try await budget.acquire(.normal)
        let admitted = Calls()
        Task {
            guard (try? await budget.acquire(.normal)) != nil else { return }
            admitted.count += 1
        }
        let deadline = ContinuousClock.now + .seconds(30)
        while await budget.waiting != 1, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }

        await budget.release(holdBack: 3)
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(admitted.isEmpty)
        clock.advance(by: .seconds(3))
        #expect(await eventually { admitted.count == 1 })
    }

    /// Review 11: a hold longer than the read may wait fails at once (and leaves the queue).
    @Test func aLongHoldFailsAtOnce() async {
        let clock = TestClock()
        let budget = RequestBudget(clock: clock)
        await budget.holdBack(seconds: 20)
        await #expect(throws: RequestBudget.HeldBack(seconds: 20)) {
            try await budget.acquire(.high, maxHold: .seconds(5))
        }
        #expect(await budget.waiting == 0)
        #expect(await budget.inFlight == 0)
    }

    /// Nit: a caller that's already cancelled doesn't start a flight.
    @Test func aCancelledCallerStartsNoFlight() async {
        let (env, _, _) = readGraph()
        let calls = Calls()
        let caller = Task { () async throws -> Int? in
            try await env.reads.run(ReadKey(.config)) {
                calls.count += 1
                return 1
            }
        }
        caller.cancel()
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(calls.isEmpty && env.reads.inFlight.isEmpty)
    }
}

@Suite("Refresh: what a pull invalidates on Today")
@MainActor
struct PullInvalidationTests {
    /// Perf 1 as a number. Before, Today's `body` read the scheduler's `states` and `inFlight` and the
    /// store's days, so every one of these events invalidated it. Now it reads `isLoading` and
    /// `refreshInputs`, which change only when what Today shows could change.
    @Test func aPullChangesWhatTodayObservesAFewTimes() async {
        let api = MockPlatformAPI()
        let (env, state, clock) = readGraph(api: api)
        await state.refresh(force: true)
        let events = Calls(), published = Calls()
        func counting(_ body: () -> Void) {
            let before = (state.isLoading, state.refreshInputs)
            body()
            events.count += 1
            if state.isLoading != before.0 || state.refreshInputs != before.1 { published.count += 1 }
        }
        let reads = env.reads.onChange, days = state.repository.onDaysChanged
        env.reads.onChange = { change in counting { reads?(change) } }
        state.repository.onDaysChanged = { counting { days?() } }

        let c = SyncCoordinator(steps: SlowUploadSteps(state: state, clock: clock, uploadDuration: .zero), clock: clock)
        await state.pullToRefresh(coordinator: c)
        await state.pullPhases?.value

        // 6 reads (today, sync status, history, me, trends, insights): start and land each, plus the stores.
        #expect(events.count >= 12, "events \(events.count)")
        // Measured 2026-10-22: 14 events (plus 6 writes of `states`, also observed before), 4 changes now.
        #expect(published.count <= 4, "published \(published.count) of \(events.count)")
    }
}

@Suite("Refresh: the record is saved before the app may be suspended")
@MainActor
struct ReadRecordSuspensionTests {
    /// Review B: what failed during a silent push is saved before its completion handler (iOS may
    /// suspend or kill the app right after); the coalesced save would come 1.5 s later.
    @Test func aSilentPushSavesTheRecordBeforeItEnds() async {
        let api = MockPlatformAPI()
        api.faults["insights"] = .init(.status(503, retryAfter: nil))
        let (env, state, clock) = readGraph(api: api)
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: SyncService.ungated(env: env)), clock: clock)
        let router = DeepLinkRouter(state: state, sleep: SleepViewModel(state: state),
                                    strain: StrainViewModel(state: state, store: TrainStore(inMemory: true)),
                                    insights: InsightsViewModel(state: state))
        let handlers = PushHandlers(registrar: PushRegistrar(env: env), router: router, coordinator: coordinator,
                                    reads: env.reads)
        _ = await AppDelegate.refresh(day: DayFormat.string(from: clock.now()), handlers: handlers)
        #expect(ReadScheduler(env: env).states[.insights]?.consecutiveFailures == 1)
    }

    /// Nothing waiting: nothing is written.
    @Test func savingNowWithoutAPendingSaveWritesNothing() async {
        let (env, _, _) = readGraph()
        env.reads.savePendingNow()
        #expect((env.persistence as? TrainStore)?.documentFetchedAt(key: ReadScheduler.documentKey) == nil)
    }
}

/// `.daysChanged` (A2: an activity or a night the platform confirmed; the training import's I5 too).
@Suite("Sync coordinator: days changed elsewhere")
@MainActor
struct SyncCoordinatorDaysChangedTests {
    @Test func itSkipsTheUploadWaitsForScoringThenRefreshes() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.daysChanged(days: ["2026-10-17"])) }
        #expect(await eventually { clock.pendingSleeps == 1 }) // the scoring wait, before any ask
        #expect(steps.events.isEmpty)
        clock.advance(by: .seconds(10))
        let outcome = await run.value
        #expect(Array(steps.events.prefix(2)) == ["poll", "days:2026-10-17"])
        #expect(!steps.events.contains("upload"))
        #expect(outcome.touched == ["2026-10-17"] && outcome.polls == 1 && outcome.attempts == 0)
        #expect(steps.phases.contains(.awaitingScores))
        #expect(SyncCoordinator.Trigger.daysChanged(days: []).priority == .utility)
    }

    @Test func inTheBackgroundItLeavesTheRefreshToThePush() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        let outcome = await SyncCoordinator(steps: steps, clock: clock, inBackground: true)
            .run(.daysChanged(days: ["2026-10-17"]))
        #expect(steps.events.isEmpty && outcome.polls == 0 && !outcome.cancelled)
        #expect(steps.phases.last == .done)
    }

    @Test func aPushForItsDayEndsTheWait() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = []
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.daysChanged(days: ["2026-10-17"])) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let pushed = await c.run(.silentPush(days: ["2026-10-17"]))
        let outcome = await run.value
        #expect(pushed == outcome && outcome.polls == 0)
        #expect(steps.events.first == "days:2026-10-17" && !steps.events.contains("poll"))
    }

    @Test func itCoalescesWithAPushIntoOneWaitForAllTheDays() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = [true, true]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let first = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let push = Task { await c.run(.silentPush(days: ["2026-10-15"])) }
        #expect(await queued(c, .silentPush(days: ["2026-10-15"])))
        let changed = Task { await c.run(.daysChanged(days: ["2026-10-16"])) }
        #expect(await queued(c, .daysChanged(days: ["2026-10-15", "2026-10-16"])))
        clock.advance(by: .seconds(10))
        _ = await first.value
        // The rerun: no upload, one wait, then both days.
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        let rerun = await changed.value
        #expect(await push.value == rerun)
        #expect(rerun.touched == ["2026-10-15", "2026-10-16"] && rerun.polls == 1)
        #expect(steps.count("upload") == 1)
        #expect(steps.events.contains("days:2026-10-15,2026-10-16"))
    }

    @Test func behindAnUploadTriggerItsDaysRideAlong() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = [true, true]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let first = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        let changed = Task { await c.run(.daysChanged(days: ["2026-10-15"])) }
        #expect(await queued(c, .daysChanged(days: ["2026-10-15"])))
        let delivery = Task { await c.run(.healthKit) } // an upload trigger wins the merge
        #expect(await queued(c, .healthKit))
        clock.advance(by: .seconds(10))
        _ = await first.value
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(10))
        let rerun = await delivery.value
        #expect(await changed.value == rerun)
        #expect(steps.count("upload") == 2)
        #expect(rerun.touched == ["2026-10-19", "2026-10-15"]) // uploaded, then the activity's day
        #expect(steps.events.last { $0.hasPrefix("days:") } == "days:2026-10-19,2026-10-15")
    }

    /// Polls the coordinator until its rerun's trigger is `trigger` (a task's call has reached the actor).
    private func queued(_ c: SyncCoordinator, _ trigger: SyncCoordinator.Trigger) async -> Bool {
        for _ in 0..<10_000 {
            if await c.queuedRunTrigger == trigger { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}
