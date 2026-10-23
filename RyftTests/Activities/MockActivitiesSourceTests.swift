import Foundation
import Testing
@testable import Ryft

/// The in-memory platform for activities (design.md §4.4): demo, previews and tests run on it until C1.
@Suite("Activities: the in-memory platform")
struct MockActivitiesSourceTests {
    private static func run(_ id: UUID = UUID(), start: Date, minutes: Double = 45, route: Bool = false) -> SportActivity {
        SportActivity(id: id, sport: .running, origin: .recorded, start: start,
                      end: start.addingTimeInterval(minutes * 60), movingSec: minutes * 60 - 60, distanceM: 8_000,
                      perceivedEffort: 6, notes: "Tempo", route: route ? "_p~iF~ps|U_ulLnnqC" : nil,
                      hrSamples: route ? [HRPoint(t: start, bpm: 120)] : nil, clientUpdatedAt: start,
                      strain: 99, strainSource: .noSource, mergedWith: UUID(), scoringState: "made-up")
    }

    @Test func aPutIsPendingThenAGetIsScored() async throws {
        let clock = TestClock()
        let source = MockActivitiesSource(now: { clock.now() }, scoreDelay: 15)
        let start = clock.now().addingTimeInterval(-3_600)
        let sent = Self.run(start: start, route: true)
        let answer = try await source.putActivity(sent)
        // The platform received the PUT body: none of the fields it sets itself.
        let received = try #require(source.puts.first)
        #expect(received.strain == nil && received.strainSource == nil && received.mergedWith == nil)
        #expect(received.scoringState == nil && received.route == sent.route && received.hrSamples == sent.hrSamples)
        // The answer: pending, without route and samples (R16).
        #expect(answer.id == sent.id && answer.scoringState == "pending" && answer.strain == nil)
        #expect(answer.route == nil && answer.hrSamples == nil)

        let day = (from: start.addingTimeInterval(-60), to: start.addingTimeInterval(86_400))
        let pending = try await source.activities(from: day.from, to: day.to)
        #expect(pending.map(\.id) == [sent.id] && pending.first?.scoringState == "pending")
        clock.advance(by: .seconds(15))
        let scored = try #require(try await source.activities(from: day.from, to: day.to).first)
        #expect(scored.scoringState == "scored" && scored.strain == 9.4 && scored.strainSource == .heartRate)
        #expect(scored.route == nil && scored.hrSamples == nil)
        // The detail read carries the route.
        let detail = try await source.activity(id: sent.id)
        #expect(detail.route == sent.route && detail.strain == 9.4)
    }

    @Test func aPutIsIdempotentByID() async throws {
        let clock = TestClock()
        let source = MockActivitiesSource(now: { clock.now() })
        let start = clock.now().addingTimeInterval(-3_600)
        var a = Self.run(start: start)
        _ = try await source.putActivity(a)
        a.notes = "Edited"
        _ = try await source.putActivity(a)
        let all = try await source.activities(from: .distantPast, to: .distantFuture)
        #expect(all.count == 1 && all.first?.notes == "Edited" && source.puts.count == 2)
    }

    @Test func theListIsTheRangeInStartOrder() async throws {
        let clock = TestClock()
        let source = MockActivitiesSource(now: { clock.now() })
        let now = clock.now()
        let late = try await source.putActivity(Self.run(start: now.addingTimeInterval(-2 * 3_600)))
        let early = try await source.putActivity(Self.run(start: now.addingTimeInterval(-5 * 3_600)))
        _ = try await source.putActivity(Self.run(start: now.addingTimeInterval(-30 * 3_600)))
        let list = try await source.activities(from: now.addingTimeInterval(-6 * 3_600), to: now)
        #expect(list.map(\.id) == [early.id, late.id])
    }

    @Test func thePlatformsRulesAnswer422() async throws {
        let clock = TestClock()
        let source = MockActivitiesSource(now: { clock.now() })
        let now = clock.now()
        var future = Self.run(start: now.addingTimeInterval(-600))
        future.end = now.addingTimeInterval(600)
        var backwards = Self.run(start: now.addingTimeInterval(-600))
        backwards.end = backwards.start
        var tooLong = Self.run(start: now.addingTimeInterval(-30 * 3_600))
        tooLong.end = now
        var effort = Self.run(start: now.addingTimeInterval(-3_600))
        effort.perceivedEffort = 11
        for bad in [future, backwards, tooLong, effort] {
            await #expect(throws: APIError.self) { try await source.putActivity(bad) }
        }
        #expect(source.puts.isEmpty)
    }

