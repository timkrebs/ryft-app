import Foundation
import Testing
@testable import Ryft

// PR 6 C's fix round (6c8): Notifications. A queued save is the account's that made it (security review S1), it waits
// as every settings write does (review S3: `SettingsWrite`), and a failed question leaves the user marked (review S5). A save
// that may have saved marks the user whether it's the latest or not, and a later success reads the settings back (round 2).
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

    @Test("A signs out while a PATCH is out, nobody signs in: the queued second is never sent, the page shows no one's change",
          .timeLimit(.minutes(1)))
    func aSignOutAloneDropsTheQueue() async throws {
        let h = WipeHarness()
        let api = try #require(h.env.liveAPI as? MockPlatformAPI)
        let model = model(h)
        let hold = RequestHold()
        api.beforePatchNotifications = { await hold.wait() }
        let first = Task { await model.set(.pr, on: false) }
        #expect(await eventually { hold.waiting == 1 })
        let second = Task { await model.set(.morningScore, on: false) }
        #expect(await eventually { !model.isOn(.morningScore) })

        await h.auth.signOut()
        #expect(!h.auth.isSignedIn)
        #expect(await eventually { !model.saving }, "the queue is cancelled at the sign-out itself")
        #expect(model.isOn(.pr) && model.isOn(.morningScore), "neither of A's changes shows")
        hold.release()
        await first.value
        await second.value
        #expect(api.count("patchNotifications") == 1 && api.prefs.isOn(.morningScore), "the second never went")
        #expect(model.isOn(.pr) && model.isOn(.morningScore) && model.failure == nil, "A's late answer changed nothing")
    }

    @Test("Demo data off while demo's PATCH is out: the queued second goes to neither, the page shows the account's settings",
          .timeLimit(.minutes(1)))
    func demoOffDropsTheQueue() async throws {
        let h = WipeHarness(demo: true)
        let account = try #require(h.env.liveAPI as? MockPlatformAPI)
        let demo = try #require(h.env.demoAPI as? MockPlatformAPI)
        // The account's settings as its store has them: PRs off.
        var user = MockData.user
        user.notifications = NotificationPrefs(categories: [NotificationCategory.pr.rawValue: false], quietHours: nil)
        h.state.repository.writingToAccountStore { h.state.user = user }
        let model = model(h)
        #expect(model.isOn(.pr), "demo data's settings")
        let hold = RequestHold()
        demo.beforePatchNotifications = { await hold.wait() }
        let first = Task { await model.set(.sessionScored, on: false) }
        #expect(await eventually { hold.waiting == 1 })
        let second = Task { await model.set(.morningScore, on: false) }
        #expect(await eventually { !model.isOn(.morningScore) })

        h.env.settings.demoMode = false
        h.state.reset()
        #expect(await eventually { !model.saving }, "the queue is cancelled")
        #expect(!model.isOn(.pr) && model.isOn(.morningScore) && model.isOn(.sessionScored), "the account's, as its store has them")
        hold.release()
        await first.value
        await second.value
        #expect(demo.count("patchNotifications") == 1 && account.count("patchNotifications") == 0)
        #expect(demo.prefs.isOn(.morningScore) && account.prefs.isOn(.morningScore) && account.prefs.isOn(.sessionScored))
        #expect(!model.isOn(.pr) && model.isOn(.sessionScored) && model.failure == nil, "demo's late answer changed nothing")
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

// MARK: - a save that may have saved, the latest or not (review 2, item 2)

/// Counts the calls a hook sees, from any thread.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0

    func next() -> Int { lock.withLock { n += 1; return n } }
}

@MainActor
struct NotificationUnsureSaveTests {
    /// Save 1 (PRs off) held at the platform and given up on after 25 s while save 2 (morning score off) waits behind it;
    /// save 2 then held on its way. The second hold is the one `PATCH 2` waits on.
    private func oneUnanswered() async -> (NotificationSettingsViewModel, AppState, MockPlatformAPI, first: RequestHold,
                                             second: RequestHold, Task<Void, Never>, Task<Void, Never>) {
        let clock = TestClock()
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, clock: clock, flags: [.pushEnabled: true])
        let state = AppState(env: env)
        state.user = MockData.user
        let model = NotificationSettingsViewModel(state: state, push: PushRegistrar(env: env))
        let holds = (RequestHold(), RequestHold())
        let calls = Calls()
        api.beforePatchNotifications = { if calls.next() == 1 { await holds.0.wait() } else { await holds.1.wait() } }
        let one = Task { await model.set(.pr, on: false) }
        #expect(await eventually { holds.0.waiting == 1 && clock.pendingSleeps == 1 })
        let two = Task { await model.set(.morningScore, on: false) }
        #expect(await eventually { !model.isOn(.morningScore) })
        clock.advance(by: SettingsWrite.deadline)
        await one.value
        #expect(await eventually { holds.1.waiting == 1 }, "save 2 went once save 1 gave up")
        return (model, state, api, holds.0, holds.1, one, two)
    }

    @Test("Save 1 gets no answer while save 2 waits behind it: no words for it, but the cached user is marked", .timeLimit(.minutes(1)))
    func anEarlierUnansweredSaveMarksTheUser() async throws {
        let (model, state, api, first, second, _, two) = await oneUnanswered()
        #expect(model.failure == nil && model.saving, "not the latest: its failure isn't the page's to say")
        let asked = api.count("me")
        try await state.repository.refreshUser()
        #expect(api.count("me") == asked + 1, "marked: the next .ifStale refresh asks")
        first.release()
        second.release()
        await two.value
    }

    @Test("Save 2 succeeds after save 1 got no answer, and save 1 lands after it: the page reads RYFT's settings back once",
          .timeLimit(.minutes(1)))
    func aLaterSuccessReadsTheSettingsBack() async throws {
        let (model, state, api, first, second, _, two) = await oneUnanswered()
        let meHold = RequestHold()
        api.beforeMeRead = { await meHold.wait() }
        let asked = api.count("me")
        second.release()
        #expect(await eventually { meHold.waiting == 1 }, "save 2 answered; RYFT is asked again")
        #expect(model.isOn(.pr) && !model.isOn(.morningScore), "save 2's answer: save 1 hadn't landed")
        // The abandoned write lands now, after the newer one.
        first.release()
        #expect(await eventually { !api.prefs.isOn(.pr) })
        meHold.release()
        await two.value
        #expect(api.count("me") == asked + 1, "read back once")
        #expect(!model.isOn(.pr) && !model.isOn(.morningScore), "the page shows what RYFT holds")
        #expect(state.user?.notifications.isOn(.pr) == false && model.failure == nil)
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
