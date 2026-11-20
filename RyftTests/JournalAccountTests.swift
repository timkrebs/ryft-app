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
        let kept = h.persistence.document([Behavior].self, key: JournalStore.behaviorsKey)
        #expect(kept?.contains { $0.name == "Evening walk" } == true, "the account's own list, on disk")
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
        // The account's list on disk is as it was: demo data's catalog never went there, nor the late answer's switch.
        #expect(h.persistence.document([Behavior].self, key: JournalStore.behaviorsKey) == kept)
    }

    @Test("A's day save, a day and the effects answered after B signed in change nothing of B's, in memory or on disk",
          .timeLimit(.minutes(1)))
    func aLateDayOrEffectsForAChangeNothingOfB() async throws {
        let h = WipeHarness()
        h.clock.set(.now)   // the mock takes days relative to the real date
        let api = try #require(h.env.liveAPI as? MockPlatformAPI)
        let store = try await loadA(h)
        let hold = RequestHold()
        api.beforeJournalAnswer = { _ in await hold.wait() }
        let yesterday = store.yesterday
        let earlier = DayFormat.string(from: DayFormat.shift(h.clock.now(), days: -2))
        let save = Task { try await store.save(day: yesterday, entries: [JournalEntry(behaviorId: MockJournal.sauna, valueBool: false)]) }
        let day = Task { await store.loadDay(earlier) }
        let effects = Task { await store.loadImpacts() }
        #expect(await eventually { hold.waiting == 3 })

        await h.auth.signOut()
        await h.signIn(WipeHarness.b)
        nothingOfA(store, h)
        hold.release()
        await #expect(throws: CancellationError.self) { try await save.value }
        #expect(await day.value == nil, "A's day isn't B's to show")
        await effects.value
        nothingOfA(store, h)
        #expect(store.cachedDay(earlier) == nil)
        #expect(h.persistence.document(JournalDay.self, key: JournalStore.dayKey(earlier)) == nil, "nor kept on disk")
    }
}

// MARK: - Journal: demo data's journal is never the account's, on either side (review 2, item 1)

@MainActor
struct JournalDemoSideTests {
    /// A harness on the account, Demo data off, at the real date (the mock takes days relative to it).
    private func onTheAccount() -> WipeHarness {
        let h = WipeHarness(demo: true)
        h.clock.set(.now)
        h.env.settings.demoMode = false
        h.state.reset()
        return h
    }

    private func switchDemo(_ h: WipeHarness, on: Bool) {
        h.env.settings.demoMode = on
        h.state.reset()
    }

