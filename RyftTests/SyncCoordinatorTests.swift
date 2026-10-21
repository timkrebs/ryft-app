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
    /// `isScored` answers per poll.
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

    func isScored(_ days: [String], since: Date) async throws -> Bool {
        events.append("poll")
        return scored.isEmpty ? false : scored.removeFirst()
    }

    func refreshDays(_ days: [String]) async throws { events.append("days:\(days.joined(separator: ","))") }
    func refreshTrends() async throws { events.append("trends") }
    func refreshInsights() async throws { events.append("insights") }
    func refreshStale() async { events.append("stale") }
    private(set) var phases: [SyncPhase] = []
    func report(_ phase: SyncPhase) { phases.append(phase) }

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
        clock.advance(by: SyncCoordinator.firstPollDelay)
        let outcome = await run.value

        #expect(outcome.touched == ["2026-10-19"] && outcome.polls == 1 && outcome.error == nil)
        #expect(Array(steps.events.prefix(3)) == ["upload", "poll", "days:2026-10-19"])
        #expect(Set(steps.events.suffix(2)) == ["trends", "insights"]) // in parallel, after the days
    }

    @Test func nothingUploadedOnlyRefreshesWhatsStale() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        let outcome = await SyncCoordinator(steps: steps, clock: clock).run(.appActive)
        #expect(steps.events == ["upload", "stale"])
        #expect(outcome.polls == 0)
    }

    @Test func pollsForScoringAtMostThreeTimesWithGrowingWaits() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = [false, false, false]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }

        for wait in [3, 6, 12] {
            #expect(await eventually { clock.pendingSleeps == 1 })
            clock.advance(by: .seconds(wait))
        }
        let outcome = await run.value
        #expect(outcome.polls == SyncCoordinator.maxPolls)
        #expect(steps.count("poll") == 3)
        #expect(steps.events.contains("days:2026-10-19")) // refreshed anyway
    }

    @Test func scoredOnTheSecondPollStopsPolling() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = [false, true]
        let c = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await c.run(.appActive) }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(3))
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(6))
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
        clock.advance(by: SyncCoordinator.firstPollDelay)
        let first = await run.value
        #expect(first.backlog)
        #expect(steps.events.contains("days:2026-10-19")) // the first score refreshed…

        #expect(await eventually { steps.count("upload") == 2 }) // …then the backlog uploads
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: SyncCoordinator.firstPollDelay)
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
        clock.advance(by: SyncCoordinator.firstPollDelay)
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
        clock.advance(by: SyncCoordinator.firstPollDelay)
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
        #expect(await eventually { steps.isUploading })

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
        clock.advance(by: SyncCoordinator.firstPollDelay)
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
        clock.advance(by: SyncCoordinator.firstPollDelay)
        _ = await run.value
        #expect(await eventually { steps.count("upload") == 2 }) // the queued rerun uploads the rest
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: SyncCoordinator.firstPollDelay)
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
        clock.advance(by: .seconds(3))
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
        #expect(await eventually { steps.isUploading })
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
        #expect(await eventually { steps.count("upload") == 2 && steps.isUploading }) // B uploads
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
