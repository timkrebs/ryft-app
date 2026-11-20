import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes the body-setting editors and Sleep's need card and sheet (PR 6 C §4.11–§4.12) as 3x PNGs, whole pages
/// (`PagedWindowShot`), at the default size and at AX3, when `SLEEPNEED_SHOTS_DIR` is set; otherwise does nothing. Run it with
/// `TEST_RUNNER_SLEEPNEED_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/SleepNeedEditorsShotsTests test-without-building`
/// and compare the set with the drafts (c-18…c-20). Each state is reached as the user reaches it (a step of the stepper, a
/// save the mock platform takes or refuses). Drawn from a real window; for comparing, not a golden-file test. Synthetic data.
@MainActor
@Suite("C3: editors and Sleep need, shots", .serialized)
struct SleepNeedEditorsShotsTests {
    @Test(arguments: Self.names)
    func writeScreen(_ name: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["SLEEPNEED_SHOTS_DIR"] else { return }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            let screen = SleepNeedShotScreen(name)
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                       screen.view) { w in
                try await w.settle()
                try await screen.stage(w)
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                try #require(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
                await screen.finish()
            }
        }
    }

    nonisolated static let names = [
        "baseline", "baseline-changed", "baseline-saved", "baseline-refused", "baseline-no-answer", "baseline-offline",
        "baseline-offline-no-account", "baseline-rescore-failed", "max-hr", "max-hr-changed",
        "sleep-need", "sleep-need-nap", "sleep-need-no-breakdown", "sleep-need-offline-no-account", "sleep-need-card",
        // The review round (C3 fix round): the states that changed or are new.
        "baseline-server-error", "baseline-not-loaded", "baseline-saving", "baseline-rescoring", "baseline-rescored",
        "baseline-onboarding-saved", "max-hr-no-birth-year", "sleep-need-saving", "sleep-need-missed-failure",
        // C3 review 2: a 429's own words.
        "baseline-busy",
    ]
}

/// One screen in one state on the mock platform (`MockSleepNeedStates`: 7:30 set by hand, RYFT learned 7:52, 190 bpm
/// estimated), US English.
@MainActor
struct SleepNeedShotScreen {
    let name: String
    let state: AppState
    let editor: BodySettingsEditor
    /// Holds a save's answer while the shot is taken (`finish` lets it go).
    let gate = Gate()
    /// The rescore whose reload never ran: the test environment's clock, moved by hand.
    private let clock = TestClock()

    init(_ name: String) {
        self.name = name
        switch name {
        case "baseline-not-loaded":
            state = MockSleepNeedStates.state(account: false)
        case "baseline-rescoring":
            state = AppState(env: .test(clock: clock))
            state.user = MockSleepNeedStates.user
        case "max-hr-no-birth-year":
            state = MockSleepNeedStates.state()
            state.user = MockSleepNeedStates.user(maxHr: 185, maxHrSource: .manual, birthYear: nil)
        default:
            state = MockSleepNeedStates.state(account: !name.hasSuffix("no-account"), online: !(name.contains("offline")))
        }
        editor = BodySettingsEditor(state: state)
    }

    /// After the shot: a held answer goes, so nothing waits past the test.
    func finish() async {
        await gate.open()
    }

    /// The mock answers with its own account (`MockData.user`), also when RYFT is asked again after a failure: the draft's
    /// (7:30 set by hand, RYFT learned 7:52) goes back in.
    private func reseed() {
        state.user = MockSleepNeedStates.user
    }

    private var api: MockPlatformAPI? { state.env.api as? MockPlatformAPI }

