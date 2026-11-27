import Foundation
import Testing
@testable import Ryft

@Suite("Recovery API decoding")
struct RecoveryDecodingTests {
    @Test func checkin() throws {
        let checkin = try Fixture.decode(RecoveryCheckin.self, "recovery_checkin")
        #expect(checkin.date == "2026-11-26")
        #expect(checkin.wakeTime.timeIntervalSince(checkin.bedtime) == 450 * 60)
        #expect(checkin.tzOffsetSec == 3600)
        #expect(checkin.perceivedSleepQuality == 7 && checkin.perceivedFreshness == 6 && !checkin.soreness)
        #expect(checkin.sleepDurationMin == 450 && checkin.recoveryScore == 77)
        #expect(checkin.components == RecoveryComponents(wellness: 63, wellnessAbsolute: 63, wellnessPersonal: nil,
                                                         duration: 100, regularity: nil, n2r: nil))
        #expect(checkin.confidence == .low && !checkin.superseded && !checkin.n2rBedtimeApplied && !checkin.acuteDrop)
        #expect(checkin.modelVersion == "2026.11.1" && checkin.createdAt == checkin.updatedAt)
    }

    @Test func statusDueAndCompleted() throws {
        let due = try Fixture.decode(RecoveryStatus.self, "recovery_status_due")
        #expect(due.date == "2026-11-26" && due.source == .none && due.needsCheckin)
        #expect(due.checkin == nil && due.confidence == nil && due.recoveryScore == nil)
        #expect(due.suggestedBedtime == "22:45" && due.suggestedWakeTime == "06:45" && due.suggestionBasis == .expectedBedtime)
        let done = try Fixture.decode(RecoveryStatus.self, "recovery_status_checkin")
        let checkin = try #require(done.checkin)
        #expect(done.source == .checkin && done.confidence == .low && !done.needsCheckin && done.recoveryScore == 31)
        #expect(checkin.acuteDrop && checkin.n2rBedtimeApplied && checkin.components.duration == 40)
    }

    @Test func theWriteBodiesMatchV1() throws {
        let sample = try Fixture.decode(RecoveryCheckin.self, "recovery_checkin")
        let checkin = RecoveryCheckinPut(bedtime: sample.bedtime, wakeTime: sample.wakeTime, tzOffsetSec: 3600,
                                        perceivedSleepQuality: 7, perceivedFreshness: 6, soreness: false)
        let fields = try json(checkin)
        #expect(Set(fields.keys) == ["bedtime", "wake_time", "tz_offset_sec", "perceived_sleep_quality", "perceived_freshness", "soreness"])
        #expect(fields["tz_offset_sec"] as? Int == 3600 && fields["soreness"] as? Bool == false)
        #expect(fields["perceived_sleep_quality"] as? Int == 7 && fields["perceived_freshness"] as? Int == 6)
        #expect(try APIClient.jsonDecoder.decode(RecoveryCheckinPut.self, from: APIClient.jsonEncoder.encode(checkin)) == checkin)
        let rpe = try Fixture.decode(WorkoutRPEPut.self, "workout_rpe_put")
        #expect(try json(rpe) as? [String: Double] == ["session_rpe": 8])
    }

    @Test func workoutRatingIsOptionalAndNilIsOmittedForSync() throws {
        let rated = try Fixture.decode(Workout.self, "workout_rpe_response")
        #expect(rated.sessionRpe == 8 && rated.sessionRpeLoad == 480 && rated.duration == 3600)
        #expect(rated.avgHr == nil)
        let older = try #require(Fixture.decode([Workout].self, "workouts").first)
        #expect(older.sessionRpe == nil && older.sessionRpeLoad == nil)
        let sync = SyncRequest(deviceId: UUID(), samples: [], sleep: [], workouts: [older])
        let fields = try json(sync)
        let workouts = try #require(fields["workouts"] as? [[String: Any]])
        #expect(workouts[0]["session_rpe"] == nil && workouts[0]["session_rpe_load"] == nil)
    }

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: APIClient.jsonEncoder.encode(value)) as? [String: Any])
    }
}
