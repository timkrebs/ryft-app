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

    private func journalStore(_ api: MockPlatformAPI = MockPlatformAPI(), online: Bool = true, cached days: [JournalDay] = [])
        -> (JournalStore, AppEnvironment) {
        // The mock answers relative to the real date, so the clock starts there too.
        let env = AppEnvironment.test(api: api, clock: TestClock(now: .now), online: online)
        env.persistence.saveDocument(MockJournal.behaviors, key: JournalStore.behaviorsKey, at: .now)
        for day in days { env.persistence.saveDocument(day, key: JournalStore.dayKey(day.day), at: .now) }
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

    @Test("A cached day is its rows offline too; without a habit chosen it is the no-habits state")
    func cachedAndNoHabits() async {
        let (store, _) = journalStore(online: false, cached: [MockJournal.journal(day: Self.yesterday)])
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

    @Test("Save is off for a read-only day, without habits, while the day isn't here, and while it saves")
    func saveIsOff() {
        let states = Dictionary(uniqueKeysWithValues: MockJournalStates.Sheet.allCases.map { ($0, MockJournalStates.content($0)) })
        #expect(states[.answered]?.canSave == true)
        #expect(states[.offline]?.canSave == true, "a cached day offline: Save tries, and says so if it can't")
        for off in [MockJournalStates.Sheet.readOnly, .noHabits, .loading, .offlineUncached, .failed, .saving] {
            #expect(states[off]?.canSave == false, "\(off)")
        }
        #expect(states[.readOnly]?.saveHint == "This day can't be changed any more.")
        #expect(states[.saving]?.saveHint == nil, "busy says In progress, not a reason")
    }

    @Test("A failed save keeps its status and request ID for Details; offline it says nothing was sent")
    func saveFailure() async throws {
        let api = MockPlatformAPI()
        let (store, env) = journalStore(api, cached: [MockJournal.journal(day: Self.yesterday)])
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
            let pixels = try #require(WindowPixels(w))
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
        try await HostedWindow.run(width: Self.width, height: 844, sheet(MockJournalStates.content(.answered))) { w in
            try await w.settle()
            #expect(!w.nodes().contains { $0.identifier == "journal.offlinePill" })
        }
    }

    @Test("Offline with the day not on this iPhone: a line with Try again, no outlines; back online it loads by itself")
    func uncachedOfflineLive() async throws {
        let state = AppState.preview(online: false)
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
        let unanswered = JournalDay(day: Self.yesterday, answered: false, answeredAt: nil, editable: true, entries: [])
        state.env.persistence.saveDocument(MockJournal.noneEnabled, key: JournalStore.behaviorsKey, at: .now)
        state.env.persistence.saveDocument(unanswered, key: JournalStore.dayKey(Self.yesterday), at: .now)
        // The platform's yesterday unanswered too (the mock answers it as API.md's example otherwise).
        let api = try #require(state.env.api as? MockPlatformAPI)
        _ = try await api.putJournal(day: Self.yesterday, JournalPut(entries: []))
        let store = JournalStore(env: state.env)
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

    @Test("Loading is one element over outline cards; a failed read says so with Try again")
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
        }
    }

    @Test("A read-only day: the lock notice; taps and VoiceOver change nothing; the switches keep their state and stay enabled")
    func readOnly() async throws {
        let taps = Taps()
        let actions = JournalSheetActions(setOn: { id, _ in taps.setOn.append(id) })
        try await HostedWindow.run(width: Self.width, height: 844, sheet(MockJournalStates.content(.readOnly), actions: actions)) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.contains { $0.identifier == "journal.readOnly" || $0.label == "This day can't be changed any more." })
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
            #expect(alcohol.label == "Alcohol" && alcohol.value == reference.on, "\(alcohol.label) \(alcohol.value ?? "nil")")
            #expect(alcohol.traits.contains(.toggleButton) || alcohol.traits.contains(.button))
            let screens = try #require(nodes.first { $0.identifier == "journal.habit.screens_in_bed" })
            #expect(screens.value == reference.off)
            let drinks = try #require(nodes.first { $0.identifier == "journal.count.drinks" })
            #expect(drinks.label == "Drinks" && drinks.value == "2" && drinks.isAdjustable, "\(drinks.label) \(drinks.value ?? "")")
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

    @Test("The card's disc and words are ink, never teal (L27)", arguments: [false, true])
    func cardDrawing(ax: Bool) throws {
        let card = JournalCardBody(summary: nil) {}
            .frame(width: Self.width - 40)
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
        // The words are drawn: the card's top line holds ink.
        let ink = shot.bounds(xs: 60...Double(shot.size.width) - 16, ys: 12...40) { Tokens.luminance($0) > 0.5 }
        #expect(ink != nil)
    }
}

/// A hosted window's pixels, drawn once, read many times (sRGB, window points).
@MainActor
private struct WindowPixels {
    let image: ControlRenderBytes

    init?(_ w: HostedWindow) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let ui = UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
            w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
        }
        guard let bytes = ControlRenderBytes(ui, scale: 2) else { return nil }
        image = bytes
    }

    func at(_ x: CGFloat, _ y: CGFloat) -> NocturneTokenTests.RGBA { image.at(Double(x), Double(y)) }

    /// How many pixels in `rect` match.
    func count(in rect: CGRect, where match: (NocturneTokenTests.RGBA) -> Bool) -> Int {
        var n = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                if match(at(x, y)) { n += 1 }
                x += 0.5
            }
            y += 0.5
        }
        return n
    }
}

/// An image's bytes in sRGB, as `ControlRender` reads its own.
private struct ControlRenderBytes {
    let width: Int, height: Int, scale: CGFloat
    let bytes: [UInt8]

    init?(_ image: UIImage, scale: CGFloat) {
        guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (w, h) = (cg.width, cg.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        (width, height, self.scale, self.bytes) = (w, h, scale, bytes)
    }

    func at(_ x: Double, _ y: Double) -> NocturneTokenTests.RGBA {
        let ix = min(max(Int((x * Double(scale)).rounded(.down)), 0), width - 1)
        let iy = min(max(Int((y * Double(scale)).rounded(.down)), 0), height - 1)
        let i = (iy * width + ix) * 4
        let a = Double(bytes[i + 3]) / 255
        guard a > 0 else { return .init(r: 0, g: 0, b: 0, a: 0) }
        return .init(r: Double(bytes[i]) / 255 / a, g: Double(bytes[i + 1]) / 255 / a, b: Double(bytes[i + 2]) / 255 / a, a: a)
    }
}