    @Test func deletesAndManualSleep() async throws {
        let clock = TestClock()
        let source = MockActivitiesSource(now: { clock.now() })
        let a = try await source.putActivity(Self.run(start: clock.now().addingTimeInterval(-3_600)))
        try await source.deleteActivity(id: a.id)
        #expect(source.deletes == [a.id])
        await #expect(throws: APIError.self) { try await source.deleteActivity(id: a.id) }
        await #expect(throws: APIError.self) { try await source.activity(id: a.id) }

        let wake = clock.now().addingTimeInterval(-3_600)
        let body = ManualSleepPut(bed: wake.addingTimeInterval(-8 * 3_600), wake: wake)
        try await source.putManualSleep(day: "2026-10-19", body)
        #expect(source.manualSleep(day: "2026-10-19") == body)
        try await source.deleteManualSleep(day: "2026-10-19")
        #expect(source.manualSleep(day: "2026-10-19") == nil)
        await #expect(throws: APIError.self) {
            try await source.putManualSleep(day: "2026-10-19", ManualSleepPut(bed: wake, wake: wake))
        }
    }

    /// Demo data: one RYFT run merged with today's mock tracker run, already scored.
    @Test func theDemoRunIsMergedWithTodaysTrackerRun() async throws {
        // One instant for MockData's today and the platform's (no midnight between two `.now`s).
        let clock = TestClock(now: Date())
        let workout = try #require(MockData.detail(for: clock.now()).workouts.first { $0.activity == "running" })
        let api = MockPlatformAPI(activities: .demoSource())
        api.now = { clock.now() }
        let today = Calendar.current.startOfDay(for: clock.now())
        let list = try await api.activities(from: today, to: today.addingTimeInterval(86_400))
        let run = try #require(list.first)
        #expect(list.count == 1)
        #expect(run.origin == .recorded && run.sport == .running && run.mergedWith == workout.id)
        #expect(run.start == workout.start && run.end == workout.end && run.strain == workout.strain)
        #expect(run.scoringState == "scored" && run.strainSource == .heartRate && run.hrSource == workout.source)
        #expect(run.splits?.reduce(0) { $0 + $1.distanceM } == run.distanceM)
    }

    /// `MockPlatformAPI` forwards through `enter`, so scripted failures and `-RyftFault` apply.
    @Test func thePlatformMockForwardsAndFailsLikeEveryCall() async throws {
        let clock = TestClock()
        let api = MockPlatformAPI(activities: MockActivitiesSource())
        api.now = { clock.now() }
        let a = Self.run(start: clock.now().addingTimeInterval(-3_600))
        api.failNext = APIError.http(503, "unavailable")
        await #expect(throws: APIError.self) { try await api.putActivity(a) }
        #expect(api.activitySource.puts.isEmpty)
        let saved = try await api.putActivity(a)
        #expect(saved.scoringState == "pending")
        #expect(try await api.activities(from: .distantPast, to: .distantFuture).first?.strain == 9.4)
        #expect(api.count("putActivity") == 2 && api.count("activities") == 1)
        #if DEBUG
        api.faults = FaultInjection.parse("/v1/activities=503x1,/v1/activities/{id}=offline")
        await #expect(throws: APIError.self) { try await api.activities(from: .distantPast, to: .distantFuture) }
        #expect(try await api.activities(from: .distantPast, to: .distantFuture).count == 1)
        await #expect(throws: APIError.self) { try await api.putActivity(a) }
        #endif
    }

    /// R19: a `PUT` without route or samples keeps the stored ones; a `null` clears an editable field.
    @Test func aPutKeepsWhatItLeavesOutAndClearsItsNulls() async throws {
        let clock = TestClock()
        let source = MockActivitiesSource(now: { clock.now() })
        var a = Self.run(start: clock.now().addingTimeInterval(-3_600), route: true)
        _ = try await source.putActivity(a)
        a.route = nil
        a.hrSamples = nil
        a.notes = nil
        a.perceivedEffort = nil
        _ = try await source.putActivity(a)
        let stored = try await source.activity(id: a.id)
        #expect(stored.route == "_p~iF~ps|U_ulLnnqC" && stored.hrSamples?.count == 1)
        #expect(stored.notes == nil && stored.perceivedEffort == nil && stored.distanceM == 8_000)
    }

    @Test func resetGoesBackToTheSeed() async throws {
        let clock = TestClock()
        let seeded = Self.run(start: clock.now().addingTimeInterval(-7_200))
        let source = MockActivitiesSource(now: { clock.now() }, seed: { _ in [seeded] })
        let added = try await source.putActivity(Self.run(start: clock.now().addingTimeInterval(-3_600)))
        try await source.putManualSleep(day: "2026-10-19", ManualSleepPut(bed: clock.now().addingTimeInterval(-9 * 3_600),
                                                                          wake: clock.now().addingTimeInterval(-3_600)))
        #expect(try await source.activities(from: .distantPast, to: .distantFuture).count == 2)
        source.reset()
        #expect(try await source.activities(from: .distantPast, to: .distantFuture).map(\.id) == [seeded.id])
        await #expect(throws: APIError.self) { try await source.activity(id: added.id) }
        #expect(source.puts.isEmpty && source.manualSleep(day: "2026-10-19") == nil)
        // Tests start empty unless they ask for the demo.
        #expect(try await MockPlatformAPI().activities(from: .distantPast, to: .distantFuture).isEmpty)
    }

    @Test func theLiveClientSendsNothingBeforeTheContract() async {
        let client = APIClient.shared
        #expect(!client.publishesActivities)
        #expect(MockPlatformAPI().publishesActivities)
        await #expect(throws: ActivitiesError.notPublished) {
            try await client.putActivity(Self.run(start: .now.addingTimeInterval(-3_600)))
        }
        await #expect(throws: ActivitiesError.notPublished) { try await client.activities(from: .now, to: .now) }
        await #expect(throws: ActivitiesError.notPublished) { try await client.activity(id: UUID()) }
        await #expect(throws: ActivitiesError.notPublished) { try await client.deleteActivity(id: UUID()) }
        await #expect(throws: ActivitiesError.notPublished) {
            try await client.putManualSleep(day: "2026-10-19", ManualSleepPut(bed: .now, wake: .now))
        }
        await #expect(throws: ActivitiesError.notPublished) { try await client.deleteManualSleep(day: "2026-10-19") }
    }
}

