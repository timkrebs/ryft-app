import SwiftUI
import Testing
@testable import Ryft

/// T5 in real windows, at the sizes that matter (design.md §5.1), read through the accessibility tree: frames in screen
/// points, as VoiceOver gets them. Synthetic values only.
@MainActor
@Suite("Focused polish, hosted", .serialized)
struct FocusedPolishHostedTests {
    struct SizeCase: Sendable, CustomTestStringConvertible {
        let width: CGFloat, height: CGFloat
        let size: DynamicTypeSize
        let category: UIContentSizeCategory
        var testDescription: String { "\(Int(width)) pt, \(size)" }

        var columns: SetTableColumns { .fitting(width: width, typeSize: size) }
    }

    nonisolated static let regularAX1 = SizeCase(width: 390, height: 844, size: .accessibility1, category: .accessibilityMedium)
    nonisolated static let compactAX1 = SizeCase(width: 320, height: 693, size: .accessibility1, category: .accessibilityMedium)
    nonisolated static let regularAX3 = SizeCase(width: 390, height: 844, size: .accessibility3, category: .accessibilityExtraLarge)
    nonisolated static let compactAX3 = SizeCase(width: 320, height: 693, size: .accessibility3, category: .accessibilityExtraLarge)
    nonisolated static let regularXXXL = SizeCase(width: 390, height: 844, size: .xxxLarge, category: .extraExtraExtraLarge)
    nonisolated static let compactXXXL = SizeCase(width: 320, height: 693, size: .xxxLarge, category: .extraExtraExtraLarge)
    nonisolated static let regular = SizeCase(width: 390, height: 844, size: .large, category: .large)
    nonisolated static let compact = SizeCase(width: 320, height: 693, size: .large, category: .large)

    private func header(_ w: HostedWindow) -> HostedWindow.Node? { w.node("Table column", exactly: true) }

    @Test("The fourth column's button goes at 320 from AX1 and everywhere from AX3",
          arguments: [regularXXXL, compactXXXL, regularAX1, compactAX1, regularAX3, compactAX3])
    func theColumnDrops(_ s: SizeCase) async throws {
        let c = FocusedPreview.controller(.estimates, column: .e1rm)
        defer { c.stop() }
        try await HostedWindow.run(width: s.width, height: s.height, typeSize: s.size, category: s.category, SessionView(controller: c)) { w in
            try await w.settle()
            #expect((header(w) != nil) == s.columns.hasFourth)
        }
    }

    @Test("Finish is one line: 44 at 320, 48 elsewhere and at AX3 everywhere", arguments: [
        (regular, 48 as CGFloat), (compact, 44), (regularAX3, 48), (compactAX3, 48),
    ])
    func finishHoldsItsLine(_ c: (s: SizeCase, height: CGFloat)) async throws {
        let controller = FocusedPreview.controller(.midSession)
        defer { controller.stop() }
        try await HostedWindow.run(width: c.s.width, height: c.s.height, typeSize: c.s.size, category: c.s.category,
                                   SessionView(controller: controller)) { w in
            try await w.settle()
            let finish = try #require(w.node("Finish", exactly: true))
            #expect(abs(finish.frame.height - c.height) < 0.5, "\(finish.frame)")
            #expect(finish.frame.maxX <= c.s.width, "\(finish.frame)")
            #expect(finish.frame.width > 60, "a word's width, not a syllable's: \(finish.frame)")
        }
    }

