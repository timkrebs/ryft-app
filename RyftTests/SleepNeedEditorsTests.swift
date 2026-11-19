import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

// C3 (PR 6 C §4.11–§4.12): the body-setting editors, Sleep's need sheet and its card in Nocturne. The decisions are pure
// (`BodySettingContent`, `SleepNeedSheetContent`, `BodySettingsFailure`, `SleepNeedBreakdown`); the hosted suites prove what
// VoiceOver and the layout get, at the default size and at AX3. Every state is honest offline: nothing reads as saved that
// wasn't, and nothing shows the default as if it were the user's.

@MainActor
private func makeState(api: MockPlatformAPI = MockPlatformAPI(), online: Bool = true, user: User? = MockSleepNeedStates.user)
    -> AppState {
    let state = AppState(env: .test(api: api, online: online))
    if let user { state.user = user }
    return state
}

// MARK: - the stepper and the ruler

@MainActor
struct BodySettingStepperTests {
    @Test("Baseline: 4–12 h in 15 minutes; heart rate: 100–230 one at a time; both clamp at their ends")
    func limits() {
        #expect(BodySetting.sleepBase.range == 240...720 && BodySetting.sleepBase.step == 15)
        #expect(BodySetting.maxHR.range == 100...230 && BodySetting.maxHR.step == 1)
        var minutes = 240
        let low = RyftStepperValue(Binding(get: { minutes }, set: { minutes = $0 }), in: BodySetting.sleepBase.range, step: 15,
                                   format: BodySetting.sleepBase.numeral, spoken: BodySetting.sleepBase.spoken)
        #expect(!low.canDecrement && low.canIncrement)
        #expect(low.accessibilityValue == "4 hours, minimum")
        low.step(-1)
        #expect(minutes == 240)
        low.step(1)
        #expect(minutes == 255)
        var bpm = 230
        let high = RyftStepperValue(Binding(get: { bpm }, set: { bpm = $0 }), in: BodySetting.maxHR.range,
                                    format: BodySetting.maxHR.numeral, spoken: BodySetting.maxHR.spoken)
        #expect(high.canDecrement && !high.canIncrement)
        #expect(high.accessibilityValue == "230 beats per minute, maximum")
        high.step(1)
        #expect(bpm == 230)
    }

    @Test("The ruler has one tick per step: 33 for the baseline, 27 (5 bpm) for the heart rate; every baseline lands on a tick")
    func ticks() {
        #expect(BodySetting.sleepBase.tickCount == 33 && BodySetting.maxHR.tickCount == 27)
        let range = 240.0...720.0
        for minutes in stride(from: 240, through: 720, by: 15) {
            let position = (RulerScale.needleFraction(value: Double(minutes), range: range) ?? -1) * 32
            #expect(abs(position - position.rounded()) < 1e-9, "\(minutes) min sits between ticks")
        }
        #expect(BodySetting.sleepBase.rulerLabels == ["4 h", "8 h", "12 h"])
        #expect(BodySetting.maxHR.rulerLabels == ["100 bpm", "165", "230 bpm"])
    }

    @Test("VoiceOver hears the unit: 8 hours 15 minutes, 185 beats per minute")
    func spokenUnits() {
        #expect(BodySetting.sleepBase.spoken(495) == "8 hours 15 minutes")
        #expect(BodySetting.sleepBase.numeral(495) == "8:15")
        #expect(BodySetting.maxHR.spoken(185) == "185 beats per minute")
        #expect(BodySetting.maxHR.text(185) == "185 bpm")
    }
}

// MARK: - what an editor shows

@MainActor
struct BodySettingContentTests {
    @Test("Unchanged: Save is off; changed: Save is on and the source line names the saved value")
    func changedAndUnchanged() {
        let editor = BodySettingsEditor(state: makeState())
        let unchanged = BodySettingContent(.sleepBase, editor: editor, draft: 450)
        #expect(!unchanged.isChanged && !unchanged.canSave)
        #expect(unchanged.source == "Set by you")
        let changed = BodySettingContent(.sleepBase, editor: editor, draft: 465)
        #expect(changed.isChanged && changed.canSave)
        #expect(changed.numeral == "7:45" && changed.spoken == "7 hours 45 minutes")
        #expect(changed.source == "Set by you · saved 7:30")
        let hr = BodySettingContent(.maxHR, editor: editor, draft: 185)
        #expect(hr.source == "Estimated from your age (born 1990) · saved 190 bpm" && hr.canSave)
    }

