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

    @Test func theOutsetMakesTheTargetAtLeast44() {
        #expect(SyncStatusLineView.verticalOutset(textHeight: 16) == SyncStatusLineView.hitOutset, "16 + 28 = 44")
        #expect(SyncStatusLineView.verticalOutset(textHeight: 15) == 14.5, "15 + 29 = 44")
        #expect(SyncStatusLineView.verticalOutset(textHeight: 40) == SyncStatusLineView.hitOutset, "a taller line: 14 each side")
        for h in stride(from: CGFloat(0), through: 60, by: 0.25) {
            #expect(h + 2 * SyncStatusLineView.verticalOutset(textHeight: h) >= 44)
        }
    }

    @Test("Today's status row is a 44 pt target and as high as its text", arguments: [CGFloat(390), 402])
    func theStatusRowIsA44PointTarget(_ width: CGFloat) async throws {
        let frames = TwoUpFrames()
        try await HostedWindow.run(width: width, height: 400,
                                   VStack(alignment: .leading, spacing: 0) {
                                       SyncStatusLineView(line: .upToDate(.now, demo: true), action: {}, alignment: .leading)
                                           .reportFrame("row", to: frames)
                                       Spacer()
                                   }
                                   .padding(.horizontal, Theme.Metrics.screenPadding)) { w in
            try await w.wait("the line") { w.nodes().contains { $0.identifier == "today.syncLine.line" } }
            try await w.settle()
            let target = try #require(w.nodes().first { $0.identifier == "today.syncLine.line" }).frame
            let row = try #require(frames.byName["row"])
            #expect(target.height >= 44 - 0.01, "the target: \(target)")
            #expect(row.height < 30, "the row is its text's height: \(row)")
            #expect(abs(target.midY - row.midY) < 0.5, "the target is centred on the text: \(target), \(row)")
        }
    }
}
