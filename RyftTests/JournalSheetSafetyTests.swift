import Foundation
import Testing
@testable import Ryft

/// T6B.8's review: the journal sheet never answers a day the user didn't answer, never rebuilds over answers being given, and
/// never drops answers without asking (B1, S1, S2, S5 and the nits). The model alone; saves are held open with a gate and reads
/// with a `Retry-After` on a test clock.
@MainActor
@Suite("T6B.8: the Journal sheet keeps answers safe", .serialized)
struct JournalSheetSafetyTests {
    private static var now: Date { MockJournalStates.clock.now() }
    private static var yesterday: String { MockJournalStates.day(1) }

    /// Days sent, in order, and whether the next send fails.
    @MainActor
    private final class Sent {
        var days: [String] = []
        var fails = true
    }

    private struct Fixture {
        let api: MockPlatformAPI
        let clock: TestClock
        let env: AppEnvironment
        let store: JournalStore
    }

    /// The catalog and `days` on this iPhone; yesterday answered as API.md's example unless `days` says otherwise.
    private func fixture(online: Bool = true, days: [JournalDay]? = nil) -> Fixture {
        let api = MockPlatformAPI()
        let clock = TestClock(now: Self.now)
        let env = AppEnvironment.test(api: api, clock: clock, online: online)
        env.persistence.saveDocument(MockJournal.behaviors, key: JournalStore.behaviorsKey, at: Self.now)
        for day in days ?? [MockJournal.journal(day: Self.yesterday, today: Self.now)] {
            env.persistence.saveDocument(day, key: JournalStore.dayKey(day.day), at: Self.now)
        }
        return Fixture(api: api, clock: clock, env: env, store: JournalStore(env: env))
    }

    private func row(_ model: JournalSheetModel, _ id: UUID) -> JournalSheetModel.Row? {
        model.groups.flatMap(\.rows).first { $0.id == id }
    }

    /// A read of the journal that waits on the clock (one `503` with `Retry-After: 2`) until the test advances it.
    private func holdNextRead(_ f: Fixture) {
        f.api.faults["journal"] = .init(.status(503, retryAfter: 2), times: 1)
    }

    // MARK: B1: a save belongs to its day

    @Test("B1: a save out while the day changes is dropped there, and Try again on an unread day sends nothing")
    func failedSaveDoesNotFollowTheDay() async throws {
        let f = fixture(online: false)   // the other day can't be read: it stays off this iPhone
        let gate = JournalTestGate(), sent = Sent()
        let model = JournalSheetModel(store: f.store, saver: { day, _ in
            sent.days.append(day)
            await gate.wait()
            throw APIError.http(503, "busy", requestID: "req-a")
        })
        model.set(MockJournal.sauna, on: false)
        let saving = Task { await model.save() }
        #expect(await eventually { gate.waiting == 1 && model.isSaving })
        #expect(await model.save() == false, "a second tap while one is out sends nothing")
        let other = MockJournalStates.day(3)
        await model.select(other)
        #expect(model.day == other && !model.hasDay)
        gate.open()
        #expect(await saving.value == false)
        #expect(model.error == nil && model.errorDetails == nil, "the failure belongs to the day it was asked for")
        #expect(await model.save() == false)
        #expect(sent.days == [Self.yesterday], "nothing sent for \(other): \(sent.days)")
    }

    @Test("B1: a save that succeeds after the day changed shows no Saved there and doesn't close the sheet")
    func successfulSaveDoesNotFollowTheDay() async throws {
        let other = JournalDay(day: MockJournalStates.day(3), answered: false, answeredAt: nil, editable: true, entries: [])
        let f = fixture(online: false, days: [MockJournal.journal(day: Self.yesterday, today: Self.now), other])
        let gate = JournalTestGate()
        let model = JournalSheetModel(store: f.store, saver: { _, _ in await gate.wait() })
        let saving = Task { await model.save() }
        #expect(await eventually { gate.waiting == 1 })
        await model.select(other.day)
        gate.open()
        #expect(await saving.value == false, "false: the sheet stays open")
        #expect(!model.saved && model.day == other.day && !model.isSaving)
    }

