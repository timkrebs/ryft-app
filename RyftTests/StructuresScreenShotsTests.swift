import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes the screens that use T5.0-B's changed components (Today, Sleep → Day, Strain, My Day) as 3x PNGs, whole pages
/// (`PagedWindowShot`), at the default size and at AX3 when `STRUCTURES_SCREENS_DIR` is set; otherwise does nothing. Run it
/// before and after a change to a shared component with `TEST_RUNNER_STRUCTURES_SCREENS_DIR=<dir> xcodebuild …
/// -only-testing:RyftTests/StructuresScreenShotsTests test-without-building` and compare the two sets: Today and Sleep → Day
/// must not move (T5.0-B's brief). Drawn from a real window (`drawHierarchy`); for comparing, not a golden-file test.
@MainActor
@Suite("T5.0-B: Today, Sleep, Strain and My Day, shots", .serialized)
struct StructuresScreenShotsTests {
    @Test func writeScreens() async throws {
        guard let dir = ProcessInfo.processInfo.environment["STRUCTURES_SCREENS_DIR"] else { return }
        let english = Locale(identifier: "en_US")
        let screens: [(String, AnyView, CGFloat, CGFloat, String)] = [
            ("today", AnyView(TodayView().previewEnvironment(AppState.preview(flags: [.todayMyDay: true], scenario: .watch))
                .environment(\.locale, english)), 1_900, 2_600, "today.ruler"),
            ("sleep-day", AnyView(SleepPreviewPage(.latest).environment(\.locale, english)), 1_900, 2_600, "sleep.numeral"),
            ("strain", AnyView(StrainView().previewEnvironment().environment(\.locale, english)), 1_500, 2_600, ""),
            ("my-day", AnyView(NavigationStack {
                MyDayPage(content: MockMyDay.content(.pastEmpty), week: MockMyDay.week(daysBack: 3))
            }.previewEnvironment(AppState.preview(flags: [.todayMyDay: true])).environment(\.locale, english)), 844, 1_600, ""),
        ]
        for (name, view, height, ax3Height, ready) in screens {
            for (size, typeSize, category, h) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large, height),
                                                  ("ax3", .accessibility3, .accessibilityExtraLarge, ax3Height)] {
                try await HostedWindow.run(width: 390, height: h, bottomInset: 0, typeSize: typeSize, category: category, view) { w in
                    if !ready.isEmpty {
                        try await w.wait(ready) { w.nodes().contains { $0.identifier == ready } }
                    }
                    try await w.settle()
                    let image = try await PagedWindowShot.image(w)
                    let data = try #require(image.pngData())
                    try data.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
                }
            }
        }
    }
}
