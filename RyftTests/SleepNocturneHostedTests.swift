import SwiftUI
import Testing
import UIKit
@testable import Ryft

// Sleep → Day in a window (docs/work/2026-11-16-nocturne/design.md §P4-11 tests 1 and 36, Sleep's half; 48–49 for
// Sleep): the board's gaps measured on the VoiceOver frames, the identifiers the UI tests use, the reading order, the
// disabled night buttons, and AX3. With `PR4_SHOTS_DIR` set it also writes every preview state at 3x.

@MainActor
@Suite(.serialized) struct SleepNocturneHostedTests {
    /// The board's width: 350 of content between the 20 pt insets.
    nonisolated private static let width: CGFloat = 390

    private func host(_ night: SleepPreviewScene.Night, width: CGFloat = width, height: CGFloat = 2000,
                      ax3: Bool = false, body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: width, height: height, bottomInset: 0,
                                   typeSize: ax3 ? .accessibility3 : .large,
                                   category: ax3 ? .accessibilityExtraLarge : .large,
                                   SleepPreviewPage(night)) { w in
            try await w.wait("Sleep's tiles") { w.nodes().contains { $0.identifier == "sleep.tile.restorative" } }
            try await w.settle()
            try await body(w)
        }
    }

    private func frame(_ w: HostedWindow, _ identifier: String) throws -> CGRect {
        try #require(w.nodes().first { $0.identifier == identifier }, "\(identifier) on screen").frame
    }

    // MARK: 36. Identifiers

    @Test func identifiersOnTheBoardNight() async throws {
        try await host(.latest) { w in
            let ids = Set(w.nodes().compactMap(\.identifier))
            for id in ["sleep.header.previous", "sleep.header.next", "sleep.numeral", "sleep.ruler", "sleep.hypnogram",
                       "sleep.tile.consistency", "sleep.tile.debt", "sleep.tile.efficiency", "sleep.tile.restorative",
                       "sleep.need"] {
                #expect(ids.contains(id), "\(id)")
            }
        }
    }

    // MARK: 1. The board's gaps

    @Test func theBoardsGapsAtTheDefaultSize() async throws {
        try await host(.latest) { w in
            let numeral = try frame(w, "sleep.numeral")
            #expect(abs(numeral.width - 125) < 0.5 && abs(numeral.height - 47) < 0.5, "numeral \(numeral.size)")
            #expect(abs(numeral.midX - Self.width / 2) < 0.5)
            let caption = try #require(w.node("94 percent of your need")?.frame)
            #expect(abs(caption.minY - numeral.maxY - SleepLayout.captionGap) < 1, "numeral→caption \(caption.minY - numeral.maxY)")
            let ruler = try frame(w, "sleep.ruler")
            #expect(abs(ruler.minY - caption.maxY - SleepLayout.rulerGap) < 1, "caption→ruler \(ruler.minY - caption.maxY)")
            // The ruler's element reaches 2/3 pt past the column on each side (its end ticks' half stroke, T4.0).
            #expect(abs(ruler.midX - Self.width / 2) < 0.5 && abs(ruler.width - 350) < 1.5, "ruler \(ruler)")
            let hypnogram = try frame(w, "sleep.hypnogram")
            // From the ruler's 36 pt box, which its labels overflow (VF1); the element's frame takes the labels in.
            #expect(abs(hypnogram.minY - ruler.minY - RulerScale.Size.regular.height - SleepLayout.hypnogramGap) < 1,
                    "ruler→tile \(hypnogram.minY - ruler.minY)")
            #expect(abs(hypnogram.height - 168) < 0.5 && abs(hypnogram.width - 350) < 0.5, "hypnogram \(hypnogram.size)")
            let tiles = try ["consistency", "debt", "efficiency", "restorative"].map { try frame(w, "sleep.tile.\($0)") }
            #expect(abs(tiles[0].minY - hypnogram.maxY - SleepLayout.tilesGap) < 0.5, "tile→grid \(tiles[0].minY - hypnogram.maxY)")
            for tile in tiles {
                #expect(abs(tile.height - SleepLayout.tileHeight) < 0.5 && abs(tile.width - 169) < 0.5, "tile \(tile.size)")
            }
            #expect(abs(tiles[1].minX - tiles[0].maxX - SleepLayout.tileGap) < 0.5)
            #expect(abs(tiles[2].minY - tiles[0].maxY - SleepLayout.tileGap) < 0.5)
            #expect(abs(tiles[3].minY - tiles[1].maxY - SleepLayout.tileGap) < 0.5)
        }
    }

    // MARK: 48. VoiceOver

    @Test func readingOrderAndHeader() async throws {
        try await host(.latest) { w in
            let nodes = w.nodes()
            let ids = nodes.map(\.identifier)
            func index(_ id: String) -> Int { ids.firstIndex(of: id) ?? -1 }
            let title = try #require(nodes.firstIndex { $0.label == "Sleep" && $0.traits.contains(.header) })
            #expect(nodes[title].value?.hasPrefix("Last night, ") == true)
            let order = [index("sleep.header.previous"), title, index("sleep.header.next"), index("sleep.numeral"),
                         index("sleep.ruler"), index("sleep.hypnogram"), index("sleep.tile.consistency"),
                         index("sleep.tile.debt"), index("sleep.tile.efficiency"), index("sleep.tile.restorative"),
                         index("sleep.need")]
            #expect(!order.contains(-1) && order == order.sorted(), "\(order)")
            // One element each: the hypnogram and a tile are not read part by part.
            #expect(!nodes.contains { $0.label.hasPrefix("Deep 1:35") })
            #expect(nodes.first { $0.identifier == "sleep.tile.debt" }?.label == "Sleep debt")
        }
    }

    @Test func theNightButtonsAtTheEnds() async throws {
        try await host(.latest) { w in
            let next = try #require(w.nodes().first { $0.identifier == "sleep.header.next" })
            let previous = try #require(w.nodes().first { $0.identifier == "sleep.header.previous" })
            #expect(!next.isEnabled && next.label == "Next night")
            #expect(previous.isEnabled && previous.label == "Previous night")
        }
        try await host(.oldest) { w in
            let previous = try #require(w.nodes().first { $0.identifier == "sleep.header.previous" })
            let next = try #require(w.nodes().first { $0.identifier == "sleep.header.next" })
            #expect(!previous.isEnabled && previous.label == "Previous night")
            #expect(next.isEnabled)
        }
    }

    @Test func loadingSaysSo() async throws {
        try await HostedWindow.run(width: Self.width, height: 1400, bottomInset: 0, SleepPreviewPage(.loading)) { w in
            try await w.wait("the numeral") { w.nodes().contains { $0.identifier == "sleep.numeral" } }
            #expect(w.nodes().first { $0.identifier == "sleep.numeral" }?.label == "Loading this night")
            #expect(!w.nodes().contains { $0.identifier == "sleep.hypnogram" })
        }
    }

    // MARK: 49. AX3

    @Test func ax3StacksAndClipsNothing() async throws {
        try await host(.latest, height: 6000, ax3: true) { w in
            for node in w.nodes() {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= Self.width + 0.5, "\(node.label) \(node.frame)")
            }
            let tiles = try ["consistency", "debt"].map { try frame(w, "sleep.tile.\($0)") }
            #expect(abs(tiles[0].minX - tiles[1].minX) < 0.5 && tiles[1].minY > tiles[0].maxY, "one column")
            #expect(abs(tiles[0].width - 350) < 0.5)
            #expect(w.nodes().contains { $0.identifier == "sleep.mode" }, "the picker is a menu")
        }
    }

    // MARK: shots

    /// Every state at 402 wide (iPhone 17 Pro), 3x, at the default size and AX3, into `PR4_SHOTS_DIR`.
    @Test func writeShots() async throws {
        guard let dir = ProcessInfo.processInfo.environment["PR4_SHOTS_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for night in SleepPreviewScene.Night.allCases {
            for ax3 in [false, true] {
                // 3x stays under the renderer's 8192 px: AX3 shows the board and the need card.
                try await HostedWindow.run(width: 402, height: ax3 ? 2700 : 1900, bottomInset: 0,
                                           typeSize: ax3 ? .accessibility3 : .large,
                                           category: ax3 ? .accessibilityExtraLarge : .large,
                                           SleepPreviewPage(night)) { w in
                    try await w.wait("Sleep's tiles") { w.nodes().contains { $0.identifier == "sleep.tile.restorative" } }
                    try await w.settle()
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 3
                    format.opaque = true
                    let image = UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
                        w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
                    }
                    let name = "hosted-\(night.rawValue)-\(ax3 ? "ax3" : "default").png"
                    try image.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
                    // The measured frames, for the comparison with the board.
                    let lines = w.nodes().filter { $0.identifier?.hasPrefix("sleep.") == true }
                        .map { "\($0.identifier ?? "") \($0.frame)" }
                    try lines.joined(separator: "\n").write(toFile: "\(dir)/\(name).frames.txt", atomically: true, encoding: .utf8)
                }
            }
        }
    }
}
