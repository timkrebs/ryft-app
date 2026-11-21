import Foundation
import Testing
@testable import Ryft

// C1's fix round: the writes behind Journal settings, Add a habit and Notifications. Answers that arrive late don't undo
// what the page shows, a retried habit isn't added twice, and a failure says what happened in calm words.

// MARK: - Journal: answers in order (S6)

@MainActor
struct JournalWriteOrderTests {
    /// The mock answers relative to the real date, so the clock starts there too.
    private func makeStore(_ api: MockPlatformAPI = MockPlatformAPI()) async -> (JournalStore, AppEnvironment) {
        let env = AppEnvironment.test(api: api, clock: TestClock(now: .now))
        let store = JournalStore(env: env)
        await store.load()
        return (store, env)
    }

    @Test("The page's opening list, answered after a switch was saved, doesn't turn the switch back")
    func anOpeningListCantUndoASwitch() async throws {
        let api = MockPlatformAPI()
        let (store, _) = await makeStore(api)
        #expect(store.behavior(MockJournal.alcohol)?.enabled == true)
        let gate = Gate()
        store.beforeApplying = { route in if route == "behaviors" { await gate.wait() } }
        // The list is read (Alcohol on), then held on its way back.
        let opening = Task { await store.load() }
        #expect(await eventually { api.count("behaviors") == 2 })
        store.beforeApplying = nil
        try await store.setEnabled(MockJournal.alcohol, false)
        #expect(store.behavior(MockJournal.alcohol)?.enabled == false)
        await gate.open()
        await opening.value
        #expect(store.behavior(MockJournal.alcohol)?.enabled == false, "the older list was dropped")
        #expect(store.isLive)
        // A list asked for after the switch applies again.
        await store.load()
        #expect(store.behavior(MockJournal.alcohol)?.enabled == false && api.count("behaviors") == 3)
    }

    @Test("A switch's answer that arrives after a delete doesn't bring the deleted habit back")
    func aLatePatchCantBringBackADeletedHabit() async throws {
        let api = MockPlatformAPI()
        let (store, env) = await makeStore(api)
        #expect(store.behavior(MockJournal.meeting) != nil)
        let gate = Gate()
        store.beforeApplying = { route in if route == "patchBehaviors" { await gate.wait() } }
        // Alcohol off: the platform answers with the whole list, the meeting still in it, and the answer is held.
        let toggle = Task { try await store.setEnabled(MockJournal.alcohol, false) }
        #expect(await eventually { api.count("patchBehaviors") == 1 })
        try await store.delete(MockJournal.meeting)
        #expect(store.behavior(MockJournal.meeting) == nil)
        await gate.open()
        try await toggle.value
        #expect(store.behavior(MockJournal.meeting) == nil, "the late list didn't bring it back")
        #expect(store.behavior(MockJournal.alcohol)?.enabled == false, "its own switch is still taken from it")
        // And the cache a relaunch reads agrees.
        let relaunched = JournalStore(env: env)
        #expect(!relaunched.behaviors.isEmpty && relaunched.behavior(MockJournal.meeting) == nil)
    }

    @Test("Without another write meanwhile, a switch's answer is the whole list, as before")
    func aPatchAloneTakesTheWholeList() async throws {
        let (store, _) = await makeStore()
        try await store.setEnabled(MockJournal.magnesium, true)
        #expect(store.behavior(MockJournal.magnesium)?.enabled == true)
        #expect(store.behaviors.count == MockJournal.behaviors.count)
    }

    @Test("Adding the same habit again with the same id updates it: one habit, not two (a retry after no answer)")
    func aRetryWithTheSameIDUpdates() async throws {
        let api = MockPlatformAPI()
        let (store, _) = await makeStore(api)
        let id = UUID()
        try await store.create(name: "Evening walk", nameDe: nil, kind: .yesNo, category: .custom, id: id)
        try await store.create(name: "Evening walk", nameDe: nil, kind: .yesNo, category: .custom, id: id)
        #expect(api.count("createBehavior") == 2)
        #expect(store.behaviors.filter { $0.name == "Evening walk" }.count == 1)
        let platform = try await api.behaviors()
        #expect(platform.filter { $0.id == id }.count == 1)
    }
}

// MARK: - Add a habit and Journal: limits and words (S2)

