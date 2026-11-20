import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// T6B.8, the Journal in Nocturne (docs/work/2026-11-16-nocturne/design-pr6-b-train.md §11, §14.2): Today's card and the sheet as
/// VoiceOver and the eye find them (`HostedWindow`), the sheet's states from the model (`JournalSheetModel.phase`), and the
/// offline-first rule (2026-11-19): a day that isn't on this iPhone shows a line offline, never outlines for good, and nothing
/// says the answers are saved or sent when they aren't.
@MainActor
@Suite("T6B.8: the Journal in Nocturne", .serialized)
struct JournalNocturneTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA

    private static let width: CGFloat = 390
    private static let english = Locale(identifier: "en_US")
    private static var yesterday: String { MockJournalStates.day(1) }

    // MARK: the model's states (no window)

    /// The states' instant (`MockJournalStates.clock`), so every day of a test is counted from one reading.
    private static var now: Date { MockJournalStates.clock.now() }

    private func journalStore(_ api: MockPlatformAPI = MockPlatformAPI(), online: Bool = true, cached days: [JournalDay] = [])
        -> (JournalStore, AppEnvironment) {
        let env = AppEnvironment.test(api: api, clock: TestClock(now: Self.now), online: online)
        env.persistence.saveDocument(MockJournal.behaviors, key: JournalStore.behaviorsKey, at: Self.now)
        for day in days { env.persistence.saveDocument(day, key: JournalStore.dayKey(day.day), at: Self.now) }
        return (JournalStore(env: env), env)
    }

    @Test("A day not on this iPhone is outlines while it's read, then its rows")
    func uncachedDayLoads() async {
        let (store, _) = journalStore()
        let model = JournalSheetModel(store: store, day: MockJournalStates.day(3))
        #expect(model.phase(isOnline: true) == .loading, "before the read: the outlines")
        await model.load()
        #expect(model.phase(isOnline: true) == .ready)
        #expect(!model.groups.isEmpty && JournalSheetContent(model, isOnline: true).canSave)
    }

    @Test("Offline with nothing cached: the offline line at once and after the read, never the outlines")
    func uncachedOffline() async {
        let api = MockPlatformAPI()
        let (store, _) = journalStore(api, online: false)
        let model = JournalSheetModel(store: store, day: MockJournalStates.day(3))
        #expect(model.phase(isOnline: false) == .offline)
        await model.load()
        #expect(model.phase(isOnline: false) == .offline)
        #expect(!model.isLoading)
        #expect(api.count("journal") == 0, "nothing was asked")
        #expect(!JournalSheetContent(model, isOnline: false).canSave, "no Save for a form that would answer no to everything")
    }

    @Test("A read that failed says so; Try again reads it once it answers")
    func failedRead() async {
        let api = MockPlatformAPI()
        let (store, _) = journalStore(api)
        let model = JournalSheetModel(store: store, day: MockJournalStates.day(3))
        api.failure = APIError.http(400, "bad request")
        await model.load()
        #expect(model.phase(isOnline: true) == .failed)
        api.failure = nil
        await model.load()
        #expect(model.phase(isOnline: true) == .ready)
    }

    @Test("Try again is the user's read: it goes while the journal's reads are held back; the sheet's own reads wait")
    func tryAgainIsUserInitiated() async {
        let api = MockPlatformAPI()
        let (store, env) = journalStore(api)
        let model = JournalSheetModel(store: store, day: MockJournalStates.day(3))
        // A failure asked the pipeline to hold the journal's reads back for five minutes (`Retry-After`).
        env.reads.seed([.journal: ResourceState(consecutiveFailures: 1, retryNotBefore: Self.now.addingTimeInterval(300))])
        await model.load()
        #expect(api.count("journal") == 0, "the opening read waits")
        #expect(model.phase(isOnline: true) == .failed)
        await model.retry()
        #expect(api.count("journal") == 1, "Try again goes")
        #expect(model.phase(isOnline: true) == .ready)
    }

    @Test("The live sheet's Try again is that read: held back, the day fails; the tap reads it and its rows come")
    func tryAgainInTheSheet() async throws {
        let api = MockPlatformAPI()
        let (store, env) = journalStore(api)
        env.reads.seed([.journal: ResourceState(consecutiveFailures: 1, retryNotBefore: Self.now.addingTimeInterval(300))])
        let view = JournalSheet(model: JournalSheetModel(store: store))
            .environment(\.appEnvironment, env)
            .environment(\.locale, Self.english)
        try await HostedWindow.run(width: Self.width, height: 844, view) { w in
            try await w.wait("the failed read") { w.nodes().contains { $0.identifier == "journal.failed.retry" } }
            #expect(api.count("journal") == 0, "the opening read waited")
            try #require(w.nodes().first { $0.identifier == "journal.failed.retry" }).activate()
            try await w.wait("yesterday's rows") { w.nodes().contains { $0.identifier == "journal.habit.alcohol" } }
            #expect(api.count("journal") == 1, "Try again went")
        }
    }

    @Test("A cached day is its rows offline too; without a habit chosen it is the no-habits state")
    func cachedAndNoHabits() async {
        let (store, _) = journalStore(online: false, cached: [MockJournal.journal(day: Self.yesterday, today: Self.now)])
        let model = JournalSheetModel(store: store)
        #expect(model.phase(isOnline: false) == .ready)
        let unanswered = JournalDay(day: MockJournalStates.day(2), answered: false, answeredAt: nil, editable: true, entries: [])
        let none = MockJournalStates.store(behaviors: MockJournal.noneEnabled, days: [unanswered])
        let empty = JournalSheetModel(store: none, day: unanswered.day)
        #expect(empty.phase(isOnline: true) == .noHabits)
        #expect(JournalSheetContent(empty, isOnline: true).saveHint == JournalSheetBody.noHabitsMessage)
    }

    @Test("Save, then \"Saved\" and off; a change makes it Save again")
    func saveThenSaved() async {
        let api = MockPlatformAPI()
        let (store, _) = journalStore(api)
        await store.load()
        let model = JournalSheetModel(store: store, day: MockJournalStates.day(3))
        await model.load()
        #expect(JournalSheetContent(model, isOnline: true).canSave)
        await model.save()
        var content = JournalSheetContent(model, isOnline: true)
        #expect(content.saved && !content.canSave && content.saveHint == nil)
        model.set(MockJournal.alcohol, on: true)
        content = JournalSheetContent(model, isOnline: true)
        #expect(!content.saved && content.canSave)
    }

    @Test("Save is off for a read-only day, without habits and while the day isn't here; its hint says why")
    func saveIsOff() {
        let states = Dictionary(uniqueKeysWithValues: MockJournalStates.Sheet.allCases.map { ($0, MockJournalStates.content($0)) })
        #expect(states[.answered]?.canSave == true && states[.answered]?.saveHint == nil)
        #expect(states[.offline]?.canSave == true, "a cached day offline: Save tries, and says so if it can't")
        for off in [MockJournalStates.Sheet.readOnly, .noHabits, .loading, .offlineUncached] {
            #expect(states[off]?.canSave == false, "\(off)")
        }
        #expect(states[.readOnly]?.saveHint == "This day can't be changed any more.")
        #expect(states[.noHabits]?.saveHint == "Choose habits in Profile → Journal.")
        #expect(states[.loading]?.saveHint == "Available once this day has loaded.")
        #expect(states[.offlineUncached]?.saveHint == "This day's answers appear once you're online.")
    }

    @Test("Save is off after a failed read (the hint says so) and while a save is out (no hint: it reads In progress)")
    func saveIsOffFailedAndSaving() async throws {
        let api = MockPlatformAPI()
        let (store, env) = journalStore(api)
        let failed = JournalSheetModel(store: store, day: MockJournalStates.day(3))
        api.failure = APIError.http(400, "bad request", requestID: "req-read-1")
        await failed.load()
        let content = JournalSheetContent(failed, isOnline: true, readState: env.reads.states[.journal])
        #expect(content.phase == .failed && !content.canSave)
        #expect(content.saveHint == "Couldn't load this day.")
        #expect(content.failedDetails?.contains("req-read-1") == true, "\(content.failedDetails ?? "nil")")
        api.failure = nil

        let gate = JournalTestGate()
        let (cached, _) = journalStore(cached: [MockJournal.journal(day: Self.yesterday, today: Self.now)])
        let saving = JournalSheetModel(store: cached, saver: { _, _ in await gate.wait() })
        let task = Task { await saving.save() }
        #expect(await eventually { gate.waiting == 1 })
        let busy = JournalSheetContent(saving, isOnline: true)
        #expect(busy.isSaving && !busy.canSave && busy.saveHint == nil)
        gate.open()
        #expect(await task.value)
    }

    @Test("A failed save keeps its status and request ID for Details; offline it says nothing was sent")
    func saveFailure() async throws {
        let api = MockPlatformAPI()
        let (store, env) = journalStore(api, cached: [MockJournal.journal(day: Self.yesterday, today: Self.now)])
        let model = JournalSheetModel(store: store)
        api.failNext = APIError.http(503, "request timed out", requestID: "req-journal-1")
        await model.save()
        #expect(model.error != nil && !model.saved)
        #expect(model.errorDetails?.contains("req-journal-1") == true, "\(model.errorDetails ?? "nil")")
        env.connectivityMonitor.update(false)
        await model.save()
        #expect(model.error == JournalStore.JournalError.offline.errorDescription && model.errorDetails == nil)
        #expect(api.count("putJournal") == 1, "offline, nothing was sent")
    }

    // MARK: hosted: the strip

    private func sheet(_ content: JournalSheetContent, actions: JournalSheetActions = JournalSheetActions()) -> some View {
        JournalSheetBody(content: content, actions: actions)
            .toggleStyle(.ryft)
            .environment(\.locale, Self.english)
    }

    @Test("The strip: yesterday first and selected, filled with ink and its words in the ground; 14 days; no today, no Volt")
    func strip() async throws {
        let content = MockJournalStates.content(.answered)
        try await HostedWindow.run(width: Self.width, height: 844, sheet(content)) { w in
            try await w.settle()
            let nodes = w.nodes()
            let chips = nodes.filter { $0.identifier?.hasPrefix("journal.day.") == true }
            #expect(chips.count == JournalSheetModel.daysBack, "\(chips.compactMap(\.identifier))")
            #expect(chips.first?.identifier == "journal.day.\(Self.yesterday)")
            #expect(!chips.contains { $0.identifier == "journal.day.\(MockJournalStates.day(0))" }, "today isn't in the strip")
            let selected = try #require(chips.first)
            #expect(selected.isSelected && chips.dropFirst().allSatisfy { !$0.isSelected })
            let date = try #require(DayFormat.date(from: Self.yesterday))
            #expect(selected.label == date.formatted(Date.FormatStyle(locale: Self.english).weekday(.wide).month(.wide).day()))
            #expect(selected.frame.width >= JournalLayout.chipWidth - 0.5 && selected.frame.height >= JournalLayout.chipHeight - 0.5)
            let pixels = try WindowPixels(w, scale: 2)
            let ink = Tokens.resolve(Theme.textPrimary), surface = Tokens.resolve(Theme.surface)
            let fill = pixels.at(selected.frame.minX + 4, selected.frame.midY)
            #expect(fill.near(ink, 3), "the selected chip's fill: \(Tokens.describe(fill))")
            let other = try #require(chips.dropFirst().first)
            #expect(pixels.at(other.frame.minX + 4, other.frame.midY).near(surface, 3), "another chip is surface")
            let volt = Tokens.resolve(Theme.signal)
            let band = selected.frame.insetBy(dx: 0, dy: -6)
            #expect(pixels.count(in: CGRect(x: 0, y: band.minY, width: Self.width, height: band.height)) { $0.near(volt, 16) } == 0,
                    "no Volt: the journal is for days gone by")
        }
    }

    @Test("A chip is a button VoiceOver activates: it selects its day")
    func chipActivates() async throws {
        let content = MockJournalStates.content(.answered)
        let taps = Taps()
        let strip = JournalDateStrip(days: content.days, selected: content.selected) { taps.days.append($0) }
            .padding(20)
            .environment(\.locale, Self.english)
        try await HostedWindow.run(width: Self.width, height: 200, strip) { w in
            try await w.settle()
            let day = MockJournalStates.day(3)
            let chip = try #require(w.nodes().first { $0.identifier == "journal.day.\(day)" })
            #expect(chip.traits.contains(.button) && !chip.isSelected)
            #expect(chip.activate())
            try await w.wait("the day selected") { taps.days == [day] }
        }
    }

    // MARK: hosted: Save

    @Test("Save reads \"Saved\" once saved, and is off (with the reason) for a read-only day, without habits, while loading; busy while saving")
    func saveButton() async throws {
        let cases: [(MockJournalStates.Sheet, label: String, enabled: Bool)] = [
            (.answered, "Save", true), (.readOnly, "Save", false), (.noHabits, "Save", false), (.loading, "Save", false),
            (.offlineUncached, "Save", false), (.saving, "Save", false),
        ]
        for (state, label, enabled) in cases {
            try await HostedWindow.run(width: Self.width, height: 844, sheet(MockJournalStates.content(state))) { w in
                try await w.settle()
                let save = try #require(w.nodes().first { $0.identifier == "journal.save" }, "\(state)")
                #expect(save.label == label && save.isEnabled == enabled, "\(state): \(save.label) \(save.isEnabled)")
                #expect(save.frame.height >= 44 - 0.5, "\(state): \(save.frame)")
                if state == .saving { #expect(save.value == "In progress") }
                if state == .readOnly { #expect(save.hint == "This day can't be changed any more.") }
            }
        }
        var saved = MockJournalStates.content(.answered)
        saved.saved = true
        try await HostedWindow.run(width: Self.width, height: 844, sheet(saved)) { w in
            try await w.settle()
            let save = try #require(w.nodes().first { $0.identifier == "journal.save" })
            #expect(save.label == "Saved" && !save.isEnabled)
        }
    }

    // MARK: hosted: offline

    @Test("Offline: one pill over the groups says saving needs the network; online there is none")
    func offlinePill() async throws {
        try await HostedWindow.run(width: Self.width, height: 844, sheet(MockJournalStates.content(.offline))) { w in
            try await w.settle()
            let nodes = w.nodes()
            let pill = try #require(nodes.first { $0.identifier == "journal.offlinePill" })
            #expect(pill.label == "Offline. You can save once you're back online.")
            let firstGroup = try #require(nodes.first { $0.label == "Substances" })
            #expect(pill.frame.maxY <= firstGroup.frame.minY, "over the groups: \(pill.frame) \(firstGroup.frame)")
            #expect(!nodes.contains { $0.label.localizedCaseInsensitiveContains("sync") || $0.label.contains("sent") },
                    "nothing promises a later upload")
        }
        // Online, a read-only day, no habits: nothing to save, so no pill.
        var readOnly = MockJournalStates.content(.readOnly), noHabits = MockJournalStates.content(.noHabits)
        readOnly.isOnline = false
        noHabits.isOnline = false
        #expect(!readOnly.showsOfflinePill && !noHabits.showsOfflinePill)
        for content in [MockJournalStates.content(.answered), readOnly, noHabits] {
            try await HostedWindow.run(width: Self.width, height: 844, sheet(content)) { w in
                try await w.settle()
                #expect(!w.nodes().contains { $0.identifier == "journal.offlinePill" }, "\(content.phase) \(content.editable)")
            }
        }
    }

    @Test("The pill's words are the store's outbox state: no outbox yet, so Save works once back online; kept answers say so")
    func offlinePillFollowsTheOutbox() async throws {
        let offline = MockJournalStates.content(.offline)
        #expect(!offline.keepsOfflineAnswers, "the store keeps no answers offline yet (writes need the network)")
        #expect(JournalOfflinePill.message(keepsAnswers: false) == "Offline. You can save once you're back online.")
        #expect(JournalOfflinePill.message(keepsAnswers: true) == "Offline. Your answers are saved on this phone.")
        var kept = offline
        kept.keepsOfflineAnswers = true
        try await HostedWindow.run(width: Self.width, height: 844, sheet(kept)) { w in
            try await w.settle()
            let pill = try #require(w.nodes().first { $0.identifier == "journal.offlinePill" })
            #expect(pill.label == "Offline. Your answers are saved on this phone.")
        }
    }

    @Test("Offline with the day not on this iPhone: a line with Try again, no outlines; back online it loads by itself")
    func uncachedOfflineLive() async throws {
        // The account's journal (PR 6 C): demo data answers on the phone and is never offline.
        let state = AppState(env: .test(clock: TestClock(now: .now), online: false))
        state.env.persistence.saveDocument(MockJournal.behaviors, key: JournalStore.behaviorsKey, at: .now)
        let store = JournalStore(env: state.env)
        let view = JournalSheet(model: JournalSheetModel(store: store)).previewEnvironment(state).environment(\.locale, Self.english)
        try await HostedWindow.run(width: Self.width, height: 844, view) { w in
            try await w.settle()
            var nodes = w.nodes()
            #expect(nodes.contains { $0.label == "This day's answers appear once you're online." }, "\(nodes.map(\.label))")
            let retry = try #require(nodes.first { $0.identifier == "journal.offline.retry" })
            #expect(retry.label == "Try again" && retry.frame.height >= 44)
            #expect(!nodes.contains { $0.identifier == "journal.loading" }, "no outlines")
            #expect(!nodes.contains { $0.identifier == "journal.offlinePill" }, "the line says it; no second notice")
            #expect(nodes.first { $0.identifier == "journal.save" }?.isEnabled == false)
            state.env.connectivityMonitor.update(true)
            try await w.wait("yesterday's rows") { w.nodes().contains { $0.identifier == "journal.habit.alcohol" } }
            try await w.settle()
            nodes = w.nodes()
            #expect(!nodes.contains { $0.identifier == "journal.offline.retry" })
            #expect(nodes.first { $0.identifier == "journal.save" }?.isEnabled == true)
        }
    }

    // MARK: hosted: no habits, loading, failed, read-only

    @MainActor
    private final class Taps {
        var choose = 0
        var setOn: [UUID] = []
        var retries = 0
        var days: [String] = []
    }

    @Test("No habits: the sentence, then Choose habits (a 52 pt pill) that opens Profile → Journal")
    func noHabits() async throws {
        let taps = Taps()
        let actions = JournalSheetActions(chooseHabits: { taps.choose += 1 })
        try await HostedWindow.run(width: Self.width, height: 844, sheet(MockJournalStates.content(.noHabits), actions: actions)) { w in
            try await w.settle()
            let nodes = w.nodes()
            let sentence = try #require(nodes.first { $0.identifier == "journal.noHabits" })
            #expect(sentence.label == "Choose habits in Profile → Journal.")
            let choose = try #require(nodes.first { $0.identifier == "journal.chooseHabits" })
            #expect(choose.label == "Choose habits" && choose.traits.contains(.button))
            #expect(choose.frame.height >= PillButton.minHeight - 0.5 && choose.frame.minY >= sentence.frame.maxY)
            #expect(!nodes.contains { $0.label.localizedCaseInsensitiveContains("behavior") }, "F1: habits")
            choose.activate()
            #expect(taps.choose == 1)
        }
    }

    @Test("The live sheet's Choose habits pushes Profile → Journal's page inside the sheet")
    func noHabitsLink() async throws {
        let state = AppState.preview()
        let store = JournalStore(env: state.env)
        // Yesterday by the store's own clock (the preview's), unanswered here and on the platform (the mock answers it as
        // API.md's example otherwise). Demo data's journal lives in memory only (PR 6 C), so it is seeded there.
        let yesterday = store.yesterday
        let unanswered = JournalDay(day: yesterday, answered: false, answeredAt: nil, editable: true, entries: [])
        store.seedForPreview(behaviors: MockJournal.noneEnabled, days: [unanswered])
        let api = try #require(state.env.api as? MockPlatformAPI)
        _ = try await api.putJournal(day: yesterday, JournalPut(entries: []))
        let view = JournalSheet(model: JournalSheetModel(store: store)).previewEnvironment(state).environment(\.locale, Self.english)
        try await HostedWindow.run(width: Self.width, height: 844, view) { w in
            try await w.wait("the no-habits state") { w.nodes().contains { $0.identifier == "journal.chooseHabits" } }
            try await w.settle()
            #expect(!w.nodes().contains { $0.label == "Alcohol" }, "no habit on the sheet")
            w.nodes().first { $0.identifier == "journal.chooseHabits" }?.activate()
            // Profile → Journal lists every habit, chosen or not.
            try await w.wait("Profile → Journal's page") { w.nodes().contains { $0.label.hasPrefix("Alcohol") } }
        }
    }

    @Test("Loading is one element over outline cards; a failed read says so with Try again and Details")
    func loadingAndFailed() async throws {
        try await HostedWindow.run(width: Self.width, height: 844, sheet(MockJournalStates.content(.loading))) { w in
            try await w.settle()
            let loading = try #require(w.nodes().first { $0.identifier == "journal.loading" })
            #expect(loading.label == "Loading…")
            #expect(loading.frame.height >= 3 * GroupedListSpec.rowMinHeight, "\(loading.frame)")
            #expect(!w.nodes().contains { $0.identifier?.hasPrefix("journal.habit.") == true }, "no switches while it loads")
        }
        let taps = Taps()
        let actions = JournalSheetActions(retry: { taps.retries += 1 })
        try await HostedWindow.run(width: Self.width, height: 844, sheet(MockJournalStates.content(.failed), actions: actions)) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.contains { $0.label == "Couldn't load this day." })
            let retry = try #require(nodes.first { $0.identifier == "journal.failed.retry" })
            retry.activate()
            try await w.wait("Try again") { taps.retries == 1 }
            // The status and request ID behind Details (the inline toggle has no identifier of its own).
            let details = try #require(nodes.first { $0.label == "Details" })
            details.activate()
            try await w.wait("the request ID") { w.nodes().contains { $0.label.contains("Request ID 01JD8K2V9Q7M3X") } }
        }
    }

    @Test("A read-only day: the lock notice; taps and VoiceOver change nothing; the switches keep their state and stay enabled")
    func readOnly() async throws {
        let taps = Taps()
        let actions = JournalSheetActions(setOn: { id, _ in taps.setOn.append(id) })
        try await HostedWindow.run(width: Self.width, height: 844, sheet(MockJournalStates.content(.readOnly), actions: actions)) { w in
            try await w.settle()
            let nodes = w.nodes()
            let notice = try #require(nodes.first { $0.identifier == "journal.readOnly" })
            #expect(notice.label == "This day can't be changed any more.")
            let sauna = try #require(nodes.first { $0.identifier == "journal.habit.sauna" })
            let alcohol = try #require(nodes.first { $0.identifier == "journal.habit.alcohol" })
            #expect(sauna.isEnabled && sauna.value != alcohol.value, "on stays on, off stays off: \(sauna.value ?? "") \(alcohol.value ?? "")")
            sauna.activate()
            try await Task.sleep(for: .milliseconds(150))
            #expect(taps.setOn.isEmpty)
        }
    }

    // MARK: hosted: VoiceOver

    /// What a system switch named `label` tells VoiceOver when on and off.
    private func systemSwitchValues() async throws -> (on: String?, off: String?) {
        var values: (String?, String?) = (nil, nil)
        let view = VStack {
            Toggle(isOn: .constant(true)) { Text(verbatim: "On") }.toggleStyle(.switch)
            Toggle(isOn: .constant(false)) { Text(verbatim: "Off") }.toggleStyle(.switch)
        }
        try await HostedWindow.run(width: Self.width, height: 300, view) { w in
            try await w.settle()
            values = (w.node("On", exactly: true)?.value, w.node("Off", exactly: true)?.value)
        }
        return values
    }

    @Test("VoiceOver: \"Alcohol\", a switch, on; \"Drinks\", 2, adjustable; the header first")
    func voiceOver() async throws {
        let reference = try await systemSwitchValues()
        let on = try #require(reference.on), off = try #require(reference.off)
        let state = AppState.preview()
        let store = journalPreviewStore(state)
        let model = JournalSheetModel(store: store)
        let view = JournalSheet(model: model).previewEnvironment(state).environment(\.locale, Self.english)
        try await HostedWindow.run(width: Self.width, height: 1_200, view) { w in
            try await w.wait("yesterday's rows") { w.nodes().contains { $0.identifier == "journal.count.drinks" } }
            try await w.settle()
            let nodes = w.nodes()
            let title = try #require(nodes.firstIndex { $0.label == "Yesterday" && $0.traits.contains(.header) })
            let alcoholIndex = try #require(nodes.firstIndex { $0.identifier == "journal.habit.alcohol" })
            #expect(title < alcoholIndex, "the title before the rows")
            let alcohol = nodes[alcoholIndex]
            #expect(alcohol.label == "Alcohol" && alcohol.value == on, "\(alcohol.label) \(alcohol.value ?? "nil")")
            #expect(alcohol.traits.contains(.toggleButton) || alcohol.traits.contains(.button))
            let screens = try #require(nodes.first { $0.identifier == "journal.habit.screens_in_bed" })
            #expect(screens.value == off)
            let drinks = try #require(nodes.first { $0.identifier == "journal.count.drinks" })
            #expect(drinks.label == "Drinks" && drinks.value == "2" && drinks.isAdjustable, "\(drinks.label) \(drinks.value ?? "")")
            #expect(drinks.inputLabels == ["Drinks", "Count"], "Voice Control also says what is on screen")
            drinks.increment()
            try await w.wait("3 drinks") { model.groups.flatMap(\.rows).first { $0.id == MockJournal.drinks }?.count == 3 }
            // The time's chip is the system's compact picker (UIKit, outside SwiftUI's nodes), found by its habit.
            let pickers = Self.datePickers(in: w.window)
            #expect(pickers.map(\.accessibilityIdentifier) == ["journal.time.last_caffeine"])
        }
    }

    /// The system date pickers under `view` (a `ValueChip` puts one over its chip).
    private static func datePickers(in view: UIView) -> [UIDatePicker] {
        (view as? UIDatePicker).map { [$0] } ?? view.subviews.flatMap { datePickers(in: $0) }
    }

    // MARK: hosted: AX3

    @Test("AX3: nothing runs off the screen; Save keeps one line; the rows grow")
    func ax3Sheet() async throws {
        try await HostedWindow.run(width: Self.width, height: 2_400, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   sheet(MockJournalStates.content(.answered))) { w in
            try await w.settle()
            let nodes = w.nodes()
            for node in nodes where node.identifier?.hasPrefix("journal.day.") != true {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= Self.width + 0.5, "\(node.label): \(node.frame)")
            }
            let save = try #require(nodes.first { $0.identifier == "journal.save" })
            #expect(save.frame.width > save.frame.height, "one line: \(save.frame)")
            let alcohol = try #require(nodes.first { $0.identifier == "journal.habit.alcohol" })
            #expect(alcohol.frame.height > GroupedListSpec.rowMinHeight, "\(alcohol.frame)")
            let chip = try #require(nodes.first { $0.identifier == "journal.day.\(Self.yesterday)" })
            #expect(chip.frame.height > JournalLayout.chipHeight, "the chip grows with its words: \(chip.frame)")
        }
    }

    // MARK: Today's card

    @Test("Today's card is one button: the question, why, \"Answer\"; once answered \"Yesterday\", the answers, \"Edit\"")
    func card() async throws {
        for summary in [nil, MockJournalStates.cardSummary] {
            let view = ScrollView { JournalCardBody(summary: summary) {}.padding(20) }
                .background(Theme.background)
                .environment(\.locale, Self.english)
            try await HostedWindow.run(width: Self.width, height: 600, view) { w in
                try await w.settle()
                let nodes = w.nodes()
                let card = try #require(nodes.first { $0.identifier == "journal.card" })
                #expect(nodes.filter { $0.frame.intersects(card.frame) }.count == 1, "one element: \(nodes.map(\.label))")
                #expect(card.traits.contains(.button) && card.hint == "Opens the journal")
                if summary == nil {
                    #expect(card.label.hasPrefix("How was yesterday?") && card.label.hasSuffix("Answer"), "\(card.label)")
                } else {
                    #expect(card.label.hasPrefix("Yesterday") && card.label.hasSuffix("Edit"), "\(card.label)")
                }
                #expect(card.frame.width >= Self.width - 40 - 0.5)
            }
        }
    }

    @Test("The card is ink, never teal or Volt; \"Answer\" ends the first line, and from AX1 goes under the words",
          arguments: [false, true])
    func cardDrawing(ax: Bool) throws {
        let width = Self.width - 40
        let card = JournalCardBody(summary: nil) {}
            .frame(width: width)
            .background(Theme.background)
            .environment(\.dynamicTypeSize, ax ? .accessibility1 : .large)
            .environment(\.locale, Self.english)
        let shot = try #require(ControlRender(card, scale: 2))
        let teal = Tokens.resolve(Theme.recovery), volt = Tokens.resolve(Theme.signal)
        var tinted = 0
        for iy in 0..<shot.height {
            for ix in 0..<shot.width where shot.px(ix, iy).near(teal, 24) || shot.px(ix, iy).near(volt, 24) { tinted += 1 }
        }
        #expect(tinted == 0, "no teal, no Volt: \(tinted) pixels")
        // Ink is the title and "Answer" (the line under the title is `textSecondary`, far dimmer; the underline is at 50 %).
        // The words' column starts after the disc.
        let isInk: (RGBA) -> Bool = { Tokens.luminance($0) > 0.55 }
        let column = Double(CardSpec.padding + IconDisc.regularDiameter + JournalLayout.cardSpacing)
        let height = Double(shot.size.height)
        let ink = try #require(shot.bounds(xs: column...Double(width), ys: 0...height, where: isInk))
        // The lowest line of ink: by default the title with "Answer" at its end, across the card; from AX1 "Answer" alone,
        // under the words at the column's start.
        let lowest = try #require(shot.bounds(xs: column...Double(width), ys: Double(ink.maxY) - 4...Double(ink.maxY), where: isInk))
        let trailing = shot.bounds(xs: Double(width - CardSpec.padding) - 12...Double(width), ys: 0...height, where: isInk)
        if ax {
            #expect(trailing == nil, "nothing at the trailing edge: \(String(describing: trailing))")
            #expect(lowest.width < 160 && abs(Double(lowest.minX) - column) < 6, "Answer under the words: \(lowest)")
            #expect(Double(lowest.minY) > height / 2, "the last line: \(lowest) in \(height)")
        } else {
            #expect(trailing != nil, "Answer at the end of the first line")
            #expect(lowest.width > 200 && Double(lowest.maxY) < height / 2, "the title's line: \(lowest) in \(height)")
        }
    }
}

/// Holds a call open until the test opens it (a save, a read).
@MainActor
final class JournalTestGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    var waiting: Int { waiters.count }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume() }
    }
}