    @Test("While a save is out, Save is off (it shows Saving… itself) and the numeral can't move")
    func whileSaving() async {
        let api = MockPlatformAPI()
        let state = makeState(api: api)
        let editor = BodySettingsEditor(state: state)
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        let save = Task { await editor.setSleepBase(465) }
        #expect(await eventually { editor.saving })
        #expect(!BodySettingContent(.sleepBase, editor: editor, draft: 480).canSave)
        await gate.open()
        #expect(await save.value)
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: 480).canSave)
    }

    @Test("Set by hand, the row goes back to RYFT's estimate with the learned value; without one, to the default")
    func theEstimateRow() {
        let state = makeState()
        let editor = BodySettingsEditor(state: state)
        let estimate = BodySettingContent(.sleepBase, editor: editor, draft: 450).estimate
        #expect(estimate == BodySettingContent.Estimate(title: "Use RYFT's estimate", value: "7:52", spokenValue: "7 hours 52 minutes"))
        var user = MockSleepNeedStates.user
        user.sleepBaseLearnedMin = nil
        state.user = user
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: 450).estimate
                == BodySettingContent.Estimate(title: "Use the default", value: nil, spokenValue: nil))
        user.sleepBaseSource = .learned
        state.user = user
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: 450).estimate == nil, "learned already")
        // Max HR: the estimate's value isn't sent, so the row has none.
        var manual = MockSleepNeedStates.user
        manual.maxHrSource = .manual
        state.user = manual
        #expect(BodySettingContent(.maxHR, editor: editor, draft: 190).estimate
                == BodySettingContent.Estimate(title: "Use the estimate", value: nil, spokenValue: nil))
    }

    @Test("No account on this iPhone: the default, no source, Save off; offline it says so")
    func noAccount() {
        let online = BodySettingContent(.sleepBase, editor: BodySettingsEditor(state: makeState(user: nil)), draft: 475)
        #expect(online.source == nil && !online.canSave && !online.isOfflineWithoutAccount)
        let offline = BodySettingContent(.sleepBase, editor: BodySettingsEditor(state: makeState(online: false, user: nil)),
                                         draft: BodySettingsEditor.defaultSleepBase)
        #expect(offline.numeral == "7:40" && offline.source == nil && !offline.canSave && offline.isOfflineWithoutAccount)
    }
}

// MARK: - failures in words

