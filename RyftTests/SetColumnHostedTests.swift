import SwiftUI
import Testing
@testable import Ryft

/// The fourth column's header as a real view in a window: VoiceOver's double tap on it, read back through the accessibility
/// tree, with the table and the last-time card following. The cell's own tap can't go this way: a row's children are hidden
/// from the tree, so `FocusedSessionUITests` covers it with a touch. Scenario: 75 × 10 and 80 × 6 done, last time 75 × 10 at
/// RPE 8. The window is tall enough to hold the card, which VoiceOver reads off screen too. Synthetic values only.
@MainActor
@Suite("Fourth column, hosted", .serialized)
struct SetColumnHostedTests {
    private func header(_ w: HostedWindow) -> HostedWindow.Node? { w.node("Table column", exactly: true) }
    private func lastTime(_ w: HostedWindow) -> String { w.node("Last time")?.label ?? "" }
    private func firstRow(_ w: HostedWindow) -> String { w.node("Set 1 of")?.label ?? "" }

    @Test("The header says what it shows, a double tap moves it on, and the table and last time follow")
    func theHeaderCycles() async throws {
        let c = FocusedPreview.controller(.estimates, column: .e1rm)
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 1400, SessionView(controller: c)) { w in
            try await w.settle()
            let start = try #require(header(w), "the header is a named element")
            #expect(start.value == "Estimated 1RM")
            #expect(start.traits.contains(.button))
            #expect(firstRow(w).contains("estimated one-rep max 100 kilograms"))
            #expect(lastTime(w).contains("10 reps at 75 kilograms, estimated one-rep max 100 kilograms"))

            #expect(start.activate())
            try await w.wait("10RM on the header") { header(w)?.value == "Estimated 10RM" }
            try await w.wait("10RM on the row") { firstRow(w).contains("estimated ten-rep max 75 kilograms") }
            try await w.wait("10RM on last time") { lastTime(w).contains("10 reps at 75 kilograms, estimated ten-rep max 75 kilograms") }
            #expect(c.settings.setColumn == .tenRM)

            try #require(header(w)).activate()
            try await w.wait("RPE on the header") { header(w)?.value == "RPE" }
            try await w.wait("RPE on last time") { lastTime(w).contains("10 reps at 75 kilograms, RPE 8") }
            #expect(!lastTime(w).contains("estimated") && !firstRow(w).contains("estimated"))
            #expect(c.settings.setColumn == .rpe)

            try #require(header(w)).activate()
            try await w.wait("round to E1RM") { header(w)?.value == "Estimated 1RM" }
            try await w.wait("last time comes round") { lastTime(w).contains("estimated one-rep max 100 kilograms") }
        }
    }

    @Test("Voice Control takes what's on the header, and what VoiceOver calls it", arguments: [
        (column: SetColumn.e1rm, shown: "E1RM"), (.tenRM, "10RM"), (.rpe, "RPE"),
    ])
    func voiceControl(_ mode: (column: SetColumn, shown: String)) async throws {
        let c = FocusedPreview.controller(.estimates, column: mode.column)
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
            try await w.settle()
            let labels = try #require(header(w)).inputLabels
            #expect(labels.contains(mode.shown) && labels.contains("Table column"), "\(labels)")
        }
    }

    @Test("Time and distance have a plain header: no button, nothing to tap")
    func timeAndDistanceHaveNoButton() async throws {
        let c = FocusedPreview.controller(.timeAndDistance, column: .e1rm)
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
            try await w.settle()
            #expect(w.node("Set 1 of") != nil, "the page is there")
            #expect(header(w) == nil)
        }
    }
}
