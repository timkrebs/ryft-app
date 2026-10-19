import Foundation
import Testing
@testable import Ryft

/// Every fixture is a JSON example from ../plattform/docs/API.md, decoded with
/// the app's real decoder.
@Suite("API decoding")
struct DecodingTests {
    @Test func syncResponse() throws {
        let r = try Fixture.decode(SyncResponse.self, "sync_response")
        #expect(r.samples == 1440)
        #expect(r.daysTouched == ["2026-10-17", "2026-10-18"])
    }

    @Test func me() throws {
        let u = try Fixture.decode(User.self, "me")
        #expect(u.name == "Tim K")
        #expect(u.email == "tim@example.com")
        #expect(u.provider == "apple")
        #expect(u.tz == "Europe/Berlin")
        #expect(u.maxHr == 190)
        #expect(u.sleepBaseMin == 460)
    }

    @Test func days() throws {
        let days = try Fixture.decode([DailyScore].self, "days")
        #expect(days.count == 2)
        let full = days[0]
        #expect(full.readiness == 84)
        #expect(full.state == .balanced)
        #expect(full.strain == 12.4)
        #expect(full.steps == 9412)
        #expect(full.activeKcal == 612)
        #expect(full.hrvBaselineMs == 53.1)
        #expect(full.rhrBaseline == 50.2)
        #expect(full.baselineDays == 30)
        #expect(!full.calibrating)
        #expect(full.computedAt != nil) // microsecond fraction parsed
    }

    @Test func calibratingDayHasNullsAndPlaceholders() throws {
        let day = try Fixture.decode([DailyScore].self, "days")[1]
        #expect(day.calibrating)
        #expect(day.readiness == nil && day.recovery == nil && day.strain == nil && day.steps == nil)
        #expect(day.resolvedState == .calibrating)
        #expect(day.nightsToGo == 4)
        #expect(Fmt.percent(day.recovery) == "–")
        #expect(Fmt.strain(day.strain) == "–")
        #expect(Fmt.duration(minutes: day.sleepActualMin) == "–")
    }

    @Test func dayDetail() throws {
        let d = try Fixture.decode(DayDetail.self, "day_detail")
        let sleep = try #require(d.sleep)
        #expect(sleep.totalMin == 468)
        #expect(sleep.inBedMin == 492)
        #expect(sleep.efficiency == 95)
        #expect(sleep.qualityLabel == .good)
        #expect(sleep.resolvedQualityLabel == "Good")
        #expect(sleep.stages.map(\.stage) == [.deep, .light, .rem, .awake])
        #expect(sleep.displayStages.map { $0.pct } == [24, 56, 20, 2]) // as sent, never rescaled
        #expect(sleep.segments.count == 5)
        #expect(sleep.segments[2].stage == .asleep)
        let strain = try #require(d.strain)
        #expect(strain.trimp == 99)
        #expect(strain.hrMin == 912)
        #expect(strain.zoneMin == [12, 24, 37, 7, 0])
        #expect(strain.steps == 9412)
        #expect(d.workouts.first?.strain == 14.9)
        #expect(d.workouts.first?.distanceM == 11800)
    }

    @Test func unscoredDay() throws {
        let d = try Fixture.decode(DayDetail.self, "day_unscored")
        #expect(d.sleep == nil && d.strain == nil && d.workouts.isEmpty)
        #expect(d.score.resolvedState == .calibrating)
        #expect(!d.score.calibrating) // baseline isn't the reason; there's no readiness yet
        #expect(ReadinessCopy.sentence(score: d.score) == "No readiness yet today. It appears once last night has synced.")
    }

    @Test func sleepRange() throws {
        let r = try Fixture.decode(SleepRange.self, "sleep_range")
        #expect(r.range == "week")
        #expect(r.from == "2026-10-12" && r.to == "2026-10-18")
        #expect(r.nights == 2)
        #expect(r.days.count == 2) // missing nights are absent
        #expect(r.days[0].minutes(for: .deep) == 95)
        #expect(r.days[1].hasStages == false)
        #expect(r.days[1].qualityLabel == .fair)
        #expect(r.avgTotalMin == 455)
        #expect(r.avgEfficiency == 94)
        #expect(r.avgStages.count == 4)
    }

    @Test func workouts() throws {
        let w = try Fixture.decode([Workout].self, "workouts")
        #expect(w.count == 2)
        #expect(w[1].avgHr == nil && w[1].strain == nil && w[1].energyKcal == nil) // omitted fields
        #expect(w[0].duration == 70 * 60)
    }

    @Test func workoutDetail() throws {
        let d = try Fixture.decode(WorkoutDetail.self, "workout_detail")
        #expect(d.workout.activity == "running")
        #expect(d.hr.count == 3)
        #expect(d.hr[1].bpm == 131)
        #expect(d.zoneMin == [2, 24, 37, 7, 0])
        #expect(d.trimp == 99)
    }

    @Test func trends() throws {
        let t = try Fixture.decode(TrendSeries.self, "trends")
        #expect(t.metric == "hrv")
        #expect(t.points.count == 3) // days without a value are absent
        #expect(t.avg == 51.7)
        #expect(t.baseline == 52.3)
    }

    @Test func trendMetricsMatchTheAPI() {
        #expect(TrendMetric.allCases.map(\.rawValue)
                == ["readiness", "recovery", "strain", "sleep", "sleep_min", "hrv", "rhr", "steps", "active_kcal"])
    }

    @Test func insights() throws {
        let i = try Fixture.decode([Insight].self, "insights")
        #expect(i.count == 3)
        #expect(i.map(\.severity) == [.warn, .notice, .info])
        #expect(i[0].id == "hrv-low-3d")
        #expect(i[0].metric == "hrv")
    }

    @Test func errorBody() throws {
        let e = try Fixture.decode(APIErrorBody.self, "error")
        #expect(e.error == "human-readable message")
        #expect(e.requestId == "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c")
    }

    @Test func accountDeleted() throws {
        let d = try Fixture.decode(AccountDeleted.self, "account_deleted")
        #expect(d.status == "deleted")
        #expect(d.authUserDeleted)
    }

    @Test func cacheRoundTripKeepsTypedFields() throws {
        let d = try Fixture.decode(DayDetail.self, "day_detail")
        let data = try APIClient.jsonEncoder.encode(d)
        let back = try APIClient.jsonDecoder.decode(DayDetail.self, from: data)
        // `computed_at` loses its microseconds (the encoder writes whole seconds); everything else survives.
        #expect(back.sleep == d.sleep)
        #expect(back.strain == d.strain)
        #expect(back.workouts == d.workouts)
        var score = back.score
        score.computedAt = d.score.computedAt
        #expect(score == d.score)
    }
}
