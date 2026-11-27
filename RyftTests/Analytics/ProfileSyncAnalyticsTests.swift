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
        let homeSync = HomeSyncModel(state: state, sync: sync, coordinator: coordinator)
        return (ProfileViewModel(state: state, sync: sync, coordinator: coordinator, homeSync: homeSync), rig)
    }

    private let triggered = FakeAnalyticsSink.Capture(name: "sync_triggered", properties: [
        "trigger_source": "profile_button", "previous_state": "stale",
    ])
    private let skipped = FakeAnalyticsSink.Capture(name: "sync_completed", properties: [
        "trigger_source": "profile_button", "status": "skipped", "duration_ms": "lt_1000",
        "connected_providers_count": "0",
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
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock)
        let homeSync = HomeSyncModel(state: state, sync: sync, coordinator: coordinator)
        let model = ProfileViewModel(state: state, sync: sync, coordinator: coordinator, homeSync: homeSync)
        await model.syncNowFromProfile()
        #expect(rig.sink.calls.isEmpty)
        #expect(rig.refusals.isEmpty)
    }

    @Test func theStatusRetryAndTheConnectionTestDontTrack() async {
        let (model, rig) = profile(online: false)
        await model.syncNow()
        #expect(rig.sink.captures.isEmpty)
        #expect(rig.refusals.isEmpty)
    }
}