@MainActor
struct JournalSettingsRulesTests {
    @Test("A name is counted in Unicode scalars, as the platform counts runes")
    func namesCountScalars() {
        // "é" typed as "e" and a combining accent: one character, two scalars.
        let accented = "e\u{301}"
        #expect(String(repeating: accented, count: 30).count == 30)
        #expect(AddBehaviorSheet.isValid(name: String(repeating: accented, count: 30)), "60 scalars")
        #expect(!AddBehaviorSheet.isValid(name: String(repeating: accented, count: 31)), "62 scalars, though 31 characters")
        #expect(AddBehaviorSheet.isValid(name: String(repeating: "a", count: 60)))
    }

    private func own(_ count: Int) -> [Behavior] {
        (0..<count).map { n in
            Behavior(id: UUID(), slug: "habit-\(n)", name: "Habit \(n)", nameEn: "Habit \(n)", nameDe: "Habit \(n)",
                     category: .custom, kind: .yesNo, defaultOn: true, enabled: true, isCustom: true, sort: n)
        }
    }

    @Test("50 of the user's own is the most: the sheet knows before it sends; its own habit (a retry that saved) doesn't count")
    func fiftyOwnHabits() throws {
        #expect(AddBehaviorSheet.maxOwn == 50)
        #expect(!AddBehaviorSheet.isFull(MockJournal.behaviors + own(48), adding: UUID()), "49 own")
        #expect(AddBehaviorSheet.isFull(MockJournal.behaviors + own(49), adding: UUID()), "50 own")
        let fifty = own(50)
        let sheets = try #require(fifty.last?.id)
        #expect(!AddBehaviorSheet.isFull(fifty, adding: sheets), "the 50th is this sheet's own, saved by a retry")
        #expect(!AddBehaviorSheet.isFull(MockJournal.behaviors.filter { !$0.isCustom } + own(49), adding: UUID()))
    }

    /// Journal's write failures and how the settings pages judge them (`SettingsWriteFailure`, PR 6 C review S4).
    private nonisolated static let failures: [(any Error, SettingsWriteFailure)] = [
        // Offline: nothing was sent.
        (JournalStore.JournalError.offline, .offline), (APIError.transport(URLError(.notConnectedToInternet)), .offline),
        // Sent, and no readable answer: it may have saved (an unreadable 2xx did: RYFT stored it).
        (APIError.http(200, "unreadable"), .noAnswer), (APIError.transport(URLError(.timedOut)), .noAnswer),
        (APIError.transport(URLError(.networkConnectionLost)), .noAnswer), (SettingsWrite.NoAnswer(), .noAnswer),
        // RYFT answered.
        (APIError.http(500, ""), .serverError), (APIError.http(503, "request timed out"), .serverError),
        (APIError.http(429, "slow down"), .busy),
        (APIError.http(409, ""), .refused), (APIError.http(403, "built-in"), .refused),
        (JournalStore.JournalError.idTaken, .refused),
    ]

    @Test("Journal's failures in the settings pages' words: what left the phone decides", arguments: failures)
    func classified(_ error: any Error, _ kind: SettingsWriteFailure) {
        let failure = JournalSettingsFailure(error)
        #expect(failure.kind == kind && failure.message == kind.saveMessage, "\(failure.message)")
    }

    @Test("An unreadable 2xx never says nothing changed: RYFT stored it")
    func anUnreadableAnswerMayHaveSaved() {
        let failure = JournalSettingsFailure(APIError.http(200, "", requestID: "01a1-200"))
        #expect(failure.message == "RYFT didn't answer, so this may not have saved. Try again in a moment.")
        #expect(!failure.message.localizedCaseInsensitiveContains("nothing changed") && failure.kind.rereads)
        #expect(failure.details == "HTTP 200 · Request ID 01a1-200")
    }

