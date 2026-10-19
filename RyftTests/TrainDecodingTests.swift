import Foundation
import Testing
@testable import Ryft

/// Train shapes, with fixtures built from the JSON examples in
/// `../plattform/docs/API.md` → Train (ids written out where the doc abbreviates).
@Suite("Train decoding")
struct TrainDecodingTests {
    @Test func exercises() throws {
        let list = try Fixture.decode([Exercise].self, "train_exercises")
        #expect(list.count == 3)
        let squat = list[0]
        #expect(squat.kind == .barbell)
        #expect(squat.nameEn == "Back squat" && squat.nameDe == "Kniebeuge")
        #expect(squat.primaryMuscles == [.quads, .glutes])
        #expect(squat.secondaryMuscles == [.hamstrings, .adductors, .lowerBack])
        #expect(list[1].loadType == .bodyweight)
        #expect(list[1].bodyweightFactor == 1)
        // Unknown values don't break the library: kind falls back, muscles are dropped.
        #expect(list[2].kind == .machine)
        #expect(list[2].primaryMuscles == [.frontDelts, .chest])
        #expect(list[2].isCustom && list[2].isUnilateral)
    }

    @Test func customExerciseInputMatchesThePOSTBody() throws {
        let e = Exercise(slug: "landmine-press", name: "Landmine press", nameDe: "Landmine-Drücken", kind: .barbell,
                         primaryMuscles: [.frontDelts, .chest], secondaryMuscles: [.triceps],
                         equipment: ["barbell", "landmine"], isUnilateral: true, isCustom: true)
        let json = try #require(String(data: APIClient.jsonEncoder.encode(ExerciseInput(e)), encoding: .utf8))
        #expect(json.contains("\"name_de\":\"Landmine-Drücken\""))
        #expect(json.contains("\"primary_muscles\":[\"front_delts\",\"chest\"]"))
        #expect(json.contains("\"load_type\":\"weight\""))
        #expect(!json.contains("is_custom")) // not a POST field
    }

    @Test func planDetail() throws {
        let p = try Fixture.decode(Plan.self, "train_plan")
        #expect(p.slug == "upper-lower-4x")
        #expect(p.goal == .hypertrophy)
        #expect(p.weeks == nil) // repeating
        #expect(p.progression == .linear)
        #expect(!p.archived)
        #expect(p.days.count == 2)
        #expect(p.days[0].week == nil && p.days[1].week == 2)
        let bench = p.days[0].exercises[0]
        #expect(bench.exerciseId == bench.exercise.id)
        #expect(bench.targetKind == .kg && bench.targetValue == 80)
        let pullUp = p.days[0].exercises[1]
        #expect(pullUp.targetKind == .bodyweight && pullUp.targetValue == nil)
        #expect(pullUp.supersetGroup == 1)
        #expect(pullUp.notes == "Slow negatives")
    }

    @Test func plansOverviewWithSummaries() throws {
        let o = try Fixture.decode(PlansOverview.self, "train_plans")
        #expect(o.builtin.count == 2)
        #expect(o.builtin[0].dayCount == 4 && o.builtin[0].exerciseCount == 18)
        #expect(o.builtin[1].weeks == 8)
        #expect(o.mine.first?.slug == nil)
        let e = try #require(o.active)
        #expect(e.status == .active)
        #expect(e.currentWeek == 6 && e.currentDayIndex == 0)
        #expect(o.summary(id: e.planId)?.name == "Upper/Lower 4×")
    }

    @Test func planToday() throws {
        let t = try Fixture.decode(PlanToday.self, "train_plan_today")
        #expect(t.day.name == "Upper A")
        let target = try #require(t.target(for: t.day.exercises[0]))
        #expect(target.exerciseId == t.day.exercises[0].exerciseId)
        #expect(target.targetKind == .kg && target.targetKg == 102.5)
        #expect(target.restSec == 180)
        #expect(Fmt.prescription(sets: target.sets, repsMin: target.repsMin, repsMax: target.repsMax) == "5 × 5")
        #expect(target.lastTime.count == 2)
        #expect(target.lastTime[0].completedAt != nil) // microsecond fraction parsed
    }