@MainActor
struct BodySettingsFailureTests {
    @Test("Offline: nothing was sent", arguments: [
        (APIError.transport(URLError(.notConnectedToInternet)), true), (APIError.transport(URLError(.timedOut)), false),
    ])
    func offline(_ error: APIError, online: Bool) {
        #expect(BodySettingsFailure(save: error, online: online).message
                == "You're offline, so this wasn't saved. Try again when you're back online.")
        #expect(BodySettingsFailure(rescore: error, online: online).message
                == "You're offline, so nothing was rescored. Try again when you're back online.")
    }

    @Test("No answer: it may have saved", arguments: [
        APIError.transport(URLError(.timedOut)), APIError.http(503, "", requestID: "rid-503"), APIError.http(500, ""),
    ])
    func noAnswer(_ error: APIError) {
        #expect(BodySettingsFailure(save: error, online: true).message
                == "RYFT didn't answer, so this may not have saved. Try again in a moment.")
        #expect(BodySettingsFailure(rescore: error, online: true).message
                == "RYFT didn't answer, so the rescore may not have started. Try again in a moment.")
    }

    @Test("Refused (429, 409, 403): it's back as it was; the request ID goes along, never the raw error text",
          arguments: [APIError.http(429, "", requestID: "rid-429"), APIError.http(409, "conflict", requestID: "rid-409"),
                      APIError.http(403, "forbidden", requestID: "rid-403")])
    func refused(_ error: APIError) {
        let failure = BodySettingsFailure(save: error, online: true)
        #expect(failure.message == "RYFT couldn't save this change, so it's back as it was.")
        #expect(failure.details?.contains("Request ID rid-") == true)
        #expect(failure.message != error.localizedDescription)
        #expect(BodySettingsFailure(rescore: error, online: true).message
                == "RYFT couldn't rescore your days, so past days keep their scores. Try again in a moment.")
    }

    @Test("Offline, a save says so, the value goes back, and nothing claims Saved")
    func anOfflineSave() async {
        let api = MockPlatformAPI()
        let state = makeState(api: api, online: false)
        let editor = BodySettingsEditor(state: state)
        api.failNext = APIError.transport(URLError(.notConnectedToInternet))
        #expect(!(await editor.setSleepBase(465)))
        #expect(editor.error == "You're offline, so this wasn't saved. Try again when you're back online.")
        #expect(editor.sleepBase == 450 && !editor.savedChange)
        #expect(BodySettingContent(.sleepBase, editor: editor, draft: editor.sleepBase).source == "Set by you")
    }

    @Test("A failed rescore is marked failed, in words, and keeps the request ID")
    func aFailedRescore() async {
        let api = MockPlatformAPI()
        let editor = BodySettingsEditor(state: makeState(api: api))
        api.failure = APIError.http(500, "", requestID: "rid-rescore")
        await editor.rescore()
        #expect(editor.rescoreFailed)
        #expect(editor.rescoreStatus == "RYFT didn't answer, so the rescore may not have started. Try again in a moment.")
        #expect(editor.rescoreDetails?.contains("rid-rescore") == true)
        api.failure = nil
        editor.begin()
        #expect(!editor.rescoreFailed && editor.rescoreStatus == nil)
    }
}

// MARK: - the need, its sheet and its card

struct SleepNeedContentTests {
    @Test("The terms as clocks, in words for VoiceOver; the nap is a real minus")
    func terms() {
        let b = SleepNeedBreakdown(MockSleepNeedStates.needWithNap)
        #expect(b.terms.map(\.title) == ["Baseline", "Strain", "Sleep debt", "Nap credit"])
        #expect(b.terms.map(\.signed) == ["7:30", "+0:20", "+0:28", "−0:25"])
        #expect(b.terms.map(\.spoken) == ["Baseline, 7 hours 30 minutes", "Strain, plus 20 minutes",
                                          "Sleep debt, plus 28 minutes", "Nap credit, minus 25 minutes"])
    }

    @Test("The sentence in clocks; VoiceOver's in words")
    func sentence() {
        let b = SleepNeedBreakdown(MockSleepNeedStates.need)
        #expect(b.sentence == "You needed 8:18: 7:30 baseline, +0:20 for yesterday's strain, +0:28 of debt.")
        #expect(b.spokenSentence
                == "You needed 8 hours 18 minutes: 7 hours 30 minutes baseline, +20 minutes for yesterday's strain, +28 minutes of debt.")
    }

    @Test("The sheet's numeral: the breakdown's total, or the night's need without one, or unlit")
    func numeral() {
        let full = SleepNeedSheetContent(need: MockSleepNeedStates.need, needMinutes: nil)
        #expect(full.numeral == "8:18" && full.spokenNumeral == "Sleep need, 8 hours 18 minutes" && full.breakdown != nil)
        let older = SleepNeedSheetContent(need: nil, needMinutes: 490)
        #expect(older.numeral == "8:10" && older.breakdown == nil)
        let none = SleepNeedSheetContent(need: nil, needMinutes: nil)
        #expect(none.numeral == nil && none.spokenNumeral == "Sleep need, no value yet")
    }

    @Test("The baseline row reads the cached account; without one it says so instead of the default")
    @MainActor
    func baselineRow() {
        let loaded = SleepNeedSheetContent.BaselineRow(editor: BodySettingsEditor(state: makeState()))
        #expect(loaded.value == "7:30" && loaded.spokenValue == "7 hours 30 minutes" && loaded.detail == "Set by you")
        let missing = SleepNeedSheetContent.BaselineRow(editor: BodySettingsEditor(state: makeState(online: false, user: nil)))
        #expect(missing.value == "Not loaded yet" && missing.detail == nil)
    }
}

