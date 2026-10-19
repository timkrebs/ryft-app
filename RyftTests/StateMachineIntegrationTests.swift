import Foundation
import Testing
import Auth
@testable import Ryft

/// The machines inside their owners: the flows move them, and the old booleans
/// (`isRestoring`, `isSyncing`, `finishing`, `asking`) are derived from them.
@Suite("State machines in use")
@MainActor
struct StateMachineIntegrationTests {
    private func auth(_ client: MockAuthClient) -> AuthService {
        AuthService(client: client, defaults: UserDefaults(suiteName: "ryft.sm.\(UUID().uuidString)")!,
                    wipeLocalData: {}, deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                    postAppleAuthorization: { _ in })
    }

    // MARK: auth

    @Test func authRestoresThenSignsInAndOut() async {
        let client = MockAuthClient()
        let auth = auth(client)
        #expect(auth.phase == .restoring && auth.isRestoring)
        client.emit(.initialSession, nil)
        #expect(await eventually { auth.phase == .signedOut })

        let signing = Task { await auth.logIn(email: "a@b.c", password: "long-enough-password") }
        _ = await signing.value
        #expect(auth.phase == .signedIn && !auth.isWorking)

        await auth.signOut()
        #expect(auth.phase == .signedOut && auth.state == .signedOut)
    }

    @Test func aRevokedSessionExpires() async {
        let client = MockAuthClient(session: .preview())
        let auth = auth(client)
        #expect(auth.phase == .signedIn)
        for _ in 0..<20 { await Task.yield() } // the SDK observer subscribes
        client.emit(.signedOut, nil)
        #expect(await eventually { auth.phase == .expired })
        #expect(auth.signOutNotice != nil && auth.state == .signedOut)
    }

    @Test func aRefreshPassesThroughRefreshing() async throws {
        let client = MockAuthClient(session: .preview())
        let auth = auth(client)
        _ = try await auth.refreshedAccessToken()
        #expect(auth.phase == .signedIn)
    }

    @Test func aFailedSignInReturnsToSignedOut() async {
        let client = MockAuthClient()
        client.emailError = URLError(.notConnectedToInternet)
        let auth = auth(client)
        client.emit(.initialSession, nil)
        #expect(await eventually { auth.phase == .signedOut })
        await auth.logIn(email: "a@b.c", password: "long-enough-password")
        #expect(auth.phase == .signedOut && auth.errorMessage != nil)
    }

    // MARK: sync

    @Test func syncPhasesFollowTheUploadAndThePipeline() async {
        let t = Date(timeIntervalSince1970: 1_792_300_000)
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [
            HealthDelta(samples: [Sample(type: .heartRate, start: t, end: t, value: 60, unit: "bpm", source: "x")])
        ]])
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, health: health)
        let sync = SyncService(env: env)
        #expect(sync.phase == .idle && !sync.isSyncing)

        _ = try? await sync.upload()
        #expect(sync.phase == .uploading) // the coordinator takes it from here
        sync.advance(to: .refreshing)
        sync.advance(to: .done)
        #expect(sync.phase == .done)
        sync.advance(to: .uploading) // refused: done → uploading isn't an edge
        #expect(sync.phase == .done)
    }

    @Test func offlineSyncIsOffline() async {
        let sync = SyncService(env: .test(online: false))
        _ = try? await sync.upload()
        #expect(sync.phase == .offline)
    }

    @Test func aFailedUploadIsFailed() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [HealthDelta(samples: [
            Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "x")])]])
        let api = MockPlatformAPI()
        api.failure = APIError.http(500, "")
        let sync = SyncService(env: .test(api: api, health: health))
        _ = try? await sync.upload()
        #expect(sync.phase == .failed)
    }

    // MARK: live session

    @Test func theRestTimerMovesTheSessionBetweenActiveAndResting() throws {
        let store = TrainStore(inMemory: true)
        let trainSync = TrainSyncService(store: store, remote: { MockPlatformAPI() }, monitorsNetwork: false)
        let s = SessionFactory.empty(in: store)
        SessionFactory.add(MockTrain.bench, to: s, sets: 2, in: store)
        let c = SessionController(session: s, sync: trainSync, liveActivity: nil)
        #expect(c.phase == .active)

        let ex = try #require(c.exercises.first)
        // A SwiftData relationship has no order: take two distinct sets once.
        let sets = Array(ex.sets)
        try #require(sets.count == 2)
        c.toggleCheck(sets[0], in: ex)
        #expect(c.phase == .resting)
        c.skipRest()
        #expect(c.phase == .active)

        c.toggleCheck(sets[1], in: ex)
        c.pause()
        #expect(c.phase == .paused)
        c.resume()
        #expect(c.phase == .resting) // the timer kept running
        c.discard()
        #expect(c.phase == .discarded)
        c.resume()
        #expect(c.phase == .discarded)
        c.stop()
    }

    @Test func finishingCompletesOnce() async throws {
        let store = TrainStore(inMemory: true)
        let trainSync = TrainSyncService(store: store, remote: { MockPlatformAPI() }, monitorsNetwork: false)
        let s = SessionFactory.empty(in: store)
        SessionFactory.add(MockTrain.bench, to: s, sets: 1, in: store)
        let c = SessionController(session: s, sync: trainSync, liveActivity: nil)
        let ex = try #require(c.exercises.first)
        c.toggleCheck(try #require(ex.sets.first), in: ex)

        _ = await c.finish()
        #expect(c.phase == .completed && !c.isFinishing)
        #expect(await c.finish() == nil) // a second finish is refused
    }

    // MARK: Health onboarding

    @Test func connectingHandsOverToTheFirstSync() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let env = AppEnvironment.test(health: health)
        env.settings.healthIntroDone = false
        let vm = HealthOnboardingViewModel(env: env)
        #expect(vm.phase == .explain)
        await vm.connect()
        #expect(vm.phase == .firstSync)
        #expect(health.authorizationRequests == 1)
        #expect(env.settings.healthIntroDone)
    }

    @Test func notNowIsDenied() {
        let env = AppEnvironment.test()
        env.settings.healthIntroDone = false
        let vm = HealthOnboardingViewModel(env: env)
        vm.notNow()
        #expect(vm.phase == .denied && env.settings.healthIntroDone)
    }
}
