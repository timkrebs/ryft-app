import Foundation
import SwiftUI
import Testing
@testable import Ryft

/// PR 6 review (seams S1, security N-2): the journal sheet keeps to the account and side it opened on at every entry, not only
/// in Save. A day read answered after the account's journal was forgotten (a sign-out, another account, the Demo data switch,
/// a wipe) rebuilds nothing and fails nothing; Try again, another day and the habits chosen in Profile read nothing more; the
/// model asks to close, and the live sheet closes by itself. Synthetic data only.
@MainActor
@Suite("Journal sheet: it stays with the side it opened on", .serialized)
struct JournalSheetSideTests {
    private static var now: Date { MockJournalStates.clock.now() }

    /// The account's catalog on this iPhone and `days` with it; the platform answers the rest.
    private func fixture(days: [JournalDay] = []) -> (JournalStore, MockPlatformAPI, AppEnvironment) {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, clock: TestClock(now: Self.now))
        env.persistence.saveDocument(MockJournal.behaviors, key: JournalStore.behaviorsKey, at: Self.now)
        for day in days { env.persistence.saveDocument(day, key: JournalStore.dayKey(day.day), at: Self.now) }
        return (JournalStore(env: env), api, env)
    }

    /// The journal's reads the platform saw: the catalog and the days.
    private func reads(_ api: MockPlatformAPI) -> Int { api.count("behaviors") + api.count("journal") }

    @Test("A day read answered after the journal was forgotten: no rebuild or failed read; Try again, another day, the habits read nothing",
          .timeLimit(.minutes(1)))
    func aLateReadChangesNothing() async throws {
        let (store, api, _) = fixture()
        let model = JournalSheetModel(store: store)
        let rows = model.groups
        #expect(!rows.isEmpty && !model.hasDay, "the catalog's rows, yesterday not on this iPhone yet")
        let hold = RequestHold()
        api.beforeJournalAnswer = { name in if name == "journal" { await hold.wait() } }
        let loading = Task { await model.load() }
        #expect(await eventually { hold.waiting == 1 })
        #expect(model.isLoading && model.isCurrent)

        store.accountChanged()
        #expect(!model.isCurrent)
        hold.release()
        await loading.value
        #expect(model.leftItsSide, "the sheet asks to close")
        #expect(model.groups == rows, "no rebuild: the rows it showed, nothing of the next journal's")
        #expect(!model.loadFailed && !model.isLoading && !model.hasDay, "no \"Couldn't load this day.\"")

        let before = reads(api)
        await model.retry()
        await model.select(MockJournalStates.day(3))
        await model.habitsChanged()
        #expect(reads(api) == before, "Try again, another day and the habits read nothing: \(api.calls)")
        #expect(model.day == store.yesterday && model.groups == rows, "still the day and rows it opened on")
        // An answer given meanwhile: switching days asks nothing either, as nothing of this sheet can be saved now.
        model.set(MockJournal.alcohol, on: true)
        await model.requestSelect(MockJournalStates.day(4))
        #expect(model.pendingDiscard == nil && model.day == store.yesterday)
        #expect(api.count("putJournal") == 0)
    }

    /// Lets the first caller through once.
    @MainActor
    private final class Once {
        private var taken = false
        func take() -> Bool {
            defer { taken = true }
            return !taken
        }
    }

    @Test("A catalog read answered after the journal was forgotten: the sheet asks for no day, even once the next journal is live",
          .timeLimit(.minutes(1)))
    func aLateCatalogReadsNoDay() async throws {
        let api = MockPlatformAPI()
        // Nothing on this iPhone yet: the sheet reads the catalog before its day.
        let store = JournalStore(env: AppEnvironment.test(api: api, clock: TestClock(now: Self.now)))
        let model = JournalSheetModel(store: store)
        let hold = RequestHold(), first = Once()
        store.beforeApplying = { name in
            if name == "behaviors", first.take() { await hold.wait() }
        }
        let loading = Task { await model.load() }
        #expect(await eventually { hold.waiting == 1 })

        store.accountChanged()
        await store.load()   // another screen reads the next journal's catalog
        #expect(store.isLive)
        hold.release()
        await loading.value
        #expect(model.leftItsSide && api.count("journal") == 0, "no day read for the next journal: \(api.calls)")
        #expect(model.groups.isEmpty && !model.isLoading && !model.loadFailed)
    }

    @Test("A save answered after the journal was forgotten, saved or failed: no Saved, no rebuild, no error; the sheet asks to close",
          arguments: [false, true])
    func aLateSaveChangesNothing(fails: Bool) async throws {
        let (store, _, _) = fixture(days: [MockJournal.journal(day: MockJournalStates.day(1), today: Self.now)])
        let gate = JournalTestGate()
        let model = JournalSheetModel(store: store, saver: { _, _ in
            await gate.wait()
            if fails { throw APIError.http(503, "busy", requestID: "req-late") }
        })
        model.set(MockJournal.alcohol, on: false)
        let rows = model.groups
        let saving = Task { await model.save() }
        #expect(await eventually { gate.waiting == 1 })

        store.accountChanged()
        gate.open()
        #expect(await saving.value == false, "the sheet doesn't close as saved")
        #expect(model.leftItsSide && !model.saved && model.error == nil && model.errorDetails == nil)
        #expect(model.groups == rows && model.isDirty, "no rebuild from the next journal")
    }

    @Test("The live sheet closes by itself, answers not saved and all, once the journal it opened on is forgotten",
          .timeLimit(.minutes(1)))
    func theLiveSheetCloses() async throws {
        let (store, _, env) = fixture(days: [MockJournal.journal(day: MockJournalStates.day(1), today: Self.now)])
        let model = JournalSheetModel(store: store)
        let view = SheetHost {
            JournalSheet(model: model)
                .environment(\.appEnvironment, env)
                .environment(\.locale, Locale(identifier: "en_US"))
        }
        try await HostedWindow.run(width: 390, height: 844, view) { w in
            try await w.wait("the sheet's rows") { sheetNodes(w).contains { $0.identifier == "journal.answer.alcohol" } }
            try await w.settle()
            model.set(MockJournal.alcohol, on: false)
            #expect(model.isDirty && !w.nodes().contains { $0.identifier == SheetHost<EmptyView>.closed })

            store.accountChanged()
            try await w.wait("closed") { w.nodes().contains { $0.identifier == SheetHost<EmptyView>.closed } }
            try await w.wait("the sheet gone") { w.host.presentedViewController == nil }
            #expect(model.pendingDiscard == nil, "no Discard? for answers that are no longer the journal's")
        }
    }
}
