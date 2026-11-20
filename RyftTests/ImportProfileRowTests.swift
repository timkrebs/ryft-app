import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Profile → Data's import rows (T5.8 N10): their titles start at one x whatever the leading glyph ("Import training data"
/// and "Clear remembered matches" were about 1 pt apart), and the text keeps the grouped rows' 10 pt from the hairlines
/// above and below. Read from pixels: the title is the row's only full-ink text (glyph and detail are `textSecondary`).
@MainActor
@Suite("Profile's import rows", .serialized)
struct ImportProfileRowTests {
    @Test("The same title after two different glyphs starts at one x; 10 pt or more from the row's top and bottom to its text")
    func titlesAlignAndBreathe() async throws {
        let title = "Import training data", detail = "RYFT forgets how it matched imported exercises."
        let rows = VStack(spacing: 0) {
            ForEach(["square.and.arrow.down", "eraser"], id: \.self) { glyph in
                ImportProfileRow(systemImage: glyph, title: title, detail: detail)
                    .accessibilityIdentifier(glyph)
                    // As Profile lays them out (`ProfileView`, `.importTraining`).
                    .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
                    .padding(.horizontal, GroupedListSpec.rowInset)
            }
        }
        .background(Theme.surface)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        try await HostedWindow.run(width: 390, height: 500, bottomInset: 0, rows) { w in
            try await w.wait("both rows") { w.nodes().filter { $0.identifier != nil }.count >= 2 }
            try await w.settle()
            let shot = try WindowPixels(w)
            let ink = NocturneTokenTests.resolve(Theme.textPrimary), surface = NocturneTokenTests.resolve(Theme.surface)
            var starts: [CGFloat] = []
            for glyph in ["square.and.arrow.down", "eraser"] {
                let row = try #require(w.nodes().first { $0.identifier == glyph }, "\(glyph)").frame
                let titleInk = try #require(shot.box(in: row) { $0.near(ink, 40) }, "\(glyph): the title's ink")
                let anyInk = try #require(shot.box(in: row) { !$0.near(surface, 24) }, "\(glyph): anything drawn")
                starts.append(titleInk.minX)
                #expect(titleInk.minY - row.minY >= GroupedListSpec.textPadding, "\(glyph): \(row) title \(titleInk)")
                #expect(row.maxY - anyInk.maxY >= GroupedListSpec.textPadding - 1, "\(glyph): \(row) text \(anyInk)")
            }
            #expect(abs(starts[0] - starts[1]) < 1 / shot.scale + 0.01, "title x \(starts)")
        }
    }
}