    @Test("A row is 64 high at AX3, and one with an RPE adds its 44 pt line")
    func theRPELineTakesItsRoom() async throws {
        let c = FocusedPreview.controller(.estimates, column: .rpe)
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 1600, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   SessionView(controller: c)) { w in
            try await w.settle()
            // Sets 1 and 2 are done, the second at RPE 8.5, and the third is active.
            #expect(abs(try #require(w.node("Set 1 of")).frame.height - 64) < 0.5)
            #expect(abs(try #require(w.node("Set 2 of")).frame.height - (64 + 4 + 44)) < 0.5)
            #expect(abs(try #require(w.node("Set 3 of")).frame.height - (64 + 4 + 44)) < 0.5, "the active row is the way in")
            #expect(abs(try #require(w.node("Set 4 of")).frame.height - 64) < 0.5)
        }
    }

    @Test("At the default size a row stays 56 and the header stays")
    func theDefaultRowHolds() async throws {
        let c = FocusedPreview.controller(.estimates, column: .rpe)
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 1400, SessionView(controller: c)) { w in
            try await w.settle()
            #expect(abs(try #require(w.node("Set 2 of")).frame.height - 56) < 0.5)
            #expect(header(w) != nil)
        }
    }

    @Test("Last time's rows are 44 high from AX1, as the card's height says")
    func lastTimeRows() async throws {
        func cardHeight(_ s: SizeCase) async throws -> CGFloat {
            let c = FocusedPreview.controller(.estimates, column: .e1rm)
            defer { c.stop() }
            var height: CGFloat = 0
            try await HostedWindow.run(width: s.width, height: 1800, typeSize: s.size, category: s.category, SessionView(controller: c)) { w in
                try await w.settle()
                height = try #require(w.node("Last time")).frame.height
            }
            return height
        }
        let small = try await cardHeight(Self.regularXXXL), large = try await cardHeight(Self.regularAX1)
        // Four rows, 8 pt each. The header and heading are capped at XXXL, so nothing else moves between these two sizes.
        #expect(abs((large - small) - 4 * 8) < 1, "\(small) to \(large)")
    }

    @Test("Scrolled to its end at 320 pt and AX3, the page clears the pill: the card ends above it")
    func thePillCoversNothing() async throws {
        let c = FocusedPreview.controller(.estimates, column: .e1rm)
        defer { c.stop() }
        try await HostedWindow.run(width: 320, height: 693, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   SessionView(controller: c)) { w in
            try await w.settle()
            let scroll = try #require(w.pageScrollView())
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
            try await w.settle()
            let card = try #require(w.node("Last time")).frame
            let pill = try #require(w.node("Rest", exactly: true)).frame
            let viewport = try #require(w.pageViewport())
            #expect(card.maxY <= viewport.maxY, "\(card) in \(viewport)")
            #expect(card.maxY <= pill.minY, "\(card) above \(pill)")
        }
    }

    @Test("At 320 pt with the keypad and a rest, the page holds the row being edited, whole", arguments: [compact, compactAX3])
    func keypadAndRest(_ s: SizeCase) async throws {
        let c = FocusedPreview.controller(.restRunning)
        defer { c.stop() }
        try await HostedWindow.run(width: s.width, height: s.height, typeSize: s.size, category: s.category, SessionView(controller: c)) { w in
            try await w.settle()
            c.edit(try #require(c.pageExercise).orderedSets[1], .kg)
            try await w.wait("the keypad") { w.node("Current value") != nil }
            try await w.settle()
            let viewport = try #require(w.pageViewport(), "the page is at least 90 pt: \(w.nodes().map(\.frame.minY))")
            let row = try #require(w.node("Set 2 of")).frame
            #expect(row.minY >= viewport.minY - 0.5 && row.maxY <= viewport.maxY + 0.5, "\(row) in \(viewport)")
        }
    }

    @Test("The tiles are 56, and 64 at AX3", arguments: [(regular, 56 as CGFloat), (regularAX3, 64)])
    func tiles(_ c: (s: SizeCase, tile: CGFloat)) async throws {
        let controller = FocusedPreview.controller(.midSession)
        defer { controller.stop() }
        try await HostedWindow.run(width: c.s.width, height: c.s.height, typeSize: c.s.size, category: c.s.category,
                                   SessionView(controller: controller)) { w in
            try await w.settle()
            for frame in try [#require(w.node("Add exercise")).frame, #require(w.node("\(controller.exercises[0].name), ")).frame] {
                #expect(abs(frame.width - c.tile) < 0.5 && abs(frame.height - c.tile) < 0.5, "\(frame)")
            }
        }
    }
}