// MARK: - colour (L27)

struct SleepNeedColourTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Ryft")

    @Test("No teal, accent or recovery in the editors, the need sheet, its card and the tile; no Volt of their own",
          arguments: ["Features/Profile/BodySettingsForms.swift", "Features/Sleep/SleepNeedSheet.swift",
                      "Design/SleepNeedBar.swift", "Preview/MockSleepNeedStates.swift"])
    func noTealNoVolt(_ path: String) throws {
        let text = try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
        let teal = try Regex(#"Theme\.(teal|accent\w*|onAccent|recovery)|Color\("(Accent|Teal|Recovery)"#)
        #expect(!text.contains(teal), "\(path) names teal or the accent")
        // Volt is the ruler's needle (`RulerScale`), never a page's own colour.
        #expect(!text.contains("Theme.signal"), "\(path) uses Volt")
    }

    @Test("The tile is the sleep colour")
    func theTileIsSleep() throws {
        let text = try String(contentsOf: Self.root.appendingPathComponent("Design/SleepNeedBar.swift"), encoding: .utf8)
        #expect(text.contains("GlowTile(Theme.metricSleep"))
    }
}

// MARK: - hosted: the editors

@MainActor
@Suite("C3: the editors, hosted", .serialized)
struct BodySettingsEditorHostedTests {
    static let width: CGFloat = 390, height: CGFloat = 844

