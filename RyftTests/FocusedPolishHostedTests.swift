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
        }
    }

    /// The word whole, in a capsule its own width: a word that wrapped or was cut has a narrower one.
    @Test("Finish keeps its whole word at 320 pt, in English and German", arguments: [
        (compact, "en", "Finish"), (compactAX3, "en", "Finish"), (compact, "de", "Beenden"), (compactAX3, "de", "Beenden"),
    ])
    func finishHoldsItsWord(_ c: (s: SizeCase, language: String, word: String)) async throws {
        let controller = FocusedPreview.controller(.midSession)
        defer { controller.stop() }
        let word = UIHostingController(rootView: Text(verbatim: c.word).font(.ryft(.headline))
            .environment(\.dynamicTypeSize, .large))
        let width = word.sizeThatFits(in: CGSize(width: 400, height: 100)).width
        try await HostedWindow.run(width: c.s.width, height: c.s.height, typeSize: c.s.size, category: c.s.category,
                                   SessionView(controller: controller).environment(\.locale, Locale(identifier: c.language))) { w in
            try await w.settle()
            let finish = try #require(w.node(c.word, exactly: true), "\(w.nodes().map(\.label).prefix(8))")
            #expect(abs(finish.frame.width - (width + 2 * 14)) < 1, "\(finish.frame), the word is \(width)")
            #expect(abs(finish.frame.height - (c.s.size == .large ? 44 : 48)) < 0.5, "\(finish.frame)")
        }
    }

    @Test("An unfilled Finish has an accent outline, and a filled one reads as accent to its edge", arguments: [true, false])
    func finishOutline(dark: Bool) async throws {
        let controller = FocusedPreview.controller(.midSession)
        defer { controller.stop() }
        try await HostedWindow.run(width: 390, height: 844, dark: dark, SessionView(controller: controller)) { w in
            try await w.settle()
            let frame = try #require(w.node("Finish", exactly: true)).frame
            let scheme: ColorScheme = dark ? .dark : .light
            let edge = try #require(w.pixel(at: CGPoint(x: frame.minX + 0.5, y: frame.midY)))
            let inside = try #require(w.pixel(at: CGPoint(x: frame.minX + 4, y: frame.midY)))
            #expect(Self.isClose(edge, to: Theme.accent, scheme), "\(edge)")
            #expect(Self.isClose(inside, to: Theme.surface, scheme), "\(inside)")
        }
    }

    @Test("At all-done the outline goes with the fill")
    func finishFilledHasNoOutline() async throws {
        let controller = FocusedPreview.controller(.allDone)
        defer { controller.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: controller)) { w in
            try await w.settle()
            let frame = try #require(w.node("Finish", exactly: true)).frame
            let inside = try #require(w.pixel(at: CGPoint(x: frame.minX + 4, y: frame.midY)))
            #expect(Self.isClose(inside, to: Theme.accent, .dark), "\(inside)")
        }
    }

    private static func isClose(_ p: (r: Double, g: Double, b: Double), to color: Color, _ scheme: ColorScheme) -> Bool {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let c = color.resolve(in: environment)
        return abs(p.r - Double(c.red)) < 0.06 && abs(p.g - Double(c.green)) < 0.06 && abs(p.b - Double(c.blue)) < 0.06
    }

    /// Node.activate(), VoiceOver's double tap. The menu lists plates here; the tap on it is a UI test's, because a menu runs an
    /// item only from a real touch.
    @Test("The title opens history and the … menu lists plates")
    func titleAndMenuReachTheirActions() async throws {
        let controller = FocusedPreview.controller(.midSession)
        defer { controller.stop() }
        var history: [UUID] = []
        let actions = SessionActions(addExercise: {}, reorder: {}, plates: { _ in }, history: { history.append($0.id) },
                                     userScrolled: {}, finish: {})
        try await HostedWindow.run(width: 390, height: 844, FocusedSessionView(controller: controller, actions: actions)) { w in
            try await w.settle()
            let page = try #require(controller.pageExercise)
            #expect(page.kind == .barbell)
            #expect(try #require(w.node("\(page.name), history", exactly: true)).activate())
            #expect(history == [page.id])
            #expect(try #require(w.node("Options for \(page.name)", exactly: true)).activate())
            try await w.wait("the menu lists plates") { w.menuItem("Plate calculator") != nil }
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
            #expect(abs(try #require(w.node("Set 2 of")).frame.height - (64 + 44)) < 0.5, "a done row's line sits against it")
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

    /// A session can come back with its keypad open: there is no width yet when the keypad first lays out.
    @Test("A keypad open before the first layout keeps its page at 320 pt and AX3")
    func keypadBeforeLayout() async throws {
        let c = FocusedPreview.controller(.restRunning)
        defer { c.stop() }
        let page = try #require(c.pageExercise)
        c.edit(page.orderedSets[1], .kg)
        try await HostedWindow.run(width: 320, height: 693, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   SessionView(controller: c)) { w in
            try await w.settle()
            #expect(c.focus != nil, "the keypad stays up")
            #expect(c.pageExerciseID == page.id, "the pager kept its page")
            #expect(w.node("Current value") != nil)
        }
    }

    @Test("With the keypad and a rest, the page holds the row being edited, whole", arguments: [compact, compactAX3, regularAX3])
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