    @Test func session() throws {
        let s = try Fixture.decode(TrainSession.self, "train_session")
        #expect(s.status == .inProgress)
        #expect(s.endedAt == nil && s.strain == nil && s.prs.isEmpty)
        #expect(s.deviceId != nil && s.updatedAt != nil)
        #expect(s.exercises[0].planExerciseId != nil && s.exercises[1].planExerciseId == nil)
        let sets = s.exercises[0].sets
        #expect(sets[0].isWarmup)
        #expect(sets[1].weightKg == 100 && sets[1].rpe == 8)
        #expect(sets[2].completedAt == nil && sets[2].reps == nil)
        #expect(s.exercises[1].sets[0].durationSec == 45)
    }

    @Test func completedSessionCarriesLoadAndPRs() throws {
        let s = try Fixture.decode(TrainSession.self, "train_session_completed")
        #expect(s.status == .completed)
        #expect(s.muscularTrimp == 55.3 && s.strain == 10.6 && s.volumeKg == 7420)
        #expect(s.workoutId != nil)
        #expect(s.prs.map(\.kind) == [.e1rm, .maxWeight])
        #expect(s.prs[0].setId != nil && s.prs[0].sessionId == s.id)
    }

    @Test func sessionSummaries() throws {
        let list = try Fixture.decode([SessionSummary].self, "train_sessions")
        #expect(list.count == 2)
        #expect(list[0].durationMin == 59 && list[0].setCount == 19 && list[0].prCount == 2)
        #expect(list[1].status == .inProgress && list[1].durationMin == nil && list[1].strain == nil)
    }

    @Test func exerciseHistory() throws {
        let h = try Fixture.decode(ExerciseHistory.self, "train_exercise_history")
        #expect(h.prs.count == 2)
        #expect(h.prs[1].kind == .maxReps)
        #expect(h.sessions.map(\.date) == ["2026-10-17", "2026-09-20"]) // newest first
        #expect(h.sessions[0].sets.first?.weightKg == 130)
        #expect(h.e1rm.map(\.value) == [131.3, 142.5]) // oldest first
    }

    @Test func sessionEncodesSnakeCaseForPut() throws {
        let s = try Fixture.decode(TrainSession.self, "train_session")
        let json = try #require(String(data: APIClient.jsonEncoder.encode(s), encoding: .utf8))
        for key in ["started_at", "plan_day_id", "is_warmup", "device_id", "plan_exercise_id", "in_progress"] {
            #expect(json.contains("\"\(key)\""), "\(key)")
        }
        let back = try APIClient.jsonDecoder.decode(TrainSession.self, from: Data(json.utf8))
        #expect(back.exercises.flatMap(\.sets).map(\.id) == s.exercises.flatMap(\.sets).map(\.id))
    }

    @Test func completeBodySendsEndedAt() throws {
        let body = SessionComplete(bodyweightKg: 80, endedAt: Date(timeIntervalSince1970: 1_792_000_000))
        let json = try #require(String(data: APIClient.jsonEncoder.encode(body), encoding: .utf8))
        #expect(json.contains("\"bodyweight_kg\":80") && json.contains("\"ended_at\""))
    }

    @Test func workoutLinksItsSession() throws {
        let json = #"{"id":"00000000-0000-4000-8000-000000000891","activity":"strength","start":"2026-10-19T17:00:00Z","end":"2026-10-19T18:00:00Z","source":"ryft-session","strain":9.8,"muscular_load":55.3,"session_id":"a7f2c3d4-5e6f-4a7b-8c9d-0e1f2a3b4c5d"}"#
        let w = try APIClient.jsonDecoder.decode(Workout.self, from: Data(json.utf8))
        #expect(w.sessionId == UUID(uuidString: "a7f2c3d4-5e6f-4a7b-8c9d-0e1f2a3b4c5d"))
        #expect(w.muscularLoad == 55.3)
    }
}
