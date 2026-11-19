import Foundation
import Testing
@testable import Ryft

// PR 6 C's fix round (6c8): Journal. Its reads and writes are the account's (security review S2, pre-existing), its habit
// writes wait as every settings write does (review S3: `SettingsWrite`), and every page's write is one attempt.
// Synthetic data only (Alex Doe).

/// What the fake platform saw of `APIClient.singleAttempt` while it answered, in order.
private final class SeenAttempts: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [Bool] = []

    func note() { lock.withLock { all.append(APIClient.singleAttempt) } }
    var values: [Bool] { lock.withLock { all } }
}

private let busyWords = "RYFT is busy right now, so this wasn't saved. Try again in a minute."

// MARK: - Journal: the account's (S2)

@MainActor
struct JournalAccountTests {
    /// A's journal on this iPhone: the catalog with a habit of A's own, yesterday's answers and the effects.
    private func loadA(_ h: WipeHarness) async throws -> JournalStore {
        let store = JournalStore(state: h.state)
        await store.load()
        try await store.create(name: "Evening walk", nameDe: nil, kind: .yesNo, category: .custom)
        await store.loadDay(store.yesterday)
        await store.loadImpacts()
        #expect(store.isLive && store.behaviors.contains { $0.name == "Evening walk" })
        #expect(store.cachedDay(store.yesterday) != nil && store.impacts != nil)
        return store
    }

    /// Nothing of A's journal is shown, kept in memory, or in the store on disk.
    private func nothingOfA(_ store: JournalStore, _ h: WipeHarness) {
        #expect(store.behaviors.isEmpty && store.availability == .unknown && !store.isLive)
        #expect(store.impacts == nil && store.error == nil)
        #expect(store.behavior(MockJournal.meeting) == nil && !store.behaviors.contains { $0.name == "Evening walk" })
        #expect(store.cachedDay(store.yesterday) == nil, "no day of A's, in memory or on disk")
        #expect(h.persistence.document([Behavior].self, key: JournalStore.behaviorsKey) == nil)
        #expect(h.persistence.document(BehaviorImpacts.self, key: JournalStore.impactKey) == nil)
    }

    @Test("A signs out and B signs in: nothing of A's journal shows (its own habits, its answers, its effects)")
    func anotherAccountSeesNothingOfA() async throws {
        let h = WipeHarness()
        let store = try await loadA(h)
        await h.auth.signOut()
        await h.signIn(WipeHarness.b)
        #expect(h.auth.isSignedIn)
        nothingOfA(store, h)
    }

    @Test("A's habit writes answered after B signed in change nothing of B's, in memory or on disk", .timeLimit(.minutes(1)))
    func aLateWriteForAChangesNothingOfB() async throws {
        let h = WipeHarness()
        let api = try #require(h.env.liveAPI as? MockPlatformAPI)
        let store = try await loadA(h)
        let hold = RequestHold()
        api.beforeBehaviorWrite = { _ in await hold.wait() }
        let toggle = Task { try await store.setEnabled(MockJournal.magnesium, true) }
        let add = Task { try await store.create(name: "Late reading", nameDe: nil, kind: .yesNo, category: .custom) }
        let remove = Task { try await store.delete(MockJournal.meeting) }
        #expect(await eventually { hold.waiting == 3 })

        await h.auth.signOut()
        await h.signIn(WipeHarness.b)
        nothingOfA(store, h)
        hold.release()
        await #expect(throws: CancellationError.self) { try await toggle.value }
        await #expect(throws: CancellationError.self) { _ = try await add.value }
        await #expect(throws: CancellationError.self) { try await remove.value }
        nothingOfA(store, h)
        #expect(store.rereading == nil, "nothing asked again for A")
    }

    @Test("Demo data on: the account's journal goes, and its write answered after the switch changes nothing",
          .timeLimit(.minutes(1)))
    func demoOnForgetsTheAccountsJournal() async throws {
        let h = WipeHarness(demo: true)
        h.env.settings.demoMode = false
        h.state.reset()
        let account = try #require(h.env.liveAPI as? MockPlatformAPI)
        let store = JournalStore(state: h.state)
        await store.load()
        try await store.create(name: "Evening walk", nameDe: nil, kind: .yesNo, category: .custom)
        await store.loadImpacts()
        let hold = RequestHold()
        account.beforeBehaviorWrite = { _ in await hold.wait() }
        let toggle = Task { try await store.setEnabled(MockJournal.magnesium, true) }
        #expect(await eventually { hold.waiting == 1 })

        h.env.settings.demoMode = true
        h.state.reset()
        #expect(store.behaviors.isEmpty && store.availability == .unknown && store.impacts == nil)
        await store.load()
        #expect(store.isLive && !store.behaviors.contains { $0.name == "Evening walk" }, "demo data's own catalog")
        let demoList = store.behaviors
        hold.release()
        await #expect(throws: CancellationError.self) { try await toggle.value }
        #expect(store.behaviors == demoList, "the account's late answer changed nothing")
        let kept = h.persistence.document([Behavior].self, key: JournalStore.behaviorsKey) ?? []
        #expect(!kept.contains { $0.name == "Evening walk" }, "nor what's kept on disk")
    }
}