    @Test("The account's saved day never shows in demo data, not even while demo data's day is on its way",
          .timeLimit(.minutes(1)))
    func demoNeverShowsTheAccountsDay() async throws {
        let h = onTheAccount()
        let demo = try #require(h.env.demoAPI as? MockPlatformAPI)
        let store = JournalStore(state: h.state)
        await store.load()
        let day = store.yesterday
        let mine = [JournalEntry(behaviorId: MockJournal.drinks, valueBool: true, valueNum: 7)]
        try await store.save(day: day, entries: mine)
        #expect(store.cachedDay(day)?.entries == mine, "the account's answers")

        switchDemo(h, on: true)
        await store.load()
        let hold = RequestHold()
        demo.beforeJournalAnswer = { name in if name == "journal" { await hold.wait() } }
        let asking = Task { await store.loadDay(day) }
        #expect(await eventually { hold.waiting == 1 })
        #expect(store.days[day] == nil && store.cachedDay(day) == nil, "nothing of the account's while demo data's day is out")
        #expect(JournalSheetModel(store: store, day: day).groups.allSatisfy { $0.rows.allSatisfy { $0.count != 7 } },
                "the sheet isn't prefilled with the account's answers")
        hold.release()
        let shown = await asking.value
        #expect(shown != nil && shown?.entries != mine, "demo data's own day")
        #expect(h.persistence.document(JournalDay.self, key: JournalStore.dayKey(day))?.entries == mine,
                "the account's day on disk, untouched")
    }

    @Test("Demo data off, the account's reads failing: nothing of demo data's catalog, day or effects shows, nor at the next launch",
          .timeLimit(.minutes(1)))
    func demoOffLeavesNothingOfDemos() async throws {
        let h = onTheAccount()
        let account = try #require(h.env.liveAPI as? MockPlatformAPI)
        let store = JournalStore(state: h.state)
        await store.load()
        try await store.create(name: "Evening walk", nameDe: nil, kind: .yesNo, category: .custom)
        let accountList = store.behaviors
        #expect(store.impacts == nil && store.cachedDay(store.yesterday) == nil, "the account has no effects or day yet")

        // Demo data: its own catalog (with a habit of its own), yesterday's answers and the effects.
        switchDemo(h, on: true)
        await store.load()
        try await store.create(name: "Demo walk", nameDe: nil, kind: .yesNo, category: .custom)
        await store.loadDay(store.yesterday)
        await store.loadImpacts()
        #expect(store.cachedDay(store.yesterday)?.answered == true && store.impacts != nil)

        account.failure = APIError.http(400, "")
        switchDemo(h, on: false)
        await store.load()
        await store.loadDay(store.yesterday)
        await store.loadImpacts()
        #expect(store.behaviors == accountList, "the account's own catalog, from its store")
        #expect(!store.behaviors.contains { $0.name == "Demo walk" })
        #expect(store.cachedDay(store.yesterday) == nil && store.impacts == nil, "no day or effects of demo data's")

        let relaunched = JournalStore(env: h.env)
        #expect(relaunched.behaviors == accountList && relaunched.impacts == nil, "nor in the store, at the next launch")
        #expect(relaunched.cachedDay(relaunched.yesterday) == nil)
    }

    @Test("5: the journal sheet opened on the account, demo data on before Save: nothing is sent, to either side, and the sheet closes quietly",
          .timeLimit(.minutes(1)))
    func theSheetStaysWithItsSide() async throws {
        let h = onTheAccount()
        let live = try #require(h.env.liveAPI as? MockPlatformAPI)
        let demo = try #require(h.env.demoAPI as? MockPlatformAPI)
        let store = JournalStore(state: h.state)
        await store.load()
        let sheet = JournalSheetModel(store: store)
        await sheet.load()
        let row = try #require(sheet.groups.first?.rows.first)
        sheet.set(row.id, on: !row.on)

        switchDemo(h, on: true)
        let puts = (live.count("putJournal"), demo.count("putJournal"))
        await sheet.save()
        #expect(sheet.leftItsSide && !sheet.saved && sheet.error == nil, "closes without a word")
        #expect(live.count("putJournal") == puts.0 && demo.count("putJournal") == puts.1, "nothing sent, to either side")
    }

    @Test("5: the journal sheet's save answered after demo data came on: nothing is kept, nothing is said, and the sheet closes quietly",
          .timeLimit(.minutes(1)))
    func theSheetsLateSaveClosesQuietly() async throws {
        let h = onTheAccount()
        let live = try #require(h.env.liveAPI as? MockPlatformAPI)
        let store = JournalStore(state: h.state)
        await store.load()
        let sheet = JournalSheetModel(store: store)
        await sheet.load()
        let row = try #require(sheet.groups.first?.rows.first)
        sheet.set(row.id, on: !row.on)
        let hold = RequestHold()
        live.beforeJournalAnswer = { name in if name == "putJournal" { await hold.wait() } }
        let saving = Task { await sheet.save() }
        #expect(await eventually { hold.waiting == 1 })

        switchDemo(h, on: true)
        hold.release()
        #expect(await saving.value == false)
        #expect(sheet.leftItsSide && sheet.error == nil && !sheet.saved, "closes without a word")
        #expect(live.count("putJournal") == 1, "the one save, sent while the sheet was the account's")
    }

    @Test("5: the journal sheet open while the account's journal is forgotten (a wipe): Save sends nothing")
    func theSheetStaysWithItsJournal() async throws {
        let h = onTheAccount()
        let live = try #require(h.env.liveAPI as? MockPlatformAPI)
        let store = JournalStore(state: h.state)
        await store.load()
        let sheet = JournalSheetModel(store: store)
        await sheet.load()
        store.accountChanged()
        let puts = live.count("putJournal")
        await sheet.save()
        #expect(sheet.leftItsSide && !sheet.saved && live.count("putJournal") == puts)

        // A sheet opened now is the journal's again, and saves.
        await store.load()
        let again = JournalSheetModel(store: store)
        await again.load()
        await again.save()
        #expect(again.saved && !again.leftItsSide && live.count("putJournal") == puts + 1)
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

/// Answers every request with a `429` (`Retry-After: 1`) and counts them. Its own state: no other suite uses it.
private final class TooManyRequests: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String] = []

    static func reset() { lock.withLock { seen = [] } }
    static var requests: [String] { lock.withLock { seen } }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.seen.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")") }
        let response = HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 429, httpVersion: "HTTP/1.1",
                                       headerFields: ["Retry-After": "1"])
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct SettingsWriteOneAttemptTests {
    @Test("Every page's write runs as one attempt (the editors', Notifications', Journal's)")
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
    }

    @Test("A 429 through the real client: one request for each page's write, and it's said at once as busy",
          .timeLimit(.minutes(1)))
    func aBusyAnswerIsOneRequest() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TooManyRequests.self]
        let base = URL(string: "https://api.test") ?? URL(fileURLWithPath: "/")
        // A retry would wait `Retry-After` here: none waits, so a second attempt would show only in the count.
        let client = APIClient(session: URLSession(configuration: config), tokens: FakeTokens(), sleep: { _ in },
                               baseURL: base, status: APIStatus())
        let clock = TestClock(now: .now)
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let env = AppEnvironment(settings: Settings(defaults: defaults), health: MockHealthStore(), liveAPI: client,
                                 demoAPI: MockPlatformAPI(), auth: .preview(), persistence: TrainStore(inMemory: true),
                                 clock: clock, notifier: MockNotifier(), flags: StaticFlags([.pushEnabled: true]),
                                 connectivity: .preview(online: true), defaults: defaults, demoOverride: false)
        let state = AppState(env: env)
        state.user = MockData.user

        TooManyRequests.reset()
        let model = NotificationSettingsViewModel(state: state, push: PushRegistrar(env: env))
        await model.set(.pr, on: false)
        #expect(TooManyRequests.requests.count == 1, "Notifications: \(TooManyRequests.requests)")
        #expect(model.failure?.kind == .busy && model.failure?.message == busyWords)

        TooManyRequests.reset()
        let store = JournalStore(env: env)
        do {
            try await store.setEnabled(MockJournal.magnesium, false)
            Issue.record("a 429 is a failure")
        } catch {
            #expect(JournalSettingsFailure(error).message == busyWords)
        }
        #expect(TooManyRequests.requests.count == 1, "Journal: \(TooManyRequests.requests)")
        #expect(store.rereading == nil, "busy: nothing changed, nothing to ask")

        TooManyRequests.reset()
        let editor = BodySettingsEditor(state: state)
        #expect(await editor.setSleepBase(465) == false)
        #expect(TooManyRequests.requests.count == 1, "the editors: \(TooManyRequests.requests)")
    }
}
