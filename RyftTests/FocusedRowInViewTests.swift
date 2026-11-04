import SwiftUI
import Testing
@testable import Ryft

/// `ExercisePage.keepRowInView` (review N6b): the active row must end whole in the page's viewport, above the pill row, the
/// toast and the keypad. Real views in a window, real frames from the accessibility tree (`HostedWindow`); no model of the
/// layout. Without the scroll, set 7 of 8 at 390 pt ended 39 pt below the page and the keypad's first scroll ran on the old
/// height. Waits are on the layout settling, not on a fixed time. Page: "Barbell row", 4 sets, 4 more added = 8.
@MainActor
@Suite("Focused: the active row stays in view", .serialized)
struct FocusedRowInViewTests {
    enum Phone: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case regular = "390 x 844", compact = "320 x 693"
        var size: CGSize { self == .regular ? CGSize(width: 390, height: 844) : CGSize(width: 320, height: 693) }
        var testDescription: String { rawValue }
    }

    private let tolerance: CGFloat = 1

    private func controller(sets: Int = 8, done: Int = 0, rest running: Bool = false) -> SessionController {
        let c = FocusedPreview.controller(.midSession)
        guard let ex = c.pageExercise else { fatalError("the scenario has a page") }
        while ex.sets.count < sets { c.addSet(to: ex) }
        for set in ex.orderedSets.prefix(done) {
            set.reps = 8
            set.weightKg = 60
            set.completedAt = .now
        }
        if running { c.startRest(for: ex, seconds: 300) }
        return c
    }

    private func check(_ c: SessionController) throws {
        let ex = try #require(c.pageExercise)
        c.toggleCheck(try #require(c.activeSet(in: ex)), in: ex)
    }

    /// The row "Set `n` of `total`", whole inside the viewport and clear of the pill row (when there is one).
    private func expectWhole(_ n: Int, of total: Int, in w: HostedWindow, _ context: String,
                             sourceLocation: SourceLocation = #_sourceLocation) throws {
        let row = try #require(w.node("Set \(n) of \(total)"), "\(context): no row \(n)", sourceLocation: sourceLocation)
        let viewport = try #require(w.pageViewport(), "\(context): no page", sourceLocation: sourceLocation)
        #expect(row.frame.minY >= viewport.minY - tolerance,
                "\(context): set \(n) starts \(viewport.minY - row.frame.minY) pt above the page", sourceLocation: sourceLocation)
        #expect(row.frame.maxY <= viewport.maxY + tolerance,
                "\(context): set \(n) ends \(row.frame.maxY - viewport.maxY) pt below the page", sourceLocation: sourceLocation)
        if let pill = w.node("Rest", exactly: true) {
            #expect(row.frame.maxY <= pill.frame.minY + tolerance,
                    "\(context): set \(n) is under the pill by \(row.frame.maxY - pill.frame.minY) pt", sourceLocation: sourceLocation)
        }
    }

    // MARK: a check moves the active row

    @Test("Every ✓ leaves the next set whole above the pill row: set 2 to 8", arguments: Phone.allCases)
    func checksKeepTheNextSetInView(_ phone: Phone) async throws {
        let c = controller()
        defer { c.stop() }
        try await HostedWindow.run(width: phone.size.width, height: phone.size.height, SessionView(controller: c)) { w in
            try await w.settle()
            for n in 1...7 {
                try check(c)
                try await w.settle()
                try expectWhole(n + 1, of: 8, in: w, "\(phone.rawValue), after check \(n)")
            }
        }
    }

    @Test("A row that already shows whole doesn't move, a hidden one moves by the least")
    func leastScroll() async throws {
        let c = controller()
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
            try await w.settle()
            let scroll = try #require(w.pageScrollView())
            let start = scroll.contentOffset.y
            for n in 1...5 {
                try check(c)
                try await w.settle()
                #expect(abs(scroll.contentOffset.y - start) < 0.5, "set \(n + 1) shows whole: the page stays (offset \(scroll.contentOffset.y))")
            }
            // Set 7 ends 39 pt below the page: it comes in flush with the bottom edge and no further.
            try check(c)
            try await w.settle()
            let viewport = try #require(w.pageViewport())
            let row = try #require(w.node("Set 7 of 8"))
            #expect(scroll.contentOffset.y > start + 20, "set 7 was hidden: the page scrolled (offset \(scroll.contentOffset.y))")
            #expect(abs(row.frame.maxY - viewport.maxY) <= 2, "flush with the bottom edge, not centred: \(row.frame.maxY - viewport.maxY) pt off")
        }
    }

    @Test("A page that opens on set 6 of 8 shows it whole", arguments: Phone.allCases)
    func pageOpensOnALaterSet(_ phone: Phone) async throws {
        let c = controller(done: 5)
        defer { c.stop() }
        try await HostedWindow.run(width: phone.size.width, height: phone.size.height, SessionView(controller: c)) { w in
            try await w.settle()
            try expectWhole(6, of: 8, in: w, "\(phone.rawValue), opened on set 6")
        }
    }

    @Test("A toast that takes room from the page doesn't push the active row under it")
    func toastShrinksThePage() async throws {
        let c = controller()
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
            try await w.settle()
            for _ in 1...5 { try check(c) }
            try await w.settle()
            try expectWhole(6, of: 8, in: w, "before the toast")
            let before = try #require(w.pageViewport())
            c.notice = SessionNotice(message: "Synthetic notice")
            try await w.wait("the toast") { (w.pageViewport()?.height ?? before.height) < before.height - 20 }
            try await w.settle()
            try expectWhole(6, of: 8, in: w, "with the toast up")
        }
    }

    // MARK: the keypad

    struct KeypadCase: Sendable, CustomTestStringConvertible {
        let phone: Phone
        let resting: Bool
        /// The set the keypad opens on, from 0.
        let index: Int
        var testDescription: String { "\(phone.rawValue), \(resting ? "resting" : "idle"), set \(index + 1)" }
    }

    nonisolated static let keypadCases = Phone.allCases.flatMap { phone in
        [false, true].flatMap { resting in [0, 3, 7].map { KeypadCase(phone: phone, resting: resting, index: $0) } }
    }

    @Test("The keypad opening keeps its row in the page that is left, idle or resting", arguments: keypadCases)
    func keypadKeepsItsRowInView(_ k: KeypadCase) async throws {
        let (phone, resting, index) = (k.phone, k.resting, k.index)
        let c = controller(rest: resting)
        defer { c.stop() }
        let ex = try #require(c.pageExercise)
        try await HostedWindow.run(width: phone.size.width, height: phone.size.height, SessionView(controller: c)) { w in
            try await w.settle()
            let full = try #require(w.pageViewport())
            c.edit(ex.orderedSets[index], .kg)
            try await w.wait("the keypad") { w.node("Current value") != nil }
            try await w.settle()
            let shrunk = try #require(w.pageViewport())
            #expect(shrunk.height < full.height, "the keypad took room from the page")
            try expectWhole(index + 1, of: 8, in: w, "\(phone.rawValue), keypad on set \(index + 1), \(resting ? "resting" : "idle")")
        }
    }
}
