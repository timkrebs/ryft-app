import Foundation
import Testing
@testable import Ryft

/// Train shapes. `API.md` has no Train section yet; these fixtures follow the
/// M3b shapes and the platform brief's enum values and are regenerated from
/// `API.md` once the platform commits it.
@Suite("Train decoding")
struct TrainDecodingTests {
    @Test func exercises() throws {
        let list = try Fixture.decode([Exercise].self, "train_exercises")
        #expect(list.count == 3)
        #expect(list[0].kind == .barbell)
        #expect(list[0].primaryMuscles == ["quads", "glutes"])
        #expect(list[1].loadType == .bodyweight)
        #expect(list[1].bodyweightFactor == 1)
        // Unknown kinds don't break the library.
        #expect(list[2].kind == .machine)
        #expect(list[2].isCustom && list[2].isUnilateral)
    }

    @Test func planDetail() throws {
        let p = try Fixture.decode(Plan.self, "train_plan")
        #expect(p.goal == .hypertrophy)
        #expect(p.weeks == nil) // repeating
        #expect(p.progression == .linear)
        #expect(p.progression.incrementKg == 2.5)
        #expect(p.days.count == 2)
        #expect(p.days[0].week == nil && p.days[1].week == 2)
        let bench = p.days[0].exercises[0]
        #expect(bench.exercise.name == "Bench press")
        #expect(bench.targetKind == .kg && bench.targetValue == 80)
        #expect(bench.supersetGroup == nil)
        let pulldown = p.days[0].exercises[1]
        #expect(pulldown.targetKind == .rpe)
        #expect(pulldown.repsMin == 10 && pulldown.repsMax == 12)
        #expect(pulldown.supersetGroup == 1)
        #expect(pulldown.notes == "Slow negatives")
    }

    @Test func planCatalogWithSummaries() throws {
        let c = try Fixture.decode(PlanCatalog.self, "train_plans")
        #expect(c.builtin.count == 2)
        #expect(c.builtin.allSatisfy { $0.days.isEmpty }) // summaries carry no days
        #expect(c.builtin[1].progression.type == .percent)
        #expect(c.mine.first?.progression == Progression.none)
        let e = try #require(c.active)
        #expect(e.status == .active)
        #expect(e.currentWeek == 6 && e.currentDayIndex == 0)
        #expect(e.planId == c.builtin[0].id)
    }

    @Test func planToday() throws {
        let t = try Fixture.decode(PlanToday.self, "train_plan_today")
        #expect(t.day.name == "Upper A")
        let target = try #require(t.target(for: t.day.exercises[0]))
        #expect(Fmt.prescription(sets: target.sets, repsMin: target.repsMin, repsMax: target.repsMax) == "3 × 5")
        #expect(target.targetKg == 100)
        #expect(target.lastTime.count == 2)
        #expect(target.lastTime[0].completedAt != nil) // microsecond fraction parsed
        #expect(target.lastTime[1].rpe == 9)
    }

    @Test func session() throws {
        let s = try Fixture.decode(TrainSession.self, "train_session")
        #expect(s.status == .inProgress)
        #expect(s.endedAt == nil && s.strain == nil)
        #expect(s.bodyweightKg == 80.5)
        #expect(s.exercises.count == 2)
        let sets = s.exercises[0].sets
        #expect(sets[0].isWarmup)
        #expect(sets[1].weightKg == 100 && sets[1].rpe == 8.5)
        #expect(sets[2].completedAt == nil && sets[2].reps == nil)
        #expect(s.exercises[1].sets[0].durationSec == 45)
    }

    @Test func completedSessionCarriesLoadAndPRs() throws {
        let c = try Fixture.decode(CompletedSession.self, "train_session_completed")
        #expect(c.session.status == .completed)
        #expect(c.session.muscularTrimp == 84.6)
        #expect(c.session.strain == 11.2)
        #expect(c.session.volumeKg == 4250)
        #expect(c.session.workoutId != nil)
        #expect(c.prs.map(\.kind) == [.e1rm, .maxWeight])
    }

    @Test func exerciseHistory() throws {
        let h = try Fixture.decode(ExerciseHistory.self, "train_exercise_history")
        #expect(h.prs.count == 2)
        #expect(h.prs[1].kind == .maxReps)
        #expect(h.sessions.count == 2) // `date` as a day or a timestamp
        #expect(DayFormat.string(from: h.sessions[0].date) == "2026-10-19")
        #expect(h.e1rm.map(\.value) == [113.8, 116.7])
    }

    @Test func sessionEncodesSnakeCaseForPut() throws {
        let s = try Fixture.decode(TrainSession.self, "train_session")
        let json = try #require(String(data: APIClient.jsonEncoder.encode(s), encoding: .utf8))
        #expect(json.contains("\"started_at\""))
        #expect(json.contains("\"plan_day_id\""))
        #expect(json.contains("\"is_warmup\""))
        #expect(json.contains("\"in_progress\""))
        let back = try APIClient.jsonDecoder.decode(TrainSession.self, from: Data(json.utf8))
        #expect(back.exercises.flatMap(\.sets).map(\.id) == s.exercises.flatMap(\.sets).map(\.id))
    }

    @Test func workoutLinksItsSession() throws {
        let json = #"{"id":"00000000-0000-4000-8000-000000000891","activity":"strength","start":"2026-10-19T17:00:00Z","end":"2026-10-19T18:00:00Z","source":"Garmin Connect","strain":9.8,"muscular_load":84.6,"session_id":"3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e01"}"#
        let w = try APIClient.jsonDecoder.decode(Workout.self, from: Data(json.utf8))
        #expect(w.sessionId == UUID(uuidString: "3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e01"))
        #expect(w.muscularLoad == 84.6)
    }
}
