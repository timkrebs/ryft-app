import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// PR 6 combine (A's About you, C's editors): once the birth year is saved, About you's two rows are C's editor rows. A row
/// says "Saving…" while a change of its setting is out, never the value on its way; a failure that answers after its editor
/// sheet went is said under the card, where the user is, as Profile's About you does (`BodySettingsEditor.errorMissed`).
@MainActor
@Suite("About you: the editor's rows and a failure that came after the sheet went", .serialized)
struct AboutYouEditorTests {
    private static let wait: Duration = .seconds(15)
    private static let noAnswer = "RYFT didn't answer, so this may not have saved. Try again in a moment."

    @Test("A write out: its row says Saving…, the other keeps its value; its failure, with no editor open, is under the card")
    func savingRowAndMissedFailure() async throws {
        let (api, platform) = C3Platform.api()
        let state = AppState(env: .test(api: api, online: true))
        state.user = MockSleepNeedStates.user
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        #expect(await model.saveAboutYou(birthYear: 1990), "the birth year saves; the rows follow")
        // From here every `PATCH /v1/me` waits for the gate and never answers: the change may or may not have saved.
        let gate = Gate()
        platform.applies = false
        platform.onPatch = {
            await gate.wait()
            throw APIError.transport(URLError(.timedOut))
        }
        let editor = model.bodySettings
        let view = OnboardingStepView(step: .aboutYou, model: model)
            .previewEnvironment(state)
            .environment(\.locale, Locale(identifier: "en_US"))
        try await HostedWindow.run(width: 390, height: 1_400, view) { w in
            let row = { (id: String) in w.nodes().first { $0.identifier == id } }
            try await w.wait("the saved rows", timeout: Self.wait) { row("aboutYou.sleepBase") != nil }
            try await w.settle()
            let maxHR = try #require(row("aboutYou.maxHR")?.value)
            let saved = try #require(row("aboutYou.sleepBase")?.value)
            #expect(saved == "7h 30m, Set by you · learned 7h 52m", "the saved value and where it comes from: \(saved)")
            #expect(row("aboutYou.bodySettingsError") == nil)

            let saving = Task { await editor.setSleepBase(480) }
            try await w.wait("Saving…", timeout: Self.wait) { row("aboutYou.sleepBase")?.value == "Saving…" }
            #expect(row("aboutYou.maxHR")?.value == maxHR, "only the setting on its way")
            #expect(!w.nodes().contains { ($0.value ?? "").contains("8h") }, "the value on its way is the editor's alone")
            #expect(row("aboutYou.bodySettingsError") == nil, "nothing failed yet")

            await gate.open()
            _ = await saving.value
            try await w.wait("the failure, under the card", timeout: Self.wait) { row("aboutYou.bodySettingsError") != nil }
            try await w.settle()
            let notice = try #require(row("aboutYou.bodySettingsError"))
            #expect(notice.label.contains(Self.noAnswer), "\(notice.label)")
            let card = try #require(row("aboutYou.sleepBase"))
            #expect(notice.frame.minY >= card.frame.maxY, "under the card: \(notice.frame) / \(card.frame)")
            #expect(card.value == saved, "back to the saved value: \(card.value ?? "")")
        }
    }
}
