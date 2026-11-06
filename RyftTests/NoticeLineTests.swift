import SwiftUI
import Testing
@testable import Ryft

/// A warning or an error as text (design.md 4.7): hue no longer says it, the glyph does.
@MainActor
@Suite("Notice lines")
struct NoticeLineTests {
    private func width<V: View>(_ view: V) -> CGFloat {
        ImageRenderer(content: view.font(.ryft(.caption))).uiImage?.size.width ?? 0
    }

    @Test func aWarningOrErrorLineCarriesItsGlyphAndAnOrdinaryLineDoesNot() {
        let text = Text(verbatim: "Synthetic line")
        let plain = width(text)
        #expect(plain > 0)
        #expect(width(text.warningLine(false)) == plain)
        #expect(width(text.warningLine()) > plain + 6, "the glyph and its 6 pt")
        #expect(width(text.errorLine()) > plain + 6, "the glyph and its 6 pt")
    }

    @Test func theGlyphsAreTheDesignsTwo() {
        #expect(NoticeGlyph.warning.rawValue == "exclamationmark.triangle")
        #expect(NoticeGlyph.error.rawValue == "exclamationmark.circle")
    }

    @Test func aWarningStatRowCarriesTheGlyphBeforeItsValue() {
        let plain = width(StatRow(title: "Sleep debt", value: "1h 05m").fixedSize())
        let warns = width(StatRow(title: "Sleep debt", value: "1h 05m", warns: true).fixedSize())
        #expect(warns > plain + 6)
    }
}
