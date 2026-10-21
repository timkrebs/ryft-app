import Foundation
import Testing
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
    private(set) var events: [String] = []

    init(clock: TestClock) { self.clock = clock }

    func upload() async throws -> [String] {
        events.append("upload")
        if uploadDuration > .zero { try await clock.sleep(for: uploadDuration) }
        if !uploadFailures.isEmpty { throw uploadFailures.removeFirst() }
        hasBacklog = backlogs.isEmpty ? false : backlogs.removeFirst()
        return touched
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
        let run = Task { await c.run(.background) }

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
        let run = Task { await c.run(.background) }
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
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await !c.isRunning)
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