@Suite("Activities: flags")
@MainActor
struct ActivityFlagTests {
    private let flags: [FeatureFlag] = [.todayMyDay, .activitiesManual, .activitiesRecording, .activityLiveHR]

    @Test func theFourFlagsAreDarkUnlessTheDemoPlatformTurnsThemOn() {
        #expect(flags.map(\.rawValue) == ["today.my_day", "activities.manual", "activities.recording", "activity.live_hr"])
        // Recording and live heart rate only in a Debug demo, before the release PR (design.md §8.5).
        #if DEBUG
        let demoOn: Set<FeatureFlag> = [.todayMyDay, .activitiesManual, .activitiesRecording, .activityLiveHR]
        #else
        let demoOn: Set<FeatureFlag> = [.todayMyDay, .activitiesManual]
        #endif
        for flag in flags {
            #expect(!flag.compiledDefault)
            #expect(!StaticFlags().isOn(flag))
            #expect((MockPlatformAPI.demoFlags[flag.rawValue] == true) == demoOn.contains(flag))
            #expect(MockPlatformAPI().remoteConfig.flags[flag.rawValue] == MockPlatformAPI.demoFlags[flag.rawValue])
        }
        #expect(MockPlatformAPI.demoFlags[FeatureFlag.devicesSetup.rawValue] == true)
    }

    /// The platform refuses any other key (`PUT /v1/admin/flags` answers 422): a flag the app reads must be one
    /// it can be set to.
    @Test(arguments: FeatureFlag.allCases)
    func everyFlagKeyIsOneThePlatformAccepts(_ flag: FeatureFlag) {
        #expect(flag.rawValue.wholeMatch(of: /[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+/) != nil, "\(flag.rawValue)")
    }

    /// Profile → Sync details → Loaded data: "Activities" appears with My Day, not while it's dark.
    @Test(arguments: [false, true])
    func syncDetailsListsTheActivitiesReadOnlyWithMyDay(_ myDay: Bool) {
        #expect(ReadResource.activities.priority == .normal)
        #expect(ReadResource.activities.displayName == String(localized: "Activities"))
        let env = AppEnvironment.test(flags: [.todayMyDay: myDay])
        let state = AppState(env: env)
        let sync = SyncService(env: env)
        let model = SyncDetailsModel(state: state, sync: sync,
                                     coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                  clock: env.clock),
                                     apiStatus: APIStatus())
        #expect(model.resources.contains { $0.resource == .activities } == myDay)
        // Copy diagnostics lists every resource either way.
        #expect(model.diagnostics.contains("\nactivities | "))
    }
}