    @Test("Busy, refused and a server error have their own words, not one \"try again in a moment\"")
    func busyRefusedAndServerErrorDiffer() {
        let busy = JournalSettingsFailure(APIError.http(429, "slow down")).message
        let refused = JournalSettingsFailure(APIError.http(409, "")).message
        let serverError = JournalSettingsFailure(APIError.http(503, "", requestID: "01a1-503"))
        #expect(busy == "RYFT is busy right now, so this wasn't saved. Try again in a minute.")
        #expect(refused == "RYFT couldn't save this change, so it's back as it was.")
        #expect(serverError.message == "RYFT had a problem saving this, so it's back as it was. Try again in a moment.")
        #expect(serverError.details == "HTTP 503 · Request ID 01a1-503")
        #expect(JournalSettingsFailure(JournalStore.JournalError.offline).message
            == "You're offline, so this wasn't saved. Try again when you're back online.")
    }

    @Test("A 422: RYFT refused it, calmly, without 'try again'; the request ID is the caption, never the platform's text")
    func refused() {
        let failure = JournalSettingsFailure(APIError.http(422, "too many custom behaviors", requestID: "01a1-422"))
        #expect(failure.message == "RYFT didn't accept that, so nothing changed.")
        #expect(failure.kind == .refused && !failure.kind.rereads)
        #expect(!failure.message.localizedCaseInsensitiveContains("try again"))
        #expect(!failure.message.localizedCaseInsensitiveContains("behavior"))
        #expect(failure.details == "HTTP 422 · Request ID 01a1-422")
    }

    @Test("No answer or a 5xx: the list is asked again, so the page shows what RYFT holds; a refusal isn't")
    func unsureWritesReread() async throws {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, clock: TestClock(now: .now))
        let store = JournalStore(env: env)
        await store.load()
        for (error, rereads) in [(APIError.transport(URLError(.timedOut)), true), (APIError.http(200, ""), true),
                                 (APIError.http(503, ""), true), (APIError.http(409, ""), false),
                                 (APIError.http(429, ""), false)] {
            let reads = api.count("behaviors")
            api.failNext = error
            await #expect(throws: (any Error).self) { try await store.setEnabled(MockJournal.magnesium, true) }
            await store.rereading?.value
            #expect((api.count("behaviors") == reads + 1) == rereads, "\(error): \(api.count("behaviors") - reads)")
        }
    }
}

// MARK: - Notifications: saves in order, failures in words (S5, S6)

@MainActor
struct NotificationSavesTests {
    let api = MockPlatformAPI()
    let state: AppState
    let model: NotificationSettingsViewModel

    init() {
        let env = AppEnvironment.test(api: api, flags: [.pushEnabled: true])
        state = AppState(env: env)
        state.user = MockData.user
        model = NotificationSettingsViewModel(state: state, push: PushRegistrar(env: env))
    }

    @Test("Two times chosen while the first is on its way reach RYFT in order; the page shows the latest, as RYFT has it")
    func overlappingTimesGoInOrder() async throws {
        await model.setQuietHours(on: true)
        let hold = RequestHold()
        api.beforePatchNotifications = { await hold.wait() }
        let first = Task { await model.setQuietFrom(NotificationSettingsViewModel.date("21:30")) }
        #expect(await eventually { hold.waiting == 1 })
        #expect(model.saving)
        let second = Task { await model.setQuietFrom(NotificationSettingsViewModel.date("21:00")) }
        #expect(await eventually { model.prefs.quietHours?.from == "21:00" }, "shown at once")
        #expect(api.count("patchNotifications") == 2, "the second waits for the first: \(api.count("patchNotifications"))")
        api.beforePatchNotifications = nil
        hold.release()
        await first.value
        await second.value
        #expect(api.count("patchNotifications") == 3)
        #expect(api.prefs.quietHours == QuietHours(from: "21:00", to: "07:00"), "the platform ends with the latest")
        #expect(model.prefs.quietHours == QuietHours(from: "21:00", to: "07:00"))
        #expect(!model.saving && model.failure == nil)
    }

    @Test("A refused change goes back and says so calmly, with the status and request ID as the caption")
    func aRefusalInWords() async {
        api.failNext = APIError.http(422, "categories: unknown key", requestID: "01a1-notif")
        await model.set(.pr, on: false)
        #expect(model.isOn(.pr), "rolled back")
        let failure = model.failure
        #expect(failure?.message == "RYFT couldn't save this change, so it's back as it was.")
        #expect(failure?.details == "HTTP 422 · Request ID 01a1-notif")
        #expect(failure?.message.contains("categories") == false, "never the raw error text")
        #expect(failure?.quietHours == false)
        // The next change that saves clears it.
        await model.set(.pr, on: false)
        #expect(model.failure == nil && !model.isOn(.pr))
    }

    @Test("No answer and offline have their own words; a quiet-hours failure is marked for its group")
    func noAnswerAndOffline() async {
        api.failNext = APIError.transport(URLError(.timedOut))
        await model.setQuietHours(on: true)
        #expect(!model.quietHoursOn)
        #expect(model.failure?.message == "RYFT didn't answer, so this may not have saved. Try again in a moment.")
        #expect(model.failure?.quietHours == true && model.failure?.details == nil)

        let offline = NotificationSettingsFailure(APIError.transport(URLError(.notConnectedToInternet)))
        #expect(offline.message == "You're offline, so this wasn't saved. Try again when you're back online.")
        // Judged by what left the phone (`SettingsWriteFailure`, C3 review item 2): a timeout was sent and may have saved.
        #expect(NotificationSettingsFailure(APIError.transport(URLError(.timedOut))).message
                == "RYFT didn't answer, so this may not have saved. Try again in a moment.")
    }
}
