import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// PR 2's screens as the app draws them (dark, default and AX5), as PNGs, when `FIRST_RUN_SHOTS_DIR` is set; otherwise does
/// nothing: `TEST_RUNNER_FIRST_RUN_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/FirstRunPR2ShotsTests test-without-building`.
/// Mock data only. Light shots are moot (ADR 0016: one-value colour assets).
@MainActor
@Suite("First run PR 2 shots", .serialized)
struct FirstRunPR2ShotsTests {
    nonisolated static let screens = ["health", "notifications", "wear", "tracker-setup", "today-first-import", "splash"]
    nonisolated static let sizes = ["default", "ax5"]

    @Test(arguments: screens, sizes)
    func write(_ screen: String, _ size: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["FIRST_RUN_SHOTS_DIR"] else { return }
        let ax5 = size == "ax5"
        let clock = TestClock()
        let view = Self.view(screen, clock: clock)
            .environment(\.locale, Locale(identifier: "en_US"))
            .preferredColorScheme(.dark)
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: ax5 ? .accessibility5 : .large,
                                   category: ax5 ? .accessibilityExtraExtraExtraLarge : .large, view) { w in
            if screen == "splash" {
                // The first run's slow caption, at 5 s.
                try await w.wait("the wait") { clock.pendingSleeps == 1 }
                clock.advance(by: .seconds(1))
                try await w.wait("the next wait") { clock.pendingSleeps == 1 }
                clock.advance(by: .seconds(4))
            }
            try await w.settle()
            let image = screen == "splash" ? Self.window(w) : try await PagedWindowShot.image(w)
            try #require(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/pr2-\(screen)-\(size).png"))
        }
    }

    private static func view(_ screen: String, clock: TestClock) -> AnyView {
        switch screen {
        case "health":
            return AnyView(HealthPermissionView(progress: FirstRunProgress(step: 5, count: 7))
                .environment(Settings.shared).environment(\.appEnvironment, .preview()))
        case "notifications":
            let env = AppEnvironment.preview()
            return AnyView(NotificationPrimerStep(model: NotificationPrimerModel(push: PushRegistrar(env: env), analytics: env.analytics),
                                                  example: .morningScore, progress: FirstRunProgress(step: 6, count: 7))
                .environment(\.appEnvironment, env))
        case "wear", "tracker-setup":
            let state = AppState.preview()
            let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
            model.devices.stage(["garmin"])
            let view: AnyView = screen == "wear"
                ? AnyView(TrackerPickerView(model: model, picked: ["garmin"], progress: FirstRunProgress(step: 4, count: 7)))
                : AnyView(TrackerSetupStepView(model: model, progress: FirstRunProgress(step: 7, count: 7)))
            return AnyView(view.previewEnvironment(state))
        case "today-first-import":
            return AnyView(TodayView().previewEnvironment(.preview(scenario: .importing)))
        default:
            return AnyView(SplashView(firstRun: true).environment(\.appEnvironment, .test(clock: clock)))
        }
    }

    /// The window as it is, at 2x.
    private static func window(_ w: HostedWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
            w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
        }
    }
}
