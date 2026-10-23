import Foundation
import SwiftData
import Testing
@testable import Ryft

/// The platform's activities in the read model (`Repository`, design.md §7.2): one `CachedDocument` per day,
/// the day's TTLs, and never a route or heart-rate samples at rest (ADR 0006, review S5).
@Suite("Activities: read model")
@MainActor
struct ActivityReadModelTests {
    @MainActor
    private struct Graph {
        let api: MockPlatformAPI
        let env: AppEnvironment
        let repo: Repository
        let clock: TestClock

        /// `hour:minute` local time on the clock's day, `days` later.
        func at(_ hour: Int, _ minute: Int = 0, days: Int = 0) -> Date {
            let day = DayFormat.shift(clock.now(), days: days)
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        func day(_ days: Int = 0) -> String { DayFormat.string(from: DayFormat.shift(clock.now(), days: days)) }

        /// The raw cached JSON of `day`'s activities.
        func document(_ day: String) -> String? {
            let key = Repository.activitiesKey(day)
            var d = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
            d.fetchLimit = 1
            return (try? env.persistence.context.fetch(d))?.first.flatMap { String(bytes: $0.data, encoding: .utf8) }
        }
    }

    /// Noon today on the clock, a platform with no activities yet.
    private func graph(answersWithTrack: Bool = false) -> Graph {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: TestClock().now()) ?? .now
        let clock = TestClock(now: noon)
        let source = MockActivitiesSource()
        source.answersWithTrack = answersWithTrack
        let api = MockPlatformAPI(activities: source)
        let env = AppEnvironment.test(api: api, clock: clock)
        return Graph(api: api, env: env, repo: Repository(env: env), clock: clock)
    }

    private func run(at start: Date, minutes: Double = 40, track: Bool = true) -> SportActivity {
        SportActivity(id: UUID(), sport: .running, origin: .recorded, start: start,
                      end: start.addingTimeInterval(minutes * 60), movingSec: minutes * 60, distanceM: 7_000,
                      route: track ? "_p~iF~ps|U_ulLnnqC_mqNvxq`@" : nil,
                      hrSamples: track ? [HRPoint(t: start, bpm: 131)] : nil, clientUpdatedAt: start,
                      strain: 8.8, strainSource: .heartRate, scoringState: "scored")
    }

    // MARK: no route at rest

    @Test func storingADaysListDropsRouteAndSamples() throws {
        let g = graph()
        let a = run(at: g.at(7))
        g.repo.store(activities: [a], day: g.day())
        let cached = try #require(g.repo.activities(day: g.day()).first)
        #expect(cached == a.withoutRouteOrHeartRate)
        #expect(cached.route == nil && cached.hrSamples == nil && cached.strain == 8.8)
        let json = try #require(g.document(g.day()))
        #expect(!json.contains("route") && !json.contains("hr_samples") && !json.contains("_p~iF"))
    }

    @Test func storingOneAnswerDropsRouteAndSamples() throws {
        let g = graph()
        let a = run(at: g.at(7))
        g.repo.store(activity: a)
        #expect(g.repo.activities(day: g.day()) == [a.withoutRouteOrHeartRate])
        let json = try #require(g.document(g.day()))
        #expect(!json.contains("route") && !json.contains("hr_samples"))
    }

    /// A platform that sends the route in a list anyway (R16 not honoured): it never reaches the store.
    @Test func aRefreshNeverCachesARouteEvenIfOneArrives() async throws {
        let g = graph(answersWithTrack: true)
        let sent = run(at: g.at(7), track: true)
        _ = try await g.api.putActivity(sent)
        let listed = try await g.repo.refreshActivities(g.day())
        #expect(listed.map(\.id) == [sent.id])
        #expect(listed.first?.route == nil && listed.first?.hrSamples == nil)
        let json = try #require(g.document(g.day()))
        #expect(!json.contains("route") && !json.contains("hr_samples") && !json.contains("_p~iF"))
    }

    // MARK: reads

    @Test func theDaysActivitiesAreFetchedForTheLocalDay() async throws {
        let g = graph()
        let morning = try await g.api.putActivity(run(at: g.at(7)))
        let lateYesterday = try await g.api.putActivity(run(at: g.at(23, 30, days: -1), minutes: 45))
        let today = try await g.repo.refreshActivities(g.day())
        #expect(today.map(\.id) == [morning.id])
        #expect(g.repo.activities(day: g.day()).map(\.id) == [morning.id])
        let yesterday = try await g.repo.refreshActivities(g.day(-1))
        #expect(yesterday.map(\.id) == [lateYesterday.id])
        #expect(g.api.count("activities") == 2)
        #expect(g.repo.activities(day: g.day(-2)).isEmpty)
    }