    private func host(_ setting: BodySetting = .sleepBase, state: AppState? = nil, ax3: Bool = false,
                      body: (HostedWindow, BodySettingsEditor) async throws -> Void) async throws {
        let state = state ?? makeState()
        let editor = BodySettingsEditor(state: state)
        let page = setting == .sleepBase ? AnyView(BaselineSleepNeedForm(editor: editor, showsClose: true))
            : AnyView(MaxHeartRateForm(editor: editor, showsClose: true))
        try await HostedWindow.run(width: Self.width, height: Self.height, bottomInset: 34,
                                   typeSize: ax3 ? .accessibility3 : .large, category: ax3 ? .accessibilityExtraLarge : .large,
                                   page.previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))) { w in
            try await w.wait("the stepper") { w.nodes().contains { $0.isAdjustable } }
            try await w.settle()
            try await body(w, editor)
        }
    }

    private func stepper(_ w: HostedWindow) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.isAdjustable }, "the stepper")
    }

    private func save(_ w: HostedWindow, _ setting: BodySetting = .sleepBase) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == setting.saveIdentifier }, "Save")
    }

    @Test("The numeral and its circles are one adjustable element that speaks its unit", arguments: [BodySetting.sleepBase, .maxHR])
    func oneAdjustableElement(_ setting: BodySetting) async throws {
        try await host(setting) { w, _ in
            let element = try stepper(w)
            #expect(element.label == (setting == .sleepBase ? "Baseline sleep need" : "Maximum heart rate"))
            #expect(element.value == (setting == .sleepBase ? "7 hours 30 minutes" : "190 beats per minute"))
            // The circles take taps but VoiceOver doesn't stop on them; the ruler repeats the value and is hidden.
            #expect(!w.nodes().contains { $0.label == "Less" || $0.label == "More" })
            #expect(!w.nodes().contains { $0.identifier == "bodySettings.ruler" })
            element.increment()
            try await w.wait("a step up") { (try? stepper(w).value) == (setting == .sleepBase ? "7 hours 45 minutes" : "191 beats per minute") }
            try stepper(w).decrement()
            try stepper(w).decrement()
            try await w.wait("two down") { (try? stepper(w).value) == (setting == .sleepBase ? "7 hours 15 minutes" : "189 beats per minute") }
        }
    }

    @Test("Save is off while nothing changed, on once something did; the source line names the saved value")
    func saveFollowsTheChange() async throws {
        try await host { w, _ in
            #expect(try !save(w).isEnabled)
            #expect(w.node("Set by you", exactly: true) != nil)
            try stepper(w).increment()
            try await w.wait("Save on") { (try? save(w).isEnabled) == true }
            #expect(w.node("Set by you · saved 7:30", exactly: true) != nil)
        }
    }

    @Test("Saving: the pill says Saving… and is busy, the stepper is off; Saved: the notice, the rescore row, Save off again")
    func savingThenSaved() async throws {
        let api = MockPlatformAPI()
        let gate = Gate()
        api.beforePatchMe = { await gate.wait() }
        try await host(state: makeState(api: api)) { w, editor in
            try stepper(w).increment()
            try await w.wait("Save on") { (try? save(w).isEnabled) == true }
            try save(w).activate()
            try await w.wait("Saving…") { (try? save(w).label) == "Saving…" }
            #expect(try save(w).value == "In progress")
            #expect(try !stepper(w).isEnabled)
            #expect(!w.nodes().contains { $0.label.hasPrefix("Saved.") }, "nothing reads as saved yet")
            await gate.open()
            try await w.wait("Saved") { w.node("Saved. Past days keep their scores until you rescore them.") != nil }
            try await w.settle()
            #expect(try save(w).label == "Save" && !save(w).isEnabled)
            #expect(try stepper(w).value == "7 hours 45 minutes" && editor.sleepBase == 465)
            #expect(w.nodes().contains { $0.identifier == "bodySettings.rescore" && $0.label == "Rescore the last 90 days" })
        }
    }

    @Test("A refusal, no answer or offline: the notice under the value, the value back, nothing saved", arguments: [
        ("refused", true), ("noAnswer", true), ("offline", false),
    ])
    func failures(_ kind: String, online: Bool) async throws {
        let api = MockPlatformAPI()
        switch kind {
        case "refused": api.failNext = APIError.http(422, "sleep_base_min out of range", requestID: "rid-422")
        case "noAnswer": api.failNext = APIError.transport(URLError(.timedOut))
        default: api.failNext = APIError.transport(URLError(.notConnectedToInternet))
        }
        let message = switch kind {
        case "refused": "RYFT takes a baseline between 4 and 12 hours."
        case "noAnswer": "RYFT didn't answer, so this may not have saved. Try again in a moment."
        default: "You're offline, so this wasn't saved. Try again when you're back online."
        }
        try await host(state: makeState(api: api, online: online)) { w, editor in
            try stepper(w).increment()
            try await w.wait("Save on") { (try? save(w).isEnabled) == true }
            try save(w).activate()
            try await w.wait("the notice") { w.node(message, exactly: true) != nil }
            try await w.settle()
            let notice = try #require(w.node(message, exactly: true))
            let value = try stepper(w)
            let paragraph = try #require(w.node("Each night's sleep need starts from this baseline"))
            #expect(notice.frame.minY > value.frame.maxY && notice.frame.maxY < paragraph.frame.minY,
                    "under the value, above the paragraph: \(notice.frame) \(value.frame) \(paragraph.frame)")
            #expect(value.value == "7 hours 30 minutes" && editor.sleepBase == 450, "back to the saved value")
            #expect(!w.nodes().contains { $0.label.hasPrefix("Saved.") })
            #expect(try !save(w).isEnabled)
            if kind == "refused" {
                #expect(w.nodes().contains { $0.label.contains("Request ID rid-422") || ($0.value ?? "").contains("rid-422") })
            }
        }
    }

    @Test("A failed rescore says so under the rescore row, with the request ID; Saved stays above")
    func aFailedRescoreUnderItsRow() async throws {
        let api = MockPlatformAPI()
        try await host(state: makeState(api: api)) { w, editor in
            await editor.setSleepBase(465)
            try await w.wait("the rescore row") { w.nodes().contains { $0.identifier == "bodySettings.rescore" } }
            api.failure = APIError.http(500, "", requestID: "rid-rescore")
            try #require(w.nodes().first { $0.identifier == "bodySettings.rescore" }).activate()
            let message = "RYFT didn't answer, so the rescore may not have started. Try again in a moment."
            try await w.wait("the rescore notice") { w.node(message) != nil }
            try await w.settle()
            let row = try #require(w.nodes().first { $0.identifier == "bodySettings.rescore" })
            let notice = try #require(w.node(message))
            let saved = try #require(w.node("Saved. Past days keep their scores until you rescore them."))
            #expect(saved.frame.maxY <= row.frame.minY && notice.frame.minY >= row.frame.maxY, "\(saved.frame) \(row.frame) \(notice.frame)")
            #expect(w.nodes().contains { $0.label.contains("Request ID rid-rescore") || ($0.value ?? "").contains("rid-rescore") })
            #expect(row.isEnabled && row.label == "Rescore the last 90 days", "it can be tried again")
        }
    }

    @Test("Offline with no account on this iPhone: the default, a notice that says so, Save off")
    func offlineWithoutAccount() async throws {
        try await host(state: makeState(online: false, user: nil)) { w, _ in
            #expect(try stepper(w).value == "7 hours 40 minutes")
            #expect(w.nodes().contains { $0.label.hasPrefix("You're offline and RYFT hasn't loaded your settings yet") })
            try stepper(w).increment()
            try await w.settle()
            #expect(try !save(w).isEnabled)
        }
    }

    @Test("AX3: nothing leaves the screen's width; the circles stay beside the numeral; Save stays reachable")
    func ax3() async throws {
        try await host(ax3: true) { w, _ in
            for node in w.nodes() {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= Self.width + 0.5 && node.frame.height > 0,
                        "\(node.label) \(node.frame)")
            }
            let value = try stepper(w)
            #expect(value.frame.height < 160, "one row, not stacked: \(value.frame)")
            let pill = try save(w)
            #expect(pill.frame.maxY <= Self.height - 34 + 0.5 && pill.frame.height >= 52)
        }
    }
}