    @Test("B1: nothing changes while a save is out")
    func noEditsWhileSaving() async throws {
        let f = fixture()
        let gate = JournalTestGate()
        let model = JournalSheetModel(store: f.store, saver: { _, _ in await gate.wait() })
        let saving = Task { await model.save() }
        #expect(await eventually { gate.waiting == 1 })
        model.set(MockJournal.alcohol, on: false)
        #expect(row(model, MockJournal.alcohol)?.on == true)
        gate.open()
        #expect(await saving.value)
    }

    @Test("B1: a day that isn't on this iPhone is never saved")
    func unreadDayIsNotSaved() async {
        let f = fixture(online: false)
        let sent = Sent()
        let model = JournalSheetModel(store: f.store, day: MockJournalStates.day(5), saver: { day, _ in sent.days.append(day) })
        #expect(!model.hasDay)
        #expect(await model.save() == false)
        #expect(sent.days.isEmpty)
    }

    // MARK: S1: a read doesn't rebuild over answers

    @Test("S1: an answer given while the opening read is out stays when it answers")
    func openingReadKeepsEdits() async throws {
        let f = fixture()
        let model = JournalSheetModel(store: f.store)
        #expect(row(model, MockJournal.sauna)?.on == true)
        holdNextRead(f)
        let loading = Task { await model.load() }
        #expect(await eventually { f.clock.pendingSleeps == 1 })
        model.set(MockJournal.sauna, on: false)
        f.clock.advance(by: .seconds(2))
        await loading.value
        #expect(f.api.count("journal") == 2, "the read went out again and answered")
        #expect(row(model, MockJournal.sauna)?.on == false, "the answer stays")
        #expect(model.isDirty)
    }

    @Test("S1: an answer given while a switched-to day is read stays when it answers")
    func switchReadKeepsEdits() async throws {
        let other = JournalDay(day: MockJournalStates.day(3), answered: false, answeredAt: nil, editable: true, entries: [])
        let f = fixture(days: [MockJournal.journal(day: Self.yesterday, today: Self.now), other])
        let model = JournalSheetModel(store: f.store)
        holdNextRead(f)
        let switching = Task { await model.select(other.day) }
        #expect(await eventually { f.clock.pendingSleeps == 1 })
        #expect(model.day == other.day && model.hasDay)
        model.set(MockJournal.alcohol, on: true)
        f.clock.advance(by: .seconds(2))
        await switching.value
        #expect(row(model, MockJournal.alcohol)?.on == true)
    }

    @Test("S1: without an answer in between, the read's answer is shown")
    func readWithoutEditsRebuilds() async {
        let other = JournalDay(day: MockJournalStates.day(3), answered: false, answeredAt: nil, editable: true, entries: [])
        let f = fixture(days: [MockJournal.journal(day: Self.yesterday, today: Self.now), other])
        // The platform has the day answered since.
        _ = try? await f.api.putJournal(day: other.day, JournalPut(entries: [JournalEntry(behaviorId: MockJournal.alcohol,
                                                                                          valueBool: true)]))
        let model = JournalSheetModel(store: f.store, day: other.day)
        #expect(row(model, MockJournal.alcohol)?.on == false)
        await model.load()
        #expect(row(model, MockJournal.alcohol)?.on == true && !model.isDirty)
    }

    // MARK: S2: answers aren't dropped without asking

    @Test("S2: with answers not saved, closing asks; Keep editing stays, Discard closes")
    func closeAsksFirst() async {
        let model = JournalSheetModel(store: fixture().store)
        #expect(!model.isDirty && model.requestClose(), "nothing to lose: it closes")
        model.set(MockJournal.alcohol, on: false)
        #expect(model.isDirty)
        #expect(!model.requestClose() && model.pendingDiscard == .close)
        model.cancelDiscard()
        #expect(model.pendingDiscard == nil && model.isDirty)
        #expect(!model.requestClose())
        #expect(await model.discard(.close))
        #expect(model.pendingDiscard == nil)
    }

