import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The tab host on Today at the scroll top (`RootTabs` on mock data), at 402 × 874 and 390 × 844 with a 34 pt home-indicator
/// inset, at the default size and at AX3, as 3x PNGs, when `TAB_BAR_SHOTS_DIR` is set; otherwise does nothing. For comparing
/// with the approved drafts (`tab-bar-today.png`, `tab-bar-today-390.png`, design.md §P5-13), not a golden-file test. Run it
/// with `TEST_RUNNER_TAB_BAR_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/RyftTabBarShotsTests test-without-building`.
@MainActor
@Suite("RyftTabBar: shots", .serialized)
struct RyftTabBarShotsTests {
    private static let sizes: [(String, DynamicTypeSize, UIContentSizeCategory)] = [
        ("default", .large, .large), ("ax3", .accessibility3, .accessibilityExtraLarge),
    ]
    private static let screens: [(width: CGFloat, height: CGFloat)] = [(402, 874), (390, 844)]

    @Test func writeToday() async throws {
        guard let dir = ProcessInfo.processInfo.environment["TAB_BAR_SHOTS_DIR"] else { return }
        for screen in Self.screens {
            for (name, typeSize, category) in Self.sizes {
                let page = RootTabs().previewEnvironment().environment(\.locale, Locale(identifier: "en_US"))
                try await HostedWindow.run(width: screen.width, height: screen.height, bottomInset: 0, typeSize: typeSize,
                                           category: category, page) { w in
                    // The home-indicator inset of the phones drawn: 34, whatever the simulator's window gets.
                    w.host.additionalSafeAreaInsets.bottom = max(0, 34 - w.window.safeAreaInsets.bottom)
                    try await w.wait("Today and the bar") {
                        w.nodes().contains { $0.identifier == "today.ruler" } && w.nodes().contains { $0.identifier == "tab.today" }
                    }
                    try await w.settle()
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 3
                    format.opaque = true
                    let image = UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
                        w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
                    }
                    let file = "\(dir)/today-\(Int(screen.width))-\(name).png"
                    try #require(image.pngData()).write(to: URL(fileURLWithPath: file))
                    let inset = w.host.view.safeAreaInsets
                    try "\(file): safe area top \(inset.top), bottom \(inset.bottom)\n"
                        .write(toFile: "\(dir)/today-\(Int(screen.width))-\(name).txt", atomically: true, encoding: .utf8)
                }
            }
        }
    }
}
