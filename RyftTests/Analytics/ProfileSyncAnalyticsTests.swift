import Foundation
import Testing
@testable import Ryft

/// Profile's "Sync now" row tracks `sync_triggered` and `sync_completed` (plan 2026-11-27, decision 10). Here: the
/// run that never starts, so the second event says `skipped`.
@Suite("Analytics: Profile's Sync now")
@MainActor
struct ProfileSyncAnalyticsTests {
    /// The environment's analytics replaced by a rig's, so its gate is open and its sink is the fake.
    private func profile(online: Bool, signedIn: Bool = true) -> (ProfileViewModel, AnalyticsRig) {
        let rig = AnalyticsRig()
        rig.optIn()
        let env = AppEnvironment.test(auth: .preview(signedIn: signedIn), online: online)
        env.analytics = rig.analytics
        let state = AppState(env: env)
        let sync = SyncService.ungated(env: env)
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock)
        return (ProfileViewModel(state: state, sync: sync, coordinator: coordinator), rig)
    }

    private let triggered = FakeAnalyticsSink.Capture(name: "sync_triggered", properties: ["trigger_source": "profile_button"])
    private let skipped = FakeAnalyticsSink.Capture(name: "sync_completed", properties: [
        "trigger_source": "profile_button", "status": "skipped", "duration_ms": "lt_1000",
    ])

    @Test func offlineStartsNothingAndSaysSkipped() async {
        let (model, rig) = profile(online: false)
        await model.syncNowFromProfile()
        #expect(rig.sink.captures == [triggered, skipped])
        #expect(rig.refusals.isEmpty)
    }

    @Test func noDataSourceStartsNothingAndSaysSkipped() async {
        let (model, rig) = profile(online: true, signedIn: false)
        await model.syncNowFromProfile()
        #expect(rig.sink.captures == [triggered, skipped])
        #expect(rig.refusals.isEmpty)
    }

    @Test func theTriggerComesBeforeTheEnd() async {
        let (model, rig) = profile(online: false)
        await model.syncNowFromProfile()
        #expect(rig.sink.captures.map(\.name) == ["sync_triggered", "sync_completed"])
    }

    @Test func nothingIsSentBeforeOptIn() async {
        let rig = AnalyticsRig()
        let env = AppEnvironment.test(online: false)
        env.analytics = rig.analytics
        let state = AppState(env: env)
        let sync = SyncService.ungated(env: env)
        let model = ProfileViewModel(state: state, sync: sync,
                                     coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock))
        await model.syncNowFromProfile()
        #expect(rig.sink.calls.isEmpty)
        #expect(rig.refusals.isEmpty)
    }
}
