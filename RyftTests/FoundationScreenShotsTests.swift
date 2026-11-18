import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes the screens that use T6.0's restyled-in-place components (`Card`, `InlineMessage`, `CheckRow`, `NumberedStep`,
/// `TrackerSetupCard`, `SelectableTile`, `CapabilityRow`) as 3x PNGs, whole pages (`PagedWindowShot`), at the default size and
/// at AX3 when `FOUNDATION_SCREENS_DIR` is set; otherwise does nothing. Run it before and after a change to one of them with
/// `TEST_RUNNER_FOUNDATION_SCREENS_DIR=<dir> xcodebuild … -only-testing:RyftTests/FoundationScreenShotsTests
/// test-without-building` and compare the two sets. Drawn from a real window (`drawHierarchy`); for comparing, not a
/// golden-file test.
@MainActor
@Suite("T6.0: screens with the restyled cards, notices and setup rows, shots", .serialized)
struct FoundationScreenShotsTests {
    @Test func writeScreens() async throws {
        guard let dir = ProcessInfo.processInfo.environment["FOUNDATION_SCREENS_DIR"] else { return }
        let english = Locale(identifier: "en_US")
        for (name, view, ready) in Self.screens(english) {
            for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                               ("ax3", .accessibility3, .accessibilityExtraLarge)] {
                try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                           view) { w in
                    if !ready.isEmpty {
                        try await w.wait(ready) { w.nodes().contains { $0.label.hasPrefix(ready) } }
                    }
                    try await w.settle()
                    let image = try await PagedWindowShot.image(w)
                    let data = try #require(image.pngData())
                    try data.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
                }
            }
        }
    }

    /// Name, page, and a label prefix to wait for (empty: settle only).
    private static func screens(_ locale: Locale) -> [(String, AnyView, String)] {
        let check = SyncCheckScenario.garmin
        let checkModel = TrackerCheckModel(env: AppEnvironment.preview(), health: check.store(now: .now), trackers: check.trackers)
        let setupState = AppState.preview()
        let setup = OnboardingCoordinator(state: setupState, apiStatus: APIStatus()) {}
        setup.devices.stage(["garmin"])
        let wearState = AppState.preview()
        let wear = OnboardingCoordinator(state: wearState, apiStatus: APIStatus()) {}
        let reportState = AppState.preview()
        let report = ReportProblemModel(env: reportState.env, apiStatus: APIStatus()) { FeedbackSync() }
        report.stage(message: "Today said calibrating after a full week of nights.", result: .rateLimited)
        return [
            ("today-not-set-up", AnyView(TodayView().previewEnvironment(AppState.preview(empty: true)).environment(\.locale, locale)),
             "Connect RYFT"),
            ("today-night-gap", AnyView(TodayView().previewEnvironment(AppState.preview(scenario: .nightGap))
                .environment(\.locale, locale)), ""),
            ("strain", AnyView(StrainView().previewEnvironment().environment(\.locale, locale)), ""),
            ("check-sync", AnyView(NavigationStack { TrackerCheckView(model: checkModel) }.previewEnvironment()
                .environment(\.locale, locale)), ""),
            ("tracker-setup", AnyView(TrackerSetupStepView(model: setup, checkOpen: false).previewEnvironment(setupState)
                .environment(\.locale, locale)), ""),
            ("wear", AnyView(TrackerPickerView(model: wear, picked: ["garmin", "oura"]).previewEnvironment(wearState)
                .environment(\.locale, locale)), ""),
            ("report-limited", AnyView(NavigationStack { ReportProblemView(model: report) }.previewEnvironment(reportState)
                .environment(\.locale, locale)), ""),
        ]
    }
}
