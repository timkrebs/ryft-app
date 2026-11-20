import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The activity row's meta line at accessibility sizes (T5.8 N8): Strain's "6:00 AM · 20 min · No heart rate" wrapped with a
/// "·" at the end of each line at AX3. From AX1 its parts stand one per line, without the separators.
@MainActor
@Suite("ActivityListRow: the meta at accessibility sizes", .serialized)
struct ActivityListRowLayoutTests {
    @Test("The meta's lines: the whole line below AX1, its parts (as StrainRows.join made them) from AX1")
    func metaLines() {
        let parts = ["6:00 AM", "20 min", "No heart rate"]
        let meta = MyDayText.join(parts)
        #expect(ActivityListRow.metaLines(meta, stacked: false) == [meta])
        #expect(ActivityListRow.metaLines(meta, stacked: true) == parts.map(MyDayText.keepTogether))
        #expect(ActivityListRow.metaLines(meta, stacked: true).allSatisfy { !$0.contains("·") })
        // The separator the row splits on is the one the rows' join puts between parts.
        #expect(MyDayText.join(["a", "b"]) == "a" + ActivityListRowSpec.metaSeparator + "b")
        #expect(StrainRows.join(["a", "b"]) == "a" + ActivityListRowSpec.metaSeparator + "b")
        // A part's own " · " (Train's "Upper/Lower 4× · week 6") is not a separator of the row's.
        #expect(ActivityListRow.metaLines("Upper/Lower 4× · week 6", stacked: true) == ["Upper/Lower 4× · week 6"])
    }

    /// The row's height with `meta`, at `typeSize`.
    private func height(meta: String, _ typeSize: DynamicTypeSize, _ category: UIContentSizeCategory) async throws -> CGFloat {
        let row = ActivityListRow(content: .init(systemImage: "figure.run", title: "Run", meta: meta, value: "9.8",
                                                 spoken: "Run"))
            .accessibilityIdentifier("row")
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        var height = CGFloat.nan
        try await HostedWindow.run(width: 402, height: 1200, bottomInset: 0, typeSize: typeSize, category: category, row) { w in
            try await w.wait("the row") { w.nodes().contains { $0.identifier == "row" } }
            try await w.settle()
            height = try #require(w.nodes().first { $0.identifier == "row" }).frame.height
        }
        return height
    }

    @Test("Hosted: two short parts fit one line at the default size; at AX3 they take a line each, one meta line taller")
    func partsStackAtAX3() async throws {
        let one = "7:10", two = MyDayText.join(["7:10", "1 h"])
        let regularOne = try await height(meta: one, .large, .large)
        let regularTwo = try await height(meta: two, .large, .large)
        #expect(abs(regularTwo - regularOne) < 0.5, "default: \(regularOne) / \(regularTwo)")
        let axOne = try await height(meta: one, .accessibility3, .accessibilityExtraLarge)
        let axTwo = try await height(meta: two, .accessibility3, .accessibilityExtraLarge)
        // "7:10 · 1 h" fits on one line at AX3 (well inside the text column's 280): only stacking adds the line.
        let line = UIFont.preferredFont(forTextStyle: .caption1,
                                        compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
            .lineHeight
        #expect(axTwo - axOne > 0.8 * line, "AX3: \(axOne) / \(axTwo), a caption line \(line)")
    }
}