// MARK: - hosted: the sheet and the card

@MainActor
@Suite("C3: Sleep need, hosted", .serialized)
struct SleepNeedHostedTests {
    private func host(need: SleepNeed? = MockSleepNeedStates.need, needMinutes: Int? = nil, state: AppState? = nil,
                      ax3: Bool = false, body: (HostedWindow) async throws -> Void) async throws {
        let state = state ?? makeState()
        let sheet = SleepNeedSheet(need: need, total: "8h 18m", needMinutes: needMinutes, night: "Last night · Sun, Nov 15",
                                   editor: BodySettingsEditor(state: state))
        try await HostedWindow.run(width: 390, height: ax3 ? 2_400 : 1_000, bottomInset: 0,
                                   typeSize: ax3 ? .accessibility3 : .large, category: ax3 ? .accessibilityExtraLarge : .large,
                                   sheet.previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))) { w in
            try await w.wait("the baseline row") { w.nodes().contains { $0.identifier == "sleepNeed.changeBaseline" } }
            try await w.settle()
            try await body(w)
        }
    }

    @Test("VoiceOver: the numeral, the tile's head, one element per term, the sentence, the paragraph, the row")
    func readingOrder() async throws {
        try await host { w in
            let labels = w.nodes().map(\.label)
            let order = ["Sleep need, 8 hours 18 minutes", "How it adds up", "Baseline, 7 hours 30 minutes",
                         "Strain, plus 20 minutes", "Sleep debt, plus 28 minutes",
                         SleepNeedBreakdown(MockSleepNeedStates.need).spokenSentence, "Your baseline is yours to set",
                         "Baseline sleep need"].map { label in labels.firstIndex { $0.hasPrefix(label) } ?? -1 }
            #expect(!order.contains(-1) && order == order.sorted(), "\(order) in \(labels)")
            let head = try #require(w.node("How it adds up", exactly: true))
            #expect(head.traits.contains(.header) && head.value == "8 hours 18 minutes")
            // Each term's ticks are one value, not 30 elements; no nap without a credit.
            #expect(!labels.contains { $0.hasPrefix("Nap credit") })
            let row = try #require(w.nodes().first { $0.identifier == "sleepNeed.changeBaseline" })
            #expect(row.label == "Baseline sleep need" && row.hint == "Opens the editor")
            #expect(row.value?.hasPrefix("7 hours 30 minutes") == true, "\(row.value ?? "")")
        }
    }

    @Test("A nap credit is its own row, a minus")
    func napCredit() async throws {
        try await host(need: MockSleepNeedStates.needWithNap) { w in
            #expect(w.node("Nap credit, minus 25 minutes", exactly: true) != nil)
            #expect(w.node("Sleep need, 7 hours 53 minutes", exactly: true) != nil)
        }
    }

    @Test("No breakdown: the notice instead of the tile, the night's need as the numeral, no sentence")
    func noBreakdown() async throws {
        try await host(need: nil, needMinutes: 498) { w in
            #expect(w.node("This night was scored before RYFT broke the need down.", exactly: true) != nil)
            #expect(w.node("How it adds up") == nil && !w.nodes().contains { $0.identifier == "sleepNeed.sentence" })
            #expect(w.node("Sleep need, 8 hours 18 minutes", exactly: true) != nil)
            #expect(w.nodes().contains { $0.identifier == "sleepNeed.changeBaseline" })
        }
    }

    @Test("Offline with no account cached: the baseline row says Not loaded yet, never the default")
    func offlineWithoutAccount() async throws {
        try await host(state: makeState(online: false, user: nil)) { w in
            let row = try #require(w.nodes().first { $0.identifier == "sleepNeed.changeBaseline" })
            #expect(row.value == "Not loaded yet")
            #expect(w.node("Sleep need, 8 hours 18 minutes", exactly: true) != nil, "the night is the cached one")
        }
    }

    @Test("AX3: nothing leaves the width, the terms stack (label and value over the ticks), the row grows")
    func ax3() async throws {
        var defaultRow: CGFloat = 0
        try await host { w in
            let strain = try #require(w.node("Strain, plus 20 minutes", exactly: true))
            #expect(strain.frame.height < 20, "one line at the default size: \(strain.frame)")
            defaultRow = try #require(w.nodes().first { $0.identifier == "sleepNeed.changeBaseline" }).frame.height
        }
        try await host(ax3: true) { w in
            for node in w.nodes() {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= 390.5 && node.frame.height > 0, "\(node.label) \(node.frame)")
            }
            for label in ["Baseline, 7 hours 30 minutes", "Strain, plus 20 minutes", "Sleep debt, plus 28 minutes"] {
                let term = try #require(w.node(label, exactly: true))
                #expect(term.frame.height > TickRow.tick.height + TickRow.stackedSpacing + 20, "\(label) stacked: \(term.frame)")
            }
            let row = try #require(w.nodes().first { $0.identifier == "sleepNeed.changeBaseline" })
            #expect(row.frame.height > 2 * defaultRow, "the value goes under the title: \(row.frame.height) vs \(defaultRow)")
        }
    }

    @Test("The card: one push row with the need in words, its hint, and the sentence as its footer; a tap opens the sheet")
    func card() async throws {
        var opened = false
        let state = makeState()
        try await HostedWindow.run(width: 390, height: 400, bottomInset: 0,
                                   SleepNeedCard(need: MockSleepNeedStates.need) { opened = true }
                                       .padding(20).previewEnvironment(state)) { w in
            try await w.wait("the card") { w.nodes().contains { $0.identifier == "sleep.need" } }
            let row = try #require(w.nodes().first { $0.identifier == "sleep.need" })
            #expect(row.label == "Sleep need" && row.value == "8 hours 18 minutes")
            #expect(row.hint == "Shows how your sleep need adds up, and your baseline to change" && row.traits.contains(.button))
            #expect(w.node(SleepNeedBreakdown(MockSleepNeedStates.need).spokenSentence, exactly: true) != nil)
            row.activate()
            #expect(await eventually(timeout: .seconds(5)) { opened })
        }
    }
}
