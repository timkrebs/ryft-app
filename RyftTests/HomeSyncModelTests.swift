import Foundation
import Testing
@testable import Ryft

@Suite("Home sync")
@MainActor
struct HomeSyncModelTests {
    private func graph(clock: TestClock, steps: FakeSteps) -> (HomeSyncModel, AppState, AnalyticsRig) {
        let analytics = AnalyticsRig()
        analytics.optIn()
        let env = AppEnvironment.test(clock: clock)
        env.analytics = analytics.analytics
        let app = AppState(env: env)
        let coordinator = SyncCoordinator(steps: steps, clock: clock)
        return (HomeSyncModel(state: app, sync: SyncService.ungated(env: env), coordinator: coordinator), app, analytics)
    }

    @Test func quietForegroundUsesStatusOnlyUntilFiveMinutesHavePassed() async {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        let (model, app, analytics) = graph(clock: clock, steps: steps)
        app.env.settings.lastSync = clock.now().addingTimeInterval(-299)

        await model.enterForeground()
        #expect(steps.count("upload") == 0)
        #expect(steps.count("poll") == 1)
        #expect(analytics.sink.captures.isEmpty)

        clock.advance(by: .seconds(2))
        await model.enterForeground()
        #expect(steps.count("upload") == 1)
        #expect(analytics.sink.captures.map(\.name) == ["sync_triggered", "sync_completed"])
        #expect(analytics.sink.captures.map { $0.properties["trigger_source"] } == ["auto_foreground", "auto_foreground"])
    }

    @Test func secondTapJoinsAndRecordsOnlyTheOriginalTrigger() async throws {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.touched = []
        steps.uploadDuration = .seconds(2)
        let (model, app, analytics) = graph(clock: clock, steps: steps)
        app.syncStatus = try Fixture.decode(SyncStatus.self, "me_sync_unknown")
        #expect(model.sources.map(\.source) == ["healthkit", "garmin"])

        let first = Task { await model.sync(trigger: .homescreenTopRight) }
        try #require(await eventually { steps.isUploading })
        var secondAsked = false
        let second = Task {
            secondAsked = true
            return await model.sync(trigger: .profileButton)
        }
        try #require(await eventually { secondAsked })
        clock.advance(by: .seconds(2))
        try #require(await eventually { analytics.sink.captures.count == 2 })
        #expect(await first.value == .success)
        #expect(await second.value == .success)
        #expect(steps.count("upload") == 1)
        #expect(analytics.sink.captures[0] == .init(name: "sync_triggered", properties: [
            "trigger_source": "homescreen_top_right", "previous_state": "error",
        ]))
        let completed = analytics.sink.captures[1]
        #expect(completed.name == "sync_completed")
        #expect(completed.properties["connected_providers_count"] == "2+")
        #expect(completed.properties["trigger_source"] == "homescreen_top_right")
        #expect(completed.properties["status"] == "success")
        #expect(analytics.refusals.isEmpty)
    }

    @Test(arguments: [3, 20])
    func pollsAtTheFixedIntervalAndStopsAtThreeMinutes(expected: Int) async throws {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = []
        steps.expectedScoringSeconds = expected
        let coordinator = SyncCoordinator(steps: steps, clock: clock)
        let run = Task { await coordinator.runHomeSync(.userInitiated, afterUpload: {}) }
        try #require(await eventually { clock.pendingSleeps == 1 })

        let interval = max(expected, 10)
        clock.advance(by: .seconds(interval - 1))
        #expect(steps.statusRequestTimes.isEmpty)
        clock.advance(by: .seconds(1))
        let polls = Array(stride(from: interval, to: 180, by: interval))
        for (index, second) in polls.enumerated() {
            if index > 0 { clock.advance(by: .seconds(interval)) }
            try #require(await eventually { steps.statusRequestTimes.count == index + 1 && clock.pendingSleeps == 1 })
            #expect(steps.statusRequestTimes.last == .seconds(second))
        }
        clock.advance(by: .seconds(180 - (polls.last ?? 0)))
        try #require(await eventually { steps.phases.last == .done })
        #expect(await run.value.scoringTimedOut)
        #expect(steps.count("home-reload") == 0)
        #expect(steps.statusRequestTimes == polls.map { .seconds($0) })

        steps.scored = [true]
        await coordinator.refreshHomeStatus()
        #expect(steps.statusRequestTimes.last == .seconds(180))
        #expect(steps.count("home-reload") == 1)
    }

    @Test func aTimedOutRunReportsPartial() async throws {
        let clock = TestClock()
        let steps = FakeSteps(clock: clock)
        steps.scored = []
        steps.expectedScoringSeconds = 180
        let (model, _, analytics) = graph(clock: clock, steps: steps)
        var spinnerEnded = false
        let pull = Task {
            await model.sync(trigger: .homescreenPullToRefresh)
            spinnerEnded = true
        }
        try #require(await eventually { steps.phases.contains(.awaitingScores) && clock.pendingSleeps > 0 })
        clock.advance(by: .seconds(3))
        try #require(await eventually { spinnerEnded })
        await pull.value
        #expect(analytics.sink.captures.map(\.name) == ["sync_triggered"])
        clock.advance(by: .seconds(177))
        try #require(await eventually { analytics.sink.captures.count == 2 })
        #expect(analytics.sink.captures.last?.properties["status"] == "partial")
        #expect(analytics.sink.captures.last?.properties["trigger_source"] == "homescreen_pull_to_refresh")
        #expect(steps.statusRequestTimes.isEmpty)
    }

    @Test func currentStatusMustBeLateEnoughAndTodayAndTheActiveBriefingMustReload() async throws {
        let current = try Fixture.decode(SyncStatus.self, "me_sync_current")
        let uploadedAt = try #require(current.lastSyncAt)
        let clock = TestClock(now: uploadedAt)
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, clock: clock)
        let app = AppState(env: env)
        var briefings = 0
        app.activeNutritionBriefing = (UUID(), {
            briefings += 1
            return briefings == 2
        })

        app.setSyncStatus(current, askedAt: clock.now())
        await app.reloadTodayAfterCurrent(uploadedAt: uploadedAt)
        #expect(api.count("day") == 0 && briefings == 0 && app.syncTodayReloadedAt == nil)

        clock.advance(by: .seconds(10))
        app.setSyncStatus(current, askedAt: clock.now())
        await app.reloadTodayAfterCurrent(uploadedAt: uploadedAt)
        #expect(api.count("day") == 1 && briefings == 1 && app.syncTodayReloadedAt == nil)
        await app.reloadTodayAfterCurrent(uploadedAt: uploadedAt)
        #expect(api.count("day") == 2 && briefings == 2 && app.syncTodayReloadedAt == clock.now())
    }
}