    @Test func todayIsFreshForFiveMinutesAPastDayForADay() async throws {
        let g = graph()
        let today = g.day(), yesterday = g.day(-1)
        try await g.repo.refreshActivities(today)
        try await g.repo.refreshActivities(today)
        #expect(g.api.count("activities") == 1)
        g.clock.advance(by: .seconds(4 * 60))
        try await g.repo.refreshActivities(today)
        #expect(g.api.count("activities") == 1)
        g.clock.advance(by: .seconds(2 * 60))
        try await g.repo.refreshActivities(today)
        #expect(g.api.count("activities") == 2)
        // Yesterday, fetched after it ended: fresh for a day.
        try await g.repo.refreshActivities(yesterday)
        g.clock.advance(by: .seconds(23 * 3600))
        try await g.repo.refreshActivities(yesterday)
        #expect(g.api.count("activities") == 3)
        g.clock.advance(by: .seconds(2 * 3600))
        try await g.repo.refreshActivities(yesterday)
        #expect(g.api.count("activities") == 4)
        // `.latest` (pull to refresh) always asks.
        try await g.repo.refreshActivities(yesterday, mode: .latest)
        #expect(g.api.count("activities") == 5)
    }

    @Test func aFailureKeepsTheCachedCopyAndWithoutOneThrows() async throws {
        let g = graph()
        let a = try await g.api.putActivity(run(at: g.at(7)))
        try await g.repo.refreshActivities(g.day())
        g.api.failure = APIError.http(422, "bad range", requestID: "req-422")
        let kept = try await g.repo.refreshActivities(g.day(), mode: .latest)
        #expect(kept.map(\.id) == [a.id])
        await #expect(throws: APIError.self) { try await g.repo.refreshActivities(g.day(-1)) }
        #expect(g.env.reads.states[.activities]?.lastError?.requestID == "req-422")
    }

    /// The live client before the contract: no request, nothing stored, no failure recorded.
    @Test func beforeTheContractTheReadIsEmptyAndNoFailure() async throws {
        let g = graph()
        g.api.failNext = ActivitiesError.notPublished
        let listed = try await g.repo.refreshActivities(g.day())
        #expect(listed.isEmpty)
        #expect(g.document(g.day()) == nil && g.repo.activitiesFetchedAt(day: g.day()) == nil)
        let state = g.env.reads.states[.activities]
        #expect(state?.lastError == nil && state?.consecutiveFailures == 0)
    }

    @Test func offlineNothingIsAsked() async throws {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: TestClock().now()) ?? .now
        let api = MockPlatformAPI(activities: MockActivitiesSource())
        let env = AppEnvironment.test(api: api, clock: TestClock(now: noon), online: false)
        let repo = Repository(env: env)
        #expect(try await repo.refreshActivities(DayFormat.string(from: noon)).isEmpty)
        #expect(api.count("activities") == 0)
    }

    @Test func readsAreMemoisedPerRevision() async throws {
        let g = graph()
        _ = try await g.api.putActivity(run(at: g.at(7)))
        try await g.repo.refreshActivities(g.day())
        // The refresh answered from the store, so these reads are memoised already.
        let decodes = g.repo.decodes
        _ = g.repo.activities(day: g.day())
        _ = g.repo.activities(day: g.day())
        #expect(g.repo.decodes == decodes)
        let revision = g.repo.activitiesRevision
        g.repo.store(activity: run(at: g.at(9), track: false))
        #expect(g.repo.activitiesRevision == revision + 1)
        #expect(g.repo.activities(day: g.day()).count == 2)
        _ = g.repo.activities(day: g.day())
        #expect(g.repo.decodes == decodes + 1)
    }

    // MARK: single answers

    @Test func oneAnswerReplacesItsCopyAndMovesWithItsDay() throws {
        let g = graph()
        var a = run(at: g.at(7), track: false)
        let other = run(at: g.at(9), track: false)
        g.repo.store(activities: [a, other], day: g.day())
        a.notes = "Edited"
        g.repo.store(activity: a)
        #expect(g.repo.activities(day: g.day()).map(\.notes) == ["Edited", nil])
        // Its start moved to yesterday: gone from today, in yesterday's list.
        a.start = g.at(18, days: -1)
        a.end = a.start.addingTimeInterval(1_800)
        g.repo.store(activity: a)
        #expect(g.repo.activities(day: g.day()).map(\.id) == [other.id])
        #expect(g.repo.activities(day: g.day(-1)).map(\.id) == [a.id])
        // A single answer doesn't make yesterday's list fresh.
        #expect(g.repo.activitiesFetchedAt(day: g.day(-1)) == .distantPast)
    }

    // MARK: housekeeping

    @Test func compactionDropsActivitiesWithTheirDays() {
        let g = graph()
        g.repo.store(activities: [run(at: g.at(7, days: -400), track: false)], day: g.day(-400))
        g.repo.store(activities: [run(at: g.at(7, days: -30), track: false)], day: g.day(-30))
        g.repo.compact()
        #expect(g.document(g.day(-400)) == nil)
        #expect(g.repo.activities(day: g.day(-30)).count == 1)
    }

    @Test func clearAndTheSignOutWipeDropThem() {
        let g = graph()
        g.repo.store(activities: [run(at: g.at(7), track: false)], day: g.day())
        g.repo.clear()
        #expect(g.repo.activities(day: g.day()).isEmpty && g.document(g.day()) == nil)
        g.repo.store(activities: [run(at: g.at(7), track: false)], day: g.day())
        g.env.persistence.wipe()
        g.repo.invalidate()
        #expect(g.repo.activities(day: g.day()).isEmpty)
    }
}
