import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// At file scope: a suite's own trait can't name a member of the suite.
private let listSheetsShotsDir = ProcessInfo.processInfo.environment["LIST_SHEETS_SHOTS_DIR"]

/// The live workout's List layout and the sheets it opens (PR 6 B §4.7, §4.8: `b-02`, `b-03`, `b-24`), written as PNGs when
/// `LIST_SHEETS_SHOTS_DIR` is set (`TEST_RUNNER_LIST_SHEETS_SHOTS_DIR` on the command line); otherwise nothing runs. For
/// comparing with the drafts, not a golden-file test. In a real window, as `LiveShellShotsTests`: a sheet is presented over the
/// List page, so it has the system's sheet edge and grabber.
@MainActor
@Suite("List and session sheets shots", .serialized, .enabled(if: listSheetsShotsDir != nil))
struct ListSheetsShotsTests {
    enum Screen: String, CaseIterable, Sendable {
        /// `b-02` / `b-03`: Bench press's set 2 active, a rest running.
        case list
        /// The rest of List's looks, the whole page: a collapsed exercise, the superset bracket, "Rest over".
        case listStates = "list-states"
        /// `b-24`.
        case addExercise = "add-exercise"
        /// Replace mode: Similar first, the split note, the plan toggle.
        case replace
        case customExercise = "custom-exercise"
        /// The form before a name is typed: the field's label once, an empty field.
        case customExerciseEmpty = "custom-exercise-empty"
        case editTargets = "edit-targets"
        case notes
        case reorder
    }

    struct Shot: Sendable, CustomTestStringConvertible {
        let screen: Screen
        var ax3 = false

        var name: String { "\(screen.rawValue)-390-\(ax3 ? "ax3" : "default")" }
        var testDescription: String { name }
    }

    nonisolated static let shots: [Shot] = Screen.allCases.flatMap { [Shot(screen: $0), Shot(screen: $0, ax3: true)] }

    @Test("Render and write", arguments: shots)
    func rendersAndWrites(_ shot: Shot) async throws {
        let dir = try #require(listSheetsShotsDir)
        let controller = Self.controller(shot.screen)
        defer { controller.stop() }
        let typeSize: DynamicTypeSize = shot.ax3 ? .accessibility3 : .large
        let presents = Self.isSheet(shot.screen)
        let root = SessionView(controller: controller)
            .sheet(isPresented: .constant(presents)) {
                // A sheet is a host of its own: the type size stops at it.
                Self.sheet(shot.screen, of: controller).dynamicTypeSize(typeSize)
            }
        try await HostedWindow.run(width: 390, height: shot.screen == .listStates ? 1_800 : 844, bottomInset: 34,
                                   typeSize: typeSize, category: shot.ax3 ? .accessibilityExtraLarge : .large, root) { w in
            // A sheet slides up between run-loop turns; a window gives no event to wait for.
            try await Task.sleep(for: .seconds(presents ? 1.5 : 0.8))
            let data = try #require(Self.draw(w).pngData())
            try data.write(to: URL(fileURLWithPath: "\(dir)/\(shot.name).png"))
        }
    }

    private static func isSheet(_ screen: Screen) -> Bool {
        screen != .list && screen != .listStates
    }

    /// `b-02`'s session (the previews' own): the plan's Upper A, Bench press's set 1 at 80 × 5, last time 4 × 80 × 5; for the
    /// states, Bench press folded and the rest over.
    static func controller(_ screen: Screen) -> SessionController {
        screen == .listStates ? SessionSheetsPreview.listFolded() : SessionSheetsPreview.listDraft()
    }

    @ViewBuilder
    private static func sheet(_ screen: Screen, of c: SessionController) -> some View {
        let bench = c.exercises[0]
        switch screen {
        case .list, .listStates:
            EmptyView()
        case .addExercise:
            AddExerciseSheet { _ in }
        case .replace:
            AddExerciseSheet(replacing: SessionSheetsPreview.replaceContext()) { _, _ in }
        case .customExercise:
            CustomExerciseForm(name: "Landmine press") { _ in }
        case .customExerciseEmpty:
            CustomExerciseForm(name: "") { _ in }
        case .editTargets:
            EditTargetsSheet(controller: c, exercise: bench)
        case .notes:
            ExerciseNotesSheet(controller: c, exercise: bench)
        case .reorder:
            ReorderSheet(controller: c)
        }
    }

    private static func draw(_ w: HostedWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
            w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
        }
    }
}
