import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// At file scope: a suite's own trait can't name a member of the suite.
private let focusedShotsDir = ProcessInfo.processInfo.environment["FOCUSED_SHOTS_DIR"]

/// Writes the Focused layout's screens from the preview mocks as PNGs when `FOCUSED_SHOTS_DIR` is set; otherwise does
/// nothing. `make focused-shots` runs it. For the design note and ui-validator, not a golden-file test (L9). In a real
/// window, as `ImportScreenshotTests`: `ImageRenderer` can't draw a `TabView` or a `ScrollView`.
@MainActor
@Suite("Focused session shots", .serialized, .enabled(if: focusedShotsDir != nil))
struct FocusedSessionShotsTests {
    enum Screen: String, CaseIterable, Sendable {
        case midSession = "mid-session"
        case tappedRow = "tapped-row"
        case allDone = "all-done"
        case noHistory = "no-history"
        case oneExercise = "one-exercise"
        case superset, warmups
        case warmupsOpen = "warmups-open"
        case bodyweight
        case timeAndDistance = "time-and-distance"
        case keypad, offline, empty
        case many = "twelve-exercises"
        case columnE1RM = "column-e1rm"
        case column10RM = "column-10rm"
        case columnRPE = "column-rpe"
        case columnBodyweight = "column-bodyweight"
        case longNote = "long-note"
        case restRunning = "rest-running"
        case restOver = "rest-over"
        case restKeypad = "rest-keypad"
        case restSheetIdle = "rest-sheet-idle"
        case restSheetChanged = "rest-sheet-changed"
        case restSheetRunning = "rest-sheet-running"
        case restChoices = "rest-choices"

        var scenario: FocusedPreview.Scenario {
            switch self {
            case .midSession, .keypad, .restSheetIdle, .restSheetChanged, .restChoices: .midSession
            case .tappedRow: .tappedRow
            case .allDone: .allDone
            case .noHistory: .oneExercise
            case .oneExercise: .oneExerciseStarted
            case .superset: .superset
            case .warmups: .warmups
            case .warmupsOpen: .warmupsOpen
            case .bodyweight: .bodyweight
            case .timeAndDistance: .timeAndDistance
            case .offline: .offline
            case .empty: .empty
            case .many: .manyExercises
            case .columnE1RM, .column10RM, .columnRPE: .estimates
            case .columnBodyweight: .bodyweightEstimates
            case .longNote: .longNote
            case .restRunning, .restKeypad, .restSheetRunning: .restRunning
            case .restOver: .restOver
            }
        }

        /// The fourth column, as if picked with the header; the other screens have the default rule's.
        var column: SetColumn? {
            switch self {
            case .columnE1RM, .columnBodyweight: .e1rm
            case .column10RM: .tenRM
            case .columnRPE: .rpe
            default: nil
            }
        }

        var hasSheet: Bool {
            switch self {
            case .restSheetIdle, .restSheetChanged, .restSheetRunning, .restChoices: true
            default: false
            }
        }
    }

    enum Size: String, CaseIterable, Sendable {
        case regular = "390"
        case compact = "320"

        var frame: CGRect {
            switch self {
            case .regular: CGRect(x: 0, y: 0, width: 390, height: 844)
            case .compact: CGRect(x: 0, y: 0, width: 320, height: 693)
            }
        }
    }

    enum TextSize: String, CaseIterable, Sendable {
        case standard = "default"
        case xl, ax1, ax3

        var category: UIContentSizeCategory {
            switch self {
            case .standard: .large
            case .xl: .extraLarge
            case .ax1: .accessibilityMedium
            case .ax3: .accessibilityExtraLarge
            }
        }

        var dynamicType: DynamicTypeSize {
            switch self {
            case .standard: .large
            case .xl: .xLarge
            case .ax1: .accessibility1
            case .ax3: .accessibility3
            }
        }
    }

    struct Shot: Sendable, CustomTestStringConvertible {
        let screen: Screen
        let size: Size
        let dark: Bool
        var text: TextSize = .standard

        var name: String { "\(screen.rawValue)-\(size.rawValue)-\(dark ? "dark" : "light")-\(text.rawValue)" }
        /// The fourth column's screens are taller, so last time's card is in the picture with the table above it.
        var frame: CGRect { screen.column == nil ? size.frame : size.frame.insetBy(dx: 0, dy: -150).offsetBy(dx: 0, dy: 150) }
        var testDescription: String { name }
    }

    /// Every screen at both widths in both schemes, and the ones text size changes at the larger sizes: the main one, the
    /// fourth column, RPE's line, the warm-ups, the done header, the pill beside the keypad and the rest sheet, with the
    /// table's two sizes in light too.
    nonisolated static let shots: [Shot] = Screen.allCases.flatMap { screen in
        Size.allCases.flatMap { size in [true, false].map { Shot(screen: screen, size: size, dark: $0) } }
    } + Size.allCases.flatMap { size in
        [Screen.midSession, .columnE1RM, .columnRPE, .warmupsOpen, .allDone, .restRunning, .restKeypad, .restSheetChanged].flatMap { screen in
            [TextSize.xl, .ax1, .ax3].map { Shot(screen: screen, size: size, dark: true, text: $0) }
        }
    } + Size.allCases.flatMap { size in
        [Screen.columnRPE, .warmupsOpen].flatMap { screen in
            [TextSize.ax1, .ax3].map { Shot(screen: screen, size: size, dark: false, text: $0) }
        }
    }

    @Test("Render and write", arguments: shots)
    func rendersAndWrites(_ shot: Shot) async throws {
        let dir = try #require(focusedShotsDir)
        let scene = try #require(await Self.windowScene(), "the test host has no window scene")
        let data = try #require(await Self.render(shot, in: scene).pngData())
        try data.write(to: URL(fileURLWithPath: "\(dir)/\(shot.name).png"))
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
            if screen == .restChoices {
                RestChoicesSheet(controller: controller, exercise: ex)
            } else {
                RestSheet(controller: controller, exercise: ex, seconds: screen == .restSheetChanged ? ex.restSec + 30 : nil)
            }
        }
    }

    private static func render(_ shot: Shot, in scene: UIWindowScene) async -> UIImage {
        let controller = FocusedPreview.controller(shot.screen.scenario, column: shot.screen.column)
        if shot.screen == .keypad || shot.screen == .restKeypad, let ex = controller.pageExercise {
            controller.edit(ex.orderedSets[0], .kg)
        }
        let root = SessionView(controller: controller)
            .sheet(isPresented: .constant(shot.screen.hasSheet)) {
                // A sheet is a host of its own: the traits below stop at this one.
                Self.sheet(shot.screen, of: controller).dynamicTypeSize(shot.text.dynamicType)
            }
            .previewEnvironment(scheme: shot.dark ? .dark : .light)
            .environment(\.dynamicTypeSize, shot.text.dynamicType)
        let host = UIHostingController(rootView: root)
        host.traitOverrides.preferredContentSizeCategory = shot.text.category

        let frame = shot.frame
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = shot.dark ? .dark : .light
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
            controller.stop()
        }
        // SwiftUI lays out and scrolls the strip to its tile between run-loop turns; a window gives no event to wait for.
        try? await Task.sleep(for: .seconds(shot.screen.hasSheet ? 1.5 : 0.6))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(bounds: frame, format: format).image { _ in
            window.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
    }
}
