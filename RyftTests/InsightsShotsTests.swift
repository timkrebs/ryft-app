import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes Insights (design.md §P5-5) as 3x PNGs, whole pages (`PagedWindowShot`), at the default size and at AX3 when
/// `INSIGHTS_SHOTS_DIR` is set; otherwise does nothing. Run it with `TEST_RUNNER_INSIGHTS_SHOTS_DIR=<dir> xcodebuild …
/// -only-testing:RyftTests/InsightsShotsTests test-without-building` and compare the set with the board. Drawn from a real
/// window (`drawHierarchy`); for comparing, not a golden-file test.
@MainActor
@Suite("T5.3: Insights, shots", .serialized)
struct InsightsShotsTests {
    /// One screen per test case (both sizes), so each stays inside the plan's time allowance.
    @Test(arguments: Self.names)
    func writeScreen(_ name: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["INSIGHTS_SHOTS_DIR"],
              let view = await Self.screen(name) else { return }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                       view) { w in
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/insights-\(name)-\(size).png"))
            }
        }
    }

    nonisolated static let names = ["scored", "not-set-up", "only-tile", "no-insights", "loading", "calibrating", "offline",
                                    "not-loaded", "unreachable", "expanded", "7d"]

    /// The screen: "scored" is the live screen on the demo data, its series read first so the shot is the loaded page.
    private static func screen(_ name: String) async -> AnyView? {
        guard name == "scored" else { return screens().first { $0.0 == name }?.1 }
        let state = AppState.preview()
        await InsightsViewModel(state: state).load()
        return AnyView(InsightsView().previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US")))
    }

    /// Name and page: the page's states (`InsightsPreview`) and the not-set-up screen; "scored" is `screen(_:)`'s.
    private static func screens() -> [(String, AnyView)] {
        let english = Locale(identifier: "en_US")
        func page(_ content: InsightsPageContent) -> AnyView {
            AnyView(InsightsPage(content: content, range: .constant(content.boardCards.first.map { range($0.days) } ?? .month),
                                 actions: InsightsPreview.actions)
                .previewEnvironment().environment(\.locale, english))
        }
        return [
            ("not-set-up", AnyView(InsightsView().previewEnvironment(AppState.preview(empty: true)).environment(\.locale, english))),
            ("only-tile", page(InsightsPreview.content(insights: InsightsPreview.onlyTile))),
            ("no-insights", page(InsightsPreview.content(insights: []))),
            ("loading", page(InsightsPreview.content(loading: true))),
            ("calibrating", page(InsightsPreview.content(bands: false))),
            ("offline", page(InsightsPreview.content(offline: true))),
            ("not-loaded", page(InsightsPreview.content(notLoaded: true, offline: true))),
            ("unreachable", page(InsightsPreview.content(issue: InsightsPreview.unreachable))),
            ("expanded", page(InsightsPreview.content(insights: [], expanded: [.readiness, .hrv]))),
            ("7d", page(InsightsPreview.content(range: .week))),
        ]
    }

    private static func range(_ days: Int) -> TrendRange {
        TrendRange.allCases.first { $0.days == days } ?? .month
    }
}
