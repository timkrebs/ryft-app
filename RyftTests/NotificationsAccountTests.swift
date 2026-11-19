import Foundation
import Testing
@testable import Ryft

// PR 6 C's fix round (6c8): Notifications. A queued save is the account's that made it (security review S1), it waits
// as every settings write does (review S3: `SettingsWrite`), and a failed question leaves the user marked (review S5).
// Synthetic data only (Alex Doe).

// MARK: - Notifications: a queued save is the account's (S1)

@MainActor
struct NotificationAccountTests {
    private func model(_ h: WipeHarness) -> NotificationSettingsViewModel {
        h.state.user = MockData.user
        return NotificationSettingsViewModel(state: h.state, push: PushRegistrar(env: h.env))
    }

    @Test("A's first PATCH held, B signs in, it's released: A's queued second never reaches B's platform", .timeLimit(.minutes(1)))
    func aQueuedSaveStaysWithItsAccount() async throws {
        let h = WipeHarness()
        let api = try #require(h.env.liveAPI as? MockPlatformAPI)
        let model = model(h)
        let hold = RequestHold()
        api.beforePatchNotifications = { await hold.wait() }
        let first = Task { await model.set(.pr, on: false) }
        #expect(await eventually { hold.waiting == 1 })
        let second = Task { await model.set(.morningScore, on: false) }
        #expect(await eventually { !model.isOn(.morningScore) }, "shown at once, queued behind the first")

        await h.auth.signOut()
        await h.signIn(WipeHarness.b)
        #expect(h.auth.isSignedIn)
        // The queue is cancelled: nothing waits for A's answer.
        #expect(await eventually { !model.saving })
        hold.release()
        await first.value
        await second.value
        #expect(api.count("patchNotifications") == 1, "only A's first, sent while A was signed in")
        #expect(api.prefs.isOn(.morningScore), "the queued change never reached the platform")
        #expect(model.failure == nil && !model.saving)
    }

    @Test("Demo data on while the account's PATCH is out: the queued second goes to neither platform", .timeLimit(.minutes(1)))
    func aQueuedSaveStaysWithItsSide() async throws {
        let h = WipeHarness(demo: true)
        h.env.settings.demoMode = false
        h.state.reset()
        let account = try #require(h.env.liveAPI as? MockPlatformAPI)
        let demo = try #require(h.env.demoAPI as? MockPlatformAPI)
        let model = model(h)
        let hold = RequestHold()
        account.beforePatchNotifications = { await hold.wait() }
        let first = Task { await model.set(.pr, on: false) }
        #expect(await eventually { hold.waiting == 1 })
        let second = Task { await model.set(.morningScore, on: false) }
        #expect(await eventually { !model.isOn(.morningScore) })

        // The switch as `ProfileViewModel.setDemoMode(true)` turns it.
        h.env.settings.demoMode = true
        h.state.reset()
        #expect(await eventually { !model.saving }, "the queue is cancelled")
        hold.release()
        await first.value
        await second.value
        #expect(account.count("patchNotifications") == 1 && demo.count("patchNotifications") == 0)
        #expect(account.prefs.isOn(.morningScore) && demo.prefs.isOn(.morningScore))
        #expect(model.failure == nil)
    }

    @Test("No answer, and RYFT can't be asked: the cached user is marked, so the next refresh asks (S5)")
    func aFailedQuestionMarksTheUser() async throws {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, flags: [.pushEnabled: true])
        let state = AppState(env: env)
        state.user = MockData.user
        let model = NotificationSettingsViewModel(state: state, push: PushRegistrar(env: env))
        let reads = api.count("me")
        try await state.repository.refreshUser()
        #expect(api.count("me") == reads, "fresh: not asked")

        api.faults["me"] = FaultInjection.Rule(.notFound)
        api.failNext = APIError.http(503, "")
        await model.set(.pr, on: false)
        await model.asking?.value
        #expect(model.failure?.kind == .serverError && model.isOn(.pr))
        api.faults["me"] = nil
        let asked = api.count("me")
        try await state.repository.refreshUser()
        #expect(api.count("me") == asked + 1, "marked: the next .ifStale refresh asks")
        try await state.repository.refreshUser()
        #expect(api.count("me") == asked + 1, "asked once: the mark went with the answer")
    }
}

// MARK: - one wait for every settings write (S3)

@MainActor
struct NotificationsWaitTests {
    private func notifications(clock: TestClock = TestClock()) -> (NotificationSettingsViewModel, AppState, MockPlatformAPI) {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, clock: clock, flags: [.pushEnabled: true])
        let state = AppState(env: env)
        state.user = MockData.user
        return (NotificationSettingsViewModel(state: state, push: PushRegistrar(env: env)), state, api)
    }

    @Test("Notifications: no answer within 25 s, the page stops waiting, says it may not have saved and asks RYFT",
          .timeLimit(.minutes(1)))
    func notificationsGiveUpInTime() async {
        let clock = TestClock()
        let (model, _, api) = notifications(clock: clock)
        let hold = RequestHold()
        api.beforePatchNotifications = { await hold.wait() }
        let reads = api.count("me")
        let save = Task { await model.set(.pr, on: false) }
        #expect(await eventually { hold.waiting == 1 && clock.pendingSleeps == 1 })
        clock.advance(by: SettingsWrite.deadline - .seconds(1))
        #expect(model.saving, "24 s: still waiting")
        clock.advance(by: .seconds(1))
        await save.value
        #expect(!model.saving && model.failure?.kind == .noAnswer && model.isOn(.pr), "back as RYFT last confirmed it")
        await model.asking?.value
        #expect(api.count("me") > reads, "asked again")
        hold.release()
    }

    @Test("Notifications: the network goes while the PATCH is out: no answer at once, nothing asked offline, the user marked",
          .timeLimit(.minutes(1)))
    func notificationsGiveUpOffline() async throws {
        let (model, state, api) = notifications()
        let hold = RequestHold()
        api.beforePatchNotifications = { await hold.wait() }
        let save = Task { await model.set(.pr, on: false) }
        #expect(await eventually { hold.waiting == 1 })
        let reads = api.count("me")
        state.env.connectivityMonitor.update(false)
        await save.value
        #expect(!model.saving && model.failure?.kind == .noAnswer && model.isOn(.pr))
        #expect(model.asking == nil && api.count("me") == reads, "offline: nothing asked")
        state.env.connectivityMonitor.update(true)
        try await state.repository.refreshUser()
        #expect(api.count("me") == reads + 1, "marked: the next refresh asks")
        hold.release()
    }
}
