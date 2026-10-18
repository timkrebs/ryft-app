import Foundation
import Testing
@testable import Ryft

@Suite("API decoding")
struct DecodingTests {
    @Test func syncResponse() throws {
        let r = try Fixture.decode(SyncResponse.self, "sync_response")
        #expect(r.samples == 1520)
        #expect(r.daysTouched == ["2026-10-17", "2026-10-18"])
    }

    @Test func me() throws {
        let u = try Fixture.decode(User.self, "me")
        #expect(u.name == "Tim")
        #expect(u.maxHr == 190)
        #expect(u.sleepBaseMin == 480)
    }

    @Test func days() throws {
        let days = try Fixture.decode([DailyScore].self, "days")
        #expect(days.count == 2)
        let full = days[0]
        #expect(full.readiness == 84)
        #expect(full.state == .balanced)
        #expect(full.strain == 12.4)
        #expect(full.zoneMinutes == [31, 25, 16, 6, 2])
        #expect(full.trimp == 112)
        #expect(full.computedAt != nil) // nanosecond fraction parsed
    }

    @Test func calibratingDayHasNullsAndPlaceholders() throws {
        let day = try Fixture.decode([DailyScore].self, "days")[1]
        #expect(day.calibrating)
        #expect(day.readiness == nil && day.recovery == nil && day.strain == nil)
        #expect(day.resolvedState == .calibrating)
        #expect(day.nightsToGo == 4)
        #expect(Fmt.percent(day.recovery) == "–")
        #expect(Fmt.strain(day.strain) == "–")
        #expect(Fmt.duration(minutes: day.sleepActualMin) == "–")
    }

    @Test func dayDetail() throws {
        let d = try Fixture.decode(DayDetail.self, "day_detail")
        #expect(d.score.sleepPerformance == 82) // 82.0 decoded leniently
        let sleep = try #require(d.sleep)
        #expect(sleep.totalMin == 468)
        #expect(sleep.stages.count == 4)
        #expect(sleep.qualityLabel == "Good")
        #expect(abs((sleep.efficiencyPercent ?? 0) - 95.5) < 0.01) // fraction normalised
        #expect(d.workouts.first?.strain == 10.6)
        #expect(d.workouts.first?.distanceM == 8400)
    }

    @Test func legacyDayDetailFallsBackToDetails() throws {
        // What the current pre-v1 backend returns: no readiness/state, no `sleep`.
        let d = try Fixture.decode(DayDetail.self, "day_detail_legacy")
        #expect(d.sleep == nil)
        #expect(d.score.readinessValue == 71) // recovery stands in
        #expect(d.score.resolvedState == .balanced)
        let sleep = try #require(d.resolvedSleep)
        #expect(sleep.totalMin == 420)
        #expect(sleep.quality == 88)
        #expect(sleep.stages.first { $0.stage == .light }?.min == 246) // "core" → light
        #expect(sleep.start != nil && sleep.end != nil)
        #expect(sleep.timeInBedMin == 448) // inbed 0 → derived from start/end
        #expect(d.score.zoneMinutes == [20.5, 18, 9, 3, 0])
    }

    @Test func sleepRangeAcceptsListAndMapStages() throws {
        let r = try Fixture.decode(SleepRange.self, "sleep_range")
        #expect(r.range == "week")
        #expect(r.days.count == 3)
        #expect(r.days[0].minutes(for: .deep) == 95)
        #expect(r.days[1].totalMin == nil)
        #expect(r.days[1].stages.isEmpty)
        #expect(r.days[2].minutes(for: .light) == 261)
        #expect(r.days[2].start != nil)
        #expect(r.avgTotalMin == 449.5)
    }

    @Test func workouts() throws {
        let w = try Fixture.decode([Workout].self, "workouts")
        #expect(w.count == 2)
        #expect(w[1].avgHr == nil && w[1].strain == nil)
        #expect(w[0].duration == 52 * 60)
    }

    @Test func workoutDetail() throws {
        let d = try Fixture.decode(WorkoutDetail.self, "workout_detail")
        #expect(d.workout.activity == "running")
        #expect(d.hr.count == 3)
        #expect(d.zoneMin == [8, 12, 20, 9, 3])
        #expect(d.trimp == 114)
    }

    @Test func trends() throws {
        let t = try Fixture.decode(TrendSeries.self, "trends")
        #expect(t.metric == "hrv")
        #expect(t.points.count == 3)
        #expect(t.points[1].value == nil)
        #expect(t.baseline == 57.9)
    }

    @Test func insights() throws {
        let i = try Fixture.decode([Insight].self, "insights")
        #expect(i.count == 3)
        #expect(i[1].id == "42") // numeric id accepted
        #expect(i[1].severity == .warn)
        #expect(i[2].severity == .info) // unknown severity falls back
    }

    @Test func errorBody() throws {
        let e = try Fixture.decode(APIErrorBody.self, "error")
        #expect(e.error.hasPrefix("invalid day"))
        #expect(APIError.http(404, "").isNotFound)
        #expect(!APIError.http(500, "").isNotFound)
    }

    @Test func cacheRoundTripKeepsDetails() throws {
        // Snapshot encode/decode rewrites `details` keys to camelCase; lookups must still work.
        let d = try Fixture.decode(DayDetail.self, "day_detail_legacy")
        let data = try APIClient.jsonEncoder.encode(d)
        let back = try APIClient.jsonDecoder.decode(DayDetail.self, from: data)
        #expect(back.score.zoneMinutes == d.score.zoneMinutes)
        #expect(back.resolvedSleep?.totalMin == 420)
        #expect(back.score.sleepStart == d.score.sleepStart)
    }
}
