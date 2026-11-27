import Foundation
import Testing
@testable import Ryft

@Suite("Session effort")
@MainActor
struct SessionRPEModelTests {
    @Test func flagOffHidesTheEditorAndMakesNoRequest() async throws {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api)
        var workout = try Fixture.decode(Workout.self, "workout_rpe_response")
        workout.sessionRpe = 8
        let model = SessionRPEModel(env: env, workoutID: workout.id, workout: workout)
        await model.save(7)
        await model.clear()
        #expect(!model.isVisible && !model.showsPrompt && api.calls.isEmpty)
    }

    @Test func noHeartRateAndNoRatingPromptsForEffort() throws {
        let env = AppEnvironment.test(flags: [.recoveryCheckin: true])
        let workouts = try Fixture.decode([Workout].self, "workouts")
        let workout = try #require(workouts.first { $0.avgHr == nil })
        let model = SessionRPEModel(env: env, workoutID: workout.id, workout: workout)
        #expect(model.isVisible && model.showsPrompt && model.rating == nil)
        let withHR = try #require(workouts.first { $0.avgHr != nil })
        let quieter = SessionRPEModel(env: env, workoutID: withHR.id, workout: withHR)
        #expect(quieter.isVisible && !quieter.showsPrompt)
    }

    @Test func ratingPersistsOnTheMockWorkoutAndOnlyThePutTracks() async throws {
        let api = MockPlatformAPI()
        let sink = FakeAnalyticsSink()
        let env = AppEnvironment.test(api: api, flags: [.recoveryCheckin: true, .analyticsEnabled: true], analyticsSink: sink)
        let flags = try #require(env.flags as? StaticFlags)
        flags.analytics = AnalyticsFixture.config
        env.analytics.setOptIn(true)

        let workout = try #require(MockData.allWorkouts.first)
        let model = SessionRPEModel(env: env, workoutID: workout.id, workout: workout)
        await model.save(8)
        #expect(model.rating == 8 && model.error == nil)
        let saved = try await api.workout(id: workout.id).workout
        #expect(saved.sessionRpe == 8)
        #expect(saved.sessionRpeLoad == Int((workout.duration / 60).rounded()) * 8)
        await model.clear()
        #expect(model.rating == nil)
        #expect(try await api.workout(id: workout.id).workout.sessionRpe == nil)
        #expect(sink.captures == [.init(name: "feature_used", properties: ["feature": "session_rpe_saved"])])
    }

    @Test func aPut404HidesTheEditorAndStopsFurtherWrites() async {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, flags: [.recoveryCheckin: true])
        let model = SessionRPEModel(env: env, workoutID: UUID())
        api.failNext = APIError.http(404, "")
        await model.save(8)
        await model.save(9)
        #expect(!model.isVisible && model.error == nil && api.calls == ["putWorkoutRPE"])
    }

    @Test func delete404ClearsTheRating() async throws {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, flags: [.recoveryCheckin: true])
        let workout = try Fixture.decode(Workout.self, "workout_rpe_response")
        let model = SessionRPEModel(env: env, workoutID: workout.id, workout: workout)
        api.failNext = APIError.http(404, "")
        await model.clear()
        #expect(model.isVisible && model.rating == nil && model.error == nil)
        #expect(api.calls == ["deleteWorkoutRPE"])
    }

    @Test func offlineAndFieldFailuresStayInline() async {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, flags: [.recoveryCheckin: true], online: false)
        let model = SessionRPEModel(env: env, workoutID: UUID())
        await model.save(8)
        #expect(model.error != nil && model.rating == nil && api.calls.isEmpty)
        env.connectivityMonitor.update(true)
        api.failNext = APIError.http(422, "Rating outside range.", requestID: "test")
        await model.save(8)
        #expect(model.error?.message == "Rating outside range." && model.error?.details?.contains("test") == true)
        #expect(model.rating == nil && model.isVisible && api.calls == ["putWorkoutRPE"])
    }

    @Test func consentRefusalReachesTheExistingGate() async {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, flags: [.recoveryCheckin: true])
        let apiStatus = APIStatus()
        let model = SessionRPEModel(env: env, workoutID: UUID(), apiStatus: apiStatus)
        api.failNext = APIError.http(403, "", code: .consentRequired)
        await model.save(8)
        #expect(apiStatus.gates.contains(.consentRequired) && model.rating == nil && model.error == nil)
    }
}