    @Test("S2: with answers not saved, switching days asks; Discard switches, Keep editing stays")
    func switchAsksFirst() async {
        let other = JournalDay(day: MockJournalStates.day(3), answered: false, answeredAt: nil, editable: true, entries: [])
        let f = fixture(online: false, days: [MockJournal.journal(day: Self.yesterday, today: Self.now), other])
        let model = JournalSheetModel(store: f.store)
        model.set(MockJournal.alcohol, on: false)
        await model.requestSelect(other.day)
        #expect(model.day == Self.yesterday && model.pendingDiscard == .day(other.day))
        model.cancelDiscard()
        #expect(model.day == Self.yesterday && row(model, MockJournal.alcohol)?.on == false)
        await model.requestSelect(other.day)
        #expect(await model.discard(.day(other.day)) == false)
        #expect(model.day == other.day && !model.isDirty && model.pendingDiscard == nil)
        await model.requestSelect(Self.yesterday)
        #expect(model.day == Self.yesterday && model.pendingDiscard == nil, "nothing to lose: it switches at once")
    }

    @Test("S2: a save makes it clean; tapping the selected day keeps its rows and its error")
    func savedIsCleanAndReselectKeepsState() async {
        let f = fixture()
        let sent = Sent()
        let model = JournalSheetModel(store: f.store, saver: { _, _ in
            if sent.fails { throw APIError.http(503, "busy", requestID: "req-b") }
        })
        model.set(MockJournal.alcohol, on: false)
        #expect(await model.save() == false)
        let error = model.error
        #expect(error != nil && model.isDirty)
        await model.select(Self.yesterday)
        await model.requestSelect(Self.yesterday)
        #expect(model.error == error && model.isDirty && row(model, MockJournal.alcohol)?.on == false)
        sent.fails = false
        #expect(await model.save())
        #expect(!model.isDirty && model.saved)
    }

    // MARK: S5 and the nits

    @Test("S5: the platform turning answers down reads as RYFT's sentence; its text never shows; the request ID goes to Details")
    func rejectedSave() async {
        let rejected = APIError.http(422, "behavior 3f1c2a9e-7b6d-4c5e-9a8f-0e1d2c3b4a55 is not enabled", requestID: "req-422")
        let model = JournalSheetModel(store: fixture().store, saver: { _, _ in throw rejected })
        #expect(await model.save() == false)
        #expect(model.error == "RYFT didn't accept that, so nothing changed.")
        #expect(model.errorDetails?.contains("req-422") == true, "\(model.errorDetails ?? "nil")")
        #expect(JournalSheetModel.message(for: APIError.http(400, "behavior_id unknown")) == model.error)
        #expect(JournalSheetModel.message(for: APIError.http(503, "")) == APIError.http(503, "").localizedDescription)
    }

    @Test("Back online, \"You're offline…\" goes; another error stays")
    func offlineErrorClearsOnReconnect() async {
        let f = fixture(online: false)
        let model = JournalSheetModel(store: f.store)
        #expect(await model.save() == false)
        #expect(model.error == JournalStore.JournalError.offline.errorDescription)
        model.connectionChanged(online: false)
        #expect(model.error != nil)
        model.connectionChanged(online: true)
        #expect(model.error == nil)

        let failing = JournalSheetModel(store: fixture().store, saver: { _, _ in throw APIError.http(503, "") })
        #expect(await failing.save() == false)
        failing.connectionChanged(online: true)
        #expect(failing.error != nil)
    }

    @Test("Back from Profile → Journal: the habits chosen there show at once, before the day's read answers")
    func habitsChangedRebuildsFirst() async throws {
        let unanswered = JournalDay(day: Self.yesterday, answered: false, answeredAt: nil, editable: true, entries: [])
        let api = MockPlatformAPI()
        let clock = TestClock(now: Self.now)
        let env = AppEnvironment.test(api: api, clock: clock)
        env.persistence.saveDocument(MockJournal.noneEnabled, key: JournalStore.behaviorsKey, at: Self.now)
        env.persistence.saveDocument(unanswered, key: JournalStore.dayKey(Self.yesterday), at: Self.now)
        let store = JournalStore(env: env)
        let model = JournalSheetModel(store: store)
        #expect(model.phase == .noHabits)
        try await store.setEnabled(MockJournal.alcohol, true)
        holdNextRead(Fixture(api: api, clock: clock, env: env, store: store))
        let back = Task { await model.habitsChanged() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(model.phase == .ready && row(model, MockJournal.alcohol) != nil, "before the read answers")
        clock.advance(by: .seconds(2))
        await back.value
    }
}