// MARK: - one wait for every settings write (S3)

@MainActor
struct JournalWaitTests {
    /// The mock answers relative to the real date, so the clock starts there too.
    private func journal(clock: TestClock = TestClock(now: .now)) async -> (JournalStore, AppEnvironment, MockPlatformAPI) {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, clock: clock)
        let store = JournalStore(env: env)
        await store.load()
        return (store, env, api)
    }

    @Test("Journal: no answer within 25 s, the habit's write gives up and the list is asked again", .timeLimit(.minutes(1)))
    func journalGivesUpInTime() async {
        let clock = TestClock(now: .now)
        let (store, _, api) = await journal(clock: clock)
        let before = store.behavior(MockJournal.magnesium)?.enabled
        let hold = RequestHold()
        api.beforeBehaviorWrite = { _ in await hold.wait() }
        let reads = api.count("behaviors")
        let toggle = Task { try await store.setEnabled(MockJournal.magnesium, before != true) }
        #expect(await eventually { hold.waiting == 1 && clock.pendingSleeps == 1 })
        clock.advance(by: SettingsWrite.deadline - .seconds(1))
        #expect(clock.pendingSleeps == 1, "24 s: still waiting")
        clock.advance(by: .seconds(1))
        await #expect(throws: SettingsWrite.NoAnswer.self) { try await toggle.value }
        #expect(JournalSettingsFailure(SettingsWrite.NoAnswer()).kind == .noAnswer)
        await store.rereading?.value
        #expect(api.count("behaviors") == reads + 1, "asked again")
        #expect(store.behavior(MockJournal.magnesium)?.enabled == before, "as RYFT holds it")
        hold.release()
    }

    @Test("Journal: the network goes while a habit's write is out: no answer at once, nothing asked offline",
          .timeLimit(.minutes(1)))
    func journalGivesUpOffline() async {
        let (store, env, api) = await journal()
        let hold = RequestHold()
        api.beforeBehaviorWrite = { _ in await hold.wait() }
        let reads = api.count("behaviors")
        let remove = Task { try await store.delete(MockJournal.meeting) }
        #expect(await eventually { hold.waiting == 1 })
        env.connectivityMonitor.update(false)
        await #expect(throws: SettingsWrite.NoAnswer.self) { try await remove.value }
        #expect(store.rereading == nil && api.count("behaviors") == reads, "offline: nothing asked")
        #expect(store.behavior(MockJournal.meeting) != nil, "not taken off before RYFT answered")
        hold.release()
    }
}

@MainActor
struct SettingsWriteOneAttemptTests {
    @Test("Every page's write is one attempt (the editors', Notifications', Journal's): a 429 comes back at once as busy")
    func oneAttempt() async throws {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, clock: TestClock(now: .now), flags: [.pushEnabled: true])
        let state = AppState(env: env)
        state.user = MockData.user
        let seen = SeenAttempts()
        api.beforePatchNotifications = { seen.note() }
        api.beforeBehaviorWrite = { _ in seen.note() }
        api.beforePatchMe = { seen.note() }
        let model = NotificationSettingsViewModel(state: state, push: PushRegistrar(env: env))
        await model.set(.pr, on: false)
        let store = JournalStore(env: env)
        await store.load()
        try await store.setEnabled(MockJournal.magnesium, true)
        let editor = BodySettingsEditor(state: state)
        #expect(await editor.setSleepBase(465))
        #expect(seen.values == [true, true, true], "\(seen.values)")
        #expect(!APIClient.singleAttempt, "only the write's own task")

        api.failNext = APIError.http(429, "", retryAfter: 30)
        await model.set(.pr, on: true)
        #expect(model.failure?.kind == .busy && model.failure?.message == busyWords)
        api.failNext = APIError.http(429, "", retryAfter: 30)
        do {
            try await store.setEnabled(MockJournal.magnesium, false)
            Issue.record("a 429 is a failure")
        } catch {
            #expect(JournalSettingsFailure(error).message == busyWords)
        }
        #expect(store.rereading == nil, "busy: nothing changed, nothing to ask")
    }
}
