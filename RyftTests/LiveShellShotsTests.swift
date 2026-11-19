import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// At file scope: a suite's own trait can't name a member of the suite.
private let liveShellShotsDir = ProcessInfo.processInfo.environment["LIVE_SHELL_SHOTS_DIR"]

/// The live workout's shell in the approved Nocturne drafts' states (PR 6 B `b-02`, `b-04` to `b-08`, `b-27`, `b-28`), written as
/// PNGs when `LIVE_SHELL_SHOTS_DIR` is set (`TEST_RUNNER_LIVE_SHELL_SHOTS_DIR` on the command line); otherwise nothing runs.
/// For comparing with the drafts, not a golden-file test. In a real window, as `FocusedSessionShotsTests`: `ImageRenderer`
/// can't draw a pager or a `ScrollView`.
@MainActor
@Suite("Live shell shots", .serialized, .enabled(if: liveShellShotsDir != nil))
struct LiveShellShotsTests {
    enum Screen: String, CaseIterable, Sendable {
        /// `b-04` (390), `b-05` (AX3), `b-28` (320).
        case focused
        /// `b-06`: the keypad on set 2's kg, the rest running.
        case keypad
        /// `b-07`: the rest sheet over the page, running.
        case restSheet = "rest-sheet"
        /// `b-27`: the rest sheet idle, the length changed to 3:00.
        case restSheetIdle = "rest-sheet-idle"
        /// `b-08`: every set done, Barbell row's page.
        case allDone = "all-done"
        /// `b-02`: the List layout, Bench press's set 2 active, a rest running.
        case list
    }

    struct Shot: Sendable, CustomTestStringConvertible {
        let screen: Screen
        let width: CGFloat
        var ax3 = false

        var name: String { "\(screen.rawValue)-\(Int(width))-\(ax3 ? "ax3" : "default")" }
        var testDescription: String { name }
        var height: CGFloat { width < 360 ? 693 : 844 }
    }

    nonisolated static let shots: [Shot] = Screen.allCases.flatMap { screen in
        [Shot(screen: screen, width: 390), Shot(screen: screen, width: 390, ax3: true)]
    } + [Shot(screen: .focused, width: 320), Shot(screen: .focused, width: 320, ax3: true), Shot(screen: .keypad, width: 320),
         Shot(screen: .list, width: 320), Shot(screen: .list, width: 320, ax3: true)]

    @Test("Render and write", arguments: shots)
    func rendersAndWrites(_ shot: Shot) async throws {
        let dir = try #require(liveShellShotsDir)
        let scene = try #require(await Self.windowScene(), "the test host has no window scene")
        let data = try #require(await Self.render(shot, in: scene).pngData())
        try data.write(to: URL(fileURLWithPath: "\(dir)/\(shot.name).png"))
    }

    /// The draft's controller in the screen's state.
    static func controller(_ screen: Screen) -> SessionController {
        switch screen {
        case .list:
            return FocusedPreview.controller(.draftList)
        case .focused, .keypad, .restSheet:
            let c = FocusedPreview.controller(.draft)
            if screen == .keypad, let ex = c.pageExercise { c.edit(ex.orderedSets[1], .kg) }
            return c
        case .restSheetIdle:
            let c = FocusedPreview.controller(.draft)
            c.skipRest()
            return c
        case .allDone:
            let c = FocusedPreview.controller(.draft)
            for ex in c.exercises {
                for set in ex.orderedSets where !set.isCompleted {
                    let ghost = ex.ghost(forSetAt: set.setIndex)
                    set.reps = set.reps ?? ghost.reps ?? 8
                    set.weightKg = set.weightKg ?? ghost.kg
                    set.completedAt = .now
                }
            }
            c.skipRest()
            return c
        }
    }

    private static func windowScene() async -> UIWindowScene? {
        for _ in 0..<100 {
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first { return scene }
            try? await Task.sleep(for: .seconds(0.05))
        }
        return nil
    }

    @ViewBuilder
    private static func sheet(_ screen: Screen, of controller: SessionController) -> some View {
        if let ex = controller.pageExercise {
            RestSheet(controller: controller, exercise: ex, seconds: screen == .restSheetIdle ? 180 : nil)
        }
    }

    private static func render(_ shot: Shot, in scene: UIWindowScene) async -> UIImage {
        let controller = controller(shot.screen)
        let hasSheet = shot.screen == .restSheet || shot.screen == .restSheetIdle
        let typeSize: DynamicTypeSize = shot.ax3 ? .accessibility3 : .large
        let root = SessionView(controller: controller)
            .sheet(isPresented: .constant(hasSheet)) {
                // A sheet is a host of its own: the traits below stop at this one.
                Self.sheet(shot.screen, of: controller).dynamicTypeSize(typeSize)
            }
            .previewEnvironment()
            .environment(\.dynamicTypeSize, typeSize)
        let host = UIHostingController(rootView: root)
        host.traitOverrides.preferredContentSizeCategory = shot.ax3 ? .accessibilityExtraLarge : .large

        let frame = CGRect(x: 0, y: 0, width: shot.width, height: shot.height)
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
            controller.stop()
        }
        // SwiftUI lays out and scrolls the strip to its tile between run-loop turns; a window gives no event to wait for.
        try? await Task.sleep(for: .seconds(hasSheet ? 1.5 : 0.8))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(bounds: frame, format: format).image { _ in
            window.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
    }
}