    var view: AnyView {
        let page: AnyView
        switch name {
        case "baseline-onboarding-saved":
            page = AnyView(BaselineSleepNeedForm(editor: editor, showsClose: true, rescores: false))
        case let n where n.hasPrefix("baseline"): page = AnyView(BaselineSleepNeedForm(editor: editor, showsClose: true))
        case let n where n.hasPrefix("max-hr"): page = AnyView(MaxHeartRateForm(editor: editor, showsClose: true))
        case "sleep-need-card":
            if var sleep = MockData.todayDetail.sleep {
                sleep.need = MockSleepNeedStates.need
                page = AnyView(ScrollView {
                    SleepNightCards(sleep: sleep, score: MockData.todayScore).padding(20)
                }
                .background(Theme.background))
            } else {
                page = AnyView(EmptyView())
            }
        case "sleep-need-nap":
            page = AnyView(SleepNeedSheet(need: MockSleepNeedStates.needWithNap, total: "7h 53m", night: Self.night, editor: editor))
        case "sleep-need-no-breakdown":
            page = AnyView(SleepNeedSheet(need: nil, total: "8h 18m", needMinutes: 498, night: Self.night, editor: editor))
        default:
            page = AnyView(SleepNeedSheet(need: MockSleepNeedStates.need, total: "8h 18m", night: Self.night, editor: editor))
        }
        return AnyView(page
            .previewEnvironment(state)
            .toggleStyle(.ryft)
            .environment(\.locale, Locale(identifier: "en_US")))
    }

    static let night = "Last night · Sun, Nov 15"

    /// Brings the page into its state as the user would: a step up, a save, a refusal.
    func stage(_ w: HostedWindow) async throws {
        switch name {
        case "baseline-changed", "max-hr-changed":
            try #require(w.nodes().first { $0.isAdjustable }).increment()
        case "baseline-saved":
            // c-19b: 7:30 saved. The mock answers with its own account; the draft's (RYFT learned 7:52) goes back in.
            await editor.setSleepBase(450)
            state.user = MockSleepNeedStates.user
        case "baseline-refused":
            api?.failNext = APIError.http(422, "sleep_base_min out of range", requestID: "01JD8K2V9Q7M3X")
            await editor.setSleepBase(465)
        case "baseline-no-answer":
            api?.failNext = APIError.transport(URLError(.timedOut))
            await editor.setSleepBase(465)
            reseed()
        case "baseline-busy":
            api?.failNext = APIError.http(429, "", requestID: "01JD8K2V9Q7M3X", retryAfter: 60)
            await editor.setSleepBase(465)
        case "baseline-server-error":
            api?.failNext = APIError.http(503, "", requestID: "01JD8K2V9Q7M3X")
            await editor.setSleepBase(465)
            reseed()
        case "baseline-offline":
            // Offline nothing is sent: the notice comes at once.
            await editor.setSleepBase(465)
        case "baseline-rescore-failed":
            await editor.setSleepBase(450)
            reseed()
            api?.failure = APIError.http(500, "", requestID: "01JD8K2V9Q7M3X")
            await editor.rescore()
        case "baseline-saving":
            // Two steps up and Save, its answer held: Save busy (its spinner), 8:00 on its way; Close stays on.
            api?.beforePatchMe = { [gate] in await gate.wait() }
            for _ in 0..<2 {
                try #require(w.nodes().first { $0.isAdjustable }).increment()
                try await w.settle()
            }
            try #require(w.nodes().first { $0.identifier == BodySetting.sleepBase.saveIdentifier }).activate()
            try await w.wait("saving", timeout: .seconds(15)) { editor.saving }
        case "sleep-need-saving":
            // A save on its way from the editor, its answer held: the sheet's row says Saving….
            api?.beforePatchMe = { [gate] in await gate.wait() }
            Task { await editor.setSleepBase(480) }
            try await w.wait("saving", timeout: .seconds(15)) { editor.saving }
        case "baseline-rescoring":
            // Accepted, then the network went before the reload: the last word stays "Rescoring — …".
            await editor.setSleepBase(450)
            reseed()
            Task { await editor.rescore() }
            try await w.wait("the delay", timeout: .seconds(15)) { clock.pendingSleeps == 1 }
            state.env.connectivityMonitor.update(false)
            clock.advance(by: SyncService.rescoreDelay)
            try await w.wait("done", timeout: .seconds(15)) { !editor.rescoring }
        case "baseline-rescored":
            await editor.setSleepBase(450)
            reseed()
            await editor.rescore()
            reseed()
        case "baseline-onboarding-saved":
            await editor.setSleepBase(450)
            reseed()
        case "sleep-need-missed-failure":
            // The save's answer came after its editor page went: said under the row.
            api?.failNext = APIError.transport(URLError(.timedOut))
            await editor.setSleepBase(480)
            reseed()
        default:
            break
        }
    }
}
