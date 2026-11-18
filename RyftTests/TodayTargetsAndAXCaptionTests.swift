import SwiftUI
import Testing
import UIKit
@testable import Ryft

// VN4: at AX3 the strain tile's caption ("of 21 · moderate") wrapped in a narrow column beside the value, its second
// line indented under the first. Now it stays beside the value when the line fits, else goes under the value from the
// tile's leading edge. VN5: Today's status row was a 43 pt tap target (a 15 pt line plus 14 above and below); it is 44
// or more and still adds only its text's height to the board.

@MainActor
@Suite(.serialized) struct TodayTargetsAndAXCaptionTests {
    // MARK: VN4

    /// The value row in the strain tile's content width at 390 (390 − 2 × 20 − 2 × 16), or wider.
    private func row(width: CGFloat, typeSize: DynamicTypeSize, category: UIContentSizeCategory,
                     caption: String) async throws -> (value: CGRect, caption: CGRect) {
        var result: (CGRect, CGRect)?
        try await HostedWindow.run(width: width + 40, height: 600, typeSize: typeSize, category: category,
                                   TodayStrainValueRow(value: "12.4", caption: caption)
                                       .frame(width: width)
                                       .frame(maxHeight: .infinity, alignment: .top)) { w in
            try await w.wait("the row") { w.node(caption, exactly: true) != nil }
            try await w.settle()
            let value = try #require(w.node("12.4", exactly: true)).frame
            let text = try #require(w.node(caption, exactly: true)).frame
            result = (value, text)
        }
        return try #require(result)
    }

    struct WrapCase: Sendable, CustomStringConvertible {
        let typeSize: DynamicTypeSize
        let category: UIContentSizeCategory
        let width: CGFloat
        var description: String { "\(typeSize) in \(width)" }
    }

    /// Where "of 21 · moderate" doesn't fit beside the value: AX5 in the tile at 390, AX3 in a narrower one.
    @Test(arguments: [WrapCase(typeSize: .accessibility5, category: .accessibilityExtraExtraExtraLarge, width: 318),
                      WrapCase(typeSize: .accessibility3, category: .accessibilityExtraLarge, width: 240)])
    func aCaptionThatDoesntFitGoesUnderTheValueFromTheLeadingEdge(_ c: WrapCase) async throws {
        let (value, text) = try await row(width: c.width, typeSize: c.typeSize, category: c.category,
                                          caption: "of 21 · moderate")
        #expect(abs(text.minX - value.minX) < 0.5, "the caption starts where the value does: \(text) under \(value)")
        #expect(text.minY >= value.maxY - 0.5, "under the value: \(text), \(value)")
    }

    @Test func atAX3InTheTileAt390TheCaptionFitsBesideTheValue() async throws {
        let (value, text) = try await row(width: 318, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                          caption: "of 21 · moderate")
        #expect(text.minX > value.maxX && abs(text.midY - value.midY) < 8, "beside: \(text) after \(value)")
    }

    @Test func whenTheLineFitsTheCaptionStaysBesideTheValue() async throws {
        let (value, text) = try await row(width: 318, typeSize: .accessibility1, category: .accessibilityMedium,
                                          caption: "of 21")
        #expect(text.minX > value.maxX, "beside: \(text) after \(value)")
        #expect(text.maxY <= value.maxY + 0.5 && text.minY >= value.minY - 0.5, "on the value's line: \(text) in \(value)")
    }

    // MARK: VN5

    @Test func theOutsetMakesTheTargetAPixelOver44() {
        // R3-E: the fault line's target was 44 exactly (a 15 pt line, 14.5 each side), its edges on half pixels; they
        // snapped inward to 43.67. Now there is a pixel to spare, on the grid.
        #expect(SyncStatusLineView.verticalOutset(textHeight: 15, scale: 3) == 44.0 / 3, "15 + 2 × 14.67 = 44.33")
        #expect(SyncStatusLineView.verticalOutset(textHeight: 16, scale: 3) == 43.0 / 3, "16 + 2 × 14.33 = 44.67")
        #expect(SyncStatusLineView.verticalOutset(textHeight: 47.0 / 3, scale: 3) == 43.0 / 3, "15.67 + 2 × 14.33 = 44.33")
        #expect(SyncStatusLineView.verticalOutset(textHeight: 15, scale: 2) == 15, "15 + 30 = 45")
        #expect(SyncStatusLineView.verticalOutset(textHeight: 40, scale: 3) == SyncStatusLineView.hitOutset,
                "a taller line: 14 each side")
        for scale in [CGFloat(1), 2, 3] {
            for h in stride(from: CGFloat(0), through: 60, by: 1 / (4 * scale)) {
                let outset = SyncStatusLineView.verticalOutset(textHeight: h, scale: scale)
                #expect(h + 2 * outset >= 44 + 1 / scale - 1e-9, "\(h) at \(scale)x: a pixel over 44")
                #expect(abs((outset * scale).rounded() - outset * scale) < 1e-9, "\(outset) on the \(scale)x grid")
                let needed = max(SyncStatusLineView.hitOutset, (44 + 1 / scale - h) / 2)
                #expect(outset >= needed - 1e-9 && outset < needed + 1 / scale, "\(h) at \(scale)x: \(outset), at most a pixel over \(needed)")
            }
        }
    }

    /// The row's lines as Today shows them, with the identifier of the line's button.
    struct StatusRowCase: Sendable, CustomStringConvertible {
        let name: String
        let line: SyncLine
        let identifier: String
        var description: String { name }

        static let all = [
            StatusRowCase(name: "up to date", line: .upToDate(.now, demo: true), identifier: "today.syncLine.line"),
            // E: the fault state's line was 43.67 (its outset unrounded).
            StatusRowCase(name: "couldn't load today", line: .issue(.today), identifier: "today.syncLine.issue"),
            StatusRowCase(name: "couldn't load your history", line: .issue(.history), identifier: "today.syncLine.issue"),
            StatusRowCase(name: "signed out", line: .issue(.today, signedOut: true), identifier: "today.syncLine.issue"),
        ]
    }

    @Test("Today's status row is a 44 pt target and as high as its text, in every state",
          arguments: [CGFloat(390), 402], StatusRowCase.all)
    func theStatusRowIsA44PointTarget(_ width: CGFloat, _ c: StatusRowCase) async throws {
        let frames = TwoUpFrames()
        try await HostedWindow.run(width: width, height: 400,
                                   VStack(alignment: .leading, spacing: 0) {
                                       SyncStatusLineView(line: c.line, action: {}, alignment: .leading)
                                           .reportFrame("row", to: frames)
                                       Spacer()
                                   }
                                   .padding(.horizontal, Theme.Metrics.screenPadding)) { w in
            try await w.wait("the line") { w.nodes().contains { $0.identifier == c.identifier } }
            try await w.settle()
            let target = try #require(w.nodes().first { $0.identifier == c.identifier }).frame
            let row = try #require(frames.byName["row"])
            #expect(target.height >= 44 - 0.01, "\(c) at \(width): the target \(target)")
            #expect(row.height < 30, "\(c): the row is its text's height: \(row)")
            #expect(abs(target.midY - row.midY) < 0.5, "\(c): the target is centred on the text: \(target), \(row)")
        }
    }
}
